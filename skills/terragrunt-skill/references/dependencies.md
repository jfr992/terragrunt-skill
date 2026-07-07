# Unit Interdependencies

Units within a stack can depend on each other, creating a DAG (Directed Acyclic Graph) of resources.

## Contents
- Dependency Patterns
- Choosing a Wiring Pattern
- How Dependencies Work (values pattern)
- Autoinclude Dependencies (Terragrunt 1.1+)
- Conditional Dependencies
- Smart Skip Outputs
- Reference Resolution in Inputs
- Provider Generation from Dependencies
- Applying Single Units with Dependencies
- Best Practices
- References

## Dependency Patterns

### Fan-Out Pattern (EKS Example)

```
eks (core cluster)
├── eks-config (depends on eks)
├── karpenter (depends on eks)
└── argocd-registration (depends on eks)
```

### Chain Pattern (Frontend Example)

```
s3 → cloudfront → route53
      ↑
     acm
```

### Multiple Dependencies (CloudFront Example)

```
cloudfront
├── depends on acm (for SSL certificate)
└── depends on s3 (for origin bucket)
```

## Choosing a Wiring Pattern

Two supported ways to wire dependencies between units in a stack:

| | Values pattern | Autoinclude (1.1+) |
|---|---|---|
| Where wiring lives | Catalog unit (`dependency` block reads `values.X_path`) | Stack file (`autoinclude` block inside `unit`) |
| Catalog unit must know about the dependency | Yes | No |
| Conditional/optional dependencies | Rich (`enabled`, `skip_outputs`, reference resolution) | Basic |
| Path references | String values (`"../eks"`) | `unit.<name>.path` (resolved, not hardcoded) |
| Works pre-1.1 | Yes | No |

