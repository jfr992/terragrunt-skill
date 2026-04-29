# Terragrunt Skill for Claude Code

A Claude Code skill providing best practices guidance for Terragrunt infrastructure-as-code with OpenTofu/Terraform.

## Architecture

> **Important:** Catalog and Live repositories should be **separate Git repositories**. The live repo consumes units and stacks from the catalog via Git URLs.

### Option A: Modules in Separate Repos

```
┌─────────────────────────────────────────────────────────────────────┐
│                        SEPARATE REPOSITORIES                         │
├─────────────────────────┬─────────────────────────┬─────────────────┤
│   Module Repos          │   Catalog Repo          │   Live Repo     │
│   (terraform-aws-*)     │   (infrastructure-      │   (infrastructure-
│                         │    <org>-catalog)       │    <org>-live)  │
├─────────────────────────┼─────────────────────────┼─────────────────┤
│ • OpenTofu modules      │ • units/ (wrappers)     │ • root.hcl      │
│ • Semantic versioning   │ • stacks/ (templates)   │ • account.hcl   │
│ • Terratest             │ • References modules    │ • Deployments   │
│ • Pre-commit hooks      │   via Git URLs          │ • Consumes      │
│                         │                         │   catalog       │
└─────────────────────────┴─────────────────────────┴─────────────────┘
         ▲                         ▲                        │
         │                         │                        │
         └─────────────────────────┴────────────────────────┘
                    Live repo references both via Git URLs
```

### Option B: Modules in Catalog

```
┌───────────────────────────────────────────────────────────────┐
│                    SEPARATE REPOSITORIES                       │
├─────────────────────────────────┬─────────────────────────────┤
│   Catalog Repo                  │   Live Repo                 │
│   (infrastructure-<org>-catalog)│   (infrastructure-<org>-live)
├─────────────────────────────────┼─────────────────────────────┤
│ • modules/ (OpenTofu modules)   │ • root.hcl                  │
│ • units/ (module wrappers)      │ • account.hcl               │
│ • stacks/ (unit compositions)   │ • Deployments               │
│ • Discovered via `tg catalog`   │ • Consumes catalog via Git  │
│ • Single versioning strategy    │ • `tg scaffold` for new     │
└─────────────────────────────────┴─────────────────────────────┘
                ▲                              │
                └──────────────────────────────┘
                  Live repo references catalog
```

**Trade-offs:**

| Aspect | Option A (Separate Module Repos) | Option B (Modules in Catalog) |
|--------|----------------------------------|-------------------------------|
| Versioning | Independent per module | Single catalog version |
| CI/CD | Dedicated pipeline per module | One pipeline for all |
| Complexity | More repos to manage | Simpler structure |
| Team ownership | Clear boundaries | Shared ownership |
| `terragrunt catalog` | Discovers units/stacks | Discovers modules too |

## Features

### Catalog & Live Pattern
- **Infrastructure Catalog**: Reusable units and template stacks (separate repo)
- **Infrastructure Live**: Environment-specific deployments consuming the catalog
- **Module Repos**: Separate repositories with semantic versioning

### Unit & Stack Patterns
- Values pattern for configuration injection
- Reference resolution (`"../unit"` → dependency outputs)
- Unit interdependencies with mock outputs
- Conditional dependencies with `enabled` and `skip_outputs`

### CI/CD Pipelines
- GitLab CI with reusable templates
- GitHub Actions workflows
- AWS OIDC authentication (`assume-role-with-web-identity`)
- GCP Workload Identity Federation
- SSH-based Git access (recommended over HTTPS)

### Performance Optimization
- Provider caching (`--provider-cache`)
- Two-layer caching architecture (local + network mirror)
- Benchmarking tools (Hyperfine, boring-registry)
- Explicit stacks for 2x faster runs

### Multi-Account Deployments
- Cross-account role assumption
- Environment-based state bucket separation
- Hierarchical configuration (root.hcl → account.hcl → region.hcl → env.hcl)

