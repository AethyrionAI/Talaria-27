from __future__ import annotations

from pathlib import Path
import subprocess
import sys

import pytest

from hermes_mobile_connector.client import HermesMobileConnector
from hermes_mobile_connector.hermes_runner import ConnectorHermesSettings, HermesCLIExecutor
from hermes_mobile_connector.service_management import (
    MacOSLaunchAgentManager,
    UnsupportedServiceManager,
    WINDOWS_TASK_NAME,
    WindowsWSLServiceManager,
    build_service_manager,
)
from hermes_mobile_connector.state import ConnectorRuntimeConfig, ConnectorState, ConnectorStateStore


def make_executor(command: str = "env-hermes") -> HermesCLIExecutor:
    return HermesCLIExecutor(
        ConnectorHermesSettings(
            hermes_command=command,
            hermes_workdir="/tmp/env-workdir",
            hermes_provider="env-provider",
            hermes_model="env-model",
            hermes_toolsets="env-tools",
            hermes_source="tool",
            hermes_history_limit=20,
        )
    )


def make_runtime_config(tmp_path: Path) -> ConnectorRuntimeConfig:
    return ConnectorRuntimeConfig(
        python_executable="/tmp/venv/bin/python",
        state_dir=str(tmp_path / "connector-state"),
        relay_url="https://relay.example.com/v1",
        hermes_command="/opt/hermes/bin/hermes",
        hermes_workdir="/srv/hermes-project",
        hermes_provider="openai-codex",
        hermes_model="gpt-5.4",
        hermes_toolsets="native-mcp",
        hermes_source="tool",
        hermes_history_limit=20,
        hermes_home="/srv/.hermes",
    )


def make_state_store(tmp_path: Path, runtime_config: ConnectorRuntimeConfig | None = None) -> ConnectorStateStore:
    state_dir = tmp_path / "connector-state"
    store = ConnectorStateStore(state_dir=state_dir)
    store.save(
        ConnectorState(
            relay_url="https://relay.example.com/v1",
            web_socket_url="wss://relay.example.com/v1/hosts/ws",
            user_id="user-123",
            host_id="host-123",
            connector_credential="secret-token",
            runtime_config=runtime_config,
        )
    )
    return store


def test_state_store_round_trips_runtime_config(tmp_path):
    runtime_config = make_runtime_config(tmp_path)
    store = make_state_store(tmp_path, runtime_config)

    loaded = store.load()

    assert loaded.runtime_config is not None
    assert loaded.runtime_config.hermes_command == "/opt/hermes/bin/hermes"
    assert loaded.runtime_config.hermes_home == "/srv/.hermes"


def test_connector_prefers_persisted_runtime_config_over_env_settings(tmp_path):
    runtime_config = make_runtime_config(tmp_path)
    store = make_state_store(tmp_path, runtime_config)
    connector = HermesMobileConnector(state_store=store, executor=make_executor())

    settings = connector.settings_for_state(store.load())

    assert settings.hermes_command == "/opt/hermes/bin/hermes"
    assert settings.hermes_workdir == "/srv/hermes-project"
    assert settings.hermes_provider == "openai-codex"


def test_macos_install_writes_launchagent_plist_and_runner(monkeypatch, tmp_path):
    home_dir = tmp_path / "home"
    home_dir.mkdir(parents=True)
    monkeypatch.setattr(Path, "home", lambda: home_dir)

    runtime_config = make_runtime_config(tmp_path)
    store = make_state_store(tmp_path, runtime_config)
    manager = MacOSLaunchAgentManager(store, command_runner=lambda command: subprocess.CompletedProcess(command, 0, "", ""), environment={})

    message = manager.install(force=False)
    artifacts = manager.service_artifacts()

    assert "LaunchAgent plist" in message
    assert artifacts.runner_path.exists()
    assert artifacts.runner_path.is_absolute()
    assert artifacts.launcher_path.exists()
    assert artifacts.plist_path is not None and artifacts.plist_path.exists()

    plist_data = artifacts.plist_path.read_bytes()
    payload = __import__("plistlib").loads(plist_data)
    assert payload["Label"] == "ai.hermes.mobile.connector"
    assert payload["ProgramArguments"] == [str(artifacts.runner_path)]
    assert payload["KeepAlive"] is True
    assert payload["RunAtLoad"] is True


