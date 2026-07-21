#!/usr/bin/env python3
"""Hermes Sessions MCP — task a Hermes gateway and read replies over MCP.

Wraps the Hermes Sessions API (`:8642`) as a stdio MCP server so Claude
Desktop / Claude Code sessions can create sessions, send chat turns, and
read transcripts on any reachable Hermes host — the OPEN_ITEMS #149 bridge.

Host selection: HERMES_BASE_URL env (default http://127.0.0.1:8642).
Auth: API_SERVER_KEY env → ~/.hermes/.env → ~/.hermes/config.yaml
      (api_server.key). Same bearer the Talaria app uses. Never logged.

Claude Desktop config (two hosts = two named servers):
    "hermes-mac":   {"command": ".../.venv/bin/python", "args": [".../server.py"]}
    "hermes-ojamd": {"command": ".../.venv/bin/python", "args": [".../server.py"],
                     "env": {"HERMES_BASE_URL": "http://100.110.102.59:8642"}}

Selftest (live, no MCP transport):  python server.py selftest
"""
from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request

BASE_URL = os.environ.get("HERMES_BASE_URL", "http://127.0.0.1:8642").rstrip("/")
CHAT_TIMEOUT_DEFAULT = 180
CHAT_TIMEOUT_MAX = 600


def _load_api_key() -> str | None:
    """API_SERVER_KEY env → ~/.hermes/.env → ~/.hermes/config.yaml (shim's proven order)."""
    key = os.environ.get("API_SERVER_KEY", "").strip()
    if key:
        return key
    env_path = os.path.expanduser("~/.hermes/.env")
    try:
        if os.path.exists(env_path):
            for line in open(env_path, encoding="utf-8"):
                line = line.strip()
                if line.startswith("API_SERVER_KEY="):
                    val = line.split("=", 1)[1].strip().strip("'\"")
                    if val:
                        return val
    except Exception:
        pass
    try:
        import yaml  # optional; present in hermes venvs
        cfg_path = os.path.expanduser("~/.hermes/config.yaml")
        if os.path.exists(cfg_path):
            cfg = yaml.safe_load(open(cfg_path, encoding="utf-8")) or {}
            val = ((cfg.get("api_server") or {}).get("key") or "").strip()
            if val:
                return val
    except Exception:
        pass
    return None


API_KEY = _load_api_key()


def _request(method: str, path: str, body: dict | None = None,
             timeout: int = 20) -> dict:
    """One Sessions-API round trip. Returns parsed JSON or an error dict
    with an actionable `error` message (never raises to the tool layer)."""
    url = f"{BASE_URL}{path}"
    headers = {"Content-Type": "application/json"}
    if API_KEY:
        headers["Authorization"] = f"Bearer {API_KEY}"
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return json.loads(resp.read().decode() or "{}")
    except urllib.error.HTTPError as e:
        detail = ""
        try:
            detail = e.read().decode()[:300]
        except Exception:
            pass
        if e.code == 401:
            return {"error": "401 unauthorized — API_SERVER_KEY missing or wrong. "
                    "Sources checked: env, ~/.hermes/.env, ~/.hermes/config.yaml."}
        return {"error": f"HTTP {e.code} from {path}: {detail or e.reason}"}
    except urllib.error.URLError as e:
        return {"error": f"Gateway unreachable at {BASE_URL} ({e.reason}). "
                "The gateway is a user-process (pythonw/`hermes gateway run`), NOT an "
                "NSSM service — check the :8642 port owner; allow ~15-20s after start."}
    except Exception as e:  # timeout, decode, etc.
        return {"error": f"{type(e).__name__}: {e}"}


# ---- plain functions (tested directly; MCP decorators wrap below) ----

def gateway_health() -> str:
    out = _request("GET", "/health", timeout=15)
    out.setdefault("base_url", BASE_URL)
    return json.dumps(out)


def list_sessions(limit: int = 20) -> str:
    out = _request("GET", "/api/sessions", timeout=20)
    if "error" in out:
        return json.dumps(out)
    sessions = out.get("sessions") or out.get("data") or out
    if isinstance(sessions, list):
        sessions = sessions[: max(1, min(int(limit), 100))]
        return json.dumps({"base_url": BASE_URL, "count": len(sessions),
                           "sessions": sessions})
    return json.dumps({"base_url": BASE_URL, "raw": sessions})


