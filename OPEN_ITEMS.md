# Talaria — Open Items / Follow-ups

**Compiled:** 2026-06-23 · **From:** the models-shim / Phase-B wiring session.
**Landed this session (on `main`, merge `98a9a89`):** T1 (Settings→Models dual-write
picker), T2 (regex + copy fixes), shim cache-bust. See the merge commit for detail.

Status legend: 🔧 in progress · ⛔ blocked · 💤 dormant · 🐛 bug · 📝 note / decision · ✅ done.

---

## 1. ✅ T4 — Host reconciliation (chat gateway ↔ shim) — RESOLVED

**Recon (done):** the **mini** runs *both* Hermes services on one box, sharing
`~/.hermes/config.yaml`:
- Hermes **gateway** on `*:8642` (the chat backend the app sends `/model` to).
- Models **shim** on `:8765` (the picker's model list + set-default).

`http://localhost:8642` and `http://100.79.222.100:8642` (mini tailnet IP) both reach the
gateway; OJAMD `100.110.102.59:8642` did **not** answer. So in the **simulator dev loop
the chat gateway and the shim are the same host (the mini) → coherent, no mismatch.** This
is why the dual-write's `/model` leg succeeded with a kimi model.

**Remaining gap — on-device (TestFlight):**
- The app's Hermes API base URL is currently persisted as `http://localhost:8642`. That
  only works because the simulator runs *on the mini*; on a physical phone `localhost`
  is the phone, not the mini.
- The in-code default is the **stale** `http://ojamd:8642` (the old Windows box, which
  did not respond) — see `UserSettings.defaultHermesAPIBaseURL`.
- The shim URL default is already tailnet-correct (`http://100.79.222.100:8765`).

**Decision needed before TestFlight:** point the Hermes API base URL at the mini's tailnet
address — either `http://100.79.222.100:8642` or, preferably, a `tailscale serve` HTTPS
MagicDNS name (also removes the `NSAllowsArbitraryLoads` ATS exception). Then chat +
picker are the same box from any network.

**Update 2026-06-24 (live probe from the mini, prompted by the token re-pair question):**
- **OJAMD's gateway is now up** — `http://ojamd:8642` and `100.110.102.59:8642` both
  respond (404 at root = server alive). The "OJAMD :8642 did not answer" note above is now
  **stale**. The mini's gateway is also up (`localhost:8642`).
- **The shim runs only on the mini** — `100.79.222.100:8765` → 401 (alive, needs auth);
  OJAMD has **no** shim (`ojamd:8765` / `100.110.102.59:8765` → no response).
- **App defaults split the two backends:** chat
  `defaultHermesAPIBaseURL = http://ojamd:8642` (OJAMD) but the models-shim URL =
  `http://100.79.222.100:8765` (mini) — `UserSettings.swift:228/232`. So on the physical
  phone (header "HERMES · OJAMD") chat lands on **OJAMD** while the picker's persistent-
  default write lands on the **mini** — different boxes. Re-pairing the shim token makes the
  picker authenticate, but its `POST /models/default` leg still writes the *mini's* config,
  not OJAMD's, so switches won't fully take on-device. **Consolidate** (stand the shim up on
  OJAMD + point the app's shim URL there, or point the app's chat base URL at the mini)
  before model-switching is coherent on the phone.

**Owen clarification (2026-06-24):** OJAMD is the **intended production host**; the mini was
only up incidentally (left on) and was **mid Hermes-update** during the earlier recon — which
is why OJAMD `:8642` looked dead then (being updated, not absent). The phone is connected to
OJAMD (`100.110.102.59:8642`). So the consolidation direction is unambiguous: **move the shim
to OJAMD**, not chat → mini. Concretely: deploy `tools/models-shim/shim.py` on OJAMD (Windows —
Task Scheduler / NSSM, not launchd), generate a token in OJAMD's `~/.hermes/talaria_shim_token`,
and repoint the app's shim URL to `http://ojamd:8765` (`UserSettings.swift:232` /
`ModelsSettingsScreen.swift:256`). The mini-side token re-pair (Item #22) **won't** enable real
on-device switch testing — the phone chats with OJAMD, not the mini.

**RESOLVED (2026-06-25): shim deployed on OJAMD; model-switching works end-to-end on-device.**
- **Shim ported to OJAMD** — native Windows Hermes (NOT WSL); home `%LOCALAPPDATA%\hermes`,
  gateway runs as a Windows service. `tools/models-shim/shim.py` is **byte-identical** to repo
  (sha256 `d57eef8f…84e11d`); runs under OJAMD's Hermes venv
  `C:\Users\Owen\AppData\Local\hermes\hermes-agent\venv\Scripts\python.exe` (Py 3.11.9). All four
  shim internals (`build_models_payload`, `load_picker_context`, `_apply_model_assignment_sync`,
  `_profile_scope`) import cleanly → **no version skew**.
- **Bind:** `TALARIA_SHIM_HOST=100.110.102.59` `:8765` (OJAMD tailnet IP). Token at
  `C:\Users\Owen\.hermes\talaria_shim_token` (note `~/.hermes`, *not* the Hermes home). No
  firewall rule needed — the phone reached `:8765` over the tailnet first try.
- **Persistence:** wrapper `tools/models-shim/run-shim.cmd` (sets env + logs to
  `%LOCALAPPDATA%\hermes\logs\talaria-shim.log`) launched by Scheduled Task **`TalariaModelsShim`**
  (at-logon, restart-on-failure, hidden). `O:` is a local M2 SSD, so the at-logon start is safe
  (no mapped-drive race).
- **Verified live:** picker loads the real list; three switches (Claude Haiku 4.5 → Gemini 2.5
  Flash Lite → Kimi K2.6) each took on a fresh session — the *answering* model actually changed.

**Follow-ups (small):**
- Update the **in-code shim-URL default** from the mini IP to OJAMD so future installs (Shelley)
  don't need manual entry: `UserSettings.swift:232` + `ModelsSettingsScreen.swift:256` →
  `http://ojamd:8765` (chat base URL `:228` is already `ojamd:8642`).
- **Retire the mini's launchd shim** (`com.aethyrion.talaria.modelsshim`) — now redundant and a
  source of two-shims/two-configs confusion. The phone uses OJAMD's.

---

## 2. 💤 T3 — Settings screens build (UNBLOCKED)

Needs the Claude Design deliverable: the 8-screen **`Settings.dc.html`** (from
`TalariaSettings.zip`) placed at **`design/Settings.dc.html`** in the repo. Then build the
6 non-MODELS screens (01 SYSTEM, 02 UPLINK, 05 VOICE, 06 APPEARANCE-HUD, 07 SESSIONS,
08 DIAGNOSTICS). MODELS (03/04) is already done (T1).

**Unblocked (2026-06-25):** `design/Settings.dc.html` + `design/support.js` placed in repo
(byte-perfect copy from the Claude Design canvas export in Downloads). Ready to build.

**Built (2026-06-26):** SettingsScreenHeader (shared) + UPLINK (02), SESSIONS (07),
DIAGNOSTICS (08), APPEARANCE (06, +4 persisted `UserSettings` fields), and the SYSTEM
index (01). VOICE (05) cut. All build clean on simulator; reachable on-device via temporary
"(T3 preview)" links in `SettingsScreen`. Landed to `main` (merge `a69e5bf`); big-work
branch `feat/settings-index-swap` cut for the rest.

**Remaining T3 work (on `feat/settings-index-swap`):**
1. Build the 4 Claude-Design "additional pages" — RELAY (09), NOTIFICATIONS (10),
   PRIVACY (11), DEVELOPER (12, DEBUG-only) — from `design/Settings-Additional.dc.html`,
   homing the sections the index doesn't cover (relay config, auto-connect, notifications/
   haptics, location, permissions, environment) so nothing is orphaned.
