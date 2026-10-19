locals {
  default_tags = {
    ManagedBy   = "terraform"
    Repository  = "wiki-js-deployment"
    Stack       = "aws/marcosms-prod/wikijs"
    Environment = "prod"
    Application = "wiki-js"
    Owner       = "marcos"
    CostCentre  = "personal"
  }
}

# Main region (ap-southeast-2)
provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile

  allowed_account_ids = [var.account_id]

  default_tags {
    tags = local.default_tags
  }
}

# Separate provider for the ACM certificate region (us-east-1), used by CloudFront.
provider "aws" {
  alias   = "acm_region"
  region  = var.acm_certificate_region
  profile = var.aws_profile

  allowed_account_ids = [var.account_id]

  default_tags {
    tags = local.default_tags
  }
}
