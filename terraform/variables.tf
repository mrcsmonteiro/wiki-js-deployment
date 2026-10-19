variable "account_id" {
  description = "AWS account ID of the workload account, used as an allowed_account_ids guard. Set in terraform.tfvars."
  type        = string
}

variable "aws_profile" {
  description = "Named AWS CLI profile for resource provisioning (marcosms-Prod)."
  type        = string
  default     = "marcosms-prod-admin"
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
  description = "A map of tags to apply to all resources."
  type        = map(string)
  default = {
    Project     = "WikiJS"
    Environment = "Production"
    ManagedBy   = "Terraform"
  }
}

