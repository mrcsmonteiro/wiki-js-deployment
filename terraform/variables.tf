variable "account_id" {
  description = "AWS account ID of the workload account, used as an allowed_account_ids guard. Set in terraform.tfvars."
  type        = string
}

variable "aws_profile" {
  description = "Named AWS CLI profile for resource provisioning (marcosms-Prod)."
  type        = string
  default     = "marcosms-prod-admin"
}

variable "alert_email" {
  description = "Email address that receives alarm notifications. Set in terraform.tfvars (not committed)."
  type        = string
}

variable "log_retention_days" {
  description = "Days to keep host logs (nginx, backup) in CloudWatch Logs."
  type        = number
  default     = 30
}

variable "pca_domain_name" {
  description = "Public name of the PCA Practice site on the same host (external health check only)."
  type        = string
  default     = "pca.marcosms.com.au"
}

variable "backup_retention_days" {
  description = "Days to keep nightly backups in the backup bucket."
  type        = number
  default     = 35
}

variable "patch_window_schedule" {
  description = "Weekly patch window, in the window's own timezone (Australia/Melbourne). Default: Sunday 02:00."
  type        = string
  default     = "cron(0 2 ? * SUN *)"
}

variable "backup_central_account_id" {
  description = "Account ID of the Control Tower central backup account (copies of the data volume backups go there). Set in terraform.tfvars."
  type        = string
}

variable "data_volume_size" {
  description = "Size in GiB of the persistent data volume (Docker data-root and the PCA app directory)."
  type        = number
  default     = 20
}

variable "db_password_parameter" {
  description = "SSM Parameter Store name of the Wiki.js database password (SecureString, created by hand)."
  type        = string
  default     = "/wiki-js/prod/db-password"
}

variable "prod_instance_type" {
  description = "Instance type for the new Wiki.js host (arm64)."
  type        = string
  default     = "t4g.small"
}

variable "wikijs_prod_ami_id" {
  description = "Packer-built image for the new Wiki.js host (packer/manifest.json). Set in terraform.tfvars."
  type        = string
}

variable "aws_region" {
  description = "The AWS region to deploy resources in."
  type        = string
  default     = "ap-southeast-2" # Sydney
}

variable "project_name" {
  description = "A name tag for your project resources."
  type        = string
  default     = "WikiJS"
}

variable "domain_name" {
  description = "Your public domain name for Wiki.js (e.g., wiki.example.com)."
  type        = string
  default     = "wiki.marcosms.com.au"
}

variable "public_hosted_zone_name" {
  description = "The name of your existing public Route 53 hosted zone (e.g., marcosms.com.au)."
  type        = string
  default     = "marcosms.com.au"
}

variable "existing_acm_certificate_arn" {
  description = "The ARN of the existing ACM certificate (us-east-1) for the domain. Set in terraform.tfvars."
  type        = string
}

variable "acm_certificate_region" {
  description = "The AWS region where your ACM certificate was issued."
  type        = string
  default     = "us-east-1" # Certificate is in us-east-1
}

variable "instance_type" {
  description = "The EC2 instance type for Wiki.js."
  type        = string
  default     = "t3.micro" # Cost-effective for low traffic
}

variable "ami_id" {
  description = "The AMI ID for Ubuntu Server 22.04 LTS in ap-southeast-2."
  type        = string
  default     = "ami-09a50a142626e358e" # Ubuntu Server 22.04 LTS (HVM), SSD Volume Type in ap-southeast-2
}

variable "key_pair_name" {
  description = "The name of your existing EC2 Key Pair for SSH access."
  type        = string
  default     = "wiki-ssh-key"
}

variable "ssh_ingress_cidrs" {
  description = "List of CIDR blocks allowed to SSH into the EC2 instance."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "vpc_cidr_block" {
  description = "The CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr_block" {
  description = "The CIDR block for the public subnet."
  type        = string
  default     = "10.0.1.0/24"
}

variable "tags" {
  description = "Extra tags merged on top of the provider default_tags. Workload tags (Environment, ManagedBy, ...) come from default_tags in providers.tf; do not repeat them here."
  type        = map(string)
  default     = {}
}


# --- Wiki.js 3 ("green") ---------------------------------------------------------

variable "prod_origin" {
  description = "Host behind the production distribution: \"legacy\" (2.x, public origin) or \"v3\" (3.x, VPC origin). Flip to \"v3\" at cutover."
  type        = string
  default     = "legacy"

  validation {
    condition     = contains(["legacy", "v3"], var.prod_origin)
    error_message = "prod_origin must be \"legacy\" or \"v3\"."
  }
}

variable "private_subnet_cidr_block" {
  description = "CIDR block of the private subnet for the Wiki.js 3 host."
  type        = string
  default     = "10.0.2.0/24"
}

variable "nat_instance_type" {
  description = "Instance type of the fck-nat NAT instance (arm64)."
  type        = string
  default     = "t4g.nano"
}

variable "v3_instance_type" {
  description = "Instance type for the Wiki.js 3 host (arm64). 4 GiB leaves room for PostgreSQL and Puppeteer."
  type        = string
  default     = "t4g.medium"
}

variable "v3_data_volume_size" {
  description = "Size in GiB of the Wiki.js 3 data volume (Docker data-root)."
  type        = number
  default     = 20
}

variable "wikijs_v3_ami_id" {
  description = "Packer-built image for the Wiki.js 3 host (packer build -var-file=v3.pkrvars.hcl). Set in terraform.tfvars."
  type        = string
}

variable "enable_v3_staging" {
  description = "Create the staging distribution, certificate and DNS name for the rehearsal. Set false after cutover."
  type        = bool
  default     = true
}

variable "v3_staging_domain_name" {
  description = "Staging name for the Wiki.js 3 host during the rehearsal."
  type        = string
  default     = "wiki-next.marcosms.com.au"
}

variable "enable_waf" {
  description = "Attach the AWS WAF web ACL to the v3 distributions (about USD 10 a month plus requests)."
  type        = bool
  default     = true
}

variable "waf_rate_limit" {
  description = "Requests per IP in any 5-minute window before AWS WAF blocks that IP."
  type        = number
  default     = 2000
}
