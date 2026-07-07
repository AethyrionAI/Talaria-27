"""Push watch (#38): relay polls the gateway for run completion → APNs.

Covers the gateway client's transcript parsing, the /v1/push/watch
endpoint guards, the end-to-end watch → completion → alert-push path,
and cancellation.
"""

from __future__ import annotations

import asyncio
import time

import httpx
import pytest
from sqlalchemy import select

from app.apns import PushResult
from app.gateway import GatewayClient, GatewayError, extract_completed_reply
from app.models import Device

from test_api import build_client, register_device


# ---------------------------------------------------------------------------
# extract_completed_reply — the positional completion watermark
# ---------------------------------------------------------------------------

def test_extract_reply_requires_assistant_after_last_user():
    messages = [
        {"role": "user", "content": "first question"},
        {"role": "assistant", "content": "first answer"},
        {"role": "user", "content": "pending question"},
    ]
    assert extract_completed_reply(messages) is None

    messages.append({"role": "assistant", "content": "fresh answer"})
    assert extract_completed_reply(messages) == "fresh answer"


def test_extract_reply_skips_empty_and_tool_rows():
    messages = [
        {"role": "user", "content": "question"},
        {"role": "tool", "content": "tool output"},
        {"role": "assistant", "content": "   "},
        {"role": "assistant", "content": [{"type": "text", "text": "part one"}, {"type": "text", "text": "part two"}]},
    ]
    assert extract_completed_reply(messages) == "part one\npart two"


def test_extract_reply_none_without_user_message():
    assert extract_completed_reply([]) is None
    assert extract_completed_reply([{"role": "assistant", "content": "orphan"}]) is None


# ---------------------------------------------------------------------------
# GatewayClient — HTTP behavior via MockTransport
# ---------------------------------------------------------------------------

def make_gateway_client(handler) -> GatewayClient:
    return GatewayClient(
        base_url="http://gateway.test:8642",
        api_key="test-api-server-key",
        transport=httpx.MockTransport(handler),
    )


def fetch_once(handler, session_id: str = "sess-1"):
    async def run():
        client = make_gateway_client(handler)
        try:
            return await client.fetch_completed_reply(session_id)
        finally:
            await client.close()
    return asyncio.run(run())


def test_gateway_client_fetches_completed_reply():
    seen = {}

    def handler(request: httpx.Request) -> httpx.Response:
        seen["url"] = str(request.url)
        seen["auth"] = request.headers.get("Authorization")
        return httpx.Response(200, json={
            "session_id": "sess-1",
            "data": [
                {"role": "user", "content": "ping"},
                {"role": "assistant", "content": "pong"},
            ],
        })

    assert fetch_once(handler) == "pong"
    assert seen["url"] == "http://gateway.test:8642/api/sessions/sess-1/messages"
    assert seen["auth"] == "Bearer test-api-server-key"


def test_gateway_client_raises_on_http_error():
    with pytest.raises(GatewayError):
        fetch_once(lambda request: httpx.Response(401, text="unauthorized"))


def test_gateway_client_raises_on_malformed_body():
    with pytest.raises(GatewayError):
        fetch_once(lambda request: httpx.Response(200, json={"nope": True}))


# ---------------------------------------------------------------------------
# /v1/push/watch endpoint
# ---------------------------------------------------------------------------

class StubAPNsClient:
    def __init__(self) -> None:
        self.alerts = []

    async def send_alert_push(
        self,
        token: str,
        *,
        title: str,
        body: str,
        category: str | None = None,
        bundle_id: str | None = None,
        environment: str | None = None,
        payload_extra: dict | None = None,
    ):
        self.alerts.append({
            "token": token,
            "title": title,
            "body": body,
            "bundle_id": bundle_id,
            "environment": environment,
            "payload_extra": payload_extra,
        })
        return PushResult.SENT


class StubGatewayClient:
    """Scripted gateway: returns each queued result in turn (None =
    run still in flight; GatewayError instances are raised)."""

    def __init__(self, results: list) -> None:
        self.results = list(results)
        self.calls = 0

    async def fetch_completed_reply(self, session_id: str):
        self.calls += 1
        if self.results:
            result = self.results.pop(0)
        else:
            result = None
        if isinstance(result, Exception):
            raise result
        return result


def register_push_token(client, access_token: str, device_id: str) -> None:
    response = client.post(
        "/v1/push/register",
        headers={"Authorization": f"Bearer {access_token}"},
        json={
            "deviceId": device_id,
            "apnsToken": "deadbeef",
            "pushEnvironment": "sandbox",
            "bundleId": "org.aethyrion.talaria",
        },
    )
    assert response.status_code == 200


def wait_for(predicate, timeout_seconds: float = 5.0) -> bool:
    deadline = time.monotonic() + timeout_seconds
    while time.monotonic() < deadline:
        if predicate():
            return True
        time.sleep(0.05)
    return False


def test_watch_rejects_when_gateway_unconfigured(tmp_path):
    with build_client(tmp_path) as client:
        client.app.state.apns_client = StubAPNsClient()
        client.app.state.gateway_client = None
        register_data = register_device(client)
        access_token = register_data["auth"]["accessToken"]

        response = client.post(
            "/v1/push/watch",
            headers={"Authorization": f"Bearer {access_token}"},
            json={"sessionId": "sess-1"},
        )
        assert response.status_code == 503
        assert "GATEWAY_API_KEY" in response.json()["detail"]


