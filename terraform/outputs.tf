output "ec2_public_ip" {
  description = "The public IP address of the Wiki.js EC2 instance."
  value       = aws_eip.wikijs_eip.public_ip
}

output "cloudfront_domain_name" {
  description = "The domain name of the CloudFront distribution."
  value       = aws_cloudfront_distribution.wikijs_cdn.domain_name
}

output "public_domain_name" {
  description = "The public domain name configured for Wiki.js."
  value       = var.domain_name
}

output "ssh_command" {
  description = "SSH command to connect to the EC2 instance."
  value       = "ssh -i ~/.ssh/${var.key_pair_name}.pem ubuntu@${aws_eip.wikijs_eip.public_ip}"
}
