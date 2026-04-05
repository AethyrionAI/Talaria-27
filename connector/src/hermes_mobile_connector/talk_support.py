from __future__ import annotations

from datetime import datetime, timezone
import os
from pathlib import Path
import re
import subprocess

from .sensor_store import SensorStore
from .state import VoiceContextSnapshot

DEFAULT_REALTIME_MODELS = ["gpt-realtime-1.5", "gpt-realtime"]
DEFAULT_REALTIME_VOICE = "verse"
VOICE_CONTEXT_MAX_CHARS = 4000
ANSI_ESCAPE_RE = re.compile(r"\x1B\[[0-9;]*[A-Za-z]")


def utcnow_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def resolve_hermes_home(explicit_home: str | None = None) -> Path:
    configured = explicit_home or os.getenv("HERMES_HOME")
    if configured:
        return Path(configured).expanduser()
    return Path.home() / ".hermes"


def read_memory_file(path: Path, *, max_chars: int = VOICE_CONTEXT_MAX_CHARS) -> str:
    if not path.exists():
        return "(not available)"

    content = path.read_text(encoding="utf-8").strip()
    if not content:
        return "(empty)"
    if len(content) <= max_chars:
        return content
    return f"{content[:max_chars].rstrip()}\n\n[truncated]"


def summarize_sensor_freshness(sensor_store: SensorStore) -> str:
    freshness = sensor_store.get_sensor_freshness_summary()
    location = freshness.get("location")
    health = freshness.get("health", {})

    if location is None:
        location_summary = "No recent location reading is available."
    else:
        state = "stale" if location["stale"] else "fresh"
        location_summary = (
            f"Current location context is {state}, recorded {location['ageSeconds']} seconds ago."
        )

    health_summary = (
        "Health context has "
        f"{health.get('freshCount', 0)} fresh metrics, "
        f"{health.get('staleCount', 0)} stale metrics, "
        f"and {health.get('count', 0)} total metrics."
    )
    return f"{location_summary} {health_summary}"


def summarize_memory_provider(*, hermes_command: str | None, hermes_home: str | None) -> str:
    if not hermes_command:
        return "Memory provider status unavailable."

    env = os.environ.copy()
    if hermes_home:
        env["HERMES_HOME"] = hermes_home

    try:
        completed = subprocess.run(
            [hermes_command, "memory", "status"],
            capture_output=True,
            text=True,
            timeout=10,
            check=False,
            env=env,
        )
    except Exception as error:  # noqa: BLE001
        return f"Memory provider status unavailable: {error}"

    output = completed.stdout or completed.stderr or ""
    cleaned_lines = [
        ANSI_ESCAPE_RE.sub("", line).strip()
        for line in output.splitlines()
        if line.strip()
    ]
    if not cleaned_lines:
        return "Memory provider status unavailable."

    relevant = [
        line for line in cleaned_lines
        if line.lower().startswith(("provider:", "builtin:", "status:", "enabled:"))
    ]
    if not relevant:
        relevant = cleaned_lines[:4]
    return " ".join(relevant)


def build_voice_context_snapshot(
    *,
    sensor_store: SensorStore,
    hermes_command: str | None,
    hermes_home: str | None,
    readiness_summary: str,
) -> VoiceContextSnapshot:
    resolved_home = resolve_hermes_home(hermes_home)
    memories_dir = resolved_home / "memories"
    soul_summary = read_memory_file(resolved_home / "SOUL.md", max_chars=1500)
    memory_summary = read_memory_file(memories_dir / "MEMORY.md")
    user_summary = read_memory_file(memories_dir / "USER.md")
    sensor_summary = summarize_sensor_freshness(sensor_store)
    memory_provider_summary = summarize_memory_provider(
        hermes_command=hermes_command,
        hermes_home=str(resolved_home),
    )
    system_prompt = render_voice_system_prompt(
        soul_summary=soul_summary,
        memory_summary=memory_summary,
        user_summary=user_summary,
        sensor_summary=sensor_summary,
        memory_provider_summary=memory_provider_summary,
        readiness_summary=readiness_summary,
    )
    return VoiceContextSnapshot(
        system_prompt=system_prompt,
        memory_summary=memory_summary,
        user_summary=user_summary,
        sensor_summary=sensor_summary,
        memory_provider_summary=memory_provider_summary,
        readiness_summary=readiness_summary,
        updated_at=utcnow_iso(),
    )


def render_voice_system_prompt(
    *,
    soul_summary: str = "(not available)",
    memory_summary: str,
    user_summary: str,
    sensor_summary: str,
    memory_provider_summary: str,
    readiness_summary: str,
) -> str:
    # Build persona block from SOUL.md if available, otherwise fall back to default
    if soul_summary and soul_summary not in ("(not available)", "(empty)"):
        persona_block = (
            f"{soul_summary}\n\n"
            "Adapt the above persona for live duplex voice: keep responses conversational, "
            "crisp, and natural. No kaomoji or formatting in speech."
        )
    else:
        persona_block = (
            "You are Hermes: a warm, playful, highly competent AI assistant.\n"
            "Keep responses conversational, crisp, and natural for live duplex voice."
        )

    return (
        f"{persona_block}\n\n"
        "You are speaking through Hermes Mobile talk mode.\n"
        "You may answer directly from the cached context below when it is enough.\n"
        "When you need deeper memory, tool use, or a more deliberate agentic action, call the "
        "`hermes_delegate` tool instead of guessing.\n"
        "When delegating, tell the user what you're doing (e.g. \"Let me check on that\") "
        "so they know to wait.\n"
        "Do not mention internal implementation details unless the user asks.\n\n"
        "Cached Hermes memory:\n"
        f"{memory_summary}\n\n"
        "Cached user profile:\n"
        f"{user_summary}\n\n"
        "Current sensor freshness:\n"
        f"{sensor_summary}\n\n"
        "Hermes memory provider status:\n"
        f"{memory_provider_summary}\n\n"
        "Hermes tool readiness:\n"
        f"{readiness_summary}"
    )
