# Classic Live Structure (Implicit Stacks)

The classic Gruntwork pattern: units organized in an account/region/environment directory hierarchy, with shared configuration pulled in via `include` blocks. Upstream calls this **implicit stacks** — any directory of units is a stack, no `terragrunt.stack.hcl` required.

**Use this pattern when:**
- Working in an existing repo that already uses it (most pre-stacks Terragrunt repos do)
- Small footprint that doesn't justify a separate catalog repo
- Team prefers the 8-years-battle-tested layout over explicit stacks

**Prefer [explicit stacks](stack-commands.md) for new builds** — they eliminate the per-unit boilerplate this pattern requires. To migrate classic → stacks, see the official [Terralith to Terragrunt guide](https://docs.terragrunt.com/guides/terralith-to-terragrunt/).

## Directory Layout

```
infrastructure-live/
├── root.hcl                      # Remote state, provider generation, global inputs
├── _envcommon/                   # Per-component config shared across ALL environments
│   ├── mysql.hcl
│   └── webserver-cluster.hcl
├── non-prod/
│   ├── account.hcl               # account_name, aws_account_id
│   └── us-east-1/
│       ├── region.hcl            # aws_region
│       ├── qa/
│       │   ├── env.hcl           # environment = "qa"
│       │   ├── mysql/terragrunt.hcl
│       │   └── webserver-cluster/terragrunt.hcl
│       └── stage/
│           ├── env.hcl
│           ├── mysql/terragrunt.hcl
│           └── webserver-cluster/terragrunt.hcl
└── prod/
    ├── account.hcl
    └── us-east-1/
        ├── region.hcl
        └── prod/
            ├── env.hcl
            ├── mysql/terragrunt.hcl
            └── webserver-cluster/terragrunt.hcl
```

Each level contributes variables; each leaf directory is one unit with its own state.

## root.hcl

```hcl
locals {
  account_vars     = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  region_vars      = read_terragrunt_config(find_in_parent_folders("region.hcl"))
  environment_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))

  account_name = local.account_vars.locals.account_name
  account_id   = local.account_vars.locals.aws_account_id
  aws_region   = local.region_vars.locals.aws_region
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "aws" {
  region              = "${local.aws_region}"
  allowed_account_ids = ["${local.account_id}"]
}
EOF
}

remote_state {
  backend = "s3"
  config = {
    encrypt      = true
    bucket       = "tfstate-${local.account_name}-${local.aws_region}"
    key          = "${path_relative_to_include()}/terraform.tfstate"
    region       = local.aws_region
    use_lockfile = true
  }
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
}

# Merged into every child config via include — all modules inherit these
inputs = merge(
  local.account_vars.locals,
  local.region_vars.locals,
  local.environment_vars.locals,
)
```

## Level files

```hcl
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
```

## _envcommon: shared component config

One file per component, holding everything common across environments:

```hcl
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
```

## Unit terragrunt.hcl

The leaf file only declares includes, the module version, and environment-specific overrides:

```hcl
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
```

## Dependencies between components

Sibling components wire together with `dependency` blocks, exactly as in explicit stacks:

```hcl
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
```

## Running

The directory you run from defines the implicit stack:

```bash
# One unit
cd non-prod/us-east-1/qa/mysql && terragrunt apply

# Whole environment, dependency-ordered
cd non-prod/us-east-1/qa && terragrunt run --all apply

# Whole account
cd non-prod && terragrunt run --all plan

# Explore an unfamiliar repo first (see discovery-commands.md)
terragrunt find --dag --dependencies
```

## Trade-offs vs explicit stacks

| | Classic (implicit) | Explicit stacks |
|---|---|---|
| Per-unit boilerplate | 2 include blocks + source per unit | None — units generated from stack file |
| Adding an environment | Copy directory tree, edit env.hcl | One new `terragrunt.stack.hcl` |
| Version promotion | Edit `?ref=` in each unit per env | Edit one value in the stack file |
| Learning curve | Low, widely documented | Stacks concepts (values, generation) |
| Maturity | 8+ years | Stable since 1.0 |
