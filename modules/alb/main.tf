resource "aws_lb" "alb" {
  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.alb_sg_id]
  subnets            = var.subnet_ids
}

resource "aws_lb_target_group" "tg" {
  name     = "${var.project_name}-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = var.vpc_id
  health_check {
  path = "/health.html"
    port = "80"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"
  # Block direct access by default; allow only via host-header rule below
  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Forbidden"
      status_code  = "403"
    }
  }
}

resource "aws_acm_certificate" "cert" {
  count = var.domain_name == "" ? 0 : 1
  # Issue certificate for the www subdomain only
  domain_name       = "www.${var.domain_name}"
  validation_method = "DNS"
}

resource "aws_route53_record" "cert_validation" {
  for_each = var.domain_name == "" ? {} : { for o in aws_acm_certificate.cert[0].domain_validation_options : o.domain_name => o }
  zone_id = var.hosted_zone_id
  name    = each.value.resource_record_name
  type    = each.value.resource_record_type
  records = [each.value.resource_record_value]
  ttl     = 60
}

resource "aws_acm_certificate_validation" "cert_validation" {
  count = var.domain_name == "" ? 0 : 1
  certificate_arn = aws_acm_certificate.cert[0].arn
  validation_record_fqdns = [for r in values(aws_route53_record.cert_validation) : r.fqdn]
}

resource "aws_lb_listener" "https" {
  count = var.domain_name == "" ? 0 : 1
  load_balancer_arn = aws_lb.alb.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = aws_acm_certificate_validation.cert_validation[0].certificate_arn
  # Block direct access by default; allow only via host-header rule below
  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Forbidden"
      status_code  = "403"
    }
  }
  depends_on = [aws_acm_certificate_validation.cert_validation]
}

# Allow only requests for our domain on HTTP: redirect to HTTPS
resource "aws_lb_listener_rule" "http_redirect_to_https" {
  count        = var.domain_name == "" ? 0 : 1
  listener_arn = aws_lb_listener.http.arn
  priority     = 1

  action {
    type = "redirect"
    redirect {
      # Preserve the original host (should be www.<domain>)
      host        = "#{host}"
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }

  condition {
    host_header {
      values = ["www.${var.domain_name}"]
    }
  }
}

# Allow only requests for our domain on HTTPS: forward to target group
resource "aws_lb_listener_rule" "https_forward_to_tg" {
  count        = var.domain_name == "" ? 0 : 1
  listener_arn = aws_lb_listener.https[0].arn
  priority     = 1

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg.arn
  }

  condition {
    host_header {
      values = ["www.${var.domain_name}"]
    }
  }
}

resource "aws_route53_record" "www" {
  count = var.domain_name == "" ? 0 : 1
  zone_id = var.hosted_zone_id
  # Create only the www record pointing to ALB
  name    = "www"
  type    = "A"
  alias {
    name                   = aws_lb.alb.dns_name
    zone_id                = aws_lb.alb.zone_id
    evaluate_target_health = true
  }
}

output "alb_dns_name" { value = aws_lb.alb.dns_name }
output "tg_arn" { value = aws_lb_target_group.tg.arn }
output "tg_arn_suffix" { value = aws_lb_target_group.tg.arn_suffix }
output "alb_arn_suffix" { value = aws_lb.alb.arn_suffix }
