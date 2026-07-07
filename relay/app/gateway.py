"""Client for the Hermes API server (gateway) Sessions API on :8642.

The relay never carries chat traffic — the phone talks to the gateway
directly — so the only way the relay can learn that a run finished is to
ask the gateway itself. This client polls the same reconciliation
endpoint the app uses (`GET /api/sessions/{id}/messages`, verified in
OPEN_ITEMS #38) and reports the assistant reply once it lands.

Environment variables (see Settings):
    GATEWAY_BASE_URL — e.g. http://127.0.0.1:8642 (relay and gateway
                       share a host on OJAMD, so localhost)
    GATEWAY_API_KEY  — the Hermes API_SERVER_KEY (Bearer auth)
"""

from __future__ import annotations

import logging

import httpx

logger = logging.getLogger("hermes.relay.gateway")


class GatewayError(Exception):
    """The gateway could not be reached or answered with an error."""


def _message_text(content: object) -> str:
    """Flatten a stored message's content — plain string or a list of
    {type, text} parts (the same tolerance the iOS client applies)."""
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts: list[str] = []
        for part in content:
            if isinstance(part, dict):
                text = part.get("text")
                if isinstance(text, str) and text:
                    parts.append(text)
        return "\n".join(parts)
    return ""


def extract_completed_reply(messages: list[dict]) -> str | None:
    """Return the assistant reply that concludes the transcript's last
    user turn, or None if the run hasn't finished.

    Watermark is positional, not clock-based: completion means a
    non-empty assistant message appears AFTER the last user message.
    Both sides of the comparison come from the gateway's own transcript,
    so phone/host clock skew can't produce a miss. (A watch is only
    registered while the app holds an unresolved pending run, so "last
    assistant follows last user" is exactly the reply the app hasn't
    seen yet — including a run that finished before the first poll.)
    """
    last_user_index: int | None = None
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
            return text
    return None


class GatewayClient:
    """Thin async client for the gateway Sessions API."""

    def __init__(
        self,
        *,
        base_url: str,
        api_key: str,
        timeout_seconds: float = 15.0,
        transport: httpx.AsyncBaseTransport | None = None,
    ):
        self.base_url = base_url.rstrip("/")
        self._api_key = api_key
        self._timeout = timeout_seconds
        self._transport = transport
        self._client: httpx.AsyncClient | None = None

    def _get_client(self) -> httpx.AsyncClient:
        if self._client is None or self._client.is_closed:
            self._client = httpx.AsyncClient(
                timeout=self._timeout,
                transport=self._transport,
            )
        return self._client

    async def fetch_completed_reply(self, session_id: str) -> str | None:
        """One poll: the session's completed assistant reply, or None.

        Raises GatewayError on transport/HTTP/parse failures so the
        caller can count consecutive failures separately from
        "run still in flight".
        """
        url = f"{self.base_url}/api/sessions/{session_id}/messages"
        try:
            response = await self._get_client().get(
                url,
                headers={"Authorization": f"Bearer {self._api_key}"},
            )
        except (httpx.TimeoutException, httpx.TransportError, OSError) as e:
            raise GatewayError(f"gateway unreachable: {e}") from e

        if response.status_code != 200:
            raise GatewayError(f"gateway returned {response.status_code} for session {session_id}")

        try:
            body = response.json()
        except ValueError as e:
            raise GatewayError(f"gateway returned non-JSON body: {e}") from e

        messages = body.get("data") if isinstance(body, dict) else None
        if not isinstance(messages, list):
            raise GatewayError("gateway response missing 'data' message list")

        return extract_completed_reply([m for m in messages if isinstance(m, dict)])

    async def close(self):
        if self._client and not self._client.is_closed:
            await self._client.aclose()


def create_gateway_client(settings) -> GatewayClient | None:
    """Create a GatewayClient from Settings, or None if not configured."""
    if not settings.gateway_api_key:
        logger.info("Gateway polling not configured (missing GATEWAY_API_KEY)")
        return None
    client = GatewayClient(
        base_url=settings.gateway_base_url,
        api_key=settings.gateway_api_key,
    )
    logger.info("Gateway client initialized (%s)", settings.gateway_base_url)
    return client
