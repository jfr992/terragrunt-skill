locals {
  # Parameters from consuming repo (via values)
  service     = values.service
  environment = values.environment
  domain      = values.domain
  runtime     = values.runtime

  # Computed values
  website_fqdn = "${values.service}-${values.environment}.${values.domain}"
  bucket_name  = "platform-${values.runtime}"
  s3_prefix    = "${values.service}/${values.environment}"

  # Common tags for all resources
  common_tags = merge(values.tags, {
    Stack       = "frontend"
    Service     = values.service
    Environment = values.environment
    Runtime     = values.runtime
    FQDN        = local.website_fqdn
  })
}

# S3 bucket for hosting files
unit "s3" {
  source = "git::git@github.com:YOUR_ORG/infrastructure-catalog.git//units/s3?ref=${values.version}"
  path   = "s3"

  values = {
    version = values.version

    bucket        = local.bucket_name
    force_destroy = try(values.s3_force_destroy, false)

    versioning = {
      status = "Enabled"
    }

    server_side_encryption_configuration = {
      rule = {
        apply_server_side_encryption_by_default = {
          sse_algorithm = "AES256"
        }
        bucket_key_enabled = true
      }
    }

    block_public_acls       = true
    block_public_policy     = true
    ignore_public_acls      = true
    restrict_public_buckets = true

    tags = local.common_tags
  }
}

# Route53 DNS records
unit "route53" {
  source = "git::git@github.com:YOUR_ORG/infrastructure-catalog.git//units/route53?ref=${values.version}"
  path   = "route53"

  values = {
    version = values.version

    create_zone = try(values.hosted_zone_id, "") == "" ? true : false
    zone_name   = try(values.hosted_zone_id, "") == "" ? values.domain : ""

    records = [
      {
        name = local.website_fqdn
        type = "A"
        alias = {
          name                   = "../cloudfront"  # Reference CloudFront
          zone_id                = "Z2FDTNDATAQYW2" # CloudFront hosted zone
          evaluate_target_health = false
        }
      }
    ]

    tags = local.common_tags
  }
}

# ACM Certificate (must be us-east-1 for CloudFront)
unit "acm" {
  source = "git::git@github.com:YOUR_ORG/infrastructure-catalog.git//units/acm?ref=${values.version}"
  path   = "acm"

  values = {
    version = values.version

    domain_name               = local.website_fqdn
    subject_alternative_names = try(values.acm_subject_alternative_names, [])
    validation_method         = "DNS"

    create_route53_records              = true
    zone_id                            = try(values.hosted_zone_id, "../route53")
    validation_allow_overwrite_records = true
    dns_ttl                            = 60

    wait_for_validation = true
    validation_timeout  = "10m"

    tags = local.common_tags
  }
}

# CloudFront distribution
unit "cloudfront" {
  source = "git::git@github.com:YOUR_ORG/infrastructure-catalog.git//units/cloudfront?ref=${values.version}"
  path   = "cloudfront"

  values = {
    version = values.version

    aliases             = [local.website_fqdn]
    enabled             = true
    comment             = "Distribution for ${local.website_fqdn}"
    default_root_object = try(values.default_root_object, "index.html")
    http_version        = "http2"
    is_ipv6_enabled     = true
    price_class         = try(values.cloudfront_price_class, "PriceClass_All")
    wait_for_deployment = true

    # S3 origin
    origin = {
      s3_origin = {
        domain_name = "${local.bucket_name}.s3.amazonaws.com"
        origin_id   = "S3-${local.bucket_name}"
        origin_path = "/${local.s3_prefix}"
      }
    }

    # SSL certificate - reference ACM unit
    viewer_certificate = {
      acm_certificate_arn      = "../acm"
      ssl_support_method       = "sni-only"
      minimum_protocol_version = "TLSv1.2_2021"
    }

    tags = local.common_tags
  }
}
