"""#45 — agent → phone inbox producer tools (send_inbox_item / get_inbox_verdict)."""

from __future__ import annotations

import json

import pytest

from hermes_mobile_connector import mcp_server
from hermes_mobile_connector.state import (
    ConnectorSecrets,
    ConnectorState,
    ConnectorStateStore,
)


def make_state() -> ConnectorState:
    return ConnectorState(
        relay_url="https://relay.example.com/v1",
        web_socket_url="wss://relay.example.com/v1/hosts/ws",
        user_id="user-123",
        host_id="host-123",
        connector_credential="secret",
    )


@pytest.fixture()
def connector_home(tmp_path, monkeypatch):
    home = tmp_path / "connector-home"
    monkeypatch.setenv("HERMES_MOBILE_CONNECTOR_HOME", str(home))
    monkeypatch.delenv("HERMES_MOBILE_INTERNAL_API_KEY", raising=False)
    monkeypatch.delenv("INTERNAL_API_KEY", raising=False)
    store = ConnectorStateStore()
    store.save(make_state())
    return store


class FakeResponse:
    def __init__(self, status_code: int = 200, payload: dict | None = None, text: str = ""):
        self.status_code = status_code
        self._payload = payload or {}
        self.text = text

    def json(self) -> dict:
        return self._payload

    def raise_for_status(self) -> None:
        if self.status_code >= 400:
            import httpx

            raise httpx.HTTPStatusError(
                f"HTTP {self.status_code}",
                request=httpx.Request("POST", "https://relay.example.com"),
                response=self,  # duck-typed: only .status_code/.text are read
            )


class FakeHTTPClient:
    """Stands in for httpx.Client; hands back queued responses and records
    every request so tests can assert URLs, headers, and bodies."""

    queued: list[FakeResponse] = []
    requests: list[tuple[str, str, dict | None, dict | None]] = []

    def __init__(self, *args, **kwargs):
        pass

    def __enter__(self):
        return self

    def __exit__(self, *args):
        return False

    def post(self, url, headers=None, json=None):
        FakeHTTPClient.requests.append(("POST", url, headers, json))
        return FakeHTTPClient.queued.pop(0)

    def get(self, url, headers=None):
        FakeHTTPClient.requests.append(("GET", url, headers, None))
        return FakeHTTPClient.queued.pop(0)


@pytest.fixture()
def fake_http(monkeypatch):
    FakeHTTPClient.queued = []
    FakeHTTPClient.requests = []
    monkeypatch.setattr(mcp_server.httpx, "Client", FakeHTTPClient)
    return FakeHTTPClient


def test_relay_root_url_strips_the_v1_api_base():
    assert mcp_server.relay_root_url("https://relay.example.com/v1") == "https://relay.example.com"
    assert mcp_server.relay_root_url("https://relay.example.com/v1/") == "https://relay.example.com"
    assert mcp_server.relay_root_url("http://100.110.102.59:8000/v1") == "http://100.110.102.59:8000"
    assert mcp_server.relay_root_url("https://relay.example.com") == "https://relay.example.com"


def test_send_inbox_item_rejects_unknown_enum_values():
    assert "Invalid kind" in json.loads(mcp_server.send_inbox_item("t", "b", kind="nag"))["error"]
    assert "Invalid priority" in json.loads(
        mcp_server.send_inbox_item("t", "b", priority="asap")
    )["error"]
    assert "Invalid notify" in json.loads(
        mcp_server.send_inbox_item("t", "b", notify="loudly")
    )["error"]


def test_send_inbox_item_requires_the_internal_key(connector_home):
    result = json.loads(mcp_server.send_inbox_item("Title", "Body"))
    assert "internal" in result["error"].lower()


def test_internal_key_resolution_prefers_env_then_secrets(connector_home, monkeypatch):
    connector_home.save_secrets(ConnectorSecrets(internal_api_key="from-secrets"))
    assert mcp_server._internal_api_key() == "from-secrets"
    monkeypatch.setenv("HERMES_MOBILE_INTERNAL_API_KEY", "from-env")
    assert mcp_server._internal_api_key() == "from-env"


def test_send_inbox_item_posts_create_then_silent_push(connector_home, fake_http):
    connector_home.save_secrets(ConnectorSecrets(internal_api_key="test-key"))
    fake_http.queued = [
        FakeResponse(payload={"data": {"item": {"id": "item-1", "status": "pending"}}}),
        FakeResponse(payload={"data": {"sent": 1}}),
    ]

    result = json.loads(
        mcp_server.send_inbox_item("Approve trip", "Book the train?", kind="approval", priority="high")
    )

    assert result["itemId"] == "item-1"
    assert result["push"] == {"requested": "silent", "sent": 1}

    create = fake_http.requests[0]
    assert create[0] == "POST"
    assert create[1] == "https://relay.example.com/internal/inbox/create"
    assert create[2] == {"X-Relay-Internal-Key": "test-key"}
    assert create[3] == {
        "kind": "approval",
        "title": "Approve trip",
        "body": "Book the train?",
        "priority": "high",
    }

    push = fake_http.requests[1]
    assert push[1] == "https://relay.example.com/v1/push/send"
    assert push[3] == {"user_id": "user-123", "type": "silent"}


