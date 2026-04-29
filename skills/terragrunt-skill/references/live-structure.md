# Infrastructure Live Structure

## Directory Layout

```
infrastructure-live/
├── root.hcl                    # Root configuration
├── setup-state-backend.sh      # State bucket setup script
├── <account>/                  # Account directories
│   ├── account.hcl             # Account config (id, name, role_arn, vpc, tags)
│   └── <region>/
│       ├── region.hcl          # Region config
│       └── <environment>/
│           ├── env.hcl         # Environment config (state_bucket_suffix)
│           └── <service>/
│               └── <resource>/
│                   └── terragrunt.stack.hcl
```

## Example Structure

```
infrastructure-live/
├── root.hcl
├── setup-state-backend.sh
├── non-prod/
│   ├── account.hcl
│   └── us-east-1/
│       ├── region.hcl
│       ├── staging/
│       │   ├── env.hcl
│       │   └── api/
│       │       └── terragrunt.stack.hcl
│       └── dev/
│           ├── env.hcl
│           └── api/
│               └── terragrunt.stack.hcl
└── prod/
    ├── account.hcl
    └── us-east-1/
        ├── region.hcl
        └── prod/
            ├── env.hcl
            └── api/
                └── terragrunt.stack.hcl
```

## Configuration Hierarchy

### root.hcl
The root configuration file contains:
- Provider generation (AWS provider with role assumption)
- Version constraints (OpenTofu/Terraform versions)
- Remote state configuration (S3 + DynamoDB)
- Catalog URLs
- Input merging from account/region/env vars

See: [Root Configuration Guide](root-config.md)

### account.hcl
Account-specific configuration:

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

### region.hcl
Region-specific configuration:

```hcl
locals {
  aws_region = "us-east-1"
}
```

### env.hcl
Environment-specific configuration:

```hcl
locals {
  environment         = "staging"
  state_bucket_suffix = local.environment  # Creates separate state bucket per env
}
```

## State Isolation

Each unit gets its own state file through `path_relative_to_include()`:

```
infrastructure-live/
├── non-prod/us-east-1/staging/api/ → tfstate-myproject-nonprod-staging-us-east-1/non-prod/us-east-1/staging/api/terraform.tfstate
├── non-prod/us-east-1/dev/api/     → tfstate-myproject-nonprod-dev-us-east-1/non-prod/us-east-1/dev/api/terraform.tfstate
└── prod/us-east-1/prod/api/        → tfstate-myproject-prod-us-east-1/prod/us-east-1/prod/api/terraform.tfstate
```

## References

- [Root Configuration](root-config.md)
- [Multi-Account Strategy](multi-account.md)
- [State Management](state-management.md)
