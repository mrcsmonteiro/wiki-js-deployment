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