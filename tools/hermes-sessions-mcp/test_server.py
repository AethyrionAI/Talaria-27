"""Unit tests for hermes-sessions-mcp. Transport is stubbed; no live gateway.
Run: .venv/bin/pytest test_server.py -v
"""
import json
import types

import server


def _stub(monkeypatch, responses):
    """responses: list of (expected_method, expected_path, reply_dict)."""
    calls = []

    def fake_request(method, path, body=None, timeout=20):
        calls.append({"method": method, "path": path, "body": body,
                      "timeout": timeout})
        exp = responses[len(calls) - 1]
        assert (method, path) == (exp[0], exp[1]), f"unexpected call {method} {path}"
        return dict(exp[2])

    monkeypatch.setattr(server, "_request", fake_request)
    return calls


def test_create_session_extracts_nested_id(monkeypatch):
    _stub(monkeypatch, [("POST", "/api/sessions",
                         {"session": {"id": "api_123_ab"}})])
    out = json.loads(server.create_session())
    assert out["session_id"] == "api_123_ab"


def test_chat_shapes_payload_and_reply(monkeypatch):
    calls = _stub(monkeypatch, [("POST", "/api/sessions/api_1/chat",
                                 {"session_id": "api_1",
                                  "message": {"role": "assistant",
                                              "content": "BRIDGE-OK"},
                                  "usage": {"total_tokens": 5}})])
    out = json.loads(server.chat("api_1", "hi", timeout_s=90))
    assert out["reply"] == "BRIDGE-OK"
    assert out["usage"]["total_tokens"] == 5
    assert calls[0]["body"] == {"message": "hi"}
    assert calls[0]["timeout"] == 90


def test_chat_timeout_clamped_and_inputs_required(monkeypatch):
    calls = _stub(monkeypatch, [("POST", "/api/sessions/s/chat",
                                 {"message": {"content": "x"}})])
    server.chat("s", "m", timeout_s=99999)
    assert calls[0]["timeout"] == server.CHAT_TIMEOUT_MAX
    assert "required" in json.loads(server.chat("", "m"))["error"]
    assert "required" in json.loads(server.chat("s", ""))["error"]


def test_error_dict_passes_through(monkeypatch):
    _stub(monkeypatch, [("POST", "/api/sessions/s/chat",
                         {"error": "401 unauthorized — API_SERVER_KEY missing"})])
    out = json.loads(server.chat("s", "m"))
    assert "401" in out["error"]


def test_read_messages_tails_to_limit(monkeypatch):
    msgs = [{"role": "user", "content": str(i)} for i in range(10)]
    _stub(monkeypatch, [("GET", "/api/sessions/s/messages", {"messages": msgs})])
    out = json.loads(server.read_messages("s", limit=3))
    assert out["count"] == 3
    assert out["messages"][-1]["content"] == "9"


def test_list_sessions_caps_limit(monkeypatch):
    _stub(monkeypatch, [("GET", "/api/sessions",
                         {"sessions": [{"id": i} for i in range(150)]})])
    out = json.loads(server.list_sessions(limit=500))
    assert out["count"] == 100


def test_key_resolution_env_file(monkeypatch, tmp_path):
    envf = tmp_path / ".env"
    envf.write_text("OTHER=1\nAPI_SERVER_KEY=\"sk-test-abc\"\n")
    monkeypatch.delenv("API_SERVER_KEY", raising=False)
    monkeypatch.setattr(server.os.path, "expanduser",
                        lambda p: str(envf) if p.endswith("/.env") else p)
    assert server._load_api_key() == "sk-test-abc"


def test_build_mcp_registers_five_tools():
    mcp = server.build_mcp()
    # FastMCP keeps a tool manager; count registered tools defensively.
    tools = getattr(getattr(mcp, "_tool_manager", None), "_tools", None)
    assert tools is not None and len(tools) == 5
    assert "hermes_chat" in tools
