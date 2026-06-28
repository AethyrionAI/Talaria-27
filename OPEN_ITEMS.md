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

## 2. ✅ T3 — Settings screens build — SUPERSEDED BY #28

**Closed 2026-06-28:** the non-MODELS screens plus sub-pages 09–12 and the SYSTEM index
swap shipped — see #28 (and #30 for the dead-monolith removal). This broad tracker is
superseded; original scope retained below for history.

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

## 9. ✅ Model transition overlay — built + both regressions fixed

When a model is tapped, the dual-write runs: shim `POST /models/default` **and** the
gateway `/model` pin (the latter creates a session + sends a command turn and can be
slow). Today the only feedback is the per-row spinner + disabled rows. We want a proper
**animation / waiting screen** for the duration of the switch so the selection feels
deliberate and the wait is covered.

**Action:** task **Claude Design** to create the animation / transition screen, then wire
it to `ModelsSettingsModel.applyingModelID` (already drives the in-flight state). Should
cover the whole apply() window and dismiss on success / surface the error or confirm
dialog. Ties to the existing optimistic-checkmark behavior.

**Built 2026-06-27 — `ModelTransitionOverlay.swift` (uncommitted) — two on-device regressions.**
Overlay driven by `applyingModelID` / `pendingConfirm` / `errorMessage`, with ACTIVATING
(reactor + stepped telemetry) → SUCCESS / CONFIRM (amber) / ERROR (retry); real copy only.
On whoGoesThere Owen hit two bugs:
1. **Scroll misalignment** — overlay is attached to the list `content` *inside* the
   ScrollView, so it scrolls / renders out of position. Fix: pin to the viewport (attach at
   the body ZStack level, fixed below header + shim config) instead of the scrolling frame.
2. **Lock-up, never resolves** — `apply()` keeps `applyingModelID` set through the whole
   window, including the slow/hang-prone gateway `/model` pin (`chat.selectModel`, ~37s+ or
   indefinite when the gateway is slow/offline). Overlay stays in ACTIVATING forever; mean-
   while every row is `.disabled(applyingModelID != nil)`, so the *next* tap (e.g. opus 4.8)
   does nothing. Backing out + in re-inits the screen and the shim's optimistic override had
   already landed, so the switch "took." Fix: resolve the overlay on the **shim** result (the
   authoritative persistent default), run the gateway pin as a non-blocking background task
   that updates status async, and add a safety timeout so it can never lock. CONFIRM only
   shows for shim-flagged expensive models — opus 4.8 isn't flagged on this box, so no
   confirm there is expected. Status: uncommitted; fix pending before commit.

**Fixed + committed 2026-06-27 — confirmed on whoGoesThere ("that works well now").**
(1) Overlay moved to the body ZStack (**viewport-pinned**) so it no longer drifts with the
scroll — tradeoff: the scrim now covers the full screen during a switch (header + shim
included), accepted over the larger refactor of pulling them outside the ScrollView.
(2) The gateway `/model` pin runs in the background (`pinSessionInBackground`) so `apply()`
returns on the shim result; the overlay resolves promptly and rows re-enable immediately.
(3) Added a 12s watchdog so the overlay can never visually lock.

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

**Status 2026-06-28:** this canonical-redeploy follow-up is **blocked on #36** (the OJAMD
checkout must track the `ChronoRixun` fork before the canonical file is visible there) and is
low-priority — the interim env-only patch is functionally identical. One of the two remaining
OJAMD blockers.


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

## 21. 🔧 Present/download agent-generated files — Tier 1 (app) ✅ done, Tier 2 (relay) follow-up

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

**Selected as next thread (2026-06-27).** First step: determine whether the Sessions API
surfaces file artifacts at all — inspect `/chat` sync payloads + the SSE stream
(`tool.completed` results, any artifact/file event) for a path or blob, vs. files only
landing in the agent's host working dir. If surfaced → file/download bubble in the
transcript + share-sheet / save-to-Files (ties into Phase 2 markdown rendering); if not →
the gateway needs a fetch endpoint first.

**Probe + plan 2026-06-27.** Hit the live OJAMD API to settle the gating question.
- **Sync `/chat`:** prose only — `message` is `{role, content}`; the agent just states the
  host path. No artifact field, URL, or blob.
