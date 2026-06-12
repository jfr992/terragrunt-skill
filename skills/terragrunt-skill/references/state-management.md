# State Management Best Practices

## Remote State Configuration

### S3 Backend (AWS)

Recommended configuration in root.hcl (OpenTofu >= 1.10 — native S3 lockfile, no DynamoDB table needed):

```hcl
remote_state {
  backend = "s3"
  config = {
    encrypt      = true
    bucket       = format("tfstate-%s%s-%s",
                    local.account_name,
                    try(local.env_vars.locals.state_bucket_suffix, "") != "" ? "-${local.env_vars.locals.state_bucket_suffix}" : "",
                    local.aws_region)
    key          = "${path_relative_to_include()}/terraform.tfstate"
    region       = local.aws_region
    use_lockfile = true
    role_arn     = local.role_arn
  }
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
}
```

Key settings:
- **encrypt = true** - Enable server-side encryption
- **use_lockfile = true** - Native S3 state locking (OpenTofu >= 1.10). No DynamoDB table to provision or pay for.
- **path_relative_to_include()** - Unique key per unit
- **role_arn** - Cross-account access

#### Legacy: DynamoDB locking

For OpenTofu < 1.10, Terraform, or existing repos already using a lock table, replace `use_lockfile = true` with:

```hcl
    dynamodb_table = format("tfstate-locks-%s-%s", local.account_name, local.aws_region)
```

Terragrunt auto-creates the table on bootstrap. Migrating an existing repo to `use_lockfile` only requires the config change — locks are ephemeral, no state migration is needed. Both can be set simultaneously during a transition.

## State Isolation

Each unit gets its own state file through `path_relative_to_include()`:

```
infrastructure-live/
├── non-prod/us-east-1/staging/api/     → tfstate-myproject-nonprod-staging-us-east-1/non-prod/us-east-1/staging/api/terraform.tfstate
├── non-prod/us-east-1/staging/db/      → tfstate-myproject-nonprod-staging-us-east-1/non-prod/us-east-1/staging/db/terraform.tfstate
└── prod/us-east-1/prod/api/            → tfstate-myproject-prod-us-east-1/prod/us-east-1/prod/api/terraform.tfstate
```

Benefits:
- Blast radius limited to single unit
- Independent apply/destroy operations
- Clear state file organization

## Environment-Based State Buckets

Use `state_bucket_suffix` in env.hcl for environment isolation:

```hcl
# non-prod/us-east-1/staging/env.hcl
locals {
  environment         = "staging"
  state_bucket_suffix = local.environment
}

# non-prod/us-east-1/dev/env.hcl
locals {
  environment         = "dev"
  state_bucket_suffix = local.environment
}
```

This creates separate buckets per environment:
- `tfstate-myproject-nonprod-staging-us-east-1`
- `tfstate-myproject-nonprod-dev-us-east-1`

## State Backend Bootstrap

Terragrunt natively provisions backend resources from the `remote_state` block — no external script needed:

```bash
# Create the S3 bucket (and DynamoDB table, if configured) for a unit
terragrunt backend bootstrap

# Bootstrap everything discovered under the current directory
terragrunt run --all -- backend bootstrap

# Migrate state between backends after editing remote_state config
terragrunt backend migrate

# Tear down backend resources (careful: state lives here)
terragrunt backend delete
```

The bucket is created with versioning, server-side encryption, public access blocked, and a TLS-enforced policy. By default Terragrunt also auto-bootstraps on first `init`/`plan` when the backend doesn't exist; `backend bootstrap` makes it explicit, which is preferable in CI (least-privilege pipelines can run it once with elevated rights, then drop them).

## State Migration

Moving state between backends:

```bash
# 1. Initialize with current backend
terragrunt init

# 2. Update backend configuration in root.hcl

# 3. Re-initialize with migration
terragrunt init -migrate-state
```

## Avoiding Workspaces

Terragrunt recommends against OpenTofu/Terraform workspaces:

**Don't use:**
```hcl
terraform workspace select dev
```

**Do use:** Separate directories per environment with isolated state:
```
non-prod/us-east-1/staging/api/
non-prod/us-east-1/dev/api/
prod/us-east-1/prod/api/
```

Each directory = isolated state = clear separation.

## Cross-Account State Access

For reading state from other accounts:

```hcl
data "terraform_remote_state" "shared_vpc" {
  backend = "s3"
  config = {
    bucket   = "tfstate-shared-services-us-east-1"
    key      = "shared-services/us-east-1/vpc/terraform.tfstate"
    region   = "us-east-1"
    role_arn = "arn:aws:iam::SHARED_ACCOUNT_ID:role/TerraformStateReader"
  }
}
```
