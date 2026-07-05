from __future__ import annotations

import asyncio
import base64
import json
import sys

from hermes_mobile_connector.client import HermesMobileConnector
from hermes_mobile_connector.hermes_runner import ConnectorHermesSettings, HermesCLIExecutor
from hermes_mobile_connector.mcp_registration import (
    MCPRegistrationStatus,
    native_mcp_readiness_message,
    register_native_mcp_server,
)
from hermes_mobile_connector.setup_code import decode_host_setup_code
from hermes_mobile_connector.runtime_adapter import (
    HermesAPIRuntimeAdapter,
    HermesRuntimeAdapter,
    RuntimeConversationMessage,
)
from hermes_mobile_connector.state import (
    ConnectorSecrets,
    ConnectorState,
    ConnectorStateStore,
    RealtimeTalkConfig,
    VoiceContextSnapshot,
)


def make_enrolled_state() -> ConnectorState:
    return ConnectorState(
        relay_url="https://relay.example.com/v1",
        web_socket_url="wss://relay.example.com/v1/hosts/ws",
        user_id="user-123",
        host_id="host-123",
        connector_credential="secret",
    )


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
    monkeypatch.setattr(HermesCLIExecutor, "detect_version", lambda self: "Hermes 1.2.3")
    monkeypatch.setattr(HermesCLIExecutor, "resolved_command_path", lambda self: "/usr/local/bin/hermes")
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
    assert state.mcp_configured is True
    assert state.mcp_command_path == "/tmp/hermes-mobile-mcp"
    assert state.mcp_last_test_error is None


def test_setup_includes_installation_secret_from_env(monkeypatch, tmp_path):
    store = ConnectorStateStore(state_dir=tmp_path / "connector-setup-secret")
    connector = HermesMobileConnector(state_store=store, executor=make_executor())
    monkeypatch.setattr(HermesCLIExecutor, "detect_version", lambda self: "Hermes 1.2.3")
    monkeypatch.setattr(HermesCLIExecutor, "resolved_command_path", lambda self: "/usr/local/bin/hermes")
    monkeypatch.setenv("CONNECTOR_SETUP_SECRET", "setup-secret")

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
        assert json["installationSecret"] == "setup-secret"
        return FakeResponse()

    monkeypatch.setattr("hermes_mobile_connector.client.httpx.post", fake_post)
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

    connector.setup(relay_url="https://relay.example.com/v1")


def test_setup_requires_explicit_relay_url_when_env_missing(monkeypatch, tmp_path):
    store = ConnectorStateStore(state_dir=tmp_path / "connector-setup-missing-relay")
    connector = HermesMobileConnector(state_store=store, executor=make_executor())
    monkeypatch.setattr(HermesCLIExecutor, "detect_version", lambda self: "Hermes 1.2.3")
    monkeypatch.delenv("HERMES_MOBILE_RELAY_URL", raising=False)

    try:
        connector.setup()
        raise AssertionError("Expected setup() to fail without relay URL")
    except RuntimeError as error:
        assert "Relay URL is required" in str(error)


