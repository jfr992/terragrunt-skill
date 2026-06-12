# Modules Monorepo Pattern

Module organization is orthogonal to the live-repo architecture: either pattern (explicit stacks or classic) can source modules from a monorepo or from per-module repos.

## Decision: monorepo vs per-repo

| | Modules monorepo | Module per repo (current skill default) |
|---|---|---|
| Versioning | One tag versions the whole repo | Independent tags per module |
| Sourcing | `//modules/<name>?ref=` subpath | repo root or `//<submodule>?ref=` |
| CI | One pipeline, path-filtered | One pipeline per repo |
| Discoverability | Everything in one place; works well with `terragrunt catalog` | Spread across repos |
| Blast radius of a tag | A tag implies all modules at that commit; consumers pin per-unit so impact is opt-in | Tag scoped to one module |
| Best for | Small/medium teams, cohesive platform modules | Independent teams, different release cadences |

**Recommendation:** start with a monorepo; split a module into its own repo only when its release cadence or ownership genuinely diverges.

## Layout (modeled on gruntwork-io/terragrunt-infrastructure-modules-example)

```
infrastructure-modules/
├── modules/
│   ├── mysql/
│   │   ├── README.md
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   └── asg-alb-service/
│       ├── README.md
│       ├── main.tf
│       ├── variables.tf
│       ├── outputs.tf
│       └── user-data.sh
└── examples/                 # Runnable example per module — doubles as docs and test fixture
    ├── mysql/
    └── asg-alb-service/
```

## Sourcing from units

```hcl
terraform {
  source = "git::git@github.com:YOUR_ORG/infrastructure-modules.git//modules/mysql?ref=v0.8.0"
}
```

With the values pattern (explicit stacks), the version comes from the stack:

```hcl
terraform {
  source = "git::git@github.com:YOUR_ORG/infrastructure-modules.git//modules/mysql?ref=${values.version}"
}
```

## Versioning and promotion

- Tag the monorepo with semver (`v0.8.0`). A tag is a snapshot of all modules.
- Promote one environment at a time by bumping `?ref=` (classic) or `values.version` (stacks): qa → stage → prod.
- Breaking change to one module → major-bump the repo tag; unaffected consumers upgrade on their own schedule since every unit pins its own ref.

## Catalog integration

Point `catalog` at the monorepo so `terragrunt catalog` can browse and scaffold from it:

```hcl
# root.hcl
catalog {
  urls = [
    "https://github.com/YOUR_ORG/infrastructure-modules",
  ]
}
```

## When to split a module out

- Its release cadence diverges (e.g., weekly networking changes vs frozen database module)
- Different team owns it and needs separate review/CODEOWNERS
- It's consumed by other orgs/repos that shouldn't see the rest
