from __future__ import annotations

import re
import shutil
import subprocess
from dataclasses import dataclass
import os
from pathlib import Path

from .state import ConnectorRuntimeConfig


@dataclass(frozen=True)
class HermesConversationMessage:
    role: str
    text: str


@dataclass(frozen=True)
class HermesChatResult:
    text: str
    session_id: str | None = None


@dataclass(frozen=True)
class ConnectorHermesSettings:
    hermes_command: str
    hermes_workdir: str | None
    hermes_provider: str | None
    hermes_model: str | None
    hermes_toolsets: str | None
    hermes_source: str
    hermes_history_limit: int

    @classmethod
    def from_env(cls) -> "ConnectorHermesSettings":
        return cls(
            hermes_command=os.getenv("HERMES_COMMAND", "hermes"),
            hermes_workdir=os.getenv("HERMES_WORKDIR") or None,
            hermes_provider=os.getenv("HERMES_PROVIDER") or None,
            hermes_model=os.getenv("HERMES_MODEL") or None,
            hermes_toolsets=os.getenv("HERMES_TOOLSETS") or None,
            hermes_source=os.getenv("HERMES_SOURCE", "tool"),
            hermes_history_limit=int(os.getenv("HERMES_HISTORY_LIMIT", "20")),
        )

    @classmethod
    def from_runtime_config(cls, config: ConnectorRuntimeConfig) -> "ConnectorHermesSettings":
        return cls(
            hermes_command=config.hermes_command,
            hermes_workdir=config.hermes_workdir,
            hermes_provider=config.hermes_provider,
            hermes_model=config.hermes_model,
            hermes_toolsets=config.hermes_toolsets,
            hermes_source=config.hermes_source,
            hermes_history_limit=config.hermes_history_limit,
        )


@dataclass(frozen=True)
class CLIHermesResponse:
    text: str
    session_id: str | None
    missing_session: bool = False


class HermesCLIExecutor:
    SESSION_ID_PATTERN = re.compile(r"(?m)^session_id:\s*(?P<session_id>\S+)\s*$")

    def __init__(self, settings: ConnectorHermesSettings | None = None) -> None:
        self.settings = settings or ConnectorHermesSettings.from_env()

    def resolved_command_path(self) -> str | None:
        match = shutil.which(self.settings.hermes_command)
        if match:
            return str(Path(match).resolve())

        candidate = Path(self.settings.hermes_command).expanduser()
        if candidate.exists():
            return str(candidate.resolve())

        return None

    def detect_version(self) -> str | None:
        command_path = self.resolved_command_path()
        if command_path is None:
            return None

        completed = subprocess.run(
            [command_path, "--version"],
            cwd=self.settings.hermes_workdir or None,
            capture_output=True,
            text=True,
            check=False,
        )
        if completed.returncode != 0:
            return None

        output = completed.stdout.strip() or completed.stderr.strip()
        return output or None

    def send_message(
        self,
        *,
        latest_user_message: str,
        history: list[HermesConversationMessage],
        session_id: str | None = None,
    ) -> HermesChatResult:
        if shutil.which(self.settings.hermes_command) is None:
            raise RuntimeError(f"Hermes command not found: {self.settings.hermes_command}")

        response = self._send_with_resume(
            latest_user_message=latest_user_message,
            history=history,
            session_id=session_id,
        )

        if response.missing_session and session_id:
            response = self._send_with_replay(latest_user_message=latest_user_message, history=history)

        if not response.text:
            raise RuntimeError("Hermes CLI returned an empty response.")

        return HermesChatResult(text=response.text, session_id=response.session_id or session_id)

    def _send_with_resume(
        self,
        *,
        latest_user_message: str,
        history: list[HermesConversationMessage],
        session_id: str | None,
    ) -> CLIHermesResponse:
        if session_id:
            command = self._build_command(query=latest_user_message, session_id=session_id)
            return self._run_command(command)
        return self._send_with_replay(latest_user_message=latest_user_message, history=history)

    def _send_with_replay(
        self,
        *,
        latest_user_message: str,
        history: list[HermesConversationMessage],
    ) -> CLIHermesResponse:
        prompt = self._build_prompt(latest_user_message=latest_user_message, history=history)
        return self._run_command(self._build_command(query=prompt))

    def _build_command(self, *, query: str, session_id: str | None = None) -> list[str]:
        command = [self.settings.hermes_command, "chat", "-Q", "-q", query]

        if session_id:
            command.extend(["--resume", session_id])
        if self.settings.hermes_provider:
            command.extend(["--provider", self.settings.hermes_provider])
        if self.settings.hermes_model:
            command.extend(["--model", self.settings.hermes_model])
        if self.settings.hermes_toolsets:
            command.extend(["--toolsets", self.settings.hermes_toolsets])
        if self.settings.hermes_source:
            command.extend(["--source", self.settings.hermes_source])

        return command

    def _run_command(self, command: list[str]) -> CLIHermesResponse:
        completed = subprocess.run(
            command,
            cwd=self.settings.hermes_workdir or None,
            capture_output=True,
            text=True,
            check=False,
        )

        if completed.returncode != 0:
            error_text = completed.stderr.strip() or completed.stdout.strip() or "Hermes CLI request failed."
            raise RuntimeError(error_text)

        return self._parse_cli_output(completed.stdout)

    def _parse_cli_output(self, output: str) -> CLIHermesResponse:
        session_match = self.SESSION_ID_PATTERN.search(output)
        session_id = session_match.group("session_id") if session_match else None
        body = self.SESSION_ID_PATTERN.sub("", output).strip()

        lines = body.splitlines()
        while lines and self._is_metadata_line(lines[0]):
            lines.pop(0)

        text = "\n".join(lines).strip()
        return CLIHermesResponse(
            text=text,
            session_id=session_id,
            missing_session=text.startswith("Session not found:"),
        )

    def _is_metadata_line(self, line: str) -> bool:
        stripped = line.strip()
        return (
            not stripped
            or stripped.startswith("↻ Resumed session ")
            or stripped.startswith("╭─ ⚕ Hermes")
        )

    def _build_prompt(self, *, latest_user_message: str, history: list[HermesConversationMessage]) -> str:
        history_lines = []
        for message in history[-self.settings.hermes_history_limit :]:
            prefix = "User" if message.role == "user" else "Hermes"
            history_lines.append(f"{prefix}: {message.text}")

        transcript = "\n".join(history_lines) if history_lines else "(no prior messages)"

        return (
            "You are Hermes responding inside Hermes Mobile.\n"
            "Continue the conversation naturally using the history below.\n"
            "Return only the next assistant reply.\n\n"
            f"Conversation history:\n{transcript}\n\n"
            f"Latest user message:\nUser: {latest_user_message}"
        )
