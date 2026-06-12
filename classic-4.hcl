# non-prod/us-east-1/qa/mysql/terragrunt.hcl
include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("root.hcl"))}/_envcommon/mysql.hcl"
  expose = true
}

# Version promoted one environment at a time: qa -> stage -> prod
terraform {
  source = "${include.envcommon.locals.base_source_url}?ref=v0.8.0"
}

# Only environment-specific overrides go here
inputs = {
  instance_class = "db.t3.small"
}
