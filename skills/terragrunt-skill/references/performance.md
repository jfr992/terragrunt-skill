# Performance Optimization Guide

## Contents
- Overview
- Easy Wins
- Provider Caching (OpenTofu >= 1.10: automatic)
- Content Addressable Store (CAS) — on by default (1.1+)
- Provider Cache Server (Terraform / tofu < 1.10 / shared CI cache)
- Dependency Outputs from State (default since 1.2)
- Advanced: Two-Layer Provider Caching
- Explicit vs Implicit Stacks
- Older Versions (0.68 – 0.86)
- Measuring Performance
- CI/CD Optimization
- Parallelism Tuning
- References

## Overview

Terragrunt operations can be significantly accelerated through proper caching and configuration. With provider caching enabled, you can achieve:

- On TG >= 0.89 with OpenTofu >= 1.10, provider caching is automatic; measure before adding anything else.
- Earlier headline numbers (1.73x cold / 2.07x warm) came from a 0.86 setup and were not reproduced by the re-run below; don't quote them.

## Easy Wins

## Provider Caching (OpenTofu >= 1.10: automatic)

With OpenTofu >= 1.10, Terragrunt **automatically** sets `TF_PLUGIN_CACHE_DIR` per run — no flags needed. On by default since **0.89.0** (0.82.3–0.88 need `--experiment auto-provider-cache-dir` / `TG_EXPERIMENT=auto-provider-cache-dir`; 0.68 has no equivalent — use the cache server, see [Older Versions](#older-versions-068--086)).

```bash
# Override the cache location if needed
TG_PROVIDER_CACHE_DIR=/path/to/cache terragrunt run --all -- plan

# Opt out
terragrunt run --all --no-auto-provider-cache-dir -- apply
```

The provider cache **server** (`--provider-cache`, below) is now mainly useful for Terraform, OpenTofu < 1.10, or multi-runner CI fleets sharing one cache.

## Content Addressable Store (CAS) — on by default (1.1+)

GA since Terragrunt 1.1 and enabled by default — no flags needed. Deduplicates source downloads (Git, HTTP, S3, GCS, Mercurial, SMB, registry) by content hash: faster clones, less disk, biggest win on repos where many units share module sources. Opt out with `--no-cas`.

See [cas.md](cas.md) for how it works, `update_source_with_cas` for self-contained catalog stacks, and pitfalls.

## Provider Cache Server (Terraform / tofu < 1.10 / shared CI cache)

For Terraform, or OpenTofu < 1.10, Terragrunt's built-in provider cache server provides effective optimization:

```bash
terragrunt run --all --provider-cache -- plan
```

Benefits:
- Significantly reduces time for batch operations
- Most effective with `--all` and `--graph` flags
- No additional infrastructure required

**Note:** Can add overhead for single operations. Measure before/after for your use case.

## Dependency Outputs from State (default since 1.2)

Terragrunt reads dependency outputs directly from remote state instead of running `tofu output` (no dependency init).
- Direct reads: **S3, GCS, Azure Storage (azurerm)**. Other backends fall back to `tofu/terraform output`.
- OpenTofu client-side state encryption: direct read can't decrypt → automatic fallback to `tofu output`, which needs a binary/config able to decrypt the state (speedup lost).
- Missing state object (dependency not applied yet) → the unit's `mock_outputs` are used only when mocks are allowed for the command; otherwise the dependency fails with an error naming the unit.
- Opt out: `terragrunt run --all --no-dependency-fetch-output-from-state -- plan` (env `TG_NO_DEPENDENCY_FETCH_OUTPUT_FROM_STATE`).
- Skip outputs entirely for init/validate: `--no-dependency-outputs`.
- Field report (anecdotal, one repo): warm `run --all -- plan` ~36s → ~23s.

Ref: https://docs.terragrunt.com/reference/experiments/completed/#dependency-fetch-output-from-state

## Advanced: Two-Layer Provider Caching

> **Benchmark caveat:** in the re-run below, cache server + mirror together was flaky (0.68) and slow (1.2.1). Use the mirror only when the public registry is unreachable or slow.

Two-layer caching architecture:

### Layer 1: Terragrunt Provider Cache Server

Local filesystem-based caching for instant access on cache hits:

```bash
export TG_PROVIDER_CACHE=1
export TG_PROVIDER_CACHE_DIR=/path/to/cached/providers
export TG_DOWNLOAD_DIR=/path/to/cached/modules
```

### Layer 2: Network Mirror (boring-registry + MinIO)

Network mirror as fallback when Layer 1 misses:

```hcl
# .tofurc or .terraformrc
provider_installation {
  network_mirror {
    url = "https://<your-boring-registry>:5601/v1/mirror/"
  }
}
```

**Note:** The trailing slash in the mirror URL is required per the protocol specification.

### Combined Configuration

```bash
# Environment variables
export TG_PROVIDER_CACHE=1
export TG_PROVIDER_CACHE_DIR=/path/to/cached/providers
export TG_DOWNLOAD_DIR=/path/to/cached/modules
export TF_CLI_CONFIG_FILE=/root/.tofurc

# Run with all optimizations
terragrunt run --all \
  --provider-cache \
  --parallelism 8 \
  -- plan --parallelism=20 -no-color
```

## Explicit vs Implicit Stacks

Earlier figures in this file (implicit 119.7s vs explicit 69.3s cold) came from [jfr992/terragrunt-cache-test](https://github.com/jfr992/terragrunt-cache-test) on 0.86. Re-benchmarking that repo (below) shows the gap is **not** caused by stacks changing provider downloads: its explicit catalog units have no `dependency` blocks, while the implicit units depend on `eks`. With dependencies removed from the implicit fixture, implicit matches or beats explicit (1.2.1 fresh-checkout 3.3s implicit-no-deps vs 15.8s explicit; warm 2.1s vs 2.7s). The win comes from fewer dependency resolutions/parses and more parallelism — consistent with the Gruntwork maintainer's hypothesis. Choose explicit stacks for structure and reuse, not for speed; for speed, keep the dependency graph shallow.

## Older Versions (0.68 – 0.86)

Env names differ by version (from `--help` of each binary):

| Setting | 0.68 – 0.7x | 0.78+ / 1.x |
|---|---|---|
| Provider cache server | `TERRAGRUNT_PROVIDER_CACHE=1` | `TG_PROVIDER_CACHE=1` |
| Cache dir | `TERRAGRUNT_PROVIDER_CACHE_DIR` | `TG_PROVIDER_CACHE_DIR` |
| Module download dir | `TERRAGRUNT_DOWNLOAD` (**not** `_DOWNLOAD_DIR`) | `TG_DOWNLOAD_DIR` |

`TG_*` names are **ignored** by 0.68 (benchmarked: same time as no cache). Recipe for 0.68:

```bash
export TERRAGRUNT_PROVIDER_CACHE=1
export TERRAGRUNT_PROVIDER_CACHE_DIR=$CI_CACHE/providers   # persist between CI jobs
export TERRAGRUNT_DOWNLOAD=$CI_CACHE/modules
terragrunt run-all plan --terragrunt-non-interactive
# Commit .terraform.lock.hcl per unit so fresh checkouts hit the cache
```

On 0.82.3–0.88 use the `TG_*` names, or `TG_EXPERIMENT=auto-provider-cache-dir` (OpenTofu >= 1.10). On 0.89+ do nothing — auto provider cache dir is default. A network mirror (boring-registry) only replaces the upstream registry; it does not avoid per-unit provider installs, so it helps only on a slow/blocked internet link.

### Benchmark: terragrunt-cache-test re-run (this PR, 2026-10-24)

> **Caveats:** 2–3 runs on 3 units; differences under ~2 s are noise. TG < 1.0.4 ignores `XDG_CACHE_HOME` and keeps its global cache in `~/.cache/terragrunt`, which these "cold" runs did not wipe, so 0.86/0.89 cold numbers may be partly warm. Prefer the controlled synthetic results below (30/100 units) (rigorous-bench: hyperfine, 3 warm-ups + 10 runs, offline mirror).

Environment: Linux x86_64 box, OpenTofu 1.10.6, 3 units (`aws`, `kubernetes`, `tls`, `null`, `helm`, `kubectl` providers, ~870 MB), local state, boring-registry pull-through on MinIO (chainguard image) on localhost. Median seconds of 3 runs (0.68–0.86 rows) or 2 runs (rest). **cold** = all caches wiped; **checkout** = fresh `.terragrunt-cache` and lock files committed, provider cache kept (typical CI with a persisted cache); **warm** = re-run in place.

| TG | Layout | Config | cold | checkout | warm |
|---|---|---|---|---|---|
| 0.68.0 | implicit | nothing | 17.8 | 25.3 | 4.7 |
| 0.68.0 | implicit | `TERRAGRUNT_*` cache server | 15.0 | **12.4** | 4.9 |
| 0.68.0 | implicit | `TG_*` names (ignored) | 17.2 | 16.6 | 4.4 |
| 0.68.0 | implicit | mirror | 16.0 | 21.0 | 4.6 |
| 0.68.0 | implicit | mirror + cache server | 5.9† | fail | fail |
| 0.86.0 | implicit | nothing | 18.7 | 26.9 | 5.8 |
| 0.86.0 | implicit | `TG_*` cache server | 13.6 | 9.7 | 4.7 |
| 0.86.0 | implicit | auto-provider-cache-dir experiment | 20.8 | **7.7** | 4.6 |
| 0.86.0 | explicit | nothing | 14.3 | 10.0 | 2.7 |
| 0.89.0 | implicit | default (auto dir) | 21.0 | **6.8** | 4.6 |
| 0.89.0 | implicit | `TG_*` cache server | 13.0 | 9.6 | 5.7 |
| 0.89.0 | explicit | default (auto dir) | 13.6 | 14.8 | 2.2 |
| 1.2.1 | implicit | default (auto dir + CAS) | 14.4 | **6.8** | 4.5 |
| 1.2.1 | implicit | `--no-auto-provider-cache-dir` | 17.1 | 23.6 | 4.7 |
| 1.2.1 | implicit | `TG_*` cache server | 13.8 | 7.8 | 4.2 |
| 1.2.1 | implicit | cache server + mirror | 13.1 | 175.5‡ | 4.7 |
| 1.2.1 | implicit, no deps | default | 15.0 | **3.3** | 2.1 |
| 1.2.1 | implicit, no deps | `TG_*` cache server | 7.8 | 3.8 | 2.2 |
| 1.2.1 | explicit | default | 17.9 | 15.8 | 2.7 |
| 1.2.1 | explicit | `TG_*` cache server | 8.7 | 4.5 | 3.4 |
| 1.2.1 | git sources | CAS on (default) | 20.6 | 6.6 | 4.6 |
| 1.2.1 | git sources | `--no-cas` | 21.2 | 6.1 | 4.5 |

† failed after the first cold run: lock-file checksum mismatch between mirror and cache server. ‡ 46s and 305s — mirror stalls under concurrent pulls.

Takeaways:
- **Fresh checkout with a persisted cache is what matters in CI.** 0.68: cache server cuts 25s → 12s. 0.89+/1.2: auto provider cache dir is already best (≈7s), the legacy cache server adds nothing on fresh checkouts and only helps fully cold runs (~14s vs ~20s, since it de-duplicates downloads across units).
- **Warm runs (~4.5s implicit, ~2.5s explicit/no-deps) are parse + dependency + plan time**, independent of caching. The implicit/explicit gap there is dependency resolution, not providers.
- **CAS made no measurable difference** here (3 small local-git modules); expect it to matter with many units sharing large remote repos.
- **Don't combine the cache server with a network mirror**: it was flaky (checksum mismatches) on 0.68 and very slow on 1.2.1. Pick one; prefer the plugin cache dir/cache server, use a mirror only for air-gapped networks.
- Intermittent "does not match any of the checksums recorded in the dependency lock file" on warm runs appeared with every shared-cache mode (5 of ~60 runs), consistent with concurrent units sharing one cache. If you see it, rerun or lower `--parallelism`.
- 0.86 → 0.89 GA'd the auto provider cache dir; no other large difference measured for this fixture.


### Synthetic overhead and cache benchmark (rigorous-bench, 2026-10-24)

`null_resource` units in a fan-out dependency tree, OpenTofu 1.10.6, offline mirror, hyperfine `-w 3 -r 10`, mean ± stddev in seconds. The `tofu-only` baseline ignores the DAG, so it is a lower bound.

| Warm `run --all plan` | 30 units | 100 units |
|---|---|---|
| tofu-only | 0.69 ± 0.05 | 2.38 ± 0.37 |
| 0.68 implicit | 1.99 ± 0.17 | 3.90 ± 0.22 |
| 1.2.1 implicit | 1.28 ± 0.12 | 2.88 ± 0.16 |
| 1.2.1 explicit | 1.06 ± 0.10 | 3.58 ± 0.25 |

| Cold `run --all init`, 30 units | offline mirror | registry |
|---|---|---|
| tofu-only | 5.17 ± 0.78 | 11.59 ± 0.69 |
| 1.2.1 default (auto cache + CAS) | 0.89 ± 0.17 | 3.19 ± 0.97 |
| 1.2.1 `--no-auto-provider-cache-dir` | 4.03 ± 0.33 | 10.42 ± 0.25 |
| 1.2.1 cache server | n/a | 2.15 ± 0.47 |

Takeaways: 1.x has lower per-unit overhead than 0.68, and the auto provider cache dir accounts for most of the cold-init win. Explicit and implicit layouts are within noise of each other.

## Measuring Performance

### Recommended Benchmarking Tools

| Tool | Purpose |
|------|---------|
| [Hyperfine](https://github.com/sharkdp/hyperfine) | Statistical CLI benchmarking with warmup runs |
| [Make](https://www.gnu.org/software/make/) | Orchestrate benchmark workflows |
| [Docker](https://www.docker.com/) | Isolated, reproducible test environments |
| [boring-registry](https://github.com/boring-registry/boring-registry) | Local provider mirror for network layer testing |
| Python + matplotlib | Generate performance graphs and reports |

### Benchmarking with Hyperfine

```bash
# Compare configurations
hyperfine -w 3 -r 5 \
  'terragrunt run --all -- plan' \
  'terragrunt run --all --provider-cache -- plan'

# Compare state-read outputs (default) vs legacy `output` fetching
hyperfine -w 3 -r 5 \
  'terragrunt run --all --no-dependency-fetch-output-from-state -- plan' \
  'terragrunt run --all -- plan'
```

### Cold vs Warm Cache Testing

```bash
# Clear caches for cold-start testing. Also clear the global cache used by the
# auto provider cache dir and CAS: ${XDG_CACHE_HOME:-~/.cache}/terragrunt/{providers,cas}
# (TG >= 1.0.4 honors XDG_CACHE_HOME; older versions always use ~/.cache/terragrunt).
# Easiest: point XDG_CACHE_HOME at a scratch dir per benchmark and delete it in hyperfine --prepare.
: "${TG_PROVIDER_CACHE_DIR:?}" "${TG_DOWNLOAD_DIR:?}"; rm -rf -- "${TG_PROVIDER_CACHE_DIR:?}"/* "${TG_DOWNLOAD_DIR:?}"/*
find . -name .terragrunt-cache -prune -exec rm -rf {} +

# Run and measure
time terragrunt run --all --provider-cache -- plan
```

### Reproducible Benchmarking Environment

For consistent benchmarking, use Docker to create isolated test environments:

```bash
# Example structure
benchmarks/
├── Makefile              # Orchestration (make bench-cold, make bench-warm)
├── docker-compose.yml    # Services (boring-registry, minio)
├── Dockerfile            # Test environment
├── .tofurc               # Provider mirror config
└── scripts/
    └── generate-report.py  # Graph generation
```

Run benchmarks with:
```bash
make up              # Start services (registry, cache)
make bench-cold      # Run cold cache benchmarks (3 iterations)
make bench-warm      # Run warm cache benchmarks (3 iterations)
make bench-graphs    # Generate PNG graphs and markdown reports
```

## CI/CD Optimization

### GitHub Actions Example

```yaml
jobs:
  plan:
    runs-on: ubuntu-latest
    env:
      # TG >= 0.89 + OpenTofu >= 1.10: drop TG_PROVIDER_CACHE/--provider-cache; the auto
      # provider cache dir already uses TG_PROVIDER_CACHE_DIR. Keep the server for Terraform.
      TG_PROVIDER_CACHE: "1"
      TG_PROVIDER_CACHE_DIR: /tmp/provider-cache
      TG_DOWNLOAD_DIR: /tmp/module-cache
    steps:
      - uses: actions/cache@v4
        with:
          path: |
            /tmp/provider-cache
            /tmp/module-cache
          key: terragrunt-cache-${{ hashFiles('**/.terraform.lock.hcl') }}
          restore-keys: |
            terragrunt-cache-

      - name: Plan
        run: terragrunt run --all --provider-cache -- plan
```

### GitLab CI Example

```yaml
.terragrunt-cache:
  variables:
    # TG >= 0.89 + OpenTofu >= 1.10: drop TG_PROVIDER_CACHE/--provider-cache (see above).
    TG_PROVIDER_CACHE: "1"
    TG_PROVIDER_CACHE_DIR: /cache/providers
    TG_DOWNLOAD_DIR: /cache/modules
  cache:
    key: terragrunt-$CI_COMMIT_REF_SLUG
    paths:
      - /cache/providers
      - /cache/modules

plan:
  extends: .terragrunt-cache
  script:
    - terragrunt run --all --provider-cache -- plan
```

## Parallelism Tuning

Two levels of parallelism can be configured:

```bash
terragrunt run --all \
  --parallelism 8 \           # Terragrunt: max concurrent units
  -- plan --parallelism=20    # OpenTofu: max concurrent operations per unit
```

Recommendations:
- **Terragrunt parallelism:** Start with CPU cores, adjust based on memory
- **OpenTofu parallelism:** Default is 10, increase for API-heavy providers

## References

- [Terragrunt Performance Troubleshooting](https://docs.terragrunt.com/troubleshooting/performance/)
- [Explicit Terragrunt Stacks: 2x Faster Runs Using Provider Cache](https://www.linkedin.com/pulse/explicit-terragrunt-stacks-2x-faster-runs-using-provider-juan-reyes-ucsre/)
- [Terragrunt Cache Benchmark Test Suite](https://github.com/jfr992/terragrunt-cache-test) - Reproducible benchmarking environment with Docker, boring-registry, and automated reporting
