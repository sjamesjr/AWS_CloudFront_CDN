variable "aws_region" {
  default = "eu-central-1"
}

variable "vpc_id" {
  description = "VPC ID where ELK server will be deployed"
}

variable "subnet_id" {
  description = "Subnet ID for ELK server"
}

variable "admin_ip" {
  description = "Your IP address (CIDR format) for SSH/Kibana access"
}