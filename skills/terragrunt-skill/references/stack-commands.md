# Stack Commands

## Basic Operations

```bash
# Generate stack units (creates .terragrunt-stack/ directory)
terragrunt stack generate

# Plan all units
terragrunt stack run plan

# Apply all units
terragrunt stack run apply

# Destroy all units
terragrunt stack run destroy

# Get outputs from all units
terragrunt stack output

# Clean generated files
terragrunt stack clean
```

## Targeting Specific Units

Apply only specific units using `--filter` (modern) or `--queue-include-dir` (legacy):

```bash
# Target a specific unit (modern filter syntax)
terragrunt stack run apply --filter '.terragrunt-stack/argocd-registration'

# Target a specific unit (legacy syntax)
terragrunt stack run apply --queue-include-dir ".terragrunt-stack/argocd-registration"

# Target multiple specific units
terragrunt stack run plan --filter '.terragrunt-stack/rds' --filter '.terragrunt-stack/secrets'

# Target by pattern (all units starting with "db-")
terragrunt stack run plan --filter '.terragrunt-stack/db-*'

# Exclude specific units
terragrunt stack run apply --filter '!.terragrunt-stack/expensive-resource'
```

## Filter Expressions

| Legacy Flag | Modern Filter | Description |
|-------------|---------------|-------------|
| `--queue-include-dir=./path` | `--filter='./path'` | Include only this path |
| `--queue-exclude-dir=./path` | `--filter='!./path'` | Exclude this path |
| `--queue-include-external` | `--filter='{./**}...'` | Include external dependencies |

## Advanced Filtering

```bash
# Target unit and its dependencies
terragrunt stack run apply --filter '.terragrunt-stack/api...'

# Target unit and its dependents (reverse)
terragrunt stack run apply --filter '.../.terragrunt-stack/vpc'

# Combine filters (intersection)
terragrunt stack run plan --filter '.terragrunt-stack/** | type=unit'

# Git-based: only changed units since main
terragrunt stack run plan --filter '[main...HEAD]'

# Use filters file
terragrunt stack run apply --filters-file my-filters.txt
```

## Parallelism Control

```bash
# Limit concurrent unit execution
terragrunt stack run apply --parallelism 3

# Save plans to directory structure
terragrunt stack run plan --out-dir ./plans
```

## Visualize Dependencies

```bash
# Generate DAG in DOT format
terragrunt dag graph

# List with dependencies
terragrunt list --format=dot --dependencies
```

## Useful Flags

| Flag | Description | Use Case |
|------|-------------|----------|
| `--filter` | Flexible unit targeting (recommended) | Target units, dependencies, patterns |
| `--queue-include-dir` | Target specific units by path (legacy) | Simple path-based targeting |
| `--queue-ignore-dag-order` | Run units concurrently | Faster plans (dangerous for apply) |
| `--queue-ignore-errors` | Continue on failures | Identify all errors at once |
| `--out-dir` | Save plan files to directory | Artifact storage for apply stage |
| `--parallelism N` | Limit concurrent units | Prevent rate limiting |

## The .terragrunt-stack Directory

The `.terragrunt-stack` directory is auto-generated when running stack commands:
- `terragrunt stack generate` - Pre-generate the directory
- `terragrunt stack clean` - Remove the generated directory
- The directory contains the resolved unit configurations

## References

- [Terragrunt Stacks Documentation](https://terragrunt.gruntwork.io/docs/features/stacks/)
- [Filter Expressions](https://terragrunt.gruntwork.io/docs/features/filter/)
- [CI/CD Pipelines](cicd-pipelines.md)
