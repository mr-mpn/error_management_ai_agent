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
    key    = "ai-agent-error-management/step-function/terraform.tfstate"
    region = "eu-west-1"
  }
}

provider "aws" {
  region = var.aws_region
}

# ── IAM Role for Step Functions ───────────────────────────────────────────────
resource "aws_iam_role" "step_function" {
  name = "${var.state_machine_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "states.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Project   = "ai-agent-error-management"
    Component = "step-function"
  }
}

resource "aws_iam_role_policy" "step_function_invoke_lambda" {
  name = "InvokeLambdaPolicy"
  role = aws_iam_role.step_function.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "InvokeLambdaFunctions"
      Effect = "Allow"
      Action = "lambda:InvokeFunction"
      Resource = [
        var.validate_key_function_arn,
        var.strands_agent_function_arn,
      ]
    }]
  })
}

# ── State Machine ─────────────────────────────────────────────────────────────
# ASL flow:
#   ValidateKey (Task) → succeeds → END
#                      → fails (any error) → Catch → InvokeAIAgent (Task) → END
#
# The InvokeAIAgent state passes the following context to the Strands agent Lambda:
#   - error:             the caught error object {Error, Cause}
#   - original_input:    the Step Function's original execution input (contains wrong api_key)
#   - execution_arn:     the failed execution ARN (for logging/diagnosis)
#   - state_machine_arn: the Step Function's own ARN (via $$.StateMachine.Id)
#                        so the agent knows which state machine to restart
#   - log_group_name:    the ValidateKey Lambda's CW log group (static, from Terraform var)
resource "aws_sfn_state_machine" "error_demo" {
  name     = var.state_machine_name
  role_arn = aws_iam_role.step_function.arn

  definition = jsonencode({
    Comment = "AI Agent Error Management Demo — validates api_key; on failure triggers Strands AI agent for autonomous recovery"
    StartAt = "ValidateKey"
    States = {

      # ── Step 1: Call ValidateKey Lambda ───────────────────────────────────
      ValidateKey = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName  = var.validate_key_function_arn
          # Pass the entire execution input as the Lambda event payload
          "Payload.$"   = "$"
        }
        # Extract the Lambda's return value from the response envelope
        ResultSelector = {
          "result.$" = "$.Payload"
        }
        # On any error, route to the AI agent — no retries (single-shot demo)
        Catch = [{
          ErrorEquals = ["States.ALL"]
          Next        = "InvokeAIAgent"
          # Merge error details into the state data under $.error
          ResultPath  = "$.error"
        }]
        End = true
      }

      # ── Step 2: Invoke Strands AI Agent for autonomous recovery ───────────
      InvokeAIAgent = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = var.strands_agent_function_arn
          Payload = {
            # The caught error details {Error, Cause}
            "error.$"              = "$.error"
            # The original execution input — contains the wrong api_key
            "original_input.$"     = "$$.Execution.Input"
            # The failed execution ARN — for reference/logging in the agent
            "execution_arn.$"      = "$$.Execution.Id"
            # The state machine's own ARN — agent uses this to restart it
            "state_machine_arn.$"  = "$$.StateMachine.Id"
            # The ValidateKey Lambda's log group — agent reads logs from here
            log_group_name         = var.validate_key_log_group_name
          }
        }
        # Extract agent Lambda's return value
        ResultSelector = {
          "agent_result.$" = "$.Payload"
        }
        End = true
      }
    }
  })

  tags = {
    Project   = "ai-agent-error-management"
    Component = "step-function"
  }

  depends_on = [aws_iam_role_policy.step_function_invoke_lambda]
}
