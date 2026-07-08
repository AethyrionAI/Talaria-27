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

## 11. ✅ Settings back-nav exits Settings instead of popping — resolved by T3 redesign (#28)

**Resolved by the T3 Settings redesign (#28, 2026-06-28).** The monolith `SettingsScreen.swift` was replaced with a proper NavigationStack sub-screen architecture; back-nav now pops within the Settings stack as expected.

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

## 15. ✅ In-app sensor diagnostics panel — built + reconciled onto main + live on device


**Reconciled 2026-07-02 (session results, verified):** Built 06-28 (`c5f01a4`) as a Sensors section in Settings → Diagnostics (`sensorDiagnostics` snapshot + `recordDrain`). It was NOT missing/reverted — it lived only on the local lineage while the tested builds ran on the origin (Fable) lineage (see #48). Cherry-picked onto canonical main during the 07-02 reconcile; on-device log confirmed drain/delivery. Owen was right — he seen't it.

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

## 17. ✅ Relay sensor delivery — RESOLVED end-to-end (crash + identity + RPC pump), confirmed on device


**Reconciled 2026-07-02 (session results, verified):** Three stacked failures, all fixed on OJAMD 07-02: (1) connector crash-looped on `UnicodeDecodeError` (cp1252) reading Hermes CLI output — patched 12 `subprocess` sites with `encoding='utf-8', errors='replace'` + `PYTHONUTF8=1` (→ #37); (2) phone re-paired onto a stale/revoked relay user after reinstall — re-paired to the live user (→ #46); (3) `talk.prewarm` RPC ran synchronously in the websocket recv loop, blocking heartbeats past the 30s timeout so the relay killed the session — detached RPCs to `asyncio.create_task`/`to_thread`. Confirmed two ways: live Hermes MCP query returned fresh location (39s) + steps/HR, and on-device drain log showed `deliveryState=delivered wasDelivered=true` with #24a chunking. All connector changes are UNCOMMITTED on the OJAMD checkout (→ #24, #36).

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

## 23. ✅ Add a "revoke permissions" affordance

**Verified on device 2026-07-05:** revoke affordances present and toggleable (GitHub #6, PR #19). Closed.

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

> **2026-07-04 (evening):** the NSSM service architecture described in 24c/24h/24i has been
> **reverted** -- see **#55**. Startup-folder scripts are the production launch path again and
> `hermes-update-safe.ps1` was rewritten for that world. 24e and 24f remain the open
> server-side gaps (24f now has a cousin in #54).

Consolidated tracker for server-side fixes on OJAMD (Windows desktop, Tailscale
`100.110.102.59`). None of these are app code — they require work on the OJAMD host.

### 24a. ✅ Health upload — chunking shipped + delivering (confirmed on device 2026-07-02)


**Reconciled 2026-07-02 (session results, verified):** iOS chunks health drains to ≤100 samples/request with 2/4/8s backoff. On-device log 07-02: `drain: health chunk (7 of 7 pending) → delivered`, outbox drains to 0. The earlier 'still blocked' state was #17's connector crash, now fixed — end-to-end health delivery verified.

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

**Update 2026-07-06 — mostly stale; one config check left.** The description above matches
the pre-rewrite relay. The relay that's been live on OJAMD since the #37 deploy is this
repo's DB-backed one: auth is opaque tokens hashed into the `auth_sessions` table, and
devices/push registrations are SQLAlchemy rows — there is no JWT signing secret and no
in-memory registry to lose. What remains is deployment hygiene: `DATABASE_URL` defaults to
`sqlite:///./relay.db` **relative to the service's working directory**, so pin it to an
absolute path in the live `.env` (see `relay/docs/APNS_OJAMD.md`, which folds this into the
#38 deploy — use the CURRENT live relay.db location; repointing it orphans pairings). After
one restart-survives-pairing test on OJAMD, close this. (#38's push watches are
intentionally in-memory — the app re-posts them — and don't reopen this item.)

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

> **SUPERSEDED 2026-07-04 by #55.** Updates kept tanking under this arrangement: nssm stops
> left detached venv processes (incl. a LocalSystem `hermes.exe` zombie) holding install-tree
> locks, and the services raced the Startup-folder scripts at boot. The conversion below is
> retained for history only.

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

**Device verification 2026-07-05: FAILED** (GitHub #4, PR #21 insufficient). New symptom set:
CTX shows **0 on some sessions**, **absent entirely on older sessions**, and occasionally
**flashes in** before reading wrong. Working theory: the meter only populates from a fresh
`run.completed` usage payload in the live session -- nothing seeds it when resuming/loading
history, and the denominator source remains unvalidated. **Next:** ground-truth against
Hermes's built-in context check (Owen investigating which surface exposes it), then capture
one live session with Verbose Logging + `run.completed` payloads to pin numerator vs denominator.

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

## 29. ✅ Verbose Logging — downstream adoption complete (launch sync + call sites)

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

## 31. ✅ Paste image into the chat composer — unblocked by #43, reconciled onto main

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

**Update 2026-07-06:** the greenfield is now populated — `StartVoiceSessionIntent` (Wave 1)
and `AskHermesIntent` (#56 / Wave 2 Issue E), both registered in the single
`TalariaAppShortcuts` provider; Control Center controls wrap them (#58).


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

## 35. ✅ VOICE settings screen — built + Host ONLINE confirmed on device


**Reconciled 2026-07-02 (session results, verified):** Two implementations existed (origin 251-line + local 204-line); origin's is canonical (kept in reconcile). On device 07-02 after the #17 connector fixes: Host **ONLINE**, voice **BALLAD**, live voice-context age. Remaining NOT CONFIGURED is truthful host config (→ #47 OpenAI Realtime), not a bug.

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

## 37. 🔧 Connector win32/encoding fix — APPLIED on OJAMD 2026-07-02 (12 sites, uncommitted on that checkout); upstreaming to the fork still pending

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

**Status 2026-07-04:** The **encoding** half (cp1252 `UnicodeDecodeError` on Hermes CLI output) now has a **durable** mitigation: the connector runs as the new `HermesMobileConnector` NSSM service (resolves GitHub #8 "NSSM-ify the connector") with `PYTHONUTF8=1` baked into `AppEnvironmentExtra`, so a manual `hermes-mobile run` without the env var can no longer resurface the crash. Verified 07-04: service Running/Automatic, `Last error: none`, sensors fresh (location 572s; 6/11 health metrics). The **source-level** patches (the subprocess `encoding=` sites + the `mcp_registration.py` win32 branch) remain uncommitted/unversioned on OJAMD — the durable fix is the service env, not the source; committing the source to the fork is still pending for #36/upstream.

**Status 2026-07-04 (evening):** the `HermesMobileConnector` NSSM service was removed in the
#55 reversion, so the `PYTHONUTF8=1` service-env mitigation is gone with it. The env moved to
the launcher: `start-connector.bat` (and `start-relay.bat`) now set `PYTHONIOENCODING=utf-8`,
but that variable does **not** cover the subprocess *pipe* decode that produced this crash
(cp1252 in `subprocess.py`'s reader thread) -- `PYTHONUTF8=1` must be added to both bats and
the connector restarted. **Queued as the first task of the next OJAMD pass (see #55).** The
source-level commit + upstream remains pending regardless.

Logged 2026-06-27.

---

## 38. 🔧 Remote push (APNs) for instant background-run completion notify — BUILT, needs OJAMD config + device verify

**Update 2026-07-06 (cloud session, branch `claude/notifications-implementation-t7ame7`):**
full pipeline implemented — nothing was deployed or device-verified (no Xcode/OJAMD from
the cloud). What shipped:
- **Relay (the never-existed piece):** `POST /v1/push/watch {sessionId}` + `/v1/push/watch/cancel`
  (device bearer auth). Chat never transits the relay, so the app names the session it
  detached from and the relay polls the gateway (`GET /api/sessions/{id}/messages`, new
  `relay/app/gateway.py`, env `GATEWAY_BASE_URL`/`GATEWAY_API_KEY`) until a non-empty
  assistant message follows the transcript's last user message — positional watermark,
  all server-clock, mirrors the app's reconcile predicate. On completion → APNs alert
  (existing `apns.py` client, extended with `payload_extra` → `session_id` rides the
  payload root; sandbox host updated to `api.sandbox.push.apple.com`), presence-gated,
  410 auto-deactivates. Watch requests flip the device to `background` so presence can't
  race the separate app-state report. Poll 3s → 10s after 2 min, TTL 30 min, in-memory
  registry (app re-posts after relay restart). 72/72 relay tests green (9 new in
  `test_push_watch.py`).
- **App (archive scaffolding ported onto current main + new watch calls):**
  `UNUserNotificationCenterDelegate` (foreground banner + tap → new
  `AppContainer.handleNotificationTap(sessionID:)` — routes to chat, `openSession(sid)`
  when the payload names one, reconciles); silent-wake now reconciles chat;
  `ChatStore.onRunDetached/onRunResolved` + `pendingRunSessionId` drive
  `postPushWatch`/`cancelPushWatch` (gated on notifications toggle + registered token);
  background scenePhase also posts the watch; Diagnostics Push Token row tap-copies the
  token (312960b port). No new Swift files — no xcodegen regen needed.
- **Remaining:** OJAMD `.env` config (the stored `.p8` + Key ID + Team ID + `GATEWAY_API_KEY`)
  + relay redeploy + the verification ladder — full runbook in `relay/docs/APNS_OJAMD.md`.
  Production APNs for TestFlight → #8.

**Observed 2026-07-05:** notifications permission prompt now appears (the #44 plumbing) and,
once granted, backgrounding the app during a run yields **no completion notification** --
expected, since this item is deferred, but worth noting: a **local**-notification variant
(schedule/fire while the app still holds background runtime; no APNs, no server work) could
ship independently and cover the common short-run case before remote push exists.

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

**Exploratory branch archived (2026-07-03):** the app-side APNs spike — `feat/apns-push` (Option B: remote-notification receive plumbing, the missing `aps-environment` entitlement, and tap-to-copy push token in Diagnostics) — was tag-archived at `archive/apns-push-20260703` (pushed to origin) and the branch deleted during repo cleanup. Push *delivery* still isn't wired (no `.p8`), but the receive scaffolding is reusable when this is picked up. Restore: `git switch -c apns-push archive/apns-push-20260703`.

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

## 41. ✅ Keychain-back the relay pairing config — shipped + survived delete/reinstall on device

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

## 42. ✅ Pairing-config loader — decode failures now logged

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

## 43. ✅ Image attachments wired into the Hermes API-server chat payload — reconciled onto main

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

**Update 2026-07-06:** the NON-image half of this pathology (text-MIME files staged but
silently never transmitted) is now closed too — #57 (Wave 2 Issue G) inlines them as
delimited `{type:"text"}` parts, with in-band omission stubs instead of silent drops.

---

## 44. ✅ Notifications — truthful push-token readout + `aps-environment` entitlement (VERIFIED on device)

Fixed on the Fable batch (`c097a8d`), on origin/main, verified 07-02. `Talaria.entitlements` was missing `aps-environment` (no APNs token issued); added `development`. Settings→Notifications and Diagnostics unified on `AppContainer.PushTokenPipelineState` (notIssued/awaitingRelay/registered). On device both read **RELAY REGISTERED**. Push *delivery* still deferred (needs `.p8`, → #38). **Caveat:** `aps-environment=development` is dev/sandbox — a TestFlight/Release build needs production (→ #8). **Trap found 07-02:** `xcodegen generate` STRIPS `aps-environment` from the entitlements (it's not declared in `project.yml`) — fix project.yml or don't regenerate without restoring it (→ #48).

---

## 45. 🔧 CarPlay voice mode — scaffold on main, gated on Apple's voice-conversational entitlement

Working CarPlay voice scaffold exists in `Talaria/CarPlay/` (`CarPlaySceneDelegate` + `CarPlayVoiceManager` bridging `TalkStore` → `CPVoiceControlTemplate`); scene declared in `project.yml`, `audio` background mode present. Can't run on device without the CarPlay entitlement (managed capability; new **voice-based conversational apps** category, requestable from iOS 26.4). App Store distribution NOT required — a granted entitlement works on a development profile — but the grant is discretionary; only way to know is to file at `developer.apple.com/contact/carplay/`. Functional gap (sim-testable without grant): the manager only reflects `TalkStore`, never starts a session — needs auto-start on connect + WebRTC↔AVAudioSession routing. Depends on voice working on the phone first (→ #47). Full reference + weekend sim plan in `CARPLAY.md`.

**Update 2026-07-07:** the functional gaps are worked as Wave 5 GitHub #19 → **#74**
(auto-start on connect, observation tracking, routing re-assert, local entitlement
key). #18 (→ #73) lifts the server half of the gate — local voice needs no OpenAI
key. Remaining here: the actual Apple grant filing once sim validation passes.

---

## 46. ✅ Reinstall resurrects a stale Keychain identity (post-#41)

**Verified on device 2026-07-05 (happy path):** delete + reinstall -> signed in without
re-pairing, persisted identity valid and functional (GitHub #3, PR #22). The *stale*-identity
branch is only exercisable by invalidating the identity server-side; if it ever recurs,
reopen with the relay-side state at time of failure.

Discovered 07-02, bit us immediately. After delete+reinstall the app came back authenticated as a **revoked** relay user (`15deb25d…`) instead of the live user (`707547ee…`) — #41's Keychain persistence preserved a dead identity. Consequence: sensors 202-forever + 'Connect a Hermes host' on VOICE, while chat (direct :8642) worked — a half-broken app with no obvious cause. **Needs (app-side):** on `pair()`, overwrite/clear ALL prior credentials in the Keychain (no stale survivors); store relay `user_id` with the pairing and validate on session restore (surface 're-pair' if the relay reports no active host for that user); Diagnostics (#15) should show the authenticated relay `user_id`. **Workaround:** unpair (clears both stores) → `hermes-mobile.exe pair-phone` on OJAMD → re-pair. Test-gap note: the dropped test suite covered a clear-on-disconnect guard for exactly this — see `handoffs/RECONCILE_TEST_GAP.md`.

---

## 47. 🎯 Configure OpenAI Realtime talk on the Hermes host (voice enablement)

Last gate to working voice. After the #17 fixes, `talk/readiness` truthfully reports `hostOnline:true, configured:false` — 'OpenAI Realtime is not configured on this Hermes host.' Per `client.py:_rpc_talk_session_create`, talk needs `realtime_talk.enabled` + an `openai_api_key` in the connector secrets (`~/.hermes-mobile` on OJAMD). Voice already reports BALLAD + live context, so everything downstream is warm. **Owen-gated** (needs an OpenAI key with Realtime access; billed per audio minute — worth a cap). Also unblocks CarPlay voice (#45).

**Update 2026-07-05 (GitHub #7 — "entered the settings but still not configured", root-caused + fixed):** the issue's own setup notes say to put `realtime_talk.enabled` in the connector **secrets** store — but the connector only ever read that flag from `state.json`, and `ConnectorSecrets(**data)` crashed with a `TypeError` on ANY unknown key in a hand-edited `secrets.json`, killing every `talk.prewarm` RPC. A key placed in the Hermes settings (`~/.hermes/.env` `OPENAI_API_KEY`) was never read either, and a stale "OpenAI API key is not configured." `last_validation_error` in `state.json` blocked readiness even after a key appeared. Connector fixes (branch `claude/issue-7-hermes-config-08bsbm`): tolerant state/secrets deserialization (unknown keys ignored); `realtime_talk.enabled` honored from `secrets.json` (flat, nested, or dotted-key shapes); API-key resolution falls back secrets → `OPENAI_API_KEY` env → `$HERMES_HOME/.env`; stale no-key validation error auto-cleared once a key exists; readiness `blockedReason` now distinguishes "no key found" from "talk disabled". **Needs OJAMD redeploy of the connector to take effect.** Billing cap + CarPlay E2E remain open on the GitHub issue.

---

## 48. 🔧 Repo hygiene — lineage divergence cleanup + xcodegen entitlements trap + logging polish

**Lineage divergence (root cause of days of 'didn't we already do this?'):** local `main` and `origin/main` forked at `cf50688` (06-28 16:43) and evolved in parallel — Fable's branch was merged to origin via PR #1, while a separate local session committed 12 different commits implementing the SAME items (#35/#41/#24a) differently, never pushed. The Mac's local checkout also hadn't fetched in days, hiding it. **Resolved 07-02:** chose origin as canonical, reset local main to `origin/main` + cherry-picked the genuinely-unique local work (#31 paste, #43 image serializer, #15 sensor panel), dropped local's redundant #41 approach. Full local lineage preserved at tag `prereconcile/local-main-20260702`. Build verified on device.
- **Prevention (TODO, → item for next session):** write `BRANCHING.md` — canonical-main rule, mandatory `git fetch` + divergence check at session start, one-lineage-at-a-time. Parallel Claude sessions must not both commit to main-equivalents.
- **xcodegen trap:** `xcodegen generate` regenerates entitlements from `project.yml`, which does NOT list `aps-environment` — so every regen silently drops the #44 push entitlement. **Fix project.yml to declare it**, or never redeploy after a bare `xcodegen` without restoring the entitlements.
  **Update 2026-07-03:** project.yml now declares `aps-environment: development` (done on the theming branch `claude/theming-options-plan-c4356l`, required because the theme system adds new files → mandatory regen). Trap closed for dev builds; the TestFlight/production switch (#8) still applies.
- **Low-pri polish:** on-device drain log shows `collectSnapshot returned nil (auth=authorized)` interleaved with successful captures — health callbacks fire faster than HealthKit has a queryable sample; self-correcting, log noise only. Consider debouncing or downgrading that log line.

---

## 49. 🔧 Theme system — four drastic themes built on `claude/theming-options-plan-c4356l`; needs Mac build + device verify

**Built 2026-07-03** (cloud session, plan reviewed + revised in `design/THEME_SYSTEM_PLAN.md`). A THEME (Deep Field / Solar Forge / Terminal / Paper Tape) now owns the whole color environment; the accent picker's three persisted slots (`cyan`/`amber`/`violet` raw values, unchanged — zero migration) are re-interpreted per theme with slot `.cyan` always the theme's hero hue (Cyan Arc / Forge Amber / Phosphor Green / Tracker Red). Shipped on the branch:
- `Shared/ThemePaletteCore.swift` — single source of truth for all 4×3 palettes, compiled into app + widgets (project.yml `Shared` sources); `Color(hex:)` moved here.
- `ThemeRuntime.theme` + all `Design.Brand`/`Design.Colors` tokens palette-computed; `cyanHairline`→`hairline`, `cyanBorder`→`strongBorder` (62 call sites). Deep Field × cyan byte-identical (guarded by `TalariaTests/DesignThemeTests.swift`).
- Textures (embers / scanlines / paper grain — seeded Canvas, motion gated behind Reduce Motion, no flicker), `GridOverlay` lines/dots/rules, per-theme `ReactorOrb` drawings, theme picker cards in APPEARANCE with contextual accent labels.
- Paper Tape (light): root `preferredColorScheme` follows `theme.isLight`; `hudGlow` × `palette.glowScale` (0.15 on paper); danger/scrim/ink variants.
- Widgets: Status + Health migrate to `AppIntentConfiguration` with a per-widget `WidgetTheme` (default Match App ← `HermesWidgetData.appearanceTheme`, BOTH copies updated in lockstep); app root reloads timelines on theme/accent change. Accessories + Live Activity untouched. CarPlay untouched (system templates).

**Remaining (Mac session):** `xcodegen generate` (project.yml now also declares `aps-environment` → #48 trap closed) → CLI build → fix any compile stragglers (written without a Swift toolchain) → run `DesignThemeTests` → device pass: Deep Field pixel-identity, then Solar Forge / Terminal contrast, then Paper Tape legibility (bubbles, code blocks, keyboard/sheets), widget gallery + edit-sheet theme picker. Deviation from plan: Deep Field ships with NO starfield texture (pixel-identity trumped the optional dots).

**Update 2026-07-05 — palette-core de-dup (GitHub #49) executed** (cloud session, branch `claude/theme-palette-dedup-4cdc35`, 5 commits, one theme per commit per the handoff sequencing). `ThemePalette(theme:accent:)` now resolves from `ThemePaletteCatalog` data (Shared) — zero per-theme switch arms in resolution; Terminal's #12 pin is `lockedAccentSlot` data; `AppearanceTheme` collapsed to a thin id (displayLabel ← catalog `displayName`, isLight ← palette data); accent labels are per-slot variant data; `ReactorOrb` dispatches on new `palette.orbStyle` (drawing stays in the view); `WidgetTheme` arms collapsed. Byte-identity verified by *execution* on Linux (mock `SwiftUI.Color` preserving construction paths; old vs new file, 4×3 slots, 364 properties — zero diffs), plus label/flag parity checks. No files added/removed → **no xcodegen needed**. Owed to the Mac: Xcode build + `DesignThemeTests`/`ThemeCatalogTests` + device theme-cycle pass — see `design/THEME_PALETTE_DEDUP_HANDOFF.md` status block.

## 50. 🐛 Terminal theme must not offer accent options — lock to Phosphor Green

**Found 2026-07-03** (Owen, reviewing `claude/theming-options-plan-c4356l` on device). The Terminal theme's identity *is* the phosphor green — reassigning its accent (Amber · Phosphor / Cyan · IBM) just recolors it into a generic themed screen and throws away what makes it Terminal. Terminal should expose NO accent choice; the green is the whole point.

**Fix (two parts):**
- **Hide the accent row for Terminal.** In `Talaria/Features/Settings/AppearanceSettingsScreen.swift`, gate `accentSection` (body VStack ~L40; section defined ~L212) to render only when `theme != .terminal`. The theme picker (`themeSection`) stays.
- **Pin Terminal's resolved slot to the hero.** Hiding the UI isn't enough: a user who picked `.amber`/`.violet` under another theme, then switches to Terminal, would still resolve `ThemePalette(theme: .terminal, accent: <stored slot>)` → amber/IBM, not green. Force the *effective* accent slot to `.cyan` (Phosphor Green hero) whenever the active theme is Terminal, at the single palette-resolution point (`ThemeRuntime` / `ThemePalette(theme:accent:)`), so app + widgets + the Appearance preview all stay green. Leave the *persisted* `appearanceAccent` untouched so switching back to Deep Field / Solar Forge / Paper Tape restores the user's prior accent.
- **Widgets:** apply the same pin when a widget's `WidgetTheme` explicitly resolves to Terminal (not just Match App).

**Acceptance:** Appearance shows no `// Accent` row while Terminal is selected; selecting Terminal always renders Phosphor Green regardless of the stored slot; switching away restores the prior accent; `DesignThemeTests` still green (Deep Field × cyan pixel-identity untouched). Small follow-up to #49; lives on the same theming branch.

## 51. 🔧 CLI `build-for-testing` can't resolve TalariaTests' test host — blocks CLI test-compilation validation

**Found 2026-07-04** (Mac, reviewing Fable's PRs). `xcodebuild build` of the `Talaria` app scheme succeeds, but `xcodebuild build-for-testing -scheme Talaria` fails with `Could not find test host for TalariaTests: TEST_HOST evaluates to ".../Debug-iphonesimulator/Talaria.app/Talaria"` — identically on `generic/platform=iOS Simulator` and on a concrete simulator id, and after a fresh `xcodegen generate`. So it is NOT the stale scheme (#52) and NOT a destination issue; the app target builds fine standalone. `project.yml` looks correct (`TalariaTests` = `bundle.unit-test`, `dependencies: [target: Talaria]`, app `scheme.testTargets: [TalariaTests]`), so xcodegen should auto-wire TEST_HOST/BUNDLE_LOADER — the failure is downstream of that.

**Impact:** PR reviews on the Mac can compile/verify the app target from the CLI but cannot compile the *test* targets — so test additions (e.g. the store PRs appending to `AppStoresTests.swift`) are diff-reviewed but not CLI-compiled. Xcode's GUI test runner resolves the host differently, so in-app test runs are unaffected.

**Next:** inspect the generated `TalariaTests` build settings (actual TEST_HOST/BUNDLE_LOADER values) and whether the app target is built as a dependency of the test action; compare against a known-good xcodegen unit-test setup. Until fixed, PR reviews use the app-build + diff bar and Owen runs the suite in Xcode.

## 52. 🔧 Committed `Talaria.xcscheme` is stale vs `xcodegen generate`

**Found 2026-07-04** (Mac). On clean `main`, `xcodegen generate` rewrites `Talaria.xcodeproj/xcshareddata/xcschemes/Talaria.xcscheme` (the pbxproj itself was already current), so the committed scheme has drifted from `project.yml`. Minor hygiene; did not resolve #51. **Fix:** regenerate and commit the scheme (or fold into the standing post-checkout xcodegen step), file-scoped.

## 53. 🐛 Sensor drain — a stuck location upload starves the health outbox

**Found 2026-07-04** (on-device, during connector-outage testing). `SensorUploadService.drainOutboxIfPossible()` drains location first and `break`s the entire loop on a location `.failed`, so it never reaches the health block. When location persistently returns `deliveryState=retry` (connector down / busy / forward stalled), the health outbox climbs unbounded even though health itself is fine — observed 475→481+ live. `LocationUploadOutcome` has no `.retry` case, so a transient `retry` is mis-mapped to a hard `.failed` that wedges the loop. **Fix (iOS, Fable):** a location failure must not `break` past health; give location its own transient retry/backoff (mirror health's `.retry` handling); drain the two outboxes on independent passes so neither can starve the other. Distinct from #24a (that was a poison *health* sample wedging health; this is the *location* path wedging health). GitHub issue snippet drafted.

## 54. 🔧 Relay restart forces connector re-attach — host session not auto-recovered

**Found 2026-07-04** (OJAMD, during the #15 relay hotfix). When `HermesMobileRelay` restarts (deploy/hotfix), it drops the connector's host WebSocket with close code 1012 (service restart). The connector does not reliably self-reconnect, and a subsequent reconnect can hit a transient **4401** — the relay still holds the stale host session from the unclean drop. Until the connector is restarted, sensor forwards return `deliveryState=retry` and no sensor data flows, which then wedges health app-side (→ #53). Root-caused this session: the 07-04 relay restart for #15 left the connector in exactly this state for hours. **Mitigations (in place):** operational — always restart the connector after a relay bounce (the new "Restart All" desktop shortcut does this in dependency order, and the connector NSSM service from GitHub #8 auto-restarts on crash). **Durable fix (server-side, #24f-adjacent):** persist the host-connection nonce so a relay restart doesn't force re-enroll/4401, and/or evict a stale host session promptly so a reconnect isn't rejected; connector-side, add auto-reconnect with backoff on 1012/4401. GitHub issue snippet drafted.
**Update 2026-07-04 (evening):** the mitigations shifted under #55 -- the `HermesMobileConnector`
NSSM service no longer exists (so "service auto-restarts on crash" no longer applies), and the
"Restart All" desktop shortcut references deleted services and needs rework for the
Startup-script world (queued in #55). The durable server-side fix (persist/evict the
host-connection nonce; connector auto-reconnect with backoff) remains open.

---

## 55. 🔧 OJAMD service layer reverted to out-of-the-box (nssm removed); safe-update rewritten

**Context (2026-07-04 evening session).** Updates kept tanking even via `hermes-update-safe.ps1`,
requiring manual intervention every time, and `HermesGateway` sat Paused in services.msc while
the gateway showed connected in Hermes. Audit findings on OJAMD:

- **Three competing launch layers** existed for the same components: nssm services (LocalSystem,
  Auto), the disabled S4U Scheduled Tasks, and the **Startup-folder scripts**
  (`Hermes_Gateway.vbs`, `Hermes_Relay.cmd`, `Hermes_Connector.cmd`) -- and the Startup scripts
  were the *actual* production path: port `:8642` was owned by the VBS-launched gateway, not the
  Paused service.
- The Paused `HermesGateway` service held a live **LocalSystem `hermes.exe` zombie** with locks
  inside `hermes-agent\venv` -- unkillable from an unelevated shell; the true update-tanker.
- The relay was **down** (`:8000` closed; last clean shutdown 19:03) and the standalone connector
  had been dead since 07-02 (the #37 cp1252 crash) -- the sensor path was broken and unnoticed.
- `HermesMobileConnector` (created earlier the same day by a parallel session per #37 /
  GitHub #8) was itself nssm-wrapped -- rediscovered here without provenance; a coordination
  gap. **Rule reinforced: pull live OPEN_ITEMS.md before any OJAMD remediation.**

**Decision (Owen):** revert to out-of-the-box, login-time startup through Hermes itself;
add capabilities back only on proven need. Keep the shim service; keep the relay service dormant.

**Executed 2026-07-04 (all verified):**
1. Zombie tree killed; **`HermesGateway` and `HermesMobileConnector` services deleted**
   (elevated; transcript at `C:\Users\Owen\.hermes\logs\service-removal-20260704.log`).
2. **`HermesMobileRelay` set to Disabled** -- dormant fallback per Owen, cannot race the
   Startup script at boot. `TalariaModelsShim` untouched (Running/Auto) -- still earns its keep.
3. `start-relay.bat` / `start-connector.bat` patched (backups `.bak-20260704`):
   `PYTHONIOENCODING=utf-8` + a launch **breadcrumb** to
   `C:\Users\Owen\.hermes\logs\launcher-breadcrumbs.log` (diagnoses any future silent
   login-launch failure). Relay + connector relaunched; **sensor path restored** (Owen
   smoke-tested green; phone traffic observed on `:8000`).
4. **`hermes-update-safe.ps1` rewritten** (old script at `.bak-20260704`): stops the shim,
   gracefully closes the Hermes desktop app, then a **kill-and-verify loop** over every process
   holding the hermes install tree -- matched by executable path / command line *including* the
   PYTHONPATH-injected system-Python processes (`hermes_cli`, `tui_gateway` matchers) that the
   old script's `Get-Process hermes` could never see -- aborts if the tree will not clear, runs
   `hermes update`, relaunches via the normal login-time launchers (shim service, gateway VBS,
   connector bat; relay stays up throughout). Supports `-DryRun`; parse-clean; dry-run validated
   with the full expected kill list.

**Remaining (next OJAMD pass):**
- [ ] Add `PYTHONUTF8=1` to both bats (see #37 status note -- `PYTHONIOENCODING` does not cover
      the subprocess pipe decode) and restart the connector.
- [ ] Rework or retire the "Restart All" desktop shortcut (references deleted services); its
      replacement should encode #54's dependency-order restart (relay -> connector).
- [ ] Reboot + login validation: check `launcher-breadcrumbs.log` fired and all four ports come
      up (`:8642` allows 15-20s warmup). The 19:03-19:04 event timeline is not yet fully
      explained (manual stops vs. relogin); breadcrumbs will settle it.
- [ ] First real `hermes-update-safe.ps1` run (note: it closes + relaunches the desktop app).

**Rollback:** disabled S4U Scheduled Tasks retained; `HermesMobileRelay` service retained
(Disabled); nssm binary untouched at `O:\Hermes\nssm\nssm.exe`; all replaced files have
dated `.bak` copies.

Logged 2026-07-04.

---

## 56. 🔧 Wave 2 Issue E (GitHub #6) — "Ask Hermes" App Intent — BUILT IN CLOUD, not compiled

**Shipped (`3ef4695`, branch `claude/issues-5-8-batches-cue3vb`, 2026-07-06).**
`Intents/AskHermesIntent.swift`: background Siri/Shortcuts query (`openAppWhenRun = false`)
through `ChatStore.sendMessage` — the exchange lands in the cached conversation and widgets
update; answer returned as spoken dialog (2-sentence/280-char summary) + HUD-styled snippet +
`ReturnsValue<String>` for Shortcuts chaining. 25 s budget: on expiry the run is NOT cancelled —
Siri says "still working", the reply lands in-app (pendingRun/reconcile). Failures throw the
REAL error text into Siri UI. Siri Stop → `cancelStreaming()`. Registered in the single
`TalariaAppShortcuts` provider ("Ask Talaria" — free-form Strings can't ride phrases, Siri
prompts for the question). Tests: `AskHermesIntentTests`.

**Tier B parked:** `AskHermesLongRunSupport.swift` holds the iOS 27 beta
`LongRunningIntent`/`CancellableIntent` adoption ENTIRELY behind `#if TALARIA_IOS27_INTENTS`
(defined nowhere). Mac session: verify every "iOS 27 beta API" comment against the beta SDK,
then add the flag to `SWIFT_ACTIVE_COMPILATION_CONDITIONS` to enable.

**Mac-session checklist:** `xcodegen generate` (new files; re-verify `aps-environment` — #44/#48)
→ CLI build → run tests → device: Siri short answer, >25 s run hand-off, stop button,
`hermes://chat` deep link, exchange visible in app, tailnet-unreachable error.

**Questions for Owen:** (1) "Ask Talaria" prompting for the question (vs. one-breath phrase —
impossible for String params) OK? (2) Snippet is always Deep-Field-styled (system process can't
read live theme) OK? (3) ~~Known edge: process death mid-run loses the cache write~~ —
**resolved 2026-07-06 (Owen approved):** ChatStore now persists the optimistic turn BEFORE
streaming starts, and cold load finalizes stranded `.sending` user turns to `.failed` (retry
affordance; same terminal as polling exhaustion) + scrubs cached streaming placeholders. The
reply of a completed-but-killed run still needs a session refresh to appear (pendingRun/session
id don't survive process death — persisting the API session id is a session-lifecycle decision,
deliberately not taken here). Tests: `ChatStorePersistenceTests`. (4) Shortcuts chaining value
is "" on still-working paths.

Logged 2026-07-06.

---

## 57. 🔧 Wave 2 Issue G (GitHub #8) — attachment text-inlining + Extract Text OCR — BUILT IN CLOUD, not compiled

**Shipped (`25bf98c`, 2026-07-06).** Fixes the #43 remainder: staged text-MIME files now reach
the agent as delimited `{type:"text"}` parts instead of silently dropping.
`Services/Support/AttachmentInlining.swift` owns assembly (ordering, 900 KB aggregate budget,
200 KB per-file cap with in-block truncation notice, omission STUBS instead of silent drops;
text-only turns stay byte-identical plain strings) — unit-tested (`AttachmentInliningTests`, 13)
and the shared surface #9 voice memos ride. Explicit per-chip "Extract text" (context menu —
never auto; confirmed decision) runs Vision `RecognizeDocumentsRequest` (iOS 26 GA) with
`RecognizeTextRequest` fallback, isolated in `Services/Support/DocumentTextExtractor.swift`;
PDFs stage to 10 MB (never transmit raw), rasterize per-page via PDFKit, OCR into `## Page N`
sections. Honest UI: un-extracted PDF = forge badge + banner + send held; sent bubbles render
text chips for inlined files, thumbnails only for images that actually shipped.

**Mac-session checklist:** build; verify the Vision API shapes flagged
"verify against SDK on Mac" in DocumentTextExtractor (DocumentObservation containers: transcript
/ tables / lists / barcodes / detectedData accessors); run AttachmentInliningTests; device:
.txt/.md/.csv/.json reach the agent, Extract Text on a screenshot + a multi-page PDF, UI truth.

**Questions for Owen:** (1) Budget-omitted attachments now tell the agent in-band (stub) — OK?
(2) Extraction failure = alert + chip stays for retry; want a persistent per-chip error state?
(3) Oversized/unsupported picks still silently don't stage (pre-existing) — worth a toast?

Logged 2026-07-06.

---

## 58. 🔧 Wave 2 Issue F (GitHub #7) — Control Center / Lock Screen controls — BUILT IN CLOUD, not compiled

**Shipped (`db9a03a`, 2026-07-06).** `TalariaWidgets/Controls/HermesControls.swift`: "Ask
Hermes" + "Talk to Hermes" `ControlWidget` buttons (iOS 18 GA) in `HermesWidgetBundle` —
Control Center gallery, Lock Screen, Action-button picker. Deliberate architecture: the app's
real intents are NOT shared into the extension (they'd drag `AppContainer` in, and control
intents perform in the EXTENSION process where router state is meaningless); extension-local
`isDiscoverable = false` intents launch the app via `OpenURLIntent` on `hermes://chat` /
`hermes://voice`, running exactly the code paths the real intents use. `hermes://voice` deep
link gained sheet-clearing parity with `StartVoiceSessionIntent` (real fix). iOS 27
`ExecutionTargets.main` upgrade path noted in comments. Polish: `systemExtraLargePortrait`
added to `HermesStatusWidget` — public docs still list the symbol as visionOS; if the beta SDK
rejects it, it's a flagged one-line deletion.

**Mac-session checklist:** build (watch the `systemExtraLargePortrait` line) → device: controls
in gallery after reinstall (+ unlock; don't judge failure from an immediate look), Lock Screen +
Action button assignment, taps open the right surfaces. Action-button test needs an
Action-button iPhone.

**Questions for Owen:** dedicated extra-large-portrait status-widget layout later, or is the
stretched small layout fine?

Logged 2026-07-06.

---

## 59. 🔧 Wave 2 Issue H (GitHub #9) — voice-memo attachments — BUILT IN CLOUD, not compiled

**Shipped (`3aa638a`, 2026-07-06).** Record (`VoiceMemoRecorder` — AVAudioRecorder, AAC mono,
real metering, session held only while recording) → transcribe fully on-device
(`VoiceMemoTranscriber` — DictationTranscriber `.longDictation` + SpeechAnalyzer
`analyzeSequence(from: AVAudioFile)`, accumulating EVERY finalized result so multi-minute memos
don't truncate; iOS 27 `AssetInputSequenceProvider` deliberately not used) → review sheet
(playback + transcript preview + "SENDS AS TEXT") → staged as a text/plain attachment whose
`data` IS the transcript (bracketed provenance header: recorded time + duration) — ships through
#57's inlining branch with zero send-path changes. Audio never transmits; additive optional
`voiceMemoAudioPath` on Pending/MessageAttachment (pre-#9 caches still decode) keeps it playable
from the staged chip and the sent bubble via shared `VoiceMemoPlayer` — play affordance only
renders while the file exists. Honest failures: mic denied / transcription error / Talk session
owns audio. Tests: `VoiceMemoAttachmentTests`.

**Mac-session checklist:** build; verify `.longDictation` preset name and
`analyzeSequence(from:)` / `finalizeAndFinish(through:)` shapes (flagged in-file); run tests;
device: multi-minute memo end-to-end offline (airplane mode: record → transcribe → stage →
play), then send over tailnet; confirm finalized-result concatenation spacing on a real memo.

**Questions for Owen:** (1) Review-before-attach step (vs. auto-attach on transcription) OK?
(2) Removing a staged memo chip orphans its audio/transcript files on disk (consistent with all
attachments today) — worth a sweep task later?

Logged 2026-07-06.
## 60. 🔧 Wave 3 / 4.15 — `_thinking` reasoning channel surfaced; delta key needs device probe

Reasoning deltas are no longer dropped at the `tool.progress` handler:
`SessionsHermesClient` forwards `tool_name:"_thinking"` payloads as
`StreamingUpdate.reasoningDelta`, `ChatStore` accumulates them on the streaming
placeholder, and the Hermes bubble shows the newest line verbatim under the
typing dots, then a collapsed **Reasoning** chevron row after the turn
(expanded = raw reasoning, selectable). Raw reasoning + its one-line summary
persist on `Message` (`reasoning` / `reasoningSummary`, decodeIfPresent — old
caches fine) and survive server refreshes (the stored transcript filters
`_thinking`, so the merge preserves the local copy). Mock client streams demo
reasoning so the UI is exercisable without a host.

**Unverified:** the exact delta-text key inside the `tool.progress` payload.
The parser tries `delta`/`content`/`text`/`message`/`preview`, then
`args.{delta,content,text}` (`SessionsHermesClient.thinkingDelta`, unit-tested
for all spellings). **Next OJAMD session:** run a reasoning-model streaming turn
with `curl -N` and pin the real key; if it's something else entirely, add it to
the chain. `<think>…</think>` fold-in splitter (CLEAN_CHAT_PATH Phase 2
fallback) deliberately not built — no observed need on the Sessions API.

Written cloud-side 2026-07-06 (branch `claude/wave-3-on-device-intelligence-rxht4l`);
not yet compiled — needs `xcodegen generate` + CLI build + device verify.

**Update 2026-07-06 (same-session adversarial review pass, 8 finder angles + verify):**
- **Wire-mode hedge added:** whether `_thinking` events carry increments or cumulative
  snapshots is as unverified as the delta key. `incrementalReasoningDelta(from:assembled:)`
  forwards only the new suffix when a chunk starts with everything assembled so far
  (unit-tested both modes) — cumulative hosts can no longer duplicate text quadratically.
- **Late reasoning kept:** reasoning now attaches to the final message at the yield
  (run.completed / stream-end fallback) from the full accumulator, not frozen at
  assistant.completed.
- **Interrupted runs keep their reasoning:** the `.interrupted` path captures the
  placeholder's partial reasoning onto the pending run and re-attaches it when reconcile
  adopts the server reply (the server transcript filters `_thinking`).
- **Blank-row guard:** a whitespace-only `_thinking` stream no longer renders an empty
  Reasoning chevron row; `lastReasoningLine` also rewritten as a backward scan (the split
  version was O(N²) across a long think). Foreground condensation now drains up to 3
  pending replies per pass instead of only the newest.

## 61. 🔧 Wave 3 / 4.8 — on-device titles + previews via FoundationModels

New `Services/Live/LocalIntelligenceService.swift` (FoundationModels): after the
first completed exchange, `ChatStore` generates `{title, preview}` on-device and
writes through `setConversationTitle`; the preview lands on
`Conversation.generatedPreview` (persisted; surfaced in the `/title` readout).
Runs only while the title is still the `Conversation.defaultTitle` placeholder —
a manual `/title` is never overwritten. Same service condenses #60's reasoning
to one line when foregrounded (also caught up on foreground return via
`AppContainer.handleAppDidBecomeActive`).

- Input trimming: `SystemLanguageModel.contextSize` (back-deployed 26.0; 8192 on
  iOS 27 hardware) minus headroom; measured with `tokenCount(for:)` behind an
  `#available(iOS 26.4, *)` guard (chars/3 conservative estimate below it).
  API signatures verified against Apple docs JSON 2026-07-06.
- Model unavailable (non-AI hardware, Apple Intelligence off, model
  downloading) → deterministic truncation fallback (first meaningful lines,
  word-boundary caps; fenced code never becomes a title). Unit-tested.
- Guided generation via `@Generable` struct; guardrail/context errors also fall
  back to truncation. Titles stay local — no Sessions-API title write (the API
  has no verified endpoint for it; candidate follow-up).

Same not-compiled caveat as #60. Device verify: first exchange in a fresh chat
titles itself (~seconds later, `/title` shows Title + Preview); reasoning row
collapses to a generated one-liner on AI hardware, last raw line otherwise.

**Update 2026-07-06 (same-session adversarial review pass):**
- **Critical fix — title/preview merge revert:** `mergeConversationMetadata` now preserves
  the local conversation title (when the refreshed base still has the placeholder) and
  `generatedPreview`. Without this, every post-turn merge into the Sessions client's empty
  `currentConversation` reverted the title to "Hermes" — re-tripping the generation gate
  every turn — and wiped the preview. Also fixes the long-standing quirk of a manual
  `/title` reverting on the next exchange. Regression-tested
  (`mergeKeepsLocalTitleAndPreviewOverPlaceholderBase`).
- **Attachment-only first turn:** the synthetic "[N attachment(s)]" display placeholder is
  no longer eligible as a title source (`normalizedRetryContent` maps it to "" — card
  derives from the reply instead).
- Placeholder-title literals consolidated onto `Conversation.defaultTitle` at every
  construction site; token budget deduped (`promptInputBudget`); tokenizer round-trip
  skipped when `utf8.count <= budget` (every token ≥ 1 byte); fallback card computed
  lazily off the happy path.

## 62. 🔧 Wave 4 — stale test expectations fixed (GitHub #13 → PR #20)

Test-only surgical pass, per the issue: `permissionTypeHasDistinctColorsAndIcons`
now asserts icon uniqueness against `PermissionType.allCases.count` (the enum
grew 6 → 8 and the literal staled); the streaming-failure recovery test renamed
to `...WhenStreamingInterruptedAfterJobAccepted` and rewritten against the
current semantics — the mock yields `.interrupted` and implements
`reconcileFromServer()`, with one reconcile pass driven deterministically via
`reconcilePendingRuns()` (the 2s loop is never slept on). No product code.
Expected 163/163 after the Mac test run.

## 63. 🔧 Wave 4 — native background wake: BGAppRefreshTask + BGContinuedProcessingTask (GitHub #14 → PR #22)

First BackgroundTasks usage. `Services/Live/BackgroundTaskService.swift`:
`BackgroundRefreshScheduler` registers in `didFinishLaunchingWithOptions` and
arms on scene background entry; each pass re-arms first, then runs
`AppContainer.handleBackgroundRefresh()` — sensor pipeline start + health
snapshot + outbox drain, one `reconcilePendingRuns()` pass (the existing
"Hermes finished" local notification fires on found completions), widget-data
rewrite. Positioned honestly: discretionary safety net complementing relay
APNs, never real-time. Attachment sends (the #38 long path) ride a
`BGContinuedProcessingTask` — submitted in-foreground from the user's send,
progress advanced per accept/delta/tool event (capped 95; cap-then-stall on a
very long tail is a known trade), expiration finalizes via `cancelStreaming()`.
Config: `fetch` background mode + `BGTaskSchedulerPermittedIdentifiers`
(`…talaria27.refresh` + `…talaria27.continued.*`) in project.yml AND the
materialized Info.plist. **Needs Mac:** compile-check
`BGContinuedProcessingTaskRequest.strategy` naming + `register` return handling;
re-verify `aps-environment` post-regen (#44/#48); device-verify with the
BGTaskScheduler `_simulateLaunchForTaskWithIdentifier` debugger trigger. Known
limitation (pre-existing): `pendingRun` doesn't survive process death, so a
cold BG launch has nothing to reconcile by design.

## 64. 🔧 Wave 4 — health widget tiles query HealthKit directly (GitHub #15 → PR #21)

`Shared/HealthQueryCore.swift` (compiled into app + widget targets, same
pattern as ThemePaletteCore): cumulativeSum / latest-sample / sleep-duration
primitives, the shared query windows (start-of-day rollups, 24h HR look-back,
wake-day sleep bucket), and `loadWidgetMetrics()` for the four tiles.
`HermesTimelineProvider` gains `queriesHealthKit` (health widget only): each
timeline pass overlays live values onto the App Group snapshot; all-empty
results — which is also what denied read-auth and a locked device
(`errorDatabaseInaccessible`) produce — fall back to the snapshot untouched,
deliberately with NO auth check (the #16 gotcha; widgets can't prompt).
`LiveHealthService` delegates its primitives to the core (statics kept as
forwards — its tests untouched). Widget target gains the HealthKit entitlement
declared in project.yml (strip trap applies to this target's own entitlements)
+ mirrored .entitlements + purpose string. `HealthQueryCoreTests` added.
**Needs Mac:** build, then device-verify tiles advance with the app killed and
show the snapshot (not blanks) when locked. Freshness bounded by the WidgetKit
reload budget (~40–70/day) — honest ceiling.

## 65. 🔧 Wave 4 — AlarmKit executor: /alarm behind the confirm gate (GitHub #16 → PR #23)

Phase 1 of the phone-side-tool pattern (zero server work). `/alarm` registered
in `SlashCommand.localCommands`; `Services/Live/AlarmService.swift` parses
durations (`25m`, `1h30m`, `90s`) → countdown timers and wall-clock forms
(`6:30`, `6:30pm`, `18:45`, `7pm`, standalone am/pm folding) → next-occurrence
alarms; bare numbers rejected as ambiguous; tail tokens = label. Nothing
schedules silently: the request is STAGED and a value-carrying
`confirmationDialog` in ChatScreen must be confirmed before
`AlarmService.schedule` runs (decided policy — the fast-follow relay-sidecar
`phone_alarm` tool inherits the same gate). Countdown presentation renders via
`TalariaWidgets/TalariaAlarmLiveActivity.swift` — its OWN ActivityConfiguration
typed on `AlarmAttributes<TalariaAlarmMetadata>` (metadata in `Shared/`), never
a new case on the Hermes activity. `NSAlarmKitUsageDescription` added (user
auth only; no App Store entitlement). `AlarmCommandParsingTests` pin the
grammar. **Needs Mac:** AlarmKit API surface is new (iOS 26) — compile-check
`AlarmManager.AlarmConfiguration` labels, `AlarmPresentationState.mode` cases,
`AlarmAttributes.metadata` optionality; device-verify ring through Silent mode
+ the countdown Live Activity.

## 66. 🔧 Wave 4 — Spotlight IndexedEntity donation + OpenSessionIntent (GitHub #17 → PR #24)

First AppEntity surface. `Intents/SpotlightEntities.swift`: `ChatSessionEntity`
(id = Sessions API string id) + `AgentFileEntity` (#21 Tier 1 staged files —
file attachments on HERMES-sent messages; user uploads stay out) as
`AppEntity + IndexedEntity`; queries resolve from the last-donated cache
(sessions mirrored to UserDefaults) so "open that" survives relaunch without a
network hop. `Services/Live/SpotlightIndexingService.swift` donates via
`CSSearchableIndex.indexAppEntities`, gated on EVERY path by
`UserSettings.spotlightIndexingEnabled` (default OFF, decode-fallback OFF —
the privacy trade is explicit opt-in); toggle-off calls
`deleteAllSearchableItems` + cache teardown, so no orphaned entries. Donation
triggers: session-list fetches (`ChatStore.onSessionsLoaded`), conversation
changes (fresh agent files), and an immediate fill when the toggle flips on.
`OpenSessionIntent` (OpenIntent) routes through `hermes://session/{id}`;
`AppEntry.handleDeeplink` gained the `session` case → Chat tab +
`openSession(id)`. PRIVACY screen: "System Search" panel.
`SpotlightIndexingTests` added. **Needs Mac:** compile-check the iOS 18
`indexAppEntities`/entity-query shapes; device-verify Spotlight find →
tap-through → right session, and that toggling off removes results. Note:
`hermes://` has no `CFBundleURLTypes` registration — in-app `OpenURLIntent`
routing doesn't need it (same as the #7 controls); external openers would.
Fast-follow (own issue): View Annotations on `MessageBubble`/`ChatScreen` +
entity ids on the finished-notification.

## 67. 🔧 Wave 4.5 — LocalChatBackend: on-device chat brain (GitHub #26)

The standalone chat brain: `Services/Live/LocalChatBackend.swift` conforms to
`HermesClientProtocol` backed by Apple FoundationModels, so ChatStore /
read-aloud / persistence / sessions drawer work unmodified. One
`LanguageModelSession` per conversation, lazily created; history replayed as a
hand-built `Transcript` on restore (cache-restored via the ChatStore-owned
UserDefaults conversation cache — standalone history is local-only by design).
Context window read at RUNTIME (`model.contextSize`, never hardcoded); when a
conversation approaches it, older turns condense through
`LocalIntelligenceService.trimmed/measuredTokenCount` (made internal for
reuse) into an instructions-appended memory block + recent verbatim turns, and
`.exceededContextWindowSize` triggers exactly one condense-and-retry — overflow
degrades to summarized memory, never errors. FM snapshots are cumulative →
`streamDelta` diffs them into `StreamingUpdate.textDelta`; snapshot rewrites
yield no delta and the finished message carries the authoritative final text.
`GenerationError` → plain-language `.failed` strings; availability reasons →
honest explanation states. Token usage only from `LanguageModelSession.usage`
(iOS 27) — never estimated. `switchModel` responds "Context: N tokens" so the
#4 CTX denominator parses it. Tool-less by design (#28 wires the belt);
NOT wired into AppContainer yet (#27 router does that).
`LocalChatBackendTests` pin the deterministic layer. **Needs Mac:**
compile-check (verified against Apple's live SDK docs 2026-07-07, but not
against the installed 27-beta SDK): `Transcript.Instructions/Prompt/Response/
TextSegment` init labels, `ResponseStream` iteration element (`snapshot.content`),
`session.usage.input/output.totalTokenCount` (27 beta), `Prompt(_:)` wrapping,
and the changed `tokenCount(for: Instructions(...))` call in
LocalIntelligenceService (docs say Instructions, Wave-3 code had Prompt).
Device checklist (after #27 lands the router): airplane mode + Hermes never
configured → streamed answer in MessageBubble + read-aloud; kill/relaunch →
conversation continues with context; Apple Intelligence off → honest
unavailable state; no SessionsHermesClient regression.

## 68. 🔧 Wave 4.5 — ChatBackendRouter: two brains, one seam (GitHub #27)

`Services/Support/ChatBackendRouter.swift` conforms to `HermesClientProtocol`
and fronts BOTH clients — ChatStore is untouched structurally (its
`hermesClient` is now the router). Rules (Owen 2026-07-06): never-configured
device → local unconditionally (no pairing wall); Hermes configured → Hermes
wins; `connectionStatus == .error` at send time → new turns route local; NO
silent mid-thread swap (`runningBrain` locks the run; routing evaluated per
new message; `lastRunBrain` keeps `currentConversation` pointed at the
backend that produced the turn for ChatStore's post-turn merge). Routing
signal = Sessions API key present (`hermesAPIKeyBox`); picker-visibility
signal = paired OR keyed. Brain preference is per-conversation, persisted in
UserDefaults (`talaria.chat.brainPreferences`); a pick made before any
conversation exists lands in a "next" slot that migrates onto the first
conversation that sends. Explicit Hermes pin fails honestly on a dead
gateway (never rerouted). `Message.brain` (new optional Codable field)
stamps every finished assistant message; `MessageBubble` shows an
ON-DEVICE / PCC β mono tag (Hermes stays untagged); chat header gains the
always-visible brain chip (menu picker once a host exists: Automatic /
Hermes / On-Device); Settings → Models gains the same picker. Clearing a
conversation clears BOTH sides so a stale Hermes session id can't
resurrect. AppContainer builds local backend + router at the old
hermesClient wiring site; key save/restore calls `refreshActiveBrain()`.
`ChatBackendRouterTests` cover routing, migration, tagging, cache
round-trip. **Questions for Owen:** the picker includes "Automatic" (not in
the issue's three-entry list) — without it a pinned conversation could never
return to auto routing; and Settings→System/Uplink "direct chat" status now
reflects the ACTIVE brain (reads .connected while routing local) — rename
that row, or pin it to the Hermes side? **Needs Mac:** compile + device:
fresh sim install chats instantly with ON-DEVICE chip; pairing makes picker
appear + Hermes default; gateway kill mid-run fails honestly then next
message routes local with visible chip change; gateway restart returns
routing within one ~10s health tick.

## 69. 🔧 Wave 4.5 — device tool belt v1: read tools for the local brain (GitHub #28)

`Services/Live/DeviceTools/` — Swift `Tool` conformances handed to the local
brain's `LanguageModelSession` (device-side mirror of the Hermes MCP tools;
READ set only, #29 adds the confirm-gated writes). `ToolEventRelay` bridges
invocations onto `StreamingUpdate.toolActivity`, so the #10/#11 chip UI
renders local tool calls with zero ChatStore changes (backend points
`relay.emit` at the live continuation per turn). Belt: readHealth (rides
`HealthQueryCore` — same windows/rounding as sensors + #15 widgets, explicit
in-app auth request per the HealthKit rule; empty-vs-denied ambiguity called
out in the result), currentLocation (shared `DeviceLocationProvider`
one-shot; place names via CLGeocoder, never raw coords), readMotion
(CMPedometer + activity), readCalendar/readReminders (EventKit
requestFullAccess on first use), currentWeather (WeatherKit — current
location or named place; entitlement added in its own surgical commit,
aps-environment re-verify), searchPlaces (MKLocalSearch anchored to the fix
when permitted, honest note when not), lookupContact (CNContactStore,
detached fetch), deviceStatus (battery/storage/thermal/low-power),
readImageText + readBarcode (Vision on the newest conversation image — the
issue's "FM built-ins" DON'T exist in FoundationModels per the SDK docs
2026-07-07, so these are ours), searchConversations (current thread + the
#17 Spotlight session cache; honest "indexing is off" note). Every
permission denial / empty read returns an honest tool RESULT (never a throw,
never fabrication) so the model reacts conversationally. Instructions become
tool-aware (`hasTools`). Usage strings added: Calendars/Reminders/Contacts.
`DeviceToolBeltTests` pin formatting, snippets, search report, instructions.
**Needs Mac:** compile-check @Generable arguments (incl. EMPTY Arguments
structs), Tool conformance shape, `requestFullAccessToEvents/Reminders`,
`WeatherService.shared`, VN* classic Vision API on iOS 27,
`MKLocalSearch`/placemark deprecations; re-verify aps-environment +
weatherkit survive regen; device checklist (airplane mode where applicable):
steps question → HealthTool chip → real number; calendar tomorrow → real
events; weather (WiFi on) → live conditions; "find the conversation about X"
→ hits; every tool denied its permission answers "not granted", nothing
invented. Flagged: transcript replay passes empty `toolDefinitions` (the
session's `tools:` param is the wiring) — if tool calls misbehave after
restore, populate `Transcript.ToolDefinition`s.

## 70. 🔧 Wave 4.5 — action tools + ToolConfirmationCenter (GitHub #29)

Side-effecting device tools behind ONE shared confirm gate (the #16
authority rule generalized: the model can never silently mutate the phone).
`DeviceTools/ToolConfirmationCenter.swift` (@Observable): a tool stages a
card and suspends on an awaited continuation; the transcript renders
`Features/Chat/ToolConfirmationCard.swift` (editable fields, forge-tinted
APPROVE/CANCEL) at the tail of the message list; approve resolves with the
CURRENT field values (edits included), decline resolves a "user declined"
result the model reacts to conversationally. Gate defaults CLOSED — app
death kills the continuation, nothing created. Second concurrent request
auto-declines (tools run serially; the gate never queues silently).
Tools (`DeviceActionTools.swift`): createReminder (EventKit; due-date
re-parse of edited values, list lookup by name else default),
createCalendarEvent (start/duration/location; duration clamped 5m–24h),
scheduleAlarm (the #16 grammar + executor unchanged: `AlarmService.parse` →
gate → `AlarmService.schedule`, same Silent-mode wording; edits re-parse
through the same grammar). Unreadable edited dates REFUSE creation — never
guess a time. `DeviceActionParsing` (ISO + human date forms, local
wall-clock) unit-tested in `DeviceActionToolsTests` along with the gate
mechanics. **Interpretation note:** "#16 confirm gate verbatim" implemented
as the same parse→stage→confirm→schedule policy + wording routed through
the shared card (a dialog can't resolve an awaiting tool continuation);
`/alarm` in ChatScreen still uses its original dialog. **Known limitation
(flagged):** cancelling the stream while a card is pending leaves the card
staged (the FM call stays suspended until decided) — decide-then-continue
is the honest state, but a per-card timeout may be worth a follow-up.
**Needs Mac:** compile + device: "Remind me to call Shelley tomorrow at 9"
→ card with parsed fields → Approve → reminder EXISTS in Reminders.app →
model confirms; Decline → nothing created + graceful acknowledgment; edit
on card → edited values created; kill mid-confirmation → nothing created.

## 71. 🔧 Wave 4.5 — standalone onboarding: pairing wall removed (GitHub #31)

The App Store reviewer path (strategy §6.1). `AppRootView` no longer gates
launch on pairing — first launch lands in MainTabView/chat backed by the
local brain (the #27 router already routes never-configured devices local).
`PermissionsOnboardingScreen` still runs once right after a successful pair
(it primes SENSOR grants, which stay Hermes-gated/opt-in as today) — it is
no longer a first-launch wall. Pairing relocated: `.connectHost` now shows
the full `ConnectHermesScreen` when unpaired (host status screen when
paired); Settings → System gains a "Connect Hermes Desktop — UPGRADE" row
(unpaired only); the pairing hero states chat already works on-device;
successful pair pops the nav path so post-onboarding lands in chat.
Unpairing (`disconnect`) returns cleanly to standalone (wall gone; stores
reset via the existing handlePairingRemoved). Honest unavailable state:
`LocalChatBackend.availabilityExplanation` (live-read) + a forge-tinted
"ON-DEVICE INTELLIGENCE UNAVAILABLE" banner in ChatScreen with the
reason-specific enable instructions and a Connect-Hermes escape hatch —
shown only while the next message would route local. Contextual permission
priming completed: notification auth moved OFF first-send onto the first
LONG-RUN (attachment continued-send start + `.interrupted`); mic/speech
ride first dictation/Talk (existing); Health/Location/Calendar/Contacts
ride first tool use (#28); alarms use AlarmKit's own auth (#16). **Needs
Mac:** fresh sim install (no Hermes anywhere) → full session: type,
dictate, health question → in-context permission prompt → answer; reviewer
walkthrough completes without leaving the app; pairing from its new
Settings home works; unpair returns to standalone; Apple-Intelligence-off
sim shows the explanation banner (Simulate Apple Foundation Models
Availability → unavailable states).

## 72. 🔧 Wave 4.5 — PCC tier: PrivateCloudComputeLanguageModel behind gates (GitHub #30)

Per the 2026-07-05 decision: on-device is the permanent free floor; PCC is
opportunistic and VISIBLY labeled beta. PCC is a MODE of LocalChatBackend
(`LocalModelTier`), never a third client — both models conform to the iOS 27
`LanguageModel` protocol, so the session construction differs by one
argument. Everything sits behind `#available(iOS 27.0, *)` + live
availability checks (SDK-doc-verified 2026-07-07:
`PrivateCloudComputeLanguageModel()` / `.isAvailable` / `.availability` /
`.quotaUsage{isLimitReached,status(.belowLimit(info.isApproachingLimit)/
.limitReached),limitIncreaseSuggestion?.show(),resetDate}` / `.contextSize`;
entitlement `com.apple.developer.private-cloud-compute` — NOT added to
project.yml yet, Apple approval chain pending: SBP submitted → PCC request →
entitlement). Denied/pending reads as unavailable; on-device unaffected.
- Picker: `Brain.privateCloud` appears only when the availability check
  passes; a standalone (never-paired) device now gets the picker too once
  PCC exists (On-Device / PCC β — no Hermes entry). `availableModels()`
  gains "private-cloud-beta" under the same gate.
- Per-message honesty: a PCC pin degrades to ON-DEVICE (never Hermes) when
  unavailable/over quota — visible indicator change + one-line notice
  banner (`privateCloudFallbackNotice`), cleared on recovery or preference
  change. Mid-turn PCC errors fail honestly with a tier-labeled message.
- Escalation offer: when on-device condensation first kicks in and PCC is
  available, ChatScreen offers "continue on Private Cloud β?" ONCE per
  conversation — accept pins the conversation to PCC; the replayed
  (condensed) transcript is the handover context. User decides, never
  silent.
- Reasoning: PCC reasoning surfaces from `Snapshot.transcriptEntries`
  `.reasoning` entries, diffed onto `StreamingUpdate.reasoningDelta` — the
  #4.15 separate-channel rule preserved; raw text persists on
  `Message.reasoning`. Explicit `ContextOptions(reasoningLevel:)` left at
  the framework default for now (`.light/.moderate/.deep` verified for a
  follow-up knob).
- Quota as persistent UI (Settings → Models → Chat Brain): BELOW / NEARING /
  REACHED (+ reset time) with the system "Show options" iCloud+ path via
  `limitIncreaseSuggestion.show()`. Context budgets read the ACTIVE tier's
  `contextSize` at runtime (32K PCC) — never hardcoded.
`PrivateCloudRoutingTests` pin picker gating, degradation notice, recovery,
and tier hand-off. **Blocked externally** on Apple PCC approval — all of
this merges behind the gates first. **Needs Mac:** compile-check the 27-beta
surface (PCC init/quota/limitIncreaseSuggestion.show(),
`Snapshot.transcriptEntries` + `Transcript.Entry.reasoning` segment shapes,
`LanguageModelSession(model: PCC)` overload); test quota paths with Xcode's
Simulate Apple Foundation Models Availability (Approaching / Reached);
device checklist: picker shows β only when live; long conversation triggers
the offer; accepting continues with condensed handover; forced rate limit
degrades on-device with notice, no crash, no fabrication; add the
entitlement to project.yml (surgical commit) only once Apple grants it.

## 73. 🔧 Wave 5 — native fallback voice mode: SpeechAnalyzer → active backend → AVSpeechSynthesizer (GitHub #18)

**Update 2026-07-07 (cloud session, branch `claude/w5-18-native-voice`):** BUILT
IN CLOUD, not compiled or device-verified. Two voice engines behind TalkStore's
one seam — `VoiceEngineRouter` (the Talk-mode sibling of ChatBackendRouter)
fronts the existing `LiveVoiceSessionService` (Realtime/WebRTC) and the new
`NativeVoicePipelineService`. TalkStore, the overlay, transcript view, Live
Activity, and CarPlay mirroring are unchanged consumers of
`VoiceSessionServiceProtocol`.
- **Pipeline:** mic → `AVAudioEngine` tap (echo cancellation via
  `inputNode.setVoiceProcessingEnabled(true)`, enabled BEFORE reading the
  input format) → `SpeechAnalyzer` with `SpeechDetector` VAD
  (`.init(detectionOptions: .init(sensitivityLevel: .medium),
  reportResults: false)`) + `SpeechTranscriber(locale:, preset:
  .progressiveTranscription)`, falling back to `DictationTranscriber(locale:,
  preset: .progressiveShortDictation)` when the full model isn't on-device →
  the ACTIVE chat backend (`ChatBackendRouter` per the #18 amendment — local
  brain = fully offline voice) → a dedicated sentence-buffered
  `SpeechOutputService` instance with the new `managesAudioSession = false`
  flag (the pipeline owns the `.playAndRecord`/`.voiceChat` session).
- **Endpointing (tolerant, wire-mode-hedged):** primary = transcriber
  finalized results (SpeechDetector gates analysis to speech, so finals land
  at pauses); fallback = the 1.35s stale-volatile watchdog
  (`shouldEndpoint`), with `isDuplicateFinalization` deduping a late final
  that re-covers committed audio (the iOS 26.0 SpeechDetector conformance
  bug, forums #797544). Analyzer start retries without the VAD module if the
  module combination refuses to start.
- **Routing:** never-paired → native unconditionally; paired → Realtime wins,
  `talk/readiness` `configured:false` or probe-failed routes native; a
  failed Realtime start falls back to native for that session unless the
  failure is the microphone permission (blocks both engines identically —
  no bouncing). No engine swap under an active session.
- **Honesty:** `TalkSessionSnapshot.engine` (`VoiceEngine.realtime/.native`,
  default `.realtime` so existing sites read unchanged) → LOCAL VOICE badge
  in the overlay header, live engine line + ENGINE status row + footer in
  Voice settings. `sendImage` returns false (no visual path — frames rode
  the OpenAI data channel). Barge-in cuts TTS + abandons the stream;
  reasoning deltas are never spoken. `CompletedVoiceSession.engine` skips
  the post-to-Hermes context turn for native sessions (turns already rode
  the chat backend — no duplicate context).
- Tests: `NativeVoicePipelineTests` (endpointer, dedupe, routing decisions,
  router seam switching via stub engines, snapshot default).

**Needs Mac:** `xcodegen generate` (2 new source files:
`Services/Live/NativeVoicePipelineService.swift`,
`Services/Support/VoiceEngineRouter.swift`; 1 new test file), CLI build +
tests. Compile-risk shortlist: `SpeechDetector` init/module usage (SDK-doc
verified 2026-07-07 but never compiled here), `SpeechTranscriber.Result`
`isFinal`/`text` field names on the 27 beta, `some SpeechModule` generic
seam in `startAnalyzer`, `OSAllocatedUnfairLock` in the tap closure,
block-based NotificationCenter observers under strict concurrency.
**Device checklist:** full loop mic → transcription → chat brain → spoken
reply with relay stopped AND (airplane mode + local brain) — zero
OpenAI/relay dependency; echo cancellation (TTS not re-transcribed — watch
for barge-in self-triggering); SpeechDetector behavior on the 27 beta
(watchdog "fallback endpointer fired" logs = VAD not finalizing); engine
badge + settings rows show LOCAL; Realtime path unchanged when configured;
transcript hand-off renders once, no duplicate context turn.

## 74. 🔧 Wave 5 — CarPlay voice upgrade: auto-start, observation tracking, routing (GitHub #19)

**Update 2026-07-07 (Mac session — MERGED to `main`, PR #40 / GitHub #19):**
Reviewed → xcodegen regen → built + tested (iPhone 17 Pro Max iOS 27 sim) →
merged. One compile fix during review: `maxTranscriptTitleLength` marked
`nonisolated` so the `nonisolated static blockedTitle(reason:)` can read it
(it was MainActor-isolated inside the `@MainActor` class).

⚠️ **CarPlay entitlement DISABLED on `main` (hotfix):** leaving
`com.apple.developer.carplay-voice-based-conversation` active in the committed
entitlements broke **signed device builds** — the dev provisioning profile
can't carry an ungranted restricted entitlement, so Xcode/device signing fails
at `GatherProvisioningInputs` (Apple's guidance: remove until approved). The
key is now COMMENTED OUT in `project.yml`; `xcodegen generate` drops it from
`Talaria.entitlements` (aps-environment + weatherkit confirmed surviving).
Signed `generic/platform=iOS` build → **BUILD SUCCEEDED**.
→ **To run the CarPlay Simulator pass:** uncomment the
`com.apple.developer.carplay-voice-based-conversation` line in `project.yml`,
`xcodegen generate`, build to the **simulator** (signed device builds fail
again while it's on). Re-enable permanently once Apple grants the capability
for team DNL25ZFSD2 / org.aethyrion.talaria27.

Pre-existing (unrelated) `main` test failures filed: ChronoRixun/Talaria#72.

**Update 2026-07-07 (cloud session, branch `claude/w5-19-carplay-voice`,
stacked on #73's branch):** BUILT IN CLOUD, not compiled — and NOT sim-validated
(the CarPlay Simulator step is the whole point of this issue's plan; it needs
the Mac).
- **Auto-start on connect:** `CarPlayVoiceManager.configure()` now runs
  `refreshReadiness()` → `startSessionDirectly()` gated on
  `talkStore.canStartSession` (`CPVoiceControlTemplate` has no tappable
  button by SDK design — connect IS the trigger). Not-ready renders a new
  `blocked` voice-control state carrying `blockedReason` (80-char car cap),
  never a dead idle screen; "Tap Start" copy removed. With #73's
  VoiceEngineRouter underneath, an unpaired/unconfigured phone auto-starts
  LOCAL voice in the car.
- **Observation:** the 500ms polling Timer is gone — one-shot
  `withObservationTracking` over TalkStore
  (voiceState/connectionState/isSessionActive/transcriptItems/
  canStartSession/blockedReason), re-armed per change, gated by an
  `isObserving` flag so tearDown kills the loop.
- **Routing:** `LiveVoiceSessionService.handleAudioRouteChange` re-asserts
  the `.playAndRecord`/`.voiceChat` category when `.carAudio` is in the
  route (the stasel/WebRTC audio unit configures AVAudioSession itself and
  can leave it shaped for the previous route); no speaker override with the
  car attached (pre-existing skip). The native engine (#73) already rebuilds
  its capture chain on every route change.
- **Entitlement:** `com.apple.developer.carplay-voice-based-conversation`
  added to project.yml properties + Talaria.entitlements (the #44/#48 strip
  trap). Key cross-checked 2026-07-07 against the June 2026 CarPlay
  Developer Guide reference — a wrong key is harmless (scene silently
  absent in the sim). Apple's discretionary grant NOT yet filed.
- Tests: `CarPlayVoiceStateTests` (state mapping incl. blocked, title caps).

**Needs Mac:** `xcodegen generate` (1 new test file; re-verify
aps-environment + weatherkit + the new CarPlay key all survive regen per
#44/#48), CLI build + tests. **Sim validation (the gate for filing the
grant):** iOS Simulator I/O → External Displays → CarPlay, or the standalone
CarPlay Simulator.app with a real iPhone over USB — connect auto-starts a
session; mic capture + agent audio + barge-in work; blocked state renders
when talk is down; phone call / nav prompt interruption recovers; disconnect
leaves the session running on the phone, reconnect re-syncs. Then file at
developer.apple.com/contact/carplay/ (category: voice-based conversational).
Real-car audio routing stays a post-grant milestone — no polish before the
grant lands.

## 75. 🔧 HUD header labels wrap/truncate — single-line hardening (GitHub #42)

**Update 2026-07-08 (cloud session, branch `claude/talaria-27-issue-42-042f8a`):**
BUILT IN CLOUD, not compiled or device-verified. On-device captures (issue #42)
showed the chat header character-wrapping under width pressure: wordmark
`HE`/`RM`/`ES`, status `ONLIN`/`E · OJAMD`, brain pill `ON-`/`DEVICE`, model
chip hard-truncating at full size.
- **New `hudSingleLine(minScale:)`** (`Core/HUD/HUDComponents.swift`): one
  line, tighten → scale (floor 0.6 default) → `…` last. Opt-in, NOT baked into
  `MonoLabel` — the voice-overlay live transcript uses MonoLabel for
  multi-line prose and must keep wrapping.
- **Wordmark:** `.lineLimit(1)` + `.fixedSize(horizontal: true, vertical:
  false)` + `.layoutPriority(1)` — never gives up width; the neighboring
  status telemetry absorbs the pressure via `hudSingleLine()`.
- **Status line, message count, CTX label:** `hudSingleLine()`.
- **Brain pill:** hidden ZStack width anchor = `Brain.widestMonoLabel`
  (computed over `allCases` by character count — valid only because the label
  is JetBrains Mono; "ON-DEVICE" today) + `fixedSize` — the pill never wraps
  inside itself and keeps one size across brain switches. Locked by a new
  `ChatBackendRouterTests` test.
- **Model chip (`ModelSelector`):** `.allowsTightening` +
  `.minimumScaleFactor(11/13)` — ~2pt of shrink before the pre-existing
  `lineLimit(1)` `…` truncation.

**Needs Mac:** CLI build + tests (**no new files → no xcodegen regen needed**),
then the issue's acceptance pass on the iOS 27 sim + whoGoesThere: narrowest
supported width, both brains (HERMES / ON-DEVICE), a long model name
(`DEEPSEEK-V4-…`), and a Dynamic Type sweep — wordmark + pill are fixedSize,
so at accessibility sizes the status label should shrink/truncate rather than
anything wrapping. Also confirm whether mainline's milder behavior was iOS 27
SDK-related (issue asks; the fix is robust either way).

---

## 76. 🔧 Orphan-surface audit — hygiene tooling (GitHub #49)

**Update 2026-07-08 (cloud session, branch `claude/t27-49-orphan-audit`):**
BUILT + RUN IN CLOUD — no Xcode dependency (pure bash + python3, both present
on the Mac Mini and OJAMD), so unlike the Swift waves this one is fully
verified as shipped: `tools/orphan-audit.sh --self-test` ran clean at
`6e604e9` and re-flagged all five Field Notes §5 graveyard types.
- **`tools/orphan-audit.sh`** — walks `Talaria/`, `TalariaWidgets/`, `Shared/`,
  strips comments/strings (real state machine: nested block comments, string
  interpolation, raw `#"…"#` strings), extracts top-level type declarations,
  and classifies into four tiers: **ORPHAN** (zero refs anywhere — not even
  same-file outside the declaration and `#Preview` blocks), **TEST-ONLY**,
  **SINGLE-SITE** (one referencing file, ≤2 lines — the dead-gate tier that
  catches `CaptureScreen` behind a never-pushed route and `MockInboxService`
  behind a never-exercised fallback), **FILE-LOCAL** (candidates for
  `private`). `private`/`fileprivate` types and `@main`-file types excluded.
- **`tools/orphan-audit-report.md`** — the committed first run (12 ORPHAN /
  8 TEST-ONLY / 118 SINGLE-SITE / 38 FILE-LOCAL at `6e604e9`). Genuinely new
  finds beyond the known graveyard: `HermesAvatar`, `StatusIndicator`,
  `MockHealthService`/`MockLocationService`; `CarPlaySceneDelegate` +
  Spotlight/App Intents entries are the documented string-/system-referenced
  false-positive classes — informs, never auto-removes.
- **Checklist line** added to `BRANCHING.md` → Safety-net habits (run every
  few sessions / before wave merges).
- `--self-test` pins the §5 oracle **at this commit** — expect churn: #45
  wires `InboxScreen` and guts `MockInboxService`; that branch must update
  `SELF_TEST_ORACLE` in the script when it lands (it does, in this stack).

**No app code touched, no xcodegen.** Nothing was deleted; the report is the
deliverable.

---

## 77. 🔧 hermes:// URL scheme registered + ask?q= payload route (GitHub #48)

**Update 2026-07-08 (cloud session, branch `claude/t27-48-url-scheme`):**
BUILT IN CLOUD, not compiled or device-verified. The deep-link router
(`AppEntry.handleDeeplink`, chat/voice/session/health) was fully built but
externally unreachable — no `CFBundleURLTypes` was declared, and widgets/
intents reach the router via `widgetURL`/open-intents, which bypass scheme
registration.
- **MVP:** `CFBundleURLTypes` (`hermes` scheme) declared in `project.yml`
  (source of truth) AND hand-mirrored into the committed generated
  `Talaria/Resources/Info.plist` (alphabetical key position matched) so the
  scheme is live before the next Mac regen — the regen should be a no-op for
  this key.
- **Extension:** new `hermes://ask?q=…` route. **Seed-only, never auto-send**
  (deliberate security posture: any app or web page can fire a custom-scheme
  URL; auto-send would let external content inject agent turns).
  `ChatStore.pendingComposerSeed` + `seedComposer`/`consumeComposerSeed`;
  ChatScreen drains it on `.onAppear` (cold launch) and
  `.onChange(of: pendingComposerSeed)` (warm), fills `messageText`, focuses
  the composer. Tests appended to `ChatStorePersistenceTests` (existing file
  — no regen needed for tests either).
- **No new source files → next Mac session needs NO xcodegen for this branch
  alone**, but any sibling-branch regen must re-verify `aps-environment` +
  CarPlay/WeatherKit/widget-HealthKit keys (#44/#48 strip trap — now a hard
  gate with the push channel live).

**Device checklist:** type `hermes://session/{id}` in Safari → app opens that
session; Shortcuts "Open URL" with `hermes://ask?q=hello` → composer seeded +
focused, NOT sent; confirm no other installed app already claims `hermes`
(first registrant wins). **Question for Owen:** want `ask` to auto-send behind
a Developer-screen toggle later? Shipped stance is seed-only.

---

## 78. 🔧 Message context menu — copy/share/select/regenerate/edit (GitHub #44)

**Update 2026-07-08 (cloud session, branch `claude/t27-44-message-context-menu`):**
BUILT IN CLOUD, not compiled or device-verified. You previously couldn't get
a Hermes answer out of the app — no `.contextMenu` on bubbles, no
`.textSelection` on prose.
- **Long-press menu on settled user/Hermes bubbles** (`MessageBubble`):
  Copy (raw content via `UIPasteboard`), Share (`ShareLink`), Select Text
  (new private `SelectableTextSheet` — plain text + `.textSelection`;
  in-bubble selection can't coexist with the long-press menu), Regenerate,
  Edit & Resend. System/compaction rows and the synthetic "[N attachment(s)]"
  placeholder are excluded; voice-transcript rows get Copy/Share/Select only.
- **Streaming guards (decided semantics):** a streaming bubble gets NO menu;
  while ANY run streams (`isTranscriptBusy`), the history-mutating items
  (Regenerate / Edit & Resend) are hidden — they truncate the transcript and
  must not race an in-flight run. Copy/Share/Select stay available on
  settled bubbles during a stream.
- **`ChatStore.regenerateReply(_:)`** — per-turn re-roll for ANY successful
  reply (not just the last): truncates from the producing user turn (nearest
  user message above the reply), restores its attachments, re-sends through
  the full pipeline. **`ChatStore.extractTurnForEditing(_:)`** — the `/undo`
  truncation plus composer restore (`EditableTurn`); ChatScreen seeds
  `messageText`/`pendingAttachments` + focuses. Nothing sends until the user
  taps send. Failed Hermes replies keep the existing inline Regenerate.
- **Honest limitation (same as `/retry`/`/undo`):** truncation is
  client-side; the server session retains the old turns as context. A true
  server-side fork would need a new session seeded with the truncated
  history — out of scope here.
- 5 tests appended to `ChatStorePersistenceTests` (existing file — no regen).

**Needs Mac:** CLI build + tests (**no new files → no xcodegen**), then
device: long-press each bubble type; copy/share/select prose; regenerate a
mid-history reply (verify truncate-from-that-turn); edit-and-resend with and
without attachments; confirm no menu on a streaming bubble and no
Regenerate/Edit while another run streams.
