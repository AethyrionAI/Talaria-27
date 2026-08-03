"""Pure logic for the talaria-push hook. No IO, no deps — fully unit-tested.

The completion predicate is the relay's `extract_completed_reply`
(relay/app/gateway.py:44) ported verbatim, extended to return the concluding
assistant message's id so the watcher can watermark it.
"""
from __future__ import annotations

from typing import Any


def _message_text(content: object) -> str:
    if isinstance(content, str):
        return content
    if isinstance(content, list):  # structured parts
        chunks = []
        for part in content:
            if isinstance(part, dict) and isinstance(part.get("text"), str):
                chunks.append(part["text"])
        return "".join(chunks)
    return ""


def extract_completion(messages: list[dict[str, Any]]) -> tuple[int, str] | None:
    """(assistant_message_id, text) concluding the last user turn, else None."""
    last_user_index = None
    for index, message in enumerate(messages):
        if str(message.get("role", "")).lower() == "user":
            last_user_index = index
    if last_user_index is None:
        return None
    for message in messages[last_user_index + 1:]:
        if str(message.get("role", "")).lower() != "assistant":
            continue
        text = _message_text(message.get("content")).strip()
        if text:
            try:
                return int(message.get("id")), text
            except (TypeError, ValueError):
                return None
    return None
