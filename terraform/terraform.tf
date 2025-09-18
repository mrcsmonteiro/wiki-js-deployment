terraform {
  backend "s3" {
    bucket       = "tfstate-wiki.js"
    key          = "terraform/terraform.tfstate"
    region       = "ap-southeast-2"
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