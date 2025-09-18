![Terransible_Wiki.js_on_EC2](Terransible_Wiki.js_on_EC2.png)

![Static Badge](https://img.shields.io/badge/Terraform-v1.13.2-blue) ![Static Badge](https://img.shields.io/badge/AWS_CLI-2.27.49-blue) ![Static Badge](https://img.shields.io/badge/Python-3.13.4-blue)

## Table of Contents
- [Overview](#overview)

## Overview

This repository provides a comprehensive and automated solution for deploying a Wiki.js instance on AWS using Terraform. The infrastructure is designed to be simple and cost effective.

This deployment uses an Infrastructure as Code (IaC) approach, so the entire infrastructure can be versioned, shared, and re-used.

### Terraform Provisioning

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

### Ansible Provisioning

The Ansible playbook automates the software installation and configuration on the EC2 instance. It is the final step in the deployment process, following the creation of all AWS resources by Terraform.

#### Key Roles of the Ansible Playbook
- **Docker & Docker Compose**: The playbook's primary function is to set up a **containerized environment** for Wiki.js. It installs **Docker** and **Docker Compose**, ensuring the `ubuntu` user has the necessary permissions to run Docker commands. This approach provides a portable and isolated environment for the application.
- **Application Deployment**: It uses **Jinja2 templates** to dynamically create a `.env` file and a `docker-compose.yml` file. These files contain sensitive information and service definitions, respectively, based on variables defined in `vars.yml`. It then uses Docker Compose to pull the Wiki.js and PostgreSQL images and run them as services. The use of the `--force-recreate` flag ensures a clean deployment and an updated application.
- **Nginx as a Reverse Proxy**: The playbook installs and configures **Nginx** to act as a reverse proxy. This allows Nginx to listen on standard **HTTP port 80** and forward requests to the Wiki.js container running on its internal port. It also handles the configuration for the custom domain name. Nginx is crucial for directing traffic from CloudFront to the correct application service.
- **Idempotency and Diagnostics**: The playbook is designed to be **idempotent**, meaning it can be run multiple times without causing unintended changes. It includes several diagnostic steps (`debug` and `shell` commands) to check the status of Docker and Nginx services, which is useful for troubleshooting.
- **Configuration**: The playbook is configured via `inventory.ini` and `vars.yml`. The `inventory.ini` file specifies the target host (the EC2 instance IP), while `vars.yml` contains key variables like domain names and database credentials.