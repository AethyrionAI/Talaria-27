# Talaria — Phase B Handoff (for Claude Code)

Session: 2026-06-21 (continued) · Branch: `feat/phase-b-wiring` (pushed to origin)

## Status

**Both Chat shells are now wired** (model selector + sessions drawer) and the
branch **builds green** on iPhone 17 Pro Max / iOS 26. The active task is the
**offline banner**, then runtime verification. Work on `feat/phase-b-wiring`.

Rules: conventional-commit per logical unit; verify `** BUILD SUCCEEDED **`
before each commit; never hand-edit the `.xcodeproj` (XcodeGen owns it).

## Already done — do NOT redo

- HUD redesign merged to `main` (`c2069e5`), pushed.
- **Model selector** (`173f829`, pushed): picker populates from `/v1/models`;
  tapping a model calls `switchModel` (`/model <id>` command turn) applying on
  the **next session**; picker shows an "APPLIES ON NEXT SESSION" hint +
  "Start New Session" button. Protocol gained `availableModels()` /
  `switchModel(_:)`; `ChatStore` gained `availableModels()` / `selectModel(_:)`.
- **Sessions drawer** (`6533f25`, pushed): `HermesSessionInfo` DTO +
  `listSessions()` (GET `/api/sessions`) + `openSession()` (GET
  `/api/sessions/{id}/messages`, adopts the session id, `mapStoredMessage`
  maps history → `Message`). `ChatStore.loadSessions()` / `openSession()` swap
  the active conversation. `ChatScreen.refreshSessions()` populates the drawer
  (refresh on open) and `onSelectSession` opens the thread with history.

## Task 1 (now) — Offline banner

Relay is offline by design and chat goes direct to `localhost:8642`, but the
"Hermes host offline" banner + stale model chip are relay-sourced, so they show
**falsely**. Drive the banner from the **direct Sessions API** health (the
Sessions client `connectionStatus`, or a `/health` or `/v1/models` probe)
instead of relay status.

Trace: `hostStore.connectionState`, the banner view in `ChatScreen.swift`, and
host plumbing in `LiveHermesHostService` / `RelayAPIClient`. Acceptance: when the
direct API is reachable, no false offline banner and the chip shows the live
model. Build green; one focused commit, pushed.

## Task 2 — Runtime verification of the wired shells

The build is green but the shells haven't been runtime-verified this session. On
the sim (terminate -> install -> launch):
- Drawer: lists real sessions grouped by recency; tapping one loads its history
  and continues that thread; "New Chat" still starts fresh.
- Model picker: host models populate; "Start New Session" works; chip updates.
Note: `idb` keyboard injection does NOT work in this sim — Owen types chat
messages manually, so test send-flows when he's at the keyboard. Capture a
screenshot of the drawer + picker.

## Backlog — NOT this session

- **Native model endpoints** (Owen prefers long-term): `GET /api/model/options`,
  `GET /api/model/info`, `POST /api/model/set`. Cleaner than `/v1/models` +
  `/model`-command. **Add as an option on the new Settings page when built** —
  e.g. toggle "command-turn (next session)" vs "native (immediate)".
- **Screen-tour verification**: onboarding/handshake, talk/voice, inbox,
  settings. Confirm "GPT-5.5" / "HERMES" are placeholders vs live bindings.

## Environment / build / conventions

- Repo: `/Users/owenjones/Documents/Claude/Talaria`. XcodeGen — `project.yml` is
  source of truth. Run `xcodegen generate` after any `project.yml` change or
  after adding NEW Swift files, then rebuild. Never hand-edit the `.xcodeproj`.
- Build: `xcodebuild -project Talaria.xcodeproj -scheme Talaria -destination 'id=47F68496-24F9-45D9-93D3-1C778DB6B557' build`. Require `** BUILD SUCCEEDED **`.
- Deploy: terminate -> install -> launch (install over a running app only
  foregrounds the OLD process).
- Runtime: relay OFFLINE; chat direct to `localhost:8642` (Bearer API key from
  app config). Offline banner is expected until Task 1 lands.
- Tooling: Desktop Commander (shell), `gh` (authed as ChronoRixun), `xcodegen`
  2.45.4, xc-all simulator tools.
- Commits: conventional (`feat:`/`fix:`/`refactor:`/`docs:`/`chore:`), one unit
  each, build verified first.
