variable "region" {
  type    = string
  default = "us-west-2"
}

variable "name" {
  description = "Maintenance window name"
  type        = string
  default     = "CVE-2026-111497"
}

variable "description" {
  type    = string
  default = "CVE-2026-111497"
}

variable "schedule" {
  description = "Cron/rate/at expression. For a one-time run use e.g. at(2026-12-04T05:43:00)."
  type        = string
  default     = "cron(43 05 ? * FRI#1 *)"
}

variable "schedule_timezone" {
  type    = string
  default = "America/New_York"
}

variable "duration" {
  description = "Window duration in hours"
  type        = number
  default     = 2
}

variable "cutoff" {
  description = "Hours before window end to stop starting new tasks"
  type        = number
  default     = 1
}

variable "enabled" {
  description = "Console shows the window as Disabled; flip to true when ready to patch."
  type        = bool
  default     = false
}

variable "target_tag_key" {
  description = "Tag key used to select instances (e.g. Patch Group)"
  type        = string
}

variable "target_tag_values" {
  description = "Tag values to match"
  type        = list(string)
}

variable "service_role_arn" {
  type    = string
  default = "arn:aws:iam::707582904453:role/mmPatchingExecutionRoleForSSM"
}

variable "max_concurrency" {
  type    = string
  default = "30%"
}

variable "max_errors" {
  type    = string
  default = "100%"
}

variable "task_priority" {
  type    = number
  default = 1
}

variable "execution_timeout" {
  description = "Seconds before the command is considered failed"
  type        = string
  default     = "3600"
}

variable "command_timeout_seconds" {
  description = "Run Command timeout (seconds)"
  type        = number
  default     = 600
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "advisory_id" {
  description = "Amazon Linux advisory to apply, e.g. ALAS2023-2026-3478 (AL2023) or ALAS2-2026-4123 (AL2)"
  type        = string

  validation {
    condition     = can(regex("^ALAS(2023|2)-[0-9]{4}-[0-9]+$", var.advisory_id))
    error_message = "advisory_id must look like ALAS2023-2026-3478 or ALAS2-2026-4123."
  }
}

variable "releasever" {
  description = "AL2023 --releasever, e.g. 2023.12.20261117 (or \"latest\"). Ignored on AL2."
  type        = string
  default     = "latest"

  validation {
    condition     = can(regex("^(latest|[0-9]+(\\.[0-9]+)*)$", var.releasever))
    error_message = "releasever must be \"latest\" or a version like 2023.12.20261117."
  }
}

variable "patch_packages" {
  description = "Package names to update; installed subpackages are included (e.g. java-17-amazon-corretto)"
  type        = list(string)

  validation {
    condition     = length(var.patch_packages) > 0 && alltrue([for p in var.patch_packages : can(regex("^[A-Za-z0-9._+-]+$", p))])
    error_message = "patch_packages needs at least one name made only of letters, digits and . _ + -"
  }
}