def test_rpc_commands_catalog_includes_personalities_and_quick_commands(monkeypatch, tmp_path):
    hermes_home = tmp_path / ".hermes"
    hermes_cli_dir = hermes_home / "hermes-agent" / "hermes_cli"
    hermes_cli_dir.mkdir(parents=True)
    (hermes_cli_dir / "__init__.py").write_text("", encoding="utf-8")
    (hermes_cli_dir / "commands.py").write_text(
        """
class Command:
    def __init__(self, name, description, category, args_hint=None, aliases=None, gateway_only=False):
        self.name = name
        self.description = description
        self.category = category
        self.args_hint = args_hint
        self.aliases = aliases or []
        self.gateway_only = gateway_only


COMMAND_REGISTRY = [
    Command("help", "Show command help", "Info"),
    Command("skills", "Browse installed skills", "Tools & Skills", "browse"),
]


def _is_gateway_available(cmd, overrides):
    return True


def _resolve_config_gates():
    return {}
""",
        encoding="utf-8",
    )
    (hermes_home / "config.yaml").write_text(
        """
personalities:
  mentor: "Helpful, practical, and direct."
  pirate: >
    Arrr! Be direct and nautical.
quick_commands:
  gpu:
    type: exec
    command: nvidia-smi
  health:
    type: exec
    description: Check Hermes health status
    command: hermes doctor
  ignored:
    type: webhook
    command: ignored
""",
        encoding="utf-8",
    )
    skill_dir = hermes_home / "skills" / "ios-context"
    skill_dir.mkdir(parents=True)
    (skill_dir / "SKILL.md").write_text(
        "# iOS Context\n\nCapture iOS-specific context.\n",
        encoding="utf-8",
    )

    monkeypatch.setenv("HERMES_HOME", str(hermes_home))
    sys.modules.pop("hermes_cli.commands", None)
    sys.modules.pop("hermes_cli", None)

    connector = HermesMobileConnector(
        state_store=ConnectorStateStore(state_dir=tmp_path / "connector-state"),
        executor=make_executor(),
    )

    catalog = connector._rpc_commands_catalog()

    assert any(command["name"] == "help" for command in catalog["commands"])
    # "skills" is cli_only, so it should NOT be in gateway commands
    assert not any(command["name"] == "skills" for command in catalog["commands"])
    # But gateway commands like "model" should be present
    assert any(command["name"] == "model" for command in catalog["commands"])
    assert catalog["skills"] == [
        {
            "name": "ios-context",
            "description": "Capture iOS-specific context.",
        }
    ]
    assert catalog["personalities"] == [
        {
            "name": "mentor",
            "description": "Helpful, practical, and direct.",
        },
        {
            "name": "pirate",
            "description": "Arrr! Be direct and nautical.",
        },
    ]
    assert catalog["quickCommands"] == [
        {
            "name": "gpu",
            "description": "nvidia-smi",
        },
        {
            "name": "health",
            "description": "Check Hermes health status",
        },
    ]


def test_rpc_commands_catalog_prefers_cli_skill_listing(monkeypatch, tmp_path):
    hermes_home = tmp_path / ".hermes"
    hermes_cli_dir = hermes_home / "hermes-agent" / "hermes_cli"
    hermes_cli_dir.mkdir(parents=True)
    (hermes_cli_dir / "__init__.py").write_text("", encoding="utf-8")
    (hermes_cli_dir / "commands.py").write_text(
        """
COMMAND_REGISTRY = []


def _is_gateway_available(cmd, overrides):
    return True


def _resolve_config_gates():
    return {}
""",
        encoding="utf-8",
    )
    monkeypatch.setenv("HERMES_HOME", str(hermes_home))
    sys.modules.pop("hermes_cli.commands", None)
    sys.modules.pop("hermes_cli", None)

    class FakeCompletedProcess:
        returncode = 0
        stdout = "manim-video  Render short manim clips from prompts\nshell-helper  Misc shell support\n"

    monkeypatch.setattr(
        "hermes_mobile_connector.client.subprocess.run",
        lambda *args, **kwargs: FakeCompletedProcess(),
    )

    connector = HermesMobileConnector(
        state_store=ConnectorStateStore(state_dir=tmp_path / "connector-state"),
        executor=make_executor(),
    )

    catalog = connector._rpc_commands_catalog()
    assert catalog["skills"] == [
        {
            "name": "manim-video",
            "description": "Render short manim clips from prompts",
        },
        {
            "name": "shell-helper",
            "description": "Misc shell support",
        },
    ]


