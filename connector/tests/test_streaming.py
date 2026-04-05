"""Tests for the connector's streaming job handler and API executor.

Covers:
  - _handle_job_streaming translates StreamEvents into WebSocket messages
  - text_delta events accumulate and are sent as job.progress
  - tool_activity events are sent as job.progress with kind=tool_activity
  - finish event triggers job.result with accumulated text, sessionId, and usage
  - empty response triggers job.failed
  - exceptions during streaming trigger job.failed
  - HermesAPIExecutor SSE line parsing (tool progress regex, content deltas)
  - HermesAPIRuntimeAdapter streaming pass-through
"""

from __future__ import annotations

import asyncio
import httpx
import json
from dataclasses import dataclass
from typing import AsyncIterator

from hermes_mobile_connector.client import HermesMobileConnector
from hermes_mobile_connector.hermes_api_executor import (
    TOOL_PROGRESS_RE,
    StreamEvent,
)
from hermes_mobile_connector.hermes_runner import ConnectorHermesSettings, HermesCLIExecutor
from hermes_mobile_connector.runtime_adapter import (
    HermesAPIRuntimeAdapter,
    RuntimeConversationMessage,
)
from hermes_mobile_connector.state import (
    ConnectorState,
    ConnectorStateStore,
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


# --------------------------------------------------------------------------
# FakeWebSocket for capturing messages
# --------------------------------------------------------------------------


class FakeWebSocket:
    """Minimal websocket mock that captures sent JSON messages."""

    def __init__(self):
        self.sent: list[dict] = []

    async def send(self, data: str) -> None:
        self.sent.append(json.loads(data))


# --------------------------------------------------------------------------
# Tool progress regex
# --------------------------------------------------------------------------


def test_tool_progress_regex_matches_hermes_api_format():
    """The API server emits tool progress as \\n`emoji label`\\n."""
    assert TOOL_PROGRESS_RE.match("\n`🔍 Searching files`\n") is not None
    assert TOOL_PROGRESS_RE.match("\n`📝 Writing code`\n").group(1) == "📝 Writing code"


def test_tool_progress_regex_rejects_normal_text():
    assert TOOL_PROGRESS_RE.match("Hello world") is None
    assert TOOL_PROGRESS_RE.match("`just backticks`") is None
    assert TOOL_PROGRESS_RE.match("\nno backticks\n") is None


# --------------------------------------------------------------------------
# _handle_job_streaming
# --------------------------------------------------------------------------


def test_handle_job_streaming_sends_progress_and_result(tmp_path):
    """Verifies the full streaming pipeline: text_delta + tool_activity + finish
    → WebSocket gets job.progress messages and a final job.result."""
    store = ConnectorStateStore(state_dir=tmp_path / "streaming-happy")
    store.save(make_enrolled_state())
    connector = HermesMobileConnector(state_store=store, executor=make_executor())

    events = [
        StreamEvent(type="tool_activity", label="🔍 Reading file"),
        StreamEvent(type="text_delta", data="Hello "),
        StreamEvent(type="text_delta", data="world!"),
        StreamEvent(
            type="finish",
            session_id="session-abc",
            usage={"prompt_tokens": 100, "completion_tokens": 25, "total_tokens": 125},
        ),
    ]

    class FakeStreamingAdapter:
        supports_streaming = True

        async def send_text_message_streaming(self, **kwargs):
            for event in events:
                yield event

    ws = FakeWebSocket()
    job = {
        "id": "job-123",
        "latestUserMessage": "Tell me something",
        "history": [],
        "sessionId": "session-prev",
    }

    asyncio.run(connector._handle_job_streaming(ws, job, FakeStreamingAdapter()))  # noqa: SLF001

    # Should have: tool_activity progress, two text_delta progress, and one job.result
    assert len(ws.sent) == 4

    # First: tool_activity
    assert ws.sent[0]["type"] == "job.progress"
    assert ws.sent[0]["kind"] == "tool_activity"
    assert ws.sent[0]["label"] == "🔍 Reading file"
    assert ws.sent[0]["jobId"] == "job-123"

    # Second + third: text_deltas
    assert ws.sent[1]["type"] == "job.progress"
    assert ws.sent[1]["kind"] == "text_delta"
    assert ws.sent[1]["delta"] == "Hello "

    assert ws.sent[2]["type"] == "job.progress"
    assert ws.sent[2]["kind"] == "text_delta"
    assert ws.sent[2]["delta"] == "world!"

    # Fourth: job.result
    assert ws.sent[3]["type"] == "job.result"
    assert ws.sent[3]["jobId"] == "job-123"
    assert ws.sent[3]["text"] == "Hello world!"
    assert ws.sent[3]["sessionId"] == "session-abc"
    assert ws.sent[3]["usage"]["total_tokens"] == 125


def test_handle_job_streaming_sends_failed_on_empty_response(tmp_path):
    """If the streaming yields a finish event but no text was accumulated,
    the handler should send job.failed."""
    store = ConnectorStateStore(state_dir=tmp_path / "streaming-empty")
    store.save(make_enrolled_state())
    connector = HermesMobileConnector(state_store=store, executor=make_executor())

    class FakeEmptyAdapter:
        supports_streaming = True

        async def send_text_message_streaming(self, **kwargs):
            yield StreamEvent(type="finish", session_id="sess-empty", usage=None)

    ws = FakeWebSocket()
    job = {"id": "job-empty", "latestUserMessage": "Empty", "history": []}

    asyncio.run(connector._handle_job_streaming(ws, job, FakeEmptyAdapter()))  # noqa: SLF001

    assert len(ws.sent) == 1
    assert ws.sent[0]["type"] == "job.failed"
    assert ws.sent[0]["jobId"] == "job-empty"
    assert "empty" in ws.sent[0]["error"].lower()


def test_handle_job_streaming_sends_failed_on_exception(tmp_path):
    """If the streaming adapter raises, the handler should catch and send job.failed."""
    store = ConnectorStateStore(state_dir=tmp_path / "streaming-error")
    store.save(make_enrolled_state())
    connector = HermesMobileConnector(state_store=store, executor=make_executor())

    class FakeErrorAdapter:
        supports_streaming = True

        async def send_text_message_streaming(self, **kwargs):
            yield StreamEvent(type="text_delta", data="partial ")
            raise RuntimeError("API server gone")

    ws = FakeWebSocket()
    job = {"id": "job-error", "latestUserMessage": "Crash", "history": []}

    asyncio.run(connector._handle_job_streaming(ws, job, FakeErrorAdapter()))  # noqa: SLF001

    # Should have one text_delta progress and then job.failed
    assert len(ws.sent) == 2
    assert ws.sent[0]["type"] == "job.progress"
    assert ws.sent[0]["delta"] == "partial "
    assert ws.sent[1]["type"] == "job.failed"
    assert "API server gone" in ws.sent[1]["error"]
    assert ws.sent[1]["retryable"] is False


def test_handle_job_streaming_marks_transport_failures_retryable(tmp_path):
    store = ConnectorStateStore(state_dir=tmp_path / "streaming-transport-error")
    store.save(make_enrolled_state())
    connector = HermesMobileConnector(state_store=store, executor=make_executor())

    class FakeErrorAdapter:
        supports_streaming = True

        async def send_text_message_streaming(self, **kwargs):
            request = httpx.Request("POST", "http://localhost:8642/v1/chat/completions")
            raise httpx.ConnectError("connection refused", request=request)
            yield  # pragma: no cover

    ws = FakeWebSocket()
    job = {"id": "job-transport", "latestUserMessage": "Retry me", "history": []}

    asyncio.run(connector._handle_job_streaming(ws, job, FakeErrorAdapter()))  # noqa: SLF001

    assert len(ws.sent) == 1
    assert ws.sent[0]["type"] == "job.failed"
    assert ws.sent[0]["retryable"] is True


def test_handle_job_streaming_passes_history_and_session(tmp_path):
    """Verifies that history and sessionId from the job are passed through to the adapter."""
    store = ConnectorStateStore(state_dir=tmp_path / "streaming-history")
    store.save(make_enrolled_state())
    connector = HermesMobileConnector(state_store=store, executor=make_executor())

    captured = {}

    class FakeCapturingAdapter:
        supports_streaming = True

        async def send_text_message_streaming(self, *, latest_user_message, history, session_id, attachments=None):
            captured["latest_user_message"] = latest_user_message
            captured["history"] = history
            captured["session_id"] = session_id
            captured["attachments"] = attachments
            yield StreamEvent(type="text_delta", data="OK")
            yield StreamEvent(type="finish", session_id="sess-new")

    ws = FakeWebSocket()
    job = {
        "id": "job-hist",
        "latestUserMessage": "Follow up question",
        "history": [
            {"role": "user", "text": "First message"},
            {"role": "hermes", "text": "First reply"},
        ],
        "sessionId": "session-prev-123",
    }

    asyncio.run(connector._handle_job_streaming(ws, job, FakeCapturingAdapter()))  # noqa: SLF001

    assert captured["latest_user_message"] == "Follow up question"
    assert captured["session_id"] == "session-prev-123"
    assert len(captured["history"]) == 2
    assert captured["history"][0].role == "user"
    assert captured["history"][0].text == "First message"
    assert captured["history"][1].role == "hermes"
    assert captured["history"][1].text == "First reply"


def test_handle_job_cli_materializes_attachments_for_tool_access(tmp_path):
    store = ConnectorStateStore(state_dir=tmp_path / "cli-attachments")
    store.save(make_enrolled_state())
    connector = HermesMobileConnector(state_store=store, executor=make_executor())

    captured = {}

    class FakeCLIRuntime:
        def send_text_message(self, *, latest_user_message, history, session_id=None):
            captured["latest_user_message"] = latest_user_message
            return type("Result", (), {"text": "Done", "session_id": "sess-cli"})()

    ws = FakeWebSocket()
    job = {
        "id": "job-cli-attachments",
        "latestUserMessage": "",
        "history": [],
        "attachments": [
            {
                "type": "image",
                "filename": "screen.png",
                "mimeType": "image/png",
                "data": "aGVsbG8=",
            },
            {
                "type": "file",
                "filename": "notes.txt",
                "mimeType": "text/plain",
                "data": "aGVsbG8=",
            },
        ],
    }

    asyncio.run(connector._handle_job_cli(ws, job, FakeCLIRuntime()))  # noqa: SLF001

    assert ws.sent[0]["type"] == "job.result"
    assert "vision_analyze" in captured["latest_user_message"]
    assert "read_file" in captured["latest_user_message"]
    assert "screen.png" in captured["latest_user_message"]
    assert "notes.txt" in captured["latest_user_message"]


def test_handle_job_routes_attachment_jobs_to_cli_even_when_streaming_runtime_exists(tmp_path, monkeypatch):
    store = ConnectorStateStore(state_dir=tmp_path / "attachment-routing")
    store.save(make_enrolled_state())
    connector = HermesMobileConnector(state_store=store, executor=make_executor())

    class FakeCLIRuntime:
        def send_text_message(self, *, latest_user_message, history, session_id=None):  # noqa: ANN001
            return type("Result", (), {"text": "Done", "session_id": "sess-cli"})()

    async def fake_runtime_adapter_async(state):  # noqa: ANN001
        raise AssertionError("Attachment jobs should not request the streaming/API runtime")

    def fake_runtime_adapter(state):  # noqa: ANN001
        return FakeCLIRuntime()

    captured: dict = {}

    async def fake_handle_job_streaming(websocket, job, runtime, workdir=None):  # noqa: ANN001
        captured["streaming"] = True

    async def fake_handle_job_cli(websocket, job, runtime):  # noqa: ANN001
        captured["cli"] = True
        captured["runtime_type"] = type(runtime).__name__

    monkeypatch.setattr(connector, "runtime_adapter_for_state_async", fake_runtime_adapter_async)
    monkeypatch.setattr(connector, "runtime_adapter_for_state", fake_runtime_adapter)
    monkeypatch.setattr(connector, "_handle_job_streaming", fake_handle_job_streaming)
    monkeypatch.setattr(connector, "_handle_job_cli", fake_handle_job_cli)

    job = {
        "id": "job-attachments",
        "latestUserMessage": "What is in this image?",
        "history": [],
        "attachments": [
            {
                "type": "image",
                "filename": "photo.jpg",
                "mimeType": "image/jpeg",
                "data": "aGVsbG8=",
            }
        ],
    }

    asyncio.run(connector._handle_job(FakeWebSocket(), job))  # noqa: SLF001

    assert captured == {"cli": True, "runtime_type": "FakeCLIRuntime"}


# --------------------------------------------------------------------------
# HermesAPIRuntimeAdapter streaming pass-through
# --------------------------------------------------------------------------


def test_api_runtime_adapter_streaming_yields_all_events():
    """The adapter's send_text_message_streaming should faithfully yield all
    events from the executor's stream_message."""
    emitted_events = [
        StreamEvent(type="tool_activity", label="🔧 Building"),
        StreamEvent(type="text_delta", data="Result: "),
        StreamEvent(type="text_delta", data="42"),
        StreamEvent(type="finish", session_id="sess-42", usage={"total_tokens": 50}),
    ]

    class FakeExecutor:
        async def stream_message(self, *, latest_user_message, history=None, session_id=None, attachments=None):
            for event in emitted_events:
                yield event

    adapter = HermesAPIRuntimeAdapter(FakeExecutor())

    collected = []

    async def collect():
        async for event in adapter.send_text_message_streaming(
            latest_user_message="What is 6*7?",
            history=[RuntimeConversationMessage(role="user", text="Hello")],
            session_id="sess-prev",
        ):
            collected.append(event)

    asyncio.run(collect())

    assert len(collected) == 4
    assert collected[0].type == "tool_activity"
    assert collected[0].label == "🔧 Building"
    assert collected[1].type == "text_delta"
    assert collected[1].data == "Result: "
    assert collected[2].type == "text_delta"
    assert collected[2].data == "42"
    assert collected[3].type == "finish"
    assert collected[3].session_id == "sess-42"
    assert collected[3].usage == {"total_tokens": 50}


def test_api_runtime_adapter_streaming_preserves_session_with_history():
    """When history is provided, the adapter should still pass session_id through
    to preserve session continuity and prefix caching."""
    captured = {}

    class FakeExecutor:
        async def stream_message(self, *, latest_user_message, history=None, session_id=None, attachments=None):
            captured["session_id"] = session_id
            captured["history"] = history
            yield StreamEvent(type="text_delta", data="ok")
            yield StreamEvent(type="finish")

    adapter = HermesAPIRuntimeAdapter(FakeExecutor())

    async def run():
        async for _ in adapter.send_text_message_streaming(
            latest_user_message="test",
            history=[RuntimeConversationMessage(role="user", text="prior")],
            session_id="should-be-dropped",
        ):
            pass

    asyncio.run(run())

    assert captured["session_id"] == "should-be-dropped"
    assert len(captured["history"]) == 1


def test_api_runtime_adapter_streaming_keeps_session_when_no_history():
    """When no history is provided, the adapter should pass the session_id through."""
    captured = {}

    class FakeExecutor:
        async def stream_message(self, *, latest_user_message, history=None, session_id=None, attachments=None):
            captured["session_id"] = session_id
            yield StreamEvent(type="text_delta", data="ok")
            yield StreamEvent(type="finish")

    adapter = HermesAPIRuntimeAdapter(FakeExecutor())

    async def run():
        async for _ in adapter.send_text_message_streaming(
            latest_user_message="test",
            history=[],
            session_id="keep-this",
        ):
            pass

    asyncio.run(run())

    assert captured["session_id"] == "keep-this"


# --------------------------------------------------------------------------
# HermesAPIExecutor._messages_payload builds correct OpenAI format
# --------------------------------------------------------------------------


def test_messages_payload_builds_openai_format():
    """The executor should build messages with 'assistant' role for 'hermes' entries."""
    from hermes_mobile_connector.hermes_api_executor import HermesAPIExecutor
    from hermes_mobile_connector.hermes_runner import HermesConversationMessage

    executor = HermesAPIExecutor()
    history = [
        HermesConversationMessage(role="user", text="Hello"),
        HermesConversationMessage(role="hermes", text="Hi there"),
        HermesConversationMessage(role="user", text="How are you?"),
    ]

    messages = executor._messages_payload(  # noqa: SLF001
        latest_user_message="What's up?",
        history=history,
    )

    assert len(messages) == 4
    assert messages[0] == {"role": "user", "content": "Hello"}
    assert messages[1] == {"role": "assistant", "content": "Hi there"}
    assert messages[2] == {"role": "user", "content": "How are you?"}
    assert messages[3] == {"role": "user", "content": "What's up?"}


def test_messages_payload_skips_empty_history_entries():
    """Empty/whitespace-only history entries should be filtered out."""
    from hermes_mobile_connector.hermes_api_executor import HermesAPIExecutor
    from hermes_mobile_connector.hermes_runner import HermesConversationMessage

    executor = HermesAPIExecutor()
    history = [
        HermesConversationMessage(role="user", text="Real message"),
        HermesConversationMessage(role="hermes", text="   "),
        HermesConversationMessage(role="user", text=""),
    ]

    messages = executor._messages_payload(  # noqa: SLF001
        latest_user_message="Final",
        history=history,
    )

    assert len(messages) == 2
    assert messages[0] == {"role": "user", "content": "Real message"}
    assert messages[1] == {"role": "user", "content": "Final"}


# --------------------------------------------------------------------------
# Git diff integration in _handle_job_streaming
# --------------------------------------------------------------------------

import subprocess


def _init_git_repo(path):
    subprocess.run(["git", "init"], cwd=str(path), capture_output=True, check=True)
    subprocess.run(["git", "config", "user.email", "t@t.com"], cwd=str(path), capture_output=True, check=True)
    subprocess.run(["git", "config", "user.name", "T"], cwd=str(path), capture_output=True, check=True)
    (path / "main.py").write_text("pass\n")
    subprocess.run(["git", "add", "."], cwd=str(path), capture_output=True, check=True)
    subprocess.run(["git", "commit", "-m", "init"], cwd=str(path), capture_output=True, check=True)


def test_handle_job_streaming_includes_diff_when_files_change(tmp_path):
    """If Hermes modifies files during streaming, the job.result should include diff data."""
    repo_dir = tmp_path / "repo"
    repo_dir.mkdir()
    _init_git_repo(repo_dir)

    store = ConnectorStateStore(state_dir=tmp_path / "streaming-diff")
    store.save(make_enrolled_state())
    connector = HermesMobileConnector(state_store=store, executor=make_executor())

    class FakeStreamingAdapterWithFileChanges:
        supports_streaming = True

        async def send_text_message_streaming(self, **kwargs):
            # Simulate Hermes modifying a file during streaming
            (repo_dir / "main.py").write_text("print('hello world')\n")
            yield StreamEvent(type="tool_activity", label="📝 Writing code")
            yield StreamEvent(type="text_delta", data="Done!")
            yield StreamEvent(type="finish", session_id="sess-diff")

    ws = FakeWebSocket()
    job = {"id": "job-diff", "latestUserMessage": "Fix the code", "history": []}

    asyncio.run(
        connector._handle_job_streaming(  # noqa: SLF001
            ws, job, FakeStreamingAdapterWithFileChanges(), workdir=str(repo_dir),
        )
    )

    # Find the job.result message
    result = next(m for m in ws.sent if m["type"] == "job.result")
    assert "diff" in result
    assert len(result["diff"]["files"]) == 1
    assert result["diff"]["files"][0]["path"] == "main.py"
    assert result["diff"]["files"][0]["status"] == "modified"
    assert "1 file changed" in result["diff"]["summary"]


def test_handle_job_streaming_no_diff_when_no_workdir(tmp_path):
    """When workdir is None (non-git context), no diff should be included."""
    store = ConnectorStateStore(state_dir=tmp_path / "streaming-no-workdir")
    store.save(make_enrolled_state())
    connector = HermesMobileConnector(state_store=store, executor=make_executor())

    class FakeAdapter:
        supports_streaming = True

        async def send_text_message_streaming(self, **kwargs):
            yield StreamEvent(type="text_delta", data="Result")
            yield StreamEvent(type="finish")

    ws = FakeWebSocket()
    job = {"id": "job-nodiff", "latestUserMessage": "Hello", "history": []}

    asyncio.run(connector._handle_job_streaming(ws, job, FakeAdapter()))  # noqa: SLF001

    result = next(m for m in ws.sent if m["type"] == "job.result")
    assert "diff" not in result


def test_handle_job_streaming_no_diff_when_no_changes(tmp_path):
    """When Hermes doesn't modify any files, no diff should be included."""
    repo_dir = tmp_path / "clean-repo"
    repo_dir.mkdir()
    _init_git_repo(repo_dir)

    store = ConnectorStateStore(state_dir=tmp_path / "streaming-clean")
    store.save(make_enrolled_state())
    connector = HermesMobileConnector(state_store=store, executor=make_executor())

    class FakeAdapter:
        supports_streaming = True

        async def send_text_message_streaming(self, **kwargs):
            yield StreamEvent(type="text_delta", data="No changes needed")
            yield StreamEvent(type="finish")

    ws = FakeWebSocket()
    job = {"id": "job-clean", "latestUserMessage": "Check the code", "history": []}

    asyncio.run(
        connector._handle_job_streaming(  # noqa: SLF001
            ws, job, FakeAdapter(), workdir=str(repo_dir),
        )
    )

    result = next(m for m in ws.sent if m["type"] == "job.result")
    assert "diff" not in result
