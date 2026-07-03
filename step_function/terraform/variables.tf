variable "aws_region" {
  description = "AWS region where resources are deployed."
  type        = string
  default     = "eu-west-1"
}

variable "state_machine_name" {
  description = "Name for the Step Function state machine."
  type        = string
  default     = "ai-agent-error-management-demo"
}

variable "validate_key_function_arn" {
  description = "ARN of the ValidateKey Lambda function (from Lambda module output)."
  type        = string
}

variable "strands_agent_function_arn" {
  description = "ARN of the Strands Agent Lambda function (from ai_agent module output)."
  type        = string
}

variable "validate_key_log_group_name" {
  description = "CloudWatch log group name of the ValidateKey Lambda. Passed to the agent at runtime."
  type        = string
}
