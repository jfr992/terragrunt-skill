# CI/CD Pipeline Examples

## Contents
- Overview
- Layouts and Versions Matrix
- Terragrunt Stack Commands
- Run Reports and Strict Mode in CI
- Platform Pipelines
- IAM Configuration
- References

## Overview

This guide covers both layouts: **explicit stacks** (`terragrunt.stack.hcl` + `stack run`) and **implicit stacks** (a tree of unit dirs run with `run --all`, or `run-all` on 0.68–0.7x). The detailed GitLab templates use explicit stacks on 1.x; the matrix below gives the equivalent commands for implicit stacks and older Terragrunt. Templates are suggestions that can be adapted to your organization's needs.

**Key features:**
- `terragrunt stack run` commands for explicit stacks
- OIDC-based authentication (no static credentials)
- SSH-based Git access (recommended over HTTPS)
- Provider caching for performance
- Selective unit targeting with `--filter` ([docs](https://docs.terragrunt.com/features/filter/))
- Change-based planning: with [CAS](cas.md) `update_source_with_cas`, unchanged units hash identically across catalog versions — a version bump only diffs changed units, so `--filter-affected` (or `--filter 'reading=<path>'`) plans only what changed instead of the whole tree

> **Why SSH over HTTPS?**
> - **Enhanced security**: SSH keys provide stronger authentication than passwords or tokens
> - **Credential-free operations**: Once configured, no credentials needed for each Git operation
> - **No token expiration**: Unlike HTTPS tokens, SSH keys don't expire unexpectedly mid-pipeline

---

## Layouts and Versions Matrix

Detect the version first (`terragrunt --version`, see [version-compatibility.md](version-compatibility.md)) and pick the row. Flags/env verified against 0.68.0, 0.78.0 and 1.2.1.

| | 0.68–0.7x | 0.78–0.96 | 0.97+ / 1.x |
|---|---|---|---|
| Implicit: plan all | `terragrunt run-all plan --terragrunt-non-interactive` | `terragrunt run --all --non-interactive -- plan` | same as 0.78+ |
| Implicit: subset | `--terragrunt-include-dir <dir>` (+ `--terragrunt-strict-include`) | `--queue-include-dir <dir>` (+ `--queue-strict-include`) | `--filter './<dir>'` (`--queue-include-dir` still works) |
| Explicit: plan all | not available — use implicit | `terragrunt stack run --non-interactive -- plan` | same |
| Explicit: one unit | — | `--queue-include-dir "$PWD/.terragrunt-stack/<unit>"` (**absolute path**; a relative one silently matches nothing on 0.78) | `--filter './.terragrunt-stack/<unit>'` |
| Env var prefix | `TERRAGRUNT_*` (e.g. `TERRAGRUNT_NON_INTERACTIVE`, `TERRAGRUNT_TFPATH`, `TERRAGRUNT_INCLUDE_DIR`) | `TG_*` (e.g. `TG_NON_INTERACTIVE`, `TG_TF_PATH`) | `TG_*` (`TERRAGRUNT_*` still read on 1.2 but deprecated) |
| Change detection | CI path rules + `git diff` → `--terragrunt-include-dir` per changed dir | CI path rules + `git diff` → `--queue-include-dir` | Git filter `--filter '[origin/main...HEAD]'` (worktree diff), or path rules |

`--terragrunt-*` flags were removed in 0.85 and `run-all` is gone by 1.0, so pin the binary version in the CI image and keep one row per pipeline.

**Change detection.** Explicit stacks: trigger on the stack file *and* the catalog it sources (`live/<env>/terragrunt.stack.hcl`, `catalog/**`), then plan the whole stack — generated `.terragrunt-stack/` is not in git. Implicit stacks: trigger on the unit dirs (`live/<env>/**/terragrunt.hcl`, `live/**/*.hcl`) and narrow the run:

```bash
# 0.97+/1.x: Terragrunt diffs the refs itself (checks out worktrees)
terragrunt run --all --non-interactive --filter "[origin/${BASE_REF:-main}...HEAD]" -- plan

# 0.68–0.96: build include flags from git diff (use --terragrunt-include-dir on 0.68)
INCLUDES=$(git diff --name-only "origin/${BASE_REF:-main}...HEAD" -- 'live/**/terragrunt.hcl' \
  | xargs -r -n1 dirname | sort -u | sed 's/^/--queue-include-dir /')
[ -n "$INCLUDES" ] && terragrunt run --all --non-interactive $INCLUDES -- plan
```

Include-dir runs also pull in the units' dependencies; add `--queue-strict-include` (0.68: `--terragrunt-strict-include`) to run only the listed dirs. Changes to a shared `root.hcl`/`_envcommon` affect every unit: plan everything when those paths change.

---

## Terragrunt Stack Commands

When working with explicit stacks (`terragrunt.stack.hcl`), use `terragrunt stack run` instead of `terragrunt run --all`:

```bash
# Navigate to stack directory
cd prod/us-east-1/my-service/

# Plan entire stack
terragrunt stack run -- plan

# Apply entire stack
terragrunt stack run -- apply

# Target specific units within the stack (using --filter)
terragrunt stack run --filter './.terragrunt-stack/dynamodb' -- plan
terragrunt stack run --filter './.terragrunt-stack/lambda' -- apply

# Target unit and its dependencies
terragrunt stack run --filter './.terragrunt-stack/lambda...' -- apply

# Destroy stack
terragrunt stack run -- destroy
```

### Useful Flags

| Flag | Description | Use Case |
|------|-------------|----------|
| `--filter` | Flexible unit targeting (recommended) | Target units, dependencies, patterns |
| `--queue-include-dir` | Target specific units by path (legacy) | Simple path-based targeting |
| `--queue-ignore-dag-order` | Run units concurrently | Faster plans (⚠️ dangerous for apply) |
| `--queue-ignore-errors` | Continue on failures | Identify all errors at once |
| `--out-dir` | Save plan files to directory | Artifact storage for apply stage |
| `--parallelism N` | Limit concurrent units | Prevent rate limiting |

> **Note:** The `.terragrunt-stack` directory is auto-generated. Use `terragrunt stack generate` to pre-generate it, or `terragrunt stack clean` to remove it.

---

## Run Reports and Strict Mode in CI

Emit a machine-readable run report for pipeline summaries:

```bash
terragrunt run --all --report-file report.json --report-schema-file schema.json -- plan
```

The report records per-unit result (succeeded/failed/excluded/early exit) and reason — feed it to your MR/PR summary step.

Fail pipelines on deprecated usage before upgrades bite:

```yaml
variables:
  TG_STRICT_MODE: "true"        # all deprecations become errors
  # or selectively:
  # TG_STRICT_CONTROL: "deprecated-flags,deprecated-env-vars"
```

---

## Platform Pipelines

- **GitLab CI** (templates, AWS/GCP OIDC auth, unit targeting): see [cicd-gitlab.md](cicd-gitlab.md)
- **GitHub Actions** (quick reference, differences from GitLab): see [cicd-github.md](cicd-github.md)

---

## IAM Configuration

### AWS OIDC Trust Policy

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:YOUR_ORG/YOUR_REPO:*"
        }
      }
    },
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/gitlab.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "gitlab.com:aud": "https://gitlab.com"
        },
        "StringLike": {
          "gitlab.com:sub": "project_path:YOUR_ORG/YOUR_REPO:*"
        }
      }
    }
  ]
}
```

### GCP Workload Identity Setup

**Using gcloud CLI:**

```bash
# Create workload identity pool
gcloud iam workload-identity-pools create "gitlab-pool" \
  --location="global" \
  --display-name="GitLab CI Pool"

