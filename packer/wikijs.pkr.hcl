# Wiki.js host image: Ubuntu 24.04 arm64 + Docker + nginx + Wiki.js compose files.
#
# The image is stateless. Data lives on a separate EBS volume mounted at /data
# (Docker data-root and the PCA app directory live there). Secrets are not baked
# in: the DB password is read from SSM Parameter Store at boot.
#
# Usage (from the repo root, with an AWS session for the workload account):
#   packer init packer
#   packer build packer

packer {
  required_version = ">= 1.16.0"

  required_plugins {
    amazon = {
      source  = "github.com/hashicorp/amazon"
      version = "= 1.8.3"
    }
    ansible = {
      source  = "github.com/hashicorp/ansible"
      version = "= 1.1.6"
    }
  }
}

variable "aws_profile" {
  description = "Named AWS CLI profile for the workload account."
  type        = string
  default     = "marcosms-prod-admin"
}

variable "aws_region" {
  description = "Region to build the image in."
  type        = string
  default     = "ap-southeast-2"
}

variable "instance_type" {
  description = "Build instance type. Must be arm64 (Graviton)."
  type        = string
  default     = "t4g.small"
}

variable "postgres_image" {
  description = "PostgreSQL container image, pinned by tag and digest."
  type        = string
  default     = "postgres:16.15-alpine@sha256:721873c34ceb9f8d8fc265984940dc982404c105f19ad51be9fdc5970a6080ea"
}

variable "root_volume_size" {
  description = "Root volume size in GiB. The root disk holds only the OS and swap; data is on /data."
  type        = number
  default     = 10
}

variable "subnet_name_tag" {
  description = "Name tag of the public subnet to build in (terraform/network.tf)."
  type        = string
  default     = "wiki-js-prod-public-subnet"
}

variable "wikijs_image" {
  description = "Wiki.js container image, pinned by tag and digest (latest stable 2.x)."
  type        = string
  default     = "requarks/wiki:2.5.316@sha256:fffff288a52f76e5b8c19a4fbcd0f3e538e96edea642c4f2d813d54d59a876de"
}

locals {
  ami_name = "wiki-js-prod-${formatdate("YYYYMMDD-hhmm", timestamp())}"

  # Tagging standard (.kiro/steering/tagging-standard.md), with ManagedBy = packer.
  common_tags = {
    Application = "wiki-js"
    CostCentre  = "personal"
    Environment = "prod"
    ManagedBy   = "packer"
    Owner       = "marcos"
    Repository  = "wiki-js-deployment"
    Stack       = "packer/wikijs"
  }
}

source "amazon-ebs" "wikijs" {
  profile       = var.aws_profile
  region        = var.aws_region
  instance_type = var.instance_type

  ami_name        = local.ami_name
  ami_description = "Wiki.js host: Ubuntu 24.04 arm64, Docker, nginx, Wiki.js 2.x compose (stateless)"

  # Latest Ubuntu 24.04 arm64 image published by Canonical.
  source_ami_filter {
    filters = {
      name                = "ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-arm64-server-*"
      architecture        = "arm64"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    owners      = ["099720109477"] # Canonical
    most_recent = true
  }

  subnet_filter {
    filters = {
      "tag:Name" = var.subnet_name_tag
    }
    most_free = true
  }
  associate_public_ip_address = true

  # SSH only from the public IP of the machine running Packer, via a temporary SG.
  ssh_username                              = "ubuntu"
  temporary_security_group_source_public_ip = true

  # IMDSv2 only, on the build instance and on instances launched from the image.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }
  imds_support = "v2.0"

  ena_support  = true
  encrypt_boot = true

  launch_block_device_mappings {
    device_name           = "/dev/sda1"
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    delete_on_termination = true
  }

  run_tags        = merge(local.common_tags, { Name = "packer-build-wiki-js" })
  run_volume_tags = merge(local.common_tags, { Name = "packer-build-wiki-js" })

  tags = merge(local.common_tags, {
    Name          = local.ami_name
    SourceAMI     = "{{ .SourceAMI }}"
    SourceAMIName = "{{ .SourceAMIName }}"
    WikijsImage   = var.wikijs_image
  })
  snapshot_tags = merge(local.common_tags, { Name = local.ami_name })
}

build {
  sources = ["source.amazon-ebs.wikijs"]

  provisioner "ansible" {
    playbook_file = "${path.root}/../ansible/image.yml"
    user          = "ubuntu"
    use_proxy     = false

    extra_arguments = [
      "--extra-vars",
      jsonencode({
        wikijs_image   = var.wikijs_image
        postgres_image = var.postgres_image
      }),
    ]

    ansible_env_vars = ["ANSIBLE_HOST_KEY_CHECKING=False"]
  }

  # Leave nothing instance-specific behind: cloud-init state, machine-id, the
  # build's temporary SSH key and the apt cache.
  provisioner "shell" {
    inline = [
      "sudo apt-get clean",
      "sudo cloud-init clean --logs --machine-id",
      "sudo rm -f /root/.ssh/authorized_keys /home/ubuntu/.ssh/authorized_keys",
    ]
  }

  post-processor "manifest" {
    output     = "${path.root}/manifest.json"
    strip_path = true
  }
}
