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
write Swift). Device target is **iOS 27 beta**, which requires **Xcode-beta4**.

## Architecture — Clean Chat Path

- **Chat** talks **directly** to the Hermes API server **Sessions API on `:8642`**
  (Bearer `API_SERVER_KEY`). `POST /api/sessions` → id at **`.session.id`**;
  `POST /api/sessions/{id}/chat` (sync) → `.message.content`; `/chat/stream` is SSE.
- **Sensors** go through the dylan-buck shell + **relay `:8000`** + connector, plus the
  **models shim `:8765`**. Independent of chat.
- **Two machines, all over Tailscale:**
  - **OJAMD** (Windows, `100.110.102.59`) — the production host the phone talks to.
  - **Mac Mini M4** (`100.79.222.100`) — always-on dev box: Xcode beta toolchain, the repo, a local
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
endpoint** (`/openapi.json`, `/v1/files`, `/api/files`, `/files` all 404 — re-verified
2026-08-02 on a CURRENT 0.19.1 process; Hermes DOES ship an `/api/files` family but it lives
in the **dashboard app**, `web_server.py` :9119, dashboard auth — a separate app from the
`:8642` api_server the phone speaks; don't mistake dashboard routes for chat-plane routes,
see #21/#223). Durable host-side
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
- **Shim `:8765`** — `TalariaModelsShim` (**NSSM service**, not a scheduled task).
- **Gateway/API server `:8642`** — **NOT a service and NOT a scheduled task.** It runs as
  Owen's user `pythonw` process (`hermes gateway run`) and answers ~15–20s after start.
  **Do NOT `Start-Service HermesGateway`** — no such service exists, and its absence does
  **not** mean chat is down. Check the port owner instead:
  `Get-NetTCPConnection -State Listen -LocalPort 8642 → OwningProcess`. The API server is a
  **gateway adapter**, not standalone — `hermes gateway run` serves the API server + all
  enabled platforms (Discord, etc.) in **one** process. Discord is one token away.
- **Connector** — a plain bat-launched process (`O:\Hermes\Talaria\scripts\start-connector.bat`,
  logs to `connector\logs\connector.log`, `PYTHONUTF8=1`). Unsupervised, unlike relay and
  shim: that supervision gap is **OPEN_ITEMS #113**. `restart-relay.ps1` in
  `C:\Users\Owen\.hermes\scripts\` does `Restart-Service HermesMobileRelay` then the bat.
- **OPS:** `Start-Service HermesMobileRelay` / `Start-Service TalariaModelsShim` need
  elevation (Owen pastes). Use `~/.hermes/scripts/hermes-update-safe.ps1`, never bare
  `hermes update`. **Do NOT run `hermes gateway install` on Windows** (creates a conflicting
  login-only task).
- **Diagnostic discipline:** verify OJAMD against live state — port listeners, DB rows,
  relay logs — never by text-matching a project-knowledge snapshot, which lags.
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
- **NEVER claim a `:8642` route from a `web_server.py` grep — read
  `gateway/platforms/api_server.py`'s `_http_route_table()`, which is the whole list.**
  **This rule exists because it was learned the hard way on 2026-08-02** (the #21
  paragraph above and the two-web-apps memory were both written that day, at 04:22, by the
  investigation session that caught it — they did *not* predate the mistake): an
  `/api/files` + `/api/model/*` "discovery" was filed into three tracker items, a dispatch
  brief, and an external audit before live probes killed it. The dashboard app (`hermes_cli/web_server.py`,
  **:9119**, dashboard auth) and the api_server the phone speaks (**:8642**) are different
  apps with different route tables; the dashboard's 129 routes are not the gateway's.
  **The complete `:8642` table, verified 2026-08-02 against a fresh 0.19.1 process:**
  `/health{,/detailed}` · `/v1/health` · `/v1/models` · **`/api/model/options` (the ONLY
  `/api/model/*` route — there is no `/info`, `/recommended-default`, `/auxiliary`, or
  `POST /api/model/set`)** · `/v1/capabilities` · `/v1/skills` · `/v1/toolsets` ·
  `/api/sessions*` (incl. `chat`, `chat/stream`, `fork`, `messages`, and
  `POST /api/sessions/{id}/model` = the session pin) · `/v1/chat/completions` ·
  `/v1/responses*` · `/api/jobs*` · **`/v1/runs*` incl. `POST /v1/runs/{id}/approval`
  and `/stop`** · `/api/platforms/{p}/events` · `/api/cron/fire`. **No `/api/files`, no
  `/api/fs`, no `/api/config`, no `/api/chat/image-upload` — those are dashboard-only.**
- **A stale gateway process is a REAL hazard, but it was NOT the cause of those 404s.**
  A long-lived `hermes gateway run` imports its modules at start, so updating Hermes leaves
  the old code serving until a restart — on 2026-08-02 the Mac listener was PID 28104 from
  **Jul 29** under a **0.19.1** install, 3d 14h uptime, which is worth knowing on its own.
  **But restarting it changed nothing**: the same routes 404'd from a 68-second-old 0.19.1
  process, because they were never on this plane. **Check the process when versions are in
  question — `ps -p $(lsof -nP -iTCP:8642 -sTCP:LISTEN -t) -o lstart=,etime=` — and check
  the route TABLE when routes are in question. Reaching for the first explanation that fit
  is what cost a day here.**
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
- **#24f is DEAD — never cite it as a cause.** The relay is DB-backed
  (`O:\Hermes\Talaria\relay\hermes_mobile.db`); there is no JWT signing secret and no
  in-memory device registry, and the registry survives restarts (verified across 4+ relay
  restarts). The live transport concern is **#54** (connector WS reconnect / nonce).
- **ATS is already scoped, and `NSAllowsLocalNetworking` is a FALSIFIED "fix".**
  `NSAllowsArbitraryLoads` was removed by **#166b** (PR #138, commit `d3c962d`,
  2026-07-22) and replaced with
  a range-scoped `NSExceptionDomains` entry keyed by the Tailscale CGNAT CIDR
  `100.64.0.0/10` (`project.yml`). The CIDR-as-domain-key form looks invalid but was
  adopted only after a four-arm controlled experiment (`OPEN_ITEMS.md` #166b, 2026-07-22)
  run **inside the app test host on the shipping toolchain — sim, not device**, which is
  what makes it trustworthy: `URLSession` there obeys the real plist, whereas `curl` does
  not exercise ATS at all. Arms: no exception → tailnet HTTP blocked −1022;
  **`NSAllowsLocalNetworking` → still blocked, CGNAT is not "local" to ATS**; the CIDR
  form → both gateways allowed; an outside-range negative control (`1.1.1.1`) → still
  blocked, so the exception does not leak globally. **So do not "narrow to
  `NSAllowsLocalNetworking`" — that arm was tested and it breaks every tailnet
  connection the app makes.** Nothing here is owed
  before submission. Consequence to know: hosts outside `100.64.0.0/10` — LAN IPs,
  MagicDNS names — have **no** exception and are ATS-blocked app-wide. `README.md` and
  `SECURITY.md` carry the same evidence; this line was wrong from 2026-07-22 until
  2026-08-01 and its bad advice propagated into a device-pass note before an external
  audit caught it. **Read `project.yml`, not a summary of it** — and note that writing
  *this* correction still produced two wrong borrowed facts (a sim experiment called
  "on-device", and 07-23 for a change git dates 07-22), both caught only by going back to
  the artifact a second time. Dates come from `git log`, not from a tracker header.

## Build / tooling

- **Xcode-beta4** (`/Applications/Xcode-beta4.app`, Xcode 27.0 build 27A5228h) is the
  standard toolchain for iOS 27 targets (per Owen, 2026-07-20; verified same day — full suite
  931/84 green on its SDK); release Xcode can't build iOS 27.
  `DEVELOPER_DIR=/Applications/Xcode-beta4.app/Contents/Developer` in every shell.
  `Xcode-beta.app` and `Xcode-beta3.app` were **deleted 2026-07-24** — beta4 and release
  Xcode are the only copies on disk. Command Line Tools 27 beta 4 is installed and
  `xcode-select` points at beta4, but CLT ships no iOS SDK and no `xcodebuild`, so the
  `DEVELOPER_DIR` export is still mandatory. Sim runtimes kept: **iOS 27.0 (24A5390f)** and
  **iOS 26.5 (23F77)**; seeds 24A5355p / 24A5380g were deleted the same day. The pinned sim
  UDID survived both the beta-4 runtime rebind and the seed prune — no re-pin needed.
  Team `DNL25ZFSD2`. DerivedData for **this** repo is
  `Talaria-gzpowyfsuofejnbsytskngrskzkm` — corrected 2026-07-30. The long-documented
  `Talaria-bkmofmhhchhruzcdudrizbbblrae` belongs to the OLD `~/Documents/Claude/Talaria`
  checkout (verified via each dir's `info.plist` → `WorkspacePath`), so purging it to
  clear a stale build silently does nothing here. **Every worktree gets its own hash** —
  resolve it from `info.plist`, never from memory:
  `plutil -extract WorkspacePath raw ~/Library/Developer/Xcode/DerivedData/Talaria-*/info.plist`.
  **`test-without-building` will happily re-run a stale `.xctest`** and report a green
  suite at the OLD test count (this cost a bogus "verified green" on 2026-07-30) — after
  editing tests, confirm the reported count MOVED, and if it did not, purge
  `<dd>/Build/Intermediates.noindex` and run plain `test`.
- **THE GATE — run `scripts/mac/lane-gate.sh` before opening any PR.** One command;
  runs the Debug suite (units + XCUITest) **and a Release build**, and requires a
  POSITIVE success marker from each. `--release` / `--suite` narrow it. Release is in
  there because #218: `main` could not build in Release for two days and every check
  we had was Debug, so 1461 green tests proved nothing. **The gate is verified to
  fail** — the #218 bug was re-injected and it caught all three errors.
- **CLI compile check:** `xcodebuild -project Talaria.xcodeproj -scheme Talaria
  -configuration Debug -destination 'generic/platform=iOS Simulator' build
  CODE_SIGNING_ALLOWED=NO`. Long builds exceed the 4-min MCP cap — run backgrounded
  (`nohup … &`) and poll the log. The gate script is the same trap: it takes minutes,
  so background it and poll rather than blocking a tool call on it.
- **Device deploy:** Xcode MCP bridge `RunProject(tabIdentifier:"windowtab1")` builds +
  installs + launches on **whoGoesThere** (iPhone, iOS 27 beta). `GetConsoleOutput` reads
  device logs. The bridge can't drive physical-device UI. After `xcodegen` regen, RunProject
  may hit a "project modified on disk" modal — stop app / dismiss / retry.
- **OTA deploy over Tailscale (proven 2026-07-27)** — THE remote deploy path when the phone
  is not on the home LAN (Owen at work). `scripts/mac/ota-stage.sh <branch>` on the Mac
  Mini: worktree → headless archive → dev-signed export (`method: debugging`, automatic
  signing, unlocked login keychain) → stages ipa + manifest into
  `~/.talaria-ota/serve_root`. Phone installs from Safari at
  `https://owens-mac-mini.tail5663a6.ts.net` (itms-services; real TLS via
  `tailscale serve --bg 8477`, which persists in tailscaled state; the
  `com.talaria.ota-http` LaunchAgent keeps the local file server alive across reboots).
  Dev-signed **upgrade-install in place** — same bundle id, app data persists. Install-only:
  no debugger attach, no console. **Do not relitigate Xcode-native wireless over the
  tailnet:** connect-by-IP was removed from Xcode entirely (Apple DTS, forums thread
  805833), CoreDevice discovery needs LAN multicast Tailscale can't carry, and the phone's
  lockdown (62078) + RemotePairing ports do not listen on its Tailscale interface — so
  pymobiledevice3-over-tailnet is equally dead (verified 2026-07-27).
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

