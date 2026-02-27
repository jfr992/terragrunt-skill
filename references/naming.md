# Naming Conventions

## Repository Names

### Catalog Repositories

| Pattern | Example | Use Case |
|---------|---------|----------|
| `infrastructure-<org>-catalog` | `infrastructure-acme-catalog` | Single cloud or multi-cloud catalog |
| `infrastructure-<cloud>-<org>-catalog` | `infrastructure-aws-acme-catalog` | Cloud-specific catalogs |

### Live Repositories

| Pattern | Example | Use Case |
|---------|---------|----------|
| `infrastructure-<org>-live` | `infrastructure-acme-live` | Single live repo |
| `infrastructure-<cloud>-<org>-live` | `infrastructure-aws-acme-live` | Cloud-specific live repos |

### Module Repositories

| Pattern | Example |
|---------|---------|
| `terraform-<provider>-<name>` | `terraform-aws-rds`, `terraform-gcp-gke` |
| `modules-<org>-<name>` | `modules-acme-networking` |

## Directory and Resource Names

| Type | Convention | Examples |
|------|------------|----------|
| **Units** | lowercase, hyphen-separated | `eks-config`, `argocd-registration` |
| **Stacks** | lowercase, hyphen-separated, descriptive | `serverless-api`, `eks-cluster` |
| **Environments** | lowercase | `staging`, `production`, `dev` |
| **Accounts** | lowercase with org prefix | `acme-prod`, `acme-nonprod` |

## State Bucket Naming

State bucket names follow the pattern:

```
tfstate-{account_name}-{suffix}-{region}
```

| With suffix | Without suffix |
|-------------|----------------|
| `tfstate-myproject-nonprod-staging-us-east-1` | `tfstate-myproject-nonprod-us-east-1` |

The suffix comes from `env.hcl`:

```hcl
locals {
  environment         = "staging"
  state_bucket_suffix = local.environment
}
```
