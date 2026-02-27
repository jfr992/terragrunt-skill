# State Management Best Practices

## Remote State Configuration

### S3 Backend (AWS)

Recommended configuration in root.hcl:

```hcl
remote_state {
  backend = "s3"
  config = {
    encrypt        = true
    bucket         = format("tfstate-%s%s-%s",
                      local.account_name,
                      try(local.env_vars.locals.state_bucket_suffix, "") != "" ? "-${local.env_vars.locals.state_bucket_suffix}" : "",
                      local.aws_region)
    key            = "${path_relative_to_include()}/terraform.tfstate"
    region         = local.aws_region
    dynamodb_table = format("tfstate-locks-%s%s-%s",
                      local.account_name,
                      try(local.env_vars.locals.state_bucket_suffix, "") != "" ? "-${local.env_vars.locals.state_bucket_suffix}" : "",
                      local.aws_region)
    role_arn       = local.role_arn
  }
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
}
```

Key settings:
- **encrypt = true** - Enable server-side encryption
- **dynamodb_table** - Enable state locking
- **path_relative_to_include()** - Unique key per unit
- **role_arn** - Cross-account access

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

## State Bucket Setup

### Prerequisites

Before first Terragrunt run, create:
1. S3 bucket with versioning and encryption
2. DynamoDB table for locking
3. IAM role with appropriate permissions

### Setup Script

> **Note:** This script currently only supports AWS (S3 + DynamoDB). GCP and Azure are not yet supported.

The `setup-state-backend.sh` script auto-discovers accounts, regions, and environments from your directory structure and creates S3 buckets and DynamoDB lock tables.

#### Required Directory Structure

```
infrastructure-live/
├── setup-state-backend.sh        # Run from here
├── root.hcl
├── <account>/                    # Directory name (e.g., "non-prod", "prod")
│   ├── account.hcl               # REQUIRED
│   └── <region>/                 # AWS region (e.g., "us-east-1")
│       ├── region.hcl
│       ├── env.hcl               # Optional: region-level state bucket
│       └── <environment>/        # Environment (e.g., "staging", "dev")
│           ├── env.hcl           # Optional: env-level state bucket
│           └── <service>/
│               └── terragrunt.stack.hcl
```

#### Required HCL Variables

**account.hcl** (required):
```hcl
locals {
  account_name   = "myproject-nonprod"  # Used in bucket name
  aws_account_id = "123456789012"       # For bucket policy
}
```

**env.hcl** (optional - for environment isolation):
```hcl
locals {
  environment         = "staging"
  state_bucket_suffix = local.environment  # Creates separate bucket
}
```

#### Usage

```bash
# Create all state backends (auto-discovers from directory structure)
./setup-state-backend.sh

# Dry run - show what would be created
./setup-state-backend.sh --dry-run

# Specific account only
./setup-state-backend.sh --account prod
```

#### What It Creates

For each discovered account/region/environment:
- **S3 Bucket** with versioning, KMS encryption, public access blocked, TLS-enforced policy
- **DynamoDB Table** with `LockID` key for state locking

The script:
- Parses account.hcl and env.hcl files
- Creates S3 buckets with versioning, encryption, and TLS enforcement
- Creates DynamoDB tables for locking
- Supports dry-run mode

Reference: [setup-state-backend.sh](../scripts/setup-state-backend.sh)

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