def create_session() -> str:
    out = _request("POST", "/api/sessions", body={}, timeout=20)
    if "error" in out:
        return json.dumps(out)
    sid = (out.get("session") or {}).get("id") or out.get("id")
    if not sid:
        return json.dumps({"error": f"no session id in response: {json.dumps(out)[:200]}"})
    return json.dumps({"base_url": BASE_URL, "session_id": sid})


def chat(session_id: str, message: str, timeout_s: int = CHAT_TIMEOUT_DEFAULT) -> str:
    session_id = (session_id or "").strip()
    message = (message or "").strip()
    if not session_id or not message:
        return json.dumps({"error": "session_id and message are both required "
                           "(use hermes_create_session first)"})
    timeout_s = max(30, min(int(timeout_s), CHAT_TIMEOUT_MAX))
    out = _request("POST", f"/api/sessions/{session_id}/chat",
                   body={"message": message}, timeout=timeout_s)
    if "error" in out:
        return json.dumps(out)
    return json.dumps({
        "base_url": BASE_URL,
        "session_id": out.get("session_id") or session_id,
        "reply": (out.get("message") or {}).get("content", ""),
        "usage": out.get("usage"),
    })


def read_messages(session_id: str, limit: int = 40) -> str:
    session_id = (session_id or "").strip()
    if not session_id:
        return json.dumps({"error": "session_id is required"})
    out = _request("GET", f"/api/sessions/{session_id}/messages", timeout=30)
    if "error" in out:
        return json.dumps(out)
    msgs = out.get("messages") or out.get("data") or []
    if isinstance(msgs, list) and limit:
        msgs = msgs[-max(1, min(int(limit), 200)):]
    return json.dumps({"base_url": BASE_URL, "session_id": session_id,
                       "count": len(msgs) if isinstance(msgs, list) else None,
                       "messages": msgs})


# ---- MCP surface ----

def build_mcp():
    from mcp.server.fastmcp import FastMCP
    mcp = FastMCP("hermes_sessions_mcp")
    ro = {"readOnlyHint": True}

    mcp.tool(name="hermes_gateway_health", annotations=ro)(
        _doc(gateway_health, "Check the Hermes gateway at this server's host: "
             "reachability, version, status. Use first when anything fails."))
    mcp.tool(name="hermes_list_sessions", annotations=ro)(
        _doc(list_sessions, "List recent Hermes sessions on this host. "
             "limit: max entries (default 20, cap 100)."))
    mcp.tool(name="hermes_create_session")(
        _doc(create_session, "Create a fresh Hermes session; returns session_id "
             "for hermes_chat. One session = one continuous transcript."))
    mcp.tool(name="hermes_chat")(
        _doc(chat, "Send a message to a Hermes session and wait for the agent's "
             "reply (the agent may run tools on ITS host; cold gateway + large "
             "context can take 20s+). timeout_s: 30-600, default 180."))
    mcp.tool(name="hermes_read_messages", annotations=ro)(
        _doc(read_messages, "Read a session's transcript (last `limit` messages, "
             "default 40). Works for sessions created by any client, incl. the phone."))
    return mcp


def _doc(fn, description: str):
    fn.__doc__ = description
    return fn


def _selftest() -> int:
    """Live smoke against the configured gateway; no MCP transport involved."""
    print(f"base_url={BASE_URL} key={'present' if API_KEY else 'MISSING'}")
    h = json.loads(gateway_health())
    print("health:", {k: h.get(k) for k in ("status", "version", "error") if k in h})
    if "error" in h:
        return 1
    s = json.loads(list_sessions(limit=3))
    print("sessions:", s.get("count", s.get("error")))
    return 0 if "error" not in s else 1


def main():
    if len(sys.argv) > 1 and sys.argv[1] == "selftest":
        raise SystemExit(_selftest())
    build_mcp().run()  # stdio transport


if __name__ == "__main__":
    main()
