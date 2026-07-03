variable "aws_region" {
  description = "AWS region where resources are deployed."
  type        = string
  default     = "eu-west-1"
}

variable "function_name" {
  description = "Name for the ValidateKey Lambda function."
  type        = string
  default     = "ai-agent-validate-key"
}

variable "expected_key" {
  description = "The correct API key that the Lambda validates against (stored in its env var)."
  type        = string
  sensitive   = true
}

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs."
  type        = number
  default     = 14
}
