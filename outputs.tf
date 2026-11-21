output "window_id" { value = aws_ssm_maintenance_window.this.id }
output "target_id" { value = aws_ssm_maintenance_window_target.this.id }
output "task_id"   { value = aws_ssm_maintenance_window_task.patch.id }