- **SSE stream:** a write surfaces as `tool.started` `{tool_name:"write_file",
  args:{path, content}, preview:<path>}`; `tool.completed` is empty; `run.completed.messages`
  also carries the tool_calls. **Files land in the host working dir (`O:\Hermes\`) and are
  never delivered to the phone.** No download URL / artifact event.
- **No built-in file endpoint:** `/openapi.json`, `/v1/files`, `/api/files`, `/files` all 404
  (`/v1/capabilities` 200).

**Tier 1 (app-only, v1 — no server change):** parse `write_file` `tool.started` (path +
content) in `SessionsHermesClient`, attach to the assistant message, render a transcript
**file bubble + share-sheet** (covers Save to Files). Works today for agent-written text/
markdown because the content rides in `args.content`.

**Tier 2 (durable, server-side follow-up):** a small authed file-fetch route on the **relay**
(`O:\Hermes\Talaria\relay`) — bearer auth, whitelisted to the agent output dir, no path
traversal, Tailscale-reachable — for binaries / files not reconstructable from args. It must
live in the relay (our sidecar), **not** a Hermes-core patch: `curl install.sh | bash`
replaces `~/.hermes/hermes-agent` and would wipe core edits, while `config.yaml`/`.env`/
skills/sessions persist. Zero-code stopgap: ask the agent to `read_file` the file back via a
chat turn (durable but an LLM round-trip).

Status (2026-06-27): Tier 1 = ✅ DONE; Tier 2 relay route = ✅ BUILT + DEPLOYED + LIVE on OJAMD; Tier 2 app-side fetch = ⏳ pending the binary-write SSE probe (see notes below).

**Tier 1 shipped + verified on-device 2026-06-27 (`96b291f`).** `write_file`/`create_file`
`tool.started` (`args.path` + `args.content`) is parsed in `SessionsHermesClient`'s SSE
loop, the bytes are staged into the app's Attachments dir, attached to the final assistant
`Message`, and rendered as a tappable `ShareLink` file bubble in the Hermes bubble (covers
Save to Files / AirDrop / Quick Look). No server change; `ChatStore` already preserves
`finalMessage.attachments`. Parser is tolerant of arg-key drift
(`args`/`arguments`/`input`, `path`/`file_path`/`filename`, `content`/`text`).
**On-device (whoGoesThere):** a plain "write a report" returns prose with no bubble (correct
— the agent didn't invoke the tool); asking for it "as a shareable file" produced the bubble
and shared cleanly to a TestFlight contact. **Tier 1 done.** Tier 2 (durable relay
file-fetch route for binaries / non-reconstructable files) remains the server-side follow-up.

**Known Tier 1 boundary (not a gap):** reconstructed files live for the active session;
reopening a session from the server won't restore them (the server never stored the local
copy). Persistence across reloads would ride on Tier 2.

**Tier 2 relay route — built + deployed + live 2026-06-27 (`ccf6e5a`, branch
`feat/agent-files-tier2`).** `GET /v1/device/files?path=…` on the relay serves a file the
agent wrote on the host, gated by device-bearer auth (`get_auth_context`) and whitelisted to
`agent_files_dir` (env `AGENT_FILES_DIR`). `resolve_agent_file()` resolves symlinks/`..` then
enforces containment via `relative_to(base)`; every failure → 404 (never leaks existence).
Streams via `FileResponse` (content-type + filename). 8 new tests + full relay suite (55)
green on the Mac. **Deployed on OJAMD** (edits hand-applied — see #36 re: why not a git pull;
`AGENT_FILES_DIR=O:\Hermes\MobileDL`; relay restarted) and **smoke-tested live**: `/v1/health`
200, `/v1/device/files` (no token) → **401** (route loaded + auth-gated). The DB is file-backed
(`hermes_mobile.db`), so device pairings survive the restart.

**Tier 2 app-side fetch — NEXT, blocked on one probe.** Plan: add `remotePath` to
`MessageAttachment` + a `fetchableAgentFile` factory; add `downloadFile(path:accessToken:)`
to `RelayAPIClient`; branch `parseWrittenFile` so *content present → Tier 1*, *content absent
→ Tier 2 fetchable bubble*; plumb a "tap → download → stage → ShareLink" path through
`MessageBubble → ChatScreen → ChatStore` (giving `ChatStore` the relay client + device token).
**Gate:** the binary-write SSE shape is unprobed — we need one real non-text `write_file`
(e.g. save a small PDF to `MobileDL`) captured off `:8642/chat/stream` to confirm whether
`args.content` is present/absent for binaries, which decides the fetch trigger. Also needs the
Hermes-side nudge so the agent writes shareable artifacts into `MobileDL`.

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

## 24. 🔧 OJAMD server-side work — 422 → Mac-side; Private Relay doc + relay-JWT persistence remain (bind/firewall/persistence/update-stability ✅)

Consolidated tracker for server-side fixes on OJAMD (Windows desktop, Tailscale
`100.110.102.59`). None of these are app code — they require work on the OJAMD host.

### 24a. 🔧 Health upload 422 — DIAGNOSED 2026-06-28, fix is Mac-side (chunking)

The relay on `:8000` accepts location uploads (`deliveryState=delivered`) but rejects
health payloads with **HTTP 422**. This is a payload format / schema issue — the relay
parses the body and doesn't like what the health upload sends. Console evidence:

```
upload device/sensor/health: error — Relay request failed with status 422.
drain: health upload (1607 samples) FAILED
```

**Root cause confirmed (2026-06-28):** `SensorHealthRequest.samples` is capped at
`max_length=100` (`relay/app/schemas.py:146`). The phone drains its whole HealthKit backlog
(console showed 1607 samples) in one request -> Pydantic 422 before any field-level check.
Location works because it sends one reading per request (no array); it's purely the array
length, not the per-sample fields.

**Decision — Option A (relay unchanged):** keep the relay cap at 100 and **chunk on the phone
to <=100 samples/request**, sent **sequentially** — the connector handles one sensor payload at
a time and returns **202 "retry"** when `session.busy`, so await each chunk and honor the 202
with backoff. No relay rate limiter on sensor endpoints, so sequencing is driven by the
connector busy-flag, not throttling. **The fix now lives on the Mac / iOS uploader, not
OJAMD** — tracked here, executed app-side.

### 24b. ✅ Relay bind to `0.0.0.0` — RESOLVED 2026-06-28

Confirmed the relay already binds `0.0.0.0:8000` (NSSM `AppParameters: app.main:app --host
0.0.0.0 --port 8000`). Tailnet reachability is carried by the existing `Tailscale-Process`
inbound **Allow (Profile: Any)** rule — no per-port rule is required for tailnet access (a
per-port rule would only matter for non-Tailscale/LAN clients, which isn't the use case).

### 24c. ✅ Shim Task Scheduler persistence — RESOLVED (2026-06-26)

The models shim runs as Scheduled Task **`TalariaModelsShim`**, hardened: **S4U** principal
(runs as Owen, passwordless — survives logoff), **boot + logon** triggers (auto-start at
reboot), launched via a hidden `wscript` wrapper (`run-shim-hidden.vbs` → `run-shim.cmd`) so
**no console window ever appears**, no execution time limit, auto-restart on crash. Replaces
the old logon-only task whose console teardown kept dropping it.

**Update 2026-06-28 — converted to an NSSM service.** The hardened Scheduled Task was replaced
by NSSM service **`TalariaModelsShim`** (LocalSystem, Automatic, `AppRestartDelay 5000`),
matching the relay, so auto-restart is native and the update-failure outage pattern (-> 24i) is
closed. The old Scheduled Task is **disabled, not deleted** (rollback path). **Recovery is now
`Start-Service TalariaModelsShim` — not `Start-ScheduledTask`.**

### 24d. ✅ Windows Firewall rule for port 8765 — RESOLVED 2026-06-28

Carried by the same `Tailscale-Process` Allow(Any) rule as 24b. The shim was rebound to
`0.0.0.0` (from the Tailscale-only `100.110.102.59`), so it's loopback-reachable for local
health checks too. Verified: `:8765` -> 401 on both loopback and tailnet.

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

### 24h. ✅ Gateway / API server now a persistent windowless service — NEW (2026-06-26; converted to NSSM 2026-06-28 -> 24i)

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

**OJAMD service inventory (all windowless + reboot-proof — all NSSM as of 2026-06-28):**
- Relay `:8000` → `HermesMobileRelay` (NSSM service, uvicorn)
- Shim `:8765` → `TalariaModelsShim` (NSSM service)
- Gateway/API `:8642` → `HermesGateway` (NSSM service)

### 24i. ✅ Update stability — gateway + shim survive `hermes update` — RESOLVED 2026-06-28

**Root cause:** the gateway (`hermes.exe`) and shim (`python.exe`) both run out of the same
`hermes-agent\venv` that `hermes update` replaces; as Scheduled Tasks they had no auto-restart,
so an update left them down (the NSSM relay survived because it has a separate `.venv` +
auto-restart). This was the recurring "update knocks `:8642`/`:8765` offline" outage.

**Fix shipped:**
1. Gateway + shim **converted from Scheduled Tasks to NSSM services** (LocalSystem, Automatic,
   `AppRestartDelay 5000`) via `~/.hermes/scripts/convert-gateway-shim-to-nssm.ps1`. Both run as
   `LocalSystem` with injected env (`HERMES_HOME`, `LOCALAPPDATA`, `APPDATA`, `USERPROFILE`) so
   the profile-dependent launchers work and `API_SERVER_KEY` stays in `.env` (never the
   registry). Old Scheduled Tasks **disabled, not deleted** (rollback).
2. `~/.hermes/scripts/hermes-update-safe.ps1` — stops gateway+shim, runs `hermes update`, then
   restarts with a warmup-aware verify (gateway answers ~15–20s after start); the relay stays up.
   **Use this instead of bare `hermes update`.**

**Recovery if ever down (supersedes the old `Start-ScheduledTask` note):**
`Start-Service HermesGateway,TalariaModelsShim`, then confirm `:8642`/`:8765` return 404/401.

### 24j. ✅ bookstack MCP registration bug — RESOLVED 2026-06-28

Found in the gateway log during the 24i verification. `config.yaml` had
`args: '["O:/Hermes/BookStackMCP/build/bookstack-mcp-server.js"]'` — a **string** that looks
like a JSON array — so Pydantic rejected it (`StdioServerParameters.args` expects a list) and
bookstack failed all 3 connection attempts on every gateway start. Environment-independent (not
caused by the NSSM conversion). Fixed to a real YAML list
`args: ["O:/Hermes/BookStackMCP/build/bookstack-mcp-server.js"]`; YAML re-validated; config
backed up; confirmed no bookstack error in the post-fix startup.

---

## 25. 🔧 CTX meter — 0% fixed (usage parsed); denominator reads ~1.4x high

**Update 2026-06-28 (Owen):** the meter now shows a live, non-zero reading — the 0% bug is
resolved. The denominator still reads ~1.4x high; **left open pending further testing**
before the model → context-window map is corrected.

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

**Resolved 2026-06-27.** Verbose Logging shipped & wired (#29, committed 9d3972f); Mock
Responses dropped from the Developer screen (#28).

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

Build: SUCCEEDED (Debug, iOS Simulator, Xcode-beta). Committed (2468471); SYSTEM index validated on whoGoesThere 2026-06-27. Logged 2026-06-26.

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

**Update 2026-06-27 — committed (9d3972f).** 27 diagnostic sites (LiveSpeechService 26,
SensorUploadService 1) routed through `TalariaLog.verbose`; error/warning/`.notice` kept
always-on. Verified on whoGoesThere — the Verbose toggle emits real `.notice` and gated
diagnostics fall silent when off. Remaining (minor): sync the flag from settings at launch.

Logged 2026-06-26.

## 30. ✅ Removed dead monolith `SettingsScreen.swift`

The #28 index swap makes `Talaria/Features/Settings/SettingsScreen.swift` unreachable
(its only entry was `ContentView` `.settings`, now repointed; its internal TEMP preview
links to the sub-screens go with it). Keep it as dead code until the SYSTEM index is
validated on whoGoesThere, then delete the file + run `xcodegen generate`.

**Done 2026-06-27 (7ae4643):** SYSTEM index validated on whoGoesThere → `git rm` +
`xcodegen generate`; ContentView comment fixed.

Logged 2026-06-26.

---

## 31. 🔧 Paste image into the chat composer (clipboard) — UI built & verified; HELD, blocked on image transmission (#43)

**Update 2026-06-28 (on-device, whoGoesThere):** the paste UI works — the button shows in the
composer and pasting attaches the image correctly. Switched from a `hasImages`-gated button to
an **always-visible, read-on-tap** button because background pasteboard detection is unreliable
(a `RunCodeSnippet` probe couldn't read the clipboard from the non-foreground harness). **But
sending fails:** an image-only send returns `HTTP 400`, because the chat client never transmits
attachments — `ChatTurnBody` is text-only, so an image-only turn POSTs `input: ""` and the API
server rejects it. Picked photos hit the identical wall; **not paste-specific, not a regression.**
Root fix tracked as **#43**. The paste UI is built but **held uncommitted** until #43 lands —
shipping a paste button that 400s is worse than not shipping it.

**Implemented 2026-06-28 (compiles clean; not yet device-verified).** Added a clipboard
paste affordance to `ChatInputBar`: a `doc.on.clipboard` button appears in the composer's
action bar whenever `UIPasteboard.general.hasImages` is true (seeded on appear, refreshed on
`scenePhase` active + `UIPasteboard.changedNotification`). On tap, `pasteImageFromClipboard()`
reads `UIPasteboard.general.image` and routes it through `onPasteImage` →
`ChatScreen.handleAttachmentResult(.image(_))` → `PendingAttachment.image(_)` — the *same*
path the photo picker uses, so pasted and picked images are byte-identical downstream (same
768px downscale, 350 KB cap, 4-attachment limit, local staging). Files: `ChatInputBar.swift`,
`ChatScreen.swift`.

On-device (whoGoesThere, 2026-06-27): pasting an image from the clipboard into the chat
input does nothing, while adding an image from the local photo store works. Add clipboard
paste support to the composer.

**Feasible — yes.** The photo-picker path already proves the app can attach + send image
data, so the missing piece is only an ingest route from `UIPasteboard`:
- A paste handler / "Paste" affordance on the input that reads `UIPasteboard.general.image`
  (and image-type items) and routes the data into the same attachment pipeline the photo
  picker feeds.
- Mirror the local-store path's size/encoding limits and send payload, so pasted and picked
  images are indistinguishable downstream.

Reported on-device 2026-06-27. Feature gap, not a regression.

## 32. ✅ SiriKit deprecation audit (forked shell) — CLEAN

**Status:** Resolved 2026-06-27 — no SiriKit usage; nothing on the deprecation clock.

**Why:** WWDC26 (2026-06-09) gave SiriKit a formal deprecation notice — App Intents is now
the only path for Siri to reach a third-party app (~2–3yr support window before removal).
Talaria forks `dylan-buck/Hermes-iOS`, so any inherited SiriKit code would have been on that
clock.

**Audit (Mac Mini repo, 167 Swift files):** grep for `import Intents` / `import IntentsUI`,
`INExtension`, `INIntent`, `INInteraction`, `IntentsSupported`,
`com.apple.intents-(ui-)service`, `*.intentdefinition`, and `intent` in `project.yml`
→ all absent. Positive control (`import SwiftUI` → 68 files) confirms the search reached the
sources. No App Intents adoption present either.

**Action:** None — note and close. Future Siri reachability (optional) is clean greenfield
App Intents 2.0 adoption (Siri AI / Spotlight / Shortcuts discoverability) — additive,
complementary to the in-app voice work, not a migration.

Logged 2026-06-27.


---

## 33. 📝 Apple app integrations — device-side (universal) + Hermes connectors (Mac-host only)

Idea (Owen, 2026-06-27): let the agent work with Apple apps. iOS reality splits these
into two layers, and the layer decides where the capability lives:

- **Device-side (universal — any backend host):** Calendar + Reminders via iOS EventKit.
  These live on the phone, so they work no matter which machine hosts Talaria's Hermes —
  buildable on the current OJAMD (Windows) backend. Needs full-access usage strings
  (`NSCalendarsFullAccessUsageDescription`, `NSRemindersFullAccessUsageDescription`),
  ties into the Permissions screens + #23 (revoke). Writes want a confirm gate — reuse
  the #4 confirm-dialog pattern.
- **Server-side (Mac-host only — additive):** iMessage + Notes + FindMy via Hermes's
  macOS-CLI connectors (`imsg`, `memo`, FindMy.app). They shell out to macOS binaries,
  so they only function when Talaria's backend runs on a Mac → gated on T6 (#34). No
  iOS-native path (no chat.db / AppleScript / Messages automation on iOS); the "key" is
  macOS session state — signed-in iMessage + Full Disk Access + Automation TCC + SMS
  forwarding — not a portable token. On Windows (OJAMD) these connectors' check_fn fails,
  so they're inert there.

Also from the original list: Mail has no iOS inbox-read API (compose-sheet send only;
true read/send would be a server-side provider API on Hermes — Gmail/Graph/IMAP). Maps
is device-side MapKit utility (search/geocode/directions/open), not personal-Maps-data read.

Near-term scope if pursued = device-side EventKit only. Connectors land with T6.

Logged 2026-06-27.


---

## 34. 💤 T6 — Mac-hosted Talaria backend (unlocks additive Apple connectors) — LATER

**Deferred rationale (Owen, 2026-06-28):** hold until the app is closer to feature-complete —
don't ship an incomplete Mac-hosted version. Revisit once the active open items resolve.

Milestone (Owen, 2026-06-27), explicitly deferred until the rest of the open-items list
is squared away. Re-home Talaria's full backend stack — models shim (:8765), relay/
connector (:8000), gateway (:8642), and any sidecars — onto the Mac Mini (macOS Hermes)
as the primary host, with the same reboot-proof hardening built for OJAMD but in macOS
terms (launchd / login items instead of NSSM / Task Scheduler).

Why: macOS Hermes exposes connectors Windows Hermes can't, so a Mac-hosted install gets
the additive layer — iMessage, Notes, FindMy — on top of the universal device-side
Calendar/Reminders (#33). The host OS is effectively the feature flag: Windows install =
device-side baseline; Mac install = baseline + connectors.

Scope: re-home + harden on macOS; install / boot-survival testing on the Mac; wire #33's
server-side connectors once the Mac backend is live. Forks (or partly reverses) the
OJAMD-as-production consolidation (→ #1) — accepted as the cost of the richer feature set.

Optional accelerator (if iMessage is wanted before full re-homing): keep OJAMD primary
and expose just the mini's Apple toolset to it via `hermes mcp serve` (mini) → `hermes
mcp add` (OJAMD) over the tailnet — "Windows brain, Mac hands." Not planned now; noted so
it isn't rediscovered later.

Deferred 2026-06-27 — revisit after the active items clear.

## 35. 🎙️ VOICE settings screen — build truthful status/launch panel

**Status:** Design resolved 2026-06-27 (truthful); SwiftUI build pending.

**Context:** First Design pass (`Voice_dc.html`) modeled a fictional on-device
`SpeechTranscriber → AVSpeechSynthesizer` pipeline (voice picker, rate/pitch, speak-replies,
PTT) — none of which exist. The real Talk engine (`LiveVoiceSessionService`, ~1185 LOC) is a
realtime WebRTC speech-to-speech session: relay readiness → relay bootstrap (ephemeral
clientSecret + RealtimeSession) → WebRTC peer → Hermes; transcripts persisted via relay,
latency tracked, image-send supported. Live controls (mute, interrupt, camera, end) already
live in `VoiceOverlayScreen`; model/voice are server-driven and READ-ONLY in the iOS surface
(no client set-voice — `VoiceSessionServiceProtocol` has none).

**Corrected design:** New `Settings_dc.html` → "05 · VOICE — status & launch" (TALK ENGINE ·
REALTIME): read-only STATUS + a START VOICE SESSION action; fictional controls removed
(verified — no AVSpeech / Speak-Replies / PTT / SpeechTranscriber / Rate / Pitch / Barge).
Good to build from.

**Action:** Build the SwiftUI VOICE status/launch screen from the new design. Bind real fields,
`"—"` where unknowable — host online / configured / ready + blockedReason (readiness), model
(selectedModel, read-only), server voice + voiceContextUpdatedAt (read-only), last-session
latency (TalkLatencyMetrics). START gated on `canStartSession` → presents `VoiceOverlayScreen`.
Retire `Voice_dc.html`. Run `xcodegen generate` after adding the file.

**Out of scope (future):** user-selectable voice would be a new relay + iOS feature (server-side
today); separate from this build.

**Insertion point (confirmed 2026-06-27):** No Voice/Talk entry exists in the live Settings
feature (10 screens: System, Uplink, Models, Sessions, Diagnostics, Appearance, Notifications,
Privacy, Developer, Relay) — verified by grep; voice mode launches only from chat
(`ChatInputBar`) + `AppEntry` via `router.isVoiceOverlayPresented`. So this is a clean tactical
insertion: add `VoiceSettingsScreen` + a "Voice & Talk" row in `SystemSettingsScreen`
(`// EXPERIENCE`) that drills into it; START sets `isVoiceOverlayPresented = true` gated on
`canStartSession` (reuses the existing launch path). `xcodegen generate` after adding the file.

Logged 2026-06-27.


---

## 36. 📝 Reconcile OJAMD's Talaria checkout onto the ChronoRixun fork

OJAMD's `O:\Hermes\Talaria` tracks **`dylan-buck/Hermes-iOS` `master`** (the upstream
parent), not Owen's `ChronoRixun/Talaria`. As of 2026-06-27 it is **0 ahead / 65 behind**
`fork/main` — a strict ancestor, so a fast-forward is clean. Crucially, **those 65 commits
change nothing in `relay/` or `connector/`** (all iOS-app + docs), so OJAMD's running
service code is already byte-identical to the fork; a sync would only drop iOS-app files
into the checkout.