## Measurement discipline (#215 — the rule that cost the most to learn)

**A battery rate is a PRODUCTION rate only if the row was ROUTED.** Production
classifies every turn first (`routeNeedsDeviceTool`), and a turn routed toolless
gets **no belt at all**. An unrouted cell arms every trial by construction, so on
any prompt the router would send toolless it is measuring a configuration the app
never enters.

- The dozens of **grab rates and "I cannot…" rates across the #200-series are
  valid CELL CONTRASTS and are not production facts.** They are left un-annotated
  on purpose — the contrasts still hold, and rewriting them would obscure what was
  actually measured. Read them as "cell A vs cell B, armed," never as "the app
  does this."
- Measured 2026-08-01, run `F486F103`, same four prompts, same build: the unrouted
  control posted **6/10 grabs plus 4/10 disclaimer tics — zero clean composition
  turns.** The routed cell posted **10/10 clean, 0 grabs** (p = 1.08e-05). Creates
  were **10/10 in both** arms.
- **So routing is a no-op on device-request prompts and decisive on composition
  prompts.** Adding routing to a battery whose prompts are all device requests
  (read-tool, motion) will not move its numbers — don't spend a device run
  expecting it to.
- What routing does NOT excuse: **over-serving on turns it CORRECTLY arms**
  (tool chaining, the `lookupContact` spiral). Those numbers were never inflated
  by this and are the real remaining work.

