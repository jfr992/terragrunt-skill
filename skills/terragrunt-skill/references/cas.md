# Content Addressable Store (CAS)

The CAS stores fetched source code addressed by content hash, so the same content is downloaded and stored once no matter how many units reference it. Generally available and **enabled by default** since Terragrunt 1.1 — faster clones and less disk usage with no configuration.

## Contents
- Overview
- How It Works
- Self-Contained Catalog Stacks (`update_source_with_cas`)
- Mutable Materialization
- Flags and Cache Location
- Pitfalls
- References

## Overview

CAS deduplicates fetched sources across all Terragrunt operations — catalog cloning, OpenTofu/Terraform source fetching, and stack generation. It is not limited to Git: HTTP/HTTPS, Amazon S3, Google Cloud Storage, Mercurial, SMB, registry sources (`tfr://`), and local paths are all deduplicated.

No setup required. Opt out per invocation with `--no-cas`.

## How It Works

1. **Probe:** cheap remote request (e.g., `git ls-remote`) derives a cache key without downloading
2. **Cache hit:** content is hard-linked into the target — no network, near-zero disk
3. **Cache miss:** content is fetched, hashed, and ingested as content-addressed blobs
4. **Dedup:** identical files occupy disk once; falls back to copying where hard links are unsupported

## Self-Contained Catalog Stacks (`update_source_with_cas`)

The recurring problem in layered catalogs: relative paths between units and stacks break once components are copied into the generated `.terragrunt-stack` tree. The workarounds — pinning every source to a remote URL, or plumbing versions through `values` at every layer — mean a single version bump rewrites files across the whole tree and CI plans hundreds of units when only a few changed.

Set `update_source_with_cas = true` on `unit`, `stack`, or `terraform` blocks and write relative paths naturally:

```hcl
# terragrunt.stack.hcl
unit "vpc" {
  source                 = "../..//units/vpc"
  path                   = "vpc"
  update_source_with_cas = true
}

stack "networking" {
  source                 = "../..//stacks/networking"
  path                   = "networking"
  update_source_with_cas = true
}
```

During `terragrunt stack generate`, relative sources are rewritten into content-addressed `cas::` references (e.g., `cas::sha1:abc123...`) that resolve from the local CAS — the generated tree no longer depends on the surrounding repository.

**Why this matters for versioning:**
- Unchanged units hash identically across catalog versions — a version bump only produces diffs where content actually changed
- One version pinned at the top-level stack controls the whole tree; no `values` interpolation plumbing
- Change-based CI (`--filter-affected`, `--filter 'reading=<path>'`) plans only the units that changed

Also works on `terraform` blocks inside units for catalog-internal module references:

```hcl
terraform {
  source                 = "../../..//modules/vpc"
  update_source_with_cas = true
}
```

## Mutable Materialization

CAS-materialized files are read-only hard links by design (shared content protection). To get an editable copy instead:

```hcl
terraform {
  source  = "git::git@github.com:YOUR_ORG/modules/vpc.git//.?ref=v1.0.0"
  mutable = true
}
```

Costs extra disk (copy instead of link). Only needed when something writes into the source tree.

## Flags and Cache Location

| Flag | Effect |
|------|--------|
| `--no-cas` | Disable CAS for `run`, `stack generate`, `stack run`, `catalog` |
| `--cas-clone-depth N` | Git clone depth (default 1; `-1` for full history) |

Cache lives at `~/Library/Caches/terragrunt/cas` (macOS), `~/.cache/terragrunt/cas` (Linux), `%LocalAppData%\terragrunt\cas` (Windows). Safe to delete when no Terragrunt process is running.

## Pitfalls

1. **`--no-cas` + `update_source_with_cas` is a hard error** — relative catalog sources cannot resolve without the CAS. Don't disable CAS in CI for repos that rely on it.
2. **Read-only materialized files** — scripts that write into fetched module directories need `mutable = true`.
3. **Shallow clones by default** — tooling that inspects Git history inside fetched sources needs `--cas-clone-depth -1`.

## References

- [CAS Documentation](https://docs.terragrunt.com/features/cas/)
- [Terragrunt 1.1 Release](https://github.com/gruntwork-io/terragrunt/releases/tag/v1.1.0)
- [Performance Guide](performance.md)
- [Unit Dependencies](dependencies.md)
