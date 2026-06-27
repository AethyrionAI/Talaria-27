# CLAUDE.md — Talaria

Guidance for Claude / Claude Code working in this repo. This is the living, in-repo source
of truth (the project-knowledge snapshot may lag). `OPEN_ITEMS.md` tracks issues with dated
notes; the `*_HANDOFF.md` docs + `CLEAN_CHAT_PATH.md` carry per-session detail.

## What this is

**Talaria** is a native SwiftUI iOS client for the owner's self-hosted **Hermes** agent.
It is **forked from `dylan-buck/Hermes-iOS`**, but the upstream shell + relay are retained
**only** for sensor ingestion + the `hermes_mobile` MCP tools. **Chat and sensors are
independent paths** — never conflate a relay/connector issue with a chat issue or vice
versa. Owen directs and tests; Claude writes all code + runs infrastructure (Owen does not
write Swift). Device target is **iOS 27 beta**, which requires **Xcode-beta**.

## Architecture — Clean Chat Path

- **Chat** talks **directly** to the Hermes API server **Sessions API on `:8642`**
  (Bearer `API_SERVER_KEY`). `POST /api/sessions` → id at **`.session.id`**;
  `POST /api/sessions/{id}/chat` (sync) → `.message.content`; `/chat/stream` is SSE.
- **Sensors** go through the dylan-buck shell + **relay `:8000`** + connector, plus the
  **models shim `:8765`**. Independent of chat.
- **Two machines, all over Tailscale:**
  - **OJAMD** (Windows, `100.110.102.59`) — the production host the phone talks to.
  - **Mac Mini M4** (`100.79.222.100`) — always-on dev box: Xcode-beta, the repo, a local
    gateway `:8642` + shim `:8765` for dev.

## SSE taxonomy (verified — Phase 0)

`run.started`, `message.started`, `tool.started`, `tool.completed`, `tool.progress`
(`tool_name:"_thinking"` = reasoning deltas, a **separate channel**), `assistant.delta`
(clean answer chunks in field `"delta"`), `assistant.completed` (final `"content"`),
`run.completed` (full transcript + **token usage**), `done`. **Reasoning is a separate
channel — never folded into the answer** (the old "thoughts fold into content" note is
stale). Token usage rides on `run.completed`, Anthropic-style
`input_tokens`/`output_tokens`/`total_tokens`.

## Agent-generated files (#21)

