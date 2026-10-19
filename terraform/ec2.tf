resource "aws_instance" "wikijs_server" {
  ami                         = var.ami_id
  instance_type               = var.instance_type
  key_name                    = var.key_pair_name
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.ec2_sg.id]
  associate_public_ip_address = true # Will be replaced by EIP
  iam_instance_profile        = aws_iam_instance_profile.ssm_profile.name
  disable_api_termination     = true # Turn off before terminating (Task 15)
  tags                        = merge(var.tags, { Name = "${var.project_name}-WikiJS-Server" })

  # User data to ensure system is updated and ready for Ansible
  user_data = <<-EOF
              #!/bin/bash
              sudo apt update -y
              sudo apt upgrade -y
              EOF

  # This instance also hosts an unmanaged app (PCA). Never replace or destroy it
  # from Terraform; a changed AMI or user_data must not force a rebuild.
  lifecycle {
    prevent_destroy = true
    ignore_changes  = [ami, user_data, user_data_base64]
  }
}

# Elastic IP for the EC2 instance
resource "aws_eip" "wikijs_eip" {
  instance = aws_instance.wikijs_server.id
  domain   = "vpc"
  tags     = merge(var.tags, { Name = "${var.project_name}-WikiJS-EIP" })

  # Public IP for both sites (CloudFront origin and PCA DNS). Losing it breaks both.
  lifecycle {
    prevent_destroy = true
  }
}