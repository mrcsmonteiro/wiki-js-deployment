# New Wiki.js host built from the Packer image, run next to the old instance
# until cutover (the Elastic IP stays on the old instance until then).
#
# The root volume is stateless and rebuilt from the image. Everything that
# must survive (Docker data-root with all volumes, the PCA app directory)
# lives on the persistent data volume, which is the only thing backed up.

resource "aws_ebs_volume" "data" {
  availability_zone = aws_subnet.public.availability_zone
  size              = var.data_volume_size
  type              = "gp3"
  encrypted         = true
  kms_key_id        = aws_kms_key.data_volume.arn

  tags = {
    Name                          = "wiki-js-prod-data"
    aws-control-tower-backupdaily = "true"
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_instance" "wikijs_prod" {
  ami                         = var.wikijs_prod_ami_id
  instance_type               = var.prod_instance_type
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.ec2_sg.id]
  iam_instance_profile        = aws_iam_instance_profile.ssm_profile.name
  key_name                    = var.key_pair_name # SSH is closed in Task 14
  associate_public_ip_address = true              # temporary test IP until the EIP moves
  disable_api_termination     = true

  # Burst credits without surplus charges; the workload is idle most of the time.
  credit_specification {
    cpu_credits = "standard"
  }

  # IMDSv2 only. Hop limit 1 keeps containers from reaching instance metadata.
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
    tags                  = { Name = "wiki-js-prod-root" }
  }

  # No backup tag here: an instance backup would include the aws/ebs root
  # volume, whose copy to the central vault fails. The data volume is tagged.
  tags = { Name = "wiki-js-prod" }

  # A new image is rolled out deliberately (remove ami from ignore_changes,
  # review the replacement plan), never as a side effect.
  lifecycle {
    prevent_destroy = true
    ignore_changes  = [ami]
  }
}

resource "aws_volume_attachment" "data" {
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.data.id
  instance_id = aws_instance.wikijs_prod.id

  # Stop the instance before any detach, so the filesystem is not cut off mid-write.
  stop_instance_before_detaching = true
}
