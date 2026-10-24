# Stack Commands

> **Requires TG >= 0.78** (explicit stacks GA). On older versions, use classic `run-all`. See [version-compatibility.md](version-compatibility.md).

## Contents
- Basic Operations
- Targeting Specific Units
- Filter Expressions
- Advanced Filtering
- Parallelism Control
- Visualize Dependencies
- Useful Flags
- The .terragrunt-stack Directory
- References

## Basic Operations

```bash
# Generate stack units (creates .terragrunt-stack/ directory)
terragrunt stack generate

# Plan all units
terragrunt stack run -- plan

# Apply all units
terragrunt stack run -- apply

# Destroy all units
terragrunt stack run -- destroy

# Get outputs from all units
terragrunt stack output

# Clean generated files
terragrunt stack clean
```

## Targeting Specific Units

Apply only specific units using `--filter` (see the legacy mapping table below for `--queue-include-dir`):

```bash
# Target a specific unit
terragrunt stack run --filter './.terragrunt-stack/argocd-registration' -- apply

# Target multiple specific units
terragrunt stack run --filter './.terragrunt-stack/rds' --filter './.terragrunt-stack/secrets' -- plan

# Target by pattern (all units starting with "db-")
terragrunt stack run --filter './.terragrunt-stack/db-*' -- plan

# Exclude specific units
terragrunt stack run --filter '!./.terragrunt-stack/expensive-resource' -- apply
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
terragrunt stack run --filter './.terragrunt-stack/api...' -- apply

# Target unit and its dependents (reverse)
terragrunt stack run --filter '.../.terragrunt-stack/vpc' -- apply

# Combine filters (intersection)
terragrunt stack run --filter './.terragrunt-stack/** | type=unit' -- plan

# Git-based: only changed units since main
terragrunt stack run --filter '[main...HEAD]' -- plan

# Use filters file
terragrunt stack run --filters-file my-filters.txt -- apply
```

## Terragrunt 1.2 Flags

```bash
# Bound discovery to the current directory (don't walk into parents/siblings)
terragrunt run --all --discovery-boundary . -- plan

# Dependency-graph operand: everything in . that is a dependency of vpc
terragrunt run --all --filter '(.)...{vpc}' -- plan

# Skip before/after/error hooks (e.g. in read-only CI plans)
terragrunt stack run --no-hooks -- plan

# Write per-run profiling data for performance analysis
terragrunt run --all --profile-dir ./tg-profile -- plan
```

Ref: https://docs.terragrunt.com/reference/experiments/completed/ , https://github.com/gruntwork-io/terragrunt/releases/tag/v1.2.0


## Parallelism Control

```bash
# Limit concurrent unit execution
terragrunt stack run --parallelism 3 -- apply

# Save plans to directory structure
terragrunt stack run --out-dir ./plans -- plan
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

- [Terragrunt Stacks Documentation](https://docs.terragrunt.com/features/stacks/)
- [Filter Expressions](https://docs.terragrunt.com/features/filter/)
- [CI/CD Pipelines](cicd-pipelines.md)
