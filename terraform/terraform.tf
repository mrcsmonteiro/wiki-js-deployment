terraform {
  backend "s3" {
    bucket       = "tfstate-wiki.js"
    key          = "terraform/terraform.tfstate"
    region       = var.aws_region
    use_lockfile = true
    encrypt      = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.13.0"
    }
  }
}