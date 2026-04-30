# CLAUDE.md - Contributor & Memory Guide

This file serves as context for Claude Code when working on the terragrunt-skill repository.

## Repository Architecture

This skill uses **progressive disclosure** to minimize token usage:

- **SKILL.md** (~960 lines): Core patterns for Terragrunt stacks, units, and catalog structure
- **references/**: Extended documentation loaded on demand
  - `cicd-pipelines.md`: GitLab CI and GitHub Actions with AWS/GCP OIDC
  - `patterns.md`: Repository separation, pre-commit hooks, semantic versioning
  - `performance.md`: Provider caching, benchmarking tools, optimization
  - `state-management.md`: S3/DynamoDB backend patterns
  - `multi-account.md`: Cross-account role assumption patterns
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

### Values Pattern
Units receive ALL configuration through the `values` object, enabling stacks to configure units without modifying unit code.

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
- Run `terragrunt hclfmt --check` on generated examples
- Verify stack files with `terragrunt stack generate`
- Test unit dependency resolution
- CI validates SKILL.md frontmatter and marketplace.json on every PR

## File Structure

```
terragrunt-skill/
├── CLAUDE.md                   # This file (memory/contributor guide)
├── README.md                   # Repository documentation
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
│       ├── assets/
│       │   ├── catalog-structure/  # Example catalog layout
│       │   ├── live-structure/     # Example live repo layout
│       │   └── images/             # Screenshots and diagrams
│       └── scripts/            # Helper scripts (setup-state-backend.sh)
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

- [Terragrunt Documentation](https://terragrunt.gruntwork.io/docs/)
- [Terragrunt Stacks](https://terragrunt.gruntwork.io/docs/features/stacks/)
- [Terragrunt Filters](https://terragrunt.gruntwork.io/docs/features/filter/)
- [Terragrunt State Backend](https://terragrunt.gruntwork.io/docs/features/state-backend/)
- [Terragrunt Catalog](https://terragrunt.gruntwork.io/docs/features/catalog/)
- [Boilerplate](https://github.com/gruntwork-io/boilerplate) - Template generation for scaffolding
- [OpenTofu Documentation](https://opentofu.org/docs/)
