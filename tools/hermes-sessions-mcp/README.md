# Hermes Sessions MCP

Task a Hermes gateway from Claude Desktop / Claude Code and read replies —
the OPEN_ITEMS #149 bridge. Wraps the Sessions API (`:8642`) as a stdio MCP
server. One server process per host; two config entries = both hosts.

## Tools
- `hermes_gateway_health` — reachability + version (use first when anything fails)
- `hermes_list_sessions` — recent sessions on the host
- `hermes_create_session` — new session → `session_id`
- `hermes_chat` — send a message, wait for the agent reply (timeout_s 30–600)
- `hermes_read_messages` — transcript tail for any session (incl. phone sessions)

## Auth
`API_SERVER_KEY` env → `~/.hermes/.env` → `~/.hermes/config.yaml`
(`api_server.key`). Same bearer the Talaria app uses. No secrets belong in
`claude_desktop_config.json` — the server resolves the key itself.

## Setup
```bash
cd tools/hermes-sessions-mcp
python3 -m venv .venv && .venv/bin/pip install mcp pytest pyyaml
.venv/bin/pytest test_server.py            # unit suite (transport stubbed)
.venv/bin/python server.py selftest        # live smoke vs the Mac gateway
HERMES_BASE_URL=http://100.110.102.59:8642 .venv/bin/python server.py selftest
```

## Claude Desktop config (macOS)
`~/Library/Application Support/Claude/claude_desktop_config.json` →
`mcpServers`:
```json
"hermes-mac": {
  "command": "/Users/owenjones/Documents/Claude/Talaria-27/tools/hermes-sessions-mcp/.venv/bin/python",
  "args": ["/Users/owenjones/Documents/Claude/Talaria-27/tools/hermes-sessions-mcp/server.py"]
},
"hermes-ojamd": {
  "command": "/Users/owenjones/Documents/Claude/Talaria-27/tools/hermes-sessions-mcp/.venv/bin/python",
  "args": ["/Users/owenjones/Documents/Claude/Talaria-27/tools/hermes-sessions-mcp/server.py"],
  "env": { "HERMES_BASE_URL": "http://100.110.102.59:8642" }
}
```
Restart Claude Desktop after editing.

## Optional: channel-bridge companion (`hermes mcp serve`)
Upstream 0.19 ships a separate stdio server exposing Hermes's PLATFORM
conversations (list/read, outbound send, live events, approval respond —
it cannot task Hermes; that's what this bridge is for). To enable, add:
```json
"hermes-channels": { "command": "hermes", "args": ["mcp", "serve"] }
```

## Posture notes
- Tasking a host's Hermes means the agent may execute tools ON THAT HOST.
  The OJAMD entry is deliberately a separate named server so it's always
  explicit which agent is being tasked. No SSH anywhere in this path.
- Chat turns can take 20s+ (cold gateway ≈21s to first token + generation).
