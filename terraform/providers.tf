# Main region (ap-southeast-2)
provider "aws" {
  region = var.aws_region
}

# Separate provider for the ACM certificate region (us-east-1)
provider "aws" {
  alias  = "acm_region"
  region = var.acm_certificate_region
}