Files the agent produces land in its **host working dir** (`O:\Hermes\` on OJAMD) and are
**never delivered to the phone**. Sync `/chat` is prose only; the **SSE stream** surfaces a
write as `tool.started` `{tool_name:"write_file", args:{path, content}, preview:path}`
(`tool.completed` is empty). So **text files can be reconstructed client-side from
`args.content`** with no server change (#21 Tier 1). There is **no built-in file/download
endpoint** (`/openapi.json`, `/v1/files`, `/api/files`, `/files` all 404). Durable host-side
serving for binaries / other tools (#21 Tier 2) must live in **our relay sidecar**
(`O:\Hermes\Talaria\relay`) — **never a patch to Hermes core**: `curl install.sh | bash`
replaces `~/.hermes/hermes-agent` and wipes core edits, while `config.yaml`/`.env`/skills/
sessions persist.

## Model switching (shim dual-write)

Picker `apply()` = shim `POST /models/default` (the expensive-model guard can interrupt →
confirm) **then** the gateway `/model` session pin (`chat.selectModel`; slow + non-fatal).
The checkmark moves optimistically; "Refresh models" reconciles. `ModelsSettingsModel`:
`applyingModelID` drives in-flight, `pendingConfirm` = expensive guard, `errorMessage` on
failure. **The gateway pin can hang ~37s+ or indefinitely** — do not block UI on it
(see `OPEN_ITEMS.md` #9). CONFIRM only appears for shim-flagged expensive models.

## OJAMD services (windowless, reboot-proof)

- **Relay `:8000`** — `HermesMobileRelay` (NSSM service; `nssm.exe` at `O:\Hermes\nssm\`;
  uvicorn from `O:\Hermes\Talaria\relay`).
- **Shim `:8765`** — `TalariaModelsShim` scheduled task.
- **Gateway/API server `:8642`** — `HermesGateway` scheduled task. The API server is a
  **gateway adapter**, not standalone — `hermes gateway run` serves the API server + all
  enabled platforms (Discord, etc.) in **one** process. Discord is one token away.
- Tasks: **S4U principal** (runs as Owen, passwordless, survives logoff), boot + logon
  triggers, hidden `wscript` wrapper, `ExecutionTimeLimit` zero, auto-restart.
- **OPS:** changing a task to S4U or adding a boot trigger needs an **elevated** PowerShell;
  action/settings edits + start/stop are non-elevated. **Do NOT run `hermes gateway install`
  on Windows** (creates a conflicting login-only task).
- `HERMES_HOME` = `C:\Users\Owen\AppData\Local\hermes`; shim token at
  `C:\Users\Owen\.hermes\talaria_shim_token`; gateway launchers at
  `C:\Users\Owen\.hermes\scripts\`. Owen runs box-side commands in **PowerShell** (`curl`
  is an alias there — use `Invoke-RestMethod` or `curl.exe`).

## Auth

Shim accepts its dedicated token **or** the Hermes `API_SERVER_KEY` (dual-token, #14) — no
shim-token paste after a re-pair. `API_SERVER_KEY` lives at `~/.hermes/.env` (64 chars) and
works against OJAMD.

## Hard-won gotchas (do not relitigate)

- **`xcodegen generate` is mandatory** after adding/removing Swift files (explicit source
  listings, not synchronized folder groups).
- `os_log` interpolations need `privacy:.public` or they redact in Console.app; emoji can
  also trigger redaction. Console.app's default view suppresses `.info` — use `.notice`+ for
  diagnostics that must be visible. `TalariaLog` gates verbose diagnostics behind
  `UserSettings.verboseLogging` (the Developer screen toggle).
- **iCloud Private Relay** intercepts HTTP to Tailscale IPs and blocks sensor delivery —
  disable it.
- **HealthKit** needs an explicit in-app `requestAuthorization()` on every
  `SensorUploadService.start()` — Settings grants alone don't suffice.
- `Restart-ScheduledTask` doesn't exist in PowerShell 5.1 — use `Start-ScheduledTask`.
- `mdfind -name` beats `find` for locating files on the Mac Mini.
- The relay does **not** persist its JWT signing secret + device registry across restarts
  (#24f) — a restart invalidates device tokens → re-pair. App-side hard-abort softened
  (`114caf2`); server-side gap remains.
- ATS: `project.yml` uses `NSAllowsArbitraryLoads` — scope to `NSAllowsLocalNetworking`
  before App Store submission.

## Build / tooling

- **Xcode-beta** (`/Applications/Xcode-beta.app`) is required for iOS 27 targets; release
  Xcode can't build iOS 27. `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer`.
  Team `DNL25ZFSD2`. DerivedData `Talaria-bkmofmhhchhruzcdudrizbbblrae`.
- **CLI compile check:** `xcodebuild -project Talaria.xcodeproj -scheme Talaria
  -configuration Debug -destination 'generic/platform=iOS Simulator' build
  CODE_SIGNING_ALLOWED=NO`. Long builds exceed the 4-min MCP cap — run backgrounded
  (`nohup … &`) and poll the log.
- **Device deploy:** Xcode MCP bridge `RunProject(tabIdentifier:"windowtab1")` builds +
  installs + launches on **whoGoesThere** (iPhone, iOS 27 beta). `GetConsoleOutput` reads
  device logs. The bridge can't drive physical-device UI. After `xcodegen` regen, RunProject
  may hit a "project modified on disk" modal — stop app / dismiss / retry.
- **Desktop Commander** is the primary Mac Mini filesystem/shell/git tool. A persistent
  `zsh -l` (`start_process`) keeps state across `interact_with_process` calls. DC's
  `read_file`/`edit_block` UI tools have hung — prefer `cat`/`perl`/`python3` heredocs in
  the persistent shell for reads + edits.

## Design system

Tokens in `Talaria/Core/Design.swift` — note the **two** namespaces:
- `Design.Brand.*` — `accent` #54E6F0, `accentBright` #CDF8FB, `accentDeep`, **`forge`**
  amber #FFC14D.
- `Design.Colors.*` — `foreground`/`foregroundBright`, `mutedForeground`, `dimForeground`,
  `danger` #E0625F, `dangerBright` #FF8A86, `surface`, `cyanHairline`, `accentTint(_)`.

HUD components in `Talaria/Core/HUD/`: `MonoLabel`, `StatusPip`, `GlowButton` (cyan-only —
build tinted pills for amber/red), `GhostButton`, `ReactorOrb`
(`.minimal`/`.standard`/`.onboarding`/`.voice`), `HUDScreenBackground`,
`SettingsScreenHeader`, `GlassCircleButton`; modifiers `.hudPanel` / `.hudGlow` /
`.continuousRotation`; `Color(hex:opacity:)`.

## Conventions

- SwiftUI + async/await; `@Observable` models, `@Bindable` in views; four-space indent;
  `PascalCase` types/files, `lowerCamelCase` members; no force-unwraps on network code
  (Hermes nests — `.session.id`).
- **Real data only** in UI — show `"—"` where a value isn't knowable; no mocked toggles.
- **Verification-first:** honest corrections over confident guesses; mid-session corrections
  are normal and valued. The **"Questions for Owen"** header surfaces decisions.
- Issues tracked in `OPEN_ITEMS.md` (dated update notes); session continuity in
  `*_HANDOFF.md` + `CLEAN_CHAT_PATH.md`.

## Current state (2026-06-27)

- Branch `feat/settings-index-swap`. T3 Settings sub-pages 09–12 built + SYSTEM index
  swapped live in `ContentView`; dead monolith `SettingsScreen.swift` removed (#28/#30).
  Verbose Logging shipped + 27 diagnostics gated (#29). CTX meter usage now parsed (#25
  numerator done; denominator reads ~1.4× high — follow-up). All committed + pushed to
  `origin` (`ChronoRixun/Talaria`).
- #9 model-transition overlay shipped + both regressions fixed, committed (`64da247`).
- #21 **Tier 1 shipped + verified on-device** (`96b291f`): agent `write_file`/`create_file`
  writes are reconstructed from the SSE stream (`tool.started.args.{path,content}`), staged
  locally, and surfaced as a tappable `ShareLink` file bubble in the Hermes bubble (Save to
  Files / AirDrop). No server change. **Tier 2** (durable relay file-fetch route for binaries
  / non-reconstructable files) is the remaining server-side follow-up.
