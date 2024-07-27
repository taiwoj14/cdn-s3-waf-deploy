resource "aws_cloudfront_response_headers_policy" "policy" {
  name    = "cdn-security-response-headers-policy"
  comment = "Security Response headers policy for cloudfront distribution"

  security_headers_config {
    strict_transport_security {
      access_control_max_age_sec = 63072000
      include_subdomains         = true
      preload                    = true
      override                   = false
    }
    content_type_options {
      override = true
    }
    xss_protection {
      protection = true
      mode_block = true
      override   = false
    }
    referrer_policy {
      referrer_policy = "strict-origin-when-cross-origin"
      override        = false
    }
    frame_options {
      frame_option = "SAMEORIGIN"
      override     = false
    }
  }
  cors_config {
    access_control_allow_credentials = false

    access_control_allow_headers {
      items = ["*"]
    }

    access_control_allow_methods {
      items = ["GET", "POST", "HEAD", "OPTIONS", "PUT", "DELETE", "PATCH"]
    }

    access_control_allow_origins {
      items = ["*"]
    }

    origin_override = true
  }
}
