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


_APNS_HOSTS = {"sandbox": "https://api.sandbox.push.apple.com",
               "production": "https://api.push.apple.com"}


def build_apns_request(token: str, session_id: str, *, topic: str,
                       environment: str, title: str, body: str):
    host = _APNS_HOSTS[environment]
    url = f"{host}/3/device/{token}"
    headers = {"apns-topic": topic, "apns-push-type": "alert",
               "apns-priority": "10"}
    payload = {"aps": {"alert": {"title": title, "body": body},
                       "sound": "default"},
               "session_id": session_id}
    return url, headers, payload


class WatcherState:
    """Per-session watermarks. Priming is silent: the first observation of a
    session records its current completion (if any) WITHOUT pinging, so a
    gateway restart can never replay old completions as fresh pushes."""

    def __init__(self) -> None:
        self._watermark: dict[str, int] = {}

    def completions_to_ping(self, session_id: str,
                            messages: list[dict]) -> list[int]:
        completion = extract_completion(messages)
        seen = session_id in self._watermark
        current = self._watermark.get(session_id, 0)
        if completion is None:
            if not seen:
                self._watermark[session_id] = 0
            return []
        msg_id, _text = completion
        if not seen:
            self._watermark[session_id] = msg_id
            return []
        if msg_id > current:
            self._watermark[session_id] = msg_id
            return [msg_id]
        return []


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
