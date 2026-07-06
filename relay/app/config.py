from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path

from dotenv import load_dotenv


load_dotenv()


# Directory above this file — the relay project root (the directory that
# contains the ``app`` package, the ``.env``, and ``hermes_mobile.db``).
# Used to resolve relative SQLite database URLs so the DB doesn't silently
# move when the process working directory changes (GH #59).
_RELAY_DIR = Path(__file__).resolve().parent.parent


def _resolve_sqlite_path(database_url: str) -> str:
    """Resolve a relative ``sqlite:///./...`` URL to an absolute path.

    SQLite URLs use **three** slashes for a relative path
    (``sqlite:///./relay.db``) and **four** for an absolute one
    (``sqlite:////var/data/relay.db``).  When the path is relative it
    resolves against ``os.getcwd()``, which means the DB silently moves
    if the process is launched from a different directory — orphaning
    all pairings and creating a fresh empty DB (GH #59).

    This helper anchors any relative SQLite path to the relay package
    directory so the DB location is stable regardless of how the relay
    is launched.
    """
    prefix = "sqlite:///"
    if not database_url.startswith(prefix):
        return database_url
    # Already absolute (4 slashes) or in-memory — leave as-is.
    rest = database_url[len(prefix):]
    if not rest or rest == ":memory:" or rest.startswith("/"):
        return database_url
    abs_path = (_RELAY_DIR / rest).resolve()
    return f"sqlite:///{abs_path}"


def normalize_database_url(database_url: str) -> str:
    if database_url.startswith("postgresql://"):
        return database_url.replace("postgresql://", "postgresql+psycopg://", 1)
    if database_url.startswith("postgres://"):
        return database_url.replace("postgres://", "postgresql+psycopg://", 1)
    return _resolve_sqlite_path(database_url)


