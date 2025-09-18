resource "aws_security_group" "ec2_sg" {
  vpc_id      = aws_vpc.main.id
  name        = "${var.project_name}-EC2-SG"
  description = "Security group for Wiki.js EC2 instance"

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

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow SSH from anywhere (for testing; restrict in production)"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1" # Allows all protocols
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = merge(var.tags, { Name = "${var.project_name}-EC2-SG" })
}