provider "aws" {
  region = "us-east-1" # ACM certificates for CloudFront must be in us-east-1
}

variable "domain_name" {
  description = "The domain name to use for the website"
  type        = string
  default     = "rekeyole.com"
}

variable "subdomain_name" {
  description = "The subdomain name to use for the website (e.g., www)"
  type        = string
  default     = "test2"
}

data "aws_route53_zone" "selected" {
  name         = var.domain_name
  private_zone = false
}

resource "aws_s3_bucket" "website_bucket" {
  bucket = "${var.subdomain_name}.${var.domain_name}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "website_bucket_block" {
  bucket = aws_s3_bucket.website_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}


resource "aws_s3_bucket_website_configuration" "website_bucket_config" {
  bucket = aws_s3_bucket.website_bucket.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "error.html"
  }
}


resource "aws_s3_bucket_policy" "website_policy" {
  bucket = aws_s3_bucket.website_bucket.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect    = "Allow",
        Principal : {
                "AWS": aws_cloudfront_origin_access_identity.origin_access_identity.iam_arn   
                 },
        Action    = "s3:GetObject",
        Resource  : [
            "${aws_s3_bucket.website_bucket.arn}",
           "${aws_s3_bucket.website_bucket.arn}/*"]
      }
    ]
  })
}

resource "aws_acm_certificate" "cert" {
  domain_name       = var.domain_name
  validation_method = "DNS"
    subject_alternative_names = ["${var.subdomain_name}.${var.domain_name}"]
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.cert.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id = data.aws_route53_zone.selected.zone_id
  name    = each.value.name
  type    = each.value.type
  records = [each.value.record]
  ttl     = 60
}

resource "aws_acm_certificate_validation" "cert_validation" {
  certificate_arn         = aws_acm_certificate.cert.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}

resource "aws_cloudfront_distribution" "website_distribution" {
  origin {
    domain_name = "${aws_s3_bucket.website_bucket.bucket}.s3.amazonaws.com"
    origin_id   = "S3-${aws_s3_bucket.website_bucket.bucket}"

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.origin_access_identity.cloudfront_access_identity_path
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "Static website hosting with S3 and CloudFront"
  default_root_object = "index.html"

  aliases = [
    "${var.subdomain_name}.${var.domain_name}"
  ]

  viewer_certificate {
    acm_certificate_arn            = aws_acm_certificate.cert.arn
    ssl_support_method             = "sni-only"
    minimum_protocol_version       = "TLSv1.2_2021"
  }

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-${aws_s3_bucket.website_bucket.bucket}"
    response_headers_policy_id = aws_cloudfront_response_headers_policy.policy.id  # Attach the response headers policy
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

#  restrictions {
#    geo_restriction {
#      restriction_type = "whitelist"
#      locations        = ["US", "GB"]
#    }
#  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  price_class = "PriceClass_100"

  web_acl_id = var.enable_waf ? aws_wafv2_web_acl.waf[0].arn : null
  depends_on = [aws_wafv2_web_acl.waf]
}

resource "aws_route53_record" "subdomain" {
  zone_id = data.aws_route53_zone.selected.zone_id
  name    = "${var.subdomain_name}.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.website_distribution.domain_name
    zone_id                = aws_cloudfront_distribution.website_distribution.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_cloudfront_origin_access_identity" "origin_access_identity" {
  comment = "Origin Access Identity for S3 website bucket"
}
