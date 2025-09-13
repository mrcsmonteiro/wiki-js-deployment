resource "aws_cloudfront_distribution" "wikijs_cdn" {
  origin {
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

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "CloudFront distribution for Wiki.js"
  default_root_object = "index.html" # Wiki.js handles routing, but good default

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "WikiJSECOrigin"

    viewer_protocol_policy = "redirect-to-https" # Force HTTPS for viewers
    compress               = true

    forwarded_values {
      query_string = true
      headers      = ["Origin", "Authorization", "Content-Type", "Accept"] # Forward headers for dynamic content
      cookies {
        forward = "all"
      }
    }

    # Set TTLs to 0 to minimize caching for dynamic content
    min_ttl     = 0
    default_ttl = 0
    max_ttl     = 0
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

  tags = merge(var.tags, { Name = "${var.project_name}-CloudFront" })
}