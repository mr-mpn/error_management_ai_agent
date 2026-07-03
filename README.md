# AI Agent Error Management

> **Purpose**: A demonstration of autonomous AI-driven error recovery using **AWS Step Functions**, **AWS Lambda**, and the **[AWS Strands Agents SDK](https://github.com/strands-agents/sdk-python)** with Claude on Bedrock.

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
3. The Step Function's `Catch` block triggers the **Strands Agent Lambda**.
4. The Strands agent runs a **ReAct loop**: reads CloudWatch logs → finds the correct key → calls `restart_step_function`.
5. A new Step Function execution starts with the correct key and **succeeds**.

---

## Repository Structure

```
ai_agent_error_management/
│
├── Lambda/                          # ValidateKey Lambda
│   ├── main.py                      # Handler — validates api_key vs EXPECTED_KEY env var
│   ├── requirements.txt
│   └── terraform/                   # Terraform module
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
│
├── step_function/                   # Step Function State Machine
│   └── terraform/
│       ├── main.tf                  # ASL definition with Catch block
│       ├── variables.tf
│       └── outputs.tf
│
├── ai_agent/                        # Strands Agent Lambda (the core AI component)
│   ├── main.py                      # Strands Agent with 2 tools
│   ├── requirements.txt             # strands-agents
│   └── terraform/
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
│
└── .github/
    └── workflows/
        └── deploy.yml               # GitHub Actions CI/CD pipeline
```

---

## Prerequisites

| Tool | Version | Notes |
|------|---------|-------|
| Terraform | ≥ 1.5.0 | |
| Python | 3.12 | For building the agent Lambda package |
| AWS CLI | v2 | For manual testing |
| AWS account | — | Claude 3.5 Sonnet must be enabled in Bedrock (eu-west-1) |

---

## AWS Setup

### 1. Create the Terraform State S3 Bucket

```bash
aws s3 mb s3://<your-tf-state-bucket> --region eu-west-1
aws s3api put-bucket-versioning \
  --bucket <your-tf-state-bucket> \
  --versioning-configuration Status=Enabled
```

### 2. Enable Bedrock Model Access

In the AWS console → **Amazon Bedrock → Model access** (eu-west-1), request access for:
- `Anthropic / Claude 3.5 Sonnet`

### 3. Create GitHub Actions OIDC IAM Role

Create an IAM role trusted by GitHub Actions OIDC:

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Federated": "arn:aws:iam::<ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com" },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
      },
      "StringLike": {
        "token.actions.githubusercontent.com:sub": "repo:<YOUR_GITHUB_ORG>/<YOUR_REPO>:*"
      }
    }
  }]
}
```

Attach a policy granting permissions for: Lambda, IAM, S3 (state bucket), Step Functions, CloudWatch Logs, Bedrock.

### 4. Set GitHub Secrets

In your GitHub repository → **Settings → Secrets and variables → Actions**:

| Secret | Value |
|--------|-------|
| `AWS_DEPLOY_ROLE_ARN` | ARN of the OIDC IAM role created above |
| `TF_STATE_BUCKET` | Name of your Terraform state S3 bucket |
| `EXPECTED_API_KEY` | The correct API key (e.g., `my-secret-key-2024`) |

---

## Deployment

### Via GitHub Actions (CI/CD)

Push to `main` — the pipeline runs automatically in 3 sequential jobs:

```
Job 1: Deploy ValidateKey Lambda
Job 2: Build & Deploy Strands Agent Lambda
Job 3: Deploy Step Function
```

### Manual Deployment (local)

#### Step 1 — ValidateKey Lambda

```bash
cd Lambda/terraform
terraform init -backend-config="bucket=<your-tf-state-bucket>"
terraform apply -var="expected_key=<your-secret-key>"
```

#### Step 2 — Strands Agent Lambda

```bash
cd ai_agent

# Build the deployment package
pip install -r requirements.txt -t package/
cp main.py package/
cd package && zip -r ../lambda_package.zip . && cd ..

cd terraform
terraform init -backend-config="bucket=<your-tf-state-bucket>"
terraform apply \
  -var="validate_key_log_group_name=$(cd ../../Lambda/terraform && terraform output -raw log_group_name)"
```

#### Step 3 — Step Function

```bash
cd step_function/terraform
terraform init -backend-config="bucket=<your-tf-state-bucket>"
terraform apply \
  -var="validate_key_function_arn=$(cd ../../Lambda/terraform && terraform output -raw function_arn)" \
  -var="strands_agent_function_arn=$(cd ../../ai_agent/terraform && terraform output -raw agent_function_arn)" \
  -var="validate_key_log_group_name=$(cd ../../Lambda/terraform && terraform output -raw log_group_name)"
```

---

## Testing the End-to-End Flow

### 1. Get the State Machine ARN

```bash
cd step_function/terraform
SF_ARN=$(terraform output -raw state_machine_arn)
echo $SF_ARN
```

### 2. Start an Execution with the WRONG Key (triggers failure + AI recovery)

```bash
aws stepfunctions start-execution \
  --state-machine-arn "$SF_ARN" \
  --input '{"api_key": "wrong-key-intentional-fail"}' \
  --region eu-west-1
```

### 3. Watch the Execution

```bash
# Poll execution status
aws stepfunctions describe-execution \
  --execution-arn "<execution-arn-from-step-2>" \
  --region eu-west-1
```

### 4. Verify Recovery

After ~30-60 seconds you should see:
- Execution 1 (with wrong key): status `SUCCEEDED` — the `InvokeAIAgent` state completed
- A new Execution 2 (with correct key): status `SUCCEEDED` — started by the AI agent

Check the Strands Agent Lambda logs in CloudWatch for the full agent trace:
```bash
aws logs tail /aws/lambda/ai-agent-strands-error-recovery --follow --region eu-west-1
```

---

## AI Agent Details

### Strands SDK ReAct Loop

The agent uses the **Strands Agents SDK** which implements the [ReAct (Reason + Act)](https://arxiv.org/abs/2210.03629) pattern:

```
Thought → which tool do I need?
Act     → call the tool
Observe → read the result
Thought → what should I do next?
... repeat until task complete
```

### Tools

| Tool | Purpose |
|------|---------|
| `read_cloudwatch_logs` | Calls `logs:FilterLogEvents` on the ValidateKey Lambda's log group. Returns all recent messages, including the line with the correct key. |
| `restart_step_function` | Calls `states:StartExecution` with the correct `api_key` to relaunch the workflow. |

### System Prompt Key Instructions

The agent is instructed to:
1. Read logs and find the line: `[KEY_VALIDATION] Expected API key: <value>`
2. Extract the key value precisely
3. Call `restart_step_function` with that key
4. Report the outcome

> **⚠️ Demo Note**: Logging the expected key in CloudWatch is **intentionally insecure** for demonstration purposes. In a real system, the correct action would be fetched from AWS Secrets Manager or SSM Parameter Store.

---

## IAM Permissions Summary

| Component | Permissions |
|-----------|-------------|
| ValidateKey Lambda | `logs:CreateLogStream`, `logs:PutLogEvents` (own log group) |
| Strands Agent Lambda | `bedrock:InvokeModel`, `logs:FilterLogEvents` (ValidateKey log group), `states:StartExecution` |
| Step Function | `lambda:InvokeFunction` (both Lambda ARNs) |

---

## Teardown

```bash
# Destroy in reverse dependency order
cd step_function/terraform && terraform destroy -auto-approve
cd ai_agent/terraform      && terraform destroy -auto-approve
cd Lambda/terraform        && terraform destroy -auto-approve
```