def test_watch_rejects_when_apns_unconfigured(tmp_path):
    with build_client(tmp_path) as client:
        client.app.state.apns_client = None
        client.app.state.gateway_client = StubGatewayClient([])
        register_data = register_device(client)
        access_token = register_data["auth"]["accessToken"]

        response = client.post(
            "/v1/push/watch",
            headers={"Authorization": f"Bearer {access_token}"},
            json={"sessionId": "sess-1"},
        )
        assert response.status_code == 503


def test_watch_requires_auth(tmp_path):
    with build_client(tmp_path) as client:
        response = client.post("/v1/push/watch", json={"sessionId": "sess-1"})
        assert response.status_code == 401


def test_watch_completion_sends_push_with_session_id(tmp_path):
    with build_client(
        tmp_path,
        push_watch_poll_seconds=0.05,
        push_watch_fast_window_seconds=60.0,
        push_watch_ttl_seconds=10.0,
    ) as client:
        apns = StubAPNsClient()
        client.app.state.apns_client = apns
        client.app.state.gateway_client = StubGatewayClient([
            None,                       # first poll: run still in flight
            GatewayError("blip"),       # transient gateway failure tolerated
            "The answer is 42.",        # run completed
        ])
        register_data = register_device(client)
        access_token = register_data["auth"]["accessToken"]
        register_push_token(client, access_token, register_data["deviceId"])

        response = client.post(
            "/v1/push/watch",
            headers={"Authorization": f"Bearer {access_token}"},
            json={"sessionId": "sess-42"},
        )
        assert response.status_code == 200
        assert response.json()["data"]["watching"] is True

        assert wait_for(lambda: len(apns.alerts) == 1), "push never fired"
        alert = apns.alerts[0]
        assert alert["token"] == "deadbeef"
        assert alert["title"] == "Hermes"
        assert "42" in alert["body"]
        assert alert["payload_extra"] == {"session_id": "sess-42"}
        assert alert["bundle_id"] == "org.aethyrion.talaria"
        assert alert["environment"] == "sandbox"

        # Watcher removed itself from the registry after firing.
        assert wait_for(lambda: len(client.app.state.push_watchers) == 0)


def test_watch_marks_device_background_and_dedupes(tmp_path):
    with build_client(
        tmp_path,
        push_watch_poll_seconds=0.05,
        push_watch_ttl_seconds=10.0,
    ) as client:
        apns = StubAPNsClient()
        client.app.state.apns_client = apns
        client.app.state.gateway_client = StubGatewayClient([None] * 200)
        register_data = register_device(client)
        access_token = register_data["auth"]["accessToken"]
        register_push_token(client, access_token, register_data["deviceId"])

        # Device reports foreground; the watch request itself must flip it to
        # background so the presence gate can't swallow the eventual push.
        state_response = client.post(
            "/v1/device/app-state",
            headers={"Authorization": f"Bearer {access_token}"},
            json={"state": "foreground"},
        )
        assert state_response.status_code == 200

        first = client.post(
            "/v1/push/watch",
            headers={"Authorization": f"Bearer {access_token}"},
            json={"sessionId": "sess-7"},
        )
        assert first.status_code == 200
        assert "deduplicated" not in first.json()["data"]

        with client.app.state.database.session() as db:
            device = db.scalar(select(Device))
            assert device.app_state == "background"

        second = client.post(
            "/v1/push/watch",
            headers={"Authorization": f"Bearer {access_token}"},
            json={"sessionId": "sess-7"},
        )
        assert second.status_code == 200
        assert second.json()["data"]["deduplicated"] is True
        assert len(client.app.state.push_watchers) == 1

        cancel = client.post(
            "/v1/push/watch/cancel",
            headers={"Authorization": f"Bearer {access_token}"},
            json={"sessionId": "sess-7"},
        )
        assert cancel.status_code == 200
        assert cancel.json()["data"]["cancelled"] is True
        assert len(client.app.state.push_watchers) == 0


def test_watch_cancel_is_noop_without_watch(tmp_path):
    with build_client(tmp_path) as client:
        register_data = register_device(client)
        access_token = register_data["auth"]["accessToken"]

        response = client.post(
            "/v1/push/watch/cancel",
            headers={"Authorization": f"Bearer {access_token}"},
            json={"sessionId": "never-watched"},
        )
        assert response.status_code == 200
        assert response.json()["data"]["cancelled"] is False


def test_watch_skips_push_for_foreground_device(tmp_path):
    """If the device is foreground at fire time (user came back and the
    app-state report landed after the watch), the push is suppressed."""
    with build_client(
        tmp_path,
        push_watch_poll_seconds=0.05,
        push_watch_ttl_seconds=10.0,
    ) as client:
        apns = StubAPNsClient()
        client.app.state.apns_client = apns
        gateway = StubGatewayClient([None] * 6 + ["Done."])
        client.app.state.gateway_client = gateway
        register_data = register_device(client)
        access_token = register_data["auth"]["accessToken"]
        register_push_token(client, access_token, register_data["deviceId"])

        response = client.post(
            "/v1/push/watch",
            headers={"Authorization": f"Bearer {access_token}"},
            json={"sessionId": "sess-fg"},
        )
        assert response.status_code == 200

        # User returns to the app before the run completes.
        state_response = client.post(
            "/v1/device/app-state",
            headers={"Authorization": f"Bearer {access_token}"},
            json={"state": "foreground"},
        )
        assert state_response.status_code == 200

        assert wait_for(lambda: len(client.app.state.push_watchers) == 0), "watcher never finished"
        assert apns.alerts == []
