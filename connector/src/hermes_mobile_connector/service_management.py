from __future__ import annotations

from collections import deque
from dataclasses import dataclass
import os
from pathlib import Path
import plistlib
import shlex
import subprocess
import sys

from .state import ConnectorRuntimeConfig, ConnectorStateStore


MACOS_LABEL = "ai.hermes.mobile.connector"
WINDOWS_TASK_NAME = "HermesMobileConnector"


@dataclass(frozen=True)
class ServiceArtifacts:
    state_dir: Path
    bin_dir: Path
    logs_dir: Path
    runner_path: Path
    launcher_path: Path
    stdout_log: Path
    stderr_log: Path
    plist_path: Path | None = None


@dataclass(frozen=True)
class ServiceStatus:
    backend: str
    supported: bool
    installed: bool
    running: bool
    detail: str
    stdout_log: Path
    stderr_log: Path

    @property
    def summary(self) -> str:
        if not self.supported:
            return f"unsupported ({self.detail})"
        if not self.installed:
            return f"not installed ({self.backend})"
        state = "running" if self.running else "stopped"
        return f"{state} ({self.backend})"


def build_service_manager(
    state_store: ConnectorStateStore,
    *,
    command_runner=None,
    environment: dict[str, str] | None = None,
) -> BaseServiceManager:
    env = environment or dict(os.environ)
    runner = command_runner or _run_command
    if sys.platform == "darwin":
        return MacOSLaunchAgentManager(state_store, command_runner=runner, environment=env)
    if is_wsl(environment=env):
        return WindowsWSLServiceManager(state_store, command_runner=runner, environment=env)
    return UnsupportedServiceManager(state_store, environment=env)


def is_wsl(*, environment: dict[str, str] | None = None) -> bool:
    env = environment or os.environ
    if env.get("WSL_DISTRO_NAME"):
        return True

    proc_version = Path("/proc/version")
    if proc_version.exists():
        try:
            return "microsoft" in proc_version.read_text(encoding="utf-8").lower()
        except OSError:
            return False
    return False


def _run_command(command: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        command,
        capture_output=True,
        text=True,
        check=False,
    )


