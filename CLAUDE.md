# CLAUDE.md — Talaria

Guidance for Claude / Claude Code working in this repo. This is the living, in-repo source
of truth (the project-knowledge snapshot may lag). `OPEN_ITEMS.md` tracks issues with dated
notes; the local `handoffs/` notes (gitignored) + in-repo `CLEAN_CHAT_PATH.md` carry per-session detail.

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

**Theme system (2026-07-03, `design/THEME_SYSTEM_PLAN.md`):** a THEME (Deep Field /
Solar Forge / Terminal / Paper Tape) owns the whole color environment; the ACCENT is one
of three persisted slots (`cyan`/`amber`/`violet` raw values — never rename) that each
theme re-interprets, slot `.cyan` always = the theme's hero hue (Cyan Arc / Forge Amber /
Phosphor Green / Tracker Red). **All color values live in
`Shared/ThemePaletteCore.swift`** (compiled into app + widget targets); `ThemeRuntime`
(theme/accent/glow/grid/reduce-motion) resolves them live. Deep Field × cyan is
byte-identical to the pre-theming app (guarded by `DesignThemeTests`). Paper Tape is
light: root `preferredColorScheme` follows `theme.isLight`, and `hudGlow` multiplies by
`palette.glowScale` (≈0.15 on paper). **Data-driven since #49 (2026-07-05):** palettes are
`ThemePaletteDefinition` entries in `ThemePaletteCatalog` (same file) — resolution is a
catalog lookup, Terminal's accent pin (#12) is `lockedAccentSlot` data, `AppearanceTheme`
is a thin id (names from `ThemeCatalog.displayName`, `isLight`/orb/texture from palette
data), and a new theme = one `ThemeID` case + one palette definition + one
`ThemeDefinition` (+ a `WidgetTheme` case for the widget edit sheet) — no switch-arm
edits. Xcode build + `DesignThemeTests` run still owed on the Mac (see the handoff doc).

