# Root Configuration (root.hcl)

The root.hcl file is the central configuration for your Terragrunt live repository.

## Complete Example

```hcl
locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))
  env_vars     = try(read_terragrunt_config(find_in_parent_folders("env.hcl")), { locals = {} })

  account_name = local.account_vars.locals.account_name
  account_id   = local.account_vars.locals.aws_account_id
  aws_region   = local.region_vars.locals.aws_region
  role_arn     = local.account_vars.locals.role_arn
}

# Generate AWS provider with role assumption
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "aws" {
  region              = "${local.aws_region}"
  allowed_account_ids = ["${local.account_id}"]
  assume_role {
    role_arn = "${local.role_arn}"
  }
  default_tags {
    tags = {
      Environment = "${try(local.env_vars.locals.environment, "default")}"
      ManagedBy   = "Terragrunt"
    }
  }
}
EOF
}

# Generate OpenTofu version constraints
generate "versions" {
  path      = "versions.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}
EOF
}

# Remote state with environment-based bucket suffix
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

catalog {
  urls = [
    "git@github.com:YOUR_ORG/infrastructure-catalog.git"
  ]
}

inputs = merge(
  local.account_vars.locals,
  local.region_vars.locals,
  local.env_vars.locals
)
```

## Key Sections

### Variable Resolution

```hcl
locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))
  env_vars     = try(read_terragrunt_config(find_in_parent_folders("env.hcl")), { locals = {} })
}
```

- `find_in_parent_folders()` searches up the directory tree
- `try()` provides fallback when env.hcl doesn't exist

### Provider Generation

The provider block configures:
- **region**: From region.hcl
- **allowed_account_ids**: Prevents accidental deployment to wrong account
- **assume_role**: Cross-account access via IAM role
- **default_tags**: Applied to all resources

### Remote State

```hcl
remote_state {
  backend = "s3"
  config = {
    bucket         = format("tfstate-%s%s-%s", ...)
    key            = "${path_relative_to_include()}/terraform.tfstate"
    dynamodb_table = format("tfstate-locks-%s%s-%s", ...)
  }
}
```

Key features:
- **Environment isolation**: `state_bucket_suffix` creates separate buckets
- **Unique keys**: `path_relative_to_include()` ensures unique state per unit
- **Locking**: DynamoDB table prevents concurrent modifications

### Catalog Configuration

```hcl
catalog {
  urls = [
    "git@github.com:YOUR_ORG/infrastructure-catalog.git",
    "git@github.com:YOUR_ORG/infrastructure-aws-catalog.git"  # Multiple catalogs
  ]
}
```

Enables `terragrunt catalog` to browse and scaffold from these repositories.

### Input Merging

```hcl
inputs = merge(
  local.account_vars.locals,
  local.region_vars.locals,
  local.env_vars.locals
)
```

All variables from the hierarchy are merged and passed to units as inputs.

## Account Configuration (account.hcl)

```hcl
locals {
  aws_account_id = "123456789012"
  account_name   = "myproject-prod"
  role_arn       = "arn:aws:iam::123456789012:role/TerraformRole"

  environment = "production"

  vpc_id             = "vpc-xxxxxxxxx"
  private_subnet_ids = ["subnet-xxx", "subnet-yyy"]
  public_subnet_ids  = ["subnet-aaa", "subnet-bbb"]

  tags = {
    Project     = "MyProject"
    Environment = "production"
  }
}
```

## Environment Configuration (env.hcl)

```hcl
locals {
  environment         = "staging"
  state_bucket_suffix = local.environment
}
```

## References

- [Live Structure](live-structure.md)
- [State Management](state-management.md)
- [Multi-Account Strategy](multi-account.md)
