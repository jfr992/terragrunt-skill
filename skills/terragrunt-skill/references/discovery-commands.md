# Discovery Commands

> `find`/`list` require the TG >= 0.77.22 CLI. `--filter` **requires TG >= 0.97** (experiment since 0.91.2); read-based change filtering requires TG >= 1.1. See [version-compatibility.md](version-compatibility.md).

First commands to run when exploring an unfamiliar Terragrunt repo — before globbing for `terragrunt.hcl` files manually.

## terragrunt find

Recursively discovers units (`terragrunt.hcl`) and stacks (`terragrunt.stack.hcl`):

```bash
# All configurations under the current directory
terragrunt find

# JSON with dependency relationships — best input for programmatic analysis
terragrunt find --json --dependencies

# Sorted in dependency (DAG) order — dependencies first
terragrunt find --dag

# Sorted as a destroy would run (reverse dependency order)
terragrunt find --as=destroy

# Only components changed vs the default branch (great for CI)
terragrunt find --filter-affected

# Combine with filter expressions
terragrunt find --filter './prod/** | type=unit'
```

JSON output shape:

```json
{
  "type": "unit",
  "path": "qa/mysql",
  "dependencies": ["../vpc"]
}
```

## terragrunt list

Human-oriented listing with tree/long formats:

```bash
# Compact listing
terragrunt list

# Tree view of the hierarchy
terragrunt list --tree

# Long format with type and dependency info, DAG-ordered
terragrunt list --long --dag --dependencies
```

`find` is for machine consumption (JSON, exact ordering); `list` is for reading.

## Change-based filtering (Terragrunt 1.1+)

Units track reads on local module files (`*.tf`, `*.hcl`, ...), so filters can select units by what they read — not just by path or Git diff:

```bash
# Units that read a given file (e.g., a shared local module)
terragrunt find --filter 'reading=modules/vpc/main.tf'

# Plan only units affected by a changed local module
terragrunt run --all --filter 'reading=modules/vpc/main.tf' -- plan
```

Units that read files outside their directory (templates, shared data) can declare it so change detection sees them:

```hcl
locals {
  _tracked = mark_glob_as_read("../shared/*.yaml")
}
```

Run queues render as a dependency tree (1.1+) showing execution order — read it before an apply to confirm blast radius.

## terragrunt dag graph

Render the dependency graph (DOT format — pipe to graphviz):

```bash
terragrunt dag graph | dot -Tpng > dag.png
```

## terragrunt catalog (machine-readable)

`catalog` lists reusable modules/units/stacks from configured catalog sources. In non-TTY contexts (agents, CI) the default format is `jsonl`; `--format=md` gives a Markdown listing:

```bash
terragrunt catalog --format=jsonl | jq -c '{kind,title,component_source}'
```

Ref: https://docs.terragrunt.com/reference/experiments/completed/

## Typical exploration sequence

```bash
terragrunt list --tree              # shape of the repo
terragrunt find --json --dependencies > /tmp/units.json   # full graph
terragrunt find --filter-affected   # what does my branch touch?
```
