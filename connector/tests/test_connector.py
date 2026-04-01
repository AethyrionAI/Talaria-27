from __future__ import annotations

import base64
import json

from hermes_mobile_connector.client import HermesMobileConnector
from hermes_mobile_connector.hermes_runner import ConnectorHermesSettings, HermesCLIExecutor
from hermes_mobile_connector.setup_code import decode_host_setup_code
from hermes_mobile_connector.state import ConnectorState, ConnectorStateStore


def make_executor() -> HermesCLIExecutor:
    return HermesCLIExecutor(
        ConnectorHermesSettings(
            hermes_command="hermes",
            hermes_workdir=None,
            hermes_provider=None,
            hermes_model=None,
            hermes_toolsets=None,
            hermes_source="tool",
            hermes_history_limit=20,
        )
    )


def test_decode_host_setup_code_roundtrip():
    payload = {
        "relay_url": "https://relay.example.com/v1",
        "enrollment_token": "token-123",
        "expires_at": "2026-03-31T16:00:00+00:00",
    }
    encoded = base64.urlsafe_b64encode(
        json.dumps(payload, separators=(",", ":"), sort_keys=True).encode("utf-8")
    ).decode("utf-8").rstrip("=")
    code = f"HC1:{encoded}"
    decoded = decode_host_setup_code(code)
    assert decoded.relay_url == "https://relay.example.com/v1"
    assert decoded.enrollment_token == "token-123"


def test_state_store_persists_with_restricted_permissions(tmp_path):
    store = ConnectorStateStore(state_dir=tmp_path / "connector-state")
    state = ConnectorState(
        relay_url="https://relay.example.com/v1",
        web_socket_url="wss://relay.example.com/v1/hosts/ws",
        user_id="user-123",
        host_id="host-123",
        connector_credential="secret",
        owner_display_name="Taylor",
        connector_display_name="Home Mac mini",
        enrolled_at="2026-03-31T16:00:00+00:00",
    )
    store.save(state)
    loaded = store.load()
    assert loaded.host_id == "host-123"
    assert loaded.user_id == "user-123"
    assert store.state_path.exists()


def test_setup_creates_connector_state(monkeypatch, tmp_path):
    store = ConnectorStateStore(state_dir=tmp_path / "connector-setup")
    connector = HermesMobileConnector(state_store=store, executor=make_executor())
    monkeypatch.setattr(connector.executor, "detect_version", lambda: "Hermes 1.2.3")

    class FakeResponse:
        def raise_for_status(self) -> None:
            return None

        def json(self) -> dict:
            return {
                "data": {
                    "user": {"id": "user-123", "displayName": "Taylor"},
                    "host": {"id": "host-123", "userId": "user-123"},
                    "connectorCredential": "secret-token",
                    "webSocketURL": "wss://relay.example.com/v1/hosts/ws",
                    "relayURL": "https://relay.example.com/v1",
                }
            }

    def fake_post(url, json=None, timeout=None, headers=None):  # noqa: ANN001
        assert url == "https://relay.example.com/v1/connector/setup"
        assert json["ownerDisplayName"] == "Taylor"
        assert json["hostDisplayName"] == "Home Mac mini"
        return FakeResponse()

    monkeypatch.setattr("hermes_mobile_connector.client.httpx.post", fake_post)

    state = connector.setup(
        owner_display_name="Taylor",
        host_display_name="Home Mac mini",
        relay_url="https://relay.example.com/v1",
    )

    assert state.user_id == "user-123"
    assert state.host_id == "host-123"
    assert state.owner_display_name == "Taylor"
    assert state.connector_display_name == "Home Mac mini"


def test_pair_phone_uses_stored_connector_credential(monkeypatch, tmp_path):
    store = ConnectorStateStore(state_dir=tmp_path / "connector-pair")
    store.save(
        ConnectorState(
            relay_url="https://relay.example.com/v1",
            web_socket_url="wss://relay.example.com/v1/hosts/ws",
            user_id="user-123",
            host_id="host-123",
            connector_credential="secret-token",
            owner_display_name="Taylor",
            connector_display_name="Home Mac mini",
        )
    )
    connector = HermesMobileConnector(state_store=store, executor=make_executor())

    class FakeResponse:
        def raise_for_status(self) -> None:
            return None

        def json(self) -> dict:
            return {
                "data": {
                    "code": "ABCDEFGH",
                    "displayCode": "ABCD-EFGH",
                    "expiresAt": "2026-03-31T16:00:00+00:00",
                }
            }

    def fake_post(url, json=None, timeout=None, headers=None):  # noqa: ANN001
        assert url == "https://relay.example.com/v1/connector/phone-pairing-codes"
        assert headers == {"Authorization": "Bearer secret-token"}
        assert json is None
        return FakeResponse()

    monkeypatch.setattr("hermes_mobile_connector.client.httpx.post", fake_post)

    pairing = connector.create_phone_pairing_code()
    assert pairing.code == "ABCDEFGH"
    assert pairing.display_code == "ABCD-EFGH"


def test_status_lines_include_core_runtime_details(tmp_path):
    store = ConnectorStateStore(state_dir=tmp_path / "connector-status")
    store.save(
        ConnectorState(
            relay_url="https://relay.example.com/v1",
            web_socket_url="wss://relay.example.com/v1/hosts/ws",
            user_id="user-123",
            host_id="host-123",
            connector_credential="secret",
            owner_display_name="Taylor",
            connector_display_name="Home Mac mini",
            last_connected_at="2026-03-31T16:00:00+00:00",
        )
    )
    connector = HermesMobileConnector(state_store=store, executor=make_executor())
    lines = connector.status_lines()
    assert any("Relay URL: https://relay.example.com/v1" == line for line in lines)
    assert any("User ID: user-123" == line for line in lines)
    assert any("Host ID: host-123" == line for line in lines)


def test_executor_detects_missing_session_and_extracts_session_id():
    executor = make_executor()
    parsed = executor._parse_cli_output(  # noqa: SLF001
        "╭─ ⚕ Hermes\n↻ Resumed session abc\nsession_id: session-123\nSession not found: session-123"
    )
    assert parsed.session_id == "session-123"
    assert parsed.missing_session is True
