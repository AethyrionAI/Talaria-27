# MCP_CLIENT_DESIGN — Talaria as an MCP client (OPEN_ITEMS #150)

**Author:** Claude (Mac session, 2026-07-20 late) · **Status:** DESIGN GATE — reviewed by
Owen before any implementation lane dispatches. · **Scope:** post-launch 1.1 marquee.
Capability claims below are cited or marked OPEN QUESTION; nothing is guessed.

## 0. The record correction is binding

Per #150's correction (Owen, 2026-07-20): the on-device brain is the ~3B FoundationModels
instruct model — the one that phrase-loops and degenerates cards (#61/#102). Free-tier
ceiling: NARROW, GUIDED SINGLE-TOOL use — one tool, clear trigger, schema-constrained args
via guided generation (prevents malformed calls; grants no planning). Fetch-and-summarize,
not orchestration. Every section below is written inside that ceiling.

## 1. What already exists (design against it, not around it)

This design plugs into shipped machinery rather than inventing parallel systems:
- **#69 device tool belt** — `Talaria/Services/Live/DeviceTools/` holds Swift `Tool`
  conformances handed to the local brain's `LanguageModelSession`; `ToolEventRelay`
  bridges invocations onto `StreamingUpdate.toolActivity` so the existing chip UI renders
  tool calls with zero ChatStore changes. MCP tools become additional belt members.
- **#70 `ToolConfirmationCenter`** (device-verified PASS) — the shared confirm gate:
  staged card, awaited continuation, gate-defaults-closed, editable fields, auto-decline
  of concurrent requests. MCP side effects route through THIS. No new gate is designed.
- **#67/#68 LocalChatBackend + ChatBackendRouter** — the two-brain seam. Context window
  read at RUNTIME (`SystemLanguageModel.contextSize`: 4096 baseline, 8192 on iOS 27
  hardware — per `IOS27_NATIVE_CAPABILITIES.md`, never hardcode).
- **#114/#116 honest-probe pattern** — two-step probe + pure classifier
  (`ServerSettingsScreen` / `ServerSettingsTests`), and `KeychainSecureStore` +
  `BackendProfileScopedKeys`-style profile-scoped secret storage.
- **project.yml already ships an SPM package** (WebRTC under `packages:`) — adding a
  package is a proven pattern in this build, not new infrastructure.

## 2. Transport + SDK — VERDICT: adopt the official Swift SDK

- stdio is impossible on iOS (no subprocesses); **Streamable HTTP is the transport**
  (MCP spec 2025-03-26+, current 2025-11-25).
- **Adopt `modelcontextprotocol/swift-sdk`** via SPM (`.package(url:
  "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.11.0")`, MIT).
  Verified from the repo README + source (2026-07-20): `Client` actor with
  `listTools()` / `callTool()` / `listResources()` / `readResource()`;
  `HTTPClientTransport` implements the Streamable HTTP spec with SSE streaming on
  Apple platforms (Linux-only caveat does not apply to us); a `requestModifier`
  closure customizes outgoing requests — that is the per-server auth-header
  injection point. SDK tracks spec 2025-11-25.
- Hand-rolling is rejected: the protocol surface (initialize/capabilities/tools/
  resources/notifications) is large enough that a minimal client would grow into a
  bad SDK. The SDK is official and actively maintained.
- **OPEN QUESTION (Lane A compile gate resolves):** exact iOS minimum of the current
  release and interplay with the app's Swift 6 region-isolation settings. Cheap to
  answer — Lane A's first Mac build is the test. Fallback if it fails to compile on
  the 27-beta toolchain: pin an older tag, or raise at loop time before writing code
  around it.

## 3. Server registry + settings UX (Lane A)

- `Services/Support/MCPServerRegistry.swift` — `@Observable` store. Non-secret
  metadata (id, display name, URL, enabled flag) persists in UserDefaults; bearer
  token per server in Keychain via `KeychainSecureStore`, profile-scoped following
  the `BackendProfileScopedKeys` naming pattern (a paired-profile wipe must take MCP
  credentials with it).
- `Features/Settings/MCPServersScreen.swift` — add/edit/remove; URL + optional
  bearer token; reachable from the server-settings area. Free and Connected tiers
  both get this screen (managing servers is not the gated capability; using them
  through a brain is).

- **Honest probe, #114/#116 semantics:** step 1 plain HTTP reachability; step 2 MCP
  `initialize` + `tools/list` through the SDK. Pure classifier
  `classifyMCPProbe(reachability:initializeStatus:toolCount:)` → UNREACHABLE /
  NO AUTH / ONLINE (n tools) — unit-testable without a network, same as the shim
  probe. No auto-connect at app launch; probes run on screen entry or user action.
  Servers being down degrade silently everywhere else (#136 posture: never a
  launch or chat-plane blocker).

## 4. Tool approval + trust model (Lane B)

- **Server-declared metadata is untrusted.** MCP `readOnlyHint` annotations and tool
  descriptions come from the server; they inform DISPLAY only, never gating. Every
  MCP tool invocation is treated as side-effect-capable.
- **Manual invocation gates through `ToolConfirmationCenter`** — the staged-card /
  awaited-continuation / defaults-closed mechanics from #70, unchanged. The card
  shows server, tool, and the exact arguments (editable where sensible).
- **Grant store** (`MCPToolGrantStore`): per-server-per-tool decisions — once /
  session / always / deny — mirroring Hermes 0.19 smart-approval choice semantics
  (#148). "Always" persists; revocation lives on the server's settings screen.
  Grants reduce repeat friction for MANUAL invocation in Lane B; model-driven
  invocation (Lane C) always confirms regardless of grants in its first version.
- **Tool results are DATA, never instructions.** Results render as content and can
  be inserted into a conversation as quoted context; nothing in a result can
  trigger another tool call or setting change. (Same rule the app applies to
  Hermes tool output.)

## 5. Split execution honesty (Connected tier) — and the tier inversion

**Finding that reshapes the tiers:** in Connected chats the HOST model reasons — and
the host cannot call phone-local MCP tools today. That transport (host agent → relay →
phone executes → result back) does not exist; it is real two-sided plumbing adjacent
to #143/#54, and it is deliberately NOT designed here — it becomes its own post-1.1
design doc (Lane D placeholder) once the value is proven.

That inverts the naive tier story: **model-driven MCP arrives free-tier-first** (the
local brain can hold MCP tools in its belt today; the host model cannot reach them
until Lane D). The Connected tier's near-term MCP value is Lane B's manual surface:
browse tools, invoke with confirmation, insert results into the Hermes conversation
as context. The #150 "game changer" claim stays scoped to Connected — it cashes out
at Lane D, not before, and this doc says so plainly rather than promising it early.

## 6. Free-tier guided single-tool flow (Lane C — the correction's ceiling)

- **The FM impedance problem (central OPEN QUESTION):** FoundationModels tool calling
  takes Swift `Tool` conformances with compile-time `@Generable` argument types; MCP
  tool schemas are runtime JSON. Resolution options, in preference order:
  1. **Curated shape (v1 recommendation):** the user exposes ONE chosen MCP tool to
     the local brain; it surfaces as a fixed-shape Tool whose `@Generable` arguments
     are a single `query: String` (plus the tool name baked into instructions). The
     bridge maps `query` onto the MCP tool's primary string parameter. This is
     exactly the fetch-and-summarize ceiling — guided generation constrains the
     call shape; no orchestration is implied or possible.
  2. iOS 27 Dynamic Profiles / dynamic tool declaration, IF the installed 27-beta
     SDK permits runtime-declared tool schemas (`IOS27_NATIVE_CAPABILITIES.md`
     mentions Dynamic Profiles; whether they accept runtime schemas is UNVERIFIED —
     check against the beta SDK on the Mac before Lane C is specced).
  3. JSON-string passthrough arguments — rejected: abandons guided generation, the
     one thing keeping the 3B model's calls well-formed.
- **Budgets (hard numbers, #61/#102 evidence):** context is 4096/8192 tokens TOTAL,
  runtime-read. Tool schema + instructions overhead budgeted ≤ ~300 tokens (one tool
  only — this is a context constraint as much as a capability one); tool RESULT
  hard-capped ≈ 1,500 tokens with an explicit truncation marker in the result text;
  over-budget results truncate at word boundaries, never error. Temperature and
  degeneration guards follow Lane H's degenerate-card guard pattern.
- One MCP call per user turn, maximum. No chaining.

## 7. Capability matrix (binding)

| Capability | Free | Connected |
|---|---|---|
| Manage MCP servers (add/edit/remove, Keychain creds, probe) | ✅ Lane A | ✅ Lane A |
| Browse tools/resources; manual invoke via confirm gate; insert results into chat | ✅ Lane B | ✅ Lane B |
| Model-driven MCP tool use | ONE curated guided tool, 1 call/turn (Lane C) | ❌ until Lane D (host↔phone transport) |
| Multi-tool orchestration / planning | ❌ (correction: 3B grants no planning) | Lane D only, host model |

Arguing the free tier above this matrix requires new evidence against #61/#102 and
goes in a marked appendix of a future revision — not in implementation lanes.

## 8. Risks + posture

- **App Review:** user-configured HTTP services = standard client territory
  (precedent: every DB client / RSS reader / home-automation app). No bundled server
  list, no store transactions through MCP. Low risk; note it in review notes.
- **Background execution:** none in v1 — MCP calls run foreground, inside a turn or
  a settings action. No BGTask, no silent network.
- **Hostile/compromised server:** results are data (see §4); size caps (§6); probe
  never auto-runs at launch; per-server enable flag is a kill switch.
- **Credentials:** Keychain only, profile-scoped, wiped with the profile; never in
  UserDefaults, logs, or exports.
- **Sessions-API reference:** a working MCP client against Hermes lives at
  `design/reference/hermes-sessions-mcp-server.py` (frozen snapshot; canonical copy
  is an out-of-repo dev tool) — useful for auth-resolution and timeout-envelope
  patterns (warm ≈12s, cold ≈21s first token on Hermes hosts).

## 9. Lane plan

- **150A — registry + settings + SDK dep + honest probe.** Dispatched:
  `dispatch/FABLE-T27-150A-mcp-registry-probe.md`. Deliberately front-loads the SPM/
  xcodegen/Swift-6 compile risk.
- **150B — tool browse + manual invocation + grants + confirm-gate routing.**
  Dispatched (send AFTER 150A merges): `dispatch/FABLE-T27-150B-mcp-tools-approval.md`.
- **150C — free-tier local-brain wiring.** NOT yet specced; blocked on §6's OPEN
  QUESTION (verify Dynamic Profiles vs curated shape against the beta SDK first).
- **150D — Connected split execution.** Placeholder only; own design doc, post-1.1.
