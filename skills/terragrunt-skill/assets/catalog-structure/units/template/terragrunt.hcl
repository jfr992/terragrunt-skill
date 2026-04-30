include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  # Module in separate repo - use Git URL with version from values
  # NOTE: Modules are in SEPARATE repos, not in the catalog
  source = "git::git@github.com:YOUR_ORG/modules/MODULE_NAME.git//app?ref=${values.version}"
}

# Declare dependencies on other units
dependency "other_unit" {
  config_path  = try(values.other_unit_path, "../other_unit")  # Allow path override
  skip_outputs = !try(values.use_other_unit, false)           # Conditional dependency

  # MUST provide mock outputs for plan/validate
  mock_outputs = {
    id  = "mock-id"
    arn = "arn:aws:service:us-east-1:123456789012:resource/mock"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

inputs = {
  # Required inputs from values
  name        = values.name
  environment = values.environment

  # Optional inputs with defaults using try()
  instance_class = try(values.instance_class, "db.t3.medium")

  # Auto-detect feature flags from config presence
  create_feature = try(values.create_feature, length(try(values.feature_config, {})) > 0)

  # Reference resolution: resolve "../unit" to dependency outputs
  some_arn = try(values.some_arn, "") == "../other_unit" ?
    dependency.other_unit.outputs.arn :
    values.some_arn

  # Pass through tags
  tags = values.tags
}
