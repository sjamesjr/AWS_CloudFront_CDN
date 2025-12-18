terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ------------------------------------------------------------------------------
# NETWORKING (VPC + Subnet + IGW + Route Table)
# ------------------------------------------------------------------------------

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "elk_vpc"
  }
}

resource "aws_subnet" "main" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "${var.aws_region}a"

  tags = {
    Name = "elk_subnet"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "elk_igw"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "elk_public_rt"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.main.id
  route_table_id = aws_route_table.public.id
}

# ------------------------------------------------------------------------------
# Secure S3 Bucket (Origin)
# ------------------------------------------------------------------------------

resource "aws_s3_bucket" "origin" {
  bucket_prefix = "my_cdn_origin"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "origin" {
  bucket = aws_s3_bucket.origin.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ------------------------------------------------------------------------------
# CloudFront Distribution with OAC (Origin Access Control)
# ------------------------------------------------------------------------------

resource "aws_cloudfront_origin_access_control" "default" {
  name                              = "s3_oac"
  description                       = "Least Privilege OAC for S3"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "cdn" {
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  origin {
    domain_name              = aws_s3_bucket.origin.bucket_regional_domain_name
    origin_id                = "S3Origin"
    origin_access_control_id = aws_cloudfront_origin_access_control.default.id
  }

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3Origin"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
    minimum_protocol_version       = "TLSv1.2_2021"
  }
}

# ------------------------------------------------------------------------------
# S3 Bucket Policy (Allow Only CloudFront OAC)
# ------------------------------------------------------------------------------

resource "aws_s3_bucket_policy" "allow_cloudfront" {
  bucket = aws_s3_bucket.origin.id
  policy = data.aws_iam_policy_document.allow_cloudfront_oac.json
}

data "aws_iam_policy_document" "allow_cloudfront_oac" {
  statement {
    sid    = "AllowCloudFrontServicePrincipal"
    effect = "Allow"

    actions = [
      "s3:GetObject"
    ]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    resources = [
      "${aws_s3_bucket.origin.arn}/*"
    ]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.cdn.arn]
    }
  }
}

# ------------------------------------------------------------------------------
# ELK Stack on EC2 (Installed via User Data)
# ------------------------------------------------------------------------------

resource "aws_instance" "elk_server" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.medium"
  subnet_id              = aws_subnet.main.id
  iam_instance_profile   = aws_iam_instance_profile.elk_profile.name
  vpc_security_group_ids = [aws_security_group.elk_sg.id]

  # User Data script creates the docker-compose.yml and installs the stack
  user_data = file("${path.module}/install_elk.sh")

  tags = {
    Name = "ELK_Stack_Server"
  }
}

# ------------------------------------------------------------------------------
# Security Group - Least Privilege
# ------------------------------------------------------------------------------

resource "aws_security_group" "elk_sg" {
  name        = "elk-sg"
  description = "Security group for ELK stack"
  vpc_id      = aws_vpc.main.id

  # Allow SSH only from Admin IP (Replace with your IP/VPN)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_ip]
  }

  # Allow Kibana (5601) only from Admin IP
  ingress {
    from_port   = 5601
    to_port     = 5601
    protocol    = "tcp"
    cidr_blocks = [var.admin_ip]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ------------------------------------------------------------------------------
# IAM Role for EC2 (Session Manager support - No SSH keys needed)
# ------------------------------------------------------------------------------

resource "aws_iam_role" "elk_role" {
  name = "elk_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_policy" {
  role       = aws_iam_role.elk_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "elk_profile" {
  name = "elk_profile"
  role = aws_iam_role.elk_role.name
}

# ------------------------------------------------------------------------------
# Data source for Ubuntu AMI
# ------------------------------------------------------------------------------

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}
