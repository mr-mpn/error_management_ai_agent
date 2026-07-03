# AI Agent Error Management

> A demonstration of autonomous AI-driven error recovery using **AWS Step Functions**, **AWS Lambda**, and the **[AWS Strands Agents SDK](https://github.com/strands-agents/sdk-python)** with Claude 3.5 Sonnet on Bedrock.

---

## How It Works

```
Step Function starts
  └─► ValidateKey Lambda ── WRONG key ──► FAILS
                                              │
                                    [Catch → InvokeAIAgent]
                                              │
                              Strands Agent Lambda (ReAct loop)
                                ├─ Tool 1: read_cloudwatch_logs
                                │     └─ Finds "[KEY_VALIDATION] Expected API key: <key>"
                                └─ Tool 2: restart_step_function(api_key=<key>)
                                              │
                              Step Function (Execution 2) ── CORRECT key ──► SUCCEEDS
```

1. The Step Function is started with a **deliberately wrong** `api_key`.
2. The ValidateKey Lambda rejects it, logs the correct expected key (demo only!), and fails.
3. The Step Function `Catch` block triggers the **Strands Agent Lambda**.
4. The Strands agent runs a **ReAct loop**: reads CloudWatch logs → finds the correct key → restarts the Step Function.
5. A new execution starts with the correct key and **succeeds**.

---

## Repository Structure

```
ai_agent_error_management/
│
├── Lambda/                          # ValidateKey Lambda
│   ├── main.py                      # Validates api_key vs EXPECTED_KEY env var; logs the correct key
│   ├── requirements.txt
│   └── terraform/
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
│
├── step_function/                   # Step Function State Machine
│   └── terraform/
│       ├── main.tf                  # ASL with Catch block → InvokeAIAgent state
│       ├── variables.tf
│       └── outputs.tf
│
├── ai_agent/                        # Strands Agent Lambda (core AI component)
│   ├── main.py                      # Lambda entry point — thin handler, wires everything together
│   ├── requirements.txt             # strands-agents
│   ├── tools/
│   │   ├── __init__.py
│   │   └── recovery_tools.py        # @tool definitions: read_cloudwatch_logs, restart_step_function
│   ├── config/
│   │   ├── __init__.py
│   │   ├── model.py                 # BedrockModel instance
│   │   └── prompts.py               # SYSTEM_PROMPT constant
│   └── terraform/
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
│
└── .github/
    └── workflows/
        └── deploy.yml               # GitHub Actions CI/CD — 3 jobs in dependency order
```

---

## Prerequisites

| Tool | Version | Notes |
|------|---------|-------|
| Terraform | ≥ 1.5.0 | |
| Python | 3.12 | For building the agent Lambda package locally |
| AWS CLI | v2 | For setup and manual testing |
| GitHub CLI (`gh`) | latest | For setting GitHub Secrets from the terminal |
| AWS account | — | Claude 3.5 Sonnet must be enabled in Bedrock (eu-west-1) |

---

## Setup

### 1. Enable Bedrock Model Access

In the AWS console → **Amazon Bedrock → Model access** (eu-west-1), enable:
- `Anthropic / Claude 3.5 Sonnet`

### 2. Create the Terraform State S3 Bucket

```bash
aws s3 mb s3://ai-agent-error-mgmt-tf-state --region eu-west-1

# Enable versioning (recommended)
aws s3api put-bucket-versioning \
  --bucket ai-agent-error-mgmt-tf-state \
  --versioning-configuration Status=Enabled
```

### 3. Set GitHub Secrets via `gh` CLI

The CI/CD pipeline authenticates with AWS using `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` injected as environment variables. Set all 4 secrets from your terminal:

```bash
# Read your credentials from the local AWS CLI config and pipe them straight in
gh secret set AWS_ACCESS_KEY_ID \
  --body "$(aws configure get aws_access_key_id)"

gh secret set AWS_SECRET_ACCESS_KEY \
  --body "$(aws configure get aws_secret_access_key)"

gh secret set TF_STATE_BUCKET \
  --body "ai-agent-error-mgmt-tf-state"

gh secret set EXPECTED_API_KEY \
  --body "super-secret-key-2024"
```

Verify all secrets are registered:

```bash
gh secret list
```

---

## Deployment

### Via GitHub Actions (CI/CD)

Push to `main` — the pipeline deploys all 3 modules in dependency order:

```
Job 1 → Deploy ValidateKey Lambda
Job 2 → Build & Deploy Strands Agent Lambda   (needs Job 1 outputs)
Job 3 → Deploy Step Function                  (needs Job 1 + 2 outputs)
```

```bash
git add .
git commit -m "initial deployment"
git push origin main
```

The **Job 4 summary** printed at the end of the pipeline gives you the State Machine ARN and a ready-to-run test command.

### Manual Deployment (local)

#### Step 1 — ValidateKey Lambda

```bash
cd Lambda/terraform
terraform init -backend-config="bucket=ai-agent-error-mgmt-tf-state"
terraform apply -var="expected_key=super-secret-key-2024"
```

#### Step 2 — Strands Agent Lambda

```bash
cd ai_agent

# Build the deployment package (includes tools/ and config/ sub-packages)
pip install -r requirements.txt -t package/
cp main.py package/
cp -r tools/  package/tools/
cp -r config/ package/config/
cd package && zip -r ../lambda_package.zip . && cd ..

cd terraform
terraform init -backend-config="bucket=ai-agent-error-mgmt-tf-state"
terraform apply \
  -var="validate_key_log_group_name=$(cd ../../Lambda/terraform && terraform output -raw log_group_name)"
```

#### Step 3 — Step Function

```bash
cd step_function/terraform
terraform init -backend-config="bucket=ai-agent-error-mgmt-tf-state"
terraform apply \
  -var="validate_key_function_arn=$(cd ../../Lambda/terraform && terraform output -raw function_arn)" \
  -var="strands_agent_function_arn=$(cd ../../ai_agent/terraform && terraform output -raw agent_function_arn)" \
  -var="validate_key_log_group_name=$(cd ../../Lambda/terraform && terraform output -raw log_group_name)"
```

---

## Testing the End-to-End Flow

### 1. Get the State Machine ARN

```bash
SF_ARN=$(cd step_function/terraform && terraform output -raw state_machine_arn)
echo $SF_ARN
```

### 2. Trigger a failure (wrong key → AI recovery)

```bash
aws stepfunctions start-execution \
  --state-machine-arn "$SF_ARN" \
  --input '{"api_key": "wrong-key-intentional-fail"}' \
  --region eu-west-1
```

### 3. Watch the Strands agent work in real time

```bash
aws logs tail /aws/lambda/ai-agent-strands-error-recovery --follow --region eu-west-1
```

### 4. Verify recovery

After ~30–60 seconds you should see two executions in the AWS console:

| Execution | Input | Status |
|-----------|-------|--------|
| Execution 1 | `wrong-key-intentional-fail` | `SUCCEEDED` (InvokeAIAgent state completed) |
| Execution 2 | `super-secret-key-2024` | `SUCCEEDED` (started by the AI agent) |

---

## AI Agent Details

### Strands SDK ReAct Loop

```
Thought → which tool do I need?
Act     → call the tool
Observe → read the result
Thought → what should I do next?
          ... repeat until done
```

### Tools

| Tool | File | What it does |
|------|------|-------------|
| `read_cloudwatch_logs` | `tools/recovery_tools.py` | Calls `logs:FilterLogEvents` — returns all recent log events including the correct key |
| `restart_step_function` | `tools/recovery_tools.py` | Calls `states:StartExecution` with the correct `api_key` extracted from the logs |

### Agent Configuration

| Item | File | Value |
|------|------|-------|
| Model | `config/model.py` | `anthropic.claude-3-5-sonnet-20241022-v2:0` |
| System prompt | `config/prompts.py` | Instructs the agent to read logs → extract key → restart |
| Agent wiring | `main.py` | Instantiates `Agent(model, tools, system_prompt)` |

> **⚠️ Demo Note**: Logging the expected key in CloudWatch is **intentionally insecure** for demonstration purposes only. In production, the correct key would be fetched from AWS Secrets Manager or SSM Parameter Store.

---

## IAM Permissions Summary

| Component | Permissions |
|-----------|-------------|
| ValidateKey Lambda | `logs:CreateLogStream`, `logs:PutLogEvents` (own log group) |
| Strands Agent Lambda | `bedrock:InvokeModel`, `logs:FilterLogEvents` (ValidateKey log group), `states:StartExecution` |
| Step Function | `lambda:InvokeFunction` (ValidateKey + Strands Agent ARNs) |

---

## Teardown

Destroy in reverse dependency order:

```bash
cd step_function/terraform && terraform destroy -auto-approve
cd ../../ai_agent/terraform && terraform destroy -auto-approve
cd ../../Lambda/terraform   && terraform destroy -auto-approve
```
