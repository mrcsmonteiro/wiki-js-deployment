# Monitoring and alarms for the Wiki.js host (and PCA, which shares it).
#
# Metrics:
#   AWS/EC2     status checks, CPU credit balance (default metrics)
#   CWAgent     memory, swap and disk used % (CloudWatch agent, ansible/roles/monitoring)
#   WikiJsProd  AppUp per app (probe timer every 5 min) and BackupSucceeded (nightly backup)
#   AWS/Route53 HealthCheckStatus for both public URLs (us-east-1 only)
# Logs: nginx access/error logs for both sites and the backup log (30 days).
#
# Alarms notify on ALARM and on OK. Route 53 health check metrics exist only in
# us-east-1, so those alarms and their topic live there (provider aws.acm_region).

locals {
  metric_namespace = "WikiJsProd"
  alarm_prefix     = "wiki-js-prod"

  log_groups = {
    wiki_access = "/wiki-js-prod/nginx/wiki-access"
    wiki_error  = "/wiki-js-prod/nginx/wiki-error"
    pca_access  = "/wiki-js-prod/nginx/pca-access"
    pca_error   = "/wiki-js-prod/nginx/pca-error"
    backup      = "/wiki-js-prod/backup"
  }

  health_checks = {
    wiki = { fqdn = var.domain_name, path = "/" }
    pca  = { fqdn = var.pca_domain_name, path = "/healthz" }
  }
}

# --- Notifications -------------------------------------------------------------

data "aws_iam_policy_document" "alerts_topic" {
  statement {
    sid       = "AllowAlarmsAndEventsToPublish"
    actions   = ["sns:Publish"]
    resources = ["*"] # this topic (the policy is attached to it)

    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com", "events.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.account_id]
    }
  }
}

resource "aws_sns_topic" "alerts" {
  name = "${local.alarm_prefix}-alerts"
  tags = { Name = "${local.alarm_prefix}-alerts" }
}

resource "aws_sns_topic_policy" "alerts" {
  arn    = aws_sns_topic.alerts.arn
  policy = data.aws_iam_policy_document.alerts_topic.json
}

resource "aws_sns_topic_subscription" "alerts_email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_sns_topic" "alerts_us_east_1" {
  provider = aws.acm_region
  name     = "${local.alarm_prefix}-alerts"
  tags     = { Name = "${local.alarm_prefix}-alerts" }
}

resource "aws_sns_topic_policy" "alerts_us_east_1" {
  provider = aws.acm_region
  arn      = aws_sns_topic.alerts_us_east_1.arn
  policy   = data.aws_iam_policy_document.alerts_topic.json
}

resource "aws_sns_topic_subscription" "alerts_email_us_east_1" {
  provider  = aws.acm_region
  topic_arn = aws_sns_topic.alerts_us_east_1.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# --- Agent permissions and log groups --------------------------------------------

resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  role       = aws_iam_role.ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_cloudwatch_log_group" "host" {
  for_each = local.log_groups

  name              = each.value
  retention_in_days = var.log_retention_days
  tags              = { Name = each.value }
}

# --- Host alarms (ap-southeast-2) --------------------------------------------------

