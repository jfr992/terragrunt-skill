# CLAUDE.md - Contributor & Memory Guide

This file serves as context for Claude Code when working on the terragrunt-skill repository.

## Repository Architecture

This skill uses **progressive disclosure** to minimize token usage:

- **SKILL.md** (~140 lines): Core patterns for Terragrunt stacks, units, and catalog structure
- **references/**: Extended documentation loaded on demand
  - `cas.md`: Content Addressable Store — default dedup, update_source_with_cas for self-contained catalog stacks
  - `catalog-scaffolding.md`: Interactive catalog browsing and unit scaffolding
  - `catalog-structure.md`: Directory layout and organization of reusable units and stacks
  - `cicd-github.md`: GitHub Actions pipelines (quick reference and OIDC patterns)
  - `cicd-gitlab.md`: GitLab CI pipelines (templates, AWS/GCP OIDC auth, unit targeting)
  - `cicd-pipelines.md`: Shared CI/CD concepts, run reports, IAM/OIDC cloud setup
  - `classic-live-structure.md`: Traditional account/region/environment hierarchy pattern
  - `dependencies.md`: Unit interdependency patterns (values pattern + autoinclude) and DAG management
  - `discovery-commands.md`: terragrunt find and exploration commands
  - `live-structure.md`: Explicit stacks directory layout and organization
  - `modules-monorepo.md`: Monorepo vs per-repo module versioning strategies
  - `multi-account.md`: Cross-account role assumption and AWS account strategy
  - `naming.md`: Repository and resource naming conventions
  - `patterns.md`: Terragrunt patterns guide and repository separation
  - `performance.md`: Provider caching, benchmarking tools, and optimization
  - `root-config.md`: Root.hcl configuration and locals setup
  - `stack-commands.md`: Stack generation and execution commands
  - `state-management.md`: State backend configuration: native S3 lockfile (OpenTofu >= 1.10) and legacy DynamoDB patterns
- **.claude-plugin/**: Marketplace distribution configuration
- **.github/workflows/**: CI/CD for validation and automated releases

## Content Philosophy

### Include in SKILL.md
- Terragrunt-specific patterns (stacks, units, values pattern)
- Decision frameworks with concrete examples
- Unit interdependency patterns
- Stack filtering and targeting commands
- Reference resolution patterns (`"../unit"` → dependency outputs)

### Exclude from SKILL.md
- Generic Terraform/OpenTofu syntax
- Provider-specific resource details
- Basic HCL language features
- Content covered by official Terragrunt documentation

### Suggestions vs Statements
- Use suggestion language ("Consider...", "Recommended") for patterns that have trade-offs
- Use definitive statements only for syntax requirements or Terragrunt-specific behavior

## Key Patterns

**Watch (active experiments — do not teach until GA):** `deep_merge()` HCL function (deep-merge), `TG_CTX_*` hook env vars (hook-context-env), `--no-hooks` (optional-hooks), Azure backend improvements (azure-backend).

### Values Pattern
Units receive ALL configuration through the `values` object, enabling stacks to configure units without modifying unit code.

### Autoinclude (Terragrunt 1.1+)
Dependencies declared in `autoinclude` blocks inside stack `unit` blocks; generates `terragrunt.autoinclude.hcl`. Documented in `dependencies.md` as a coexisting option with the values pattern — neither is anointed default.

### Reference Resolution
Units resolve symbolic references like `"../acm"` to actual dependency outputs, allowing stacks to wire dependencies declaratively.

### Catalog vs Live
- **Catalog**: Reusable units and template stacks (version-controlled patterns)
- **Live**: Environment-specific deployments consuming the catalog
- **Architecture Options**:
  - Option A: Modules in separate repos (independent versioning, dedicated CI/CD)
  - Option B: Modules in catalog repo (simpler structure, single versioning)

## Development Workflow

### Testing Changes
1. Load updated skill in Claude Code
2. Test against real Terragrunt projects
3. Verify generated configurations are valid HCL
4. Check that patterns match Terragrunt best practices

### Validation
- Run `terragrunt hcl fmt --check` on generated examples
- Verify stack files with `terragrunt stack generate`
- Test unit dependency resolution
- CI validates SKILL.md frontmatter and marketplace.json on every PR

## File Structure

```
terragrunt-skill/
├── CLAUDE.md                   # This file (memory/contributor guide)
├── README.md                   # Repository documentation
├── evaluations/                # Trigger/behavior eval scenarios (manual harness)
│   └── evaluations.json
├── .claude-plugin/
│   ├── plugin.json             # Plugin manifest
│   └── marketplace.json        # Claude Code marketplace distribution
├── .github/workflows/
│   ├── validate.yml            # Skill validation (frontmatter, links)
│   └── automated-release.yml   # Conventional commits → GitHub releases
├── skills/
│   └── terragrunt-skill/
│       ├── SKILL.md            # Main skill (loaded by Claude Code)
│       ├── references/         # Extended documentation
│       └── assets/
│           ├── catalog-structure/  # Example catalog layout
│           ├── live-structure/     # Example live repo layout
│           └── images/             # Screenshots and diagrams
└── test-output/                # Generated test examples
```

## Quality Standards

Contributions should:
- Follow existing code style and patterns
- Include both AWS and GCP examples where applicable
- Use generic placeholders (`YOUR_ORG`, `123456789012`) not real values
- Provide mock outputs for unit dependencies
- Document trade-offs for architectural decisions

## References

- [Terragrunt Documentation](https://docs.terragrunt.com/)
- [Terragrunt Stacks](https://docs.terragrunt.com/features/stacks/)
- [Terragrunt Filters](https://docs.terragrunt.com/features/filter/)
- [Terragrunt State Backend](https://docs.terragrunt.com/features/units/state-backend/)
- [Terragrunt Catalog](https://docs.terragrunt.com/features/catalog/)
- [Boilerplate](https://github.com/gruntwork-io/boilerplate) - Template generation for scaffolding
- [OpenTofu Documentation](https://opentofu.org/docs/)
