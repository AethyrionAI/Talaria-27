from __future__ import annotations
import asyncio
from dataclasses import dataclass
from datetime import datetime, timezone
import json
import os
import platform as platform_module
import socket
import sys

import httpx
from websockets.asyncio.client import connect as websocket_connect

from . import __version__
from .hermes_runner import ConnectorHermesSettings, HermesCLIExecutor, HermesConversationMessage
from .mcp_registration import (
    inspect_native_mcp_registration,
    native_mcp_readiness_message,
    register_native_mcp_server,
    validate_native_mcp_tools,
    validate_native_mcp_server,
)
from .sensor_store import HealthSample, LocationReading, SensorStore
from .service_management import build_service_manager
from .setup_code import decode_host_setup_code
from .state import ConnectorRuntimeConfig, ConnectorState, ConnectorStateStore

DEFAULT_RELAY_URL = "https://hermes-mobile-relay-dylan.fly.dev/v1"


def utcnow_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


@dataclass(frozen=True)
class ConnectorMetadata:
    platform: str
    hostname: str
    connector_version: str
    hermes_command: str
    hermes_version: str | None
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
        return ConnectorMetadata(
            platform=platform_module.system().lower(),
            hostname=socket.gethostname(),
            connector_version=__version__,
            hermes_command=effective_settings.hermes_command,
            hermes_version=version_executor.detect_version(),
            display_name=display_name,
        )

    def default_relay_url(self) -> str:
        return os.getenv("HERMES_MOBILE_RELAY_URL", DEFAULT_RELAY_URL).rstrip("/")

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
        response = httpx.post(
            f"{resolved_relay_url}/connector/setup",
            json={
                "connector": {
                    "platform": metadata.platform,
                    "hostname": metadata.hostname,
                    "connectorVersion": metadata.connector_version,
                    "hermesCommand": metadata.hermes_command,
                    "hermesVersion": metadata.hermes_version,
                },
            },
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
        self.apply_runtime_environment(state)
        settings = self.settings_for_state(state)
        metadata = self.metadata(display_name=state.connector_display_name, settings=settings)
        async with websocket_connect(
            state.web_socket_url,
            additional_headers={"Authorization": f"Bearer {state.connector_credential}"},
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
                if message_type == "ready":
                    continue
                sensor_ack = self._handle_sensor_message(message)
                if sensor_ack is not None:
                    await websocket.send(json.dumps(sensor_ack))
                    continue
                raise RuntimeError(f"Unsupported relay message: {message_type}")

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
        executor = self.executor_for_state(state)

        async def execute_job() -> dict:
            try:
                result = await asyncio.to_thread(
                    executor.send_message,
                    latest_user_message=job["latestUserMessage"],
                    history=[
                        HermesConversationMessage(role=item["role"], text=item["text"])
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
                    "retryable": False,
                    "error": str(error),
                }

        task = asyncio.create_task(execute_job())
        while True:
            done, _ = await asyncio.wait({task}, timeout=self.heartbeat_interval_seconds)
            if task in done:
                await websocket.send(json.dumps(task.result()))
                return
            await websocket.send(json.dumps({"type": "heartbeat"}))

    def status_lines(self) -> list[str]:
        state = self.state_store.load()
        self.apply_runtime_environment(state)
        settings = self.settings_for_state(state)
        metadata = self.metadata(display_name=state.connector_display_name, settings=settings)
        mcp_status = inspect_native_mcp_registration(server_name=state.mcp_server_name)
        sensor_status = self.sensor_store.get_sensor_freshness_summary()
        service_status = build_service_manager(self.state_store).status()
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
        state.mcp_last_test_at = utcnow_iso()
        state.mcp_last_test_error = None
        return self.state_store.save(state)

    @staticmethod
    def _mcp_validation_summary(*, state: ConnectorState, mcp_status) -> str:
        if state.mcp_last_test_error:
            return state.mcp_last_test_error
        if not mcp_status.registered:
            return "not configured (run `hermes-mobile configure-mcp` when ready)"
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
        )

    def settings_for_state(self, state: ConnectorState) -> ConnectorHermesSettings:
        if state.runtime_config is not None:
            return ConnectorHermesSettings.from_runtime_config(state.runtime_config)
        return self.executor.settings

    def executor_for_state(self, state: ConnectorState) -> HermesCLIExecutor:
        return HermesCLIExecutor(self.settings_for_state(state))

    def apply_runtime_environment(self, state: ConnectorState) -> None:
        if state.runtime_config is not None and state.runtime_config.hermes_home:
            os.environ["HERMES_HOME"] = state.runtime_config.hermes_home
