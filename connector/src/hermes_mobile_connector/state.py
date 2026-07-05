from __future__ import annotations

from dataclasses import asdict, dataclass, field, fields
from datetime import datetime
import json
import os
from pathlib import Path


def _dataclass_from_dict(cls, data: dict):
    """Build a dataclass instance from JSON data, ignoring unknown keys.

    State and secrets files are user-editable (issue #7 documents hand-editing
    ``~/.hermes-mobile``); an unrecognized key must not make the whole
    connector unable to load its state.
    """
    known = {f.name for f in fields(cls)}
    return cls(**{key: value for key, value in data.items() if key in known})


def _default_state_dir() -> Path:
    configured = os.getenv("HERMES_MOBILE_CONNECTOR_HOME")
    if configured:
        return Path(configured).expanduser()
    return Path.home() / ".hermes-mobile"


@dataclass
class ConnectorRuntimeConfig:
    python_executable: str
    state_dir: str
    relay_url: str
    hermes_command: str
    hermes_workdir: str | None
    hermes_provider: str | None
    hermes_model: str | None
    hermes_toolsets: str | None
    hermes_source: str
    hermes_history_limit: int
    hermes_home: str | None = None
    api_server_url: str | None = None
    api_server_key: str | None = None


@dataclass
class RealtimeTalkConfig:
    enabled: bool = False
    preferred_models: list[str] = field(default_factory=lambda: ["gpt-realtime-1.5", "gpt-realtime"])
    voice: str = "ballad"
    turn_detection_type: str = "semantic_vad"
    create_response: bool = True
    interrupt_response: bool = True
    last_validated_at: str | None = None
    last_validation_error: str | None = None
    last_selected_model: str | None = None


@dataclass
class VoiceContextSnapshot:
    system_prompt: str
    memory_summary: str
    user_summary: str
    sensor_summary: str
    readiness_summary: str
    updated_at: str
    memory_provider_summary: str = "Memory provider status unavailable."


@dataclass
class ConnectorState:
    relay_url: str
    web_socket_url: str
    host_id: str
    connector_credential: str
    user_id: str | None = None
    connector_display_name: str | None = None
    enrolled_at: str | None = None
    last_connected_at: str | None = None
    last_error: str | None = None
    mcp_server_name: str = "hermes_mobile"
    mcp_configured: bool = False
    mcp_command_path: str | None = None
    mcp_registered_at: str | None = None
    mcp_last_test_at: str | None = None
    mcp_last_test_error: str | None = None
    runtime_config: ConnectorRuntimeConfig | None = None
    realtime_talk: RealtimeTalkConfig | None = None
    voice_context_snapshot: VoiceContextSnapshot | None = None

    @property
    def enrolled_datetime(self) -> datetime | None:
        return datetime.fromisoformat(self.enrolled_at) if self.enrolled_at else None


@dataclass
class ConnectorSecrets:
    openai_api_key: str | None = None
    # Tri-state: True/False = explicit choice stored in secrets.json,
    # None = not set there, fall back to realtime_talk.enabled in state.json.
    realtime_talk_enabled: bool | None = None


class ConnectorStateStore:
    def __init__(self, state_dir: Path | None = None) -> None:
        self.state_dir = (state_dir or _default_state_dir()).expanduser()
        self.state_path = self.state_dir / "state.json"
        self.secrets_path = self.state_dir / "secrets.json"

    def load(self) -> ConnectorState:
        if not self.state_path.exists():
            raise RuntimeError(
                "Connector is not set up yet. Run `hermes-mobile setup` first "
                "or use the legacy `hermes-mobile enroll --code ...` flow."
            )
        data = json.loads(self.state_path.read_text(encoding="utf-8"))
        runtime_config = data.get("runtime_config")
        if isinstance(runtime_config, dict):
            data["runtime_config"] = _dataclass_from_dict(ConnectorRuntimeConfig, runtime_config)
        realtime_talk = data.get("realtime_talk")
        if isinstance(realtime_talk, dict):
            data["realtime_talk"] = _dataclass_from_dict(RealtimeTalkConfig, realtime_talk)
        voice_context_snapshot = data.get("voice_context_snapshot")
        if isinstance(voice_context_snapshot, dict):
            data["voice_context_snapshot"] = _dataclass_from_dict(VoiceContextSnapshot, voice_context_snapshot)
        data.setdefault(
            "mcp_configured",
            bool(data.get("mcp_registered_at") or data.get("mcp_command_path")),
        )
        return _dataclass_from_dict(ConnectorState, data)

    def save(self, state: ConnectorState) -> ConnectorState:
        self.state_dir.mkdir(parents=True, exist_ok=True)
        try:
            os.chmod(self.state_dir, 0o700)
        except PermissionError:
            pass

        self.state_path.write_text(json.dumps(asdict(state), indent=2, sort_keys=True), encoding="utf-8")
        try:
            os.chmod(self.state_path, 0o600)
        except PermissionError:
            pass
        return state

    def load_secrets(self) -> ConnectorSecrets:
        if not self.secrets_path.exists():
            return ConnectorSecrets()
        data = json.loads(self.secrets_path.read_text(encoding="utf-8"))
        # Issue #7 documents enabling talk mode via the secrets store. Accept
        # every shape a hand-edit plausibly produces:
        #   {"realtime_talk_enabled": true}
        #   {"realtime_talk": {"enabled": true}}
        #   {"realtime_talk.enabled": true}
        if "realtime_talk_enabled" not in data:
            nested = data.get("realtime_talk")
            if isinstance(nested, dict) and "enabled" in nested:
                data["realtime_talk_enabled"] = nested["enabled"]
            elif "realtime_talk.enabled" in data:
                data["realtime_talk_enabled"] = data["realtime_talk.enabled"]
        if data.get("realtime_talk_enabled") is not None:
            data["realtime_talk_enabled"] = bool(data["realtime_talk_enabled"])
        return _dataclass_from_dict(ConnectorSecrets, data)

    def save_secrets(self, secrets: ConnectorSecrets) -> ConnectorSecrets:
        self.state_dir.mkdir(parents=True, exist_ok=True)
        try:
            os.chmod(self.state_dir, 0o700)
        except PermissionError:
            pass

        self.secrets_path.write_text(json.dumps(asdict(secrets), indent=2, sort_keys=True), encoding="utf-8")
        try:
            os.chmod(self.secrets_path, 0o600)
        except PermissionError:
            pass
        return secrets

    def clear(self) -> None:
        if self.state_path.exists():
            self.state_path.unlink()
        if self.secrets_path.exists():
            self.secrets_path.unlink()
        if self.state_dir.exists() and not any(self.state_dir.iterdir()):
            self.state_dir.rmdir()
