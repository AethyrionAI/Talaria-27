from __future__ import annotations

import pytest

from hermes_mobile_connector.client import HermesMobileConnector, _phone_reachable_host
from hermes_mobile_connector.hermes_runner import ConnectorHermesSettings, HermesCLIExecutor
from hermes_mobile_connector.state import (
    ConnectorRuntimeConfig,
    ConnectorState,
    ConnectorStateStore,
)


PROVISIONING_ENV_VARS = (
    "TALARIA_SHIM_TOKEN_FILE",
    "TALARIA_SHIM_BASE_URL",
    "TALARIA_GATEWAY_BASE_URL",
    "TALARIA_PROVISIONING_HOST",
    "HERMES_API_SERVER_URL",
)


@pytest.fixture(autouse=True)
def clean_provisioning_env(monkeypatch):
    """The descriptor reads env overrides — start every test from none."""
    for name in PROVISIONING_ENV_VARS:
        monkeypatch.delenv(name, raising=False)


def make_connector(tmp_path) -> HermesMobileConnector:
    return HermesMobileConnector(
        state_store=ConnectorStateStore(state_dir=tmp_path / "connector"),
        executor=HermesCLIExecutor(
            ConnectorHermesSettings(
                hermes_command="hermes",
                hermes_workdir=None,
                hermes_provider=None,
                hermes_model=None,
                hermes_toolsets=None,
                hermes_source="tool",
                hermes_history_limit=20,
            )
        ),
    )


def make_state(
    relay_url: str = "http://100.79.222.100:8000/v1",
    runtime_config: ConnectorRuntimeConfig | None = None,
) -> ConnectorState:
    return ConnectorState(
        relay_url=relay_url,
        web_socket_url="ws://100.79.222.100:8000/v1/hosts/ws",
        host_id="host-123",
        connector_credential="secret",
        runtime_config=runtime_config,
    )


def make_runtime_config(api_server_url: str | None) -> ConnectorRuntimeConfig:
    return ConnectorRuntimeConfig(
        python_executable="/usr/bin/python3",
        state_dir="/tmp/state",
        relay_url="http://100.79.222.100:8000/v1",
        hermes_command="hermes",
        hermes_workdir=None,
        hermes_provider=None,
        hermes_model=None,
        hermes_toolsets=None,
        hermes_source="tool",
        hermes_history_limit=20,
        api_server_url=api_server_url,
    )


def write_token_file(tmp_path, contents: str = "shim-token-abc") -> str:
    token_file = tmp_path / "talaria_shim_token"
    token_file.write_text(contents, encoding="utf-8")
    return str(token_file)


# --- descriptor construction (#116) ---


def test_descriptor_built_from_real_token_file(monkeypatch, tmp_path):
    monkeypatch.setenv("TALARIA_SHIM_TOKEN_FILE", write_token_file(tmp_path, "shim-token-abc\n"))
    connector = make_connector(tmp_path)

    descriptor = connector.provisioning_descriptor(make_state())

    # Host derives from the relay URL the connector enrolled against — the
    # relay's PUBLIC_BASE_URL, phone-reachable by definition.
    assert descriptor == {
        "shim_base_url": "http://100.79.222.100:8765",
        "shim_token": "shim-token-abc",
        "gateway_base_url": "http://100.79.222.100:8642",
    }


def test_descriptor_omits_shim_fields_without_token_file(monkeypatch, tmp_path):
    monkeypatch.setenv("TALARIA_SHIM_TOKEN_FILE", str(tmp_path / "does-not-exist"))
    connector = make_connector(tmp_path)

    descriptor = connector.provisioning_descriptor(make_state())

    # A host may legitimately run no shim — nothing fabricated.
    assert "shim_base_url" not in descriptor
    assert "shim_token" not in descriptor
    assert descriptor["gateway_base_url"] == "http://100.79.222.100:8642"


def test_descriptor_treats_empty_token_file_as_absent(monkeypatch, tmp_path):
    monkeypatch.setenv("TALARIA_SHIM_TOKEN_FILE", write_token_file(tmp_path, "   \n"))
    connector = make_connector(tmp_path)

    descriptor = connector.provisioning_descriptor(make_state())

    assert "shim_token" not in descriptor


