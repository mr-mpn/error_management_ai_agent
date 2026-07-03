"""
tools/recovery_tools.py
=======================
Strands @tool definitions for the AI error-recovery agent.

The two tools share a module-level runtime context dict (_ctx) that is
populated by main.handler() before the agent runs, so each Lambda
invocation gets the correct log group and state machine ARN without
relying on environment variables alone.
"""

import json
import logging
import os
import time

import boto3
from strands import tool

logger = logging.getLogger(__name__)

# ── Runtime context ───────────────────────────────────────────────────────────
# Populated via set_context() in the Lambda handler before every agent call.
# Thread-safe: Lambda's Python runtime is single-threaded per instance.
_ctx: dict = {}


def set_context(log_group_name: str, state_machine_arn: str) -> None:
    """
    Populate the shared runtime context used by both tools.
    Must be called by the Lambda handler before invoking the agent.

    Args:
        log_group_name:    CloudWatch log group of the ValidateKey Lambda.
        state_machine_arn: ARN of the Step Function to restart on recovery.
    """
    global _ctx  # noqa: PLW0603
    _ctx = {
        "log_group_name":    log_group_name,
        "state_machine_arn": state_machine_arn,
    }
    logger.debug(
        "Runtime context set — log_group=%s | sfn_arn=%s",
        log_group_name,
        state_machine_arn,
    )


# ─────────────────────────────────────────────────────────────────────────────
# Tool 1: read_cloudwatch_logs
# ─────────────────────────────────────────────────────────────────────────────
@tool
def read_cloudwatch_logs(minutes_back: int = 15) -> str:
    """
    Fetches recent log events from the failed ValidateKey Lambda's CloudWatch
    log group. The logs contain the correct expected API key in a line that
    includes '[KEY_VALIDATION] Expected API key'. Read these logs carefully
    to locate the correct key value.

    Args:
        minutes_back: How many minutes back to search for log events (default: 15).

    Returns:
        All recent log messages as a single string, one event per line.
        Returns an error description if the call fails.
    """
    log_group_name: str = _ctx.get("log_group_name", "")
    if not log_group_name:
        return "ERROR: log_group_name is not set in runtime context. Cannot read CloudWatch logs."

    logger.info("[TOOL] read_cloudwatch_logs — group=%s, minutes_back=%d",
                log_group_name, minutes_back)

    logs_client = boto3.client("logs", region_name=os.environ.get("AWS_REGION", "eu-west-1"))
    start_time_ms = int((time.time() - minutes_back * 60) * 1000)

    try:
        response = logs_client.filter_log_events(
            logGroupName=log_group_name,
            startTime=start_time_ms,
            limit=50,
        )
        events = response.get("events", [])
        if not events:
            return (
                f"No log events found in '{log_group_name}' for the last "
                f"{minutes_back} minutes. Try increasing minutes_back."
            )

        messages = "\n".join(ev["message"] for ev in events)
        logger.info("[TOOL] read_cloudwatch_logs — returned %d events", len(events))
        return messages

    except Exception as exc:  # pylint: disable=broad-except
        logger.error("[TOOL] read_cloudwatch_logs error: %s", exc)
        return f"Error fetching CloudWatch logs: {exc}"


# ─────────────────────────────────────────────────────────────────────────────
# Tool 2: restart_step_function
# ─────────────────────────────────────────────────────────────────────────────
@tool
def restart_step_function(api_key: str) -> str:
    """
    Starts a new execution of the Step Function using the correct API key.
    Call this ONLY after you have extracted the correct api_key from the logs.

    Args:
        api_key: The correct API key value to pass as input to the Step Function.

    Returns:
        Success message with the new execution ARN, or an error description.
    """
    state_machine_arn: str = _ctx.get("state_machine_arn", "")
    if not state_machine_arn:
        return "ERROR: state_machine_arn is not set in runtime context. Cannot restart Step Function."

    logger.info("[TOOL] restart_step_function — sfn_arn=%s", state_machine_arn)

    sfn_client = boto3.client(
        "stepfunctions",
        region_name=os.environ.get("AWS_REGION", "eu-west-1"),
    )
    try:
        response = sfn_client.start_execution(
            stateMachineArn=state_machine_arn,
            input=json.dumps({"api_key": api_key}),
        )
        new_execution_arn = response["executionArn"]
        logger.info("[TOOL] restart_step_function — new execution: %s", new_execution_arn)
        return (
            f"Step Function restarted successfully.\n"
            f"New execution ARN: {new_execution_arn}\n"
            f"The correct api_key has been supplied. The execution should now SUCCEED."
        )

    except Exception as exc:  # pylint: disable=broad-except
        logger.error("[TOOL] restart_step_function error: %s", exc)
        return f"Error restarting Step Function: {exc}"
