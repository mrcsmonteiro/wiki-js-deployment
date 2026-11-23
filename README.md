![Terransible_Wiki.js_on_EC2](Terransible_Wiki.js_on_EC2.png)

![Static Badge](https://img.shields.io/badge/OpenTofu-v1.13.9-blue) ![Static Badge](https://img.shields.io/badge/AWS_CLI-2.27.49-blue) ![Static Badge](https://img.shields.io/badge/Python-3.13.4-blue)

## Table of Contents
- [Overview](#overview)
- [Usage](#usage)

## Overview

This repository provides a comprehensive and automated solution for deploying a Wiki.js instance on AWS using OpenTofu. The infrastructure is designed to be simple and cost effective.

This deployment uses an Infrastructure as Code (IaC) approach, so the entire infrastructure can be versioned, shared, and re-used.

### OpenTofu Provisioning

The core components:

- **VPC, Subnet, and Internet Gateway**: A dedicated **Virtual Private Cloud (VPC)** isolates the Wiki.js environment. A single public subnet is created within this VPC, connected to the internet via an **Internet Gateway (IGW)**. This setup provides a secure and organized network foundation.
- **EC2 Instance & Elastic IP**: A single **EC2 (Elastic Compute Cloud)** instance serves as the Wiki.js application server. An **Elastic IP (EIP)** is associated with the instance, giving it a fixed public IP address. The instance is configured to automatically update itself on launch using `user_data`, preparing it for subsequent provisioning.
- **IAM Role**: An **IAM (Identity and Access Management) Role** is created and attached to the EC2 instance. This allows the instance to securely interact with other AWS services, specifically enabling **AWS Systems Manager (SSM)** for potential future management without the need for SSH keys.
- **Security Groups**: A **Security Group** acts as a virtual firewall for the EC2 instance. It allows inbound **HTTP (port 80)** from anywhere (CloudFront connects to the origin over HTTP), **HTTPS (port 443)** for another site served directly from the same instance, and **SSH (port 22)** for management. All outbound traffic is allowed.
- **CloudFront Distribution (CDN)**: A **CloudFront Content Delivery Network (CDN)** sits in front of the EC2 instance. It handles all incoming user requests, providing several key benefits:
  - **HTTPS Enforcement**: All traffic from users is forced to use HTTPS, and CloudFront securely handles the SSL termination using an existing AWS Certificate Manager (ACM) certificate.
  - **Geographic Latency Reduction**: It caches content closer to end-users, reducing latency.
  - **DDoS Protection**: It provides a layer of protection against denial-of-service attacks.
  - The CloudFront distribution connects to the EC2 instance using **HTTP**, simplifying the server configuration.
- **Route 53 Records**: Route 53 manages the domain routing. Two records are created:
  - An **A record** (`origin.yourdomain.com`) that points directly to the EC2 instance's Elastic IP. This is used as the origin for the CloudFront distribution.
  - An **Alias record** (`yourdomain.com`) that points to the CloudFront distribution's domain name, effectively routing all public traffic through the CDN.
- **Ansible Provisioning**: OpenTofu does not run Ansible. The earlier `null_resource` with a `local-exec` provisioner was removed, so `tofu apply` only changes AWS resources and never reconfigures the running server as a side effect. Run the playbook as a separate step (see [Usage](#usage)).
- **Outputs**: Several outputs are defined to provide useful information after deployment, such as the public IP of the EC2 instance, the CloudFront domain name, and the `ssh` command for connecting to the server.
- **Backend & Providers**: State is stored in a shared **S3 bucket** in a separate deployments account, with S3 native state locking. `backend.tf` sets only the state key; the bucket, region and profile come from `backend-prod.hcl` (copy it from `backend-prod.hcl.example`). There are two **AWS providers**: one for the main region and one for `us-east-1`, which CloudFront needs for its ACM certificate. Both use a named AWS CLI profile, an `allowed_account_ids` guard and `default_tags`, so every resource gets the same set of tags.

### Ansible Provisioning

The Ansible playbook automates the software installation and configuration on the EC2 instance. Run it separately from OpenTofu, after the AWS resources exist.

#### Key Roles of the Ansible Playbook
- **Docker & Docker Compose**: The playbook's primary function is to set up a **containerized environment** for Wiki.js. It installs **Docker** and **Docker Compose**, ensuring the `ubuntu` user has the necessary permissions to run Docker commands. This approach provides a portable and isolated environment for the application.
- **Application Deployment**: It uses **Jinja2 templates** to dynamically create a `.env` file and a `docker-compose.yml` file. These files contain sensitive information and service definitions, respectively, based on variables defined in `vars.yml`. It then uses Docker Compose to pull the Wiki.js and PostgreSQL images and run them as services. The use of the `--force-recreate` flag ensures a clean deployment and an updated application.
- **Nginx as a Reverse Proxy**: The playbook installs and configures **Nginx** to act as a reverse proxy. This allows Nginx to listen on standard **HTTP port 80** and forward requests to the Wiki.js container running on its internal port. It also handles the configuration for the custom domain name. Nginx is crucial for directing traffic from CloudFront to the correct application service.
- **Idempotency and Diagnostics**: The playbook is designed to be **idempotent**, meaning it can be run multiple times without causing unintended changes. It includes several diagnostic steps (`debug` and `shell` commands) to check the status of Docker and Nginx services, which is useful for troubleshooting.
- **Configuration**: The playbook is configured via `inventory.ini` and `vars.yml`. The `inventory.ini` file specifies the target host (the EC2 instance IP), while `vars.yml` contains key variables like domain names and database credentials.

## Usage

> Moved from Terraform to OpenTofu in November 2026. The state format is the same; see
> [docs/migration-v3.md](docs/migration-v3.md#phase-2-switch-to-opentofu) for the one-time switch.

Prerequisites: OpenTofu >= 1.13 (pinned in `.opentofu-version`), AWS CLI v2 with named profiles for the deployments account (state) and the workload account (resources).

### 1. Configure

```bash
cd terraform
cp backend-prod.hcl.example backend-prod.hcl          # set the state bucket name
cp terraform.tfvars.example terraform.tfvars          # set account_id and the ACM certificate ARN
```

Both files are git-ignored.

### 2. Plan and apply

```bash
tofu init -backend-config=backend-prod.hcl
tofu plan -out tfplan
tofu apply tfplan
rm -f tfplan
```

Review the plan before applying. Delete the plan file afterwards.

### 3. Build the server image (separate step)

The server is built from an image, not configured in place. Packer starts a temporary instance, runs the Ansible roles in `ansible/roles/` (Docker, nginx, Wiki.js compose files) and saves an arm64 AMI. Nothing secret is baked in: at boot the instance reads the database password from SSM Parameter Store.

```bash
packer init packer
packer build packer
```

Requires Packer >= 1.16 and an AWS session for the workload account.
