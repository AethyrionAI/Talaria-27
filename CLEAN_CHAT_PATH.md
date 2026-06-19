# Talaria — Clean Chat Path

The plan for replacing Talaria's chat layer so it talks directly to the Hermes API server's Sessions API on port 8642 (structured JSON/SSE), instead of the relay → connector → Hermes-CLI pipe.

Save this in the repo (e.g. repo root). Xcode's AI chat is ephemeral; this file is the durable source of truth. Hand the agent one Phase at a time.

## Goal

Keep dylan's app shell and the working sensor pipeline. Swap only the chat transport: from the relay/CLI pipe (which leaks raw ANSI codes + thinking and depends on a fragile connector→CLI launch) to Hermes's Sessions API on 8642, which returns clean structured data.

This single change fixes, at the root:

- **Garbled chat** — no more ANSI escape codes (`[2;3m`, `[0m`); those only exist in CLI terminal output.
- **No new chat** — a session is first-class on 8642; "New Chat" = create a new session.
- **Awkward model switching** — switch via a `/model` turn, then start a fresh session.
- **The "Hermes command not found" blocker** — chat no longer touches the connector→CLI path at all.

Sensors are untouched and stay available to chat, because the sensor MCP tools live in Hermes's config and run server-side for any session.

## Why it works (architecture)

```
Talaria (SwiftUI)
  ├─ CHAT  ──(Tailscale, Bearer API_SERVER_KEY)──▶  Hermes API server :8642  (Sessions API)
  │                                                   └─ server-side agent: memory, skills, MCP tools
  │                                                        └─ hermes_mobile MCP tools (GPS, health, …)
  └─ SENSORS ──(Tailscale)──▶ Relay :8000 ──WS──▶ Connector ──▶ SQLite + registers hermes_mobile MCP
```

- The API server spins a full Hermes agent per request — same memory, skills, and MCP servers as any session. So a Sessions-API chat can still call the sensor tools (`get_user_location`, `get_health_summary`, …) registered by the connector.
- The Sessions API is JSON/SSE, not a terminal stream — no ANSI, clean markdown, optional separate reasoning.
- Chat and sensors are now independent paths. The relay/connector keep doing sensor ingestion + MCP registration; chat goes straight to 8642.

## Verified API contract (Hermes docs + your live tests)

Auth header on every request: `Authorization: Bearer <API_SERVER_KEY>`

| Action | Request | Notes |
|---|---|---|
| Models (sanity) | `GET /v1/models` | Lists `hermes-agent`. Confirms the server is up + key works. |
| Capabilities | `GET /v1/capabilities` | `session_*` feature flags; confirms session surface. |
| Create session | `POST /api/sessions` body `{}` | Returns `{ "object":"hermes.session", "session": { "id":"api_…" } }` — id is at `.session.id`. |
| Turn (sync) | `POST /api/sessions/{id}/chat` body `{"input":"…"}` | Returns assistant message JSON. |
| Turn (stream) | `POST /api/sessions/{id}/chat/stream` body `{"input":"…"}` | SSE deltas. Exact event names + reasoning field = confirm in Phase 0. |
| Switch model | `POST /api/sessions/{id}/chat` body `{"input":"/model provider:model"}` | Dispatched as a command; applies to the NEXT session. |
| List / delete | `GET /api/sessions`, `DELETE /api/sessions/{id}` | Session management. |

Model identifier format: `provider:model` (e.g. `deepseek:deepseek-v4-pro`, `groq:qwen/qwen3-32b`). Send verbatim.

## Phase 0 — Stand up + verify on the box (NO Swift yet)

The de-risk step. Locks the contract on your box and reveals the reasoning format before any code is written.

**A. Enable + start the API server (Hermes Git Bash on the Windows box):**

```bash
hermes config set API_SERVER_ENABLED true
hermes config set API_SERVER_KEY "PICK-A-STRONG-SECRET"   # secret lands in ~/.hermes/.env
# default port is 8642; to override: add API_SERVER_PORT=8642 to ~/.hermes/.env
hermes gateway run        # native Windows: run in a terminal and leave it open
                          # (background service is macOS/WSL2 only — same caveat as the connector)
```

**B. Verify with curl — paste the JSON/SSE shapes back; that's what finalizes the Swift:**

```bash
KEY="PICK-A-STRONG-SECRET"

# 1) server up + key valid
curl -s http://localhost:8642/v1/models -H "Authorization: Bearer $KEY"

# 2) create a session -> copy .session.id into SID below
curl -s -X POST http://localhost:8642/api/sessions \
  -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" -d '{}'

# 3) sync turn -> confirm CLEAN markdown, NO ANSI codes
curl -s -X POST http://localhost:8642/api/sessions/SID/chat \
  -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -d '{"input":"Reply in markdown: a # heading, a - bullet list, and **bold**."}'

# 4) streaming turn -> note the SSE EVENT NAMES and whether reasoning is separate
curl -N -X POST http://localhost:8642/api/sessions/SID/chat/stream \
  -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -d '{"input":"Think step by step, then give the answer: 17 * 23?"}'

# 5) capabilities
curl -s http://localhost:8642/v1/capabilities -H "Authorization: Bearer $KEY"

# 6) does an API-server session see the SENSOR tools?
curl -s -X POST http://localhost:8642/api/sessions/SID/chat \
  -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -d '{"input":"What is my current location? Use your tools."}'

# 7) model switch test (applies to the NEXT session)
curl -s -X POST http://localhost:8642/api/sessions/SID/chat \
  -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -d '{"input":"/model deepseek:deepseek-v4-pro"}'
#   then create a NEW session (step 2) and run a reasoning prompt to see the reasoning format
```

