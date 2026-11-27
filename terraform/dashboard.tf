# CloudWatch dashboard for the Wiki.js host (and PCA, which shares it).
#
# Rows: 1 at a glance (alarms, current values) | 2 availability | 3 capacity,
# with alarm thresholds drawn on the graphs | 4 operations | 5 logs.
# Route 53 and CloudFront metrics live in us-east-1; each widget sets its region.
#
# Cost: the first 3 dashboards per account are free. Logs Insights widgets are
# billed per GB scanned, only when the dashboard is viewed (the logs are small).

locals {
  instance_dim = ["InstanceId", aws_instance.wikijs_v3.id]

  dashboard_alarm_arns = concat(
    [
      aws_cloudwatch_metric_alarm.system_status.arn,
      aws_cloudwatch_metric_alarm.instance_status.arn,
      aws_cloudwatch_metric_alarm.cpu_credits.arn,
      aws_cloudwatch_metric_alarm.memory.arn,
      aws_cloudwatch_metric_alarm.zombies.arn,
    ],
    [for a in aws_cloudwatch_metric_alarm.disk : a.arn],
    [for a in aws_cloudwatch_metric_alarm.app_up : a.arn],
    [for a in aws_cloudwatch_metric_alarm.backup : a.arn],
    [for a in aws_cloudwatch_metric_alarm.site_health : a.arn],
  )

  access_logs = "SOURCE '${local.log_groups.wiki_access}' | SOURCE '${local.log_groups.pca_access}'"
  error_logs  = "SOURCE '${local.log_groups.wiki_error}' | SOURCE '${local.log_groups.pca_error}'"
}