2. Wire each new page as a row into its SYSTEM-index group.
3. The swap: point `ContentView`'s settings sheet at `SystemSettingsScreen` and delete
   the five temp preview links from `SettingsScreen`.

**Build-truthfulness rule (Owen, 2026-06-26):** anything Claude Design mocked that isn't
what the app actually does must be adjusted to the truth — real data only, `—` where a
value is unknowable. Adjustments already identified:
- **Health** permission row can't show a real read-auth status (iOS hides HealthKit read
  grants) → `—` / share-only state, not WHILE-USING-style values.
- **Developer `// BUILD` commit hash** isn't available at runtime → needs a build-time
  Info.plist injection (Run Script → e.g. `GIT_COMMIT`) or `—`. Version/build are real.
- Map all placeholders to real state: per-permission vocab (Notifications is authorized/
  denied/provisional, not "ALWAYS"), Developer env host labels, the Notifications hero
  summary (derive from real toggle states), relay/device readouts.

---

## 3. 📝 xcodegen needed when adding/removing source files

This project's generated `.xcodeproj` lists every source file **explicitly** (no Xcode
synchronized-folder groups). Editing existing `.swift` files needs nothing, but **adding
or removing** files requires `xcodegen generate` + committing the regenerated
`project.pbxproj` — otherwise new files don't compile in. (This is why it hadn't been
needed since project setup: no files had been added since.)
**Optional improvement:** enable synchronized folder groups so new files auto-include.

---

## 4. 💤 Expensive-model confirm guard (wired, dormant)

The app handles the shim's `{ok:false, confirm_required:true, confirm_message}` response
(→ confirm dialog → re-POST with `confirm_expensive:true`). This comes from the shim
(`tools/models-shim/shim.py`, committed `e019415`) wrapping Hermes's own
`hermes_cli.model_cost_guard.expensive_model_warning` — not Dylan's shell, not new app
scope. It is currently **dormant**: on this box `expensive_model_warning` returns nothing
for opus / deepseek-pro, so the dialog can't be triggered live. Revisit if/when the box's
cost-guard is enabled.