class BaseServiceManager:
    def __init__(
        self,
        state_store: ConnectorStateStore,
        *,
        command_runner,
        environment: dict[str, str] | None = None,
    ) -> None:
        self.state_store = state_store
        self.command_runner = command_runner
        self.environment = environment or dict(os.environ)

    def status(self) -> ServiceStatus:
        raise NotImplementedError

    def install(self, *, force: bool = False) -> str:
        raise NotImplementedError

    def start(self) -> str:
        raise NotImplementedError

    def stop(self) -> str:
        raise NotImplementedError

    def restart(self) -> str:
        raise NotImplementedError

    def uninstall(self) -> str:
        raise NotImplementedError

    def logs(self, *, lines: int = 100) -> str:
        artifacts = self.service_artifacts()
        sections: list[str] = []
        sections.append(f"stdout: {artifacts.stdout_log}")
        sections.append(_tail_file(artifacts.stdout_log, lines=lines))
        sections.append(f"stderr: {artifacts.stderr_log}")
        sections.append(_tail_file(artifacts.stderr_log, lines=lines))
        return "\n\n".join(section for section in sections if section)

    def ensure_artifacts(
        self,
        runtime_config: ConnectorRuntimeConfig,
        *,
        force: bool = False,
    ) -> ServiceArtifacts:
        artifacts = self.service_artifacts()
        artifacts.bin_dir.mkdir(parents=True, exist_ok=True)
        artifacts.logs_dir.mkdir(parents=True, exist_ok=True)
        try:
            os.chmod(artifacts.bin_dir, 0o700)
            os.chmod(artifacts.logs_dir, 0o700)
        except PermissionError:
            pass

        if force or not artifacts.runner_path.exists():
            artifacts.runner_path.write_text(
                self.render_runner(runtime_config=runtime_config, runner_path=artifacts.runner_path),
                encoding="utf-8",
            )
            try:
                os.chmod(artifacts.runner_path, 0o700)
            except PermissionError:
                pass

        if force or not artifacts.launcher_path.exists():
            artifacts.launcher_path.write_text(
                self.render_launcher(runtime_config=runtime_config, artifacts=artifacts),
                encoding="utf-8",
            )
            try:
                os.chmod(artifacts.launcher_path, 0o700)
            except PermissionError:
                pass

        return artifacts

    def render_runner(self, *, runtime_config: ConnectorRuntimeConfig, runner_path: Path) -> str:
        return (
            f"#!{runtime_config.python_executable}\n"
            "from hermes_mobile_connector.service_runner import run_from_state_dir\n"
            "\n"
            "if __name__ == \"__main__\":\n"
            f"    raise SystemExit(run_from_state_dir({runtime_config.state_dir!r}))\n"
        )

    def render_launcher(self, *, runtime_config: ConnectorRuntimeConfig, artifacts: ServiceArtifacts) -> str:
        python_path = shlex.quote(runtime_config.python_executable)
        runner_path = shlex.quote(str(artifacts.runner_path))
        stdout_path = shlex.quote(str(artifacts.stdout_log))
        stderr_path = shlex.quote(str(artifacts.stderr_log))
        return (
            "#!/bin/sh\n"
            f"exec {python_path} {runner_path} >>{stdout_path} 2>>{stderr_path}\n"
        )

    def service_artifacts(self) -> ServiceArtifacts:
        state_dir = self.state_store.state_dir
        logs_dir = state_dir / "logs"
        bin_dir = state_dir / "bin"
        return ServiceArtifacts(
            state_dir=state_dir,
            bin_dir=bin_dir,
            logs_dir=logs_dir,
            runner_path=bin_dir / "hermes-mobile-service.py",
            launcher_path=bin_dir / "hermes-mobile-service.sh",
            stdout_log=logs_dir / "connector.stdout.log",
            stderr_log=logs_dir / "connector.stderr.log",
            plist_path=None,
        )

    def _require_runtime_config(self) -> ConnectorRuntimeConfig:
        state = self.state_store.load()
        if state.runtime_config is None:
            raise RuntimeError(
                "Connector runtime config is missing. Re-run `hermes-mobile setup` "
                "or `hermes-mobile service install --force` from the configured environment."
            )
        return state.runtime_config


class UnsupportedServiceManager(BaseServiceManager):
    def __init__(self, state_store: ConnectorStateStore, *, environment: dict[str, str] | None = None) -> None:
        super().__init__(state_store, command_runner=_run_command, environment=environment)

    def status(self) -> ServiceStatus:
        artifacts = self.service_artifacts()
        return ServiceStatus(
            backend="unsupported",
            supported=False,
            installed=False,
            running=False,
            detail="macOS LaunchAgent and Windows WSL2 are supported in this pass",
            stdout_log=artifacts.stdout_log,
            stderr_log=artifacts.stderr_log,
        )

    def install(self, *, force: bool = False) -> str:
        raise RuntimeError("Background service management is only available on macOS and Windows WSL2 in this pass.")

    def start(self) -> str:
        raise RuntimeError("Background service management is unavailable on this platform.")

    def stop(self) -> str:
        raise RuntimeError("Background service management is unavailable on this platform.")

    def restart(self) -> str:
        raise RuntimeError("Background service management is unavailable on this platform.")

    def uninstall(self) -> str:
        raise RuntimeError("Background service management is unavailable on this platform.")