def test_rpc_commands_catalog_uses_configured_context_length(monkeypatch, tmp_path):
    hermes_home = tmp_path / ".hermes"
    hermes_home.mkdir(parents=True)
    (hermes_home / "config.yaml").write_text(
        """
model:
  default: gpt-5.4-mini
  provider: openai-codex
  context_length: 262144
""",
        encoding="utf-8",
    )
    monkeypatch.setenv("HERMES_HOME", str(hermes_home))

    connector = HermesMobileConnector(
        state_store=ConnectorStateStore(state_dir=tmp_path / "connector-state"),
        executor=make_executor(),
    )

    catalog = connector._rpc_commands_catalog()

    assert catalog["activeModel"] == {
        "name": "gpt-5.4-mini",
        "provider": "openai-codex",
        "contextWindow": 262144,
    }


def test_rpc_commands_catalog_uses_updated_hermes_fallback_context_length(monkeypatch, tmp_path):
    hermes_home = tmp_path / ".hermes"
    hermes_home.mkdir(parents=True)
    (hermes_home / "config.yaml").write_text(
        """
model:
  default: gpt-5.4-mini
  provider: openai-codex
""",
        encoding="utf-8",
    )
    monkeypatch.setenv("HERMES_HOME", str(hermes_home))

    connector = HermesMobileConnector(
        state_store=ConnectorStateStore(state_dir=tmp_path / "connector-state"),
        executor=make_executor(),
    )

    catalog = connector._rpc_commands_catalog()

    assert catalog["activeModel"] == {
        "name": "gpt-5.4-mini",
        "provider": "openai-codex",
        "contextWindow": 128000,
    }


def test_runtime_adapter_falls_back_to_cli_without_explicit_api_config(monkeypatch, tmp_path):
    store = ConnectorStateStore(state_dir=tmp_path / "connector-runtime")
    state = make_enrolled_state()
    store.save(state)
    connector = HermesMobileConnector(state_store=store, executor=make_executor())

    async def fail_health_check(self):  # noqa: ANN001
        raise AssertionError("Implicit localhost API health check should not run without explicit config")

    monkeypatch.delenv("HERMES_API_SERVER_URL", raising=False)
    monkeypatch.delenv("HERMES_API_SERVER_KEY", raising=False)
    monkeypatch.setattr("hermes_mobile_connector.client.HermesAPIExecutor.health_check", fail_health_check)

    adapter = asyncio.run(connector.runtime_adapter_for_state_async(state))
    assert isinstance(adapter, HermesRuntimeAdapter)


def test_setup_can_skip_native_mcp_configuration(monkeypatch, tmp_path):
    store = ConnectorStateStore(state_dir=tmp_path / "connector-setup-skip")
    connector = HermesMobileConnector(state_store=store, executor=make_executor())
    monkeypatch.setattr(HermesCLIExecutor, "detect_version", lambda self: "Hermes 1.2.3")
    monkeypatch.setattr(HermesCLIExecutor, "resolved_command_path", lambda self: "/usr/local/bin/hermes")

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
    assert state.mcp_configured is False
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
    assert state.mcp_configured is True
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


def test_configure_realtime_stores_api_key_in_secrets_only(monkeypatch, tmp_path):
    store = ConnectorStateStore(state_dir=tmp_path / "connector-realtime")
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

    monkeypatch.setattr(connector, "refresh_voice_context", lambda *, state=None: state or store.load())
    monkeypatch.setattr(
        connector,
        "_create_openai_realtime_session",
        lambda **kwargs: (
            {
                "value": "ephemeral-secret",
                "expires_at": 1_775_001_600,
                "session": {
                    "id": "sess_123",
                    "type": "realtime",
                },
            },
            "gpt-realtime-1.5",
        ),
    )

    state = connector.configure_realtime(api_key="sk-test-realtime")

    assert store.load_secrets().openai_api_key == "sk-test-realtime"
    assert "sk-test-realtime" not in store.state_path.read_text(encoding="utf-8")
    assert "sk-test-realtime" in store.secrets_path.read_text(encoding="utf-8")
    assert state.realtime_talk is not None
    assert state.realtime_talk.enabled is True
    assert state.realtime_talk.last_selected_model == "gpt-realtime-1.5"
    assert state.realtime_talk.last_validation_error is None


