"""Calls Claude to turn a raw capture into structured items."""

import logging
import os
from datetime import datetime

import anthropic

from .prompt import SYSTEM, user_message
from .schema import ParseResult

log = logging.getLogger("sift.parser")

MODEL = "claude-opus-5"

_client: anthropic.Anthropic | None = None


def client() -> anthropic.Anthropic:
    """Built on first use so the module imports without credentials present."""
    global _client
    if _client is None:
        if not (os.environ.get("ANTHROPIC_API_KEY") or os.environ.get("ANTHROPIC_AUTH_TOKEN")):
            raise MissingCredentials(
                "No ANTHROPIC_API_KEY on the server. Put one in server/.env and restart."
            )
        _client = anthropic.Anthropic()
    return _client


class RefusalError(RuntimeError):
    """The model declined to answer. Surfaced to the client rather than swallowed."""


class MissingCredentials(RuntimeError):
    """No API key on the server. Says how to fix it rather than failing opaquely."""


def parse_capture(transcript: str, now: datetime) -> ParseResult:
    response = client().messages.parse(
        model=MODEL,
        max_tokens=8000,
        # The system prompt is the stable prefix; everything volatile (the clock,
        # the date table, the transcript) lives in the user message after it.
        system=[{"type": "text", "text": SYSTEM, "cache_control": {"type": "ephemeral"}}],
        messages=[{"role": "user", "content": user_message(transcript, now)}],
        output_format=ParseResult,
    )

    if response.stop_reason == "refusal":
        detail = getattr(response.stop_details, "explanation", None)
        raise RefusalError(detail or "The model declined to process this capture.")

    log.info(
        "parsed capture: %d chars -> %d items (in=%d, cached=%d, out=%d)",
        len(transcript),
        len(response.parsed_output.items),
        response.usage.input_tokens,
        response.usage.cache_read_input_tokens or 0,
        response.usage.output_tokens,
    )
    return response.parsed_output