# Create provider for GitLab
gcloud iam workload-identity-pools providers create-oidc "gitlab-provider" \
  --location="global" \
  --workload-identity-pool="gitlab-pool" \
  --issuer-uri="https://gitlab.com" \
  --attribute-mapping="google.subject=assertion.sub,attribute.project_path=assertion.project_path"

# Create provider for GitHub
gcloud iam workload-identity-pools providers create-oidc "github-provider" \
  --location="global" \
  --workload-identity-pool="github-pool" \
  --issuer-uri="https://token.actions.githubusercontent.com" \
  --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository"

# Grant service account impersonation
gcloud iam service-accounts add-iam-policy-binding \
  "sa-tf-admin@PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/gitlab-pool/attribute.project_path/YOUR_ORG/YOUR_REPO"
```

**Using OpenTofu/Terraform:**

```hcl
# variables.tf
variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "terraforming" {
  description = "Terraforming configuration for CI/CD"
  type = object({
    enabled           = bool
    repo_namespace_ids = optional(list(string), [])
    delegated_repos   = optional(list(string), [])
    jwks_json         = optional(string)
  })
  default = {
    enabled = false
  }
}

# locals.tf
locals {
  # Terraform admin service account (created when terraforming enabled)
  tf_admin_account = var.terraforming.enabled ? [
    {
      id          = "sa-tf-admin"
      name        = "TF Admin"
      description = "Terraform Admin service account"
      disabled    = false
    }
  ] : []

  # Namespace condition for GitLab OIDC (restrict to specific groups/namespaces)
  namespace_condition = var.terraforming.enabled && length(var.terraforming.repo_namespace_ids) > 0 ? (
    join(" || ", [for id in var.terraforming.repo_namespace_ids : "assertion.namespace_id=='${id}'"])
  ) : null

  # Workload Identity pool configuration
  tf_workload_identity_pool = var.terraforming.enabled ? [
    {
      id          = "gitlab-pool"
      name        = "GitLab CI Pool"
      description = "Workload Identity pool for GitLab CI/CD"
      disabled    = false
      providers = [
        {
          id          = "gitlab-provider"
          name        = "GitLab OIDC Provider"
          description = "OpenID Connect provider for GitLab"
          disabled    = false
          type        = "oidc"
          attribute_mapping = {
            "google.subject" = "assertion.project_path"
          }
          attribute_condition = local.namespace_condition
          settings = {
            issuer_uri = "https://gitlab.com/"
            jwks_json  = var.terraforming.jwks_json
          }
        }
      ]
    }
  ] : []

  service_accounts        = { for sa in local.tf_admin_account : sa.id => sa }
  workload_identity_pools = { for wp in local.tf_workload_identity_pool : wp.id => wp }
}

