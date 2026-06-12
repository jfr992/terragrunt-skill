# GitLab CI Pipelines for Terragrunt

## Contents
- Base Templates (`.gitlab-ci.yml`)
- AWS Authentication Pattern
- GCP Authentication Pattern
- Targeting Specific Units
- References

> **Best Practice: Reusable Templates**
>
> Structure GitLab CI with reusable templates (`.template-name`) that can be extended and overridden:
> - **Consistency**: All jobs follow the same patterns
> - **Maintainability**: Update logic in one place
> - **Flexibility**: Override specific steps when needed
>
> These templates are suggestions—adapt them to your organization's requirements.

## Base Templates (`.gitlab-ci.yml`)

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
    - terragrunt hcl fmt --check
    - terragrunt hcl validate
  rules:
    - if: '$CI_PIPELINE_SOURCE == "merge_request_event"'
    - if: '$CI_COMMIT_REF_NAME == $CI_DEFAULT_BRANCH'

# STACK PLAN TEMPLATE

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

## AWS Authentication Pattern

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

## GCP Authentication Pattern

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

## Targeting Specific Units

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

## References

### GitLab OIDC Authentication (Official)
- [GitLab CI/CD with AWS](https://docs.gitlab.com/ci/cloud_services/aws/) - Official GitLab documentation for AWS OIDC integration
- [Configure OIDC in AWS (GitLab Guided Exploration)](https://gitlab.com/guided-explorations/aws/configure-openid-connect-in-aws) - Step-by-step AWS IAM Identity Provider setup
- [Configure OIDC in GCP (GitLab Guided Exploration)](https://gitlab.com/guided-explorations/gcp/configure-openid-connect-in-gcp) - Step-by-step GCP Workload Identity Federation setup
- [GitLab CI/CD Documentation](https://docs.gitlab.com/ee/ci/)