def test_configure_realtime_clear_removes_api_key_and_disables_talk(tmp_path):
    store = ConnectorStateStore(state_dir=tmp_path / "connector-realtime-clear")
    store.save(
        ConnectorState(
            relay_url="https://relay.example.com/v1",
            web_socket_url="wss://relay.example.com/v1/hosts/ws",
            user_id="user-123",
            host_id="host-123",
            connector_credential="secret-token",
            realtime_talk=RealtimeTalkConfig(enabled=True),
        )
    )
    store.save_secrets(ConnectorSecrets(openai_api_key="sk-test-realtime"))
    connector = HermesMobileConnector(state_store=store, executor=make_executor())

    state = connector.configure_realtime(clear=True)

    assert store.load_secrets().openai_api_key is None
    assert state.realtime_talk is not None
    assert state.realtime_talk.enabled is False
    assert state.voice_context_snapshot is None


def test_load_secrets_tolerates_unknown_keys_and_reads_dotted_realtime_enabled(tmp_path):
    store = ConnectorStateStore(state_dir=tmp_path / "connector-secrets-dotted")
    store.state_dir.mkdir(parents=True)
    store.secrets_path.write_text(
        json.dumps(
            {
                "openai_api_key": "sk-hand-edited",
                "realtime_talk.enabled": True,
                "some_future_key": "ignored",
            }
        ),
        encoding="utf-8",
    )

    secrets = store.load_secrets()

    assert secrets.openai_api_key == "sk-hand-edited"
    assert secrets.realtime_talk_enabled is True


def test_load_secrets_reads_nested_realtime_block(tmp_path):
    store = ConnectorStateStore(state_dir=tmp_path / "connector-secrets-nested")
    store.state_dir.mkdir(parents=True)
    store.secrets_path.write_text(
        json.dumps(
            {
                "openai_api_key": "sk-hand-edited",
                "realtime_talk": {"enabled": True},
            }
        ),
        encoding="utf-8",
    )

    secrets = store.load_secrets()

    assert secrets.openai_api_key == "sk-hand-edited"
    assert secrets.realtime_talk_enabled is True


def test_state_load_tolerates_unknown_keys(tmp_path):
    store = ConnectorStateStore(state_dir=tmp_path / "connector-state-unknown")
    store.save(make_enrolled_state())
    data = json.loads(store.state_path.read_text(encoding="utf-8"))
    data["openai_api_key"] = "sk-misplaced"
    data["realtime_talk"] = {"enabled": True, "unexpected_field": 1}
    store.state_path.write_text(json.dumps(data), encoding="utf-8")

    state = store.load()

    assert state.host_id == "host-123"
    assert state.realtime_talk is not None
    assert state.realtime_talk.enabled is True


def test_talk_readiness_configured_via_hand_edited_secrets(monkeypatch, tmp_path):
    monkeypatch.delenv("OPENAI_API_KEY", raising=False)
    monkeypatch.setenv("HERMES_HOME", str(tmp_path / ".hermes"))
    store = ConnectorStateStore(state_dir=tmp_path / "connector-readiness-secrets")
    store.save(make_enrolled_state())
    store.state_dir.mkdir(parents=True, exist_ok=True)
    store.secrets_path.write_text(
        json.dumps(
            {
                "openai_api_key": "sk-hand-edited",
                "realtime_talk.enabled": True,
            }
        ),
        encoding="utf-8",
    )
    connector = HermesMobileConnector(state_store=store, executor=make_executor())

    payload = connector.talk_readiness_payload()

    assert payload["configured"] is True
    assert payload["apiKeyPresent"] is True
    assert payload["blockedReason"] is None