`runActionBattery`'s `routed-production` cell is the routed arm. Every other
wrapper is still unrouted.

**Where it lives (#216, 2026-08-01):** the battery and the DEBUG instruments were
split out of `LocalChatBackend.swift` (5,727 → 1,826 lines) into
`LocalChatBackend+Battery.swift`, `+Harnesses.swift` and `+IntentRouting.swift`.
Pure code motion. Because Swift's `private` is FILE-scoped, the production
members those files reach are now `internal` and tagged **`// harness-visible`**
— that tag means "private in spirit, widened only for the harness"; grep it
before assuming a member is part of any real interface.

**Where the BARS live (convention change, recorded 2026-08-01):** lanes through
#214 pre-registered their bars in a `dispatch/` doc; `dispatch/OPUS-T27-214-scopedv2.md`
(2026-07-31) is the last one. Since then — #215, #216, #217, #217B — bars are
pre-registered **inside the OPEN_ITEMS entry**, before the run, and each of those
entries says "bars written first" in so many words. **The rule did not change; the
vehicle did.** Bars still go in writing before the run and a missed bar is still a
falsification, not a redefinition. Write them in the OPEN_ITEMS entry; a dispatch
doc is optional and mostly useful when handing a lane to another agent. Flagged by
the 2026-08-01 external audit (§4) as undocumented drift — not a discipline lapse,
just a convention the next lane could not have inferred.

**A promoted clause is PRODUCTION CODE (#218, 2026-08-01).** When a lane promotes
a string, it moves out of the harness file in the same commit. Three promoted
instruction clauses stayed declared inside `#if DEBUG` while production read them
every turn, and **`main` could not build in Release for two days** — invisible
because the suite, corded device installs and the CLI compile check are all Debug.
Corollary, and it applies to any `#if DEBUG` or gating edit: **verify with a
Release build**, because a green Debug suite cannot see a mis-set gate.

  ```bash
  DEVELOPER_DIR=/Applications/Xcode-beta4.app/Contents/Developer xcodebuild -project Talaria.xcodeproj -scheme Talaria -configuration Release -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO
  ```

## Project history

Dated per-item history — every wave, lane, and PR previously transcribed here — lives in
`OPEN_ITEMS.md`, which is the canonical tracker and stays monolithic. The narrative
duplicate that used to sit at the end of this file was pruned 2026-07-24: it had drifted
badly, still describing merged work as "cloud-written, NOT compiled" with next-session
instructions for sessions long past. Read `OPEN_ITEMS.md` for state; read this file for
standing rules. OPEN_ITEMS item numbers are a **separate sequence** from GitHub issue and
PR numbers — always disambiguate which you mean.