Tokens in `Talaria/Core/Design.swift` — note the **two** namespaces:
- `Design.Brand.*` — `accent`/`accentBright`/`accentDeep` (theme-resolved; Deep Field
  cyan #54E6F0/#CDF8FB), **`forge`** warning (amber on Deep Field).
- `Design.Colors.*` — `foreground`/`foregroundBright`, `mutedForeground`, `dimForeground`,
  `danger`, `dangerBright`, `surface`, `hairline`/`strongBorder` (ex-`cyanHairline`/
  `cyanBorder`), `accentTint(_)`, `scrim`, `screenGradient`, `drawerGradient`.

HUD components in `Talaria/Core/HUD/`: `MonoLabel`, `StatusPip`, `GlowButton` (accent —
build tinted pills for forge/danger), `GhostButton`, `ReactorOrb`
(`.minimal`/`.standard`/`.onboarding`/`.voice`; drawing re-skins per theme),
`HUDScreenBackground` (gradient + `ThemeTextureView` + `GridOverlay`
lines/dots/rules), `SettingsScreenHeader`, `GlassCircleButton`; modifiers `.hudPanel` /
`.hudGlow` / `.continuousRotation`; `Color(hex:opacity:)` (defined in
`Shared/ThemePaletteCore.swift`). Widgets pick a theme per instance
(`WidgetTheme`, default Match App via `HermesWidgetData.appearanceTheme` — kept in
lockstep across BOTH `HermesWidgetData.swift` copies).

## Conventions

- SwiftUI + async/await; `@Observable` models, `@Bindable` in views; four-space indent;
  `PascalCase` types/files, `lowerCamelCase` members; no force-unwraps on network code
  (Hermes nests — `.session.id`).
- **Real data only** in UI — show `"—"` where a value isn't knowable; no mocked toggles.
- **Verification-first:** honest corrections over confident guesses; mid-session corrections
  are normal and valued. The **"Questions for Owen"** header surfaces decisions.
- Issues tracked in `OPEN_ITEMS.md` (dated update notes); session continuity in
  the local `handoffs/` notes (gitignored) + `CLEAN_CHAT_PATH.md`.

## Current state (2026-07-07)

- **Wave 5 (GitHub #18–#19, label standalone-wave-5) built as two STACKED
  per-issue branches off main (b1a00a7), one PR each (merge order: #18's PR →
  #19's PR):** `claude/w5-18-native-voice` = #18 native fallback voice
  (`VoiceEngineRouter` + `NativeVoicePipelineService`: SpeechAnalyzer/
  SpeechDetector → the ACTIVE `ChatBackendRouter` backend per the #18
  amendment → dedicated sentence-buffered `SpeechOutputService` with
  `managesAudioSession=false`; echo cancellation via
  `setVoiceProcessingEnabled`; auto-selects when unpaired, talk unconfigured,
  or relay unreachable; honest LOCAL VOICE badging via
  `TalkSessionSnapshot.engine`; native sessions skip the post-to-Hermes
  transcript context turn; OPEN_ITEMS #73). `claude/w5-19-carplay-voice` =
  #19 CarPlay upgrade (auto-start on connect gated on `canStartSession` with
  a blocked state, `withObservationTracking` replaces the 500ms Timer,
  `.carAudio` category re-assert in the WebRTC engine, verified
  `com.apple.developer.carplay-voice-based-conversation` key added locally;
  Apple grant NOT filed — sim validation first; OPEN_ITEMS #74).
  **Cloud-written, NOT compiled, NOT sim/device-verified.** Next Mac
  session: merge in order, `xcodegen generate` (2 new source + 2 new test
  files; re-verify aps-environment/weatherkit/CarPlay keys survive regen per
  #44/#48), CLI build + tests, then the #73/#74 checklists (relay-down +
  airplane-mode local-voice bar for #18; CarPlay Simulator pass for #19).
- **Wave 4.5 (GitHub #26–#31, label standalone-wave-4.5) built as six STACKED
  per-issue branches off `claude/talaria-wave-4-5-sg7kdj` (6332869), one PR
  each, each based on the previous** (merge order: #32 → #33 → #34 → #35 →
  #36 → #37): PR #32 = #26 `LocalChatBackend` (FoundationModels behind
  `HermesClientProtocol`; runtime `contextSize`; cumulative-snapshot →
  `textDelta` diffing; deterministic condensation via the
  LocalIntelligenceService trimming helpers, now internal; OPEN_ITEMS #67).
  PR #33 = #27 `ChatBackendRouter` (two brains one seam; never-configured →
  local, Hermes wins when keyed, per-message routing, no mid-thread swap;
  `Message.brain` transcript tags; header brain chip + picker; #68). PR #34 =
  #28 device tool belt (read tools on `ToolEventRelay` →
  `StreamingUpdate.toolActivity`; WeatherKit entitlement in its own surgical
  commit; the issue's "FM built-ins" DON'T exist in the framework — Vision/
  CoreSpotlight implementations instead; #69). PR #35 = #29 action tools +
  `ToolConfirmationCenter` (awaited-continuation confirm gate, defaults
  closed; #70). PR #36 = #31 standalone onboarding (pairing wall removed;
  pairing lives in Settings as the upgrade; honest Apple-Intelligence-off
  state; notification priming moved to first long-run; #71). PR #37 = #30
  PCC tier (a MODE of LocalChatBackend behind `#available(iOS 27)` +
  availability gates; picker entry + quota UI + escalation offer + honest
  degradation; externally blocked on Apple approval — merges behind gates;
  #72). **Cloud-written, NOT compiled or device-verified.** FoundationModels
  names verified against Apple's live SDK-doc JSON 2026-07-07 (incl. the
  27-beta surface), not the installed SDK — compile-risk shortlists in each
  PR. Next Mac session: merge the stack in order, `xcodegen generate`
  (14 new source + 5 new test files; re-verify `aps-environment` AND the new
  `com.apple.developer.weatherkit` survive regen per #44/#48), CLI build +
  tests, then the per-item device checklists in OPEN_ITEMS #67–#72
  (airplane-mode bar for #26/#28).
- **Wave 4 (GitHub #13–#17) built as five per-issue branches off this branch's
  tip (656dee2), one PR each into `claude/wave-4-issues-13-17-qu38px`:**
  PR #20 = #13 stale-test fixes (test-only, OPEN_ITEMS #62); PR #22 = #14
  BGAppRefreshTask + BGContinuedProcessingTask background wake (#63); PR #21 =
  #15 widget-side HealthKit queries via new `Shared/HealthQueryCore.swift`
  (#64); PR #23 = #16 AlarmKit `/alarm` executor behind the in-app confirm
  gate (#65); PR #24 = #17 Spotlight IndexedEntity donation + OpenSessionIntent,
  toggle default OFF (#66). **Cloud-written, NOT compiled or device-verified** —
  next Mac session: merge the PRs (project.yml/Info.plist edits from #14/#15/#16
  land in different hunks), `xcodegen generate` (9 new files; re-verify
  `aps-environment` + the new widget HealthKit entitlement per #44/#48), CLI
  build + tests, then the per-item device checklists in OPEN_ITEMS #62–#66.
  New-API compile risks flagged in the PRs: AlarmKit configuration/presentation
  shapes (#16), `BGContinuedProcessingTaskRequest` (#14), `indexAppEntities`
  (#17).
- **Wave 2 (Issues E–H / GitHub #6–#9) built on `claude/issues-5-8-batches-cue3vb`**
  (AethyrionAI/Talaria-27): Ask Hermes App Intent (OPEN_ITEMS #56), attachment
  text-inlining + explicit Extract Text OCR closing the #43 silent drop (#57), Control
  Center / Lock Screen controls (#58), voice-memo attachments (#59). **Cloud-written,
  NOT compiled or device-verified** — next Mac session must `xcodegen generate`
  (re-verify `aps-environment`, #44/#48), run the CLI build + tests, and work the
  per-item checklists in OPEN_ITEMS #56–#59. The iOS 27 beta LongRunningIntent adoption
  is parked behind the undefined `TALARIA_IOS27_INTENTS` flag; the delimited text-part
  surface lives in `Services/Support/AttachmentInlining.swift` (shared by #57 file
  inlining and #59 transcripts).
- **Wave 3 built on `claude/wave-3-on-device-intelligence-rxht4l`** (Wave 2 merged in):
  on-device intelligence. 4.15: `_thinking` reasoning deltas forwarded as
  `StreamingUpdate.reasoningDelta` → live line in the streaming placeholder + collapsed
  REASONING chevron on the bubble (raw text persisted on `Message.reasoning`; the exact
  `tool.progress` delta key still needs a device probe — tolerant parser + wire-mode
  hedge, OPEN_ITEMS #60). 4.8: `LocalIntelligenceService` (FoundationModels) generates
  `{title, preview}` after the first completed exchange → `setConversationTitle` +
  `Conversation.generatedPreview`; truncation fallback off-AI-hardware; reasoning
  condensed to one line when foregrounded (OPEN_ITEMS #61). Adversarially reviewed
  same-session (10 findings fixed — see the #60/#61 update notes). **Not yet compiled** —
  next Mac session: `xcodegen generate` (1 new source file + 2 test files), CLI build,
  device verify.

## Prior state (2026-07-03)

- **Theme system built on `claude/theming-options-plan-c4356l`** (#49): four themes ×
  three accent slots, palette core in `Shared/`, textures, per-theme orbs, theme picker,
  themed widgets with per-instance selection. **Not yet compiled or device-verified** —
  written in the cloud session without Xcode; next Mac session must `xcodegen generate`
  (project.yml now declares `aps-environment`, closing the #44/#48 strip trap), run the
  CLI build, fix any stragglers, and verify Deep Field is pixel-identical on device.
- Branch `feat/settings-index-swap`. T3 Settings sub-pages 09–12 built + SYSTEM index
  swapped live in `ContentView`; dead monolith `SettingsScreen.swift` removed (#28/#30).
  Verbose Logging shipped + 27 diagnostics gated (#29). CTX meter usage now parsed (#25
  numerator done; denominator reads ~1.4× high — follow-up). All committed + pushed to
  `origin` (`ChronoRixun/Talaria`).
- #9 model-transition overlay shipped + both regressions fixed, committed (`64da247`).
- #21 **Tier 1 shipped + verified on-device** (`96b291f`): agent `write_file`/`create_file`
  writes are reconstructed from the SSE stream (`tool.started.args.{path,content}`), staged
  locally, and surfaced as a tappable `ShareLink` file bubble in the Hermes bubble (Save to
  Files / AirDrop). No server change. **Tier 2 relay route** (`ccf6e5a`, branch
  `feat/agent-files-tier2`): `GET /v1/device/files` — device-bearer auth, whitelisted to
  `AGENT_FILES_DIR` (`O:\Hermes\MobileDL` on OJAMD), traversal-safe, `FileResponse`. Tested
  (8 + 55 suite) and **deployed + live on OJAMD** (health 200, route 401-gated). **Tier 2
  app-side fetch** is the remaining piece — blocked on probing the binary-write SSE shape
  (does a non-text `write_file` carry `args.content`?), which decides the fetch trigger. See
  `OPEN_ITEMS.md` #21 (full plan), #36 (OJAMD↔fork reconcile), #37 (upstream connector win32 fix).
