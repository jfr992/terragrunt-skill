# Infrastructure Catalog Structure

## Directory Layout

```
infrastructure-catalog/
├── units/                      # Terragrunt units (building blocks)
│   ├── acm/
│   │   └── terragrunt.hcl
│   ├── cloudfront/
│   │   └── terragrunt.hcl
│   ├── dynamodb/
│   │   └── terragrunt.hcl
│   ├── eks/
│   │   └── terragrunt.hcl
│   ├── rds/
│   │   └── terragrunt.hcl
│   ├── route53/
│   │   └── terragrunt.hcl
│   └── s3/
│       └── terragrunt.hcl
└── stacks/                     # Template stacks (compositions)
    ├── frontend/
    │   └── terragrunt.stack.hcl
    ├── backend-api/
    │   └── terragrunt.stack.hcl
    └── data-platform/
        └── terragrunt.stack.hcl
```

## Units

Units are the building blocks of your infrastructure catalog. Each unit:
- Wraps a single OpenTofu/Terraform module
- Receives configuration through `values.xxx`
- Declares dependencies on other units
- Provides mock outputs for plan/validate

### Unit Pattern

```hcl
include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "git::git@github.com:YOUR_ORG/modules/rds.git//app?ref=${values.version}"
}

dependency "vpc" {
  config_path  = try(values.vpc_path, "../vpc")
  skip_outputs = !try(values.use_vpc, true)

  mock_outputs = {
    vpc_id          = "vpc-mock"
    private_subnets = ["subnet-mock"]
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

inputs = {
  name        = values.name
  environment = values.environment
  vpc_id      = dependency.vpc.outputs.vpc_id
}
```

## Stacks

Stacks compose multiple units into deployable infrastructure:

### Template Stacks (in catalog)

```hcl
locals {
  service     = values.service
  environment = values.environment
  domain      = values.domain

  fqdn = "${values.service}-${values.environment}.${values.domain}"

  common_tags = merge(try(values.tags, {}), {
    Stack       = "frontend"
    Service     = values.service
    Environment = values.environment
  })
}

unit "s3" {
  source = "git::git@github.com:YOUR_ORG/infrastructure-catalog.git//units/s3?ref=${values.catalog_version}"
  path   = "s3"

  values = {
    version = values.module_version
    bucket  = "my-bucket-${values.environment}"
    tags    = local.common_tags
  }
}

unit "cloudfront" {
  source = "git::git@github.com:YOUR_ORG/infrastructure-catalog.git//units/cloudfront?ref=${values.catalog_version}"
  path   = "cloudfront"

  values = {
    version  = values.module_version
    acm_path = "../acm"
  }
}
```

### Deployment Stacks (in live repo)

```hcl
locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  env_vars     = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  environment  = local.env_vars.locals.environment
  service      = "my-service"
}

unit "database" {
  source = "git::git@github.com:YOUR_ORG/infrastructure-catalog.git//units/dynamodb?ref=main"
  path   = "database"

  values = {
    version    = "v1.0.0"
    name       = "${local.service}-${local.environment}"
    hash_key   = "PK"
    range_key  = "SK"
    attributes = [
      { name = "PK", type = "S" },
      { name = "SK", type = "S" }
    ]
    tags = merge(local.account_vars.locals.tags, {
      Service = local.service
    })
  }
}
```

## References

- [Unit Template](../assets/catalog-structure/units/template/)
- [Stack Template](../assets/catalog-structure/stacks/template/)
