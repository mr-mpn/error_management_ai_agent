"""config package — exposes the BedrockModel instance and the system prompt."""

from .model import bedrock_model, BEDROCK_MODEL_ID
from .prompts import SYSTEM_PROMPT

__all__ = ["bedrock_model", "BEDROCK_MODEL_ID", "SYSTEM_PROMPT"]
