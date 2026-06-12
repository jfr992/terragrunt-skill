# non-prod/account.hcl
locals {
  account_name   = "non-prod"
  aws_account_id = "123456789012"
}

# non-prod/us-east-1/region.hcl
locals {
  aws_region = "us-east-1"
}

# non-prod/us-east-1/qa/env.hcl
locals {
  environment = "qa"
}