@dataclass(frozen=True)
class Settings:
    service_name: str = "hermes-mobile-relay"
    version: str = "0.1.0"
    environment: str = "development"
    public_base_url: str = "http://127.0.0.1:8000/v1"
    database_url: str = "sqlite:///./relay.db"
    internal_api_key: str = "replace-me"
    access_token_ttl_seconds: int = 3600
    refresh_token_ttl_seconds: int = 60 * 60 * 24 * 30
    # How long a rotated-away refresh token stays honored after a refresh,
    # so a client that lost the rotation response can retry (GH #15).
    refresh_token_grace_seconds: int = 60
    pairing_code_ttl_seconds: int = 900
    phone_pairing_code_ttl_seconds: int = 600
    phone_pairing_max_attempts_per_code: int = 5
    phone_pairing_max_attempts_per_ip: int = 5
    phone_pairing_rate_limit_window_seconds: int = 300
    host_enrollment_code_ttl_seconds: int = 900
    default_user_display_name: str = "Hermes User"
    hermes_adapter: str = "mock"
    hermes_command: str = "hermes"
    hermes_workdir: str | None = None
    hermes_provider: str | None = None
    hermes_model: str | None = None
    hermes_toolsets: str | None = None
    hermes_source: str = "tool"
    hermes_history_limit: int = 20
    connector_sync_wait_seconds: int = 0
    connector_job_lease_seconds: int = 180
    connector_heartbeat_timeout_seconds: int = 30
    connector_idle_poll_interval_seconds: float = 1.0
    connector_sensor_ack_timeout_seconds: float = 3.0
    connector_rpc_timeout_seconds: float = 30.0
    talk_delegate_timeout_seconds: float = 90.0
    sse_keepalive_seconds: int = 30
    connector_setup_secret: str | None = None
    apns_key_path: str | None = None
    apns_key_contents: str | None = None
    apns_key_id: str | None = None
    apns_team_id: str | None = None
    apns_bundle_id: str = "io.hermesmobile.HermesMobile"
    apns_environment: str = "development"
    # Push watch (#38): the gateway the relay polls to detect run completion
    # for detached runs. Chat never transits the relay, so this is its only
    # window into the Sessions API. gateway_api_key is the Hermes
    # API_SERVER_KEY; polling is disabled when it's unset.
    gateway_base_url: str = "http://127.0.0.1:8642"
    gateway_api_key: str | None = None
    push_watch_poll_seconds: float = 3.0
    push_watch_slow_poll_seconds: float = 10.0
    push_watch_fast_window_seconds: float = 120.0
    push_watch_ttl_seconds: float = 1800.0
    app_presence_stale_seconds: int = 120
    # #21 Tier 2: directory the relay is allowed to serve agent-written files from.
    # Files are returned only if they resolve to a real file *inside* this dir.
    # On OJAMD this is the dedicated mobile-download dir (e.g. O:\Hermes\MobileDL).
    agent_files_dir: str | None = None

    @classmethod
    def from_env(cls) -> "Settings":
        return cls(
            environment=os.getenv("RELAY_ENVIRONMENT", "development"),
            public_base_url=os.getenv("PUBLIC_BASE_URL", "http://127.0.0.1:8000/v1"),
            database_url=normalize_database_url(os.getenv("DATABASE_URL", "sqlite:///./relay.db")),
            internal_api_key=os.getenv("INTERNAL_API_KEY", "replace-me"),
            access_token_ttl_seconds=int(os.getenv("ACCESS_TOKEN_TTL_SECONDS", "3600")),
            refresh_token_ttl_seconds=int(os.getenv("REFRESH_TOKEN_TTL_SECONDS", str(60 * 60 * 24 * 30))),
            refresh_token_grace_seconds=int(os.getenv("REFRESH_TOKEN_GRACE_SECONDS", "60")),
            pairing_code_ttl_seconds=int(os.getenv("PAIRING_CODE_TTL_SECONDS", "900")),
            phone_pairing_code_ttl_seconds=int(os.getenv("PHONE_PAIRING_CODE_TTL_SECONDS", "600")),
            phone_pairing_max_attempts_per_code=int(os.getenv("PHONE_PAIRING_MAX_ATTEMPTS_PER_CODE", "5")),
            phone_pairing_max_attempts_per_ip=int(os.getenv("PHONE_PAIRING_MAX_ATTEMPTS_PER_IP", "5")),
            phone_pairing_rate_limit_window_seconds=int(os.getenv("PHONE_PAIRING_RATE_LIMIT_WINDOW_SECONDS", "300")),
            host_enrollment_code_ttl_seconds=int(os.getenv("HOST_ENROLLMENT_CODE_TTL_SECONDS", "900")),
            default_user_display_name=os.getenv("DEFAULT_USER_DISPLAY_NAME", "Hermes User"),
            hermes_adapter=os.getenv("HERMES_ADAPTER", "mock"),
            hermes_command=os.getenv("HERMES_COMMAND", "hermes"),
            hermes_workdir=os.getenv("HERMES_WORKDIR") or None,
            hermes_provider=os.getenv("HERMES_PROVIDER") or None,
            hermes_model=os.getenv("HERMES_MODEL") or None,
            hermes_toolsets=os.getenv("HERMES_TOOLSETS") or None,
            hermes_source=os.getenv("HERMES_SOURCE", "tool"),
            hermes_history_limit=int(os.getenv("HERMES_HISTORY_LIMIT", "20")),
            connector_sync_wait_seconds=int(os.getenv("CONNECTOR_SYNC_WAIT_SECONDS", "0")),
            connector_job_lease_seconds=int(os.getenv("CONNECTOR_JOB_LEASE_SECONDS", "180")),
            connector_heartbeat_timeout_seconds=int(os.getenv("CONNECTOR_HEARTBEAT_TIMEOUT_SECONDS", "30")),
            connector_idle_poll_interval_seconds=float(os.getenv("CONNECTOR_IDLE_POLL_INTERVAL_SECONDS", "1.0")),
            connector_sensor_ack_timeout_seconds=float(os.getenv("CONNECTOR_SENSOR_ACK_TIMEOUT_SECONDS", "3.0")),
            connector_rpc_timeout_seconds=float(os.getenv("CONNECTOR_RPC_TIMEOUT_SECONDS", "30.0")),
            talk_delegate_timeout_seconds=float(os.getenv("TALK_DELEGATE_TIMEOUT_SECONDS", "90.0")),
            connector_setup_secret=os.getenv("CONNECTOR_SETUP_SECRET") or None,
            apns_key_path=os.getenv("APNS_KEY_PATH") or None,
            apns_key_contents=os.getenv("APNS_KEY_CONTENTS") or None,
            apns_key_id=os.getenv("APNS_KEY_ID") or None,
            apns_team_id=os.getenv("APNS_TEAM_ID") or None,
            apns_bundle_id=os.getenv("APNS_BUNDLE_ID", "io.hermesmobile.HermesMobile"),
            apns_environment=os.getenv("APNS_ENVIRONMENT", "development"),
            gateway_base_url=os.getenv("GATEWAY_BASE_URL", "http://127.0.0.1:8642"),
            gateway_api_key=os.getenv("GATEWAY_API_KEY") or None,
            push_watch_poll_seconds=float(os.getenv("PUSH_WATCH_POLL_SECONDS", "3.0")),
            push_watch_slow_poll_seconds=float(os.getenv("PUSH_WATCH_SLOW_POLL_SECONDS", "10.0")),
            push_watch_fast_window_seconds=float(os.getenv("PUSH_WATCH_FAST_WINDOW_SECONDS", "120.0")),
            push_watch_ttl_seconds=float(os.getenv("PUSH_WATCH_TTL_SECONDS", "1800.0")),
            app_presence_stale_seconds=int(os.getenv("APP_PRESENCE_STALE_SECONDS", "120")),
            agent_files_dir=os.getenv("AGENT_FILES_DIR") or None,
        )
