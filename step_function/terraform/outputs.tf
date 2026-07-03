output "state_machine_arn" {
  description = "ARN of the Step Function state machine."
  value       = aws_sfn_state_machine.error_demo.arn
}

output "state_machine_name" {
  description = "Name of the Step Function state machine."
  value       = aws_sfn_state_machine.error_demo.name
}
