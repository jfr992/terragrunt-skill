# ---------------------------------------------------------------------------------------------------------------------
# TERRAGRUNT ROOT CONFIGURATION
# Root configuration for Terragrunt with OpenTofu
# ---------------------------------------------------------------------------------------------------------------------

locals {
  # Automatically load account-level variables
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))

  # Automatically load region-level variables
  region_vars = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  # Try to load env.hcl, but don't fail if it doesn't exist
  env_vars = try(read_terragrunt_config(find_in_parent_folders("env.hcl")), { locals = {} })

  # Try to load stack configuration for cross-account settings
  stack_vars = try(read_terragrunt_config(find_in_parent_folders("terragrunt.stack.hcl")), { locals = {} })

  # Extract variables for easy access
  account_name = local.account_vars.locals.account_name
  account_id   = local.account_vars.locals.aws_account_id
  aws_region   = local.region_vars.locals.aws_region
  role_arn     = local.account_vars.locals.role_arn

  # Cross-account DNS (for Route53 in different account)
  dns_account_id = try(local.stack_vars.locals.dns_account_id, null)
}

# Generate AWS provider with role assumption
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "aws" {
  region = "${local.aws_region}"

  allowed_account_ids = ${local.dns_account_id != null ? jsonencode([local.account_id, local.dns_account_id]) : jsonencode([local.account_id])}
  assume_role {
    role_arn = "${local.role_arn}"
  }

  default_tags {
    tags = {
      Environment = "${try(local.env_vars.locals.environment, local.account_vars.locals.environment, "default")}"
      ManagedBy   = "Terragrunt"
    }
  }
}

${local.dns_account_id != null ? <<-DNS
# Cross-account provider for DNS operations
provider "aws" {
  alias  = "dns"
  region = "us-east-1"

  assume_role {
    role_arn = "arn:aws:iam::${local.dns_account_id}:role/TerraformCrossAccount"
  }
}
DNS
: ""}
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

# Configure remote state in S3
remote_state {
  backend = "s3"
  config = {
    encrypt        = true
    bucket         = format("tfstate-%s%s-%s", local.account_name, try(local.env_vars.locals.state_bucket_suffix, "") != "" ? "-${local.env_vars.locals.state_bucket_suffix}" : "", local.aws_region)
    key            = "${path_relative_to_include()}/terraform.tfstate"
    region         = local.aws_region
    dynamodb_table = format("tfstate-locks-%s%s-%s", local.account_name, try(local.env_vars.locals.state_bucket_suffix, "") != "" ? "-${local.env_vars.locals.state_bucket_suffix}" : "", local.aws_region)
    role_arn       = local.role_arn
  }
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
}

# Configure catalog sources for 'terragrunt catalog' command
catalog {
  urls = [
    "git@github.com:YOUR_ORG/infrastructure-catalog.git"
  ]
}

# Global inputs merged into all child configurations
inputs = merge(
  local.account_vars.locals,
  local.region_vars.locals,
  local.env_vars.locals
)
