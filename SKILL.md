---
name: terragrunt-skill
description: "Use this skill when working with Terragrunt infrastructure configurations. Triggers include: setting up a new Terragrunt infrastructure catalog from scratch, creating or managing Terragrunt stacks (terragrunt.stack.hcl), creating units that wrap OpenTofu modules from separate repos, configuring live infrastructure repositories with root.hcl hierarchy, setting up remote state backends (S3 with DynamoDB locking), and multi-account/multi-environment deployments with cross-account role assumption."
---

# Terragrunt Infrastructure Skill

## Overview

Terragrunt with OpenTofu, following a three-repository pattern:

| Repository | Purpose |
|-----------|---------|
| **Infrastructure Catalog** | Reusable units and stacks referencing modules from separate repos |
| **Infrastructure Live** | Environment-specific deployments consuming the catalog |
| **Module Repos** | Separate repos per OpenTofu module (independent versioning) |

## Quick Navigation

| Topic | Reference |
|-------|-----------|
| Naming conventions | [naming.md](references/naming.md) |
| Catalog structure | [catalog-structure.md](references/catalog-structure.md) |
| Live repo structure | [live-structure.md](references/live-structure.md) |
| Root/account/env configs | [root-config.md](references/root-config.md) |
| Unit dependencies | [dependencies.md](references/dependencies.md) |
| Catalog scaffolding | [catalog-scaffolding.md](references/catalog-scaffolding.md) |
| Stack commands | [stack-commands.md](references/stack-commands.md) |
| Patterns & best practices | [patterns.md](references/patterns.md) |
| State management | [state-management.md](references/state-management.md) |
| Multi-account setup | [multi-account.md](references/multi-account.md) |
| Performance optimization | [performance.md](references/performance.md) |
| CI/CD pipelines | [cicd-pipelines.md](references/cicd-pipelines.md) |

## Core Concepts

### Values Pattern

Units receive configuration through `values.xxx`:

```hcl
inputs = {
  name        = values.name
  environment = values.environment
  instance_class = try(values.instance_class, "db.t3.medium")  # Optional with default
}
```

### Reference Resolution

Units resolve symbolic references like `"../acm"` to dependency outputs:

```hcl
inputs = {
  acm_certificate_arn = try(values.acm_certificate_arn, "") == "../acm" ?
    dependency.acm.outputs.acm_certificate_arn :
    values.acm_certificate_arn
}
```

### Module Sourcing

Units reference modules via Git URL with version from values:

```hcl
terraform {
  source = "git::git@github.com:YOUR_ORG/modules/rds.git//app?ref=${values.version}"
}
```

## Common Operations

### Create New Unit

Create `units/<name>/terragrunt.hcl` with module source, values-driven inputs, dependencies, and reference resolution:

```hcl
terraform {
  source = "git::git@github.com:YOUR_ORG/modules/rds.git//app?ref=${values.version}"
}

dependency "vpc" {
  config_path = try(values.vpc_path, "../vpc")
  mock_outputs = {
    vpc_id             = "vpc-mock"
    private_subnet_ids = ["subnet-mock-1", "subnet-mock-2"]
  }
}

inputs = {
  name           = values.name
  environment    = values.environment
  instance_class = try(values.instance_class, "db.t3.medium")
  vpc_id         = dependency.vpc.outputs.vpc_id
  subnet_ids     = dependency.vpc.outputs.private_subnet_ids
}
```

Validate before proceeding: `terragrunt validate` then `terragrunt plan` to verify dependency resolution.

### Create New Stack

Create `stacks/<name>/terragrunt.stack.hcl` with locals, unit blocks, and dependency wiring:

```hcl
locals {
  env     = "staging"
  version = "v1.2.0"
}

unit "vpc" {
  source = "${get_repo_root()}/units/vpc"
  values = {
    name        = "main-vpc"
    environment = local.env
    version     = local.version
  }
}

unit "rds" {
  source = "${get_repo_root()}/units/rds"
  values = {
    name        = "app-db"
    environment = local.env
    version     = local.version
    vpc_path    = "../vpc"
  }
}
```

Validate the stack: `terragrunt stack generate` to verify unit resolution, then `terragrunt stack plan` to check the full dependency graph.

### Deploy to New Environment

1. Create environment directory structure
2. Add `env.hcl` with `state_bucket_suffix`
3. Run `./setup-state-backend.sh` to create state resources
4. Add stack files referencing catalog
5. Validate: run `terragrunt validate` then `terragrunt plan` on the new environment before applying

If validation fails: check `root.hcl` includes are correct and `env.hcl` locals match expected names. If state backend setup fails: verify IAM permissions, S3 bucket policies, and DynamoDB table exists. Re-run `./setup-state-backend.sh` after fixing.

## Best Practices

1. **Pin module versions** - Use Git tags in `values.version`
2. **Pin catalog versions** - Use refs in unit source URLs
3. **Use reference resolution** - `"../unit"` → dependency outputs
4. **Provide mock outputs** - Enable plan/validate without dependencies
5. **Auto-detect features** - `length(keys(try(values.X, {}))) > 0`
6. **Override paths** - `try(values.X_path, "../default")`
7. **Separate state per environment** - Use `state_bucket_suffix`

## Common Pitfalls

1. **Git refspec error** - Use `//path?ref=branch` NOT `?ref=branch//path`
2. **Heredoc in ternary** - Wrap in parentheses: `condition ? (\n<<-EOF\n...\nEOF\n) : ""`
3. **Missing mock outputs** - Always provide for plan/validate
4. **Hardcoded paths** - Use local paths only for testing

## Version Management

- **Development:** Branch refs (`ref=feature-branch`)
- **Testing:** RC tags (`ref=v1.0.0-rc1`)
- **Production:** Stable tags (`ref=v1.0.0`)