def test_talk_readiness_api_key_from_hermes_env_file(monkeypatch, tmp_path):
    monkeypatch.delenv("OPENAI_API_KEY", raising=False)
    hermes_home = tmp_path / ".hermes"
    hermes_home.mkdir(parents=True)
    (hermes_home / ".env").write_text(
        "# Hermes settings\nAPI_SERVER_KEY=abc\nOPENAI_API_KEY=\"sk-from-hermes-env\"\n",
        encoding="utf-8",
    )
    monkeypatch.setenv("HERMES_HOME", str(hermes_home))
    store = ConnectorStateStore(state_dir=tmp_path / "connector-readiness-env")
    state = make_enrolled_state()
    state.realtime_talk = RealtimeTalkConfig(enabled=True)
    store.save(state)
    connector = HermesMobileConnector(state_store=store, executor=make_executor())

    payload = connector.talk_readiness_payload()

    assert payload["configured"] is True
    assert payload["apiKeyPresent"] is True
    assert payload["blockedReason"] is None
    assert connector.resolve_openai_api_key() == "sk-from-hermes-env"


def test_talk_readiness_blocked_when_key_present_but_disabled(monkeypatch, tmp_path):
    monkeypatch.delenv("OPENAI_API_KEY", raising=False)
    monkeypatch.setenv("HERMES_HOME", str(tmp_path / ".hermes"))
    store = ConnectorStateStore(state_dir=tmp_path / "connector-readiness-disabled")
    store.save(make_enrolled_state())
    store.save_secrets(ConnectorSecrets(openai_api_key="sk-test-realtime"))
    connector = HermesMobileConnector(state_store=store, executor=make_executor())

    payload = connector.talk_readiness_payload()

    assert payload["configured"] is False
    assert payload["apiKeyPresent"] is True
    assert "disabled" in payload["blockedReason"]


def test_talk_readiness_clears_stale_no_key_validation_error(monkeypatch, tmp_path):
    monkeypatch.delenv("OPENAI_API_KEY", raising=False)
    monkeypatch.setenv("HERMES_HOME", str(tmp_path / ".hermes"))
    store = ConnectorStateStore(state_dir=tmp_path / "connector-readiness-stale")
    state = make_enrolled_state()
    state.realtime_talk = RealtimeTalkConfig(
        enabled=True,
        last_validation_error="OpenAI API key is not configured.",
    )
    store.save(state)
    store.save_secrets(ConnectorSecrets(openai_api_key="sk-added-later"))
    connector = HermesMobileConnector(state_store=store, executor=make_executor())

    payload = connector.talk_readiness_payload()

    assert payload["configured"] is True
    assert payload["lastValidationError"] is None
    assert payload["blockedReason"] is None


def test_talk_session_create_uses_secrets_level_enabled_flag(monkeypatch, tmp_path):
    monkeypatch.delenv("OPENAI_API_KEY", raising=False)
    store = ConnectorStateStore(state_dir=tmp_path / "connector-session-secrets-enabled")
    state = make_enrolled_state()
    state.voice_context_snapshot = VoiceContextSnapshot(
        system_prompt="System prompt",
        memory_summary="Memory",
        user_summary="User",
        sensor_summary="Sensors",
        readiness_summary="Ready",
        updated_at="2026-04-01T12:00:00+00:00",
    )
    store.save(state)
    store.state_dir.mkdir(parents=True, exist_ok=True)
    store.secrets_path.write_text(
        json.dumps(
            {
                "openai_api_key": "sk-hand-edited",
                "realtime_talk": {"enabled": True},
            }
        ),
        encoding="utf-8",
    )
    connector = HermesMobileConnector(state_store=store, executor=make_executor())

    monkeypatch.setattr(connector, "refresh_voice_context_if_stale", lambda *, state=None: state or store.load())
    captured_keys: list[str] = []

    def fake_create(**kwargs):
        captured_keys.append(kwargs["api_key"])
        return (
            {
                "value": "ephemeral-secret",
                "expires_at": 1_775_001_600,
                "session": {"id": "sess_secrets", "type": "realtime"},
            },
            "gpt-realtime-1.5",
        )

    monkeypatch.setattr(connector, "_create_openai_realtime_session", fake_create)

    payload = connector._rpc_talk_session_create({"relayMcpURL": "https://relay.example.com/v1/talk/mcp?token=test"})  # noqa: SLF001

    assert payload["clientSecret"] == "ephemeral-secret"
    assert captured_keys == ["sk-hand-edited"]


