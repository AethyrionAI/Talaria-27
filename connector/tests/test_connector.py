from __future__ import annotations

import base64
import json

from hermes_mobile_connector.client import HermesMobileConnector
from hermes_mobile_connector.hermes_runner import ConnectorHermesSettings, HermesCLIExecutor
from hermes_mobile_connector.mcp_registration import (
    MCPRegistrationStatus,
    native_mcp_readiness_message,
    register_native_mcp_server,
)
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
    monkeypatch.setattr(
        "hermes_mobile_connector.client.register_native_mcp_server",
        lambda state_dir: MCPRegistrationStatus(
            server_name="hermes_mobile",
            hermes_home=tmp_path / ".hermes",
            config_path=tmp_path / ".hermes" / "config.yaml",
            command_path="/tmp/hermes-mobile-mcp",
            registered=True,
        ),
    )
    monkeypatch.setattr("hermes_mobile_connector.client.validate_native_mcp_server", lambda hermes_command, server_name: None)
    monkeypatch.setattr("hermes_mobile_connector.client.validate_native_mcp_tools", lambda server_name: None)

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
        assert "connector" in json
        return FakeResponse()

    monkeypatch.setattr("hermes_mobile_connector.client.httpx.post", fake_post)

    state = connector.setup(relay_url="https://relay.example.com/v1")

    assert state.user_id == "user-123"
    assert state.host_id == "host-123"
    assert state.mcp_command_path == "/tmp/hermes-mobile-mcp"
    assert state.mcp_last_test_error is None


def test_setup_can_skip_native_mcp_configuration(monkeypatch, tmp_path):
    store = ConnectorStateStore(state_dir=tmp_path / "connector-setup-skip")
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
        return FakeResponse()

    monkeypatch.setattr("hermes_mobile_connector.client.httpx.post", fake_post)
    monkeypatch.setattr(
        "hermes_mobile_connector.client.register_native_mcp_server",
        lambda state_dir: (_ for _ in ()).throw(AssertionError("register_native_mcp_server should not be called")),
    )

    state = connector.setup(relay_url="https://relay.example.com/v1", configure_mcp=False)

    assert state.user_id == "user-123"
    assert state.host_id == "host-123"
    assert state.mcp_registered_at is None
    assert state.mcp_last_test_error is None


def test_configure_mcp_updates_existing_connector_state(monkeypatch, tmp_path):
    store = ConnectorStateStore(state_dir=tmp_path / "connector-configure-mcp")
    store.save(
        ConnectorState(
            relay_url="https://relay.example.com/v1",
            web_socket_url="wss://relay.example.com/v1/hosts/ws",
            user_id="user-123",
            host_id="host-123",
            connector_credential="secret-token",
        )
    )
    connector = HermesMobileConnector(state_store=store, executor=make_executor())
    monkeypatch.setattr(connector.executor, "detect_version", lambda: "Hermes 1.2.3")
    monkeypatch.setattr(
        "hermes_mobile_connector.client.register_native_mcp_server",
        lambda state_dir: MCPRegistrationStatus(
            server_name="hermes_mobile",
            hermes_home=tmp_path / ".hermes",
            config_path=tmp_path / ".hermes" / "config.yaml",
            command_path="/tmp/hermes-mobile-mcp",
            registered=True,
        ),
    )
    monkeypatch.setattr("hermes_mobile_connector.client.validate_native_mcp_server", lambda hermes_command, server_name: None)
    monkeypatch.setattr("hermes_mobile_connector.client.validate_native_mcp_tools", lambda server_name: None)

    state = connector.configure_mcp()

    assert state.host_id == "host-123"
    assert state.mcp_command_path == "/tmp/hermes-mobile-mcp"
    assert state.mcp_registered_at is not None
    assert state.mcp_last_test_error is None