---

## 5. ✅ Host-status display quirk — Settings now uses direct connection state

Settings was reading `hostStore.connectionState` (relay-based) while chat used
`chatStore.directConnectionStatus` (direct Sessions API). When the relay was down but
chat worked, Settings showed "OFFLINE · STANDBY" while chat was fully operational.

**Fixed 2026-06-25:** Added `effectiveConnectionState` to SettingsScreen that prefers
the direct Sessions API probe over the relay-based host store — same pattern ChatScreen
uses. All 6 references to `hostStore.connectionState` updated.

---

## 6. 📝 config.yaml provider normalization (acknowledged)

The shim's set-default writes the canonical slug, so `config.yaml`'s `provider` changed
`kimi-for-coding` → `kimi-coding` (same provider). Cosmetic; left as-is per Owen.

---

## 7. 📝 DEBUG shim-token launch-env seam (informational)

`ModelsShimClient`'s token provider falls back to a `TALARIA_SHIM_TOKEN` launch-env var in
**DEBUG only** (for simulator verification without idb keyboard injection). Production reads
the Keychain (`talaria.modelsShimToken`) only. No token in git.

---

## 8. 📝 TestFlight (future gate)

On-device + HealthKit work is gated on a TestFlight build. Ties to item 1 (base URL) and
the `tailscale serve` HTTPS work. Add Shelley as the second tester when ready.

---

## 9. 📝 Model-selection waiting / transition animation (needs Claude Design)

When a model is tapped, the dual-write runs: shim `POST /models/default` **and** the
gateway `/model` pin (the latter creates a session + sends a command turn and can be
slow). Today the only feedback is the per-row spinner + disabled rows. We want a proper
**animation / waiting screen** for the duration of the switch so the selection feels
deliberate and the wait is covered.

**Action:** task **Claude Design** to create the animation / transition screen, then wire
it to `ModelsSettingsModel.applyingModelID` (already drives the in-flight state). Should
cover the whole apply() window and dismiss on success / surface the error or confirm
dialog. Ties to the existing optimistic-checkmark behavior.

---

## 10. ✅ Top-center model chip — shows real model, seeded from shim

The ChatScreen top-center `ModelSelector` chip now shows the real active model name,
seeded on launch from the models shim (cached, fast) when the command catalog doesn't
provide one. Falls back to "HERMES" instead of the old hardcoded "CLAUDE OPUS 4.6"
placeholder. Updated in sync with `/model` switches via `chatStore.activeModelName`.

**Fixed 2026-06-25:** `AppContainer.initialize()` → `seedActiveModelFromShim()` as
fallback after `refreshCommandCatalog`. Also added to `handleAppDidBecomeActive()` as
a secondary path (runs even when `initialize()` aborts due to relay guard).
`ModelSelectorModel.activeDisplayName` fallback changed from stub list to "HERMES".

**Verified on-device 2026-06-25:** chip shows "kimi-k2.6" (correct active selection).
Command catalog provides the model name when relay is reachable; shim seed serves as
fallback when relay is down.

---

## 11. 🐛 Settings back-nav exits Settings instead of popping