def test_realtime_session_creation_falls_back_to_secondary_model(monkeypatch, tmp_path):
    connector = HermesMobileConnector(state_store=ConnectorStateStore(state_dir=tmp_path / "connector-realtime-fallback"), executor=make_executor())
    attempted_models: list[str] = []
    captured_sessions: list[dict] = []

    class FakeResponse:
        def __init__(self, status_code: int, payload: dict) -> None:
            self.status_code = status_code
            self._payload = payload
            self.text = json.dumps(payload)

        def json(self) -> dict:
            return self._payload

    def fake_post(url, headers=None, json=None, timeout=None):  # noqa: ANN001
        session = json["session"]
        attempted_models.append(session["model"])
        captured_sessions.append(json)
        if len(attempted_models) == 1:
            return FakeResponse(400, {"error": {"message": "Model not available."}})
        return FakeResponse(
            200,
            {
                "value": "ephemeral-secret",
                "expires_at": 1_775_001_600,
                "session": {
                    "id": "sess_456",
                    "model": "gpt-realtime",
                },
            },
        )

    monkeypatch.setattr("hermes_mobile_connector.client.httpx.post", fake_post)

    payload, selected_model = connector._create_openai_realtime_session(  # noqa: SLF001
        api_key="sk-test-realtime",
        config=RealtimeTalkConfig(preferred_models=["gpt-realtime-1.5", "gpt-realtime"]),
        instructions="Say hello.",
        relay_mcp_url=None,
    )

    assert attempted_models == ["gpt-realtime-1.5", "gpt-realtime"]
    session_def = captured_sessions[0]["session"]
    assert session_def["type"] == "realtime"
    assert session_def["audio"]["output"]["voice"] == "ballad"
    assert "modalities" not in session_def
    assert selected_model == "gpt-realtime"
    assert payload["value"] == "ephemeral-secret"


def test_talk_session_create_normalizes_client_secret_payload(monkeypatch, tmp_path):
    store = ConnectorStateStore(state_dir=tmp_path / "connector-realtime-session")
    store.save(
        ConnectorState(
            relay_url="https://relay.example.com/v1",
            web_socket_url="wss://relay.example.com/v1/hosts/ws",
            user_id="user-123",
            host_id="host-123",
            connector_credential="secret-token",
            realtime_talk=RealtimeTalkConfig(enabled=True, last_validation_error=None),
            voice_context_snapshot=VoiceContextSnapshot(
                system_prompt="System prompt",
                memory_summary="Memory",
                user_summary="User",
                sensor_summary="Sensors",
                readiness_summary="Ready",
                updated_at="2026-04-01T12:00:00+00:00",
            ),
        )
    )
    store.save_secrets(ConnectorSecrets(openai_api_key="sk-test-realtime"))
    connector = HermesMobileConnector(state_store=store, executor=make_executor())

    monkeypatch.setattr(connector, "refresh_voice_context_if_stale", lambda *, state=None: state or store.load())
    monkeypatch.setattr(
        connector,
        "_create_openai_realtime_session",
        lambda **kwargs: (
            {
                "value": "ephemeral-secret",
                "expires_at": 1_775_001_600,
                "session": {
                    "id": "sess_789",
                    "type": "realtime",
                    "model": "gpt-realtime-1.5",
                },
            },
            "gpt-realtime-1.5",
        ),
    )

    payload = connector._rpc_talk_session_create({"relayMcpURL": "https://relay.example.com/v1/talk/mcp?token=test"})  # noqa: SLF001

    assert payload["clientSecret"] == "ephemeral-secret"
    assert payload["session"]["id"] == "sess_789"
    assert payload["session"]["type"] == "realtime"
    assert payload["expiresAt"] == "2026-04-01T00:00:00+00:00"
    assert payload["model"] == "gpt-realtime-1.5"


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


