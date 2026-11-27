# Production distribution for wiki.marcosms.com.au.
#
# var.prod_origin picks the host behind it, so the cutover to Wiki.js 3 is one
# variable flip (and the rollback is the same flip back):
#   "legacy" -> the 2.x host over the public origin record (HTTP over the internet)
#   "v3"     -> the 3.x host through the CloudFront VPC origin (private subnet),
#               with managed cache and origin request policies and the WAF web ACL.
# With "legacy" this file plans exactly as before.

locals {
  prod_on_v3     = var.prod_origin == "v3"
  prod_origin_id = local.prod_on_v3 ? "WikiJSV3Origin" : "WikiJSECOrigin"
}

resource "aws_cloudfront_distribution" "wikijs_cdn" {
  dynamic "origin" {
    for_each = local.prod_on_v3 ? [] : [1]
    content {
      # Use the FQDN of the new Route 53 A record as the origin domain name
      domain_name = aws_route53_record.wikijs_origin_record.fqdn
      origin_id   = "WikiJSECOrigin"

      custom_origin_config {
        http_port              = 80
        https_port             = 443         # Not used if CF -> EC2 is HTTP
        origin_protocol_policy = "http-only" # CloudFront connects to EC2 via HTTP
        origin_ssl_protocols   = ["TLSv1.2"] # Not relevant for http-only
      }
    }
  }

  dynamic "origin" {
    for_each = local.prod_on_v3 ? [1] : []
    content {
      domain_name = aws_instance.wikijs_v3.private_dns
      origin_id   = "WikiJSV3Origin"

      vpc_origin_config {
        vpc_origin_id            = aws_cloudfront_vpc_origin.wikijs_v3.id
        origin_read_timeout      = 60
        origin_keepalive_timeout = 5
      }
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "CloudFront distribution for Wiki.js"
  default_root_object = "index.html" # Wiki.js handles routing, but good default
  web_acl_id          = local.prod_on_v3 && var.enable_waf ? aws_wafv2_web_acl.wikijs[0].arn : null

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.prod_origin_id

    viewer_protocol_policy = "redirect-to-https" # Force HTTPS for viewers
    compress               = true

    # v3: managed policies (no caching, forward everything the viewer sent).
    cache_policy_id          = local.prod_on_v3 ? data.aws_cloudfront_cache_policy.caching_disabled.id : null
    origin_request_policy_id = local.prod_on_v3 ? data.aws_cloudfront_origin_request_policy.all_viewer.id : null

    # legacy: the original forwarded_values settings, unchanged.
    dynamic "forwarded_values" {
      for_each = local.prod_on_v3 ? [] : [1]
      content {
        query_string = true
        headers      = ["Origin", "Authorization", "Content-Type", "Accept"] # Forward headers for dynamic content
        cookies {
          forward = "all"
        }
      }
    }

    # Set TTLs to 0 to minimize caching for dynamic content (legacy only; the
    # cache policy carries them on v3).
    min_ttl     = local.prod_on_v3 ? null : 0
    default_ttl = local.prod_on_v3 ? null : 0
    max_ttl     = local.prod_on_v3 ? null : 0
  }

  # SSL certificate for CloudFront - using the existing one
  viewer_certificate {
    acm_certificate_arn      = var.existing_acm_certificate_arn # Use the ARN from the variable
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  aliases = [var.domain_name] # Associate your custom domain with CloudFront

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = merge(var.tags, { Name = "${local.name_prefix}-cdn" })

  lifecycle {
    prevent_destroy = true
  }
}
