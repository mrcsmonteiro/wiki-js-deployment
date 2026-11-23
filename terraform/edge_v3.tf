# Edge for the Wiki.js 3 host: AWS WAF, and a staging distribution with its DNS
# records for the rehearsal. The existing wildcard certificate (*.marcosms.com.au)
# covers the staging name. Remove the staging pieces after cutover
# (set var.enable_v3_staging = false).

data "aws_cloudfront_cache_policy" "caching_disabled" {
  name = "Managed-CachingDisabled"
}

# Forwards the viewer's Host header, cookies, query strings and headers, so the
# nginx vhost and Wiki.js see the real site name.
data "aws_cloudfront_origin_request_policy" "all_viewer" {
  name = "Managed-AllViewer"
}

# --- AWS WAF (CloudFront scope, so it lives in us-east-1) ---------------------

resource "aws_wafv2_web_acl" "wikijs" {
  count    = var.enable_waf ? 1 : 0
  provider = aws.acm_region

  name        = "${local.v3_name}-edge"
  description = "Wiki.js 3: rate limit, IP reputation and AWS managed rules"
  scope       = "CLOUDFRONT"

  default_action {
    allow {}
  }

  rule {
    name     = "rate-limit-per-ip"
    priority = 1

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = var.waf_rate_limit
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "rate-limit-per-ip"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "aws-ip-reputation"
    priority = 10

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesAmazonIpReputationList"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "aws-ip-reputation"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "aws-known-bad-inputs"
    priority = 20

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "aws-known-bad-inputs"
      sampled_requests_enabled   = true
    }
  }

  # Wiki pages are full of code, HTML and long bodies, so the body-inspecting
  # rules only count. Watch the counts during the rehearsal before tightening.
  rule {
    name     = "aws-common"
    priority = 30

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesCommonRuleSet"

        dynamic "rule_action_override" {
          for_each = ["SizeRestrictions_BODY", "CrossSiteScripting_BODY", "GenericRFI_BODY", "GenericLFI_BODY", "EC2MetaDataSSRF_BODY"]
          content {
            name = rule_action_override.value
            action_to_use {
              count {}
            }
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "aws-common"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${local.v3_name}-edge"
    sampled_requests_enabled   = true
  }

  tags = { Name = "${local.v3_name}-edge" }
}

# --- Staging name for the rehearsal -------------------------------------------

resource "aws_cloudfront_distribution" "wikijs_v3_staging" {
  count = var.enable_v3_staging ? 1 : 0

  origin {
    domain_name = aws_instance.wikijs_v3.private_dns
    origin_id   = "WikiJSV3Origin"

    vpc_origin_config {
      vpc_origin_id            = aws_cloudfront_vpc_origin.wikijs_v3.id
      origin_read_timeout      = 60
      origin_keepalive_timeout = 5
    }
  }

  enabled         = true
  is_ipv6_enabled = true
  comment         = "Wiki.js 3 staging (rehearsal before cutover)"
  aliases         = [var.v3_staging_domain_name]
  web_acl_id      = var.enable_waf ? aws_wafv2_web_acl.wikijs[0].arn : null

  default_cache_behavior {
    allowed_methods          = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods           = ["GET", "HEAD"]
    target_origin_id         = "WikiJSV3Origin"
    viewer_protocol_policy   = "redirect-to-https"
    compress                 = true
    cache_policy_id          = data.aws_cloudfront_cache_policy.caching_disabled.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer.id
  }

  viewer_certificate {
    acm_certificate_arn      = var.existing_acm_certificate_arn # *.marcosms.com.au covers the staging name
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = { Name = "${local.v3_name}-staging-cdn" }
}

resource "aws_route53_record" "v3_staging" {
  count = var.enable_v3_staging ? 1 : 0

  zone_id = data.aws_route53_zone.public.zone_id
  name    = var.v3_staging_domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.wikijs_v3_staging[0].domain_name
    zone_id                = aws_cloudfront_distribution.wikijs_v3_staging[0].hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "v3_staging_aaaa" {
  count = var.enable_v3_staging ? 1 : 0

  zone_id = data.aws_route53_zone.public.zone_id
  name    = var.v3_staging_domain_name
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.wikijs_v3_staging[0].domain_name
    zone_id                = aws_cloudfront_distribution.wikijs_v3_staging[0].hosted_zone_id
    evaluate_target_health = false
  }
}