def test_status_lines_keep_mcp_not_configured_hint_when_host_machine_has_native_config(tmp_path):
    store = ConnectorStateStore(state_dir=tmp_path / "connector-status-machine-config")
    store.save(
        ConnectorState(
            relay_url="https://relay.example.com/v1",
            web_socket_url="wss://relay.example.com/v1/hosts/ws",
            user_id="user-123",
            host_id="host-123",
            connector_credential="secret",
            mcp_configured=False,
        )
    )
    connector = HermesMobileConnector(state_store=store, executor=make_executor())

    lines = connector.status_lines()

    assert any("MCP validation: not configured" in line for line in lines)


def test_hermes_runtime_adapter_preserves_history_and_session(monkeypatch):
    executor = make_executor()
    captured: dict = {}

    def fake_send_message(*, latest_user_message, history, session_id):  # noqa: ANN001
        captured["latest_user_message"] = latest_user_message
        captured["history"] = history
        captured["session_id"] = session_id
        return type(
            "FakeResult",
            (),
            {
                "text": "Adapter reply",
                "session_id": "session-456",
            },
        )()

    monkeypatch.setattr(executor, "send_message", fake_send_message)
    adapter = HermesRuntimeAdapter(executor)

    result = adapter.send_text_message(
        latest_user_message="How are you?",
        history=[RuntimeConversationMessage(role="user", text="Hello")],
        session_id="session-123",
    )

    assert result.text == "Adapter reply"
    assert result.session_id == "session-456"
    assert captured["latest_user_message"] == "How are you?"
    assert captured["session_id"] == "session-123"
    assert len(captured["history"]) == 1
    assert captured["history"][0].role == "user"
    assert captured["history"][0].text == "Hello"


def test_hermes_api_runtime_adapter_preserves_session_with_history():
    """Session ID should always be passed through to preserve prefix caching."""
    captured: dict = {}

    class FakeExecutor:
        async def send_message(self, *, latest_user_message, history=None, session_id=None):  # noqa: ANN001
            captured["latest_user_message"] = latest_user_message
            captured["history"] = history
            captured["session_id"] = session_id
            return type(
                "FakeResult",
                (),
                {
                    "text": "API reply",
                    "session_id": "session-456",
                    "usage": {"total_tokens": 42},
                },
            )()

    adapter = HermesAPIRuntimeAdapter(FakeExecutor())

    result = adapter.send_text_message(
        latest_user_message="How are you?",
        history=[
            RuntimeConversationMessage(role="user", text="Hello"),
            RuntimeConversationMessage(role="hermes", text="Hi there"),
        ],
        session_id="session-123",
    )

    assert result.text == "API reply"
    assert result.session_id == "session-456"
    assert captured["latest_user_message"] == "How are you?"
    assert captured["session_id"] == "session-123"
    assert len(captured["history"]) == 2
    assert captured["history"][1].role == "hermes"


def test_hermes_api_runtime_adapter_delegate_uses_session_id():
    captured: dict = {}

    class FakeExecutor:
        async def send_message(self, *, latest_user_message, history=None, session_id=None):  # noqa: ANN001
            captured["latest_user_message"] = latest_user_message
            captured["history"] = history
            captured["session_id"] = session_id
            return type(
                "FakeResult",
                (),
                {
                    "text": "Delegated",
                    "session_id": "voice-session-2",
                    "usage": None,
                },
            )()

    adapter = HermesAPIRuntimeAdapter(FakeExecutor())

    result = adapter.delegate_talk_turn(
        prompt="Use tools",
        session_id="voice-session-1",
    )

    assert result.text == "Delegated"
    assert captured["latest_user_message"] == "Use tools"
    assert captured["session_id"] == "voice-session-1"
    assert captured["history"] == []