resource "aws_cloudwatch_dashboard" "host" {
  dashboard_name = local.alarm_prefix

  dashboard_body = jsonencode({
    widgets = [
      # --- Row 1: at a glance --------------------------------------------------
      {
        type = "alarm", x = 0, y = 0, width = 10, height = 6
        properties = {
          title  = "Alarms"
          alarms = local.dashboard_alarm_arns
          sortBy = "stateUpdatedTimestamp"
        }
      },
      {
        type = "metric", x = 10, y = 0, width = 14, height = 6
        properties = {
          title     = "Now"
          region    = var.aws_region
          view      = "singleValue"
          sparkline = true
          period    = 300
          metrics = [
            [local.metric_namespace, "AppUp", "App", "wikijs", { stat = "Minimum", label = "Wiki.js up" }],
            [local.metric_namespace, "AppUp", "App", "pca", { stat = "Minimum", label = "PCA up" }],
            concat(["CWAgent", "mem_used_percent"], local.instance_dim, [{ stat = "Average", label = "Memory %" }]),
            concat(["CWAgent", "disk_used_percent"], local.instance_dim, ["path", "/", "fstype", "ext4", { stat = "Maximum", label = "Disk / %" }]),
            concat(["CWAgent", "disk_used_percent"], local.instance_dim, ["path", "/data", "fstype", "ext4", { stat = "Maximum", label = "Disk /data %" }]),
            concat(["AWS/EC2", "CPUCreditBalance"], local.instance_dim, [{ stat = "Average", label = "CPU credits" }]),
            [local.metric_namespace, "BackupSucceeded", "App", "wikijs", { stat = "Sum", period = 86400, label = "Wiki.js backups (24 h)" }],
            [local.metric_namespace, "BackupSucceeded", "App", "pca", { stat = "Sum", period = 86400, label = "PCA backups (24 h)" }],
          ]
        }
      },

      # --- Row 2: availability ---------------------------------------------------
      {
        type = "metric", x = 0, y = 6, width = 8, height = 6
        properties = {
          title  = "App probes on the host (1 = up)"
          region = var.aws_region
          view   = "timeSeries"
          stat   = "Minimum"
          period = 300
          yAxis  = { left = { min = 0, max = 1 } }
          metrics = [
            [local.metric_namespace, "AppUp", "App", "wikijs", { label = "Wiki.js" }],
            [local.metric_namespace, "AppUp", "App", "pca", { label = "PCA" }],
          ]
        }
      },
      {
        type = "metric", x = 8, y = 6, width = 8, height = 6
        properties = {
          title   = "Public URLs (Route 53 health checks, 1 = healthy)"
          region  = "us-east-1"
          view    = "timeSeries"
          stat    = "Minimum"
          period  = 60
          yAxis   = { left = { min = 0, max = 1 } }
          metrics = [for k, hc in aws_route53_health_check.site : ["AWS/Route53", "HealthCheckStatus", "HealthCheckId", hc.id, { label = k }]]
        }
      },
      {
        type = "metric", x = 16, y = 6, width = 8, height = 6
        properties = {
          title  = "Wiki.js readers (CloudFront)"
          region = "us-east-1"
          view   = "timeSeries"
          period = 300
          metrics = [
            ["AWS/CloudFront", "Requests", "DistributionId", aws_cloudfront_distribution.wikijs_cdn.id, "Region", "Global", { stat = "Sum", label = "Requests" }],
            ["AWS/CloudFront", "4xxErrorRate", "DistributionId", aws_cloudfront_distribution.wikijs_cdn.id, "Region", "Global", { stat = "Average", label = "4xx %", yAxis = "right" }],
            ["AWS/CloudFront", "5xxErrorRate", "DistributionId", aws_cloudfront_distribution.wikijs_cdn.id, "Region", "Global", { stat = "Average", label = "5xx %", yAxis = "right" }],
          ]
        }
      },

      # --- Row 3: capacity (alarm thresholds drawn as lines) ----------------------
      {
        type = "metric", x = 0, y = 12, width = 8, height = 6
        properties = {
          title  = "CPU"
          region = var.aws_region
          view   = "timeSeries"
          period = 300
          metrics = [
            concat(["AWS/EC2", "CPUUtilization"], local.instance_dim, [{ stat = "Average", label = "CPU %" }]),
            concat(["AWS/EC2", "CPUCreditBalance"], local.instance_dim, [{ stat = "Average", label = "Credit balance", yAxis = "right" }]),
          ]
          annotations = { horizontal = [{ label = "Credits alarm", value = 30, yAxis = "right" }] }
        }
      },
      {
        type = "metric", x = 8, y = 12, width = 8, height = 6
        properties = {
          title  = "Memory and swap used %"
          region = var.aws_region
          view   = "timeSeries"
          stat   = "Average"
          period = 300
          yAxis  = { left = { min = 0, max = 100 } }
          metrics = [
            concat(["CWAgent", "mem_used_percent"], local.instance_dim, [{ label = "Memory" }]),
            concat(["CWAgent", "swap_used_percent"], local.instance_dim, [{ label = "Swap" }]),
          ]
          annotations = { horizontal = [{ label = "Memory alarm", value = 90 }] }
        }
      },
      {
        type = "metric", x = 16, y = 12, width = 8, height = 6
        properties = {
          title  = "Disk used %"
          region = var.aws_region
          view   = "timeSeries"
          stat   = "Maximum"
          period = 300
          yAxis  = { left = { min = 0, max = 100 } }
          metrics = [
            concat(["CWAgent", "disk_used_percent"], local.instance_dim, ["path", "/", "fstype", "ext4", { label = "/ (root, 10 GiB)" }]),
            concat(["CWAgent", "disk_used_percent"], local.instance_dim, ["path", "/data", "fstype", "ext4", { label = "/data (20 GiB)" }]),
          ]
          annotations = {
            horizontal = [
              { label = "/ alarm", value = 85 },
              { label = "/data alarm", value = 80 },
            ]
          }
        }
      },

      # --- Row 4: operations ------------------------------------------------------
      {
        type = "metric", x = 0, y = 18, width = 8, height = 6
        properties = {
          title   = "Nightly backup (1 = succeeded)"
          region  = var.aws_region
          view    = "bar"
          stat    = "Sum"
          period  = 86400
          metrics = [[local.metric_namespace, "BackupSucceeded", "App", "wikijs", { label = "Wiki.js" }], [local.metric_namespace, "BackupSucceeded", "App", "pca", { label = "PCA" }]]
        }
      },
      {
        type = "metric", x = 8, y = 18, width = 8, height = 6
        properties = {
          title       = "Zombie processes"
          region      = var.aws_region
          view        = "timeSeries"
          stat        = "Maximum"
          period      = 300
          metrics     = [concat(["CWAgent", "processes_zombies"], local.instance_dim, [{ label = "Zombies" }])]
          annotations = { horizontal = [{ label = "Alarm", value = 50 }] }
        }
      },
      {
        type = "metric", x = 16, y = 18, width = 8, height = 6
        properties = {
          title  = "Network"
          region = var.aws_region
          view   = "timeSeries"
          stat   = "Sum"
          period = 300
          metrics = [
            concat(["AWS/EC2", "NetworkIn"], local.instance_dim, [{ label = "In" }]),
            concat(["AWS/EC2", "NetworkOut"], local.instance_dim, [{ label = "Out" }]),
          ]
        }
      },

      # --- Row 5: logs (Logs Insights, follows the dashboard time range) ----------
      {
        type = "log", x = 0, y = 24, width = 12, height = 6
        properties = {
          title  = "nginx 5xx responses by site and status"
          region = var.aws_region
          view   = "table"
          query  = "${local.access_logs} | parse @message /\"\\s(?<status>\\d{3})\\s/ | filter status >= 500 | stats count(*) as responses by @log, status | sort responses desc"
        }
      },
      {
        type = "log", x = 12, y = 24, width = 12, height = 6
        properties = {
          title  = "Nightly backup runs"
          region = var.aws_region
          view   = "table"
          query  = "SOURCE '${local.log_groups.backup}' | fields @timestamp, @message | sort @timestamp desc | limit 20"
        }
      },
      {
        type = "log", x = 0, y = 30, width = 24, height = 6
        properties = {
          title  = "Latest nginx errors (both sites)"
          region = var.aws_region
          view   = "table"
          query  = "${local.error_logs} | fields @timestamp, @log, @message | sort @timestamp desc | limit 25"
        }
      },
    ]
  })
}