class MacOSLaunchAgentManager(BaseServiceManager):
    def service_artifacts(self) -> ServiceArtifacts:
        artifacts = super().service_artifacts()
        plist_path = Path.home() / "Library" / "LaunchAgents" / f"{MACOS_LABEL}.plist"
        return ServiceArtifacts(
            state_dir=artifacts.state_dir,
            bin_dir=artifacts.bin_dir,
            logs_dir=artifacts.logs_dir,
            runner_path=artifacts.runner_path,
            launcher_path=artifacts.launcher_path,
            stdout_log=artifacts.stdout_log,
            stderr_log=artifacts.stderr_log,
            plist_path=plist_path,
        )

    def status(self) -> ServiceStatus:
        artifacts = self.service_artifacts()
        installed = artifacts.plist_path is not None and artifacts.plist_path.exists()
        loaded, running, detail = self._query_launch_agent(installed=installed)
        return ServiceStatus(
            backend="macOS launchd",
            supported=True,
            installed=installed,
            running=loaded and running,
            detail=detail,
            stdout_log=artifacts.stdout_log,
            stderr_log=artifacts.stderr_log,
        )

    def install(self, *, force: bool = False) -> str:
        runtime_config = self._require_runtime_config()
        artifacts = self.ensure_artifacts(runtime_config, force=force)
        assert artifacts.plist_path is not None
        if artifacts.plist_path.exists() and not force:
            raise RuntimeError("LaunchAgent already exists. Use `hermes-mobile service install --force` to rewrite it.")

        artifacts.plist_path.parent.mkdir(parents=True, exist_ok=True)
        plist_payload = {
            "Label": MACOS_LABEL,
            "ProgramArguments": [str(artifacts.runner_path)],
            "RunAtLoad": True,
            "KeepAlive": True,
            "StandardOutPath": str(artifacts.stdout_log),
            "StandardErrorPath": str(artifacts.stderr_log),
            "ProcessType": "Background",
        }
        with artifacts.plist_path.open("wb") as handle:
            plistlib.dump(plist_payload, handle)
        return f"Installed LaunchAgent plist at {artifacts.plist_path}"

    def start(self) -> str:
        artifacts = self.service_artifacts()
        assert artifacts.plist_path is not None
        if not artifacts.plist_path.exists():
            raise RuntimeError("LaunchAgent is not installed. Run `hermes-mobile service install` first.")

        loaded, _, _ = self._query_launch_agent(installed=True)
        target = self._launchctl_target()
        if not loaded:
            self._run_checked(["launchctl", "bootstrap", target, str(artifacts.plist_path)])
        self._run_checked(["launchctl", "kickstart", "-k", f"{target}/{MACOS_LABEL}"])
        return "Started macOS LaunchAgent."

    def stop(self) -> str:
        artifacts = self.service_artifacts()
        assert artifacts.plist_path is not None
        if not artifacts.plist_path.exists():
            return "LaunchAgent is not installed."

        loaded, _, _ = self._query_launch_agent(installed=True)
        if loaded:
            self._run_checked(["launchctl", "bootout", self._launchctl_target(), str(artifacts.plist_path)])
            return "Stopped macOS LaunchAgent."
        return "LaunchAgent is already stopped."

    def restart(self) -> str:
        self.stop()
        self.start()
        return "Restarted macOS LaunchAgent."

    def uninstall(self) -> str:
        artifacts = self.service_artifacts()
        assert artifacts.plist_path is not None
        if artifacts.plist_path.exists():
            loaded, _, _ = self._query_launch_agent(installed=True)
            if loaded:
                self._run_checked(["launchctl", "bootout", self._launchctl_target(), str(artifacts.plist_path)])
            artifacts.plist_path.unlink()
            return "Removed macOS LaunchAgent."
        return "LaunchAgent is not installed."

    def _launchctl_target(self) -> str:
        return f"gui/{os.getuid()}"

    def _query_launch_agent(self, *, installed: bool) -> tuple[bool, bool, str]:
        if not installed:
            return False, False, "not installed"

        completed = self.command_runner(["launchctl", "print", f"{self._launchctl_target()}/{MACOS_LABEL}"])
        if completed.returncode != 0:
            return False, False, "installed but not loaded"

        output = (completed.stdout or completed.stderr or "").lower()
        running = "state = running" in output or "pid =" in output
        return True, running, "running" if running else "loaded but idle"

    def _run_checked(self, command: list[str]) -> None:
        completed = self.command_runner(command)
        if completed.returncode != 0:
            output = (completed.stderr or completed.stdout or "").strip()
            raise RuntimeError(output or f"Command failed: {' '.join(command)}")


