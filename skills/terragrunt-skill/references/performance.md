# Performance Optimization Guide

## Overview

Terragrunt operations can be significantly accelerated through proper caching and configuration. With provider caching enabled, you can achieve:

- **Cold cache:** 42% faster (1.73x speedup)
- **Warm cache:** 51% faster (2.07x speedup)

For a 10-person team running 35 Terragrunt operations daily, this translates to approximately 35 hours saved monthly.

## Easy Wins

### Provider Cache Server

The simplest optimization is using Terragrunt's built-in provider cache server:

```bash
terragrunt run --all plan --provider-cache
```

Benefits:
- Significantly reduces time for batch operations
- Most effective with `--all` and `--graph` flags
- No additional infrastructure required

**Note:** Can add overhead for single operations. Measure before/after for your use case.

### Automatic Provider Caching (OpenTofu >= 1.10)

With OpenTofu 1.10+ and latest Terragrunt, provider caching is automatic via `TF_PLUGIN_CACHE_DIR`. No manual configuration needed.

> **Note:** OpenTofu's auto provider cache is generally more performant at lower scales compared to Terraform. For larger operations, the explicit `--provider-cache` flag with Terragrunt's cache server provides better results.

**Limitation:** Filesystem lock contention can occur with many concurrent operations.

### Dependency Output Fetching (Experimental)

Bypass `tofu output -json` by reading S3 state directly:

```bash
terragrunt run --all plan --experiment=dependency-fetch-output-from-state
```

Constraints:
- Only works with S3 backends
- State file schema compatibility not guaranteed across versions
- Experimental feature

## Advanced: Two-Layer Provider Caching

For maximum performance, implement a two-layer caching architecture:

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
terragrunt run --all plan \
  --provider-cache \
  --parallelism 8 \
  -- --parallelism=20 -no-color
```

## Explicit vs Implicit Stacks

Explicit stacks (using `terragrunt.stack.hcl`) provide better performance than implicit dependency resolution:

| Scenario | Implicit | Explicit | Speedup |
|----------|----------|----------|---------|
| Cold cache | 119.7s | 69.3s | 1.73x |
| Warm cache | 35.4s | 17.2s | 2.07x |

This skill uses explicit stacks by default.

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
  'terragrunt run --all plan' \
  'terragrunt run --all plan --provider-cache'

# Compare with experimental features
hyperfine -w 3 -r 5 \
  'terragrunt run --all plan' \
  'terragrunt run --all plan --experiment=dependency-fetch-output-from-state'
```

### Cold vs Warm Cache Testing

```bash
# Clear caches for cold-start testing
rm -rf $TG_PROVIDER_CACHE_DIR/* $TG_DOWNLOAD_DIR/*

# Run and measure
time terragrunt run --all plan --provider-cache
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
      TG_PROVIDER_CACHE: "1"
      TG_PROVIDER_CACHE_DIR: /tmp/provider-cache
      TG_DOWNLOAD_DIR: /tmp/module-cache
    steps:
      - uses: actions/cache@v4
        with:
          path: |
            /tmp/provider-cache
            /tmp/module-cache
          key: terragrunt-cache-${{ hashFiles('**/*.hcl') }}
          restore-keys: |
            terragrunt-cache-

      - name: Plan
        run: terragrunt run --all plan --provider-cache
```

### GitLab CI Example

```yaml
.terragrunt-cache:
  variables:
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
    - terragrunt run --all plan --provider-cache
```

## Parallelism Tuning

Two levels of parallelism can be configured:

```bash
terragrunt run --all plan \
  --parallelism 8 \           # Terragrunt: max concurrent units
  -- --parallelism=20         # OpenTofu: max concurrent operations per unit
```

Recommendations:
- **Terragrunt parallelism:** Start with CPU cores, adjust based on memory
- **OpenTofu parallelism:** Default is 10, increase for API-heavy providers

## References

- [Terragrunt Performance Troubleshooting](https://terragrunt.gruntwork.io/docs/troubleshooting/performance/)
- [Explicit Terragrunt Stacks: 2x Faster Runs Using Provider Cache](https://www.linkedin.com/pulse/explicit-terragrunt-stacks-2x-faster-runs-using-provider-juan-reyes-ucsre/)
- [Terragrunt Cache Benchmark Test Suite](https://github.com/jfr992/terragrunt-cache-test) - Reproducible benchmarking environment with Docker, boring-registry, and automated reporting
