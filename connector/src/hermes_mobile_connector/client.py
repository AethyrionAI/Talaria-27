from __future__ import annotations
import asyncio
import base64
from dataclasses import dataclass
from datetime import datetime, timezone
import json
import logging
import os
from pathlib import Path
import platform as platform_module
import re
import socket
import subprocess
import sys
import uuid

logger = logging.getLogger("hermes.mobile.connector")

import httpx
from websockets.asyncio.client import connect as websocket_connect

from . import __version__

# Gateway-available commands from Hermes COMMAND_REGISTRY.
# These are the commands available on messaging platforms (not cli_only).
# Kept as static data to avoid importing hermes_cli (different venv).
_GATEWAY_COMMANDS: list[dict] = [
    {"name": "new", "description": "Start a new session", "category": "Session", "args": None, "aliases": ["reset"], "gatewayOnly": False},
    {"name": "retry", "description": "Retry the last message", "category": "Session", "args": None, "aliases": [], "gatewayOnly": False},
    {"name": "undo", "description": "Remove the last user/assistant exchange", "category": "Session", "args": None, "aliases": [], "gatewayOnly": False},
    {"name": "title", "description": "Set a title for the current session", "category": "Session", "args": "[name]", "aliases": [], "gatewayOnly": False},
    {"name": "branch", "description": "Branch the current session", "category": "Session", "args": "[name]", "aliases": ["fork"], "gatewayOnly": False},
    {"name": "compress", "description": "Manually compress conversation context", "category": "Session", "args": None, "aliases": [], "gatewayOnly": False},
    {"name": "rollback", "description": "List or restore filesystem checkpoints", "category": "Session", "args": "[number]", "aliases": [], "gatewayOnly": False},
    {"name": "stop", "description": "Kill all running background processes", "category": "Session", "args": None, "aliases": [], "gatewayOnly": False},
    {"name": "approve", "description": "Approve a pending dangerous command", "category": "Session", "args": "[session|always]", "aliases": [], "gatewayOnly": True},
    {"name": "deny", "description": "Deny a pending dangerous command", "category": "Session", "args": None, "aliases": [], "gatewayOnly": True},
    {"name": "background", "description": "Run a prompt in the background", "category": "Session", "args": "<prompt>", "aliases": ["bg"], "gatewayOnly": False},
    {"name": "btw", "description": "Ephemeral side question (no tools, not persisted)", "category": "Session", "args": "<question>", "aliases": [], "gatewayOnly": False},
    {"name": "queue", "description": "Queue a prompt for the next turn", "category": "Session", "args": "<prompt>", "aliases": ["q"], "gatewayOnly": False},
    {"name": "status", "description": "Show session info", "category": "Session", "args": None, "aliases": [], "gatewayOnly": True},
    {"name": "profile", "description": "Show active profile and home directory", "category": "Info", "args": None, "aliases": [], "gatewayOnly": False},
    {"name": "sethome", "description": "Set this chat as the home channel", "category": "Session", "args": None, "aliases": ["set-home"], "gatewayOnly": True},
    {"name": "resume", "description": "Resume a previously-named session", "category": "Session", "args": "[name]", "aliases": [], "gatewayOnly": False},
    {"name": "model", "description": "Switch model for this session", "category": "Configuration", "args": "[model] [--global]", "aliases": [], "gatewayOnly": False},
    {"name": "provider", "description": "Show available providers", "category": "Configuration", "args": None, "aliases": [], "gatewayOnly": False},
    {"name": "personality", "description": "Set a predefined personality", "category": "Configuration", "args": "[name]", "aliases": [], "gatewayOnly": False},
    {"name": "yolo", "description": "Toggle auto-approve mode", "category": "Configuration", "args": None, "aliases": [], "gatewayOnly": False},
    {"name": "reasoning", "description": "Manage reasoning effort and display", "category": "Configuration", "args": "[level|show|hide]", "aliases": [], "gatewayOnly": False},
    {"name": "voice", "description": "Toggle voice mode", "category": "Configuration", "args": "[on|off|tts|status]", "aliases": [], "gatewayOnly": False},
    {"name": "reload-mcp", "description": "Reload MCP servers from config", "category": "Tools & Skills", "args": None, "aliases": ["reload_mcp"], "gatewayOnly": False},
    {"name": "commands", "description": "Browse all commands and skills", "category": "Info", "args": "[page]", "aliases": [], "gatewayOnly": True},
    {"name": "help", "description": "Show available commands", "category": "Info", "args": None, "aliases": [], "gatewayOnly": False},
    {"name": "usage", "description": "Show token usage", "category": "Info", "args": None, "aliases": [], "gatewayOnly": False},
    {"name": "insights", "description": "Show usage insights", "category": "Info", "args": "[days]", "aliases": [], "gatewayOnly": False},
    {"name": "update", "description": "Update Hermes Agent", "category": "Info", "args": None, "aliases": [], "gatewayOnly": True},
]


_MEDIA_PATTERN = re.compile(
    r'''[`"']?MEDIA:\s*(?P<path>`[^`\n]+`|"[^"\n]+"|'[^'\n]+'|(?:~/|/)\S+(?:[^\S\n]+\S+)*?\.(?:png|jpe?g|gif|webp|mp4|mov|avi|mkv|webm|ogg|opus|mp3|wav|m4a)(?=[\s`"',;:)\]}]|$)|\S+)[`"']?'''
)

_MIME_TYPES = {
    ".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg",
    ".gif": "image/gif", ".webp": "image/webp",
    ".mp4": "video/mp4", ".mov": "video/quicktime", ".avi": "video/x-msvideo",
    ".mkv": "video/x-matroska", ".webm": "video/webm",
    ".ogg": "audio/ogg", ".opus": "audio/opus", ".mp3": "audio/mpeg",
    ".wav": "audio/wav", ".m4a": "audio/mp4",
}


def _extract_media_from_response(text: str) -> tuple[list[dict], str]:
    """Extract MEDIA: tags from agent response and encode files as attachments.

    Uses the same regex pattern as the Hermes gateway's extract_media().
    Files are read from disk, base64-encoded, and returned as attachment dicts
    compatible with the relay's attachments_data schema.

    Returns (attachments_list, cleaned_text).
    """
    import base64

    attachments: list[dict] = []
    cleaned = text.replace("[[audio_as_voice]]", "")

    for match in _MEDIA_PATTERN.finditer(text):
        raw_path = match.group("path").strip()
        # Strip surrounding quotes/backticks
        if len(raw_path) >= 2 and raw_path[0] == raw_path[-1] and raw_path[0] in "`\"'":
            raw_path = raw_path[1:-1].strip()
        raw_path = raw_path.lstrip("`\"'").rstrip("`\"',.;:)}]")
        if not raw_path:
            continue

        # Resolve path
        file_path = Path(raw_path).expanduser()
        if not file_path.is_file():
            continue

        ext = file_path.suffix.lower()
        mime = _MIME_TYPES.get(ext, "application/octet-stream")
        kind = "image" if mime.startswith("image/") else "file"

        try:
            data = file_path.read_bytes()
            # Skip files larger than 10MB
            if len(data) > 10 * 1024 * 1024:
                continue
            encoded = base64.b64encode(data).decode("ascii")
            attachments.append({
                "type": kind,
                "filename": file_path.name,
                "mimeType": mime,
                "data": encoded,
            })
        except Exception:
            continue

    if attachments:
        cleaned = _MEDIA_PATTERN.sub("", cleaned)
        cleaned = re.sub(r"\n{3,}", "\n\n", cleaned).strip()

    return attachments, cleaned


def _context_window_for(model_name: str, hermes_home: Path | None = None) -> int:
    """Resolve context window size using Hermes's own model_metadata.

    Calls the Hermes agent's Python environment directly to use
    get_model_context_length() — the same resolver the TUI status bar
    uses. Falls back to 128K if the subprocess fails.
    """
    if hermes_home is None:
        hermes_home = Path.home() / ".hermes"
    agent_venv_python = hermes_home / "hermes-agent" / "venv" / "bin" / "python3"
    agent_dir = hermes_home / "hermes-agent"

    if not agent_venv_python.exists():
        return 128_000

    try:
        result = subprocess.run(
            [
                str(agent_venv_python), "-c",
                f"from agent.model_metadata import get_model_context_length; print(get_model_context_length('{model_name}'))",
            ],
            cwd=str(agent_dir),
            capture_output=True, text=True, check=True, timeout=10,
        )
        return int(result.stdout.strip())
    except Exception:
        return 128_000


