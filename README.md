![Terransible_Wiki.js_on_EC2](Terransible_Wiki.js_on_EC2.png)

![Static Badge](https://img.shields.io/badge/Terraform-v1.13.2-blue) ![Static Badge](https://img.shields.io/badge/AWS_CLI-2.27.49-blue) ![Static Badge](https://img.shields.io/badge/Python-3.13.4-blue)

## Table of Contents
- [Overview](#overview)
- [Usage](#usage)

## Overview

This repository provides a comprehensive and automated solution for deploying a Wiki.js instance on AWS using Terraform. The infrastructure is designed to be simple and cost effective.

This deployment uses an Infrastructure as Code (IaC) approach, so the entire infrastructure can be versioned, shared, and re-used.

### Architecture

The core components of this infrastructure work together to create a robust setup:

- **VPC, Subnet, and Internet Gateway**: A dedicated **Virtual Private Cloud (VPC)** isolates the Wiki.js environment. A single public subnet is created within this VPC, connected to the internet via an **Internet Gateway (IGW)**. This setup provides a secure and organized network foundation.
- **EC2 Instance & Elastic IP**: A single **EC2 (Elastic Compute Cloud)** instance serves as the Wiki.js application server. An **Elastic IP (EIP)** is associated with the instance, giving it a fixed public IP address. The instance is configured to automatically update itself on launch using `user_data`, preparing it for subsequent provisioning.
- **IAM Role**: An **IAM (Identity and Access Management) Role** is created and attached to the EC2 instance. This allows the instance to securely interact with other AWS services, specifically enabling **AWS Systems Manager (SSM)** for potential future management without the need for SSH keys.
- **Security Groups**: A **Security Group** acts as a virtual firewall for the EC2 instance, allowing only necessary traffic. It permits inbound **HTTP (port 80)** traffic from anywhere (for the CloudFront distribution to connect) and **SSH (port 22)** access for management. All outbound traffic is allowed.
- **CloudFront Distribution (CDN)**: A **CloudFront Content Delivery Network (CDN)** sits in front of the EC2 instance. It handles all incoming user requests, providing several key benefits:
 - **HTTPS Enforcement**: All traffic from users is forced to use HTTPS, and CloudFront securely handles the SSL termination using an existing AWS Certificate Manager (ACM) certificate.
 - **Geographic Latency Reduction**: It caches content closer to end-users, reducing latency.
 - **DDoS Protection**: It provides a layer of protection against denial-of-service attacks.
 - The CloudFront distribution connects to the EC2 instance using **HTTP**, simplifying the server configuration.
- **Route 53 Records**: Route 53 manages the domain routing. Two records are created:
 - An **A record** (`origin.yourdomain.com`) that points directly to the EC2 instance's Elastic IP. This is used as the origin for the CloudFront distribution.
 - An **Alias record** (`yourdomain.com`) that points to the CloudFront distribution's domain name, effectively routing all public traffic through the CDN.
- **Ansible Provisioning**: A `null_resource` in Terraform executes an **Ansible playbook** on the newly created EC2 instance. This is a crucial step for installing and configuring the Wiki.js application, its dependencies, and the database. The `null_resource` uses a `local-exec` provisioner to run Ansible from your local machine. It has a `depends_on` rule to ensure it only runs after the EC2 instance is available. A `triggers` block is also used to hash the content of the Ansible playbooks, forcing a re-run if any changes are made.
- **Outputs**: Several outputs are defined to provide useful information after deployment, such as the public IP of the EC2 instance, the CloudFront domain name, and the `ssh` command for connecting to the server.
- **Backend & Providers**: Terraform's state is stored remotely in an **S3 bucket**, enabling collaboration and preventing data loss. The configuration uses two **AWS providers**, one for the primary region of deployment and a second for `us-east-1`, which is required for creating CloudFront distributions with ACM certificates.