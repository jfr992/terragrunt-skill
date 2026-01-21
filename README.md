# Terragrunt Skill for Claude Code

A Claude Code skill providing best practices guidance for Terragrunt infrastructure-as-code with OpenTofu/Terraform.

## Architecture

> **Important:** Catalog and Live repositories should be **separate Git repositories**. The live repo consumes units and stacks from the catalog via Git URLs.

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

### Claude Code Marketplace
```bash
/install jfr992/terragrunt-skill
```

> **Note:** Auto-discovery on claudemarketplaces.com requires 5+ GitHub stars. Before that threshold, use manual installation or share the direct repository link.

### Manual Installation
Clone to your Claude Code skills directory:
```bash
git clone https://github.com/jfr992/terragrunt-skill.git ~/.claude/skills/terragrunt-skill
```

### Local Testing
To test the skill in a specific project, add it to your project's Claude Code settings:

```bash
# Create .claude/settings.json in your project root
mkdir -p .claude
cat > .claude/settings.json << 'EOF'
{
  "skills": ["~/.claude/skills/terragrunt-skill"]
}
EOF
```

Or add the skill path to your global Claude Code configuration.

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

# Target specific unit
terragrunt stack run apply --queue-include-dir ".terragrunt-stack/dynamodb"
```

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
| `SKILL.md` | Core skill documentation |
| `test-output/` | Example output generated by this skill |
| `references/cicd-pipelines.md` | GitLab CI & GitHub Actions templates |
| `references/patterns.md` | Repository separation, pre-commit, semantic-release |
| `references/performance.md` | Caching, benchmarking, optimization |
| `references/state-management.md` | S3/DynamoDB backend patterns |
| `references/multi-account.md` | Cross-account deployment patterns |

## Compatibility

- Terragrunt 0.68+
- OpenTofu 1.6+ / Terraform 1.5+
- AWS, GCP (authentication patterns)

## Contributing

See [CLAUDE.md](CLAUDE.md) for contributor guidelines and repository architecture.

## References

- [Terragrunt Documentation](https://terragrunt.gruntwork.io/docs/)
- [Terragrunt Stacks](https://terragrunt.gruntwork.io/docs/rfc/stacks/)
- [Terragrunt Cache Benchmark](https://github.com/jfr992/terragrunt-cache-test)
- [OpenTofu Documentation](https://opentofu.org/docs/)

## License

Apache 2.0
