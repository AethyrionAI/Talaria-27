"""Hermes API server executor — HTTP/SSE alternative to the CLI subprocess."""

from __future__ import annotations

import json
import re
from dataclasses import dataclass, field
from typing import AsyncIterator

import httpx

from .hermes_runner import HermesChatResult, HermesConversationMessage


# Tool progress markers injected by the API server's _on_tool_progress callback:
#   f"\n`{emoji} {label}`\n"
# We detect these in the streaming content to emit structured events.
TOOL_PROGRESS_RE = re.compile(r"^\n`([^\n]+)`\n$")

DEFAULT_API_SERVER_URL = "http://localhost:8642"
CONNECT_TIMEOUT = 10.0
READ_TIMEOUT = 300.0  # 5 minutes — long enough for Claude thinking, catches dead connections


@dataclass(frozen=True)
class StreamEvent:
    """A single event from the streaming chat completions endpoint."""

    type: str  # "text_delta" | "tool_activity" | "finish"
    data: str = ""
    label: str = ""
    session_id: str | None = None
    usage: dict | None = None


@dataclass
class HermesAPIExecutor:
    """Talks to the Hermes API server at ``/v1/chat/completions``."""

    api_server_url: str = DEFAULT_API_SERVER_URL
    api_server_key: str | None = None

    def _base_url(self) -> str:
        return self.api_server_url.rstrip("/")

    def _auth_headers(self) -> dict[str, str]:
        headers: dict[str, str] = {}
        if self.api_server_key:
            headers["Authorization"] = f"Bearer {self.api_server_key}"
        return headers

    @staticmethod
    def _api_role(role: str) -> str:
        if role in ("hermes", "voice_hermes"):
            return "assistant"
        if role == "voice_user":
            return "user"
        return role

    def _messages_payload(
        self,
        *,
        latest_user_message: str,
        history: list[HermesConversationMessage] | None,
        attachments: list[dict] | None = None,
    ) -> list[dict]:
        messages: list[dict] = [
            {"role": self._api_role(message.role), "content": message.text}
            for message in history or []
            if message.text.strip()
        ]

        # Build the final user message — may be multipart if attachments are present
        if attachments:
            content_parts: list[dict] = []
            if latest_user_message.strip():
                content_parts.append({"type": "text", "text": latest_user_message})
            for att in attachments:
                att_type = att.get("type", "file")
                mime_type = att.get("mimeType", "application/octet-stream")
                b64_data = att.get("data", "")
                if att_type == "image" or mime_type.startswith("image/"):
                    content_parts.append({
                        "type": "image_url",
                        "image_url": {
                            "url": f"data:{mime_type};base64,{b64_data}",
                        },
                    })
                else:
                    # For non-image files, try to decode as text; skip truly binary files
                    filename = att.get("filename", "file")
                    text_mimes = {
                        "text/", "application/json", "application/xml",
                        "application/yaml", "application/x-yaml",
                    }
                    is_text_like = any(mime_type.startswith(prefix) for prefix in text_mimes)
                    if is_text_like:
                        try:
                            import base64
                            decoded = base64.b64decode(b64_data).decode("utf-8")
                        except (UnicodeDecodeError, Exception):
                            decoded = f"[Could not decode file: {filename}]"
                        content_parts.append({
                            "type": "text",
                            "text": f"--- Attached file: {filename} ({mime_type}) ---\n{decoded}",
                        })
                    elif mime_type == "application/pdf":
                        # PDFs can't be passed as text — note their presence
                        content_parts.append({
                            "type": "text",
                            "text": f"[Attached PDF: {filename} — PDF content analysis is not yet supported through this path]",
                        })
                    else:
                        content_parts.append({
                            "type": "text",
                            "text": f"[Attached file: {filename} ({mime_type}) — binary file content not readable]",
                        })
            messages.append({"role": "user", "content": content_parts})
        else:
            messages.append({"role": "user", "content": latest_user_message})

        return messages

    # ------------------------------------------------------------------
    # Health check
    # ------------------------------------------------------------------

    async def health_check(self) -> bool:
        """Return True if the API server is reachable and healthy."""
        try:
            async with httpx.AsyncClient(timeout=CONNECT_TIMEOUT) as client:
                response = await client.get(
                    f"{self._base_url()}/health",
                    headers=self._auth_headers(),
                )
                if response.status_code == 200:
                    body = response.json()
                    return body.get("status") == "ok"
        except Exception:  # noqa: BLE001
            pass
        return False

    # ------------------------------------------------------------------
    # Non-streaming send
    # ------------------------------------------------------------------

    async def send_message(
        self,
        *,
        latest_user_message: str,
        history: list[HermesConversationMessage] | None = None,
        session_id: str | None = None,
        attachments: list[dict] | None = None,
    ) -> HermesChatResult:
        """Send a single message and wait for the full response."""
        headers = {
            **self._auth_headers(),
            "Content-Type": "application/json",
        }
        if session_id:
            headers["X-Hermes-Session-Id"] = session_id

        payload = {
            "model": "hermes-agent",
            "messages": self._messages_payload(
                latest_user_message=latest_user_message,
                history=history,
                attachments=attachments,
            ),
            "stream": False,
        }

        async with httpx.AsyncClient(
            timeout=httpx.Timeout(connect=CONNECT_TIMEOUT, read=READ_TIMEOUT, write=30.0, pool=30.0),
        ) as client:
            response = await client.post(
                f"{self._base_url()}/v1/chat/completions",
                headers=headers,
                json=payload,
            )
            response.raise_for_status()

            body = response.json()
            result_session_id = response.headers.get("X-Hermes-Session-Id") or session_id

            text = ""
            choices = body.get("choices", [])
            if choices:
                message = choices[0].get("message", {})
                text = message.get("content", "")

            usage = body.get("usage")

            return HermesChatResult(
                text=text.strip(),
                session_id=result_session_id,
                usage=usage,
            )

    # ------------------------------------------------------------------
    # Streaming send
    # ------------------------------------------------------------------

    async def stream_message(
        self,
        *,
        latest_user_message: str,
        history: list[HermesConversationMessage] | None = None,
        session_id: str | None = None,
        attachments: list[dict] | None = None,
    ) -> AsyncIterator[StreamEvent]:
        """Stream a chat completion, yielding events as they arrive."""
        headers = {
            **self._auth_headers(),
            "Content-Type": "application/json",
        }
        if session_id:
            headers["X-Hermes-Session-Id"] = session_id

        payload = {
            "model": "hermes-agent",
            "messages": self._messages_payload(
                latest_user_message=latest_user_message,
                history=history,
                attachments=attachments,
            ),
            "stream": True,
        }

        async with httpx.AsyncClient(
            timeout=httpx.Timeout(connect=CONNECT_TIMEOUT, read=READ_TIMEOUT, write=30.0, pool=30.0),
        ) as client:
            result_session_id = session_id
            accumulated_usage: dict | None = None

            async with client.stream(
                "POST",
                f"{self._base_url()}/v1/chat/completions",
                headers=headers,
                json=payload,
            ) as response:
                response.raise_for_status()
                result_session_id = response.headers.get("X-Hermes-Session-Id") or session_id

                async for raw_line in response.aiter_lines():
                    line = raw_line.strip()
                    if not line:
                        continue
                    if line.startswith(":"):
                        # SSE comment (keepalive), skip
                        continue
                    if line == "data: [DONE]":
                        break
                    if not line.startswith("data: "):
                        continue

                    json_str = line[6:]  # strip "data: " prefix
                    try:
                        chunk = json.loads(json_str)
                    except json.JSONDecodeError:
                        continue

                    choices = chunk.get("choices", [])
                    if not choices:
                        continue

                    choice = choices[0]
                    delta = choice.get("delta", {})
                    finish_reason = choice.get("finish_reason")

                    # Capture usage from the finish chunk
                    chunk_usage = chunk.get("usage")
                    if chunk_usage:
                        accumulated_usage = chunk_usage

                    # Content delta
                    content = delta.get("content")
                    if content:
                        # Check if this is a tool progress marker
                        tool_match = TOOL_PROGRESS_RE.match(content)
                        if tool_match:
                            yield StreamEvent(
                                type="tool_activity",
                                label=tool_match.group(1),
                            )
                        else:
                            yield StreamEvent(
                                type="text_delta",
                                data=content,
                            )

                    if finish_reason == "stop":
                        yield StreamEvent(
                            type="finish",
                            session_id=result_session_id,
                            usage=accumulated_usage,
                        )
                        return

            # If we exited the stream without a finish event, emit one
            yield StreamEvent(
                type="finish",
                session_id=result_session_id,
                usage=accumulated_usage,
            )
