variable "aws_region" {
  description = "AWS region where resources are deployed."
  type        = string
  default     = "eu-west-1"
}

variable "function_name" {
  description = "Name for the Strands Agent Lambda function."
  type        = string
  default     = "ai-agent-strands-error-recovery"
}

variable "bedrock_model_id" {
  description = "Bedrock foundation model ID used by the Strands agent."
  type        = string
  default     = "anthropic.claude-3-5-sonnet-20241022-v2:0"
}

variable "validate_key_log_group_name" {
  description = "CloudWatch log group name of the ValidateKey Lambda. The agent tool reads logs from here."
  type        = string
}

variable "log_retention_days" {
  description = "Number of days to retain the agent Lambda's own CloudWatch logs."
  type        = number
  default     = 14
}
