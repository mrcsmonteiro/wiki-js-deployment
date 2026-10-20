# OS patching with Systems Manager Patch Manager, using AWS's default Ubuntu
# patch baseline.
#
# Unattended upgrades on the host already install security updates daily but
# never reboot. This weekly window installs everything the baseline approves
# and reboots if needed (both apps come back by themselves: wikijs.service is
# enabled and PCA uses restart: unless-stopped). Expect ~2 minutes of downtime.
#
# The window has its own timezone, so it follows AEST/AEDT; the host stays UTC.

resource "aws_ssm_maintenance_window" "patching" {
  name              = "wiki-js-prod-patching"
  description       = "Weekly OS patching and reboot for the Wiki.js host"
  schedule          = var.patch_window_schedule
  schedule_timezone = "Australia/Melbourne"
  duration          = 2
  cutoff            = 1

  allow_unassociated_targets = false

  tags = { Name = "wiki-js-prod-patching" }
}

resource "aws_ssm_maintenance_window_target" "patching" {
  window_id     = aws_ssm_maintenance_window.patching.id
  name          = "wiki-js-prod"
  description   = "The Wiki.js host, by Name tag"
  resource_type = "INSTANCE"

  targets {
    key    = "tag:Name"
    values = ["wiki-js-prod"]
  }
}

resource "aws_ssm_maintenance_window_task" "patch_install" {
  window_id       = aws_ssm_maintenance_window.patching.id
  name            = "install-patches"
  description     = "AWS-RunPatchBaseline Install, reboot if needed"
  task_type       = "RUN_COMMAND"
  task_arn        = "AWS-RunPatchBaseline"
  priority        = 1
  max_concurrency = "1"
  max_errors      = "1"

  targets {
    key    = "WindowTargetIds"
    values = [aws_ssm_maintenance_window_target.patching.id]
  }

  task_invocation_parameters {
    run_command_parameters {
      timeout_seconds = 3600

      parameter {
        name   = "Operation"
        values = ["Install"]
      }

      parameter {
        name   = "RebootOption"
        values = ["RebootIfNeeded"]
      }
    }
  }
}

# Daily scan (no install, no reboot) keeps patch compliance current between
# the weekly windows.
resource "aws_ssm_association" "patch_scan" {
  name                = "AWS-RunPatchBaseline"
  association_name    = "wiki-js-prod-patch-scan"
  schedule_expression = "rate(1 day)"

  parameters = {
    Operation = "Scan"
  }

  targets {
    key    = "tag:Name"
    values = ["wiki-js-prod"]
  }
}
