resource "aws_security_group" "ec2_sg" {
  vpc_id      = aws_vpc.main.id
  name        = "${var.project_name}-EC2-SG"
  description = "Security group for Wiki.js EC2 instance"

  # HTTP from anywhere: CloudFront origin for Wiki.js, and PCA direct + Let's Encrypt http-01.
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTP access from anywhere (CloudFront will filter)"
  }

  # HTTPS from anywhere: PCA (pca.marcosms.com.au) is served directly over TLS on this host.
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTPS access from anywhere"
  }

  # All outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow SSH from anywhere (for testing; restrict in production)"
  }

  tags = merge(var.tags, { Name = "${var.project_name}-EC2-SG" })
}