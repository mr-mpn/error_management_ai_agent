"""
config/model.py
===============
Bedrock foundation model instance shared across the application.
Initialised once at module load time so it is reused on warm Lambda starts.
"""

import os

from strands.models.bedrock import BedrockModel

# Model ID defaults to Claude 3.5 Sonnet; can be overridden via env var.
BEDROCK_MODEL_ID: str = os.environ.get(
    "BEDROCK_MODEL_ID",
    "anthropic.claude-3-5-sonnet-20241022-v2:0",
)

bedrock_model = BedrockModel(
    model_id=BEDROCK_MODEL_ID,
    region_name=os.environ.get("AWS_REGION", "eu-west-1"),
)