def test_descriptor_refreshes_when_token_rotates(monkeypatch, tmp_path):
    token_path = write_token_file(tmp_path, "token-v1")
    monkeypatch.setenv("TALARIA_SHIM_TOKEN_FILE", token_path)
    connector = make_connector(tmp_path)
    state = make_state()

    first = connector.provisioning_descriptor(state)
    (tmp_path / "talaria_shim_token").write_text("token-v2", encoding="utf-8")
    second = connector.provisioning_descriptor(state)

    assert first["shim_token"] == "token-v1"
    assert second["shim_token"] == "token-v2"
    assert first != second


def test_descriptor_env_url_overrides_win(monkeypatch, tmp_path):
    monkeypatch.setenv("TALARIA_SHIM_TOKEN_FILE", write_token_file(tmp_path))
    monkeypatch.setenv("TALARIA_SHIM_BASE_URL", "http://shim.example.test:9001/")
    monkeypatch.setenv("TALARIA_GATEWAY_BASE_URL", "http://gateway.example.test:9002/")
    connector = make_connector(tmp_path)

    descriptor = connector.provisioning_descriptor(make_state())

    assert descriptor["shim_base_url"] == "http://shim.example.test:9001"
    assert descriptor["gateway_base_url"] == "http://gateway.example.test:9002"


def test_descriptor_falls_back_past_loopback_relay_url(monkeypatch, tmp_path):
    monkeypatch.setenv("TALARIA_SHIM_TOKEN_FILE", write_token_file(tmp_path))
    monkeypatch.setattr("hermes_mobile_connector.client.socket.gethostname", lambda: "OJAMD")
    connector = make_connector(tmp_path)

    descriptor = connector.provisioning_descriptor(make_state(relay_url="http://127.0.0.1:8000/v1"))

    # Loopback relay host would make the phone dial itself — fall back to the
    # machine hostname (lowercased, the MagicDNS convention).
    assert descriptor["shim_base_url"] == "http://ojamd:8765"
    assert descriptor["gateway_base_url"] == "http://ojamd:8642"


def test_descriptor_provisioning_host_override_wins(monkeypatch, tmp_path):
    monkeypatch.setenv("TALARIA_SHIM_TOKEN_FILE", write_token_file(tmp_path))
    monkeypatch.setenv("TALARIA_PROVISIONING_HOST", "100.110.102.59")
    connector = make_connector(tmp_path)

    descriptor = connector.provisioning_descriptor(make_state())

    assert descriptor["shim_base_url"] == "http://100.110.102.59:8765"
    assert descriptor["gateway_base_url"] == "http://100.110.102.59:8642"


def test_descriptor_gateway_prefers_reachable_api_server_url(monkeypatch, tmp_path):
    monkeypatch.setenv("TALARIA_SHIM_TOKEN_FILE", str(tmp_path / "does-not-exist"))
    connector = make_connector(tmp_path)
    state = make_state(runtime_config=make_runtime_config("http://100.79.222.100:8642/"))

    descriptor = connector.provisioning_descriptor(state)

    assert descriptor["gateway_base_url"] == "http://100.79.222.100:8642"


def test_descriptor_gateway_ignores_loopback_api_server_url(monkeypatch, tmp_path):
    monkeypatch.setenv("TALARIA_SHIM_TOKEN_FILE", str(tmp_path / "does-not-exist"))
    connector = make_connector(tmp_path)
    state = make_state(runtime_config=make_runtime_config("http://127.0.0.1:8642"))

    descriptor = connector.provisioning_descriptor(state)

    assert descriptor["gateway_base_url"] == "http://100.79.222.100:8642"


def test_phone_reachable_host_rejects_loopback_shapes():
    assert not _phone_reachable_host(None)
    assert not _phone_reachable_host("")
    assert not _phone_reachable_host("localhost")
    assert not _phone_reachable_host("LOCALHOST")
    assert not _phone_reachable_host("127.0.0.1")
    assert not _phone_reachable_host("::1")
    assert _phone_reachable_host("100.79.222.100")
    assert _phone_reachable_host("ojamd")
