locals {
  environment         = "staging"
  state_bucket_suffix = local.environment  # Creates: tfstate-myproject-nonprod-staging-us-east-1
}
