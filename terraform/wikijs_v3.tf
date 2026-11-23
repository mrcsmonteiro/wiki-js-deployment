# Wiki.js 3 host ("green"). Built next to the 2.x host and reached first on the
# staging name (var.v3_staging_domain_name). The production name moves to it by
# setting var.prod_origin = "v3" (see cloudfront.tf and docs/migration-v3.md).
#
# Same pattern as the 2.x host: a stateless Packer image (packer/v3.pkrvars.hcl)
# plus a separate encrypted data volume that holds the Docker data-root.

locals {
  v3_name = "wiki-js-v3"
}

data "aws_ec2_managed_prefix_list" "cloudfront_origin_facing" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

resource "aws_security_group" "wikijs_v3" {
  name        = "${local.v3_name}-sg"
  description = "Wiki.js 3 host: HTTP from CloudFront only (VPC origin), no other inbound"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "${local.v3_name}-sg" }
}

# CloudFront's origin-facing prefix list. Counts as 55 rules in the group.
resource "aws_vpc_security_group_ingress_rule" "wikijs_v3_http_cloudfront" {
  security_group_id = aws_security_group.wikijs_v3.id
  description       = "HTTP from CloudFront (VPC origin)"
  prefix_list_id    = data.aws_ec2_managed_prefix_list.cloudfront_origin_facing.id
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
}

resource "aws_vpc_security_group_egress_rule" "wikijs_v3_all" {
  security_group_id = aws_security_group.wikijs_v3.id
  description       = "Outbound through the NAT instance and the S3 endpoint"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_ebs_volume" "wikijs_v3_data" {
  availability_zone = aws_subnet.private.availability_zone
  size              = var.v3_data_volume_size
  type              = "gp3"
  encrypted         = true
  kms_key_id        = aws_kms_key.data_volume.arn

  tags = {
    Name                          = "${local.v3_name}-data"
    aws-control-tower-backupdaily = "true"
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_instance" "wikijs_v3" {
  ami                         = var.wikijs_v3_ami_id
  instance_type               = var.v3_instance_type
  subnet_id                   = aws_subnet.private.id
  vpc_security_group_ids      = [aws_security_group.wikijs_v3.id]
  iam_instance_profile        = aws_iam_instance_profile.ssm_profile.name
  associate_public_ip_address = false
  disable_api_termination     = true
  # No key pair: shell access is SSM Session Manager only.

  credit_specification {
    cpu_credits = "standard"
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 10
    encrypted             = true
    delete_on_termination = true
    tags                  = { Name = "${local.v3_name}-root" }
  }

  tags = { Name = local.v3_name }

  lifecycle {
    prevent_destroy = true
    ignore_changes  = [ami]
  }

  # Outbound (Git sync, SSM) needs the NAT route before the first boot.
  depends_on = [module.fck_nat, aws_route_table_association.private]
}

resource "aws_volume_attachment" "wikijs_v3_data" {
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.wikijs_v3_data.id
  instance_id = aws_instance.wikijs_v3.id

  stop_instance_before_detaching = true
}

# CloudFront reaches the instance privately through a service-managed ENI in the
# private subnet. Shared by the staging distribution now and production at cutover.
resource "aws_cloudfront_vpc_origin" "wikijs_v3" {
  vpc_origin_endpoint_config {
    name                   = local.v3_name
    arn                    = aws_instance.wikijs_v3.arn
    http_port              = 80
    https_port             = 443
    origin_protocol_policy = "http-only" # Private path inside AWS; nginx listens on 80.

    origin_ssl_protocols {
      items    = ["TLSv1.2"]
      quantity = 1
    }
  }

  tags = { Name = local.v3_name }
}