## Installation

This skill is distributed via Claude Code marketplace using `.claude-plugin/marketplace.json`.

### Claude Code (Recommended)

```bash
/plugin marketplace add jfr992/terragrunt-skill
/plugin install terragrunt-skill@jfr992
```

### Manual Installation

```bash
# Clone to Claude skills directory
git clone https://github.com/jfr992/terragrunt-skill.git ~/.claude/skills/terragrunt-skill
```

### Verify Installation

After installation, try:
```
"Create a Terragrunt stack for a serverless API with Lambda, DynamoDB, and S3"
```

Claude will automatically use the skill when working with Terragrunt code.

## Quick Start

### 1. Create a Catalog Repository

```bash
# Ask Claude to scaffold a new catalog
"Create a new infrastructure catalog with units for S3, DynamoDB, and Lambda"
```

This generates:
```
infrastructure-catalog/
├── units/
│   ├── s3/terragrunt.hcl           # Wraps terraform-aws-s3 module
│   ├── dynamodb/terragrunt.hcl     # Wraps terraform-aws-dynamodb module
│   └── lambda/terragrunt.hcl       # Wraps terraform-aws-lambda module
└── stacks/
    └── serverless-api/terragrunt.stack.hcl  # Combines units
```

### 2. Create a Live Repository

```bash
# Ask Claude to scaffold a live repo
"Create a live infrastructure repo for AWS with staging environment"
```

This generates:
```
infrastructure-live/
├── root.hcl                        # Provider, backend, catalog config
├── non-prod/
│   ├── account.hcl                 # AWS account config
│   └── us-east-1/
│       ├── region.hcl
│       └── staging/
│           ├── env.hcl             # Environment config
│           └── my-api/
│               └── terragrunt.stack.hcl  # Deployment (references catalog)
```

### 3. Deploy

```bash
cd infrastructure-live/non-prod/us-east-1/staging/my-api

# Plan the stack
terragrunt stack run plan

# Apply the stack
terragrunt stack run apply

# Target specific unit using filters (recommended)
terragrunt stack run apply --filter '.terragrunt-stack/dynamodb'

# Target unit and its dependencies
terragrunt stack run apply --filter '.terragrunt-stack/lambda...'
```