**Decision (Owen, 2026-06-27):** repoint now, defer the FF. The `fork` remote
(`ChronoRixun/Talaria`) has been **added** on OJAMD (non-destructive). Do the one-time clean
reconciliation **after Tier 2 merges to `main`**, in a single pass:
1. `git stash` the lone local mod (`connector/.../mcp_registration.py` — see #37) + the
   hand-applied Tier 2 relay edits.
2. Repoint `master` → track `fork/main` (or check out `main` from `fork`).
3. `git pull` (by then includes Tier 2, subsuming the hand-applied edits).
4. `git stash pop` and reconcile `mcp_registration.py`.

**Must NOT be clobbered** during any sync: live `.env`, `hermes_mobile.db` (+ `-shm`/`-wal`),
`connector/.hermes/`, `relay/logs/`, `connector/logs/`, untracked debug scripts — all are
gitignored/untracked and a FF leaves them alone, but verify before any reset.

**Status 2026-06-28:** still **blocked / low-priority** — the one-pass reconciliation waits on
Tier 2 merging to `main`. This is one of the two remaining OJAMD blockers; it gates the
canonical-`shim.py` redeploy (#14 caveat / 24g).

Logged 2026-06-27.

---

## 37. 📝 Upstream the connector `win32` fix to the fork

`connector/src/hermes_mobile_connector/mcp_registration.py` is modified **only on OJAMD**
(not in the fork). The change makes `_hermes_chat_running()` Windows-compatible: the upstream
version shells out to `ps -axo` (Unix-only); the OJAMD edit adds a `sys.platform == "win32"`
branch using `tasklist /FO CSV /NH`. This is a legitimate cross-platform fix that a blind
re-sync would silently revert.

**Patch saved** (durable, outside the repo): `C:\Users\Owen\.hermes\scripts\connector-win32-chat-running.patch`
(33 insertions / 25 deletions). **Action:** apply the same edit to the fork's
`connector/.../mcp_registration.py` on the Mac, commit, push — then it's part of `main` and
survives the #36 reconciliation.

**Status 2026-06-28:** still open, low-priority (not blocked). The Mac-side apply/commit/push
can be done independently of #36; doing it before the reconciliation lets the FF subsume the
OJAMD-local edit cleanly.

Logged 2026-06-27.

---

## 38. 📌 Remote push (APNs) for instant background-run completion notify — deferred

**Context:** The agent-run background-completion fix (detach + reconcile + local
notification, on `feat/agent-files-tier2`) handles the common case — an interrupted
run no longer errors; it reconciles on resume via `GET /api/sessions/{id}/messages`,
and a local notification fires when completion is detected. A background `URLSession`
download task against the sync endpoint lets iOS hold a *deliberately-backgrounded*
send across lock and relaunch with the result for up to ~a couple minutes.

**Gap this covers:** guaranteed *instant* "answer ready" notification while the phone
is locked/pocketed for a run that was started in the foreground and then walked away
from (not issued through the background-download path) and that outlasts the ~30s
background-task window. Such a run reconciles cleanly on resume but cannot buzz the
user while suspended — iOS offers no client-side way to fire a notification from a
server-side completion event while the app is suspended. The only reliable path is a
remote push.

**Design when picked up:** Hermes/relay fires APNs on `run.completed`; app registers
for remote notifications and sends its device token to the relay at pair time; push
payload carries `session_id`; tap deep-links and fetches via `GET /messages`. Depends
on the relay persisting the device registry across restarts (#24f) and ties into the
NOTIFICATIONS settings screen (#10).

**Verified prerequisite (2026-06-27):** runs already complete server-side after SSE
disconnect and persist — a push only needs to announce an already-finished result.
Probe: client cut at 8s mid-run (only `run.started`/`message.started` had streamed);
the final assistant message (`finish: stop`) landed in the session post-cut, twice.
Reconciliation endpoint confirmed: `GET /api/sessions/{id}/messages`.

Logged 2026-06-27. Deferred — local-notification path is sufficient for now.

---

## 39. ✅ Motion & Fitness authorization shows "off" on every launch — fixed + verified + committed

**Fixed 2026-06-28 — verified on whoGoesThere (Motion & Fitness reads Enabled and stays correct across force-quit + relaunch); committed as `f84dc19`.** Confirmed root cause:
`LiveMotionService.authorizationStatus` initialized to `.notDetermined` and was only updated
inside `requestAuthorization()`; `PermissionsStore.reloadCapabilities()` refreshed
location/health/notifications from the system but **omitted motion**, so the Privacy row kept
rendering the stale in-memory value after a cold launch. Fix: added
`LiveMotionService.refreshAuthorizationStatus()` (maps `CMMotionActivityManager.authorizationStatus()`
→ `PermissionStatus`; CoreMotion's static persists the real grant across launches, unlike
HealthKit reads), seeded it from a new `init()`, and added `motionService?.refreshAuthorizationStatus()`
to `reloadCapabilities()`. Files: `LiveMotionService.swift`, `PermissionsStore.swift`.

**Settings → Privacy → Motion and Fitness** displays the toggle/status as **disabled**
each time the app launches, even though iOS Settings (System Settings → Talaria →
Motion & Fitness) correctly shows it as **on**.

**Likely root cause:** same pattern as #16 (HealthKit) — `CMMotionActivityManager`
authorization status is **in-memory only** and resets to `.notDetermined` on each
process launch. Apple's read-privacy model returns `.unknown` or `.notDetermined` for
`CMMotionActivityManager.authorizationStatus()` until the system permission sheet has
been presented in *this process*. If `LiveMotionService` gates its "authorized" display
on that in-memory value without re-checking via the actual CMMotion API, it will always
show "off" after a cold start.

**What to check:**
- `LiveMotionService.authorizationStatus` initialization — does it reset to
  `.notDetermined` in `init()` even when permission was previously granted?
- Is `CMMotionActivityManager.authorizationStatus()` called on launch to seed the
  displayed state, or only after a fresh `requestActivityUpdates()` call?
- Compare pattern with #16 fix: `SensorUploadService.start()` now re-asserts
  `requestAuthorization()` on each launch for HealthKit; Motion may need the same.

**Repro:** fresh cold launch → Settings → Privacy → Motion and Fitness → shows off.
Go to iOS Settings → Talaria → Motion & Fitness → shows on.

Reported on-device 2026-06-28.

---

## 40. ✅ Theming refactor — runtime accent re-skin shipped

**Closed 2026-06-28 (Owen).** The `Design.Brand` / `Design.Colors` migration off hardwired
static constants landed, and `AppearanceSettingsScreen` preferences now drive the app live
(accent theme, glow, grid, reduce-motion, voice orb, Theme row unlocked). Tracked during the
build in `THEMING_REFACTOR_PROMPT.md`; shipped in `9076381` (runtime accent foundation) and
`a9007ce` (wire glow/grid/reduce-motion + voice orb + unlock Theme row). Recorded here for the
closure trail.

---

## 41. 🔧 Keychain-back the relay pairing config so reinstalls don't drop pairing

**Diagnosed 2026-06-28 on whoGoesThere.** A device "lost pairing" event was traced to a
wholesale wipe of the app's `.standard` UserDefaults container — an on-device read showed
`hermes.pairedRelayConfiguration` ABSENT and **zero** `hermes.*` keys remaining (not a targeted
loss, not a decode failure). Cause: iOS did a **clean install** (delete + data wipe) instead of
an upgrade install — the signature of a provisioning/cert rotation or an iOS 27 beta reinstall
quirk. Backend, relay, bundle ID (`org.aethyrion.talaria`), app group
(`group.org.aethyrion.talaria`), entitlements, and pairing code were all verified unchanged, so
this is **not** a code regression.

**Why fix:** session tokens already persist in the Keychain (`KeychainSecureStore`, service
`org.aethyrion.talaria.session`), which **survives reinstalls** — but `PairedRelayConfiguration`
is persisted **only** in UserDefaults (`UserDefaultsAppPersistenceStore`, key
`hermes.pairedRelayConfiguration`), which a clean install wipes. `PairingStore.isPaired` keys
solely off that config, so a container wipe forces a full re-pair even though the tokens were
sitting safe in the Keychain the whole time.

**Fix:** mirror (or move) `PairedRelayConfiguration` into the Keychain so it survives reinstalls.
- Write to both stores on `pair()`; clear from both on `disconnect()` / `clearLocalPairing()`.
- On load, prefer Keychain, fall back to UserDefaults, and re-hydrate UserDefaults from the
  Keychain copy when only it survived (the reinstall-recovery path).
- Net: a UserDefaults wipe like tonight's no longer costs a re-pair; also protects Shelley
  (TestFlight) across build/signing transitions.

Found via on-device `RunCodeSnippet` forensics 2026-06-28.

## 42. 📝 Pairing-config loader silently swallows decode errors

`UserDefaultsAppPersistenceStore.load(_:key:)` (generic loader, ~line 120) uses
`try? decoder.decode(...)`, so any decode failure returns `nil` with no log. For
`loadPairedRelayConfiguration()` that means a future `PairedRelayConfiguration` schema change
would present as a **silent unpair** — identical symptom to a container wipe, with nothing in
the log to tell them apart.

**Fix (low priority):** in the decode-failure branch, `os_log` the type + key + error before
returning nil (route through the Verbose Logging seam, #29). Diagnostics only, no behavior
change. Not the cause of the 2026-06-28 wipe (that container was genuinely empty), but it would
have turned tonight's triage into a one-line log read instead of an on-device probe.

---

## 43. 🔧 Wire image attachments into the Hermes API-server chat payload (unblocks #31 + photo picker)

**Diagnosed 2026-06-28 on whoGoesThere.** Image attachments — pasted or picked — never reach
Hermes. `SessionsHermesClient.send()` and `sendStreaming()` accept `attachments:
[PendingAttachment]` but never serialize it; the body is always `ChatTurnBody { let input: String }`
(text only), POSTed to `/api/sessions/{id}/chat` and `/chat/stream`. Consequences:
- image **with text** → normal reply, image silently dropped;
- image **with no text** → `input: ""` → API server rejects the empty turn → **HTTP 400**
  (the "Hermes API returned status 400" seen when sending a paste-only message).

Not paste-specific, not a regression — the photo picker hits the same wall; image
**transmission** on the clean-chat `:8642` path was simply never built.

**Gate — probe before building (verification-first):**
- Does `/chat` / `/chat/stream` accept a structured `input` (content blocks) or only a string?
- What image shape does it want — base64 + `media_type`? an `image_url` / `source` block? a
  separate `attachments` / `images` field?
- Does the configured text model (Kimi K2.6 / MiniMax) accept image input at all, or is
  multimodal only wired on the WebRTC voice path?

**Then build:** extend `ChatTurnBody` (or a multimodal variant) to carry each image attachment's
`base64Data` + `mimeType` in the confirmed shape; respect the 350 KB per-image / ~1 MB aggregate
body limits.

**Net:** unblocks #31 (paste) and makes the photo picker actually send images. Found via
on-device send test + client read 2026-06-28.

