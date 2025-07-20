# Configure the AWS Provider for the main region (ap-southeast-2)
provider "aws" {
  region = var.aws_region
}

# Configure a separate AWS Provider for the ACM certificate region (us-east-1)
# This provider is still needed because CloudFront requires the ACM certificate
# to be in us-east-1, and Terraform needs to know about that region.
provider "aws" {
  alias  = "acm_region"
  region = var.acm_certificate_region
}

# --- VPC and Networking ---

resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr_block
  tags       = merge(var.tags, { Name = "${var.project_name}-VPC" })
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr_block
  availability_zone       = "${var.aws_region}a" # Use a specific AZ for simplicity
  map_public_ip_on_launch = true
  tags                    = merge(var.tags, { Name = "${var.project_name}-PublicSubnet" })
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
  tags   = merge(var.tags, { Name = "${var.project_name}-IGW" })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
  tags = merge(var.tags, { Name = "${var.project_name}-PublicRouteTable" })
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# --- Security Groups ---

resource "aws_security_group" "ec2_sg" {
  vpc_id      = aws_vpc.main.id
  name        = "${var.project_name}-EC2-SG"
  description = "Security group for Wiki.js EC2 instance"

  # SSH access
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.ssh_ingress_cidrs
    description = "Allow SSH access"
  }

  # HTTP access from CloudFront (or direct for testing)
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # CloudFront will forward HTTP requests
    description = "Allow HTTP access from anywhere (CloudFront will filter)"
  }

  # All outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = merge(var.tags, { Name = "${var.project_name}-EC2-SG" })
}

# --- EC2 Instance ---

resource "aws_instance" "wikijs_server" {
  ami                         = var.ami_id
  instance_type               = var.instance_type
  key_name                    = var.key_pair_name
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.ec2_sg.id]
  associate_public_ip_address = true # Will be replaced by EIP
  tags                        = merge(var.tags, { Name = "${var.project_name}-WikiJS-Server" })

  # User data to ensure system is updated and ready for Ansible
  user_data = <<-EOF
              #!/bin/bash
              sudo apt update -y
              sudo apt upgrade -y
              EOF
}

# Elastic IP for the EC2 instance
resource "aws_eip" "wikijs_eip" {
  instance = aws_instance.wikijs_server.id
  domain   = "vpc" # Corrected: Changed from vpc = true to domain = "vpc"
  tags     = merge(var.tags, { Name = "${var.project_name}-WikiJS-EIP" })
}

# --- Route 53 Public Hosted Zone and ACM Certificate ---

# Data source to reference the existing public hosted zone
data "aws_route53_zone" "public" {
  name = var.public_hosted_zone_name
}

# New: Route 53 A record for the CloudFront origin, pointing to the EC2 EIP
# This is needed because CloudFront origin_name cannot be an IP address directly.
resource "aws_route53_record" "wikijs_origin_record" {
  zone_id = data.aws_route53_zone.public.zone_id
  name    = "origin.${var.public_hosted_zone_name}" # e.g., origin.marcosms.com.au
  type    = "A"
  ttl     = 300
  records = [aws_eip.wikijs_eip.public_ip]
}

# --- CloudFront Distribution ---

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

# Route 53 Alias record for public domain to CloudFront
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
