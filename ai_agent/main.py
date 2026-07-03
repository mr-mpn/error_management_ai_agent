"""
AI Agent Lambda — Entry Point
==============================
Thin Lambda handler that wires together the Strands agent, its tools, the
Bedrock model, and the system prompt — all imported from sub-packages.

Package layout:
  main.py              ← this file (Lambda handler)
  tools/
    __init__.py
    recovery_tools.py  ← @tool definitions + runtime context
  config/
    __init__.py
    model.py           ← BedrockModel instance
    prompts.py         ← SYSTEM_PROMPT constant
"""

import json
import logging
import os

from strands import Agent

from config import bedrock_model, SYSTEM_PROMPT
from tools import read_cloudwatch_logs, restart_step_function, set_context

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# ── Strands Agent — module-level for warm-start reuse ─────────────────────────
_agent = Agent(
    model=bedrock_model,
    tools=[read_cloudwatch_logs, restart_step_function],
    system_prompt=SYSTEM_PROMPT,
)


# ── Lambda Handler ─────────────────────────────────────────────────────────────
def handler(event: dict, context) -> dict:
    """
    Entry point called by the Step Function's Catch → InvokeAIAgent state.

    Expected event shape (assembled by the Step Function ASL):
    {
      "error":             {"Error": "...", "Cause": "..."},
      "original_input":    {"api_key": "<wrong-value>"},
      "execution_arn":     "arn:aws:states:...",
      "state_machine_arn": "arn:aws:states:...:stateMachine:...",
      "log_group_name":    "/aws/lambda/ai-agent-validate-key"
    }
    """
    # ── Populate shared runtime context for tools ─────────────────────────────
    set_context(
        log_group_name=event.get("log_group_name",
                                 os.environ.get("LOG_GROUP_NAME", "")),
        state_machine_arn=event.get("state_machine_arn",
                                    os.environ.get("STATE_MACHINE_ARN", "")),
    )

    error_info     = event.get("error", {})
    execution_arn  = event.get("execution_arn", "N/A")
    original_input = event.get("original_input", {})

    logger.info(json.dumps({
        "event":         "AGENT_TRIGGERED",
        "execution_arn": execution_arn,
        "error_type":    error_info.get("Error"),
    }))

    # ── Build the agent prompt ────────────────────────────────────────────────
    prompt = (
        "A Step Function execution has FAILED and requires immediate autonomous recovery.\n\n"
        f"  Failed Execution ARN : {execution_arn}\n"
        f"  Error Type           : {error_info.get('Error', 'Unknown')}\n"
        f"  Error Cause          : {error_info.get('Cause', 'Unknown')}\n"
        f"  Original Input       : {json.dumps(original_input)}\n\n"
        "The Lambda rejected the api_key in the original input because it did not "
        "match the expected key. Follow your instructions: read the CloudWatch logs, "
        "extract the correct api_key, and restart the Step Function."
    )

    # ── Run the Strands agent (synchronous ReAct loop) ────────────────────────
    response   = _agent(prompt)
    agent_text = str(response)

    logger.info(json.dumps({
        "event":            "AGENT_COMPLETED",
        "response_preview": agent_text[:500],
    }))

    return {"agent_response": agent_text, "recovered": True}