**C. Reach it from the Mac over Tailscale:**

```bash
curl -s http://ojamd:8642/v1/models -H "Authorization: Bearer $KEY"   # run ON the Mac
```

If that works, the simulator can reach chat. For HTTPS (nicer, and removes the need for the ATS exception): `tailscale serve` a cert onto 8642. Otherwise plain http + the `NSAllowsArbitraryLoads` exception already in `project.yml`.

**Phase 0 deliverable:** the exact shapes from steps 2–7 (especially the SSE event names in step 4 and whether step 6 actually calls a sensor tool). Paste them back to finalize Phase 1.

## Phase 1 — Direct Sessions-API client (Swift; Xcode agent)

Reuse dylan's abstraction — don't rip anything out. Add a new client that conforms to the existing `HermesClientProtocol` but targets 8642.

- New `HermesMobile/Services/Live/SessionsHermesClient.swift`:
  - `createSession()` → `POST /api/sessions`, read `.session.id`.
  - `sendTurn(sessionId:input:)` → `POST /api/sessions/{id}/chat` (sync; prove auth + render first).
  - `streamTurn(sessionId:input:)` → `POST /api/sessions/{id}/chat/stream`, map SSE deltas → existing `StreamingUpdate`.
  - `switchModel(_:)` → send `"/model <identifier>"` as a turn.
  - Bearer auth on every request; base URL + key from settings/Keychain.
- Settings: add a "Hermes API" section — Base URL (e.g. `http://ojamd:8642`) and API key. Store the key in the app's existing secure store (Keychain), never in source.
- Wire chat (`ChatScreen` / its view model) to use `SessionsHermesClient` instead of `LiveHermesClient`. Leave the relay client (`RelayAPIClient`) in place for sensors/pairing.

**Verify:** send "Hello" → a clean response renders, no ANSI. Sync first, then add streaming.

## Phase 2 — Reasoning + markdown (Xcode agent)

- **Reasoning channel:** add `reasoning` to `Models/Message.swift` and `case reasoningDelta(String)` to `Models/StreamingUpdate.swift`. In `SessionsHermesClient`, route the reasoning field/event found in Phase 0 to `.reasoningDelta`; add a `<think>…</think>` splitter as a fallback.
- **Markdown:** render prose with MarkdownUI (add via `project.yml` packages + `xcodegen generate`), replacing the inline-only `AttributedString` in `Features/Chat/MarkdownContentView.swift`. Put reasoning behind a collapsible disclosure (the app already has `ThinkingIndicatorView` styling to match).

**Verify:** ask a reasoning model → clean markdown answer, thinking tucked into a disclosure, no symbols, no ANSI.

## Phase 3 — New chat + model picker (Xcode agent)

- **New Chat:** toolbar + → `createSession()` + set active. Real fresh chats now (sessions are first-class on 8642).
- **Model picker:** `ModelPickerView` seeded from `HermesModelsSeed.swift` (move it from `~/Downloads` into the project), grouped by company. On select → `switchModel("/model …")` → `createSession()` → set active. (Switch applies on the new session — matches Hermes behavior, and gives clear feedback, fixing "typing /model does nothing".)
- Manually add the built-in Anthropic and DeepSeek rows (absent from `config.yaml`).

**Verify:** pick a model → a fresh chat starts on it; switching is one tap.

## Phase 4 — Settings + UI polish (optional)

- Flesh out the sparse Settings page (API host, key, current model, reasoning on/off; sensor toggles already exist).
- A real visual pass on the chat so it isn't boring (use the frontend-design conventions).

## Phase 5 — Tailscale HTTPS + TestFlight

- `tailscale serve` HTTPS onto 8642; then you can drop the `NSAllowsArbitraryLoads` ATS exception.
- Archive → upload → TestFlight while Mac access lasts. Add Shelley as the second tester.

## Runtime checklist (what must be running on the box)

1. **Hermes gateway with API server enabled** → chat on 8642. (`hermes gateway run`, foreground on native Windows.)
2. **Relay (port 8000)** → sensor uploads from the phone.
3. **Connector** → sensor storage + serves the `hermes_mobile` MCP tools.

Chat depends only on #1. Sensors depend on #2 + #3. The connector→CLI "command not found" issue no longer blocks chat.

## Open items to confirm in Phase 0

- Exact SSE event names on `/api/sessions/{id}/chat/stream`, and the reasoning field/event format (folded vs separate `reasoning_content`).
- Whether API-server sessions actually invoke the `hermes_mobile` MCP tools (Phase 0 step 6). If not, ensure the API-server platform's toolset includes MCP tools (per-platform tool config), so chat stays sensor-aware.
