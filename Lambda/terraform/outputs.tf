output "function_arn" {
  description = "ARN of the ValidateKey Lambda function."
  value       = aws_lambda_function.validate_key.arn
}

output "function_name" {
  description = "Name of the ValidateKey Lambda function."
  value       = aws_lambda_function.validate_key.function_name
}

output "log_group_name" {
  description = "CloudWatch Log Group name for the ValidateKey Lambda (used by the AI agent tool)."
  value       = aws_cloudwatch_log_group.validate_key.name
}

output "log_group_arn" {
  description = "ARN of the ValidateKey Lambda CloudWatch Log Group."
  value       = aws_cloudwatch_log_group.validate_key.arn
}
