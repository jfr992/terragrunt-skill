# Deployment stack for my-api in staging environment

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  env_vars     = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  environment = local.env_vars.locals.environment
  service     = "my-api"

  # Computed names
  function_name = "${local.service}-${local.environment}-api"
  table_name    = "${local.service}-${local.environment}"
  bucket_name   = "${local.service}-${local.environment}-artifacts"

  catalog_path = "git::git@github.com:YOUR_ORG/infrastructure-catalog.git"

  # Common tags for all resources
  common_tags = merge(local.account_vars.locals.tags, {
    Stack       = "serverless-api"
    Service     = local.service
    Environment = local.environment
  })
}

# S3 bucket for Lambda deployment packages
unit "s3" {
  source = "${local.catalog_path}//units/s3?ref=main"
  path   = "s3"

  values = {
    version       = "v1.0.0"
    bucket        = local.bucket_name
    force_destroy = false

    versioning = {
      status = "Enabled"
    }

    lifecycle_rule = [
      {
        id      = "cleanup-old-versions"
        enabled = true
        noncurrent_version_expiration = {
          days = 30
        }
      }
    ]

    tags = local.common_tags
  }
}

# DynamoDB table for API data
unit "dynamodb" {
  source = "${local.catalog_path}//units/dynamodb?ref=main"
  path   = "dynamodb"

  values = {
    version   = "v1.0.0"
    name      = local.table_name
    hash_key  = "PK"
    range_key = "SK"

    attributes = [
      { name = "PK", type = "S" },
      { name = "SK", type = "S" },
      { name = "GSI1PK", type = "S" },
      { name = "GSI1SK", type = "S" }
    ]

    billing_mode                   = "PAY_PER_REQUEST"
    point_in_time_recovery_enabled = true

    global_secondary_indexes = [
      {
        name            = "GSI1"
        hash_key        = "GSI1PK"
        range_key       = "GSI1SK"
        projection_type = "ALL"
      }
    ]

    tags = local.common_tags
  }
}

# Lambda function for API
unit "lambda" {
  source = "${local.catalog_path}//units/lambda?ref=main"
  path   = "lambda"

  values = {
    version       = "v1.0.0"
    function_name = local.function_name
    handler       = "src/handler.main"
    runtime       = "python3.12"

    # Use S3 for deployment package
    use_s3_package = true
    s3_path        = "../s3"
    s3_key         = "deployments/${local.service}/latest.zip"

    memory_size = 512
    timeout     = 60

    environment_variables = {
      TABLE_NAME  = local.table_name
      ENVIRONMENT = local.environment
      LOG_LEVEL   = "DEBUG"
      API_URL     = "https://api.staging.example.com"
    }

    cloudwatch_logs_retention_in_days = 14

    tags = local.common_tags
  }
}
