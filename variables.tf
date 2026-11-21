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
  default = "arn:aws:iam::897138222775:role/mmPatchingExecutionRoleForSSM"
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