Navigating into some Settings sub-screens and tapping Back exits Settings entirely instead
of returning to the previous screen. Back should pop to the prior screen within the
Settings stack. Audit the Settings navigation (NavigationStack push vs sheet presentation;
the custom HUD back buttons' `dismiss()` vs an explicit path pop). Owen to pinpoint which
screens on-device.




---

## 12. ✅ Sensor data stale / not collecting on-device — app-side resolved

**Status:** App-side fixes complete. Remaining gap is OJAMD server-side (#24a).

**What was fixed (2026-06-25):**
- **HealthKit auth** (#16): `requestAuthorization()` re-asserted on every sensor start.
  11 health observer types now fire, fresh samples captured (`distance_walking`, `steps`).
- **iCloud Private Relay** blocking all Tailscale HTTP: discovered and documented.
  Disabling Private Relay restored connectivity to relay (`:8000`) and shim (`:8765`).
- **Location delivery** now works end-to-end: `deliveryState=delivered` confirmed.

**What remains (OJAMD server-side, → #24a):**
Health uploads are rejected by the relay with HTTP 422. The app captures and queues
health samples (1700+ in outbox) but the relay rejects the payload format. This is a
server-side schema/content-type issue, not app code.

---

## 13. ✅ Model identification — resolved (SOUL.md was the cause)

**Closed 2026-06-25.** The app-side placeholder issue was fixed in #10 (chip now shows
the shim's real model name). The "MiniMax-M3 responding when config says kimi" confusion
was caused by SOUL.md on Hermes being edited to identify as MiniMax after a persona
experiment — not an app or routing bug.

---

## 14. ✅ Shim token onboarding — unified key, zero manual entry

**Approach chosen:** unified API key. The shim now accepts the same Hermes API server
key the app already stores for chat — no second token needed.

**Shim side (`tools/models-shim/shim.py`):**
- `_load_api_server_key()` reads the Hermes API server key from `API_SERVER_KEY` env
  var or `~/.hermes/config.yaml → api_server.key`
- `_authed()` accepts BOTH the dedicated shim token (legacy) AND the API server key
- Backward compatible — existing shim tokens still work

**App side (`AppContainer.swift`):**
- `ModelsShimClient.tokenProvider` now has a 3-tier fallback:
  1. Dedicated shim token from Keychain (legacy/override)
  2. `TALARIA_SHIM_TOKEN` launch-env (DEBUG simulator)
  3. Hermes API server key (same key used for chat — zero-config)
- New users only need to enter ONE key (the Hermes API key) and models switching
  works immediately — no manual token copy from the server

**Deploy note:** Owen needs to redeploy `shim.py` on OJAMD for the server side to
take effect. The app-side fallback is already active.

Fixed 2026-06-25.

**Verified live on OJAMD (2026-06-26):** the server-side key fallback now authenticates
end-to-end — Hermes API key → 200, dedicated token → 200, bogus → 401. The mechanism on
OJAMD is `run-shim.cmd` exporting `API_SERVER_KEY` from `%LOCALAPPDATA%\hermes\.env` (→ #24g),
which feeds source 1 of `_load_api_server_key()`. So after a re-pair/reinstall the app needs
no shim-token paste. **Caveat:** OJAMD currently runs an *interim* patched `shim.py`
(env-only fallback, 7249 B) re-implemented in the OJAMD session before the canonical file was
visible from that box — functionally identical to canonical (7681 B, which additionally has
the `config.yaml` source-2 fallback) since both read the env key. Follow-up: deploy the
canonical `shim.py` over the interim patch on OJAMD so deployed == repo byte-for-byte.


---

## 15. 📝 In-app sensor diagnostics panel

Add a diagnostic section to Settings (or a hidden debug screen) that surfaces the sensor
pipeline's internal state at a glance:
- `SensorUploadService.isActive` (was `start()` called?)
- `isPairedProvider()` result
- `accessTokenProvider()` result (non-nil / nil — don't display the actual token)
- Outbox state: pending location (lat/lon/age), pending health sample count
- Last drain result (success / which gate blocked / HTTP error)
- `LiveHealthService.authorizationStatus`
- `LiveLocationService.authorizationStatus` + `authorizationLevel`
- `LiveMotionService` status
- Last location update timestamp + last health snapshot timestamp

This lets Owen (and eventually Shelley) see the pipeline state without Console.app.


---

## 16. ✅ HealthKit authorization — fixed: re-assert on sensor start

**Status:** Fix applied 2026-06-25, pending device verification.

**Corrected diagnosis:** The original tracker note ("the app has never called
`requestAuthorization()`") was wrong — `LiveHealthService.requestAuthorization()` exists
and is wired through `PermissionsStore.requestPermission(for: .health)`. The real root
cause is subtler:

1. `LiveHealthService.authorizationStatus` is **in-memory only** — initialized to
   `.notDetermined` in `init()`, set to `.authorized` only when `requestAuthorization()`
   runs *this process*.
2. Apple's read-privacy model: `HKHealthStore.authorizationStatus(for:)` deliberately
   returns `.notDetermined` for read-only types even after the user grants access — iOS
   hides read status to prevent apps from inferring what the user denied.
3. `collectSnapshot()` hard-gates on `authorizationStatus == .authorized` (line 145).
4. `SensorUploadService.start()` — which runs on every launch — called
   `healthService.startMonitoring()` but **never** called `requestAuthorization()`.
5. The only caller of `requestAuthorization()` was a manual onboarding/Permissions UI tap.

Result: after a relaunch, the in-memory flag resets to `.notDetermined`, the Apple API
can't recover it, and `start()` never re-asserts it → `collectSnapshot()` returns nil
forever until/unless the user manually re-taps ENABLE.

**Fix (SensorUploadService.swift):** `start()` now awaits
`healthService.requestAuthorization()` inside a Task before calling
`healthService.startMonitoring()`. For read-only types, iOS shows the system permission
sheet at most once per install — every subsequent call is a silent no-op — so this is safe
on every launch with zero nagging. After re-asserting, it does an immediate
`forceFullRefresh` capture to prime the outbox.

**Note:** This unblocks the app-side collection gate. Fresh samples will flow into the
outbox, but **#17** (relay `deliveryState=retry`) still blocks delivery to Hermes — both
fixes are needed for end-to-end sensor data.

**Verified on-device 2026-06-25:** `start() — health auth re-asserted: authorized` ✅.
Health observer callbacks fire for 11 types (active_calories, blood_oxygen, body_mass,
heart_rate, distance_walking, respiratory_rate, sleep_duration, resting_heart_rate,
workout_minutes, stand_hours, steps). Fresh samples captured: `captureHealth: got 2
samples — distance_walking, steps`.

---

## 17. 🐛 Relay sensor delivery returns `retry` — connector handoff failing

**Status:** Confirmed blocker — location uploads reach the relay but never deliver.

The phone successfully uploads sensor data to the relay on `:8000`, but the relay responds
with `deliveryState=retry` instead of `delivered`. This means the relay accepted the upload
but the connector has not confirmed delivery to Hermes.

**Console evidence (console2.txt):**
```
drain: starting. Outbox: loc=true, health=49
executeUpload device/sensor/location: deliveryState=retry wasDelivered=false
drain: location upload ❌ failed
drain: finished. Outbox remaining: loc=true, health=49
```

**Architecture reminder:**
```
Phone → relay (:8000, OJAMD) → connector → Hermes CLI session on OJAMD
```

The connector appears connected to the relay, but delivery isn't completing. Possible causes:
- Connector's Hermes session is dead or the `hermes_mobile` MCP tools are not registered
- Connector received the payload but failed to forward (check connector logs)
- Relay-to-connector protocol mismatch or timeout

**Next step:** Ask Hermes on OJAMD to check relay + connector logs for sensor delivery
errors and verify the `hermes_mobile` MCP tools are registered and the connector session
is alive.

**Update (2026-06-25):** Root cause of `deliveryState=retry` identified — **iCloud Private
Relay** was intercepting HTTP requests to Tailscale IPs and proxying them through
`mask.icloud.com`, which has no route to the tailnet. Manifested as 502 responses from the
proxy for `:8000` and 30-second timeouts for `:8765` (shim).

After disabling Private Relay on the phone:
- **Location delivery now works:** `deliveryState=delivered wasDelivered=true` ✅
- **Health uploads still fail with 422** — relay rejects the payload. This is a
  payload format / schema issue, not a connectivity problem. The relay accepts location
  but not health — likely a content-type or body-structure mismatch in the health upload
  endpoint.

**Known networking requirement:** iCloud Private Relay must be disabled (or Tailscale IPs
excluded) for any Tailscale-routed HTTP services. This affects the relay (`:8000`), the
shim (`:8765`), and potentially the gateway (`:8642`). Should be documented in onboarding
and checked in the diagnostics panel (#15).


---

## 18. ✅ Session shelf — scrim opacity increased, toolbar hit-testing blocked

The session shelf (sessions drawer) overlay was too transparent (62% opacity) and let
taps fall through to the toolbar (model chip, settings gear) because SwiftUI's navigation
toolbar renders above `.overlay` content.

**Fixed 2026-06-25:**
- Scrim opacity bumped from 0.62 → 0.85 (`Design.Colors.scrim`)
- All three toolbar items (sessions button, model chip, settings gear) now have
  `.allowsHitTesting(!sessionsOpen)` — taps on the toolbar area pass to the scrim
  dismiss gesture when the drawer is open

---

## 19. ✅ Session shelf — history now populated from Hermes Sessions API

**Root cause:** `SessionsListResponse` expected a `"sessions"` key in the API JSON,
but the Hermes Sessions API returns `"data"`. One-word DTO mismatch. The `try?` in
`ChatStore.loadSessions()` silently swallowed the decode error, returning `[]`.

**Fixed 2026-06-25:**
- Changed `SessionsListResponse.sessions` → `.data` to match the API contract
- Added diagnostic logging to `loadSessions()` (ChatStore) and `listSessions()`
  (SessionsHermesClient) so decode failures surface with the raw response body
- Removed placeholder sessions from `SessionsDrawerModel` (was showing fake
  "Morning Briefing" / "Reschedule afternoon" entries)
- Updated stale TODO comment

**Verified on-device:** `listSessions: decoded 50 rows`, `loadSessions: got 50 sessions`.
Session tap → open also fixed: `SessionMessagesResponse` had the same `"messages"` vs
`"data"` key mismatch. Both DTOs now use `data` to match the Hermes API contract.
Tapping a session loads its full conversation history.

---

## 20. ✅ Top-center model chip — routes to real picker; stub dropdown + "Start New Session" removed

**Decision (Owen, 2026-06-24): option (b)** — implemented 2026-06-25.

The top-center `ModelSelector` chip now routes taps to the real **Settings → MODELS picker**
(shim-backed, `ModelsSettingsScreen`) via a new `SheetDestination.settingsModels` that
presents the picker directly in a NavigationStack (no detour through Settings root).

Removed:
- The stub `availableModels` dropdown (opus/sonnet/haiku hardcoded list)
- The `onStartNewSession` / "Start New Session" action (session management belongs in the
  left drawer)
- The popover picker UI entirely
- The chevron.down icon on the chip
- `ModelSelectorModel.selectedModelID`, `.onSelectModel`, `.onStartNewSession`, `.select()`,
  `ModelOption` struct

Net -102 lines across 5 files.

**Verified on-device 2026-06-25:** chip tap opens the Models picker directly. No
dropdown, no popover, no "Start New Session" — straight to the shim-backed list.

---

## 21. 📝 No way to present/download agent-generated files (reports, text, etc.)

Ask the agent to produce a file — a markdown report, a text file — and the app has **no
surface to present it for viewing or download**, the way claude.ai and Hermes Desktop do.
The content is effectively stuck in (or absent from) the chat stream.

**Open questions / what's needed:**
- **Does the Sessions API emit file artifacts at all?** Confirm whether `/chat` or the SSE
  stream surfaces generated files (a tool result with a path/blob, an artifact event) or
  whether the agent only writes them to its working dir on the host. If surfaced, the app
  can render a download affordance; if not, the gateway needs an endpoint to fetch them.
- **App side:** a file/attachment bubble in the transcript with view + share-sheet / save
  to Files. Ties into Phase 2 markdown rendering.

Feature gap, not a regression. Reported on-device 2026-06-24.

---

## 22. ✅ Shim token re-established — model switching works (shim now on OJAMD)

After re-pairing/reinstalling, the **phone no longer has a valid models-shim bearer token**,
so the picker's set-default leg (shim `POST /models/default`) can't authenticate and model
switching couldn't be tested this session. This is the concrete near-term instance of the
onboarding-friction problem in Open Item #14 (and the DEBUG seam in #7).

**Near-term:** re-establish the shim token on the device (re-copy from
`~/.hermes/talaria_shim_token` on the mini into the Keychain via the Settings field).
**Resolved (2026-06-24):** `~/.hermes/talaria_shim_token` is intact on the mini — no
rotation needed. Re-pair the existing value onto the phone (it was lost from the Keychain
on the fresh install, not changed by the re-pair). Reported 2026-06-24.

**Closed (2026-06-25):** superseded by the OJAMD shim deploy (→ #1). The token that matters now
lives on **OJAMD** at `C:\Users\Owen\.hermes\talaria_shim_token` (auto-created on first run),
paired into the app, and switching is confirmed end-to-end. The mini token is moot — the phone
never used the mini shim.

---

## 23. 📝 Add a "revoke permissions" affordance

The app can request permissions (HealthKit, Location, Notifications, etc.) via the
Permissions/Onboarding screens, but there is **no in-app way to revoke** them. Users must
navigate to iOS Settings manually to disable individual permissions.

**What's needed:** a revoke/disable control per permission type in the Settings →
Permissions screen (or wherever permissions are surfaced). For HealthKit specifically this
means calling `HKHealthStore` methods to disable background delivery and stopping observer
queries; for Location, stopping monitoring and resetting the sync preference; for
Notifications, deregistering from the relay. Some permissions (Camera, Photos) can only be
toggled in iOS Settings — for those, surface a "Manage in Settings" deep-link.

**Designed (2026-06-26):** the PRIVACY (11) page in `design/Settings-Additional.dc.html`
provides this — per-permission `MANAGE ›` deep-links + a "Revoke / Reset Permissions"
action. To be built on `feat/settings-index-swap` (see #2).

Logged 2026-06-25.

---

## 24. 🐛 OJAMD server-side work — health 422, relay bind (shim + gateway persistence ✅)

Consolidated tracker for server-side fixes on OJAMD (Windows desktop, Tailscale
`100.110.102.59`). None of these are app code — they require work on the OJAMD host.

### 24a. Health upload rejected with 422

The relay on `:8000` accepts location uploads (`deliveryState=delivered`) but rejects
health payloads with **HTTP 422**. This is a payload format / schema issue — the relay
parses the body and doesn't like what the health upload sends. Console evidence:

```
upload device/sensor/health: error — Relay request failed with status 422.
drain: health upload (1607 samples) FAILED
```

**Investigate:** check OJAMD relay logs for the 422 response body / validation error.
Compare the health upload body structure against what the relay endpoint expects.
Location works, so the auth + routing is fine — it's specifically the health payload.

### 24b. Relay bind to `0.0.0.0`

The relay on `:8000` has the same localhost-bind issue the gateway had before it was
fixed. Needs `0.0.0.0` treatment + Windows Firewall rule so the phone can reach it
over Tailscale without the iCloud Private Relay workaround. (Currently works because
Private Relay is off, but shouldn't depend on that.)

### 24c. ✅ Shim Task Scheduler persistence — RESOLVED (2026-06-26)

The models shim runs as Scheduled Task **`TalariaModelsShim`**, hardened: **S4U** principal
(runs as Owen, passwordless — survives logoff), **boot + logon** triggers (auto-start at
reboot), launched via a hidden `wscript` wrapper (`run-shim-hidden.vbs` → `run-shim.cmd`) so
**no console window ever appears**, no execution time limit, auto-restart on crash. Replaces
the old logon-only task whose console teardown kept dropping it.

### 24d. Windows Firewall rule for port 8765

The shim listens on `:8765`. Needs an inbound firewall rule on OJAMD for Tailscale
access. Currently works when Private Relay is off, but should be explicitly allowed.

### 24e. iCloud Private Relay networking requirement

**Discovery (2026-06-25):** iCloud Private Relay intercepts HTTP to Tailscale IPs via
`mask.icloud.com`, which has no tailnet route. This caused 502s for the relay and
30-second timeouts for the shim. Disabling Private Relay on the phone fixes everything.

This needs to be:
- Documented in onboarding / setup instructions
- Checked in the diagnostics panel (#15)
- Potentially mitigated by using HTTPS via `tailscale serve` (which may bypass the proxy)

Logged 2026-06-25.

### 24f. Relay JWT signing secret + device registry not persisted across restarts

**Root cause of the launch-splash lockout (2026-06-26).** When Hermes/the relay restarts it
regenerates its JWT signing secret and loses the in-memory device registry, so every
previously-paired device's tokens are invalidated → relay returns 401 to bootstrap
(`registerDevice` / `/session` / refresh) and the phone is forced to re-pair. The app-side
hard-abort that turned this into a permanent splash hang is fixed (soft fall-through, commit
`114caf2`), but the **server-side gap remains**: persist the relay's JWT signing secret and
device registry to disk so restarts don't brick paired devices. Until fixed, every Hermes
restart forces a re-pair.

### 24g. ✅ Shim API-key fallback on Windows — RESOLVED (2026-06-26)

The shim accepts *either* its dedicated token *or* the Hermes `API_SERVER_KEY` (the app's
zero-token fallback, #14). But on OJAMD the shim never loads that key: `API_SERVER_KEY` env is
unset and the shim looks for `~/.hermes/config.yaml` (doesn't exist on Windows), while the real
key lives in `%LOCALAPPDATA%\hermes\.env`. So after any re-pair/reinstall (empty Keychain shim
token) the app's key-fallback **401s** against the shim. Fix: have `run-shim.cmd` read
`API_SERVER_KEY` from `%LOCALAPPDATA%\hermes\.env` and export it before launching python
(OJAMD-local, no shim.py/repo divergence). Also harden the Task Scheduler trigger (24c) — it's
logon-only and a console teardown took the shim down (2026-06-26).

**Resolved (2026-06-26):** `run-shim.cmd` now reads `API_SERVER_KEY` from
`%LOCALAPPDATA%\hermes\.env` and exports it before launching python, so the shim's
`_load_api_server_key()` finds it (source 1). Verified: API-key path → 200. The logon-only
trigger fragility is fixed via 24c (S4U + boot trigger). Note: the file deployed on OJAMD is
the interim env-only patch — see the #14 caveat for the canonical-vs-deployed follow-up.

### 24h. ✅ Gateway / API server now a persistent windowless service — NEW (2026-06-26)

The Hermes **gateway** (which hosts the **API Server adapter on `:8642`** — the phone's chat
path) was being run in a foreground console (`hermes gateway run`), so it dropped whenever the
window was closed, and the bare console "looked suspicious." Now it runs as Scheduled Task
**`HermesGateway`** with the same hardening as the shim: S4U, boot + logon triggers, hidden
`wscript` wrapper (`~/.hermes/scripts/run-gateway-hidden.vbs` → `run-gateway.cmd` →
`hermes.exe gateway run`), no time limit, auto-restart. Verified: `:8642` serves a real
`POST /api/sessions`, `hermes gateway status` → running. (`hermes gateway install` was **not**
used — on Windows it only makes a login-only, possibly-flashing task; running it would fight
`HermesGateway` for `:8642`.)

**Discord is one token away:** the API Server is just one gateway adapter; the same
`HermesGateway` process will also serve Discord once a `DISCORD_BOT_TOKEN` exists (none yet —
needs a bot created in Discord's dev portal + invited to the server). No new service required:
add the token, restart the task.

**OJAMD service inventory (all windowless + reboot-proof):**
- Relay `:8000` → `HermesMobileRelay` (NSSM service, uvicorn)
- Shim `:8765` → `TalariaModelsShim` (Scheduled Task, hardened)
- Gateway/API `:8642` → `HermesGateway` (Scheduled Task, hardened)

---

## 25. 🐛 CTX meter always shows 0% — SSE usage not parsed

The "CTX 0%" telemetry in the agent identity strip never updates. Root cause:
`SessionsHermesClient` emits `.finished(message, nil, nil)` at the `assistant.completed`
SSE event — it never parses the `run.completed` event which carries token usage data
(`input_tokens`, `output_tokens`, etc.).

The pipeline from `.finished` → `ChatStore.lastTokenUsage` → `ChatScreen.contextProgress`
is already wired; the client just needs to extract `TokenUsage` from `run.completed` and
pass it through.

Also depends on `contextWindow` being set (the denominator). Currently seeded from the
command catalog's `activeModel.contextWindow` or `inferredContextWindow(for:)` — both may
return nil if the catalog doesn't include context info for the active model.

Logged 2026-06-25.

**Update 2026-06-27 — numerator fixed; denominator follow-up.** `SessionsHermesClient`
now defers `.finished` to the `run.completed` SSE event and parses its top-level `usage`
(Hermes emits Anthropic-style `input_tokens`/`output_tokens`/`total_tokens`, mapped onto
TokenUsage's prompt/completion/total). Verified on device — the CTX meter populates from
real usage. REMAINING: the percentage reads low (~36% where Hermes estimates ~50%), so the
`contextWindow` denominator is ~1.4x too large. The numerator is server-authoritative
(`input_tokens`), so the gap is the denominator: the seeded model contextWindow exceeds
Hermes's effective/compacted window. Reconcile against a Hermes-provided limit (shim model
list or a run/session limit field) rather than the catalog's nominal window.

---

## 26. ✅ Removed non-functional "/ slash" and "@ context" hint chips

The decorative hint chips ("/ slash", "@ context") above the text input area were
purely cosmetic and non-interactive — tapping them did nothing. Removed from
`ChatInputBar.swift` (31 lines deleted).

Fixed 2026-06-25.

## 27. 📝 Developer screen flags — keep Verbose Logging, drop Mock Responses

From the Claude Design DEVELOPER (12) mockup `// FLAGS` panel. Decision (Owen, 2026-06-26):

- **Mock Responses:** **dropped** — no real backing, not building it.
- **Verbose Logging:** **keep**, but only as a real control — wire the toggle to an actual
  os_log level change (raise diagnostic-log visibility, e.g. `.info`→`.notice`/`.debug`, or
  gate the verbose `privacy:.public` diagnostics). Persist as a DEBUG-scoped `UserSettings`
  flag. Until wired, omit it rather than ship a dead toggle.

Logged 2026-06-26.

---

## 28. ✅ T3 — Settings sub-pages 09–12 built + SYSTEM index swap

Built the four remaining T3 Settings sub-screens from
`design/Settings-Additional.dc.html`, real-data-only, matching the existing
sub-screen + HUD patterns:

- **09 RELAY** (`RelaySettingsScreen`) — relay mode/URL via real `RelayConfiguration`
  (validation + normalize), reachability from the live relay session, DEVICE via
  `PairingStore` (PAIRED host name, RE-PAIR → pairing flow, FORGET → `disconnect()`),
  auto-connect toggle. Relay locked while paired.
- **10 NOTIFICATIONS** (`NotificationsSettingsScreen`) — Push toggle drives
  `notificationsEnabled` + re-runs `registerPushTokenIfNeeded`; hero + token row reflect
  live OS auth (`PermissionsStore`) and `sessionStore.state.pushTokenRegistered`.
- **11 PRIVACY** (`PrivacySettingsScreen`) — permission rows from live
  `PermissionsStore.capabilities`; not-determined → in-app prompt, else MANAGE →
  iOS Settings; location accuracy + foreground/background sync segmented.
  "Revoke/Reset" reworded to an honest "Manage in System Settings" deep-link (the app
  can't revoke OS grants; real in-app revoke is #23).
- **12 DEVELOPER** (`DeveloperSettingsScreen`, DEBUG-only) — environment radio from
  `availableEnvironments` with real endpoints; Verbose Logging (see #27/#29); Mock
  Responses dropped; COMMIT renders "—" (no build-injected hash). Index row compiled
  out of Release via `#if DEBUG`.

Wired all four into `SystemSettingsScreen` (Relay→Connection, Notifications+Privacy→
Experience, DEBUG Developer group) and **swapped the live Settings entry**:
`ContentView` now presents the SYSTEM index instead of the monolith `SettingsScreen`.

Build: SUCCEEDED (Debug, iOS Simulator, Xcode-beta). Not yet committed; on-device pass
on whoGoesThere pending. Logged 2026-06-26.

## 29. 🔧 Verbose Logging — downstream adoption

`TalariaLog` (`Talaria/Core/TalariaLog.swift`) now backs the Developer screen's Verbose
Logging toggle: it persists `UserSettings.verboseLogging`, mirrors the flag into a
UserDefaults bridge (`talaria.verboseLogging`), and emits a real, observable os_log
`.notice` on every change — so the toggle has a genuine effect today (supersedes #27's
"omit until wired").

Remaining: route the existing per-service `Logger(...)` call sites
(`ChatStore`, `LiveHermesClient`, `SessionsHermesClient`, `SensorUploadService`,
`LiveSpeechService`, `LiveVoiceSessionService`, `AppContainer`) through
`TalariaLog.verbose(_:)` so they actually fall silent when the flag is off. Also consider
syncing `TalariaLog` from settings at launch (today the toggle is the only writer).

Logged 2026-06-26.

## 30. 📝 Remove dead monolith `SettingsScreen.swift` after on-device confirmation

The #28 index swap makes `Talaria/Features/Settings/SettingsScreen.swift` unreachable
(its only entry was `ContentView` `.settings`, now repointed; its internal TEMP preview
links to the sub-screens go with it). Keep it as dead code until the SYSTEM index is
validated on whoGoesThere, then delete the file + run `xcodegen generate`.

Logged 2026-06-26.
