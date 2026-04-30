# Multi-Account Strategy

## Account Structure

Recommended AWS account structure:

```
Organization
├── Management Account (root)
├── Security Account
├── Logging Account
├── Shared Services Account
├── Non-Prod Account
│   ├── dev environment
│   └── staging environment
└── Prod Account
    └── prod environment
```

## Live Repository Structure

```
infrastructure-live/
├── root.hcl
├── setup-state-backend.sh
├── shared-services/
│   ├── account.hcl
│   └── us-east-1/
│       └── region.hcl
├── non-prod/
│   ├── account.hcl
│   ├── us-east-1/
│   │   ├── region.hcl
│   │   ├── dev/
│   │   │   ├── env.hcl
│   │   │   └── api/
│   │   │       └── terragrunt.stack.hcl
│   │   └── staging/
│   │       ├── env.hcl
│   │       └── api/
│   │           └── terragrunt.stack.hcl
│   └── us-west-2/
└── prod/
    ├── account.hcl
    └── us-east-1/
        ├── region.hcl
        └── prod/
            ├── env.hcl
            └── api/
                └── terragrunt.stack.hcl
```

## Cross-Account Access

### Assume Role Pattern

In root.hcl, configure cross-account access:

```hcl
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "aws" {
  region = "${local.aws_region}"

  assume_role {
    role_arn = "${local.role_arn}"
  }
}
EOF
}
```

### IAM Role Setup

Create TerraformCrossAccount role in each account:

```hcl
resource "aws_iam_role" "terraform_cross_account" {
  name = "TerraformCrossAccount"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        AWS = "arn:aws:iam::${var.management_account_id}:root"
      }
    }]
  })
}
```

## Environment Isolation

### Per-Account State Buckets

Each account has its own state bucket:

```hcl
bucket = format("tfstate-%s%s-%s",
  local.account_name,
  try(local.env_vars.locals.state_bucket_suffix, "") != "" ? "-${local.env_vars.locals.state_bucket_suffix}" : "",
  local.aws_region)
```

Results in:
- `tfstate-myproject-nonprod-staging-us-east-1`
- `tfstate-myproject-prod-us-east-1`

### Account-Level Variables

account.hcl provides account-specific values:

```hcl
# non-prod/account.hcl
locals {
  account_name   = "myproject-nonprod"
  aws_account_id = "111111111111"
  role_arn       = "arn:aws:iam::111111111111:role/TerraformCrossAccount"

  environment = "non-production"

  vpc_id             = "vpc-nonprod"
  private_subnet_ids = ["subnet-priv1", "subnet-priv2"]

  tags = {
    Environment = "non-production"
  }
}

# prod/account.hcl
locals {
  account_name   = "myproject-prod"
  aws_account_id = "222222222222"
  role_arn       = "arn:aws:iam::222222222222:role/TerraformCrossAccount"

  environment = "production"

  vpc_id             = "vpc-prod"
  private_subnet_ids = ["subnet-priv1", "subnet-priv2"]

  tags = {
    Environment = "production"
  }
}
```

## Cross-Account DNS

For ACM certificates with Route53 validation in a different account:

```hcl
# In stack
locals {
  dns_account_id = "333333333333"  # Route53 account
}

unit "acm" {
  values = {
    dns_account_id         = local.dns_account_id
    create_route53_records = false
  }
}

unit "route53" {
  values = {
    dns_account_id = local.dns_account_id
    acm_path       = "../acm"
  }
}
```

The root.hcl generates the cross-account provider automatically when `dns_account_id` is set.

## Deployment Order

Deploy shared infrastructure first:

1. Management account (IAM, Organizations)
2. Security account (GuardDuty, Security Hub)
3. Logging account (CloudTrail, Config)
4. Shared services (VPC, Transit Gateway)
5. Workload accounts (non-prod, prod)

Use `run-all` with dependency ordering:

```bash
cd infrastructure-live
terragrunt run-all apply
```
