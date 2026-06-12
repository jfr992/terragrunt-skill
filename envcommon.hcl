# _envcommon/mysql.hcl
locals {
  environment_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  env              = local.environment_vars.locals.environment

  # Exposed so children can build a versioned source URL
  base_source_url = "git::git@github.com:YOUR_ORG/infrastructure-modules.git//modules/mysql"
}

inputs = {
  name              = "mysql_${local.env}"
  instance_class    = "db.t3.micro"
  allocated_storage = 20
}