class WindowsWSLServiceManager(BaseServiceManager):
    def status(self) -> ServiceStatus:
        artifacts = self.service_artifacts()
        completed = self.command_runner(["schtasks.exe", "/Query", "/TN", WINDOWS_TASK_NAME, "/FO", "LIST", "/V"])
        installed = completed.returncode == 0
        output = (completed.stdout or completed.stderr or "").lower()
        running = installed and "status:" in output and "running" in output
        detail = "running" if running else ("registered" if installed else "not installed")
        return ServiceStatus(
            backend="Windows Scheduled Task (WSL2)",
            supported=True,
            installed=installed,
            running=running,
            detail=detail,
            stdout_log=artifacts.stdout_log,
            stderr_log=artifacts.stderr_log,
        )

    def install(self, *, force: bool = False) -> str:
        runtime_config = self._require_runtime_config()
        if not force and self.status().installed:
            raise RuntimeError("Scheduled Task already exists. Use `hermes-mobile service install --force` to rewrite it.")

        artifacts = self.ensure_artifacts(runtime_config, force=force)
        command = [
            "schtasks.exe",
            "/Create",
            "/TN",
            WINDOWS_TASK_NAME,
            "/SC",
            "ONLOGON",
            "/TR",
            self._task_action(artifacts),
            "/F",
        ]
        self._run_checked(command)
        return f"Installed Windows Scheduled Task `{WINDOWS_TASK_NAME}`."

    def start(self) -> str:
        self._run_checked(["schtasks.exe", "/Run", "/TN", WINDOWS_TASK_NAME])
        return "Started Windows Scheduled Task."

    def stop(self) -> str:
        self._run_checked(["schtasks.exe", "/End", "/TN", WINDOWS_TASK_NAME])
        return "Stopped Windows Scheduled Task."

    def restart(self) -> str:
        try:
            self.stop()
        except RuntimeError:
            pass
        self.start()
        return "Restarted Windows Scheduled Task."

    def uninstall(self) -> str:
        self._run_checked(["schtasks.exe", "/Delete", "/TN", WINDOWS_TASK_NAME, "/F"])
        return f"Removed Windows Scheduled Task `{WINDOWS_TASK_NAME}`."

    def _task_action(self, artifacts: ServiceArtifacts) -> str:
        distro = self._require_environment_value("WSL_DISTRO_NAME")
        linux_user = self.environment.get("USER") or self.environment.get("LOGNAME")
        if not linux_user:
            raise RuntimeError("Could not determine the current WSL Linux user.")
        return f"wsl.exe -d {distro} -u {linux_user} -- {artifacts.launcher_path}"

    def _require_environment_value(self, key: str) -> str:
        value = self.environment.get(key)
        if not value:
            raise RuntimeError(f"Missing required WSL environment value: {key}")
        return value

    def _run_checked(self, command: list[str]) -> None:
        completed = self.command_runner(command)
        if completed.returncode != 0:
            output = (completed.stderr or completed.stdout or "").strip()
            raise RuntimeError(output or f"Command failed: {' '.join(command)}")


def _tail_file(path: Path, *, lines: int) -> str:
    if not path.exists():
        return "(no log file yet)"

    collected: deque[str] = deque(maxlen=max(lines, 1))
    with path.open("r", encoding="utf-8", errors="replace") as handle:
        for line in handle:
            collected.append(line.rstrip("\n"))

    if not collected:
        return "(empty)"
    return "\n".join(collected)
