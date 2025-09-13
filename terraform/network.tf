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