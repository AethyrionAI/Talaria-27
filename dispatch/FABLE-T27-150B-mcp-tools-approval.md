# FABLE-T27-150B — MCP client Lane B: tool browse, manual invocation, grants, confirm-gate routing

**Item:** OPEN_ITEMS #150 (✨), Lane B of `design/MCP_CLIENT_DESIGN.md` (binding) ·
**Repo:** AethyrionAI/Talaria-27 · **Base:** main AFTER 150A merges — **DO NOT START
until the loop confirms 150A is on main**; this lane builds on its registry, probe, and
SDK dependency. · **Branch:** `claude/t27-150b-mcp-tools-approval` · **Size:** medium-large, one PR
**Staleness check:** re-run at start time (`gh pr list`, `git log --grep t27-150a`) —
confirm 150A merged and no overlapping PR appeared. OPEN_ITEMS numbers ≠ GitHub numbers.

## Mission

The power-user surface, model-free: browse a server's tools, invoke one manually behind
the #70 confirm gate, see the result, optionally insert it into the current conversation
as quoted context. NO model-driven invocation (that is Lane C), NO chat-plane streaming
changes. Trust model per design §4: server-declared metadata is display-only; every
invocation is treated as side-effect-capable; results are DATA, never instructions.

## Deliverables

### D1 — `Talaria/Services/Support/MCPToolClient.swift`
Thin session layer over the SDK for a registered server: connect (transport + auth per
150A's pattern), `listTools()` → `[MCPToolInfo]` (name, description, input schema as
display JSON, server-declared readOnlyHint AS DISPLAY METADATA ONLY), `callTool(name:
arguments:)` → normalized `MCPToolResult` (text content concatenated; non-text content
noted by type, not rendered), disconnect. Timeouts: connect ~10s, call ~60s. All errors
→ typed, user-renderable strings (unreachable / auth / tool-error / timeout).

### D2 — `Talaria/Services/Support/MCPToolGrantStore.swift`
Per-server-per-tool grant decisions: once / session / always / deny (0.19
smart-approval semantics per #148). "Always"/"deny" persist (UserDefaults, single
blob, versioned); "session" clears on process death; "once" is consumed on use.
Revocation API (`clearGrants(server:)`) surfaced on the server row in the 150A screen.
In THIS lane grants gate whether the confirm card can be skipped for a REPEAT manual
invocation of the same tool with the user re-shown the args inline instead; deny
blocks invocation outright with an honest message.

### D3 — `Talaria/Features/Settings/MCPToolBrowserScreen.swift`
Reached from an ONLINE server row (150A screen). Lists tools with name/description and
a read-only schema disclosure. Tapping a tool opens an invocation sheet: argument
fields generated from the input schema for the SIMPLE cases (string / number / bool /
enum top-level properties — text fields, toggles, pickers), with a raw-JSON fallback
editor for anything nested. Required fields marked from the schema.

### D4 — Confirm-gate routing (the #70 integration)
Manual invocation stages through `ToolConfirmationCenter` — the SAME staged-card /
awaited-continuation mechanics, defaults-closed, editable argument preview, second
concurrent request auto-declines. Read `ToolConfirmationCenter.swift` and
`DeviceActionTools.swift` for the exact staging contract BEFORE writing this; extend,
do not fork. The card labels server + tool explicitly (the user must always know which
remote is being hit). Grant store consulted per D2 semantics.

### D5 — Result rendering + insert-into-chat
Result view: monospaced text content, size-capped display with expand; truncation
marker if the client capped it. "Insert into conversation" appends the result to the
CURRENT conversation's composer as quoted context (prefixed provenance line:
`[MCP <server>/<tool>]`) — the user sends it; the app never auto-sends. Works
identically for local-brain and Hermes conversations (it is just composer text —
zero ChatStore/streaming changes).

### D6 — Tests
Extend `MCPClientTests.swift` + new `MCPToolFlowTests.swift` (regen rule applies):
grant-store truth table (all four decisions × persistence classes); schema→field
generation for the simple cases + raw-JSON fallback selection; result normalization
(text concat, non-text noted, cap + marker); confirm-gate staging contract with a
faked center (mirror how `DeviceActionToolsTests` fakes it — read it first).

## Hard constraints
- No ChatStore/streaming/router changes (composer insertion is plain text into the
  existing composer API). No model wiring of any kind — Lane C's job.
- **Do NOT touch `OPEN_ITEMS.md`** — hard fail.
- New files ⇒ `xcodegen generate`; regen separate commit; `aps-environment` re-verify.
- File-scoped commits; PR against main; merge commits only; loop merges.
- SDK API reality wins over this spec's sketches; note deltas in the PR description.

## DoD
- PR open; CLI build + suite green on the loop.
- Device pass (loop-owed): browse a live server's tools → invoke with an edited arg →
  confirm card names server+tool → result renders capped → insert lands in composer
  with provenance line → deny grant blocks with honest message.