# A failed system status check means the underlying hardware; EC2 recovers the
# instance onto healthy hardware (same ID, IP, EBS volumes).
resource "aws_cloudwatch_metric_alarm" "system_status" {
  alarm_name          = "${local.alarm_prefix}-system-status-check"
  alarm_description   = "System status check failed; EC2 auto-recovery triggered."
  namespace           = "AWS/EC2"
  metric_name         = "StatusCheckFailed_System"
  dimensions          = { InstanceId = aws_instance.wikijs_prod.id }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = 1
  alarm_actions       = [aws_sns_topic.alerts.arn, "arn:aws:automate:${var.aws_region}:ec2:recover"]
  ok_actions          = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "instance_status" {
  alarm_name          = "${local.alarm_prefix}-instance-status-check"
  alarm_description   = "Instance status check failed (OS unreachable: kernel, memory, network config)."
  namespace           = "AWS/EC2"
  metric_name         = "StatusCheckFailed_Instance"
  dimensions          = { InstanceId = aws_instance.wikijs_prod.id }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 3
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = 1
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
}

# Standard credits: when the balance runs out, the CPU is throttled to baseline.
resource "aws_cloudwatch_metric_alarm" "cpu_credits" {
  alarm_name          = "${local.alarm_prefix}-cpu-credits-low"
  alarm_description   = "CPU credit balance low; the instance will be throttled to its baseline."
  namespace           = "AWS/EC2"
  metric_name         = "CPUCreditBalance"
  dimensions          = { InstanceId = aws_instance.wikijs_prod.id }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 3
  comparison_operator = "LessThanThreshold"
  threshold           = 30
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
}

# Missing data counts as breaching: no memory metric means the agent has stopped.
resource "aws_cloudwatch_metric_alarm" "memory" {
  alarm_name          = "${local.alarm_prefix}-memory-high"
  alarm_description   = "Memory used above 90% for 15 minutes, or the CloudWatch agent stopped reporting."
  namespace           = "CWAgent"
  metric_name         = "mem_used_percent"
  dimensions          = { InstanceId = aws_instance.wikijs_prod.id }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 3
  comparison_operator = "GreaterThanThreshold"
  threshold           = 90
  treat_missing_data  = "breaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
}

# A process that does not reap its children (Wiki.js did, before init: true)
# leaves zombies that each hold a PID until the PID space runs out.
resource "aws_cloudwatch_metric_alarm" "zombies" {
  alarm_name          = "${local.alarm_prefix}-zombie-processes"
  alarm_description   = "More than 50 zombie processes: a process is not reaping its children (check init: true in the compose files)."
  namespace           = "CWAgent"
  metric_name         = "processes_zombies"
  dimensions          = { InstanceId = aws_instance.wikijs_prod.id }
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 2
  comparison_operator = "GreaterThanThreshold"
  threshold           = 50
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "disk" {
  for_each = {
    root = { path = "/", threshold = 85 }
    data = { path = "/data", threshold = 80 }
  }

  alarm_name          = "${local.alarm_prefix}-disk-${each.key}-high"
  alarm_description   = "Disk ${each.value.path} above ${each.value.threshold}% used."
  namespace           = "CWAgent"
  metric_name         = "disk_used_percent"
  dimensions          = { InstanceId = aws_instance.wikijs_prod.id, path = each.value.path, fstype = "ext4" }
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 2
  comparison_operator = "GreaterThanThreshold"
  threshold           = each.value.threshold
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
}

# Probe from inside the host every 5 minutes; down for 10 minutes, or no probe
# data at all, raises the alarm.
resource "aws_cloudwatch_metric_alarm" "app_up" {
  for_each = toset(["wikijs", "pca"])

  alarm_name          = "${local.alarm_prefix}-${each.key}-down"
  alarm_description   = "${each.key} failed its local health probe for 10 minutes (or the probe stopped)."
  namespace           = local.metric_namespace
  metric_name         = "AppUp"
  dimensions          = { App = each.key }
  statistic           = "Minimum"
  period              = 300
  evaluation_periods  = 2
  comparison_operator = "LessThanThreshold"
  threshold           = 1
  treat_missing_data  = "breaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
}

# The nightly backup pushes BackupSucceeded = 1 only after both uploads succeed.
# Alarm when there has been no success for 26 consecutive hours.
resource "aws_cloudwatch_metric_alarm" "backup" {
  alarm_name          = "${local.alarm_prefix}-backup-missing"
  alarm_description   = "No successful nightly backup (Wiki.js and PCA to S3) in 26 hours."
  namespace           = local.metric_namespace
  metric_name         = "BackupSucceeded"
  statistic           = "Sum"
  period              = 3600
  evaluation_periods  = 26
  datapoints_to_alarm = 26
  comparison_operator = "LessThanThreshold"
  threshold           = 1
  treat_missing_data  = "breaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
}

# --- Patch window failures ---------------------------------------------------------

resource "aws_cloudwatch_event_rule" "patch_failed" {
  name        = "${local.alarm_prefix}-patch-window-failed"
  description = "The weekly patch maintenance window failed or timed out."

  event_pattern = jsonencode({
    source        = ["aws.ssm"]
    "detail-type" = ["Maintenance Window Execution State-change Notification"]
    detail = {
      "window-id" = [aws_ssm_maintenance_window.patching.id]
      status      = ["FAILED", "TIMED_OUT"]
    }
  })
}

resource "aws_cloudwatch_event_target" "patch_failed" {
  rule = aws_cloudwatch_event_rule.patch_failed.name
  arn  = aws_sns_topic.alerts.arn
}

# --- External checks (Route 53, us-east-1) -----------------------------------------

resource "aws_route53_health_check" "site" {
  for_each = local.health_checks

  fqdn              = each.value.fqdn
  port              = 443
  type              = "HTTPS"
  resource_path     = each.value.path
  request_interval  = 30
  failure_threshold = 3

  tags = { Name = "${local.alarm_prefix}-${each.key}" }
}

resource "aws_cloudwatch_metric_alarm" "site_health" {
  for_each = local.health_checks
  provider = aws.acm_region

  alarm_name          = "${local.alarm_prefix}-${each.key}-unreachable"
  alarm_description   = "https://${each.value.fqdn}${each.value.path} failed Route 53 health checks for 3 minutes."
  namespace           = "AWS/Route53"
  metric_name         = "HealthCheckStatus"
  dimensions          = { HealthCheckId = aws_route53_health_check.site[each.key].id }
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = 3
  comparison_operator = "LessThanThreshold"
  threshold           = 1
  alarm_actions       = [aws_sns_topic.alerts_us_east_1.arn]
  ok_actions          = [aws_sns_topic.alerts_us_east_1.arn]
}

# --- Dashboard ------------------------------------------------------------------

resource "aws_cloudwatch_dashboard" "host" {
  dashboard_name = local.alarm_prefix

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric", x = 0, y = 0, width = 12, height = 6
        properties = {
          title = "App health (1 = up)", region = var.aws_region, view = "timeSeries", stat = "Minimum", period = 300
          yAxis = { left = { min = 0, max = 1 } }
          metrics = [
            [local.metric_namespace, "AppUp", "App", "wikijs"],
            [local.metric_namespace, "AppUp", "App", "pca"],
          ]
        }
      },
      {
        type = "metric", x = 12, y = 0, width = 12, height = 6
        properties = {
          title   = "Public URLs (Route 53 health checks)", region = "us-east-1", view = "timeSeries", stat = "Minimum", period = 60
          yAxis   = { left = { min = 0, max = 1 } }
          metrics = [for k, hc in aws_route53_health_check.site : ["AWS/Route53", "HealthCheckStatus", "HealthCheckId", hc.id, { label = k }]]
        }
      },
      {
        type = "metric", x = 0, y = 6, width = 12, height = 6
        properties = {
          title = "CPU", region = var.aws_region, view = "timeSeries", period = 300
          metrics = [
            ["AWS/EC2", "CPUUtilization", "InstanceId", aws_instance.wikijs_prod.id, { stat = "Average" }],
            ["AWS/EC2", "CPUCreditBalance", "InstanceId", aws_instance.wikijs_prod.id, { stat = "Average", yAxis = "right" }],
          ]
        }
      },
      {
        type = "metric", x = 12, y = 6, width = 12, height = 6
        properties = {
          title = "Memory and disk used %", region = var.aws_region, view = "timeSeries", stat = "Average", period = 300
          yAxis = { left = { min = 0, max = 100 } }
          metrics = [
            ["CWAgent", "mem_used_percent", "InstanceId", aws_instance.wikijs_prod.id],
            ["CWAgent", "swap_used_percent", "InstanceId", aws_instance.wikijs_prod.id],
            ["CWAgent", "disk_used_percent", "InstanceId", aws_instance.wikijs_prod.id, "path", "/", "fstype", "ext4"],
            ["CWAgent", "disk_used_percent", "InstanceId", aws_instance.wikijs_prod.id, "path", "/data", "fstype", "ext4"],
          ]
        }
      },
      {
        type = "metric", x = 0, y = 12, width = 12, height = 6
        properties = {
          title   = "Nightly backup (1 = succeeded)", region = var.aws_region, view = "bar", stat = "Sum", period = 86400
          metrics = [[local.metric_namespace, "BackupSucceeded"]]
        }
      },
      {
        type = "metric", x = 12, y = 12, width = 12, height = 6
        properties = {
          title = "Network", region = var.aws_region, view = "timeSeries", stat = "Sum", period = 300
          metrics = [
            ["AWS/EC2", "NetworkIn", "InstanceId", aws_instance.wikijs_prod.id],
            ["AWS/EC2", "NetworkOut", "InstanceId", aws_instance.wikijs_prod.id],
          ]
        }
      },
      {
        type = "metric", x = 0, y = 18, width = 12, height = 6
        properties = {
          title   = "Zombie processes", region = var.aws_region, view = "timeSeries", stat = "Maximum", period = 300
          metrics = [["CWAgent", "processes_zombies", "InstanceId", aws_instance.wikijs_prod.id]]
        }
      },
    ]
  })
}
