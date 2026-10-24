# Expansion (`for_each` / `count`) and `enabled` (Terragrunt 1.2+)

> **Requires TG >= 1.2.** Older versions: see [version-compatibility.md](version-compatibility.md).

## Contents
- When to use
- Unit/stack expansion
- Dependency expansion
- Addressing expanded elements
- Autoinclude over expanded dependencies
- `enabled = false`
- State safety
- References

## When to use

Use an `expansion` block instead of copy-pasting near-identical `unit`, `stack`, or `dependency` blocks that differ only by a name or a value. GA in Terragrunt 1.2 (no experiment flag needed).

## Unit/stack expansion

```hcl
# terragrunt.stack.hcl
unit "app" {
  expansion {
    for_each = toset(["web", "api"])
  }
  enabled = each.key != "api"   # evaluated per element
  source  = "../units/app"
  path    = "app/${each.key}"
  values  = { role = each.key }
}
```

- `expansion` takes `for_each` (set/map → `each.key` / `each.value`) or `count` (→ `count.index`).
- Works the same on `stack` blocks.
- Keep `path` unique per element (include `each.key`).

## Dependency expansion

```hcl
dependency "aurora" {
  expansion {
    for_each = toset(["web", "api"])
  }
  config_path = "../aurora-${each.key}"
}

inputs = {
  web_id = dependency.aurora["web"].outputs.id
}
```

## Addressing expanded elements

- In the stack file / autoinclude: `unit.app["web"].path`.
- From the CLI: `terragrunt stack output 'app["web"].role'` (quote it for the shell).
- `count` elements: `shard[0]` is the same as `shard["0"]`.
- Expanded units work with autoinclude and with stack-level dependencies (a stack containing expanded units is waited on).

## Autoinclude over expanded dependencies

Iterate the whole expanded dependency as a map:

```hcl
inputs = {
  vpc_ids = { for k, v in dependency.vpc : k => v.outputs.vpc_id }
}
```

## `enabled = false`

`enabled` is evaluated per element (`each.key` usable). Setting it to `false` drops just that component; the addresses of the other elements are unchanged.

## State safety

- **Growing:** with `for_each`, stable keys, and an unchanged `path` template, adding a key only adds a new unit — existing elements keep their state.
- **`count` reindexes:** removing/reordering list items shifts `count.index`, so units change identity. Prefer `for_each` with stable keys.
- **Converting an existing unit to `expansion`**: the state key follows the generated `path` (with the usual `path_relative_to_include()` key). Going from `path = "app"` to `path = "app/${each.key}"` moves the state from `.terragrunt-stack/app/…` to `.terragrunt-stack/app/web/…`, so the new unit starts with empty state. Migrate the state first (copy or move the state object to the new key, or `tofu state pull`/`push`). If one element keeps the old `path`, its key stays the same (tested on Terragrunt 1.2.1 with an S3 backend).
- **Shrinking orphans units:** removing a key stops generating that unit but does not destroy its infrastructure.
  - Find and clean up orphans with Git filters, which may destroy removed units only with an explicit opt-in:
    ```bash
    terragrunt run --all --filter '[main...HEAD]' --filter-allow-destroy -- plan
    terragrunt run --all --filter '[main...HEAD]' --filter-allow-destroy -- apply
    ```
  - A plain `run --all --filter ... -- destroy` is rejected.
  - Removals driven by env vars or external values files are **not** detectable by Git filters → run `destroy` on the element manually **before** removing its key.

## References

- https://docs.terragrunt.com/reference/hcl/blocks#expansion
- https://docs.terragrunt.com/reference/experiments/completed/#block-iteration
- https://github.com/gruntwork-io/terragrunt/releases/tag/v1.2.0
