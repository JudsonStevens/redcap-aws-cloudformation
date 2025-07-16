# ACM Certificate (if enabled)
resource "aws_acm_certificate" "main" {
  count = var.use_acm ? 1 : 0

  domain_name       = "${var.domain_name}.${var.hosted_zone_name}"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(var.tags, {
    Name = "${var.domain_name}.${var.hosted_zone_name}"
  })
}

# Route53 record for ACM certificate validation
resource "aws_route53_record" "cert_validation" {
  for_each = var.use_acm ? {
    for dvo in aws_acm_certificate.main[0].domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  } : {}

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = var.hosted_zone_id
}

# ACM certificate validation
resource "aws_acm_certificate_validation" "main" {
  count = var.use_acm ? 1 : 0

  certificate_arn         = aws_acm_certificate.main[0].arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]

  timeouts {
    create = "10m"
  }
}

# Route53 A record for ALB
resource "aws_route53_record" "main" {
  zone_id = var.hosted_zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = var.alb_dns_name
    zone_id                = var.alb_zone_id
    evaluate_target_health = true
  }

  depends_on = [aws_acm_certificate_validation.main]
}

# Route53 AAAA record for ALB (IPv6 support)
resource "aws_route53_record" "ipv6" {
  zone_id = var.hosted_zone_id
  name    = var.domain_name
  type    = "AAAA"

  alias {
    name                   = var.alb_dns_name
    zone_id                = var.alb_zone_id
    evaluate_target_health = true
  }

  depends_on = [aws_acm_certificate_validation.main]
}

# Route53 health check for monitoring
resource "aws_route53_health_check" "main" {
  fqdn                            = "${var.domain_name}.${var.hosted_zone_name}"
  port                            = var.use_acm ? 443 : 80
  type                            = var.use_acm ? "HTTPS" : "HTTP"
  resource_path                   = "/redcap/"
  failure_threshold               = "3"
  request_interval                = "30"
  cloudwatch_alarm_region         = data.aws_region.current.name
  cloudwatch_alarm_name           = "${var.domain_name}-health-check"
  insufficient_data_health_status = "Failure"

  tags = merge(var.tags, {
    Name = "${var.domain_name} Health Check"
  })
}

# CloudWatch alarm for Route53 health check
resource "aws_cloudwatch_metric_alarm" "health_check" {
  alarm_name          = "${var.domain_name}-health-check-alarm"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "HealthCheckStatus"
  namespace           = "AWS/Route53"
  period              = "60"
  statistic           = "Minimum"
  threshold           = "1"
  alarm_description   = "This metric monitors health check status"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    HealthCheckId = aws_route53_health_check.main.id
  }

  tags = var.tags
}

# SNS Topic for DNS/health check alerts
resource "aws_sns_topic" "alerts" {
  name = "${var.domain_name}-dns-alerts"

  tags = var.tags
}

# Data source for current region
data "aws_region" "current" {}