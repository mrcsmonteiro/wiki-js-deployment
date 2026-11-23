terraform {
  # OpenTofu (CNCF). Pinned for local use in /.opentofu-version.
  required_version = ">= 1.13.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0, < 7.0"
    }
  }
}
