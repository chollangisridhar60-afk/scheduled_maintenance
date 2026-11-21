locals {
  # The script is sent as-is, preceded by exports for the pipeline parameters.
  # The shebang must stay on line 1, so the script's own first line is dropped and re-added.
  # Inputs are charset-validated in variables.tf, so single-quoting here is safe.
  patch_commands = join("\n", [
    "#!/bin/bash",
    "export ADVISORY='${var.advisory_id}'",
    "export RELEASEVER='${var.releasever}'",
    "export PACKAGES='${join(" ", var.patch_packages)}'",
    "export RESTART_SERVICES='${var.restart_services ? 1 : 0}'",
    replace(file("${path.module}/scripts/patch_brotli.sh"), "/^#![^\\n]*\\n/", ""),
  ])
}

resource "aws_ssm_maintenance_window" "this" {
  name                       = var.name
  description                = var.description
  schedule                   = trimspace(var.schedule)
  schedule_timezone          = var.schedule_timezone
  duration                   = var.duration
  cutoff                     = var.cutoff
  enabled                    = var.enabled
  allow_unassociated_targets = false
  tags                       = var.tags
}

resource "aws_ssm_maintenance_window_target" "this" {
  window_id     = aws_ssm_maintenance_window.this.id
  resource_type = "INSTANCE"

  dynamic "targets" {
    for_each = var.target_tags
    content {
      key    = "tag:${targets.key}"
      values = targets.value
    }
  }
}

resource "aws_ssm_maintenance_window_task" "patch" {
  window_id        = aws_ssm_maintenance_window.this.id
  task_type        = "RUN_COMMAND"
  task_arn         = "AWS-RunShellScript"
  priority         = var.task_priority
  service_role_arn = var.service_role_arn
  max_concurrency  = var.max_concurrency
  max_errors       = var.max_errors

  targets {
    key    = "WindowTargetIds"
    values = [aws_ssm_maintenance_window_target.this.id]
  }

  task_invocation_parameters {
    run_command_parameters {
      timeout_seconds  = var.command_timeout_seconds
      document_version = "$DEFAULT"

      parameter {
        name   = "commands"
        values = [local.patch_commands]
      }
      parameter {
        name   = "executionTimeout"
        values = [var.execution_timeout]
      }
    }
  }
}
