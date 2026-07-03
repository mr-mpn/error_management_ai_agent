output "agent_function_arn" {
  description = "ARN of the Strands Agent Lambda function."
  value       = aws_lambda_function.strands_agent.arn
}

output "agent_function_name" {
  description = "Name of the Strands Agent Lambda function."
  value       = aws_lambda_function.strands_agent.function_name
}

output "agent_log_group_name" {
  description = "CloudWatch Log Group name for the Strands Agent Lambda."
  value       = aws_cloudwatch_log_group.strands_agent.name
}
