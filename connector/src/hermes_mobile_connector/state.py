from __future__ import annotations

from dataclasses import asdict, dataclass
from datetime import datetime
import json
import os
from pathlib import Path


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
    mcp_command_path: str | None = None
    mcp_registered_at: str | None = None
    mcp_last_test_at: str | None = None
    mcp_last_test_error: str | None = None
    runtime_config: ConnectorRuntimeConfig | None = None

    @property
    def enrolled_datetime(self) -> datetime | None:
        return datetime.fromisoformat(self.enrolled_at) if self.enrolled_at else None


class ConnectorStateStore:
    def __init__(self, state_dir: Path | None = None) -> None:
        self.state_dir = (state_dir or _default_state_dir()).expanduser()
        self.state_path = self.state_dir / "state.json"

    def load(self) -> ConnectorState:
        if not self.state_path.exists():
            raise RuntimeError(
                "Connector is not set up yet. Run `hermes-mobile setup` first "
                "or use the legacy `hermes-mobile enroll --code ...` flow."
            )
        data = json.loads(self.state_path.read_text(encoding="utf-8"))
        runtime_config = data.get("runtime_config")
        if isinstance(runtime_config, dict):
            data["runtime_config"] = ConnectorRuntimeConfig(**runtime_config)
        return ConnectorState(**data)

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

    def clear(self) -> None:
        if self.state_path.exists():
            self.state_path.unlink()
        if self.state_dir.exists() and not any(self.state_dir.iterdir()):
            self.state_dir.rmdir()
