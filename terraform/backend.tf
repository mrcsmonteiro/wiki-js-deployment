# Bucket, region, profile and locking come from backend-prod.hcl (a mirror of
# cloud-platform/aws/backend-prod.hcl):
#   terraform init -backend-config=backend-prod.hcl
terraform {
  backend "s3" {
    key = "wiki-js-deployment/aws/marcosms-prod/wikijs/terraform.tfstate"
  }
}