Use the values pattern when catalog units are designed around it (this skill's existing catalogs) or dependencies are conditional. Use autoinclude when composing units that shouldn't know about each other, or to avoid plumbing paths through `values`. Both can coexist in one stack.

## How Dependencies Work (values pattern)

### 1. Stack passes dependency paths via values

```hcl
# terragrunt.stack.hcl
unit "eks" {
  source = "${local.catalog_path}//units/eks?ref=main"
  path   = "eks"
  values = { ... }
}

unit "karpenter" {
  source = "${local.catalog_path}//units/eks-karpenter?ref=main"
  path   = "karpenter"
  values = {
    eks_path = "../eks"  # Relative path to eks unit
    version  = "v1.0.0"
  }
}

unit "argocd-registration" {
  source = "${local.catalog_path}//units/argocd-cluster-configuration?ref=main"
  path   = "argocd-registration"
  values = {
    eks_path = "../eks"  # Same dependency, different unit
    version  = "v1.0.0"
  }
}
```

### 2. Catalog units resolve paths to dependencies

```hcl
# units/eks-karpenter/terragrunt.hcl
dependency "eks" {
  config_path = values.eks_path  # "../eks" from stack

  mock_outputs = {
    cluster_name = "mock-eks-cluster"
    eks_managed_node_groups = {
      mock = { iam_role_arn = "arn:aws:iam::123456789012:role/mock" }
    }
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

inputs = {
  cluster_name = dependency.eks.outputs.cluster_name
  node_iam_role_arn = values(dependency.eks.outputs.eks_managed_node_groups)[0].iam_role_arn
}
```

## Autoinclude Dependencies (Terragrunt 1.1+)

Declare the dependency in the stack file itself — the catalog unit stays dependency-agnostic:

```hcl
# terragrunt.stack.hcl
unit "vpc" {
  source = "${local.catalog_path}//units/vpc?ref=v1.0.0"
  path   = "vpc"
}

unit "app" {
  source = "${local.catalog_path}//units/app?ref=v1.0.0"
  path   = "app"

  autoinclude {
    dependency "vpc" {
      config_path = unit.vpc.path  # resolved sibling path, not hardcoded
      mock_outputs = {
        vpc_id = "vpc-mock"
      }
    }
    inputs = {
      vpc_id = dependency.vpc.outputs.vpc_id
    }
  }
}
```

`terragrunt stack generate` writes a `terragrunt.autoinclude.hcl` next to the generated unit, which Terragrunt merges automatically during parsing — the unit's own `terragrunt.hcl` is untouched.

`autoinclude` also supports depending on entire stacks: point `config_path` at a stack directory (via `stack.<name>.path`) to aggregate that stack's outputs.

Pairs well with [CAS relative sources](cas.md) — `update_source_with_cas = true` plus autoinclude makes a generated stack fully self-contained.

## Conditional Dependencies

Enable/disable dependencies based on configuration:

```hcl
# units/cloudfront/terragrunt.hcl

# Only enable ACM dependency if using ACM certificate
dependency "acm" {
  enabled      = try(values.use_acm_certificate, false)
  config_path  = try(values.acm_path, "../acm")
  mock_outputs = {
    acm_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/mock"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

# Only enable S3 dependency if using S3 origin
dependency "s3" {
  enabled      = try(values.use_s3_origin, false)
  config_path  = try(values.s3_path, "../s3")
  mock_outputs = {
    s3_bucket_bucket_domain_name = "mock-bucket.s3.amazonaws.com"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}
```

## Smart Skip Outputs

Skip dependency outputs based on whether they're actually needed:

```hcl
# units/route53/terragrunt.hcl
dependency "cloudfront" {
  config_path = try(values.cloudfront_path, "../cloudfront")

  # Only fetch outputs if records actually reference CloudFront
  skip_outputs = !try(
    anytrue([
      for record in try(values.records, []) :
        try(record.alias.name == "../cloudfront", false)
    ]),
    false
  )

  mock_outputs = {
    cloudfront_distribution_domain_name    = "d111111abcdef8.cloudfront.net"
    cloudfront_distribution_hosted_zone_id = "Z2FDTNDATAQYW2"
  }
}
```

## Reference Resolution in Inputs

Resolve symbolic references to actual dependency outputs:

```hcl
inputs = {
  # Replace "../cloudfront" with actual CloudFront domain
  origin = {
    for key, origin_config in values.origin :
    key => merge(
      origin_config,
      origin_config.domain_name == "../s3" ? {
        domain_name = dependency.s3.outputs.s3_bucket_bucket_domain_name
      } : {}
    )
  }

  # Replace "../acm" with actual certificate ARN
  viewer_certificate = merge(
    values.viewer_certificate,
    try(values.viewer_certificate.acm_certificate_arn, "") == "../acm" ? {
      acm_certificate_arn = dependency.acm.outputs.acm_certificate_arn
    } : {}
  )
}
```

## Provider Generation from Dependencies

Generate providers that authenticate using dependency outputs:

```hcl
# units/eks-config/terragrunt.hcl
generate "provider_kubectl" {
  path      = "cluster_auth.tf"
  if_exists = "overwrite"
  contents  = <<EOF
data "aws_eks_cluster_auth" "eks" {
  name = "${dependency.eks.outputs.cluster_name}"
}

provider "kubectl" {
  host                   = "${dependency.eks.outputs.cluster_endpoint}"
  cluster_ca_certificate = base64decode("${dependency.eks.outputs.cluster_certificate_authority_data}")
  token                  = data.aws_eks_cluster_auth.eks.token
  load_config_file       = false
}
EOF
}
```

## Applying Single Units with Dependencies

When applying a single unit that has dependencies, the dependencies must already exist:

```bash
# First apply the base unit
terragrunt stack run apply --filter '.terragrunt-stack/eks'

# Then apply dependent units (eks must be applied first)
terragrunt stack run apply --filter '.terragrunt-stack/karpenter'

# Or apply a unit and all its dependencies
terragrunt stack run apply --filter '.terragrunt-stack/karpenter...'
```

## Best Practices

1. **Always provide mock outputs** - Required for plan/validate without real dependencies
2. **Use `enabled` for optional dependencies** - Don't fetch outputs for unused features
3. **Use `skip_outputs` for conditional fetching** - Based on actual usage in inputs
4. **Allow path overrides** - `try(values.X_path, "../default")` for flexibility
5. **Document required outputs** - In mock_outputs, show what the dependency must provide

## References

- [Patterns Guide](patterns.md)
- [Stack Commands](stack-commands.md)
