# Version Compatibility (Terragrunt 0.68 → 1.2, OpenTofu vs Terraform)

## Contents
- Detect the version first
- Eras at a glance
- Feature matrix (minimum versions)
- Old → new CLI mapping
- OpenTofu vs Terraform
- Classic (implicit) vs explicit stacks
- Verification notes

The rest of this skill targets **Terragrunt 1.2**. Use this page to adjust advice for older versions. Minimum versions come from the [Terragrunt release notes](https://github.com/gruntwork-io/terragrunt/releases). Anything marked *UNVERIFIED* is not confirmed by release notes or a local test.

## Detect the version first

```bash
terragrunt --version                         # actual binary
cat .terragrunt-version 2>/dev/null           # tgenv / tgswitch pin
grep -A3 -iE 'terragrunt|opentofu|terraform' mise.toml .mise.toml .tool-versions 2>/dev/null
grep -rn terragrunt_version_constraint --include='*.hcl' .   # in-repo constraint
grep -rn terraform_version_constraint  --include='*.hcl' .
command -v tofu && tofu version; command -v terraform && terraform version
```

If `tofu` and `terraform` are both present, Terragrunt prefers `tofu` unless `--tf-path` / `TG_TF_PATH` (or legacy `--terragrunt-tfpath`) says otherwise.

## Eras at a glance

| Era | Versions | What it looks like |
|-----|----------|--------------------|
| Implicit stacks only | **0.68 – 0.70** | Directories of `terragrunt.hcl` units, `run-all`, `--terragrunt-*` flags, `TERRAGRUNT_*` env vars, unknown commands forwarded to tofu/terraform. No `terragrunt.stack.hcl`. |
| Explicit stacks experiment | **0.71.3 – 0.77.x** | `terragrunt.stack.hcl` + `stack generate` behind `--experiment stacks` (first shipped in 0.71.3). |
| CLI redesign | **0.73.0** (experiment) → **0.77.22** (complete) | `run --all`, `TG_*` env vars and flags without the `terragrunt-` prefix (0.73.0 adds them with warnings), `backend bootstrap`, `hcl fmt`, `find`/`list`/`dag`. |
| Stacks GA, legacy deprecated | **0.78.0** | Stacks experiment complete (no flag needed); `run-all`, `hclfmt`, `graph-dependencies`, `render-json`, the default command, etc. deprecated. |
| Removals | **0.84.0**, **0.85.0** | 0.84.0 removes `plan-all`/`apply-all`/`*-all`/`spin-up`/`tear-down`. 0.85.0 removes all `--terragrunt-*` flags. |
| 1.0 | **1.0.0** (2026-03-30) | No breaking changes in minors from here on. `.terragrunt-cache` for every run; built-in tflint removed. `run-all` is gone (tested: `tg 1.0.0 run-all …` fails). `stack-dependencies` (`autoinclude`, `unit.<n>.path`) experiment since 1.0.1. |
| 1.1 | **1.1.0** (2026-07-01) | `stack-dependencies` (autoinclude) and `cas` experiments complete. |
| 1.2 | **1.2.0** (2026-10-21) | `expansion`/`enabled` (block-iteration), dependency outputs from state, `oci`, `version` attribute, azurerm backend, mutable-generate, bounded discovery and more complete. |

## Feature matrix (minimum versions)

| Feature | Min Terragrunt | Notes |
|---------|----------------|-------|
| Implicit stacks (`run-all` over a directory tree), `dependency` blocks, `include`/`expose` | ≤ 0.68 | Works on every version covered here; use `run --all` from 0.77.22. |
| `terragrunt.stack.hcl` / `stack generate` | 0.71.3 (experiment), **0.78.0** (GA) | Requires TG ≥ 0.78 without `--experiment stacks`. |
| `stack run`, `stack output` | 0.72.x (experiment) | *UNVERIFIED* exact first version; GA with stacks in 0.78.0. |
| `run --all`, `TG_*` vars, prefix-less flags | 0.73.0 (experiment) / **0.77.22** (GA) | `TERRAGRUNT_*` env vars still accepted in 1.2.1 (tested). |
| `backend bootstrap` command | **0.77.0** | Before it, the S3/GCS bucket was created automatically on `init`. |
| Automatic backend provisioning | ≤ 0.77 default; **0.78.0** opt-in (`--backend-bootstrap`); **removed 0.87.0** | From 0.87, Terragrunt exits with an error if the backend is missing. Run `backend bootstrap --all` first. |
| `remote_state.encryption` (OpenTofu state encryption) | **0.72.2** | OpenTofu-only (≥ 1.7). |
| CAS (`update_source_with_cas`, content-addressed store) | 0.75.5 (experiment), **1.1.0** (GA) | |
| Native `use_lockfile` in `remote_state` S3 | **0.82.4** | Earlier TG passes the key through: TG 0.68.0 + OpenTofu 1.10.6 planned fine with `use_lockfile = true` on Floci (tested). Needs a supporting IaC version (below). |
| `--filter` | 0.91.2 (experiment), **0.97.0** (GA) | |
| `autoinclude`, `unit.<n>.path` / `stack.<n>.path` in stack files | 1.0.1 (experiment), **1.1.0** (GA) | `unit.a.path` fails with `Unknown variable` on 0.78.1 and 1.0.0 (tested). |
| `expansion` (`for_each`/`count`), `enabled` | 1.1.3 (experiment), **1.2.0** (GA) | |
| Dependency outputs read from state by default | **1.2.0** | Earlier: opt in with the `dependency-fetch-output-from-state` experiment (added in **0.96.0**). |
| OCI module sources, `version` constraints | **1.2.0** | |
| Auto provider cache dir (`TF_PLUGIN_CACHE_DIR`, OpenTofu >= 1.10 only) | 0.82.3 (experiment), **0.89.0** (default) | Silently does nothing on Terraform or OpenTofu < 1.10. |
| Global cache dir honors `XDG_CACHE_HOME` (CAS, auto provider cache) | **1.0.4** | Earlier versions use `~/.cache/terragrunt` on Linux. |

## Old → new CLI mapping

| Old (≤ 0.77, removed or deprecated) | New (≥ 0.77.22) | Removed in |
|------------------------------------|-----------------|-----------|
| `terragrunt run-all plan` | `terragrunt run --all -- plan` (or `terragrunt plan --all`) | gone by 1.0.0 |
| `plan-all` / `apply-all` / `destroy-all` / `output-all` / `validate-all` | `run --all <cmd>` | 0.84.0 |
| `spin-up` / `tear-down` | `run --all -- apply` / `run --all -- destroy` | 0.84.0 |
| `terragrunt workspace list` (default command forwarding) | `terragrunt run -- workspace list` | gone by 1.0 (1.2.1: `unknown command`) |
| `hclfmt` | `hcl fmt` | deprecated 0.78.0 |
| `hclvalidate` / `validate-inputs` | `hcl validate` / `hcl validate --inputs [--strict]` | deprecated 0.78.0 |
| `terragrunt-info` | `info print` | deprecated 0.78.0 |
| `graph-dependencies` | `dag graph` | deprecated 0.78.0 |
| `output-module-groups` | `find --dag --json` | deprecated 0.78.0 |
| `render-json` | `render --json -w` | deprecated 0.78.0 |
| `graph` | `run --graph` | deprecated 0.78.0 |
| `--terragrunt-non-interactive` | `--non-interactive` | 0.85.0 |
| `--terragrunt-tfpath` | `--tf-path` | 0.85.0 |
| `--terragrunt-working-dir` | `--working-dir` | 0.85.0 |
| `--terragrunt-include-dir` / `--terragrunt-exclude-dir` | `--queue-include-dir` / `--queue-exclude-dir` (later `--filter`) | 0.85.0 |
| `TERRAGRUNT_*` env vars | `TG_*` env vars | not removed (still accepted in 1.2.1). 0.68 ignores `TG_*`. Not a 1:1 rename: `TERRAGRUNT_DOWNLOAD` → `TG_DOWNLOAD_DIR` |
| auto provider cache dir (OpenTofu >= 1.10) | — | experiment **0.82.3** (`--experiment auto-provider-cache-dir`), default **0.89.0** (opt out `--no-auto-provider-cache-dir`) |

Tested on Floci with a two-unit classic layout: TG 0.68.0 `run-all plan --terragrunt-non-interactive --terragrunt-tfpath …` works. 0.78.1 accepts both forms and prints deprecation warnings for the old ones. 1.0.0 rejects `--terragrunt-non-interactive` and `run-all`. 1.2.1 prints `unknown command: "run-all"`.

## OpenTofu vs Terraform

| Feature | OpenTofu | Terraform |
|---------|----------|-----------|
| S3 `use_lockfile` (no DynamoDB) | **≥ 1.10** ([1.10.0 release](https://github.com/opentofu/opentofu/releases/tag/v1.10.0)) | **1.10** experimental, **≥ 1.11** GA; DynamoDB args deprecated ([1.11.0 release](https://github.com/hashicorp/terraform/releases/tag/v1.11.0)) |
| State/plan encryption (`remote_state.encryption`, `terraform { encryption {} }`) | **≥ 1.7** ([blog](https://opentofu.org/blog/opentofu-1-7-0/)) | Not available, so don't suggest it for Terraform users |
| OCI registry module sources (`oci:`) | ≥ 1.10 | Not available (*UNVERIFIED* for latest Terraform) |
| Provider-defined functions in config | ≥ 1.7 | ≥ 1.8 (*UNVERIFIED*) |
| Binary selection in Terragrunt | `tofu` preferred if on `PATH` | set `--tf-path terraform` / `TG_TF_PATH=terraform` (legacy `terraform_binary`, `--terragrunt-tfpath`) |

Pin the IaC version with `terraform_version_constraint` and Terragrunt with `terragrunt_version_constraint` in `root.hcl`.

## Classic (implicit) vs explicit stacks

| Layout | Works on | Use when |
|--------|----------|----------|
| Classic/implicit: directories of `terragrunt.hcl`, `_envcommon`, `run-all`/`run --all` | every version (0.68+) | TG < 0.78, an existing Gruntwork-style repo, or a small footprint. See [classic-live-structure.md](classic-live-structure.md). |
| Explicit stacks: `terragrunt.stack.hcl` + catalog + `values` | Requires TG ≥ 0.78 (≥ 0.71.3 with `--experiment stacks`) | New repos on a modern TG. |
| Stacks + `autoinclude` / `unit.x.path` wiring | Requires TG ≥ 1.1 | Otherwise wire `dependency` blocks with paths passed through `values`. |
| Stacks + `expansion` | Requires TG ≥ 1.2 | Otherwise copy blocks or generate them. |

## Verification notes

- Versions above come from GitHub release notes (fetched 2026-10-24): 0.71.3, 0.72.2, 0.73.0, 0.75.5, 0.77.0, 0.77.22, 0.78.0, 0.82.4, 0.84.0, 0.85.0, 0.87.0, 0.91.2, 0.97.0, 1.0.0, 1.0.1, 1.1.0, 1.1.3 and 1.2.0.
- Local tests: Terragrunt 0.68.0, 0.78.1, 1.0.0 and 1.2.1 with OpenTofu 1.10.6 on a Floci S3 backend.
- Old TG (aws-sdk v1, e.g. 0.68) ignores `endpoints = { s3 = … }`. For S3-compatible or local endpoints, use `endpoint = "…"` + `force_path_style = true`, or the bucket checks go to real AWS.
