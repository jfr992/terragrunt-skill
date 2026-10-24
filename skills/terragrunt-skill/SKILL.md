---
name: terragrunt-skill
description: >-
  Use for Terragrunt work (0.68 to 1.2; OpenTofu or Terraform): building an infrastructure catalog, explicit stacks (terragrunt.stack.hcl),
  units wrapping OpenTofu/Terraform modules, live repos with a root.hcl hierarchy, remote state and locking (S3
  lockfile, DynamoDB, GCS, azurerm), multi-account/multi-env with role assumption, classic Gruntwork live repos
  (_envcommon), migrating a terralith, exploring repos (find, list, dag), wiring dependencies (autoinclude,
  values), expansion blocks (for_each/count), the Content Addressable Store (CAS), OCI and versioned module
  sources, upgrading to 1.2, and CI/CD pipelines (GitHub Actions, GitLab).
license: Apache-2.0
compatibility: Terragrunt >= 0.68 (1.2 recommended); OpenTofu or Terraform. Version-specific guidance in references/version-compatibility.md. Agent-agnostic.
metadata:
  version: "3.0.0"
  terragrunt: ">=0.68 (target 1.2)"
  author: jfr992
---

# Terragrunt Infrastructure Skill

## Overview

This skill provides guidance for infrastructure using Terragrunt with OpenTofu, following a three-repository pattern:

1. **Infrastructure Catalog** - Units and stacks that reference modules from separate repos
2. **Infrastructure Live** - Environment-specific deployments consuming the catalog
3. **Module Repos** - Separate repositories for each OpenTofu module (independent versioning)

## Step 0: Detect Versions

Before giving commands, check `terragrunt --version`, `.terragrunt-version`, `mise.toml`/`.tool-versions`, `terragrunt_version_constraint` in `root.hcl`, and whether `tofu` or `terraform` is installed. This skill defaults to **TG 1.2 + OpenTofu ≥ 1.10**. For older Terragrunt (0.68+), Terraform, or classic layouts, follow [version-compatibility.md](references/version-compatibility.md): use `run-all`/`--terragrunt-*` on < 0.77.22, classic layouts on < 0.78, no `autoinclude` on < 1.1, no `expansion` on < 1.2, and no state encryption on Terraform.

## Choosing an Architecture

**Default recommendation: explicit stacks** — the catalog + `terragrunt.stack.hcl` + values pattern this skill teaches. Units are generated from stack files; configuration flows through `values`; no per-unit boilerplate.

**Supported alternative: classic implicit stacks** — the original Gruntwork pattern: `account/region/env/component` directory hierarchy, per-level `.hcl` variable files, shared component config in `_envcommon/` via `include` + `expose`. Any directory of units is an implicit stack. Use it when the repo already follows it, when the footprint is too small to justify a catalog, or when the team isn't ready for stacks. See [classic-live-structure.md](references/classic-live-structure.md).

**Orthogonal choice: module organization** — modules monorepo (`modules/` + `examples/`, one tag versions all, `//modules/x?ref=` sourcing) vs module-per-repo (independent versioning). Either works with either architecture. See [modules-monorepo.md](references/modules-monorepo.md).

