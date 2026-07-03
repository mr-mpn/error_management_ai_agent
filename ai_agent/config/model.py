"""
config/model.py
===============
Bedrock foundation model instance shared across the application.
Initialised once at module load time so it is reused on warm Lambda starts.
"""

import os

from strands.models.bedrock import BedrockModel

# Amazon Nova Pro — AWS's own foundation model with strong tool-use support.
# Uses the eu. cross-region inference profile prefix required in eu-west-1.
BEDROCK_MODEL_ID: str = os.environ.get(
    "BEDROCK_MODEL_ID",
    "eu.amazon.nova-pro-v1:0",
)

bedrock_model = BedrockModel(
    model_id=BEDROCK_MODEL_ID,
    region_name=os.environ.get("AWS_REGION", "eu-west-1"),
)
