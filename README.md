# AWS CloudFront CDN & ELK Stack with Terraform

This project automates the deployment of a secure, high-performance content delivery network (CDN) using **AWS CloudFront** backed by a private **S3 origin**, alongside an **ELK Stack** (Elasticsearch, Logstash, Kibana) for log monitoring deployed on an EC2 instance.

Infrastructure is defined as code (IaC) using **Terraform**, adhering to "least privilege" security best practices.

## 🏗 Architecture

1.  **CloudFront CDN**:
    *   Serves content globally with low latency.
    *   Uses **Origin Access Control (OAC)** to securely authenticate with S3 (replacing legacy OAI).
    *   Enforces HTTPS.
2.  **S3 Origin**:
    *   Completely private bucket (no public access).
    *   Bucket policy strictly allows access only from the specific CloudFront distribution.
3.  **ELK Stack Server**:
    *   **EC2 Instance** (t3.medium) running Ubuntu.
    *   **Docker & Docker Compose** installed automatically via User Data.
    *   **IAM Role**: Uses `AmazonSSMManagedInstanceCore` for secure Session Manager access (no SSH keys required).
    *   **Security Group**: Restricts port 5601 (Kibana) and 22 (SSH) to a specific Admin IP only.

## 📂 Project Structure

```text
.
├── main.tf                # Main Terraform configuration (Resources)
├── variables.tf           # Input variables definition
├── install_elk.sh         # User Data script to install Docker & ELK
├── .github/
│   └── workflows/
│       ├── terraform-check.yml  # CI: Checks formatting and validation
│       └── deploy.yml           # CD: Deploys infrastructure on push
└── README.md
```

## 🚀 Quick Start

### Prerequisites
*   [Terraform](https://developer.hashicorp.com/terraform/downloads) installed (v1.0+).
*   AWS CLI configured with appropriate credentials.
*   An existing VPC and Subnet ID where the EC2 instance will reside.

### 1. Clone & Initialize
```bash
git clone <repository-url>
cd <repository-folder>
terraform init
```

### 2. Configure Variables
Create a `terraform.tfvars` file to store your specific settings (do not commit this file to Git):

```hcl
# terraform.tfvars
aws_region = "us-east-1"
vpc_id     = "vpc-xxxxxxxx"
subnet_id  = "subnet-xxxxxxxx"
admin_ip   = "192.168.1.100/32" # Replace with your public IP
```

### 3. Deploy
Review the plan and apply changes:
```bash
terraform plan
terraform apply
```

### 4. Accessing Services
*   **CloudFront**: The output `cloudfront_domain_name` (if added to outputs) or console will show your distribution URL (e.g., `d1234.cloudfront.net`).
*   **Kibana**: Access via `http://<EC2-Public-IP>:5601`.
    *   *Note: Ensure your current IP matches the `admin_ip` variable.*

## ⚙️ CI/CD Pipelines (GitHub Actions)

This project includes two workflows:

1.  **Terraform Check** (`terraform-check.yml`):
    *   Runs on Pull Requests.
    *   Checks for proper formatting (`terraform fmt`).
    *   Validates syntax (`terraform validate`).

2.  **Deploy Infrastructure** (`deploy.yml`):
    *   Runs on pushes to `main`.
    *   Automatically applies Terraform changes.
    *   **Required Secrets**: Go to **Settings > Secrets and variables > Actions** and add:
        *   `AWS_ACCESS_KEY_ID`
        *   `AWS_SECRET_ACCESS_KEY`
        *   `VPC_ID`
        *   `SUBNET_ID`
        *   `ADMIN_IP`

## 🔒 Security Highlights

*   **OAC (Origin Access Control)**: We use the modern AWS standard for S3-CloudFront security. The S3 bucket policy is generated dynamically to trust *only* the specific CloudFront ARN.
*   **No Hardcoded SSH Keys**: The EC2 instance does not use key pairs. Management is done via AWS Systems Manager (SSM) or by allowing SSH explicitly from a trusted IP.
*   **Restricted Ingress**: The ELK Security Group blocks all traffic by default, opening only necessary ports to the administrator's IP.

## 📝 Configuration Files

### `install_elk.sh`
This script runs once on instance boot. It:
1.  Installs Docker Engine.
2.  Writes a `docker-compose.yml` to `/opt/elk`.
3.  Starts the Elasticsearch, Logstash, and Kibana containers.

To modify the ELK version or configuration, edit the heredoc content inside `install_elk.sh` before deployment.