See [Terragrunt Filters](https://terragrunt.gruntwork.io/docs/features/filter/) for advanced filtering options.

## Usage

The skill activates when working with:
- `terragrunt.hcl` files (units)
- `terragrunt.stack.hcl` files (stacks)
- `root.hcl` configuration
- Terragrunt CLI commands

### Example Prompts
- "Create a new EKS stack with Karpenter and ArgoCD registration"
- "Set up a serverless API with Lambda, DynamoDB, and S3"
- "Add GitLab CI pipeline with GCP Workload Identity"
- "Optimize Terragrunt performance with provider caching"

## Test Output (Examples)

The `test-output/` directory contains example files generated using this skill, demonstrating the recommended patterns:

```
test-output/
├── catalog/                    # Example catalog repo structure
│   ├── units/
│   │   ├── s3/terragrunt.hcl
│   │   ├── dynamodb/terragrunt.hcl
│   │   └── lambda/terragrunt.hcl
│   └── stacks/
│       ├── serverless-api/terragrunt.stack.hcl
│       └── eks-cluster/terragrunt.stack.hcl
└── live/                       # Example live repo structure
    ├── root.hcl
    └── non-prod/
        ├── account.hcl
        └── us-east-1/
            ├── region.hcl
            └── staging/
                ├── env.hcl
                └── my-api/terragrunt.stack.hcl
```

> **Note:** In production, `catalog/` and `live/` would be **separate Git repositories**. They are combined here for demonstration purposes only.

## Documentation Structure

| File | Description |
|------|-------------|
| `skills/terragrunt-skill/SKILL.md` | Core skill documentation |
| `test-output/` | Example output generated by this skill |
| `skills/terragrunt-skill/references/cicd-pipelines.md` | GitLab CI & GitHub Actions templates |
| `skills/terragrunt-skill/references/patterns.md` | Repository separation, pre-commit, semantic-release |
| `skills/terragrunt-skill/references/performance.md` | Caching, benchmarking, optimization |
| `skills/terragrunt-skill/references/state-management.md` | S3/DynamoDB backend patterns |
| `skills/terragrunt-skill/references/multi-account.md` | Cross-account deployment patterns |

## Compatibility

- Terragrunt 0.68+
- OpenTofu 1.6+ / Terraform 1.5+
- AWS, GCP (authentication patterns)

## Contributing

See [CLAUDE.md](CLAUDE.md) for contributor guidelines and repository architecture.

## State Backend Bootstrap

Terragrunt can automatically create state backend resources (S3 bucket + DynamoDB table) when you run any command:

```hcl
# root.hcl
remote_state {
  backend = "s3"
  config = {
    bucket         = "tfstate-${local.account_name}-${local.aws_region}"
    key            = "${path_relative_to_include()}/terraform.tfstate"
    region         = local.aws_region
    encrypt        = true
    dynamodb_table = "tfstate-locks-${local.account_name}-${local.aws_region}"
  }
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
}
```

Terragrunt automatically provisions the S3 bucket (with versioning, encryption, access logging) and DynamoDB table (with encryption) if they don't exist.

See [State Backend](https://terragrunt.gruntwork.io/docs/features/state-backend/) for details.

> **Note:** The `skills/terragrunt-skill/scripts/setup-state-backend.sh` in this repo provides an alternative manual approach with more control over bucket configuration.

## Platform Engineering & Self-Service

### Catalog Discovery

The `terragrunt catalog` command enables self-service infrastructure by letting teams browse and scaffold from your catalog:

```bash
# Browse available modules, units, and stacks
terragrunt catalog

# Scaffold a specific unit
terragrunt scaffold git@github.com:YOUR_ORG/infrastructure-catalog.git//units/rds
```

### Boilerplate Templates

[Boilerplate](https://github.com/gruntwork-io/boilerplate) powers the scaffolding with interactive prompts:

```yaml
# units/rds/boilerplate.yml
variables:
  - name: instance_class
    description: "RDS instance class"
    type: string
    default: "db.t3.medium"

  - name: engine_version
    description: "Database engine version"
    type: string
    default: "15.4"
```

When users run `terragrunt scaffold`, they're prompted for these values, generating a pre-configured `terragrunt.hcl`.

### Self-Service Portal Integration

The scaffold command can be integrated with internal developer platforms:

```bash
# API endpoint calls scaffold with predefined values
terragrunt scaffold \
  git@github.com:YOUR_ORG/infrastructure-catalog.git//units/rds \
  --var instance_class=db.r5.large \
  --var engine_version=15.4 \
  --output-folder /deployments/team-a/rds
```

This enables:
- **Standardized deployments** across teams
- **Governance** via catalog-level policies
- **Reduced toil** through automated configuration
- **Version control** with automatic Git tag resolution

## References

- [Terragrunt Documentation](https://terragrunt.gruntwork.io/docs/)
- [Terragrunt Stacks](https://terragrunt.gruntwork.io/docs/features/stacks/)
- [Terragrunt Filters](https://terragrunt.gruntwork.io/docs/features/filter/)
- [Terragrunt State Backend](https://terragrunt.gruntwork.io/docs/features/state-backend/)
- [Boilerplate](https://github.com/gruntwork-io/boilerplate) - Template generation tool
- [Terragrunt Cache Benchmark](https://github.com/jfr992/terragrunt-cache-test)
- [OpenTofu Documentation](https://opentofu.org/docs/)

## License

Apache 2.0