@pytest.mark.skipif(sys.platform != "darwin", reason="macOS LaunchAgent service test — requires launchctl and os.getuid()")
def test_macos_service_start_stop_restart_and_uninstall_issue_expected_launchctl_calls(monkeypatch, tmp_path):
    home_dir = tmp_path / "home"
    home_dir.mkdir(parents=True)
    monkeypatch.setattr(Path, "home", lambda: home_dir)

    runtime_config = make_runtime_config(tmp_path)
    store = make_state_store(tmp_path, runtime_config)
    commands: list[list[str]] = []
    responses = [
        subprocess.CompletedProcess(["launchctl", "print"], 1, "", "not loaded"),
        subprocess.CompletedProcess(["launchctl", "bootstrap"], 0, "", ""),
        subprocess.CompletedProcess(["launchctl", "kickstart"], 0, "", ""),
        subprocess.CompletedProcess(["launchctl", "print"], 0, "state = running\npid = 10\n", ""),
        subprocess.CompletedProcess(["launchctl", "bootout"], 0, "", ""),
        subprocess.CompletedProcess(["launchctl", "print"], 1, "", "not loaded"),
        subprocess.CompletedProcess(["launchctl", "print"], 1, "", "not loaded"),
        subprocess.CompletedProcess(["launchctl", "bootstrap"], 0, "", ""),
        subprocess.CompletedProcess(["launchctl", "kickstart"], 0, "", ""),
        subprocess.CompletedProcess(["launchctl", "print"], 0, "state = running\npid = 10\n", ""),
        subprocess.CompletedProcess(["launchctl", "bootout"], 0, "", ""),
    ]

    def runner(command):
        commands.append(command)
        return responses.pop(0)

    manager = MacOSLaunchAgentManager(store, command_runner=runner, environment={})
    manager.install(force=False)

    assert manager.start() == "Started macOS LaunchAgent."
    assert manager.stop() == "Stopped macOS LaunchAgent."
    assert manager.restart() == "Restarted macOS LaunchAgent."
    assert manager.uninstall() == "Removed macOS LaunchAgent."
    assert store.state_path.exists()

    assert any(command[:2] == ["launchctl", "bootstrap"] for command in commands)
    assert any(command[:2] == ["launchctl", "kickstart"] for command in commands)
    assert any(command[:2] == ["launchctl", "bootout"] for command in commands)


def test_windows_wsl_install_and_lifecycle_commands_use_scheduled_task(tmp_path):
    runtime_config = make_runtime_config(tmp_path)
    store = make_state_store(tmp_path, runtime_config)
    commands: list[list[str]] = []

    def runner(command):
        commands.append(command)
        return subprocess.CompletedProcess(command, 0, "Status: Running\n", "")

    manager = WindowsWSLServiceManager(
        store,
        command_runner=runner,
        environment={"WSL_DISTRO_NAME": "Ubuntu-24.04", "USER": "testuser"},
    )

    assert f"Installed Windows Scheduled Task `{WINDOWS_TASK_NAME}`." == manager.install(force=True)
    assert manager.start() == "Started Windows Scheduled Task."
    assert manager.stop() == "Stopped Windows Scheduled Task."
    assert manager.restart() == "Restarted Windows Scheduled Task."
    assert manager.uninstall() == f"Removed Windows Scheduled Task `{WINDOWS_TASK_NAME}`."

    create_command = commands[0]
    assert create_command[:4] == ["schtasks.exe", "/Create", "/TN", WINDOWS_TASK_NAME]
    assert "/TR" in create_command
    action = create_command[create_command.index("/TR") + 1]
    assert "wsl.exe -d Ubuntu-24.04 -u testuser --" in action

    assert ["schtasks.exe", "/Run", "/TN", WINDOWS_TASK_NAME] in commands
    assert ["schtasks.exe", "/End", "/TN", WINDOWS_TASK_NAME] in commands
    assert ["schtasks.exe", "/Delete", "/TN", WINDOWS_TASK_NAME, "/F"] in commands


def test_windows_wsl_status_parses_query_output(tmp_path):
    runtime_config = make_runtime_config(tmp_path)
    store = make_state_store(tmp_path, runtime_config)

    manager = WindowsWSLServiceManager(
        store,
        command_runner=lambda command: subprocess.CompletedProcess(command, 0, "Status: Running\n", ""),
        environment={"WSL_DISTRO_NAME": "Ubuntu", "USER": "testuser"},
    )

    status = manager.status()

    assert status.installed is True
    assert status.running is True
    assert status.backend == "Windows Scheduled Task (WSL2)"


def test_unsupported_service_manager_is_returned_for_non_wsl_linux(monkeypatch, tmp_path):
    runtime_config = make_runtime_config(tmp_path)
    store = make_state_store(tmp_path, runtime_config)
    monkeypatch.setattr(sys, "platform", "linux")

    manager = build_service_manager(store, environment={})

    assert isinstance(manager, UnsupportedServiceManager)
    with pytest.raises(RuntimeError):
        manager.install()


def test_service_logs_reads_connector_owned_log_files(tmp_path):
    runtime_config = make_runtime_config(tmp_path)
    store = make_state_store(tmp_path, runtime_config)
    manager = MacOSLaunchAgentManager(
        store,
        command_runner=lambda command: subprocess.CompletedProcess(command, 0, "", ""),
        environment={},
    )
    artifacts = manager.ensure_artifacts(runtime_config, force=True)
    artifacts.stdout_log.write_text("line-1\nline-2\n", encoding="utf-8")
    artifacts.stderr_log.write_text("warn-1\n", encoding="utf-8")

    output = manager.logs(lines=10)

    assert "stdout:" in output
    assert "line-2" in output
    assert "stderr:" in output
    assert "warn-1" in output
