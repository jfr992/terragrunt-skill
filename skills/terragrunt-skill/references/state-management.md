# State Management Best Practices

> Native S3 `use_lockfile` **requires TG >= 0.82.4 and OpenTofu >= 1.10 or Terraform >= 1.11**. `encryption` is OpenTofu-only (>= 1.7, TG >= 0.72.2). See [version-compatibility.md](version-compatibility.md).

## Contents
- Remote State Configuration
- State Isolation
- Environment-Based State Buckets
- S3-Compatible Backends (MinIO, OCI, R2, Ceph…)
- Azure (azurerm)
- State Backend Bootstrap
- State Migration
- Avoiding Workspaces
- Cross-Account State Access

## Remote State Configuration

### S3 Backend (AWS)

Recommended configuration in root.hcl (OpenTofu >= 1.10 or Terraform >= 1.11 — native S3 lockfile, no DynamoDB table needed; Terragrunt >= 0.82.4 handles it natively, older versions pass it through):

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
- **use_lockfile = true** - Native S3 state locking (OpenTofu >= 1.10 / Terraform >= 1.11). No DynamoDB table to provision or pay for.
- **path_relative_to_include()** - Unique key per unit
- **role_arn** - Cross-account access

#### Legacy: DynamoDB locking

For OpenTofu < 1.10, Terraform < 1.11, or existing repos already using a lock table, replace `use_lockfile = true` with:

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

## S3-Compatible Backends (MinIO, OCI, R2, Ceph…)

`use_lockfile = true` relies on S3 **conditional writes** (`If-None-Match` on the `.tflock` object). The Terragrunt/OpenTofu docs do not list which S3-compatible providers implement this.

- **OCI Object Storage: works** (field result, reported in testing — a second lock attempt gets HTTP 412). Not documented by the vendor or Terragrunt.
- **MinIO: works** (tested 2026-10 with Terragrunt 1.2.1 + OpenTofu 1.10.6: second `plan -lock-timeout=0s` while an apply held the lock failed with `Error acquiring the state lock … StatusCode: 412 PreconditionFailed`).
- **Floci (local AWS emulator, good for testing): works** (same test, same 412 result).
- **Cloudflare R2: documented** — `PutObject` supports `If-None-Match: *` atomically, losers get 412 ([R2 S3 API compatibility](https://developers.cloudflare.com/r2/api/s3/api/), [consistency model](https://developers.cloudflare.com/r2/reference/consistency/)). Not tested here.
- **Ceph RGW, others: UNVERIFIED** — RGW's `PutObject` docs don't list `If-None-Match` (only a tracker issue, https://tracker.ceph.com/issues/8562). Test before relying on it: hold the lock with one `apply`, run `plan -lock-timeout=0s` in a second shell, and expect `Error acquiring the state lock`.

```hcl
remote_state {
  backend = "s3"
  config = {
    bucket       = "tfstate-myproject"
    key          = "${path_relative_to_include()}/terraform.tfstate"
    region       = "us-ashburn-1"                     # provider-specific
    use_lockfile = true
    endpoints    = { s3 = "https://<namespace>.compat.objectstorage.<region>.oraclecloud.com" } # provider-specific
    use_path_style              = true                # provider-specific (MinIO/OCI usually need it)
    skip_credentials_validation = true                # provider-specific
    skip_region_validation      = true                # provider-specific
    skip_requesting_account_id  = true                # provider-specific
    skip_s3_checksum            = true                # provider-specific
  }
  generate = { path = "backend.tf", if_exists = "overwrite_terragrunt" }
}
```

**Deterministic lock test** (disposable bucket/prefix — never against real state):

```bash
# shell 1: hold the lock (console holds a state lock until you exit)
terragrunt run -- console
# shell 2: must fail with an error mentioning "lock"
terragrunt run -- plan -lock-timeout=0s
# after shell 1 exits, shell 2 must succeed
```

If the provider lacks conditional writes, fall back to a DynamoDB-compatible lock table (`dynamodb_table` + `endpoints.dynamodb`) or run without locking (not recommended).

## Azure (azurerm)

The `azurerm` backend is GA in Terragrunt 1.2: `terragrunt backend bootstrap`, `backend delete`, and `backend migrate` work with it, and dependency outputs can be read directly from azurerm state. See [completed experiments: azure-backend](https://docs.terragrunt.com/reference/experiments/completed/#azure-backend).

## State Backend Bootstrap

Terragrunt natively provisions backend resources from the `remote_state` block — no external script needed:

```bash
# Create the S3 bucket (and DynamoDB table, if configured) for a unit
terragrunt backend bootstrap

# Bootstrap everything discovered under the current directory
terragrunt backend bootstrap --all

# Migrate state between backends after editing remote_state config
terragrunt backend migrate

# Tear down backend resources (careful: state lives here)
terragrunt backend delete
```

The bucket is created with versioning, server-side encryption, public access blocked, and a TLS-enforced policy. Do not use `run --all -- backend bootstrap`, because everything after `--` goes to OpenTofu/Terraform. Automatic provisioning on first `init`/`plan` was the default before 0.78. It became opt-in (`--backend-bootstrap`) in 0.78.0 and was removed in 0.87.0, so Terragrunt now errors when the backend is missing. Explicit `backend bootstrap` (0.77+) is the way, and it is preferable in CI (least-privilege pipelines can run it once with elevated rights, then drop them).


### 1.2 bootstrap change: no bucket root-access statement

Since Terragrunt 1.2, S3 bootstrap **no longer adds** the `arn:aws:iam::<account>:root` statement to the state bucket policy. To keep the old behavior:

```hcl
remote_state {
  backend = "s3"
  config = {
    # ...
    enable_bucket_root_access = true
  }
}
```

`skip_bucket_root_access` is deprecated (strict control `skip-bucket-root-access`). Buckets bootstrapped by earlier versions keep the existing statement. See the [v1.2.0 release](https://github.com/gruntwork-io/terragrunt/releases/tag/v1.2.0).

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
