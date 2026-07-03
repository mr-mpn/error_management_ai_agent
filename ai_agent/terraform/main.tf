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
    key    = "ai-agent-error-management/ai-agent/terraform.tfstate"
    region = "eu-west-1"
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ── CloudWatch Log Group for the Agent Lambda ─────────────────────────────────
resource "aws_cloudwatch_log_group" "strands_agent" {
  name              = "/aws/lambda/${var.function_name}"
  retention_in_days = var.log_retention_days

  tags = {
    Project   = "ai-agent-error-management"
    Component = "strands-agent-lambda"
  }
}

# ── IAM Execution Role ────────────────────────────────────────────────────────
resource "aws_iam_role" "strands_agent" {
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
    Component = "strands-agent-lambda"
  }
}

resource "aws_iam_role_policy" "strands_agent" {
  name = "StrandsAgentPolicy"
  role = aws_iam_role.strands_agent.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # ── Write own CloudWatch logs ───────────────────────────────────────────
      {
        Sid    = "WriteSelfLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = "${aws_cloudwatch_log_group.strands_agent.arn}:*"
      },

      # ── Read ValidateKey Lambda logs (tool: read_cloudwatch_logs) ───────────
      {
        Sid    = "ReadValidateKeyLogs"
        Effect = "Allow"
        Action = [
          "logs:FilterLogEvents",
          "logs:GetLogEvents",
          "logs:DescribeLogStreams",
        ]
        Resource = [
          "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:${var.validate_key_log_group_name}",
          "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:${var.validate_key_log_group_name}:*",
        ]
      },

      # ── Invoke Claude on Bedrock (Strands SDK calls) ────────────────────────
      {
        Sid    = "BedrockInvokeModel"
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream",
        ]
        # Allow both foundation model ARNs and cross-region inference profile ARNs.
        # eu-west-1 requires the eu. prefixed inference profile (different ARN format).
        Resource = [
          "arn:aws:bedrock:*::foundation-model/*",
          "arn:aws:bedrock:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:inference-profile/*",
        ]
      },

      # ── Start new Step Function execution (tool: restart_step_function) ─────
      {
        Sid    = "StartStepFunctionExecution"
        Effect = "Allow"
        Action = "states:StartExecution"
        # Scoped to all state machines in this account/region.
        # The specific ARN is passed at runtime via the event payload.
        Resource = "arn:aws:states:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:stateMachine:*"
      },
    ]
  })
}

# ── Strands Agent Lambda Function ─────────────────────────────────────────────
# The deployment package is built by CI/CD before terraform apply:
#   pip install -r requirements.txt -t package/
#   cp main.py package/
#   cd package && zip -r ../lambda_package.zip .
resource "aws_lambda_function" "strands_agent" {
  function_name = var.function_name

  # Packaged by CI/CD pipeline (see .github/workflows/deploy.yml)
  filename         = "${path.module}/../lambda_package.zip"
  source_code_hash = filebase64sha256("${path.module}/../lambda_package.zip")

  role        = aws_iam_role.strands_agent.arn
  runtime     = "python3.12"
  handler     = "main.handler"
  timeout     = 300 # 5 minutes — Strands ReAct loop may run multiple Bedrock calls
  memory_size = 512 # Strands SDK + dependencies need headroom

  environment {
    variables = {
      BEDROCK_MODEL_ID = var.bedrock_model_id
      # LOG_GROUP_NAME and STATE_MACHINE_ARN are passed at runtime via
      # the Step Function event payload, but can be set here as fallbacks.
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.strands_agent,
    aws_iam_role_policy.strands_agent,
  ]

  tags = {
    Project   = "ai-agent-error-management"
    Component = "strands-agent-lambda"
  }
}
