# Data source to reference the existing public hosted zone
data "aws_route53_zone" "public" {
  name = var.public_hosted_zone_name
}

# Route 53 A record for the CloudFront origin, pointing to the EC2 EIP
# This is needed because CloudFront origin_name cannot be an IP address directly.
resource "aws_route53_record" "wikijs_origin_record" {
  zone_id = data.aws_route53_zone.public.zone_id
  name    = "origin.${var.public_hosted_zone_name}"
  type    = "A"
  ttl     = 300
  records = [aws_eip.wikijs_eip.public_ip]
}

# Alias record for public domain to CloudFront
resource "aws_route53_record" "wikijs_cname" {
  zone_id = data.aws_route53_zone.public.zone_id # Use the existing hosted zone's ID
  name    = var.domain_name
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.wikijs_cdn.domain_name
    zone_id                = aws_cloudfront_distribution.wikijs_cdn.hosted_zone_id
    evaluate_target_health = false
  }
}