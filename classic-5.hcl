# non-prod/us-east-1/qa/webserver-cluster/terragrunt.hcl (excerpt)
dependency "mysql" {
  config_path = "../mysql"

  mock_outputs = {
    address = "mock-mysql-endpoint"
    port    = 3306
  }
  mock_outputs_allowed_terraform_commands = ["plan", "validate"]
}

inputs = {
  db_address = dependency.mysql.outputs.address
  db_port    = dependency.mysql.outputs.port
}
