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
  description = "Bedrock model ID for the Strands agent. Uses eu. prefix for cross-region inference in eu-west-1."
  type        = string
  default     = "eu.amazon.nova-pro-v1:0"
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