def test_pair_phone_uses_stored_connector_credential(monkeypatch, tmp_path):
    store = ConnectorStateStore(state_dir=tmp_path / "connector-pair")
    store.save(
        ConnectorState(
            relay_url="https://relay.example.com/v1",
            web_socket_url="wss://relay.example.com/v1/hosts/ws",
            user_id="user-123",
            host_id="host-123",
            connector_credential="secret-token",
    
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


def test_register_native_mcp_server_updates_existing_hermes_config(monkeypatch, tmp_path):
    hermes_home = tmp_path / ".hermes"
    hermes_home.mkdir(parents=True)
    config_path = hermes_home / "config.yaml"
    config_path.write_text(
        "model: gpt-5.4\n"
        "mcp_servers:\n"
        "  other:\n"
        "    command: other-mcp\n",
        encoding="utf-8",
    )
    monkeypatch.setenv("HERMES_HOME", str(hermes_home))
    monkeypatch.setattr(
        "hermes_mobile_connector.mcp_registration.resolve_mcp_command_path",
        lambda: tmp_path / "bin" / "hermes-mobile-mcp",
    )

    status = register_native_mcp_server(state_dir=tmp_path / "connector-state")
    second_status = register_native_mcp_server(state_dir=tmp_path / "connector-state")

    text = config_path.read_text(encoding="utf-8")
    assert status.registered is True
    assert second_status.registered is True
    assert text.count("hermes_mobile:") == 1
    assert "other:" in text
    assert "HERMES_MOBILE_CONNECTOR_HOME" in text


def test_status_lines_include_core_runtime_details(tmp_path):
    store = ConnectorStateStore(state_dir=tmp_path / "connector-status")
    store.save(
        ConnectorState(
            relay_url="https://relay.example.com/v1",
            web_socket_url="wss://relay.example.com/v1/hosts/ws",
            user_id="user-123",
            host_id="host-123",
            connector_credential="secret",
    
            connector_display_name="Home Mac mini",
            last_connected_at="2026-03-31T16:00:00+00:00",
            mcp_command_path="/tmp/hermes-mobile-mcp",
        )
    )
    connector = HermesMobileConnector(state_store=store, executor=make_executor())
    lines = connector.status_lines()
    assert any("Relay URL: https://relay.example.com/v1" == line for line in lines)
    assert any("User ID: user-123" == line for line in lines)
    assert any("Host ID: host-123" == line for line in lines)
    assert any("Native MCP config: missing" in line or "Native MCP config: present" in line for line in lines)


def test_status_lines_show_mcp_not_configured_hint(tmp_path):
    store = ConnectorStateStore(state_dir=tmp_path / "connector-status-mcp-hint")
    store.save(
        ConnectorState(
            relay_url="https://relay.example.com/v1",
            web_socket_url="wss://relay.example.com/v1/hosts/ws",
            user_id="user-123",
            host_id="host-123",
            connector_credential="secret",
        )
    )
    connector = HermesMobileConnector(state_store=store, executor=make_executor())

    lines = connector.status_lines()

    assert any("MCP validation: not configured" in line for line in lines)


def test_native_mcp_readiness_requires_reload_when_chat_process_is_running(monkeypatch):
    class FakeProcess:
        returncode = 0
        stdout = " 123 /usr/local/bin/hermes chat\n"

    monkeypatch.setattr(
        "hermes_mobile_connector.mcp_registration.subprocess.run",
        lambda *args, **kwargs: FakeProcess(),
    )

    message = native_mcp_readiness_message(hermes_command="/usr/local/bin/hermes")
    assert message.startswith("Reload required")


def test_native_mcp_readiness_reports_ready_when_no_chat_process_is_running(monkeypatch):
    class FakeProcess:
        returncode = 0
        stdout = " 123 /usr/bin/python something-else\n"

    monkeypatch.setattr(
        "hermes_mobile_connector.mcp_registration.subprocess.run",
        lambda *args, **kwargs: FakeProcess(),
    )

    message = native_mcp_readiness_message(hermes_command="/usr/local/bin/hermes")
    assert message.startswith("Ready now")


def test_state_store_clear_removes_state(tmp_path):
    store = ConnectorStateStore(state_dir=tmp_path / "connector-clear")
    store.save(
        ConnectorState(
            relay_url="https://relay.example.com/v1",
            web_socket_url="wss://relay.example.com/v1/hosts/ws",
            user_id="user-123",
            host_id="host-123",
            connector_credential="secret",
        )
    )
    assert store.state_path.exists()
    store.clear()
    assert not store.state_path.exists()
    assert not store.state_dir.exists()


def test_executor_detects_missing_session_and_extracts_session_id():
    executor = make_executor()
    parsed = executor._parse_cli_output(  # noqa: SLF001
        "╭─ ⚕ Hermes\n↻ Resumed session abc\nsession_id: session-123\nSession not found: session-123"
    )
    assert parsed.session_id == "session-123"
    assert parsed.missing_session is True
