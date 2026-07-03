"""
ValidateKey Lambda
==================
Validates the `api_key` field in the Step Function input against the
EXPECTED_KEY environment variable.

Demo behaviour (intentional, NOT production practice):
  - Logs the expected key in plaintext so the Strands AI agent can read
    it from CloudWatch logs and use it to restart the Step Function.

Flow:
  - Key matches  → returns {"status": "success"}
  - Key mismatch → raises ValueError → Lambda FAILS → Step Function Catch fires
"""

import json
import logging
import os

logger = logging.getLogger()
logger.setLevel(logging.INFO)

EXPECTED_KEY: str = os.environ.get("EXPECTED_KEY", "")


def handler(event: dict, context) -> dict:
    """
    Lambda entry point.

    Args:
        event: Step Function input, expected shape: {"api_key": "<value>"}
        context: Lambda context (unused)

    Returns:
        {"status": "success"} on success.

    Raises:
        ValueError: when the provided api_key does not match EXPECTED_KEY.
    """
    provided_key: str = event.get("api_key", "")

    # ── Intentional demo logging — AI agent will read this from CloudWatch ──
    # WARNING: logging secrets in plaintext is NOT acceptable in production.
    logger.info(
        json.dumps(
            {
                "event": "KEY_VALIDATION_START",
                "message": "Starting API key validation",
                "[KEY_VALIDATION] Expected API key": EXPECTED_KEY,
                "[KEY_VALIDATION] Provided API key": provided_key,
            }
        )
    )

    if provided_key != EXPECTED_KEY:
        error_msg = (
            f"[KEY_VALIDATION] FAILED: "
            f"Provided key '{provided_key}' does not match the expected key '{EXPECTED_KEY}'. "
            f"The correct key is: {EXPECTED_KEY}"
        )
        logger.error(error_msg)
        raise ValueError(error_msg)

    logger.info(
        json.dumps(
            {
                "event": "KEY_VALIDATION_SUCCESS",
                "message": "API key validated successfully",
            }
        )
    )
    return {"status": "success", "message": "API key validated successfully"}