def _cached_context_window(hermes_home: Path, model_name: str, base_url: str | None) -> int | None:
    if not base_url:
        return None
    cache_path = hermes_home / "context_length_cache.yaml"
    if not cache_path.is_file():
        return None
    try:
        import yaml

        with open(cache_path, "r", encoding="utf-8") as f:
            payload = yaml.safe_load(f) or {}
        cache = payload.get("context_lengths", {})
        cached = cache.get(f"{model_name}@{base_url}")
        if isinstance(cached, int) and cached > 0:
            return cached
    except Exception:
        pass
    return None
from .git_diff import capture_diff, capture_snapshot
from .hermes_api_executor import HermesAPIExecutor
from .hermes_runner import ConnectorHermesSettings, HermesCLIExecutor
from .mcp_registration import (
    inspect_native_mcp_registration,
    native_mcp_readiness_message,
    register_native_mcp_server,
    validate_native_mcp_tools,
    validate_native_mcp_server,
)
from .sensor_store import HealthSample, LocationReading, SensorStore
from .runtime_adapter import HermesAPIRuntimeAdapter, HermesRuntimeAdapter, HostRuntimeAdapter, RuntimeConversationMessage
from .service_management import build_service_manager
from .setup_code import decode_host_setup_code
from .state import (
    ConnectorRuntimeConfig,
    ConnectorSecrets,
    ConnectorState,
    ConnectorStateStore,
    RealtimeTalkConfig,
)
from .talk_support import DEFAULT_REALTIME_MODELS, DEFAULT_REALTIME_VOICE, build_voice_context_snapshot

OPENAI_REALTIME_CLIENT_SECRETS_URL = "https://api.openai.com/v1/realtime/client_secrets"


def _read_env_file_value(path: Path, key: str) -> str | None:
    """Read a single KEY=value entry from a dotenv-style file."""
    if not path.is_file():
        return None
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError:
        return None
    for raw_line in lines:
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if line.lower().startswith("export "):
            line = line[7:].lstrip()
        name, sep, value = line.partition("=")
        if not sep or name.strip() != key:
            continue
        value = value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
            value = value[1:-1]
        return value or None
    return None


def utcnow_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


@dataclass(frozen=True)
class ConnectorMetadata:
    platform: str
    hostname: str
    connector_version: str
    hermes_command: str
    hermes_version: str | None
    hermes_model: str | None = None
    display_name: str | None = None


@dataclass(frozen=True)
class PhonePairingDetails:
    code: str
    display_code: str
    expires_at: str | None


