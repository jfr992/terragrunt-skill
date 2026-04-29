# CI/CD Pipeline Examples

## Overview

This guide provides CI/CD pipeline templates for **Terragrunt Stacks** (explicit stacks using `terragrunt.stack.hcl`). These templates are suggestions that can be adapted to your organization's needs.

**Key features:**
- `terragrunt stack run` commands for explicit stacks
- OIDC-based authentication (no static credentials)
- SSH-based Git access (recommended over HTTPS)
- Provider caching for performance
- Selective unit targeting with `--filter` ([docs](https://terragrunt.gruntwork.io/docs/features/filter/))

> **Why SSH over HTTPS?**
> - **Enhanced security**: SSH keys provide stronger authentication than passwords or tokens
> - **Credential-free operations**: Once configured, no credentials needed for each Git operation
> - **No token expiration**: Unlike HTTPS tokens, SSH keys don't expire unexpectedly mid-pipeline

---

## Terragrunt Stack Commands

When working with explicit stacks (`terragrunt.stack.hcl`), use `terragrunt stack run` instead of `terragrunt run-all`:

```bash
# Navigate to stack directory
cd prod/us-east-1/my-service/

# Plan entire stack
terragrunt stack run plan

# Apply entire stack
terragrunt stack run apply

# Target specific units within the stack (using --filter)
terragrunt stack run plan --filter '.terragrunt-stack/dynamodb'
terragrunt stack run apply --filter '.terragrunt-stack/lambda'

# Target unit and its dependencies
terragrunt stack run apply --filter '.terragrunt-stack/lambda...'

# Destroy stack
terragrunt stack run destroy
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

## GitLab CI

> **Best Practice: Reusable Templates**
>
> Structure GitLab CI with reusable templates (`.template-name`) that can be extended and overridden:
> - **Consistency**: All jobs follow the same patterns
> - **Maintainability**: Update logic in one place
> - **Flexibility**: Override specific steps when needed
>
> These templates are suggestions—adapt them to your organization's requirements.

### Base Templates (`.gitlab-ci.yml`)

```yaml
stages:
  - checks
  - plan
  - apply

default:
  image: "ghcr.io/opentofu/opentofu:latest"

variables:
  TG_STACK_PATH: "."              # Path to terragrunt.stack.hcl directory
  TG_PARALLELISM: "10"
  # Performance: Provider caching
  TG_PROVIDER_CACHE: "1"
  TG_PROVIDER_CACHE_DIR: "/tmp/provider-cache"
  TG_DOWNLOAD_DIR: "/tmp/module-cache"

# -----------------------------------------------------------------------------
# REUSABLE TEMPLATES
# -----------------------------------------------------------------------------

.terragrunt-cache:
  cache:
    key: terragrunt-${CI_COMMIT_REF_SLUG}
    paths:
      - /tmp/provider-cache
      - /tmp/module-cache
    policy: pull-push

.ssh-setup:
  before_script:
    - |
      mkdir -p ~/.ssh && chmod 700 ~/.ssh
      ssh-keyscan -t rsa github.com >> ~/.ssh/known_hosts 2>/dev/null
      ssh-keyscan -t rsa gitlab.com >> ~/.ssh/known_hosts 2>/dev/null

      # Setup SSH key for private repos (implementation depends on your secret management)
      # Options: SOPS, HashiCorp Vault, AWS Secrets Manager, GCP Secret Manager, etc.
      # <RETRIEVE_SSH_KEY_FROM_SECRET_MANAGER> > ~/.ssh/id_rsa
      chmod 0400 ~/.ssh/id_rsa

# -----------------------------------------------------------------------------
# CHECK TEMPLATES
# -----------------------------------------------------------------------------

.terragrunt_version_check_template:
  stage: checks
  cache: {}
  script:
    - |
      echo "===== Version Check ====="
      # Adapt version checks to your tooling
      terragrunt --version
      tofu --version || terraform --version
  rules:
    - if: '$CI_PIPELINE_SOURCE == "merge_request_event"'
    - if: '$CI_COMMIT_REF_NAME == $CI_DEFAULT_BRANCH'

.terragrunt_fmt_template:
  stage: checks
  cache: {}
  script:
    - cd $TG_STACK_PATH
    - terragrunt hclfmt --terragrunt-check
  rules:
    - if: '$CI_PIPELINE_SOURCE == "merge_request_event"'
    - if: '$CI_COMMIT_REF_NAME == $CI_DEFAULT_BRANCH'

# -----------------------------------------------------------------------------
# STACK PLAN TEMPLATE
# -----------------------------------------------------------------------------

.terragrunt_stack_plan_template:
  stage: plan
  extends:
    - .terragrunt-cache
  script:
    - cd $TG_STACK_PATH
    - |
      echo "===== Stack Plan ====="

      # Plan entire stack
      terragrunt stack run plan \
        --parallelism ${TG_PARALLELISM}

      # Optional: Use --out-dir to save plans for apply stage
      # terragrunt stack run plan --out-dir ${CI_PROJECT_DIR}/plans
  artifacts:
    paths:
      - $TG_STACK_PATH/.terragrunt-stack/**/tfplan
    expire_in: 1 day
  rules:
    - if: '$CI_PIPELINE_SOURCE == "merge_request_event"'
      changes:
        - $TG_STACK_PATH/**/*
    - if: '$CI_COMMIT_REF_NAME == $CI_DEFAULT_BRANCH'
      changes:
        - $TG_STACK_PATH/**/*

# -----------------------------------------------------------------------------
# STACK APPLY TEMPLATE
# -----------------------------------------------------------------------------

.terragrunt_stack_apply_template:
  stage: apply
  extends:
    - .terragrunt-cache
  script:
    - cd $TG_STACK_PATH
    - |
      echo "===== Stack Apply ====="

      # Re-plan and apply (recommended for safety)
      terragrunt stack run plan \
        --parallelism ${TG_PARALLELISM}

      terragrunt stack run apply \
        --parallelism ${TG_PARALLELISM}
  rules:
    - if: '$CI_PIPELINE_SOURCE == "merge_request_event"'
      when: manual
      changes:
        - $TG_STACK_PATH/**/*
    - if: '$CI_COMMIT_REF_NAME == $CI_DEFAULT_BRANCH'
      changes:
        - $TG_STACK_PATH/**/*

# -----------------------------------------------------------------------------
# TARGETED UNIT TEMPLATES (Optional)
# -----------------------------------------------------------------------------
# Use these when you need to deploy specific units within a stack

.terragrunt_stack_plan_unit_template:
  stage: plan
  extends:
    - .terragrunt-cache
  script:
    - cd $TG_STACK_PATH
    - |
      echo "===== Plan Unit: ${TG_TARGET_UNIT} ====="
      terragrunt stack run plan \
        --queue-include-dir ".terragrunt-stack/${TG_TARGET_UNIT}" \
        --parallelism ${TG_PARALLELISM}
  variables:
    TG_TARGET_UNIT: ""  # Override per job (e.g., "dynamodb", "lambda")

.terragrunt_stack_apply_unit_template:
  stage: apply
  extends:
    - .terragrunt-cache
  script:
    - cd $TG_STACK_PATH
    - |
      echo "===== Apply Unit: ${TG_TARGET_UNIT} ====="
      terragrunt stack run plan \
        --queue-include-dir ".terragrunt-stack/${TG_TARGET_UNIT}" \
        --parallelism ${TG_PARALLELISM}

      terragrunt stack run apply \
        --queue-include-dir ".terragrunt-stack/${TG_TARGET_UNIT}" \
        --parallelism ${TG_PARALLELISM}
  variables:
    TG_TARGET_UNIT: ""
```

---

### AWS Authentication Pattern

```yaml
# aws/.gitlab-ci-aws.yml

.aws-variables:
  variables:
    AWS_REGION: "us-east-1"
    TG_TARGET_ACCOUNT: ""      # Set per environment
    TG_TARGET_ASSUME_ROLE: "TerraformCrossAccount"
    TG_ACCESS_DURATION_SECONDS: "3600"

.aws-oidc-auth:
  id_tokens:
    AWS_OIDC_TOKEN:
      aud: https://gitlab.com
  before_script:
    - |
      echo "===== AWS OIDC Authentication ====="

      # Get temporary credentials via OIDC
      ROLE_ARN="arn:aws:iam::${TG_TARGET_ACCOUNT}:role/${TG_TARGET_ASSUME_ROLE}"

      CREDS=$(aws sts assume-role-with-web-identity \
        --role-arn "$ROLE_ARN" \
        --role-session-name "gitlab-ci-${CI_PIPELINE_ID}" \
        --web-identity-token "$AWS_OIDC_TOKEN" \
        --duration-seconds "${TG_ACCESS_DURATION_SECONDS}" \
        --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' \
        --output text)

      export AWS_ACCESS_KEY_ID=$(echo $CREDS | awk '{print $1}')
      export AWS_SECRET_ACCESS_KEY=$(echo $CREDS | awk '{print $2}')
      export AWS_SESSION_TOKEN=$(echo $CREDS | awk '{print $3}')

      echo "Authenticated to account: $TG_TARGET_ACCOUNT"

      # SSH setup for private repos (see .ssh-setup template)
      mkdir -p ~/.ssh && chmod 700 ~/.ssh
      ssh-keyscan -t rsa github.com >> ~/.ssh/known_hosts 2>/dev/null
      ssh-keyscan -t rsa gitlab.com >> ~/.ssh/known_hosts 2>/dev/null
      # <RETRIEVE_SSH_KEY_FROM_SECRET_MANAGER> > ~/.ssh/id_rsa
      chmod 0400 ~/.ssh/id_rsa

# Example: AWS Staging Stack
.aws-staging-stack:
  extends: .aws-variables
  variables:
    TG_STACK_PATH: "non-prod/us-east-1/staging/my-service"
    TG_TARGET_ACCOUNT: "111111111111"
    AWS_REGION: "us-east-1"

# Example jobs using stack templates
aws:staging:fmt:
  extends:
    - .terragrunt_fmt_template
    - .aws-staging-stack
  rules:
    - if: '$CI_PIPELINE_SOURCE == "merge_request_event"'
      changes:
        - non-prod/us-east-1/staging/**/*

aws:staging:plan:
  extends:
    - .terragrunt_stack_plan_template
    - .aws-oidc-auth
    - .aws-staging-stack
  needs: ["aws:staging:fmt"]
  rules:
    - if: '$CI_PIPELINE_SOURCE == "merge_request_event"'
      changes:
        - non-prod/us-east-1/staging/**/*

aws:staging:apply:
  extends:
    - .terragrunt_stack_apply_template
    - .aws-oidc-auth
    - .aws-staging-stack
  rules:
    - if: '$CI_COMMIT_REF_NAME == "main"'
      changes:
        - non-prod/us-east-1/staging/**/*
```

---

### GCP Authentication Pattern

```yaml
# gcp/.gitlab-ci-gcp.yml

.gcp-variables:
  variables:
    GC_PROJECT_NUMBER: ""      # Set per environment
    SERVICE_ACCOUNT: ""        # Set per environment
    WORKLOAD_IDENTITY_POOL: "gitlab-pool"
    WORKLOAD_IDENTITY_PROVIDER: "gitlab-provider"
    GOOGLE_APPLICATION_CREDENTIALS: $CI_BUILDS_DIR/.workload_identity.wlconfig

.gcp-oidc-auth:
  id_tokens:
    GITLAB_OIDC_TOKEN:
      aud: https://iam.googleapis.com/projects/${GC_PROJECT_NUMBER}/locations/global/workloadIdentityPools/${WORKLOAD_IDENTITY_POOL}/providers/${WORKLOAD_IDENTITY_PROVIDER}
  before_script:
    - |
      echo "===== GCP Workload Identity Authentication ====="

      # Write OIDC token
      echo $GITLAB_OIDC_TOKEN > $CI_BUILDS_DIR/.workload_identity.jwt
      export TF_VAR_gitlab_token=$GITLAB_OIDC_TOKEN

      # Create workload identity config
      cat << EOF > $GOOGLE_APPLICATION_CREDENTIALS
      {
        "type": "external_account",
        "audience": "//iam.googleapis.com/projects/$GC_PROJECT_NUMBER/locations/global/workloadIdentityPools/$WORKLOAD_IDENTITY_POOL/providers/$WORKLOAD_IDENTITY_PROVIDER",
        "subject_token_type": "urn:ietf:params:oauth:token-type:jwt",
        "token_url": "https://sts.googleapis.com/v1/token",
        "credential_source": {
          "file": "$CI_BUILDS_DIR/.workload_identity.jwt"
        },
        "service_account_impersonation_url": "https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/$SERVICE_ACCOUNT:generateAccessToken"
      }
      EOF

      echo "Authenticated as: $SERVICE_ACCOUNT"

      # SSH setup for private repos (see .ssh-setup template)
      mkdir -p ~/.ssh && chmod 700 ~/.ssh
      ssh-keyscan -t rsa github.com >> ~/.ssh/known_hosts 2>/dev/null
      ssh-keyscan -t rsa gitlab.com >> ~/.ssh/known_hosts 2>/dev/null
      # <RETRIEVE_SSH_KEY_FROM_SECRET_MANAGER> > ~/.ssh/id_rsa
      chmod 0400 ~/.ssh/id_rsa

# Example: GCP Dev Stack
.gcp-dev-stack:
  extends: .gcp-variables
  variables:
    TG_STACK_PATH: "gcp-dev/us-east4/my-service"
    TG_PARALLELISM: "5"
    GC_PROJECT_NUMBER: "123456789012"
    SERVICE_ACCOUNT: "sa-tf-admin@my-project-dev.iam.gserviceaccount.com"
  tags:
    - gcp

# Example jobs using stack templates
gcp:dev:fmt:
  extends:
    - .terragrunt_fmt_template
    - .gcp-dev-stack
  rules:
    - if: '$CI_PIPELINE_SOURCE == "merge_request_event"'
      changes:
        - gcp-dev/us-east4/**/*

gcp:dev:plan:
  extends:
    - .terragrunt_stack_plan_template
    - .gcp-oidc-auth
    - .gcp-dev-stack
  needs: ["gcp:dev:fmt"]
  rules:
    - if: '$CI_PIPELINE_SOURCE == "merge_request_event"'
      changes:
        - gcp-dev/us-east4/**/*

gcp:dev:apply:
  extends:
    - .terragrunt_stack_apply_template
    - .gcp-oidc-auth
    - .gcp-dev-stack
  rules:
    - if: '$CI_COMMIT_REF_NAME == "main"'
      changes:
        - gcp-dev/us-east4/**/*
```

---

### Targeting Specific Units

When you need to deploy specific units within a stack (e.g., only the database component):

```yaml
# Example: Target a specific unit within the stack

gcp:dev:dynamodb:plan:
  extends:
    - .terragrunt_stack_plan_unit_template
    - .gcp-oidc-auth
    - .gcp-dev-stack
  variables:
    TG_TARGET_UNIT: "dynamodb"
  rules:
    - if: '$CI_PIPELINE_SOURCE == "merge_request_event"'
      changes:
        - gcp-dev/us-east4/my-service/terragrunt.stack.hcl

gcp:dev:dynamodb:apply:
  extends:
    - .terragrunt_stack_apply_unit_template
    - .gcp-oidc-auth
    - .gcp-dev-stack
  variables:
    TG_TARGET_UNIT: "dynamodb"
  needs: ["gcp:dev:dynamodb:plan"]
  rules:
    - if: '$CI_COMMIT_REF_NAME == "main"'
      when: manual
```

> **Tip:** Use `--queue-include-dir` to target multiple units:
> ```bash
> terragrunt stack run plan \
>   --queue-include-dir ".terragrunt-stack/s3" \
>   --queue-include-dir ".terragrunt-stack/dynamodb"
> ```

---

## GitHub Actions

> **Work in Progress**: GitHub Actions workflows are under development. For now, refer to the GitLab CI examples above and adapt them for GitHub Actions using:
> - [aws-actions/configure-aws-credentials](https://github.com/aws-actions/configure-aws-credentials) for AWS OIDC
> - [google-github-actions/auth](https://github.com/google-github-actions/auth) for GCP Workload Identity
> - [actions/cache](https://github.com/actions/cache) for provider caching

### Key Differences from GitLab CI

| GitLab CI | GitHub Actions |
|-----------|----------------|
| `id_tokens` block | `permissions: id-token: write` |
| `extends: .template` | `uses: ./.github/workflows/reusable.yml` |
| `rules: changes:` | `paths:` filter or `dorny/paths-filter` |
| `needs: [job]` | `needs: [job]` (same) |
| `when: manual` | `environment:` with required reviewers |

### Quick Reference

```yaml
# AWS OIDC Authentication
- name: Configure AWS Credentials
  uses: aws-actions/configure-aws-credentials@v4
  with:
    role-to-assume: arn:aws:iam::111111111111:role/TerraformCrossAccount
    aws-region: us-east-1

# GCP Workload Identity
- name: Authenticate to GCP
  uses: google-github-actions/auth@v2
  with:
    workload_identity_provider: 'projects/123456789012/locations/global/workloadIdentityPools/github-pool/providers/github-provider'
    service_account: 'sa-tf-admin@my-project.iam.gserviceaccount.com'
```

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
- [Terragrunt Stacks](https://terragrunt.gruntwork.io/docs/features/stacks/) - Official documentation for explicit stacks
- [Terragrunt Run Command](https://terragrunt.gruntwork.io/docs/reference/cli/commands/run/) - CLI reference for run flags
- [Run Queue](https://terragrunt.gruntwork.io/docs/features/run-queue/) - Queue flags and filtering

### CI/CD Basics
- [Terragrunt Performance Guide](performance.md)
- [GitLab CI/CD Documentation](https://docs.gitlab.com/ee/ci/)
- [GitHub Actions Documentation](https://docs.github.com/en/actions)

### GitLab OIDC Authentication (Official)
- [GitLab CI/CD with AWS](https://docs.gitlab.com/ci/cloud_services/aws/) - Official GitLab documentation for AWS OIDC integration
- [Configure OIDC in AWS (GitLab Guided Exploration)](https://gitlab.com/guided-explorations/aws/configure-openid-connect-in-aws) - Step-by-step AWS IAM Identity Provider setup
- [Configure OIDC in GCP (GitLab Guided Exploration)](https://gitlab.com/guided-explorations/gcp/configure-openid-connect-in-gcp) - Step-by-step GCP Workload Identity Federation setup

### GitHub Actions OIDC Authentication
- [AWS OIDC for GitHub Actions](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services)
- [GCP Workload Identity Federation](https://cloud.google.com/iam/docs/workload-identity-federation)
- [google-github-actions/auth](https://github.com/google-github-actions/auth) - Official GitHub Action for GCP authentication