# main.tf
resource "google_service_account" "tf_admin" {
  for_each = local.service_accounts

  project      = var.project_id
  account_id   = each.value.id
  display_name = each.value.name
  description  = each.value.description
  disabled     = each.value.disabled
}

resource "google_iam_workload_identity_pool" "pool" {
  for_each = local.workload_identity_pools

  project                   = var.project_id
  workload_identity_pool_id = each.value.id
  display_name              = each.value.name
  description               = each.value.description
  disabled                  = each.value.disabled
}

resource "google_iam_workload_identity_pool_provider" "provider" {
  for_each = { for p in flatten([
    for pool_key, pool in local.workload_identity_pools : [
      for provider in pool.providers : {
        pool_id     = pool_key
        provider_id = provider.id
        provider    = provider
      }
    ]
  ]) : "${p.pool_id}-${p.provider_id}" => p }

  project                            = var.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.pool[each.value.pool_id].workload_identity_pool_id
  workload_identity_pool_provider_id = each.value.provider_id
  display_name                       = each.value.provider.name
  description                        = each.value.provider.description
  disabled                           = each.value.provider.disabled
  attribute_mapping                  = each.value.provider.attribute_mapping
  attribute_condition                = each.value.provider.attribute_condition

  oidc {
    issuer_uri = each.value.provider.settings.issuer_uri
  }
}

# Grant workload identity user role to delegated repos
resource "google_service_account_iam_member" "workload_identity_user" {
  for_each = toset(var.terraforming.delegated_repos)

  service_account_id = google_service_account.tf_admin["sa-tf-admin"].id
  role               = "roles/iam.workloadIdentityUser"
  member             = format(
    "principal://iam.googleapis.com/%s/subject/%s",
    google_iam_workload_identity_pool.pool["gitlab-pool"].name,
    each.value
  )
}

# Grant project owner to TF admin service account
resource "google_project_iam_member" "tf_admin_owner" {
  count   = var.terraforming.enabled ? 1 : 0
  project = var.project_id
  role    = "roles/owner"
  member  = google_service_account.tf_admin["sa-tf-admin"].member
}
```

**Example usage:**

```hcl
module "gcp_workload_identity" {
  source = "./modules/gcp-workload-identity"

  project_id = "my-project-dev"

  terraforming = {
    enabled            = true
    repo_namespace_ids = ["12345678"]  # GitLab group/namespace ID
    delegated_repos    = [
      "my-org/infrastructure-live",
      "my-org/infrastructure-catalog"
    ]
  }
}
```

---

## References

### Terragrunt Stack Commands
- [Terragrunt Stacks](https://docs.terragrunt.com/features/stacks/) - Official documentation for explicit stacks
- [Terragrunt Run Command](https://docs.terragrunt.com/reference/cli/commands/run/) - CLI reference for run flags
- [Run Queue](https://docs.terragrunt.com/features/stacks/run-queue/) - Queue flags and filtering

### CI/CD Basics
- [Terragrunt Performance Guide](performance.md)

### Cloud OIDC
- [AWS OIDC for GitHub Actions](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services)
- [GCP Workload Identity Federation](https://cloud.google.com/iam/docs/workload-identity-federation)
