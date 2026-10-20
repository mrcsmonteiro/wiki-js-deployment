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

  # Old host, stopped after the cutover and kept for rollback until Task 15.
  # Never replace or destroy it from Terraform: a changed AMI or user_data must
  # not force a rebuild, and neither may the public IP it lost when it stopped
  # (refresh then reads associate_public_ip_address = false, which forces
  # replacement).
  lifecycle {
    prevent_destroy = true
    ignore_changes  = [ami, user_data, user_data_base64, associate_public_ip_address]
  }
}

# Elastic IP: the public address of both sites (CloudFront origin record and PCA DNS).
# Cutover (Task 12) moved it from the old instance (aws_instance.wikijs_server) to the new
# one. Rollback = point it back at aws_instance.wikijs_server and apply.
resource "aws_eip" "wikijs_eip" {
  instance = aws_instance.wikijs_prod.id
  domain   = "vpc"
  tags     = merge(var.tags, { Name = "${var.project_name}-WikiJS-EIP" })

  # Public IP for both sites (CloudFront origin and PCA DNS). Losing it breaks both.
  lifecycle {
    prevent_destroy = true
  }
}