def test_rpc_talk_delegate_supports_neutral_and_legacy_method_names(monkeypatch, tmp_path):
    store = ConnectorStateStore(state_dir=tmp_path / "connector-talk-delegate")
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
    captured_prompts: list[str] = []

    class FakeAdapter:
        def send_text_message(self, *, latest_user_message, history, session_id=None):  # noqa: ANN001
            raise AssertionError("send_text_message should not be called")

        def delegate_talk_turn(self, *, prompt, session_id=None):  # noqa: ANN001
            captured_prompts.append(prompt)
            return type("Result", (), {"text": "Delegated reply", "session_id": "voice-session-1"})()

    async def fake_runtime_adapter_async(state):  # noqa: ANN001, ARG001
        return FakeAdapter()

    monkeypatch.setattr(connector, "runtime_adapter_for_state_async", fake_runtime_adapter_async)

    neutral_response = asyncio.run(
        connector._handle_rpc_request(  # noqa: SLF001
            {
                "requestId": "req-1",
                "method": "talk.delegate",
                "params": {"voiceSessionId": "voice-123", "prompt": "Use tools"},
            }
        )
    )
    legacy_response = asyncio.run(
        connector._handle_rpc_request(  # noqa: SLF001
            {
                "requestId": "req-2",
                "method": "talk.hermes_delegate",
                "params": {"voiceSessionId": "voice-123", "prompt": "Use tools again"},
            }
        )
    )

    assert neutral_response["success"] is True
    assert neutral_response["result"]["text"] == "Delegated reply"
    assert legacy_response["success"] is True
    assert legacy_response["result"]["text"] == "Delegated reply"
    assert captured_prompts == ["Use tools", "Use tools again"]


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


def test_handle_sensor_message_stores_location(tmp_path):
    store = ConnectorStateStore(state_dir=tmp_path / "connector-sensor-loc")
    store.save(make_enrolled_state())
    connector = HermesMobileConnector(state_store=store, executor=make_executor())

    result = connector._handle_sensor_message({  # noqa: SLF001
        "type": "sensor.location",
        "deliveryId": "delivery-loc-1",
        "latitude": 40.7128,
        "longitude": -74.006,
        "accuracy": 35.0,
        "address": "New York, NY",
        "recordedAt": "2026-04-01T15:00:00Z",
    })

    assert result is not None
    assert result["type"] == "sensor.ack"
    assert result["deliveryState"] == "delivered"

    current = connector.sensor_store.get_current_location()
    assert current is not None
    assert current.latitude == 40.7128
    assert current.address == "New York, NY"


def test_handle_sensor_message_stores_health(tmp_path):
    store = ConnectorStateStore(state_dir=tmp_path / "connector-sensor-health")
    store.save(make_enrolled_state())
    connector = HermesMobileConnector(state_store=store, executor=make_executor())

    result = connector._handle_sensor_message({  # noqa: SLF001
        "type": "sensor.health",
        "deliveryId": "delivery-health-1",
        "samples": [
            {"metric": "steps", "value": 5000, "unit": "count", "startAt": "2026-04-01T00:00:00Z", "endAt": "2026-04-01T15:00:00Z"},
            {"metric": "heart_rate", "value": 72, "unit": "bpm", "startAt": "2026-04-01T15:00:00Z"},
        ],
    })

    assert result is not None
    assert result["deliveryState"] == "delivered"

    metrics = connector.sensor_store.get_latest_metrics()
    metric_names = {m.metric for m in metrics}
    assert "steps" in metric_names
    assert "heart_rate" in metric_names


def test_handle_sensor_message_returns_none_for_unknown_type(tmp_path):
    store = ConnectorStateStore(state_dir=tmp_path / "connector-sensor-unknown")
    store.save(make_enrolled_state())
    connector = HermesMobileConnector(state_store=store, executor=make_executor())

    result = connector._handle_sensor_message({"type": "something.else"})  # noqa: SLF001
    assert result is None
