terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "var.aws_region"
}

# Secure S3 Bucket (Origin)

resource "aws_s3_bucket" "origin" {
  bucket_prefix = "my_cdn_origin"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "origin" {
  bucket = aws_s3_bucket.origin.id

  block_public_acls = true
  block_public_policy = true
  ignore_public_acls = true
  restrict_public_buckets = true
}

# CloudFront Distribution with OAC (Origin Access Control)

resource "aws_cloudfront_origin_access_control" "default" {
  name = "s3_oac"
  description = "Least Privilege OAC for S3"
  origin_access_control_origin_type = "s3"
  signing_behavior = "always"
  signing_protocol = "sigv4"
}

resource "aws_cloudfront_distribution" "cdn" {
  enabled = true
  is_ipv6_enabled = true
  default_root_object = "index.html"

  origin {
    domain_name = aws_s3_bucket.origin.bucket_regional_domain_name
    origin_id   = "S3Origin"
    origin_access_control_id = aws_cloudfront_origin_access_control.default.id
  }

  default_cache_behavior {
    allowed_methods = ["GET", "HEAD"]
    cached_methods = ["GET", "HEAD"]
    target_origin_id       = "S3Origin"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
    viewer_protocol_policy = "redirect_to_https"
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

# S3 Bucket Policy (Allow Only CloudFront OAC)

resource "aws_s3_bucket_policy" "allow_cloudfront" {
  bucket = aws_s3_bucket.origin.id
  policy = data.aws_iam_policy_document.allow_cloudfront_oac.json
}

data "aws_iam_policy_document" "allow_cloudfront_oac" {
  statement {
    sid = "AllowCloudFrontServicePrincipal"
    effect = "Allow"
    actions = [
      "s3:GetObject"
    ]
    principals {
      type = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }
    resources = [
      "${aws_s3_bucket.origin.arn}/*"
    ]
    condition {
      test     = "StringEquals"
      values = [aws_cloudfront_distribution.cdn.arn]
      variable = "AWS:SourceArn"
    }
  }
}

# ELK Stack on EC2 (Installed via User Data)
resource "aws_instance" "elk_server" {
  ami           = data.awd_ami.ubuntu.id
  instance_type = "t3.medium" #Minimum for ELK
  subnet_id = var.subnet.id

  iam_instance_profile = aws_iam_instance_profile.elk_profile.name
  vpc_security_group_ids = [aws_security_group.elk_sg.id]

  # User Data script create the docker-compose.yml and installs the stack
  user_data = file("${path.module}/install_elk.sh")

  tags = {
    Name = "ELK_Stack_Server"
  }
}

#