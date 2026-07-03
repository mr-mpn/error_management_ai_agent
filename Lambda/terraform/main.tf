terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Partial backend configuration — supply bucket via CLI flag:
  #   terraform init -backend-config="bucket=<your-tf-state-bucket>"
  backend "s3" {
    key    = "ai-agent-error-management/lambda/terraform.tfstate"
    region = "eu-west-1"
  }
}

provider "aws" {
  region = var.aws_region
}

# ── Package: zip the Lambda source file ──────────────────────────────────────
data "archive_file" "validate_key" {
  type        = "zip"
  source_file = "${path.module}/../main.py"
  output_path = "${path.module}/validate_key_lambda.zip"
}

# ── CloudWatch Log Group ──────────────────────────────────────────────────────
resource "aws_cloudwatch_log_group" "validate_key" {
  name              = "/aws/lambda/${var.function_name}"
  retention_in_days = var.log_retention_days

  tags = {
    Project   = "ai-agent-error-management"
    Component = "validate-key-lambda"
  }
}

# ── IAM Execution Role ────────────────────────────────────────────────────────
resource "aws_iam_role" "validate_key" {
  name = "${var.function_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Project   = "ai-agent-error-management"
    Component = "validate-key-lambda"
  }
}

resource "aws_iam_role_policy" "validate_key_logs" {
  name = "CloudWatchLogsWritePolicy"
  role = aws_iam_role.validate_key.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogStream",
        "logs:PutLogEvents",
      ]
      # Restrict to only this function's log group
      Resource = "${aws_cloudwatch_log_group.validate_key.arn}:*"
    }]
  })
}

# ── Lambda Function ───────────────────────────────────────────────────────────
resource "aws_lambda_function" "validate_key" {
  function_name    = var.function_name
  filename         = data.archive_file.validate_key.output_path
  source_code_hash = data.archive_file.validate_key.output_base64sha256
  role             = aws_iam_role.validate_key.arn
  runtime          = "python3.12"
  handler          = "main.handler"
  timeout          = 30
  memory_size      = 128

  environment {
    variables = {
      # This is the key the Lambda validates against.
      # The AI agent reads this from CloudWatch logs during error recovery.
      EXPECTED_KEY = var.expected_key
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.validate_key,
    aws_iam_role_policy.validate_key_logs,
  ]

  tags = {
    Project   = "ai-agent-error-management"
    Component = "validate-key-lambda"
  }
}