Migrating classic → stacks: follow the official [Terralith to Terragrunt guide](https://docs.terragrunt.com/guides/terralith-to-terragrunt/).

## Quick Navigation

| Topic | Reference |
|-------|-----------|
| Version compatibility (TG 0.68→1.2, OpenTofu vs Terraform) | [version-compatibility.md](references/version-compatibility.md) |
| Naming conventions | [naming.md](references/naming.md) |
| Catalog structure | [catalog-structure.md](references/catalog-structure.md) |
| Live repo structure | [live-structure.md](references/live-structure.md) |
| Classic live structure (implicit stacks) | [classic-live-structure.md](references/classic-live-structure.md) |
| Modules monorepo | [modules-monorepo.md](references/modules-monorepo.md) |
| Discovery commands (find/list/dag) | [discovery-commands.md](references/discovery-commands.md) |
| Root/account/env configs | [root-config.md](references/root-config.md) |
| Unit dependencies | [dependencies.md](references/dependencies.md) |
| Expansion (for_each/count) | [expansion.md](references/expansion.md) |
| Catalog scaffolding | [catalog-scaffolding.md](references/catalog-scaffolding.md) |
| Stack commands | [stack-commands.md](references/stack-commands.md) |
| Patterns & best practices | [patterns.md](references/patterns.md) |
| State management | [state-management.md](references/state-management.md) |
| Multi-account setup | [multi-account.md](references/multi-account.md) |
| Performance optimization | [performance.md](references/performance.md) |
| Content Addressable Store (CAS) | [cas.md](references/cas.md) |
| CI/CD pipelines (shared + IAM/OIDC setup) | [cicd-pipelines.md](references/cicd-pipelines.md) |
| GitLab CI pipelines | [cicd-gitlab.md](references/cicd-gitlab.md) |
| GitHub Actions pipelines | [cicd-github.md](references/cicd-github.md) |

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

### Dependency Wiring (autoinclude first)

Since Terragrunt 1.1, declare dependencies in the stack file with `autoinclude` so catalog units stay dependency-agnostic. See [dependencies.md](references/dependencies.md) for the full pattern.

### Reference Resolution (legacy)

Older catalogs resolve symbolic references like `"../acm"` to dependency outputs inside the unit:

```hcl
inputs = {
  acm_certificate_arn = try(values.acm_certificate_arn, "") == "../acm" ?
    dependency.acm.outputs.acm_certificate_arn :
    values.acm_certificate_arn
}
```

Keep it when maintaining an existing catalog; prefer `autoinclude` for new work.

### Module Sourcing

Units reference modules via Git URL with version from values:

```hcl
terraform {
  source = "git::git@github.com:YOUR_ORG/modules/rds.git//app?ref=${values.version}"
}
```

For catalog-internal references (units/stacks/modules in the same repo), Terragrunt 1.1+ allows plain relative paths with `update_source_with_cas = true` — `stack generate` rewrites them to content-addressed references, so no URL pinning or version plumbing is needed. See [cas.md](references/cas.md).

## Common Operations

### Create New Unit

1. Create `units/<name>/terragrunt.hcl`
2. Reference module via Git URL with `${values.version}`
3. Use `values.xxx` for inputs
4. Add dependencies with mock outputs
5. Wire dependencies via `autoinclude` in the stack (legacy: `"../unit"` reference resolution)

### Create New Stack

1. Create `stacks/<name>/terragrunt.stack.hcl`
2. Define `locals` for computed values
3. Add `unit` blocks referencing catalog units
4. Pass values including version and dependency paths

### Deploy to New Environment

1. Create environment directory structure
2. Add `env.hcl` with `state_bucket_suffix`
3. Add stack files referencing catalog and run `terragrunt stack generate`
4. Run `terragrunt backend bootstrap --all` to create state resources (or pass `--backend-bootstrap` on the first run). Do not use `run --all -- backend bootstrap`: everything after `--` goes to OpenTofu/Terraform.

## Best Practices

1. **Pin module versions** - Use Git tags in `values.version`
2. **Pin catalog versions** - Use refs in unit source URLs
3. **Wire dependencies with autoinclude** - legacy `"../unit"` resolution only in existing catalogs
4. **Provide mock outputs** - Enable plan/validate without dependencies
5. **Auto-detect features** - `length(keys(try(values.X, {}))) > 0`
6. **Override paths** - `try(values.X_path, "../default")`
7. **Separate state per environment** - Use `state_bucket_suffix`

## Common Pitfalls

1. **Git refspec error** - Use `//path?ref=branch` NOT `?ref=branch//path`
2. **Heredoc in ternary** - Wrap in parentheses: `condition ? (\n<<-EOF\n...\nEOF\n) : ""`
3. **Missing mock outputs** - Always provide for plan/validate
4. **Hardcoded paths** - Use local paths only for testing

## Upgrading to 1.2

1. **`base64gzip()` output changed** - may force resource replacement; `base64gzip_compat` exists as an experiment.
2. **Generated files are read-only** - stored in CAS as links; set `mutable = true` on a `generate` block that must be edited (see [cas.md](references/cas.md)).
3. **S3 bootstrap no longer adds a root-access bucket policy** - set `enable_bucket_root_access = true` if you relied on it.
4. **Dependency outputs read from state by default** - S3/GCS/azurerm; encrypted state and other backends fall back to `output`; opt out with `--no-dependency-fetch-output-from-state` (see [performance.md](references/performance.md)).

## Docs Lookup

Prefer the Terragrunt docs MCP server `https://mcp.docs.terragrunt.com/mcp` (public beta) when available; otherwise https://docs.terragrunt.com.

## Version Management

- **Development:** Branch refs (`ref=feature-branch`)
- **Testing:** RC tags (`ref=v1.0.0-rc1`)
- **Production:** Stable tags (`ref=v1.0.0`)
