# Private subnet for the Wiki.js 3 host. Nothing in it has a public IP: viewers
# reach it only through the CloudFront VPC origin, and it reaches out (GitHub for
# Git sync, SSM, CloudWatch, package mirrors) through a NAT instance.
#
# Same AZ as the public subnet, so EBS volumes and the instance stay together.

resource "aws_subnet" "private" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.private_subnet_cidr_block
  availability_zone       = aws_subnet.public.availability_zone
  map_public_ip_on_launch = false

  tags = { Name = "${local.name_prefix}-private-subnet" }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  # The default route (0.0.0.0/0 -> NAT ENI) is managed by the fck-nat module.
  tags = { Name = "${local.name_prefix}-private-rt" }

  lifecycle {
    ignore_changes = [route]
  }
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

# S3 traffic (nightly backups) skips the NAT instance. Gateway endpoints are free.
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]

  tags = { Name = "${local.name_prefix}-s3-endpoint" }
}

# NAT instance (fck-nat, MIT licence) instead of a managed NAT Gateway: one
# t4g.nano in an auto scaling group with a static ENI, so a replaced instance
# keeps the same route. A managed NAT Gateway would cost more than the wiki host.
# Pinned to the commit of tag v1.6.1.
module "fck_nat" {
  source = "git::https://github.com/RaJiska/terraform-aws-fck-nat.git?ref=9b991ddf8e61f8834242b33f8eccae3afd57bc4e"

  name          = "${local.name_prefix}-nat"
  vpc_id        = aws_vpc.main.id
  subnet_id     = aws_subnet.public.id
  instance_type = var.nat_instance_type
  ha_mode       = true
  # Root volume encrypted with the default aws/ebs key: the auto scaling
  # service role has no grant on the data-volume CMK, and the NAT holds no data.

  update_route_tables = true
  route_tables_ids = {
    private = aws_route_table.private.id
  }

  tags = { Name = "${local.name_prefix}-nat" }
}
