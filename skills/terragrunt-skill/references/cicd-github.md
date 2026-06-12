# GitHub Actions Pipelines for Terragrunt

> **Work in Progress**: GitHub Actions workflows are under development. For now, refer to the GitLab CI examples in [cicd-gitlab.md](cicd-gitlab.md) and adapt them for GitHub Actions using:
> - [aws-actions/configure-aws-credentials](https://github.com/aws-actions/configure-aws-credentials) for AWS OIDC
> - [google-github-actions/auth](https://github.com/google-github-actions/auth) for GCP Workload Identity
> - [actions/cache](https://github.com/actions/cache) for provider caching

## Key Differences from GitLab CI

| GitLab CI | GitHub Actions |
|-----------|----------------|
| `id_tokens` block | `permissions: id-token: write` |
| `extends: .template` | `uses: ./.github/workflows/reusable.yml` |
| `rules: changes:` | `paths:` filter or `dorny/paths-filter` |
| `needs: [job]` | `needs: [job]` (same) |
| `when: manual` | `environment:` with required reviewers |

## Quick Reference

```yaml
# AWS OIDC Authentication
- name: Configure AWS Credentials
  uses: aws-actions/configure-aws-credentials@v4
  with:
    role-to-assume: arn:aws:iam::111111111111:role/TerraformCrossAccount
    aws-region: us-east-1

# GCP Workload Identity
- name: Authenticate to GCP
  uses: google-github-actions/auth@v2
  with:
    workload_identity_provider: 'projects/123456789012/locations/global/workloadIdentityPools/github-pool/providers/github-provider'
    service_account: 'sa-tf-admin@my-project.iam.gserviceaccount.com'
```

---

## References

### GitHub Actions OIDC Authentication
- [AWS OIDC for GitHub Actions](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services)
- [GCP Workload Identity Federation](https://cloud.google.com/iam/docs/workload-identity-federation)
- [google-github-actions/auth](https://github.com/google-github-actions/auth) - Official GitHub Action for GCP authentication
- [GitHub Actions Documentation](https://docs.github.com/en/actions)
