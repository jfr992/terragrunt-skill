# Serverless API Stack (Template)
# Deploys: S3 bucket + DynamoDB table + Lambda function
# Usage: Reference this stack from live repo and pass values

locals {
  service     = values.service
  environment = values.environment

  # Computed values
  function_name = "${values.service}-${values.environment}-api"
  table_name    = "${values.service}-${values.environment}"
  bucket_name   = "${values.service}-${values.environment}-artifacts"

  # Common tags for all resources
  common_tags = merge(try(values.tags, {}), {
    Stack       = "serverless-api"
    Service     = values.service
    Environment = values.environment
  })
}

# S3 bucket for Lambda deployment packages
unit "s3" {
  source = "git::git@github.com:YOUR_ORG/infrastructure-catalog.git//units/s3?ref=${values.catalog_version}"
  path   = "s3"

  values = {
    version       = try(values.s3_module_version, "v1.0.0")
    bucket        = local.bucket_name
    force_destroy = try(values.s3_force_destroy, false)

    versioning = {
      status = "Enabled"
    }

    lifecycle_rule = try(values.s3_lifecycle_rules, [
      {
        id      = "cleanup-old-versions"
        enabled = true
        noncurrent_version_expiration = {
          days = 30
        }
      }
    ])

    tags = local.common_tags
  }
}

# DynamoDB table for API data
unit "dynamodb" {
  source = "git::git@github.com:YOUR_ORG/infrastructure-catalog.git//units/dynamodb?ref=${values.catalog_version}"
  path   = "dynamodb"

  values = {
    version   = try(values.dynamodb_module_version, "v1.0.0")
    name      = local.table_name
    hash_key  = try(values.dynamodb_hash_key, "PK")
    range_key = try(values.dynamodb_range_key, "SK")

    attributes = try(values.dynamodb_attributes, [
      { name = "PK", type = "S" },
      { name = "SK", type = "S" }
    ])

    billing_mode                   = try(values.dynamodb_billing_mode, "PAY_PER_REQUEST")
    point_in_time_recovery_enabled = try(values.dynamodb_pitr_enabled, true)

    global_secondary_indexes = try(values.dynamodb_gsis, [])

    tags = local.common_tags
  }
}

# Lambda function for API
unit "lambda" {
  source = "git::git@github.com:YOUR_ORG/infrastructure-catalog.git//units/lambda?ref=${values.catalog_version}"
  path   = "lambda"

  values = {
    version       = try(values.lambda_module_version, "v1.0.0")
    function_name = local.function_name
    handler       = try(values.lambda_handler, "index.handler")
    runtime       = try(values.lambda_runtime, "nodejs20.x")

    # Use S3 for deployment package
    use_s3_package = true
    s3_path        = "../s3"
    s3_key         = try(values.lambda_s3_key, "lambda/${local.function_name}.zip")

    memory_size = try(values.lambda_memory_size, 256)
    timeout     = try(values.lambda_timeout, 30)

    environment_variables = merge(
      {
        TABLE_NAME  = local.table_name
        ENVIRONMENT = values.environment
      },
      try(values.lambda_environment_variables, {})
    )

    cloudwatch_logs_retention_in_days = try(values.lambda_logs_retention, 14)

    tags = local.common_tags
  }
}