def test_send_inbox_item_alert_push_carries_title_and_body(connector_home, fake_http):
    connector_home.save_secrets(ConnectorSecrets(internal_api_key="test-key"))
    fake_http.queued = [
        FakeResponse(payload={"data": {"item": {"id": "item-2", "status": "pending"}}}),
        FakeResponse(payload={"data": {"sent": 2}}),
    ]

    result = json.loads(mcp_server.send_inbox_item("Heads up", "Something happened", notify="alert"))

    assert result["push"]["sent"] == 2
    assert fake_http.requests[1][3] == {
        "user_id": "user-123",
        "type": "alert",
        "title": "Heads up",
        "body": "Something happened",
    }


def test_send_inbox_item_notify_none_skips_the_push(connector_home, fake_http):
    connector_home.save_secrets(ConnectorSecrets(internal_api_key="test-key"))
    fake_http.queued = [
        FakeResponse(payload={"data": {"item": {"id": "item-3", "status": "pending"}}}),
    ]

    result = json.loads(mcp_server.send_inbox_item("Quiet", "No push", notify="none"))

    assert result["itemId"] == "item-3"
    assert result["push"] == {"requested": "none"}
    assert len(fake_http.requests) == 1


def test_send_inbox_item_survives_push_failure(connector_home, fake_http):
    connector_home.save_secrets(ConnectorSecrets(internal_api_key="test-key"))
    fake_http.queued = [
        FakeResponse(payload={"data": {"item": {"id": "item-4", "status": "pending"}}}),
        FakeResponse(status_code=503),  # APNs not configured on the relay
    ]

    result = json.loads(mcp_server.send_inbox_item("Still lands", "Push down"))

    assert result["itemId"] == "item-4"
    assert result["push"]["error"] == "HTTP 503"


def test_get_inbox_verdict_reports_pending_and_decided(connector_home, fake_http):
    connector_home.save_secrets(ConnectorSecrets(internal_api_key="test-key"))

    fake_http.queued = [FakeResponse(payload={"data": {"actions": []}})]
    pending = json.loads(mcp_server.get_inbox_verdict("item-1"))
    assert pending["pending"] is True
    assert fake_http.requests[0][1] == "https://relay.example.com/internal/inbox/item-1/actions"

    fake_http.queued = [
        FakeResponse(
            payload={
                "data": {
                    "actions": [
                        {"actionId": "approve", "actorType": "user", "createdAt": "2026-07-08T00:00:00Z"}
                    ]
                }
            }
        )
    ]
    decided = json.loads(mcp_server.get_inbox_verdict("item-1"))
    assert decided["pending"] is False
    assert decided["actions"][0]["actionId"] == "approve"


def test_secrets_roundtrip_preserves_internal_api_key(tmp_path):
    store = ConnectorStateStore(state_dir=tmp_path / "secrets-home")
    store.save_secrets(ConnectorSecrets(internal_api_key="k-123"))
    assert store.load_secrets().internal_api_key == "k-123"
    # Older secrets.json files (no key) still load.
    store.secrets_path.write_text(json.dumps({"openai_api_key": "sk-x"}), encoding="utf-8")
    assert store.load_secrets().internal_api_key is None


def test_send_inbox_item_rejects_non_string_payload_values():
    result = json.loads(mcp_server.send_inbox_item("t", "b", payload={"count": 3}))
    assert "payload" in result["error"].lower()


def test_send_inbox_item_forwards_payload_when_given(connector_home, fake_http):
    connector_home.save_secrets(ConnectorSecrets(internal_api_key="test-key"))
    fake_http.queued = [
        FakeResponse(payload={"data": {"item": {"id": "item-9", "status": "pending"}}}),
        FakeResponse(payload={"data": {"sent": 1}}),
    ]

    result = json.loads(
        mcp_server.send_inbox_item(
            "Morning briefing — Thu Jul 17",
            "## Sleep\nYou slept 7h 24m.",
            payload={"category": "briefing", "speakable": "Good morning."},
        )
    )

    assert result["itemId"] == "item-9"
    create = fake_http.requests[0]
    assert create[3] == {
        "kind": "notification",
        "title": "Morning briefing — Thu Jul 17",
        "body": "## Sleep\nYou slept 7h 24m.",
        "priority": "normal",
        "payload": {"category": "briefing", "speakable": "Good morning."},
    }


def test_send_inbox_item_empty_payload_stays_omitted(connector_home, fake_http):
    connector_home.save_secrets(ConnectorSecrets(internal_api_key="test-key"))
    fake_http.queued = [
        FakeResponse(payload={"data": {"item": {"id": "item-2", "status": "pending"}}}),
        FakeResponse(payload={"data": {"sent": 1}}),
    ]
    mcp_server.send_inbox_item("t", "b", payload={})
    assert "payload" not in fake_http.requests[0][3]