class HermesMobileConnector:
    def __init__(
        self,
        *,
        state_store: ConnectorStateStore | None = None,
        executor: HermesCLIExecutor | None = None,
        heartbeat_interval_seconds: float = 10.0,
        reconnect_delay_seconds: float = 3.0,
    ) -> None:
        self.state_store = state_store or ConnectorStateStore()
        self.executor = executor or HermesCLIExecutor()
        self.heartbeat_interval_seconds = heartbeat_interval_seconds
        self.reconnect_delay_seconds = reconnect_delay_seconds
        self._sensor_store: SensorStore | None = None
        self._voice_delegate_sessions: dict[str, str] = {}
        self._health_cache: tuple[float, HostRuntimeAdapter | None] = (0.0, None)
        self._HEALTH_CACHE_TTL: float = 30.0

    @property
    def sensor_store(self) -> SensorStore:
        if self._sensor_store is None:
            self._sensor_store = SensorStore(self.state_store.state_dir / "sensors.db")
        return self._sensor_store

    def metadata(
        self,
        *,
        display_name: str | None = None,
        settings: ConnectorHermesSettings | None = None,
    ) -> ConnectorMetadata:
        effective_settings = settings or self.executor.settings
        version_executor = HermesCLIExecutor(effective_settings)
        # Read model name from config
        hermes_home = self._resolve_hermes_home()
        model_info = self._read_active_model(hermes_home)

        return ConnectorMetadata(
            platform=platform_module.system().lower(),
            hostname=socket.gethostname(),
            connector_version=__version__,
            hermes_command=effective_settings.hermes_command,
            hermes_version=version_executor.detect_version(),
            hermes_model=model_info["name"] if model_info else None,
            display_name=display_name,
        )

    def default_relay_url(self) -> str:
        return (os.getenv("HERMES_MOBILE_RELAY_URL") or "").rstrip("/")

    def setup(
        self,
        *,
        relay_url: str | None = None,
        configure_mcp: bool = True,
    ) -> ConnectorState:
        metadata = self.metadata()
        if metadata.hermes_version is None:
            raise RuntimeError(
                f"Hermes command not found or not runnable: {self.executor.settings.hermes_command}"
            )

        resolved_relay_url = (relay_url or self.default_relay_url()).rstrip("/")
        if not resolved_relay_url:
            raise RuntimeError(
                "Relay URL is required. Pass --relay-url or set HERMES_MOBILE_RELAY_URL."
            )
        setup_body: dict = {
            "connector": {
                "platform": metadata.platform,
                "hostname": metadata.hostname,
                "connectorVersion": metadata.connector_version,
                "hermesCommand": metadata.hermes_command,
                "hermesVersion": metadata.hermes_version,
                            "hermesModel": metadata.hermes_model,
            },
        }
        setup_secret = os.getenv("CONNECTOR_SETUP_SECRET")
        if setup_secret:
            setup_body["installationSecret"] = setup_secret
        response = httpx.post(
            f"{resolved_relay_url}/connector/setup",
            json=setup_body,
            timeout=30.0,
        )
        response.raise_for_status()
        data = response.json()["data"]
        runtime_config = self.capture_runtime_config(relay_url=resolved_relay_url)
        state = ConnectorState(
            relay_url=data["relayURL"],
            web_socket_url=data["webSocketURL"],
            user_id=data["user"]["id"],
            host_id=data["host"]["id"],
            connector_credential=data["connectorCredential"],
            enrolled_at=utcnow_iso(),
            runtime_config=runtime_config,
        )
        self.state_store.save(state)
        if configure_mcp:
            return self._configure_native_mcp(state, hermes_command=metadata.hermes_command)
        return self._mark_mcp_unconfigured(state)

    def enroll(
        self,
        *,
        code: str,
        display_name: str | None = None,
        configure_mcp: bool = True,
    ) -> ConnectorState:
        payload = decode_host_setup_code(code.strip())
        metadata = self.metadata(display_name=display_name)

        response = httpx.post(
            f"{payload.relay_url.rstrip('/')}/hosts/redeem",
            json={
                "enrollmentToken": payload.enrollment_token,
                "displayName": display_name,
                "connector": {
                    "platform": metadata.platform,
                    "hostname": metadata.hostname,
                    "connectorVersion": metadata.connector_version,
                    "hermesCommand": metadata.hermes_command,
                    "hermesVersion": metadata.hermes_version,
                            "hermesModel": metadata.hermes_model,
                },
            },
            timeout=30.0,
        )
        response.raise_for_status()
        data = response.json()["data"]
        runtime_config = self.capture_runtime_config(relay_url=payload.relay_url.rstrip("/"))
        state = ConnectorState(
            relay_url=data["relayURL"],
            web_socket_url=data["webSocketURL"],
            user_id=data["host"]["userId"],
            host_id=data["host"]["id"],
            connector_credential=data["connectorCredential"],
            connector_display_name=display_name,
            enrolled_at=utcnow_iso(),
            runtime_config=runtime_config,
        )
        self.state_store.save(state)
        if configure_mcp:
            return self._configure_native_mcp(state, hermes_command=metadata.hermes_command)
        return self._mark_mcp_unconfigured(state)

    def configure_mcp(self) -> ConnectorState:
        state = self.state_store.load()
        self.apply_runtime_environment(state)
        settings = self.settings_for_state(state)
        metadata = self.metadata(display_name=state.connector_display_name, settings=settings)
        return self._configure_native_mcp(state, hermes_command=metadata.hermes_command)

    def configure_realtime(
        self,
        *,
        api_key: str | None = None,
        clear: bool = False,
        validate: bool = True,
    ) -> ConnectorState:
        state = self.state_store.load()
        secrets = self.state_store.load_secrets()

        if clear:
            secrets.openai_api_key = None
            secrets.realtime_talk_enabled = None
            self.state_store.save_secrets(secrets)
            state.realtime_talk = RealtimeTalkConfig(enabled=False)
            state.voice_context_snapshot = None
            return self.state_store.save(state)

        normalized_api_key = (api_key or "").strip()
        if normalized_api_key:
            secrets.openai_api_key = normalized_api_key
            self.state_store.save_secrets(secrets)

        if not self.resolve_openai_api_key(secrets):
            raise RuntimeError("An OpenAI API key is required to configure Realtime talk mode.")

        config = state.realtime_talk or RealtimeTalkConfig()
        config.enabled = True
        if not config.preferred_models:
            config.preferred_models = list(DEFAULT_REALTIME_MODELS)
        if not config.voice:
            config.voice = DEFAULT_REALTIME_VOICE
        state.realtime_talk = config
        state = self.refresh_voice_context(state=state)
        self.state_store.save(state)

        if validate:
            return self.validate_realtime_configuration()
        return state

    def validate_realtime_configuration(self) -> ConnectorState:
        state = self.state_store.load()
        secrets = self.state_store.load_secrets()
        self.apply_runtime_environment(state)
        api_key = self.resolve_openai_api_key(secrets)
        if not api_key:
            config = state.realtime_talk or RealtimeTalkConfig(enabled=False)
            config.enabled = False
            config.last_validated_at = utcnow_iso()
            config.last_validation_error = self._NO_KEY_VALIDATION_ERROR
            config.last_selected_model = None
            state.realtime_talk = config
            return self.state_store.save(state)

        config = state.realtime_talk or RealtimeTalkConfig()
        state = self.refresh_voice_context(state=state)
        try:
            _, selected_model = self._create_openai_realtime_session(
                api_key=api_key,
                config=config,
                instructions="Validation run for Hermes Mobile talk mode.",
                relay_mcp_url=None,
            )
            config.enabled = True
            config.last_validated_at = utcnow_iso()
            config.last_validation_error = None
            config.last_selected_model = selected_model
            state.realtime_talk = config
            self.state_store.save(state)
            return state
        except Exception as error:  # noqa: BLE001
            config.enabled = True
            config.last_validated_at = utcnow_iso()
            config.last_validation_error = str(error)
            config.last_selected_model = None
            state.realtime_talk = config
            return self.state_store.save(state)

    _VOICE_CONTEXT_FRESH_SECONDS = 60.0  # prewarm rebuilds context; session create reuses if fresh

    def refresh_voice_context_if_stale(self, *, state: ConnectorState | None = None) -> ConnectorState:
        """Refresh voice context only if the snapshot is older than _VOICE_CONTEXT_FRESH_SECONDS."""
        state = state or self.state_store.load()
        snapshot = state.voice_context_snapshot
        if snapshot and snapshot.updated_at:
            try:
                from datetime import datetime, timezone
                age = (datetime.now(timezone.utc) - datetime.fromisoformat(snapshot.updated_at)).total_seconds()
                if age < self._VOICE_CONTEXT_FRESH_SECONDS:
                    return state
            except (ValueError, TypeError):
                pass
        return self.refresh_voice_context(state=state)

    def refresh_voice_context(self, *, state: ConnectorState | None = None) -> ConnectorState:
        state = state or self.state_store.load()
        self.apply_runtime_environment(state)
        settings = self.settings_for_state(state)
        readiness_summary = native_mcp_readiness_message(hermes_command=settings.hermes_command)
        if state.mcp_last_test_error:
            readiness_summary = f"{readiness_summary} ({state.mcp_last_test_error})"
        state.voice_context_snapshot = build_voice_context_snapshot(
            sensor_store=self.sensor_store,
            hermes_command=settings.hermes_command,
            hermes_home=state.runtime_config.hermes_home if state.runtime_config else os.getenv("HERMES_HOME"),
            readiness_summary=readiness_summary,
        )
        return self.state_store.save(state)

    def resolve_openai_api_key(self, secrets: ConnectorSecrets | None = None) -> str | None:
        """Locate the OpenAI API key across every supported storage location.

        Order: connector secrets store (`~/.hermes-mobile/secrets.json`),
        the OPENAI_API_KEY environment variable, then the Hermes settings
        (`$HERMES_HOME/.env`).
        """
        secrets = secrets or self.state_store.load_secrets()
        if secrets.openai_api_key:
            return secrets.openai_api_key
        env_key = (os.getenv("OPENAI_API_KEY") or "").strip()
        if env_key:
            return env_key
        return _read_env_file_value(self._resolve_hermes_home() / ".env", "OPENAI_API_KEY")

    @staticmethod
    def realtime_talk_enabled(state: ConnectorState, secrets: ConnectorSecrets) -> bool:
        """Effective talk-mode toggle: the secrets store wins when set there.

        Issue #7 documents `realtime_talk.enabled` in the connector secrets;
        `configure-realtime` stores it in state.json. Honor both.
        """
        if secrets.realtime_talk_enabled is not None:
            return secrets.realtime_talk_enabled
        return bool(state.realtime_talk and state.realtime_talk.enabled)

    _NO_KEY_VALIDATION_ERROR = "OpenAI API key is not configured."

    @classmethod
    def _effective_validation_error(cls, config: RealtimeTalkConfig, *, has_api_key: bool) -> str | None:
        """Drop the recorded no-key validation error once a key exists.

        A key added out-of-band (secrets.json hand-edit, env var, Hermes .env)
        doesn't re-run validation, so the persisted error would otherwise block
        readiness forever.
        """
        if has_api_key and config.last_validation_error == cls._NO_KEY_VALIDATION_ERROR:
            return None
        return config.last_validation_error

    def talk_readiness_payload(self) -> dict:
        state = self.state_store.load()
        config = state.realtime_talk or RealtimeTalkConfig(enabled=False)
        secrets = self.state_store.load_secrets()
        self.apply_runtime_environment(state)
        runtime = self.settings_for_state(state)
        has_api_key = bool(self.resolve_openai_api_key(secrets))
        enabled = self.realtime_talk_enabled(state, secrets)
        configured = bool(enabled and has_api_key)
        validation_error = self._effective_validation_error(config, has_api_key=has_api_key)
        blocked_reason = None
        if not has_api_key:
            blocked_reason = (
                "No OpenAI API key found. Run `hermes-mobile configure-realtime` "
                "or add openai_api_key to ~/.hermes-mobile/secrets.json."
            )
        elif not enabled:
            blocked_reason = (
                "Realtime talk is disabled. Run `hermes-mobile configure-realtime` "
                "or set realtime_talk.enabled in ~/.hermes-mobile/secrets.json."
            )
        elif validation_error:
            blocked_reason = validation_error
        return {
            "configured": configured and validation_error is None,
            "apiKeyPresent": has_api_key,
            "preferredModels": config.preferred_models or list(DEFAULT_REALTIME_MODELS),
            "selectedModel": config.last_selected_model,
            "voice": config.voice or DEFAULT_REALTIME_VOICE,
            "lastValidatedAt": config.last_validated_at,
            "lastValidationError": validation_error,
            "blockedReason": blocked_reason,
            "mcpReadiness": native_mcp_readiness_message(hermes_command=runtime.hermes_command),
            "voiceContextUpdatedAt": state.voice_context_snapshot.updated_at if state.voice_context_snapshot else None,
        }

    def refresh_runtime_config(self, *, force: bool = False) -> ConnectorState:
        state = self.state_store.load()
        if state.runtime_config is not None and not force:
            return state

        state.runtime_config = self.capture_runtime_config(relay_url=state.relay_url)
        return self.state_store.save(state)

    def create_phone_pairing_code(self) -> PhonePairingDetails:
        state = self.state_store.load()
        response = httpx.post(
            f"{state.relay_url.rstrip('/')}/connector/phone-pairing-codes",
            headers={"Authorization": f"Bearer {state.connector_credential}"},
            timeout=30.0,
        )
        response.raise_for_status()
        data = response.json()["data"]
        return PhonePairingDetails(
            code=data["code"],
            display_code=data["displayCode"],
            expires_at=data.get("expiresAt"),
        )

    async def run_forever(self) -> None:
        while True:
            state = self.state_store.load()
            try:
                await self._run_once(state)
            except KeyboardInterrupt:
                raise
            except Exception as error:  # noqa: BLE001
                state.last_error = str(error)
                self.state_store.save(state)
                await asyncio.sleep(self.reconnect_delay_seconds)

    async def _run_once(self, state: ConnectorState) -> None:
        state = self.refresh_runtime_config(force=False)
        state = self.refresh_voice_context(state=state)
        self.apply_runtime_environment(state)
        settings = self.settings_for_state(state)
        metadata = self.metadata(display_name=state.connector_display_name, settings=settings)
        async with websocket_connect(
            state.web_socket_url,
            additional_headers={"Authorization": f"Bearer {state.connector_credential}"},
            max_size=50 * 1024 * 1024,  # 50 MB — job payloads with image attachments can be large
        ) as websocket:
            await websocket.send(
                json.dumps(
                    {
                        "type": "hello",
                        "version": 1,
                        "connector": {
                            "platform": metadata.platform,
                            "hostname": metadata.hostname,
                            "connectorVersion": metadata.connector_version,
                            "hermesCommand": metadata.hermes_command,
                            "hermesVersion": metadata.hermes_version,
                            "hermesModel": metadata.hermes_model,
                            "displayName": metadata.display_name,
                        },
                    }
                )
            )

            ready = json.loads(await websocket.recv())
            if ready.get("type") != "ready":
                raise RuntimeError("Relay did not accept the connector session.")

            state.last_connected_at = utcnow_iso()
            state.last_error = None
            self.state_store.save(state)

            while True:
                try:
                    raw_message = await asyncio.wait_for(
                        websocket.recv(),
                        timeout=self.heartbeat_interval_seconds,
                    )
                except asyncio.TimeoutError:
                    await websocket.send(json.dumps({"type": "heartbeat"}))
                    continue

                message = json.loads(raw_message)
                message_type = message.get("type")
                if message_type == "job.execute":
                    await self._handle_job(websocket, message["job"])
                    continue
                if message_type == "rpc.request":
                    await websocket.send(json.dumps(await self._handle_rpc_request(message)))
                    continue
                if message_type == "ready":
                    continue
                sensor_ack = self._handle_sensor_message(message)
                if sensor_ack is not None:
                    await websocket.send(json.dumps(sensor_ack))
                    continue
                logger.warning("Ignoring unknown relay message type: %s", message_type)
                continue

    def _handle_sensor_message(self, message: dict) -> dict | None:
        """Store a sensor message locally and return an ACK payload when handled."""
        message_type = message.get("type", "")
        delivery_id = message.get("deliveryId")
        if message_type == "sensor.location":
            try:
                self.sensor_store.store_location(
                    LocationReading(
                        latitude=message["latitude"],
                        longitude=message["longitude"],
                        altitude=message.get("altitude"),
                        accuracy=message.get("accuracy"),
                        address=message.get("address"),
                        recorded_at=message.get("recordedAt"),
                    )
                )
                return {
                    "type": "sensor.ack",
                    "deliveryId": delivery_id,
                    "deliveryState": "delivered",
                }
            except Exception as error:  # noqa: BLE001
                return {
                    "type": "sensor.ack",
                    "deliveryId": delivery_id,
                    "deliveryState": "retry",
                    "error": str(error),
                }
        if message_type == "sensor.health":
            try:
                samples = [
                    HealthSample(
                        metric=s["metric"],
                        value=s["value"],
                        unit=s["unit"],
                        start_at=s["startAt"],
                        end_at=s.get("endAt"),
                    )
                    for s in message.get("samples", [])
                ]
                if samples:
                    self.sensor_store.store_health_samples(samples)
                return {
                    "type": "sensor.ack",
                    "deliveryId": delivery_id,
                    "deliveryState": "delivered",
                }
            except Exception as error:  # noqa: BLE001
                return {
                    "type": "sensor.ack",
                    "deliveryId": delivery_id,
                    "deliveryState": "retry",
                    "error": str(error),
                }
        return None

    async def _handle_job(self, websocket, job: dict) -> None:
        state = self.state_store.load()
        workdir = state.runtime_config.hermes_workdir if state.runtime_config else None

        # Stage image attachments to disk and replace them with vision context
        # in the user message. The Hermes API server can't handle multipart
        # content arrays, but the agent's vision_analyze tool works on local files.
        # Do this BEFORE runtime selection so streaming still works for image jobs.
        attachments = job.get("attachments") or []
        if attachments:
            attachment_context = self._build_cli_attachment_context(
                job_id=str(job["id"]),
                attachments=attachments,
            )
            if attachment_context:
                msg = job.get("latestUserMessage", "")
                job["latestUserMessage"] = (
                    f"{msg}\n\n{attachment_context}" if msg.strip() else attachment_context
                )
            job["attachments"] = None  # staged to disk; don't pass raw data downstream

        try:
            runtime = await self.runtime_adapter_for_state_async(state)
            if not getattr(runtime, "supports_streaming", False):
                await self._handle_job_cli(websocket, job, runtime)
                return

            await self._handle_job_streaming(websocket, job, runtime, workdir=workdir)
        finally:
            # Clean up staged attachment files after job completes
            staging_dir = self.state_store.state_dir / "attachment_staging" / str(job["id"])
            if staging_dir.exists():
                import shutil
                shutil.rmtree(staging_dir, ignore_errors=True)

    async def _handle_job_streaming(
        self, websocket, job: dict, runtime, *, workdir: str | None = None,
    ) -> None:
        """Process a job using the Hermes API server with streaming events."""
        try:
            accumulated_text = ""
            session_id: str | None = None
            usage: dict | None = None

            # Snapshot git state before Hermes runs so we can diff afterwards
            pre_snapshot = await capture_snapshot(workdir) if workdir else None

            history = [
                RuntimeConversationMessage(role=item["role"], text=item["text"])
                for item in job.get("history", [])
            ]

            # Prepend voice transcript context so the Hermes agent sees the
            # voice conversation even when using its own session history.
            user_message = job["latestUserMessage"]
            voice_context = job.get("voiceTranscriptContext")
            if voice_context:
                user_message = (
                    f"[Recent voice conversation for context]\n{voice_context}\n"
                    f"[End voice conversation]\n\n{user_message}"
                )

            async for event in runtime.send_text_message_streaming(
                latest_user_message=user_message,
                history=history,
                session_id=job.get("sessionId"),
                attachments=job.get("attachments"),
            ):
                if event.type == "text_delta":
                    accumulated_text += event.data
                    await websocket.send(json.dumps({
                        "type": "job.progress",
                        "jobId": job["id"],
                        "kind": "text_delta",
                        "delta": event.data,
                    }))
                elif event.type == "tool_activity":
                    await websocket.send(json.dumps({
                        "type": "job.progress",
                        "jobId": job["id"],
                        "kind": "tool_activity",
                        "label": event.label,
                    }))
                elif event.type == "finish":
                    session_id = event.session_id
                    usage = event.usage

            final_text = accumulated_text.strip()
            if not final_text:
                raise RuntimeError("Hermes API server returned an empty response.")

            # Capture what files Hermes changed during this job
            diff_data = await capture_diff(workdir, pre_snapshot) if pre_snapshot else None

            # Extract MEDIA: tags from the response — same pattern the
            # Hermes gateway uses to deliver files on Discord/Telegram.
            media_attachments, cleaned_text = _extract_media_from_response(final_text)

            result_payload: dict = {
                "type": "job.result",
                "jobId": job["id"],
                "text": cleaned_text,
                "sessionId": session_id,
                "usage": usage,
            }
            if media_attachments:
                result_payload["attachments"] = media_attachments
            if diff_data is not None:
                result_payload["diff"] = diff_data

            await websocket.send(json.dumps(result_payload))
        except Exception as error:  # noqa: BLE001
            await websocket.send(json.dumps({
                "type": "job.failed",
                "jobId": job["id"],
                "retryable": self._is_retryable_job_error(error),
                "error": str(error),
            }))

    async def _handle_job_cli(self, websocket, job: dict, runtime) -> None:
        """Process a job using the CLI subprocess (original path)."""

        async def execute_job() -> dict:
            try:
                user_message = job["latestUserMessage"]
                voice_context = job.get("voiceTranscriptContext")
                if voice_context:
                    user_message = (
                        f"[Recent voice conversation for context]\n{voice_context}\n"
                        f"[End voice conversation]\n\n{user_message}"
                    )
                attachments = job.get("attachments") or []
                if attachments:
                    attachment_context = self._build_cli_attachment_context(
                        job_id=str(job["id"]),
                        attachments=attachments,
                    )
                    if attachment_context:
                        user_message = (
                            f"{user_message}\n\n{attachment_context}"
                            if user_message.strip()
                            else attachment_context
                        )

                result = await asyncio.to_thread(
                    runtime.send_text_message,
                    latest_user_message=user_message,
                    history=[
                        RuntimeConversationMessage(role=item["role"], text=item["text"])
                        for item in job.get("history", [])
                    ],
                    session_id=job.get("sessionId"),
                )
                return {
                    "type": "job.result",
                    "jobId": job["id"],
                    "text": result.text,
                    "sessionId": result.session_id,
                }
            except Exception as error:  # noqa: BLE001
                return {
                    "type": "job.failed",
                    "jobId": job["id"],
                    "retryable": self._is_retryable_job_error(error),
                    "error": str(error),
                }

        task = asyncio.create_task(execute_job())
        while True:
            done, _ = await asyncio.wait({task}, timeout=self.heartbeat_interval_seconds)
            if task in done:
                await websocket.send(json.dumps(task.result()))
                return
            await websocket.send(json.dumps({"type": "heartbeat"}))

    def _build_cli_attachment_context(self, *, job_id: str, attachments: list[dict]) -> str:
        attachment_root = self.state_store.state_dir / "attachment_staging" / job_id
        attachment_root.mkdir(parents=True, exist_ok=True)

        lines = [
            "The user attached files for this request. Use them if they are relevant.",
        ]
        for index, attachment in enumerate(attachments, start=1):
            filename = self._sanitize_attachment_filename(attachment.get("filename") or f"attachment-{index}")
            mime_type = str(attachment.get("mimeType") or "application/octet-stream")
            data_b64 = str(attachment.get("data") or "")
            if not data_b64:
                continue

            try:
                raw_data = base64.b64decode(data_b64)
            except Exception:
                continue

            file_path = attachment_root / filename
            file_path.write_bytes(raw_data)

            if mime_type.startswith("image/"):
                lines.append(
                    f"- Image attachment available at {file_path}. If you need to inspect it, use vision_analyze with image_url: {file_path}"
                )
            elif self._is_text_like_attachment(mime_type):
                lines.append(
                    f"- Text attachment available at {file_path}. Read it with read_file if you need its contents."
                )
            else:
                lines.append(f"- Binary attachment available at {file_path} ({mime_type}).")

        return "\n".join(lines)

    @staticmethod
    # _should_use_cli_runtime removed — attachment staging now happens in
    # _handle_job before runtime selection, so all jobs go through streaming.

    @staticmethod
    def _is_retryable_job_error(error: Exception) -> bool:
        if isinstance(error, (ConnectionError, TimeoutError, OSError, httpx.TransportError, httpx.TimeoutException)):
            return True

        message = str(error).lower()
        transient_markers = (
            "connection refused",
            "temporarily unavailable",
            "timed out",
            "timeout",
            "network is unreachable",
            "connection reset",
            "broken pipe",
        )
        return any(marker in message for marker in transient_markers)

    @staticmethod
    def _sanitize_attachment_filename(filename: str) -> str:
        cleaned = re.sub(r'[^A-Za-z0-9._-]+', "_", filename).strip("._")
        return cleaned or "attachment"

    @staticmethod
    def _is_text_like_attachment(mime_type: str) -> bool:
        return mime_type.startswith("text/") or mime_type in {
            "application/json",
            "application/xml",
            "application/yaml",
            "application/x-yaml",
        }

    async def _handle_rpc_request(self, message: dict) -> dict:
        request_id = message.get("requestId") or str(uuid.uuid4())
        method = message.get("method")
        params = message.get("params") or {}

        try:
            if method == "talk.prewarm":
                result = self._rpc_talk_prewarm()
            elif method == "talk.session.create":
                result = self._rpc_talk_session_create(params)
            elif method == "talk.session.end":
                result = self._rpc_talk_session_end(params)
            elif method in {"talk.delegate", "talk.hermes_delegate"}:
                result = await self._rpc_talk_delegate(params)
            elif method == "commands.catalog":
                result = self._rpc_commands_catalog()
            else:
                raise RuntimeError(f"Unsupported RPC method: {method}")
            return {
                "type": "rpc.response",
                "requestId": request_id,
                "success": True,
                "result": result,
            }
        except Exception as error:  # noqa: BLE001
            return {
                "type": "rpc.response",
                "requestId": request_id,
                "success": False,
                "error": str(error),
            }

    def _rpc_talk_prewarm(self) -> dict:
        state = self.refresh_voice_context()
        return self.talk_readiness_payload() | {
            "voiceContextUpdatedAt": state.voice_context_snapshot.updated_at if state.voice_context_snapshot else None,
        }

    def _rpc_talk_session_create(self, params: dict) -> dict:
        state = self.refresh_voice_context_if_stale()
        config = state.realtime_talk or RealtimeTalkConfig(enabled=False)
        secrets = self.state_store.load_secrets()
        resolved_api_key = self.resolve_openai_api_key(secrets)
        if not self.realtime_talk_enabled(state, secrets) or not resolved_api_key:
            raise RuntimeError("OpenAI Realtime talk mode is not configured on this Hermes host.")
        validation_error = self._effective_validation_error(config, has_api_key=True)
        if validation_error:
            raise RuntimeError(validation_error)

        relay_mcp_url = params.get("relayMcpURL")
        if not relay_mcp_url:
            raise RuntimeError("Relay MCP URL is required.")

        snapshot = state.voice_context_snapshot
        if snapshot is None:
            raise RuntimeError("Voice context is not ready yet.")

        session_payload, selected_model = self._create_openai_realtime_session(
            api_key=resolved_api_key,
            config=config,
            instructions=snapshot.system_prompt,
            relay_mcp_url=relay_mcp_url,
        )

        config.last_selected_model = selected_model
        config.last_validated_at = utcnow_iso()
        config.last_validation_error = None
        state.realtime_talk = config
        self.state_store.save(state)

        # The /v1/realtime/client_secrets response puts the ephemeral key at the
        # top level: {"value": "ek_...", "expires_at": ..., "session": {...}}
        # Also support the legacy nested format just in case.
        client_secret = session_payload.get("client_secret")
        if isinstance(client_secret, dict):
            secret_value = client_secret.get("value")
            expires_at = client_secret.get("expires_at")
            session_data = {k: v for k, v in session_payload.items() if k != "client_secret"}
        else:
            secret_value = session_payload.get("value")
            expires_at = session_payload.get("expires_at")
            session_data = session_payload.get("session") or {}
        if isinstance(expires_at, (int, float)):
            expires_at = datetime.fromtimestamp(expires_at, timezone.utc).isoformat()
        return {
            "clientSecret": secret_value,
            "expiresAt": expires_at,
            "session": session_data,
            "model": selected_model,
            "voice": config.voice or DEFAULT_REALTIME_VOICE,
            "voiceContextUpdatedAt": snapshot.updated_at,
        }

    def _rpc_commands_catalog(self) -> dict:
        """Return the slash command catalog for iOS autocomplete and manual dispatch.

        The iOS app uses this to populate its slash command menu dynamically,
        matching Hermes docs more closely:
        - gateway-available built-in commands
        - installed skills
        - custom personalities from ~/.hermes/config.yaml
        - quick commands from ~/.hermes/config.yaml

        Quick commands are included in the payload for completeness, but Hermes
        docs say they resolve at dispatch time and are not shown in the built-in
        autocomplete tables.
        """
        hermes_home = self._resolve_hermes_home()

        commands = _GATEWAY_COMMANDS
        skills = self._load_installed_skills(hermes_home)
        personalities = self._load_custom_personalities(hermes_home)
        quick_commands = self._load_quick_commands(hermes_home)

        # Read active model/provider from config
        model_info = self._read_active_model(hermes_home)

        return {
            "commands": commands,
            "skills": skills,
            "personalities": personalities,
            "quickCommands": quick_commands,
            "activeModel": model_info,
        }

    @staticmethod
    def _read_active_model(hermes_home: Path) -> dict | None:
        """Read the active model name and provider from ~/.hermes/config.yaml."""
        config_path = hermes_home / "config.yaml"
        if not config_path.is_file():
            return None
        try:
            import yaml
        except ImportError:
            # Fall back to basic parsing if PyYAML isn't available
            try:
                text = config_path.read_text(encoding="utf-8")
                model_name = None
                provider = None
                context_length = None
                base_url = None
                for line in text.splitlines():
                    stripped = line.strip()
                    if stripped.startswith("default:") and model_name is None:
                        model_name = stripped.split(":", 1)[1].strip()
                    if stripped.startswith("provider:") and provider is None:
                        provider = stripped.split(":", 1)[1].strip()
                    if stripped.startswith("context_length:") and context_length is None:
                        try:
                            context_length = int(stripped.split(":", 1)[1].strip())
                        except ValueError:
                            context_length = None
                    if stripped.startswith("base_url:") and base_url is None:
                        base_url = stripped.split(":", 1)[1].strip()
                if model_name:
                    resolved_context = (
                        context_length
                        or _cached_context_window(hermes_home, model_name, base_url)
                        or _context_window_for(model_name, hermes_home=hermes_home)
                    )
                    return {"name": model_name, "provider": provider, "contextWindow": resolved_context}
            except Exception:
                pass
            return None
        try:
            with open(config_path, "r", encoding="utf-8") as f:
                config = yaml.safe_load(f)
            model_section = config.get("model", {})
            model_name = model_section.get("default")
            provider = model_section.get("provider")
            base_url = model_section.get("base_url")
            context_length = model_section.get("context_length")
            if model_name:
                try:
                    resolved_context = int(context_length) if context_length is not None else None
                except (TypeError, ValueError):
                    resolved_context = None
                resolved_context = (
                    resolved_context
                    or _cached_context_window(hermes_home, model_name, base_url)
                    or _context_window_for(model_name)
                )
                return {"name": model_name, "provider": provider, "contextWindow": resolved_context}
        except Exception:
            pass
        return None

    def _resolve_hermes_home(self) -> Path:
        try:
            state = self.state_store.load()
            runtime_home = state.runtime_config.hermes_home if state.runtime_config else None
            if runtime_home:
                return Path(runtime_home).expanduser()
        except Exception:
            pass

        env_home = os.getenv("HERMES_HOME")
        if env_home:
            return Path(env_home).expanduser()
        return Path.home() / ".hermes"

    def _load_custom_personalities(self, hermes_home: Path) -> list[dict]:
        entries = self._read_named_yaml_string_map(
            hermes_home / "config.yaml",
            section_name="personalities",
        )
        personalities: list[dict] = []
        for name, description in sorted(entries.items()):
            summary = description.strip() or f"Use the {name} personality"
            personalities.append(
                {
                    "name": name,
                    "description": summary[:140],
                }
            )
        return personalities

    def _load_installed_skills(self, hermes_home: Path) -> list[dict]:
        skills = self._load_installed_skills_from_cli(hermes_home)
        if skills:
            return skills
        return self._load_installed_skills_from_directory(hermes_home)

    def _load_installed_skills_from_cli(self, hermes_home: Path) -> list[dict]:
        env = dict(os.environ)
        env["HERMES_HOME"] = str(hermes_home)
        env["COLUMNS"] = "200"
        env["NO_COLOR"] = "1"
        env["TERM"] = "dumb"

        # Resolve the hermes command path: try executor, then state, then bare name
        hermes_cmd = self.executor.resolved_command_path() or self.executor.settings.hermes_command
        if hermes_cmd == "hermes":
            try:
                state = self.state_store.load()
                if state.runtime_config and state.runtime_config.hermes_command:
                    hermes_cmd = state.runtime_config.hermes_command
            except Exception:
                pass

        try:
            completed = subprocess.run(
                [hermes_cmd, "skills", "list"],
                cwd=self.executor.settings.hermes_workdir or None,
                env=env,
                capture_output=True,
                text=True,
                check=False,
            )
        except Exception:
            return []

        if completed.returncode != 0:
            return []

        skills: list[dict] = []
        seen_names: set[str] = set()
        for raw_line in completed.stdout.splitlines():
            line = raw_line.strip()
            if not line:
                continue
            # Rich table format: │ name │ category │ source │ trust │
            if "│" in line:
                # Split on │ keeping all cells (including empty ones)
                cells = [c.strip() for c in line.split("│")]
                # First and last are empty from leading/trailing │
                cells = cells[1:-1] if len(cells) > 2 else cells
                if len(cells) >= 1:
                    name = cells[0].strip()
                    # Skip header row and separator lines
                    if not name or name.lower() == "name" or not re.match(r"^[A-Za-z0-9._-]+$", name):
                        continue
                    if name in seen_names:
                        continue
                    seen_names.add(name)
                    category = cells[1].strip() if len(cells) > 1 else ""
                    # Try to get a better description from SKILL.md
                    desc = self._read_skill_description(hermes_home, name)
                    if not desc:
                        desc = f"{category} skill" if category else f"Invoke the {name} skill"
                    skills.append({"name": name, "description": desc})
                continue
            # Plain text fallback: name  description
            match = re.match(r"^(?P<name>[A-Za-z0-9._-]+)\s{2,}(?P<desc>.+)$", line)
            if match:
                name = match.group("name")
                if name not in seen_names:
                    seen_names.add(name)
                    skills.append({"name": name, "description": match.group("desc").strip()[:140]})
        return skills

    @staticmethod
    def _read_skill_description(hermes_home: Path, skill_name: str) -> str:
        """Read the first non-header, non-frontmatter line from a skill's SKILL.md."""
        # Skills can be nested: skills/category/skill-name/SKILL.md or skills/skill-name/SKILL.md
        for candidate in [
            hermes_home / "skills" / skill_name / "SKILL.md",
            *(hermes_home / "skills").glob(f"*/{skill_name}/SKILL.md"),
        ]:
            if candidate.is_file():
                try:
                    with open(candidate, "r", encoding="utf-8") as f:
                        in_frontmatter = False
                        for line in f:
                            stripped = line.strip()
                            if stripped == "---":
                                in_frontmatter = not in_frontmatter
                                continue
                            if in_frontmatter or not stripped or stripped.startswith("#"):
                                continue
                            return stripped[:120]
                except Exception:
                    pass
        return ""

    def _load_installed_skills_from_directory(self, hermes_home: Path) -> list[dict]:
        skills: list[dict] = []
        skills_dir = hermes_home / "skills"
        if skills_dir.is_dir():
            for skill_dir in sorted(skills_dir.iterdir()):
                skill_file = skill_dir / "SKILL.md"
                if skill_file.is_file():
                    desc = ""
                    try:
                        with open(skill_file, "r", encoding="utf-8") as f:
                            for line in f:
                                line = line.strip()
                                if line and not line.startswith("#") and not line.startswith("---"):
                                    desc = line[:80]
                                    break
                    except Exception:
                        pass
                    skills.append({
                        "name": skill_dir.name,
                        "description": desc or f"Invoke the {skill_dir.name} skill",
                    })
        return skills

    def _load_quick_commands(self, hermes_home: Path) -> list[dict]:
        entries = self._read_quick_command_map(hermes_home / "config.yaml")
        quick_commands: list[dict] = []
        for name in sorted(entries):
            description = entries[name]
            quick_commands.append(
                {
                    "name": name,
                    "description": description,
                }
            )
        return quick_commands

    def _read_named_yaml_string_map(self, config_path: Path, *, section_name: str) -> dict[str, str]:
        text = self._read_text_file(config_path)
        if not text:
            return {}

        section_lines = self._extract_top_level_yaml_section(text, section_name)
        results: dict[str, str] = {}
        index = 0

        while index < len(section_lines):
            indent, raw_line = section_lines[index]
            stripped = raw_line.strip()

            if not stripped or stripped.startswith("#") or indent != 2 or ":" not in stripped:
                index += 1
                continue

            key, value = stripped.split(":", 1)
            key = key.strip()
            value = value.strip()
            if not key:
                index += 1
                continue

            if value in {"|", ">", "|-", ">-", "|+", ">+"}:
                block_lines: list[str] = []
                index += 1
                while index < len(section_lines):
                    next_indent, next_line = section_lines[index]
                    if next_indent <= indent:
                        break
                    block_lines.append(next_line[indent + 2 :] if len(next_line) > indent + 2 else "")
                    index += 1
                joined = self._normalize_yaml_block_scalar(block_lines, folded=value.startswith(">"))
                if joined:
                    results[key] = joined
                continue

            normalized = self._strip_yaml_scalar(value)
            if normalized:
                results[key] = normalized
            index += 1

        return results

    def _read_quick_command_map(self, config_path: Path) -> dict[str, str]:
        text = self._read_text_file(config_path)
        if not text:
            return {}

        section_lines = self._extract_top_level_yaml_section(text, "quick_commands")
        results: dict[str, str] = {}
        index = 0

        while index < len(section_lines):
            indent, raw_line = section_lines[index]
            stripped = raw_line.strip()
            if not stripped or stripped.startswith("#") or indent != 2 or not stripped.endswith(":"):
                index += 1
                continue

            command_name = stripped[:-1].strip()
            index += 1
            command_type: str | None = None
            shell_command: str | None = None
            description: str | None = None

            while index < len(section_lines):
                next_indent, next_line = section_lines[index]
                next_stripped = next_line.strip()

                if not next_stripped or next_stripped.startswith("#"):
                    index += 1
                    continue
                if next_indent <= indent:
                    break
                if next_indent != 4 or ":" not in next_stripped:
                    index += 1
                    continue

                key, value = next_stripped.split(":", 1)
                key = key.strip()
                value = value.strip()

                if value in {"|", ">", "|-", ">-", "|+", ">+"}:
                    block_lines: list[str] = []
                    index += 1
                    while index < len(section_lines):
                        block_indent, block_line = section_lines[index]
                        if block_indent <= next_indent:
                            break
                        block_lines.append(block_line[next_indent + 2 :] if len(block_line) > next_indent + 2 else "")
                        index += 1
                    parsed_value = self._normalize_yaml_block_scalar(block_lines, folded=value.startswith(">"))
                else:
                    parsed_value = self._strip_yaml_scalar(value)
                    index += 1

                if key == "type":
                    command_type = parsed_value
                elif key == "command":
                    shell_command = parsed_value
                elif key in {"description", "help"}:
                    description = parsed_value

            if command_type == "exec":
                summary = description or shell_command or f"Run the {command_name} quick command"
                results[command_name] = summary[:140]

        return results

    def _read_text_file(self, path: Path) -> str | None:
        try:
            if path.is_file():
                return path.read_text(encoding="utf-8")
        except Exception:
            return None
        return None

    def _extract_top_level_yaml_section(self, text: str, section_name: str) -> list[tuple[int, str]]:
        section_lines: list[tuple[int, str]] = []
        in_section = False
        section_indent = 0

        for raw_line in text.splitlines():
            stripped = raw_line.strip()
            indent = len(raw_line) - len(raw_line.lstrip(" "))

            if not in_section:
                if indent == 0 and stripped.startswith(f"{section_name}:"):
                    in_section = True
                    section_indent = indent
                continue

            if stripped and not stripped.startswith("#") and indent <= section_indent:
                break

            section_lines.append((indent, raw_line))

        return section_lines

    def _strip_yaml_scalar(self, value: str) -> str:
        normalized = value.strip()
        if len(normalized) >= 2 and normalized[0] == normalized[-1] and normalized[0] in {"'", '"'}:
            return normalized[1:-1]
        return normalized

    def _normalize_yaml_block_scalar(self, lines: list[str], *, folded: bool) -> str:
        cleaned = [line.rstrip() for line in lines]
        if folded:
            return " ".join(line.strip() for line in cleaned if line.strip())
        return "\n".join(cleaned).strip()

    def _rpc_talk_session_end(self, params: dict) -> dict:
        voice_session_id = str(params.get("voiceSessionId") or "").strip()
        if voice_session_id:
            self._voice_delegate_sessions.pop(voice_session_id, None)
        return {"ended": True, "voiceSessionId": voice_session_id or None}

    async def _rpc_talk_delegate(self, params: dict) -> dict:
        voice_session_id = str(params.get("voiceSessionId") or "").strip()
        prompt = str(params.get("prompt") or "").strip()
        if not voice_session_id:
            raise RuntimeError("voiceSessionId is required.")
        if not prompt:
            raise RuntimeError("prompt is required.")

        state = self.state_store.load()
        runtime = await self.runtime_adapter_for_state_async(state)
        session_id = self._voice_delegate_sessions.get(voice_session_id)
        result = await asyncio.to_thread(
            runtime.delegate_talk_turn,
            prompt=prompt,
            session_id=session_id,
        )
        if result.session_id:
            self._voice_delegate_sessions[voice_session_id] = result.session_id
        return {
            "text": result.text,
            "sessionId": result.session_id,
            "voiceSessionId": voice_session_id,
        }

    def _create_openai_realtime_session(
        self,
        *,
        api_key: str,
        config: RealtimeTalkConfig,
        instructions: str,
        relay_mcp_url: str | None,
    ) -> tuple[dict, str]:
        last_error: str | None = None
        preferred_models = config.preferred_models or list(DEFAULT_REALTIME_MODELS)
        for model in preferred_models:
            try:
                turn_detection: dict = {
                    "type": config.turn_detection_type,
                    "create_response": config.create_response,
                    "interrupt_response": config.interrupt_response,
                }
                if config.turn_detection_type == "semantic_vad":
                    turn_detection["eagerness"] = "medium"

                session_definition: dict = {
                    "type": "realtime",
                    "model": model,
                    "instructions": instructions,
                    "audio": {
                        "output": {
                            "voice": config.voice or DEFAULT_REALTIME_VOICE,
                        },
                        "input": {
                            "turn_detection": turn_detection,
                            "transcription": {
                                "model": "gpt-4o-mini-transcribe",
                            },
                        },
                    },
                }
                if relay_mcp_url:
                    session_definition["tools"] = [
                        {
                            "type": "mcp",
                            "server_label": "hermes_mobile_relay",
                            "server_url": relay_mcp_url,
                            "allowed_tools": ["hermes_delegate"],
                            "require_approval": "never",
                        }
                    ]

                response = httpx.post(
                    OPENAI_REALTIME_CLIENT_SECRETS_URL,
                    headers={
                        "Authorization": f"Bearer {api_key}",
                        "Content-Type": "application/json",
                    },
                    json={"session": session_definition},
                    timeout=30.0,
                )
                if response.status_code >= 400:
                    message = self._extract_http_error_message(response)
                    last_error = message
                    continue
                return response.json(), model
            except Exception as error:  # noqa: BLE001
                last_error = str(error)
                continue

        raise RuntimeError(last_error or "OpenAI Realtime session creation failed.")

    @staticmethod
    def _extract_http_error_message(response: httpx.Response) -> str:
        try:
            payload = response.json()
        except Exception:  # noqa: BLE001
            return response.text or f"HTTP {response.status_code}"

        error = payload.get("error")
        if isinstance(error, dict):
            message = error.get("message")
            if message:
                return str(message)
        message = payload.get("message")
        if message:
            return str(message)
        return response.text or f"HTTP {response.status_code}"

    def status_lines(self) -> list[str]:
        state = self.state_store.load()
        self.apply_runtime_environment(state)
        settings = self.settings_for_state(state)
        metadata = self.metadata(display_name=state.connector_display_name, settings=settings)
        mcp_status = inspect_native_mcp_registration(server_name=state.mcp_server_name)
        sensor_status = self.sensor_store.get_sensor_freshness_summary()
        service_status = build_service_manager(self.state_store).status()
        talk_status = self.talk_readiness_payload()
        lines = [
            f"Relay URL: {state.relay_url}",
            f"WebSocket URL: {state.web_socket_url}",
            f"User ID: {state.user_id or 'unknown'}",
            f"Host ID: {state.host_id}",
            f"Hermes command: {metadata.hermes_command}",
            f"Hermes version: {metadata.hermes_version or 'unknown'}",
            f"Native MCP config: {'present' if mcp_status.registered else 'missing'}",
            f"MCP command: {mcp_status.command_path or state.mcp_command_path or 'unknown'}",
            f"MCP tools: {', '.join(mcp_status.included_tools) if mcp_status.included_tools else 'none configured'}",
            f"MCP validation: {self._mcp_validation_summary(state=state, mcp_status=mcp_status)}",
            f"MCP readiness: {native_mcp_readiness_message(hermes_command=metadata.hermes_command)}",
            f"Realtime talk: {'configured' if talk_status['configured'] else 'not configured'}",
            f"Realtime models: {', '.join(talk_status['preferredModels'])}",
            f"Realtime selected model: {talk_status['selectedModel'] or 'none'}",
            f"Realtime API key: {'present' if talk_status['apiKeyPresent'] else 'missing'}",
            f"Realtime validation: {talk_status['lastValidationError'] or 'ok'}",
            f"Background service: {service_status.summary}",
            f"Last connected: {state.last_connected_at or 'never'}",
            f"Last error: {state.last_error or 'none'}",
        ]
        if state.connector_display_name:
            lines.insert(4, f"Host label: {state.connector_display_name}")
        location = sensor_status.get("location")
        health = sensor_status.get("health", {})
        if location is None:
            lines.append("Location freshness: none")
        else:
            lines.append(
                f"Location freshness: {'stale' if location['stale'] else 'fresh'}"
                f" ({location['ageSeconds']}s old)"
            )
        lines.append(
            "Health freshness: "
            f"{health.get('freshCount', 0)} fresh / {health.get('staleCount', 0)} stale "
            f"across {health.get('count', 0)} metrics"
        )
        if state.voice_context_snapshot is not None:
            lines.append(f"Voice context updated: {state.voice_context_snapshot.updated_at}")
        return lines

    def validate_mcp(self) -> list[str]:
        state = self.state_store.load()
        self.apply_runtime_environment(state)
        settings = self.settings_for_state(state)
        metadata = self.metadata(display_name=state.connector_display_name, settings=settings)
        config_status = inspect_native_mcp_registration(server_name=state.mcp_server_name)
        connection_error = validate_native_mcp_server(
            hermes_command=metadata.hermes_command,
            server_name=state.mcp_server_name,
        )
        tool_error = validate_native_mcp_tools(server_name=state.mcp_server_name)
        readiness = native_mcp_readiness_message(hermes_command=metadata.hermes_command)
        return [
            f"Native MCP config: {'present' if config_status.registered else 'missing'}",
            f"MCP connection test: {connection_error or 'ok'}",
            f"MCP tool validation: {tool_error or 'ok'}",
            f"MCP readiness: {readiness}",
        ]

    def _configure_native_mcp(self, state: ConnectorState, *, hermes_command: str) -> ConnectorState:
        try:
            registration = register_native_mcp_server(state_dir=self.state_store.state_dir)
            state.mcp_server_name = registration.server_name
            state.mcp_configured = True
            state.mcp_command_path = registration.command_path
            state.mcp_registered_at = utcnow_iso()
            state.mcp_last_test_at = utcnow_iso()
            state.mcp_last_test_error = validate_native_mcp_server(
                hermes_command=hermes_command,
                server_name=registration.server_name,
            ) or validate_native_mcp_tools(server_name=registration.server_name)
        except Exception as error:  # noqa: BLE001
            state.mcp_last_test_at = utcnow_iso()
            state.mcp_last_test_error = str(error)
        return self.state_store.save(state)

    def _mark_mcp_unconfigured(self, state: ConnectorState) -> ConnectorState:
        state.mcp_configured = False
        state.mcp_last_test_at = utcnow_iso()
        state.mcp_last_test_error = None
        return self.state_store.save(state)

    @staticmethod
    def _mcp_validation_summary(*, state: ConnectorState, mcp_status) -> str:
        if state.mcp_last_test_error:
            return state.mcp_last_test_error
        if not state.mcp_configured:
            return "not configured (run `hermes-mobile configure-mcp` when ready)"
        if not mcp_status.registered:
            return "configured in connector state, but Hermes config is currently missing"
        return "ok"

    def capture_runtime_config(self, *, relay_url: str) -> ConnectorRuntimeConfig:
        settings = self.executor.settings
        resolved_command = self.executor.resolved_command_path()
        if resolved_command is None:
            raise RuntimeError(f"Hermes command not found or not runnable: {settings.hermes_command}")

        return ConnectorRuntimeConfig(
            python_executable=str(sys.executable),
            state_dir=str(self.state_store.state_dir),
            relay_url=relay_url.rstrip("/"),
            hermes_command=resolved_command,
            hermes_workdir=settings.hermes_workdir,
            hermes_provider=settings.hermes_provider,
            hermes_model=settings.hermes_model,
            hermes_toolsets=settings.hermes_toolsets,
            hermes_source=settings.hermes_source,
            hermes_history_limit=settings.hermes_history_limit,
            hermes_home=os.getenv("HERMES_HOME") or None,
            api_server_url=os.getenv("HERMES_API_SERVER_URL") or None,
            api_server_key=os.getenv("HERMES_API_SERVER_KEY") or None,
        )

    def settings_for_state(self, state: ConnectorState) -> ConnectorHermesSettings:
        if state.runtime_config is not None:
            return ConnectorHermesSettings.from_runtime_config(state.runtime_config)
        return self.executor.settings

    def executor_for_state(self, state: ConnectorState) -> HermesCLIExecutor:
        return HermesCLIExecutor(self.settings_for_state(state))

    def runtime_adapter_for_state(self, state: ConnectorState) -> HostRuntimeAdapter:
        return HermesRuntimeAdapter(self.executor_for_state(state))

    async def runtime_adapter_for_state_async(self, state: ConnectorState) -> HostRuntimeAdapter:
        """Prefer the API server adapter when available, fall back to CLI.

        Caches the health check result for ``_HEALTH_CACHE_TTL`` seconds to
        avoid hitting the API server on every single job.
        """
        import time

        now = time.monotonic()
        cached_at, cached_adapter = self._health_cache
        if cached_adapter is not None and (now - cached_at) < self._HEALTH_CACHE_TTL:
            return cached_adapter

        config = state.runtime_config
        api_url = (config.api_server_url if config else None) or os.getenv("HERMES_API_SERVER_URL")
        api_key = (config.api_server_key if config else None) or os.getenv("HERMES_API_SERVER_KEY")

        if api_url or api_key:
            executor = HermesAPIExecutor(
                api_server_url=api_url or "http://localhost:8642",
                api_server_key=api_key,
            )
            if await executor.health_check():
                adapter = HermesAPIRuntimeAdapter(executor)
                self._health_cache = (now, adapter)
                return adapter

        cli_adapter = HermesRuntimeAdapter(self.executor_for_state(state))
        self._health_cache = (now, cli_adapter)
        return cli_adapter

    def apply_runtime_environment(self, state: ConnectorState) -> None:
        if state.runtime_config is not None and state.runtime_config.hermes_home:
            os.environ["HERMES_HOME"] = state.runtime_config.hermes_home
