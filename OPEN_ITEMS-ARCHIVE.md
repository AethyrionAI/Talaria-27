# Talaria — OPEN_ITEMS Archive (closed items)

**Created 2026-08-06 by #261 (the archive split).** Every item below was moved
VERBATIM from `OPEN_ITEMS.md` — same bytes, same order the blocks had in the
original file, nothing summarized or reworded. This file is history: it answers
"did we already try this?"; it is not the live board.

- **Numbering is one monotonic sequence across this file and `OPEN_ITEMS.md`.**
  A moved item keeps its number forever; nothing is ever renumbered. The
  canonical header form and counting rules live at the top of `OPEN_ITEMS.md`
  and govern both files (`## N.` / `## NL.`; #198 and #199 each have two
  headings from an old convention — count UNIQUE items, and count across the
  concatenation of both files for whole-project figures).
- **Do not edit item bodies here.** If a closed item turns out to need work,
  move its block back to the live file verbatim and add a dated note there —
  history stays a record, not a draft.
- Status legend (same as the live file): 🔧 in progress · ⛔ blocked ·
  💤 dormant · 🐛 bug · 📝 note / decision · ❌ cut / won't-do (terminal) ·
  ✅ done. Items here are ✅, carry an explicit "✅ CLOSED / ✅ SUBSUMED"
  suffix under the newer category-emoji header form, or are terminal records
  with nothing left to build (⚰️ retired/moot, ❌ completed cuts).

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

## 4. 💤 Expensive-model confirm guard (wired, dormant) — **⚰️ RETIRED 2026-08-04 (PR #255 merged): the guard was shim machinery; Owen waived it 2026-08-03 ("I don't care about expensive guard") and Lane 5 deleted the shim + the CONFIRM card. Pricing stays visible in the gateway-backed picker rows. Reopen only as a NEW app-side feature if a spend-guard is ever wanted again.**

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

## 9. ✅ Model transition overlay — built + both regressions fixed — **AND THE HANG PATH ITSELF IS GONE 2026-08-04 (PR #255 merged): Lane 5 deleted the gateway `/model` session pin (`switchModel`/`pinSessionInBackground`) entirely — apply() is a synchronous local persist now, so the ~37s-hang class this item worked around no longer exists.**

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

**`got 2 samples — distance_walking, steps` is EXPECTED — stop re-diagnosing it
(2026-07-17).** Chased at least three times now (Debug-2 on 2026-06-28 opened three
hypotheses about missing observer queries and Health permissions; a device log review on
2026-07-17 raised it again). It is not a bug:

- `HKObserverQuery` invokes its update handler **once at registration**, regardless of whether
  new data exists. "11 health observer types fire" at launch means *11 observers registered* —
  NOT 11 types with data.
- `collectSnapshot` returns only types with samples in the query window. **Owen wears the Apple
  Watch infrequently** (confirmed 2026-07-17), so on a typical day steps and distance_walking
  are the only iPhone-native types with samples to find. Heart rate, resting HR, blood oxygen,
  respiratory rate, sleep duration, stand hours and workout minutes are all Watch-sourced and
  legitimately empty.
- This also resolves Debug-2's server-side observation that `health_samples` only ever holds
  steps/distance and `health_latest` has ~3 rows. The pipeline is fine; the sensor isn't on the
  wrist. **Debug-2's Hypotheses 1 and 2 are closed as not-the-cause.**

**Falsifiable re-test if ever suspected again:** wear the Watch for a day, then check whether
HR/SpO2 appear. If they do NOT *with the Watch worn*, THEN it is a real item — and the place to
look is the per-type query windows in `LiveHealthService`, not authorization.

---

## 17. ✅ Relay sensor delivery — 07-02 fix did NOT hold: connector was dead 2026-07-02→07-11 (9-day prod outage; see #87/#103 post-mortem). Durably fixed + deployed 2026-07-11

> **Audit 2026-07-13:** The 07-02 "RESOLVED end-to-end ... confirmed on device" claim did not survive the day. Per #103's post-mortem (OPEN_ITEMS.md:3136, logged 2026-07-11): "connector.log shows the connector died 2026-07-02 18:45 in a `UnicodeDecodeError: charmap codec` loop — #87's exact defect — and never came back," a 9-day production sensor-delivery outage beginning the same evening as this item's claimed fix. #87 (OPEN_ITEMS.md:2770) independently rediscovered the identical cp1252/UnicodeDecodeError defect on 2026-07-09, labeled it "Pre-existing," patched 17 subprocess call sites (this item patched only 12), and states outright "`PYTHONUTF8` does not reach the connector process" — directly contradicting this item's stated fix mechanism ("...+ PYTHONUTF8=1"). #87's own 07-09 "deployed" claim was itself later corrected on 07-11 ("the connector had been dead since 07-02... the fixed code was not running") because OJAMD was 107 commits behind. Even this item's sibling #37 (OPEN_ITEMS.md:1168), dated two days later (07-04), shows the encoding mitigation was still non-durable and in flux (moved to an NSSM service env var, then that service was removed the same evening in the "#55 reversion," with "the source-level commit + upstream remains pending regardless") — confirming no durable fix existed as of 07-04, let alone 07-02. This item's own hedge ("All connector changes are UNCOMMITTED on the OJAMD checkout") foreshadowed exactly this failure mode. The other two legs of the "crash + identity + RPC pump" bundle held up independently and are not in question: identity re-pairing was separately verified on device 2026-07-05 (#46), and #47's note ("After the #17 fixes, `talk/readiness` truthfully reports `hostOnline:true`...") corroborates the RPC-pump/heartbeat leg. Only the crash/encoding leg failed, but since it killed the connector process outright, it invalidated the "end-to-end" and "confirmed on device" framing for the whole item. Reclassified: over-reported (marked ✅, actually the underlying defect stayed live in prod for 9 days) → superseded by #87/#103's actual 2026-07-11 fix, which is the current authoritative record.


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

## 18. ✅ Session shelf — scrim opacity increased, toolbar hit-testing blocked (merged 2026-06-25; device verification not recorded)

> **Device pass 2026-07-13 (eve):** verified on whoGoesThere — the scrim blocks toolbar hit-testing while the shelf is open. Audit's ✅→🔧 downgrade resolved.

> **Audit 2026-07-13:** Code re-confirmed present on main — `.allowsHitTesting(!sessionsOpen)` on all 4 toolbar items in `ChatScreen.swift` (486/491/506/512; the 4th is the later #45 Inbox button, which inherited the same guard, showing the pattern survived and was extended, not reverted), and `Design.Colors.scrim` resolves via `ThemeRuntime` (Design.swift:100) with 0.85-opacity scrim values intact in `ThemePaletteCore.swift` post-#49 theming refactor. However, unlike sibling items #16/#17/#19/#20 from the same 2026-06-25 batch (each carries an explicit "Verified on-device"/"confirmed on device" line with device log evidence), this item's body contains only "**Fixed 2026-06-25:**" with no verification statement. No later item confirms or contradicts the on-device hit-testing behavior (searched "session shelf", "scrim", "sessionsOpen", "hit-test", "toolbar", "drawer" — all hits reviewed; the only other scrim hit is the unrelated #9 model-transition overlay). This also matches the document's own established convention elsewhere (#49, line 813, line 1204, line 2946, etc.) of reserving ✅ for explicitly device-confirmed work and using 🔧 + "verification owed" wording for merged-but-unverified fixes. Downgrading header to 🔧 merged-unverified; discrepancy = over-reported.

The session shelf (sessions drawer) overlay was too transparent (62% opacity) and let
taps fall through to the toolbar (model chip, settings gear) because SwiftUI's navigation
toolbar renders above `.overlay` content.

**Fixed 2026-06-25:**
- Scrim opacity bumped from 0.62 → 0.85 (`Design.Colors.scrim`)
- All three toolbar items (sessions button, model chip, settings gear) now have
  `.allowsHitTesting(!sessionsOpen)` — taps on the toolbar area pass to the scrim
  dismiss gesture when the drawer is open

**Update 2026-07-26 — the root cause was never fixed, only mitigated; now it is.**
Found on device during the 2b shelf work: two grey capsules floating over the top of the
drawer panel, hiding its own header. They were the chat toolbar. Three layers, peeled in
order, each one revealing the next:

1. `.allowsHitTesting` killed the taps but never the pixels — that was always the 2026-06-25
   fix's stated limit, and a scrim is not a fix on a light palette.
2. Adding `.opacity(sessionsOpen ? 0 : 1)` faded the item CONTENT but left the capsules.
   On iOS 26+ the system draws each toolbar item's glass **outside** the item's own view, so
   opacity cannot reach it. `GlassCircleButton` draws a *circle*; the hamburger draws no
   background at all — the *capsules* were proof the shapes were system-drawn, not ours.
   `ToolbarContent.sharedBackgroundVisibility(_:)` (iOS 26+) is what takes the material.
3. With the glass gone the panel's header was **still** invisible while being correctly laid
   out — the a11y tree showed the `0 THREADS` heading at (16, 73) and the ✕ at (348, 62), and
   a 440pt-wide bar Group at y=62 over a 408pt panel. The navigation bar composites above
   `.overlay` content as a LAYER, whatever its contents' alpha.

`.toolbar(.hidden, for: .navigationBar)` did fix it, but dropped the bar's height from the
safe area and slid the chat up **~57pt** behind the panel — measured in the peek sliver, and
a jump on close. So the drawer moved out of `ChatScreen.overlay` and became a sibling of the
whole `NavigationStack` in `MainTabView.compactStack`, with `sessionsOpen` lifted alongside
the other state that must survive the compact↔regular boundary.

Payoffs beyond the z-order: the panel inherits the window's real safe area, so the UIKit
`DeviceSafeArea` scene-inset read the drawer needed is **deleted**; and crossing into regular
width stops rendering the drawer structurally, retiring the `onChange(horizontalSizeClass)`
stale-flag reset. Layers 1 and 2 are kept — the panel leaves a 32pt peek sliver, and the
gear's right edge falls inside it.

Verified in the simulator: header legible and unobstructed, no capsules, no reflow.

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

## 25. ✅ CTX meter resume-cache — DEVICE VERIFIED 2026-07-17 (old session: honestly absent; live: real number; relaunch: cached). 'Flashes wrong' half rides #120's lane

> **SECOND HALF ('flashes wrong' mid-stream) FIXED in the #120 lane (PR #116, 2026-07-18);
> device check owed.** The gauge's only mid-stream writers (the 2s poll tick + `loadConversation`)
> adopted merged `conversation.latestUsage`, which a refresh source's own non-nil number (relay
> legacy accounting, another backend's thread) could overwrite — and at `.finished` that merged
> number outranked the run's own `run.completed` usage, so it could stick, not just flash. Fix:
> both adopters skip `lastTokenUsage` while a stream is live (previous number keeps displaying,
> honestly — dispatch option (a)); recovery polling after a dead stream settles unchanged; at
> `.finished` the run's own usage now wins, merged number stays the no-wire fallback. Cumulative
> session `input_tokens` still untouched (banned path). Fail-first tests in `ContextMeterTests`.
> → **Device check:** mid-stream the gauge holds the previous number (or stays hidden), no
> transient jump, settles on completion.

> **MERGED 2026-07-17 (PR #110, `f42ba3f`→`5510c41`).** Built exactly to the probe verdict:
> `SessionUsageIndex` + `SessionUsageIndexStore` (SessionProfileIndex pattern) cache each live
> `run.completed`'s usage keyed by session id; `openSession` reads the cache on resume. The gauge
> renders ONLY when both halves are known (`ChatScreen.swift:620` gates on window AND numerator) —
> unknown hides the gauge, never "CTX 0%". Compliance verified in the loop: `token_count` appears
> only as a warning comment (never decoded — null on 100% of rows per the probe); zero cumulative
> `input_tokens` division anywhere; the spy-store conformance stubs in SensorOutboxChurnTests are
> the protocol growth, benign. Suite **754 tests / 62 suites** green (new baseline); tree-identity
> validation (branch tree == merged main tree). → **Device re-verify owed:** open an OLD session —
> gauge honestly absent (not 0%); send a message — gauge appears with a real number; kill + relaunch
> + reopen that session — cached number returns. 'Flashes wrong' second half remains open per the
> dispatch (separate investigation, not covered by this fix).

**Dispatch spec 2026-07-16:** `dispatch/FABLE-T27-25-ctx-meter.md` — **READY TO SEND (gate
lifted).** Root cause confirmed in source at HEAD: `SessionsHermesClient.swift:1523`
`SessionMessagesResponse.StoredMessage` decodes `role`/`content`/`timestamp`/`toolCalls` and NO
usage field → `latestUsage` always nil on a resumed session → `ChatScreen.swift:569`
`contextProgress` guards to 0 → "CTX 0%".

**PROBE RUN 2026-07-16** (Claude Desktop, live against OJAMD `:8642`, 25 sessions, all four
sources — `api_server`/`cron`/`desktop`/`tui`). Verdict (c), plus a trap the three-way framing
missed:

1. `GET /api/sessions/{id}/messages` exposes `token_count` per row — **null on 100% of rows**,
   including `api_server` (Talaria's own source). Decoding it is the obvious one-liner, compiles,
   passes a hand-made fixture, and renders a permanent 0% on real data. Do not.
2. Session usage DOES exist on `/api/sessions` (list) and `/api/sessions/{id}` (detail):
   `input_tokens`, `output_tokens`, `cache_read_tokens`, `cache_write_tokens`,
   `reasoning_tokens`, `api_call_count`. `/runs` and `/usage` → 404, they don't exist.
3. **But session usage is CUMULATIVE across api calls, not context occupancy.** Live example:
   `api_1783825106_6e2766ab` — 10 messages, 5 api calls, `input_tokens` 114,754 → naively over a
   128k window that renders **90%** for a chat occupying a fraction of it. Cumulative/last-run
   ≈ 1.5× at two calls and worsens with length — **likely the true origin of this item's
   historical "denominator ~1.4× high" note, which was probably never a denominator bug at all.**

**Fix (per the probe):** no endpoint knows the last run's prompt size, so stop asking one. Cache
`run.completed` usage app-side keyed by session id (that parse path already works — it's why live
sessions read correctly), read it on resume, and render the gauge **honestly absent** when
unknown — never "CTX 0%". Never divide cumulative `input_tokens` by the window; comment it so
nobody re-tries. Second half ('flashes in before reading wrong') is separate and NOT covered by
this fix.

**Bonus finding (cross-ref #60, do not scope-creep):** stored messages carry `reasoning` and
`reasoning_content` per row — resumed sessions could restore their reasoning panes; they don't
today.

**Audit 2026-07-13:** Confirmed independently — auditor's status-flip upheld. The item's own latest dated note (2026-07-05, positioned first in the block) reads "Device verification 2026-07-05: FAILED" with a broader symptom set (CTX shows 0 on some sessions, absent entirely on older sessions, occasionally flashes in before reading wrong) and lists next steps (ground-truth against Hermes's built-in context check; capture a Verbose-Logging + `run.completed` session) that no later note reports as started or done — nothing in OPEN_ITEMS.md after 2026-07-05 mentions CTX/context-window/denominator except item #46's 2026-07-08 note, which independently reaffirms "distinct from OPEN_ITEMS #25 (CTX denominator accuracy — still open)". The header ("0% fixed; denominator ~1.4x high") only describes the superseded 2026-06-27 intermediate state. Source-code at current HEAD (cca1345) mechanically confirms the FAILED note's symptoms are still live: `SessionsHermesClient.fetchSessionConversation` (Talaria/Services/Live/SessionsHermesClient.swift:467-488, used by `openSession`) builds `Conversation` from `SessionMessagesResponse` — which decodes only `role`/`content`/`timestamp`/`toolCalls` (no usage field, lines 1098-1113) — so `latestUsage` is always nil for any resumed/older session; `ChatScreen.contextProgress` (Talaria/Features/Chat/ChatScreen.swift:557-563, comment "Shows 0 when no usage data yet") then guards to 0. This is exactly "absent/0 on older sessions." The note's citations don't hold up as fix evidence either: ISSUE_INDEX.md GitHub #4 = closed "Composer: multi-line TextEditor with Writing Tools" (unrelated) and PR_INDEX.md PR #21 = merged "Health widget tiles query HealthKit directly (#15)" (unrelated) — "#4" is reused in this codebase purely as an internal shorthand tag for CTX-denominator work (also appears in ChatStore.swift, HermesClientProtocol.swift, LocalChatBackend.swift), not a real GitHub link to a fix. MAIN_LOG.txt (174 commits, origin/main tip cca1345) has zero commits touching CTX/meter/denominator/numerator/contextWindow/run.completed. Header/title corrected to reflect the FAILED verification as the current, unresolved status.

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

## 27. ✅ Developer screen flags — keep Verbose Logging, drop Mock Responses

> **CLOSED — header flipped 2026-08-01 (Hermes audit Part 1A).** Resolved 2026-06-27 — Verbose Logging shipped and wired; Mock Responses dropped.

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

## 31. ✅ Paste image into the chat composer — paste UI + paste-with-text send device-verified 2026-07-20; image-only failure is NOT paste-specific (→ #142)

**Device pass 2026-07-20 (Session C launch sweep): paste flow VERIFIED — CLOSED, history
rhyming.** Paste attaches and paste-WITH-TEXT sends successfully end-to-end. Pasted image
ALONE yields a literally EMPTY assistant reply — but picker images alone also fail (as
“[attachment]” text, see #61 note), so exactly as in the 2026-06-28 round, the residual is a
shared image-only send defect, not a paste defect → tracked as #142. Paste/picker parity is
this item’s scope and it holds.

> **Audit 2026-07-13:** Header said ✅ done; downgraded to 🔧 merged-unverified. Code confirms the merge is real: `Talaria/Features/Chat/ChatInputBar.swift:174` (`// Paste image from clipboard (#31)`, uncommented) wires a button to `pasteImageFromClipboard()` (516-518: reads `UIPasteboard.general.image`, calls `onPasteImage`); `ChatScreen.swift:201` routes it to `handleAttachmentResult(.image($0))` (same path as the photo picker, confirmed at line 1135-1136); `Talaria/Services/Support/AttachmentInlining.swift:87` builds a `data:<mime>;base64,...` URL for the `.image` case; `Talaria/Services/Live/SessionsHermesClient.swift`'s `ChatTurnBody.make()` (line 975, comment 956-962 citing "#43 ... they used to be silently dropped here") consumes it and is called from three live send paths (lines 120, 170, 596) — verified by direct grep/read, not by trusting the prior auditor. But no dated note anywhere in this item, in item #43, or in item #48's 2026-07-02 reconcile note ("Build verified on device") ever confirms an on-device re-test of the *full* paste-then-send flow after the merge. This item's own latest dated note (2026-06-28) is pre-merge and negative: image-only send returned HTTP 400, and the paste UI was explicitly "held uncommitted until #43 lands." Contrast item #15 (reconciled the same day, 07-02), which carries an explicit post-reconcile line — "on-device log confirmed drain/delivery" — that #31 conspicuously lacks. A later BGTask crash fix for "attachment sends via beginLongSend" (commit 71468ca, PR #67, ~2026-07-10/11) shows attachment sending was still being debugged on-device well after the merge, with no subsequent success note logged. Per AUDIT_GUIDE.md, "merged to main" alone does not earn ✅ absent an explicit device-verified note — none exists here.

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

## 36. ✅ Reconcile OJAMD's Talaria checkout onto the ChronoRixun fork

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

**✅ RESOLVED 2026-07-08.** OJAMD reconciled onto the canonical repo. Divergence turned out
tiny: merge-base was OJAMD's own parent; OJAMD was +1 commit (`6d86907`, of which only
`scripts/update-hermes.ps1` was genuinely unique — `cleanup-stale-users.py` was already
upstream byte-identical modulo EOL), and t27/main was ahead by exactly the #44–#49 wave. All
17 "dirty" files were untracked ops files (launchers/logs/DB journals) — no floating hotfixes.
OJAMD now runs branch **`ojamd-deploy`** = `t27/main` + that cherry-pick, tracking remote
`t27` (AethyrionAI/Talaria-27); future updates are a `git pull`. `.env`, DBs, and launcher
scripts untouched. The unique commit was pushed as branch `ojamd/update-hermes-helper` on
AethyrionAI/Talaria-27 — **PR still to be opened** (no `gh` on OJAMD). Remotes on the OJAMD
checkout: `origin`=dylan-buck (legacy), `fork`=ChronoRixun, `t27`=canonical.

---

## 37. ✅ Connector win32/encoding fix — RESOLVED (win32 `tasklist` branch landed on main via PR #38, merged 2026-07-06; encoding fix — 17 sites incl. mcp_registration ×3 + AST-audit test — shipped 2026-07-09 and deployed to OJAMD 2026-07-11 per #87)

> **Audit 2026-07-13:** Header and last note (2026-07-04 evening) are stale by over a week. Re-verified independently: (1) `connector/src/hermes_mobile_connector/mcp_registration.py` in the current working tree (== main tip) contains the exact `sys.platform == "win32"` / `tasklist /FO CSV /NH` branch this item describes as OJAMD-only/uncommitted; GitHub's actual diff for PR #38 ("Sync upstream ChronoRixun/Talaria," merged 2026-07-06 per PR_INDEX.md) shows this precise code being added to `mcp_registration.py` — the fork-port happened, via an upstream-sync PR rather than the manual apply/commit/push this item planned. (2) The encoding half's `PYTHONUTF8` env-var mitigation, which this item's last note says was reverted (#55) and "queued" for a future pass, was superseded by a proper source-level fix: `encoding="utf-8", errors="replace"` pinned on all 17 text-mode subprocess sites (confirmed present across `mcp_registration.py`, `cli.py`, `client.py`, `hermes_runner.py`, `git_diff.py`, `service_management.py`, `talk_support.py`) plus a new AST-audit test `connector/tests/test_subprocess_encoding.py` — tracked at OPEN_ITEMS #87, whose 2026-07-11 correction note confirms an actual OJAMD deploy (rebase onto `t27/main` + connector restart, backlog drain confirmed), which necessarily also carries PR #38's win32 fix since that landed on main first. Item #55's still-open checklist line ("Add `PYTHONUTF8=1` to both bats — see #37") is itself now moot. Recommend closing #37 as resolved, cross-referencing #38 and #87.

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

## 38. ✅ Remote push (APNs) for instant background-run completion notify — RESOLVED (config in place + tests passing, Owen 2026-07-09)

**RESOLVED 2026-07-09 (Owen):** APNs config in place — all `APNS_*` keys + `GATEWAY_API_KEY` present in relay `.env` (verified this session); Owen confirmed push tests working.

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

## 46. ✅ Reinstall resurrects a stale Keychain identity (post-#41)

**Verified on device 2026-07-05 (happy path):** delete + reinstall -> signed in without
re-pairing, persisted identity valid and functional (GitHub #3, PR #22). The *stale*-identity
branch is only exercisable by invalidating the identity server-side; if it ever recurs,
reopen with the relay-side state at time of failure.

Discovered 07-02, bit us immediately. After delete+reinstall the app came back authenticated as a **revoked** relay user (`15deb25d…`) instead of the live user (`707547ee…`) — #41's Keychain persistence preserved a dead identity. Consequence: sensors 202-forever + 'Connect a Hermes host' on VOICE, while chat (direct :8642) worked — a half-broken app with no obvious cause. **Needs (app-side):** on `pair()`, overwrite/clear ALL prior credentials in the Keychain (no stale survivors); store relay `user_id` with the pairing and validate on session restore (surface 're-pair' if the relay reports no active host for that user); Diagnostics (#15) should show the authenticated relay `user_id`. **Workaround:** unpair (clears both stores) → `hermes-mobile.exe pair-phone` on OJAMD → re-pair. Test-gap note: the dropped test suite covered a clear-on-disconnect guard for exactly this — see `handoffs/RECONCILE_TEST_GAP.md`.

---

## 47. ✅ Configure OpenAI Realtime talk on the Hermes host — key/config deployed + confirmed minting on OJAMD 2026-07-08, then PARKED behind the unrelated #82 audio-capture wedge

> **CLOSED — header flipped 2026-08-01 (Hermes audit Part 1A).** Core ask DONE and in daily use — #82's wedge cleared (PR #106, device-confirmed 2026-07-16); realtime live on OJAMD since 07-20. **Residual UNFILED and needs Owen: the billing-cap decision.** CarPlay E2E lives at #45/#74.

> **Audit 2026-07-13:** Re-verified independently. The connector fix code described in the 2026-07-05 note (tolerant state/secrets deserialization, `realtime_talk.enabled` flat/nested/dotted resolution, API-key fallback secrets→env→`.env`, stale-error auto-clear) is confirmed present in `connector/src/hermes_mobile_connector/state.py` (~L150-167) and `client.py` (~L517-593) on current main. Item #82's OJAMD relay-log evidence (2026-07-08, 00:55-01:04 UTC) shows `talk/readiness` 200 → `POST /v1/talk/session` 200 → a minted realtime session (`sess_…`, `last_error: None`) — per `client.py:_rpc_talk_session_create`, a mint is only reachable when both `realtime_talk_enabled` and a resolved API key are true, so this is direct proof the configure-ask was deployed and working on OJAMD. Item #85 (also OJAMD-log-sourced, 2026-07-08: "every voice session logged mcp_list_tools.failed") independently corroborates that Realtime sessions were minting in volume around that date. Voice then failed end-to-end for the unrelated device-level audio-capture-stack wedge (item #82), and Owen explicitly **PARKED voice 2026-07-09** ("voice is optional; CarPlay voice inherits this when resumed"), which also shelves this item's two remaining sub-tasks (billing cap: moot while parked; CarPlay E2E: independently gated on Apple's discretionary entitlement per item #45). Correction to the record: this item's own citation of connector fixes on branch `claude/issue-7-hermes-config-08bsbm` traces to commit `8ca7741` ("PR #71" in the old pre-fork `ChronoRixun/Talaria` tracker, not this repo's current PR numbering) — that exact SHA is **not** an ancestor of current `origin/main` (main was re-rooted at orphan commit `9964f02` on 2026-07-10, which already carries the fix forward as part of a full-repo snapshot). The fix's presence on main is established by working-tree file content, not commit ancestry.

Last gate to working voice. After the #17 fixes, `talk/readiness` truthfully reports `hostOnline:true, configured:false` — 'OpenAI Realtime is not configured on this Hermes host.' Per `client.py:_rpc_talk_session_create`, talk needs `realtime_talk.enabled` + an `openai_api_key` in the connector secrets (`~/.hermes-mobile` on OJAMD). Voice already reports BALLAD + live context, so everything downstream is warm. **Owen-gated** (needs an OpenAI key with Realtime access; billed per audio minute — worth a cap). Also unblocks CarPlay voice (#45).

**Update 2026-07-05 (GitHub #7 — "entered the settings but still not configured", root-caused + fixed):** the issue's own setup notes say to put `realtime_talk.enabled` in the connector **secrets** store — but the connector only ever read that flag from `state.json`, and `ConnectorSecrets(**data)` crashed with a `TypeError` on ANY unknown key in a hand-edited `secrets.json`, killing every `talk.prewarm` RPC. A key placed in the Hermes settings (`~/.hermes/.env` `OPENAI_API_KEY`) was never read either, and a stale "OpenAI API key is not configured." `last_validation_error` in `state.json` blocked readiness even after a key appeared. Connector fixes (branch `claude/issue-7-hermes-config-08bsbm`): tolerant state/secrets deserialization (unknown keys ignored); `realtime_talk.enabled` honored from `secrets.json` (flat, nested, or dotted-key shapes); API-key resolution falls back secrets → `OPENAI_API_KEY` env → `$HERMES_HOME/.env`; stale no-key validation error auto-cleared once a key exists; readiness `blockedReason` now distinguishes "no key found" from "talk disabled". **Needs OJAMD redeploy of the connector to take effect.** Billing cap + CarPlay E2E remain open on the GitHub issue.

---

## 48. ✅ Repo hygiene — lineage divergence cleanup + xcodegen entitlements trap — RESOLVED (`BRANCHING.md` shipped; log-noise line kept as accepted non-blocking polish)

> **Audit 2026-07-13:** Independently re-verified all four sub-threads; auditor's status-flip upheld but their header overclaimed "logging polish" as done. (1) Lineage divergence: item's own 07-02 note already says "Resolved... Build verified on device" — no later regression found anywhere in the file (the unrelated OJAMD repo-tracking item near line 1155 is a different divergence). (2) Prevention TODO: `BRANCHING.md` exists at repo root and its content matches the ask almost verbatim (canonical-main rule, mandatory `git fetch`+divergence-check script, one-lineage-at-a-time, "Parallel Claude sessions... must never assume its local main reflects reality"); it is a genuine living doc, not a coincidental file — merged GitHub PR #50 (`986bc62`, referenced at OPEN_ITEMS.md:2288) later added a session-checklist line to it, proving real adoption. The item's own "Prevention (TODO, → item for next session)" bullet is now stale and should be struck. (3) xcodegen trap: confirmed live at `project.yml:45` (`aps-environment: development`) on the current origin/main tip (cca1345). The item's own text adds "the TestFlight/production switch (#8) still applies" — the auditor's evidence omitted this — but it does not block closure: item #44 (already ✅ VERIFIED, OPEN_ITEMS.md:1394-1396) carries the identical "→ #8" forward-reference caveat without it blocking #44's own resolved status, establishing this as the project's own convention for this exact caveat. Item #8 itself stays a separately-tracked 📝 future gate. (4) Logging polish: `collectSnapshot returned nil` is still logged verbatim at `Talaria/Services/Live/SensorUploadService.swift:424` — genuinely untouched — but the item's own text already characterizes it as self-correcting, harmless "log noise only" and phrases the ask as "Consider debouncing," never a hard requirement, so treating it as accepted non-blocking polish is consistent with the item's own framing rather than a real open thread. Net: 3 of 4 threads cleanly resolved with explicit RESOLVED/device-verified or docs-exist evidence; the 4th was optional by its own original design. The 🔧 header is stale and should flip to ✅, but the corrected title should not claim "logging polish" was performed — only that it was triaged and deliberately left as-is.

**Lineage divergence (root cause of days of 'didn't we already do this?'):** local `main` and `origin/main` forked at `cf50688` (06-28 16:43) and evolved in parallel — Fable's branch was merged to origin via PR #1, while a separate local session committed 12 different commits implementing the SAME items (#35/#41/#24a) differently, never pushed. The Mac's local checkout also hadn't fetched in days, hiding it. **Resolved 07-02:** chose origin as canonical, reset local main to `origin/main` + cherry-picked the genuinely-unique local work (#31 paste, #43 image serializer, #15 sensor panel), dropped local's redundant #41 approach. Full local lineage preserved at tag `prereconcile/local-main-20260702`. Build verified on device.
- **Prevention (TODO, → item for next session):** write `BRANCHING.md` — canonical-main rule, mandatory `git fetch` + divergence check at session start, one-lineage-at-a-time. Parallel Claude sessions must not both commit to main-equivalents.
- **xcodegen trap:** `xcodegen generate` regenerates entitlements from `project.yml`, which does NOT list `aps-environment` — so every regen silently drops the #44 push entitlement. **Fix project.yml to declare it**, or never redeploy after a bare `xcodegen` without restoring the entitlements.
  **Update 2026-07-03:** project.yml now declares `aps-environment: development` (done on the theming branch `claude/theming-options-plan-c4356l`, required because the theme system adds new files → mandatory regen). Trap closed for dev builds; the TestFlight/production switch (#8) still applies.
- **Low-pri polish:** on-device drain log shows `collectSnapshot returned nil (auth=authorized)` interleaved with successful captures — health callbacks fire faster than HealthKit has a queryable sample; self-correcting, log noise only. Consider debouncing or downgrading that log line.

---

## 49. ✅ Theme system — four themes + palette-core de-dup SHIPPED, compiled, and device-verified (4 flagships live on-device 2026-07-10 per #91; Lane E built directly on this catalog, device-verdicted through 07-12)

> **Audit 2026-07-13:** Auditor's status-flip upheld and strengthened with independent, earlier evidence. `Shared/ThemePaletteCore.swift` (85KB) and `TalariaTests/DesignThemeTests.swift` are present on `main` (tip cca1345, clean working tree) and implement exactly the 2026-07-05 de-dup design this item describes: `ThemePaletteCatalog` data-driven resolution, `lockedAccentSlot` field (`DesignThemeTests.swift:48` `#expect(ThemeID.terminal.lockedAccentSlot == .cyan)` — confirmed verbatim). `DesignThemeTests.swift` is wired into the TalariaTests target's Sources build phase in `project.pbxproj` (not an orphan file) and its own content has been extended through Lane E batch 4 (Molten Forge/Midnight Aquarium assertions), so it is live in the routine build/test loop, not dead code. Three independent dated on-device confirmations, earliest first: (1) item #50's own finding note — "Found 2026-07-03 (Owen, reviewing `claude/theming-options-plan-c4356l` **on device**)" — i.e. the four-theme branch was already built and running on Owen's physical device the same day item 49 was authored, undercutting the "needs Mac build + device verify" framing almost immediately. (2) Item #91's context paragraph, explicitly dated "verified at HEAD 2026-07-10": "On device today: 4 flagships + 4 seasonals + 4 complex ... all selectable" — "4 flagships" is `ThemeCatalog.flagship` = exactly Deep Field/Solar Forge/Terminal/Paper Tape (confirmed in `Talaria/Models/ThemeCatalog.swift:112-122`), i.e. item 49's deliverable, compiled and running on the physical device a day before Lane E's gate-clear. (3) Lane E (PR #66, merged=YES per PR_INDEX.md, base=main) then built 16 more themes directly on the same catalog/lockedAccentSlot mechanism with its own repeated device verdicts through 07-11/12 ("Now THAT is an outrageous theme"; Haunted VHS and Deep Sea Diner both explicitly "CUT on device verdict"), and a 2026-07-12 full-suite run ("542/542 tests green, 49 suites," OPEN_ITEMS line 3256) post-dates Lane E and necessarily exercises the TalariaTests target containing DesignThemeTests. Item 49's own 07-05 note ("Owed to the Mac: Xcode build + DesignThemeTests... + device theme-cycle pass") and CLAUDE.md's Design-system paragraph ("Xcode build + DesignThemeTests run still owed on the Mac") are both stale carryovers nobody updated once the work was folded into and superseded by Lane E. Minor aside (not load-bearing): item 49's own text mislabels the de-dup as "(GitHub #49)" — GitHub issue #49 is actually the unrelated orphan-surface audit (OPEN_ITEMS #76; ISSUE_INDEX.md confirms it CLOSED under that different feature) — a pre-existing numbering slip in the doc, distinct from this status question.

**Built 2026-07-03** (cloud session, plan reviewed + revised in `design/THEME_SYSTEM_PLAN.md`). A THEME (Deep Field / Solar Forge / Terminal / Paper Tape) now owns the whole color environment; the accent picker's three persisted slots (`cyan`/`amber`/`violet` raw values, unchanged — zero migration) are re-interpreted per theme with slot `.cyan` always the theme's hero hue (Cyan Arc / Forge Amber / Phosphor Green / Tracker Red). Shipped on the branch:
- `Shared/ThemePaletteCore.swift` — single source of truth for all 4×3 palettes, compiled into app + widgets (project.yml `Shared` sources); `Color(hex:)` moved here.
- `ThemeRuntime.theme` + all `Design.Brand`/`Design.Colors` tokens palette-computed; `cyanHairline`→`hairline`, `cyanBorder`→`strongBorder` (62 call sites). Deep Field × cyan byte-identical (guarded by `TalariaTests/DesignThemeTests.swift`).
- Textures (embers / scanlines / paper grain — seeded Canvas, motion gated behind Reduce Motion, no flicker), `GridOverlay` lines/dots/rules, per-theme `ReactorOrb` drawings, theme picker cards in APPEARANCE with contextual accent labels.
- Paper Tape (light): root `preferredColorScheme` follows `theme.isLight`; `hudGlow` × `palette.glowScale` (0.15 on paper); danger/scrim/ink variants.
- Widgets: Status + Health migrate to `AppIntentConfiguration` with a per-widget `WidgetTheme` (default Match App ← `HermesWidgetData.appearanceTheme`, BOTH copies updated in lockstep); app root reloads timelines on theme/accent change. Accessories + Live Activity untouched. CarPlay untouched (system templates).

**Remaining (Mac session):** `xcodegen generate` (project.yml now also declares `aps-environment` → #48 trap closed) → CLI build → fix any compile stragglers (written without a Swift toolchain) → run `DesignThemeTests` → device pass: Deep Field pixel-identity, then Solar Forge / Terminal contrast, then Paper Tape legibility (bubbles, code blocks, keyboard/sheets), widget gallery + edit-sheet theme picker. Deviation from plan: Deep Field ships with NO starfield texture (pixel-identity trumped the optional dots).

**Update 2026-07-05 — palette-core de-dup (GitHub #49) executed** (cloud session, branch `claude/theme-palette-dedup-4cdc35`, 5 commits, one theme per commit per the handoff sequencing). `ThemePalette(theme:accent:)` now resolves from `ThemePaletteCatalog` data (Shared) — zero per-theme switch arms in resolution; Terminal's #12 pin is `lockedAccentSlot` data; `AppearanceTheme` collapsed to a thin id (displayLabel ← catalog `displayName`, isLight ← palette data); accent labels are per-slot variant data; `ReactorOrb` dispatches on new `palette.orbStyle` (drawing stays in the view); `WidgetTheme` arms collapsed. Byte-identity verified by *execution* on Linux (mock `SwiftUI.Color` preserving construction paths; old vs new file, 4×3 slots, 364 properties — zero diffs), plus label/flag parity checks. No files added/removed → **no xcodegen needed**. Owed to the Mac: Xcode build + `DesignThemeTests`/`ThemeCatalogTests` + device theme-cycle pass — see `design/THEME_PALETTE_DEDUP_HANDOFF.md` status block.

## 50. ✅ Terminal theme accent lock — code merged to main (`lockedAccentSlot`), Mac build + device verify owed

> **Device pass 2026-07-13 (eve):** the Terminal theme keeps its locked accent on device regardless of the accent picker.

> **Audit 2026-07-13:** Re-verified independently — the auditor's file/line citations are all accurate (checked `Shared/ThemePaletteCore.swift:257,351,607`, `Talaria/Features/Settings/AppearanceSettingsScreen.swift:33-39,53-55`, `TalariaTests/DesignThemeTests.swift:45-59`, plus `TalariaWidgets/WidgetTheme.swift:45,51` confirming the widget path also routes through the single `ThemePalette(theme:accent:)` resolution point — all three required surfaces from the item's "Fix (two parts)" + widget bullet are covered). Traced to commit `869b850` (2026-07-04, "fix(theme): lock Terminal to Phosphor Green") and folded into the #49 palette-core de-dup on 2026-07-05. So the CODE claim is correct — but "done" is not supported: no Xcode-build/DesignThemeTests-run/device-verified note exists anywhere in current main's copy of this item, and sibling item #49's own latest surviving note (2026-07-05, still current) explicitly says "Xcode build + `DesignThemeTests`/`ThemeCatalogTests` + device theme-cycle pass" remain **owed to the Mac** — per the house merged≠device-verified rule that governs every other item in this file, that blocks ✅. Interesting wrinkle the auditor missed: a correct RESOLVED write-up for this *exact* item already exists — commit `b6913eb` (2026-07-09, "dedup pass"), which set the header to `## 50. ✅ … — RESOLVED on main` with a verification note — but that commit only lives on unmerged remote branch `claude/fable-handoff-task-batch-etoz56` (confirmed via `git branch -a --contains b6913eb`) and is NOT an ancestor of current `origin/main` (`git merge-base --is-ancestor` = false), so it never reached this file. Even that orphaned note only claims "verified in code," not a build/device pass, so it wouldn't fully clear the bar either. Recommend 🔧 merged-unverified (matching #49's own convention) rather than ✅, until an explicit Mac build/test/device-pass note is recorded — and separately, someone should reconcile/merge `claude/fable-handoff-task-batch-etoz56`'s doc fixes (it also correctly resolves #48 and #53, the latter of which is still shown 🐛 open in current main too).

**Found 2026-07-03** (Owen, reviewing `claude/theming-options-plan-c4356l` on device). The Terminal theme's identity *is* the phosphor green — reassigning its accent (Amber · Phosphor / Cyan · IBM) just recolors it into a generic themed screen and throws away what makes it Terminal. Terminal should expose NO accent choice; the green is the whole point.

**Fix (two parts):**
- **Hide the accent row for Terminal.** In `Talaria/Features/Settings/AppearanceSettingsScreen.swift`, gate `accentSection` (body VStack ~L40; section defined ~L212) to render only when `theme != .terminal`. The theme picker (`themeSection`) stays.
- **Pin Terminal's resolved slot to the hero.** Hiding the UI isn't enough: a user who picked `.amber`/`.violet` under another theme, then switches to Terminal, would still resolve `ThemePalette(theme: .terminal, accent: <stored slot>)` → amber/IBM, not green. Force the *effective* accent slot to `.cyan` (Phosphor Green hero) whenever the active theme is Terminal, at the single palette-resolution point (`ThemeRuntime` / `ThemePalette(theme:accent:)`), so app + widgets + the Appearance preview all stay green. Leave the *persisted* `appearanceAccent` untouched so switching back to Deep Field / Solar Forge / Paper Tape restores the user's prior accent.
- **Widgets:** apply the same pin when a widget's `WidgetTheme` explicitly resolves to Terminal (not just Match App).

**Acceptance:** Appearance shows no `// Accent` row while Terminal is selected; selecting Terminal always renders Phosphor Green regardless of the stored slot; switching away restores the prior accent; `DesignThemeTests` still green (Deep Field × cyan pixel-identity untouched). Small follow-up to #49; lives on the same theming branch.

## 51. ✅ CLI `build-for-testing` can't resolve TalariaTests' test host — blocks CLI test-compilation validation

> **CLOSED — header flipped 2026-08-01 (Hermes audit Part 1A).** Commit `450ed1e`; `project.yml` carries explicit TEST_HOST/BUNDLE_LOADER; build-for-testing + test-without-building green 2026-08-01.

> **Audit 2026-07-13:** Downgraded from a first-pass 'RESOLVED' flip to stale-wording after adversarial re-check. `project.yml:305-311` on main DOES now carry an explicit `TEST_HOST`/`BUNDLE_LOADER` override with a comment naming the exact PRODUCT_NAME-has-a-space bug this item diagnosed — but no one has re-run `xcodebuild build-for-testing` to confirm the 'could not find test host' error is actually gone (no PR/issue/commit/dated note records it), and sibling #52 scheme-drift is still open. Stays 🔧, not ✅. The 'Next:' paragraph is stale — `project.yml` no longer relies on xcodegen auto-derivation; it has an explicit override to verify against a real Mac `build-for-testing` run.

**Found 2026-07-04** (Mac, reviewing Fable's PRs). `xcodebuild build` of the `Talaria` app scheme succeeds, but `xcodebuild build-for-testing -scheme Talaria` fails with `Could not find test host for TalariaTests: TEST_HOST evaluates to ".../Debug-iphonesimulator/Talaria.app/Talaria"` — identically on `generic/platform=iOS Simulator` and on a concrete simulator id, and after a fresh `xcodegen generate`. So it is NOT the stale scheme (#52) and NOT a destination issue; the app target builds fine standalone. `project.yml` looks correct (`TalariaTests` = `bundle.unit-test`, `dependencies: [target: Talaria]`, app `scheme.testTargets: [TalariaTests]`), so xcodegen should auto-wire TEST_HOST/BUNDLE_LOADER — the failure is downstream of that.

**Impact:** PR reviews on the Mac can compile/verify the app target from the CLI but cannot compile the *test* targets — so test additions (e.g. the store PRs appending to `AppStoresTests.swift`) are diff-reviewed but not CLI-compiled. Xcode's GUI test runner resolves the host differently, so in-app test runs are unaffected.

**Next:** inspect the generated `TalariaTests` build settings (actual TEST_HOST/BUNDLE_LOADER values) and whether the app target is built as a dependency of the test action; compare against a known-good xcodegen unit-test setup. Until fixed, PR reviews use the app-build + diff bar and Owen runs the suite in Xcode.

## 52. ✅ Committed `Talaria.xcscheme` is stale vs `xcodegen generate`

> **CLOSED — header flipped 2026-08-01 (Hermes audit Part 1A).** Commit `3090c00` committed xcodegen's canonical scheme; later regens commit it as practice (`8902d2e`).

**Found 2026-07-04** (Mac). On clean `main`, `xcodegen generate` rewrites `Talaria.xcodeproj/xcshareddata/xcschemes/Talaria.xcscheme` (the pbxproj itself was already current), so the committed scheme has drifted from `project.yml`. Minor hygiene; did not resolve #51. **Fix:** regenerate and commit the scheme (or fold into the standing post-checkout xcodegen step), file-scoped.

## 53. ✅ Sensor drain — location/health outboxes decoupled (fix merged 2026-07-06; device verification owed)

> **Device pass 2026-07-13 (eve):** location/health outboxes drain independently on device — no drain/backlog storm.

> **Audit 2026-07-13:** Re-verified against current main (working tree = origin/main tip `cca1345`). The auditor's code citations are all accurate: `Talaria/Services/Live/SensorUploadService.swift` has `LocationUploadOutcome.retry` (line 136) with its own backoff (`locationBusyRetries`/`maxLocationBusyRetries`, lines 161 & 487-497), and `drainOutboxIfPossible()` runs location (lines 473-503) and health (lines 508-540) as two independent `while` loops — location always exits after one outcome (line 502) and unconditionally falls through to health (comment lines 505-507: "Independent of location — runs even when location failed above"). This traces to commit `fbb31e4` ("fix: decouple location and health outbox drain paths, add location retry/backoff," 2026-07-06) — its file content is byte-identical to HEAD's (`git diff fbb31e4:...SensorUploadService.swift cca1345:...SensorUploadService.swift` = empty), though `fbb31e4` itself is not a direct ancestor of HEAD (`git merge-base --is-ancestor` = false; `git blame` shows the boundary commit `^9964f02`), consistent with this repo's fork/rename history. Notably, a 2026-07-09 "dedup pass" commit (`b6913eb`) DID write this exact resolution into OPEN_ITEMS.md ("RESOLVED — on main since 2026-07-06... Verified in code on main") — but that commit is likewise NOT an ancestor of current HEAD, so its text is genuinely absent from today's file (confirmed: item #53's block, lines 1476-1478, is byte-for-byte the original 2026-07-04 report, no update notes at all — the auditor is correct that none was ever appended on the surviving lineage). However, even that lost note only claimed code-level verification, not device-verification — and per this project's own "merged != device-verified" standard, that is not sufficient to mark a client-side runtime/behavioral bug (originally caught via on-device connector-outage testing, symptom = health outbox count climbing) as ✅ done. No test target covers `SensorUploadService`/`LocationUploadOutcome`/`drainOutboxIfPossible` (zero hits outside the source file), and no note anywhere on current main confirms the original symptom (475→481+ climbing) was re-observed and is now gone. The closest corroboration is item #103 (2026-07-11 live production incident): a fresh investigation into a real connector-outage/backlog incident found "the app-side outbox machinery is correct" without flagging the #53 symptom — supportive circumstantial evidence, but not a targeted re-test of this exact scenario. Conclusion: the fix is real, structurally sound, and has been on main for a week, so the current 🐛 "open, unaddressed, GitHub issue snippet drafted" framing is factually stale and should be corrected — but the auditor's recommended clean "✅ RESOLVED" flip over-reaches past the available evidence. Recommend 🔧 (merged-unverified) with a note pointing at `fbb31e4` and flagging device re-verification of the original connector-outage scenario as the remaining step.

**Found 2026-07-04** (on-device, during connector-outage testing). `SensorUploadService.drainOutboxIfPossible()` drains location first and `break`s the entire loop on a location `.failed`, so it never reaches the health block. When location persistently returns `deliveryState=retry` (connector down / busy / forward stalled), the health outbox climbs unbounded even though health itself is fine — observed 475→481+ live. `LocationUploadOutcome` has no `.retry` case, so a transient `retry` is mis-mapped to a hard `.failed` that wedges the loop. **Fix (iOS, Fable):** a location failure must not `break` past health; give location its own transient retry/backoff (mirror health's `.retry` handling); drain the two outboxes on independent passes so neither can starve the other. Distinct from #24a (that was a poison *health* sample wedging health; this is the *location* path wedging health). GitHub issue snippet drafted.

## 54. ✅ Relay restart forces connector re-attach — RESOLVED (nonce DB-persisted + race-safe eviction, verified 2026-07-09)

> **Mac deployment re-verified 2026-07-15:** `verify-phase1.sh --restart-check` on the Mini —
> relay bounced via launchctl kickstart, connector reattached unattended, `last_connected_at`
> advanced. Same DB-backed behavior as OJAMD.

**Update 2026-07-12 (Mac deployment, verification owed):** the T6 Phase 1 re-home (#107)
adds a second deployment of this exact seam — launchd-managed connector vs launchd-managed
relay on the Mini. The 2026-07-11 OJAMD restart showed clean reattach, so this is expected
to hold; `scripts/mac/verify-phase1.sh --restart-check` bounces the Mac relay and watches
the connector's `state.json` `last_connected_at` advance. Record the Mac finding here when
#107 executes (stays ✅ unless the Mac shows a regression).

**RESOLVED 2026-07-09:** Server-side verified. Host-connection nonce lifecycle in `relay/app/services.py` (`activate` / `touch` / `deactivate`) operates on the `HermesHost` DB row (`active_connection_nonce` column, `db.commit()`), so it persists across relay restarts; `deactivate` clears only when the presented nonce matches the active one, so a stale socket's teardown can't strand a fresh reconnect (race-safe). Behaviorally: zero 4401 in the recent relay log, and the connector reattached cleanly (`/v1/hosts/ws [accepted]`) after this session's connector restart — corroborating the earlier relay-restart test. Connector-side auto-reconnect (ccee0f6) merged.

**Found 2026-07-04** (OJAMD, during the #15 relay hotfix). When `HermesMobileRelay` restarts (deploy/hotfix), it drops the connector's host WebSocket with close code 1012 (service restart). The connector does not reliably self-reconnect, and a subsequent reconnect can hit a transient **4401** — the relay still holds the stale host session from the unclean drop. Until the connector is restarted, sensor forwards return `deliveryState=retry` and no sensor data flows, which then wedges health app-side (→ #53). Root-caused this session: the 07-04 relay restart for #15 left the connector in exactly this state for hours. **Mitigations (in place):** operational — always restart the connector after a relay bounce (the new "Restart All" desktop shortcut does this in dependency order, and the connector NSSM service from GitHub #8 auto-restarts on crash). **Durable fix (server-side, #24f-adjacent):** persist the host-connection nonce so a relay restart doesn't force re-enroll/4401, and/or evict a stale host session promptly so a reconnect isn't rejected; connector-side, add auto-reconnect with backoff on 1012/4401. GitHub issue snippet drafted.
**Update 2026-07-04 (evening):** the mitigations shifted under #55 -- the `HermesMobileConnector`
NSSM service no longer exists (so "service auto-restarts on crash" no longer applies), and the
"Restart All" desktop shortcut references deleted services and needs rework for the
Startup-script world (queued in #55). The durable server-side fix (persist/evict the
host-connection nonce; connector auto-reconnect with backoff) remains open.

**Update 2026-07-12 — third clean reattach.** The #98 deploy restart of `HermesMobileRelay` was another live test of this path: after the relay came up on a fresh PID the connector reattached on its own (`/v1/hosts/ws [accepted]`, established WS to :8000), zero 4401. The nonce-persistence + race-safe-eviction fix continues to hold; nothing to reopen.

---

## 57. ✅ Wave 2 Issue G (GitHub #8) — attachment text-inlining + Extract Text OCR — MERGED (PR #11); device-verified 2026-07-20

**Device pass 2026-07-20 (Session C launch sweep): PASS — CLOSED.**

> **Audit 2026-07-13:** PR #11 (GitHub #8) merged this to main 2026-07-06; header's 'BUILT IN CLOUD, not compiled' is stale — AttachmentInlining.swift and DocumentTextExtractor.swift are on main and compiled. Unlike siblings #56/#58/#60, #57 is absent from the 2026-07-11 device-verification backlog (commit 373f65d) and carries no device-pass note — it is merged-unverified, not uncompiled.

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

## 59. ✅ Wave 2 Issue H (GitHub #9) — voice-memo attachments — MERGED (PR #11); device-verified 2026-07-20

**Device pass 2026-07-20 (Session C launch sweep): PASS — CLOSED.**

> **Audit 2026-07-13:** PR #11 (GitHub #9) merged this to main 2026-07-06; header's 'BUILT IN CLOUD, not compiled' is stale — VoiceMemoRecorder.swift/VoiceMemoTranscriber.swift/VoiceMemoAttachmentTests.swift are on main and compiled. Like #57, #59 is absent from the 2026-07-11 device-verification backlog (commit 373f65d) — merged-unverified, not uncompiled.

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
## 62. ✅ Wave 4 — stale test expectations fixed (GitHub #13 → PR #20)

> **CLOSED — header flipped 2026-08-01 (Hermes audit Part 1A).** PR #20 merged. Suite has moved 163 → 1463 tests since.

Test-only surgical pass, per the issue: `permissionTypeHasDistinctColorsAndIcons`
now asserts icon uniqueness against `PermissionType.allCases.count` (the enum
grew 6 → 8 and the literal staled); the streaming-failure recovery test renamed
to `...WhenStreamingInterruptedAfterJobAccepted` and rewritten against the
current semantics — the mock yields `.interrupted` and implements
`reconcileFromServer()`, with one reconcile pass driven deterministically via
`reconcilePendingRuns()` (the 2s loop is never slept on). No product code.
Expected 163/163 after the Mac test run.

## 63. ✅ Wave 4 — native background wake: BGAppRefreshTask + BGContinuedProcessingTask (GitHub #14 → PR #22)

> **Device pass 2026-07-13 (eve):** background wake (BGAppRefresh + BGContinuedProcessing) fires a run on device.

> **Audit 2026-07-13:** PR #22 merged (PR_INDEX; BackgroundTaskService.swift present on main) — the 'compile-check BGContinuedProcessingTaskRequest.strategy naming + register return handling' clause is stale pre-merge wording. Real remaining work is only the device-verify half (BGTaskScheduler `_simulateLaunchForTaskWithIdentifier` pass); keep 🔧 but drop the compile-check/'Needs Mac' framing.

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

## 64. ✅ Wave 4 — health widget tiles query HealthKit directly (GitHub #15 → PR #21)

> **Device pass 2026-07-13 (eve):** health-widget tiles read HealthKit directly on device.

> **Audit 2026-07-13:** PR #21 merged (PR_INDEX; Shared/HealthQueryCore.swift + HealthQueryCoreTests.swift present on main) — 'Needs Mac: build, then...' is stale wording. Only the device-verify half (tiles advance with app killed, snapshot shown when locked) remains open; keep 🔧, drop the 'build' framing.

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

## 65. ✅ Wave 4 — AlarmKit executor: /alarm behind the confirm gate (GitHub #16 → PR #23)

> **Device pass 2026-07-13 (eve):** AlarmKit `/alarm` rings through Silent mode on device.

> **Audit 2026-07-13:** PR #23 merged (PR_INDEX; AlarmService.swift, TalariaAlarmLiveActivity.swift, AlarmCommandParsingTests.swift present on main) — the 'compile-check AlarmManager.AlarmConfiguration/AlarmPresentationState/AlarmAttributes' clause is stale. Only the device-verify half (ring through Silent mode + countdown Live Activity) is still legitimately open; keep 🔧.

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

## 66. ✅ Spotlight tap-through — handler LANDED 2026-07-17 (round 2); device-verified 2026-07-20 (session results 3/3)

**Device pass 2026-07-20 (Session S launch sweep): PASS — CLOSED.** In-app Spotlight search
→ session result tap → opened directly TO THAT SESSION, 3/3 attempts. The tap-dies-upstream
defect this item chased is dead. Residual, deferred opportunistic (not blocking closure): the
Hermes-FILE result variant — the only indexed-eligible file was too recent to appear; check it
whenever a file result naturally surfaces, and eyeball the three SpotlightOpen .notice lines
in the same capture.

> **Device run 2026-07-17 (post-#107 build): tap still does nothing — and the #107 instrumentation
> did exactly its job: ZERO SpotlightOpen breadcrumbs in the capture (no entity-query line, no
> perform line, no deep-link line).** The failure is upstream of our intents entirely — the tap
> never reaches them. Refined root cause: `indexAppEntities` items opened from Spotlight deliver an
> `NSUserActivity` of type `CSSearchableItemActionType` (identifier in
> `CSSearchableItemActivityIdentifier`) — and the app handles that activity NOWHERE (grep
> verified). The #107 openAppWhenRun fix was necessary for the Shortcuts/Siri surface but not
> sufficient for Spotlight's tap path. **Fix (micro):** `onContinueUserActivity(
> CSSearchableItemActionType)` at the scene root → parse the entity identifier → route via the
> existing `hermes://session/{id}` / file deep-link path; keep the breadcrumb pattern (log the
> received identifier). GitHub #88 reopened with this evidence.

> **MERGED 2026-07-17 (PR #107, `39d17ee`).** Root cause was the #58 twin, exactly as the dispatch
> predicted: `OpenSessionIntent` + `OpenAgentFileIntent` paired `openAppWhenRun = true` with the
> `OpenURLIntent` returned from `perform()` — `openAppWhenRun` is read and acts BEFORE `perform()`,
> so the pair races and the tap dies. **Divergence from the #58 fix, deliberate and correct:** both
> are declared **explicitly `false`** rather than omitted, because `OpenIntent` rides the
> `SystemIntent` protocol chain whose default for the member is undocumented — absence could
> silently mean `true`. `SpotlightOpenIntentTests` pins both. Instrumentation KEPT at all three
> joints (entity query → perform → deep link, subsystem `org.aethyrion.talaria`, category
> `SpotlightOpen`) so Console names the broken joint without a rebuild. Loop: regen pbxproj-only,
> entitlements survived, **695 tests / 59 suites** green. → **Device re-verify owed:** Spotlight →
> search a session → tap → opens TO THAT SESSION; repeat for a Hermes file result; three `.notice`
> lines in order. If `perform()` never fires, the defect is donation-side, not launch-side.

> **Dispatch spec 2026-07-16:** `dispatch/FABLE-T27-66-spotlight-tapthrough.md` — **READY TO
> SEND.** Prime suspect found 2026-07-16 while validating GitHub #88: `SpotlightEntities.swift:89`
> `OpenSessionIntent` pairs `openAppWhenRun = true` with `perform()` →
> `.result(opensIntent: OpenURLIntent(url))` — the **identical combination** PR #100 removed from
> `HermesControls.swift` the same day to fix the inert Ask control (#58), where it made the system
> silently swallow the tap. Symptom matches: surface fires, nothing opens. `OpenAgentFileIntent`
> shares the shape and has never been device-verified. Spec instruments the three joints (entity
> query → perform → deep link) BEFORE fixing — these are `OpenIntent` not `AppIntent`, so the #58
> fix may not transfer verbatim and could even invert.

> **Device pass 2026-07-13 (eve): FAILED.** Search surfaced the session but tap → OpenSessionIntent did not open it. Needs investigation (Spotlight donation vs OpenSessionIntent wiring); code-investigatable, device-verify to confirm.

> **Audit 2026-07-13:** PR #24 merged (PR_INDEX; SpotlightEntities.swift, SpotlightIndexingService.swift, SpotlightIndexingTests.swift present on main) — 'compile-check the iOS 18 indexAppEntities/entity-query shapes' is stale. Only the device-verify half (Spotlight find → tap-through, toggle-off removes results) is still open; keep 🔧.

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

## 67. ✅ Wave 4.5 — LocalChatBackend: on-device chat brain (GitHub #26)

> **CLOSED — header flipped 2026-08-01 (Hermes audit Part 1A).** PR #32 merged — the brain it built IS the production brain, exercised by months of device batteries.

> **Audit 2026-07-13:** PR #32 merged (PR_INDEX; LocalChatBackend.swift + LocalChatBackendTests.swift present on main), and the router it was gated behind (#27) also merged as PR #33 — so the 'compile-check against the installed 27-beta SDK' clause is stale and the 'after #27 lands' gate is already satisfied. Remaining work is only the device checklist (airplane-mode local answer, kill/relaunch context continuity, Apple Intelligence off state, no SessionsHermesClient regression); keep 🔧.

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

## 68. ✅ Wave 4.5 — ChatBackendRouter: two brains, one seam (GitHub #27)

> **CLOSED — header flipped 2026-08-01 (Hermes audit Part 1A).** PR #33 merged; routing truth is covered by the #190–#192 arc.

> **Audit 2026-07-13:** PR #33 (GitHub #27) confirmed merged to main; ChatBackendRouter.swift + ChatBackendRouterTests.swift present at HEAD cca1345. Per MAIN_LOG (373f65d backlog listing, f35edb9 verification results) item #68 was NOT among the #69/#70/#92 items verified on 2026-07-11, so 🔧 and the device checklist / Questions for Owen correctly stand open. Correction: 'Needs Mac: compile + device' is stale on the compile half — the merge already required a successful build; only the device-verification pass and the two open product decisions remain owed.

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

## 69. ✅ Wave 4.5 — device tool belt v1: read tools for the local brain (GitHub #28)

**Device pass 2026-07-11: PASS (initially misread as fail)** — local brain called its native belt (e.g. deviceStatus), which IS the design: these Swift Tools are the device-side mirror; `hermes_mobile` MCP is the server-side path for the cloud agent. Tool calls fired and rendered.

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

## 70. ✅ Wave 4.5 — action tools + ToolConfirmationCenter (GitHub #29)

**Device pass 2026-07-11: PASS** — confirm gate appeared before the write; approve performed it.

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

## 71. ✅ Wave 4.5 — standalone onboarding: pairing wall removed (GitHub #31)

> **Device pass 2026-07-13 (eve):** standalone onboarding — usable on a fresh install with no pairing wall.

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

## 73. ✅ Wave 5 — native fallback voice mode: SpeechAnalyzer → active backend → AVSpeechSynthesizer (GitHub #18)

> **CLOSED — header flipped 2026-08-01 (Hermes audit Part 1A).** PR #39 merged; echo/barge-in residuals live at #130 and #138.

> **Audit 2026-07-13:** PR #39 (`claude/w5-18-native-voice`→main, merged) and GitHub #18 (closed) confirm this landed; `Talaria/Services/Live/NativeVoicePipelineService.swift`, `Talaria/Services/Support/VoiceEngineRouter.swift`, and `TalariaTests/NativeVoicePipelineTests.swift` are present on main. The 'BUILT IN CLOUD, not compiled or device-verified' and 'Needs Mac: xcodegen generate...' wording is stale (merge already implies xcodegen+build+test); the real remaining work is the on-device checklist (mic→transcription→chat brain→TTS loop, echo cancellation, relay-down/airplane-mode path) — keep emoji 🔧 as merged-unverified.

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

## 76. ✅ Orphan-surface audit — hygiene tooling (GitHub #49)

> **Audit 2026-07-13:** Re-verified independently and upheld as under-reported. PR #50 (claude/t27-49-orphan-audit→main) Merged=YES; issue #49 CLOSED. `tools/orphan-audit.sh` (16235 bytes, executable) has `--self-test` (arg at line 255) and `SELF_TEST_ORACLE` (line 57, 5 real graveyard names); `tools/orphan-audit-report.md` (27059 bytes) opens "Generated by `tools/orphan-audit.sh` at commit `6e604e9`" and contains all four claimed tiers/counts (12/8/118/38). `BRANCHING.md:66,68` carries the checklist line verbatim. Went beyond the original note's evidence: actually re-ran `bash tools/orphan-audit.sh --self-test` live against current origin/main tip (cca1345; tree has grown to 222 app files/388 types vs. 204/324 at authoring) — exit 0, "self-test OK — all 5 known graveyard types re-flagged." A second in-repo corroboration exists at OPEN_ITEMS.md:2438 (item #80's same-day note): "Orphan-audit `--self-test` re-run: still green." Pure bash+python tooling, no Xcode/device dependency, nothing pending in the item's own text ("No app code touched, no xcodegen. Nothing was deleted; the report is the deliverable") — meets the done carve-out for docs/tooling items. Header corrected 🔧→✅. (Side note: the original PR-merge commits 335a1c0/986bc62/6e604e9 are not in current origin/main's git ancestry — but this is a repo-wide artifact affecting the whole #50–#55 stacked wave equally, not specific to #76; file presence + PR_INDEX + live execution all independently confirm the deliverable is on main and functioning, per the guide's own warning not to rely on git ancestry for squash/rewrite cases.)

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

## 79. ✅ Turn Receipts — per-turn tokens, cost, and time (GitHub #46)

> **Audit 2026-07-13:** Header corrected 🔧 → ✅ (independently re-verified). PR #53 (`claude/t27-46-turn-receipts`→main) confirmed Merged=YES in PR_INDEX.md; GitHub #46 and follow-up #57 both confirmed CLOSED in ISSUE_INDEX.md. Code confirmed on the current `origin/main` checkout: `Talaria/Services/Support/TurnReceipts.swift` + `TalariaTests/TurnReceiptsTests.swift` exist; `ModelPricingCatalog` used at `ModelsSettingsScreen.swift:62,80`, `ChatScreen.swift:741,746`, `MessageBubble.swift:309`, `AppContainer.swift:1290`; `Message.swift:77,80,83` has `usage`/`turnDuration`/`servingModel`. The #57 hardening (`.lineLimit(1)` + `.minimumScaleFactor(0.7)` + `.truncationMode(.middle)` + `.frame(maxWidth:.infinity,.leading)`) is present verbatim at `MessageBubble.swift:317-320`, matching commit `81b160c`'s diff exactly (verified with `git show 81b160c`) and matching the item's own note description word-for-word. The item's own second 2026-07-08 note explicitly states "merged to main via PR #53; device-verified with the wave" with concrete runtime detail ("Runtime measurement showed the receipt itself fit at ~319pt"). Independently corroborated by cross-referenced item #83, which documents an actual on-device debugging session that same evening that specifically runtime-measured ("`sizeThatFits` measurements") and exonerated the "receipt" component of a display bug — this is external, non-self-referential evidence of genuine device verification, not a rubber-stamped claim. Contrast with sibling wave items #76-78/#80-81, which remain single-note "BUILT IN CLOUD, not compiled or device-verified" with no such follow-up — confirming #79's second note is a deliberate, specific update, not a templating artifact.

**Update 2026-07-08 (cloud session, branch `claude/t27-46-turn-receipts`):**
BUILT IN CLOUD, not compiled or device-verified. Every turn's usage report
was decoded, persisted, and rendered nowhere; duration was measured and
discarded; pricing was downloaded and thrown away. All three now land:
- **`Message.usage` / `.turnDuration` / `.servingModel`** (persisted,
  `decodeIfPresent` — pre-#46 caches decode). Stamped at `.finished`: usage
  from this run's `run.completed` (or the local brain's `session.usage` —
  local turns get receipts too, iOS 27 only per #67's real-data rule);
  duration from `pendingMessageSentAt` (previously nulled without stamping);
  `servingModel` = `activeModelName` **only for hermes-brain turns** (an
  on-device turn priced at the Hermes model's rate would be a lie).
  `mergeConversationMetadata` preserves all three (client-only, like
  reasoning). Reconciled (#38-detached) turns get duration from real
  timestamps + usage only when the adopted reply is the session's last.
- **Pricing kept:** `ShimProviderRow.pricing` now decoded
  (`ShimModelPricing` display strings, per-1M implied); new
  `ModelPricingCatalog` (**new file** `Services/Support/TurnReceipts.swift`)
  parses + persists to UserDefaults, harvested at all three existing fetch
  sites (picker load/refresh + `seedActiveModelFromShim`). Lookup tolerates
  `provider/model`, `provider:model`, and bare ids; an ambiguous bare name
  with differing prices refuses to guess. ⚠️ `convertFromSnakeCase` would
  mangle a model id containing `_` (none exist today) — that model would
  just show no cost.
- **UI:** compact receipt footer on metered Hermes bubbles
  ("IN 1.2K · OUT 356 · 8.4S · ~$0.0042"); **CTX gauge is now tappable** →
  resurrects `StatusCardView` (`showStatusCard` was init-false, set-false
  only — the audit's dead-but-wanted case) with LAST TURN
  (input/output/total/duration/est. cost) + SESSION sections (metered turns,
  Σ input/output — summing input IS the billed amount since every turn
  re-reads context — model time, est. cost with honest x/y-turns-priced
  coverage) + the no-cache-split disclaimer line.
- **New files:** `TurnReceipts.swift` + `TurnReceiptsTests.swift` (13 tests:
  parse/match/ambiguity/cost math/round-trip/formatting) → **xcodegen regen
  owed** (re-verify aps-environment etc. per the regen checklist).

**Needs Mac:** regen + CLI build + tests; device: send a turn → footer
receipt appears with real numbers; open Models once (harvest pricing) →
cost appears labeled "~"; tap CTX gauge → card with session totals; local
brain (iOS 27) turn shows receipt with no cost; distinct from OPEN_ITEMS #25
(CTX denominator accuracy — still open).

**Update 2026-07-08 (merged to main via PR #53; device-verified with the wave):**
Follow-up hardening `81b160c` (gh#57, closed): the receipt `MonoLabel` got
`.frame(maxWidth:.infinity, .leading)` + `.lineLimit(1)` + `minimumScaleFactor(0.7)` +
middle truncation — the messageList `LazyVStack` has no horizontal width cap on children,
so any unconstrained row *could* widen the whole column. (Runtime measurement showed the
receipt itself fit at ~319pt; the evening's portrait "clip" was actually the device-side
Display Zoom/beta letterbox → item #83. The cap stays as cheap insurance.)

---

## 84. ✅ Talk-mode preflight + mic flatline tripwire + route display — merged (PR #62); device checklist PASSED 2026-07-20

**Device pass 2026-07-20 (whoGoesThere, Session V launch sweep): PASS — CLOSED.** All six
checklist steps verified: denied-mic → actionable banner (never LISTENING); live speech → no
hint; 12s silence → flatline hint, first words clear it; mute-through-window rearm; ROUTE line
updates on BT attach/detach; Diagnostics Voice/Talk panel shows real states.

> **Audit 2026-07-13:** PR #62 (branch `claude/t27-84-talk-preflight`) merged to main 2026-07-10 (`8830b11`). `Talaria/Services/Support/TalkPreflight.swift` and `TalariaTests/TalkPreflightTests.swift` (20 @Test cases) are confirmed present at origin/main tip `cca1345`. The 'BUILT IN CLOUD, not compiled' header and 'Needs Mac: xcodegen generate ..., CLI build' body text are stale — that build step already happened as part of the PR #62 merge. The on-device checklist (items 1-7, including the reboot-guidance addition from the 2026-07-10 update) remains unconfirmed — no device-verification note exists, so this stays merged-unverified rather than done.

**The "never again" from the #82 evening (2026-07-08), built 2026-07-09** (cloud session,
branch `claude/t27-84-talk-preflight`). Talk rendered a live LISTENING state over a dead
microphone — transport connectivity was treated as proof of audio. Shipped, on BOTH engines
(realtime/WebRTC + #73 native fallback):
- **Preflight:** standardized actionable permission wording (`TalkPreflight.swift`:
  `TalkMicPreflight`) — mic denial (both engines) + Speech Recognition denial (native)
  block the start with "…is off — enable it for Talaria in Settings." and the overlay's
  OPEN SETTINGS deep link; the link's gate is now a shared predicate
  (`isPermissionActionable`) kept in lockstep with the engine wording (the old substring
  check missed the speech-permission phrasing). A denied mic never reaches "Connected".
- **Flatline tripwire:** `.connected` arms a 12s window (`MicFlatlineRule`, pure +
  unit-tested in `TalkPreflightTests`). Zero speech evidence (no `speech_started`/
  committed/transcription events realtime; no volatile/finalized transcription native)
  while connected + unmuted → non-fatal mic-health hint under LISTENING + settings link,
  instead of silent listening. Muted windows re-arm; unmute restarts; first evidence
  disarms. Snapshot field `micHealthHint`.
- **Route visibility:** snapshot field `audioRouteSummary` ("iPhone Microphone → Speaker"),
  refreshed at connect + every route change → ROUTE line in the talk overlay + new
  `// Voice / Talk` panel in Diagnostics (Microphone, Speech Recognition, live Audio
  Route). The stale-BT-route-with-dead-mic was the other live #82 suspect.

**Needs Mac:** `xcodegen generate` (2 new files: `Talaria/Services/Support/
TalkPreflight.swift`, `TalariaTests/TalkPreflightTests.swift`; re-verify `aps-environment`
survives per #48), CLI build + `TalkPreflightTests`, then device: (1) mic permission off →
launch talk → actionable banner + OPEN SETTINGS, never "Connected"/LISTENING; (2) grant →
speak → no hint; (3) stay silent 12s+ → hint appears, first words clear it; (4) mute
through the window → no hint until unmuted-silence; (5) ROUTE line updates on
BT-headset attach/detach; (6) Diagnostics Voice/Talk panel shows real states. Note: the
handoff referenced `tools/diagnostics/README.md` for the diagnostic ladder — that file
does not exist in the repo (the ladder likely lives in the gitignored `handoffs/`); the
Diagnostics panel rows cover its first rungs (can record / can transcribe / where audio
routes).

**Update 2026-07-10 (Lane C item 5, cloud session):** third preflight state added.
The preflight was two-way — permission granted → proceed, else "Microphone access is
off — enable it for Talaria in Settings." — so the #82 wedge shape (permissions ON,
capture side dead) read as a permission problem and dead-ended the user in Settings.
`TalkMicPreflight.classify(permissionGranted:inputAvailable:)` is now the shared
three-way decision core (`ok` / `permissionDenied` / `noInputAvailable`); both engines
switch on it at start. The no-input state blocks with `noMicInputMessage` ("Microphone
permission is on, but no mic input is reachable — try rebooting this iPhone.") and is
explicitly carved OUT of `isPermissionActionable` so the overlay never offers the OPEN
SETTINGS dead end for it. Input probe = `AVAudioSession.isInputAvailable`
(`isMicInputAvailable()`); whether the seed wedge actually trips that flag is a
device-checklist question (post-seed). New `TalkPreflightTests` cover the classifier
(all three states + denial-wins-over-missing-input), the reboot-wording contract, and
the actionable-predicate carve-out. No files added/removed — no xcodegen regen owed for
this update. Device checklist addition: (7) with permissions granted and capture wedged
(pre-seed-fix state, or a simulated no-input route), talk start must show the reboot
guidance with NO OPEN SETTINGS button, never "Connected"/LISTENING.

Logged 2026-07-09.

---

## 85. ✅ hermes_delegate MCP path — advertising gated + URL normalized — RESOLVED (deployed on OJAMD; verified live 2026-07-25)

> **CORRECTION 2026-07-25 (OJAMD server pass).** The "OJAMD deploy owed" note was
> stale. The change is deployed and running. Verified against the live checkout at
> `O:\Hermes\Talaria` on the box — not against a document snapshot: all four
> markers present at their named sites, and the source mtimes (2026-07-20
> 23:19:37) predate the relay service start (2026-07-24 21:53:26), so the running
> process demonstrably loaded this code. No deploy session is owed.

**Found 2026-07-08 (OJAMD logs), built 2026-07-09** (cloud session, branch
`claude/t27-85-mcp-path`). Every voice session logged `mcp_list_tools.failed`: the relay
handed OpenAI's Realtime API an MCP server URL built as `{PUBLIC_BASE_URL}/talk/mcp`, but
(a) the endpoint mounts at the literal `/v1/talk/mcp`, so a base URL without the `/v1`
suffix registered a 404ing URL, and (b) OpenAI fetches the tool list from *its* servers,
so OJAMD's Tailscale-CGNAT base (`100.110.102.59`) can never serve it regardless of path —
the round-trip was doomed every session.

**Shipped (both halves in this repo, suites green in-container):**
- Relay: `build_talk_mcp_url()` normalizes with/without-`/v1` and trailing-slash spellings
  onto the mounted route; new `TALK_MCP_ADVERTISE` env (`auto`|`always`|`never`, default
  `auto`) withholds `relayMcpURL` from `talk.session.create` when the base host isn't
  publicly routable (IP literals via `is_global` — loopback/RFC1918/100.64-10 CGNAT
  excluded; hostnames public unless `localhost`/`*.local`). Token auth unchanged; skip is
  logged once per mint. Relay suite 83 passed.
- Connector: `talk.session.create` no longer raises when `relayMcpURL` is absent — the
  realtime session mints without the `hermes_delegate` tools block, so plain voice is
  unaffected. Connector suite 102 passed, 1 skipped.

**Remaining:** deploy relay + connector halves on OJAMD (no env change needed — `auto`
does the right thing on the tailnet IP); the real delegation transport is the ⛔
OJAMD-side Tailscale Funnel / Cloudflare Tunnel work (then either `TALK_MCP_ADVERTISE`
stays `auto` with the public hostname or is forced `always`). Once public, set
`PUBLIC_BASE_URL` to the tunnel hostname and hermes_delegate lights up with zero code
change.

Logged 2026-07-09.

---

## 86. ✅ Relay QueuePool exhaustion — session-across-await audit + pool hygiene — DEPLOYED on OJAMD (verified 2026-07-25); pool ceiling untouched

> **CLOSED — header flipped 2026-08-01 (Hermes audit Part 1A).** DEPLOYED on OJAMD, verified 2026-07-25. Pool ceiling deliberately untouched.

> **CORRECTION 2026-07-25 (OJAMD server pass).** "OJAMD deploy owed" was stale.
> `pool_pre_ping` and `pool_recycle` are deployed and live, verified the same way
> as #85 (markers present at named sites; source mtime predates service start).
>
> **Scope annotation.** What shipped fixes connection *staleness*. It does not
> raise the ceiling: `pool_size` (5) and `max_overflow` (10) are still at their
> defaults, and the ceiling is what the original `QueuePool limit` error names.
> Deliberately NOT split into a new item — both tracebacks in `relay.log` name
> `main.py:1999 in hosts_websocket`, but line 1999 of the deployed `main.py` sits
> inside `send_push` and `hosts_websocket` begins at 2341, so those tracebacks
> were emitted by an earlier file and predate the running code. There is no
> evidence the ceiling has been reached since the deploy. Trigger for opening a
> real item: a fresh traceback whose frames match deployed line numbers.

**Found 2026-07-08 (OJAMD logs: `QueuePool limit of size 5 overflow 10 reached`, 2×), built
2026-07-09** (cloud session, branch `claude/t27-86-relay-pool`). Root cause: FastAPI's
`get_db` dependency closes the request session only when the *response* finishes, and
several handlers awaited slow things with that session's pooled connection checked out:
the **SSE job-events stream pinned a connection for its entire lifetime** (primary vector),
the three talk endpoints pinned across connector RPCs (30s each on a hung connector — 7/8
was a day of repeated talk mint/end cycles for #82), `send_message` across the sync wait,
the sensor/commands endpoints across ack waits (via the auth dependency's session), and
both APNs push helpers across network sends.

**Shipped:** every audited site releases the connection (`db.close()`) before awaiting —
the session transparently reopens on next use; push helpers now materialize `PushTarget`
values in a short session and send pool-free; engine gains `pool_pre_ping` +
`pool_recycle=1800`; a middleware logs `pool.status()` + full traceback on pool timeout and
full route+traceback on any unhandled exception (the 7/8 one-off `'NoneType' object has no
attribute 'splitlines'` RuntimeError had surfaced context-free — next occurrence won't).
Regression test watches `pool.checkedout()` while an SSE stream is live. **Relay suite: 89
passed in-container.** Remaining: deploy on OJAMD; keep an eye on the relay log for the
`DB pool exhausted` marker (now impossible to miss) if it ever recurs.

Logged 2026-07-09.

## 87. ✅ Connector — subprocess output decoded as cp1252 on Windows — RESOLVED (ACTUALLY deployed 2026-07-11; the 07-09 claim below did not hold)

**Correction 2026-07-11:** the 07-09 "deployed" status was wrong in effect — on 07-11 the OJAMD deploy repo was 107 commits behind `t27/main` and the connector had been dead since 07-02 (killed by this very defect; see #103 post-mortem). Whatever happened on 07-09, the fixed code was not running. Real deploy: 2026-07-11 rebase + connector restart; attach and backlog drain confirmed.

**RESOLVED 2026-07-09:** Deployed to OJAMD. `ojamd-deploy` rebased onto `t27/main` (helper commit replayed clean, no conflicts); fix confirmed live on the editable module (19 `errors=replace` sites); connector restarted and holding its WS to the relay; `hermes memory status` populates cleanly. The cp1252 tracebacks still in connector.log are pre-deploy residue (file static since 2026-07-02).

**Found 2026-07-09 (reproduced live on OJAMD), built same day** (cloud session, branch
`claude/connector-utf8-subprocess-fypam0`). Root cause: every connector
`subprocess.run(..., text=True)` omitted `encoding=`, so Windows decoded the child's
stdout/stderr pipes with the locale codepage (cp1252 — `PYTHONUTF8` does not reach the
connector process). `hermes` prints UTF-8 (box-drawing `─` = e2 94 80, em-dashes), so the
reader thread threw `UnicodeDecodeError: 'charmap' codec can't decode byte 0x90` — a
daemon-thread exception, non-fatal, but the child's output was **silently lost** (empty
`hermes memory status` → `summarize_memory_provider` degraded, skills list `[]`, version
detection failed, mcp registration output dropped) plus 1,192 tracebacks in connector.log.
Pre-existing; unrelated to #85/#86. Core paths (host WS, sensor ingestion) and chat
(iOS → `:8642` direct) were never affected.

**Shipped:** `encoding="utf-8", errors="replace"` pinned on all 17 text-mode subprocess
call sites (talk_support, client ×2, hermes_runner ×2, mcp_registration ×3, git_diff ×4,
cli ×4, service_management); byte-mode calls and file reads untouched. Tests are
platform-independent (CI is Linux/UTF-8 where the locale default masks the bug): an AST
audit in `tests/test_subprocess_encoding.py` asserts every text-mode subprocess call in
the package pins utf-8/replace — new call sites can't regress silently — and an
end-to-end test forces the exact bad bytes (e2 94 80 + 0x90) through a real pipe via
`summarize_memory_provider`. Both fail against the unfixed code. **Connector suite: 104
passed / 1 skipped.** Remaining: reaches OJAMD prod on the next ojamd-deploy reconcile —
after deploy, confirm connector.log stops accruing `_readerthread` UnicodeDecodeError
tracebacks and `summarize_memory_provider` returns real provider lines.

Logged 2026-07-09.

## 88. ✅ OJAMD `restart-relay.ps1` — relay half stale — RESOLVED (fixed 2026-07-09)

**RESOLVED 2026-07-09:** Relay half changed to `Restart-Service HermesMobileRelay`; header comment corrected to flag NSSM + elevation; connector half left as-is; script parses clean. Lives in `~/.hermes/scripts/` (outside the repo, untracked) — left there by design, not a repo-tracked ops script.

`~/.hermes/scripts/restart-relay.ps1` still restarts the relay via
`scripts/start-relay.bat` as a plain user process (“post-nssm world, #55” comment
notwithstanding) — but the relay is NSSM-managed again (`HermesMobileRelay`, verified
2026-07-09: nssm.exe → uvicorn `app.main:app --host 0.0.0.0 --port 8000`). Running the
script as-is would start a second uvicorn that fights the service for `:8000`.

**Fix:** relay half becomes `Restart-Service HermesMobileRelay` (needs elevation — keep
Owen’s paste-into-elevated-PowerShell pattern); the connector half
(`start-connector.bat`, single-instance enforcer) is still correct as-is.

Logged 2026-07-09.

## 89. ✅ P1 "brain" transplant-fidelity probe — PASS → Lane A GO

**Ran 2026-07-09 against the Sessions API (`http://ojamd:8642`, sync `POST /api/sessions/{id}/chat`).**
Three-arm probe — A (original session: entangled facts + a mid-stream $4,200 to $4,700 correction),
C (raw replay into a fresh session), B (condensed ~10:1 priming into a fresh session). B was
indistinguishable from A and C on recall, cross-turn inference, and the correction: the condensed
priming read as continuous *context*, not a quoted artifact, and B reconstructed inference the priming
never spelled out. -> **transplant mechanism validated; Lane A = GO.**

**Condenser-fidelity rung (same day):** had Hermes itself condense a messier 9-turn transcript (two
corrections + two distractors), then transplanted the machine summary. Fidelity clean — both corrections
preserved at their latest values, distractors never leaked into answers, cross-turn inference held.
Residual is **pruning discipline / token cost** (the condenser kept the distractors as ballast despite
being told to drop them), not fidelity. Caveat: used the full Hermes model as the condenser (optimistic
proxy) — the on-device LocalIntelligenceService is the real test and likely needs the pruning discipline
more; that validation is app-side (Fable/Xcode). Bonus finding: long single sessions degrade per-turn
(70s to 126s by turn 9 vs 5–14s on fresh sessions) — an argument *for* the condense-and-transplant
architecture. Reusable harness: `C:\Users\Owen\talaria-probe\probe.py`.

Logged 2026-07-09.

## 91. ✅ Theme suite — SHIPPED: Event Horizon bar cleared, Phase 2 schema + full gallery port merged

> **Audit 2026-07-13:** Header confirmed accurate - PRs #66, #70, #72, #73, #74 all Merged=YES per PR_INDEX (code present in Shared/ThemePaletteCore.swift, Talaria/Core/ThemeArtDirection.swift, Talaria/Core/HUD/{ReactorOrb,ThemeTextures,HUDComponents}.swift); #71 correctly shows Merged=no, matching the item's 'lost PR, recreated as #74' account. The trailing 'Update 2026-07-11 (cloud session — Phases 2+3 BUILT, NOT compiled, gated on device verdict)' paragraph is now stale — it predates the merge + device-verdict pass documented above it and still cites the superseded PR #71. Recommend trimming or marking that paragraph historical.

**Context (verified at HEAD 2026-07-10):** the `talaria-neon-arcade` gallery (17 themes; now in-repo at `design/themes/`) is the outrageous-theme suite. On device today: 4 flagships + 4 seasonals + 4 complex (Cereal Box / Bubblegum Mecha / Retro Sci-Fi / Event Horizon), all selectable. Why the complex ones "didn't hit right": (1) no atmosphere motion engine — the handoffs' 4-layer parallax drift was never ported; (2) no bespoke orbs — `ThemeOrbStyle` has only the 4 flagship cases, complex themes fall back to `.arcReactor`; (3) only Event Horizon has an art-direction override — the other three are pure recolors. 10 gallery themes unported entirely (incl. Neon Arcade #01 itself, Glitch Garden, Witch's Brew, Holo Sushi, Lunar Diner, Cyber Cactus, Deep Sea Diner, Disco Inferno, Graffiti Galaxy SE, Karaoke Supernova SE).

**Phase 1 (Lane E, spec at `dispatch/FABLE-LANE-E-theme-drama.md`):** catalog taxonomy → gallery categories (Flagship / Neon Arcade Collection / Special Edition / Seasonal); data-driven atmosphere motion engine (TimelineView+Canvas, 3 on-device A/B presets, reduced-motion safe, widget layer untouched); `.singularity` orb composition; Event Horizon intensity pass. No `ChatScreen.swift` overlap — independent of Lanes A–D merge order.

**Gate: CLEARED 2026-07-11 — "Now THAT is an outrageous theme" (device verdict, PR #66 merged).** Phase 1 shipped: taxonomy sections, atmosphere motion engine (3 presets, ships `.faithful`), `.singularity` orb, intensity pass, PLUS two device-verdict corrections that ARE the Phase 3 recipe: (a) specks render as soft blurred points (1.25pt + per-layer blur), never hard discs — CSS `radial-gradient(… transparent 2px)` is a fade, not a radius; (b) panel/card/bubble washes must NOT be promoted to screen-scale glow pools (the teal-swamp bug); (c) port the full element inventory — the `.spin-ring` lensing starburst (now `RadialSpokeSpec`/`RadialSpokeField`) was the design's biggest chat-surface drama and the original port skipped it. **Phase 2+3 SHIPPED 2026-07-11** (PRs #70 schema → #74 batch 1 → #72 batch 2 → #73 batch 3, all device-verdicted): 20-theme catalog — 4 Flagship, 9 Neon Arcade Collection (shipped trio drama-retrofitted + Glitch Garden, Witch's Brew, Holo Sushi, Lunar Diner, Cyber Cactus, Disco Inferno), 3 Special Editions (Event Horizon, Graffiti Galaxy w/ TAG ribbon + panel top-strip, Karaoke Supernova), 4 Seasonals. **Deep Sea Diner CUT on device verdict** (too close to Deep Field) — settings decode hardened so a vanished theme degrades to Deep Field instead of resetting prefs; `.anglerLure` orb kept as an intentional orphan (reusable). Correction-round learnings added to the recipe: stacked-PR merges = merge → retarget next PR to main → THEN delete branch (GitHub auto-closes, not retargets — #71 was lost to this, recreated as #74); "tests pass" means nothing if the count doesn't move (stale DerivedData shipped a stale test bundle — nuke on suspicion). Icon SVGs still missing for graffiti-galaxy / karaoke-supernova / event-horizon in `app-icons.html`. NEXT WAVE staged: three Claude-Design SE candidates (Midnight Aquarium, Molten Forge, Haunted VHS — `Neon-Arcade-2.zip`), ~90% schema-native; gaps = line-field drift, heat-shimmer breather, REC blink; Molten-vs-Solar-Forge identity overlap flagged for Owen pre-port.

**Related:** orb enhancement issue filed on Talaria-27 (2026-07-10; the 7/6 draft was never actually filed).

**Update 2026-07-11 (cloud session — Phases 2+3 BUILT, NOT compiled, gated on device verdict):**
four stacked PRs open, merge order **#70 → #71 → #72 → #73**, ZERO new files across the lane
(no `xcodegen generate` needed). **#70 Phase 2 schema:** full 12-theme element inventory
(table in the PR) drove ONLY these extensions — `ThemeLineFieldSpec` (angled lattices /
dark scanline rows / spray streaks; two slots: `lineTexture` below the grid,
`scanlineOverlay` above), `ThemeTitleShadowSpec` (comic/chromatic offset titles + Glitch's
3s jitter), `ThemeGlowPool.pulsePeriod` (Karaoke roomPulse), `AtmosphereMotionSpec.Layer`
`tileHeight`/`barHeight`/`blurScale` (non-square laser tiles, bar specks, crisp halftone) —
every default inert, EH pinned byte-identical by test; PLUS all twelve gallery orb
compositions (tri-ring family parameterized; bespoke disco ball / spray cap / rocket badge /
cauldron bubbles / ♪ mirror ball), landed unwired, Appearance preview generalized to render
any bespoke orb. **#71 batch 1:** Glitch Garden / Witch's Brew / Holo Sushi (full identities)
+ drama retrofits for Cereal Box / Bubblegum Mecha / Retro Sci-Fi (art direction + handoff
orbs; palettes untouched). **#72 batch 2:** Lunar Diner / Cyber Cactus / Deep Sea Diner
(inverted abyss gradient, verbatim) / Disco Inferno (bright sparkle field + gold dot grid as
palette data, glow 1.2). **#73 batch 3:** Graffiti Galaxy + Karaoke Supernova SEs (pulsing
spotlights, drifting laser bars, panel halos, tag-shadow title; NA#01 confirmed = gallery
chrome, NOT ported). Recipe rules 1–3 enforced throughout; deferred elements dispositioned
in the PR tables (TAG ribbon, card top-strip/wash, bubble-scope pips, title outline echo).
Noted for the Mac session: Cereal Box × Cyber Cactus share the #FF5078 hero verbatim
(distinct-environments test relaxed accordingly, commit in #72); icon SVGs missing for
graffiti-galaxy / karaoke-supernova / event-horizon in `app-icons.html` (Mac-side assets).
Device-verdict knobs called out per PR (laser `barHeight`/`speckRadius`, graffiti streak
`lineWidth`, atmosphere presets precedent).

---

## 92. ✅ Lane B — markdown rendering depth (dispatch FABLE-LANES-BC)

> **Audit 2026-07-13:** Confirmed device-verified and merged — PR #60 Merged=YES; CodeSyntaxHighlighter.swift and all 5 named Markdown*Tests.swift files present on main; item #100 independently cites '#92 verified 2026-07-11', matching this item's own 'Device pass 2026-07-11: PASS' line. The trailing 'Update 2026-07-10 (cloud session...): BUILT IN CLOUD, not compiled or device-verified... Needs Mac: xcodegen generate + CLI build + device test' paragraph is now stale, superseded by the device pass recorded above it — recommend trimming or marking it historical.

**Device pass 2026-07-11: PASS** — table/headings/quote/lists/code block all rendered on device. Unblocks #100.

**Update 2026-07-10 (cloud session, branch `claude/lane-b-handoff-g8zxbl`):**
BUILT IN CLOUD, not compiled or device-verified. `MarkdownSegment` grew from
three cases (prose / codeBlock / image) to seven:

- **Headings** — ATX `#`–`######`, space-after-hashes required (`#hashtag`
  stays prose), closing-hash runs stripped, inline markdown preserved;
  rendered at graduated Space Grotesk sizes, levels 1–3 in
  `foregroundBright`.
- **Block quotes** — 1-based `>` depth; consecutive same-depth lines merge,
  a depth change starts a new segment (`>> ` and `> > ` both = depth 2);
  rendered with an accent bar + `secondaryForeground`, indented per level.
- **Lists** — `-`/`*`/`+` bullets and `1.`/`1)` ordinals (1–3 digits, so
  `2026.` stays prose) in one segment with per-item depth via an
  indent-stack (≥2 cols = deeper); one blank line tolerated between items,
  two end the list; indented continuation lines append to the prior item;
  bullets `•`/`◦`/`▪` by depth, ordinals rendered from the literal numbers.
- **Tables** — GFM pipe tables gated on a real delimiter row with matching
  cell count (pipe-containing prose stays prose); `:---:`-style alignments;
  rows normalized to header width; `\|` escapes; rendered as a
  horizontally-scrollable `Grid` in a hudPanel with header rule + faint
  row striping. Streaming: header renders as prose until its delimiter row
  arrives — self-heals on the next delta.
- **Syntax highlighting** — new `Talaria/Core/CodeSyntaxHighlighter.swift`:
  single-pass tokenizer (keywords / strings / comments / numbers) with
  profiles for swift, python, js/ts, json, bash, yaml, c-family; unknown
  languages get a conservative strings+numbers-only fallback. Colors ride
  the live theme palette (keyword `accentBright`, string `forge`, comment
  `dimForeground`, number `accent`); `CodeBlockView` now renders the
  highlighted AttributedString.

Parser + tokenizer logic verified in-session via a line-for-line Python
port run against every test expectation (all green); Swift Testing suites:
`MarkdownHeadingTests` / `MarkdownBlockQuoteTests` / `MarkdownListTests` /
`MarkdownTableTests` / `CodeSyntaxHighlighterTests` /
`MarkdownInterleavingTests` (+ `MarkdownTestSupport` accessors). Existing
behaviors pinned: prose/image interleaving order, streaming unclosed-fence
emission, non-streaming empty-fence prose fallback, block syntax inside
fences staying code.

**Needs Mac:** `xcodegen generate` (1 new source + 7 new test files —
re-verify `aps-environment`/WeatherKit/widget-HealthKit per the #44/#48
strip trap), CLI build + full test run (Swift Testing: grep "Test run with
N tests passed"), then device: stream a reply mixing headings, nested
lists, a table, a quote, and a swift code block; confirm Deep Field code
blocks still read correctly and Paper Tape (light) keeps token colors
legible; confirm table horizontal scroll inside bubbles.

## 94. ✅ Pairing hardening — pair() already redeems before clearing the old record (no ordering bug found)

> **Audit 2026-07-13:** Independently re-verified, refutation attempted and failed. `Talaria/Stores/PairingStore.swift` (HEAD `cca1345`) redeems the new code FIRST (`try await pairingService.redeemPairingCode(...)`, lines 84-87) and only clears/saves afterward (lines 95-99), all inside the same `do` block — a throw from redeem (network/relay failure) jumps straight to `catch` (line 107) and never reaches the clear/save code. This is exactly the "redeem FIRST, then clear+save atomically" fix shape the item proposes as still-needed. `git blame` traces lines 63-111 to commit `9964f02` (2026-07-10 14:58:15 -0500), the shallow-clone boundary commit — and critically, `git show 560b560:Talaria/Stores/PairingStore.swift` (560b560 is the exact commit, 2026-07-11 12:59:24 -0500, whose diff added item #94's text to OPEN_ITEMS.md) shows the SAME already-correct ordering. So the item's factual claim was wrong at the moment it was authored, not merely stale later. Checked for alternate culprits and found none: `LivePairingService.redeemPairingCode` (Services/Live/LivePairingService.swift) is a pure network POST + response decode with zero local Keychain/UserDefaults mutation, so no clearing happens inside redeem either; the only production call site of `pair(using:)` is `ConnectHermesScreen.swift:338`, with no pre-clear wrapper. Item #46 (✅, "Verified on device 2026-07-05") independently corroborates that this same clear-after-redeem "clean slate on pair()" logic has been live since before #94 was even logged. Recommend closing; no code change required.

`PairingStore.pair()` calls `clearPairedRelayConfiguration()` BEFORE redeeming the new code (deliberate, for #3 stale-identity protection) — so a pair attempt that fails midway destroys the existing pairing and saves nothing. This is the likely mechanism behind the 2026-07-10 "total wipe" (a failed PAIR DEVICE tap during the frozen/wedged chaos): defaults copy + keychain mirror both gone, nothing for #41 rehydration to restore. Fix shape: redeem FIRST, then clear+save atomically (preserving the stale-identity wipe semantics on SUCCESS only). Small, low-urgency — recoverable by one re-pair — but it converts a transient network/relay failure into credential loss.

Logged 2026-07-11.

## 95. ✅ WATCH — credential-staleness fix set, verify across future reboots

> **CLOSED — header flipped 2026-08-01 (Hermes audit Part 1A).** WATCH silent across three weeks and multiple reboots — closed by time, per the audit's recommendation.

The 2026-07-10/11 "random unpair" saga resolved into three fixed defects + one edge (#94): BGTask handler isolation trap (PR #67), keychain `WhenUnlocked` accessibility (PR #68), voice restart race/lockup (PR #68), pre-first-unlock zombie-process staleness (PR #69 — reload on `protectedDataDidBecomeAvailable` + `didBecomeActive`, gates on `isProtectedDataAvailable`). Verified 2026-07-11: reboot → unlock → open app WITHOUT force-quit → pairing + API key + relay URL all present. Watch the next several organic reboots (and the next Apple seed) for any recurrence; if credentials ever vanish again, pull the launch story via the protected-data log lines before touching anything.

Logged 2026-07-11.

## 96. ✅ In-app conversation search (Lane F)

Both ChatGPT iOS and Claude iOS ship a first-class in-app search over prior chats; Talaria has only opt-in Spotlight indexing (#66) and the local-brain search tool. Add a search screen over the local `ConversationJournal` (now primary per #93) plus fetched Hermes sessions. Spec: `dispatch/FABLE-LANE-F-conversation-management.md`. Sourced from the 2026-07-11 feature gap analysis (table-stakes gap, both competitors confirmed).

**RESOLVED 2026-07-12: PR #77 merged.** Sim 483/483 (39 suites), device-verified on whoGoesThere — local body-text hit, server title hit, "—" for missing fields all pass. Regen commit carried aps-environment/WeatherKit/app-group entitlements intact.

Logged 2026-07-11.

## 97. ✅ Pin / archive conversations (Lane F)

Baseline list hygiene present in both competitor apps (ChatGPT's pin confirmed with a 3-pin cap on all tiers — ours deliberately uncapped; archive confirmed in ChatGPT, Claude iOS parity unconfirmed). Journal metadata + local overlay for server sessions, pinned section + archived filter in the drawer. Same lane/spec as #96.

**RESOLVED 2026-07-12: PR #77 merged (same PR as #96).** Device-verified: pin float + no cap, archive hide + ARCHIVED filter, relaunch persistence, swipe + long-press, drawer-reopen resets the archived filter (the onAppear concern didn't bite), ScrollView→List row-spacing parity confirmed by eyeball.

Logged 2026-07-11.

## 98. ✅ Scheduled / recurring agent runs — relay-side v0 (Lane G) — DEPLOYED to OJAMD 2026-07-12

**Update 2026-07-12 — DEPLOYED to OJAMD (verified live).** Second deploy pass done from the Windows side: `git fetch t27` + rebased `ojamd-deploy` onto `t27/main` (clean, ahead 1 local helper commit / behind 0), `tzdata` satisfied in the relay `.venv` (uv-managed; `ZoneInfo('America/Chicago')` resolves on the box — the Windows no-system-IANA-db gap is closed), relay restarted (elevated `Restart-Service HermesMobileRelay`, fresh PID) then the connector re-launched in dependency order. Live confirmation: `/v1/schedules` now answers **401** (was **404** pre-deploy) → the Lane G routes are registered and correctly device-bearer-gated; `/v1/health` 200; connector WS `/v1/hosts/ws [accepted]`. Left `SCHEDULER_ENABLED` at its default (on). Honest caveat: the trigger loop starts with the app lifespan and logs nothing at idle, so the *loop's execution* is presumed-live until the first real schedule fires — the route surface and auth are proven, a fired run is the last rubber stamp.

**Update 2026-07-12: PR #76 merged** (117/117 relay tests on the conflict-resolved merge with main). Remaining: the second, smaller OJAMD deploy — `git fetch t27` + rebase `ojamd-deploy`, **`pip install -e .` in the relay venv (new `tzdata` dep)**, then `Restart-Service HermesMobileRelay`. Nothing fires until then; `SCHEDULER_ENABLED=false` is the kill switch for a cautious first restart.

Both competitors run scheduled/monitoring agent tasks with push delivery (ChatGPT Scheduled Tasks replaced Pulse 2026-06-17, confirmed on the mobile app; Claude Cowork scheduled tasks). The relay already watches runs and pushes on completion (#38) — Lane G adds a `schedules` table, authed CRUD, and an asyncio trigger loop that starts Hermes runs through the existing gateway path. Python only, zero Swift contact, hourly floor, additive migration (prod DB is live). iOS management UI deferred to a later lane. Spec: `dispatch/FABLE-LANE-G-scheduled-runs.md`.

**Update 2026-07-12 (cloud session, branch `claude/t27-lane-g-kc07qu`): built, tested, PR'd.**
Everything lives in `relay/` — zero Swift contact as speced. What shipped:
- **Schema:** `schedules` table (prompt, `session_strategy` "fresh", kind
  once/interval/daily/weekly + per-kind fields, tz-aware daily/weekly via zoneinfo,
  enabled, last_run_at, last_run_session_id, next_run_at) + index — created additively/
  idempotently on boot (create_all + `CREATE INDEX IF NOT EXISTS`); migration test boots
  the new code over a pre-Lane-G DB file and existing rows survive. Prod DB needs zero
  manual steps.
- **CRUD:** `/v1/schedules` create/list/get/patch/pause/resume/delete, device-bearer auth
  (same as `/v1/push/watch`). Validation: sub-hourly → 422 (floor 60 min), past one-shot →
  400, unknown IANA tz → 422, cross-kind fields → 422; create 503s when GATEWAY_API_KEY
  is unset (a schedule that can never fire is a config error). Resume re-anchors from now
  (no stale catch-up); resuming an expired one-shot → 409.
- **Trigger loop:** asyncio task in the app lifespan (60s tick, `SCHEDULER_ENABLED` kill
  switch, `SCHEDULER_TICK_SECONDS`). Fire = fresh gateway session (`POST /api/sessions`) →
  `/chat/stream` with the prompt, disconnect on first SSE event (the #38-verified detach:
  runs complete server-side post-disconnect) → register the session with the EXISTING
  watch → completion-push machinery (no new delivery code; e2e test asserts the APNs alert
  with `session_id` + `HERMES_RUN_COMPLETED` category rides through). Missed-run policy:
  ≤ one catch-up if miss < one period, else skip forward (once = 60-min window, then marked
  missed/disabled); in-flight guard skips the tick while the previous run's watch is live;
  transient gateway failure leaves the row due for next-tick retry. Fires/skips audited
  (`schedule.fire`/`schedule.skip_forward`, actor `relay`).
- **Tests:** 28 new in `relay/tests/test_scheduler.py` — fake clock throughout, fake sleep
  for the loop (no real sleeps pace anything); full relay suite **117 passed**. Gateway
  additions (`create_session`, `start_detached_run`) are surgical on `gateway.py` and
  MockTransport-covered.
- **Contract doc:** `relay/docs/SCHEDULED_RUNS.md` — endpoints, recurrence grammar, and
  loop semantics for the future iOS management-UI lane.
- **OPS for the combined deploy (below):** `pyproject.toml` gained `tzdata` (Windows has no
  system IANA db — daily/weekly tz math needs it), so the OJAMD deploy pass must re-run
  the relay's `pip install` (`pip install -e .` in the relay venv) before
  `Restart-Service HermesMobileRelay`. v0 schedule management is device-bearer curl
  (grammar + examples in the doc); nothing fires until `GATEWAY_API_KEY` is set (already
  live on OJAMD per #38).

**Deploy plan (REVISED 2026-07-11, see #103):** pulled FORWARD — do the OJAMD rebase + connector restart NOW (sensor delivery is down in prod, #103), don't wait for Lane G. When G later merges it rides a second, smaller deploy. Original combined plan: one OJAMD deploy event — `git fetch t27` + rebase `ojamd-deploy` onto `t27/main` (picks up #87 connector UTF-8 fix and Lane G together), fix #88 (`restart-relay.ps1` → `Restart-Service HermesMobileRelay`) in the same pass, restart connector via `start-connector.bat` + `Restart-Service HermesMobileRelay`, then verify #54 closure (connector reattach, no 4401) post-restart.

Logged 2026-07-11.

## 100. ✅ Inline charts / data viz — BOTH PRs MERGED (#108 + #109); device-verified 2026-07-20 (Path B toggle + fullscreen, real HealthKit data)

**Device pass 2026-07-20 (Session C sweep, second attempt): PASS — CLOSED.** Real-data table
(avg daily steps, 7 days, numbers-only prompt) → chart toggle surfaced → fullscreen in/out →
toggle round-trip back to the markdown table. Confirms the earlier inconclusive attempt was
eligibility (units in cells), not a defect. Residuals redirected, not dropped: the VoiceOver
label check and the Midnight Marquee contrast spot-check ride the P-2 accessibility lane
(which names ChartCanvas explicitly). Follow-up candidate stays open for Owen’s call: tolerant
`numericCell` (strip units/%%/currency) so agent tables qualify without prompt discipline.

**Session C sweep 2026-07-20: attempt INCONCLUSIVE — eligibility, not a defect (probably).**
Owen asked the agent for a numeric table; a markdown table rendered but no chart toggle.
Source-read of the gate (`ChartSpec.promoted`, ChartSpec.swift:183): toggle requires ≥2
columns (≤8 series), 2–500 rows, rectangular, and EVERY cell after column 1 parsing as a pure
finite number — any unit suffix (“72 bpm”), “%”, “$”, dash, or empty cell anywhere returns
nil and the table silently stays plain. Agent tables love units, so this is the likely miss.
Retry with: “Give me a markdown table of X — first column the label, remaining columns numbers
only, no units or symbols.” **Follow-up candidate (Owen’s call):** tolerant `numericCell` —
strip common unit suffixes / %% / currency before parsing (small, pure, testable) so
real-world agent tables qualify.

> **MERGED 2026-07-17 — PR #108 (`9e8ac4c`, model+parser) + PR #109 (`5c79d62`, render surface).**
> Loop merged main into each branch BEFORE the regen, so the tested tree == merged main tree (tree
> SHAs verified identical `08ad358` on PR 2). Suites: **741/61** after PR 1 (+46 from the chart
> tolerance + streaming suites), **744/61** after PR 2. New baseline: **744 tests / 61 suites**.
> Built to spec and past it: `.chart(id:spec:source:)` retains the original fence body (so
> degradation and copy keep the raw data); `ChartSpec.decode` returns nil — never throws — on
> malformed JSON / unknown type / ragged series / over-budget (8 series × 500 points) **and** on
> non-finite values (Fable's own NaN/Inf guard, not specced). Streaming constraint honored: `.chart`
> is emitted ONLY from the closed-fence branch; an unterminated fence mid-stream stays a
> `.codeBlock`. Zero hardcoded colors — every axis/series color resolves through `Design.Colors`
> → `ThemeRuntime.palette`. PR 2 also landed the **Path B numeric-table chart toggle** (optional in
> the dispatch).
> → **Device pass owed:** ask Hermes for a ```chart fence of recent resting HR (sensor data is
> already flowing to the host); confirm it renders themed, tap → fullscreen, VoiceOver reads the
> label; confirm a malformed fence degrades to a code block rather than vanishing; check a numeric
> table offers the chart toggle. Verify under a non-default theme (Midnight Marquee) too.
> **Device check 2026-07-17: app surface PASS (with comedy)** — the OJAMD agent's health tool
> returned no steps, so it produced a TEMPLATE markdown table instead … which the app dutifully
> offered the chart toggle on. Surface works end-to-end; the empty host-side health-tool result is
> a Hermes-side data question (noted for Owen, not an app item). Mac-host attempt failed at the
> model level, same data issue.
> → **DECIDED 2026-07-17 (Owen): Path B only.** The numeric-table chart toggle is the contract —
> no prompt addition, no Hermes-side config, no added complexity. The ```chart fence parser stays
> merged and dormant; if a fence ever arrives it renders, but nothing teaches the model to emit
> one. Revisit only if Path B proves insufficient on device.

> **Dispatch spec 2026-07-16:** `dispatch/FABLE-T27-100-inline-charts.md` — **READY TO SEND.**
> Two stacked PRs: PR 1 = `ChartSpec` + `MarkdownSegment.chart` + parser (pure, cloud-testable);
> PR 2 = themed Swift Charts render surface. Seam verified at HEAD: `MarkdownSegment` already
> parses `.table` into header/alignments/rows and `MarkdownContentView` already switches on it —
> one enum case, one switch arm, no forked parser. Hard constraint written into the spec:
> `parseMarkdownSegments(content, isStreaming:)` re-runs per SSE delta, so a chart fence is
> malformed JSON for most of its onscreen life — charts materialize only on a closed, decoding
> fence; every failure path degrades to the original code block. **Owen's open call (in the
> spec, deliberately unanswered):** nothing tells the model the ```chart contract exists —
> system-prompt addition, app-side numeric-table promotion, or both. The app surface is built so
> either path lights it up.

> **Audit 2026-07-13:** Item #92's own note ('Device pass 2026-07-11: PASS ... Unblocks #100') confirms #92 already flipped fully verified on the same date this item's header claims. The body sentence 'Lane B — merged, awaiting device verify... queue until #92 flips ✅' is now stale and contradicts this item's own header — strike the 'awaiting device verify' clause; #100 itself remains correctly undispatched (no chart/data-viz PR in PR_INDEX.md).

Both competitors render charts inline; pairs naturally with Talaria's health/sensor and cost telemetry. Detect chart/table specs in Hermes output and render native Swift Charts. Depends on the markdown/code rendering pipeline (#92, Lane B — merged, awaiting device verify) as the detection/rendering substrate; queue until #92 flips ✅.

Logged 2026-07-11.

## 102. ✅ Local brain generation health — DEVICE-VERIFIED 2026-07-18 via #134 harness

> **DEVICE-VERIFIED 2026-07-18 (Owen's device, via the #134 forced-trip harness).** Forced trip → chat reply collapsed to ONE copy of the loop unit; switched to on-device, `deviceStatus` thermal **FAIR** (no overheat); post-trip normal send worked; live-SDK-hold mode repeated clean (abandoning an in-flight SDK generation did NOT wedge the next turn). The free-tier standalone runaway/overheat gate is CLOSED. Read-aloud (#110) cut-vs-drone confirmation tracked separately on #110.

> **Audit 2026-07-13:** Header emoji 🔍 (investigating) is stale and self-contradicts the item's own latest (2026-07-13) note, which describes a shipped, merged, unit-tested fix, not an open investigation. Independently re-verified: PR #83 (`claude/lane-h-setup-bmi058` → main) is closed/Merged=YES per PR_INDEX.md, titled "Lane H — local brain generation health (#102 #61)"; merge commit `23387b7` and implementation commit `c2de665` ("#102: bound + retune chat generation; hysteresis tail-repetition breaker") both present in MAIN_LOG.txt, and `c2de665` is literally the last commit touching `Talaria/Services/Live/LocalChatBackend.swift` in the current tree. `chatGenerationOptions(for:)` is defined at LocalChatBackend.swift:76 and called at lines 280/370 exactly as described; the hysteresis tail-repetition breaker (`RepetitionBreaker.shouldAbandon`, `TailRepetitionRun`, `degenerateTailRepetitionRun`) is present at lines ~800-925, with a matching bank of `@Test` cases in `TalariaTests/LocalChatBackendTests.swift` (tailRepetition*/breaker* tests). The claimed Mac-loop compile fix is corroborated by commit `ef5e89d` ("hoist mutating shouldAbandon calls out of #expect"), which sits directly between the spec-dispatch and implementation commits. Follow-up docs commits `578e5ca`/`63284e9` match the device-pass narrative, and both spun-off items #110 and #111 exist in the file. However, per the "merged != device-verified" rule, this is NOT done: the note's own words are "Device pass 2026-07-12 (partial)" and "STILL OWED (organic): #67-style session — loop should self-terminate..., thermal recover, log shows the breaker line; then SEND ANOTHER MESSAGE after a trip" plus "D3 (post-trip send probe) stays conditionally owed." The deterministic repro was defeated by the model's own guardrails, so the breaker's actual on-device trip has never been observed — only synthetic unit tests and a thermal-only partial pass exist. 🔍 is also the only use of that emoji anywhere in OPEN_ITEMS.md, while comparable "MERGED, verification pending" items in this file (e.g. #61) use 🔧, not 🔍 — reinforcing that the header was simply never revisited after the merge landed. Recommend downgrading to 🔧 and updating the title to name the MERGED state and the specific organic-trigger device-verification still owed; do not mark ✅.

Device pass 2026-07-11, observed during the #67 session (which otherwise mostly passed): (a) the on-device brain repeats a certain phrase while in use; (b) `deviceStatus` reported thermal state "serious," attributed to running apps, with only Talaria running. Investigate TOGETHER — a repetition/generation loop that keeps the ANE/GPU spinning would explain both. Check: generation stop conditions / max-token bounds in `LocalChatBackend`, whether the loop persists across sessions, and thermal recovery after force-quit. If repetition is plain small-model sampling degeneracy, thermal may still warrant a mitigation (throttle sustained inference or surface a thermal notice). Possibly related: #61's repeated title/preview text (same model, same session).

**MERGED 2026-07-13 (Lane H, PR #83) — 570/570 green (49 suites).** Explicit `GenerationOptions` on both send paths (nucleus 0.9 / temp 0.7 / cap = tier headroom: 1024 on-device, 4096 PCC — the probe confirmed no implicit cap exists when unset), plus a tail-repetition breaker with arm/disarm/escalate hysteresis; on a trip the looped tail collapses to ONE copy and the session is invalidated so rebuilt transcripts can't re-prime the loop (deliberate deviation from the spec's "keep what's emitted", documented in the PR). Mac loop caught one compile issue (mutating `shouldAbandon` inside `#expect` — receiver captured immutably; calls hoisted). **Device pass 2026-07-12 (partial):** the deterministic breaker trigger ("repeat X 25 times") is DEFEATED by the base model's own guardrails — it refuses verbatim-repetition requests, and also declines long-form ("1500-word story") citing its own limits. Consequence: the breaker is organic-only on device (28 unit tests carry the algorithm), and the PR's accepted residual about requested repeats truncating is moot in practice. Ten rapid generations ran warm-but-recovering with the explicit caps live on every turn — the #102 thermal outcome achieved. D3 (post-trip send probe) stays conditionally owed, only testable if an organic trip ever occurs. Same session surfaced the PCC availability-check session churn → #111. STILL OWED (organic): #67-style session — loop should self-terminate (~12 copies), thermal recover, log shows the breaker line; then SEND ANOTHER MESSAGE after a trip — if it fails "still working", stream abandonment doesn't cancel SDK-side generation → follow-up needed. Speech-queue interaction spun off as #110.

**Localized 2026-07-11, CORRECTED on second read (Owen challenged, rightly):** the live call `liveSession.streamResponse(to:)` passes NO options — SDK defaults govern; line 597's `GenerationOptions()` is cosmetic (transcript rehydration), not the mechanism. `streamDelta` prefix-guard and the single-shot condense-retry loop both verified safe — runaway regeneration RULED OUT. Best fit remains model-level repetition under default sampling with nothing bounding response length. Fix unchanged (explicit options + cap + tail-repetition breaker); Lane H spec corrected so Fable doesn't chase the red herring. Spec: `dispatch/FABLE-LANE-H-local-brain-gen-health.md`.

Logged 2026-07-11.

## 103. ✅ Health sensor delivery DOWN in prod — RESOLVED 2026-07-11 (connector dead 9 days, #87 defect)

**Post-mortem (OJAMD session 2026-07-11):** connector.log shows the connector died 2026-07-02 18:45 in a `UnicodeDecodeError: charmap codec` loop — #87's exact defect — and never came back; the deploy repo was 107 commits behind, so the #87 fix never reached the box (see correction in #87). Remedy applied: rebased `ojamd-deploy` onto `t27/main` (c073baa+1), started ONE connector via `start-connector.bat` (single-instance enforcer verified in the script), WS attach to relay confirmed via `Get-NetTCPConnection`. Device confirmed: 2,000 pending → 0, actively draining, phone cooled significantly (empirical support for #104's persistence-amplification mechanism). Diagnostic notes for posterity: `hermes-mobile-mcp.exe` processes are MCP children of Hermes hosts, NOT connector instances; nssm-wrapper PIDs won't match port owners (LocalSystem children own the ports, cmdlines hidden from unelevated shells); HermesGateway now runs as a user pythonw process (`hermes gateway run`), not an NSSM service.

Observed on device 2026-07-11: health uploads constantly failing, ~2,000 pending samples. Localized 2026-07-11 (source + live probe from Mac): relay `:8000` is UP (`/v1/health` ok) and the app-side outbox machinery is correct (#24a chunking/poison-isolation intact) — but `forward_sensor_payload` maps EVERY connector-side failure (no session, busy, send exception, ack timeout) to 202 "retry," so a dead or wedged connector reads as an endless retry loop on device. Chat unaffected (gateway `:8642` is a separate service). Prime suspect: connector process down or wedged — possibly the #87 UTF-8 crash (fix merged, NEVER deployed to OJAMD). Remedy = the #98 deploy plan pulled forward: rebase `ojamd-deploy` onto `t27/main`, restart connector (`start-connector.bat`), watch the backlog drain on the device diagnostics panel. Thermal note (CORRECTED 2026-07-11 after actual investigation, prompted by Owen): the retry POSTs are modest, BUT `persistOutboxState()` rewrites the ENTIRE outbox to UserDefaults on EVERY sensor tick (location/motion/health), on the main actor — at 2k samples that's a sustained encode/write loop whose cost scales with backlog size. Compounding feedback: connector down → backlog grows → every event costs more. A genuine thermal contributor alongside #102's generation issue, and it makes this deploy doubly urgent — draining the backlog collapses the cost immediately. App-side hardening tracked as #104.

Logged 2026-07-11.

## 104. ✅ Sensor outbox persistence churn — full rewrite on every tick, main actor, unbounded backlog

> **CLOSED — header flipped 2026-08-01 (Hermes audit Part 1A).** PR #85 merged; the DRAINING follow-up it waited on is #117's PR #103, merged.

> **MERGED 2026-07-13 as PR #85 (`93e0222`)** + xcodegen registration `e903cb2` — discovered 2026-07-16 via the same dead-dispatch incident as #110. **Follow-up in flight (2026-07-16):** Fable, re-reviewing against this spec, found a real bug in the DRAINING path and is building the fix now — PR expected; loop it on arrival. Device verify owed for both.

> **Dispatch spec 2026-07-13 (eve):** `dispatch/FABLE-T27-104-sensor-outbox-churn.md` — cloud-safe, unit-test-gated (debounce+flush / backlog cap / off-main encode). Ready to send to CC.

Found 2026-07-11 while investigating #103's thermal contribution: `SensorUploadService.persistOutboxState()` (backed by `UserDefaultsAppPersistenceStore.saveSensorOutboxState`) encodes and rewrites the WHOLE outbox on every location update, motion activity change, and health snapshot — in `@MainActor` tasks. Cost scales linearly with backlog size and there is no backlog cap, so any connector outage (like #103) turns routine sensor ticks into a sustained CPU/IO loop (heat + potential UI jank). Hardening shape: (a) debounce/coalesce persistence (e.g. persist at most every few seconds or on chunk boundaries — crash-loss window of a few seconds of sensor samples is acceptable), (b) cap `pendingHealthSamples` with oldest-drop + an honest diagnostics note when capped, (c) move the encode off the main actor. Small, file-scoped to `SensorUploadService.swift` + the persistence store; no collision with Lanes D/F/G/H. UN-GATED 2026-07-11: #103's deploy drained 2k→0 cleanly and the device cooled as the backlog fell — current semantics proven, mechanism empirically supported. Dispatchable as its own small lane whenever desired.

**Partial device-verify evidence 2026-07-17 (log review, Owen's device).** A drain absorbed a
concurrent capture mid-flight, correctly:

```
drain: starting. Outbox: loc=false, health=1
captureHealth: got 2 samples — distance_walking, steps
drain: health chunk (1 of 3 pending) → delivered
drain: health chunk (2 of 2 pending) → retry
drain: connector busy — retrying chunk in 2.000000s (attempt 1/3)
drain: health chunk (2 of 2 pending) → delivered
drain: finished. Outbox remaining: loc=false, health=0
```

The loop re-reads `outboxState.pendingHealthSamples` each pass, so mid-flight growth cost
nothing: 1-sample chunk delivered → prefix removed → next pass formed a 2-sample chunk →
busy-retry ladder → delivered → outbox to 0. **Does NOT close the device-verify DoD** — this
exercised neither the backlog cap nor the debounce under a real outage — but the drain path's
behaviour under concurrent mutation is now positively observed.

**Read the chunk log carefully — it has already misled one reviewer (2026-07-17):**
`drain: health chunk (\(chunk.count) of \(pendingHealthSamples.count) pending)` — the FIRST
number is the chunk SIZE, not a chunk index, and the denominator is evaluated AFTER the
`await`, so it reports a later instant than the numerator. `(1 of 3)` → `(2 of 2)` is therefore
correct and NOT a shrinking denominator. Worth rewording if anyone touches that line.

Logged 2026-07-11.

---

## 105. ✅ OJAMD startup-layer hygiene — stale relay launcher retired (NSSM-only at boot)

**Fixed 2026-07-12.** During the pre-Mac OJAMD health pass, found a live conflict armed for the
next login: `Hermes_Relay.cmd` still sat in the Startup folder
(`%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup`), and its single-instance
enforcer kills any process matching `*uvicorn*app.main*8000*` before launching its own uvicorn.
But the relay is NSSM-owned now (`HermesMobileRelay`, LocalSystem) — so at next login this script
would either die on the bind (benign) or win the port race and leave the relay running in the
login session (dies at logoff), NSSM crash-looping behind it. This is #55's competing-launch-layers
problem in mirror image. **Action taken:** moved `Hermes_Relay.cmd` out of Startup to
`C:\Users\Owen\.hermes\scripts\retired\Hermes_Relay.cmd.retired-20260712` (reversible). The
`Hermes_Connector.cmd` and `Hermes_Gateway.vbs` Startup entries are **legitimately retained** —
the connector is a plain bat-launched process and the gateway runs as Owen's user `pythonw` (per
the corrected topology), neither is a service, so both still need login-launch.

**Unattended-reboot gap (accepted, not fixed).** AutoAdminLogon is off and the gateway + connector
only start at login, so a reboot while unattended leaves chat dead + reproduces the #103/#104 shape
(relay up, connector down, phone in 202-retry with outbox-persistence amplification). **Owen's
policy (2026-07-12):** Windows + Hermes updates are paused and reboots are done attended (in front
of the screen), which sidesteps the gap without auto-login's security trade-off or resurrecting the
boot-trigger scar tissue. No boot-survival change needed for gateway/connector while this holds.

Logged 2026-07-12.

## 106. ✅ P8 IR v0 — constrained generative UI rung MERGED + device-verified (Lane D, PR #65)

Landed 2026-07-12 (merge 2545eff). The model-never-emits-UI-code rung: `@Generable` IR schema (depth-bounded by construction, not recursion), tolerant `GenUIDecoder` (JSONSerialization walk, unknown/malformed nodes skip-and-log, siblings survive), `sanitized()` ingestion funnel, hardcoded renderer mapping IR onto shipped HUD components, DEBUG-only Developer-screen harness. No model wiring, no ChatScreen contact — buttons stage prompts, v0 sends nothing. Mac review-loop caught 2 cloud-code failures (both fixed in 4a5582a): the NSNumber Int→Bool bridging trap in the decoder's bool reader (`1 as? Bool` succeeds — strict CFBoolean check now enforced; add to the wrong-Xcode-smell tier of gotchas: JSONSerialization + `as? Bool` is never wrong-type-safe), and an under-framed ImageRenderer test fixture (zero-height view → nil image by design). Device-verified on whoGoesThere 2026-07-12: all three harness sections healthy (Swift-built tree, on-device JSON decode, mangled-JSON survivors), staged-only readout confirmed. NOTE: this install replaced whoGoesThere's c9e909e wedge-instrumented build — rebuild #84 branch before the next-seed voice retest. Numbering note: the branch's docs commit claimed #92 (parallel-collision with Lane B markdown); resolved to main's file, entry re-registered here as #106. NEXT RUNGS un-gated: #99 in-app preview surface (spec being revised on the landed IR), then P8 model wiring as its own future lane.

Logged 2026-07-12.

---

## 107. ✅ T6 Phase 1+2 — Mac Mini backend EXECUTED + reboot-verified; Shelley send from Talaria chat VERIFIED 2026-07-20 — CLOSED

**Device pass 2026-07-20 (Session D launch sweep): PASS — CLOSED.** Agent-composed iMessage
sent from Talaria chat, delivered to Shelley, READ RECEIPT 9:53 PM (screenshot on file — the
agent signed off with “Have a pleasant circadian cycle”). Sender of record is imsg per the
Phase-2 verdict; the message body’s “sending this via BlueBubbles” self-description is the
agent’s own flavor text, not the plumbing. First full end-to-end proof of the T6 pipeline in
the wild. Also closes the #114 residual (note added there).

> **Reboot test PASS (2026-07-16, Owen at the screen):** relay, connector, gateway, and shim all
> recovered at login (LaunchAgents); APNs came up clean on its first post-.p8 boot (zero
> key-not-found lines); connector reattached in ~2 min; phone→Mac chat round-trip worked with no
> hands on the Mac. Findings: (a) **recovery is login-gated** — auto-login and
> `pmset autorestart` are both OFF, so an unattended power event parks the stack at the login
> screen until someone logs in; enabling both is Owen's posture call, documented not decided.
> (b) **BlueBubbles was the sole casualty**: its login start hung silently in "pre-start checks"
> (BB-internal flake — identical signature in its log from Jul 5; ruled out: architecture and
> TCC, since the binary held chat.db handles while hung). Cure: `pkill -9 -f BlueBubbles` +
> fresh launch → "Successfully started HTTP server"; the gateway's 300s-backoff retry then
> self-attached ("✓ bluebubbles reconnected successfully"). Incident bonus: BB migrated to the
> **native arm64 1.9.9 build** (Rosetta retired). Recommended BB settings, Owen's clicks:
> enable BB auto-start (method: launch-agent — their crash-persistence mode) so boot recovery
> stops depending on window restoration; note BB's headless quirk (instance logged headless
> despite config `headless|0` — the dashboard window may not exist when you go looking; the
> real log is `~/Library/Logs/bluebubbles-server/main.log`).

> **Executed 2026-07-14/15 (Claude Desktop session, main @ da24e4a).** Phase 1 on-box complete:
> relay LaunchAgent `org.aethyrion.talaria-relay` live on :8000 (venv py3.13), connector
> `ai.hermes.mobile.connector` running + attached, shim re-rendered onto this checkout,
> gateway persistence confirmed native (`ai.hermes.gateway`, RunAtLoad+KeepAlive).
> `verify-phase1.sh --restart-check`: 13 pass / 0 fail / 1 warn (warn = native gateway agent,
> expected). macOS suites: relay 117 passed, connector 105 passed (LaunchAgent test un-skipped).
> Findings: (a) first launchd boot took ~13 min — Gatekeeper/syspolicyd assessing venv .so files;
> one-time, restarts ~5s; the installer's 30s health poll reports a false failure — wait it out.
> (b) `pytest -q` doubles pyproject's `addopts=-q` and suppresses the summary — run bare `pytest`.
> (c) BB server password appeared once in a Claude transcript (webhook-list dump) — rotation
> recommended at Owen's convenience; BB is loopback-bound, low exposure.
>
> **Phase 2 (Apple connectors):** Q2 verdict — **`imsg` (brew, v0.13.0) is the sender of record**,
> invoked via terminal with full path; upstream deliberately ships no agent-callable send tool.
> **BlueBubbles = inbound/reader only**, adapter enabled credential-driven, gated
> (`require_mention: true`, `send_read_receipts: false`), reusing the pre-existing 2026-07-05
> webhook. **Photon evaluated & REJECTED** (managed cloud iMessage lines — wrong identity, no
> Mac session state; Owen: no adoption plans). iMessage **send ✅ + read ✅** verified agent-driven
> through the Sessions API (the exact app path). Notes: `memo` installed, **read ✅ + write ✅**
> verified agent-driven (write via AppleScript — memo's -a/-s flags are interactive-only; skill
> corrected). FindMy: UI automation abandoned (too fragile, Owen call) — pyicloud `play_sound()`
> is the documented adoption path if ever wanted (#114-adjacent, parked). TCC ledger: FDA granted
> to gateway python (uv cpython 3.11 — re-add if `hermes update` swaps the runtime) + Claude;
> Notes Automation + Accessibility granted; launchd Automation prompts DO surface with an active
> GUI session (run stalls at prompt, resumes on approval — better than the silent-denial trap).
> Skills hardened on-box: apple-messaging (confirm-before-send + single-writer rules),
> apple-notes (non-interactive corrections), findmy (parked banner).
> **Remaining:** .p8 → `~/.secrets/apns/` + relay kickstart; reboot test (Owen); dev-device
> pairing rides Part 2 (#114).

**Executes #34 (un-deferred by Owen 2026-07-12); enables #33's server-side connectors.**
Spec committed at `design/T6_MAC_BACKEND_SPEC.md` (v0.2, Q1–Q5 defaults recorded in §7);
runbook at `relay/docs/DEPLOY_MAC.md`. Definition of done: a dev build pointed at
`http://100.79.222.100:8000/v1` can pair, deliver sensors, bootstrap talk, receive a
run-completion push, and fetch a Tier-2 agent file — OJAMD untouched, phone's production
pairing unaffected.

**2026-07-12 (cloud, branch `claude/talaria-mac-backend-phase1-m0jkm0` → PR #79):** repo-side
scaffolding written — NOT yet executed on the Mini (no Mac access from the cloud session).
Numbering note: this entry was #105 in the original commit and became **#107** when the PR
branch rebased onto main (main had grown its own #105/#106 in parallel); all artifact
cross-references (spec, runbook, env template, scripts, CLAUDE.md) were renumbered with it:
- `relay/.env.mac.example` — Mac-shaped env template (mint fresh keys; `RELAY_ENVIRONMENT=production`
  so the `replace-me` startup guard enforces; absolute `DATABASE_URL`; absolute `APNS_KEY_PATH`
  — config does NOT expand `~`; `APNS_BUNDLE_ID=org.aethyrion.talaria27` verified against
  `project.yml`, NOT OJAMD's `org.aethyrion.talaria`; `GATEWAY_API_KEY` = the Mac's own
  `API_SERVER_KEY`).
- `scripts/mac/install-relay-launchd.sh` — `org.aethyrion.talaria-relay` LaunchAgent
  (RunAtLoad/KeepAlive, logs `~/Library/Logs/talaria-relay/`), preflights env, polls `/v1/health`.
- `scripts/mac/install-shim-launchd.sh` — re-renders `com.aethyrion.talaria.modelsshim`
  against THIS checkout (the committed plist still points at the pre-fork
  `…/Documents/Claude/Talaria` path — stale-path trap found during scaffolding).
- `scripts/mac/install-gateway-launchd.sh` — fallback persistence for `hermes gateway run`
  (check native macOS persistence first; the `hermes gateway install` prohibition is
  Windows-specific; refuses to double-manage a gateway-shaped agent).
- `scripts/mac/verify-phase1.sh` — acceptance smoke: launchd state, health endpoints, Tier-2
  401-gate probe, .env hygiene; `--restart-check` bounces the relay and proves the connector
  reattaches via `state.json` `last_connected_at` (→ #54 annotation either way).
- Test baseline (cloud Linux, Python 3.11.15): relay **117 passed**; connector **104 passed,
  1 skipped** — the skip IS the macOS LaunchAgent test (`test_service_management.py`), so the
  Mac run should show 105/105. macOS counts to be recorded here.

**Mini execution checklist (next Mac session — runbook has the commands):**
- [ ] `main` pulled on the Mini; pinned commit recorded here; `hermes --version` OK
- [ ] Dirs + secrets: `~/Hermes/agent-work/MobileDL`, APNs `.p8` at `~/.secrets/apns/` (600)
- [ ] Relay venv + `.env` (fresh keys) + `install-relay-launchd.sh` → `/v1/health` OK; startup
      log shows APNs client (bundle `org.aethyrion.talaria27`) + gateway client initialized
- [ ] Connector: setup vs `http://127.0.0.1:8000/v1` (secret matching) → `validate-mcp` →
      `hermes-ios` skill copied (real copy) + `/reload-mcp` → `service install/start` →
      `status` running; sensor DB appears at `~/.hermes-mobile/sensors.db`
- [ ] Shim plist re-rendered against Talaria-27; gateway persistence confirmed (native or ours)
- [ ] Relay + connector suites green ON MACOS (record counts; expect connector 105/105)
- [ ] `verify-phase1.sh` all-pass; `--restart-check` pass → note on #54
- [ ] Mini reboot → all four services return unattended
- [ ] Device half: dev device/simulator paired to the Mac relay (physical phone STAYS on
      OJAMD — #91 one-pairing rule; Private Relay OFF per #24e); sensors
      `deliveryState=delivered` w/ #24a chunking; talk readiness OK; run-completion APNs
      (or documented dev-APNs limitation); authed Tier-2 `/v1/device/files` fetch 200
- [ ] Phase 2 (#33): imsg-vs-Photon evaluated + single-automated-sender rule decided (Q2);
      TCC granted against the launchd context (the LaunchAgent-TCC-identity trap — runbook
      Phase 2 step 2); ≥1 connector end-to-end from Talaria chat with confirm gate
- [ ] Optional accelerator: "Windows brain, Mac hands" (`hermes mcp serve` Mini → `hermes mcp
      add` OJAMD) if iMessage is wanted on the phone's production brain first

Logged 2026-07-12.

## 108. ✅ iPad support — universal foundation + native split view (Lane J)

> **CLOSED — header flipped 2026-08-01 (Hermes audit Part 1A).** Lane J PRs 1+2 merged. The iPad pass's failure was PAIRING, not Lane J; multi-window lives at #109.

> **iPad pass 2026-07-13 (eve): NOT a Lane J defect.** The M3 iPad ran the local brain (on-device AI, no network) but could NOT switch to Hermes. Root cause: pairing configures the RELAY plane, but the Hermes switch is gated on `isHermesConfigured` — the Sessions-API key, a separate plane the pairing QR doesn't carry — so the picker offered Hermes yet the switch silently stayed on-device. Fix: enter the API key on the iPad (Settings → Uplink), plus a UX nudge on `claude/t27-hermes-switch-nudge` (ef5dbd9) that surfaces 'paired — add your key in Uplink' instead of a silent lock. Lane J UI matrix (resize / keyboard / Stage Manager / column transparency) still owed.

> **Audit 2026-07-13:** PR #81 (Lane J PR 2 — NavigationSplitView) is confirmed MERGED and on main (RootLayoutPlan @ ContentView.swift:9, ConversationListPane @ SessionsDrawer.swift:312; PR_INDEX #81 Merged=YES; merge commit 3fd5554), consistent with this item's own 'MERGED 2026-07-12 ... PRs #80 + #81 landed on main' paragraph. The item's final paragraph ('PR 2 BUILT IN CLOUD ... not compiled') is stale wording left over from before the Mac merge — PR 2 has since merged and compiled. Header 🔧 is still correct on its own separate merits: iPad-side device verification (J-3 resize matrix, external keyboard sweep, mid-stream Stage Manager boundary crossing, column-transparency check on Shelley's iPad Air) remains genuinely outstanding per this item's own 'Remaining matrix items are iPad-side' line.

Spec: `dispatch/FABLE-LANE-J-ipad-support.md`. Target hardware: Shelley's iPad Air (M3) on iPadOS 27 beta (M3 = Apple Intelligence-capable — on-device brain fully live, not gated). Two PRs: PR 1 universal foundation (this branch, `claude/lane-j-ipad-support-uf1t39`), PR 2 NavigationSplitView (stacked).

**Update 2026-07-12 (cloud session): PR 1 BUILT IN CLOUD, not compiled or device-verified.**
- **J-1 was already satisfied on main:** `TARGETED_DEVICE_FAMILY "1,2"` (global base + widget target) and all-four iPad orientations (`INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad`) were in project.yml/pbxproj before this lane — verified, not changed. New `UniversalTargetInfoPlistTests` guards the built plist (UIDeviceFamily, orientation variants, scene manifest). DISCREPANCY for Owen: `settings.base` pins `IPHONEOS_DEPLOYMENT_TARGET: "26.0"` while `options.deploymentTarget` says 27.0 — the pbxproj carries **26.0**, so the dispatch's "nothing installs on iPadOS 26" assumption is wrong today. Left as-is (not this lane's call).
- **J-2 single window:** `SingleWindowPolicy` (AppEntry.swift) — `UIScene.willConnectNotification` observer destroys any second `.windowApplication` scene session; CarPlay (`CPTemplateApplicationScene`) passes untouched; deliberately NOT via `configurationForConnecting` (stays out of SwiftUI scene attachment + manifest CarPlay resolution). True multi-window = #109.
- **J-3 measure cap:** `Design.Layout.chatMeasureMaxWidth` (700pt) on transcript column, composer card, chat banners — unconditional `.frame(maxWidth:)`, no size-class branch, no-op at all compact widths (parity locked by `ChatMeasureCapTests`). Attachment sheet gets `.presentationSizing(.form.fitted(horizontal:false, vertical:true))` for regular-width form-sheet sanity. Lane E atmosphere audited: zero `UIScreen.main`/cached bounds — every texture draws from live Canvas/Geometry size; fixed particle counts (embers 22, starfield 56/104) just read sparser at 13" — cosmetic, left alone.
- **J-4 shortcuts:** `Core/KeyboardShortcuts.swift` table (⌘N new-chat via clear-confirm, ⌘K → Lane F ConversationSearchScreen presented from ChatScreen with the same drawer model/selection seam, ⌘, settings, ⌘1…⌘9 drawer-order jump reusing `SessionsDrawerModel.grouped`), hidden bridge buttons on ChatScreen, Return-sends/⇧Return-newline via `onKeyPress` on the composer TextEditor (hardware-only), Esc (.cancelAction) on drawer/search/settings/models/select-text/attachment-picker closes. Voice overlay deliberately excluded from Esc (live mic session).
- **J-5:** `.hoverEffect(.highlight)` on shared button components + rows/chips/cards/gauge.
- **J-6 sensor reality (report, no code):** probes already honest — `HKHealthStore.isHealthDataAvailable()` (LiveHealthService:49), `CMMotionActivityManager.isActivityAvailable()` (LiveMotionService:59/77/118) → `.unsupported`, no fake readings; #104 sensor outbox untouched by this lane.

**Needs Mac:** `xcodegen generate` (2 new files: `Talaria/Core/KeyboardShortcuts.swift`, `TalariaTests/IPadAdaptationTests.swift`) → verify aps-environment/WeatherKit/app-group entitlements survive regen (#44/#48 trap; CarPlay key stays commented) → CLI build for an iPad destination + full test run → J-3 resize matrix on an iPad Air 13" (M3) iPadOS 27 sim (full screen both orientations, Split View 1/2 + 1/3, Slide Over, Stage Manager free resize; Deep Field + one Lane E complex theme; Dynamic Type spot check). Compile-risk shortlist (cloud-unverifiable): `presentationSizing(.form.fitted…)` shape, `onKeyPress(keys:phases:)` overload + whether it intercepts Return on a focused TextEditor on the iOS 27 SDK (fallback: UIKeyCommand bridge with wantsPriorityOverSystemBehavior), `KeyEquivalent` Equatable synthesis in `Spec`, built-plist key spellings in `UniversalTargetInfoPlistTests` (`UIDeviceFamily`, `UISupportedInterfaceOrientations~iphone` variant), SwiftUI honoring the app-delegate-registered willConnect refusal timing on iPadOS 27. Device pass per dispatch checklist (external keyboard sweep, pointer hover, atmosphere perf, sensor honest states).

**MERGED 2026-07-12 (Mac review-then-build loop): PRs #80 + #81 landed on main; 542/542 tests green (49 suites, iPhone 17 Pro Max iOS 27 sim). Lane K (#82, 14 gallery app icons) merged in the same train — all 18 alternates + previews verified flat in the built bundle.** The Mac loop caught three cloud-unverifiable issues, all from the PR's own compile-risk shortlists:
- **Swift 6 region isolation (PR 1):** the block-based `addObserver` hands the Notification to a @Sendable closure, making it task-isolated and unsendable into `MainActor.assumeIsolated` — `SingleWindowPolicy` rewritten selector-based (plain @objc method parameter has no such isolation; UIKit posts on main, hop is sound).
- **Orientation keys never landed (PR 1) — the plist tests found a REAL pre-existing gap:** `INFOPLIST_KEY_UISupportedInterfaceOrientations_*` build settings are IGNORED when a custom Info.plist is used (this project generates its plist from project.yml `info.properties`), so the built app had NO orientation keys at all — the "J-1 already satisfied on main" claim above was wrong (it verified the build setting, not the built plist). Fixed by moving orientations into `info.properties`. **Behavior change: iPhone is now genuinely portrait-locked for the first time** (previously OS-default rotation); iPad all four, matching long-declared intent.
- **`NavigationSplitViewVisibility.automatic` aliases `.detailOnly` on the iOS 27 SDK (PR 2)** (`.doubleColumn` on macOS — platform-dependent alias), so automatic-as-visible is unimplementable via equality; test replaced with an SDK-reality canary that asserts the alias so a future SDK change surfaces. App unaffected in steady state (onAppear imposes the persisted value).
Numbering: branch entries #107/#108 renumbered to #108/#109 (main grew T6 as #107 in parallel). **Device pass (iPhone) 2026-07-12: build installed and running on device — portrait lock confirmed live (the first real-world proof of the orientation fix), all 14 new gallery icons visible in the picker.** Remaining matrix items are iPad-side (Shelley's iPad Air): J-3 resize matrix, external keyboard sweep, mid-stream Stage Manager boundary crossing, column-transparency visual check. Previously: STILL OWED: the sim/device matrix above (J-3 resize matrix, external keyboard sweep, mid-stream Stage Manager boundary crossing, column-transparency visual check, icon visual pass on device).

**Update 2026-07-12 (same cloud session): PR 2 BUILT IN CLOUD on stacked branch `claude/t27-lane-j-pr2-splitview` (based on PR 1's branch), not compiled.**
- **J-8:** `RootLayoutPlan` decides by horizontal size class only — every non-regular width renders today's iPhone tree UNTOUCHED (explicit compact branch; parity beats purity, per dispatch); regular gets `NavigationSplitView` with `ConversationListPane` (extracted verbatim from the drawer panel — Lane F surfaces exist once) as sidebar + ChatScreen detail. Selection = `ChatStore.activeSessionID` (journal active-hop handle); rows write via `openSession`. Settings stays a sheet. Empty state = the real empty transcript (single-active-conversation model — no placeholder art surface exists to need).
- **J-9:** boundary-survival state (composer draft, staged attachments, sessions model) hoisted to MainTabView and passed into ChatScreen via explicit init; streaming lives in ChatStore (untouched by recreation); recreated transcript re-anchors to the tail. One atmosphere spans the window behind both columns (`showsAtmosphere: false` per-column + `containerBackground(.clear, for: .navigation)` — the single biggest compile/visual risk: if columns still paint system backgrounds on device, Deep Field reads black in the columns). Sidebar visibility persists via AppStorage; ⌘K in regular reveals the sidebar and focuses the inline filter (request/consume seam); hamburger + drawer overlay are compact-only.
- **Compile-risk shortlist (PR 2):** `containerBackground(_:for: .navigation)` existence/placement; `navigationSplitViewColumnWidth(min:ideal:max:)` shape; NavigationSplitView column transparency on iPadOS 27 generally; the onDisappear/onAppear polling flip across the size-class boundary (setPollingEnabled(false) then re-enable — watch for a stuck-off race in the sim).
- **Sim musts (dispatch J-9/J-10):** mid-STREAM Stage Manager resize across the boundary (highest-risk case), composer-text survival, voice overlay in both width classes, full J-3 matrix re-run.
- **Adversarial review pass (same session, agent-verified against definitions):** no compile failures beyond the documented risk lists; one REAL bug found and fixed — the persistent sidebar had no post-mutation refresh (all refresh paths were drawer-lifecycle-based), so the list + "● CURRENT" highlight went stale in regular width after a row switch / ⌘1-9 / New Chat. Fixed by refreshing after each mutating action (behavior-neutral in compact: one extra background fetch; the drawer refetches on open anyway). Row highlight deliberately stays server-sourced (`isActive`) for Lane F parity; `ChatStore.activeSessionID` is the observable local-selection surface (doc clarified).

Logged 2026-07-12.

## 110. ✅ Read-aloud retracts the collapsed loop — DEVICE-VERIFIED 2026-07-18

> **⚠️ ENGINE-AMBIGUOUS — flagged 2026-08-01 by the #220 audit.** This item's device
> verdict was recorded while NOTHING logged which voice engine was active, and the engine
> varied run-to-run with OJAMD's health. Specifically: the fix is in `SpeechOutputService`, which serves BOTH read-aloud (engine-independent) and native voice sessions. Safe if exercised via read-aloud, engine-dependent if via a voice session — **the record does not say which**.
> **See #220 before trusting or re-running this.**

> **DEVICE-VERIFIED 2026-07-18 (Owen's device, via the #134 forced-trip harness):** with read-aloud ON, the trip spoke ONLY the single collapsed on-screen line — the repeated loop tail was NOT droned. #110 retraction (`shouldRetractSpeech` / `finishStream(finishedContent:)`, PR #86) confirmed on device.

> **MERGED 2026-07-13 as PR #86 (`a62dc8c`)** — discovered 2026-07-16 when a fresh dispatch found the work shipped (Fable audit branch `claude/fable-t27-110-readaloud-wbsvmy` @ 3c15f1d verifies every acceptance line against the tree; implementation seam: `shouldRetractSpeech` static + `finishStream(finishedContent:)`, five decision tests + suite green via PR #94's Mac run 618/51). Remaining: organic-only device verify (deterministic repro defeated by base-model guardrails per #102). **Ledger lesson: this entry sat 🔧 with no merge note for 3 days and caused a dead dispatch** — merge notes are not optional.

> **Dispatch spec 2026-07-13 (eve):** `dispatch/FABLE-T27-110-readaloud-retract.md` — cloud-safe, pure-decision-fn test gate. Ready to send to CC.

Fell out of Lane H's adversarial review (PR #83), outside its file scope (touches `ChatStore`/`SpeechOutputService`, which Lane H deliberately never contacted): with auto read-aloud ON, a #102 breaker trip rewrites the bubble to one copy of the looped phrase — but the utterances already enqueued during streaming still SPEAK the full run of copies. The user sees the fixed transcript while hearing the loop the breaker just cut.

**Exact fix (documented in PR #83):** at `ChatStore.swift:517`, call `stop()` instead of `finishStream` when the finished content is shorter than the streamed text — a finished reply shorter than what streamed means content was retracted, so flushing the remaining queue is wrong by construction. Small, self-contained, no collision surface with anything in flight.

Only reachable when a breaker trip and auto read-aloud coincide, so low urgency — but when it fires it's maximally weird (eyes and ears disagree). Good candidate to ride along with the next `ChatStore`-touching lane, or as a standalone micro-PR.

Logged 2026-07-13 (Mac session, Lane H merge train).

## 111. ✅ PCC availability check churns doomed ModelManager sessions on every UI tick (#30 follow-up)

> **CLOSED — header flipped 2026-08-01 (Hermes audit Part 1A).** Closed by the #72 stopgap (PR #104, 2026-07-16) — `pccGrantConfirmed` short-circuits all four PCC surfaces.

> **MERGED 2026-07-16 as PR #104 (`bf36d29`).** The `pccGrantConfirmed` master gate short-circuits all four PCC surfaces before `PrivateCloudComputeLanguageModel` is ever constructed — no construction, no XPC churn. Branch-base suite 582/49 green; post-merge full-suite validation on main run same day. → ✅ on the next device build (verify the ModelManager flood is gone from the console). The memoize fix stays deferred until the PCC entitlement lands — when it does, flip the gate and re-verify.

> **2026-07-13 (eve): closed by the #72 stopgap.** This churn is the same unentitled `ModelManager` requests; the `pccGrantConfirmed` gate (branch `claude/t27-pcc-crash-stopgap`) never constructs a PCC session, so the churn stops. → ✅ once that branch merges.

Observed on whoGoesThere 2026-07-12 (Lane H device pass log): a near-continuous flood of `ModelManager received unentitled request. Expected entitlement com.apple.developer.private-cloud-compute` → `establishment of session failed` → `Sending cancel session failed` → `DeleteSessionRequest` internal errors, in bursts interleaved with sensor activity updates.

**Mechanism (source-read):** `LocalChatBackend.isPrivateCloudAvailable` / `isPrivateCloudUsable` (LocalChatBackend.swift ~153/162) each construct a **fresh `PrivateCloudComputeLanguageModel()`** per call; without the entitlement every construction attempts (and fails) an XPC session. The router's `availableBrains` consults `isPrivateCloudSelectable()` on every SwiftUI evaluation of the tier picker/status surface, and sensor activity updates invalidate that UI constantly → a burst of doomed session attempts per tick. Present since #30 shipped; not a Lane H regression.

**Cost:** log noise drowning real diagnostics (it buried the #61 `card generated` line), plus nonstop XPC establish/cancel/delete churn — a plausible background thermal/battery contributor on a device that runs the sensor loop all day.

**Fix shape:** memoize. A missing entitlement is static for the process lifetime — resolve availability ONCE (lazily, or at launch + foreground), cache the result, and have `isPrivateCloudUsable` only re-query quota when availability was true. Optionally hold one `PrivateCloudComputeLanguageModel` instance instead of constructing per call. Small, `LocalChatBackend`-scoped; could ride the next lane touching that file, or a standalone micro-PR (pairs naturally with #110's micro-PR sizing).

When the PCC entitlement is eventually granted (SBP → capability request pipeline), re-verify the cached path flips to available on next launch.

**Corroborated 2026-07-12 late (longer idle capture):** the burst pattern repeats with EVERY sensor activity tick with the app otherwise idle — no chat activity at all — confirming the render-driven mechanism and the all-day background cost.

**Same-capture triage — system noise, NOT ours, no action:** (a) `TUIPredictionViewCell` / `TUICandidateGradientContentLabel` unsatisfiable-constraint dumps (×15) and `variant selector cell index` (×18) are the iOS 27 beta SYSTEM KEYBOARD's own layout bugs — TextUI/UIKB classes only, zero Talaria views in any constraint list; same family as the `UIKBDynamicRenderFactory` warnings. (b) One transient `-1005 connection lost` on the `:8000` health upload self-healed on immediate retry within the same drain (outbox → 0) — the retry path working exactly as designed, and mild positive evidence for #104's outbox behavior under real network flap.

Logged 2026-07-13 (device pass finding).

## 113. ✅ Connector supervision — cloud half MERGED (PR #113, 2026-07-18) — CLOSED 2026-07-25; duplicate-connector premise refuted on the box. Successor: #188

> **CLOSED 2026-07-25 (OJAMD server pass).** Both premises below are refuted by
> direct observation on OJAMD.
>
> - **There are no duplicate connectors.** The "two live instances under DIFFERENT
>   interpreters" candidate describes normal health: one connector is three
>   processes in a single parent chain, all created in the same second, because
>   the venv `python.exe` trampolines to the uv-managed cpython. The enforcer
>   matches on `CommandLine`, catches all three, and held at exactly 1 across four
>   relay restarts.
> - **The "8,405 lines / 580 RESTART" figures came from a rotated log**, not from
>   current state. The four watchdog restarts on record all fall inside the single
>   2026-07-24 relay outage.
>
> The one real half — the watchdog cannot distinguish relay-down from
> connector-down — is documented in the script's own `.NOTES` and continues as
> **#188**.

**2026-07-23 — WATCHDOG LEG CLOSED; the real gap is somewhere else.** Confirmed on OJAMD via the
Hermes agent: scheduled task `TalariaConnectorWatchdog`, State=Ready, every minute,
LastTaskResult 0, NumberOfMissedRuns 0, running since 2026-07-17 18:30. Script at
`O:\Hermes\Talaria\scripts\connector-watchdog.ps1`, log at
`O:\Hermes\Talaria\logs\connector-watchdog.log` — 8,405 lines: 7,242 OK, 582 MISS, 580
RESTART, 0 ERROR. Installed AND working.
**But it only watches the connector.** Its own header says relay supervision is NSSM's job, and
NSSM `Automatic` fires at BOOT only — so a service that dies mid-session has no supervisor at
all. That is why relay and shim sat stopped (forensics note above). **The owed work is no longer
"install the watchdog"; it is "who watches the services".**
**Duplicate-connector mechanism candidate:** with the relay down there are no port-8000 sockets,
so the watchdog cannot tell "connector died" from "relay died" and relaunches the connector
every 2 minutes into a void. 580 relaunches is a lot of chances to beat
`start-connector.bat`'s single-instance enforcer — and the two live instances ran under
DIFFERENT interpreters (venv python vs uv cpython-3.12.11), which would sail past an enforcer
matching on process name or path. Unproven; check the enforcer's matching criteria first.

**2026-07-23 — FORENSICS (gathered via the Hermes agent on OJAMD, unelevated).**
- **Two concurrent connector processes**, not one: `hermes-mobile.exe run` under the venv python
  AND under uv-managed cpython-3.12.11. At least one was not launched by
  `scripts/start-connector.bat`. Alongside them, many never-exited per-session spawns
  (`hermes-mobile-mcp.exe`, `steam_mcp_server.py`, `bluebubbles_mcp_server.py`).
- **connector.log tail is pure `UnicodeDecodeError`** — cp1252 choking on byte 0x90 from a
  subprocess stdout reader thread, repeating. Consistent with an instance running WITHOUT the
  `PYTHONUTF8=1` the bat sets.
- **Relay AND shim were found Stopped** on 2026-07-23 ~10:00 CDT, both `StartType=Automatic`,
  with OJAMD up since 2026-07-16 17:45 — so they were stopped well after boot, not a failed
  boot start. Bounded: the phone checked into the relay at 2026-07-22 13:32, so the stop falls
  between then and 07-23 10:00. No SCM events inside a 40-event window; dating it exactly needs
  a wider filtered sweep (EventID 7000/7009/7031/7036).
- **Nothing alerted.** This is the supervision gap this item exists for, now demonstrated on the
  NSSM-managed services too, not only the bare connector.
- Hermes cannot start these itself: `Start-Service` returns "Cannot open <svc> service on
  computer '.'" — SCM requires elevation, Owen pastes. Diagnosis it CAN do unelevated.

> **MERGED 2026-07-18 (PR #113, `bb33328`).** Die-loudly hardening (FATAL log + nonzero exit
> through cli/client/service_runner), `supervision.py` + 5 tests — connector suite **123/123 on
> the Mac**; `scripts/connector-watchdog.ps1` committed (port-truth liveness, 2-miss threshold,
> invokes start-connector.bat, log rotation, `schtasks` install line in header — NOT
> self-executing); app-side outage alert (`type: .alert`, deduped, clears on delivery, 15 tests).
> App suite **780/65** on the union tree (tree-identity validated). New baseline: **780/65**,
> connector **123**. → **Owed:** (1) Owen installs the scheduled task on OJAMD (one schtasks line,
> file header); (2) death forensics from the 07-14/07-16 connector logs, next OJAMD pass;
> (3) NSSM-promotion decision stays open — watchdog covers either answer.

> **BUILT 2026-07-17 (cloud) on `claude/fable-t27-113-connector-krjdhu` — all three deliverables.**
> D1 die-loudly: new `connector/src/hermes_mobile_connector/supervision.py`
> (`run_connector_until_stopped` + `fatal_exit`) wraps BOTH entry paths (`cli._run_foreground`,
> `service_runner.run_from_state_dir` incl. startup failures) — any end except Ctrl+C logs a
> timestamped `FATAL: <reason>` + traceback and exits 1; catches `BaseException` so
> CancelledError/SystemExit can't slip the loop's `except Exception`; a clean `run_forever()`
> return is ALSO fatal (that IS the silent-death shape). The reconnect loop's `last_error`
> bookkeeping save is now best-effort (a transient write must not kill the loop); the state
> `load()` at loop top stays unguarded on purpose — unreadable identity should die loudly. No
> lock to release: the bat's enforcer keys off the live process/port, and exit happens after
> asyncio teardown closes the WS. 8 new tests in `tests/test_supervision.py`; connector suite
> **122 passed + 1 macOS-only skip (Linux)**. D2: `scripts/connector-watchdog.ps1` committed —
> port-truth liveness (`Get-NetTCPConnection -State Established -LocalPort 8000` filtered to
> local-address peers, never process names), one check per run with a persisted miss counter
> (2 consecutive → fire `start-connector.bat`, fire-and-forget), rotating log at
> `O:\Hermes\Talaria\logs\connector-watchdog.log`, exact `schtasks /Create … /SC MINUTE /RU Owen`
> line in the header — NOT installed/executed by the repo. D3 app alert:
> `ConnectorOutageAlertPolicy` (pure state machine: 3 CONSECUTIVE delivery-free retry-exhausted
> drain cycles → raise ONCE; only a real delivery clears; inconclusive cycles break the streak
> but never clear) fed at drain end by `SensorUploadService`; `InboxStore` gains persisted
> LOCAL items (`InboxLocalState.localItems`, additive decoder per the #42 lesson) — kind
> `.alert` (valid enum, never touches the #58 decoder), deduped, leads the fetched rows,
> survives relay-fetch failure AND relaunch mid-outage, Acknowledge/Dismiss resolve locally
> (no relay round-trip); wired in AppContainer. 16 new Swift tests
> (`ConnectorOutageAlertTests.swift`). **Swift half cloud-written, NOT compiled** — next Mac
> session: `xcodegen generate` (2 new files: `Services/Support/ConnectorOutageAlertPolicy.swift`
> + `TalariaTests/ConnectorOutageAlertTests.swift`; separate commit; verify aps-environment
> survives), CLI build + app suite (≥755/62 baseline), then device-verify the alert via a
> connector-down window. Forensics on the 07-14/07-16 deaths STILL OWED (next OJAMD pass);
> NSSM-promotion vs scheduled-task watchdog remains Owen's infra decision — the watchdog ships
> either way and is strictly additive.

> **Dispatch spec 2026-07-17:** `dispatch/FABLE-T27-113-connector-supervision.md` — SENT (see
> above). Cloud half only: connector dies-loudly hardening (nonzero exit + FATAL log),
> `scripts/connector-watchdog.ps1` committed (port-truth liveness per house learnings, invokes
> start-connector.bat, installed by Owen as a scheduled task — NOT executed by the repo), and the
> app-side inbox `alert` on repeated retry-exhaustion (valid kind, deduped). NSSM-vs-watchdog
> remains Owen's infra decision; the code works under either. Forensics on the 07-14/07-16 deaths
> still owed on the next OJAMD pass.

**Incident (2026-07-14):** health uploads stopped draining on both whoGoesThere and Shelley's iPad ("upload busy, retries exhausted" in the sensor diagnostics panel). Diagnosis walked outside-in from the Mac: app-side drain/chunking ruled out (#104 touched persistence only; #24a chunking long shipped), relay up with `/v1/device/sensor/health` answering 401 in 27ms unauthenticated — then on OJAMD, `Get-NetTCPConnection -State Established -LocalPort 8000` showed only device sockets, no local connector, and `Get-Process hermes-mobile` returned nothing. **The connector process was dead entirely** — relay 202-busied every ingest, devices mapped it to `.retry`, exhausted, deferred, piled up. Chat unaffected (Sessions plane).

**Fix:** relaunched via `O:\Hermes\Talaria\scripts\start-connector.bat`; connector re-attached in ~10s (Established from `100.110.102.59`), both devices confirmed delivering + clearing on next foreground drain. Diagnostics panel string (#15) earned its keep — it was the 30-second confirmation.

**Distinct from #54** (re-attach when the process lives, resolved 2026-07-09): this is process mortality. Relay and shim are NSSM-supervised; the connector is a bare bat-launched user process — a crash is a permanent detach until a human notices via piled-up sensors.

**Owed:**
- **Forensics on next OJAMD pass:** why it died (connector log around time of death; likely window = during/after the 07-13 evening deploy work) + confirm whether #85/#86 deploys actually landed (handoff listed them owed; OJAMD DC session dropped before verification).
- **Supervision decision (Owen):** promote connector to an NSSM service like relay/shim (must respect the single-instance enforcer + `PYTHONUTF8=1` env), or a scheduled-task watchdog that re-runs the bat when `hermes-mobile` is absent.
- Optional app-side: consider surfacing repeated retry-exhaustion as an inbox alert instead of a panel-only string (kind must be within the app enum).

Logged 2026-07-14.

---

## 114. ✅ Backend Profiles — server switcher (T6 Part 2): second profile without wiping the first

**Residual CLOSED 2026-07-20:** the from-Talaria-chat Shelley send — the last outstanding
DoD element per the 2026-07-16 device verification — landed via #107 (read receipt on file).
Item complete.

> **MERGED 2026-07-16** — Lane M landed as the three stacked PRs (#96 model+migration+per-profile
> clean-slate, #97 routing, #98 Settings surgery), main @ `2ab4945`. Mac review loop: xcodegen
> regen clean (entitlements survived), BUILD SUCCEEDED, **645 tests green** (643-test full run's
> only 4 issues were a test-fidelity bug — see trap below — fixed and re-verified 22/22 across
> the three Lane M suites; tree-identity checked against the tested build).
>
> **Loop findings (repo-wide precedents):**
> - **`withTaskGroup` + @MainActor children is categorically broken on the iOS 27 SDK** —
>   "pattern that the region-based isolation checker does not understand", regardless of capture
>   Sendability (three variants tried). Working pattern, now used in `SessionsHermesClient` and
>   `ServerSettingsScreen`: **unstructured `Task<Void, Never>` handles + a `@MainActor`
>   accumulator box**, await every handle, then read the box. Add to the Swift-6 gotcha list.
> - **ISO8601 date round-trip trap:** the #41-era store encodes dates whole-second; tests that
>   `#expect(loaded == saved)` with `pairedAt: .now` fail invisibly (values print identically).
>   Use whole-second fixture dates in round-trip expectations.
> - `Design.Typography.BodyWeight` has no `.semibold` (regular/medium/bold); `Logger.verbose`
>   is the String-taking TalariaLog extension — no `privacy:` interpolation.
>
> **Fable deviations — ACCEPTED:** migrated profile keeps legacy Keychain keys (mapping, not
> renaming — re-migration after data loss provably re-finds the pairing, #41-safer); active +
> sensor-destination IDs live on the Keychain-mirrored blob so a reinstall can't recover
> profiles yet lose which is active.
>
> **OPEN (Owen):** should the #4 confirm gate cover agent-initiated iMessage sends? Today the
> only guard is the apple-messaging skill instruction (soft). Flagged in the dispatch, not built.
>
> **Device verification owed (definition of done):** on whoGoesThere — migration lands existing
> install as "OJAMD" (active, sensor destination) with pairing intact; add "Mac Mini" profile
> (gateway `http://100.79.222.100:8642`, relay `http://100.79.222.100:8000/v1`, shim `:8765`);
> pair via `hermes-mobile pair-phone` on the Mini; switch both ways confirming NOTHING wipes;
>
> **DEVICE-VERIFIED 2026-07-16 (whoGoesThere):** migration landed as "OJAMD" with pairing intact;
> Mac Mini profile added, keyed, and paired (relay devices table = 1 row, redeem 200 from the
> phone's tailnet IP); **both cards PAIRED simultaneously — the P0, on device**; switched both
> ways with a successful chat round-trip on EACH host; SENSORS badge stayed pinned to OJAMD
> while Mac was active (D2). Remaining: the Shelley iMessage closer (deferred by Owen to
> after-work hours — the human confirm gate at work; closes this DoD + #107's last criterion).
> Friction found: shim token required manual locate-and-paste, and SHIM ONLINE reads green from
> the unauthenticated /healthz probe even with no/bad token → both captured as #116.
> "New chat on Mac Mini" long-press; then the closer: "send an iMessage to Shelley: …" from the
> Mac profile → #4 confirm → delivered — which also closes #107's dev-pairing criterion.

Owen's model (2026-07-14/15 session): capability-based hosts — OJAMD = production brain
(sensors, Windows toolsets, scheduled runs); Mac Mini = Apple-ecosystem hands (iMessage,
Notes, Xcode toolsets, agent files). Re-homing via a Settings profile switcher: tap the
profile, pick the host, bam — new work targets it; switch back for Windows needs.

Spec: `planning/SPEC-backend-profiles-v1.md` (v2 + session directives; Fable lane dispatch
pending final doc pass). Locked decisions: relay plane FOLLOWS the profile (one-time QR pair
per relay, N stored pairings — makes #94/#3 clean-slate-on-pair PER-PROFILE, so a
second profile never wipes the first; #41 Keychain mirror extends per-profile); sensors stay pinned to production
(`sensorDestinationProfileID`); sessions carry immutable birth-host `profileID` (drawer
routes reconnects; pushes from both relays route by session tag); **"New chat on <profile>"
shortcut IS in v1** (Owen), including retooling/removing the warning text on the current
New Chat button. Settings cleanups folded in: retire the dead relay "use hosted" tab; retire
the Hermes Host Relay/Direct switch (Direct-only reality per #108 iPad lesson — every
profile is Direct-with-its-own-key by construction).

Definition of done: whoGoesThere holds OJAMD + Mac profiles simultaneously, switching is
non-destructive both ways, and "send an iMessage to Shelley" works from Talaria chat on the
Mac profile with the #4 confirm gate.

Logged 2026-07-15.

---

## 115. ✅ Connector `resolve_mcp_command_path()` macOS venv fix — MERGED (PR #111) + Mini-VERIFIED 2026-07-17

> **Loop verdict 2026-07-17 (PR #111 merged):** connector suite **118/118 on the Mac** (Fable's
> Linux 117 + 1 macOS-only skip — the skip runs here, on the platform the bug bites, and passes;
> import provenance verified against the branch source before trusting the run). **Mini
> verification complete post-merge:** the venv install is editable, so the pulled fix is live —
> `resolve_mcp_command_path()` returns `.venv/bin/hermes-mobile-mcp` with NO PATH override. The
> 2026-07-14 workaround is retired. Process note: OPEN_ITEMS again rode the feature commit
> (recurring Fable miss, not blocking).

> **Dispatch spec 2026-07-17:** `dispatch/FABLE-T27-115-connector-venv-path.md` — **READY TO
> SEND.** Unresolved-sibling-first fix in `mcp_registration.py:47`, pytest fixtures for
> macOS-symlink vs Windows-copy shapes, Windows behavior unchanged. Kills the PATH-override
> workaround on the Mini.

> **Update 2026-07-17 (Fable lane): built** on `claude/fable-t27-115-connector-venv-tlnhty`.
> `resolve_mcp_command_path()` now tries the unresolved sibling
> (`Path(sys.executable).with_name(...)`) before the resolved one; which/PATH candidate
> order untouched. Three new tests in `connector/tests/test_connector.py` (macOS symlink
> shape, Windows copied-exe shape, which fall-through); the macOS-shape test verified to
> FAIL against the old code. Connector suite green on Linux: **117 passed + 1 macOS-only
> skip** (old baseline 114+1 plus the 3 new tests). No relay/app changes, no Xcode loop.
> **Owed after merge:** the Mini device check — plain `hermes-mobile configure-mcp` (no
> PATH override) must succeed; then delete the PATH-override workaround from any Mini notes.

`Path(sys.executable).resolve().with_name("hermes-mobile-mcp")` resolves the venv python
symlink to the framework/uv binary FIRST, escaping the venv, so the sibling lookup misses
`.venv/bin/hermes-mobile-mcp` and setup/configure-mcp report "Could not find
hermes-mobile-mcp" (Windows venvs copy the exe — OJAMD never hit this). Workaround used on
the Mini 2026-07-14: `PATH="$PWD/.venv/bin:$PATH" hermes-mobile configure-mcp` (shutil.which
candidate wins). Fix: try the UNRESOLVED sibling (`Path(sys.executable).with_name(...)`)
before the resolved one, in `connector/src/hermes_mobile_connector/mcp_registration.py`.
Micro-PR, standalone.

Logged 2026-07-15.

---

## 118. ✅ Voice capture background teardown — MERGED (Lane V, PR #112, 2026-07-18); device-verified 2026-07-20

**Device pass 2026-07-20 (Session V launch sweep): PASS — CLOSED.** Backgrounding mid/post
voice session extinguishes the system mic indicator; CarPlay exemption held per checklist.

> **MERGED 2026-07-18 (PR #112, `ceecfdb`).** Backgrounding ends the session through the user-end
> path on whichever engine is driving; **CarPlay exempted** (Fable's catch, correct — CarPlay voice
> runs backgrounded by design, #19); pure `TalkSessionRules.shouldEndSession` pinned by tests. The
> Swift 6 observer landmine handled by documented payload-untouched main-actor hop. Suite 765/63.
> → Device: start voice → background → mic indicator OFF; repeat in CarPlay sim → stays ON.

> **Dispatch spec 2026-07-17:** `dispatch/FABLE-T27-118-119-voice-residuals.md` (Lane V, shared
> with #119) — **READY TO SEND.** Background → clean session end via the user-end path; Swift 6
> selector-observer landmine flagged; realtime engine audited the same way; decision-function
> test. Rider in the same lane: migrate voice-path setActive calls to the async API without
> touching #106 ownership.

Observed on the #82 device-confirm run (2026-07-16, whoGoesThere, `probe/t27-fix84-verify`):
after backgrounding the app mid/post voice session, the system mic-in-use indicator stays lit —
the capture chain isn't torn down on scene-phase change or app background. Expected: leaving the
app (without an intentional background-audio mode) ends capture and releases the session.
Likely a missing scene-phase/`didEnterBackground` hook in the voice session lifecycle
(`NativeVoicePipelineService` / `VoiceEngineRouter` teardown path). Privacy-relevant —
prioritize into the next voice lane.

Logged 2026-07-16.

---

## 119. ✅ Voice UI cancel-race banner + CONNECTING header — MERGED (Lane V, PR #112, 2026-07-18); device-verified 2026-07-20

**Device pass 2026-07-20 (Session V launch sweep): PASS — CLOSED.** Post-completion barge-in
surfaces no banner; header tracks live session state past CONNECTING through a full
conversation.

> **MERGED 2026-07-18 (PR #112).** `RealtimeErrorRule` classifies no-op-cancel and
> response-create races → `.notice` + swallow; real failures still surface. Header bound to live
> session state past connect. Rider landed with one deliberate exclusion: `SpeechOutputService`
> stays synchronous (interlocked with the #106 gate — rationale in-source); other voice-path
> setActive calls moved off-main. → Device: barge-in post-completion → no banner; header tracks a
> full conversation; setActive warning wall reduced.

> **Dispatch spec 2026-07-17:** rides `dispatch/FABLE-T27-118-119-voice-residuals.md` (Lane V,
> with #118) — **READY TO SEND.** No-op cancel race classified + swallowed at the call site;
> header bound to live session state instead of the connect phase.

Same #82 confirm run, screenshot on file: (1) a barge-in/cancel racing an already-completed
response bubbles the backend error string straight into the session UI — a no-op cancel is a
normal race, log it and swallow it; (2) the session header still reads 'VOICE LINK ·
CONNECTING' while a live two-way conversation is flowing — the status label isn't tracking the
session state machine past the connect phase. Two small fixes, likely same surface
(voice session screen state plumbing).

Logged 2026-07-16.

---

## 120. ✅ Chat message list — duplicate ForEach IDs — FIXED (PR #116); device-verified 2026-07-20 (standing Console watch continues)

**Device pass 2026-07-20 (Session C launch sweep): PASS — CLOSED.** Streamed replies across
variants with zero ForEach/LazyVStack duplicate-ID warnings in Console. Owen’s call: keep this
as a STANDING WATCH — the dup-ID Console check rides every future device session (added to the
#141 watch list) rather than being one-and-done.

> **LANE BUILT LOCALLY 2026-07-18 (PR #116, `claude/t27-120-chat-hygiene`), suite 807/68 green.**
> Root cause found + pinned by a fail-first test (`MessageListIdentityTests`, new file, regen'd):
> conversation-maintaining backends (LocalChatBackend, the mock) append the final reply to their
> own thread BEFORE yielding `.finished`; a conversation merge landing in that window (the 2s
> relay-poll tick every send starts) adopts the reply into the store while the streaming
> placeholder is still in the array, and the `.finished` handler replaced the placeholder by
> index without checking for an existing copy of the final id — same UUID twice. The post-finish
> metadata merge only masked it when `hermesClient.currentConversation` happened to contain the
> reply (nil on warm launch — `loadConversationIfNeeded` returns early from cache; wrong backend
> under overlapping turns). Fix at the source: `.finished` drops any pre-merged copy before the
> placeholder swap (placeholder's slot wins — stable identity for animations + #78 menu targets),
> and `mergeConversationMetadata` now dedupes the refreshed list itself (first occurrence wins),
> so a foreign transcript can't import an internal duplicate wholesale. Same lane: #25 second
> half + the CFPrefs rider (closed as framework-side no-op — code-absence proof in the PR body).
> → **Device check:** stream replies (incl. on-device brain + forced trip) with the relay paired;
> Console must show no `ForEach`/`LazyVStackLayout` duplicate-ID warnings.

> **E2E REGRESSION GUARD ADDED 2026-07-18 (same lane, `7a08142`), fail-first proven red/green.**
> `MessageIdentityUITests` drives the real app (cold launch + two warm relaunches, real sends)
> and asserts transcript id uniqueness via a `chat.dupIDProbe` a11y seam on the transcript
> ScrollView — it publishes the ForEach source array's max id multiplicity, joins the view tree
> only under `UITEST_DUPID_PROBE=1`. Determinism comes from a DEBUG+env-gated synthetic turn in
> `LocalChatBackend` (no model needed): production append→finish machinery, a 2.6s dwell so the
> 2s poll-tick merge lands inside the duplicate-seeding window, and `currentConversation`
> cleared pre-`.finished` to model the unprimed-client shape. That clear is what makes red
> reachable — a key finding from building this: with `currentConversation` populated, the
> post-finish metadata merge heals the duplicate in the same MainActor turn (SwiftUI never
> renders it), which is precisely why the bug only survived device warm launches. Red proof:
> with the `.finished` dedupe reverted, the probe reports multiplicity 2 on the cold-launch
> send; restored, the full cycle passes. `TalariaUITests` now rides the test scheme (gate:
> 807/68 unit + identity UITest + launch smoke, TEST SUCCEEDED). The sim-side guard narrows the
> owed device check to the relay-paired + forced-trip variants.

> **Dispatch spec 2026-07-17:** `dispatch/FABLE-T27-120-chat-hygiene.md` — **READY TO SEND.**
> Fail-first uniqueness test through a stream-then-finalize cycle, fix at the source (no
> `.id(UUID())` papering). Same lane carries #25's second half (mid-stream gauge flash — interim
> numerator suppression, cumulative-tokens path stays banned) and a rider: the launch-time
> CFPreferences kCFPreferencesAnyUser app-group warning (fix the domain or prove it framework-side).

Device logs 2026-07-16 (two separate runs): `ForEach<Array<Message>, UUID, …>: the ID
1C6EBACD-8632-4E77-9257-9D054CF7E82D occurs multiple times within the collection` plus a
`LazyVStackLayout` duplicate-child-ID warning. A message UUID appears twice in the rendered
collection — either a real duplicate in the store (streaming placeholder + finalized message
both retained?) or a derived-array bug. SwiftUI declares the result undefined; symptoms may
include ghost/duplicated bubbles. Cross-ref #110's ChatStore territory — could ride the next
ChatStore micro-lane.

Logged 2026-07-16.

---

## 125. ❌ Health trends view — CUT 2026-07-24 (PR #142, merge `dd3074e`); shipped in PR #117, never reachable in practice, removed rather than rescued

**CUT 2026-07-24 (Owen).** Removed: `HealthTrendsScreen`, `LiveHealthTrendsService`,
`MockHealthTrendsService`, `HealthTrendsServiceProtocol`, `HealthTrendsCore`,
`HealthTrendsCoreTests`, the `PermissionsScreen` entry point and the `AppContainer` wiring.
`xcodegen generate` run (mandatory — files removed); pbxproj diff PURE DELETIONS, 32 lines,
0 additions; `aps-environment: development` verified intact post-regen. Suite **1091 / 98,
TEST SUCCEEDED** (baseline 1107/99 — delta is exactly the 16 tests and 1 suite covering the
deleted code). Zero `HealthTrend` references survive in `Talaria/`, `TalariaTests/`, `Shared/`.

**`Shared/HealthQueryCore.swift` deliberately KEPT** — it is not a trends file. It is the shared
HealthKit primitive layer behind the sensor pipeline (#103/#104/#117), `DeviceHealthTool` (#28),
and the widget's shared window (#15). `HealthQueryCoreTests` stays with it.

**Cutting this did NOT shed the HealthKit dependency.** The sensor path still reads health data,
so the entitlement, the usage strings, and the App Store review scrutiny that comes with HealthKit
all remain. What was shed is a screen and two lanes of work, not a platform dependency — worth
recording so nobody later cites this cut as having simplified the review posture.

**Why it went rather than got fixed.** The screen was reachable only in the same session in which
health was granted (#181). Making it reachable meant persisting the grant, which reaches into
`collectSnapshot()` and the sensor pipeline — a real lane. And nobody had established that the
screen would show anything at all for a granted-but-sensors-off free-tier user, which was the
tier it was built for. Building a pipeline fix to feed a screen of unknown value failed the test.


**2026-07-23 — THIS SCREEN IS UNREACHABLE ON A COLD LAUNCH. See #181.** Owen reported never having
come across Health Trends in the app; a source read found the entry-point gate depends on an
in-memory health-auth flag that resets every launch. Not a discoverability problem — the link does
not render. Device pass for this item is blocked behind that finding and runs as Lane 10 of
`dispatch/OPUS-T27-DEVICE-PASS-2026-07-24.md`.

HKStatisticsCollectionQuery daily buckets (7/30/90d) over the already-authorized metric set,
rendered through the #100 chart pipeline (reuse, don't fork). Hidden cards for unauthorized/
empty metrics; pure-function trend deltas; no new scopes, no server. The App Store screenshot.

> **Dispatch spec 2026-07-17:** `dispatch/FABLE-T27-125-health-trends.md` — **READY TO SEND.**

**Built 2026-07-18 (Mac session, branch `claude/t27-125-health-trends`), TDD fail-first:**
pure math in `Services/Support/HealthTrendsCore.swift` (`dayStarts` calendar-day windows —
DST-tested over the 2026-03-08 spring-forward; `alignedDailyPoints` sparse-not-zero-filled
stat alignment; `dailySleepPoints` via the existing `HealthQueryCore.aggregateSleepDuration`
end-day attribution; `weekOverWeekDelta` averaging only days-with-data, nil on missing
window or zero baseline; `downsampled` endpoint-preserving stride; `chartSpec` downsamples
BEFORE the #100 point budget; `cardAccessibilityLabel`), 15 tests in
`HealthTrendsCoreTests`. Service = `HealthTrendsServiceProtocol` + `LiveHealthTrendsService`
(HKStatisticsCollectionQuery per quantity metric, `.cumulativeSum` steps/calories vs
`.discreteAverage` resting-HR/HRV/resp-rate, sleep via sample query + core bucketing; auth
gate = a closure over `LiveHealthService.authorizationStatus` — never requests scopes) +
`MockHealthTrendsService` (deterministic, HRV/resp absent to exercise hidden cards). Screen
`Features/Health/HealthTrendsScreen.swift`: cards render through `ChartCanvas` (the #100
plot, no fork — `ChartSegmentView` needed no refactor), 7/30/90 pills, hidden empty cards,
honest NO-TREND-DATA / HEALTH-ACCESS-OFF panels, tap-to-fullscreen via the existing
`ChartViewerScreen`, per-card VoiceOver label. Entry: nav link under the health card in
`PermissionsScreen`, only when authorized (the `hermes://health` surface). NOTE: HRV is in
the metric list per dispatch but the app has never requested its read scope — its card
stays hidden until a future lane adds the scope. LLM commentary on trends remains the
future connected-tier rider (no FoundationModels here).

---

## 126. ❌ Daily briefing — DROPPED 2026-07-23 (superseded by the #162 Tasks/cron surface); app half stays merged and inert

**DROPPED 2026-07-23 (Owen): “the daily cron — lets drop that. No need now that we have scheduled
tasks.”** The #162 Tasks lane (cron browse/create/edit/control, PR #135, device-checklisted under
#171) gives the same outcome through a surface the user drives, without a bespoke host-side cron
half and a JSON contract to maintain. The two remaining blockers — OJAMD deploy and the host cron
config — are now moot and will not be built.

**What stays:** the app half is merged (PR #126, `edeba74`) and inert without a host sending
`category: "briefing"` payloads. `BriefingDetailScreen`, the widget, and `InboxStore.markRead`
remain wired and harmless. The `send_inbox_item` payload passthrough in the connector stays — it
is additive and useful to the inbox generally. **No revert commit is owed;** removing it would be
more churn than leaving it dormant. Revisit only if a briefing product need reappears.

**The six-step device pass is CANCELLED.** Do not run it. #147 (inbox-alert tap crash) was found
against this PR and stays open on its own merits — dropping #126 does not close #147.

**Session S sweep 2026-07-20: deferred to circle-back (Owen’s call)** — consistent with the
known blockers (OJAMD deploy + host cron half still owed ahead of the device pass).

> **MERGED 2026-07-20.** Recognition (category-only, #58-tolerant), speakable derivation
> (fenced blocks fully stripped), BriefingDetailScreen via MarkdownContentView (charts render
> free), local-only markRead, read-aloud toggle, HermesBriefingWidget (small/medium,
> `hermes://briefing`), payload fields on BOTH lockstep HermesWidgetData copies. Connector:
> `send_inbox_item` now forwards optional `payload` (additive, own commit) — the dispatch's
> "no connector changes" premise was wrong for this one field; approved in review.
> **Remaining, in order:** (1) OJAMD deploy — rebase `ojamd-deploy` onto `t27/main`, restart
> connector (payload passthrough is dead until deployed); (2) host cron half — scheduled run
> + prompt using the JSON contract in the PR #126 body; (3) Owen device pass — six-step
> checklist in the PR body. **Known scope cut (accepted):** notification tap still routes to
> chat — inbox alert pushes carry no identifying userInfo; the small relay follow-up
> (userInfo on inbox alert pushes → tap-to-detail) is described in the PR if wanted later.

> **BUILT in lane 2026-07-20 (`claude/t27-126-daily-briefing`, PR #126).** App half complete: recognition
> (`payload.category == "briefing"`, kind-tolerant), `BriefingDetailScreen` through the EXISTING
> MarkdownContentView (chart fences render + tap through free), read-aloud via the SHARED
> SpeechOutputService (`speakable` ?? fence-stripped body; #106 gate untouched), Daily Briefing
> widget (small/medium, `hermes://briefing` deep link, honest empty state), snapshot fields on
> BOTH HermesWidgetData copies (lockstep verified), `InboxStore.markRead` (local, no relay
> round-trip). Suites in lane: app **929/84 + UI 8/8** green (pre-lane 913/80), connector **129
> passed**. DISPATCH CORRECTION: the connector's `send_inbox_item` did NOT forward `payload`
> (relay DTO/DB/serializer + app decoder all did) — minimal additive passthrough shipped in its
> own commit, flagged for Owen in the PR alongside the tap-routing decision (inbox alert pushes
> carry no identifying userInfo, so notification tap stays → chat; detail reachable via row +
> widget). **Device pass owed:** hand-crafted payload through `send_inbox_item` → push → inbox
> row → detail renders markdown + inline chart → read-aloud speaks (both speakable and fallback)
> → widget shows it → widget tap deep-links back. THEN wire the real cron with the PR's JSON
> example.

Host cron synthesizes health + calendar + threads → inbox `notification` with markdown body
(may carry ```chart fences — dormant Path A wakes scoped to briefings), optional `speakable`,
`category: "briefing"`. App: detail view via MarkdownContentView, read-aloud via the existing
gated SpeechOutputService, latest-briefing widget via SharedWidgetDataStore, hermes:// deep
link. Host half = Owen's cron config against the JSON contract in the spec/PR.

> **Dispatch spec 2026-07-17:** `dispatch/FABLE-T27-126-daily-briefing.md` — **READY TO SEND.**

Logged 2026-07-17.

---

## 128. ✅ Voice capture crash — double installTap via actor reentrancy — FIXED (2026-07-17); repro DECOUPLED (not unreachable) — source archaeology 2026-08-01; **CLOSED by Owen 2026-08-01**

> **⚠️ NAMING COLLISION — the same one #129 documents, and it has now actually
> misfired once. GitHub #128 is `probe(#130) DO-NOT-MERGE: half-duplex + .default
> mode`, closed unmerged 2026-07-30 — it is a DIFFERENT THING from this item.**
> Owen closed this item citing *"it looks closed to me on github"*; that was the
> probe PR, not this. **The close still stands on the archaeology below** (the fix
> is live, and the DoD as written cannot verify anything), so the outcome was right
> and the premise was not. Recorded because the collision is no longer hypothetical:
> **`probe/t27-130-halfduplex` is deliberately KEPT and #130's A/B is still owed**,
> so reading GitHub #128's closed state as "we're done here" is wrong twice over.
> **Tracker numbers and GitHub numbers are independent sequences — always say which.**

> **§E1 RAN 2026-08-01 — and be precise about what it settled.** It proved the
> migrated installer **THROWS** on a double-install (`Code=-10863`,
> `{false condition=nullptr == Tap()}` — *this item's exact crash assertion*)
> rather than raising an uncatchable exception. **So if this race ever occurs
> again it is recoverable, not a hard kill.** But it did **NOT** test the adjacency
> invariant itself; it priced the residue, exactly as it always said it would.
> **This close is STRENGTHENED, not independently verified** — the distinction
> matters, because "the crash became a throw" and "the race cannot happen" are
> different claims and only the first is measured.

> **CLOSING BASIS, stated so it can be reversed if it turns out thin.** This item is
> ✅ because its fix is in the tree and load-bearing (layer 3 of 4), **not** because
> its Definition of Done was met. **The DoD as written — "repeat the exact repro" —
> is now known to be unable to verify anything**, since PR #127 removed the trigger
> while re-enabling the button. **No test has ever exercised the #128 invariant and
> none is planned.** The only lane that would produce real evidence is §E1's
> deliberate double-install probe, which stays open on its own merits. If §E1 ever
> runs and the invariant fails, **reopen this** — closing it does not make the
> comment-as-guard any stronger than it was.

> **✅ ARCHAEOLOGY DONE 2026-08-01 (§G, no device time).** The 2026-07-25 note asked
> "dead defensive code, or an unrecorded repro route?" **The answer is neither, and the
> premise was stale when it was written.** Four findings, each checkable from the tree:
>
> **1. "Structurally impossible since April" was stale by five days at the moment it was
> written.** It describes #129's *base* commit, where mid-session preview was
> double-blocked. **PR #127 (`175261b`, 2026-07-20) removed the `.disabled(isSessionActive)`
> stopgap** — #129's own entry says so — and the current tree confirms it:
> `VoiceSettingsScreen.swift:189` has **no `.disabled` modifier at all**. The button is
> reachable mid-session and has been since 07-20; the note is dated 07-25.
>
> **2. The button was re-enabled and the MECHANISM was removed in the SAME PR.** #128's
> trigger was never "audition a voice" — it was the **chat** instance re-categorizing the
> shared session `.playAndRecord → .playback` under a live capture engine. PR #127 routed
> mid-session previews to the session-less native instance
> (`SpeechOutputService.swift:159-165` says this outright). So the documented repro is now
> **a button that no longer produces the category flip that raced the restarts.**
> **The repro is DECOUPLED from the defect, not unreachable** — running it proves nothing
> about #128 in either direction. That distinction is the whole finding: an unreachable
> repro is a gap in coverage; a decoupled one is a test that will always pass.
>
> **3. #220's engine hypothesis HOLDS — and it is stronger than it was filed.** The
> realtime engine is **WebRTC** (`LiveVoiceSessionService.swift:5-6,136-138`), which owns
> its own audio unit: **zero** matches for `installTap`/`AudioNodeTap`/`AVAudioEngine` in
> that file, against 5 tap sites in `NativeVoicePipelineService`. So on a paired phone with
> healthy realtime the #128 invariant is not "exercised by different code" — **no
> tap-install code is in the process's path at all.** The 07-25 attempt could not have
> reached it whatever Owen did in Settings. This is the third independent reason that
> attempt came back empty, and the only one that was invisible before #198A's logging.
>
> **4. The fix is NOT dead code — it is the innermost of four guards.** See the table
> below. **And it has a demonstrated bypass history:** the 07-10 serialization whose commit
> message names this exact failure was already in the tree on 07-17 (verified:
> `git merge-base --is-ancestor 67cf879 d8b9ad7`), and the crash happened anyway.
>
> **Owed after this:** nothing on the device queue. The physical re-verify is still
> #129's test (§F6) and closes #129, not this. **If a future lane wants real evidence for
> the #128 invariant it must construct the race deliberately** — §E1's `installTap`
> double-install probe is that lane, and it is deliberately not a unit test.

**Defence in depth as it now stands — the #128 fix is layer 3 of 4:**

| date | commit | guard | what it stops |
|---|---|---|---|
| 2026-07-10 | `67cf879` | `restartTask` coalesce + >3/30s breaker | restart-vs-restart racing |
| 2026-07-16 | `54824a3` | `isConfiguringAudioSession` + `.categoryChange` carve-out | self-inflicted category churn restarting capture |
| **2026-07-17** | **`d8b9ad7`** | **#128: remove adjacent to install** | **a race that slips both → last writer wins cleanly** |
| 2026-08-01 | `f636297` | #198 `AudioNodeTap.install` | a double-install **throws** instead of raising an uncatchable NSException |

**The loose end, recorded rather than smoothed over.** Layer 1 landed **seven days before**
the crash it was built to prevent, and its commit message names the failure verbatim —
*"racing restarts (double tap-install NSException)"*. It was in the tree on 07-17 and the
crash still occurred. The uncovered path is visible in the source: `restartTask` serializes
`restartCapture` against itself, but **`startSession() → beginCapture()` is not guarded by
it** — only by `isConfiguringAudioSession`, which landed 2026-07-16, *one day* before the
crash. So either the crash came in through that window, or the coalescing had a hole since
closed. **Not settled here, and it does not need to be to close the archaeology question** —
but it is why layer 3 should not be deleted as redundant, and it is a standing caution
that a guard naming the right failure is not proof the failure is covered.

> **Routed out of the device queue 2026-08-01 (Hermes audit Part 1C):** this item's owed
> work is NOT a device check — see `dispatch/DEVICE-PASS-RUNNING-LIST.md` §G for what it
> actually needs. Do not carry it into a device sitting.

> **2026-07-25 — SUPERSEDED, and preserved because how it was wrong is the lesson.**
> Original text: *"The documented reproduction path for this crash has been structurally
> impossible since April. Either the fix is dead defensive code, or the original
> reproduction used a route that was never recorded."*
> **Both halves of the dichotomy were false and the premise was already out of date.**
> "Since April" was read off #129's *base* commit five days after PR #127 changed it — the
> same shape as the eight stale records of 2026-08-01: **true when the underlying text was
> written, false when it was cited.** It cost nothing here only because the item was
> correctly kept OFF the device queue. See the ARCHAEOLOGY block above.

**Session V sweep 2026-07-20: DoD NOT closed — the exact repro never cleanly ran.** The attempt
tangled with a different failure: cycling several auditions in Voice Settings then starting the
session FROM SETTINGS hung at ESTABLISHING LINK (→ #139; non-reproducible later same day).
Audition-then-composer-origin start passed. No crash observed at any point — but the #128 repro
(ACTIVE session → audition several → apply) is still owed. Re-run at the #139 circle-back, both
hosts.

> **Record correction (2026-07-20, from the #129 lane):** at #129's base commit, mid-session
> preview was DOUBLE-blocked since Wave 1 (disabled button + gated `speak()`), so "preview
> triggered #128" only holds if `isSessionActive` flapped during the interruption burst. The
> device re-verify below stands on its own evidence — PR #127 must NOT be read as closing it.

Device crash 2026-07-17 (whoGoesThere, mid-session voice change in settings):
`AVAEGraphNode CreateRecordingTap: nullptr == Tap()` — uncaught NSException, hard kill. Root
cause: the defensive `removeTap` sat FOUR suspension points (format negotiation + analyzer prep)
before the `installTap`; actor serialization does not survive awaits, so two interleaved capture
starts (triggered by the interruption/route event burst from #129's category yank) both passed
the remove and double-installed the bus tap. Fix (`d8b9ad7`, merged): remove-then-install in the
same synchronous stretch — last writer wins cleanly. Invariant pinned in-source; no unit test
(requires real AVAudioEngine reentrancy) — the comment IS the guard. Suite 800/67.
→ Device re-verify: repeat the exact repro — active voice session → Settings → audition several
voices → apply one. No crash; session degrades or recovers per #129's current behavior.

Logged 2026-07-17.

---

## 131. ✅ Composer mic (dictation) inert — NOT REPRODUCIBLE 2026-07-20: dictation works on device; instrumented catch retained. (Suspect correction stands: LiveSpeechService was untouched by Lane V)

**Device pass 2026-07-20 (Session V launch sweep): dictation functional.** Composer mic toggles
and transcribes on whoGoesThere. The 2026-07-17 inertness did not reproduce; the instrumented
catch named no error because no failure occurred. Closing as unreproducible-with-guard rather
than fixed-by-change — the catch stays in place to name it if it recurs (P-3 release-hygiene
sweep revisits the log level).

Device 2026-07-17: pressing the composer mic does nothing (OJAMD and Mac Mini, monetization gate
on — gate almost certainly irrelevant: the button calls `toggleDictation()` on `speechService` =
`LiveSpeechService`, which Lane V's async-setActive rider REWROTE the same day (+102/-45). Prime
suspect: rider regression in the dictation start path (activation reordering / early-return
guard). Discriminators owed: (a) dev-override gate OFF → retry (rule the gate out formally);
(b) confirm mic worked on the pre-tonight build. Investigate the rider's LiveSpeechService diff
first; likely a micro-fix.

Logged 2026-07-17.

---

## 133. ✅ Dormant-relay push registration idempotency — ROOT CAUSE FOUND AND FIXED 2026-08-02: the installation identity was stored inside profile-scoped session state that unpair deletes. DEVICE PASS ✅ 2026-08-03.

> **CLOSED — device pass verified 2026-08-03 (running list §F1, four-measurement protocol).**
> Baseline OJAMD 22/22/22 devices · 15/12 push_regs → Disconnect+relaunch: IDENTICAL
> (disconnect is purely client-side) → re-pair #1: **+1 row (23/23/23 · 16/13)** — the
> one-time legacy→durable convergence, NOT the bug: the old row's id predated the fix →
> re-pair #2: **ZERO growth, same row upserted in place** (`913f0656…` stable). The churn
> equality is broken. **A single-cycle read would have mis-scored the migration step as
> FAIL — the two-cycle protocol is the honest close.** Residual RESOLVED same night:
> Owen approved the #144-shape chore and it ran on OJAMD — 21 stale devices + 11
> stale/duplicate registrations deactivated (never deleted; backup + rollback next to
> the DB), leaving 2 devices + 2 registrations active and zero duplicate tokens.

> ## ✅ ROOT CAUSE 2026-08-02 — measured, not argued. **99 device rows / 99 distinct
> ## `installation_id`s.** The relay was right all along; the app minted every identity.
>
> **The measurement first** (Mac relay `devices` table, direct read):
>
> | | |
> |---|---|
> | device rows | **99** |
> | distinct `installation_id` | **99** — a perfect 1:1 |
> | the ONE real handset | **two** rows, `install=3b6f41e8` (born 07-16) and `install=c718cc64` (born 07-23) |
>
> A 1:1 ratio means the relay's `upsert_push_registration` was doing exactly what it
> should — one row per installation identity it was handed. **It was handed 99.**
>
> **Mechanism, source-confirmed:** `AppSessionStore.init` read
> `persistence.loadSessionState(profileScope:) ?? AppSessionState()`, and
> `AppSessionState()` mints a fresh `UUID()`. The installation id lived **inside the
> profile-scoped session state**, which `clearSession` deletes. So:
> **unpair → cold launch (nothing persisted) → NEW identity → re-pair → new device row →
> its own active push registration carrying the SAME APNs token → the relay fans out per
> registration → #143's duplicate notifications.** One root, two symptoms, exactly as
> #143's 2026-07-25 re-root-cause said — and **the 2026-07-23 "mechanism is RELAY-side"
> note below is wrong**; no relay change is needed for this.
>
> **Fix:** the identity moves to a durable, **non-profile-scoped** persistence key
> (`talaria.installationID`) that `clearSessionState` never touches — it names the app
> INSTALL, not a session or a relay. Upgrade behaviour is deliberate: the durable id is
> stamped onto whatever session state loads, so a pre-fix install **converges on one
> identity** rather than grandfathering whichever it last minted.
>
> **A partial fix would have left the defect reachable, and the test caught it.** Fixing
> `init` alone left `rebindToCurrentScope()` doing `state = persisted` — adopting a
> persisted (pre-fix or foreign-scope) state's own churned id, re-identifying the device
> on the next **profile switch**. Now it stamps instead of adopts.
> `aProfileSwitchDoesNotAdoptAPersistedStatesStaleIdentity` **failed behaviourally
> against the partial fix** (1 of 6 red, five green) before that line changed — a real
> red, not just a compile error.
>
> Six tests: unpair+cold-launch, ordinary relaunch, cross-scope sharing, minted-once,
> `clearSessionState` leaves it alone, and the rebind case. All six audited every write
> to `state` in the store (lines 100/269/271/318/356/361) — the other five already
> retained or merged.
>
> **Still owed — device pass.** These are unit-level guarantees; the row count is the
> real check, and the honest one (#144's lesson: verify by row count, not by suite).
> After a build with this fix: unpair, relaunch, re-pair, and confirm the relay gains
> **no new device row**. **OJAMD has never been measured at all** — its relay is where
> #143's ×5 was actually observed, and the 92 junk `iPhone 17 Pro Max` rows on the Mac
> are test pollution (#144), now prevented but not deleted.
>
> **What this does NOT fix, kept because the entry below is right about it:** the
> **insert race** (two rows 53 ms apart, same device AND same token) is a check-then-act
> race that a stable identity makes far rarer but does not make impossible, and
> `send_push` still has no per-token dedup. **The partial unique index on active
> `apns_token` remains the relay-side backstop** — recorded as still-open below, and
> unaffected by this lane.

> **LANDED 2026-08-01, eight days late: #133 cannot be captured from the Mac CLI.**
> `idevicesyslog` carries the legacy syslog stream — **system daemons only**. The app
> logs via `Logger(subsystem:)`, which writes to unified logging, a pipe
> `idevicesyslog` does not surface and `log stream --device` cannot reach on this
> macOS build. Proven on hardware 2026-07-24, not assumed: a cold launch inside a
> **1.47M-line capture contained zero app-process lines.** #133 has no visual
> substitute, so it was CUT from the device pass rather than restructured. Use the
> Xcode bridge's `GetConsoleOutput` for app log lines.
>
> **The finding was correct on 2026-07-24 and still cost something, because it lived
> on an unmerged branch.** For eight days `dispatch/OPUS-T27-DEVICE-PASS-2026-07-25.md`
> told the next session to run this check and "read the rest from Console" — an
> instruction already disproven on hardware, sitting in the document that governs
> device passes. The branch was found during a branch cleanup that was about to
> delete it.
>
> **Rule: a finding recorded on a branch that never merges is not recorded.** It is
> worse than unrecorded — the disproven instruction stays live and authoritative
> while the disproof sits somewhere nobody reads. Three instances surfaced on
> 2026-08-01 alone (this, the ATS rule in `CLAUDE.md`, and #130's restore command),
> all correct when written, all turned into traps by not landing. **A negative
> result is a deliverable and merges like any other.**

> **DEVICE PASS 2026-07-25 — idempotency is defeated by app-side identity churn.**
> One handset produced **36 device rows / 36 active push registrations / 4 distinct
> tokens** on the Mac Mini (OJAMD: 15 registrations / 9 tokens across 14 rows). Two
> rows were observed inserted **53 ms apart carrying the same device AND the same
> token**, both active — a check-then-act race, not a logic error.
>
> Consequence for the fix shape: deactivate-at-registration is the same
> check-then-act that just lost this race. **The partial unique index is
> load-bearing, not polish.**
>
> > **⛔ SUPERSEDED 2026-08-02 — the index is NOT being built, and the app-side fix is
> > why that is safe rather than merely a decision.** Declined under Owen's standing
> > no-hardening rule (`CLAUDE.md`). **The race needed churn to matter:** two rows land
> > 53 ms apart only when registration is racing itself during the identity churn this
> > item's root cause produced. With the installation identity now durable, a re-pair
> > re-registers the SAME identity, so the upsert has one row to find instead of
> > minting a rival. **The index guarded a window the app no longer opens.**
> > It stays filed, unbuilt. `send_push`'s missing per-token dedup and the unreachable
> > `TOKEN_INVALID` reaper (below) are likewise findings, not lanes — both are relay
> > hardening, and both stop mattering when one handset stops producing many rows.
>
> Also established: `send_push` has no per-token dedup, and the `TOKEN_INVALID`
> reaper can never fire — `apns.py:173` deactivates only on HTTP 410, and
> duplicate rows carry a *valid* token, so APNs returns 200 for all of them. The
> pile-up is not self-limiting by construction.

**2026-07-23 — ROW-COUNT LEG CLOSED on BOTH relays.** Direct DB reads. Mac relay: 16 device
rows, every one with exactly 1 push_registrations row. OJAMD relay: 21 device rows, 13
registrations, none exceeding 1. App-side idempotency verified in the field — no device has
ever accumulated duplicate registrations.
**What this leg CANNOT clear, and it matters:** the item's own prediction ("app-side idempotency
cannot clean pre-existing duplicate rows if any exist") is confirmed true in a shape nobody
anticipated. The duplication is at the DEVICE-ROW level, not the registration level: one APNs
token spread across five device rows. That is #143's root cause and it is relay-side. Nothing
the app can do fixes it.
Remaining #133 device pass: unchanged.

**Cross-ref 2026-07-20 (#143):** 5× notifications per Siri ask observed — but the Mac relay
DB shows whoGoesThere’s token registered EXACTLY ONCE (stable device row, last refreshed
00:17 — the #133 fix visibly holding server-side on this relay). During the owed device pass,
ALSO count `push_registrations` rows per device on the OJAMD DB to rule relay fan-out in/out
there; app-side idempotency cannot clean pre-existing duplicate rows if any exist.

> **LANE BUILT 2026-07-20 (`claude/fable-t27-133-push-idempotency`), suite 901/77 green, TDD
> (guard tests proven red first).** The fix is the active path's short-circuit mirrored per
> profile: `AppSessionState` gains `registeredPushToken` (optional — absent on pre-#133
> persisted states, so grandfathered profiles POST once, record, then go quiet), and
> `markPushTokenRegistered(_:profileID:token:)` records the acked token on success and nils it
> on deactivate. The dormant loop consults pure
> `DormantPushRegistrationPolicy.shouldRegister(recordedToken:currentToken:)`
> (`ProfileRelaySession.swift`) before POSTing — skip ONLY on exact recorded-token match, so an
> APNs token rotation and a cleared mark (unpair, notifications toggle off) both still
> re-register, and a failed POST leaves the record stale → retried on the next pass. Rider
> landed: the bare duplicate `reportAppStateIfNeeded("background")` Task in `AppEntry.swift`
> dropped. No files added/removed — tests ride `BackendProfileRoutingTests` (no regen needed).
> → **Device pass (Owen):** fresh launch with both profiles paired → at most one registration
> line per profile in the launch log (2 max, not 5); exactly one background app-state report
> per backgrounding; sensor pipeline unaffected.

**Found 2026-07-17** in a device log (background launch → foreground activation). One launch,
zero user input, produced **five** relay push registrations across the 2-profile config (OJAMD
+ Mac Mini, both legitimately paired — Owen confirmed 2026-07-17; the "dormant" label is the
app's, not a stale entry):

```
registerPushToken: relay accepted push registration
registerPushToken: relay accepted push registration
registerPushToken: dormant relay 'Mac Mini' accepted push registration
registerPushToken: dormant relay 'Mac Mini' accepted push registration
...
registerPushToken: dormant relay 'Mac Mini' accepted push registration
```

**Mechanism confirmed in source — not hypothesised.** `AppContainer.registerPushTokenWithActiveRelay`
short-circuits when nothing changed:

```swift
if notificationService.isPushTokenRegistered,
   notificationService.currentPushToken == normalizedToken {
    sessionStore.state.pushTokenRegistered = true
    return
}
```

`registerPushTokenWithDormantRelays` has **no equivalent guard** — it loops
`profilesStore.profiles where profile.id != activeProfileID` and POSTs unconditionally for
every paired dormant profile, on every call. That asymmetry is exactly the observed 2-active /
3-dormant split: the active path deduped after its first success; the dormant path never does.

Amplified by caller count — `registerStoredPushTokenIfNeeded()` has **five** call sites
(`AppContainer.swift` 1005, 1034, 1168, 1198, 1910), plus `AppEntry.swift:167`
(`didRegisterForRemoteNotifications`) and the Settings toggle
(`NotificationsSettingsScreen.swift:217`). None coordinate.

**Fix shape (small, file-scoped).** The per-profile state already exists and is already
WRITTEN — `profileRelaySessions.markPushTokenRegistered(_:profileID:)` is called on the
deactivate path — it is simply never READ as a guard. Mirror the active-relay short-circuit per
profile: skip the POST when that profile's registration is already marked true AND its stored
token matches `normalizedToken`. Keep the unconditional path for token CHANGE and for re-arming
after a relay-side registration wipe.

**Also fix while in `AppEntry.swift` (same launch path, trivial):** the `.background` branch of
the `scenePhase` `onChange` dispatches `reportAppStateIfNeeded("background")` **twice** — once
in a bare `Task`, once at the head of the following `Task` that also calls
`watchPendingRunIfNeeded()`. Reads as an edit artifact; drop the bare `Task`.

**Severity: low — no user-visible bug.** The relay is DB-backed (**#24f is DEAD — do not cite
it**), so every redundant POST is a real round-trip and a real write, but they are idempotent
server-side. The payoff is (a) 5 writes → 2 per launch, and (b) a readable launch log — which
matters, because the launch log is the primary diagnostic surface for the whole sensor
pipeline. Same family as #48's `collectSnapshot` debounce and #111's every-tick churn; a
natural companion lane.

**NOT a bug — checked 2026-07-17, recorded so nobody re-chases it.** The same log's doubled
`app-refresh scheduled` and doubled full health/location refresh are NOT fan-out.
`BackgroundRefreshScheduler.schedule()` has exactly one caller (`AppEntry.swift:239`, on
`.background`) plus a deliberate re-arm at `BackgroundTaskService.swift:78`; and the log opens
with `handleSystemLaunch` and only later reaches `handleAppDidBecomeActive` — it was a
background launch followed by a foreground activation, i.e. two legitimate lifecycle entries,
not one launch fanning out.

Logged 2026-07-17.

## 134. ✅ Free-tier launch gate — DEBUG forced-trip harness — DEVICE-VERIFIED 2026-07-18

> **DONE 2026-07-18.** Merged PR #115 (`fed76b5`); 803 tests / 67 suites green incl. 3 harness tests, zero compiler errors. Device pass (Owen): both buttons — Force repetition trip + Force trip (live SDK) — trip → collapse → #102 notice → thermal FAIR → post-trip send OK, no issues. Trigger lives in Settings → Diagnostics (`// Local brain — #102`), `#if DEBUG` only.

> **Dispatch spec 2026-07-18:** `dispatch/FABLE-T27-134-debug-forced-trip-harness.md` —
> cloud-safe, unit-test-gated, file-scoped to `LocalChatBackend.swift` + its test file.
> Sent to Fable; built same day (update note below).

The free-tier standalone runaway/overheat gate. #102's token cap is device-proven, but the
tail-repetition breaker (#102, PR #83) and the read-aloud retraction (#110, PR #86) — both
MERGED and unit-tested — have NEVER tripped organically on device: the deterministic repro is
defeated by the base model's own guardrails (it refuses verbatim-repeat and declines
long-form). This harness adds a `#if DEBUG` button in Settings → Diagnostics that drives a SYNTHETIC
degenerate stream through the EXISTING production path, so one device session verifies breaker
arm→escalate→abandon→collapse, thermal recovery, read-aloud non-drone (#110 retraction), and
post-trip send (D3, via the `session = nil` rebuild). Release-inert. Touches NO shipped
breaker/retraction logic — harness only. Scope = free-tier standalone chat; #61 title/preview
degeneracy is adjacent but OUT of this gate.

**UPDATE 2026-07-18 — harness BUILT (branch `claude/fable-t27-134-forced-trip-s0w9wc`),
cloud-written, NOT compiled.** Dispatch scope exactly, no new files (no xcodegen):
- `LocalChatBackend` gains a `#if DEBUG` extension — one-shot static arming
  (`debugForcedTripCopies` / `debugForcedTripHoldsLiveSDKStream`), the cumulative snapshot
  generator, and a forced-trip turn spliced into `streamTurn` right after the availability
  guard that reuses the PRODUCTION machinery verbatim: `streamDelta` → `.textDelta`, a real
  `RepetitionBreaker` judging every snapshot, the SAME #102 escalation notice,
  `collapsingDegenerateTail`, `appendAssistantMessage`, `session = nil`, `.finished`.
- **Unit-length correction to the dispatch:** the example unit ("The signal repeats. ",
  20 chars) can never trip — a 20-char unit reaches the 192-span detection floor only at
  10 copies, arming there and pushing the doubling threshold to 20 > the 16-copy default.
  The spec'd arm-at-6/escalate-at-12 shape requires a ≥32-char unit, hence the 32-char
  "The device loop signal repeats. " (fundamental period 32, qualifies; math pinned by the
  new tests: arms at 6, trips at 12).
- Snapshots pace 200 ms apart so read-aloud has STARTED speaking before the trip — #110
  must be seen retracting a live queue, not one that never began.
- `ChatStore.debugRunForcedTrip(copies:holdLiveSDKStream:)` arms one-shot and issues a
  NORMAL `sendMessage` through the standard streaming consumer (`enqueueStreamChunk` /
  `finishStream` + retraction). **Routing addition beyond the dispatch:** the router
  preference is pinned to `.onDevice` for that one turn and restored after — on a
  Hermes-paired device the backend flag alone is insufficient (the turn would route to
  Hermes and the stale flag would hijack the next real local turn; it's also cleared
  unconditionally post-send).
- Diagnostics `// Local brain — #102` panel (voice/sensor panel pattern): hint
  ("turn on read-aloud first to verify #110"), **Force repetition trip**, and the
  nice-to-have **Force trip (live SDK)** — holds a real suppressed SDK generation and
  cancels it on trip, probing that abandoning a live stream doesn't wedge the next turn.
- Tests appended to `LocalChatBackendTests` (arm-at-6/trip-at-12 pin, cumulative-shape +
  one-unit-delta pin, collapse-to-preamble+one-copy pin), all `#if DEBUG`.

**Mac owed:** CLI build + full suite (no regen — verify `git status` clean post-build),
then the acceptance session on whoGoesThere: **D2** reply collapses to one unit copy +
the #102 notice in Console + thermal ≤ fair and recovering; **#110** with auto-read-aloud
ON, speech cuts at the trip instead of droning the loop; **D3** an immediate normal send
streams a real reply (session rebuilt); plus the live-SDK button's no-wedge check.

Logged 2026-07-18.

---

## 135. ✅ Template UITests refreshed — MERGED (PR #124, merge `b027abd`, 2026-07-20); five flows green + un-skipped

The July-5 `TalariaUITests` class (AppTemplateUITests.swift: manual-pairing flow, chat send,
paired-launch skip, disconnect, host-status screen) predates the #31 no-pairing-wall redesign —
every test opens with `Enter Code Manually` as the expected landing state, which no longer
exists. They had NEVER run: the `TalariaUITests` target wasn't in the test scheme until the
#120 E2E-guard lane added it (2026-07-18), which is what surfaced all five failing at once.
Skipped at the scheme level (`project.yml` -> `skippedTests: [TalariaUITests]`), not deleted —
the mock-pairing scaffolding (`UITEST_PAIRING_MODE=mock`, `MockPairingService`, the
`/tmp/hermesmobile-uitest-config.json` external config) is worth keeping and refreshing.
`MessageIdentityUITests` and `TalariaUITestsLaunchTests` stay active in the gate.

**Known-stale locators for the refresh:** GlowButton uppercases its title into the a11y label
(`CONTINUE`, not `Continue` — verified via hierarchy dump 2026-07-18), so the template's
`completePairing` Continue-tap silently no-ops; entry points must switch from onboarding-first
to Settings -> Connect Hermes Desktop (#31).

Logged 2026-07-18.

> **REFRESHED in lane 2026-07-20 (branch `claude/fable-t27-135-uitests-refresh`).** The five
> flows rewritten against #31 reality and GREEN on the standard sim (47F68496,
> `CODE_SIGNING_ALLOWED=NO`), un-skipped in the scheme (project.yml regen; `aps-environment`
> verified surviving): standalone first launch → chat reachable + asserts the wall is GONE;
> mock pairing via Settings → Connect Hermes Desktop → ConnectHermesScreen → post-pair
> permissions onboarding CONTINUE; chat send rides the #120 `UITEST_DUPID_PROBE` synthetic
> turn (deterministic "Acknowledged" reply — mock pairing sets no API key, so routing stays
> local-brain by design); paired relaunch skip-path (also asserts the Settings upgrade row is
> GONE — a real paired-persistence signal); disconnect via Settings → Hermes Host →
> PAIR DEVICE → Connect Host → Disconnect → standalone chat, wall stays gone, upgrade row
> returns. `testLaunchPerformance` dropped (redundant with `TalariaUITestsLaunchTests`); the
> old host-status test folded into the disconnect traversal. Mock scaffolding retained
> (`UITEST_PAIRING_MODE`, external config JSON, per-test defaults/keychain isolation).
> Locators audited for the GlowButton casing trap via one case-insensitive containment
> helper (`CONTAINS[c]` — also absorbs SwiftUI row-button label concatenation).
>
> Two harness traps found and fixed on the way:
> 1. **`typeText` races the code field's reformatter** — the display-dash insertion rewrites
>    the binding mid-burst and DROPS keystrokes (on-sim: only ABCDEF of ABCDEFGH landed, so
>    PAIR DEVICE stayed disabled and the tap silently no-oped). Fix: one keystroke per
>    `typeText` call + an explicit `isEnabled` gate on the pair button.
> 2. **`CODE_SIGNING_ALLOWED=NO` breaks sim KEYCHAIN writes** (the #125 HealthKit-strip
>    trap's sibling): the entitlement-stripped build's SecItem writes all fail — silently,
>    since `KeychainSecureStore` ignores statuses — so the mock pair's tokens vanished and
>    `initialize()`'s no-access-token guard un-paired the app 6ms after
>    `pair: adopted relay user…` (sim log; the identical build SIGNED passes).
>    Accommodation, never a production path: when `UITEST_KEYCHAIN_SERVICE` is set,
>    `AppContainer` backs `SecureStoreProtocol` with the UITest defaults suite
>    (`Talaria/Services/Mocks/UITestSecureStore.swift`, relaunch-durable) and skips the
>    reinstall keychain mirror — `CODE_SIGNING_ALLOWED=NO` stays the standing harness.
>
> Full gate green on the Mac: unit suite 901 tests / 77 suites passed (Swift Testing);
> UI bundle 8/8 (MessageIdentity + the five + launch smoke ×2 configs). Merge owed.


---

## 136. ✅ Offline-first launch — MERGED (PR #122); device-verified 2026-07-20 (instant launch under relay+shim black-hole)

**Device pass 2026-07-20 (Session C launch sweep): PASS — CLOSED, with a mystery solved.**
With the OJAMD NSSM services stopped, cold launch went INSTANTLY to chat — the splash fix
holds under the exact black-hole case that spawned this item. Owen’s puzzle — “Hermes stays an
option and messages still go through” — is expected: the NSSM stop killed relay `:8000` + shim
`:8765` ONLY; the gateway `:8642` is NOT an NSSM service (it runs as the user `pythonw`
process — standing hard-rule trap) and was never down, and chat rides the gateway plane
independently of relay/shim. No hidden backup; the architecture behaved as designed.

**MERGED 2026-07-19 (PR #122, merge commit `0528529`).** Splash now drops on
local-state-ready; relay-backed init backgrounded; 5s bootstrap probe timeouts. **Device
pass owed:** cold launch with OJAMD relay+shim STOPPED (services down, machine up — the
firewall black-hole case) must reach chat in seconds, standalone fully functional; services
restored → state upgrades live without relaunch.

Device-caught 2026-07-19: with OJAMD's relay `:8000` + shim `:8765` STOPPED (NSSM services down
for an update) but the machine UP, the app sat on `ESTABLISH UPLINK` for minutes. Root cause is
two-part. (1) Windows Firewall silently DROPS packets to a listener-less port instead of
refusing — every relay/shim request hangs the full URLSession timeout (~60s, `-1001`) rather
than failing fast. (2) `AppContainer.initialize()` is SERIAL and only sets
`isInitialized = true` (which drops the splash) at the END: `sessionStore.bootstrap()` →
`hostStore.refresh()` → `loadInbox()` → `refreshCommandCatalog(force: true)` →
`seedActiveModelFromShim()` → `registerStoredPushTokenIfNeeded()` — each relay/shim-touching
step eats up to a full timeout back-to-back. The existing #3/#46 degraded-mode hardening
("do NOT strand the launch splash") only covers relays that ANSWER (401 / refused / instant
fail); the black-hole case was never exercised because Mac-side services refuse when down.
Verified live: services restarted → app launched instantly.

**Fix shape (non-negotiables restated in the dispatch spec):** (a) splash drops on
LOCAL-state-ready — flip `isInitialized` after capabilities reload, conversation load, sensor
start, and share-inbox drain; NO relay or shim call may sit on the splash critical path.
(b) Relay-backed init (bootstrap, `validateRestoredIdentity`, host refresh, inbox, command
catalog, shim model seed, push register) moves to a detached background task that updates state
as it lands — degraded is the DEFAULT launch posture; connectivity upgrades it live. This is
the freemium free-tier contract: standalone on-device MUST cold-launch fully functional with
zero hosts reachable. (c) Belt-and-suspenders: dedicated `URLSessionConfiguration` for the
bootstrap probes with `timeoutIntervalForRequest` ≈ 5s. (d) Preserve existing semantics: the
no-access-token → `clearLocalPairing()` guard is Keychain-local and stays on the critical
path; re-pairing still re-runs `initialize()`; #123 share drain stays free-tier-safe.

**Dispatch spec:** `dispatch/FABLE-T27-136-offline-first-launch.md`

Logged 2026-07-19.

---

## 141. ✅ iOS 27 beta 4 seed — released 2026-07-20; whoGoesThere updating tonight (watch list)

> **CLOSED — header flipped 2026-08-01 (Hermes audit Part 1A).** Transition COMPLETE 2026-07-20. Beta 4 is now the standing toolchain; the watch served its purpose.

**Environmental event, logged for attribution discipline.** Owen updates the device tonight;
remaining launch-pass sweep sessions (C, S, D, J circle-backs) will run on b4, so the OS delta
becomes a confound for anything non-reproducible — notably the #139 settings-origin hang
repro attempts and all #138/#130 voice echo observations. Note the seed in any new device
findings.

**Transition COMPLETE 2026-07-20 late — toolchain verified, baseline GREEN.**
- Xcode 27 beta 4 installed at `/Applications/Xcode-beta4.app` (Xcode 27.0, build
  `27A5228h`); CLAUDE.md toolchain references updated (own commit) — beta3 retired.
- Device on iOS 27 b4 (`24A5390f`). Sim runtimes `24A5355p` (b3) + `24A5380g` (b4) coexist;
  the pinned sim UDID SURVIVED the runtime rebind — no re-pin needed.
- **Full-suite baseline on the b4 SDK: 931 tests / 84 suites green + all UI bundles, TEST
  SUCCEEDED.** Canaries held — no SDK movement on the #108 alias or #58 symbol.
- Field report (Owen, early): keyboard behaving better on b4 — no forced ~15s waits yet.
  Console confirmation (absence of TUI constraint dumps) still owed before the #111-noise
  excuse is retired.
- Two sim-run observations: (a) `com.apple.modelcatalog` assets absent on the fresh b4 sim
  runtime — expected sim behavior, #61 guard owns it; (b) `SessionUsageIndex` persisted
  value failed JSON decode (legacy-state wart, self-healed fresh) — WATCH the first b4
  DEVICE Console for the same line; if it appears there, promote to its own item.

**Transition IN PROGRESS 2026-07-20 late: (Owen):** device updating to b4 AND Xcode 27
beta 4 installing — so the first watch item is answered: this is a full TOOLCHAIN
transition, not just a seed bump. Consequences queued: (a) DEVELOPER_DIR changes — confirm
the install path / rename convention (beta3 was a local rename; Apple default is
Xcode-beta.app) before updating CLAUDE.md and the standing build commands; (b) the pinned
sim UDID (47F68496…, created under beta3) may not survive — the new Xcode ships its own b4
sim runtime; re-pin after first boot; (c) first action on the new toolchain: full-suite
baseline build — the SDK canaries (#108 NavigationSplitViewVisibility alias, #58
systemExtraLargePortrait) exist to go red on exactly this transition, and a red there is
information, not failure.

**Watch on first b4 build/run:**
- Toolchain: does Xcode-beta3 still deploy/debug against a b4 device, or does a new Xcode
  beta land (→ DEVELOPER_DIR change, CLAUDE.md + README:77 update rides #140)?
- SDK canaries: the `NavigationSplitViewVisibility.automatic` alias test (#108) and the
  `systemExtraLargePortrait` line (#58) exist to surface exactly this kind of seed change —
  a new red there is information, not noise.
- Entitlements: `aps-environment` survival on the next regen (standing trap, #44/#48).
- Known b3 SYSTEM noise possibly resolved: TextUI/UIKB keyboard constraint dumps (#111
  triage) — if gone, stop excusing them.
- Voice: b3-era audio observations (#130 fidelity, #138 self-barge-in) re-observed on b4
  before any verdicts — seed changes to VPIO/AEC are plausible and would move conclusions.
- Standing #120 watch (Owen, 2026-07-20): the ForEach dup-ID Console check rides EVERY
  device session going forward — passive, but log any hit immediately.

Logged 2026-07-20.

## 142. ✅ Image-only sends — APP EXONERATED 2026-07-23 by wire capture; the defect is HOST-SIDE handling of a text-less parts array

**2026-07-23 — RESOLVED APP-SIDE (wire capture via logging reverse proxy, Mac host, build `cbcc824`).**
Three cases captured on the wire from whoGoesThere:
- picker image, no text -> `{"input":[{"type":"image_url","image_url":{"url":"data:image/jpeg;base64,..."}}]}`
- pasted image, no text -> structurally IDENTICAL
- image + text -> `{"input":[{"text":"Test","type":"text"},{"type":"image_url",...}]}`

**Suspect (1) DEAD.** `AttachmentInlining` assembles a correct parts array for a text-less
turn; it does not misclassify image-only as text-only.
**Suspect (2) DEAD.** There is no "[attachment]" string anywhere on the wire. The app never
emits it — so it is generated HOST-SIDE when Hermes (or its model adapter) receives a parts
array with no text part.
**Suspect (3) CONFIRMED as the location.** The only structural difference between the working
and failing cases is the presence of a text part.
**Kills the picker-vs-paste theory outright:** both paths emit the SAME shape, so two different
symptoms from byte-identical payload structure cannot be path-specific placeholder substitution.
All three cases also pass end-to-end against a healthy host as of 2026-07-23.
**Consequence: #61's card DoD is UNBLOCKED.** Host-side residue joins #132 (same family — app
exonerated by wire probe, host vision/config question owed).

**Found 2026-07-20 (Session C launch sweep, whoGoesThere; seed unconfirmed — b4 update was
scheduled the same night, #141).** Two symptoms, one shared shape:
- **Picker image, no text:** turn completes but the model responds as if it received only the
  literal text “[attachment]” — the image never reaches it. (Surfaced while attempting the
  #61 card DoD, which is blocked on this.)
- **Pasted image, no text:** assistant returns a literally EMPTY message — no text, no
  placeholder. Different downstream symptom, same trigger.
- **Any text + image:** works on BOTH paths — model sees the image. So the attachment
  pipeline is sound; the failure keys on the ABSENCE of text.

History rhyme: the 2026-06-28 round found image-only sends 400ing because `ChatTurnBody` was
text-only (→ #43). #43 made attachments transmit — evidently with a remaining image-ONLY
branch defect.

**Suspects (source-informed, unverified):** (1) the “text-only turns stay byte-identical plain
strings” branch in `AttachmentInlining` misclassifying an image-only turn (empty text) as a
text-only turn, so parts assembly never runs; (2) an “[attachment]” placeholder/stub
substituted for empty `input` (the #43-era 400 guard or the #57 omission-stub family) landing
INSTEAD of, not alongside, the image part; (3) host-side handling of a parts array whose text
part is empty (discriminate app vs host FIRST). The picker-vs-paste symptom split may just be
which placeholder each path substitutes.

**Discriminators (a)+(b) ANSWERED 2026-07-20 (Owen): BOTH entry modes affected.** Sequence: app
was already running (foreground wedge) -> OJAMD restored -> force-quit -> cold RELAUNCH stuck
on the LAUNCH SNAPSHOT ~10s -> phone restart. Three sharpenings fall out:
- Stuck-at-snapshot = the fresh process blocked BEFORE FIRST FRAME - upstream of the #122
  splash logic entirely. Implicates app/scene construction (App struct init, AppContainer
  construction, any synchronous store/Keychain/protected-data work pre-render), not
  initialize().
- The ~10s observation window cannot distinguish a permanent wedge from a slow grind through
  ~60s black-hole timeouts - the relaunch may have been alive and stacking timeouts.
- If the relaunch landed inside the gateway's ~15-20s post-start warmup, it hit a THIRD
  network failure shape: ACCEPTED-BUT-SILENT connections (port listening, no response) -
  distinct from refuse (fast-fail) and firewall black-hole (60s). The launch path must
  survive all three; the 5s dedicated-timeout config covers this shape too.
- IMMEDIATE evidence check (no repro needed): tonight's wedge + stuck relaunch likely left
  hang/spindump entries in Settings -> Privacy & Security -> Analytics & Improvements ->
  Analytics Data - a stack from either event names the blocking call outright.

**Discriminators owed:** wire-capture the outgoing `ChatTurnBody` JSON for all three cases
(picker-only, paste-only, text+image) — one look at the payloads names the guilty side and
likely the guilty branch. Then a Fable micro-lane with a fail-first test per case.

Logged 2026-07-20.

## 143. ✅ Siri-ask completion notifications arrive ×5 — ROOT FIXED 2026-08-02 with #133 (one cause, two symptoms); DEVICE PASS ✅ 2026-08-03

> **CLOSED — same verdict as #133 (2026-08-03): identity churn broken by the two-cycle
> re-pair proof. The ×5 itself was FOUND LIVE in the table this sitting** — token
> `0aa87bdf…` holds 5 active registrations, `df04a6a7…` (the phone's) 3 — so duplicate
> pushes CONTINUE until the #144-shape deactivation chore runs; that is debris from the
> old bug, not evidence against the fix. Also note the device pass's D4 finding (running
> list): the foreground reconcile posts its own local notification on top of any remote
> fan-out, so the user-visible count is (active rows) + 1 until D4's app-side fix lands.

> ## ✅ THE 2026-07-25 RE-ROOT-CAUSE WAS RIGHT, and the fix landed 2026-08-02 in #133.
>
> **Confirmed by measurement, not inference: 99 relay device rows against 99 distinct
> `installation_id`s** — the relay upserts one row per identity it is handed, correctly,
> and the app handed it 99. The fan-out is arithmetic from there: each extra device row
> carries its own ACTIVE `push_registrations` row for the **same APNs token**, and
> `active_push_registrations_for_user` returns them all → N identical notifications for
> one ask. Four active rows produced the ×4 that #146 screenshotted; five produced ×5.
>
> **The cause was in `AppSessionStore`, not the relay:** the installation id rode inside
> profile-scoped session state that unpair deletes, so unpair → cold launch → re-pair
> minted a fresh identity. **Full mechanism, fix, and the six tests are in #133** — do
> not duplicate them here; one root gets one write-up.
>
> **Owed:** the device check (unpair → relaunch → re-pair adds **no** new device row) and
> — the one that matters for THIS item — **re-count OJAMD**, where the ×5 was observed and
> which has never been measured. If OJAMD still holds N active registrations for one
> token, those pre-existing rows are historical debris the app cannot clean: the fix stops
> new ones, it does not deactivate old ones. **Deactivating them is a relay-side chore**
> (the same shape as #144's Mac cleanup: deactivate, never delete, keep a rollback).
>
> **Separate and still open — the `push_environment` contradiction** recorded below
> (registrations say `development`, devices say `production`, same handsets). Untouched by
> this fix and still worth an answer: if real, every OJAMD-originated push is addressed to
> the APNs sandbox.

> **RE-ROOT-CAUSED 2026-07-25 (device pass).** The relay-side framing below is
> wrong. The relay behaves correctly — it fans out to the active registrations it
> holds. The duplicate rows are created app-side: same root as **#133**. The fix
> belongs there; do NOT spec a relay-side fix from this item.
>
> Separate lead, explicitly not a verdict: on OJAMD `push_registrations.push_environment`
> reads `development` for all 15 rows while `devices.environment` reads
> `production` for all 22 — same handsets. If that contradiction is real, every
> push originating from OJAMD is addressed to the APNs sandbox.

**2026-07-23 — ROOT CAUSE FOUND. Source-verified. Mechanism is RELAY-side, not app-side.**
OJAMD relay DB: APNs token `0aa87bdfa91d...` is registered against FIVE distinct device_ids,
FOUR still `is_active=1`. Every re-pairing mints a fresh device row; nothing deactivates the old
ones (21 device rows total, all `is_active=1`).
Source, `relay/app/services.py`:
- `upsert_push_registration` keys the upsert on **device_id**, NOT on apns_token — so each new
  device row gets its own registration carrying the SAME token. This is precisely why every
  device reads exactly 1 registration and why #133's app-side fix looked correct.
- `active_push_registrations_for_user` selects every active (Device, PushRegistration) pair for
  the user with **no dedup on apns_token** — returning four rows for one physical handset.
Four rows -> four separate APNs requests -> duplicates arriving SPACED rather than bursty,
which is exactly the observed shape and is why app-local scheduling was correctly ruled out.
**Numerically corroborated by #146:** that item records the push delivering ×4 (screenshot on
file) while the diagnostics row sat stuck. Four active registrations, four deliveries.
**The discriminators previously owed from Owen are NO LONGER NEEDED** — superseded by direct DB
plus source evidence.
**Fix shape (relay):** (a) dedup by apns_token at send time — cheap, immediate; (b) proper fix:
deactivate prior registrations/device rows for the same token at registration time; (c) partial
unique index on active apns_token to stop recurrence.

**New candidate mechanism 2026-07-20 late (Hermes 0.19 changelog):** 0.19 ships a
delivery-obligation LEDGER — finished responses are REDELIVERED after a gateway crash/restart.
A redelivery loop misfiring (or replaying against tonight’s bounced services) could produce
exactly N identical simultaneous deliveries. New discriminator: establish whether OJAMD was
already ON 0.19 during the ×5 events (update timing vs Session S sub-checks), and check the
ledger’s state/logs host-side next OJAMD window.

**Discriminators partially ANSWERED 2026-07-20 late (screenshot on file):** the burst is
SIMULTANEOUS (all “now”) with IDENTICAL content — and the multiplicity DRIFTED: ×4 on this
delivery vs ×5 earlier the same evening. Count drift across the relay’s 0.19-window bounce
favors a server-side row-count mechanism (something count-like changed host-side tonight)
over app-side duplication; a simultaneous identical burst is consistent with fan-out at send
time. Sharpens the OJAMD DB query (#143(b)/#144): expect ~4 active registration rows for
whoGoesThere right now — if the count matches the delivery multiplicity, mechanism closed.

**Constraint (added 2026-07-20, sweep-owner note):** the Mac ×0 is UNEXPLAINED under both candidate
mechanisms and should be treated as a hard constraint. The Mac relay holds exactly ONE
healthy registration for whoGoesThere, so relay fan-out predicts ×1 on Mac-pointed asks —
not ×0; and app-side local-notification duplication should replicate regardless of host —
also not ×0. Whatever the mechanism is, it must simultaneously produce ×5 on OJAMD and ×0
on Mac (e.g. the notification originates host/relay-side and the Mac deploy lacks that path,
OR the app’s completion-notification only fires on reconcile paths the Mac asks never took).
Add to the discriminator list: one Mac-pointed ask with Console attached — does ANY
notification get scheduled/delivered at all, and by which carrier?

**Found 2026-07-20 (Session S sweep, seed b3).** Both the Siri-Stop run (which kept generating,
#56(2)) and the tailnet-off run (#56(3)) delivered FIVE notifications each for a single ask.

**Evidence so far (Mac relay DB, read 2026-07-20 late):** whoGoesThere’s APNs token is
registered ONCE on the Mac relay (stable row since 07-16, refreshed today 00:17) — so on Mac
evidence the phone has no server-side fan-out, and the initially suspected “pre-#133 stale
registration rows” theory does NOT hold there. (The five same-day registrations that first
looked like fan-out are test-harness pollution — #144, unrelated device rows.)

**Candidate mechanisms:**
(a) **App-side local-notification duplication** in the pendingRun/reconcile/retry path — one
notification scheduled per poll tick / retry attempt / reconcile pass instead of once per
terminal state. STRENGTHENED by the tailnet-off case: if the relay was unreachable, remote
push could not have been the carrier (unless the five arrived after reconnect).
(b) **OJAMD relay-side duplicate registrations** — unverifiable from the Mac; count
`push_registrations` per device in `O:\Hermes\Talaria\relay\hermes_mobile.db` next OJAMD
session (rides the #133 device pass, cross-ref added there).

**Discriminators owed (Owen, 30 seconds of memory):** did the five arrive WHILE offline or
after rejoining? Simultaneous burst or spread (poll-cadence spacing)? Identical content?
Then: Console capture of one repro — local-notification scheduling lines from our subsystem
vs APNs delivery tells the carrier immediately.

**Datapoint 2026-07-21 (controlled):** ONE `send_inbox_item` (notify:alert) from OJAMD →
FOUR notifications on the phone. Fan-out ×4 confirmed on a clean single send, host healthy,
phone online — rules out offline-queue replay as the sole mechanism; ×4 matches the prior
observation exactly (stable multiplier, not random).

**Discriminator ANSWERED 2026-07-21 late:** second controlled single send → 4 copies,
SPACED (not a burst) — poll-cadence spacing. **CARRIER CORRECTED 2026-07-21 (source-read):** NOT app-local scheduling — the app has
no inbox local-notification path (`LocalNotificationService` covers only reply-failed /
run-completed, UUID identifiers). Mechanism is RELAY-side: `relay/app/main.py:413` loops
`active_push_registrations_for_user` (`services.py:918`) and sends one alert push PER
active (Device, PushRegistration) row — each app reinstall re-enrolls a new active row
(→ #144's pollution), so ×N = active row count for the phone; spacing = the sequential
send loop. Tonight's reinstall-heavy debugging likely GREW the multiplier. Fix: dedupe on
`upsert_push_registration` (`services.py:873`, deactivate prior rows for the same physical
device / replace same-token), send-loop token dedupe, and APNs 410 → deactivate. Confirm
first in OJAMD relay DB (count whoGoesThere's active rows, expect ≈4). Ship list in
`planning/HANDOFF-2026-07-21-PUSH-FIXES.md`.

Logged 2026-07-20.

---

## 144. ✅ Test-harness runs enroll as LIVE devices on the Mac relay — **PREVENTION BUILT 2026-08-02**; registrations cleaned 2026-08-02; **device rows cleaned 2026-08-03 — DONE**

> **CLOSED 2026-08-03 — the device-row half ran (Owen approved, device-pass sitting):
> 97 harness device rows (`iPhone 17 Pro Max` ×92, `CC-M4a-Baseline` ×5) deactivated on
> the Mac relay DB; the 2 real `iPhone` rows stay active; totals preserved at 99 —
> deactivate, never delete.** Backup + rollback ids:
> `handoffs/evidence/t27-144-mac-relay-backup-20260803.db` / `t27-144-device-rollback-20260803.json`.
> **The same shape also ran on OJAMD production the same night** (first time ever):
> 21 stale devices + 11 stale/duplicate registrations deactivated, leaving 2+2 active
> and **zero duplicate active APNs tokens** — this, plus #133's root fix, is the full
> end of #143's duplicate pushes. OJAMD backup + rollback sit next to that DB
> (`hermes_mobile.backup-20260803.db`, `deactivation-rollback-20260803.json`).

> ## PREVENTION BUILT 2026-08-02 — and the verification is a ROW COUNT, not a suite
>
> **The premise was re-checked before any code, and it had grown.** 2026-07-23
> recorded 15 pollution rows against 1 real device. **2026-08-02: 92
> `iPhone 17 Pro Max` + 5 `CC-M4a-Baseline` against 2 real `iPhone` — 99 total —
> and FIVE were created that same day by this project's own suite and gate runs**
> (00:11, 05:49, 06:03, 06:15, 06:58). Not a stale entry: reproduced live, by us.
>
> **Mechanism confirmed in source:** `AppSessionStore.swift:88-99` registers
> whenever `!state.deviceRegistered`, and test launches use a fresh
> `UITEST_DEFAULTS_SUITE`, so every run looks like a brand-new device — matching
> the original note's "each with a FRESH `installation_id`".
>
> ### The fix that would NOT have worked, recorded because it read perfectly
>
> The first version routed the guard through `usesMockPairingService` →
> `allowsFallback`. **`ResilientSessionBootstrapService` tries `primary` FIRST and
> falls back only on a thrown error.** The relay is UP during a test run, so the
> live call **succeeds**, `allowsFallback` never fires, and the row is created
> regardless. **A guard consulted only on a path the bug does not take** — the same
> shape as #145 Part D's cooperative-cancellation trap found the same day. The
> primary itself must be the mock.
>
> ### Detection, not "remember to set the env var"
>
> `UITEST_PAIRING_MODE` already existed and **was** the mechanism — it just relied
> on every test author remembering. **A guard that depends on being remembered is
> precisely what failed.** `TestRunGuard` now detects the run
> (`XCTestConfigurationFilePath` for the in-process host, the `UITEST_` prefix for
> the separate XCUITest app process), so the safe path is the default.
>
> **Gated on `allowsEnvironmentOverrides`** — otherwise an environment variable
> would silently disable real pairing on a SHIPPED build. Pinned.
>
> ### A hypothesis of mine that measurement KILLED
>
> I identified `AppTemplateUITestsLaunchTests.testLaunch` — the auto-generated
> bare `XCUIApplication()` that runs on every gate — as "THE polluter", and wrote
> that into the source. **A control run carrying `TestRunGuard` but NOT the
> `testLaunch` marker added ZERO rows.** If that launch were enrolling, it would
> have added one. **The likelier culprit is the unit-test HOST process**, caught by
> the guard's other branch. The marker is kept as belt (a bare launch is a standing
> hazard) but its comment now states it is **not** the proven cause.
>
> ### Evidence
>
> | run | rows before → after |
> |---|---|
> | full suite + XCUITest (guard only) | **99 → 99** |
> | full gate incl. Release (guard + marker) | **99 → 99** |
>
> **Every other check run this session measured the CODE. This one measured the
> DEFECT** — and it is the only one that could have shown the fix working while
> the story about it was wrong. GATE: PASS, 1477 + 8, Release green.
>
### ✅ MAC CLEANUP DONE 2026-08-02 (Owen approved) — 84 deactivated, nothing deleted

**Deactivated, not deleted**, per the original note's preference for keeping audit
history. Ran against the live relay (it stayed healthy — `/v1/health` 200 after).

| | before | after |
|---|---|---|
| ACTIVE registrations, sim (`iPhone 17 Pro Max`) | 79 | **0** |
| ACTIVE registrations, `CC-M4a-Baseline` | 5 | **0** |
| ACTIVE registrations, real `iPhone` | 2 | **2** ✅ |

**Integrity confirmed after:** `push_registrations` total unchanged at **86**,
`devices` total unchanged at **99** — nothing was deleted, only flagged. Both real
devices remain active.

**Reversible two ways**, and both were captured BEFORE the write:
- the 84 affected registration ids → `/tmp/t27-144-rollback-ids.txt`
- a full DB copy → `/tmp/t27-144-relay-backup.db`

The id list matters more than the predicate: **re-running the discriminator later
would not reproduce the same set** once new rows exist, so a predicate is not a
rollback.

**⚠️ The discriminator is a TRIAGE RULE, not an invariant.** It keys on
`device_name != 'iPhone'`. Both real devices are iPhones today, so it is correct
now — **but an iPad, or any real device reporting a different name, would look
like junk to it.** Do not automate on this.

### STILL OWED — OJAMD's relay has NEVER been measured

This item has only ever looked at the **Mac's** relay. **OJAMD is the host the
phone actually talks to**, so junk registrations there fan out against real device
traffic and matter more. It cannot be read from the Mac: the relay exposes no
admin or device-listing route (all 20 routes enumerated 2026-08-02), and the DB is
a file on the Windows box. **Owen, in PowerShell — read-only:**

```
python -c "import sqlite3;c=sqlite3.connect(r'O:\Hermes\Talaria\relay\hermes_mobile.db');print(c.execute('SELECT COALESCE(device_name,\"(null)\"),COUNT(*) FROM devices GROUP BY 1 ORDER BY 2 DESC').fetchall())"
```

Python rather than a `sqlite3` CLI because Hermes brings Python and the CLI may
not be installed there.

**2026-07-23 — DISCRIMINATOR FOUND, no repro needed.** Real devices report
`UIDevice.current.name` REDACTED as the generic "iPhone"; simulators report their actual
configured name. The Mac relay therefore separates cleanly: 1 row named "iPhone" (whoGoesThere,
live) versus 10 named "iPhone 17 Pro Max" and 5 "CC-M4a-Baseline" — all 15 harness/sim
pollution.
Cross-confirmed independently: the single anomalous 160-char APNs token (every other token is
standard 64-char hex) belongs to sim row `135656d8`, named "iPhone 17 Pro Max".
Name-based filtering is therefore a viable triage rule for cleaning production device tables,
and a viable guard for keeping harness runs out of them.

**Found 2026-07-20 while chasing #143 (Mac relay DB read).** `devices` shows five
`CC-M4a-Baseline` rows created 17:46–20:22 (one per merge-loop/baseline run window, each with
a FRESH `installation_id`) plus two sim “iPhone 17 Pro Max” rows (16:33/16:37) — all with
ACTIVE `push_registrations` carrying the simulator’s APNs token. The polluter is the
automated loop itself: harness runs pair/enroll against the LIVE Mac relay because the
checkout’s config points at it.

**Costs:** unbounded device-row growth (one per run, forever); relay pushes fanning out to
sim/test tokens (APNs errors + wasted sends); DB reads during diagnosis actively misleading
(this exact read initially masqueraded as the #143 fan-out mechanism).

**Fix shape (two halves):**
(1) **Prevention:** test/baseline executions must not enroll against a live relay — env-gate
pairing/enrollment + push registration in harness runs (e.g. skip under `XCTestConfiguration`
/ a `TALARIA_TEST_RUN` env), or point the harness at a scratch relay DB. Decide the mechanism
against how the baseline loop actually launches the app.
(2) **Cleanup:** one-off sweep of existing `CC-M4a-Baseline` + sim device rows and their
registrations on the Mac relay (and OJAMD if present — check same session as #143(b)).
Deactivate rather than delete if audit history matters.

Logged 2026-07-20.

## 145. ✅ App hard-locks when entered during an OJAMD gateway outage — **Parts A–D + E(a) ALL BUILT 2026-08-02; DEVICE PASS ✅ 2026-08-02, CLEAN**; only E(b) remains, tabled behind written triggers

> **CLOSED — device pass 2026-08-02 (running list §F5), against a live black-holed
> fixture (`100.69.76.52`, packets dropped): all three parts CLEAN, the pre-registered
> "expect CLEAN, not merely better" bar met.** (1) app fully navigable while blocked;
> (2) last-known-good visible immediately, badges honest; (3) restore → self-recovery,
> no restart — Part D superseded the stale activation, journal hop re-primed, and the
> failed send's retry delivered. Part A proved live: black-holed send died at 21s
> (interactive bound) with working/stop affordance then retry. E(a):
> `foregroundActivationsCutShort` stayed ZERO across the window. Part D observed firing
> three separate times this sitting. E(b) stays tabled as before.

> **Header corrected 2026-08-02 — it was STALE, and the way it went stale is the point.**
> It read *"Parts B + C BUILT; Parts A + D owed"* while the body of this same entry
> recorded A and D built and merged. **The header survived two PRs that edited this very
> entry** (#234, #235) — nobody re-read the top of an entry they were appending to.
> That is precisely the header-only-judgement failure **#230 (Phase 0)** indicted, filed
> the same weekend, committed by the same author who wrote the indictment. Caught by the
> external Hermes audit of #218–#238, not by us. **Standing consequence: when a lane
> appends to an entry, it re-reads that entry's HEADER before it commits** — the header is
> what the next reader judges from, and Phase 0 measured six of six header judgements
> wrong.

> ## PARTS B + C BUILT 2026-08-02 — the phone-restart property is what these two address
>
> **The 2026-07-24 investigation was re-verified against today's tree before any
> code was written** (it was nine days old, and this file's own lesson is that an
> entry is not evidence). **All three load-bearing claims still held:**
>
> | claim | verified 2026-08-02 |
> |---|---|
> | chat plane has NO timeout config | ✅ zero matches across all five clients — still `URLSession.shared`, **60s request / 7 DAYS resource** |
> | `handleAppDidBecomeActive` = 12 serial awaits, UI writes last | ✅ intact (now `AppContainer.swift:1375`; no `async let`, no task group) |
> | reconcile budget wrong by ~30× | ✅ `ChatStore.swift:1628` |
>
> ### PART C — the reconcile loop now budgets WALL TIME, not attempts
>
> `maxAttempts = 60 // 60 x 2s = ~2 min` budgeted only the `Task.sleep`. Each
> attempt is an unbounded gateway fetch, so the real ceiling was **60 × (2s + 60s)
> ≈ 62 minutes.** **An attempt counter cannot bound a loop whose per-attempt cost
> is unbounded.**
>
> **Written into the source, because it is the part most likely to be misread:
> this bounds the LOOP, not a single call.** The deadline is only tested between
> attempts, so one hung fetch still outlives it. **Bounding the call is Part A.
> Neither part alone closes #145.**
>
> ### PART B — the visible state now refreshes BEFORE any network call
>
> The spec's highest-value part. `reconcileLiveActivities()` / `updateWidgetData()`
> sat behind ~8 network awaits, so the app could not repaint until the chain
> drained — minutes, continuing after the host recovered. **That is the difference
> between "slow right now" and "broken, and I restarted my phone."**
>
> **The spec's open question — do the UI writes depend on the network steps above
> them? — was answered from source: NO.** Both are synchronous, purely local and
> idempotent. They are now called **early AND late**, deliberately: the early pass
> is the anti-freeze, the late pass is the freshness. **Removing either is a
> regression** and the source says so.
>
> ### Evidence
>
> TDD, red first, both parts. **Part B's red was behavioural, not a compile
> error — the pin waited its full 5.031s timeout and the widget was never
> written**, which is #145's core property reproduced in a test. After the fix:
> **0.017s.** Suite **1471/1471**, zero failures, count moved 1469 → 1471.
>
> **Two guards so the pins cannot pass for the wrong reason:** a unique UUID marker
> (`SharedWidgetDataStore` is real app-group `UserDefaults` shared process-wide, so
> "something got written" would pass on another test's write — #183's shape), and a
> `fetchCallCount > 0` assertion so a build where the fetch returns instantly fails
> loudly instead of proving nothing.
>
> ### PART A BUILT 2026-08-02 — and it corrects this item's own numbers
>
> **The chat plane was worse than the investigation recorded.** That block says
> `URLSession.shared`'s 60s request default. **It is not 60s:
> `SessionsHermesClient.makeRequest` stamped `timeoutInterval = 300` on EVERY
> request** — five minutes each, over `.shared`'s **7-day** resource ceiling.
> (#151's entry had this right in July; #145's did not, and the two were never
> reconciled.) So the "8+ minutes per activation" estimate above understates it:
> eight serial calls at 300s is **most of an hour.**
>
> | path | budget | why |
> |---|---|---|
> | streaming (`text/event-stream`) | **300s** | for a stream this is an **idle gap**, not a total duration — bounds a *silent* stream without capping a long one |
> | interactive (everything else) | **20s** | a user is watching, and eight run serially |
> | unknown `Accept` | **20s** | **fail safe, not fail open** — a call site that forgets the header gets bounded, not silently granted the streaming allowance |
>
> **Resource ceiling: one hour, not seven days.** That is the knob that made a
> wedge effectively permanent.
>
> **The split keys off the `Accept` header — a distinction the code ALREADY
> makes** (`text/event-stream` on the two streaming call sites,
> `application/json` on the other four), rather than new plumbing that could
> drift out of sync with the call sites it describes.
>
> **This is what makes Part C sufficient.** Part C's deadline is only tested
> between attempts, so without a bounded call one hung fetch outlived it.
>
> **Deliberately NOT `RelayAPIClient.makeBootstrapProbeSession()`** — its own
> comment says it must never serve the chat path or SSE streams, and its 10s
> resource timeout would break exactly the runs Part A preserves.
>
> **Discipline note:** the pins were written before the implementation but **run
> after it**, so they passed on first execution. That is weaker than a watched
> red-then-green and is recorded as such rather than presented as clean TDD.
>
> ### STILL OWED — do not read this as "#145 fixed"
> - ~~**Part D — activations must not stack.**~~ **BUILT 2026-08-02.** Activations
>   now supersede: cancel the in-flight chain, **await its unwinding** (following
>   `cancelBackgroundBootstrap`'s precedent — without the wait, teardown overlaps
>   the new chain's start and both are briefly live, which is the very thing being
>   fixed), then run. **The wait is bounded BECAUSE OF PART A** — an interactive
>   call is 20s now, not 300s.
>   **Swift cancellation is COOPERATIVE**, so `Task.isCancelled` guards sit between
>   the network steps; without them a superseded chain keeps walking its remaining
>   eight awaits and the supersede is **cosmetic** — the counter reads right while
>   the wedge keeps running. The trailing UI writes are deliberately unguarded
>   (local, idempotent, and a chain that got that far may as well publish).
>   **Pin is PEAK CONCURRENCY, not a call count:** both activations legitimately
>   touch the host, so a count rises whether they superseded or stacked — it moves
>   for the right and wrong reasons equally, which measures nothing.
> - **Part E — SPLIT, and only half of it is tabled.** Owen asked 2026-08-02
>   whether E gets addressed or permanently tabled. **The honest answer is that
>   the spec bundled two different changes under one letter:**
>   - **(a) ONE SHARED DEADLINE around the whole chain — ✅ BUILT 2026-08-02.**
>     It needed **no dependency map**, because nothing is reordered; only the
>     total is capped. **`foregroundActivationBudget` = 45s** (harness-visible),
>     with **`foregroundActivationsCutShort`** counting every cut — *a silent
>     cut is indistinguishable from a fast success*, and that counter is what
>     tells them apart in the field and in §F5.
>     **Cancellation, not a race:** the deadline cancels **Part D's existing
>     activation `Task`**, whose per-step `if Task.isCancelled` guards are what
>     make a cancel actually stop work — so E(a) rides machinery already built
>     and tested rather than inventing one. Racing `task.value` in a `TaskGroup`
>     was rejected outright: a non-throwing `Task<Void, Never>.value` cannot be
>     timeout-raced without stranding the loser's waiter.
>     **45s is generous on purpose.** A deadline that fired on healthy-but-slow
>     refreshes would silently truncate real work — a worse and far less visible
>     bug than the slow chain it replaces. Pinned from both sides: one test
>     proves it FIRES against a dead dependency, one proves it does NOT fire on
>     a healthy run.
>     **RED witnessed behaviourally:** with only the `task.cancel()` disabled,
>     the suite reported **79 tests, 1 failure** — the deadline test burned its
>     full poll without settling (the chain really never returns) while the
>     healthy-path test and the other 77 stayed green. *(The first attempt at
>     that RED used an `-only-testing` NAME filter and reported
>     `Test run with 0 tests … TEST SUCCEEDED` — matched nothing, proved
>     nothing. Second time this session. **Filter at SUITE level and read the
>     count before the marker.**)*
>   - **(b) PARALLELISE the twelve awaits — TABLED, behind triggers.**
>     **Part A destroyed its value proposition.** E was written when a call cost
>     **300s**, so parallelising 12 × 300s was worth real risk. With calls bounded
>     at 20s the worst case is ~160s plus N×20s for dormant profiles — and the app
>     is **responsive throughout** (Part B painted first, Part D prevents pile-up).
>     **Trading a diagnosable slow refresh for undiagnosable intermittent
>     foreground auth failures is a bad trade at that size.**
>   - **Triggers that should REOPEN (b):** the device pass shows the refresh
>     window is genuinely painful, **or** the profile count grows until
>     `refreshDormantProfileTokensIfNeeded`'s serial N-loop
>     (`AppContainer.swift:2497`, still serial) dominates the chain.
>   - **Do not reopen (b) on the grounds that "E was never finished."** It was
>     evaluated and priced, and the price changed because Part A landed.
> - **DEVICE PASS — none of this is provable in the simulator.** The check is
>   Owen's original scenario: enter the app during a host outage, confirm it stays
>   responsive, and confirm it recovers on its own **without a phone restart**.
>   Staging an outage on OJAMD is out of scope.
>
> **Also spotted, NOT fixed, out of this lane's scope:** `ChatStore.swift:1549`
> carries `maxPollAttempts = 30 // 30 × 2s = 60 seconds max` — **the same
> attempt-counter-with-an-unbounded-call shape as Part C.** Likely the same defect.
> Filed here rather than fixed silently, because a drive-by change to a second
> polling loop is how a scoped lane becomes an unreviewable one.

**FIX SPEC WRITTEN 2026-07-24: `dispatch/OPUS-T27-145-foreground-deadlines.md`** — five parts, independently revertable. A: dedicated timeouts on the chat plane (streaming path MUST be distinguished from polling, or live SSE runs get killed). B: UI-state writes moved out from behind the network chain — highest value, this is what makes it outlive the outage. C: reconcile loop budget bounded by wall clock, not attempt count. D: activations supersede rather than stack. E: parallelisation, OPTIONAL and explicitly risky — skip unless the dependency map is certain. Verification is injected-hanging-client only; staging an outage is out of scope. Do not re-spec.

**Spec written 2026-07-24: `dispatch/OPUS-T27-145-147-outage-spike.md`** — INVESTIGATION lane, not a fix lane; a PR is a possible outcome, not the deliverable. Carries the correction that dropping OPEN_ITEMS #126 did NOT remove GitHub PR #126's code, so #147's prime suspect is still in the app. Do not re-spec.

**⚠️ DELIBERATELY EXCLUDED FROM THE 2026-07-24/25 BUILD WEEKEND (Owen).** Not forgotten, not
deprioritised by accident — an explicit call. Reason: **unreproduced since 2026-07-20**, and what
it needs is an INVESTIGATION lane (like #58's spike) rather than a fix lane. Specced work for that
weekend is Bundle B (`dispatch/OPUS-T27-BUNDLE-B-146-174-175-154.md`), #164 and the #58 spike; this
is named in Bundle B's out-of-scope section so it does not get picked up mid-lane.

**Standing caution for whoever does pick it up:** #146 and #147 were found in the SAME test and
share the push surface, so a push-path change can wander into this without meaning to. Keep them
apart deliberately.

**What it would need to become dispatchable:** a reproduction, or a decision to chase it from logs
rather than repro. The discriminators already listed below are still the right first questions.

**Observed 2026-07-20 (Owen, whoGoesThere, seed b3 presumed — pre-b4-update).** Owen opened
the app while `hermes update` was running on OJAMD (gateway `:8642` down/bouncing — the
user-process plane; relay/shim state during the window unrecorded). The app LOCKED UP, did
NOT recover after OJAMD came back, and a PHONE RESTART was needed to restore it.

**Why this is its own item and not #136:** it is the INVERSE outage shape. #136’s verified
pass was relay+shim black-holed with the GATEWAY ALIVE (cold launch → instant, chat worked).
This event is the gateway down with the rest (presumably) alive — and the entry was almost
certainly a FOREGROUND/resume, not a cold launch. PR #122 moved `initialize()` off the splash
critical path; the foreground-activation and chat-plane refresh paths (session sync/poll,
`handleAppDidBecomeActive`-driven work, any gateway-bound await reachable from UI) were not
in its scope. With the Windows-firewall black-hole (#136 part 1: DROP, not REFUSE — every
request eats the full ~60s URLSession timeout), serial gateway calls on a UI-blocking path
would stack into exactly this.

**Severity:** launch-blocking family. The freemium contract (#136) says degraded is the
DEFAULT posture — a wedge that outlives the outage and defeats app relaunch (if it did;
see discriminators) violates it categorically.

**Discriminators owed:**
- (a) Cold launch vs foreground entry — Owen: was the app already running in the background?
- (b) Did a plain force-quit + relaunch get tried before the phone restart, and did it fail?
  (A wedge that survives relaunch points at something persisted/system-side — e.g. a poisoned
  cache read on the launch path, or a system-level stall — vs a merely hung process.)
- (c) Which screen froze, and was it full input-freeze or stuck-but-scrollable?
- (d) Repro under instrumentation: next Hermes-update window (or a deliberate gateway stop on
  OJAMD), foreground the app with Console attached; if it hangs, grab a spindump / the iOS
  hang report (Settings → Privacy → Analytics) — the stack names the blocking call directly.
  Synergy note: the P-3 MetricKit subscriber (MXHangDiagnostic) would capture exactly this
  class of event in the field — this item is an argument for building P-3 sooner.

**Fix shape (pending discriminators):** extend the #136 non-negotiables to the foreground
path — no gateway/relay/shim call may block UI-reachable work; foreground refresh becomes the
same detached-background-upgrade posture as launch; the 5s bootstrap-probe URLSession config
extends to the chat-plane sync calls. Cross-refs: #136 (✅ stands — its DoD was the launch
path and it passed), #139 (separate defect family; different plane).

**Timing datum (2026-07-20 late, OJAMD sibling session):** gateway cold-start plus a
~55k-token context measured ~21s to first token on a fresh session; tonight's outage
window ran roughly 21:14 restart + warmup. Baseline for discriminator (d): a
healthy-but-cold gateway alone can legitimately eat ~20s+ — the wedge threshold must be
judged against cold-start latency, not warm-path latency, or a slow-but-alive gateway
gets misread as the hang.

**INVESTIGATION 2026-07-24 (source read, no device) — NAMED BLOCKING PATH. The spec's
hypothesis is CONFIRMED, and the launch-path half of it is DISPROVED.**

**(1) The chat/session plane has NO timeout configuration at all.** Every service client
defaults to `URLSession.shared` — `SessionsHermesClient` (gateway `:8642`),
`ModelsShimClient` (`:8765`), `CronJobService`, `SkillsService`, `InsightsService`. That is
**60s `timeoutIntervalForRequest` and 7 DAYS `timeoutIntervalForResource`**. The only
dedicated timeout in the app is `RelayAPIClient.bootstrapProbeRequestTimeout` (5s/10s,
`RelayAPIClient.swift:132-143`) and it is scoped to the #136 bootstrap probe alone. So the
answer to #151's question is: the 5s config exists and is used in exactly one place; the
chat plane never got it.

**(2) `handleAppDidBecomeActive()` (`AppContainer.swift:1324-1357`) is the blocking path —
TWELVE strictly serial awaits, ~8 of them network-bound, with no deadline, no concurrency,
no cancellation.** In order: `currentAccessToken` (Keychain) → `reloadCapabilities` →
**`hostStore.refresh`** → **`refreshCommandCatalog(force:)`** → **`seedActiveModelFromShim`**
→ **`registerStoredPushTokenIfNeeded`** → **`sensorUploadService.handleAppDidBecomeActive`**
→ `talkStore.refreshReadiness` → **`chatStore.reconcilePendingRuns`** →
`condensePendingReasoning` → **`refreshDormantProfileTokensIfNeeded`** →
**`reportAppStateIfNeeded`**. No `async let`, no task group, no shared deadline. Under the
#136 black-hole shape (DROP, full 60s per request) one foreground activation costs **8+
minutes** — and `refreshDormantProfileTokensIfNeeded` (`:2348-2360`) is itself a serial
`for` loop over dormant profiles, adding N×60s inside that chain. This is the spec's
question 3 answered: **the calls are serial, not concurrent-with-shared-deadline.**

**(3) Why it outlives the outage — three compounding reasons, this is the load-bearing part:**
  - **Every UI-state write is sequenced LAST.** `reconcileLiveActivities()` and
    `updateWidgetData()` are lines 1354/1356, behind all eight network awaits. The app
    cannot refresh its visible state until the entire chain drains — so it stays frozen on
    stale content for minutes *after* the host is healthy again.
  - **The reconcile loop's documented budget is wrong by ~30×.**
    `ChatStore.startReconcileLoopIfNeeded()` (`ChatStore.swift:1450-1464`) says
    `maxAttempts = 60 // 60 x 2s = ~2 min` — but that budgets only `Task.sleep`, **not the
    network call**. Each `attemptReconcile` → `reconcileFromServer()` is an unbounded
    gateway fetch, so on a black-holed host the real ceiling is 60 × (2s + 60s) ≈ **62
    minutes**, not 2. The loop is armed at step 9 of the chain above and keeps grinding long
    after the outage ends.
  - **Every scene activation queues another full chain.** Background→foreground cycles stack
    them; nothing coalesces or supersedes.

**(4) DISPROVED — the launch critical path is clean; #136 stands.** The spec (and this
item's own fix-shape note) suspected a gateway-bound await on the launch path. It is not
there. Traced every step of `initialize()` (`:1174-1210`): `currentAccessToken()` is a pure
Keychain read (`AppSessionStore.swift:133-135`), and `loadConversationIfNeeded()`'s
"no-cache fallback fetch" is **stale documentation** — both backends' `loadConversation()`
are purely local (`SessionsHermesClient.swift:448-453` returns in-memory-or-fresh;
`LocalChatBackend.swift:513-519` restores from cache). The `LaunchInitStep` doc comment
claiming that fallback "rides the chat path" describes the retired relay-backed
`LiveHermesClient`, not current code. **So #145 is a FOREGROUND-path defect, not a launch
defect** — consistent with the original observation that entry was a resume, not a cold
launch.

**(5) The #136 guard test is a tautology.** `AppStoresTests.swift:2751-2752` iterates
`LaunchInitStep.criticalPath` asserting `!step.touchesNetwork` — but `touchesNetwork` is a
hand-maintained switch in the *same enum*. It asserts the label against itself, never
against what `initialize()` actually calls, and it does not model the foreground path at
all. It would not have caught (2), and will not catch a future network call added to
`initialize()`.

**Honest limit — what this does NOT explain:** a true input freeze. Serial `await`s on the
MainActor suspend and yield; they do not block the main thread. This mechanism fully
explains "wedged, stale, unresponsive-looking, and still broken after the host returned",
but a literal frozen-touch UI needing a phone restart needs a spindump or an
`MXHangDiagnostic` to confirm. Treat the "hard-lock" wording as unverified until then;
discriminator (c) is still owed.

**Fix shape (unchanged in spirit, now specific):** give the chat/session plane the dedicated
short-timeout `URLSessionConfiguration` that `RelayAPIClient` already has; hoist
`reconcileLiveActivities()`/`updateWidgetData()` to the FRONT of
`handleAppDidBecomeActive`; run the independent refreshes concurrently under one shared
deadline instead of twelve serial awaits; make the reconcile loop budget wall-clock rather
than sleep-count; and make the foreground chain supersede-on-re-entry the way
`cancelBackgroundBootstrap()` does. **Owed a device pass** — none of this is provable in
the simulator.

Logged 2026-07-20.

## 146. ✅ Diagnostics push row stuck on TOKEN HELD · AWAITING RELAY — CONFIRMED display desync 2026-07-20 (push delivered while row stuck); fix = kill the dual bookkeeping

> **CLOSED — header flipped 2026-08-01 (Hermes audit Part 1A).** Bundle B Part A fixed on merged PR #144 — `pushTokenRegistered` is derived. Device check queued as device-list §F1.

> **Device debt queued 2026-08-01 (Hermes audit Part 1C):** the owed device check for
> this item now lives in `dispatch/DEVICE-PASS-RUNNING-LIST.md` **§F1**, written as a
> runnable check. **One queue** — do not restate it here; a check that lives in two
> places drifts, and a check that lives only in a closed-looking item is not recorded.

**Spec written 2026-07-24: `dispatch/OPUS-T27-BUNDLE-B-146-174-175-154.md`** (bundled with #174, #175, #154 — PART A, fix shape known). Do not re-spec; check merge state before sending.

**2026-07-24 — FIXED on `claude/t27-bundle-b-hygiene` (PART A, preferred fix taken).** The parallel Bool is dead: `AppSessionState.pushTokenRegistered` is now DERIVED (`registeredPushToken != nil`) and the token string is the only stored record. `pushTokenPipelineState` became a COMPARISON — the token iOS handed us against the token the relay acked — via a new pure `AppContainer.pushTokenPipelineState(heldToken:recordedToken:)`. Two records of one fact cannot drift when there is one record.

**Took the preferred fix, not the minimum,** because asserting the Bool in one more place leaves the shape intact — and the shape had already produced a SECOND defect nobody had named: a rotated APNs token kept reading `registered` off a stale ack, which is the opposite lie from the observed one and would have suppressed a needed re-registration. The comparison fixes both.

**Found while doing it — the divergence had an in-tree cause.** `AppSessionStore.loadAndApplySessionState` builds a FRESH `AppSessionState` from `/session` and only merged the Bool, so every reload WIPED `registeredPushToken`. The two fields diverged by construction, not by an exotic ordering race. The merge now carries the record.

**One bridge was needed:** `/session` reports `push.tokenRegistered` as a Bool and never says WHICH token the relay holds. `LiveSessionBootstrapService` resolves it against the locally cached APNs token — it is registered against THIS device, so that is the token it holds; nil when we hold none, which is the honest reading.

**Migration: none needed.** Pre-fix blobs carry only the Bool, decode as unregistered, and the next foreground's `registerPushTokenIfNeeded` re-registers and records the token. Self-healing in one launch. Asserted in `PushRegistrationRecordTests`.

**Device check still owed** — and per the spec, a device check that still sees the push arrive ×4 has NOT falsified this: that count is #143, relay-side. What to look for is the Diagnostics row reading REGISTERED while a push delivers, and (the new case) the row dropping to AWAITING RELAY after an APNs token rotation instead of sitting on a stale `registered`.

**2026-07-23 — the ×4 delivery count belongs to #143, not to this defect.** This item records the
push arriving ×4 while the diagnostics row sat stuck. That multiplicity is a separate bug: OJAMD's
relay holds ONE APNs token against five device rows, four still active, and
`active_push_registrations_for_user` does not dedup by token — four rows, four sends.
**Fixing this item's dual bookkeeping will NOT reduce the count.** Kept separate deliberately so
neither fix gets judged by the other's symptom.

**CONFIRMED 2026-07-20 late — hypothesis (a), discriminator 1.** OJAMD’s agent sent an
inbox item via hermes_mobile; the push DELIVERED (×4, screenshot on file) while the
Diagnostics row still read AWAITING RELAY. Registration is live server-side; the row lies.
Dispatchable micro-fix per the fix shape below: the skip path asserts the boolean (a skip IS
a confirmation), or preferably the UI derives from the recorded token and the parallel bool
dies. Hypothesis (b) is dead for the current state. Rider observed in the same test: tapping
the notification crashes the app → #147.

**Observed 2026-07-20 late (Owen, OJAMD profile active, post-Hermes-0.19 update window).**
Diagnostics (and presumably Notifications settings — same source of truth) shows the push
pipeline stuck at TOKEN HELD · AWAITING RELAY. Earlier the same evening push demonstrably
worked against OJAMD (#143’s ×5 deliveries), so something changed tonight.

**Source-read (2026-07-20):** both screens render `AppContainer.pushTokenPipelineState`,
which reads a BOOLEAN — `sessionStore.state.pushTokenRegistered` (AppContainer.swift:1527).
The #133 fix (PR #123) introduced a SECOND bookkeeping surface: per-profile
`registeredPushToken` (token STRING on AppSessionState) consulted by the skip-on-exact-match
policy. Two records of one fact.

**Hypothesis (a) — #133 regression, specific mechanism:** a launch that restores a MATCHING
recorded token skips the POST by design — but if the boolean is false at that point (state
restoration ordering, a deactivate that cleared the bool but not the mark, or any path where
the two fields diverge), the UI shows AWAITING RELAY indefinitely and the skip guarantees no
future POST ever sets it true. Fix shape if confirmed: the skip path must ALSO assert the
boolean (a skip IS a confirmation — the recorded ack is why we skipped), or better, derive
the UI state from the recorded token instead of the parallel bool (kill the dual
bookkeeping).

**Hypothesis (b) — truthful failure:** post-0.19 + tonight’s service bouncing, registration
may be genuinely failing (markPushTokenRegistered(false) on POST failure is the honest
path). The same evening’s #145 window makes host-side flux entirely plausible.

**Discriminators (fastest first):**
1. Trigger any push from OJAMD (agent inbox item) — ARRIVAL while the row reads AWAITING =
   display bug, hypothesis (a) confirmed in one move.
2. Launch Console filter `registerPushToken` — an “accepted” line (or a skip with no
   failure) alongside the stuck row = (a); repeated failure lines = (b), go look at the
   OJAMD relay.
3. Note for the #133 device pass: post-fix, a healthy launch may legitimately show ZERO
   registration lines (skip working as designed) — update that pass’s expectation from
   “at most one per profile” to “at most one per profile, possibly none”.

Cross-refs: #133 (the fix under suspicion — its device pass and this item should run in the
same Console session), #143/#144 (same notification plane), #145 (same host-flux evening).

Logged 2026-07-20.

## 147. 🐛 Tapping an inbox-alert notification CRASHES the app — **⚰️ MOOT 2026-08-04 (goal-run sweep, under Owen's standing "disregard obsolete/moot items"): #238 deleted the ENTIRE system-notification surface — the `UNUserNotificationCenter` delegate this crash lived in no longer exists, and notifications, if ever reintroduced, are in-app surfaces only (permanent cut). The device check in DEVICE-PASS-RUNNING-LIST §F1 is likewise moot. Reopen only if an in-app alert TAP-THROUGH surface is built and crashes — which would be a NEW item against new code, not this one.** — (was: REOPENED 2026-07-25; the 2026-07-21 fix has been inert since it merged)

> **Device debt queued 2026-08-01 (Hermes audit Part 1C):** the owed device check for
> this item now lives in `dispatch/DEVICE-PASS-RUNNING-LIST.md` **§F1**, written as a
> runnable check. **One queue** — do not restate it here; a check that lives in two
> places drifts, and a check that lives only in a closed-looking item is not recorded.

> **FIX ON BRANCH 2026-07-27** (`claude/opus-t27-notifications-e2e-upxqau`, with #189). The
> `nonisolated` on the async `didReceive` overload is removed, so it actually inherits the
> class-level `@MainActor` that `22f92e1` added — the annotation had opted the method back out,
> which is why the 2026-07-21 "fix" was inert. The `nonisolated` appears carried over from
> `willPresent`, which genuinely takes a completion handler; `willPresent` stays `nonisolated`
> deliberately (sync handler, invoked synchronously, no actor-crossing state — and a sync
> nonisolated requirement cannot be witnessed by a `@MainActor` method anyway). The #47
> process-lifetime guarantee is untouched: it comes from the system AWAITING the async variant,
> independent of which actor the body runs on. The crash itself is not unit-testable —
> **closes only on Owen's on-device cold-launch tap** (the mis-verified case last time), warm tap,
> and a #47 headless typed reply; repro on demand via `mcp__hermes_mobile__send_inbox_item`.

> **REOPENED 2026-07-25 (device pass + ultrareview).** The "device-verified closed
> 2026-07-21" entry below is wrong. The crash reproduced deterministically on
> 2026-07-25 across multiple independent Claude Code test runs, on a build
> containing the fix.
>
> **The fix never applied.** `22f92e1` annotated the *class* `HermesAppDelegate`
> `@MainActor`. Both `userNotificationCenter` overloads are declared `nonisolated`
> (`AppEntry.swift:124` and `:141`), which opts them back out of class-level
> isolation. Dated: the `nonisolated` annotations landed in `937e110`
> (2026-06-29) and `a2a1d88` (2026-07-05), weeks *before* the fix, and nothing has
> touched the delegate since — the only later commit to `AppEntry.swift` is
> `a62503f`, which added `consumePendingControlDestination` (+32 lines, delegate
> untouched). The `@MainActor` has been inert from the moment it merged.
>
> **Process note.** This was closed on a merge commit plus one device observation
> that most likely caught the #145 wedge (the unbounded `openSession` await)
> rather than a fixed crash — a hang never reaches the completion bridge, so the
> crash cannot fire. That reading is not required to reopen; the determinism above
> settles it.
>
> **The real fix is a design call, not a one-liner.** Removing or narrowing
> `nonisolated` must preserve the #47 process-lifetime guarantee protected by the
> comment at `AppEntry.swift:137–140`. Do NOT write a lane from "annotate the
> delegate `@MainActor`" — that change is already in the crashing build.

**Spec written 2026-07-24: `dispatch/OPUS-T27-145-147-outage-spike.md`** — INVESTIGATION lane, not a fix lane; a PR is a possible outcome, not the deliverable. Carries the correction that dropping OPEN_ITEMS #126 did NOT remove GitHub PR #126's code, so #147's prime suspect is still in the app. Do not re-spec.

**⚠️ DELIBERATELY EXCLUDED FROM THE 2026-07-24/25 BUILD WEEKEND (Owen).** Not forgotten, not
deprioritised by accident — an explicit call. Reason: **unreproduced since 2026-07-20**, and what
it needs is an INVESTIGATION lane (like #58's spike) rather than a fix lane. Specced work for that
weekend is Bundle B (`dispatch/OPUS-T27-BUNDLE-B-146-174-175-154.md`), #164 and the #58 spike; this
is named in Bundle B's out-of-scope section so it does not get picked up mid-lane.

**Standing caution for whoever does pick it up:** #146 and #147 were found in the SAME test and
share the push surface, so a push-path change can wander into this without meaning to. Keep them
apart deliberately.

**What it would need to become dispatchable:** a reproduction, or a decision to chase it from logs
rather than repro. The discriminators already listed below are still the right first questions.

**Observed 2026-07-20 late (Owen, whoGoesThere):** Hermes inbox-item push delivered (see
#146/#143); tapping a notification to open it crashes the app. Multiple identical
notifications remain on the lock screen — live repro material.

**Prime suspect — recency:** PR #126 (merged TODAY, merge edeba74) touched exactly this
surface: inbox-alert notification handling, with the documented scope cut that inbox alert
pushes carry NO identifying userInfo and tap deliberately routes to chat. A tap handler
change that shipped hours before taps started crashing is the first place to look. Second
suspect: notification-response handling colliding with tonight’s host-flux state (#145
evening) — but a crash (not a hang) points app-side.

**Discriminators:**
1. **Crash log — the whole answer:** Settings → Privacy & Security → Analytics &
   Improvements → Analytics Data → tonight’s Talaria27 .ips entries (the #145 hang check
   covers the same screen — grab both while there). AirDrop to the Mac; the crashing frame
   names the fix.
2. Cold vs warm: does the tap crash when the app is already running, freshly launched by the
   tap, or both? (Remaining lock-screen notifications = controlled repro.)
3. Does tapping the inbox ROW inside the app (vs the system notification) also crash? Splits
   notification-response handling from inbox-detail rendering.

Cross-refs: #126 (suspect PR — its device pass inherits this), #146 (found in the same
test), #143 (same delivery).

**CONTROLLED REPRO 2026-07-21 (Owen + Claude):** fresh single inbox alert sent via OJAMD
Hermes (`mcp__hermes_mobile__send_inbox_item`, notify:alert, item 166e88c2…). Tap from
UNLOCKED home screen, app killed first: launch zoom → BLACK first frame → dead, back to
home. So: cold-launch-via-notification crash at/before first render; NOT lock-screen
protected-data race (device unlocked); NOT the #145 wedge (instant exit, no freeze).
Source-read state (same night): PR #126's app diff did NOT touch the notification-response
path (only widget deep-link + Route.briefing + BriefingDetailScreen + markRead); the
didReceive handler is defensive (`userInfo["session_id"] as? String`, nil-tolerant),
`sharedDefault()` returns a static container, `handleNotificationTap` guards on isPaired —
no obvious trap on the handler itself. Suspicion shifts to what's UNIQUE about
notification-launch vs icon-launch: response delivery/scene-connection options during the
launch window, or the push payload shape from the #126 HOST half (relay/agent side — was
a category/userInfo field added that the launch path chokes on?). Console capture of tap #2
attempted (transfer failed — resend); fresh .ips from tap #1 owed from Analytics Data —
that frame names the fix.

**VERDICT 2026-07-21 (.ips Talaria_27-2026-07-21-191840, tap #2):** uncaught
NSInternalInconsistencyException → SIGABRT on thread 7 (cooperative pool). Chain:
`HermesAppDelegate.userNotificationCenter(_:didReceive:)` is async but NOT main-actor
isolated → compiler-synthesized objc completion bridge fires on the cooperative executor
→ UIKit's completion path runs snapshot/state-restoration
(`_updateSnapshotAndStateRestoration…` → `_performBlockAfterCATransactionCommitSynchronizes:`)
which hard-asserts main thread. Main thread confirmed healthy at crash (keyboard-scene
launch work). Cold-launch-only because warm taps skip the restoration path; #47 reply is
headless. PR #126 EXONERATED (exposure timing only: cold taps on inbox pushes first became
reachable when #143 delivery started working, same night). FIX: `@MainActor` on
`HermesAppDelegate` (class-level — covers every synthesized completion bridge). Branch
`claude/t27-147-mainactor-delegate`; build gate in flight; DoD = Owen cold-tap opens clean
(repro on demand via `mcp__hermes_mobile__send_inbox_item`).

**DEVICE VERIFY 2026-07-21 late — CRASH PORTION CLOSED, remainder folds into #145.**
PR #129 on device: cold tap no longer crashes (fresh controlled push, item 66feaf42…).
NEW behavior exposed: launch proceeds to the Talaria splash (bare — no locked/connecting
sublabel) and WEDGES; backgrounding no-op; force-quit + relaunch wedges again; only a
REINSTALL clears it (Owen waited ~1 min on the first occurrence, then rebuilt). So the
wedging state is PERSISTED IN THE APP CONTAINER (reinstall clears, Keychain survives →
not Keychain), written during notification-tap handling. Suspect surface: what
`handleNotificationTap` touches — `reconcilePendingRuns()` and inbox local state — leaving
a record the launch path re-hits before `isInitialized` on every subsequent launch.
This is #145's family with sharper evidence than #145's own repro (there: outage-entry,
phone restart; here: tap-created, container-persisted, on-demand reproducible). Remaining
work tracked in #145: source-read reconcilePendingRuns + pending-run persistence vs the
#136 LaunchInitStep critical path; extend timeout non-negotiables to the tap/foreground
path; and the persistence bug (nothing written on the tap path may wedge future launches).

**INVESTIGATION 2026-07-24 — the owed source-read is DONE. Crash portion re-confirmed
closed; the "container-persisted wedge" theory is DISPROVED as stated.**

**Spec-premise correction for anyone reading `dispatch/OPUS-T27-145-147-outage-spike.md` (or
its `-147-145-outage-investigation.md` twin): both are STALE on this item.** They instruct
"get the crash log before theorising" and name PR #126 as prime suspect. That work was
already done on 2026-07-21: `.ips Talaria_27-2026-07-21-191840` named the frame, PR #126 was
EXONERATED, the `@MainActor` fix shipped as PR #129 (merge `20b46fc`, in main — verified live
at `AppEntry.swift:87`), and the device pass closed the crash. The three ranked candidates
the spec asks for (userInfo force-unwrap / `InboxStore.markRead` / `briefing` deeplink
nil-id) are all moot — none was the cause. **Do not re-run Part 1 of that spec.**

**`reconcilePendingRuns` is NOT the persistence culprit.** `pendingRun` is
`private var pendingRun: PendingRun?` (`ChatStore.swift:202`) — in-memory only, never
written to the container by any code path. On a cold launch it is nil, so
`reconcilePendingRuns()` returns at its first guard (`:1443-1448`). **Nothing on the tap
path persists a record that could re-poison a subsequent launch**, so "only a reinstall
clears it" needs a different explanation than a poisoned pending-run.

**The likelier reading of the same evidence:** the tap path makes an *unbounded* gateway
call, not a persistent one. `handleNotificationTap` (`AppContainer.swift:1443-1452`) awaits
`chatStore.openSession(sessionID)` → `SessionsHermesClient.openSession` on
`URLSession.shared` — **60s request / 7-day resource, no timeout config anywhere on the chat
plane** — then `reconcilePendingRuns()`, which arms a retry loop whose documented "~2 min"
ceiling is really ~62 min against a black-holed host (full derivation in #145). Owen waited
**~1 min** on the first occurrence before rebuilding — that is right at the 60s URLSession
boundary, so "force-quit + relaunch wedges again; only a reinstall clears it" is equally
consistent with **a ~60s-per-launch stall against a host that was still down**, where the
rebuild+reinstall cycle simply outlasted the outage. Reinstall also wipes the UserDefaults
pairing flag, which drops the `isPaired && !isInitialized` splash branch entirely — a second
reason reinstall "fixes" it without any persisted poison existing.

**Consequence:** the remaining work genuinely is #145's, but as a *timeout/serialisation*
defect on the tap + foreground paths, not a persistence bug. The "nothing written on the tap
path may wedge future launches" line above is retained for history but is not supported by
the source. **Owed to settle it definitively:** re-run the controlled repro
(`send_inbox_item`, cold tap) with the gateway deliberately black-holed, and let it sit 3+
minutes without rebuilding — if it self-clears, the wedge is the timeout chain and this item
needs no further work of its own.

Logged 2026-07-20.

## 151. ✅ Settings → Hermes Host: "Test Connection" gives NO pass/fail feedback — **built + merged (PR #146, 2026-07-24); ALL THREE device shapes ✅ 2026-08-02**

> **CLOSED — device pass 2026-08-02 (running list §F1 + §F5): live host → verdict with
> latency (29ms); dead port on a live host → REFUSED, fast; black-holed tailnet IP →
> NO ANSWER at ~5s (the case that used to hang five minutes).** All three honest
> verdicts verified on hardware.

> **⚠️ ROUTING CORRECTED 2026-08-01 — the note below was WRONG, and it was mine.**
> It said this item's owed work is "NOT a device check" and sent it to §G pending a
> source-confirm. **That confirm was already done 2026-07-24 and the fix merged as
> PR #146** — verified in the tree, not from this file: `probeTimeout = 5`, a
> dedicated probe deliberately off the shared 300s client path, `testState` bound to
> the UI, and **REFUSED / NO ANSWER / NO HOST** at `UplinkSettingsScreen.swift:38-40`.
> **What is left IS a device check**, and it is now in the queue as
> **§F1** (live host) and **§F5** (stopped, black-holed). Carry it into a sitting.
>
> **How it went wrong:** §G was written from this entry's *"Source-confirm owed (next
> Mac shell)"* line — true when logged 2026-07-20, dead four days later — while the
> answer sat in a **later paragraph of this same entry**. Read the whole item, not
> its oldest line.

> ~~**Routed out of the device queue 2026-08-01 (Hermes audit Part 1C):** this item's owed
> work is NOT a device check — see `dispatch/DEVICE-PASS-RUNNING-LIST.md` §G for what it
> actually needs. Do not carry it into a device sitting.~~ *(struck 2026-08-01, same day, see above)*

**Spec written 2026-07-24: `dispatch/OPUS-T27-SETTINGS-151-152-153.md`** — PHASE 0 CONFIRM IS MANDATORY (all three carry source-confirm-owed; Bundle B had 2 of 4 premises wrong). #153 is gated: if hosts are a single record it is a data-model lane and gets split out. Do not re-spec.

**2026-07-24 — DONE on `claude/t27-settings-host-surface`. Premise CONFIRMED, and the timing assumption in this item was wrong in the dangerous direction.** `UplinkSettingsScreen.testConnection()` did probe — `hostStore.refresh()` (relay plane) plus `chatStore.refreshDirectHealth()` (chat plane) — and read neither result. Precise correction to "no visible result": the link panel at the TOP of the screen does recompute from those probes, but the button is at the bottom, there is no acknowledgement, no latency, no reason, and `hostStore.lastErrorMessage` is never rendered on this screen at all.

**The 60s in this item's fix shape was optimistic.** `SessionsHermesClient.makeRequest` stamps `request.timeoutInterval = 300` on EVERY request, including the `/v1/models` health call `refreshDirectHealth()` rides. A black-holed host would have hung Test Connection for **five minutes**, not 60s. The 5s dedicated probe is therefore not a nicety — the shared client path was unusable here. Built as its own probe rather than a timeout override on the shared one.

Status vocabulary reused rather than reinvented, as instructed: verdicts defer to `ServerProbeResult.classify`, so a 401 renders **NO KEY** here exactly as on the Server screen. New honest states where the family had only OFFLINE: **REFUSED** (`cannotConnectToHost` — wrong port/nothing listening), **NO ANSWER** (`timedOut` — firewall DROP or host asleep), **NO HOST** (`cannotFindHost`/`dnsLookupFailed`). Each carries a one-sentence fix. Retyping the base URL clears the verdict so a stale ONLINE can't sit under a changed endpoint.

**Owed on device (Owen's):** the three shapes — live host, stopped host, black-holed host.

Reported 2026-07-20 (Owen). Tapping Test Connection in Settings → Hermes Host produces no visible result — success, failure, and in-flight are indistinguishable. The user can't tell whether the host is reachable, which is exactly the moment the control exists to answer.

Fix shape (source-confirm before dispatch): the action almost certainly already performs a reachability probe (bootstrap/health call on the Sessions API plane, :8642); what's missing is the UI binding of its result. Wants a small state enum (idle / testing / success / failure(reason)) driving: an inline spinner while testing, then a pass row (host + latency) or a fail row with a reason (unreachable / auth rejected / wrong port), in the standardized status wording family (#84 / #71 precedent). Distinguish the three network shapes #145/#136 established (refuse fast-fail vs firewall black-hole ~60s vs accepted-but-silent warmup) — a Test button that hangs 60s silently on black-hole is its own papercut, so give it the 5s dedicated-timeout config too.

Source-confirm owed (next Mac shell): locate the Test Connection action (grep testConnection / "Test Connection" under Talaria/Features/Settings), confirm whether it already calls the probe and simply drops the result, and whether a status enum exists to reuse. Fable-dispatchable micro-lane once confirmed; pairs with #152 (same screen).

Logged 2026-07-20.

---

## 152. ✅ Settings host disconnect/revoke is buried under "Pair Device" — **RENAMED + merged (PR #146, 2026-07-24); device check ✅ 2026-08-02**

> **CLOSED — device leg passed 2026-08-02 (running list §F1):** "Pairing & Devices" lands
> on the revoke/disconnect surface with **Pair New Device (QR) on top**, so the screen is
> not destructive-only. Sim 8/8 + device pass = fully verified. Bonus from the same
> sitting: the Revoke-vs-Disconnect distinction proved live and correct — Disconnect is
> purely client-side (relay rows untouched, measured), matching its "signs this device
> out" copy.

> **⚠️ ROUTING CORRECTED 2026-08-01, and a decision withdrawn off Owen's plate.**
> §G called this "a naming decision, not a check" and the device list asked Owen to
> **pick a label**. He does not need to — **the label shipped 2026-07-24.** The row
> and the destination screen both read **"Pairing & Devices"**
> (`UplinkSettingsScreen.swift:357`, `ConnectHermesHostScreen.swift:38`), merged in
> PR #146. The decision row is withdrawn. **If Owen wants a different label that is
> now a change, not a decision.**
>
> **This was live on Owen's plate for a week and I restated it to him verbally on
> 2026-08-01 as still-outstanding.** A stale decision costs more than a stale fact:
> a fact gets re-checked when someone uses it, whereas a decision sits and blocks
> until someone answers a question that no longer exists.
>
> **What is actually left is a device check** — the renamed row reaching revoke —
> and it is now **§F1**.

> ~~**Routed out of the device queue 2026-08-01 (Hermes audit Part 1C):** this item's owed
> work is NOT a device check — see `dispatch/DEVICE-PASS-RUNNING-LIST.md` §G for what it
> actually needs. Do not carry it into a device sitting.~~ *(struck 2026-08-01, same day, see above)*

**Spec written 2026-07-24: `dispatch/OPUS-T27-SETTINGS-151-152-153.md`** — PHASE 0 CONFIRM IS MANDATORY (all three carry source-confirm-owed; Bundle B had 2 of 4 premises wrong). #153 is gated: if hosts are a single record it is a data-model lane and gets split out. Do not re-spec.

Reported 2026-07-20 (Owen). To DISCONNECT or REVOKE a host you must open Pair Device — an unpair action living behind a label that only advertises pairing. The name describes one direction of a two-direction surface (pair AND unpair/revoke/manage).

Owen's ask: better naming. Candidates, roughly in order:

"Pairing & Devices" — covers both add and remove; plain, App-Settings-idiomatic.

"Manage Pairing" / "Device Pairing" — honest that it's manage, not just add.

"Connection" / "Host Connection" — user-facing framing (they think "connect," not "pair"), but risks colliding with the #151 Test Connection language on the same screen.

"Paired Devices" — good if the screen leads with the current pairing + a revoke and tucks the QR add-flow under a button.

Recommendation: "Pairing & Devices" for the row, and inside, lead with the current host/pairing state + a clear Disconnect/Revoke, with Pair New Device (QR) as the add action — so the destructive/management actions aren't hidden behind an add-only verb. Keep the QR pairing flow itself unchanged (three-plane model intact; pairing QR still carries no Sessions API key).

**2026-07-24 — DONE on `claude/t27-settings-host-surface`. Premise CONFIRMED exactly as filed.** The "Pair Device" `GlowButton` in `UplinkSettingsScreen` routes to `.connectHost`, which while paired resolves (ContentView's route seam) to `ConnectHermesHostScreen` — whose only two actions are **Revoke Host** and **Disconnect**. An unpair behind a pairing verb, confirmed.

Row is now **"Pairing & Devices"** (Owen's recommendation) and the destination screen's title matches. Avoided "Connection"/"Host Connection" per the collision note above.

**Where revoke lived, for the record:** in two places with different scopes — `ConnectHermesHostScreen` (this screen: `hostStore.revokeCurrentHost()` + `pairingStore.disconnect()`), and per-profile **Forget Pairing** in the Server screen's card menu (`pairingStore.forgetPairing(profileID:)`). Only the former was behind the misleading label.

**Pair New Device (QR)** added as the explicit add action, so destructive actions are no longer the entire surface. It names the active profile as pair target, re-resolving the same `.connectHost` seam to the QR flow — the identical path the Server screen's per-profile Pair already uses, so **the pairing flow itself is untouched** and the QR still carries no Sessions API key. Revoke and Disconnect now each carry a one-line description, because they sit adjacent and are not the same operation.

**The rename trap, checked before renaming:** no `"Pair Device"` in any plist, `.xcstrings`, `.strings` or App Intent phrase — the only App Intent phrases in the tree belong to `StartVoiceSessionIntent`. Exactly one test bound it (`AppTemplateUITests.testDisconnectReturnsToStandaloneChat`), updated **in the same commit as the rename**. The onboarding screen's button keeps its "Pair Device" title — that test matches its `"Connect Hermes"` accessibility label, not the renamed one. UI suite green (8/8), so the renamed path is sim-verified end to end.

**Owed on device (Owen's):** the renamed surface reaching revoke.

Source-confirm owed (next Mac shell): find the row label + destination (grep "Pair Device" / "Pairing" under Talaria/Features/Settings), confirm where revoke lives today, and check Siri/Spotlight/deep-link strings or tests that hard-code "Pair Device" before renaming. Pure UX lane, no backend change; batch with #151 as one Settings-host PR.

Logged 2026-07-20.

---

## 153. ✅ Settings → Server: multi-host management — delete profile, active-host selection, list semantics — **CLOSED 2026-08-01 (header caught up to a body written 2026-07-24)**

> **✅ CLOSED 2026-08-01.** Nothing was done today to close this — **the work merged
> 2026-07-24 in PR #146 and this entry's own body has said so since.** Its last
> substantive line reads *"Still open under this number: nothing from the original
> ask."* The header stayed 🔧 for eight days and §G kept it queued as owing a
> source-confirm that had already come back.
>
> **This is the largest category the 2026-08-01 Hermes audit named** — *items whose
> fix merged but whose header never changed* — caught here by the routine act of
> going to do the work and finding it done. **Verified in the tree before flipping**,
> not taken from the body: hosts were **already an array**
> (`BackendProfile.swift:100`), so it was never a data-model lane; and
> `deleteProfile(id:)` ships with both house rules — `profileIsActive` and
> `profileIsSensorDestination` (`BackendProfilesStore.swift:35,37`).
>
> **Reverse if:** an empty-list → standalone path is ever wanted. That means allowing
> the last profile to be deleted, which is a **new decision**, not a completion of
> this one — the current design makes the last profile necessarily active, so there
> is no empty-list path to wedge.

> ~~**Routed out of the device queue 2026-08-01 (Hermes audit Part 1C):** this item's owed
> work is NOT a device check — see `dispatch/DEVICE-PASS-RUNNING-LIST.md` §G for what it
> actually needs. Do not carry it into a device sitting.~~ *(struck 2026-08-01, same day, see above)*

**Spec written 2026-07-24: `dispatch/OPUS-T27-SETTINGS-151-152-153.md`** — PHASE 0 CONFIRM IS MANDATORY (all three carry source-confirm-owed; Bundle B had 2 of 4 premises wrong). #153 is gated: if hosts are a single record it is a data-model lane and gets split out. Do not re-spec.

**2026-07-24 — PARTIALLY DONE on `claude/t27-settings-host-surface`. The premise was CONTRADICTED and the assumed fix was NOT implemented, per the spec's stop rule.** The scope gate came back the good way — hosts are **already an array** (`BackendProfilesState.profiles: [BackendProfile]`, Lane M / #114), so this was never a data-model lane. But the ask itself was already shipped:

- **Delete exists** — `BackendProfilesStore.deleteProfile(id:)`, with the active and sensor-destination house rules (`DeleteError.profileIsActive` / `.profileIsSensorDestination`).
- **Delete ≠ revoke, already** — `Forget Pairing` is a separate card action with its own confirm.
- **Active selection is already explicit** — tap a card → "Switch backend?" confirm → `setActiveProfile`.
- **Keychain purge already wired** — `AppContainer.onProfileDeleted` clears the paired relay configuration, session state, and the four profile-scoped Keychain keys (access/refresh token, gateway API key, shim token).

**Why it read as missing: discoverability.** Every per-profile action lived only under a long-press on a card that gave no sign it was long-pressable. Fixed — the same action set is now also behind a visible menu button on each card, built from one shared `@ViewBuilder` so the two entry points cannot drift.

**One genuine defect found and fixed:** delete did **not** confirm. It fired straight off the menu and purged the profile's credentials, while the strictly *less* destructive Forget Pairing did confirm. It now confirms, naming what is removed and that other profiles are untouched.

**The #137 interaction, checked explicitly as the spec demanded — already safe.** The sensor-migration stamp is stored under a separate **unscoped** key (`saveSensorStreamingMigrationStamp`, UserDefaults) and `onProfileDeleted` does not touch it, so a delete cannot cause a later re-pair to re-run the migration and switch sensors on without consent. Pinned with a regression test so it stays that way.

**Correction to this item's highest-risk path.** "Deleting the LAST host must return to standalone cleanly" is **unreachable by construction** — the last profile is necessarily active (normalization falls back to `profiles.first`), so the active-profile guard blocks it. There is no empty-list path to wedge. "Delete if there's more than one" is precisely the shipped behaviour, which means the open questions below about deleting the active/last host were already answered by the house rules, not left implicit.

**Still open under this number:** nothing from the original ask. If a real empty-list → standalone path is ever wanted, that is a new decision (it would mean allowing the last profile to be deleted), not a completion of this one.

Reported 2026-07-20 (Owen): "add a delete feature on Settings → Server as well, if there's more than one."

Why it's its own item, not just "add a button": DELETE and REVOKE are different actions and must not be conflated. Revoke (#152) severs the PAIRING/credential but may keep the host profile in the list; DELETE removes the saved profile entirely. A multi-host list (OJAMD + Mac Mini today, Shelley's host plausibly) needs both, plus list plumbing that single-host UI never had to answer:

Which profile is ACTIVE (the one chat/models talk to)? Explicit selection vs implicit.

Deleting the ACTIVE host — block it, or auto-fall-back to another / to standalone free-tier?

Deleting the LAST host — app returns to free-tier standalone cleanly (ties to #136/#137 posture; must not wedge).

Confirm on delete (destructive); revoke may or may not need one.

Does deleting a profile also purge its stored pairing secret from Keychain? (It should — no orphaned credentials.)

Scope: larger than the #151/#152 micro-lane — this is the "Settings → Server becomes a real list" lane. Suggest treating #151 (test feedback) + #152 (rename/surface revoke) as the quick Settings-host PR, and #153 as a slightly larger follow-up that introduces delete + active-selection + empty-list→standalone. Could be one combined lane if the list refactor is small; source-read decides.

Source-confirm owed (next Mac shell): how are hosts stored today — single host record or already an array? (grep host/profile model under Talaria; check SettingsStore / whatever holds pairing state). If it's still single-host, #153 is partly a data-model lane, not just UI — size accordingly. Confirm Keychain key layout for per-host secrets before wiring delete.

Logged 2026-07-20.

## 154. ✅ Dead `#available(iOS …)` guards after the deployment-floor bump to 27.0

> **CLOSED — header flipped 2026-08-01 (Hermes audit Part 1A).** Bundle B Part D done (PR #144). Verified in tree: ZERO live non-27 `#available` guards remain.

**Spec written 2026-07-24: `dispatch/OPUS-T27-BUNDLE-B-146-174-175-154.md`** (bundled with #146, #174, #175 — PART D, CONFIRM-FIRST, and note the masked-test trap). Do not re-spec; check merge state before sending.

**2026-07-24 — DONE on `claude/t27-bundle-b-hygiene` (PART D). The confirm contradicted this item's own framing, and the contradiction is the useful part:** "each `else` branch behind one is unreachable dead code" holds for **three** of the 11 sites, not 11.

**7 of the 8 `LocalChatBackend` sites are COMPOUND guards** — `#available(iOS 27.0, *), Self.pccGrantConfirmed`. `pccGrantConfirmed` is a `static let = false` pending Apple's PCC grant (#72), so those `else` branches are **not dead — they are the only live path today.** Deleting them would have deleted the shipping behaviour. Only the version clause went; `pccGrantConfirmed` now reads as the single gate it always was. That is also the answer to confirm-question 2: yes, one logical guard repeated, and dropping the redundant clause IS the collapse.

**`LocalIntelligenceService:271` is the same shape for a different reason.** The `try?` inside means the `text.count / 3` estimate below still catches a throwing or unavailable model — it is not a version fallback. Wrapper removed, fallback kept.

**Genuinely dead, deleted (3):** `SensorUploadService:973`'s `else` (a deprecated `CLGeocoder` path), `LocalChatBackend.currentTokenUsage`'s iOS-26 `return nil`, and the widget's conditional `.systemExtraLargePortrait` append.

**THE TRAP, checked as instructed.** Grepped `TalariaTests` for anything exercising a deleted branch: `reverseGeocode`/`CLGeocoder` — zero hits; `currentTokenUsage` — zero (the `usage == nil` hits are `Message` decoding, not this); `systemExtraLargePortrait` — zero; and **no `#available` anywhere in either test target**. `PrivateCloudRoutingTests` drives `ChatBackendRouter` through injected closures and never reaches these guards. Nothing masked the deletion.

**Build stayed clean** — no new warnings, and specifically no "will never be executed" from the now-bare `pccGrantConfirmed` guards.

**Kept out of PR #132's history as instructed** — its own commit, its own review.

Surfaced 2026-07-21 while landing PR #132 (deployment floor). `project.yml` had declared the floor twice and disagreed with itself — `options.deploymentTarget.iOS: "27.0"` versus an explicit `settings.base.IPHONEOS_DEPLOYMENT_TARGET: "26.0"`. The explicit build setting wins in XcodeGen, so the real shipping floor had been **26.0** despite Requirements claiming 27. #132 removed the stale override; the floor is now genuinely 27.0.

Consequence: every `#available(iOS …)` guard in the app is now always-true, and each `else` branch behind one is unreachable dead code. 11 sites:

- `27.0` × 8 — `Talaria/Services/Live/LocalChatBackend.swift` lines 162, 171, 190, 210, 245, 430, 735, 792
- `27.0` × 1 — `TalariaWidgets/HermesStatusWidget.swift:34`
- `26.4` × 1 — `Talaria/Services/Live/LocalIntelligenceService.swift:271`
- `26.0` × 1 — `Talaria/Services/Live/SensorUploadService.swift:973`

**Not a bug, and not urgent.** An always-true guard takes the correct branch, so behaviour is right today. Swift emitted no warning for any of these — the 931/84 suite passed clean on beta-4 with zero availability diagnostics. This is cleanup, not a defect.

Why it's worth doing anyway: the dead `else` branches are iOS-26 fallback paths that can no longer execute. They read as live code to anyone reviewing `LocalChatBackend` (8 of the 11 are there, i.e. the on-device FoundationModels path — the newest and least-worn subsystem), which invites someone maintaining a fallback that is structurally unreachable.

Scope note: deliberately kept OUT of #132. That PR was a config change with a mechanical pbxproj regen; deleting branches across 11 sites is a refactor and needs its own review and test pass. Do not fold them together retroactively.

Source-confirm owed before dispatching: for each site, check whether the `else` branch is genuinely dead or whether the guard wraps something with a non-trivial fallback worth preserving as a comment. `LocalChatBackend` clustering suggests several may be one logical guard repeated — collapse rather than delete one-by-one if so. Also confirm nothing in `TalariaTests` asserts on the fallback path (a test exercising unreachable code would still pass and would mask the deletion).

Related: the floor mismatch was invisible to CI by construction — SDK and deployment target are orthogonal, so a 27-SDK build with a 26 floor compiles clean and stays green forever. Nothing in the sim matrix ever exercised a real 26 runtime. Worth remembering the next time "the tests are green" is treated as evidence about deployment posture.

Logged 2026-07-22.

## 157. ✅ Reproduce the verbatim WebRTC BSD-3-Clause notice before App Store submission — CLOSED 2026-07-22

`THIRD_PARTY_LICENSES.md` landed 2026-07-22 recording `stasel/WebRTC` 130.0.0 (the only third-party package Talaria links — voice-mode transport, declared in `project.yml` and pinned in `Package.resolved`). The entry currently *describes* the license rather than reproducing it.

BSD 3-Clause requires reproducing the copyright notice, condition list, and disclaimer in binary distributions. Shipping to the App Store without it is a license violation, and it is the kind that surfaces after release rather than before.

Owed: copy the verbatim notice and patent grant out of the distributed XCFramework/package into `THIRD_PARTY_LICENSES.md`. Cheap to do, easy to forget, and blocking for submission rather than for development — so it is not urgent now but must not be carried into a release lane silently.

Related: #156 review noted hermex ships an in-app acknowledgements surface. Worth deciding whether Talaria's licenses live only in the repo or also in Settings; App Review does not require the latter, but it is conventional.

Logged 2026-07-22.

## 158. ✅ #156 source-confirms ANSWERED — hermes-agent 0.19.0 capability inventory

Dispatched to Kimi K3 on the Mac host 2026-07-22 (session `api_1784695729_f089fe1f`, 30 tool calls). Every claim traces to a file/line in the local install at `~/.hermes/hermes-agent` (upstream `e57918ac`) or to a query against the real `state.db`. Nothing returned UNKNOWN. This resolves the source-confirms attached to #156 and re-sizes every sub-lane.

**156a Tasks/cron — BUILDABLE, no new endpoint.** Best outcome available. Durable subsystem at `cron/jobs.py` + `cron/scheduler.py`, persisted to `~/.hermes/cron/jobs.json`. Full CRUD already on `:8642`: `GET/POST /api/jobs`, `GET/PATCH/DELETE /api/jobs/{id}`, plus `/pause`, `/resume`, `/run`. Job record has ~30 fields; PATCH whitelist is `{name, schedule, prompt, deliver, skills, skill, repeat, enabled}`. Caveat: the HTTP surface does NOT expose `script`/`no_agent`/`workdir`/model override on create — those are CLI/tool only. Design the phone UI to the PATCH whitelist, not the full record.

**156b Skills — BUILDABLE (list only).** `GET /v1/skills` on `:8642` returns `{name, description, category}` and nothing else. No path, no enabled state. Note an upstream quirk: the handler calls `_find_all_skills(skip_disabled=False)` but the function excludes disabled skills internally, so disabled skills never appear AND there is no flag to distinguish them. Enabled-state, paths, install and toggle are dashboard (`:9119`) or CLI only. Scope the lane to a read-only browser or accept a new relay endpoint.

**156c Memory — BUILDABLE via direct file read, not via API.** No memory route exists on `:8642` at all. Built-in backend is two plain-text files, `~/.hermes/memories/MEMORY.md` and `USER.md`, free-text entries separated by `§`, under a char budget. **Hard caveat:** if the profile's `memory.provider` is Honcho or Mem0, those files are stale and the real content lives remotely — Talaria would need its own client for that provider. Confirm the active provider before building. Even the dashboard cannot return memory *content*.

**156d Insights — split verdict, and #25 is now CLOSED as a finding.** Per-message token counts are **NOT-POSSIBLE** on 0.19.0. The `messages.token_count` column exists in the schema but is never written: zero non-test call sites, and empirically `COUNT(token_count) = 0` across 7595 real rows on this machine. `GET /api/sessions/{id}/messages` returns the field and it is always null. This is the definitive confirmation of #25's suspicion — it is an upstream gap, not a Talaria bug, and no relay work can fix it. What IS available: session cumulative totals, and **live per-turn usage** returned in `run.completed` on `chat/stream`. Build the panel on per-turn + session totals; never promise per-message history.

**156e Projects — NOT-POSSIBLE server-side.** No project/folder/tag/group concept anywhere. `PATCH /api/sessions/{id}` accepts exactly `{title, end_reason}` — no metadata field to piggyback on. The only handles are `title`, `source`, `parent_session_id`/`_lineage_root_id` (fork tree, not user grouping), `archived`, `profile_name`. If we want this, it is a Talaria-side local mapping (session id → folder, stored on device), or an upstream schema feature. Decide which before designing.

**156f Mid-run steering — NOT-POSSIBLE today, but closer than expected.** The primitive EXISTS and is battle-tested: `AIAgent.steer(text)` at `run_agent.py:2899` stashes text and appends it to the last tool result after the current tool batch, and it is already used by the CLI, messaging gateway, TUI gateway and ACP adapter. It is simply not exposed on `:8642` — zero `.steer(` calls in `api_server.py`, no route. So this is NEEDS-NEW-RELAY-ENDPOINT (an upstream patch adding `POST /api/sessions/{id}/steer`), not architecturally impossible. Reclassify from "may be impossible" to "small upstream shim".

**Operationally important side-finding (not a bug, but verify on any change):** `chat/stream` turns are NOT registered in `_active_run_agents` — that only happens in the `/v1/runs` flow. So `POST /v1/runs/{run_id}/stop` **cannot** stop a session-chat turn; closing the SSE connection is the only cancel path. Talaria is already correct here (`ChatStore.cancelStreaming()` calls `streamingTask?.cancel()`, which closes the stream), but anyone "improving" stop by calling the runs endpoint would ship a silently no-op button.

Suggested sequencing given the above: 156a first (free — the API already exists), then 156b read-only. 156d needs a scope decision (per-turn only). 156e and 156f need Owen posture calls before any code.

Logged 2026-07-22.

## 164. ✅ Recurring UI-test flake: `testDisconnectReturnsToStandaloneChat` fails on bundle-warm runs — **CLOSED 2026-08-04: fix landed 2026-07-24, close criteria exceeded — zero recurrences across 11 days of full-bundle gate runs**

> **✅ CLOSED 2026-08-04 (queue item 4, flake family).** The discriminating fix
> (`waitForNonExistence(timeout: 5)` — tolerates the dismissal animation,
> still fails on a real #31 regression) has been on main since 2026-07-24.
> The close criteria asked for three consecutive green full-suite bundle
> runs; the accumulated record is stronger: **every lane gate and combined
> gate from 2026-07-24 through 2026-08-04 ran the full bundle and the #164
> assertion signature never fired again** (that is well over a dozen runs,
> including five on 2026-08-04 alone). The test's only appearance since is
> inside **#219's runner-death list (2026-08-01), which is explicitly a
> different mechanism** — no assertion text, runner lost, four tests taken
> together — and stays filed there. Quarantine never needed.

**2026-07-24 — REPRODUCED UNDER CONTROLLED CONDITIONS. Occurrence 4, and the first with a captured
mechanism.** Three sequential full-suite runs on an otherwise-idle sim (Mac Mini, Owen away):
**run 1 PASS, run 2 FAIL, run 3 PASS.** So it is ~1-in-3 on back-to-back runs and it is NOT
dependent on a human driving the machine.

**Mechanism — from the run-2 timing, not inferred.** The failure is the `#31` assertion at
`AppTemplateUITests.swift:209`:

    t = 41.93s  Checking existence of "chat.composer" TextView     → present
    t = 41.98s  Checking existence of "Enter Code Manually" Button → ALSO present
    FAIL: XCTAssertFalse — no pairing wall may return after disconnect (#31)

**Fifty milliseconds apart.** The composer and the dismissing pairing wall coexist in the
accessibility tree for a beat after disconnect, and the assertion used a bare `.exists` — which is
true for a view still on its way out. The test was asserting "the wall was never momentarily in the
tree" when the contract is "the wall is gone."

**This is exactly the ambiguity this item was filed about.** From the log alone, a mid-dismissal
wall and a genuinely-returned wall (#31 regressing for real) are indistinguishable — which is why
the spec warned that this flake impersonates a plausible regression. That warning turned out to
describe the actual failure, not a hypothetical.

**FIX — discriminating, not masking.** `XCTAssertTrue(app.buttons["Enter Code Manually"]
.waitForNonExistence(timeout: 5))`. This tolerates the dismissal animation **and still fails on a
real #31 regression**, because a wall that genuinely returned never disappears — it just fails
after the timeout instead of during someone else's animation. Deliberately NOT a sleep (tuned to
today's machine) and NOT a plain `.exists` in either direction (one masks the defect, the other
re-opens the flake). The reasoning is in an in-code comment so the next reader does not "simplify"
it back.

**Quarantine was NOT taken** — it was the spec's fallback for a genuinely environmental flake, and
this turned out to have a real, fixable cause in the test's own assertion.

**Note on the reproduction runs:** `testMockPairingViaSettingsEntryPoint` (#182) passed all three
times in this sequence. Its single flake remains at 1 occurrence.

**Spec written 2026-07-24: `dispatch/OPUS-T27-164-uitest-flake.md`** — deliberately NOT bundled: its close criteria is three consecutive full-suite runs, which holds the sim for ~an hour. Do not re-spec.

Promoted to its own item per the rule stated when it first appeared: one occurrence is noise, two is a pattern. Now at **two consecutive lane runs**:

- 156a bundle run (PR #135, noted in #162) — failed in-bundle, passed solo rerun
- 156b bundle run (PR #136, noted in #163) — identical: failed in-bundle only, passed solo

Same class both times: the tap-timing/bundle-warm behaviour the test's own comments document, in the pairing/disconnect flow — which **neither lane touched**. Both lanes were additive elsewhere (Tasks, Skills), so the flake is orthogonal to the changes that surfaced it; it fires when the XCUITest bundle runs warm after the full unit suite.

Why it matters despite passing on rerun: it is now a **standing tax on every lane's verification** (each bundle run needs a manual rerun-and-eyeball to distinguish this flake from a real disconnect regression), and its failure mode is exactly the shape a real regression in the disconnect flow would take. A flake that impersonates a plausible regression in a flow we rarely touch is the kind that eventually gets a real bug waved through as "oh, that one again".

Scope when picked up (small lane):
1. Read the test's own comments about tap timing and the bundle-warm condition; reproduce locally with a full-suite run rather than solo.
2. Prefer fixing the wait condition (explicit existence/hittable predicate on the post-disconnect standalone-chat element) over adding sleeps.
3. If the wait is already correct and the flake is genuinely environmental (sim warm-state), quarantine deliberately: mark the test's known-flaky status in-code with a comment pointing here — NOT deletion, NOT a blind retry wrapper that would also mask a real regression.
4. Close criteria: three consecutive full-suite bundle runs green on the pinned sim, or an explicit quarantine decision recorded here.

Not urgent; it costs minutes per lane, not correctness — but it should not survive into the launch-pass test discipline, where "rerun until green" is exactly the habit to have eliminated.

Logged 2026-07-22.

## 167. ✅ #166a/#166b/#166d landed (PR #138, merge cbcc824) — and #164 hits its third occurrence

**2026-07-23 — THE ATS EXCEPTION IS INERT, AND MagicDNS IS A LATENT LANDMINE.**
The shipped key is `NSExceptionDomains: { "100.64.0.0/10": { NSExceptionAllowsInsecureHTTPLoads:
true } }`. `NSExceptionDomains` keys are DOMAIN NAMES — ATS does not accept CIDR notation and
will not expand that string into a range, so it can never match a host like `100.79.222.100`.
Plain-HTTP tailnet traffic works in the field (verified on device against BOTH hosts on
`cbcc824` — the phone drove chat against OJAMD and the Mac all session) because bare-IP hosts
are not policed the way named hosts are, NOT because this exception is doing anything.
**Consequence:** the moment a host field is pointed at a MagicDNS name (e.g.
`ojamd.<tailnet>.ts.net`) rather than a raw IP, ATS will block it and no exception will match.
Revisit before any DNS-based host configuration ships, and before assuming #166b bought
protection it did not buy.
**Method correction worth keeping:** an in-session claim that a successful `curl` from the Mac
confirmed ATS posture was WRONG. curl does not exercise ATS at all — ATS is enforced by
URLSession. Only on-device traffic tests it.

The three code-side items of the #166 review-risk register are done, verified, and merged. Four file-scoped commits; unit suite 1088/96 green on the pinned sim.

**166a — privacy manifests: RESOLVED.** `PrivacyInfo.xcprivacy` for all three bundle targets (app, TalariaWidgets, TalariaShare), plutil-lint clean, wired through the resource build phases (verified in the regenerated pbxproj). Declarations: UserDefaults with CA92.1 + 1C8F.1 (App Group), zero collected data types (sensor/health/location go only to the user's own host — nothing is developer-accessible), tracking false. WebRTC's xcframework ships its own per-slice manifests, so the SDK side needed nothing. If a future upload's ITMS-91053 email names additional required-reason categories, extend these files.

**166b — ATS: RESOLVED, and better than hoped.** `NSAllowsArbitraryLoads` is GONE. Replaced by a range-scoped `NSExceptionDomains` entry keyed by the CGNAT CIDR `100.64.0.0/10` — undocumented form, adopted only after a four-arm controlled experiment on the shipping toolchain (probes inside the app test host, so URLSession obeys the real plist): (1) no exception → tailnet HTTP BLOCKED -1022, so the exception is load-bearing; (2) `NSAllowsLocalNetworking` → still BLOCKED, CGNAT is not "local" to ATS; (3) the CIDR form → both live gateways ALLOWED (http 200); (4) negative control `http://1.1.1.1/` outside the range → still BLOCKED, so the scoping is real, not a leaky global. hermex ships this exact form and passed App Review with it. TLS enforcement is now ON for every non-tailnet connection the app makes. Rollback symptom if an OS update ever regresses the behaviour: -1022 on all host traffic → restore `NSAllowsArbitraryLoads` and reopen this. TalariaShare needed no entry (no-network by design, #123). README + SECURITY.md updated with the evidence so the exception never gets re-litigated from scratch.

**166d — RESOLVED.** `ITSAppUsesNonExemptEncryption: false` declared (HTTPS + DTLS-SRTP are exempt-standard); ends the per-upload compliance prompt.

**#164 — THIRD occurrence, counter reset, priority promoted.** The gate's bundle run failed only `testDisconnectReturnsToStandaloneChat` (XCUITests 7/8). This time the flake dismissal was NOT automatic: the lane touched ATS and the test lives in the connect/disconnect flow — exactly where a real regression would wear the flake's clothes. The solo rerun on the same binary passed 1/1, confirming the ATS change is innocent and the signature matches #164 exactly (warm-bundle fail, solo pass). Consequences per #164's own text: the green-bundle counter resets to 0, and at three occurrences across four lane gates this is no longer ambient noise — the #164 fix lane (wait-predicate first, deliberate quarantine second) should be scheduled rather than deferred.

Remaining from #166: 166c (public HTTPS review host — deployment task), 166e (portal capability pre-flight), 166f (runbook adoption into the launch pass) — all Owner-side, all submission-blocking, none code.

Process note: this lane was landed end-to-end without Desktop Commander (mid-session outage) by relaying exact shell commands through the local Hermes agent (K3) on the Mac — including the gate read, the #164 solo-rerun differential, push, PR #138 creation, merge, and this entry. Verbatim-command relay + raw-output pastes held up; the one hiccup was the shell guard rejecting nohup (K3 substituted its tracked background runner, same invocation).

Logged 2026-07-22.

## 168. ✅ Skills picker "EDIT AS TEXT" is a one-way door + the picker never recovers after a cold-offline launch (device-found 2026-07-22)

> **CLOSED — header flipped 2026-08-01 (Hermes audit Part 1A).** Device checks 2026-07-23 — ALL THREE PASS.

**Device re-checks 2026-07-23: ALL THREE PASS** (whoGoesThere, build off `324689b`).
1. **PASS — and this closes #171's stranded assertion.** EDIT LIST AS TEXT -> typed value ->
   USE PICKER returned to the picker with the hand-typed value preserved and selectable. The
   #163 D5 assertion, unreachable since the one-way door was found, is now verified on device.
2. **PASS.** Standalone with both hosts disconnected: free text only, no USE PICKER, no dead end.
3. **PASS.** Cold-offline launch (force-quit -> airplane -> launch) correctly degraded to free
   text with the RETRY control present; tapping it loaded the picker in place, without
   dismissing the sheet.

**CAVEAT — the retry affordance is effectively invisible.** Owen ran check 3, missed the control
entirely, and reported it as a FAIL; it had rendered the whole time.
`HOST LIST UNAVAILABLE — RETRY` is a `MonoLabel(size: 8)` tucked under the caption. This is the
SECOND time size-8 mono has hidden a control in this exact field — #168's own design note already
flagged the same treatment for EDIT AS TEXT. **The wiring is right; the visual weight is wrong.**
Worth a pass on both controls before this ships, because an affordance nobody sees is not an
affordance.

**Also confirmed correct, recorded so nobody "fixes" it:** restoring connectivity does NOT
auto-reload the field. That is 168b's deliberate design — the foreground-refresh alternative was
rejected because it fires on every app switch and gives the user no way to ask. Dismiss-and-reopen
still recovers as it always did.

Two defects in `TaskSkillsPicker.swift`, both found during the #163 device checklist (Owen driving, Opus verifying against source). Neither is data loss; both are dead-end UX in the cron editor's SKILLS field.

**168a — EDIT AS TEXT cannot be exited (confirmed in source).** `@State useFreeText` has exactly ONE write site: line 122 sets it `true`. Nothing ever sets it back to `false`. So tapping EDIT AS TEXT permanently swaps the picker for a raw `TextField` for the life of the sheet — there is no return control. The caption at line ~90 literally reads "COMMA-SEPARATED — PICKER AVAILABLE WHEN NOT EDITING AS TEXT", i.e. the UI promises a way back that the code does not implement. Fix: add a "USE PICKER" / "DONE" affordance in `freeTextField` that sets `useFreeText = false` (only meaningful when `pickerSkills != nil`; when the host list is unavailable, free text is the only mode and no toggle should show). Consequence today: the "(custom)"-value-preservation property (D5, #160 idea 1) is UNVERIFIABLE on device — you cannot type an unknown value in text mode and return to the picker to see it pinned, because you cannot return. The `SkillsPickerSelectionTests` cover the model round-trip, so the preservation logic is likely intact; it is simply unreachable through the UI. Re-run that device assertion once the return path exists.

**168b — picker stays degraded after a failed fetch, for the life of the sheet.** Reported as the #163 Gap-1 finding. FIRST ROOT CAUSE WAS WRONG and is corrected here: I initially claimed nothing ever re-attempts the fetch. It does — `TaskEditSheet.swift:78-82` has a `.task { await skillsStore?.refresh() }`, so every create/edit sheet retries on appear.

The real mechanism is the gate at `TaskEditSheet.swift:187`:
`skills: (skillsStore?.hasLoaded == true) ? skillsStore?.skills : nil`
plus `SkillsStore.refresh()`, which sets `hasLoaded = true` ONLY on success (the catch block deliberately leaves prior rows and `hasLoaded` untouched — correct for the browser, where a failed refresh must not wipe the list).

So after a cold-offline launch: refresh fails → `hasLoaded` stays false → the picker gets `nil` → free text. Correct so far. But the retry only runs on sheet appear, and `TaskSkillsPicker` receives `skills` as a plain `let`. Within one already-open sheet there is no re-evaluation, so restoring connectivity does nothing until the sheet is dismissed and reopened. Owen's device repro matches exactly: the field stayed free-text for the whole session because he never closed and reopened the sheet after coming back online.

Severity is therefore LOWER than first filed — dismiss-and-reopen already recovers it, and visiting the Skills browser is not actually required. Fix is a polish item, not a defect: give the free-text mode a retry affordance, or re-run the store refresh when the sheet returns to the foreground. Do NOT "fix" this by making `SkillsStore.refresh()` set `hasLoaded` on failure — that would break the browser's keep-rows-on-failure contract verified in #163 Check 4.

**Also worth a design note (not a bug):** "EDIT AS TEXT" reads as single-skill editing, not whole-list editing. Owen — the person who knows the field is a comma-separated list — still read the raw text box as "edit this one skill's name". The button is size-8 mono and nothing signals that the mode edits a delimited list. Consider a clearer label ("EDIT LIST AS TEXT") or an inline hint. Cheap, and it removes a real point of confusion at the exact spot where hand-typed values enter.

Scope: one small lane, `TaskSkillsPicker.swift` plus a touch of `TaskEditSheet.swift`. 168a is a few lines (a toggle-back button + guard); 168b is a retry affordance; the design note rides along. No API changes, no service changes, and `SkillsStore` must not be touched. Swift 6.2 strict-concurrency conventions apply. Spec: `dispatch/FABLE-T27-168-skills-picker-return-path.md`.

Logged 2026-07-22.

**UPDATE 2026-07-22 — ALL THREE BUILT + suite-green on branch `claude/t27-168-170-device-polish`** (spec executed: `dispatch/OPUS-T27-168-170-device-polish.md`; Xcode-beta4, pinned sim, **1107 tests / 99 suites passed**, baseline was 1088/96). Compiled and unit-verified on the Mac; **NOT device-verified** — the three device re-checks below are owed.

- **168a (commit `c7b04a2`)** — the mode moved out of `@State` into a `SkillsFieldMode` value type so the transitions are assertable, and a `USE PICKER` control returns from free text. Both transitions leave `skillsText` untouched, so the round trip is selection-preserving *by construction*. Second dead end closed as specified: with `pickerSkills == nil` **neither** toggle renders. The picker-available caption drops the now-false "PICKER AVAILABLE WHEN NOT EDITING AS TEXT" promise and reads `COMMA-SEPARATED SKILL NAMES` (the list-ness stays on screen — that is 168's design note doing double duty); the nil-list caption is unchanged as specced.
- **168b (commit `d9913cd`)** — chose the **closure-down** option, not a store reference and not a foreground re-refresh. `TaskEditSheet` exposes `retrySkillsFetch` (nil when it has no store) and `TaskSkillsPicker` renders `HOST LIST UNAVAILABLE — RETRY` only when degraded *and* refetchable. On success `hasLoaded` flips, the sheet re-renders, and the field upgrades to a picker **in place**. Rejected the foreground-refresh alternative because it fires on every app switch and gives the user no way to *ask*; rejected any `SkillsStore` change outright. **`SkillsStore.swift` was not modified — confirmed, `git diff main..HEAD --stat` lists neither it nor `SkillsService`/`Skill`.**
- **168 design note (commit `2590121`)** — `EDIT AS TEXT` → **`EDIT LIST AS TEXT`**, plus a spoken-form accessibility label. The `skill-one, skill-two (optional)` placeholder already carried the hint and stays.
- **Tests (commit `eae53a7`)** — `SkillsFieldModeTests` (7) + `SkillsFieldRoundTripTests` (2) in the existing `SkillsPickerSelectionTests.swift`. The round-trip suite is exactly the assertion #171 could not reach on device: a hand-typed value survives the trip back and is reported by `customValues(knownNames:)`.

**Device re-checks owed:** (1) tap EDIT LIST AS TEXT → type an unknown value → USE PICKER → confirm it is pinned at the top as a `(custom)` row **(this is #171's owed #163 assertion — re-run it here)**; (2) with no host list, confirm no USE PICKER appears; (3) airplane-mode open the sheet, restore connectivity, tap RETRY, confirm the field becomes a picker without dismissing.

## 169. ✅ Insights EST COST caveat reads as scoping the whole totals card (device-found 2026-07-22)

> **CLOSED — header flipped 2026-08-01 (Hermes audit Part 1A).** Device check 2026-07-23 — PASS.

**Device check 2026-07-23: PASS.** EST COST renders as its own card, clearly separate from the
totals card, and the caveat now reads as scoping cost alone — token and session totals no longer
inherit the estimate qualifier. Closes the device re-check owed from the PR #139 lane.

Found by Owen during the #165 device checklist. Not a data bug — the numbers and the caveat are both correct — but a grouping/legibility problem at the one place on the screen where a misread produces a WRONG belief about the data.

**Observed:** the totals card renders as a 2×2 grid (TOKENS IN / TOKENS OUT / TOOL CALLS / API CALLS) with `EST COST ~$2.59 — COVERS 21 OF 230 SESSIONS` as a full-width row inside the SAME card, directly beneath the grid. Owen's reaction, verbatim: "made me double take thinking that was the cost for everything above it that I just saw."

**Why it matters:** the coverage caveat belongs to the cost figure ALONE — the four totals above it cover all 230 fetched sessions. Sharing a card makes "COVERS 21 OF 230" read as a footnote on the entire panel, i.e. as though the token and call totals were also computed from only 21 sessions. That is a factually wrong reading of correct data, and it undersells the totals by an order of magnitude.

Same pattern as #168's EDIT AS TEXT label: the person who specified the feature misread his own screen. If the author misreads it, users will.

**Fix options (implementer's judgement, all small, `InsightsScreen.swift` only):**
- Move the EST COST row OUT of the totals card into its own adjacent card — cleanest, makes the caveat's scope structural rather than typographic.
- Or keep it in-card but fold the scope into the label itself: `EST COST · 21 OF 230 SESSIONS WITH COST DATA` on one line, so the caveat is visibly attached to the cost and not floating under the grid.
- Or add a hairline separator + indent so the row reads as a distinct block.

Prefer option 1. Do NOT solve this by dropping the coverage caveat — it is the honest-absence rule doing its job (only 21 of 230 sessions carry a nonzero `estimated_cost_usd`; `actual_cost_usd` is null on all 231, verified against the live host).

**Correction to the #156d dispatch while here:** that spec predicted the cost row would be ABSENT on this host ("cost row absent while the host serves 0.0/null costs (expected today)"). Wrong — the Mac host has 21 sessions with real nonzero estimated costs, so the cost path renders and was exercised on device. The prediction was wrong; the implementation handled the case the spec did not expect, which is the tolerant-decode posture working as intended.

Could ride along with #168's polish lane (different file, same class of finding) or stand alone. Either is fine; do not bundle it into a feature lane.

Logged 2026-07-22.

**UPDATE 2026-07-22 — BUILT + suite-green on `claude/t27-168-170-device-polish` (commit `ad34b74`)**, rode along with #168 as suggested. **Chose fix option 1** (the preferred one): the EST COST element moved OUT of the totals card into its own adjacent card, so the caveat's scope is structural rather than typographic. Options 2 and 3 were rejected as strictly weaker — both leave the row inside a card whose other four numbers have a different scope, which is the actual defect; a separator only makes the boundary thinner, not real.

Belt-and-braces on top of the structural fix: the caveat string moved into `InsightsReadout.costCoverageText` and now names its own subject — **`FROM 21 OF 230 SESSIONS WITH COST DATA`** rather than `COVERS 21 OF 230 SESSIONS`. The scope now travels *with the string*, so a future refactor that re-nests the row cannot silently reintroduce the misread. Unit-covered (partial coverage says it, full coverage and an empty window say nothing). The caveat itself is untouched in spirit — it was never the problem.

**NOT device-verified.** Owed on device: confirm the two cards read as two things at a glance, and that the caveat wraps acceptably at the trailing edge on a phone (it is a MonoLabel at size 8 with `.multilineTextAlignment(.trailing)` and no line limit, so it wraps rather than truncating).

## 171. ✅ Device checklists #162 / #163 / #165 COMPLETE — 17 pass, 2 partial, 1 untestable, 3 defects filed

**2026-07-23 — the stranded assertion is CLOSED.** The #163 D5 check this item parked as
unreachable — no way back out of text mode, so a hand-typed value could not be shown surviving the
round trip — was verified on device: EDIT LIST AS TEXT -> type a value -> USE PICKER returns to the
picker with the typed value preserved and selectable. See #168's device re-checks, all three of
which pass.

Full device pass 2026-07-22, Owen driving on the phone against the Mac Mini host, Claude verifying every claim against the live gateway rather than accepting screen state. Host left clean (0 cron jobs; all `T27TEST*` fixtures deleted, verified).

### #162 Tasks — 7/7 PASS
- **Empty state** → honest, offers creation inline.
- **All five presets** created and round-tripped against what the server actually stored: interval → `{kind:interval, minutes:30}`; daily → `cron 0 22 * * *`; weekly → `cron 5 22 * * 3` (day-of-week correct, next fire landed on the right Wednesday); once-relative → `{kind:once}` + *"once in 1h"*; once-absolute → `run_at` carrying the device's `-05:00` offset. **This is the D4 verification the whole lane existed for.**
- **Advanced rejection** → sheet stayed open, input preserved, banner read `HOST REJECTED THIS TASK` with the server's full syntax help verbatim. Better than specced.
- **Run Now / Pause / Resume / Delete** → host confirmed `completed 0→1`, `last_status: ok`, clean pause/resume, delete propagated. List and detail stayed in lockstep with no refetch flicker.
- **PATCH-diff proof (the strongest result)** → planted `deliver: "telegram:-100999:42"` host-side (a targeted format with no UI in the app), then renamed the job from the phone. Host after: name changed, **deliver intact**, schedule/prompt/repeat/enabled all untouched. The app sends a MINIMAL patch. Given upstream's naive `{**job, **updates}` merge, a full-record PATCH here would have silently destroyed host-side config the phone doesn't understand.
- **needsAttention — PARTIAL, checklist repro was wrong.** #162 assumed `enabled:false` produces the dead-job condition. It does not: disabling leaves `state: scheduled` and `next_run_at` populated, so neither attention branch fires. That state is reserved for genuinely uncomputable schedules (the croniter-missing shape), which is covered by unit tests and is not reachable on a healthy host. What the repro DID verify, and it matters more: the disabled job **stayed visible** with an OFF badge — proving `include_disabled=true` is being sent. Without it, any job disabled from the desktop would silently vanish from the phone.
- **Timezone caveat** → present on daily/weekly/advanced, absent on once-absolute. Correct: cron always evaluates on the host clock, while once-absolute emits a real device offset (verified in the stored `run_at`).

### #163 Skills — 4 PASS, 1 partial
98 skills, groups alphabetical, Uncategorized last. Search matched name, description AND category independently (a description-only query returned three distinct hits). Multi-line descriptions collapsed cleanly in rows and expanded with breaks intact. Airplane refresh kept all rows behind a `Refresh failed — showing last fetch` strip, with search/scroll/expand still usable.
**Partial:** the picker's "(custom)"-value preservation could not be asserted on device — #168a makes the return path from EDIT AS TEXT physically unreachable. Model-level tests cover it; re-run this assertion after #168 merges.

### #165 Insights — 5 PASS, 1 untestable
Banner named window + host + AS OF. Totals reconciled against a live spot-check (app fetched 230 sessions vs the 200-row sample; every total proportionally larger, cost coverage 20→21 as the window grew). Source shares summed to exactly 100%. The no-usage rule got a real workout — ~60% of sessions carry no usage data — and rendered an honest `No Usage Data Recorded` rather than a wall of zeros. Airplane refresh kept numbers and correctly left the AS OF stamp STALE (a stamp that updates on failure is the subtle version of lying). CTX/billing separation held with millions of tokens on screen.
**Untestable:** the >600-session truncation strip. This host has 231 sessions, so the strip correctly never appears. Rests on its unit test until a host with enough history exists.

### Defects found — all filed, none blocking
- **#168** — EDIT AS TEXT is a one-way door (`useFreeText` has one write site, no way back) + degraded picker can't recover in-sheet. Spec'd.
- **#169** — Insights EST COST caveat reads as scoping the whole totals card. Owen double-took on his own screen.
- **#170** — Task detail renders `model_snapshot` under a bare "Model" label, so an UNPINNED job looks pinned; plus no model selection is possible from the phone at all (upstream: model absent from both the create body and the PATCH whitelist).

### What this pass proves about the method
Every one of the three defects is invisible to the test suite — 1088 tests green while EDIT AS TEXT had no exit, the cost caveat misled its own author, and a snapshot masqueraded as a pin. All three are UI-path and labelling failures, which unit tests structurally cannot see. Conversely, the checks that mattered most (PATCH-diff, include_disabled, schedule emission) passed cleanly, so the automated coverage was doing its job where it could.

Two process notes worth keeping: (1) verifying host-side rather than trusting the screen caught that `once-abs` had fired and self-removed, which the app correctly showed as stale until refreshed — a screen-only pass would have logged a phantom missing-job bug; (2) the #162 needsAttention repro was wrong in the checklist itself, which is an argument for writing repro steps against source rather than from memory of the spec.

Logged 2026-07-22.

## 172. ✅ The DELIVER picker has #168a's one-way door too — found while fixing #168, deliberately NOT fixed there

> **CLOSED — header flipped 2026-08-01 (Hermes audit Part 1A).** Fixed on merged Bundle A; third-instance audit clean — `useFreeText` has zero live hits.

**Spec written 2026-07-24: `dispatch/OPUS-T27-BUNDLE-A-178a-172-61-137.md`** (bundled with #178a, #61, #137). Do not re-spec; check merge state before sending.

**2026-07-24 — FIXED on `claude/t27-bundle-a-four-fixes`.** `DeliverFieldMode` (mirroring `SkillsFieldMode`) replaces the `useFreeText` flag, and a `USE LIST` control returns the field to the server's platform menu. Rendered **only when `platforms != nil`** — a return to a list that cannot open would be the second dead end #168a's fix was careful to avoid. New `DeliverFieldModeTests` suite, 7 tests, mirroring `SkillsFieldModeTests` including the no-list guard and the value-preservation property.

**Mirrored rather than shared, deliberately:** "a list exists" means different things in the two fields (a non-nil platforms array vs. a non-empty skills array) and the deliver field has no refetch/retry, so `SkillsFieldMode` did not generalise cleanly without renaming a #168a-era tested type and widening this lane into that one. **If a third instance ever appears, collapse all three into one neutral `ListFieldMode`** — that consolidation is the real cure for the shape and is noted in both types' doc comments.

**Third-instance audit: CLEAN.** `grep -rn "useFreeText" Talaria` now returns nothing — the two instances (#168a's and this one) were the only ones, and both are now mode types.

**What is NOT covered by tests:** the view WIRING, same as #168a. `DeliverFieldModeTests` pins the mode's transitions and gates, but nothing asserts that `TaskDeliverPicker`'s body actually renders `useListButton` — SwiftUI bodies are not reachable from this suite. The device check is one tap: open a cron sheet against a host that answered `/health/detailed`, tap Custom…, confirm `USE LIST` appears and returns to the menu with the typed value intact.

Filed, not fixed, per the #168/#169/#170a dispatch's explicit instruction: the deliver picker shares the pattern but was never reported broken, so fixing it in that lane would have widened a device-found polish lane into an unrequested change.

**Verified in source, same session** (`TaskEditSheet.swift`, `TaskDeliverPicker`):

- `@State private var useFreeText = false` has exactly ONE write site — `Button("Custom…") { useFreeText = true }`.
- `body` is `if platforms == nil || useFreeText { freeTextField } else { menuPicker }`.
- `freeTextField` offers no control that sets it back.

So tapping **Custom…** swaps the menu for a raw `TextField` permanently, for the life of the sheet. Identical mechanism to #168a, in the field directly above the one that was just fixed.

**Two reasons it is milder than #168a was, and one reason it still matters:**

1. Milder — the deliver picker already preserves an off-list value as a marked `(custom)` row in the menu (`isCustomValue` / `currentLabel`), so nothing is unverifiable the way #168a made the skills picker's preservation contract unverifiable. The property is reachable; only the affordance is one-way.
2. Milder — the value is a single token, not a delimited list, so free text is a more plausible terminal state than it was for SKILLS.
3. Still matters — there is no way back to a server-driven list of connected platforms once you leave it. A user who taps Custom… to inspect the field, or taps it by accident, hand-types the rest of the sheet's most typo-sensitive value (`telegram:-100999:42` shapes live here — see #171's PATCH-diff proof) with no list to fall back to.

**Fix when picked up (tiny, and the pattern now exists):** #168a's `SkillsFieldMode` is a general shape — a mode value type with `showsPicker` / `offersEditAsText` / `offersReturnToPicker`, all gated on whether a list is actually available. Reuse or mirror it; add a `USE LIST` control to the deliver free-text field, rendered only when `platforms != nil`. Roughly a 10-line change plus one test suite mirroring `SkillsFieldModeTests`.

**Worth doing at the same time:** audit for a third instance. Two of two hand-rolled `useFreeText` escapes in this sheet shipped as one-way doors, which suggests the shape, not the author, is the problem. `grep -rn "useFreeText" Talaria` is the whole audit.

Logged 2026-07-22 (found during the #168/#169/#170a lane; not device-reported).


## 174. ✅ Attachment payloads inline at full size — 233-472 KB of base64 in one JSON body, no downscaling

> **CLOSED — header flipped 2026-08-01 (Hermes audit Part 1A).** Bundle B Part B fixed — 1.77× payload reduction, `AttachmentDownscaleTests`. Chunking declared out of scope by the item itself.

**Spec written 2026-07-24: `dispatch/OPUS-T27-BUNDLE-B-146-174-175-154.md`** (bundled with #146, #175, #154 — PART B, payload size only; chunking and progress affordance explicitly OUT). Do not re-spec; check merge state before sending.

**2026-07-24 — FIXED on `claude/t27-bundle-b-hygiene` (PART B), and the item's premise was wrong.** "No evidence of any downscale or recompression before inlining" is not what the code does. `PendingAttachment.image(_:)` HAS downscaled all along — it just did not do what its own comment said. It compared `UIImage.size` (**points**) against a bare `768` and rendered through a **default-scale** `UIGraphicsImageRenderer`, so on a 3× device a "768 px" downscale produced a **2304 px** raster: nine times the intended pixel area. The 350 KB staging cap then quietly absorbed it via the progressive-quality loop, which is why nothing looked wrong locally and why the measured payloads clustered just under the cap.

**Confirmed on the sim, not inferred.** `AttachmentDownscaleTests` carries the pre-fix algorithm verbatim and reports `before: 2304×1728 px` off a 4032×3024 source — 768 × 3 exactly.

**Fix:** pin both halves — measure from `size * scale`, render with `format.scale = 1`. Cap `imageMaxPixelDimension = 1536` px on the long edge. **JPEG quality stays 0.5** deliberately: 0.6 was tried and handed back roughly a third of the reduction, and moving two knobs would have muddied the measurement.

**Measured (same fixture): 315,352 → 177,984 B base64, 1.77×.** The fixture is adversarial noise whose grain does NOT scale with the canvas, so it compresses worse after downscaling than real photographic detail; camera output should land at or above the 2.25× pixel-area ratio. Against the item's real captures that projects 472/301/227 KB → roughly 210/134/101 KB.

**The 1536 px choice is a trade-off and is reviewable, not settled.** The binding constraint is that #8's "Extract text" runs Vision OCR over these SAME bytes: at 1536 px across a photographed page, body text sits near 22 px cap height. 1024 px would be ~5× smaller on the wire but pushes OCR to its reliability edge. If cellular pain outweighs extraction accuracy, the knob is one constant.

**Side effect worth having:** four attachments (the composer's max) used to overrun the 900 KB aggregate budget at pre-fix sizes, so images silently became omission stubs. They now fit. Pinned by test.

**Still out of scope, still real:** no chunking and no progress affordance, so a slow upload remains indistinguishable from a hang. Also unexamined: `LiveVoiceSessionService.sendImage` inlines caller-supplied frames with no cap of its own — a different path from the one #174 measured.

**Measured 2026-07-23 (wire capture, whoGoesThere on `cbcc824`).** Three real image sends
captured: 472,471 / 301,227 / 227,747 bytes of base64 data-URI, inlined directly into the
`chat/stream` request body. Base64 carries roughly 33% overhead, so the source JPEGs were about
354 / 226 / 171 KB. No evidence of any downscale or recompression before inlining.
**Why it matters:** fine on a tailnet, considerably less fine on cellular. A single body that
size is a plausible contributor to send timeouts on a slow link — and image-send timeouts are a
symptom already seen this session, though that instance had a different cause. There is also no
chunking or progress affordance, so a slow upload is indistinguishable from a hang.
**Candidate fix:** downscale to a sensible max dimension and re-encode before inlining. Most
vision models gain nothing from full-resolution phone camera output.

Logged 2026-07-23.

## 175. ✅ Idle chattiness — `/v1/models` polled 6x and the session list 3x inside ~1 minute of idle

> **CLOSED — header flipped 2026-08-01 (Hermes audit Part 1A).** Bundle B Part C fixed (PR #144) — `ChatHealthPollPolicy` relaxes 10s→30s.

**Spec written 2026-07-24: `dispatch/OPUS-T27-BUNDLE-B-146-174-175-154.md`** (bundled with #146, #174, #154 — PART C, CONFIRM-FIRST: mechanism is not yet established). Do not re-spec; check merge state before sending.

**2026-07-24 — CONFIRMED then FIXED on `claude/t27-bundle-b-hygiene` (PART C). The two counts are two DIFFERENT mechanisms**, which is why a single fix would have been half a fix.

**Six `/v1/models` = a deliberate timer.** `ChatScreen.monitorConnectionStatus()` slept a flat 10s and called `ChatStore.refreshDirectHealth()`, whose `hermesClient.connect()` probe IS the `/v1/models` GET. Six ticks a minute, six requests — the arithmetic is exact, and that is what identifies it rather than a guess. It also kept firing while BACKGROUNDED: a SwiftUI `.task` is cancelled on view *disappearance*, and backgrounding does not disappear the view.

**Three `/api/sessions` = no timer at all.** Nothing polls that endpoint. Every fetch is a view appearing — `configureChatSeams` on appear, the persistent sidebar's mount seam, `SystemSettingsScreen`'s count, `SessionsSettingsScreen`, the Spotlight donation pass — and none of them knew about the others. This is the spec's explicitly-listed third possibility: **a missing shared cache, not a cadence.** A timer change would have fixed nothing.

**Fixes, one per mechanism:** new pure `ChatHealthPollPolicy` relaxes 10s → 30s once the status has held three probes and snaps back the moment it moves (6 req/min → 2 while idle), and probes only while `.active`. Separately `ChatStore.loadSessions()` answers from its existing `lastLoadedSessions` snapshot within 15s; every caller that MUTATES the list (open session, clear, new chat) passes `force: true`. A failed fetch records no timestamp, so it retries rather than serving an empty list for the window.

**Honest limit:** the exact spacing of the three session fetches was not recoverable from the capture, so which views fired is inferred from the call sites rather than observed. The coalescer addresses the class regardless of which three they were. If a device capture still shows repeat fetches more than 15s apart, the remaining source is a view re-appearing on that cadence and wants its own look.

**One existing test needed updating and this is worth flagging:** `ConversationManagementTests`' failed-refresh case would otherwise have been answered from the snapshot and never reached the throwing client — it would have kept PASSING while asserting nothing. `force: true` restores it.

**Observed 2026-07-23 (wire capture, Mac host).** With the app open and otherwise idle, the
capture logged six `GET /v1/models` and three
`GET /api/sessions?limit=50&order=recent&min_messages=1` within roughly a minute. None
user-initiated.
**Why it matters:** battery and cellular data on a device nominally doing nothing, plus needless
load on a self-hosted gateway. Low severity, likely an easy win.
**Next step:** locate the poll sites and establish whether the cadence is deliberate or an
observer firing per view-appearance. Not yet investigated — logged from wire evidence only.

Logged 2026-07-23.


## 176. ✅ On-device model fires `readImageText` on a text-only prompt with no image present

> **CLOSED — header flipped 2026-08-01 (Hermes audit Part 1A).** Became the entire #194/#196/#200 measurement program. Production is armed-routed (#215: 10/10 clean, 0 grabs). **Live over-serving work continues at #200.**

> **WIDENED 2026-07-25/26 — the reflex is unconditional, not vision-specific.**
> On-device, **every** turn routes to a tool, including turns no tool can serve:
>
> | Prompt | Tool fired |
> |---|---|
> | "Remember the number 7" | offers to create a Reminder |
> | "Can you tell me about Greece?" | declines to answer, offers to search |
> | "What's the capital of Greece" | `SEARCHPLACES` (failed, offline) |
> | "What number did I ask you to remember" | `READREMINDERS` |
> | "Repeat my previous message word for word" | `READREMINDERS` |
> | "What is 2+2" | `SEARCHCONVERSATIONS`, searching the literal string "2+2" |
>
> It re-selects per turn (different tools chosen across turns), so this is not a
> jammed selection — the selector always picks **something**. It also declines to
> state facts it plainly knows ("I can't provide information about Greece
> directly"), which offline leaves it able to answer almost nothing. Offline
> capability is the entire premise of the free tier.
>
> **The model has the history and ignores it.** Verified in source: history IS
> replayed into the `LanguageModelSession` transcript on every rebuild —
> `transcriptTurns(from: currentConversation?.messages ?? [])`,
> `LocalChatBackend.swift:609`. This is a **selection** defect, not a
> context-assembly defect.
>
> **Absorbing state — the sharpest consequence.** Once any tool returns a denial,
> `LocalChatBackend` instructs the model to relay denials faithfully, so every
> subsequent turn returns the same canned denial and the user's actual question is
> never seen. The chat is dead with no in-chat exit. Reached by declining a
> permission the user was never asked to grant. Compounds with **#190**: the only
> escape destroys the history.
>
> **Connectivity gating is NOT the fix.** The 2+2 failure occurred online, with
> full bars. The network was never the problem; routing is.
>
> **Bad belt member for standalone:** `ConversationSearchTool` advertises "the
> current thread's messages plus the titles/previews of indexed past sessions",
> but standalone has no past sessions (**#190**), so it can only ever see the
> thread already on screen — and the selector reaches for it constantly.

**Update 2026-07-27 — 176B BUILT (branch `claude/opus-t27-belt-truth-wkxblt`): the belt stops
being a job description.** Part A — `instructionsText`'s armed branch now OPENS by licensing
tool-free work: answering from own knowledge, writing/composing/summarizing, ordinary
conversation ("facts you know are not guesses, and general knowledge is not device data"). "Use
tools instead of guessing" is scoped to the user's own data, and the recovery clause lands the
absorbing-state exit: a failed or denied tool is never the answer — answer without it, and never
repeat a denial already given in this conversation. Part B — `ConversationSearchTool` KEPT on the
belt, not withheld: in-thread search reaches verbatim text that #26 condensation dropped from the
replayed transcript, and past-session titles/previews are real now that #190's store donates to
the Spotlight cache (the widened quote's "standalone has no past sessions" predates PR #151); its
description corrected to the #148 when-it-applies shape — "Use this ONLY … a specific past
mention — never to answer a question; the recent conversation is already visible to you without
any tool." Three new deterministic substring tests beside the unmodified #148 set, none asserting
what the model chose. **NOT compiled:** the build container has no Xcode or Swift toolchain
(27A5228h unavailable there) — the suite run + green count are owed from the Mac. **Device
verification owed (Owen), the dispatch's DoD:** offline "2+2" / "capital of Greece" answered, not
searched; airplane-mode "write a poem about spring" produces a poem (#194); same-chat recall
answered with no tool; three unrelated questions after a permission denial each answered on their
own terms; and the negative guard — health/location/calendar questions still route to tools.

**Spec written 2026-07-24: `dispatch/OPUS-T27-176-tool-selection.md`** — confirm-then-fix. Preference order: availability gating > description tightening > selection-prompt change. Explicit warning against a test that asserts the model did NOT call a tool (passes/fails on temperament — #183's masked pattern by a new road). Do not re-spec.

**Update 2026-07-24 — BUILT, gating + descriptions (PR #148, `claude/t27-176-tool-selection`):**
the confirm answered all four questions, and the headline is that the belt was never conditioned
on anything at all. `DeviceToolBelt.makeReadTools` returns a FIXED 12-tool array, built ONCE in
`AppContainer` and handed to every `LanguageModelSession` — `readImageText` was offered on every
turn of every conversation, image or not. The model reached for OCR on a haiku because the belt
handed it an OCR tool. **Fixed structurally** (option 1, the dispatch's preference): new
`ImageDependentTool` marker + `DeviceToolBelt.offeredTools(from:hasImageInContext:)` withhold the
two vision tools when the conversation carries no image; `LocalChatBackend` records the live
session's tool names (`sessionToolNames`) and recreates the session when the condition flips,
because a `LanguageModelSession` keeps the tool list it was born with. **Ordering trap found and
cleared:** all three send paths call `preparedSession` BEFORE `appendUserMessage`, so a gate
reading stored history alone would have withheld OCR on the exact turn that attaches the image —
`ConversationImageSource.hasImage(in:incoming:)` takes the turn's pending attachments too. The
presence check is deliberately cheaper AND more permissive than `latestImage` (reachable bytes,
no decode): a present-but-undecodable image still gets the tools, which answer honestly. Option 2
alongside it, for the case gating can't reach (an image twenty turns back keeps the tools
offered): both descriptions now state when the tool APPLIES — "Use this ONLY when the user is
asking what an image says or shows". The instructions' capability list drops "image text/barcode
reading" on exactly the turns the tools are withheld — one image-presence read drives both, so
the persona can never advertise a tool the session wasn't given. 14 deterministic tests
(`DeviceToolBeltTests`), asserted against the real `makeReadTools` output, none of them asserting
what the model chose. `xcodegen` NOT needed — no Swift files added or removed.

**Baseline correction:** the dispatch's "1121 tests / 103 suites" is stale against current main
(it predates the #146/#147 merges). Main today is **1135 tests**; this branch is **1149 tests /
104 suites**, i.e. +14, all of them the new `DeviceToolBeltTests` cases, no new suite.

**Option 3 NOT taken, and the finding stands for the record:** the armed capability block has no
none-of-these path. It lists twelve tools and says *"Use them to work with the user's real data
instead of guessing"* — while the tool-LESS branch explicitly authorizes *"say so plainly instead
of guessing"*. A belt that lists tools without an explicit "some turns need none" biases toward
reaching, which is the general shape behind both this item and the eager 4-call greeting turn.
Left untouched on purpose: changing it in the same lane would make the gate's effect
unattributable on device. If over-reach survives the device verify, this sentence is the next
lever — and it is the item's remaining work, not a new one.

**On defect 2 (the refusal preamble) — mechanism identified, DOWNSTREAM of defect 1.**
`ImageTextTool.call` with no image returns the literal string *"There's no image attached to this
conversation to read text from."* That negative tool result lands in the transcript before the
model composes its answer; *"I can't create a haiku directly, but here's a simple one:"* is the
model narrating it as a statement about its own capability, then contradicting itself. No
spurious call → no negative result → nothing to narrate. This is a hypothesis with a concrete
mechanism, not a confirmed fix — only the device pass can settle it.

**Device verification OWED (Owen), NOT done — this cannot be checked on sim, where the on-device
model path differs:**
1. Standalone, on-device model, literal prompt "Write a haiku about rain" — confirm no
   `readImageText` call and no refusal preamble.
2. Attach an image and ask what it says — confirm `readImageText` IS still offered and works
   (the gate's negative case; this is what the ordering trap above protects).
3. Attach an image, then ask something unrelated in the SAME thread — the tools stay offered
   here by design, so this is where the tightened description is doing the work alone.

If the preamble survives with no tool call, it is independent — **file it separately, do not
widen this item.**

**Observed 2026-07-23 (standalone / ON-DEVICE model, whoGoesThere, build `cbcc824`).** The prompt
was "Write a haiku about rain". The turn shows a `readImageText` tool call — an OCR tool — with
no image anywhere in the conversation and nothing to read. The reply then opened "I can't create
a haiku directly, but here's a simple one:" and produced a haiku anyway.
Two things worth separating: the spurious INVOCATION, and the reply's refusal preamble, which
reads like the model narrating a tool result it should never have had.
**Earlier the same session,** "Hello. How are things working today?" produced 4 tool calls
returning health and motion — appropriate there, but it shows the device tool belt is eager.
**Why it matters:** every spurious call costs latency and context on a small on-device model
(that turn: IN 3.5K / OUT 65 / 4.9s) — and #61's card generation consumes the reply, so a
tool-narrating preamble becomes the conversation's title.
**Next step:** review the tool-belt tool descriptions and selection prompt for the on-device
tier. Not yet investigated.

Logged 2026-07-23.

## 178. ✅ Build-warning inventory — 21 warnings, one of which FAILS App Store validation

> **CLOSED — header flipped 2026-08-01 (Hermes audit Part 1A).** Both halves covered — 178a fixed in Bundle A; the deprecation debt is what #198's sweep cleared.

**Spec written 2026-07-24: `dispatch/OPUS-T27-BUNDLE-A-178a-172-61-137.md`** (bundled with #172, #61, #137 — this item's PART A is the CFBundleShortVersionString launch blocker only; the deprecation debt is NOT in scope). Do not re-spec; check merge state before sending.

**2026-07-24 — PART A (178a) FIXED on `claude/t27-bundle-a-four-fixes`. The deprecation debt below is untouched and still open; this item stays open for it.**

The `1.0` was not a stray literal anywhere. Both extension targets DO set `MARKETING_VERSION: "1.0.0"` in their build settings — but neither declared `CFBundleShortVersionString` in its `info.properties` at all, so **XcodeGen wrote its own `"1.0"` default** into each generated plist, while the app target hard-coded `"1.0.0"` in a third place. Three targets, three independent version literals, two of them invisible.

Fix: all three `info.properties` blocks now read `$(MARKETING_VERSION)` / `$(CURRENT_PROJECT_VERSION)` instead of restating them, so the build setting is the single source of truth and a version bump cannot drift the extensions apart again.

**Verified end-to-end, not just in the source:** after `xcodegen generate`, the three BUILT plists in DerivedData all read `1.0.0` / `1` (`Talaria 27.app`, `PlugIns/TalariaWidgets.appex`, `PlugIns/TalariaShare.appex`), and the warning string is absent from a full build log. `aps-environment: development` intact post-regen (#44/#48).

**Captured 2026-07-23 (Xcode issue navigator, successful build, Xcode-beta4).**

**LAUNCH BLOCKER — not a warning in practice:**
`The CFBundleShortVersionString of an app extension ('1.0') must match that of its containing
parent app ('1.0.0').` A warning at build time and a HARD REJECTION at App Store validation.
One-line fix in `project.yml` — align the extension's version with the app's. Must land before
any submission attempt.

**Deprecations that are load-bearing for open items — migrate deliberately, not opportunistically:**
- `installTap(onBus:bufferSize:format:)` deprecated in iOS 27.0 — `LiveSpeechService.swift`,
  `NativeVoicePipelineService.swift`. This is **#128's exact surface** (double-installTap via
  actor reentrancy). Any rework there should adopt the replacement rather than re-pin the
  deprecated call.
- `AVAudioSession.InterruptionType` / `InterruptionOptions` deprecated in iOS 27.0 in favour of
  `AVAudioSessionDidBecomeInactiveNotification` /
  `AVAudioSessionResumptionRecommendationNotification` — `LiveVoiceSessionService.swift`,
  `NativeVoicePipelineService.swift`. Touches the same audio-session bookkeeping that #82/#106
  fixed; that lane was expensive to get right, so this migration wants its own careful pass.

**Ordinary deprecation debt (cleanup-lane sized):**
- `CLGeocoder`, `reverseGeocodeLocation`, `geocodeAddressString`, `placemark` — deprecated in
  iOS 26.0 for MapKit equivalents (`MKReverseGeocodingRequest`, `MKGeocodingRequest`) —
  `DeviceReadTools.swift`, 6 warnings.
- `AlarmService.swift` — `init(title:stopButton:secondaryButton:secondaryButtonBehavior:)`
  deprecated in 26.1; `stopButton` no longer used.
- `BackgroundTaskService.swift` — `submit` deprecated in 27.0; use
  `submitTaskRequest:completionHandler:` to capture all error conditions. 2 warnings.
- `LocalChatBackend.swift` — `GenerationError` deprecated in 27.0. 2 warnings.
- `ConversationSearch.swift` — 3x `nonisolated(unsafe)` unnecessary for a Sendable
  `DateFormatter` constant.

**Relationship to #154:** that item covers dead `#available` guards left behind by the 27.0
deployment-floor bump; this is the complementary list of APIs the same SDK generation
DEPRECATED. Likely one cleanup lane, two checklists.

Logged 2026-07-23.


## 181. ✅ Health Trends entry point — CLOSED MOOT 2026-07-24: the screen it guarded was cut (#125, PR #142)

**CLOSED MOOT 2026-07-24.** This item existed only to make `HealthTrendsScreen` reachable. #125
cut the screen, so there is nothing left to reach. The grant-persistence lane (option (a)) is
**not** owed — it was never wanted for its own sake, only as the prerequisite for this entry point.

**One finding worth keeping out of the closure, because it outlives the screen.**
`LiveHealthService.authorizationStatus` is still in-memory and still resets to `.notDetermined`
on every launch, recoverable only by `SensorUploadService.start()`'s re-assert behind
`isHealthCollectionEnabled()`. That means the **Permissions health card still reads "Not Set"
after a relaunch even when the user has granted access** — a smaller, live instance of the same
dishonesty, on a surface that still ships. Not tracked here anymore; if it bites, it is a fresh
item and #16 is the mechanism.

Arc, for the record: filed as a source-read finding → fixed via option (c) (PR #140) → reverted
next morning (PR #141) → discriminator answered (the link had never rendered on Owen's build,
which predated the merge) → the screen itself cut (PR #142). Three PRs and a revert to arrive at
deletion. The cheaper path was available at the first step: ask whether the feature was wanted
before making it reachable.


**REVERTED 2026-07-24 — PR #141 (merge `62ef0be`), Owen's call.** PR #140 shipped option (c)
— render the link wherever HealthKit exists, and let the screen's HEALTH ACCESS OFF panel
handle a missing grant. Owen built main to whoGoesThere and reported: *"there's nothing there
for health insights."* Reverted same session; suite back to the pre-#140 baseline 1107/99,
TEST SUCCEEDED. Clean revert of exactly the three files, no intervening code commits.

**Option (c) is dead either way, and the reason is worth keeping.** An entry point whose
destination explains why it is empty is honest but useless. The HEALTH ACCESS OFF panel was
written to catch a user who revoked access mid-use; it was never meant to be the *default*
first impression of the free-tier flagship. Reaching for (c) because it was small was the
wrong selection criterion — small and correct are independent, and #140's own PR body already
admitted it fixed reachability rather than the defect.

**DISCRIMINATOR ANSWERED 2026-07-24 (Owen) — state (ii): the link NEVER RENDERED.** "There was
never a health insight after you finished last night. I built and could not find it." PR #141's
body asserted the opposite — that the link rendered over a blank screen — and that assertion was
inferred from one sentence rather than observed. **It is wrong; disregard it.**

Most probable explanation: the build predated merge `8c8e3b9`, so it never contained #140 at all
and the revert was decided against a build that could not have shown the change. Not worth
chasing further — the revert was correct on independent grounds and main is clean.

**The finding that actually matters, and it survives all of this:** on Owen's device the screen
would have been empty even with the link rendering. The health scope was never granted and sensor
streaming is off, so there is no data behind it. The entry-point gate was never the only thing
between this user and Health Trends — it was the first of at least two, and the cheaper one to
notice. Option (a) alone will not produce a populated screen either; it makes the *grant* survive
a relaunch, which is necessary and not sufficient.

**Before any further work on #125/#181, establish what a real free-tier user actually sees**: grant
health, leave sensor streaming off, cold launch, and check whether `HealthTrendsService` returns
anything at all. If it does not, this whole feature needs a data story before it needs an entry
point, and that is a product question for Owen rather than a lane to dispatch.

**Option (a), still the presumed fix, still owed.** Persist the grant: write
`didGrantHealthAccess` on a successful `requestAuthorization()` and read it at launch, so the
status survives a relaunch and the screen has data behind it before any link points at it.
Blast radius is real — it changes what `collectSnapshot()` gates on and therefore touches the
sensor pipeline (#16's territory), which is why it did not ride #140. It needs its own lane,
a build, and a device pass. **Do not re-render the entry point until (a) lands.**

Lesson recorded alongside #61's and #24f's: a fix that is cheap to write is not thereby the
right fix, and "the screen handles the empty case honestly" is not the same as "the user gets
something." Cross-ref #180 — this is the umbrella's inverse and belongs in the same design
pass: there, the app hid its degradation; here, it would have advertised it.


**FIXED SAME DAY — PR #140 (merge `8c8e3b9`).** Option (c) shipped: `PermissionStatus`
gains `allowsHealthTrendsEntry` (`self != .unsupported`), the entry point at
`PermissionsScreen.swift` uses it, and three tests pin it against re-narrowing. The doc
comment on the property carries the reasoning so the next reader does not "correct" it back
to `.authorized`. Suite **1110 / 99 green** (baseline 1107/99 — delta is exactly the three
new tests); no new files, no xcodegen regen.

**What PR #140 does NOT fix, and this item stays open for it.** Only reachability was
addressed. The underlying dishonesty is untouched: `LiveHealthService.authorizationStatus`
still resets to `.notDetermined` every launch, so the Permissions health card still reads
"Not Set" after a relaunch even when the user granted access, and `HealthTrendsScreen` will
still show HEALTH ACCESS OFF until something re-asserts the grant. **Option (a) — persist
the grant (`didGrantHealthAccess` written on a successful `requestAuthorization()`, read at
launch) — remains owed** and is the real fix. It is a separate, larger blast radius: it
touches what `collectSnapshot()` gates on and therefore the sensor pipeline (#16's original
territory), which is why it did not ride this PR.

**Device confirm (Lane 10 of the 2026-07-24 dispatch) now confirms the FIX, not the defect.**
The pre-fix repro ladder is preserved above for the record, but on a post-`8c8e3b9` build the
link should be present on a cold launch with sensors off — showing HEALTH ACCESS OFF when
tapped, which is the honest state, not a regression.


**Found 2026-07-23 by source read (no device needed), prompted by Owen: "ive never come across
health trends in app."** He is right, and it is not a discoverability problem — the link genuinely
does not render.

The only entry point to `HealthTrendsScreen` is a `NavigationLink` at
`PermissionsScreen.swift:44`, gated on `capability.permissionType == .health && capability.status
== .authorized`. That status resolves to `LiveHealthService.authorizationStatus`, which is
**in-memory only** — `refreshAuthorizationStatus()` (`LiveHealthService.swift:83`) cannot recover
it, because Apple deliberately hides read-scope status. The method's own comment says exactly this,
and #16 recorded the same mechanism a month ago.

Exactly two callers set it to `.authorized`:

1. `PermissionsStore.requestPermission(for: .health)` (`:44`) — the manual ENABLE tap.
2. `SensorUploadService.start()` (`:473`) — the per-launch re-assert, **gated on
   `isHealthCollectionEnabled()`**.

So the link renders only when sensor health collection is ON, or within the same app session in
which the user tapped ENABLE. **With sensors off it is invisible on every cold launch.** Owen turned
sensor streaming OFF on 2026-07-23 (state note in #137) — precisely the posture that hides it.

**Why this matters more than it looks.** #125 calls this screen "the free-tier flagship" and "the
App Store screenshot." A free-tier standalone user has no host and no reason to enable sensor
streaming — sensors are a *connected*-tier concern. The one tier the screen was built for is the
tier that cannot find it.

**Same shape as #180** (the app hides its own state) with a sharper edge: here it hides a *feature*
rather than a degradation, and the hiding is driven by a flag that resets every launch.

**Fix directions — not yet decided:**

- **(a) Persist the grant.** A `didGrantHealthAccess` flag written on a successful
  `requestAuthorization()` and read at launch. Cheap, and it matches what the code already
  *assumes*: "If we previously got authorized via requestAuthorization, keep it" is a comment
  describing behaviour that does not actually survive relaunch.
- **(b) Re-assert health auth on launch unconditionally**, not behind `isHealthCollectionEnabled()`.
  Safe per the existing in-source note — for read-only types iOS shows the sheet at most once per
  install — but it couples a *view* feature to the *sensor* pipeline, which is the coupling that
  caused this in the first place.
- **(c) Render the link whenever HealthKit is available** and let the screen's own HEALTH-ACCESS-OFF
  panel do the honest work. That panel already exists and already says the right thing; the gate
  above it is what makes it unreachable.

(c) is probably right and nearly free — the screen was built to handle the unauthorized case and is
being denied the chance to. (a) is the more correct underlying fix. They are not exclusive.

**Device confirmation queued** as Lane 10 of `dispatch/OPUS-T27-DEVICE-PASS-2026-07-24.md`, with the
repro ladder written out (sensors off → link absent; ENABLE → link appears in-session; cold relaunch
→ link gone; sensors on → link stable). Confirm on metal before fixing: the source read is strong
but unverified.

Cross-refs: #125 (the screen itself), #16 (same in-memory-auth mechanism, found 2026-06-25), #137
(the sensor posture that exposes it), #180 (the umbrella this belongs under).

Logged 2026-07-23.

## 183. 🧹 Tests that pass without exercising what they name — three instances, one shape — **✅ CLOSED 2026-08-04: Phase 2 mutation check RUN, 6 invariants verified real, 1 coverage gap found and fixed**

> ## ✅ PHASE 2 RAN 2026-08-04 (quality-batch lane; Owen queued the batch on-deck,
> ## which supersedes the "after the device pass" hold — device passes have since
> ## landed 2026-08-02/03/04). Per-invariant verdicts, every mutation reverted
> ## before the next (verified by `git status` + `git diff` each time; final tree
> ## carried ONLY the new test):
>
> | target | mutation | verdict |
> |---|---|---|
> | **#137 consent inversion** (the most expensive failure on the list) | no-blob branch grants health+location | **PASS** — `pairedDeviceWithoutBlobGrandfathersStreamingOnlyNotHealthOrLocation` RED on both flipped assertions, 5 tests executed |
> | **#61 `degenerateCardReason`** | unconditional `nil` | **PASS** — every trip-branch test RED (identical, containment, repetition, preamble, end-to-end, single-field) |
> | **#127 monetization fail-open** | `existingPairing` → `.showPaywall` | **PASS** — `existingPairingAlwaysPassesRegardlessOfEntitlement` RED across its whole state×cache matrix |
> | **#172/#168a field-mode dead-end guard** | `offersReturnToList` drops `hasPlatformList` | **PASS** — `noPlatformListMeansNoModeToggleInEitherDirection` RED, 7 executed |
> | **#174 downscale, renderer half** | `format.scale = 1` pin removed | **PASS** — 4 of 5 tests RED |
> | **#174 downscale, measurement half** | `* image.scale` dropped | **NOT OBSERVABLE → GAP FIXED.** Whole suite stayed GREEN because every fixture was scale-1 (points == pixels). Not a masked test — a fixture that cannot distinguish the fixed code from half-reverted code. Fixed in this lane: `threeXScaleImageIsStillCappedInPixels` (3×-scale image, points 1344 < cap, pixels 4032 > cap) — RED under the mutation (ONLY it; the other 5 stayed green, confirming the gap), GREEN on production. Suite 1574 → **1575** on this branch |
> | #133 push idempotency / #146 derived Bool | — | **MOOT** — #238 deleted the entire push-registration surface; zero references (re-verified today) |
>
> **The Phase-1 lesson recurred INSIDE this run, twice:** `-only-testing:` with a
> FILE name (`SensorOptInTests`) and with a FUNCTION path both silently ran
> **`Executed 0 tests` under `TEST SUCCEEDED`** — each nearly minted a false
> MASKED verdict. Suites in this repo are named per-struct, not per-file
> (`SensorGrandfatheringTests` lives in `SensorOptInTests.swift`), and the
> function-level filter doesn't match swift-testing tests at all here. **Read
> the executed count before believing any green — including a mutation run's.**
>
> **Close accounting per the spec's full-lane criteria:** Phase 1 counts
> reported (2026-08-02, below) ✓ · Phase 2 run against the prioritized list
> with per-test verdicts ✓ · clear-cut fix landed (+1 test), nothing left to
> file ✓ · no mutation committed ✓ · suite green with the delta accounted ✓.
> **Deliberately a prioritized SAMPLE (the spec forbids mutating across the
> whole suite)** — six invariants proven, not 1,500. Instance 3
> (`CondenserFidelityTests` skip-not-pass) stays with **#93**, its owner; the
> gate has reported skips since Phase 1.

**Raised 2026-07-24 (Owen) after the second instance surfaced in one bundle.** Three independent
findings now share a shape, which makes it a pattern rather than a run of accidents:

1. **`ConversationManagementTests`** failed-refresh case answered from a fresh snapshot and never
   reached the throwing client — passing while testing nothing. Found and fixed in PR #144
   (`force: true`).
2. **#154's unreachable-fallback trap.** A test asserting on a branch behind an always-true
   `#available` guard still passes, and would have *validated* deleting live code. It came back
   clean — but only because the Bundle B spec told someone to look. Nothing structural caught it.
3. **#93's `CondenserFidelityTests`** — SKIPPED on sim since 2026-07-13. #93 already records the
   correct verdict: **a skip is not a pass.** It has been green-by-omission for eleven days.

**Why it earns a lane.** The suite is the primary evidence behind every merge decision here —
"1105/100 green" has gated Bundle A, the #125 cut, and Bundle B. A test that *cannot fail* is worse
than a missing test: a missing test is visible in coverage, while a masked one reads as protection.
The count is only meaningful if the green means something.

**Distinct from #164 and #182**, and the distinction matters: those are flakes, which fail *visibly*
and intermittently. This is the opposite failure — tests that never fail at all. Do not merge these
items or let a fix for one be credited to the other.

**PHASE 2 DEFERRED (Owen, 2026-07-24) — Phase 1 only for now.** The mutation targets are the guards
Bundle B just changed and the device pass is about to verify by hand; mutating code that is
simultaneously moving gives a muddier signal than waiting for a settled baseline. Phase 2 runs
after the device pass. **A Phase 1 report does NOT close this item** — a static sweep can find
suspicious tests but cannot prove any test actually works.

**Spec written 2026-07-24: `dispatch/OPUS-T27-183-masked-tests-sweep.md`.** Two phases: a cheap
static sweep (vacuous suites, skip-guarded tests, never-invoked doubles, assertions on constants),
then a targeted **mutation check** — deliberately break the production code a test names and
confirm it goes red. That is the only check that proves a test works. Prioritised by blast radius,
not run across all 1121.

**Two standing cautions carried into the spec:**
- Every mutation must be reverted; a stray one reaching main would be far worse than the bug hunted.
- **The lane must not widen.** If the static sweep turns up thirty candidates, fix the obvious few
  and file the rest as one follow-up. A sweep that tries to fix everything it finds does not land.

**A falling test count is a legitimate outcome** if a vacuous test is deleted rather than repaired.
Recorded here in advance so nobody preserves a meaningless test to protect the number.

Logged 2026-07-24.

> ## PHASE 1 RAN 2026-08-02 — the suite is clean by all four static criteria, and the real
> ## finding is that THE GATE COULD NOT SEE SKIPS. Item stays OPEN (Phase 2 unrun).
>
> **Counts, per the spec's four categories, over 1,504 parsed test functions:**
>
> | category | candidates | real |
> |---|---|---|
> | **A. vacuous** (no assertion anywhere in body) | 1 | **1** — `testLaunch`, the auto-generated XCUITest template. Already annotated (#144). It is a launch smoke test: it fails if the app crashes on launch, which is a real if narrow subject. **Kept, not deleted.** |
> | **B. silent early-return** (`guard … else { return }`, nothing recorded) | 0 | 0 |
> | **C. `withKnownIssue`** (passes even when FAILING) | 0 | 0 |
> | **D. constant assertions** (`#expect(true)`, `x == x`) | 0 | 0 |
>
> **The dominant idiom here is already the honest one:** `guard case … else { Issue.record(…); return }`.
> That is a real assertion in the failure path, and it is why category B is empty.
>
> ### The finding: a skipped test was indistinguishable from a passing one
>
> `CondenserFidelityTests` — **instance 3 of this item** — gates its two model-path tests on
> `.enabled(…)` with a live Apple-Intelligence probe. On the sim it skips. The gate's own log
> from 2026-08-02:
>
> ```
> ➜ Test "Condensed priming: latest corrected values…" skipped: "Requires the on-device …"
> ➜ Test "Condensed priming stays in budget on a long journal" skipped: "Requires …"
> ✔ Suite CondenserFidelityTests passed after 0.455 seconds.
> ```
>
> **The suite prints `passed` having run nothing, and `lane-gate.sh` never mentioned the word
> "skip".** Its headline read `Swift Testing tests run — 1497`, with no signal that two
> subjects went unexercised. That is #218's lesson one level up: *a positive marker that a
> no-op satisfies is not a positive marker* — and "passed" over an all-skipped suite is
> exactly that no-op.
>
> **Fixed in `scripts/mac/lane-gate.sh`:** the gate now counts skips, prints each skipped
> test with its reason, and prints `no skipped tests` when there are none. **Deliberately a
> REPORT, not a FAIL** — these two skips are honest (the hardware genuinely is absent on a
> sim run) and **#93 owns making them run**; what was wrong was that they were invisible.
> Expected steady state is **2**. If that number moves, it is a finding.
>
> ### The other finding, and it is the one worth carrying
>
> **The sweep tool needed FOUR corrections before its output could be trusted, and every
> prior version returned a confident, wrong answer** — 22 candidates, then 6, then 3, then 1:
>
> 1. `@Test func x()` on ONE line — the dominant style here. The parser treated `@Test` as
>    always standalone and silently found **357 of ~1,500** tests. Caught only because that
>    count was checkable against the gate's.
> 2. `Issue.record` missing from the assertion regex — made **4 honest tests** read as vacuous.
> 3. Brace-matching counted braces **inside string literals**, truncating bodies early: a test
>    building the fixture `"struct A {\n…"` lost its three real `#expect`s.
> 4. Same again for **raw strings** (`#"…"#`), which this suite uses for JSON fixtures.
> 5. `@MainActor @Test func` — attribute ORDER — left **14 tests unparsed**, i.e. unswept.
>
> **A masked masked-test detector.** The only thing that caught any of it was refusing to
> accept a count that did not reconcile (357 ≠ 1497; 1420 ≠ 1497; 1486 ≠ 1497). **Read the
> count first** — the same rule that caught the stale `.xctest` on 2026-07-30 and
> `Executed 0 tests` under `** TEST SUCCEEDED **`. Tooling written to find masked tests is not
> exempt from being one.
>
> **Instances 1 and 2 re-verified against the tree, not the entry:** #1
> (`ConversationManagementTests`) carries `force: true` at
> `ConversationManagementTests.swift:247` — fixed, confirmed. #2 (#154's unreachable-fallback
> trap) was a one-off caught by review, with nothing structural to sweep for; Phase 2's
> mutation check is the only thing that would catch its shape.
>
> **THE ITEM STAYS OPEN.** Per the spec's own close criteria, a Phase 1 report is not a closed
> sweep: **a static pass cannot prove any test actually works.** Phase 2 (mutation) remains
> unrun — see the deferral note above, and the question raised with Owen 2026-08-02: its
> stated reason ("mutating code Bundle B is simultaneously moving") has expired, but the
> condition Owen set ("after the device pass") has not been met, so it was not restarted
> unilaterally.

## 191. ✅ Chat header is not backend-aware — title and model pill keep reporting the Hermes session — **CLOSED 2026-08-04 (closure sweep): fix built 2026-07-27, device check PASSED 2026-08-02**

> **✅ CLOSED 2026-08-04 (queue item 3 closure sweep).** The only thing this
> item still owed was its §F1 device check, and it PASSED 2026-08-02 (recorded
> in the running list): airplane mode, BOTH an existing Hermes session and a
> fresh chat — header + pill read ON-DEVICE, the flip logged as user-initiated,
> offline errors honest. Nothing left to build; the conversation-shell swap
> this entry deliberately excluded belongs to #190.

> **Device debt queued 2026-08-01 (Hermes audit Part 1C):** the owed device check for
> this item now lives in `dispatch/DEVICE-PASS-RUNNING-LIST.md` **§F1**, written as a
> runnable check. **One queue** — do not restate it here; a check that lives in two
> places drifts, and a check that lives only in a closed-looking item is not recorded.

**Observed 2026-07-25 on whoGoesThere, ON-DEVICE active, phone in airplane mode.** The header read
`HERMES` with a model pill of `KIMI-K3` — a model that runs on OJAMD and was unreachable at the
time. Only the ON-DEVICE badge told the truth.

Message count and CTX% **do** update correctly (10→12 messages, 12%→15%). An earlier reading that
they were frozen was taken from too short a window and is withdrawn.

**Likely mechanism:** the local backend runs inside a Hermes session shell because it has no session
identity of its own to mint (**#190**). Switching backends does not switch the conversation — the
Hermes thread stays on screen with the on-device model behind it.

**Not a content leak.** Verified: the on-device model does *not* receive the Hermes transcript — asked
about prior content it reports no history. Display defect, not contamination.

Same family as **#139** (engine-truth label lie) and **#189** (false-green notification panel):
surfaces asserting state they do not have.

Logged 2026-07-25.

> **FIX BUILT 2026-07-27 (backend-truth lane, with #192 + #193 — branch
> `claude/opus-t27-backend-truth-pvj3fn`).** The header now derives from the ACTIVE brain:
> the wordmark reads TALARIA (not HERMES) while a local brain is active, the model pill
> names the active brain's model (ON-DEVICE / Private Cloud β) instead of the loaded
> session's Hermes model, the status pip + telemetry read local readiness
> (`READY`/`UNAVAILABLE`) instead of `ONLINE · OJAMD`, and the toolbar pill's pip follows
> local readiness too. Message count and CTX% untouched (they were correct); the CTX
> denominator stays keyed to the Hermes-reported model deliberately so #191 moves the pill
> without moving CTX behavior. The conversation-shell swap on backend switch is NOT here —
> that is #190's identity work — but header truth no longer depends on it. Device
> verification owed (airplane-mode ground truth). NOT compiled on 27A5228h: the authoring
> environment has no Xcode — see the PR body.

---

## 192. ✅ The app SWITCHES ITSELF away from on-device; the refused manual switch is the residue — **CLOSED 2026-08-04 (closure sweep): both of this entry's own bars are met**

> **✅ CLOSED 2026-08-04 (queue item 3 closure sweep), against the two bars the
> entry itself set:** (1) *"a fix must carry a test that creates the stuck
> state synthetically, or the item stays open"* — the 2026-07-27 fix carries
> exactly those tests (never-finishing stream creates the wedge; the refused
> switch is asserted; both recovery paths asserted); (2) the reproduction
> trigger ("500-word summary" on-device) PASSED on device 2026-08-02 (§F1):
> generated fully on-device in airplane mode, `routing lock released (#192)`
> in the console, no brain flip. Sticky mode, the run-token teardown, the
> one-writer instrumentation, and the fallback banner are all long merged.
> this item now lives in `dispatch/DEVICE-PASS-RUNNING-LIST.md` **§F1**, written as a
> runnable check. **One queue** — do not restate it here; a check that lives in two
> places drifts, and a check that lives only in a closed-looking item is not recorded.

> **RE-DIAGNOSED 2026-07-26 (device, with screenshots).** The original report —
> "switching to on-device doesn't take" — was the *symptom of recovery*, not the
> defect. Observed live: with ON-DEVICE active, a request for a 500-word summary
> **switched the backend to Hermes on its own** — no user action. Screenshots
> show ON-DEVICE badge + `DEEPSEEK-V4-FLASH` pill + `ONLINE · OJAMD` +
> server-shaped tool confirmations simultaneously. Whatever performs that
> reversion leaves state behind that then refuses the manual switch back until a
> force quit.
>
> So the lane is now: **find what INITIATES an un-asked backend change** —
> deliberate big-request routing? failover on a local-model error? — then
> instrument both directions. If it is designed failover it must announce itself
> and be consented; silent reversion with a lying header is not a feature.
> First reproducible lead: long-form generation requests ("write a 500 word
> summary"). Consequence already banked: it contaminated the #190 device pass
> (threads believed local actually ran on Hermes) and it feeds the #190
> `isLocalThread` contamination hole. Severity: this plus #191 means the user
> CANNOT KNOW which brain has their conversation. Ship blocker adjacent.
>
> **INITIATOR FOUND 2026-07-26 late (source, ChatBackendRouter).** Not failover,
> not big-request routing: `resolvedBrainForNextTurn()` defaults to **Hermes on a
> paired device**, and the on-device pick is a **per-conversation preference
> keyed to the conversation UUID** — so New chat / clearConversation / #190
> openSession orphan the pick and the next send or ~10s `connect()` probe
> reverts. The refusal half: `refreshActiveBrain()` no-ops while `runningBrain
> != nil`, and `sendStreaming` only clears `runningBrain` on completion, so a
> dropped run wedges routing until force quit. Full mechanism + fix
> requirements in the dispatch. **DECIDED 2026-07-27: sticky mode.** The user's
> explicit pick is the resolution default; id rotations (New/clear/openSession)
> must not revert it. Dispatch updated.

> **INTERMITTENT — could not be reproduced on demand 2026-07-26.** Owen attempted
> a fresh reproduction and the switch behaved correctly. This is a real data
> point, not an absence of one: the defect does not reproduce from a clean app
> state, so whatever sets the stuck condition is **rare and situational**, not a
> flag that is always set on a common path.
>
> Consequence for the lane: **the missing observation (toggle moves-then-reverts
> vs refuses to move) is currently unobtainable.** Do not gate work on getting
> it. See the dispatch for the instrument-first approach.
>
> Consequence for verification: a fix shipped without a reproduction **cannot be
> confirmed on device**. Any fix must therefore carry a test that creates the
> stuck state synthetically, or the item stays open regardless of what merges.

**Observed 2026-07-25 on whoGoesThere.** Selecting the on-device backend does not take — the UI stays
on Hermes. Force-quitting clears it, after which the switch succeeds.

Force quit being the remedy establishes the stuck state is **in-memory only** — nothing persisted, it
dies with the process. Expected shape: a transition guard set and not cleared on some path, so every
later switch attempt is refused up front.

**This bug invalidates other tests, which is why it is filed above its apparent severity.** A tester
can believe they are on-device while Hermes answers every turn. The 2026-07-25 number test was only
trustworthy because it ran in **airplane mode** — on-device answers offline, Hermes cannot, so any
reply at all proves the switch took. Any future on-device check must establish the active backend
independently of the UI's claim.

Fourth instance this weekend of *state a transition should have released and did not* — see **#184**
(`reset()` cancels nothing; `openSession` leaves `pendingRun` armed) and **#191**.

**Not yet captured:** whether the toggle moves-then-reverts (switch accepted, apply failed) or
refuses to move (guard rejects input up front). Different fixes; needs one observation.

Read the `Settings-ModelTransition` design doc against live source before speccing.

Logged 2026-07-25.

> **FIX BUILT 2026-07-27 — sticky mode + run teardown + instrumentation (backend-truth
> lane, branch `claude/opus-t27-backend-truth-pvj3fn`). Item stays OPEN pending device
> evidence per the dispatch DoD — the wedge never reproduced on demand, so a green suite
> proves nothing.**
> - **Sticky mode (decided 2026-07-27):** an explicit pick writes a `default` slot in the
>   existing preference dict that every new chat inherits; per-conversation overrides layer
>   on top; "Automatic" clears both. The legacy `next` slot still migrates onto the first
>   conversation that resolves — stored picks are never stranded. Scoped pins (#30
>   escalation offer, #134 debug harness) pass `updatesDefault: false` so they cannot
>   hijack the app-wide mode. Picker checkmarks now show the EFFECTIVE pick.
> - **Wedge released:** `runningBrain` is paired with a run token and cleared on every
>   exit — stream completion, consumer termination (`onTermination` cancels the pump), and
>   the new `abandonActiveRun()` wired into ChatStore's `abandonPendingRun` (#184's
>   primitive) and `cancelStreaming`.
> - **Instrumentation:** one `setActiveBrain` writer logs every change old→new + initiator
>   + conversation key; `refreshActiveBrain` logs WHICH guard refused and why; resolution
>   reasons are named (override / sticky-default / automatic-default / hermes-unreachable /
>   pcc-degraded / hermes-unconfigured). All at `.notice` so Console.app shows them.
> - **No more silent fallback:** automatic error-fallback to on-device now sets
>   `automaticFallbackNotice`, rendered as the #30-style one-line banner.
> - **Synthetic tests:** the stuck state is created on demand (never-finishing stream),
>   the refused switch is asserted, and both recovery paths (explicit abandon; consumer
>   walk-away alone) are asserted. Refusal-path inventory is in the PR body.
> - `Settings-ModelTransition` read against live source: it specs the SHIM model-switch
>   overlay only (`applyingModelID`/`pendingConfirm`/`error`, all cleared on every exit) —
>   the brain-switch path had no designed transition state machine; `runningBrain` was its
>   only transition guard, which is exactly where the wedge lived.

---

## 193. ✅ `confirmationDialog` Cancel button does not render on iOS 27 — **CLOSED 2026-08-04 (closure sweep): all seven converted to `.alert` 2026-07-27; device check PASSED 2026-08-02**

> **✅ CLOSED 2026-08-04 (queue item 3 closure sweep).** Zero
> `confirmationDialog` uses remain in app code (all seven converted to
> `.alert` with explicit Cancel, 2026-07-27), and the owed device check PASSED
> 2026-08-02 (§F1): the Servers → delete-profile sheet rendered "Delete Mac
> Mini" AND Cancel — which Owen confirmed did not render before the fix.

> **Device debt queued 2026-08-01 (Hermes audit Part 1C):** the owed device check for
> this item now lives in `dispatch/DEVICE-PASS-RUNNING-LIST.md` **§F1**, written as a
> runnable check. **One queue** — do not restate it here; a check that lives in two
> places drifts, and a check that lives only in a closed-looking item is not recorded.

**Observed 2026-07-25 device pass.** Destructive-action confirmations built with
`.confirmationDialog` present with no visible Cancel affordance — an iOS 26/27 presentation change.
The cancel role is declared in code, so this is dead code rather than an omission.

**Fix direction:** move destructive confirmations to `.alert`, which still renders an explicit
cancel.

Low severity in isolation; filed because a destructive action with no visible way out is a poor
first impression and the affected surfaces are few.

Logged 2026-07-25.

> **FIX BUILT 2026-07-27 (backend-truth lane).** All seven `confirmationDialog`s converted
> to `.alert` with an explicit Cancel — five destructive (task delete, privacy revoke,
> clear conversation, forget pairing, delete profile) and two decided case-by-case: the
> alarm consent ("rings through Silent mode" needs a visible decline) and the
> backend-profile switch (a one-button sheet with no visible decline reads as a forced
> choice for something that re-homes the app). Zero `confirmationDialog` uses remain in
> app code. Device verification owed.

## 194. ✅ On-device brain refuses creative generation, reciting its tool belt — tool fixation

> **CLOSED — header flipped 2026-08-01 (Hermes audit Part 1A).** Commit `7bbcd4b` — enumeration convicted; PR #157 merged; production armed IS noprose. Residual tic re-filed as #196.

**Observed 2026-07-27, whoGoesThere, AIRPLANE MODE (ground truth: genuinely local).**
Reproduced 4×: "Write a poem about spring", "Write a sonnet about spring", bare "Write me a
poem" after a normal greeting — every one refuses in the same shape: *"I can't write
poems/a sonnet, but I can help with reminders, checking your calendar, or providing
information about your location or weather."* The deflection list IS the tool belt. Fresh-chat
input is a consistent ~1.6K tokens (system prompt + belt definitions); the model has
concluded it is a dispatcher whose only legal moves are its tools.

**Scope of evidence:** offline reproduction on device, iOS 27 beta 4, PR #151 branch build
(OTA-installed). Same session retroactively convicted the morning's "successful" on-device
haiku: that chat carried a SEARCHCONVERSATIONS tool chip and IN 5.1K — Hermes answering
behind the ON-DEVICE badge (the #192 flip; evidence recorded there, not here).

**Distinct from #83's device note** (base model declining verbatim-repetition and long-form
citing *its own limits* — Apple-side guardrails). Here the model cites *our belt*, which
implicates the LocalChatBackend system prompt / DeviceToolBelt instructions framing, not the
base model.

**Fix direction:** the system prompt must license ordinary conversation and creative
generation as first-class, tools as optional capabilities — not enumerate tools as the job
description. Adjacent to the #176B belt-truth lane (same prompt surface); widen that lane or
follow it. Verification: airplane mode, fresh chat, "write a poem" → a poem.

**2026-07-27 (same day): folded into the 176B dispatch** (Items header, observation, Part A
clause, DoD line) — decided widened, not separate. Tracks with #176 from here.

**DEVICE PASS 2026-07-27 (post-merge main a86c750, airplane mode) — SPLIT VERDICT, #194
REOPENS AS ITS OWN ITEM.** The #176 half PASSES: "what's 2+2" -> "The answer is 4.",
"capital of Greece" -> "Athens", both offline, no tool, no belt recital — the shipped Part A
clause fixed factual tool-fixation. The #194 creative half FAILS with the clause live
(fresh-chat IN rose 1.6K -> 1.7K, confirming the new instructions were in-session):
- Haiku (3 lines) refused identically -> length is not the variable.
- "You're allowed to write. Write a poem about spring" -> WORD-FOR-WORD identical refusal ->
  instruction strength / user-level permission is not the variable.
- Refusal signature stable across BOTH instruction sets all day: "I can't write a poem FOR
  YOU, but I can help you [tool-flavored deflection]" — reads as base-model policy, not our
  prompt's voice; rhymes with #83's device note (verbatim-repetition + long-form declines
  citing the model's own limits).

**Next discriminator (Owen, ~1 min): Shortcuts -> "Use Model" (On-Device) -> "Write a poem
about spring".** Removes Talaria entirely. Refusal there => Apple base-model policy; no
instructions text can fix it — resolution becomes PCC escalation offer (#30 pattern) for
creative asks and/or honest messaging. Success there => the tool-ARMED session shape itself
suppresses creation — a 176C lane (e.g. probe whether dropping the prose tool enumeration,
already natively registered on the session, releases it).

**DISCRIMINATOR RESULT 2026-07-27 12:41 — Shortcuts On-Device model WROTE THE HAIKU**
("Cherry blossoms bloom— / soft pink whispers in the breeze, / spring wakes the earth.",
On-Device badge visible). Base-model policy EXONERATED; Talaria's session shape is the
suppressor. Remaining suspects, in order: (1) the registered tool belt itself biasing the
armed session, (2) the prose tool enumeration in instructions (redundant with the tools'
native descriptions — the "job description" signal), (3) long shots: #83 GenerationOptions,
#26 transcript condensation. Next: 176C device A/B — same creative prompt across four
session shapes (armed as-is / tools minus enumeration prose / enumeration without tools /
tool-less branch) behind a debug toggle; the passing cells convict the mechanism.

**Dispatch written 2026-07-27: `dispatch/OPUS-T27-176C-194-creative-suppressor.md`** —
confirm-then-fix shape (harness + labeled inert Part 2), Owen to send.

**DEVICE A/B VERDICT 2026-07-27 ~14:35 — THE ENUMERATION IS CONVICTED.** Desk A/B on the
`claude/t27-176c-desk-ab` Debug OTA build (Part 1 tip + Diagnostics picker), airplane mode,
cell confirmed by the Diagnostics active-shape label:
- `armed` (control, 4 probes): creative content refused every time — deflection only. The
  control reproduces the defect on this build.
- `armed-noprose` (belt fully registered, roster sentence removed): haiku WRITTEN, bobsled
  poem WRITTEN, 100-word Italy summary WRITTEN; tools still fire when apt (READCALENDAR
  earlier same build). "B writes, A refuses" — the dispatch's conviction cell, exactly.
The belt itself is exonerated; the prose roster was teaching the model its job description.
Per the readout: **PR #157 merges whole, Part 2 included** (production armed becomes
roster-less). `toolless` / `prose-notools` cells not run — decision did not require them.

**Residual (separate item, polish not blocker): the disclaimer tic.** Every noprose reply
opens "I can't write X for you, but here's one…" and then delivers the content in full
(peak absurdity: "I can't directly calculate that for you, but 2 + 2 is 4"). A learned
preamble reflex, not a capability gate — distinct mechanism from #194's refusal.

**2026-07-27, later: BUILT with 176B** — the armed instructions now license
writing/composing/summarizing and ordinary conversation as first-class ("need no tool"), pinned
by `armedInstructionsLicenseAnsweringAndCreatingWithoutATool`. The airplane-mode device check
("write a poem" → a poem, fresh chat) rides with the 176B verification pass; details under #176.

**2026-07-27, 176C Part 1 BUILT (branch `claude/t27-176c-creative-suppressor`): the
session-shape instrument.** `TALARIA_SESSION_SHAPE` launch env (DEBUG-only, DUPID-probe
precedent, inert unset or unrecognized) selects the session cell at construction time:
`armed` (production control) / `armed-noprose` (belt registered, instructions minus only the
roster sentence) / `prose-notools` (armed instructions verbatim, NO tools registered — a
deliberate, commented doc-rule violation; measurement cell, not shippable) / `toolless` (far
control). The selector touches construction only (`effectiveOfferedTools` /
`effectiveInstructionsText`); every session build notice-logs `session shape: <cell>` so
device runs self-label in Console. The `includeBeltRoster` seam splits the armed paragraph
without changing it — verified byte-identical to pre-seam for both vision variants, tool-less
branch untouched. Tests: +4 in `DeviceToolBeltTests` (noprose lacks the roster, keeps all four
kept sentences; prose-notools == armed verbatim; armed cell == production; env spellings
parse + tool gating). Part 2 (production armed → noprose) sits as the labeled FINAL commit —
**do not merge-cherry-pick until the device A/B convicts the enumeration** — and the A/B must
run on a build of the Part 1 tip, since a binary containing Part 2 makes the armed control
cell roster-less and collapses the A vs B comparison. Four-cell checklist in the PR body.
Baseline confirmed 1231 tests / 109 suites green on 27A5228h before the change; Part 1 tip
green at 1235/109 (delta exactly the 4 new tests).

Logged 2026-07-27.

## 195. ✅ MessageIdentityUITests — typeText keyboard race renders the test flaky

> **CLOSED — header flipped 2026-08-01 (Hermes audit Part 1A).** FIXED 2026-07-27, 3/3 iterations green.

**Observed 2026-07-27, Mac Mini, pinned sim, during PR #156 verification.** The suite failed
twice (full run + isolated re-run) on `testTranscriptNeverRendersDuplicateMessageIDs`:
"the on-device reply for 'first' should render." The AX hierarchy in the xcresult proved the
app innocent: the composer held **"firstst"** and the probe correctly rendered
"Acknowledged firstst" — `typeText` fired before the keyboard settled and duplicated the
trailing characters, so the exact-match `staticTexts["Acknowledged first"]` wait could never
succeed. Third isolated run, same binary: passed. Cost: ~40 minutes of dispatch-verification
time attributing a phantom regression (PR #156 touches nothing in the input path).

**Fix direction:** make `sendMessage` robust to input mangling — read the composer's settled
value after typing and assert against *that* ("Acknowledged \(actualTyped)"), or clear-and-retry
on mismatch before sending. Keying the assertion to what was actually typed preserves the
test's real charter (duplicate-id detection) while removing the keyboard-timing dependency.

Test-hygiene severity, but it sits in the verification path of every returned PR, so its
flake rate taxes every lane.

**FIXED 2026-07-27 (same day, 414ed4d, direct to main per Owen):** sendMessage reads the
composer's settled value and keys the reply assertion to it. 3/3 iterations green on
27A5228h; pre-fix the test failed 3 of 5 runs across three branches including main. Device
evidence not applicable (sim-only UI test). CLOSED.

Logged 2026-07-27.

## 196. ✅ On-device disclaimer tic — replies open "I can't do X, but…" then do X in full

> **CLOSED — header flipped 2026-08-01 (Hermes audit Part 1A).** Commit `b644bf4` (2026-07-28) titled '#196 CLOSED — stack merged'; all four PRs merged.

**Observed 2026-07-27 device A/B (armed-noprose cell, now production armed post-#157).** With
#194's suppressor removed and content delivery fully restored, every creative/factual reply
retains a vestigial preamble: "I can't write a haiku for you, but here's one I've seen…"
(then an original haiku), "I can't write a poem for you, but here's one inspired by…" (then
the poem), and — peak form — "I can't directly calculate that for you, but 2 + 2 is 4."
Observed on turn TWO of a fresh chat, so NOT history imitation of earlier refusals in-context.

**A learned preamble reflex, not a capability gate** — distinct mechanism from #194 (which
refused to deliver content at all). Candidate sources, undiscriminated: (a) negative-flavored
instruction sentences priming "can't" language (the honesty + recovery clauses, which have
real jobs and must survive in production), (b) tool registration itself biasing hedged
prefaces, (c) base-model conversational habit in tool-armed sessions. Absent in the Shortcuts
probe (base model, no tools, no instructions) — so it is OUR session shape again, in a
smaller way.

Polish severity, but high visibility — it undermines trust in every on-device answer.
Instrument-first per today's lesson: cells, not vibes. Dispatch to follow.

**FIRST BATTERY RUN 2026-07-27 19:27 (n=10/cell, PR #158's instrument) — MECHANISMS FOUND.**
Full table + analysis in `planning/HANDOFF-2026-07-27-EVENING.md`. Headlines: (1) TASK-VERB
CONFUSION — "write a haiku" parses as a todo; production armed grabbed the reminder tool 8/10
(the belt's presence, not its prose, drives creative failure; toolless wrote 10/10 flawless).
(2) KNOWLEDGE-DENIAL ON COMPOSITION — "summarize Norway" refused as "can't access external
knowledge" across every tool cell; the licensing clause covers recall, not composition; Norway
content 0-4/10 everywhere. (3) The tool-less branch (never given the clause) went 0/10 on
Norway with the purest denials. (4) armed-direct LOSES (Norway 1/10, no haiku gain) — Part 2
dropped from #158 per the readout; instruction stacking is not the road. (5) Single-shot cell
verdicts on this model are unreliable — n=4 convictions did not survive n=10; rates or nothing.
Next lane: mechanism-targeted cells (ReminderTool description scope, composition-licensing
sentence, clause in the tool-less branch), after a battery rev that logs every tool invocation
(read tools fired invisibly this run).

**2026-07-27, instrument built (branch `claude/t27-196-preface-tic`, dispatch
`OPUS-T27-196-preface-tic.md`): the reworked cells + the desk picker, confirm-then-fix.**
Part 0 cherry-picks the 176C side-branch desk instrument (`8f92385`: DEBUG-only persisted
`debug.sessionShape` fallback on `activeSessionShape` — read once per process, launch env
wins — plus the Diagnostics segmented picker with the active-cell label); the side branch
itself is left for Owen to tidy. Part 1 retires `armed-noprose`/`prose-notools` (question
closed with PR #157) and rebuilds the cells for the tic: `armed` (production, the control —
the tic lives here) / `armed-direct` (production PLUS one anti-preface sentence beside the
licensing clause: "Answer directly — never begin a reply by saying you can't do something
you are then going to do.") / `armed-noneg` (production MINUS the honesty + recovery
clauses — thermometer only, NEVER shippable: it removes #176's absorbing-state protections)
/ `toolless` (production tool-less branch, no tools — discriminates tool registration,
suspect 2). Two seams in `instructionsText`, production passes neither: armed text
byte-identical to main's literal, armed-direct a pure one-sentence insertion, armed-noneg a
pure two-clause tail removal (all three script-checked). A retired cell name still
persisted on the phone parses to nil → lands on production (pinned by test; the picker
seeding normalizes the same way). Tests repinned −2/+2 (net zero): suite 1235/109 green on
27A5228h at the Part 1 tip; baseline on main confirmed 1235/109 the same day. Release
build succeeds — the seam compiles out. Part 2 (the armed-direct sentence into the
production armed branch) sits as the labeled inert tip — **do not merge-cherry-pick until
the device A/B clears `armed-direct`** — and the desk A/B must run on a Debug OTA build of
the Part 1 tip (`ad0fb73`, branch `claude/t27-196-ab-build`): a binary containing
Part 2 makes the control cell direct and collapses the comparison. The PR body carries the
per-cell checklist with the two-axis scoring (content delivered / preface present) and the
readout table.

**2026-07-27, SECOND-BATTERY LANE MERGED (PR #159, Mac-side): mechanism-targeted cells +
instrument rev.** Cells: `armed` (control) / `armed-remfix` (`createReminder` description
scoped against task-verb confusion — belt-only treatment) / `armed-complic`
(composition-licensing sentence — instructions-only) / `armed-fix` (both — the ship
candidate, same-run so interaction effects can't hide) / `toolless` (far control) /
`toolless-lic` (bare branch licensed, no-internet caveat kept). First-battery cells
retired (`armed-direct` measured loser; `armed-noneg` exonerated the clauses); retired
spellings parse to production. Instrument rev: every tool start logs per trial via
`ToolEventRelay.batteryTrialTag` (read-tool blind spot closed), battery belt built
per cell (no `activeSessionShape` leakage into tool cells), "What's 2+2?" canary,
`denial=` flag for non-prefix knowledge-denials, two-power launcher (n=10 / n=20 —
the composition verdict REQUIRES n=20: 4/10 vs 8/10 at n=10 is p≈0.17). Suite
1236/109 + 15 UI green on 27A5228h; Release build verified (instrument compiles out).
Next: Debug OTA at `d41dc6e`, one tap n=20, verdict from rates.

**2026-07-27 late night, THIRD BATTERY RUN (n=20/cell, Debug `26094e8`, branch
`claude/t27-196-decomposition-cells` / PR #160, whoGoesThere, 23:32–23:50 CDT) — THE
DECOMPOSITION READS OUT.** Six structural cells per `dispatch/OPUS-T27-196-decomposition.md`
v2, built on the Part-0 SDK findings (`GenerationOptions.toolCallingMode` — .allowed/
.required/.disallowed, per-call, iOS 27 — and `Tool.includesSchemaInInstructions`).
Classified from raw text (the instrument's 180-char prefixes); clean = no disclaimer open,
no decline-apology, no spurious tool offer, no garble — note this bar is STRICTER than
battery-2's "clean opens," so compare cells within this run, not across batteries. 3 ERROR
trials excluded from denominators (all `ToolCallError` on READ tools, norway — #197's
family): armed-readonly t9 (currentWeather), t14 (readHealth), armed-noschema t20
(readHealth). No timeouts. Grabs measured directly (`tool=` lines); all action grabs
occurred on haiku.

| Cell | Canary content (clean) | Haiku content (clean) | Action grabs | Norway content (clean) |
|---|---|---|---|---|
| armed | 13/20 (5) | 15/20 (2) | 19/20 | 5/20 (0) |
| armed-noinstr | 16/20 (12) | 15/20 (6) | 18/20 | 1/20 (0) |
| toolless-noinstr | 18/20 (0) | 16/20 (2) | 0 | 1/20 (0) |
| armed-readonly | 17/20 (13) | 6/20 (0) | 0 | 6/18 (0) |
| armed-nocall | 14/20 (5) | 19/20 (0) | 0 | 1/20 (0) |
| armed-noschema | 17/20 (8) | 10/20 (0) | 0 | 2/19 (0) |

The decomposition, comparison by comparison:
1. **Grabs are SCHEMA VISIBILITY, not prose.** armed-noinstr grabs 18/20 with ZERO
   instructions — our text was never the grab driver. armed-noschema grabs 0/20 with the
   action tools still CALLABLE but their schemas hidden — the model cannot grab what it
   cannot see. nocall (0, `.disallowed` verified — not one `tool=` line) and readonly (0,
   structural) confirm. Three independent kill switches for the confirmation-card defect.
2. **Disclaimers are BELT PRESENCE, not call ability.** armed-nocall delivers haiku 19/20
   — the best armed-path content ever measured — yet clean 0/20: every reply still opens
   "I can't write haikus, but…". Schemas in context sustain the tic even when calling is
   impossible. Canary clean tracks action-schema visibility: armed 5 / nocall 5 (schemas
   visible) vs noschema 8 / noinstr 12 / readonly 13 (hidden or gone).
3. **Readonly is a trap.** Belt minus action tools COLLAPSED haiku to 6/20 (worse than
   armed): with only read tools the model reframes as a pure data-reader ("I can't write
   haikus, but I can describe / check the weather / search"). Extending #176 availability
   gating to action tools kills grabs but deepens the identity disease — not the creative
   cure.
4. **toolless-noinstr falsifies the Shortcuts-replica premise.** The truly bare in-app
   session hallucinates a TOOL HARNESS from nothing — fake `tool:` / `response_format:` /
   JSON / XML wrappers on ~18/20 canary+haiku replies (canary clean 0/20 despite content
   18/20), plus fabricated policy on norway ("I must follow instructions not to create
   content about specific countries"). The healthy Shortcuts "Use Model" probe must carry
   its own hidden wrapper. Instructions are what SUPPRESS the scaffold — load-bearing, not
   the disease.
5. **Norway is sick in every structural cell** (max 6/18): knowledge-denial is untouched by
   structure; the licensing prose (battery-2's HELD sentence; toolless-lic 18/20) remains
   the only measured cure. armed-noinstr norway adds a new absurdity family: 19/20 trials
   grabbed searchPlaces/currentLocation and demanded LOCATION PERMISSION to summarize a
   country — read-tool capture of knowledge asks.

**VERDICT vs THE BAR** (toolless-class numbers WITH a belt available): **not met by any
cell — nothing ships from this battery.** But the armed disease is now decomposed into two
separable mechanisms with proven structural kill switches: (a) GRABS ← action-schema
visibility at decode time (kill: per-turn `toolCallingMode: .disallowed`, or
`includesSchemaInInstructions = false`); (b) DISCLAIMER/DENIAL ← belt presence in context
plus the missing composition license (cure candidates: the held complic sentence / held
licensed bare branch). Routed next lane: COMBINATION cells — nocall+complic and
noschema+complic (structural grab-kill × licensing prose) — and, if one clears, per-turn
routing (creative/knowledge turns → `.disallowed`) as the production ship path. Verdict
desk: Owen.

**2026-07-28, battery 4 built (routed cure, branch `claude/t27-196-routed-cure` / PR #161,
stacked on #160) + results-page lane (dispatch `OPUS-T27-196-results-page.md`, branch
`claude/t27-196-results-page` / PR #162, stacked on #161).** Battery 4: per-turn few-shot
guided-generation router (greedy, fail-safe to armed) → device turns get production armed;
words-only turns get `toolless-lic2` (licensed bare branch + math/facts license +
plain-prose mandate, no belt). Mac-host evidence directional only (26.5 model): router
200/200, lic2 59/60. Headless auto-battery seam shipped (launch env, triple-sink capture),
but the DEVICE run is still owed — six overnight launch attempts failed on the locked/
off-LAN phone; zero device rows exist, so no battery-4 verdict yet. Results-page lane
unblocks Console-less runs from work: structured per-trial store (FULL reply texts,
untruncated tool details, routes, latency; App Support JSON, bounded 10 runs), Diagnostics →
Battery results view with heuristic-labeled tallies + raw-reply drill-down, and export
(clipboard in the emit grammar / JSON share). Suite 1256/110 green (27A5228h). Owen installs
the OTA-staged Debug build at work, runs battery n=20 + router probe n=20, exports, pastes;
classification stays raw-text at the verdict desk.

**2026-07-28 ~08:37 CDT, BATTERY 4 RUN + VERDICT (device, n=20/cell, zero ERROR/TIMEOUT
trials — first battery with full denominators everywhere). Provenance: Owen installed the
OTA-staged Debug build (`claude/t27-196-results-page` @ `004ad98`, v1.0.0(1), iOS 27.0
24A5390f) at WORK and ran Battery n=20 via the new results page; the run JSON
(`run-20260728-133701`) arrived through the share-sheet export — the Console-less flow's
first live use, end to end. Classified from raw text (all 240 replies read).**

| Cell | Canary content/clean | Haiku content/clean | Norway content/clean | Grab trials |
|---|---|---|---|---|
| armed (control) | 17/20 · 13/20 | 14/20 · 0/20 | 3/20 · 0/20 | haiku 15/20, norway 6/20 |
| toolless-lic (A) | 13/20 · 4/20 | 20/20 · 20/20 | 18/20 · 18/20 | — |
| toolless-lic2 (B) | **20/20 · 20/20** | **20/20 · 20/20** | **20/20 · 20/20** | — |
| armed-routed | **20/20 · 20/20** | **20/20 · 20/20** | **20/20 · 20/20** | 0 (60/60 routed toolless) |

1. **armed-routed and toolless-lic2 both post 60/60 CONTENT and 60/60 CLEAN — the
   100%×3 goal (canary/haiku/norway at 20/20 content each) is MET, at the clean bar, with
   the armed control exhibiting the untreated disease in the same run** (haiku clean 0/20,
   norway content 3/20, 21 tool-grab trials). THE BAR (toolless-class numbers with a belt
   available) is met by armed-routed: the belt exists in the architecture; the router
   withheld it correctly on all 60 words-only trials (WWDC26-242-style contextual gating).
2. **lic vs lic2 head-to-head resolves decisively for lic2.** lic's device residual on
   canary: 7/20 arithmetic denials + 8/20 hallucinated `response_format:` JSON scaffolds
   (clean 4/20). lic2's two added sentences (math/facts license + plain-prose mandate)
   cure BOTH families completely — canary replies collapse to a bare "4" ×20.
3. **Router (words-only direction): 60/60 correct on device.** The device-needing
   direction is still unmeasured on 27b4 (this file carries no probe records — the Router
   probe n=20 button run is still wanted before any production promotion). Mac-host
   evidence for that direction remains 200/200 (26.5, directional).
4. **Router latency cost, measured:** canary 1.1s vs lic2 0.5s; haiku ~1.55s vs ~0.95s;
   norway ~2.25s vs ~1.65s — the router generation adds **~0.6s per turn**, cheaper than
   the ~1s feared.
5. Quirks (content+clean, noted): two routed/lic2 norway trials append an unprompted
   "Today is Tuesday, July 28, 2026." tail (t13 routed, t17 lic2) — deviceContext leakage
   flavor, cosmetic. The 26.5 Mac haiku-refusal watch-item did NOT manifest on device
   (0/60 refusals across lic/lic2/routed haiku).
6. **Promotion decision (Owen's desk): armed-routed → production.** Evidence for: the
   table; against/open: device-direction probe unrun, ~0.6s/turn router cost. The held
   battery-2 candidates remain held; nothing ships without Owen's call.

**2026-07-28 ~08:52 CDT, ROUTER PROBE RUN (device, `run-20260728-135219`, same
install/flow): 200/200.** All ten probes 20/20 — five words-only (canary/haiku/norway/
joke/poem) correctly routed toolless AND five device-needing (reminder/weather/alarm/
steps/calendar) correctly routed armed. The device-direction gap from verdict point 3 is
CLOSED; 27b4 matches the Mac's 200/200. Remaining promotion consideration is solely the
~0.6s/turn router cost (point 4). Verdict desk: Owen.

**2026-07-28 ~09:05 CDT, PROMOTED (Owen's call, after a live-path spot check on novel
prompts).** armed-routed is the production session architecture: PR #163
(`claude/t27-196-promote-routed`, stacked on #162; dispatch
`OPUS-T27-196-promote-routed.md`). Release routes every turn — words-only turns get NO
belt + the toolless-lic2 text, device turns get the pre-promotion armed session verbatim,
router errors fail safe to armed. Router machinery left DEBUG (prompt/options pinned);
DEBUG A/B intact with default flipped to armed-routed; legacy cells disable routing per
launch. Suite 1258/110 green + Release-config build SUCCEEDED (the promoted code's first
compile outside `#if DEBUG`), 27A5228h. Merge order #160 → #161 → #162 → #163. Device
verification of the promoted default: staged for Owen's install. THE BAR: met — this item
closes on merge.

Logged 2026-07-27; battery-4/results-page note 2026-07-28; battery-4 VERDICT 2026-07-28;
router probe 200/200 2026-07-28; PROMOTED 2026-07-28.

## 197. ✅ Tool-invocation failure aborts the turn and renders the RAW error — types, descriptions, and a memory address in the transcript — **CLOSED 2026-08-04 (closure sweep): both defects fixed; the unexplained decode cause becomes a WATCH on the armed instrument**

> **✅ CLOSED 2026-08-04 (queue item 3 closure sweep).** Both stacked defects
> are fixed and merged: the raw-error rendering (2026-07-31 — only `tool.name`
> surfaces, pinned by tests) and the dead turn (2026-08-02 — the once-only
> decode retry, six truth-table rows RED-witnessed). **What stays open is not
> app work: the decode failure's upstream CAUSE is unexplained** — and per the
> never-blame-Apple rule that is recorded as *unexplained*, not attributed.
> **WATCH, on the instrument already armed:** every retry logs a notice and
> bumps `toolDecodeRetryCount`; the failure class is spurious, so observation
> is opportunistic by nature. **Reopen triggers:** a second-consecutive-failure
> message reaching the user in the wild, or a verbose pass showing the counter
> climbing (the retry masking a worsening decode layer rather than absorbing a
> rare one).

**Observed 2026-07-27 18:23, device, airplane mode, armed cell (#196 A/B battery, fresh
chat).** "Write a 50 word summary about Norway" → the model spuriously invoked WeatherTool
(place-name → weather association; no weather was asked for) → the invocation failed with a
FoundationModels "Failed to parse generated content" → the turn DIED with a Retry affordance
and the transcript rendered the raw error verbatim: tool name, the full description string,
`RELAY: TALARIA.TOOLEVENTRELAY`, and a live pointer (`<TALARIA.DEVICELOCATIONPROVIDER:
0x108BD0B00>`).

Two stacked defects:
1. **Raw internal error as a chat message.** Internal type names and memory addresses are
   never user-facing content. The streaming path evidently catches (or fails to catch) the
   thrown tool-invocation error and surfaces its description into the transcript.
2. **The #176 recovery clause is unreachable on this failure class.** "A failed or denied
   tool is never the answer — answer without it" operates INSIDE a model turn; a tool
   invocation that throws kills the turn upstream, so the model never gets to recover. The
   instruction-level absorbing-state exit has a machinery-level hole.

**DEFECT 1 FIXED 2026-07-31 — and the cause was one line.** `failureMessage` humanized
`LanguageModelSession.GenerationError` and fell through to `error.localizedDescription`
for everything else. **A tool throw is a `ToolCallError`, not a `GenerationError`** —
and `ToolCallError` carries `tool: any Tool`, the **live instance**, so describing it
reflects the struct's stored properties. That is exactly how the transcript got the
tool's full description string, `RELAY: TALARIA.TOOLEVENTRELAY`, and
`<TALARIA.DEVICELOCATIONPROVIDER: 0x108BD0B00>`.

`ToolCallError` is now matched explicitly and **only `tool.name` is surfaced**.
Pinned by a test that asserts the message contains the tool name and contains none of
`RELAY`, `TOOLEVENTRELAY`, `0x`, `Talaria.`, the type name, or the underlying error —
and that it is not the raw description. A third test pins that the `GenerationError`
mapping #30 relies on is unchanged.

**DEFECT 2 — the message now does the recovering, because nothing else can.** The
#176 clause operates INSIDE a model turn; this class throws **above `call()`** (the
argument-DECODE layer), killing the turn upstream, so **no tool can catch it and the
model never gets to recover**. Feeding a terse failure back to the session — the
original fix direction — is therefore not reachable for this class. What is reachable
is the sentence: *"Talaria couldn't read the arguments for X on that turn. Ask again
and it should go through."* Names what failed, leaks nothing, and gives a path.
**Same shape as #201B's continuation clause and #202D's clause v2, both of which
measured well.**

**Verified WITHOUT a device run** — this is pure error-mapping logic, so unlike every
other lane today it is fully unit-testable. Suite 1382/1382.

**STILL OPEN:** the turn still dies, and the underlying decode failure is unexplained
— **#208 removed the token cap as its standing suspect**, so the argument-decode layer
itself is now the only candidate. An automatic single retry is the obvious next
question and is a product decision, not a code one (same family as #203's residue).

> **RETRY DECIDED AND BUILT 2026-08-02 (Owen: "go") — `claude/t27-197-decode-retry`.**
> The turn no longer dies on the observed shape. `shouldRetryToolDecodeFailure` re-runs
> the turn **exactly once**, gated on ALL of:
> 1. **Decode class only** — `ToolCallError` whose underlying error is
>    `GenerationError.decodingFailure` (typed) or carries "Failed to parse generated
>    content" (#210's content-backstop pattern, applied from day one). **The successor
>    `LanguageModelError` declares NO decode case** — verified against the beta-4
>    swiftinterface — so the deprecated case + backstop are the whole class. This class
>    throws ABOVE `call()`: the failing tool never executed, so the retry cannot
>    double-fire it. An error a tool threw from inside `call()` (#200H's readHealth)
>    never retries — the tool may have completed its side effect first.
> 2. **Zero observable activity** — no text delta, no reasoning delta, no tool event
>    this turn. A DIFFERENT tool that already completed would run AGAIN on the retried
>    turn, and painted text would restart mid-bubble. The observed specimen (spurious
>    WeatherTool grab as the turn's first action) is the nothing-shown shape, so the
>    constraint costs almost no coverage. Tracked via an `OSAllocatedUnfairLock` flag
>    fed by both yields and the tool-relay emit hook (chained in the sync path so a
>    harness observer survives).
> 3. **Once** — the second failure surfaces the existing #197 message.
>
> Both paths (sync `send` + `streamTurn`), each mirroring the adjacent #26 condense
> arm; the session is rebuilt from our history on retry (#102's transcript-unknowable
> rule). **The recovery never hides the defect:** every retry logs a notice and bumps
> `toolDecodeRetryCount` — because the decode failure's CAUSE is still open, above.
>
> **Honest limits:** the policy is pure-tested (six truth-table rows, REDs witnessed);
> the WIRING cannot be exercised by the suite — a real FM turn doesn't run in sim
> tests — so it rests on mirroring the proven condense arm plus review. Device
> verification is opportunistic by nature (the failure is spurious): the next natural
> occurrence should produce a silent recovery + the notice + a counter bump instead of
> a dead turn, and a SECOND consecutive failure still shows the message.

**Original fix direction, for the record:** catch tool-invocation errors in the streaming worker; log the full detail
(`chatLog`), surface a friendly failure — or better, feed a terse tool-failure result back to
the session so the model can apply the recovery clause and answer without the tool (which is
what the instructions already promise). Related but distinct observation for the #196 lane:
spurious tool grabs on non-tool asks persist post-#194 at some rate — the desk A/B should
score a THIRD axis (tool chip present on a non-tool ask) alongside content/preface.

Logged 2026-07-27.

## 198. ✅ Beta-4 SDK deprecation sweep — ~20 warnings, 6 clusters

> **CLOSED — header flipped 2026-08-01 (Hermes audit Part 1A).** The beta-4 deprecation sweep is DONE — all three structural clusters migrated and the 2026-08-01 device pass PASSED. **Residual probes are device-list A1/A2/E1.** The header's '~20 warnings, 6 clusters' count is superseded by the per-cluster counts inside.

> ## ✅ **E1 RAN 2026-08-01 — the `installTap` migration's rationale is CONFIRMED, no longer inference.**
>
> This entry's `installTap` cluster was migrated on the reasoning that *"the
> successor returns an error instead of raising"* — and that sentence was
> **reasoning from a header comment, never executed.** It has now been executed.
>
> **iOS 27.0 simulator (`24A5390f`), standalone binary under `simctl spawn`, two
> identical runs, process exit 0 both times:**
>
> ```
> mainMixer THREW — Error Domain=com.apple.coreaudio.avfaudio Code=-10863
>                   UserInfo={false condition=nullptr == Tap()}
> ```
>
> **`nullptr == Tap()` is the exact condition string from #128's 2026-07-17
> device crash.** Same assertion, now a catchable Swift error rather than an
> uncatchable Objective-C exception.
>
> **It also settled #82's half for free, which nobody asked it to.** The
> simulator's `inputNode` reports a degenerate format (rate=0.0) — *#82's own
> wedge shape* — and that install threw too (`Code=-10868`,
> `IsFormatSampleRateAndChannelCountValid(format)`). **Both hand-rolled
> mitigations in this codebase — #82's format preflight and #128's `removeTap`
> adjacency — now guard failures the API reports rather than raises.** Neither
> was written knowing that.
>
> **Both preflights STAY.** They prevent the failure; E1 only prices the residue.
> A recoverable throw is a better floor, not a reason to remove what stops you
> reaching it.
>
> **Limits, stated because the result is favourable:** simulator not hardware; the
> double-install ran on `mainMixerNode` because the sim's `inputNode` cannot
> complete a *first* install. **`inputNode` double-install on real hardware stays
> unmeasured** — queued as a zero-setup rider on any native voice session
> (device-list §F6). Full verdict and the probe's provenance: device-list §E1.

Filed from the 2026-07-27 evening sweep (cluster enumeration lives in
`planning/HANDOFF-2026-07-27-EVENING.md`; representative: the
`LanguageModelSession.GenerationError` family around `isContextOverflow` /
`failureMessage`, visible in every Release build log). Zero behavioral impact today;
the risk is beta-5+ removing the deprecated symbols mid-flight. Disjoint,
mechanical, safe to route to any executor as an isolated lane. Status: filed,
unrouted.

Logged 2026-07-28.

## 199. ✅ On-device brain fabricates a COMPLETED ACTION after a declined confirmation

> **CLOSED — header flipped 2026-08-01 (Hermes audit Part 1A).** Verdict filed — disease confined to grabs, intended-create path clean. **The false-attribution family it surfaced is now lane #199A.**

Observed battery 2 (2026-07-27, build `686d2e2`, cell `armed`, haiku t=11): the
confirmation gate auto-declined `createReminder`, and the reply then claimed Ive
also created a reminder for you to reflect on sledding" — a fabricated completed
action. Distinct from and worse than the #196 disclaimer tic: it asserts a
side-effect that never happened, violating the real-data-only rule and the #176
honesty clause ("never invent a value" — this invents an ACTION). Observed once
across ~35 declined grabs in batteries 2–3 (low rate, high severity: phantom actions
are a trust-breaker). Repro path: battery instrument, armed cell, haiku prompt,
auto-decline armed. Fix territory (unrouted, pending the #196 endgame): strengthen
the post-decline turn framing, or detect claim-vs-tool-result mismatch before
render. Parent: #196.

Logged 2026-07-28.

## 200. ✅ Armed path refuses APPROPRIATE device actions — read-for-create substitution, then capability denial that survives corrections — **CLOSED 2026-08-04 (closure sweep): the disease is measured CURED — #204's warm scoreboard is 30/30 across all three create intents**

> **✅ CLOSED 2026-08-04 (queue item 3 closure sweep).** The defect this item
> filed — appropriate creates refused — was treated through the measured
> promotion arc this entry documents and its cure is on the record: **remind
> 0/50 lifetime control → 75% (#200G) → 90% (#200K) → 10/10; calendar 53% →
> 10/10; alarm 10/10 throughout** (#204 verdict run `E3759EE3`, production
> cell, warm). Zero spiral, zero invented locations, zero card narration in
> that run. **Residues all have named owners and none belong here:** the
> false-attribution family → **#199A**; router/context misroutes → **#202
> (closed)**; the structural over-serving question → **#214 (closed, both
> directions answered)**; the window/overflow class → **#229 (built
> 2026-08-04)**. The multi-turn offer→denial instrument, queued behind the
> treatments all series long, is **MOOT under Owen's standing
> moot-retirement note**: its entry point (read-then-offer on a failed
> create) existed only while creates failed — at 10/10 there is no failed
> create to offer after. The #200-series cell contrasts remain valid as
> contrasts and are read per the #215 measurement-discipline rule (armed
> cells, not production facts).

Observed 2026-07-28 09:28–09:29 CDT, whoGoesThere, promoted build (`8e99402` Debug,
armed-routed default), live chat, Owen's post-promotion spot check (screenshots on the
verdict desk). "Remind me to test talaria at 4:30pm" — the router correctly sent every
attempt ARMED (tool chips rendered), then the armed session failed the action path
end to end:

1. **Wrong tool**: the create request fired `readReminders` (the READ tool) — never
   `createReminder`. Twice on the initial prompt, again on a later explicit "you create
   it" — three reads, zero creates, so the #29 confirmation card never even appeared.
2. **Absorbing state, action flavor (#176B recurrence)**: the first turn's honest
   permission-denied tool result became every later turn's answer. After Owen granted
   Reminders access AND the model itself read real reminders and OFFERED "Would you
   like to create one now?", his "Yes please" produced a flat capability denial — no
   tool call at all — escalating over four turns to "I can't access your iPhone's apps
   or settings, even if you've enabled permissions." False: `createReminder` was
   registered in that session, and battery evidence shows the model calls it readily —
   on HAIKU prompts (15/20 inappropriate grabs, battery 4 armed cell).
3. **Confabulated app model**: readReminders results referencing Owen's "Job Hunter"
   reminders were woven into fiction — "open Job Hunter App, tap 'Reminders,' and set
   a new one" — misdirecting the user into a third-party app that cannot do this.

The through-line with #196 is the same task-verb confusion, INVERTED: there the model
grabbed `createReminder` when nobody asked; here it refuses the identical tool when
explicitly asked. NOT a promotion regression — the armed session is byte-identical
pre/post promotion (pinned), and no #196 battery ever measured the action-SUCCESS
path (the auto-decline contract made grabs measurable but "does an appropriate create
go through" was never a cell). Coverage gap, now the frontier.

Lane sketch (pending Owen's routing): (a) instrument first — an action-path battery
cell ("Remind me to X at Ypm" ×n) needing a new auto-ACCEPT (or at least
count-the-card) mode on the confirmation gate, since auto-decline can't measure
success; (b) verify ReminderReadTool/ReminderCreateTool EventKit authorization flow
requests on first use per #31 (the first turn reported missing permission without
prompting); (c) fix territory afterward: tool descriptions disambiguating read vs
create intent (the #196 remfix seam exists), and the #176B recovery clause extended
to permission-recovery ("a permission granted mid-conversation supersedes every
earlier denial"). Related: #197 (raw error rendering), #199 (post-decline
fabrication). Parent: #196.

Logged 2026-07-28.

**#200 addendum, 2026-07-28 09:50 CDT (merge-gate flip test, same promoted build):** a
second misattribution specimen, read flavor — "What's the weather right now?" routed
armed, `currentLocation` RESOLVED (chip shows Gulfport, MS), `currentWeather` then
failed (the #197 Weather/Health error family; WeatherKit flakiness on 27b4 has battery-3
precedent), and the reply blamed LOCATION ACCESS: "Would you like to try enabling
location access for a fix?" — inventing the wrong cause while its own transcript shows
location succeeded. Same wrong-cause-suggestion mechanism as the reminder case, no
create/permission involved. The action battery's classification should count
"misattributed failure cause" as its own column. (Same turn's flip-back haiku also
carried the deviceContext date-leak tail — "Tuesday's deep breath" — cosmetic, tracked
in the #196 verdict quirks.)

**#196 CLOSED 2026-07-28 (~10:00 CDT).** The full stack is merged to main in order:
PR #160 (decomposition cells, `5e55b22`) → #164 (routed cure, `c05d912` — recreates #161,
which GitHub closed permanently when #160's head branch was deleted pre-retarget; lesson:
retarget stacked PRs BEFORE deleting a base branch) → #162 (results page, `7bd3351`) →
#163 (promotion, `62d7654`). Production is armed-routed. Merge-gate device test passed:
words→device→words route flip in one conversation, tools firing on the armed half,
context surviving both session rebuilds. Follow-on items carry the remainder: #197 (raw
tool errors), #199 (post-decline fabrication), #200 (action-path refusal + misattribution;
dispatch OPUS-T27-200-action-path.md ready on main). Item closed — five batteries, four
PRs, one architecture.

**#200 update, 2026-07-28 (instrument lane BUILT — PR #165, branch
`claude/t27-200-action-instrument`, head `a6accab`, OTA-staged Debug).** Dispatch
OPUS-T27-200-action-path executed: Parts 1+2 complete, Part 3 verified code-side with
NO code change. (1) Gate: `autoAcceptForBattery` alongside the #196 auto-decline —
decline checked FIRST (fail-safe: never-create if both flags ever set); auto-accept
approves the STAGED values with the `[T27-battery]` marker injected (title prefix;
alarm-request suffix — the alarm grammar takes its time token first, so the marker
lands in the label, pinned through `AlarmService.parse`); every gate resolution emits
`battery: confirm=accepted|declined <trial tag>` and records it. Capture field lives
per TOOL CALL (`BatteryToolCallRecord.confirmation`, optional — deliberate deviation
from the dispatch's per-trial field: the grammar is per action-tool invocation, and
per-call pairs each outcome with the invocation that staged it); pre-#200 run JSONs
decode unchanged (fixture-pinned). (2) Action battery: Diagnostics "Action battery
n=20 (60)" — remind ("Remind me to test Talaria at 4:30pm", the observed failure) /
alarm ("Set an alarm for 6:30") / calendar ("Put lunch with Sam on my calendar Friday
at noon") × 20 each, ARMED production construction (armed-routed armed branch ≡ armed —
identity in shapedBelt/instructionsText/options — so the cell label is `armed`), no
per-trial routing, shared trial executor extracted from the shape battery (heuristics
can't drift), export gains confirm lines + action-run `confirm=none` synthesis
(pre-gate bail, e.g. unparseable alarm time) + REAP line, all `(#200)`-marked; legacy
#196 exports byte-identical (pinned). Teardown BEFORE DONE reaps marker-matched
reminders/events (EventKit, idempotent across crashed runs) and battery alarms by
tracked ID (AlarmKit enumeration returns no labels); missing read access reports
`skipped(no-access)`, never a silent zero. Classification caveat: created titles carry
the `[T27-battery] ` prefix — instrument residue in tool results and echoing replies.
(3) Part 3 (#31): ALL four EventKit tools + AlarmService already request contextually
on `.notDetermined`, and every usage-description key is in `project.yml` — the spot
check's "missing permission, no iOS prompt" is consistent with status `.denied` at the
time (iOS never re-prompts after a deny), NOT a missing request call. Secondary
hypotheses if device-verify contradicts: the tools' `try?` swallows a thrown 27b4
EventKit error as "not granted", or beta full-access semantics changed. Device verify
needs a permission reset (app delete → re-pair) — Owen's call on timing. Evidence:
unit suite 1269/1269 green in 110 suites (baseline 1258 + 11 capture pins;
Xcode-beta4 SDK, 27.0 sim); Release-config build clean (everything `#if DEBUG`-gated);
UI suite not run (no UI test touches the battery surfaces). NEXT: Owen runs the
battery (Reminders/Calendar GRANTED), exports from Battery results, pastes for
classification — columns: tool(s) fired (wrong-tool `readReminders` substitution
primary), confirm outcome, reply class (honest-confirmation / fabricated-action —
#199's denominator / denial / misattributed-failure-cause), ERROR trials excluded and
listed. Multi-turn absorbing-state instrument deliberately NOT built until these
single-turn numbers say where the failure concentrates. Treatments route at the
verdict desk afterward — none shipped in this lane.

**#200 update, 2026-07-28 afternoon — battery crash saga RESOLVED (root cause named by
.ips), instrument device-verified end to end, preliminary n=20/prompt data in hand.**
Four consecutive action-battery runs (two n=20, two n=5) crashed mid-run. Debug arc, for
the record: (1) per-trial snapshot persistence + endedCleanly seal shipped after runs 1–2
lost everything → runs 3–4 survived their crashes carrying every trial, which localized
the death to the teardown reap (all trials present, never sealed); (2) the alarm sweep
(42 orphans cancelled clean) exonerated AlarmKit cancel; (3) a sim probe of the reap's
exact EventKit ops PASSED on a fresh 27.0 store while every device run died — read then
as content-dependence, and the events query was narrowed to writable calendars/−1d…+14d
(kept as scope-correctness, but aimed at a step that never ran); (4) Owen's two .ips
files named the truth, identical frames in both: `EXC_BREAKPOINT brk 1` →
`_dispatch_assert_queue_fail` → `_swift_task_checkIsolatedSwift` in the reap's
`fetchReminders` COMPLETION, faulting queue `com.apple.eventkit.reminders.search`. The
closure, formed in MainActor context, inherited MainActor isolation; EventKit invokes it
on its private queue; the 27b4 DEVICE runtime dynamically enforces the check (the SIM
runtime does not — why the probe passed). ReminderReadTool's twin closure never crashed
because Tool.call is nonisolated. Fix: `@Sendable` on the completion (`972af5c`).
**Run 5 (n=5, build `4d419a9`) completed and SEALED: `reminders=0 events=13 alarms=4
failures=0` — the reap swept all 13 Lunch-with-Sam events the crashed runs had
accumulated; phone ends clean.** New standing gotcha (memory + here): on 27b4, closures
handed to framework completion APIs from MainActor contexts trap ONLY on device — sim
green proves nothing for this class; mark framework completions `@Sendable`.
Preliminary single-turn action-path numbers, four surviving records (runs 1/2/3/5 =
n=20 per prompt, 0 ERROR trials): **remind 0/20 creates** (≈11 clarify-stalls — six ask
"which list?", the createReminder `list` field read as required-blank; ≈7 readReminders
substitutions, two carrying the spot check's exact "I don't see a reminder — would you
like me to create one?" signature; 2 cant-flavored), **alarm 19/20 creates** (all
accepted, honest confirmations; 1 recurrence-clarify stall), **calendar 3/20 creates**
(≈15 lookupContact("Sam") fixation absorbing the task; 1 fabricated constraint — "no
free slots Friday" after reading only 2 days ahead — the misattributed-cause column,
live; creates that DID land pulled currentLocation+searchPlaces and attached a
location). Confirmation capture worked throughout: every create carries
confirm=accepted; zero declines; zero pre-gate bails. Mechanism read for the verdict
desk (NOT treated in this lane): the model stalls on optional-but-present schema fields
instead of defaulting — single-field alarm 19/20 vs three-field reminder 0/20 is the
cleanest dose-response #196/#200 has produced. NEXT: Owen runs Action battery n=20 (60)
on `4d419a9` for the fileable table; multi-turn absorbing-state instrument still
deliberately unbuilt pending those numbers.

**#200 MEASUREMENT FILED, 2026-07-28 evening — Action battery n=20 (60 trials), build
`4d419a9` Debug, armed production construction, auto-accept armed, permissions granted,
run sealed clean (`reminders=0 events=3 alarms=19 failures=0` — created == reaped
exactly). Classified from raw text. One TIMEOUT excluded and listed below; zero ERROR
trials.**

| cell | creates | wrong-tool substitution | clarify-stall | fabricated/misattributed cause |
|---|---|---|---|---|
| remind | **0/20** | 5 (`readReminders`) | 15 | 3 of the 5 substitutions carry false-inability framing |
| alarm | **19/20** | 0 | 1 | 0 |
| calendar | **3/19** | ~13 contact-lookup fixation (+1 searched "Sam" as a PLACE) | most non-creates end in a question | 3 |

Confirmation capture across the run: 22 staged, 22 accepted, 0 declined, 0 pre-gate
bails — **the gate never blocked an appropriate create; every reminder/calendar failure
happens BEFORE tool selection.** Excluded trial: calendar t4 TIMEOUT — a
`searchConversations` name-spiral (Sam, Shelley, Adam, Amanda, Brent, Corey, Desiree,
Scott, Owen — 15 tool calls) guillotined at 35s; the contact-fixation absorbing state in
its extreme form. Mechanism findings, now at rate: (1) **optional-field stall** — 15/20
remind trials interrogate the `list` (± date) field instead of defaulting ("which list
should this go in?"); the single-field alarm tool goes 19/20 — the cleanest
dose-response of the whole investigation, and the direct treatment target for the
remfix-style seam. (2) **read-for-create substitution** 5/20, three ending in "would you
like me to create one?" offers a single-turn battery cannot answer — the observed
spot-check entry point; the multi-turn absorbing-state instrument is now JUSTIFIED by
these numbers. (3) **contact fixation**: "with Sam" parses as requires-a-contact and its
absence absorbs the task (~13/19), with two trials emitting corrupted lookup args
("Sam}<ctrl43>" — #197-family token leakage, one echoed the garbage to the user).
(4) **fabricated constraints**: "today's calendar is all booked" (after reading 3 days,
never Friday), "can't create a calendar event without the location" (location is
optional in the schema), "couldn't retrieve location… needs a live connection" — the
misattributed-cause column at ~3/19. (5) remind t1 self-contradicts inside one reply
("I can't see any reminders yet" followed by Owen's actual reminder list). Consistency:
the four earlier n=5-scale records (independent 20/prompt) match every rate direction —
remind 0/20 there too, alarm 19/20, calendar 3/20. Same-day legacy shape battery
(n=20×4 cells, sealed) re-verified production armed-routed at 60/60 clean content while
the armed control keeps its known diseases (canary tic 15/20, haiku grab 14/20 now with
confirm=declined captured, norway denials, one #197 malformed-tool-name ERROR).
**Lane complete: instrument built + crash-hardened, root cause fixed and
device-verified, table filed. Treatments route at the verdict desk — candidate order
from the data: createReminder `list` @Guide de-stall ("empty = default, do not ask"),
createCalendarEvent contact/location de-fixation, then the multi-turn instrument for
the offer→denial absorbing state. None shipped in this lane.**

**#200B VERDICT FILED, 2026-07-28 night — destall battery n=10 (160 trials, PR #166
branch `bc68112`, run sealed, `reminders=27 events=5 alarms=40 failures=0` — reap
arithmetic independently confirms the classification counts). First attempt was
INVALIDATED by a concurrency contamination (two loops from a view-scoped guard; fixed
with a backend-owned battery mutex, pinned) — clean rerun classified below. ERROR
trials excluded and listed: armed/calendar/t4 (8,583-token context overflow from a
searchConversations spiral) and armed-toolfix/alarm/t4 (ModelManager 1041 AFTER the
accepted schedule; artifact created and reaped). Zero timeouts.**

| cell | remind creates | alarm | calendar creates | haiku GRABS |
|---|---|---|---|---|
| armed (control) | 0/10 | 10/10 | 0/9 | **8/10** |
| armed-guidefix | 0/10 | 10/10 | 0/10 | 7/10 |
| armed-toolfix | 0/10 | 9/9 | 1/10 | 6/10 |
| armed-bothfix | 1/10 | 10/10 | 4/10 | 5/10 |

**Treatment verdict: the tool-text seam does NOT reach the remind stall — 0/0/0/1
across 40 trials.** The de-stalled @Guide ("empty is correct — never ask which list")
and the de-stalled description ("create immediately; never ask first") both left the
clarify-stall intact and verbatim ("which list should this go in?"). Mechanism
refinement: the stall happens at RESPONSE PLANNING, before the model ever engages the
tool schema — text inside the tool cannot treat a disease that fires before tool
selection. NOTHING PROMOTES from this battery (dispatch discipline held; two cheap
text candidates falsified at n=10 before anything shipped). Second headline, from the
grab canary: **production armed grabs createReminder on 8/10 haiku prompts under
auto-accept** — the #196 grab disease is fully alive on the armed half whenever the
gate approves; production is protected ONLY by the router, and the unshipped
remfix-scoped description was in none of these cells. The treatments trend grabs DOWN
(8→7→6→5), not up — the feared collateral did not materialize. Curious tertiary:
calendar creates ROSE in bothfix (4/10 vs 0-1 elsewhere) — schema/description texts
ride in the session instructions, so the reminder tool's "create immediately" plausibly
bled into general behavior; n=10, direction only. New specimens for the files:
armed-toolfix/haiku/t6 dumped HEALTH DATA into a haiku reply (readHealth scope-creep);
armed-guidefix/calendar/t8 dumped the entire week's calendar into a reply;
armed-bothfix/calendar/t5 CREATED the event with a confabulated city (Houston, TX —
from a searchPlaces("lunch with Sam") result — while the phone sat in Gulfport);
armed-bothfix/haiku/t10: "I can't write a haiku, but I made a reminder for you to
sledding" — tic + grab + garble in one sentence. NEXT candidates for the verdict desk,
now correctly aimed upstream: (a) an INSTRUCTIONS-level de-stall clause (the
`instructionsText` seam — same promoted-payload territory as #196's lic2), (b) the
multi-turn offer→denial instrument (the read-then-offer entry replicated again at
~15-20% of remind trials), (c) the still-unshipped remfix scoped description as
grab insurance if the router ever misroutes. The #200B instrument (cells + canary +
mutex) is reusable as-is for any future text candidate.

**#200C VERDICT FILED, 2026-07-28 night — instrfix battery n=10 (80 trials, PR #167
branch `6f8da47`, run sealed clean `endedCleanly:true`, `reminders=13 events=9
alarms=18 failures=0` — reap arithmetic confirms the classification exactly:
13 reminders = 2 instrfix-remind creates + 9 control haiku grabs + 2 instrfix haiku
grabs; 9 events = 8 instrfix-calendar creates + 1 instrfix haiku CALENDAR-grab;
18 alarms = 8 control + 10 instrfix). ERROR trials excluded and listed:
armed/calendar/t1 ("Session ended without producing a response", 30s, after
readCalendar) and armed-instrfix/haiku/t7 (ToolCallError: createReminder
GeneratedContent missing 'title', args were only {due, list} — itself a FAILED grab
attempt). Zero timeouts.**

| cell | remind creates | alarm | calendar creates | haiku GRABS |
|---|---|---|---|---|
| armed (control) | 0/10 | 8/10 | 0/9 | **9/10** |
| armed-instrfix | **2/10** | **10/10** | **8/10** | **3/9** |

**Treatment verdict: the INSTRUCTIONS seam is LIVE — the identical clause that did
nothing from inside the tool schema (#200B) moves all three action prompts when
spoken from `instructionsText`.** Calendar is the headline: 0/9 → 8/10 (lifetime
control aggregate 3/28), and the mechanism is visible in the traces — control
fixated on lookupContact("Sam") in 8/9 valid trials (the corrupted arg `Sam}`
appeared in 5 of them, #197 family), instrfix called lookupContact in only 2/10:
"create it right away" de-licensed the whole contact-resolution side quest even
though the clause never mentions contacts. Alarm 8/10 → 10/10 (control stalls:
"today or a specific date?", "repeat, or just ring once?"). Remind moved OFF ZERO —
2/10 vs a lifetime control of 0/40 and a best prior treatment of 1/10 (bothfix);
both creates ran readReminders first, the check-first habit surviving but no longer
terminal. But the list-stall persists in 5/10 WITH the clause explicitly saying
"never ask which list" — remind remains the deepest form of the disease. Second
headline, the RISK INVERTED: the feared grab cost did not materialize — haiku grabs
went 9/10 control → 3/9 instrfix. The antecedent ("When the user ASKS for a
reminder…") appears to sharpen creation licensing in BOTH directions: more creates
when asked, fewer when not. The visible collateral is milder and new: 4/9 instrfix
haiku trials refused the poem outright with cant=true (vs 1/10 control) — the clause
makes the model action-conservative enough to sometimes decline the creative task
itself — plus one garbage create (title `","` while apologizing "I can't write a
haiku right now"). New specimens: armed-instrfix/calendar/t1 CREATED "Lunch with
Sam" located at **Rural Damascus, Syria (6,777 miles away)** — searchPlaces("Sam")
first-hit-as-venue, outdoing Houston; armed-instrfix/haiku/t1 grabbed via CALENDAR —
a 120-minute "Sledding" event at "an outdoor snowy area"; armed-instrfix/calendar/t5
ran a seven-call spiral ending in currentWeather then blamed "couldn't access your
current location or weather or weather data"; armed/calendar/t9 fabricated
"your calendar is already full for Friday" with cant=true; armed-instrfix/remind/t6
plan-stalled with a hallucinated due date of 2026-07-08 — three weeks in the PAST.
Instrument note (mild confound, flag for future remind cells): in-run artifact
contamination — instrfix remind t3/t8 readReminders FOUND t1/t9's `[T27-battery]`
artifacts and reported "you already have a reminder" (reap is end-of-run, so earlier
creates are visible to later read-inclined trials in the same cell); both affected
trials were read-bound anyway, but per-trial unique titles or a mid-run reap would
close it. NEXT: the clause meets the dispatch's success bar (remind off zero at
negative grab cost) — promotion follow-up on the table per the dispatch (#163-style:
flip `includeActionDestallClause` on in production `instructionsText`, update the
byte-identity pin to the new production text, battery re-verify on the promoted
build); Owen routes. Remaining queue behind it: the multi-turn offer→denial
instrument; remfix scoping as router insurance; calendar contact de-fixation may be
moot — this clause largely cured it from upstream.

**#200D PROMOTION SHIPPED, 2026-07-28 night (routed by Owen: "yup, merge and start
on the next"; PR #167 merged `28551c7`, promotion branch
`claude/t27-200-promote-clause`): `includeActionDestallClause` defaults TRUE in
`instructionsText` — the de-stall clause is production.** One edit flips every
production path by construction (Release call, DEBUG `armedRouted` default shape,
every structural cell pinned as production-verbatim, the batteries' control cells);
the toolless branches are `hasTools:false` and never carried it. Explicit `false`
stays as the pinned ROLLBACK seam — the pre-promotion text, byte-identical, one
default-flip away. TDD: the #200C off-by-default pin inverted to
`actionDestallClauseIsProductionDefaultAndRemovable` (clause verbatim at its
measured seam — after the confirmation-card sentence, before honesty-and-recovery;
explicit-true identity; explicit-false removes exactly the clause; toolless clean),
watched RED (3 expectations, the other 51 suite tests green) then GREEN after the
flip. Full suite **1282/1282 in 111 suites**. The `armed-instrfix` cell is now
identity with control, which makes the Diagnostics "Instrfix battery n=10 (80)"
button the RE-VERIFY instrument for free: 2× replication of promoted production,
20 trials/prompt including the grab canary. AWAITING: Owen installs the promoted
build and runs it; expected if promotion holds — both cells replicate the #200C
treated rates (remind ~2/10, alarm ~10/10, calendar ~8/10, grabs ≤3/10 per cell).
Re-verify verdict files here on classification. Queued behind it: the multi-turn
offer→denial instrument; remfix scoping as router insurance; the battery
artifact-contamination fix (per-trial unique titles).

**#200D re-verify attempt 1, 2026-07-28 late — STALE INSTALL (run `98DF19D1`): the
export came from the PRE-promotion app.** Proof is behavioral and arithmetic:
post-promotion both cells speak byte-identical instructions, but the run is
sharply asymmetric — armed remind 0/10, calendar 1/10 (8 contact-fixations),
grabs 8/10 vs instrfix remind 2/10, calendar 9/10, grabs 2/8 — the exact #200C
control/treated signatures; reap `reminders=12 events=10 alarms=19 failures=0`
matches that classification exactly (12 = 0+2 remind creates + 8+2 grabs;
10 = 1+9 events; 19 = 9+10 alarms). The staged ipa was verified CORRECT (the
binary contains the promoted clause; staged 17:42 CDT, run started 17:50 CDT) —
the phone ran the still-installed `6f8da47` app. Instrument hole closed on the
branch: `ota-stage.sh` now stamps CFBundleVersion with the branch commit count,
so every future run record proves its build via `appBuild` (previously always
"1" — a stale install was indistinguishable except by behavioral signature).
BONUS SCIENCE: as an accidental third replication on fresh trials the #200C
contrast reproduced — treated calendar 9/10 vs control 1/10 (aggregate on this
instrument: treated 17/20 vs control 1/19), treated remind 2/10 AGAIN with the
same read-then-create shape (control 0/10; lifetime control 0/50), grab
suppression replicated (8/10 → 2/8). TIMEOUT trials excluded and listed:
instrfix/haiku/t1 (latency 2371s — timedOut recorded, but the wedged respond
still blocked the loop ~39 min; hung-respond instrument note for later) and
instrfix/haiku/t9 (578s). New specimens: THREE treated calendar events venued at
Owen's HOME ADDRESS (currentLocation → "19200 Crestwick St" as the lunch venue);
one venued "Shelley work @ Memorial Hospital" — a location lifted from an
unrelated calendar event it had just read (cross-event leakage, no contact
lookup involved); `searchPlaces("lunch}<ctrl43>")` corruption feeding a created
event's venue ("Cuandet Rd 43, Gulfport"); armed/calendar/t9 echoing
`Sam}ctrl43` verbatim in user-facing reply text; armed/remind/t1 fabricating a
capability denial ("I don't have the ability to create reminders") with
cross-tool deflection; instrfix/haiku/t7 saying "I can't create reminders right
now" WHILE its accepted createReminder (title `"],"`) went through. AWAITING:
the true promoted-build run — install the restaged build (the install page now
shows the build number; the export must show `appBuild` ≠ "1") and rerun
"Instrfix battery n=10 (80)".

**#200 addendum, 2026-07-28 late — SDK SEAM SURVEY (prior-art list surfaced by Owen
via Kimi K3; every claim verified independently against the local beta-4 SDK
swiftinterface — assistant knowledge cutoff predates WWDC26, so the SDK on disk is
the only ground truth).** VERIFIED REAL in
`FoundationModels.swiftmodule/arm64e-apple-ios.swiftinterface`:
(1) **`GenerationOptions.ToolCallingMode`** — `.allowed` / `.required` /
`.disallowed`, PER-REQUEST (`GenerationOptions(… toolCallingMode:)` and a
`DynamicProfile.toolCallingMode(_:)` builder). A STRUCTURAL seam aimed at exactly
the #200 disease: `.required` forces tool engagement at decoding level, upstream
of the response-planning stall that prose treatments reach only probabilistically.
Community note (Crosley): the framework may flip the mode back after the first
call so the model still produces a final response — "at least one call," not a
loop. → **#200E candidate cell `armed-toolmode`**: production belt + production
instructions + `.required` on the action prompts. Open questions the battery must
answer: does remind hit ~10/10 CREATES, or does forced-calling satisfy itself
with readReminders (read-substitution survives — a read is a call)? And the
canary is critical: `.required` on a misrouted haiku FORCES a grab, so any
promotion would have to be router-gated. `.disallowed` is separately interesting
as a cheaper structural toolless half (vs belt removal). (2) **`public protocol
LanguageModel` + `LanguageModelExecutor`** — third-party providers can back
`LanguageModelSession` (capabilities: `.vision/.guidedGeneration/.reasoning/
.toolCalling`); the architecture item this opens: Hermes as a `LanguageModel`
behind the SAME session/tool surface as on-device chat — unifying the two paths.
Big; separate item if pursued. (3) **`DynamicProfile`** per-turn steering surface:
`historyTransform` (context management — relevant to the 8,583-token
searchConversations overflow), `transcriptErrorHandlingPolicy` (#197 corruption
family), `reasoningLevel`, `onPrompt` hooks; plus a typed **`LanguageModelError`**
taxonomy (`contextSizeExceeded`, `timeout`, `guardrailViolation`,
`unsupportedTranscriptContent`, …) — we currently diagnose these from raw strings.
FAILED VERIFICATION (do not build on): `OCRTool`/`BarcodeReaderTool` — absent from
FoundationModels, Vision, AND VisionKit beta-4 interfaces despite the blog claim
(the article itself admits Apple's docs are partially elided); no semantic-search
API in FoundationModels. VALIDATION FROM APPLE'S OWN CORPUS (samhenrigold's iOS 27
system-prompts gist, PLANNER_* agentic-Siri assets): Apple's tool-invocation
prompts license calling under uncertainty — "Use this tool if any of the following
applies, even if you are not certain about all the details" — the same convention
the #200C clause encodes ("leave optional fields empty and the defaults apply").
Our measured clause independently converged on Apple's phrasing philosophy.
Queue position: #200E toolmode cell slots after the #200D re-verify; the
DynamicProfile/error-taxonomy items are instrument-hardening candidates; the
provider unification is an architecture discussion for Owen.

**#200 addendum 2, 2026-07-28 late — 8-agent comb synthesis (workflow, one sonnet
agent per source; 8/8 returned) + one CORRECTION to addendum 1.**
**CORRECTION: `OCRTool`/`BarcodeReaderTool` ARE in the beta-4 SDK** — in the
cross-import overlay `_Vision_FoundationModels.framework` (both conform to
`FoundationModels.Tool`, `call → some PromptRepresentable`); my "failed
verification" grepped only the three primary interfaces, and overlay APIs live in
separate `_A_B.framework` modules. Likewise `SpotlightSearchTool` +
`Configuration` live in `_CoreSpotlight_FoundationModels` — which RESOLVES the
"semantic search" claim (it's a Tool over Core Spotlight, not a new API);
`_FoundationModels_UIKit` / `_FoundationModels_SwiftUI` overlays also exist.
Kimi K3's original claims were right on this; the false negative was mine.
SYNTHESIS, in program order:
(1) **#200E design hardened by three independent sources:** rudrankriyam's
`fmf.md` (a 9,737-line raw transcription of THIS beta-4 swiftinterface including
doc comments we don't see) documents that `.required` "will loop until a Tool
throws an error or this value is changed dynamically"; Apple's WWDC pattern is
`.toolCallingMode(state.done ? .disallowed : .required)` + `.onToolCall` flag;
Foundation Lab ships working demote-after-first-call code
(`ToolCallingModeProfile.swift`). The #200E cell MUST use the DynamicProfile
demote pattern — raw `.required` in GenerationOptions would spin trials into the
guillotine. (2) **D4 mechanism candidate from Apple's own docs:** a strict
`maximumResponseTokens` "can lead to the model producing malformed results" —
and Talaria caps EVERY on-device chat turn at 1024 (#102 thermal guard,
deliberate). Candidate measured cell: armed-cap2048 / armed-nocap vs control on
the corruption rate; do NOT touch #102 without a battery. (3) **Independent
convergence on the D1 fix class:** rryam/FoundationModelsKit ships production
instructions "Always execute tool calls directly without asking for confirmation
… call the RemindersTool immediately" — session-instructions clause, same class
as our promoted fix. (4) **Planner corpus (190 files, not 128):** Apple runs
BOTH policies — the on-device ODM planner bakes in "Clarify with user if
unclear" (a plausible TRAINING-DISTRIBUTION source of our clarify-stall), while
the big-model CATALOG planner does omit-optional-fields-never-null-fill and a
find-first-on-ambiguity rule (plausible source of the D2 read-substitution).
Steal-worthy conventions: anti-loop hard-stop ("calling the same tool with the
same parameters in succession is a hard failure"), typed tool-error taxonomy
(interventionRequired/unsupported/retryable/fatal), a `not_supported`
escape-valve tool (D3 candidate), canonical date-format examples in param
descriptions (D4 candidate). (5) **Tool count:** Apple's guidance recommends
3–5 active tools per request; our belt is 10 → per-turn tool-scoping is a
measured-cell candidate. (6) **Provider surface is production-real:**
anthropics/ClaudeForFoundationModels exists (Apache-2.0, verified firsthand via
gh api raw reads); client-side Tool conformances are invoked by the FRAMEWORK
regardless of the backing model — so Hermes-as-LanguageModel would keep OUR belt
running locally; PCC model = 32K context, entitlement-gated, free tier under 2M
users; known provider-side hang (30–48s grammar compile on schema change).
(7) **Apple ships an "Evaluations" framework** (Swift Testing integration,
model-judge scoring) — our battery, productized; investigate for instrument
evolution. And `logFeedbackAttachment(sentiment:issues:desiredOutput:)` is the
sanctioned channel to file D1–D4 to Apple. (8) **Zero public prior art on D1–D4
as measured phenomena** — a documented absence across all eight sources; the
battery results are novel. Low-yield sources for the record: the ECC skill
(iOS 26 tutorial, no companions), IvanCampos playgrounds (LLM-generated iOS 26
stubs), Saharshv tutorial (all-required params, uncaught respond errors — a
useful cautionary example only).

**#200D RE-VERIFY PASSED — PROMOTION VERIFIED, 2026-07-28/29 (run `B468B062`,
`appBuild:"1387"` — the build stamp worked on its first outing and proves the
promoted binary). Sealed clean. Both cells speak the promoted text; both
replicate the treated signature:**

| prompt | armed | armed-instrfix | pooled (promoted production) | pre-promotion control |
|---|---|---|---|---|
| remind creates | 0/9 | 2/10 | **2/19** | 0/50 lifetime |
| alarm | 10/10 | 10/10 | **20/20** | 8–10/10 |
| calendar creates | 9/9 | 9/9 | **18/18** | 1/19 (this instrument) |
| haiku GRABS | 2/8 | 6/10 | **8/18 (44%)** | 17/20 (85%) |

Calendar hit CEILING — 18/18 with the contact-fixation dead (three trials had
lookupContact fail and CREATED ANYWAY, behavior control never showed). Alarm
ceiling. Remind matches the treated rate (~10%; the list-stall lives on as the
#200E target). Grabs halved though noisy between cells (2/8 vs 6/10 on
IDENTICAL text — n=10 variance; creative cant-refusals hold at ~9/18, the known
collateral). Excluded and listed: TIMEOUTs armed/calendar/t3 (weather spiral)
and instrfix/calendar/t8; ERRORs — THREE `GeneratedContent does not contain a
property 'title'` ToolCallErrors (armed remind t3, armed haiku t5+t7 — all
FAILED creates/grabs, args {list,due} only) — a rising D4 signal, possibly the
clause's "leave optional fields empty" bleeding into dropping the REQUIRED
title; plus comma-prefix title corruption in instrfix grabs (`,`, `,Sledding
Fun`, `,Sledding`). **REAP ARITHMETIC FAILED for the first time in five runs:**
reminders reaped 15 vs 10 accepted in-run, events 33 vs 18, alarms exactly
20=20. The surplus pattern fits PRE-EXISTING marker artifacts swept by this
run's store-query reap (in-run evidence: four already-exists readReminders hits
on a "Test Talaria July 30" artifact NO recorded run created) — most plausibly
an ABORTED RUN between exports 98DF19D1 and B468B062 (app killed mid-run:
creates persist, no reap, no export). CRITICAL ASYMMETRY EXPOSED: the
reminders/events reap is a marker QUERY (sweeps leftovers, self-healing) but
the alarm reap cancels only ITS OWN tracked IDs — an aborted run's alarms are
invisible to every later reap and stay scheduled (the 42-orphan lesson, now
structural). Owen asked to confirm the aborted run + run the alarm sweep.
Instrument follow-ups queued: persist tracked alarm IDs per-run to disk for
cross-run reap (marker-query reap is impossible — AlarmKit exposes no labels on
enumeration); document reap counts as this-run + leftovers.
**2026-07-29 confirmed by Owen: "I picked up my phone from reflex, and it
killed the run when I backgrounded it."** The aborted-run hypothesis is fact —
backgrounding kills the battery loop mid-run (foreground-only is a standing
instrument constraint, now with a measured failure signature: store leftovers +
orphaned alarms + inflated next-run reap counts). Alarm sweep requested; the
per-run persisted alarm-ID reap moves up the instrument queue.

**#200E VERDICT FILED, 2026-07-29 — toolmode battery n=10 (80 trials, PR #169
branch `fb21bfd`, CORDED deploy via the Xcode bridge — first run with live
console; classified from the console stream, run sealed clean, reap
`reminders=17 events=10 alarms=10 failures=0` — arithmetic EXACT:
17 = 2 control-remind + 6 control-grabs + 5 toolmode-remind + 4
toolmode-grabs).**

| prompt | armed (promoted control) | armed-toolmode |
|---|---|---|
| remind creates | 2/10 | **5/10** |
| alarm | 10/10 | **0/10 — ALL ERROR** |
| calendar | 10/10 | **0/10 — ALL ERROR** |
| haiku GRABS | 6/10 | 4/10 |

**Three-part verdict. (1) The demote mechanism WORKS:** every treated trial
shows `toolmode call#1` → (optionally `call#2`) → final response — the
`.required`→`.allowed` exit fired every time, zero infinite loops, and the
@SessionProperty counter reset per session exactly as designed. **(2) THE
BLOCKER — a deterministic FoundationModels decoder bug:** every alarm and
calendar trial under `.required` died with
`TokenGenerationInference.DecoderModelError.ifpInvalidExpertPickPosition
("Intermediate repick at position 1763 is not on frequency boundary 32")` —
position 1763 on ALL TEN alarm trials, 1764 on ALL TEN calendar trials
(surfacing as `FoundationModels.LanguageModelError Code=-1`). Deterministic by
prompt: the failing position tracks the prompt's token length, so `.required`
+ guided tool-decode at specific context lengths breaks the MoE
expert-repick machinery. Remind and haiku (different lengths) never hit it.
20/20 reproduction = a FILEABLE APPLE BUG with a deterministic repro — the
`logFeedbackAttachment`/Feedback Assistant channel from the seam survey is the
route; Owen routes. `.required` is NOT promotable while this exists.
**(3) The signal where it ran:** remind 2/10 → 5/10 — and the mechanism is
now visible: the forced first call was `readReminders` in 10/10 treated remind
trials (find-first is baked into the model — matching Apple's own CATALOG
planner convention from the survey), and after the forced read, half proceed
to create. CONFOUND biasing the treatment DOWN: 4 of the 5 non-creates were
already-exists reads of REAL in-run artifacts (the control cell's creates —
reap is end-of-run), so 5/10 is a floor; the per-trial unique-title fix is now
REQUIRED instrument work, not queued nice-to-have. Haiku under forcing is
benign: the forced call chose `searchConversations` 10/10 (a read, never a
straight grab); grabs 4/10 vs control 6/10. New specimens: armed/haiku/t5
LEAKED THE MARKER into its reply ("I created a reminder titled
'[T27-battery] ,'") — the tool result echoes the final title, so the model
sees the marker (second reason for the title fix); armed/haiku/t6 created the
reminder then said "I can't create a reminder about a haiku directly";
armed/haiku/t7 created ",Sledding" then ASKED "Would you like me to create
the reminder?"; toolmode/haiku/t8 fabricated "I don't have the capability to
write creative content" + grabbed; comma-prefix titles in 4 control grabs
(",Sledding"×2, ","×2 — D4 ongoing); armed/remind/t1 fabricated "there's no
reminder list active"; toolmode/haiku/t9 offered a sledding spot 8.9 miles
away in Mississippi in July. Control drift note: promoted-production grabs
pooled across #200D+E runs now 14/28 ≈ 50%. NEXT per the verdict: file the
Apple bug; ship the unique-title instrument fix; re-run toolmode ONLY if the
bug is fixed or the prompts are length-shifted to dodge the boundary (a
diagnostic cell, not a promotion path); the remaining pivot queue (B bundle,
tool-scoping, cap cell) proceeds per the survey plan. **PR #168 merges on
this verdict; the clause is production. #200E (toolmode, demote pattern) is
next per Owen's routing of the survey plan ("Lets do it").**

**#200F BUILT, 2026-07-29 — community-destall battery (PR #170, branch
`claude/t27-200f-community-destall` @ `a656004`; dispatch
`dispatch/OPUS-T27-200F-community-destall.md`). ROUTING CORRECTION to the
#200E note's "NEXT": Owen routed NO Apple filing** ("the last time we thought
we found an apple bug, it was our own oversight") — the `.required` decoder
crash is treated as an unresolved environmental constraint (possibly our own
DynamicProfile usage) and routed around; PR #169 merged (`6c22fe5`) on the
verdict as filed. Part 0 instrument fixes, both TDD-pinned: **(a) per-trial
reap** — the reminders+events marker sweep now runs after EVERY action-battery
trial (the #200E contamination cost 4/10 treatment remind trials to
already-exists reads of real in-run artifacts); one pinned `REAP-TRIAL` line
per trial; the final `REAP` line keeps its grammar with the per-trial sums
folded in, so reap arithmetic stays exact; alarms stay end-of-run tracked-ID
and the full reap stays as backstop. **(b) unmarked-title echo** —
`ToolConfirmationCenter.strippingBatteryMarker` cleans every create-tool
success text (the #200E marker leak: a reply carried "[T27-battery] ,"); the
store writes keep the marker; the alarm echo re-parses the cleaned raw because
its SCHEDULED label must keep the marker for the teardown. Cells per the
dispatch: `armed` control / `armed-scoped` (per-intent 3–5 belt, same-domain
reads in) / `armed-createonly` (per-intent belt without the same-domain read —
no readReminders to flee into) / `armed-findfix` (full production belt; the
two planner-corpus carve-out sentences behind `includeFindFirstCarveout`,
flag-off byte-identical, pinned). Haiku rides the remind scope in the scoping
cells. Suite 1292/1292 in 111 suites (8 new pins). Corded deploy on
whoGoesThere @ `a656004`; Owen running 4×4×10 = 160 trials. Success bar:
remind ≥8/10 in a cell with alarm/calendar holding ceiling, grabs ≤ control,
no new corruption. Verdict note follows the classified export.

**#200F VERDICT FILED, 2026-07-29 — community battery n=10 (160 trials, corded
@ `a656004`, classified live from the Xcode console bridge; run sealed clean.
Per-trial reap arithmetic EXACT: reminders 23 = 5 armed (1 remind + 4 grabs) +
0 scoped + 5 createonly + 13 findfix (9 remind + 4 grabs); events 30 = 5 + 7 +
10 + 8 (7 calendar + 1 haiku event-grab); alarms 40 = 10×4; failures 0; the
end-of-run backstop found ZERO leftovers — the per-trial sweep caught
everything, and cross-cell artifact contamination is instrument-dead (no
already-exists reads of in-run artifacts anywhere in 160 trials).**

| prompt | armed (control) | armed-scoped | armed-createonly | armed-findfix |
|---|---|---|---|---|
| remind creates | 1/10 | 0/10 | 5/10 | **9/10** |
| alarm | 10/10 | 10/10 | 10/10 | 10/10 |
| calendar | 5/8 | 7/10 | **10/10** | 7/9 |
| haiku GRABS | 4/9 | 0/10 | 0/10 | 5/10 |

ERROR/TIMEOUT excluded (4 of 160, all listed): armed/calendar/t8 ERROR
(context overflow 8,278 > 8,192 — a searchConversations "Sam" spiral, five
calls); armed/calendar/t10 TIMEOUT (same spiral shape, four calls);
armed/haiku/t6 ERROR ("cannot be completed into valid JSON");
armed-findfix/calendar/t9 TIMEOUT (eight-call spiral incl. currentWeather;
createCalendarEvent fired but the guillotine landed before the gate — reap 0
confirms nothing was created). **THE HEADLINE: `armed-findfix` remind 9/10 —
CLEARS the ≥8/10 bar** (lifetime control 1/60; the two planner-corpus
sentences killed find-first outright: ZERO readReminders calls in the cell's
remind trials, 9 straight createReminder-first creates, the one miss an
ask-date stall). Alarm ceiling holds everywhere; findfix calendar 7/9 beats
this run's control 5/8 (the #200D 18/18 calendar ceiling did NOT reproduce in
control — the searchConversations spiral is the new calendar failure mode,
worth its own cell). **The caveat: findfix grabs 5/10 vs control 4/9 —
nominally ABOVE control, within n=10 noise but the letter of the bar is not
met**; grab titles are now clean ("Sledding", never ","), and one grab was a
calendar EVENT (new specimen: haiku → createCalendarEvent "Sledding at the
snowy hill"). Scoped/createonly both fail as promotion candidates despite
createonly's calendar 10/10 CEILING and both cells' 0/10 grabs: the narrow
belts resurrect the #196 composition-denial disease in force — haiku cant
10/10 in BOTH cells ("I don't have creative writing tools", "I'm not a poet"),
half refusing to deliver any haiku at all — and scoped remind is 0/10 (the
ask-stall in full force; belt narrowing alone does NOT create). The
createonly-vs-scoped delta isolates the mechanism: removing readReminders
converts half the stalls to creates (0/10 → 5/10), the other half revert to
which-list interrogation — the stall has TWO forms (read-flee +
ask-interrogation) and structural narrowing only kills the first; the findfix
sentences kill both. New D4-family specimen class, filed: TOOL-RESULT
SEMANTIC MISBINDING — searchPlaces("Sam") returns Sam's Club and the model
binds it as the lunch location ("at Sam's Club — 10431 Old Hwy 49", "9.0
miles away"), pervasive across calendar creates in all cells; plus
armed/remind/t9 fabricated "I don't have permission to create new reminders"
(permission granted), and word-salad denials in createonly/haiku ("access to
the internet access to the model's training data"). No missing-title
ToolCallErrors and no comma-prefix titles in any treatment cell this run.
NEXT: promotion decision is Owen's — findfix promotes via the #200D pattern
(flip `includeFindFirstCarveout` default TRUE, pin flip, re-verify battery)
with the grab-rate caveat on the table; the searchConversations calendar
spiral and the cap cell remain queued.

**#200G PROMOTION RE-VERIFY PASSED, 2026-07-29 — findfix battery n=10 (80
trials, PR #171 branch `f79c074`, corded, classified live from the bridge;
Owen routed the promotion "Lets get the next lane going" and PR #170 merged
`2bcf1af` on the #200F verdict). `includeFindFirstCarveout` defaults TRUE;
both cells now speak identical promoted production and POOL. Per-trial reap
arithmetic EXACT: reminders 22 = 7 armed-remind + 8 findfix-remind + 1
armed-grab + 6 findfix-grabs; events 17 = 7 + 7 calendar + 2 + 1
haiku-event-grabs; alarms 20 = 10×2; failures 0; backstop ZERO leftovers
(second consecutive clean-sweep run).**

| prompt | armed (promoted prod.) | armed-findfix (identity) | POOLED |
|---|---|---|---|
| remind creates | 7/10 | 8/10 | **15/20 (75%)** |
| alarm | 10/10 | 10/10 | 20/20 |
| calendar | 7/10 | 7/9 | 14/19 (74%) |
| haiku GRABS | 3/10 | 7/10 | 10/20 (50%) |

One trial excluded and listed: armed-findfix/calendar/t3 TIMEOUT. **Remind
15/20 pooled — vs ~3/29 on the promoted-clause-only text and 1/60 lifetime
pre-carve-out control; the production construction now creates at 75% with
ZERO readReminders calls in all 20 remind trials (find-first stays dead on
the promoted text).** Alarm ceiling holds. Calendar 14/19 matches the #200F
band. **The #200F grabs caveat RESOLVES at pooled n: 10/20 = 50%, exactly
the standing promoted baseline (#200D+E pooled 14/28 ≈ 50%) — the carve-out
does NOT elevate grabs; the ~50% haiku grab rate is the pre-existing
standing disease, tracked, not this lane's regression.** Grab titles all
clean ("Sledding", "Sledding Joy"); zero comma-prefix titles and zero
missing-title ToolCallErrors for the second consecutive run. New D4-family
specimens, filed: findfix/calendar/t5 bound "Pluckers Wing Bar — Pasadena,
TX" (500 miles away) as the lunch location — the searchPlaces("Sam")
semantic-misbinding disease's worst specimen yet; findfix/calendar/t8
fabricated the location NAME "Sam's place"; findfix/calendar/t9 narrated
"(25 feet away)"; armed/calendar/t4 refused on a fabricated blocker ("the
location information isn't available" — location is optional);
findfix/haiku/t1 meta-grab (reminder titled "Write a haiku about sledding",
haiku delivered anyway). PR #171 merges on this verdict per Owen's routing.
Queued next per the survey plan: the searchConversations calendar-spiral
cell, the cap cell (D4), the DynamicProfile adoption bundle,
Hermes-as-provider.

**#200H VERDICT FILED, 2026-07-29 — spiral battery n=10 (120 trials, PR #172
branch `f73339c`, corded, classified from the bridge; run sealed clean;
per-trial reap arithmetic EXACT: reminders 31 = 8 armed + 12 spiralfix + 11
strikefix, events 27 = 9 + 9 + 9, alarms 30 = 10×3, failures 0, backstop
ZERO — third consecutive clean sweep).**

| prompt | armed (prod.) | armed-spiralfix | armed-strikefix |
|---|---|---|---|
| remind creates | 6/10 | 4/10 | 7/10 |
| alarm | 10/10 | 10/10 | 10/10 |
| calendar | 7/10 | **9/10** | 7/10 |
| haiku GRABS | 4/8 | **8/10** | 6/10 |

Excluded (2 of 120, both listed): armed/haiku t2 + t8 — ERROR
`ToolCallError(tool: DeviceHealthTool …)`: readHealth THREW on a haiku
misroute instead of returning an explanatory string. NEW Talaria-side bug
class filed: a belt tool with a throwing path violates the honesty design
(tools report failure as their RESULT); DeviceHealthTool needs the
throw→string audit. **Verdict, mixed: (1) spiralfix hits the target and
misses the bar** — calendar 9/10 (best calendar cell ever measured), zero
spiral casualties, hunts that still ran all ENDED IN CREATES, misbinds
reduced (5/9 clean creates vs ~1/7 control — "Sam's place" and "your
location" still leak) — BUT the collateral disqualifies promotion as-is:
remind sagged 6/10 → 4/10 and grabs DOUBLED 4/8 → 8/10, incl. two
meta-grabs (reminder titled "Write a haiku about sledding"). The sentence's
"an event or reminder" phrasing bleeds across intents — it licenses
reminder-making everywhere. Follow-up treatment queued (#200I candidate):
intent-scope the sentence to events only, re-measure. **(2) strikefix is
INCONCLUSIVE — the treatment never engaged.** Ground truth (relay tool=
lines): ZERO same-tool repeats occurred within any strikefix trial, so no
third strike was ever due (control had repeats in 3/30 trials — bursty).
AND the strike diagnostics are anomalous: all 132 strike lines are
DOUBLED-at-#1 (66 calls × 2 identical emits, never a #2) — the
`@SessionProperty [String: Int]` write appears not to persist across
onToolCall invocations, unlike #200E's Int counter which visibly
accumulated (call#1 → call#2). The demote path and the .disallowed
decoder watch-for are both UNEXERCISED; the cell's numbers read as a
second production sample. Instrument follow-up REQUIRED before any strike
re-run: pin down the dictionary-entry persistence (or fall back to the
proven Int total-call budget). **(3) Control notes:** no casualties in
control this run either (the spiral fired, 5-call hunts, no overflow) —
casualty rate is bursty, zero-casualty claims need bigger n; misbinds
pervasive (own street address bound onto 3 creates, "(your current
location)"); armed/calendar/t9 created-then-denied again. New corruption
specimens: a 12-hour event ("2:00 PM to 2:00 AM") and an event narrated
as a "reminder" (strikefix/haiku/t10, REAP-TRIAL proves the artifact).
NO cell clears its bar → NOTHING promotes from this battery. Merge
question (cells are picker-reachable instrument machinery, flag-off
byte-identical — the #200B/#200E precedent): Owen routes.

**#200I VERDICT FILED, 2026-07-29 — spiralfix battery n=10 (80 trials, PR #174
branch `04463e3`, OTA build 1421 Debug, os 27.0 24A5390f, run sealed
`reminders=18 events=12 alarms=20 failures=0`). FIRST RUN IN THE PROGRAM WITH
ZERO EXCLUSIONS — no ERROR, no TIMEOUT, 80/80 classifiable, and the reap
arithmetic is EXACT for the fourth consecutive run: counted accepted creates
`createReminder=18 createCalendarEvent=12 scheduleAlarm=20` == the REAP line,
zero backstop leftovers, zero marker leaks. Owen ran it OTA from work; the
verdict was classified from the run-JSON export, no console.**

| prompt | armed (control) | armed-spiralfix (v2) | #200H v1 for reference |
|---|---|---|---|
| remind | 6/10 | 5/10 | 4/10 (control 6/10) |
| alarm | **10/10** | **10/10** | 10/10 (control 10/10) |
| calendar | 4/10 | **6/10** | 9/10 (control 7/10) |
| haiku grabs | 4/10 | 5/10 | 8/10 (control 4/8) |

**NOT PROMOTED — the treatment misses every quantitative bar set before the run:**
calendar 6/10 vs the required ≥8/10; remind 5/10 vs ≥6/10; grabs 5/10 vs
"≤ control" (4/10). The fourth criterion (misbind-clean > control) is NOT
DEMONSTRABLE this run: all 12 events in BOTH cells were titled "Lunch with Sam"
with no location bound at all — zero Sam's Club, zero Pluckers, zero own-address
misbinds in control either. The #200F/#200G misbind class simply did not recur.

**(1) The control moved more than the treatment does.** Control calendar was
7/10 in #200H and 4/10 here on byte-identical production instructions — a
3-trial swing between runs, larger than the effect being chased. In BOTH runs
spiralfix beat its own same-run control on calendar by exactly +2 (9 v 7, 6 v 4);
pooled that is treatment 15/20 vs control 11/20, consistent in direction and
underpowered at n=10. The absolute bar was set from v1's absolute number, which
a low-baseline run cannot reach no matter what the seam does. **Any future
calendar bar must be stated as a within-run delta against its own control, not
as an absolute count.**

**(2) The v1 cross-intent bleed did NOT reproduce.** v2 grabs 5/10 vs control
4/10 (v1 was 8/10 vs 4/8) and remind 5/10 vs 6/10 (v1 was 4/10 vs 6/10). Either
the event-scoped reword removed the bleed or the v1 bleed was n=10 noise; this
data cannot distinguish the two, and honesty says say so.

**(3) The carve-out DOES do what it says — the hunt counts moved even though the
creates did not clear.** Identity-hunt calls on the calendar prompt
(`lookupContact`+`searchConversations`+`searchPlaces`): control 18, spiralfix 8
(−56%). On the haiku prompt: control `searchConversations`×5, spiralfix **zero**.
`currentLocation` rose 3→5 but bound nothing. The seam is real; it is just not
worth 2 trials of create rate.

**(4) Residual disease A — the `lookupContact` dead-end, 6 trials, evenly split
3 control / 3 treatment.** The model calls `lookupContact("Sam")`, finds nothing,
and ASKS instead of creating ("I couldn't find a contact named 'Sam.' Could you
provide more details?"). The carve-out halves the hunting but does not stop
`lookupContact` by name, and when it fires it still kills the create.

**(5) Residual disease B — the NARRATED CONFIRMATION CARD, now the single
largest failure bucket in the run: 10 zero-tool trials, 9 of them the remind
misses, cell-independent (4 control / 6 treatment).** The model writes the
confirmation card out in prose — "**Title:** Test Talaria / **Due:**
2026-07-30T16:30 / **List:** Default list / Would you like to proceed?" — and
calls no tool at all. The product already SHOWS a real confirmation card
automatically, and the production instructions already tell the model so
("Every action tool shows the user a confirmation card first"), so the model is
duplicating in text the exact affordance the tool provides and then waiting on
an answer a single-turn battery can never give. Knowing about the card is not
the same as being told not to impersonate it. **This is the next treatment
target, and it is crisper than anything left on the calendar side: one seam, one
sentence, 9 of 19 non-creates in its blast radius.**

**(6) Clean bills:** alarm ceiling holds 20/20 (never regressed, any cell, any
run). ZERO `readReminders` find-first anywhere in 80 trials — the #200G
promoted carve-out is holding perfectly. ZERO tool-throws — `readHealth` did not
throw once this run, so the #200H tool-throw specimen stays a real but
low-frequency bug-class (audit still owed, no battery needed). Grab specimens
shifted shape without shifting rate: control grabs split reminders/events
("Sledding", "Sledding Joy"), treatment grabs were ALL reminders and three of
five were meta-grabs titled "Write a haiku about sledding".

**Disposition:** the spiralfix cell stays flag-off and picker-reachable as
measured instrument machinery (the #200B/#200E/#200H precedent); production is
untouched by this lane. Merge of PR #174 and the next lane start: Owen routes.

**TOOL-THROW AUDIT DONE, 2026-07-29 (week-plan Lane 2) — the #200H filing was
half wrong, and the correction matters.** The claim was "DeviceHealthTool has a
throwing path; convert it to a string." Reading every belt tool says otherwise:
all six propagating `try` sites in `Talaria/Services/Live/DeviceTools/`
(`requestAuthorization`, `EKEventStore.save` ×2, `alarmService.schedule`,
`WeatherService.weather`, `MKLocalSearch.start`) are ALREADY inside `do/catch`
blocks that return explanatory strings, and there is not one `throw` statement in
the belt. The tools are honest as designed.

**The throws come from ABOVE `call(arguments:)`, in FoundationModels' argument
decode.** Every belt `Arguments` struct declares NON-OPTIONAL `@Generable`
fields (`metric: String`, `title: String`, `startsAt: String`, `daysAhead: Int`,
`query: String`, …), so the schema marks them required; when the model emits a
malformed or field-missing tool call — the D4 corruption class already on file
here (`missing required property 'title'` ToolCallErrors at #200F/#200G, the
`Sam}<ctrl43>` arg garbage) — the decode fails and FoundationModels throws
`ToolCallError(tool: …)` BEFORE the tool body runs. `DeviceHealthTool`'s single
required `metric` is simply the smallest target: a bare `{}` emit is enough.
Nothing inside the tool can catch this; the tool never executes.

**So the fix is not a throw→string edit, and it is not free.** Making the fields
decode-total (optional + sane default, tool returns "I need a title…" instead)
would convert a dead turn into recoverable guidance — but optionality also
REMOVES the field from the schema's required list, which may make the model omit
it more often and cost create rate. That is a production tool-schema change with
a two-sided risk, i.e. exactly the class this program measures rather than
assumes. **Recommended as a measured cell (read tools first — `metric`/
`daysAhead`/`query` have obvious safe defaults and no create rate to lose),
NOT as an unmeasured edit. Owen routes production schema changes.** No code
changed in this audit; the #200H note's "DeviceHealthTool needs the throw→string
audit" line is superseded by this entry. Frequency check from #200I: zero
tool-throws in 80 trials, so this is real but low-rate — worth a cell, not worth
jumping the queue.

**#200J VERDICT FILED, 2026-07-29 — cardfix battery n=10 (80 trials, PR #175
branch `f5cb906`, OTA build 1430 Debug, os 27.0 24A5390f, run sealed
`reminders=24 events=19 alarms=20 failures=0`). SECOND consecutive
zero-exclusion run (no ERROR, no TIMEOUT, 80/80 classifiable) and the FIFTH
consecutive exact reap: counted accepted creates `createReminder=24
createCalendarEvent=19 scheduleAlarm=20` == the REAP line, zero backstop
leftovers. Classified from the run-JSON export; Owen ran it OTA from work.**

| prompt | armed (control) | armed-cardfix |
|---|---|---|
| remind | 5/10 | **8/10** |
| alarm | **10/10** | **10/10** |
| calendar | **10/10** | 8/10 |
| haiku grabs | 7/10 | **5/10** |

**THE SPECIMEN IS DEAD.** Card narration — the model typing the confirmation
card out and asking "Would you like to proceed?" — occurred **3 times in
control (remind t2, t4, t10, all zero-tool) and ZERO times anywhere in the
treatment cell**, across all 40 of its trials, on any prompt. A grep for
"would you like to proceed" / "confirmation card" / "shall I proceed" over the
whole run returns only those three control trials. The clause did exactly what
it was written to do, and the remind rate moved with it: **5/10 → 8/10, +3,
the largest single-seam remind gain since the #200D promotion.**

**Bar check (delta-based against the SAME RUN's control, the #200I lesson):**
remind ≥ control+3 → 8 vs 5, **PASS (exactly at the bar)**. Narration trials ≤
half of control → 0 vs 3, **PASS**. Alarm 10/10 → **PASS** (ceiling intact,
never regressed in any cell of any run). Grabs ≤ control+1 → 5 vs 7,
**PASS (better than control)**. Calendar ≥ control → 8 vs 10, **FAIL**.

**The calendar guard tripped, and the mechanism says the clause is not the
cause.** Both treatment calendar misses are the untreated "Sam" identity
hunt — t1 `readCalendar → searchPlaces` → "I couldn't find a location for Sam";
t7 `readCalendar → searchPlaces → lookupContact` → "the search for 'Sam' nearby
returned a remote location". That is the #200H/#200I lookup-spiral disease,
whose carve-out is flag-OFF in this cell; it is not narration and not
card-related. The control simply dodged it 10/10 this run — and control calendar
has now read **7/10, 4/10, 10/10 across three consecutive runs on byte-identical
production text**. At n=10, 8 vs 10 is p≈0.47 by Fisher exact: indistinguishable
from that noise. **Recording this as a bar-design flaw as much as a result — a
"≥ control" no-regression guard has no headroom when the control lands on its
ceiling. Future guards should be stated as "not worse than control by more than
K" with K set from the observed between-run control variance (which is ±3).**

**Residual diseases, both named and both OTHER than narration:** (1) the
treatment's 2 remind misses are date-interrogation with zero tools ("Could you
clarify the due date?", "keep it open for today?") — the optional-field stall
(#200B/#200D family), untouched by a clause about confirmation cards.
(2) Haiku zero-tool trials rose 2 → 4, but they are the `cant` disease ("I
cannot write a haiku…"), not narration; total zero-tool trials therefore only
moved 7 → 6 even though narration went 3 → 0. **Reporting all three readings
because they disagree, and the specimen-level one is the one the bar meant.**
(3) Hunt calls rose slightly (control 27, treatment 32) — the clause says
nothing about hunting, so this is drift, not treatment.

**Grab note:** treatment grabs fell 7 → 5 and all 5 were reminders, 2 of them
meta-grabs titled "Write a haiku about sledding"; control's 7 were 6 reminders +
1 event ("Sledding Joy"). Grab RATE is now the highest-variance number in the
program (4/8, 4/10, 7/10 control across three runs) and remains armed-routed in
production.

**Disposition: NOT PROMOTED UNILATERALLY — 4 of 5 bars pass, the one failure has
a proven different etiology, and promotion is Owen's call. Recommendation on
file: promote behind the default-flip with a pinned byte-identical rollback
(the #200D/#200G pattern) and settle calendar with the pooled re-verify battery,
which measures production at n=20/prompt — the best calendar estimate this
program can buy. The alternative, a second identical A/B first, costs one run
and answers only the same question with the same n.**

**#200K VERDICT FILED, 2026-07-29 — datefix battery n=10 (120 trials, PR #176
branch `d2a7aca`, OTA build 1435 Debug, os 27.0 24A5390f, run sealed
`reminders=49 events=15 alarms=30 failures=0`). SIXTH consecutive exact reap:
counted accepted creates `createReminder=49 createCalendarEvent=15
scheduleAlarm=30` == the REAP line. 3 of 120 excluded and listed: armed/
calendar/t5 ERROR (`Encountered content that cannot be completed into valid
JSON. Text: {"term":"Sam"Sam"}<ctrl43>` — the D4 malformed-args class, on a
`searchPlaces("Sam")` hunt), armed/calendar/t6 TIMEOUT, armed-datefix/
calendar/t10 TIMEOUT. ALL THREE are calendar-prompt "Sam" hunts.**

| prompt | armed | armed-cardfix | **POOLED production** | armed-datefix |
|---|---|---|---|---|
| remind | 8/10 | 10/10 | **18/20 (90%)** | 8/10 |
| alarm | 10/10 | 10/10 | **20/20 (100%)** | 10/10 |
| calendar | 3/8 | 5/10 | **8/18 (44%)** | 6/9 |
| haiku grabs | 9/10 | 6/10 | **15/20 (75%)** | 9/10 |

**PROMOTION RE-VERIFIED on its own axis.** `armed` and `armed-cardfix` are
byte-identical post-promotion, so they pool as production at n=20/prompt:
**remind 18/20 (90%) — the best remind number in the program's history**
(lifetime arc 0/50 → 75% at #200G → 90% now), alarm 20/20, and **ZERO card
narration in all 120 trials** (grep for "would you like to proceed" /
"confirmation card" / "shall I proceed" returns nothing in any cell). The
#200K clause holds. Re-verify bars: remind ≥12/20 PASS, alarm 20/20 PASS,
narration-free PASS, **calendar ≥12/20 FAIL (8/18)**.

**DATEFIX: specimen killed, rate unchanged — the stall is CONSERVED, and this
is the finding of the run.** The pooled control's 2 remind misses were both
zero-tool DATE questions ("Could you specify the date?", "today, or a different
date?"). The datefix cell's 2 remind misses were both zero-tool LIST questions
("Would you like it on a specific list?", "which list to add this reminder
to?"). **Same count, different field.** The clause closed the door it named and
the model found the next one. Datefix bars: date-interrogation ≤half → 2→0
PASS; remind ≥ pooled+15pts → 80% vs 90% **FAIL**; alarm PASS; calendar/grabs
within K=3 PASS. **NOT PROMOTED.**

Two readings, both worth carrying: (a) the interrogation is a hydra — naming
one optional field relocates the stall rather than removing it, so
field-by-field clauses are a losing shape and the next attempt should treat the
CLASS ("create with defaults; the card is the correction point"); (b) possible
instruction crowding — the #200D destall clause ALREADY says "never ask which
list", and the list-asking appeared only in the cell carrying an extra
sentence. Adding sentences may dilute existing ones. Untested either way.

**CALENDAR IS NOW THE FIRE, and it is ONE disease.** Pooled 8/18 (44%), the
worst recorded, plus all 3 exclusions. **Every single classified calendar miss
in all three cells — 14 of 14 — is the "Sam" identity dead-end**: `lookupContact`
/`searchConversations`/`searchPlaces` on "Sam", nothing found, then a question
instead of a create. That is exactly the disease #200I's spiralfix v2 carve-out
targets, which cut hunt calls 56% and beat its control by +2. Hunt calls this
run: armed 35, cardfix 25, datefix 34.

**Honest watch item — the card clause may cost calendar, and we cannot yet
exclude it.** Post-promotion calendar is 22/37 (59%); pre-promotion controls
were 21/30 (70%). Fisher p≈0.4, so this is NOT significant and the between-run
control swing (7/10, 4/10, 10/10) dwarfs it — but the direction is unfavorable
and the #200J A/B (10/10 control vs 8/10 treated) points the same way. The
rollback is one pinned flag away. **The next battery should settle it directly
with a card-clause-ROLLBACK cell run alongside spiralfix v2 — one run answers
both "does the card clause cost calendar" and "does the spiral carve-out fix
it" against the promoted baseline.**

**Grabs are getting worse as remind gets better: 75% pooled, the highest
recorded** (4/8 → 4/10 → 7/10 → 15/20). Mechanically coherent — the program has
spent five lanes teaching prompt, unhesitating creation, and the haiku prompt
is swept up in it. Production remains armed-routed (a router miss is required
first), so this is not the user-facing number it looks like, but it is now the
program's largest untreated disease by rate and it is trending the wrong way.
Specimens are increasingly meta-grabs ("Write haiku about sledding" as a
reminder title, 5 of 15).

**Disposition: promotion STANDS (re-verified on remind/alarm/narration).
Datefix NOT promoted. Recommended next lane on file: the calendar/rollback
battery described above. Owen routes.**

**#200L VERDICT FILED, 2026-07-29 — calendar battery n=10 (120 trials, PR #177
branch `84af969`, OTA build 1442 Debug, os 27.0 24A5390f, run sealed
`reminders=48 events=18 alarms=30 failures=0`). SEVENTH consecutive exact reap:
counted accepted creates `createReminder=48 createCalendarEvent=18
scheduleAlarm=30` == the REAP line. 4 of 120 excluded, all listed and
individually adjudicated below — that adjudication is itself a finding.**

| prompt | armed (promoted production) | armed-cardrollback | armed-spiralfix |
|---|---|---|---|
| remind | **10/10** | 7/10 | 7/10 |
| alarm | **10/10** | **10/10** | **10/10** |
| calendar | 5/10 | 5/8 | **8/8** (8/10 counting casualties) |
| haiku grabs | 7/10 | 7/10 | 9/10 |

**HYPOTHESIS 1 — THE CARD CLAUSE IS EXONERATED ON CALENDAR, AND CONFIRMED ON
REMIND.** Rollback calendar 5/8 (62.5%) vs production 5/10 (50%) — about one
trial, far inside the K=4 guard, so the promoted clause is NOT what put calendar
at 44% last run. And removing it reproduced its effect in reverse, which is the
strongest evidence the program has produced for any promoted seam: **remind fell
10/10 → 7/10 and card narration CAME BACK** (production remind narrations: 0;
rollback remind t4 "Here's the confirmation for your reminder… Would you like to
adjust any details?" and t10 "Here's the confirmation card… Would you like to
proceed?"). That is now three independent confirmations — #200J's A/B, #200K's
pooled re-verify at 90%, and #200L's removal. **The promotion stands, and the
rollback flag is proven live rather than merely pinned.**

**EXCLUSION ADJUDICATION — a rule refinement, recorded because it changes a
headline number.** The standing rule (ERROR/TIMEOUT excluded and listed) exists
to drop INSTRUMENT failures. It should not silently drop failures that ARE the
disease under test, because that flatters the treatment being measured:

- cardrollback/calendar/t3 — `ToolCallError(tool: WeatherTool …)`, the
  argument-decode class from the tool-throw audit. **Instrument. Excluded.**
- cardrollback/calendar/t9 — "Insufficient system resources (7)", device-side.
  **Instrument. Excluded.**
- spiralfix/calendar/t6 — TIMEOUT after **20 tool calls, 17 of them consecutive
  `searchConversations`**: the identity spiral in its most extreme form ever
  recorded here. **DISEASE, not instrument.**
- spiralfix/calendar/t7 — "Session ended without producing a response" mid-hunt
  (`readCalendar → searchConversations → lookupContact → searchPlaces →
  currentLocation → currentWeather`). **Ambiguous; hunt-adjacent.**

So spiralfix calendar is **8/8 by the standing rule and 8/10 counting both
casualties as failures** — both are reported, and the second is the honest one
for a treatment whose entire purpose is to stop hunts. The #200H claim of "zero
spiral casualties" for this cell does NOT generalize: it produced two here, one
catastrophic.

**HYPOTHESIS 2 — THE CARVE-OUT WORKS ON ITS TARGET, AND THE MECHANISM IS
NARROWER THAN ADVERTISED.** Sam dead-end misses: production **5** (all five of
its calendar misses), rollback **3**, spiralfix **ZERO**. Every spiralfix
calendar trial that produced a response created the event. But identity-hunt
calls only fell from 23 to 16 (−30%), not to zero. **The carve-out does not stop
the hunting; it converts "hunt → ask" into "hunt → create".** That is why the
runaway spiral still happened: nothing in the sentence bounds the search, only
its conclusion.

**The trade is now measured TWICE and is consistent in direction on all three
axes** (spiralfix vs its own same-run control, #200I + #200L pooled):
calendar **14/18 (78%) vs 9/20 (45%)**, remind **12/20 (60%) vs 16/20 (80%)**,
grabs **14/20 (70%) vs 11/20 (55%)** worse. Calendar +33 points, remind −20,
grabs −15. Against its pre-set bars this run the cell PASSES everything —
calendar ≥ production+3, dead-ends ≤half (0), alarm 10/10, remind not worse by
more than 3 (exactly −3), grabs not worse by more than 3 (−2) — but two of those
passes sit on the boundary and the pooled picture says the bleed is real, not
noise.

**Disposition: nothing promoted; the decision is a genuine trade and it is
Owen's.** Options on file: **(a)** promote the carve-out and accept calendar
~50%→~78% against remind ~90%→~70% and slightly worse grabs; **(b)** one more
iteration first — a **v3 scoped to the DEAD END rather than the search**, which
this run's mechanism directly motivates ("if you can't identify a person named
in an event, create it with the name as given"), aiming to keep the calendar win
without moving the reminder path's weight. Recommendation: **(b)** — remind at
90% is the program's hardest-won number and the v3 hypothesis is a one-sentence
test, but (a) is defensible if calendar is judged the more valuable surface.

**#200M VERDICT FILED, 2026-07-29 — deadend battery n=10 (120 trials, PR #178
branch `50d5603`, OTA build 1447 Debug, os 27.0 24A5390f, run sealed
`reminders=49 events=17 alarms=30 failures=0`). EIGHTH consecutive exact reap:
counted `createReminder=49 createCalendarEvent=17 scheduleAlarm=30` == the REAP
line. 2 excluded, both adjudicated per the #200L refinement: spiralfix/calendar/
t10 `ToolCallError(tool: CalendarEventTool …)` = argument-decode, INSTRUMENT,
excluded; spiralfix/calendar/t7 TIMEOUT after 15 calls with ~11 consecutive
`searchConversations` = DISEASE, counted as a failure.**

| prompt | armed (production) | **armed-deadendfix (v3)** | armed-spiralfix (v2) |
|---|---|---|---|
| remind | **10/10** | 8/10 | 6/10 |
| alarm | **10/10** | **10/10** | **10/10** |
| calendar | 5/10 | **8/10** | 4/9 (44%, casualty counted) |
| haiku grabs | 9/10 | 9/10 | **7/10** |

**v3 BEATS v2 ON EVERY AXIS IT WAS BUILT TO BEAT IT ON, and the mechanism
reads exactly as designed.** Calendar misses: production **5, all Sam dead
ends**; v3 **2, and NEITHER is a Sam dead-end** (t2 and t8 both fail on
Gulfport location/weather lookups — a different, smaller failure); v2 **4, all
Sam dead ends**. Hunt calls: production 20, v3 16, v2 12. So v2 suppresses the
searching most (it carries the search prohibition) and still dead-ends most,
while **v3 barely touches the hunting and nearly eliminates the dead end** —
which is precisely the hypothesis: the win comes from licensing the create, not
from forbidding the search.

**NEW AND DECISIVE AGAINST v2: it resurrects a disease #200G already killed.**
Three of v2's four remind misses called `readReminders` first, including the
textbook read-for-create substitution — "I can't create a reminder for 'Test
Talaria' right now — I don't see any existing reminders." Zero `readReminders`
calls appear in production or v3 remind trials. **v2 is not merely a trade; it
reopens find-first. It should be retired, not promoted.**

**v3 against its pre-set bars: 5 of 6 PASS, one MISS by a single trial.**
calendar ≥ production+3 → 8 vs 5 PASS (exactly); Sam dead-ends ≤half → 5 → ~0
PASS; grabs not worse by >2 → 9 vs 9 PASS; alarm 10/10 PASS; vs v2, remind
strictly greater → 8 > 6 PASS and calendar no more than 2 below → far above
PASS. **remind within 1 of production → 8 vs 10, MISS.**

The miss is one trial and its two specimens are the CONSERVED STALL, not a new
disease: both are zero-tool interrogations ("Should it have a due date?",
"specific date and time… also a specific list?") — the exact hydra #200K
documented, where closing one field moves the question to another. Note also
that 8/10 sits INSIDE production's own historical range (production remind has
read 8/10, 10/10, 10/10, and 10/10 across the last runs), so the −2 is
plausibly noise rather than bleed — but the bar was set at "within 1" precisely
so that this call would not be made by eyeball after the fact, and it missed.

**Disposition: NOT PROMOTED (one bar, one trial). v2 RETIRED — recommend it
never promotes, on the find-first resurrection.** Recommended next step, cheap
and decisive: an 80-trial confirmation A/B of `[.armed, .armedDeadendfix]`
only. If remind lands ≥9 and calendar repeats ≥production+3, promote v3 on two
independent runs instead of one. Production calendar has now read 5/10 twice
consecutively, so the baseline is stable for once and a repeat measurement
actually means something. Owen routes.

**#200N VERDICT FILED, 2026-07-29 — deadend verify n=10 (80 trials, PR #179
branch `86bc343`, OTA build 1454 Debug, os 27.0 24A5390f, run sealed
`reminders=31 events=15 alarms=20 failures=0`). NINTH consecutive exact reap.
1 excluded and adjudicated: armed/calendar/t6 `ToolCallError(tool: WeatherTool
…)` = argument-decode, INSTRUMENT. No disease casualties in either cell.**

| prompt | armed (production) | **armed-deadendfix (v3)** |
|---|---|---|
| remind | 9/10 | **10/10** |
| alarm | **10/10** | **10/10** |
| calendar | 5/9 | **9/10** |
| haiku grabs | **4/10** | 8/10 |

**THE REMIND BAR — the single trial that stopped the #200M promotion — PASSES
EMPHATICALLY: v3 10/10, one BETTER than production's 9/10.** Pooled across the
two runs v3 has now had against production: remind **18/20 vs 19/20** (dead
level), so #200M's −2 was noise exactly as the specimens suggested, and it was
right to spend 80 trials rather than argue the point by eyeball.

**THE CALENDAR WIN REPRODUCES, and the mechanism reconfirms.** Calendar **9/10
vs 5/9** (+4 in counts, the bar wanted +3). Sam dead-end misses: production
**4** (t2/t3/t8/t10, all "I couldn't find a contact named Sam"), v3 **1**.
Hunt calls: production 16, v3 **15** — again essentially unchanged, so v3
still is not suppressing the search, it is licensing the create. Pooled over
#200M+#200N: **calendar 17/20 (85%) for v3 vs 10/19 (53%) for production, +32
points, same direction and similar size in both runs.**

**THE GRAB GUARD FAILS: v3 8/10 vs production 4/10, worse by 4 against a K=2
guard.** Reported without softening — but with the context that makes it hard
to read: production grabs across recent runs have gone 7/10, 15/20, 9/10,
9/10, and now **4/10, the lowest ever recorded**, so the guard tripped against
an outlier control. v3's own grabs are steady (9/10, 8/10). Pooled: v3 17/20
(85%) vs production 13/20 (65%). Mechanistically a grab increase IS plausible
here and should not be waved away: the clause is one more "just create it"
licence, and this program has spent six lanes raising create-pressure — the
specimens are the meta-grab class ("Write a haiku about sledding" as a reminder
title, and one v3 trial produced BOTH a reminder and a calendar event).

**Bars: 4 of 5 applicable PASS (remind, calendar, Sam dead-ends, alarm), grabs
FAIL. Nothing promoted unilaterally — Owen routes.**

**Recommendation: PROMOTE v3 and open the grab lane as the next battery.** The
two load-bearing axes are now confirmed twice each — calendar +32 points,
remind level — while the failing guard is a noisy metric measured against
production's best-ever grab run. Grabs need their own treatment regardless:
they have risen across five lanes, they are now the program's largest
untreated disease, and no clause aimed at calendar or reminders will fix a
disease whose cause is the create-pressure all of those clauses add. Note the
standing framing: production is armed-routed, so a grab requires a router miss
first. **Alternative if Owen prefers strictness: one more 80-trial A/B settles
grabs, at the cost of a run that will not change the calendar or remind
picture.**

**#200O VERDICT FILED, 2026-07-29 — grabfix battery n=10 (120 trials, PR #180
branch `11303f3`, OTA build 1460 Debug, os 27.0 24A5390f, run sealed
`reminders=43 events=24 alarms=31 failures=0`). 1 excluded: armed-deadendfix/
haiku/t9 `ToolCallError(tool: DeviceHealthTool …)` — the argument-decode class
again, INSTRUMENT.**

**REAP ARITHMETIC: 42 accepted `createReminder` calls counted across ALL trials
vs 43 swept — a ONE-ARTIFACT GAP, the first in ten runs.** Events (24) and
alarms (31) match exactly. Every one of the 42 recorded calls carries
`confirmation=accepted`, so the extra artifact was created by a call that never
made it into the trial record; the only truncated record in the run is the
ERROR trial, whose `readHealth` throw cut it short after its own accepted
create. Reported rather than smoothed over. **The gap is in the SAFE
direction** — the sweep removed more than we counted, so nothing leaked; the
dangerous direction would be counted > swept. Watch it next run; if it
recurs, the trial-record write on the throw path is the suspect.

| prompt | armed | armed-deadendfix | **POOLED production** | armed-grabfix |
|---|---|---|---|---|
| remind | 6/10 | 6/10 | **12/20 (60%)** | 6/10 |
| alarm | 10/10 | 10/10 | **20/20** | 10/10 |
| calendar | 9/10 | 7/10 | **16/20 (80%)** | 8/10 |
| haiku grabs | 7/10 | 8/9 | **15/19 (79%)** | 8/10 |

**THE CALENDAR PROMOTION RE-VERIFIES AT n=20: 16/20 (80%)** against the 53%
pre-promotion baseline, with Sam dead-end misses down to 2 of 20. The
promotion's own claim holds at a real sample size. Alarm 20/20, untouched as
ever.

**GRABFIX IS A CLEAN NEGATIVE.** Grabs 8/10 against a pooled control of 15/19
(79%) — the bar wanted ≤half — and **meta-grabs did not move at all: 7 in the
treated cell vs 5 and 7 in the two control cells.** Naming the artifact
("the writing itself is the answer — never also create a reminder, event, or
alarm about writing it") did nothing. **Note the asymmetry with #200J, where
naming the artifact DID work (card narration 3 → 0):** that clause fixed a
behaviour the model chose *instead of* calling a tool, while a grab happens
when the model has already committed to using the belt. **A grab looks like a
ROUTING failure, not a licensing one — no instructions clause has moved it in
seven lanes, and the next attempt should measure the router's haiku miss rate
instead (the week plan's option (b)), because in production a grab requires a
router miss first.**

**THE REMIND RE-VERIFY BAR FAILS (12/20 vs ≥17/20) — AND THE FAILURE IS
RUN-LEVEL, NOT TREATMENT-LEVEL. All three cells landed on EXACTLY 6/10**, on
three different instruction texts, and all 12 misses across the run are the
conserved stall — zero-tool list/date interrogation ("which list should I add
it to?", "should it be today, or a different date?"). A treatment effect cannot
be identical across treated and untreated arms; a run effect can.

**METHODOLOGICAL FINDING, and it should govern every future verdict: CROSS-RUN
COMPARISONS ARE NOT TRUSTWORTHY — ONLY WITHIN-RUN ARMS ARE.** Pooling the
carve-out across runs would say remind 30/40 (75%) with it vs 47/50 (94%)
without, Fisher p≈0.017 — apparently significant, and an artifact of exactly
the run-level swing this run demonstrates. The unconfounded within-run
comparisons are #200M (−2), #200N (+1), #200O (0, all arms equal): **net −1
over 30 trials, i.e. neutral.** A time-of-day confound was checked and REJECTED
— remind by run start reads 65%, 87%, 80%, 80%, 95%, 60% with no monotone
trend. **No rollback recommended; the promotion stands on its within-run
evidence.**

**Disposition: calendar promotion RE-VERIFIED and standing. Grabfix NOT
promoted (clean negative, and the disease is relabelled as routing). The
conserved stall is now the largest remaining disease on the remind path — it
took 12 of 30 remind trials here, it survived the #200K datefix cell, and
field-by-field clauses provably relocate it. Recommended next: either the
router's haiku miss rate (cheap, and re-frames the grab number production
actually experiences) or a CLASS-level stall treatment ("create with the
defaults; the confirmation card is where corrections happen"). Owen routes.**

**#200P VERDICT FILED, 2026-07-29 — stallfix battery n=10 (80 trials, PR #181
branch `c5a6cb5`, OTA build 1466 Debug, os 27.0 24A5390f, run sealed
`reminders=35 events=13 alarms=20 failures=0`). REAP EXACT again when counted
correctly: 35 / 13 / 20 accepted creates across ALL trials (12 calendar creates
in valid trials + 1 in an excluded one) == the REAP line. #200O's one-artifact
gap did NOT recur.**

| prompt | armed (production) | armed-stallfix |
|---|---|---|
| remind | 8/10 | **10/10** |
| alarm | **10/10** | **10/10** |
| calendar | 8/10 | 3/3 — **CELL COLLAPSED, see below** |
| haiku grabs | **10/10** (worst ever) | 7/10 |

**THE TREATMENT DID EXACTLY WHAT IT WAS BUILT TO DO.** Remind **10/10, a
perfect cell**, with **zero** zero-tool stalls against the control's 2 — and
both control misses were **card NARRATION** ("Here's the confirmation card for
your reminder: **Title:** … **Due:** …"), the #200K disease reappearing in
production at 2/10. The card-correction clause did not merely suppress the
stall; it appears to reinforce the promoted card clause, which is coherent —
both name the card, one as the thing not to impersonate and one as the place a
missing detail gets fixed. Grabs also came in 3 BETTER than a control that
posted its worst-ever 10/10.

**BUT THE STALLFIX CALENDAR ARM COLLAPSED AND THE COLLATERAL IS UNMEASURED: 7
of its 10 trials errored**, 5 of them with **zero tool calls** —
`Insufficient system resources (7)` and five `LanguageModelError Code=-1`. One
was a genuine disease casualty (t1, an 8,529-token context overflow after a
9-call hunt) and one is ambiguous (t5, after 4 calls), but the tail of five
zero-tool resource failures is the RUNTIME giving out, not the treatment. The
same cell's latency ran mean 9.7s / **max 33.6s against a 35s guillotine**,
where every other cell sat at 2-7s. **The phone had run eight batteries and
~800 trials today.** No calendar conclusion can be drawn from 3 valid trials,
so collateral for this treatment is simply unknown.

**BAR-DESIGN FAILURE, MINE, AND THE SECOND OF THIS SHAPE.** The remind bar was
"≥ control + 3" and the control scored 8/10 — making the bar require 11/10.
Unreachable by construction, exactly like #200J's "calendar ≥ control" against
a 10/10 ceiling control. **Delta bars on a 10-trial metric need a ceiling
clause; from now on: "≥ control + K, OR treatment = 10/10 with the specimen
eliminated."** Under the bar as written: remind MISSES (+2 vs +3). Under the
specimen bar: stall trials 2 → 0, **PASS**. Alarm PASS. Grabs PASS (better than
control). Calendar UNMEASURABLE.

**Disposition: NOTHING PROMOTED — the headline result is strong but the
collateral arm is missing and the bar as written was unmeetable.** Recommended:
**re-run the same two cells once, on a rested device** (power-cycle first; the
resource-error tail and the 33.6s latency say the runtime was degraded, and no
verdict should rest on a run where the hardware was failing), with the bar
restated in the ceiling-aware form. If remind repeats at or near 10/10 with
stalls at zero and calendar lands within K=3 of control, promote on the
#200D/#200G/#200K/#200O pattern.

**Instrument note for the day:** eight batteries / ~800 trials on one device
produced, in order, a first-ever reap gap (#200O) and then a resource-error
cascade (#200P). Both are consistent with accumulated pressure rather than any
code change. Cool-down between batteries is now part of the protocol.

**#200P RE-RUN + ROUTER PROBE FILED, 2026-07-29 (rested device, build 1466).
Two results, and they close two different questions.**

**(1) ROUTER PROBE: 200/200 PERFECT — and it retires the grab lane by
measurement rather than assumption.** n=20 × 10 probes, every one 20/20:

| probe | expected | correct |
|---|---|---|
| What's 2+2? | toolless | 20/20 |
| **Write a haiku about sledding** | **toolless** | **20/20** |
| write a 50 word summary about Norway | toolless | 20/20 |
| Tell me a joke about penguins | toolless | 20/20 |
| Write a poem for my mom's birthday | toolless | 20/20 |
| Remind me to buy milk tomorrow at 9am | device | 20/20 |
| What's the weather like right now? | device | 20/20 |
| Set an alarm for 6:30 | device | 20/20 |
| How many steps have I taken today? | device | 20/20 |
| Do I have anything on my calendar Friday? | device | 20/20 |

The grab disease only exists in ARMED construction, and **the router sent the
grab canary toolless 20 times out of 20** — as it did every other composition
prompt. So the 79–100% grab rates measured in armed cells all session are NOT
numbers a production user meets for this prompt class; a grab needs a router
miss first, and the measured miss rate is **zero**. This is the standing
framing, finally measured. **The grab lane closes: #200O's clean negative no
longer matters much, and no further instructions work on grabs is justified
until a router miss is actually observed.** Honest caveat: this is 5
composition prompts × 20; the router's behaviour on OTHER phrasings is
unmeasured, so the claim is "perfect on the measured set", not "perfect".

**(2) STALLFIX DOES NOT REPRODUCE — NOT PROMOTED.** Same two cells, rested
device, `reminders=33 events=17 alarms=20 failures=0`, reap EXACT, and **ZERO
exclusions in 80 trials** (which also confirms #200P's 7-error collapse was
device pressure, not code — same build, same cells, healthy hardware, clean
run).

| within-run arms | remind | zero-tool stalls |
|---|---|---|
| #200P run 1 — control | 8/10 | 2 |
| #200P run 1 — stallfix | **10/10** | **0** |
| re-run — control | 8/10 | 2 |
| re-run — stallfix | **8/10** | **2** |

Pooled: stallfix 18/20 with 2 stalls vs control 16/20 with 4. **+2 over 20
trials — indistinguishable from a noise floor #200O measured at ±4.** The
entire apparent effect came from run 1; on a healthy device the treated and
control arms are identical, and the treated cell's misses are the same
interrogation as the control's ("Could you specify the date?", "a due date or a
specific list?").

**This is the protocol working.** #200P's headline was a perfect 10/10 with the
specimen at zero, filed with a recommendation to re-run rather than promote
because the collateral arm had collapsed. The re-run says don't promote.
Without that discipline a run-level fluctuation would now be production text.

**Disposition: nothing promoted. Stallfix stays a flag-off measured cell.** The
conserved stall remains the largest live disease on the remind path (4 of 20
control trials here) and is now 0-for-2 on instruction treatments (datefix
relocated it, stallfix did not reproduce) — the next attempt should change
KIND, not wording: the promoted destall clause already forbids asking, so a
structural seam (tool-schema defaults, or a DynamicProfile that demotes on a
question-shaped output) is the untried direction.

**#200Q VERDICT FILED, 2026-07-29 — schemafix battery n=10 (80 trials, PR #182
branch `baf5015`, OTA build 1473 Debug, os 27.0 24A5390f, run sealed
`reminders=29 events=16 alarms=20 failures=0`, ZERO exclusions). Owen's note:
an accidental Control Center swipe killed a FIRST attempt ~1 minute in; the
file classified here is the complete retry (80 trials, all eight cell×prompt
groups populated, `endedCleanly: true`). Per-trial reap means a backgrounding
kill strands nothing, so the earlier abort leaves no orphans and no
contamination.**

| prompt | armed (production) | armed-schemafix |
|---|---|---|
| remind | 8/10 (2 stalls) | **10/10 (0 stalls)** |
| alarm | **10/10** | **10/10** |
| calendar | 9/10 | 8/10 |
| **haiku grabs** | **10/10** | **1/10** |

**EVERY BAR PASSES, including the primary one on its ceiling-aware form.**
Remind 10/10 with zero-tool stalls at ZERO against a control that interrogated
twice ("Could you specify the date for this reminder?", "should it be on a
default list?"). Stalls ≤half → 0 vs 2. Alarm 10/10. Calendar within K=3 (8 vs
9). **The hypothesis predicted this exactly: the two fields the model kept
asking about were the two the schema REQUIRED while the instructions told it to
leave them empty. Removing the contradiction removed the questions.**

**AND AN EFFECT NOBODY PREDICTED: grabs collapsed 10/10 → 1/10.** Control
grabbed on all ten haiku trials, every one a reminder, five titled with the
request itself ("Write a haiku about sledding"). The treated cell grabbed ONCE;
**seven of its ten trials called no tool at all** and simply wrote the poem.
That is a nine-trial within-run swing, far outside any noise this program has
measured, from a cell whose only intended delta was two field types.

**Confound, stated because it cannot be separated in this design:**
`includesSchemaInInstructions` is true, so the tool renders its schema INTO the
instructions — changing two field types therefore also changes the instructions
text the model reads. The grab effect may be optionality itself or may be the
rendered-schema change. Mechanism is UNEXPLAINED and is not needed for the
promotion decision, but it should not be written up as understood.

**Disposition: NOT PROMOTED YET — replication required, and this is precisely
the #200P lesson.** #200P produced a perfect 10/10 cell with its specimen at
zero and evaporated on re-run; an unpredicted effect this large gets the same
scepticism, not less. **The confirmation run needs NO new code and no new
build:** `schemafixBatteryCells` is already `[.armed, .armedSchemafix]` and the
"Schemafix battery n=10 (80)" button already exists on staged build 1473 — the
next run is the same button a second time, on a rested device. If remind holds
at/near 10/10 with stalls at zero AND grabs stay far below control, promote the
optional-field schema on the #200D/#200G/#200K/#200O pattern, and the obvious
follow-on is extending optionality to `CalendarEventTool`'s `location` /
`durationMinutes` (a separate measured cell, not a freebie).

**Instrument note: 17 accepted `createCalendarEvent` calls counted vs 16
events swept.** The gap is one artifact in the "accepted create that never
became an artifact" direction, which points at an EventKit save failure (the
tool returns an explanatory string on that path) rather than a leak — a leaked
marker artifact would have been caught by the same run's backstop sweep, which
ran and found 16. Nothing stranded. Also of note, `armed-schemafix/calendar/t6`
shows a `confirm=none` call followed by an `accepted` one: the tool bailed
pre-gate once and then succeeded, which is the honest-failure path working.

**#200R VERDICT FILED, 2026-07-29 — schema-mechanism battery n=10 (120 trials,
PR #183 branch `e5240e5`, CORDED Xcode build (`appBuild=1`, so unstamped —
corded builds carry no CURRENT_PROJECT_VERSION), os 27.0 24A5390f, run sealed
`reminders=33 events=34 alarms=31 failures=0`, ZERO exclusions).**

| prompt | armed | armed-schemafix | armed-schemaquiet |
|---|---|---|---|
| remind | 9/10 (1 stall) | **10/10 (0 stalls)** | **0/10** |
| alarm | **10/10** | **10/10** | **10/10** |
| calendar | 8/10 | 7/10 | 9/10 |
| haiku grabs | 8/10 | 7/10 | 0/10 |

**(1) THE REMIND RESULT REPLICATES. Pooled over #200Q + #200R: schemafix
20/20 with ZERO zero-tool stalls vs control 17/20 with 3.** Both runs hit
10/10; the ceiling-aware bar passes both times. The schema-contradiction
hypothesis is now confirmed twice: making `due`/`list` optional in the schema —
so it no longer demands what the promoted #200D clause tells the model to leave
empty — removes the interrogation. Alarm untouched, calendar within K=3.

**(2) #200Q's GRAB COLLAPSE DOES NOT REPLICATE. 7/10 vs a control of 8/10 —
essentially equal, against #200Q's 1/10 vs 10/10.** The grab bar (≤half
control) FAILS. That nine-trial swing was a one-run fluke, and the
"reproduction required" rule caught it exactly as intended. Nothing got worse;
the claim simply evaporates. **Two unexplained large effects have now failed to
replicate in two days (#200P's perfect stall cell, #200Q's grab collapse) — the
rule earns its keep and stays.**

**(3) THE MECHANISM ARM IS DEGENERATE, AND WHAT IT REVEALS IS WORSE THAN
"INCONCLUSIVE": the schema description is load-bearing for tool SELECTION.**
With the reminder tool's schema suppressed from the instructions (decoding
unchanged), the model did not merely fail to create reminders — **9 of 10 remind
trials created a CALENDAR EVENT instead** (one scheduled an alarm) **while
telling the user a reminder had been set**: "Your reminder to test Talaria has
been scheduled for July 29, 2026, at 4:30 PM" — on the calendar. Three trials
bound junk locations ("at Talia", "at Test Talaria"). Its 0/10 grabs are the
same artifact: no usable reminder tool means no reminder grabs, not restraint.
**So the #200Q confound cannot be separated by removing the description —
removing it breaks the tool.** The confound is formally unresolved and now moot:
what would promote is the optional-field schema WITH its description, which is
exactly the cell measured twice.

**New specimen for the D4/honesty ledger:** silent wrong-artifact substitution
with a confident false claim. Production never suppresses schema descriptions,
so this is a model/SDK finding rather than a live bug — but it is the starkest
"the reply lies about what it did" case the program has recorded, and it
independently re-justifies the standing rule that a create is
`confirm=accepted` + its artifact, NEVER the reply text.

**(4) THE CRASHES WERE JETSAM MEMORY KILLS — instrument, not code.** Four
consecutive runs died with no in-app error, no timeout, no assertion, healthy
latencies, and scattered death points (≈105, 26, 17, 49 trials). Re-launching
with the DEBUGGER ATTACHED — which makes a process jetsam-exempt — the identical
build completed all 120 trials on the first attempt. Two earlier hypotheses were
wrong and are recorded as such: device/model degradation (refuted by 2.5-6.4s
mean latencies in the crashing runs) and an AlarmKit ceiling from orphaned
alarms (refuted by a death mid-reminder with only 10 alarms live). **Protocol
addition: run corded batteries with the debugger attached.**

**(5) REAL INSTRUMENT DEFECT FOUND EN ROUTE: the per-trial reap sweeps
reminders and events but NOT alarms** — alarms are cancelled only at end-of-run,
so every crashed run strands every alarm it scheduled (~30 for a 3-cell battery;
today's four crashes stranded ~47, matching the "~50 armed for 6:30 AM" already
on file from 2026-07-28). Owen had to sweep manually to proceed. **Fix owed:
cancel each trial's tracked alarm in the per-trial reap so a crash can strand at
most one.**

**Disposition: the optional-field schema (#200Q's cell) is CONFIRMED on remind
across two runs — 20/20, zero stalls — with no collateral, and the grab claim is
withdrawn. Promotion is Owen's call. Recommended: promote it on the
#200D/#200G/#200K/#200O pattern (production types become optional, the pinned
rollback is the required-field struct, promoted cell becomes the next pooled
re-verify) and land the per-trial alarm cancel in the same branch. The
schemaquiet cell should be RETIRED, not re-measured — it disables the tool it
was meant to isolate.**

**#200S RE-VERIFY FILED, 2026-07-29 — schema re-verify n=10 (120 trials, PR #184
branch `c279794`, corded Xcode build WITH DEBUGGER ATTACHED per the new
protocol, os 27.0 24A5390f, run sealed `reminders=45 events=25 alarms=30
failures=0`, ZERO exclusions, classified live from the console bridge — no
export needed). Reap arithmetic EXACT and hand-verified against the console:
reminders 17+14+14=45, events 8+8+9=25, alarms 10+10+10=30. First run with the
per-trial alarm cancel live: 30 scheduled, 30 cancelled, nothing stranded.**

| prompt | **POOLED production** (armed + schemafix, n=20) | armed-schemarollback (n=10) |
|---|---|---|
| remind | **20/20 (100%)** | 7/10 |
| alarm | **20/20** | **10/10** |
| calendar | 15/20 (75%) | 9/10 |
| haiku grabs | 10/20 (50%) | 7/10 |

**THE PROMOTION IS CONFIRMED AGAINST ITS OWN ROLLBACK, IN THE SAME RUN, AND THE
CAUSAL CHAIN IS NOW CLOSED.** Pooled production remind is **20/20 with zero
stalls** — the third independent 10/10 for the optional-field schema (#200Q,
#200R, and both arms here) — while the rollback arm, which differs ONLY in
those two field types being required again, drops to **7/10**. And its three
misses are the exact disease, verbatim from the console:

- t2: "Here's the confirmation card for your reminder … Would you like to proceed?"
- t8: "Here's the reminder setup … Would you like to proceed?"
- t9: **"I need to know which list you'd like it added to (e.g. 'Default' or another list)."**

**Restore the required `list` field and the model asks which list; make it
optional and it creates.** Five lanes of wording (#200B guidefix, #200D destall,
#200K datefix, #200P stallfix) could not move this because they were arguing
with a schema constraint prose cannot reach. The card-narration relapse in the
rollback arm is the same story: with a field it must fill and no value for it,
narrating the card and asking is the model's rational move.

**Collateral, honestly:** calendar 15/20 (75%) pooled vs the rollback's 9/10,
i.e. ~1.5 trials/10 worse — inside the K=3 guard and inside calendar's own
demonstrated between-run swing (7/10, 4/10, 10/10, 8/10, 9/10 across the week),
but the direction is unfavourable and it is the one number to watch on the next
run. Grabs pooled 10/20 (50%) vs the rollback's 7/10, i.e. the optional schema
looks BETTER on grabs — directionally consistent with #200Q's collapse but far
weaker, and NOT claimed: #200R already withdrew that claim once.

**Protocol note, stated because it is a gap and not a detail: this run had NO
pre-registered dispatch doc.** The promotion itself was justified by #200Q +
#200R, both with bars set in advance, and this run is a confirmation — but a
120-trial run without written bars is a lane run on memory, which is exactly
what the dispatch discipline exists to prevent. The numbers above are reported
against the standing #200K-pattern bars (pooled remind ≥17/20, alarm 20/20,
calendar ≥14/20, rollback arm worse on remind); all four hold. A #200S dispatch
doc is owed retroactively or the next lane starts one.

**Also confirmed: the jetsam protocol works.** Debugger attached, 120/120 trials,
zero exclusions, first attempt — against four consecutive kills without it.

**Disposition: the optional-field reminder schema STANDS as production.** The
rollback cell stays picker-reachable as the pinned revert. Next candidates, in
order of evidence: (1) extend optionality to `CalendarEventTool`'s `location` /
`durationMinutes` — the same mechanism, and calendar is now the weakest
production number at ~75%; (2) the remaining calendar disease is still the "Sam"
lookup dead-end that #200O's promoted carve-out only partly tames.

**#200T VERDICT FILED, 2026-07-29 — calendar optional-field schema, n=10 (80
trials, PR #185 branch `d1aa7ee`, corded Xcode build WITH DEBUGGER ATTACHED, os
27.0, run sealed `reminders=34 events=15 alarms=20 failures=0`, ZERO exclusions
— no ERROR, no TIMEOUT, no guillotine anywhere in the run — classified live from
the console bridge). Reap arithmetic EXACT: reminders 10+6+10+8=34, events
7+8=15, alarms 10+10=20. Second run with the per-trial alarm cancel live: 20
scheduled, 20 cancelled, final sweep found `marked=0` — nothing stranded.
BARS WERE PRE-REGISTERED in `dispatch/OPUS-T27-200T-calendar-schema.md` before
any data existed, which closes the gap #200S filed against itself.**

| prompt | armed (control) | armed-calfix (treatment) |
|---|---|---|
| remind | **10/10** | **10/10** |
| alarm | **10/10** | **10/10** |
| calendar | 7/10 | 8/10 |
| haiku grabs | 6/10 | 8/10 |

**THE PRIMARY BAR FAILED. NO PROMOTION.** It asked for calendar ≥ control + 2
(9/10 against this control) or 10/10 with the control ≤ 9/10. The treatment
returned **8/10 against 7/10 — a delta of +1**, inside noise and inside
calendar's own demonstrated between-run swing. Both guards hold: remind 10/10
and alarm 10/10 in BOTH arms, so the belt swap cost nothing. Grabs 6/10 → 8/10
is reported, not gated (the #200O router probe went 200/200 and sends the canary
toolless in production), but the direction is unfavourable and is noted.

**MECHANISM, ADJUDICATED BEFORE THE DELTA WAS CLAIMED, AS PRE-REGISTERED.** The
control's three calendar misses, verbatim:

- t1 — after `currentLocation` + `lookupContact` + `searchPlaces` +
  `searchConversations`: "I couldn't find any details about Sam or a lunch spot
  nearby. Could you clarify the location or provide more information?"
- t7 — "I couldn't find a contact named \"Sam.\" Could you provide more details…"
- t10 — card narration with **every field already filled** (Location, Duration
  60): "Here's the confirmation card for your calendar event: … Would you like
  to proceed?"

Only ONE of three is field-flavoured, and it arrived wrapped in a four-tool
spiral. The treatment's two misses are **both** the Sam dead-end verbatim. So
**4 of the 5 calendar misses across both arms are the "Sam" lookup dead-end** —
the disease #200O's promoted carve-out only partly tames. Per the pre-registered
reading, this null is NOT evidence against the schema mechanism; it is evidence
that calendar's remaining losses live somewhere else, and it redirects the next
lane rather than counting against #200S.

**EXPLORATORY FINDING — POST HOC, NOT PRE-REGISTERED, AND LABELLED THAT WAY.**
The two field types changed the model's TOOL BEHAVIOUR far more than its
success rate. Control: `currentLocation` in **9 of 10** calendar trials,
`searchPlaces` in **6 of 10**. Treatment: `currentLocation` in **2** and
`searchPlaces` in **0** of the 9 trials whose full sequence was read (t1's
sequence was outside the console window; its reply cites no location).

And it shows up in the ARTIFACTS, not just the latency. The control filled the
required `location` field by geolocating the user and stamping a place onto a
lunch event that never mentioned one — "Saucier, MS", and twice the home street
address **"19200 Crestwick St, Saucier, MS"**. Treatment creates carry no
location at all. A required field the request cannot fill is being satisfied by
inventing data about the user, which is a correctness and privacy concern
independent of any create rate.

This effect is large (9→2 and 6→0 on n=10 within one run) but it was discovered
AFTER the data and has no pre-registered bar, so it earns **its own lane with
bars written first** — not a promotion, and not a claim on this run.

**Instrument notes.** `armed-calfix` calendar t9 emitted TWO
`createCalendarEvent` calls under one `confirm=accepted` with one event reaped
(the #200H double class, harmless to the arithmetic here). The optional-field
schema itself behaved: every treatment create resolved duration to the pinned
60-minute default and the card carried it.

**Disposition: the calendar optional-field schema does NOT promote.** The
measurement cell (`armed-calfix`) and `CalendarEventToolOptionalFields` stay
picker-reachable for the confirmation run; production `CalendarEventTool` is
unchanged apart from the shared `performCreate` engine and `resolveMinutes`,
which are behaviour-identical on every path the pre-promotion tool could reach.
Next candidates, in order of evidence: (1) the **"Sam" lookup dead-end**, which
owns 4 of 5 calendar misses and is where the rate actually lives; (2) a
pre-registered run for the **location-spiral / invented-location** effect above.

**#200U VERDICT FILED, 2026-07-29 — contact dead-end at the tool-RESULT layer,
n=10 (120 trials, PR #186 branch `d33546a`, corded Xcode build WITH DEBUGGER
ATTACHED, os 27.0, run sealed `reminders=49 events=29 alarms=30 failures=0`,
ZERO exclusions — no ERROR, no TIMEOUT, no guillotine — classified live from the
console bridge). Reap arithmetic EXACT: reminders 16+17+16=49, events 8+11+10=29,
alarms 10+10+10=30. Bars pre-registered in
`dispatch/OPUS-T27-200U-contact-deadend.md` before any data existed.**

| prompt | armed (control) | armed-deadend2 (fix) | armed-nocontact (ceiling) |
|---|---|---|---|
| remind | **10/10** | **10/10** | **10/10** |
| alarm | **10/10** | **10/10** | **10/10** |
| calendar | 7/10 | **10/10** | **10/10** |
| haiku grabs | 7/10 | 8/10 | 6/10 |

**BOTH CO-PRIMARY BARS PASS, AND THE FIX LANDS EXACTLY ON THE CEILING.** Calendar
10/10 vs the control's 7/10 clears ≥ control + 2 and the 10/10 clause both. The
dead-end miss count — the co-primary, and the sharper instrument at n=10 — went
**3 → 0**. Every guard holds: remind and alarm are 10/10 in all three arms.
**Calendar 10/10 is the best calendar number in the program.**

**THE CAUSAL CHAIN IS CLOSED, AND IT IS THE ONE THE HYPOTHESIS NAMED.** All three
control misses are the dead-end, verbatim from the console:

- t6: "I couldn't locate a contact named \"Sam.\" Would you like to choose a
  different name or location for the lunch?"
- t8: **"I couldn't find a contact named Sam in your contacts. Would you like me
  to proceed without the name, or search for it differently?"** — it asks
  PERMISSION to do exactly what the promoted #200O prose already told it to do.
- t9: "I couldn't find a contact named \"Sam.\" Would you like to try a different
  name or provide more details?"

And in the fix arm the lookup **still runs and still misses** — `lookupContact
detail=Sam` appears in every sampled trial (t1, t2, t3, t10) — and the model
creates anyway, 10/10. The treatment did not stop the lookup; **it stopped the
failed lookup from reading as a blocker.** Same tool, same miss, one different
result string, opposite outcome. Prose could not reach this because prose was
never the layer: a tool result is consumed as fact.

**Arm B (tool absent) also hit 10/10, which is the useful part of a ceiling
probe: the promotable one-string fix captures the ENTIRE available win.** No
production intent-scoping is needed, and that avoids removing a tool the user
legitimately wants.

**NOT PROMOTED YET — TWO REASONS, BOTH PRE-COMMITTED OR NEWLY VISIBLE.**

1. **Reproduction is mandatory and pre-registered.** #200P produced a perfect
   10/10 stall cell that evaporated on re-run; #200Q's grab collapse did the
   same. A perfect cell is exactly the shape that has fooled this program twice.
2. **CELL-ORDER CONFOUND, named here because it now spans three runs.** Cells
   execute sequentially, control first. Calendar by run position: #200S armed
   first (pooled 75%) vs rollback last (9/10); #200T armed 7/10 first vs calfix
   8/10 second; #200U armed 7/10 first vs 10/10 and 10/10 second and third. **In
   three consecutive runs the FIRST cell posted the lowest calendar number.**
   That is consistent with treatment effects AND with a warm-up / thermal /
   model-load artifact, and the instrument cannot currently tell them apart.
   Ordering cannot easily explain the qualitative switch — an identical failed
   lookup producing "may I proceed?" in one arm and a create in another — but it
   can inflate the size of the win.

**THE CONFIRMATION RUN IS THEREFORE ORDER-REVERSED:** cells
`[.armedNocontact, .armedDeadend2, .armed]`, same n=10, so production runs LAST.
If the effect is real the control still posts the lowest number from the last
slot; if run position was doing the work, the ordering flips the result and the
promotion is withdrawn. This is a decisive test of the confound rather than
another repetition of it, and it is owed a dispatch doc with bars BEFORE the run.

**Collateral, honestly:** grabs 7 → 8 in the fix arm and 6 in the probe (reported,
not gated — the #200O router probe went 200/200 and sends the canary toolless in
production). Two WRONG-ARTIFACT grabs are worth naming separately from the
counts: control haiku t10 and fix-arm haiku t6 each created a **calendar event**
for "write a haiku about sledding". That class is not new and not caused here,
but it is the ugliest thing in the run.

**Disposition: the fix is a PASS on its pre-registered bars and is held for the
order-reversed confirmation run before any promotion.** `continuesAfterNoMatch`
stays `false` in production until that run clears, so the shipping belt is
unchanged; promotion is flipping one default and rollback is flipping it back.

**#200V VERDICT FILED, 2026-07-29 — order-reversed confirmation + warm-up, n=10
(120 counted trials + 4 discarded warm-up, PR #187 branch `a54161b`, corded
build WITH DEBUGGER ATTACHED, os 27.0, run sealed `reminders=44 events=30
alarms=31 failures=0`, classified live from the console bridge). Reap arithmetic
EXACT including the warm-up, stated separately as the dispatch required:
reminders 1+13+15+15=44, events 1+10+10+9=30, alarms 1+10+10+10=31.**

**THE PRE-REGISTERED WITHDRAWAL TRIGGER FIRED. #200U'S HEADLINE IS WITHDRAWN AND
THE FIX DOES NOT PROMOTE.**

| slot | cell | remind | alarm | calendar | dead-end misses | haiku grabs |
|---|---|---|---|---|---|---|
| 1 | armed-nocontact | **10/10** | **10/10** | 9/9 (1 TIMEOUT excl) | n/a (tool absent) | 4/10 |
| 2 | armed-deadend2 | **10/10** | **10/10** | **10/10** | **0** | 5/8 (2 ERR excl) |
| 3 | **armed (production)** | **10/10** | **10/10** | **9/10** | **0** | 5/9 (1 ERR excl) |

**Exclusions, listed and adjudicated (4):** `nocontact/calendar/t5` TIMEOUT —
guillotined after **six** `searchConversations` calls on the same query; three
`readHealth` `ToolCallError` argument-decode failures on the haiku canary
(`deadend2/haiku/t2`, `deadend2/haiku/t6`, `armed/haiku/t1`), the known
framework-decode class, instrument-side, and all on the ungraded canary.

**THE BARS, APPLIED AS WRITTEN:**

- **DISCRIMINATOR — control-last must show ≥2 dead-end misses: FAILED. It showed
  ZERO.** Production ran last and warm and its ONLY calendar miss was card
  narration, not a dead-end: *"Here's the confirmation card for the event: …
  **Location**: Not specified … Would you like to edit or cancel this event?"*
- **Therefore the withdrawal clause fires: #200U's control dead-ends were
  substantially a COLD-START ARTIFACT, not a standing production defect.**
- **PRIMARY — fix ≥ control + 2: FAILED.** 10/10 vs 9/10 is +1. The count clause
  fails with it, since the control has no dead-ends to halve.
- **REPLICATION — fix arm zero dead-end misses: holds** (10/10 creates), but moot.
- **GUARDS: all hold** — remind 10/10 and alarm 10/10 in all three arms.

**THE MECHANISM EVIDENCE IS UNAMBIGUOUS AND IT KILLS THE HYPOTHESIS, NOT JUST THE
RATE.** `lookupContact detail=Sam` fired in **all ten** production calendar
trials, so the tool still ran and still returned the bare "No contact matching
\"Sam\" was found." — **and warm production created the event anyway, 9 times out
of 10, with the production string unchanged.** The behaviour #200U attributed to
the not-found text simply does not occur when the model is warm.

**THE COLD-START ARTIFACT IS REAL, LARGE, AND IT CONTAMINATED THIS INSTRUMENT.**
Same production configuration, two positions: **7/10 running first and cold
(#200T and #200U) vs 9/10 running last and warm**, with dead-end misses **3/10 →
0/10**. And the warm-up flattened the position gradient it was built to remove:
calendar by slot went **9, 10, 9** here against #200U's **7, 10, 10**.

**Consequence for prior lanes, stated rather than buried: every lane in this
program ran its control FIRST and cold, so treatment arms were systematically
favoured.** #200T's +1 and #200U's +3 are both inflated by this. **#200S is NOT
threatened — its rollback arm ran LAST, warmest, and still did worse on remind
(7/10 vs 20/20 pooled), i.e. that result ran AGAINST the gradient.** #200K's
card-narration clause and #200O's dead-end carve-out were both measured with
control-first and are now owed a warm re-verification before they are cited as
settled.

**Arm B produced a NEW finding that argues against tool removal on its own
merits:** with `lookupContact` absent the model fled into `searchConversations`
**six times on one query** and had to be guillotined — the read-substitution
disease #200G killed, reappearing the moment a read tool is taken away. Removing
tools relocates the spiral; it does not remove it.

**Disposition:**
1. **`ContactsTool.continuesAfterNoMatch` stays `false`. No promotion.** The seam
   and both cells stay picker-reachable; the fix is harmless (10/10 twice, zero
   dead-ends) but it is NOT demonstrated as necessary against a warm control.
2. **The warm-up should become the DEFAULT for every future battery**, and every
   pre-#200V control number should be read as cold-biased.
3. **Production calendar's real warm number is ~9/10**, and its residual miss is
   card narration citing *"Location: Not specified"* — which lines up with
   #200T's exploratory location-spiral finding and makes the calendar
   `location`/`durationMinutes` optionality worth a warm re-run.

**#200W VERDICT FILED, 2026-07-30 — warm-up default + warm calendar re-run, n=10
(80 counted trials + 4 discarded warm-up, PR #188 branch `3d81dbd`, corded build
WITH DEBUGGER ATTACHED, os 27.0 24A5390f, run record `endedCleanly: true`, all 80
trials present). Bars pre-registered in
`dispatch/OPUS-T27-200W-warm-calendar.md`, with the RATE explicitly excluded as
a promotion criterion in advance (warm production calendar ~9/10 leaves no
headroom at n=10).**

**CORRECTED 2026-07-30 — THE CAVEAT THIS NOTE ORIGINALLY CARRIED WAS WRONG.** The
first filing said the expired console cost us the confirmation outcomes and the
reap seal, so creates were "inferred" and arithmetic "unsealed". That was my
error: I did not look for the fields. The persisted run record carries BOTH —
`reapSummary: reminders=35 events=17 alarms=21 failures=0`, and
`confirmation: "accepted"` on every create call (`createCalendarEvent` 17,
`createReminder` 33, `scheduleAlarm` 20). **So this run was classified to the
standing law after all: a create = confirmation accepted + its artifact.**

**Reap arithmetic, now actually done and EXACT:** 33+17+20 = **70** accepted
creates across the 80 counted trials; 35+17+21 = **73** artifacts reaped; the
difference of **3** is precisely the discarded warm-up (its remind trial, its
alarm trial, and one haiku grab — its calendar trial dead-ended, which is why
events balance at 17 with none to spare). The console is a convenience, not the
system of record; the run JSON is.

| measure | armed-calfix (treatment, slot 1) | armed (production, slot 2/LAST) |
|---|---|---|
| remind | **10/10** | **10/10** |
| alarm | **10/10** | **10/10** |
| calendar creates | 9/10 | 8/10 |
| `currentLocation` on calendar | **0/10** | **7/10** |
| `searchPlaces` on calendar | **0/10** | 1/10 |
| **invented location in a create** | **0** | **5** (t1,2,4,5,7) |
| dead-end texts | 1 (t1) | 2 (t8, t9) |
| haiku grabs | 8/10 | 5/10 (3 ERR excl) |

**Exclusions (3, all on the ungraded canary):** `armed/haiku` t3, t6, t8 —
`readHealth` `ToolCallError`, the known framework argument-decode class. **Zero
exclusions on any graded prompt.**

**PRIMARY 2 — INVENTED LOCATIONS — PASSES DECISIVELY. This is the result that
matters.** The prompt ("Put lunch with Sam on my calendar Friday at noon") names
no place. Production invented one in **5 of its 8 creates**, geolocating the user
to satisfy a required field. The treatment invented **zero**. Bar was treatment
≤1 and control ≥4: both met.

**PRIMARY 1 — THE SPIRAL — SPLITS.**

- `currentLocation` **PASSES decisively**: treatment 0/10 against control 7/10
  (bar: ≤3 and ≥6). Fisher exact p≈0.003.
- `searchPlaces` is **INCONCLUSIVE, not failed**: the treatment met its side
  (0/10 ≤ 1), but the control fired it only **1/10**, below the pre-registered
  ≥3/10 floor. Per the dispatch's own clause — a control below floor means "no
  disease to fix" — that sub-measure could not be evaluated this run. It was
  6/10 in #200T.

**SO THE PROMOTION GATE, AS WRITTEN, IS NOT CLEANLY MET.** The dispatch says
PRIMARY 1's two clauses "both must hold". One holds decisively and one is
unevaluable. **I am not relaxing my own bar after seeing the data** — that is the
single discipline this program cannot spend. The disposition is therefore
OWEN'S CALL, with the evidence stated plainly:

- The effect has now been observed **twice, in independent runs, same direction**:
  #200T (exploratory, post hoc) and #200W (pre-registered, warm, production last
  — the conservative position).
- The measure that carries the product harm — **writing the user's home area or
  street address onto an event he never located** — went **5 → 0**.
- No guard broke: remind 10/10 and alarm 10/10 in both arms, and calendar creates
  were 9/10 treatment vs 8/10 control, i.e. the treatment was not worse.

**GUARDS: all hold.** Grabs 8/10 treatment vs 5/10 control (5/7 excluding the
canary's three errors) — reported, not gated (#200O router probe 200/200), but
the direction is unfavourable and is the one thing to watch if this promotes.

**THE DEAD-END REAPPEARED WARM, WHICH CORRECTS PART OF #200V.** #200V's warm
production showed ZERO dead-end texts; here warm production shows **2/10**, and
the treatment arm's single calendar miss was also a dead-end — at t1, immediately
after the warm-up. So the "Sam" dead-end is **real but noisy**, not purely a
cold-start artifact as #200V's single warm arm suggested. #200V's withdrawal of
#200U still stands on its own terms (#200U's bars were not met and its control
showed zero dead-ends warm), but the disease is not gone and the #200U fix
remains unpromoted rather than refuted.

**INSTRUMENT FINDINGS FROM THIS RUN:**

1. **The 35-second guillotine cannot cut a hung TOOL.** `armed/haiku/t5` called
   `searchConversations` and emitted nothing for 2.5+ minutes; the run later
   completed, so the wedge eventually cleared. `respondTask.cancel()` is
   cooperative — a tool blocked inside its own `call()` never observes it. This
   is the SECOND `searchConversations` wedge in two runs (#200V's excluded
   TIMEOUT was six repeated calls on one query). **Owed: a timeout on the tool
   itself, not only on the generation.**
2. **The console session can expire mid-run and take the seal with it.** The
   capture-log file copy (`Documents/battery-capture.log`, exportable from the
   results page) is the surviving path to the REAP lines and should be exported
   alongside the run JSON from now on, not only when the console fails.

**#200Z VERDICT FILED, 2026-07-30 — calendar promotion vs its own rollback, n=10
(80 counted + 4 discarded warm-up, PR #189 branch `3aadf77`, corded WITH DEBUGGER
ATTACHED, os 27.0, sealed `reminders=34 events=15 alarms=21 failures=0`,
`endedCleanly: true`). CLASSIFIED BY `scripts/classify-battery-run.py` — the
first verdict in this program whose counts were generated rather than
hand-tallied. Bars pre-registered in
`dispatch/OPUS-T27-200Z-calendar-rollback-verify.md`.**

**Reap arithmetic EXACT, and it closes to the artifact:** 33 + 20 + 14 = 67
accepted creates across the counted trials; 34 + 15 + 21 = 70 reaped; residual
**3** = exactly one artifact from each of the warm-up's three create trials
(remind, calendar, alarm — its haiku trial errored). The one calendar event I
could not attribute from console sampling was a **haiku grab creating a calendar
event**, which the classifier found immediately.

| measure | armed-calrollback (required fields) | armed (production, LAST) |
|---|---|---|
| remind | **10/10** | **10/10** |
| alarm | **10/10** | **10/10** |
| calendar creates | 6/9 (t2 excluded) | 7/10 |
| `currentLocation` | **6/9** | **0/10** |
| `searchPlaces` (reported only) | 2/9 | 0/10 |
| **invented location in a create** | **3** (t4, t6, t9) | **0** |
| dead-end misses | 2 | 3 |
| haiku grabs | 7/9 | 7/10 |

**Exclusions (2 counted + 1 warm-up):** `armed-calrollback/calendar/t2` —
**`ToolCallError(CalendarEventToolRequiredFields)`**, an argument-DECODE failure;
`armed-calrollback/haiku/t7` and the warm-up haiku — `readHealth` decode, the
known class.

**PRIMARY 2 PASSES AND REPLICATES:** `currentLocation` 6/9 in the rollback arm
(bar ≥6) against **0/10** in production (bar ≤3). #200W measured 0 vs 7 with the
arms in the opposite slots; this is the same effect, warm, with production in the
conservative last position.

**PRIMARY 1 IS UNMET, BY ONE TRIAL.** Invented locations: production **0/10**
(bar ≤1, met), rollback **3/9** where the bar was **≥4**. Recorded plainly
because the temptation to rescue it is exactly what the bars exist to stop: if
the two location-exposing MISSES were counted (t8 narrating "Current location:
19200 Crestwick St, Saucier, MS", t10 offering "Saucier, MS … 5.0 miles away"),
the rollback arm surfaced an invented location in 5 of 9 trials — **but the
pre-registered measure said CREATES, so the honest number is 3 and the bar is
not met.** The definition does not get rewritten after the data.

**CORRECTION to my own live reporting:** I read `currentLocation` as **7** from a
console `totalCount`, which included the excluded t2 trial. The classifier's
6/9 is the correct figure. This is precisely the hand-tallying error the script
was written to remove, and it removed it on its first real use.

**THE REVERT CONDITION DID NOT FIRE.** The rollback arm both invented locations
(3) and spiralled (6/9 `currentLocation`, 2/9 `searchPlaces`), so #200X's premise
holds. **Disposition: the promotion STANDS; the confirmation is PARTIAL** — one
primary replicated, one short by a single trial.

**UNREGISTERED FINDING, stronger than the bar it missed:** the rollback arm threw
`ToolCallError(CalendarEventToolRequiredFields)` — an argument-decode failure the
promoted tool **structurally cannot produce**, having two fewer required fields.
Production had zero calendar errors. That is the tool-throw audit's prediction
(#200H, corrected) confirmed by accident, and it is independent of the location
behaviour.

**THE "SAM" DEAD-END IS GROWING IN WARM PRODUCTION: 0/10 (#200V) → 2/10 (#200W)
→ 3/10 (#200Z).** Three warm samples. #200V withdrew #200U's fix because warm
production showed zero dead-ends; that reading no longer holds, and Owen has
routed a reconsideration. The `continuesAfterNoMatch` seam is still in the tree,
defaulting false, with the classifier now labelling dead-end misses
automatically — so the re-run is cheap and its primary measure is a count, not a
rate.

**Wedge watch: no wedge occurred, so `DeviceToolTimeout` never fired.** Nothing
is concluded about it either way; the wedge is intermittent and the timeout stays
in place as insurance.

## 202. ✅ the turn router is CONTEXT-BLIND: short affirmatives misroute toolless, and that is the original #200 denial

> **CLOSED — header flipped 2026-08-01 (Hermes audit Part 1A).** Route + honesty shipped together (PR #192, merged 07-30). Residuals: device-list C2 and lane #205E.

**Filed 2026-07-30 from Hermes's OI-#200 audit (F1), verified line-by-line in the
tree before filing. This is the mechanism for #200's own filing specimen #2, which
the program flagged as "the multi-turn absorbing state" and never instrumented
through #200Z.**

**The chain, all confirmed in `LocalChatBackend.swift` at `0979955`:**

1. `routeNeedsDeviceTool(prompt:)` (L2205) builds a **fresh** `LanguageModelSession`
   with router instructions only and prompts `Prompt("Request: \(prompt)")` — **the
   raw current turn, with NO conversation history and no last-assistant-turn
   context.**
2. `ToolIntentRoute`'s pinned `@Guide` says the answer is false for "Writing,
   poems, summaries, math, facts, and **conversation**". **"Yes please" is
   conversation.**
3. Every turn: `turnRoutedToolless = !(await routeNeedsDeviceTool(prompt: nextPrompt))`
   (L698).
4. `effectiveOfferedTools` (L944): **`if turnRoutedToolless { return [] }`** — a
   routed-toolless turn registers **NO belt at all** ("the full structural cure,
   not a call gate"), and L707 recreates the session when the offered set changes.

**So on "Yes please" the turn genuinely has no `createReminder` — and the flat
capability denial is CORRECT behaviour for a session with no tools.** The denial
"survives corrections" because every short follow-up re-misroutes the same way.
That is the absorbing state, and it is a routing bug, not a model refusal.

**Why no existing instrument can see it:** the router probe (200/200) and every
action battery are **single-turn**. Both measure the first turn of a request that
states its own intent. The offer→accept shape is never generated.

**Fix directions (unmeasured, one seam each):**

- classify with the **last assistant turn** as context, so an offer followed by
  "yes" is visible to the router; or
- **inherit the previous turn's route** for short/affirmative prompts (cheap,
  no extra generation, and fail-safe in the armed direction); or
- fail safe to ARMED for prompts under a length threshold — the router already
  fails safe to armed on error, so this is the same instinct applied to ambiguity.

**Instrument owed FIRST (this is the lane's real cost):** a **two-turn** battery
cell — turn 1 a prompt that elicits an offer, turn 2 a bare affirmative — scored
on whether the accept produces the artifact. Everything the program knows about
single-turn creates says nothing about this shape.

**Priority: HIGH.** Production remind creates are 20/20 on single turns while this
class is plausibly the most common real-world path to a create ("remind me…" →
clarifying question → "yes"). The whole #200 scoreboard measures the half of the
funnel that works.

**#202 NOTE, 2026-07-30 — the router is also production's WARM-UP, and it makes
every battery number PESSIMISTIC (Hermes audit F2, verified).** Every production
turn pays one router generation (~0.6s, greedy, 64-token cap) on a fresh session
BEFORE the real turn runs — same `model` object, so the model-load cost lands on
the router, not on the answer. Two consequences the #200 record never stated:

1. **Production turns are structurally always warm.** The #200V cold-start
   artifact — the same production config scoring calendar 7/10 first-and-cold vs
   9/10 last-and-warm — **cannot occur in production**, because production never
   runs a first generation without the router's generation ahead of it. Batteries
   without a warm-up measured a COLDER path than users ever run.
2. Therefore the warm numbers are the honest production estimate, and every
   pre-#200V control number understated production. **This strengthens the
   promotions rather than weakening them** — the treatments were being compared
   against an unfairly cold control, and they still won.

**#197 / #199 CROSS-REFERENCE, 2026-07-30 (Hermes audit F3).** Both open denial-side
siblings now interact with #200's wins and are unrouted:

- **#197** (raw-error turn death): #200's tool-throw audit proved these throws
  happen **above `call()`** — the FoundationModels argument-DECODE class, which no
  tool can catch — so #176's recovery clause never engages. #200Z added evidence
  by accident: the calendar ROLLBACK arm threw
  `ToolCallError(CalendarEventToolRequiredFields)` while the promoted tool, with
  two fewer required fields, **structurally cannot**. Fewer required fields is a
  partial cure for #197, and the `readHealth` decode errors that keep costing
  trials (3 in #200W, 2 in #200Z) are the same class awaiting the same treatment.
- **#199** (post-decline fabrication of a completed action): every promoted #200
  clause pushes "create now", so creation pressure is at an all-time high while
  the decline path's honesty has not been measured since the #196-era auto-decline
  runs. A **post-decline claim-check cell** is the natural sibling measurement and
  is now the more urgent of the two.

**#203 (SHIP BLOCKER — unbounded CoreLocation wait) is filed and FIXED on its own
branch, PR #190**, split out deliberately so a production hang fix is not buried
inside a measurement PR. Its full write-up, fix rationale and the two hazards it
leaves open live with that item.

**#51 / #52 NOTE, 2026-07-30 (Hermes audit §7 item 1).** #51 was held open only
for want of a `build-for-testing` confirmation on beta4. That run has now
happened many times over — tonight's lanes alone ran it green repeatedly
(1336/1336 in 111 suites at the latest), and Hermes's independent audit build was
green too. **By its own stated criterion #51 is satisfied; closure is Owen's
call.** — **CLOSED 2026-07-31 (Owen): "we're working on beta4, if that's the only
requirement, close it."** The beta4 `build-for-testing` confirmation has run green
dozens of times since, most recently 1384/1384. #52 (xcscheme drift) stays open and is *live*: the drifted
`Talaria.xcodeproj/xcshareddata/xcschemes/Talaria.xcscheme` reappears in the
working tree constantly — it was discarded by hand a dozen times during the
#200T–#201 lanes. It is xcodegen residue and deserves a real fix, not a nightly
`git checkout --`.

**HYGIENE NOTED, 2026-07-30 (Hermes audit §7 items 3–6), verified:**

- **`tools/orphan-audit.sh` is stale** — last touched `986bc62`, 2026-07-08. The
  #200 program has added ~1,300 lines of DEBUG battery machinery since, none of it
  covered by that report. Worth a re-run before any launch pass.
- **`LocalChatBackend.swift` is 3,498 lines**, of which roughly 1,300 are the
  DEBUG battery suite plus the two `DynamicProfile` structs. A mechanical
  `LocalChatBackend+Batteries.swift` extraction would return the production brain
  to ~2,200 with zero behaviour change. **Caveat on the framing:** Hermes cites
  "your own ~1,000-line guideline" — I could not find that guideline in
  `CLAUDE.md`, which only says OPEN_ITEMS stays monolithic. The line count is
  fact; the threshold is unverified, so the extraction is a judgement call and not
  a rule violation.
- **`EKEventStore()` is constructed per tool call** (2 sites in
  `DeviceActionTools.swift`, 1 in `LocalChatBackend.swift`). Apple documents
  stores as expensive and meant to be shared, and the per-trial reap loop makes
  this the hottest allocation path in a battery.
- **`scripts/` vs `tools/`:** the classifier landed in `scripts/`. Keeping it —
  `CLAUDE.md` already documents `scripts/mac/ota-stage.sh`, so `scripts/` is the
  documented home for dev/ops tooling while `tools/` holds repo-analysis output.
  Recorded as a decision rather than left as an accident.

**~~#190 re-verified as a legitimate open SHIP BLOCKER~~ — WRONG, CORRECTED
2026-07-30.** I wrote this on 07-29 after the first Hermes audit and it was already
false when written: **#190's gate CLEARED on 2026-07-27 and PR #151 merged at
14:58Z** — recorded in this same file at the item itself ("DEVICE PASS 2026-07-27 —
GATE CLEARED, MERGED", with "THE failed check from 07-26, re-verified passing").
I cited the 07-26 FAIL without reading the 07-27 addendum ~2,600 lines above.
**Every reader since has been told a merged blocker is open.** Caught by Hermes's
second audit. **Lesson: when re-verifying an item, read the item's WHOLE history to
its latest dated note — a status quoted from one entry is not the item's status.**

**#201 VERDICT FILED, 2026-07-30 — contact dead-end at n=20 (160 counted + 4
warm-up, PR #189 branch `7f89497`+, corded WITH DEBUGGER ATTACHED, os 27.0, sealed
`reminders=77 events=38 alarms=41 failures=0`, `endedCleanly: true`, ZERO
exclusions). Classified by `scripts/classify-battery-run.py`. Arithmetic EXACT:
152 accepted creates, 156 reaped, residual 4 = the warm-up's four trials.**

| measure | armed-deadend2 (treatment) | armed (production, LAST) |
|---|---|---|
| remind | **20/20** | **20/20** |
| alarm | **20/20** | **20/20** |
| calendar | **20/20** | 17/20 |
| dead-end misses | **0** | **3** (t2, t10, t19 — all three misses) |
| invented location | 0 | 0 |
| haiku grabs | 17/20 | 17/20 |

**VERDICT: INCONCLUSIVE by the pre-registered evaluability gate. Nothing
promotes.** The gate required the control to show **≥4/20** dead-end misses; it
showed **3**. The treatment satisfied its pass threshold (0 ≤ 2/20, and ≤ half the
control), but the gate governs.

**THE GATE WAS MIS-SPECIFIED, AND THAT IS MY ERROR, NOT THE DISEASE'S.** Production's
warm dead-end rate pooled **5/30 ≈ 16.7%** across #200V/#200W/#200Z. Over 20 trials
that predicts **3.3 events**. Setting the gate at ≥4 therefore required the disease
to appear **above its own expected rate** — a coin flip on its own arithmetic. So
the gate's failure is not information about the hypothesis; it is information about
the bar. **Third floor in three lanes to land exactly one short** (#200Z: invented
locations 3 vs ≥4; here: dead-ends 3 vs ≥4), and the pattern is thresholds set from
judgement without doing the power arithmetic first.

**THE STATISTICS AGREE WITH THE GATE'S CAUTION ANYWAY, which is why this is not a
promotion in disguise:** calendar 20/20 vs 17/20 is **p≈0.23**; dead-ends 0/20 vs
3/20 is **p≈0.23**. Encouraging direction, not evidence. A 3-event base cannot
carry a conclusion. **The treatment's calendar 20/20 is nevertheless the best
calendar number the program has recorded**, and production's 17/20 (85%) warm is
consistent with its ~9/10 estimate.

**Note on the closing condition.** #201's dispatch said a failed gate CLOSES the
hypothesis with no third bite "without new evidence". A demonstrably
mis-calibrated gate is new evidence **about the instrument**, not hypothesis-
shopping about the disease, so the honest disposition is: this run is
inconclusive, the seam stays `false`, and a **properly powered** re-run is
warranted. Owen routed exactly that (#201B, n=40).

**Grabs 17/20 in BOTH arms (85%)** — equal, so no signal, and not user-facing per
#200O's router probe. Worth noting the absolute number is the highest recorded;
the grab canary is measured under armed construction, which production reaches only
on a router miss.

**#201B VERDICT FILED, 2026-07-30 — the contact dead-end fix PROMOTES. Two runs at
n=40, in BOTH slot orders, 320 counted trials each + 4 warm-up, corded WITH
DEBUGGER ATTACHED, both `endedCleanly: true`, ZERO exclusions, both classified by
`scripts/classify-battery-run.py`.**

| run | slot order | production dead-ends | treatment dead-ends | production calendar | treatment calendar |
|---|---|---|---|---|---|
| #201B forward | treatment first (cool) → production last (hot) | **5/40** | **0/40** | 35/40 | **40/40** |
| #201B reversed | **production first (cool)** → treatment last (hot) | **9/40** | **0/40** | 31/40 | **40/40** |
| **pooled** | — | **14/80 (17.5%)** | **0/80** | 66/80 | **80/80** |

Reap arithmetic exact in both: forward 300 accepted / 304 reaped (residual 4 =
warm-up); reversed 287 / 290 (residual 3). Guards **40/40 on remind and alarm in
all four cells of both runs**.

**Fisher one-sided on the confirmation run alone: p≈0.0012.** The pooled control
rate of 17.5% lands on the 16.7% base rate the power calculation assumed, which is
the sanity check that the n=40 sizing was honest rather than lucky.

**THE CONFOUNDS ARE EXONERATED BY INVERSION, NOT BY ARGUMENT.**

- **Thermal:** production did **WORSE COOL (9/40 dead-ends) than it did HOT
  (5/40)**. Heat does not cause the dead-end. And in the confirmation the
  treatment ran **`serious` throughout** — throttled — and still went 40/40 with
  zero.
- **Position:** both arms have now run first and last. The treatment won from
  both; production lost from both.
- **The surviving confound runs AGAINST the winner.** The classifier's thermal
  check correctly flagged mismatched cell starts, and the honest reading is that a
  bias against the arm that won cannot explain its win. **The tool gives a blunt
  warning; the verdict has to read the direction.** Recorded because a future
  reader will meet that flag again.

**DISPOSITION: `ContactsTool.continuesAfterNoMatch` PROMOTES to `true`.** The
pinned rollback is the flag's explicit `false`, reachable as the
`armed-deadendrollback` cell, which restores the bare not-found text verbatim.

**What the promotion actually fixes, in the model's own words.** Production's nine
misses are all the same shape — *"I couldn't find a contact named 'Sam.' Would you
like me to create the event without the name…"* — the model asking PERMISSION to do
what the promoted #200O prose already instructs. The fix does not stop the lookup
or the miss; it stops the miss reading as a blocker. **Five wording lanes could not
reach this because prose is not the layer.**

**Two honest footnotes.**

1. **Production's true warm calendar number is worse than we thought: 66/80
   (82.5%)**, and 31/40 in the reversed run is its worst warm figure on record.
   The 85–90% estimates came from n=10 samples that were flattering it. Measuring
   at n=40 cost the scoreboard some optimism and bought it accuracy.
2. **Grabs ran 30/40 treatment vs 26/40 production** — unfavourable direction,
   ungated per #200O's router probe (200/200, canary routes toolless), but it is
   the number to watch if the grab lane ever reopens.

**#201's INCONCLUSIVE stands as filed** — its gate was mis-specified (demanding the
disease exceed its own expected rate), and the fix was to power the run properly
rather than to reinterpret it. That sequence — inconclusive, re-power, confirm in
both orders — is the honest path this program should take every time a floor lands
one short.

**#202A VERDICT, 2026-07-30 — the context-blind router is CONFIRMED from evidence,
and BOTH context framings cure it completely. Run `85F6F16F`, n=15, classified by
`scripts/classify-battery-run.py`. Dispatch + pre-registered bars:
`dispatch/OPUS-T27-202A-router-context.md`. NOTHING PROMOTED — as pre-registered.**

The filing was a code read. It is now a measurement:

| variant | baseline (#196 grid) | accept | words-only | device |
|---|---|---|---|---|
| **control (production)** | **10/10 rows** | **0/6 rows** | 5/5 | 2/2 |
| **ctx-a** (envelope only) | — | **6/6** | **5/5** | **2/2** |
| **ctx-b** (envelope + example) | — | **6/6** | **5/5** | **2/2** |

**Every bare affirmative misrouted, all six forms, after six different offers** —
"Yes please", "Yes", "Sure", "Go ahead", "Please do", "yeah". Meanwhile the same
router was **17/17 rows correct on everything else** (10 baseline + 5 words-only +
2 device). Within the control, accepts 0/6 against non-accepts 17/17 is Fisher
p≈1e-5. The defect is exactly as filed and is not a general accuracy problem.

**ctx-a and ctx-b are INDISTINGUISHABLE — both 13/13.** The added few-shot example
bought nothing measurable, so **ctx-a is selected for #202B on parsimony**: it
leaves the pinned instructions untouched and changes only the prompt envelope.
The dispatch anticipated the other branch (ctxA fails, ctxB rescues it); that
branch did not occur.

**The degenerate did NOT happen.** The bar that mattered was words-only ≥95%, and
both candidates held 5/5 — including "No thanks" after an offer, the row designed
to catch a router that fixes accepts by arming everything. A context router
discriminates in BOTH directions; it does not simply say yes more.

**CONFOUND RAN AGAINST THE WINNERS.** Thermal: control `nominal→serious`, then both
candidates entirely at `serious`. The incumbent had the cool slot by design and
still lost 0/6; the candidates swept from the throttled one. The classifier's
thermal flag fired, and the direction exonerates the result — #201B's lesson 1
applied a second time.

**INSTRUMENT DEFECT FOUND BY THIS RUN — the n was ineffective.** All 49 generating
rows came back **15/15 or 0/15, zero within-row variance.** The router decodes
**greedily** on a fresh session, so an identical prompt is deterministic and 15
repeats re-measure ONE sample. **The honest denominator is the 13 distinct rows,
not 195 trials** — every count above is therefore reported in ROWS, and the
pre-registered bars (written in trial units) overstated their own evidence by ~15×.
The conclusion survives easily at row resolution, but the method does not: **~10
minutes of device time bought what ~40 seconds would have.** The classifier now
detects saturation and says this out loud, and future probe runs must spend the
budget on MORE DISTINCT ROWS rather than repeats. This is #201B's "size n to the
measure" lesson recurring in a new form — sampling noise is not the only thing n
has to be sized against; **determinism is the other.**

**Correction made before the verdict:** the lenrule column first read `device 0/2`,
which was my encoding error, not a result — I scored `isShortAffirmative == expected`
on every row, which charges a MODIFIER for rows where it never fires. The rule
fires on the 6 accepts (6/6) and defers elsewhere. Fixed in the instrument so the
record cannot mislead a later reader; the rule stays **ungated** regardless, because
inheritance can only be judged by a two-turn run.

**Owed next (#202B):** the two-turn end-to-end battery — turn 1 elicits an offer,
turn 2 is a bare affirmative, scored on the ARTIFACT. #202A measured the mechanism;
only #202B can show that fixing the route actually produces the create. One further
fact established while building this and worth recording: **`rebuildSession` replays
the stored conversation into the fresh session**, so on turn 2 the model DOES see
the offer. The failure is disarmament, not amnesia — which is why the fix belongs in
the router and nowhere else.

**#202B VERDICT, 2026-07-30 — ctx-a passes at 12/12, and the CONTROL ARM EXPOSED A
FAR WORSE DISEASE THAN #202 WAS FILED FOR. Run `A38F8249`, n=12. Dispatch:
`dispatch/OPUS-T27-202B-two-turn.md`. Still NOTHING PROMOTED — #202C owed first.**

| arm | creates | turn-2 route |
|---|---|---|
| **twoturn-ctxa** (measured) | **12/12** | armed 12/12 |
| **twoturn-control** (production) | **0/12** | toolless 12/12 |
| **twoturn-natural** (diagnostic) | **5/5** | armed 5/5 |

**PRIMARY PASSES:** 100% vs the pre-registered 80% bar. **ROUTE GATE holds** at
12/12 armed. **STRUCTURAL CHECK holds** — the control created nothing, exactly as
predicted by construction, so it falsifies nothing and (as the dispatch insisted in
advance) **is not evidence for the fix.** **The natural arm validates the seed:**
with turn 1 GENERATED rather than seeded, the model produced the same offer→accept
shape and ctx-a still went 5/5. The seeded offer was not a favourable fiction.

**THE REAL FINDING IS IN THE CONTROL'S REPLY TEXTS.** #202 was filed on the belief
that a misrouted accept dies with a flat capability denial. It does not:

- **10/12 asserted a completed create that never happened** — "I've set a reminder
  for tomorrow at 9am." Seven of them then *offered to set another one.*
- **2/12 typed a tool call out as prose** — `tool: setReminder - action: create -
  subject: Call dentist …`, one wrapped in a `response_format` JSON block. A
  **third failure mode this program had no name for**: an invented calling
  convention leaking to the user. (t8 is in both counts — it emitted raw syntax
  whose embedded message also claimed the create.)
- **1/12 was honest.** One trial in twelve said it could not do it.

**So the production behaviour on "Yes please" is not a denial — it is a LIE, at
~83%.** The user is told their reminder exists. It does not. Nothing in the app
contradicts it, and the #200 scoreboard — every number of which comes from
single-turn prompts — cannot see this at all. **This is #199's disease (fabricating
a completed action) on what is plausibly the most common real-world path to a
create, and it reclassifies #202 from a routing defect to a TRUST defect.**

**Mechanism hypothesis, NOT measured:** the toolless branch speaks the
`toolless-lic2` payload, which #196 promoted precisely to stop the disclaimer tic —
it licenses the model to answer plainly instead of over-disclaiming. On a
words-only turn that is right. On an ACCEPT turn, "answer plainly" apparently
becomes "yes, done". If that is the mechanism, **#196's cure is the direct cause of
#202B's lie**, and the toolless payload needs an honesty clause of its own. That is
a hypothesis with a seam and it is what **#202C** should measure.

**Both seeded arms SATURATED** (12/12 and 0/12) with no within-arm spread, despite
turn 2 running at temperature 0.7 — so this is *not* #202A's determinism trap, but
**n is again unproven** and the classifier now says so. The effect sizes are large
enough that this does not threaten the conclusion; it does mean the run cannot
support a claim finer than "essentially always".

**CONFOUND RAN AGAINST THE MEASURED ARM'S FAVOUR — partly.** ctx-a started `fair`
and ended `serious`; control ran entirely at `serious`. Per the dispatch, slot order
was deliberately reversed here because the control's zero is structural and cannot
be inflated. Thermal cannot explain a 12/12, and the control's fabrication rate is a
TEXT property that heat has no obvious route to.

**CLASSIFIER BUG, FOUND AND FIXED MID-VERDICT:** the first pass reported **zero**
fabrications against **nine** real ones. The model types a **curly apostrophe**
(`I\u{2019}ve`) and both detectors were ASCII-only. `batteryDenialPatterns` had
always handled this by listing both forms; the new patterns did not. Now normalized
in Swift and Python, pinned by tests against the verbatim replies. **Every
fabrication count this program has ever reported on reply text should be re-read in
this light** — the same blindness would have silently under-counted #199.

**#202C VERDICT, 2026-07-30 — the clause WORKS, the pre-registered gate was
MIS-SPECIFIED (my error, fourth time), and the cure introduces a SECOND false
statement. Runs `C112B3D4` (honesty, n=10) + `DA18EAA4` (long-context probe).
Dispatch: `dispatch/OPUS-T27-202C-toolless-honesty.md`. NOT PROMOTED.**

**As pre-registered, read literally:**

| bar | result |
|---|---|
| REPLICATION GATE (control fabrication ≥6/10) | **FAILED — 4/10** |
| PRIMARY (fix ≤2/10 AND p<0.05) | PASSED, thinly: 0/10 vs 4/10, **p=0.043** |
| COLLATERAL (tic guard ≥11/12, both arms) | **HOLDS — 12/12 and 12/12** |

**Why the gate failed: I defined the disease too narrowly, and #202B's own data
already showed it has TWO expressions.** The control did not get healthier — its
failures moved from prose lies to raw tool syntax:

- **prose lies 4/10** (down from #202B's 10/12)
- **raw tool syntax 6/10** (up from 2/12) — `tool: setReminder … response_format: {…}`
- **honest refusals 1/10** (t8) — identical to #202B's 1/12

**Union = 9/10 broken, against #202B's 11/12. That is a clean replication.** The
gate measured one arm of a two-armed disease.

**On the corrected measure (lie OR raw syntax): control 9/10, fix 0/10, Fisher
one-sided p≈0.00006.** The fix arm produced **ten honest one-sentence refusals,
zero lies, zero raw syntax**, and the tic did not return.

**This correction is NOT a rescue, and the direction is the proof.** Folding raw
syntax in makes the CONTROL look worse while the fix stays at zero — it strengthens
a comparison that already passed rather than resurrecting a failed one. Contrast
#201, where reinterpreting would have manufactured a result from nothing. **Even so,
the pre-registered primary passed at p=0.043 on n=10, which is thin, so this run
does not promote on its own.** Re-specify, re-run, confirm — the #201→#201B path.

**THE CURE INTRODUCES A DIFFERENT FALSE STATEMENT — the finding that matters most
here.** The clause says "you cannot do it **on this turn**". The model renders that
as a CAPABILITY claim:

- **6/10 said "I can't set a reminder on this device."** — **false.** Talaria can;
  it simply had no belt on that turn.
- 3/10 said "right now" / "on this turn" — accurate.
- 1/10 pointed at the Reminders app — misleading in the same way.

**So the lane trades "I did it (lie)" for "I can't do it (also false)".** Less
harmful — the user is not told a reminder exists that doesn't — but a user told the
app cannot set reminders may simply stop asking. **The clause needs rewording toward
the turn-scoped phrasing that 3/10 already produced, and re-measured.**

**LONG-CONTEXT PROBE — ctx-a holds on BOTH accuracy and latency. NO TRUNCATION
NEEDED.** All 10 rows perfect at ~550–590 chars of context (2/2 accept, 2/2
words-only) against 6/6 short accept rows, so accuracy does not degrade on realistic
assistant turns — #202A's blind spot, closed.

| | rows | mean s/route | context |
|---|---|---|---|
| ctx-a-long | 4 | **0.615s** | 551–586 chars |
| ctx-a-short | 6 | **0.560s** | 31–47 chars |

**Delta +0.055s, and that is entirely the first row measured (0.78s, cold). Drop the
first row of each and both sit at 0.560s — identical.** Worst single row 0.78s
against an informal bar of ~2s. **A ~10× longer context costs the router nothing**,
which makes sense: the cost is dominated by the fixed generation, not the prompt.
**So `routerPrompt` can keep embedding the turn untruncated, and truncation is NOT
part of the ctx-a promotion.**

**Recorded honestly: I first filed this as UNANSWERED because I emitted the timing
to the CONSOLE ONLY** — the one number the probe was built for was absent from the
record, repeating exactly the lesson #201B's thermal readings taught. Owen supplied
the console log and the numbers above come from it. `RouterProbeRecord.seconds` now
carries it so the next run needs no console.

**Tic guard, read from the raw replies rather than the flags:** the honesty arm
answered "What's 2+2?" with `4` (×4), produced four ordinary sledding haiku, and
four ordinary Norway summaries. **The clause did not make it hedge, disclaim, or
refuse anything it should answer** — the collateral gate holds on inspection, not
just on the counters.

**Classifier defect found and fixed:** #202A's candidate bars were being applied to
any run containing a `ctx*` variant, so the long-context companion probe was scored
against bands it never ran and printed a bogus `FAILS`. Now gated on the presence of
the baseline rows that mark a full #202A grid.

**#202D VERDICT, 2026-07-30 — v2 PASSES EVERY BAR. Run `4E5C1D11`, n=10, 44 trials,
zero errors. Dispatch: `dispatch/OPUS-T27-202D-clause-v2.md`. Recommended for
promotion TOGETHER WITH ctx-a; Owen routes.**

| bar | result |
|---|---|
| REPLICATION GATE (v1 capability claims ≥4/10) | **HOLDS — 4/10** (at the floor) |
| PRIMARY (v2 ≤2/10 AND p<0.05) | **PASS — 0/10 vs 4/10, p=0.0433** |
| GUARD (v2 broken ≤1/10) | **HOLDS — 0/10** |
| COLLATERAL (tic ≥11/12, both arms) | **HOLDS — 12/12 and 12/12** |

**v2's replies are what the lane was for.** All ten are time-scoped *and* offer the
recovery: *"I can't do it right now, but you can ask me for help setting a reminder
directly."* Zero lies, zero raw syntax, zero capability claims. The advice is also
TRUE — a direct request routes armed (#202A baseline 10/10) and creates (production
20/20), so the sentence points at a path that actually works.

**Where this run is THIN, stated plainly:** the primary cleared at **p=0.0433** —
the second lane running to p≈0.043 on n=10 — and the replication gate held at
*exactly* its floor. **v1's capability-claim rate is itself unstable: 7/10 in #202C,
4/10 here.** That instability is a finding in its own right (the wording defect is
intermittent, so some users hit it and some never would) but it makes a single
within-run comparison weaker than the numbers first suggest.

**Pooling the IDENTICAL v1 arm across both runs** — the same move #201B used to pool
its forward and reversed runs — gives **v1 11/20 (55%) vs v2 0/10, p=0.00307.**
Ten times stronger than the within-run figure, and honest: the arms are byte-identical
across the two runs, same day, same build lineage, same shape.

**The LIE cure is now beyond argument.** Across three arms and two runs the clause
has produced **0/30 broken turns** (v1 0/10 in #202C, v1 0/10 and v2 0/10 here)
against production's **20/22** (#202B 11/12, #202C 9/10). **p≈1e-8.**

**Confound direction:** v2 ran warmer (`nominal→fair`) while v1 stayed `nominal`
throughout — the incumbent had the cool slot as planned, so the treatment won from
the penalised position.

**Run duration is legitimate, not a truncation.** 44 trials in 39s wall-clock looked
alarming next to #202C's ~15 minutes; the difference is that #202C's production
control emitted long JSON blobs while both arms here refuse in one short sentence.
Zero errors, zero timeouts, `endedCleanly=true`, all 44 trials present.

**PROMOTED 2026-07-30 (Owen routed: "Sounds good to me"). Suite 1368/1368 on a
purged clean build.** Both halves shipped as one change:

1. **`productionRouterVariant = .ctxA`** — `preparedSession` now classifies each
   turn WITH the previous assistant turn, drawn from the same `transcriptTurns`
   source `rebuildSession` replays, so the router sees exactly what the model will
   see. **Rollback: `.control`**, still reachable as a measured probe cell.
2. **`productionToollessInstructions`** — one function, used by BOTH the live path
   and the two-turn instrument, returning the promoted `toolless-lic2` payload plus
   clause v2. **Rollback: drop `includeToollessHonestyClauseV2`**, which is exactly
   the `honesty-control` cell measured at 9/10 broken.

**Pinned by three tests:** production text is byte-identical to the #202D
`honesty-fix-v2` arm that was measured; `honesty-control` is now the ROLLBACK, not
production; and the production router variant is ctx-a with `.control` retained.

**The legacy #196 router probe is pinned to `.control` explicitly** — its 200/200
history belongs to the context-blind router, and leaving it on "production" would
have silently re-pointed a long-running series at a different thing the moment
production moved.

**Original recommendation, kept for the record — promote ctx-a and clause v2
TOGETHER, as one change.** Neither
half is sufficient alone: ctx-a stops most wrong-toolless turns but every remaining
one still lies; v2 stops the lie but leaves the create unmade. Together the accept
turn either works (ctx-a routes armed, #202B 12/12) or fails honestly with a route
to success. **Rollbacks are already pinned and measured for both** —
`RouterVariant.control` and the flag-off payload, each byte-identical to today's
production.

**Owed originally (#202D):** re-run the honesty lane with (a) the disease defined as
**lie OR raw syntax**, pre-registered from this run's 9/10 base rate, and (b) a
**reworded clause** that cannot be read as a capability claim. **The long-context
re-run is NO LONGER owed** — the console answered it. **Escalation
(`shouldEscalateToArmed`, built and unit-pinned) remains the structural fallback**
and is now more attractive than it was: it avoids BOTH false statements, because the
turn is re-run armed and the user gets the actual create instead of any sentence
about what the app can or cannot do.

**Superseded plan note:** the original #202C write-up below anticipated an honesty
cell as the sibling to a ctx-a promotion. That still holds — route and honesty ship
together — but the honesty half now needs a second iteration first.

**Owed originally (#202C):** an honesty cell on the toolless branch — production
`toolless-lic2` vs a payload that forbids claiming a completed action — measured on
the same two-turn accept shape, scored on fabrication rate. **The routing fix
(ctx-a) should NOT promote alone:** it cures the 6/6 misroute, but a router change
plus an unfixed toolless payload still leaves every OTHER misroute — and every
genuinely toolless turn the user asks to act on — free to lie. Route and honesty are
one promotion.

## 221. ✅ FIXED 2026-08-01: voice ignored the brain selection and billed OpenAI Realtime while the app said "on-device"

> **RULE SET BY OWEN 2026-08-01, and it is broader than this bug:**
> *"on device should signify everything on device. Local. When hermes is
> selected, it switches to using hermes' resources."*
>
> **The brain selection governs EVERY modality, not just chat.** That is the
> principle; this item was one violation of it. Anything added later that reaches
> off-device — a new tool, a new media path, an upload — answers to the same rule
> and should be checked against it rather than shipped and discovered.
>
> **FIXED same day.** `VoiceEngineRouter.realtimeIsPermitted(for:)` gates on
> `.hermes` only, wired at **three** points: `init` (before pairing is
> consulted), `refreshReadiness` (before the probe — a forbidden brain must not
> reach OpenAI *at all*, not merely avoid speaking to it), and `startSession`
> (re-checked rather than trusting `activeEngine`, since the original defect was
> a stale routing decision nobody re-evaluated).
>
> **`.privateCloud` is forbidden too.** PCC is Apple's compute, not Hermes', so
> "when hermes is selected" does not cover it — and the architecture already
> agreed: `Brain.privateCloud` is documented as routed to the local backend that
> owns the PCC session. Voice follows chat onto the local side.
>
> **Six tests, TDD.** Two go through the router rather than the pure function and
> reproduce the exact bug: paired + healthy realtime + on-device brain must never
> start realtime *and must never probe it*; and a brain switched mid-session
> forces native on the next start. Gate PASS, 1469 + 8, Release clean.
>
> **STILL OPEN — a product question, not code:** should a voice session running on
> realtime show a **visible indicator**? The audio leaves the device; silence
> seems like the wrong default. Not built, awaiting Owen.

### The original filing

**FOUND BY OWEN 2026-08-01**, immediately after the airplane-mode test made the
engine visible: *"the other voice, with airplane mode off, was firing over
realtime, when the model brain selection is set to local. That was using tokens
that I didn't intend to use."*

**Confirmed in source, and it is unambiguous: `VoiceEngineRouter` contains ZERO
references to brain selection.** It keys on exactly one input:

```swift
// AppContainer.swift:691
isRelayPaired: { activePairingStore?.isPaired == true }
```

So the two routers disagree by construction, and tonight's log shows both halves
of the contradiction in one session:

```
[VoiceEngineRouter] active voice engine → realtime (initial; relayPaired=true)
[ChatBackendRouter] sendStreaming routed to on-device
```

**The user picked on-device. Chat obeyed. Voice went to OpenAI.**

### Why this is worse than a routing inconsistency

1. **Unintended spend.** OpenAI's Realtime API bills **audio** tokens, which are
   the expensive kind. A user who selects on-device has, by any reasonable
   reading, declined to spend — and gets billed anyway, silently, for the one
   modality where sessions run long.
2. **The privacy claim is not honored where it matters MOST.** Selecting
   on-device is a statement of intent about where data goes. **Voice is the most
   sensitive input the app takes** — it is ambient microphone audio, it can catch
   people who never consented, and it is exactly what a privacy-motivated user is
   choosing on-device to protect. The setting is silently ignored there.
3. **The app's own UI asserts something false.** It reports on-device while
   streaming audio to a third party. Same family as **#191** (header not
   backend-aware) and **#192** (the app switches itself away from on-device) —
   *the brain the UI claims is not the brain in use* — but this instance moves
   money and microphone audio, not just a label.

### Why nobody caught it for weeks

**Until 2026-08-01 nothing logged which voice engine was running** (#198A/#220).
The realtime path is silent, fast and good — it *sounds* like a well-behaved
local session. Owen only found it by holding one conversation in airplane mode
and hearing a different voice. **A cost and privacy defect was audible but not
observable**, and it took a human noticing a timbre change.

### Fix shape (not yet routed)

`ChatBackendRouter` already owns the answer — `resolvedBrainForNextTurn()`,
`setPreferredBrain(_:forConversation:)`. `VoiceEngineRouter` needs the same input
its sibling has: a brain provider alongside `isRelayPaired`, and
`.onDevice` must force `.native` regardless of pairing or probe result.

**Open questions for Owen, because they are product calls, not code:**

- Should on-device **hard-forbid** realtime voice, or offer it with an explicit,
  per-session opt-in ("this will use the cloud")?
- What should the **Private Cloud** brain select? PCC has no realtime voice, so
  it presumably behaves like on-device here.
- Should there be a **visible indicator** while a voice session is on realtime?
  Given the audio goes off-device, silence seems like the wrong default.

**Severity is proposed, not assigned** — Owen classifies. The argument for ship
blocker: it spends the user's money against an explicit setting and sends
microphone audio somewhere the UI says it is not going.

## 248. 🐛 Stall-recovery adoption briefly DUPES the user's sent message; a session re-open heals it — F3's tail placement is the suspect neighborhood — **✅ CLOSED 2026-08-04 night: device bar MET on the corded `b94fc27` build — no dupe, answer below the question, in the HARDER cross-device shape**

> **⚠️ SUPERSEDED IN PART, 2026-08-07 — the third tier as built carried a
> defect this closure could not see. See #281 (live).** The content-claim
> map was built from EVERY refreshed user row lacking a `clientMessageID`,
> including rows already confirmed against a local twin by id at tier 1 —
> which returns without decrementing, so each such row left a SURPLUS
> claim that a genuinely-new user row then consumed and vanished. Nothing
> in the run below is retracted: the dupe this item existed to kill really
> is dead, and the four pins (248-A..D) are green and byte-unmodified
> under #281's fix. What is corrected is the implication that the tier was
> finished — "exactly as designed" describes what was built, and the
> design was under-specified. #281 fixes the minting side; the tier's
> SCOPE (a whole-transcript content map solving a one-row, in-flight
> problem) is recorded there as unresolved.

> **✅ CLOSED 2026-08-04 night.** Owen's device run: *"picked up a session
> that started on the mac on talaria, and asked a follow up question that
> will need research and tools - Question not duplicated. Response below
> question. PASS."* Note the shape is STRONGER than the filing's: a
> cross-device session pickup means the transcript is FULL of server rows
> with no `clientMessageID` — exactly the population the content-claim tier
> exists for — and zero dupes survived. With this, the 235-E/237-E recovery
> saga is fully closed: answer surfaces solo (#246, met on 1987) AND the
> sent message renders exactly once (this bar).

> **✅ BUILT 2026-08-04 late afternoon (`claude/t27-247-248-fixes`, TDD
> watched-RED).** `unconfirmedLocalMessages` extracted as the testable
> static with the third confirmation tier exactly as designed —
> content-claim for user rows, dequeue counting. 248-A (Owen's exact shape
> → empty), 248-B (repeat safety → one survives), 248-C/D (pins) all GREEN.
> Device half: tonight's backgrounding maneuver — answer solo AND the sent
> message exactly once.

**FILED 2026-08-04 (~2:45 PM) from Owen's build-1987 pass of the #246 device
bar:** *"Duped the original message when I first went back in, but, it had
the response. I left the conversation after a minute, and returned, and the
message deduped."* The core recovery WORKED (the answer surfaced without
manual re-entry — 235-E met); this is the residue.

**Mechanism — first suspect FALSIFIED by source read, corrected same hour.**
The filing named #235-F3's tail placement. **F3 is exonerated:**
`placingRecoveredReply` (`ChatStore.swift:311-321`) only MOVES the existing
reply row and explicitly no-ops when the reply is already last — it inserts
nothing, and in Owen's shape (nothing sent after backgrounding, reply
already the tail) it provably did nothing. **Owen's discriminator answers
narrowed the real neighborhood:** the duped bubble was his SENT message,
identical copies, one in its ORIGINAL position and one BELOW the response —
i.e., a second user row entered the list after the reply. That points at
the MERGE layer: during the ~60s stall window after his return, one of the
mid-stream merge paths (the #120-family relay-poll/refresh merge, or
`mergeConversationMetadata`'s adoption semantics) pulled the SERVER's copy
of the user message (server id) in beside the LOCAL optimistic row (client
id), and **#237's dedupe sweep did not collapse the pair** — its
stable-id mapping presumably doesn't bind for user rows on the stall path
(no `.finished` ever delivered the id mapping this turn). The heal on
re-open (clean server refetch) confirms app-side presentation state.

**Needs a real diagnosis pass, not a drive-by:** read
`mergeConversationMetadata` + the poll-merge path + the 237-D sweep's
mapping source against the stall timeline, build a fixture that models the
local-row + server-row coexistence, watch it RED. The fix likely belongs in
the dedupe sweep (match user rows by content+sender+timestamp-window when
no id mapping exists) or in gating the mid-stream merge while a stall
recovery is pending.

**Severity:** low-moderate — transient, self-healing, cosmetic; but it's a
dupe in the message list, the exact family #237 exists to keep at zero.

**Discriminators ANSWERED (Owen, 2026-08-04 ~2:50 PM):** yes his sent
message, one copy, identical; *"One at the top where I started, and one
below the response."* Recorded verbatim — these answers are what falsified
the F3 suspect above.

**Owed:** the diagnosis-then-fix lane (unrouted — Owen routes): merge-path
read → fixture modeling the coexistence → watched RED → fix → the same
backgrounding maneuver clean on device.

> **ROUTED 2026-08-04 (~3:15 PM): Owen — "Route both, I'll test tonight"
> (with #247's app half).** Diagnosis COMPLETE from source before the bars:
> - **Root cause, exact:** `mergeConversationMetadata`'s unconfirmed-locals
>   pass (`ChatStore.swift:2047-2054`) confirms a local row only by id or
>   `clientMessageID` — and the gateway transcript carries NO
>   `clientMessageID`, so the just-sent local user row (id = client id)
>   fails both checks and is APPENDED below the reply. Owen's layout
>   reproduced by construction: server user row in place, local copy below
>   the response.
> - **Why the #237 sweep passed the pair:** `dedupingAdoptedEchoes` keys on
>   `sender|content|timestamp` — the two copies carry different timestamps.
> - **Fix:** the unconfirmed-locals selection becomes a testable static with
>   a third confirmation tier — CONTENT CLAIM, `.user` rows only: each
>   refreshed user row lacking `clientMessageID` confirms at most ONE
>   content-identical local user row (dequeue counting), so legitimate
>   repeats keep their counts and in-flight sends still survive the merge.
>   Hermes-row handling deliberately untouched.
>
> ## 📋 BARS — PRE-REGISTERED 2026-08-04, BEFORE THE CODE
> - **248-A (unit, Owen's exact shape):** local = the optimistic user row;
>   refreshed = server user row (same text, no clientMessageID) + reply ⇒
>   unconfirmed is EMPTY (today it re-appends the user row — RED).
> - **248-B (unit, repeat safety):** local = two identical "yes" rows;
>   refreshed carries ONE server copy ⇒ exactly one local row stays
>   unconfirmed (the in-flight second send survives; today both do — RED).
> - **248-C (unit, pin):** a refreshed row echoing `clientMessageID` confirms
>   its local row regardless of content (existing behavior, pinned).
> - **248-D (unit, pin):** with an EMPTY refresh, a just-sent local row
>   survives the merge (the vanish-protection this pass exists for).
> - **Device (Owen, tonight):** the same backgrounding maneuver — answer
>   surfaces solo AND the sent message renders exactly once.

## 247. 🐛 Failover is theater when the fallback host is dark: switching profiles to the Mac Mini "does absolutely nothing" — and nothing TOLD Owen the fallback was dead — **✅ CLOSED 2026-08-04 night: B1 + B2 device bars MET on the corded `b94fc27` build; ops half DECIDED — no launchd, the Mac gateway stays a plain process (Owen: "we deal with the gateway staying alive. The two persistance things were flukes")**

> **Ops decision, 2026-08-04 night: NO persistence machinery.** Owen
> declined launchd for the Mac gateway — consistent with the standing
> anti-hardening rule, and his fluke read is CORRECT: both 2026-08-04
> deaths were SIGTERMs at Claude-session boundaries reaping an orphaned
> child process, not gateway crashes. The current launch (PID 51417,
> 21:10) is double-fork-detached (`( nohup … & )`), which orphans it to
> launchd-as-parent and survives session teardown — future sessions
> should launch it the same way. If it's ever found down, that's a
> 20-second relaunch, and the #247 banners now TELL the phone when a
> host is dark instead of failing silently.

> **✅ DEVICE BARS MET 2026-08-04 night.** **B1 (voice, Tailscale off):**
> *"Like, 2 seconds, not even. no hang. Just instant up"* — the fallback
> verdict fired immediately, the 12s belt never even needed to run. **B2
> (switch banners):** offline switch → the banner appeared and stayed;
> healthy switch → "server online" banner, then self-dismissed. One
> observation to keep visible: Owen noted the offline banner *"didn't clear
> after 15s"* — that is BY DESIGN (only the online verdict auto-clears at
> ~5s; a dead-host warning persists until acted on), but if the persistence
> reads as a bug to the user it may want a manual dismiss — Owen's call,
> cosmetic lane if wanted. Remaining half unchanged: the MAC GATEWAY is
> still a plain user process (relaunched twice on 2026-08-04 after
> SIGTERMs at session boundaries) — launchd persistence is Owen's pending
> decision.

> **✅ APP HALF BUILT 2026-08-04 late afternoon (`claude/t27-247-248-fixes`,
> TDD watched-RED).** B1: `realtimeStartTimeout` (12s, harness-shortenable)
> belts the realtime start — the belt Task cancels the wedged bootstrap at
> the deadline and the EXISTING native fallback runs;
> `shouldFallBackToNative(timedOut:)` pinned (247-A: timed-out overrides
> `.connecting`; late-but-connected is not bounced; the microphone
> exemption outranks). B2: `handleActiveProfileChanged` probes the new and
> previous gateways concurrently (5s each, unauthenticated on the previous —
> 401/403 still proves reachability) and sets `profileSwitchNotice`,
> rendered in ChatScreen's banner cascade; online confirmations auto-clear
> in 5s, failures persist to the next switch. 247-B string rows GREEN
> including the all-hosts-dead sentence. 247-C by construction as
> pre-registered. **Still open on this item:** tonight's device bars, and
> the ops decision (Mac gateway persistence — launchd or plain process).

**FILED 2026-08-04 (~2 PM) from Owen at work, mid-outage:** *"the connection
to ojamd failed. And i discovered if ojamd goes down, the way its set up,
switching to the mac mini does absolutely nothing."*

**Vantage-point evidence captured DURING the report (Mac Mini, same tailnet):**
OJAMD `:8642` AND `:8000` both listening; authenticated `/health` → **200**.
**The host was healthy — the PHONE's path was down** (its Tailscale at the
work network, or iCloud Private Relay re-grabbing the route — the standing
gotcha). Meanwhile the Mac Mini's own gateway had **nothing listening on
`:8642`**: it has been deliberately stopped since 2026-08-02 (Owen's choice,
recorded in the handoffs). So the profile switch re-pointed the app at a
DARK host — with the phone's tailnet path likely dead, BOTH targets were
unreachable from the phone, and "nothing" is what honest failure looked
like, minus the honesty.

**Two halves, different owners:**
1. **Ops half (acted on immediately):** the Mac gateway was started back up
   during the report so the fallback profile has a live target again. The
   deeper truth: a fallback host that is off is not a fallback, and nothing
   anywhere says which hosts are currently live. Whether the Mac gateway
   should RUN persistently (launchd, reboot-proof, like OJAMD's services) is
   **Owen's call** — it was stopped by his choice.
2. **App half (the filed defect):** switching to a profile whose gateway is
   unreachable produced **no visible verdict.** The app has the pieces —
   the #146 Test Connection probe (5s verdict + latency), honest offline
   console errors (#191's pass) — but a PROFILE SWITCH runs none of them
   visibly. Candidate shape (unrouted, needs Owen's read of what the UI
   actually showed): the switch runs the existing connection probe against
   the new profile's gateway and surfaces the verdict inline (the #30-style
   one-line banner), so a switch to a dark host SAYS "Mac Mini: unreachable"
   within seconds instead of nothing.

**Open question for Owen (needed before the app half is specced):** what did
the UI show after the switch — header unchanged? Spinner? Old OJAMD session
still on screen? "Does absolutely nothing" is the symptom; which nothing
matters.

> **UI SEQUENCE ANSWERED (Owen, ~3 PM — the app-half question):** *"it
> locked up on establishing link. I force quit, and reloaded. Sent a message
> and it timed out. Tried to go into models and it timed out. Switched to
> Mac Mini. Same thing on both tries."* And the root cause, his own
> diagnosis confirmed: *"The issue wasn't talaria, it was tailnet. I
> couldn't rdp into anything **from my phone** … I restarted tailnet,
> functionality returned"* — the PHONE's own Tailscale was wedged.
> **So "does absolutely nothing" meant "switching didn't help," not "the UI
> was inert" — the app tried and timed out everywhere.** That reshapes the
> app half into two specific defects:
> 1. **The establishing-link path can HANG hard enough to need a force
>    quit** — no timeout, no escape. A link attempt must always resolve to
>    a verdict or a cancellable state; force-quit-required is never
>    acceptable.
> 2. **Nothing DIAGNOSES the all-hosts-dead shape.** Every surface timed out
>    independently and identically, and the one true statement — "every
>    tailnet host is unreachable; the problem is this phone's network, check
>    Tailscale" — appeared nowhere. When BOTH profiles (or N≥2 endpoints)
>    time out in a window, the app has the evidence to say exactly that
>    instead of letting the user debug by RDP elimination like Owen had to.
> **Both are spec-ready now; unrouted — Owen routes.**
>
> **ROUTED 2026-08-04 (~3:15 PM): Owen — "Route both, I'll test tonight"
> (with #248).** Designs, from source:
> - **B1 (the hang):** the ESTABLISHING LINK surface is the VOICE overlay;
>   `realtime.startSession()` rides the shared 300s-timeout client, so a
>   black-holed relay pins it for five minutes while the REFUSED-path
>   fallback (which works — logged) never fires. Fix: the router belts the
>   realtime start with `realtimeStartTimeout` (12s, harness-shortenable);
>   on expiry the start Task is cancelled and the EXISTING native fallback
>   runs. `shouldFallBackToNative` gains `timedOut:` — true overrides even
>   `.connecting` (a timed-out start never gets to keep "still connecting"
>   as an excuse); false rows byte-preserve today's table.
> - **B2 (the missing diagnosis):** `handleActiveProfileChanged` probes the
>   NEW and PREVIOUS profiles' gateways concurrently (5s, the #151 probe
>   shape) and sets a `profileSwitchNotice` rendered in ChatScreen's
>   existing banner cascade: online → brief positive confirmation
>   (auto-clears); new-host-only unreachable → names the host; BOTH
>   unreachable → "every host is unreachable — the problem is likely this
>   phone's network; check Tailscale." Self-contained at switch time — no
>   failure-stamp plumbing, always current.
>
> ## 📋 BARS — PRE-REGISTERED 2026-08-04, BEFORE THE CODE
> - **247-A (unit):** `shouldFallBackToNative` — `timedOut: true` forces
>   fallback from `.connecting` and from every other state; the existing
>   `timedOut: false` rows (connected/connecting stay, microphone-blocked
>   stays native-exempt) are pinned unchanged.
> - **247-B (unit):** the switch-verdict classifier — (online, _) → positive
>   confirmation naming the profile; (unreachable, previousOnline) → names
>   the new host only; (unreachable, previousUnreachable) → the
>   check-this-phone's-network wording. Exact strings pinned.
> - **247-C (by construction, recorded honestly):** the belt-race wiring in
>   `startSession` and the concurrent probe wiring in
>   `handleActiveProfileChanged` — network-bound seams; the predicates they
>   consult are the pinned pure functions above.
> - **Device (Owen, tonight):** with Tailscale OFF on the phone (airplane-
>   style repro): voice attempt resolves to local voice within ~12s instead
>   of a force-quit; a profile switch shows the every-host banner within
>   ~5s. With the network healthy: switch shows the positive confirmation.

> **RESOLVED (ops half) 2026-08-04 ~2:15 PM — Owen: "There it goes. I
> restarted tailnet."** Full diagnosis, confirmed from the Mac vantage while
> it was live: OJAMD was NEVER down (gateway/relay/RDP all listening, authed
> `/health` 200 throughout). The tailnet map showed the break: Mac↔OJAMD
> rode a DIRECT LAN path (192.168.1.x), while the phone AND the work PC both
> rode DERP relay "mia" — and both failed. OJAMD's relay path was broken
> while its LAN path was fine; Owen's tailnet restart cured it. The Mac
> timeout during the flap was the same broken path, not the Mac gateway —
> exercised locally mid-outage: `/api/model/options` 200 (42 providers),
> session create instant, chat answered 5.1s. **Still open on this item:**
> the APP half (a profile switch to an unreachable host shows no verdict —
> Owen's UI detail still wanted), and Owen's call on whether the Mac gateway
> runs persistently (it is currently a plain process started 2026-08-04,
> dies with a reboot).

## 246. ✅ A backgrounded remote turn shows the pending spinner forever when the stream ZOMBIFIES — recovery only arms on stream END, and a stream that never ends never arms it — **CLOSED 2026-08-04: device bar MET on 1987 — the answer surfaced WITHOUT manual re-entry; residue (transient user-message dupe) filed as #248**

> **✅ CLOSED 2026-08-04 (~2:45 PM).** On 1987, Owen's exact morning
> maneuver: backgrounded mid-run, returned — *"it had the response."* No
> leave/re-enter needed; the stall guard + reconcile did the recovery. That
> is **235-E MET** (recorded in #235). **235-F (the longer-absence variant)
> was not separately run** — same mechanism, so it inherits reasonable
> confidence but stays honest as not-independently-exercised. The one
> residue — the user's sent message briefly duped during adoption, healing
> on re-open — is **#248**, its own mechanism (F3 placement), its own item.

> **✅ BUILT 2026-08-04 afternoon (`claude/t27-245-246-fixes`, TDD
> watched-RED).** `stallGuardedLines` (pump + watchdog over the post-2xx
> byte stream) throws `StreamStallError` after `streamStallThreshold` (60s
> production, harness-shortenable) of silence; the existing catch
> classifies it `.interrupted` and #235's machinery owns recovery — zero
> ChatStore change, exactly as designed. 246-A/B GREEN (wrapper unit,
> sub-second thresholds); **246-C GREEN end-to-end** (zombie SSE stub:
> `run.started` + one more event then silence → `.interrupted` with the
> runId in 0.4s, hang-belt never needed); #240's two regression tests
> untouched-green. **Fixture lesson recorded:** `bytes.lines` swallows
> blank lines, so a LONE final event never dispatches until the next
> `event:` line — a zombie right after `run.started` with nothing following
> arms recovery with a nil runId (positional reconcile, per #240's note);
> the fixture streams a following event because real zombies do. Device
> half: Owen re-runs the exact 235-E maneuver on the next OTA — the answer
> must surface WITHOUT leaving the conversation.

**FILED 2026-08-04 (~1 PM) from Owen's build-1978 test — the first run of the
235-E device bar, and it FAILED as shipped.** His exact maneuver: held a
conversation, asked for something longer, backgrounded mid-run, returned ~30s
later → **pending spinner, no response.** Left the conversation via the
sidebar, re-entered → **the answer was there.** No duplicates (that half is
237-E's bar and it PASSED — recorded in #237).

**Mechanism hypothesis (from source, not yet log-confirmed):** #235's recovery
arms when a stream ENDS abnormally (`.interrupted` / empty clean-close). A
stream that goes zombie in the background — socket nominally open, no bytes
ever arriving, no terminal event — never ends, so `pendingRun` never arms.
The foreground reconcile then no-ops on its very first guard
(`performReconcilePendingRuns`: `guard let pending = pendingRun else { return }`,
`ChatStore.swift:1740`) and the polling loop behind it never starts. **The
leave/re-enter "fix" wasn't the recovery path at all** — it was the ordinary
session-open history fetch, which is why it worked.

**What this is NOT:** not a reconcile-loop bug (the loop is fine once armed —
235-A/B/C pinned it); not #237's dedupe (passed on this very maneuver); not
the #240 parking path (the turn was streaming long before backgrounding).

**Fix territory (unrouted — Owen routes):** a stall detector on the live
stream — foregrounded with an in-flight streaming task whose last received
event is older than N seconds ⇒ treat as interrupted, arm recovery, reconcile.
The foreground-return hook is the natural site: it already runs; it just has
nothing armed to act on. **Discriminator to capture on the next natural
occurrence (verbose ON):** whether ANY terminal stream event logged during
the background window — if one did, the bug is in arming, not detection, and
the fix aims differently.

**Owed:** the fix lane, then a re-run of the same maneuver (235-E stays the
bar; it is not met until the answer surfaces WITHOUT manual re-entry).

> **ROUTED 2026-08-04 (~1:30 PM): Owen — "Build both, I'll test on the next
> OTA."** Fix design (refined from the filing's foreground-hook sketch to a
> STRUCTURALLY simpler site): the stall detector lives INSIDE
> `SessionsHermesClient.streamTurn` — the byte loop iterates a stall-guarded
> wrapper of `bytes.lines` that THROWS `StreamStallError` when no line
> arrives within the threshold. The existing catch already converts any
> post-2xx throw into `.interrupted` (#240's guard), which arms `pendingRun`
> and the reconcile loop — ALL of #235/#237's pinned machinery reused, zero
> ChatStore change. The suspension case falls out for free: while suspended
> nothing runs; on resume the watchdog wakes, sees the stale clock, throws —
> so Owen's return-from-background recovers within seconds without any
> foreground-hook special case. **Threshold 60s** (instance-injectable for
> tests): a false positive merely degrades transport from SSE to the
> budgeted reconcile poll — the turn still resolves — so the cost of firing
> on a legitimately quiet slow tool is a vanished streaming bubble, not a
> lost answer. The guard wraps only the post-2xx byte stream by
> construction, so pre-response failures keep their existing
> unreachable/failed semantics untouched.
>
> ## 📋 BARS — PRE-REGISTERED 2026-08-04, BEFORE THE CODE
> - **246-A (unit):** the wrapper — a sequence that yields once then goes
>   silent past the threshold THROWS `StreamStallError` (test threshold
>   sub-second); the yielded line was delivered first.
> - **246-B (unit):** lines flowing faster than the threshold pass through
>   untouched and the sequence completes normally — no throw on a healthy
>   stream, however long.
> - **246-C (integration, URLProtocol SSE stub):** a stream that delivers
>   `run.started` then goes silent yields `.interrupted` (with the runId) —
>   not `.failed`, not a hang — within the shortened test threshold.
> - **Device (Owen, next OTA):** the exact 235-E maneuver — background
>   mid-run, return — and the answer surfaces WITHOUT leaving the
>   conversation. 235-E/F close through this bar.

## 245. ✅ The chat header reverts to the HOST default model after relaunch while the per-turn lock quietly keeps working — a #191-family surface lie, and the catalog refresh is the stomp — **CLOSED 2026-08-04: device bar MET on 1987 (Owen: "Pass. Remained on DeepSeek")**

> **✅ CLOSED 2026-08-04 (~2:45 PM).** Filed, diagnosed (probe + code),
> built, gated, and device-verified inside one afternoon: on 1987 the header
> held the pick through force-quit + relaunch with nothing sent — no
> last-second correction needed. Every bar met (245-A/B suite, 245-C by
> construction, device pass above).

> **✅ BUILT 2026-08-04 afternoon (`claude/t27-245-246-fixes`, TDD
> watched-RED).** `ModelSelection.displayName` (the one tail-split) +
> `ModelSelection.headerName(pick:hostDefault:)` (pick-wins); the catalog
> refresh call site threads the preference; `applyModelSelection` and the
> boot seed now share the same derivation. 245-A/B GREEN
> (`GatewayModelCatalogTests` 6 → 8); 245-C by construction as
> pre-registered. Picker checkmark confirmed profile-sourced pre-build —
> untouched. Device half: Owen's relaunch re-test on the next OTA.
>
> **📸 MECHANISM CONFIRMED ON DEVICE 2026-08-04 ~1:46 PM (Owen, build 1978
> — pre-fix — two screenshots, same conversation):** header KIMI-K3 while
> the turn underneath answers "deepseek-v4-flash, via the deepseek
> provider"; the pill flips to DEEPSEEK-V4-FLASH only when the turn's
> `runtime` correction lands, then the next catalog refresh stomps it back.
> Owen: *"It was lying to me right up until the last second and it
> changed."* The stomp-then-correct cycle, observed exactly as filed — the
> per-turn runtime handler was the only truth-teller on 1978.

**FILED 2026-08-04 (~1 PM) from Owen's build-1978 test #3 ("Fail. …if I force
quit and reload, it changes back to the server default (kimi at the moment)").**

**PROBED THE SAME HOUR — the lock is INTACT; the display is lying.** Read-only
OJAMD session probe during his test window: the newest api_server session
(fresh "Hi" opener, 12:48 PM — post-relaunch) carries **session model
`deepseek-v4-flash`**, and asked "What model are you on?" the model answered
*"DeepSeek v4 Flash, via the deepseek provider on the API server."* **No
api_server session after the pick ran kimi — none.** So the persisted pick
survived the relaunch and rode the wire exactly as Lane 5 built it
(boot re-arm at `AppContainer.swift:775` works; persistence chain verified
end to end: fields + CodingKeys + tolerant decode + `didSet` save +
`normalized()` harmless).

**The stomp, located:** `performCommandCatalogRefresh` ends in
`chatStore.replaceCommandCatalog(catalog, activeModel: response.activeModel?.name, …)`
(`AppContainer.swift:1846-1850`) — the **host's own default** (kimi),
written over the header unconditionally on launch and every foreground
catalog refresh. The Lane 5 seed (`seedActiveModelFromGateway`) correctly
lets a pick win, but the catalog refresh landing after it does not. The
header then claims a model the turns are not using — precisely the #191
family (a surface asserting state it does not have), in the opposite
direction.

**Fix shape (small):** the catalog-refresh call site prefers
`activeModelSelection`'s display name when a pick exists (host default only
when no pick), mirroring the seed's rule; a unit pins "catalog refresh does
not overwrite a persisted pick's header." **Open sub-question for the fix
lane:** whether the Models picker's checkmark ALSO misreports after relaunch
(readSelection reads the profile, so it should be correct — verify while in
there rather than assume).

**Owed:** the fix lane (unrouted — Owen routes), then the relaunch test
re-run: pick DS Flash → force quit → relaunch → header still names the pick
before any message is sent.

> **ROUTED 2026-08-04 (~1:30 PM): Owen — "Build both, I'll test on the next
> OTA."** Fix as filed: the catalog-refresh call site prefers the persisted
> pick's display name over `response.activeModel?.name` (mirroring the seed's
> pick-wins rule); the tail-split display derivation moves to ONE place
> (`ModelSelection.displayName`). The picker checkmark was verified
> profile-sourced before building (`ModelsSettingsModel.isActive` reads
> `readSelection()` → `activeModelSelection` live) — no picker change needed.
> CTX denominator deliberately stays host-reported (#191's standing choice) —
> this lane moves the LABEL only.
>
> ## 📋 BARS — PRE-REGISTERED 2026-08-04, BEFORE THE CODE
> - **245-A (unit):** `ModelSelection.displayName` — `"deepseek/deepseek-v4-flash"`
>   → `"deepseek-v4-flash"`; an id with no slash is unchanged.
> - **245-B (unit):** the header preference is pick-wins — pick present ⇒ pick's
>   display name regardless of host default; nil pick ⇒ host default; both nil
>   ⇒ nil.
> - **245-C (by construction, recorded honestly):** the
>   `performCommandCatalogRefresh` call site threads the preference — the
>   refresh path is relay-network-bound with no scriptable seam; the pure
>   preference is pinned and the call site is a one-line read.
> - **Device (Owen, next OTA):** pick a non-default model → force quit →
>   relaunch → the chat header names the PICK before any message is sent, and
>   keeps naming it after the catalog refresh lands.

## 244. 🎨 APPEARANCE TAB HOLISTIC REWORK — "It doesn't flow right" — **✅ CLOSED 2026-08-04 (Owen's device pass on 1955: "looks good!"). ROUTED same day: Owen supplied Claude Design's channel-browser mockup and delegated the build ("If this is something doable and you like the design, implement that as well"). Verdict: doable + good — BUILT on `claude/t27-244-appearance-channels`; #243 subsumed; #239's sub-screen superseded (its live-re-skin guarantee carries forward by construction). Spec: `planning/superpowers/specs/2026-08-04-244-appearance-channel-browser-design.md`.**

> ## 📋 BARS — PRE-REGISTERED 2026-08-04, BEFORE the lane's tests ran. Written first.
> - **244-A (unit):** `ThemeChannels.build` — channel 00 is AUTO resolving
>   today's season; order = catalog section order (Flagship → Neon Arcade →
>   Special Edition → Midnight Marquee → Seasonal); count = available
>   definitions + 1; Terminal's channel reports the locked accent slot.
> - **244-B (unit):** the resolved-Color→hex helper renders real values (the
>   palettes store no raw hex — computed, never hardcoded copy).
> - **244-C (UI, replaces the #239 test IN PLACE):** settings → Appearance →
>   browser present (counter) → › to Solar Forge → name label renders →
>   reopening lands on Solar Forge's channel (apply-on-land persisted).
> - **Counted delta (pinned BEFORE the verification run):** DesignThemeTests
>   25 − 2 (themesRowValue pair dies with the row) + 4 = 27 ⇒ swift-testing
>   **1557 + 2 = 1559 expected on this branch** (bases off main; Lane 5's
>   1570 rides unmerged PR #255); XCUITest **10** (one replaced in place).
> - Mockup's three open decisions resolved in the spec: accent dots under
>   the spectrum (hidden for Terminal); Seasonal AUTO = channel 00 (counter
>   NN/30, computed); inert `locked` badge machinery carried deliberately.

> **✅ OWEN'S DEVICE VISUAL PASS: PASSED — 2026-08-04 morning, build 1955
> ("looks good!"). The channel browser ships as designed; #244 CLOSED (the
> umbrella's flow complaint answered by the rebuild), #243 stays subsumed.**
>
> **✅ BUILT + BARS MET — 2026-08-04 early AM.** 244-A/B green (DesignThemeTests
> 27/27 — honest note: the four new tests were written before the
> implementation but their RED was not separately witnessed; new-type
> compile-RED class, implementation landed in the same edit window). 244-C
> MET live: the replaced XCUITest drives the real browser — opens on Deep
> Field, › to Solar Forge, leaves, re-enters, and the browser reopens on
> Solar Forge's channel (apply-on-land persisted). **GATE: PASS — 1559 exact
> (pinned), XCUITest 10, 2 expected skips, Release clean.** Dropped detail
> recorded in the spec: TabView has no native page-peek, so the prev/next
> edge slivers are omitted (‹ › + counter carry adjacency). Owen's visual
> pass owed on device — the design is his call to keep, tune, or bounce.

**Owen, minutes after #239 closed, verbatim:** *"The whole appearance tab feels
like it needs a rework in general. It doesn't flow right."* Read: #239's
sub-section split fixed the burying problem but the screen's overall FLOW —
what order things appear in, how preview / themes row / glow / grid / app icon
/ feel toggles relate as you scroll — still reads wrong to the owner. This is
the umbrella item: when routed it starts at brainstorming with Owen (his
design instinct filed #239 and #243; the questions are his to answer —
what feels out of order, what belongs together, what the screen is FOR
post-pivot). **Fold-ins when routed:** #243 (sliding card gallery toggle)
should ride this rework rather than land piecemeal; #239's navRow/sub-screen
survives as a component either way. Current anatomy for the brainstorm:
`AppearanceSettingsScreen` = header → previewPanel → themesNavRow →
glowSection → gridSection → appIconRow → togglePanel (Reduce Motion, Haptic
Feedback); `ThemesSettingsScreen` = cards + seasonal toggle + accents.

## 243. 🎨 Theme selection as a SLIDING CARD GALLERY (toggle option) — **✅ SUBSUMED 2026-08-04 by #244's channel browser (PR #258 merged): theme selection IS a full-bleed sliding gallery now — not as a toggle beside the grid, but as the whole surface. If Owen's device pass bounces the browser, this idea un-subsumes and goes back on the shelf.**

**Owen, immediately after approving #239's merge, verbatim:** *"I do want to
redesign Theme selection into a sliding card gallery (toggle option), just a
note for another time."* Read: an ALTERNATIVE presentation mode for the theme
picker inside ThemesSettingsScreen (#239's new screen) — a horizontally
sliding, presumably full-bleed card gallery — offered as a toggle alongside
(not replacing) the current grid. Nothing designed; when routed it starts at
brainstorming. Natural home: ThemesSettingsScreen owns all picker UI now, so
this touches one screen. The existing per-card palette-resolution idiom
(`ThemePalette(theme:accent:)` direct) carries over to gallery cards.

## 240. 🐛 Backgrounding in the accepted-but-pre-`run.started` window parks the question as QUEUED — visible dupe + armed auto-resend — **✅ CLOSED 2026-08-03 ~10:02 PM — filed, spec'd, built, gated, merged (PR #253), corded-deployed, and ALL THREE BARS MET in one evening; 240-C observed on device (row adopted, no second answer)**

> **BUILD RECORD — 2026-08-03 late night, branch `claude/t27-240-preflight-parking`
> (plan `planning/superpowers/plans/2026-08-03-240-preflight-parking.md`).**
> **Fix 1** (`8e3e9f8`): `responseReceived` set after the 2xx guard in
> `SessionsHermesClient.streamTurn`; catch condition now
> `runStarted || responseReceived → .interrupted` (nil runId; reconcile
> resolves positionally). **Fix 2** (`b27b629`): one `reconcileFromServer()`
> fetch at drain start + `ChatStore.historyAdoptsQueuedTurn` predicate
> (trimmed-equal user message at/after `composedAt − 60s`); adopted turns drop
> with the "#240 adopted, not re-sent" log line; nil fetch drains as before.
> **240-A MET (watched RED→GREEN):** `StreamLossClassificationTests` — the
> accepted-but-pre-`run.started` drop yields `.interrupted("sess-1", runId
> nil)`, never `.unreachable`; the pre-response drop still parks. RED was
> witnessed TWICE, honestly: the first fixture RACED (URLSession buffers a
> custom URLProtocol's sub-512B body until completion, so a synchronous — and
> even a 100–300ms-delayed — `didFailWithError` superseded the never-flushed
> 2xx and exercised the PRE-response path while claiming to test the
> mid-stream one; isolated with standalone `swift` CLI transport probes,
> fixed with an over-threshold SSE comment pad + 0.1s-delayed error, then RED
> re-witnessed with the production fix stashed → 3 issues via the TRUE
> window → popped → GREEN 2/2). Fixture gotcha banked to persistent memory.
> **240-B MET (watched RED→GREEN):** `ContinuityFabricTests` +5 — adoption
> drop (park-time send stays the only send), absent-from-history re-send,
> nil-fetch drains-as-today, predicate window edges (−59s in / −61s out,
> trimming) and sender/text mismatches. Behavioral RED: 4 issues, all the
> missing guard's consequences; GREEN: 28/28 suite-wide.
> **Counted delta (pinned BEFORE the verification run): 1548 + 7 = 1555 —
> OBSERVED 1555 exactly** ("Test run with 1555 tests in 121 suites passed").
> **GATE: PASS** (Debug suite TEST SUCCEEDED, swift-testing 1555, XCUITest 9,
> the 2 expected Apple-Intelligence skips only, Release build clean — the
> #218 check). Merged same night (PR #253, merge commit `3cbfd2d`).
>
> **240-C MET — 2026-08-03 ~10:02 PM, corded deploy (Owen home, phone on
> the cable; Xcode bridge MCP absent this session, so plain
> `xcodebuild -destination platform=iOS` + `devicectl install/launch`).**
> The armed Steam-question row from 238-D trial 2 (parked 7:48 PM under
> 1908) **drained without Hermes answering it a second time.** Evidence is
> BEHAVIORAL, stated honestly: header count went **6 → 5 messages** — the
> queued row was REMOVED and NOTHING was added, which is adoption's
> signature (a re-send keeps count level-or-growing and starts a visible
> run; none appeared by 10:02+). The app wrote its prefs domains (outbox +
> cache home) 16s after the 10:01 cold relaunch — timing consistent with
> the adoption persisting. The literal "#240 adopted" log line was NOT
> captured: **idevicesyslog on iOS 27b4 relays only daemon lines about the
> app, never the app's own os_log output** (312 process-mention lines, 0
> app-emitted), and `log collect --device` needs root — memory updated.
> **Deploy footnote:** the first `devicectl launch` (no
> `--terminate-existing`) at 9:56 almost certainly just FOREGROUNDED the
> still-running 1908 process — the dupe visible at 9:57 was the old build;
> the 10:01 `--terminate-existing` relaunch was the fixed build's first
> true boot and the adoption fired on its cold-load drain (ChatStore:377).
> Always pass `--terminate-existing` after a corded install.

**Evidence (Owen, 1908, OJAMD, kimi-k3, screenshot):** the 238-D pass itself was clean
(no banner; answer on open), but the transcript showed his question TWICE — the server's
copy in correct position above the answer, and a second copy at the BOTTOM stamped
**7:48 PM with the queued clock glyph** (#90 compose-outbox shape). Not #237's family:
that was answer echoes with fresh identities; this is the QUESTION, parked by
classification.

**Mechanism (read tonight, `SessionsHermesClient.swift` ~445–457):** the stream-error
branch routes to `.unreachable` (→ durable `.queued` parking, auto-resend on drain)
only when `runStarted == false`. Backgrounding fast kills the SSE connection in the
window where the server has ACCEPTED the run but the client has not yet parsed
`run.started`; the teardown surfaces as an unreachable-family `URLError`
(`isUnreachableError`: notConnectedToInternet / cannotConnectToHost / dnsLookupFailed
/ …), so the app concludes "never reached the API" — while the run is in fact live
server-side (the answer's existence proves it). #235 covered every window AFTER
`run.started`; this is the same hole one event earlier.

**Consequence:** cosmetic dupe now, and the parked row is an ARMED AUTO-RESEND — the
next outbox drain re-sends the question and Hermes answers it again, unprompted.

**Candidate fixes (none built; Owen routes):**
1. **Track `responseReceived` separately from `runStarted`** — once HTTP
   response bytes/status have arrived, the turn provably reached the API: never
   park it as queued; arm recovery instead (`.interrupted` with nil runId — the
   reconcile already resolves positionally).
2. **Drain-time dedupe guard** — before re-sending a queued row, check server
   history for an identical user message at/after its sentAt; adopt instead of
   re-send. Belt-and-braces; also heals rows parked before the fix.

## 239. 🎨 Appearance screen: the theme picker buries everything below it — Themes should be a tappable sub-section — **✅ CLOSED 2026-08-03 night — all three bars met; merged (PR #254); 239-C passed Owen's corded visual check ("Ok yeah it works"). SUPERSEDED one day later by #244's channel browser (PR #258, 2026-08-04): ThemesSettingsScreen deleted; the live-re-skin guarantee carries forward by construction; `themesRowValue` + its two tests retired with the row.**

> **239-C MET — Owen, on device (corded branch build, cold-launched with
> `--terminate-existing`), same night:** Appearance opens compact, the
> Themes row navigates, theme picks re-skin the sub-screen live. Merge
> approved on that check; merged as PR #254 (`95a4d18`). The phone's
> installed build IS the merged content (branch tip == main tip) — no
> redeploy owed. Follow-on idea filed as #243 (sliding card gallery).

> **BARS — written first, before the run** (spec:
> `planning/superpowers/specs/2026-08-03-239-themes-subsection-design.md`):
> **239-A (suite, TDD watched RED):** pure navRow-value helper — manual mode
> → uppercased theme name; seasonal mode → `"<SEASON> · <THEME>"` for a
> fixed date. **239-B (XCUITest, new walk):** fresh context → Settings →
> Appearance & HUD → Themes → tap a different theme card → sub-screen
> re-skins (selection applies) → back → navRow value shows the NEW theme.
> This is Owen's "new page covered for theme changes" made mechanical.
> **239-C (device, Owen, observational):** Appearance opens compact; theme
> switching from the sub-screen re-skins live; Glow/Grid/App Icon/toggles
> discoverable. Counters pinned BEFORE verification: swift-testing 1555 →
> 1555 + new helper tests; XCUITest `Executed` 9 → 10. Owen's answered
> design fork: the seasonal auto-rotate toggle moves INTO the sub-screen.
>
> **BUILD RECORD — same night, branch `claude/t27-239-themes-subsection`
> (plan `planning/superpowers/plans/2026-08-03-239-themes-subsection.md`).**
> T1 (`a96500f`): `AppearanceSettingsScreen.themesRowValue(settings:on:)`
> — **239-A MET, watched RED** (compile-fail naming the member) → GREEN,
> `DesignThemeTests` 23 → 25. T2 (`467e374`): `ThemesSettingsScreen.swift`
> (new file; themeSection/themeGroup/automaticPanel+caption+binding/
> themeCard/lockBadge/accentSection/accentSwatch moved VERBATIM, own
> resolution layer + `HUDScreenBackground` → live re-skin preserved by
> construction); parent body: cards+accents → `themesNavRow`
> (iconTile+hudPanel idiom); orphaned `isAutomatic` removed;
> `effectiveAccent` stays (still feeds the App Icon row label). T3
> (`bbc4ab2`): **239-B MET** —
> `testThemeChangeFromThemesSubScreenAppliesAndSurfacesInRow` passed,
> `Executed 1` (16.8s): settings → Appearance → Themes → Solar Forge card
> gains `.isSelected` (one hedged re-tap per sim-verify memory) → Back →
> row label contains "SOLAR FORGE". First run was a false green —
> `-only-testing:TalariaUITests/AppTemplateUITests/...` matched NOTHING
> (`Executed 0` + TEST SUCCEEDED; the class inside AppTemplateUITests.swift
> is named `TalariaUITests`) — caught by the count, re-run correctly.
> **Suite: 1557 observed = 1555 + 2 pinned, exactly.** **GATE: PASS**
> (Debug TEST SUCCEEDED, swift-testing 1557, XCUITest 10 — BOTH counters
> moved as pinned; 2 expected Apple-Intelligence skips; Release clean).
> PR open; 239-C owed to Owen on device (corded, `--terminate-existing`).

**Owen, on 1908 (which relocated the haptics toggle into Appearance per #238):** *"we
may want to put Themes in a tappable section inside Appearance. It takes up so much,
that folks won't realize there are other options."* Post-pivot this is a launch-quality
concern: the default user's first Appearance visit shows a wall of theme cards and
never scrolls to Reduce Motion / Haptic Feedback / glow / grid. Candidate shape: a
`navRow` ("Themes", value = current theme name) pushing a ThemesSettingsScreen that
owns the picker + accent slots; the feel toggles stay on the top level. Small lane;
Owen routes.

## 238. ✂️ NOTIFICATION REMOVAL — the pivot's first cut (post-#235/#237, banners are scaffolding around a fixed defect) — **✅ CLOSED 2026-08-03 evening — ALL FIVE BARS MET same day as filing**

> **✅ 238-D MET — trial 2 (Owen, 1908, ~7:49 PM, kimi-k3, the Steam friends
> sweep: 17 tool calls completing server-side while backgrounded).** No banner
> arrived; the answer was on screen at open with no reload — via the normal
> merge, not the reconcile (no RECOVERED marker needed; the healthier shape).
> The question-dupe observed in the same trial is NOT this item's failure — it
> is the pre-`run.started` parking hole, filed as #240 with mechanism and fix
> candidates. **#238 CLOSED: filed, spec'd, built (−1,242 lines), gated, merged,
> disarmed, and device-verified inside one evening.**

> **📜 OJAMD-session findings (2026-08-03 night, archived
> `handoffs/ojamd-findings-2026-08-03.md`) — three post-closure notes:**
> (1) **The 16:28 CDT `push/register` + `push/watch` the relay logged does NOT
> contradict this item** — the OJAMD session couldn't see the build, but the Mac
> timeline can: 1908 was staged 18:58 and installed ~19:05, so 16:28 traffic was
> build 1886 (which still carried push code). Zero `/v1/push/*` since the 19:59
> gateway restart (small sample; keep an eye on the next OJAMD look).
> (2) **The relay's push leg was ALREADY dead at APNs** — 6× `403
> BadEnvironmentKeyInToken` (production-environment registration vs a key APNs
> rejects for it). The removal deleted an already-broken path; the "flaky relay
> push" of recent days was actually a hard fail.
> (3) The stale-row deactivation chore had ALREADY run 2026-08-02 (rollback JSON
> + DB backup exist relay-side); the phone's 1886-era re-registration undid it,
> as re-running would be until the fleet is on ≥1908. Recommendation adopted:
> don't re-run; rows starve naturally now.
>
> **⚠ 238-D trial 1 (Owen, 1908, ~19:1x): CONTAMINATED — no verdict either way.**
> Settings eyeball on 1908: GOOD (no Notifications row; haptics in Appearance;
> Privacy/Diagnostics clean). The 238-D attempt ran on deepseek-flash, which
> **stalled server-side and produced no answer** — the bar's precondition ("the
> answer exists server-side while you're away") never held, so the trial counts
> neither for nor against. Owen's read, consistent with the evidence: a Hermes/
> provider quirk, server-side — no app item. Switching to K3 in-session picked
> the question up and finished it (foreground, not the backgrounded path).
> **238-D still owed: one clean pass on a behaving model** — remote prompt,
> background until completion, open → no banner, answer at the tail. Note the
> OJAMD relay cannot push either despite its stale token rows: its watcher fires
> only on app-armed watches, and 1908 never arms one — starved as designed.

> **✅ 238-E MET — 2026-08-03 ~18:59, host-side, by CONTRAST not mere absence.**
> Sequence: hook disarmed 18:52 (device file deleted — the designed OFF switch,
> no gateway restart) → deliberate Mac-gateway probe session
> `api_1785801465_f8c45089` completed ~18:57 → **zero `talaria-push: ping` lines
> and zero APNs traffic** in agent.log since the 15:35 rotation. The contrast
> that makes it evidence: the morning smoke's identical scenario WITH the device
> file pinged within seconds (`ping … device=whoGoesThere status=200`, e.g.
> 12:14:49), and watcher crashes provably log loudly (12:10:10 traceback) — so
> silence here means alive-and-not-sending, not dead. Merged as PR #252
> (`0b4a4e0`); **OTA build 1908 staged from `main @ 6894c73`** — Owen installs
> from Safari, then 238-D: backgrounded remote run → NO banner → open the app →
> answer at the tail.

> **✅ GATE PASS 2026-08-03 ~19:0x, third run.** 238-A: `testFreshInstall-
> NeverPresentsNotificationPermissionDialog` PASSED (13.7s) on the ERASED sim —
> genuine fresh-install condition, walks first-launch + a dispatched send (the
> exact trigger the retired #189 priming rode). 238-B: absence sweep clean, first
> try. 238-C: 1548 green TWICE (T8 + gate — the −22 delta held on two independent
> runs; #235 recovery tests ride inside), XCUITest count MOVED 8 → 9. Release
> build clean (#218 arm — the config-plane check that matters for an entitlement
> cut). **Two gate hangs en route, both harness, both banked to memory:** the
> sim erase wiped TCC and the EventKit probes hang on undetermined authorization;
> first fix granted a FALLBACK-LITERAL bundle id (`org.aethyrion.talaria`) read
> from code instead of the real `org.aethyrion.talaria27` — the TCC.db query is
> what settled it. Two compile fixups en route (custom `encode(to:)`, DemoData
> capability row) — the compiler caught both, the designed failure mode.

**FILED AND ROUTED 2026-08-03 evening, Owen home.** Post-pivot ("self-contained local
brain that can upgrade to Hermes"), the default user is HOSTLESS — notifications can
never fire for them, yet the app still shows the iOS permission dialog on first run.
The upgrade tier can't push either: self-hosted Hermes can never hold our team `.p8`.
And the one user notifications served no longer needs them — Owen, routing the lane:
*"I was only going to check because it wasn't giving me the answer completed... If
that's there when I go to check, the notification is moot."* The banner was scaffolding
around the #235 defect; #235 fixed reconstruction, #237 fixed dedupe, and
open-the-app-and-it's-there is now the trusted surface.

**Scope settled with Owen same evening** (spec:
`planning/superpowers/specs/2026-08-03-notification-removal-design.md`, approach A — one
clean cut): everything goes — APNs registration, delegate, both producer services, the
push-token pipeline (#189), settings UI, `notificationsEnabled`, the `aps-environment`
entitlement and `remote-notification` background mode. **Confirmed collateral, Owen
accepted explicitly: reply-from-the-lock-screen (#47) and its failure banner.** STAYS:
BGAppRefresh (#14, now the sole background catch-up), Live Activities, inbox/briefings
(poll-fed, verified), connector-outage alert (in-app, verified), durable installation
identity (sensor pairing), and the relay — zero edits, its push endpoints starve.
Mac talaria-push hook disarmed at merge time (device-file OFF switch);
`claude/t27-223-talaria-push` stays as the archive; OJAMD 1.7 deploy cancelled.

## 📋 BARS — PRE-REGISTERED 2026-08-03 evening, BEFORE the run. Written first.
- **238-A (sim, fresh install):** erased sim, scripted pass through onboarding +
  first chat + settings → the iOS notification permission dialog NEVER appears.
- **238-B (mechanical):** zero `UserNotifications` / `UNUserNotificationCenter`
  references in app-target sources; `project.yml` clean of `aps-environment` and
  `remote-notification`.
- **238-C (suite):** #235 recovery tests green; the UserSettings decode-tolerance
  test green (old JSON carrying the retired key still loads); suite count moves
  DOWN by the counted delta recorded before the verification run.
- **238-D (device, OTA):** remote run, app backgrounded → NO banner; open the app →
  answer present at the tail. The waiting surface observed doing the banners' old job.
- **238-E (host):** a Mac-gateway session completion produces NO APNs attempt in
  agent.log — the Lane-1 OFF-check, inverted.
- Gate before PR, Release build included (#218 — entitlement edits are config-plane).

**Counted delta, recorded BEFORE the verification run:** −11 (`PushRegistrationRecordTests`
deleted) −8 (`RunCompletionWatchTests` deleted) −2 (AppStoresTests priming pair) −2
(BackendProfileRoutingTests dormant-idempotency pair) +1 (the decode-tolerance pin) =
**−22.** ✅ **DELTA VERIFIED EXACTLY: 1548 observed** (T8 run, green, 120 suites).
Anchor correction recorded with it: the entry's first two wordings mis-derived the
absolute number (1543/1544) from a STALE baseline — 1565 was pre-#251-merge; tonight's
merge took main to 1570 — and from counter-scope confusion (the 238-A UI test is
XCTest-based, so it never rides the swift-testing "Test run with N tests" line; XCUITest
results live in the `Executed N` counters). The pre-registered claim that survives
untouched is the **−22 delta**, and 1570 − 22 = 1548 landed on the number. The two
wrong absolute pins stay recorded above as what they are: mis-anchored, caught at
verification.

## 234. 🐛 "Day after tomorrow" received TOMORROW'S forecast — **✅ CLOSED 2026-08-04: guide boundary + pass-through + dated line built (PR #256), 234-A/B sim-met, 234-C device-met on build 1955 (honest horizon answer, Owen's screenshot)** — *(was: mechanism confirmed — argument-time nearest-fit, trial-7 severity family)*

**FILED 2026-08-03 from Owen's at-work spot check of the just-shipped #230** (Release
OTA of the fix branch, fresh chat): "What's the weather in Gulfport the day after
tomorrow" → tomorrow's forecast served as the answer. This is the user-facing shape
#230 was explicitly designed to never produce ("never a silent date-relabel — the
#199-suspect shape") — arriving one boundary higher, above the tool.

**The tool half is verified correct and is NOT the defect:** `requestedDay`
equality-matches only `""`/`"today"`/`"now"`/`"tomorrow"`; anything else — including
the literal "day after tomorrow" — is `.unsupported` → `unsupportedDayAnswer` names
the horizon honestly. Pinned by `WeatherTomorrowTests` ("friday", "next week"); the
literal phrase "day after tomorrow" should be added as a pin in any fix lane — same
mechanism, but it is THE observed input.

**Two candidate mechanisms were filed; (a) CONFIRMED by Owen's screenshot the same
morning (8:23 AM, fresh chat, chip reads 2 TOOL CALLS — a single `currentWeather`
call, so no refuse-and-re-call round ever happened):**
- **(a) Argument-time nearest-fit (2 calls):** the `day` @Guide advertises exactly
  two states ("'tomorrow' … or empty for today") — a model with no advertised way to
  say "day after tomorrow" snaps to `"tomorrow"`, and the honest path never fires.
  The tool cannot detect this; it receives a well-formed request.
- **(b) Refusal-then-substitution (3 calls):** the model passed the phrase through,
  got the honest unsupported answer, and re-called with `"tomorrow"` — #216's
  substitution mechanism in miniature, bounded by the caps, same wrong answer.

**Severity settled by the same screenshot:** the answer opens "**Tomorrow** in
Gulfport, it will rain…" (90°F / 79°F, 60% precip) — the day label is honest about
the data it carries, it just is not the day the user asked about. That is **trial
7's family (true data, misread question), NOT the fabricated-label full-#199 shape.**
Consequence of (a) for any fix lane: the tool receives a well-formed `"tomorrow"`
and CANNOT detect the collapse — a tool-side guard is structurally impossible here
(the same reframe #233 hit: the model qualifies before the tool sees).

**Candidate directions (none decided; bars pre-register HERE before any lane):**
@Guide text naming the boundary AND a pass-through rule ("if the user asks beyond
tomorrow, pass their words through unchanged — never substitute 'tomorrow'"); and/or
`tomorrowForecastLine` carrying its calendar date ("Tomorrow (Aug 4): …") so a
mislabeled relay is at least self-contradicting on its face. Either is device-only to
verify — the sim has no model.

**🏗 LANE ROUTED 2026-08-04 early AM (goal run "finish the rest of the open
items that are workable"; #234 was queue item 5 in Owen's post-compaction
list). Direction: BOTH candidates — they are complementary and both were the
only ones filed: (a) the `day` @Guide names the boundary and the pass-through
rule; (b) `tomorrowForecastLine` carries its calendar date. Branch
`claude/t27-234-day-nearest-fit`.**

## 📋 BARS — PRE-REGISTERED 2026-08-04, BEFORE the lane's tests ran. Written first.
- **234-A (sim, mechanical):** the `day` guide text names the beyond-tomorrow
  boundary AND the pass-through rule verbatim (pinned by a text test so a
  guide edit is a deliberate act, the `theDescriptionAdvertisesTomorrow`
  pattern); the literal observed input "day after tomorrow" is pinned
  `.unsupported` (a PIN, expected green-on-arrival — the tool half was always
  correct; recorded honestly as a pin, not a RED→GREEN).
- **234-B (sim, mechanical):** `tomorrowForecastLine` carries the forecast's
  calendar date — "Tomorrow (Aug 5) at Gulfport: …" for a fixed date — so a
  mislabeled relay contradicts itself on its face. RED-able: the existing
  exact-string test pins the UNDATED line today.
- **234-C (device, owed to the next OTA — the sim has no model):** trial
  prompt verbatim, fresh chat: "What's the weather in Gulfport the day after
  tomorrow" → PASS = the honest horizon answer reaches the user (pass-through
  fired), OR the reply is visibly self-contradicting (asked-day ≠ the dated
  label). FAIL = the trial-7 shape recurs: tomorrow's numbers presented as
  the asked day with no contradiction visible.
- **Counted delta (pinned BEFORE the verification run):** WeatherTomorrowTests
  +2 (guide-text pin, day-after-tomorrow pin; the dated-line change edits the
  existing exact-string test in place) ⇒ swift-testing **1557 + 2 = 1559
  expected on this branch** (bases off main — Lane 5's 1570 rides the
  unmerged PR #255); XCUITest 10 unchanged.

**✅ 234-C MET ON DEVICE — 2026-08-04 7:52 AM (Owen's screenshot, build 1955,
ON-DEVICE brain, fresh chat, trial prompt verbatim "What's the weather in
Gulfport, MS the day after tomorrow"): 3 tool calls, then the IDEAL pass shape
— "I can't provide the forecast for the day after tomorrow in Gulfport, MS —
only today and tomorrow's data are available." The pass-through fired and the
honest unsupported answer reached the user. The trial-7 collapse did not
recur. ALL BARS MET — #234 CLOSED.**

**✅ 234-A/B MET (sim) — 2026-08-04 early AM.** RED witnessed on both new
members (`dayGuideText` missing; `date:` param missing), then GREEN 8/8 in
the suite. The guide now reads: *"…Weather beyond tomorrow is not available:
if the user asks about a later day (like 'day after tomorrow' or a weekday),
pass their exact words through unchanged — never substitute 'tomorrow'."*
`tomorrowForecastLine` emits "Tomorrow (Aug 5) at Gulfport: …" (fixed-locale
month-day off the forecast entry's own date; nil-date keeps the undated
form). The #209 rollback twin has no `day` field — untouched. **GATE: PASS —
swift-testing 1559 (pinned delta met exactly), XCUITest 10, 2 expected skips,
Release clean.** **234-C stays OWED to the next device pass** (the sim has no
model): trial prompt verbatim on a fresh chat; PASS = honest horizon answer
or a visibly self-contradicting dated label; FAIL = the trial-7 collapse
recurs uncontradicted.

## 233. 🐛 "Tomorrow at 4" became a 4:00 AM reminder — half-day defaulting on `createReminder`, and the confirm card did not save it — **✅ CLOSED 2026-08-03 evening — every bar met: 233-A/B/C suite + device, 233-E device, 233-D midday (preferred shape) AND evening (fallback shape), store row observed**

> **2026-08-04 night re-observation (Owen's tonight-list item 4): stays
> CLOSED, and the machinery was NOT at fault in what he saw.** "Remind me
> at 8 (to call Shelley)" asked ~9:15 PM staged a card for **9:00 PM**,
> twice — the model resolved the bare hour to 21:00-ish, which is OUTSIDE
> the wee-hour window (00:00–06:59), so the bounce and caution correctly
> stayed silent; this shape cannot exercise 233-D/E at all. The
> wrong-hour defect itself is **#249** (instrumented; raw-`due`
> discriminator pre-registered there).

**FILED 2026-08-02, Lane 1 trial 3 (run results doc).** "Remind me to call Shelley
tomorrow at 4," sent at 23:05, produced a REAL reminder due **Aug 3, 4:00 AM** —
verified in the store by trial 7's `readReminders`. Mechanically flawless (1 call,
~1 min including confirmation, B4's shape); semantically wrong: a human saying "at 4"
in the evening means 4 PM. The model even hedged ("let me know if you'd like to
adjust"), and the #29 confirm card was approved without the AM registering — a card
that makes AM/PM easy to miss is part of the finding.

**Candidate directions (none decided):** a bare-hour disambiguation default (afternoon
for 1–11 unless context says otherwise — what Siri does), or the create tool
REFUSING bare hours back to the model with "ask AM or PM," plus making the card's
time rendering unmissable. Bars pre-register HERE before any fix lane.

> **DIRECTION DECIDED 2026-08-03 (AM) with Owen — design doc
> `planning/superpowers/specs/2026-08-03-233-bare-hour-reminders-design.md`.**
> His preference order: ask AM/PM (ideal) → afternoon default (fallback).
> Key reframe from reading the code: **the tool never sees "bare hours"** —
> the model qualifies the time before the tool runs — so the buildable form
> is a **wee-hour bounce**: due in 00:00–06:59 + conversation latch clear →
> `performCreate` returns an ask-AM/PM instruction as ordinary tool output
> (never a throw, #197) before staging any card; the latch (NOT reset by
> `beginTurn`, cleared on fresh chat) admits the re-call so a confirmed
> "yes, 4 AM" cannot loop. Card gains a forge-amber "⚠ EARLY MORNING" row for
> staged wee-hour dues. Shared-engine placement means the DEBUG twins inherit
> it. No `@Guide` changes: the afternoon-default guide line is the RECORDED
> FALLBACK if device trials show the bounce grinding, not stacked on top.
> `createCalendarEvent` has the same exposure — follow-on, not built here.
>
> ## 📋 BARS — PRE-REGISTERED 2026-08-03, BEFORE THE FIX LANE. Written first.
> - **233-A (mechanical, sim):** wee-hour due (hour 0–6) with latch clear →
>   bounce string, NO card staged, latch set; hour ≥ 7 stages normally; latch
>   set → same wee-hour due proceeds to a card; a fresh conversation clears
>   the latch. Pinned by tests written first.
> - **233-B (mechanical, sim):** the bounce increments no governor refusal
>   count and no `refusalsThisTurn` (#228 instrument counters assert it).
> - **233-C (mechanical, sim):** an early-morning staged due carries the card
>   caution; a 16:00 due carries none and renders unchanged from today.
> - **233-D (device):** trial 3's prompt verbatim, evening send → the
>   assistant asks AM or PM; answering "PM" → card shows 4:00 PM, store row
>   at 16:00 (baseline: the real Aug 3 4:00 AM row). A silent 4 PM card
>   without the ask also passes — the accepted fallback shape.
> - **233-E (device):** explicit "remind me at 5 AM tomorrow" completes with
>   ≤ 1 bounce; its card shows the caution.

> **✅ BOUNCE BUILT 2026-08-03, later the same morning** (spec + plan under
> `planning/superpowers/`; tests first, RED watched per task — the two wiring
> tests were watched fail on ASSERTION, not just compile). Mechanical bars:
> **233-A** pinned by `weeHourDueBouncesOnceThenProceeds` /
> `daytimeDueNeverBounces` / `noDueDateNeverBounces` /
> `isEarlyMorningCoversMidnightThroughSixFiftyNine` /
> `earlyMorningAskClaimsExactlyOncePerConversation` /
> `beginTurnDoesNotClearTheEarlyMorningLatch` /
> `clearConversationResetsTheEarlyMorningLatch`; **233-B** asserted inside the
> bounce test against the #228 counters (executed 2, refusals 0); **233-C** by
> `earlyMorningCautionOnlyForWeeHours` /
> `stagedCardCarriesTheCautionThroughTheGate` /
> `weeHourRecallStagesCardWithCaution`. **Found while wiring: `openSession(_:)`
> is a SECOND conversation boundary** — it resets #30's per-conversation state,
> so the latch clears there too (`openingAStoredSessionResetsTheWeeHourAskLatch`);
> reopening the same conversation keeps the latch by design. **Device bars
> 233-D/E NOT claimed** — the next OTA's script: evening send of trial 3's
> prompt verbatim ("Remind me to call Shelley tomorrow at 4" → expect the AM/PM
> question; a silent 4 PM card also passes, the accepted fallback), and
> "remind me at 5 AM tomorrow" (≤ 1 bounce, amber EARLY MORNING row on the
> card, store row at 5:00 AM). **Build 1860 (`df9a300`) staged and installed
> on whoGoesThere 2026-08-03 AM; superseded same day by build 1870 (`main @
> 3a41757`, both PRs merged) — the device bars ride 1870.**

> **❌ 233-E FALSIFIED ON DEVICE — 2026-08-03 12:34 PM, build 1870, Owen's
> at-work test.** "Remind me at 5am tomorrow" (fresh chat) → ONE
> `createReminder` call, **no confirmation card, no store row** — that
> triple is the bounce's exact signature (every non-bounce path stages a
> card), so **the mechanism worked**: no wee-hour creation, no loop, one
> bounce. What failed is the MODEL's reaction: instead of relaying the
> AM/PM question, it FABRICATED completion — "The reminder has been set for
> **Aug 4, 2026 at 5:00 AM**. Would you like to confirm the time, or adjust
> it?" — and the smoking gun is that date string: it is the bounce text's
> own `displayDate` output echoed verbatim; the model mined the ask
> instruction for a success claim. **The design's degradation ladder did
> not include "claims completion without acting" — that branch is real and
> it is the WORST shape (user believes a reminder exists; none does).**
> Owen deleted trial 3's leftover 4 AM row in the same sitting.
> **Candidate re-fix (small, needs routing + a new OTA): harden the bounce
> string** — lead with the negative before anything mineable ("No reminder
> was created. …ask the user whether they meant AM or PM…"), keep the
> display time AFTER the ask instruction, and pin the new wording in the
> 233-A tests. 233-D verdict still pending (midday/evening sends).
>
> **233-D midday data point (Owen, ~12:0x, build 1874/1886 era): reported
> SUCCESSFUL, in the PREFERRED shape (Owen, confirmed ~4 PM): the model
> ASKED AM or PM, then staged the confirmation card** — the full
> ask→confirm→card chain on the founding prompt, at midday. **The pre-registered EVENING send runs after 5 PM** — Owen
> self-scheduled; the evening condition is the baseline-matching half.

> **✅ 233-E MET ON DEVICE — 2026-08-03 ~1 PM, build 1874 (the hardened
> string, Owen routed the re-fix same hour).** Full chain observed: the
> model CLARIFIED AM vs PM; the confirm card appeared **with the
> early-morning notice** (that banks 233-C's device half too); the reminder
> was **actually scheduled in the Reminders store** — Owen verified the row
> this time. Falsify → harden → pass, all in one sitting. The re-fix went
> beyond the entry's candidate wording: the hardened string carries NO
> formatted date at all (nothing mineable), pinned by prefix + no-date
> assertions in the bounce test. 233-D remains tonight's evening send.

> **✅ 233-D EVENING SEND PASSED — 2026-08-03 4:57 PM, build 1886, Owen home,
> fresh chat, trial 3's prompt verbatim ("remind me to call Shelley tomorrow
> at 4"), screenshots in hand.** Observed shape: **the accepted FALLBACK arm**
> — no AM/PM ask; the model resolved bare "4" to afternoon on its own, staged
> the confirm card at **Aug 4, 2026 at 4:00 PM** (2 tool calls, IN 5.9K ·
> OUT 101), **no caution row — correct**, 16:00 is not a wee hour (233-C's
> negative half, now also observed on device). Owen approved; completion text
> matched the card. Baseline contrast: the founding trial-3 send of this exact
> prompt in the evening produced a real **4:00 AM** row. **Shape ledger for the
> founding prompt: midday = preferred rung (asked AM/PM → card); evening =
> fallback rung (silent 4 PM card). Both inside the pre-registered pass band;
> the bounce never needed to fire because the model never picked a wee hour —
> it exists for exactly the runs where it does.** Store glance done two
> minutes later (4:59 PM, screenshot): Reminders → Scheduled → Tomorrow →
> **"Call Shelley — Stuff — 4:00 PM."** Observed, not derived. **#233 CLOSED.**

## 232. 🐛 THE REFUSAL GRIND: the #225 cap bounds executed calls, but NOTHING bounds refusals — 57 refusal→re-infer cycles at ~2.4s each WERE the "still working" minutes — **✅ CLOSED 2026-08-03 night — corded coda log: ZERO refusals on the control prompt (was 57), turn 5.9s (was minutes); 232-E's device notice unobservable-because-healed, recorded honestly**

> **✅ THE CODA'S LOG HALVES — 2026-08-03 ~10:44 PM, verbose RELEASE device
> build, `log collect` archive (verbatim lines in #228's closure block).**
> - **232-C log half MET, and the exact refusal count is ZERO:** the
>   Gulfport control prompt — the turn that once ground through 57
>   refusal→re-infer cycles — executed `#1 currentLocation` →
>   `#2 currentWeather` and finished. No refusal line exists in the archive
>   (the L0-B shape would have printed one); routed→finished **5.9s**,
>   against the <30s bar. The grind is not bounded — it is GONE (#230's
>   tomorrow-fix removed its cause; this cut remains the backstop).
> - **232-D re-confirmed on Release:** the right-now turn, same shape, 5.2s.
> - **232-E device half: UNOBSERVABLE-BECAUSE-HEALED, said plainly.** The
>   cut's `.notice` fires only when a turn actually grinds, and no known
>   prompt grinds anymore. The suite half (232-E green, line shape pinned)
>   stands. NOT claimed as device-witnessed. Reopen trigger: any future
>   long "still working" turn whose log lacks the cut's notice.

> **✅ MECHANISM BUILT overnight, same session** (branch `claude/t27-232-refusal-cut`,
> tests first): refusals 1–3 stay strings; the 4th attempted call throws
> `ToolPhaseCutError` → both send loops retry ONCE as a routed-toolless turn.
> `relay.started` is now `throws` (compiler-enforced sweep). Mechanical bars
> 232-A/B/E green in suite; **232-C/D are DEVICE bars, not claimed** — OTA or
> corded verify per the 2026-08-03 handoff.

> **📱 DEVICE RESULTS 2026-08-03, ~7:38 AM — Owen's at-work test, OTA install of
> the fix branch, fresh chats, screenshots in hand:**
> - **232-C, experiential half MET:** the Gulfport control prompt — the exact turn
>   that ground 57 refusals / ~2.5 min on build 1843 — replied **within the same
>   clock minute** (2 tool calls, receipt IN 5.8K · OUT 84). Note the mechanism:
>   with #230 aboard the same branch, the trigger is gone and this prompt now ends
>   at call 2 — it no longer *reaches* the cut. The ≤3-refusals log half still
>   needs the corded coda (trivially expected 0 on this prompt now; a grind-shaped
>   prompt is the one that would show the cut itself firing).
> - **232-D, experiential half MET:** "What's the weather right now" (fresh chat)
>   → `currentLocation` + `currentWeather`, answer within the same clock minute
>   (IN 5.8K · OUT 107), behavior unchanged from the healthy trials. The
>   0-refusals / no-cut-line log half is the coda's.
> - **The formal close remains the corded coda** (~10 min: verbose ON +
>   `idevicesyslog`) — exact refusal counts for 232-C, and the cut's `.notice`
>   line (232-E's device half) on a prompt that actually grinds.
> - **The same screenshot closes the run's follow-up list:** trial 1 was the
>   only Lane 1 row that failed a bar (L1-B's no-trial->90s clause, ~150s on
>   the grind), and this is that row on the fixed build, done in seconds. The
>   handoff's "re-run the failed Lane 1 rows" is complete — **the tier
>   question (#166c / Phase 7) is LIVE, and it is Owen's verdict, not a
>   lane's.**

**FILED 2026-08-02 from the first fully instrumented device turn (#228's instrument,
Release build 1843, verbose ON, the Gulfport control prompt).** The turn executed its
12 budgeted calls, then spent ~2.3 MINUTES in a loop the instrument watched live:
the model calls `searchConversations`, the governor refuses (as tool output, per
#225's correct never-throw design), the model burns a full ~2.4s inference round
reacting to the refusal — **by calling the tool again. 53 consecutive
`searchConversations` refusals, then a thrash to `currentLocation` (#56) and
`currentWeather` (#57), then an honest text decline.** Receipt IN 5.7K · OUT 66;
no overflow; no fabrication.

**Why this was invisible until tonight:** refusals deliberately emit no chip (#180 —
right call, unchanged), and the relay's only logging was DEBUG+battery-gated. The
user-visible symptom was exactly Owen's report: *"after 12 tools, its giving the
still working."*

**The mechanism, named:** a refusal handed back as tool output keeps the model in
tool-calling mode — the text says "answer now," but the model treats it as one more
result to react to. Each cycle also appends ~45 tokens of refusal text to the very
window #225 worries about (57 × ~45 ≈ 2,500 tokens of pure refusal).

**Candidate fix, with the SDK seam verified in the beta4 interface:** after K
refusals, END the tool phase structurally instead of rhetorically — demote the
turn's `GenerationOptions.ToolCallingMode` to `.disallowed` (per-request, exists,
see the FM surfaces memory) or drop the belt for the remainder of the turn. Terser
refusal strings are a secondary patch. **Bars to pre-register in THIS entry before
any fix lane runs.** Baseline for judgement: this trial — 12 executed / 57 refused /
~2.5min / honest decline.

**Cross-links:** the executed-call bound is #225 (correct, insufficient — again);
the window class is #229; the trigger fix is #230. Same-tool cap held (4 executed
max per tool); the grind is a REFUSAL loop, a distinct third mechanism.

> ## 📋 BARS — PRE-REGISTERED 2026-08-02 (night), BEFORE THE FIX LANE. Written first.
>
> **Design chosen: the cut-and-toolless-retry.** At the FOURTH refusal in one turn
> (threshold 3 — every healthy trial tonight had zero refusals; trial 1's refusals
> 4–57 were pure waste, and no observed case exists where refusal ≥4 led anywhere),
> `ToolEventRelay.started` THROWS `ToolPhaseCutError` instead of returning a string.
> The tool protocol is already `throws`; the error surfaces as
> `ToolCallError.underlyingError`; both send loops catch it exactly like #26/#197
> and retry ONCE as a **routed-toolless turn** (`turnRoutedToolless = true` → empty
> belt + the 486-token instruction set — the shape that went 10/10 tonight).
> Deliberate scope: the retry loses this turn's tool results (mid-turn transcripts
> are unknowable, #102) — for grind-shaped turns those results are noise by
> definition. **The transcript-preserving deeper fix (DynamicProfile
> `.toolCallingMode` demote, session-init-attached, re-evaluation semantics
> unverified) is recorded as its own future spike, not attempted blind.**
>
> - **232-A (mechanical, sim):** refusals 1–3 return strings unchanged; the 4th
>   attempted call in a turn throws; `beginTurn()` resets the count; a healthy turn
>   (0 refusals) can never reach the throw. Pinned by tests written first.
> - **232-B (mechanical, sim):** the cut error is detected both bare and wrapped in
>   `ToolCallError`, and triggers exactly ONE toolless retry per turn.
> - **232-C (device):** the Gulfport prompt produces reply text in **< 30s** with
>   **≤ 3 refusals** in the log (baseline: ~2.5min / 57).
> - **232-D (device):** healthy turns unchanged — a trial-2-shaped prompt still
>   answers in seconds with 0 refusals and no cut line.
> - **232-E:** the cut logs an always-on `.notice` (same convention as #26's
>   condense line), so a cut turn is visible without verbose.

## 231. 🐛 RELEASE-ONLY: the chat screen scrambles — transcript collapses, identity strip lands on the input bar. Debug is fine, so every check we run was blind to it (#218's family, for UI) — **✅ CLOSED 2026-08-03 night: 231-C's captured-log half met in the corded coda; all four bars now met**

> **✅ 231-C LOG HALF MET — the corded coda's `log collect` archive shows the
> #228 instrument lines on the RELEASE build after Owen flipped Verbose
> Logging in the Release Developer screen** (tool-call sequence + session
> budget lines at 22:44 and 22:47; full verbatim in #228's closure block).
> With 231-A (sim screenshots), 231-B (Owen's device confirm), 231-C both
> halves, and 231-D (Debug banner unchanged) — CLOSED.

**FILED 2026-08-02, found by Owen ~60 seconds into the first Release install anyone
has LOOKED at on device** (build 1839, staged for the local-brain run). Two
screenshots, same phone, same data: tonight's earlier build renders the strip under
the nav with a live transcript; build 1839 renders the strip ON the input bar with
the transcript area empty despite "2 MESSAGES".

**Reproduced in the sim within minutes: Release scrambled, Debug correct — identical
code, identical fresh state.** So: not the phone, not the data, not #228's diff
(which touches no UI). A compile-conditional layout divergence.

- **ROOT CAUSE CONFIRMED same night, one-variable experiment:** `ChatScreen.body`'s
  `.safeAreaInset(edge: .top, spacing: 0) { debugSessionShapeBanner }` — the #205
  banner. In Debug the builder yields a real zero-height conditional view; in
  Release the empty `@ViewBuilder` yields `EmptyView` **as a top safe-area inset's
  content**, and iOS 27 beta 4 mis-lays-out the containing stack for it. Compiling
  the MODIFIER out of Release (content already was) healed the sim Release build
  byte-for-byte to Debug's layout. **231-A MET** (screenshots, both configs, same
  sim, same state). #205's Debug behavior untouched.
- **The find that led here:** tonight's 21:16 "production build" failure log carries
  `armed — 13 tools registered`, a `#if DEBUG`-only line — **so tonight's build was
  DEBUG, and the dispatch's "production build" label was wrong.** Release UI had not
  been looked at since the 2026-07-27 OTA proof.
- **Sibling finding, same sitting:** the Developer menu row is `#if DEBUG`
  (`SystemSettingsScreen`), so **Release has no path to `verboseLogging` and #228's
  instrument gate is unreachable exactly where it matters** — L0-A was unmeetable as
  shipped. `DeveloperSettingsScreen` is already internally Release-clean (its
  DEBUG-only sections are individually gated), so exposing the row is safe;
  **re-hiding for App Store builds is a Phase 7 question, flagged there.**

> ## 📋 BARS — PRE-REGISTERED 2026-08-02 BEFORE THE FIX LANE
> - **231-A:** Release sim build renders the chat screen byte-identically in
>   structure to Debug: strip under nav, transcript expanded, input at bottom —
>   verified by screenshot both configs.
> - **231-B:** on the DEVICE Release build, Owen confirms the layout is back.
> - **231-C:** Settings → System shows the Developer row in Release; flipping
>   Verbose Logging there produces the #228 lines in a captured device log.
> - **231-D:** the DEBUG banner behavior (#205) is unchanged in Debug builds.

> **✅ 231-B MET; 231-C's UI HALF MET — 2026-08-03 (AM), Owen at work, Release
> OTA of the fix branch.** Both morning screenshots show the healed layout —
> strip under the nav, live transcript, input at the bottom — and Owen
> confirmed in so many words. The Developer row SHOWS in Release Settings →
> System (the #246 promotion's first device look). **Still owed:** 231-C's
> captured-log half (verbose toggle → #228 lines) rides the corded coda.

## 226. 🐛 The #38 run-completion push watch is a STRUCTURAL NO-OP for home-screen backgrounding — **⚰️ MOOT 2026-08-04 (goal-run sweep): the push-watch surface itself was deleted by #238 (app posts no `push/watch` calls; banners cannot exist without the notification plane). The one durable piece of this item — the reconcile-leg single-flight — was FIXED in this item's own lane (`0b8aad4`, `reconcileInFlight`) and stays. Nothing left to build.** — (was: nothing, or THREE identical banners)

**FILED 2026-08-02 from the device pass (running list §D4, which holds the attempt table
and the full source trace).** Four live attempts plus source; **all four explained
without residue.**

**User-visible truth today: background the app mid-run and you get NOTHING (short run)
or THREE identical banners at foreground (long run). Never one banner at the right
time** — which is the entire point of #38.

**Mechanism, source-confirmed:**
1. `PendingRun` is created **only on `.interrupted`** (stream drop), never during
   healthy streaming (`ChatStore.swift:716`).
2. So the scene-phase hook `watchPendingRunIfNeeded()` (`AppEntry.swift:311` →
   `AppContainer.swift:2178`) **silently no-ops at the home-screen transition** — inside
   iOS's background grace the stream is still healthy, so there is no pending run to
   watch. **The hook's own comment describes exactly the case its guard excludes.**
3. **Short run** ⇒ finishes in-process during grace ⇒ no orphan, no watch, **no
   notification at all**; the reply just waits silently.
4. **Long run** ⇒ stream dies at suspension, but `.interrupted` → `onRunDetached` →
   `postPushWatch` runs **only on foreground** ⇒ the watch arms against an
   already-finished run ⇒ the relay **insta-pushes by design**, once per active
   `push_registrations` row, **plus** the reconcile's local notify fired while the
   activation chain is still `.inactive` (`ChatStore.swift:1743`) — each with a
   **unique UUID identifier** (`LocalNotificationService.swift:58`), so nothing
   coalesces ⇒ **×3 identical banners over the app you just opened.**

**Fix shape — all app-side, ZERO relay change (fits the no-hardening rule):**
- **(a)** arm the watch on the background transition whenever a **stream is in flight**,
  not only when a `PendingRun` exists. The relay watcher is positional and the code
  comment already blesses insta-fire as correct.
- **(b)** a **stable** notification identifier (`hermes.run.completed.<runId>`) so
  duplicates REPLACE instead of stack.
- **(c)** single-flight the reconcile path — **this is instance 3 of #227**.

> **⚠️ THE INSTRUMENTATION TRAP, and it generalises — read before attempting to verify
> this.** Attempt 5 (instrumented, `sleep 150`, 18:43) showed the stream **surviving
> 2m42s of home-screen backgrounding**. **A process with a live Xcode launch session
> (corded, on power) NEVER SUSPENDS**, so the `.interrupted` branch is unreachable on
> the instrumented rig and "no banner" is the correct outcome for ANY run length there.
> That is not a weakness in the finding — it **explains the attempt table's split**:
> attempts 1–2 (the ×3 banners) ran under an EXPIRED launch session, i.e. normal
> suspension; every live-session attempt rode a process that never sleeps.
> **The ×3 branch cannot be instrumented with the corded console at all.**
> **Consequence for this item AND for #81 (§F4):** verification must be **uncorded and
> un-attached** — launch by hand, phone off the cable, recover the log afterwards via
> Console.app or a sysdiagnose. A lock-mid-stream or background-mid-stream check on the
> kept-alive rig measures nothing real.

**Still owed:** the **×N decomposition** arrives free with #133/#143's OJAMD recount —
N should equal this token's active `push_registrations` rows **+ 1 local**. If it does
not, there is a fourth source.

> ## ✅ ALL THREE LEGS BUILT 2026-08-02 — device verification owed, and it must be UNCORDED.
>
> | leg | what changed | pinned by |
> |---|---|---|
> | **(a)** | `ChatStore.watchableSessionId` — a stream in flight is watchable via `activeSessionID` when no `PendingRun` exists. `watchPendingRunIfNeeded` consults it. **A pending run still wins** (it names the session actually orphaned); idle, or streaming with no server session, still watches nothing | 4 truth-table rows |
> | **(b)** | `LocalNotificationService.runCompletedIdentifier(runId:)` — `notifyRunCompleted` now takes the run id, so the relay's insta-push and the local notify **REPLACE** instead of stacking | 3 rows |
> | **(c)** | `reconcilePendingRuns()` single-flighted onto one in-flight `Task`; concurrent callers await it. **#227 instance 3** | 1 concurrency test |
>
> **Leg (b)'s nil case is deliberate and is the non-obvious half.** An unidentifiable
> run falls back to a **unique** id, not a stable constant — a constant would collapse
> every such run onto one banner, so a second run would silently replace a first the
> user had not read. **That trades three banners for a MISSING one: the same defect
> wearing the opposite sign.**
>
> **Leg (c) was written as a `Task`, never an `isReconciling` Bool** — every concurrent
> caller clears a Bool check before any of them sets it, which is precisely the
> non-guard #227 exists to name. Same shape as
> `AppSessionStore.refreshAccessTokenIfNeeded` and #145 Part D.
>
> **RED witnessed behaviourally for (c):** with only the coalescing disabled, the suite
> reported **8 tests / 1 failure** — the single-flight test alone, legs (a) and (b)
> untouched. The test parks the first reconcile *inside* the client before releasing the
> second, so it cannot pass by mere sequencing; counting calls against an instant client
> would have let a store with no guard at all pass.
>
> **⚠️ DEVICE VERIFICATION MUST BE UNCORDED — see the instrumentation trap above.** A
> live Xcode launch session never suspends, so the `.interrupted` branch is unreachable
> corded and "no banner" is the correct outcome there for ANY run length. Launch by
> hand, phone off the cable, recover the log afterwards. **What to expect after this
> lane: exactly ONE banner** — leg (a) arms the watch so a short run is no longer
> silent, and leg (b) collapses the duplicates. If it is still >1, the ×N decomposition
> (above) says where the extra came from.

## 216A. ✅ re-read #200F and #214's grab results in light of the substitution finding — RESOLVED 2026-08-02: #214 CONFIRMED a true zero; #200F evicted, permanently unresolved

**FILED 2026-08-01** from the audit's unfiled-lanes list. **Analysis, not a device
run** — cheap, and it may retire other work.

#216 established that narrowing a belt **redirects** over-serving rather than
removing it (`readCalendar` 7→0 and `lookupContact` 8→0 while `currentLocation`
went 1/10 → 10/10). If substitution is the mechanism, then **grab counts recorded
before that was understood may have been measuring displacement, not disease** —
a tool going to zero reads as a win when the pressure simply moved.

**Owed:** re-read #200F's and #214's grab tables against the substitution model
and record whether any conclusion changes. **A conclusion that survives the
re-read is stronger than one that was never re-read** — and if one does not
survive, it is better found here than in a promotion.

### RE-READ DONE 2026-08-01 — the analysis CANNOT settle it, and why it cannot IS the finding

**Result: #216's reframing is BETTER supported than the argument it was made
with — and every 0/10 haiku grab in the series is now a live suspect, not a
cleared one.** One command settles it; the data may or may not still exist.

**I set out to defend those 0/10s and the source refused.** The reasoning I
started with was: substitution needs somewhere to go, #214's treatment rode a
**create-only** belt, so on the haiku prompt there was no hunting tool left to
displace onto and the 0/10 must be real. **That is wrong, and `scopedBelt`
says so in its own doc comment (`LocalChatBackend+Battery.swift:645`):**

> *"Haiku rides the REMIND scope — the worst-case misroute canary."*

| cell | haiku belt (`scopedBelt`) | hunting tools left to displace onto |
|---|---|---|
| `armed-scoped` (#200F) | `createReminder`, **`readReminders`**, **`readCalendar`** | **two** |
| `armed-createonly` (#200F) | `createReminder`, **`readCalendar`** | **one** |
| `armed-scopedv2` (#214) | `createReminder`, **`readCalendar`** | **one** |

**All three cells reported haiku grabs 0/10. All three had at least one hunting
tool on the belt — and it is `readCalendar`, one of the exact two tools #216
measured the impulse displacing OFF of on the calendar prompt** (`readCalendar`
7/10 → 0/10, `lookupContact` 8/10 → 0/10, `currentLocation` 1/10 → **10/10**).

So the structural opening #216 found on calendar was present on haiku too. **If a
grab was scored from the response TEXT** — and #214's control grabs are quoted as
text (*"I've set a reminder for you to write a haiku… Here's"*) — **then a haiku
trial that silently called `readCalendar` and then answered would have scored as
NO GRAB.** That is the artifact, and it is exactly what #216A was filed to look
for.

**Why #216 could not have caught this in its own run, and this is not a criticism
of it:** under routing the haiku prompt goes **toolless 10/10 in both arms**, so
#216's haiku trials had no belt at all. Its reframing had to be extrapolated from
calendar to haiku — and **the only cells that can test it are the old UNROUTED
ones, #200F and #214.** A lane cannot falsify itself on a prompt its own design
routes away from the belt.

**Evidence pointing the other way, recorded so this is not one-sided:** #214's
treatment refused all ten *explicitly* — *"I cannot write a haiku **without
external tools**"*. A model saying that is reporting an unusable belt, not
narrating a successful hunt. That is real but soft: it is consistent both with
"did not call anything" and with "called `readCalendar`, got nothing useful,
gave up." **The two are distinguishable only in the record.**

### It is settleable in ONE command — if the runs survive

`call_economy_report` (`scripts/classify-battery-run.py:709`) already prints the
per-prompt tool-name `Counter` for every cell, haiku included. **And `toolCalls`
recording landed 2026-07-28 (`801e872`), BEFORE both runs** — #200F 07-29,
#214 07-31 (`1835BBF9`). So the runs, if present, contain the answer.

**The risk is that they are gone, and the timing is painful.** `BatteryRunStore.maxRuns`
was **10** until `7bf206e` (2026-08-01) raised it to 50 — and **pruning was
SILENT until that same commit** added the `.notice` and the `onPrune` seam. #200F
ran 07-29 with a dozen-plus runs after it. **The bound was raised one day after
the runs this lane needs were most at risk, and nothing recorded whether they
were evicted.**

That is the #219/`BatteryRunStore` argument arriving in the concrete: *"a battery
run IS the evidence a promotion rests on."* Here it is the evidence a
**retraction** rests on, which is the same thing pointed backwards.

**Owed — one cheap device read, now queued as §C5:** open the Battery Results
screen, check whether runs `1835BBF9` (#214) and #200F's are still in the store,
and export them. Then `call_economy_report` gives the verdict directly.

**Until that runs, the honest status of every 0/10 haiku grab in the series is
UNRESOLVED — neither confirmed nor retracted.** They are not being called wrong.
They are being called **unverified in a way nobody had noticed**, which is the
outcome #216A was filed to produce.

### RESOLVED 2026-08-02 — §C5 ran (device pass, corded). #214 CONFIRMED; #200F EVICTED.

**The one command ran, on the one record that survived.**

- **Recovery method, worth keeping:** the records needed neither the share sheet
  nor the DEBUG-only Battery Results screen — `xcrun devicectl device copy from
  --domain-type appDataContainer --domain-identifier org.aethyrion.talaria27`
  pulls `Library/Application Support/BatteryRuns/` off a corded phone directly,
  on any build config. **All ten surviving runs are archived at
  `handoffs/evidence/battery-runs/`** (local, gitignored) — the store can no
  longer lose anything that existed on 2026-08-02.
- **#214 (`1835BBF9`) — the 0/10 is REAL.** `call_economy_report`: the
  `armed-scopedv2` haiku cell recorded **zero tool calls in all ten trials**
  (median=0, max=0, empty Counter). **No silent `readCalendar` — the artifact
  this lane was filed to look for did not occur.** Text scoring and the call
  record also agree on the control cell (`armed` haiku: grabs 8/10, `toolCalls`
  `createReminder`×8). And the soft evidence is now hard: the *"I cannot write a
  haiku without external tools"* refusals came from trials that called
  **nothing** — an unusable-belt report, not a failed-hunt narration.
- **#200F — evicted, unrecoverable, and the timing fear above was exactly
  right.** The store held **exactly 10 files**, oldest 2026-07-31 19:29Z: the
  silent `maxRuns = 10` bound pruned the 07-29 run during the 07-31/08-01 lanes,
  before `7bf206e` raised it. **Its `armed-scoped` and `armed-createonly` haiku
  0/10s stay permanently UNRESOLVED as direct evidence — do not cite them as
  verified.** Closest inference: `armed-createonly`'s belt is identical to
  `armed-scopedv2`'s (`createReminder` + `readCalendar`), which posted a true
  zero on the same prompt. Supportive, not probative.
- The #219 argument this entry invoked in the abstract now has its concrete
  instance: evidence a retraction would have rested on was destroyed silently,
  and the deletion left no trace until someone went looking.

## 218. ✅ `main` DID NOT BUILD IN RELEASE for two days, and every check we run is blind to it. FIXED 2026-08-01.

> **CLOSED — header flipped 2026-08-01 (Hermes audit Part 1A).** FIXED 2026-08-01 and closed out — `scripts/mac/lane-gate.sh`, verified to FAIL as well as pass.

*(OPEN_ITEMS #218. **Not** GitHub PR #218, which was the same day's documentation
lane — the sequences are separate and collided here.)*

**FOUND 2026-08-01 while sweeping the external audit's nits — not by the audit,
and not by anything that was looking for it.**

```
LocalChatBackend.swift:1444: error: type 'Self' has no member 'toollessHonestyClause'
LocalChatBackend.swift:1526: error: type 'Self' has no member 'deadEndCarveoutClause'
LocalChatBackend.swift:1578: error: type 'Self' has no member 'toollessHonestyClauseV2'
```

**Root cause: three PROMOTED instruction clauses were declared inside the
`#if DEBUG` harness region while production read them on every turn.**
`instructionsText` — production instruction assembly — referenced all three. A
production reference to a DEBUG-only declaration compiles fine in Debug and not
at all in Release.

Introduced by **#202C (`7b3bf09`, 2026-07-30)**, extended by **#202D (`eea6683`)**
and **#204 (`7c3bf37`)**. Each lane promoted a clause into production and left the
`let` where the lane happened to be working.

**Confirmed on a clean worktree of `main` with no local edits** — identical three
errors. This was not an artifact of the branch that found it.

### Why nothing caught it, which is the actual finding

**Every build this project runs is Debug.**

| check | configuration | would it have caught this? |
|---|---|---|
| full unit + UI suite | **Debug** | no |
| corded device install (`RunProject`) | **Debug** | no |
| CLI compile check in `CLAUDE.md` | **Debug** | no |
| the 2026-08-01 external audit's independent `build-for-testing` | **Debug** | no |
| `scripts/mac/ota-stage.sh` | **Release** (default) | **yes — and it would have failed at archive** |

So the app could not be archived, OTA-deployed, or submitted for two days, and
**1461 green tests said nothing about it.** The audit rebuilt the project from a
fresh clone and ran the whole suite independently — and still could not see it,
because it ran the same configuration everything else runs.

**This is a blind spot in the verification stack, not a slip in one commit.** No
amount of care inside the Debug configuration would have surfaced it.

### NOT caused by #216, checked specifically

The extraction was the obvious suspect and it is innocent. The declarations were
inside `#if DEBUG` **both before and after** the split; the call sites were
production **both before and after**. #216 remains pure motion and the audit's
verdict on it stands.

**But it exposes a limit in how #216 was verified.** The multiset line-diff proved
every line survived the move — it cannot see a line's **compilation condition**.
"Pure motion" as measured meant "same lines", not "same lines, compiled under the
same conditions". For this defect the two differ, and the technique would have
reported clean either way.

### Fix

The three clauses moved into `LocalChatBackend.swift`, unconditionally compiled,
with a do-not-move-back pointer left in `+Battery.swift`. Release **BUILD
SUCCEEDED**; suite **1461/1461 in 117 suites** + 8 UI tests, every edited file
confirmed recompiled rather than assumed.

### Rules this earns

1. **A promoted string is production code and moves out of the harness in the
   same commit that promotes it.** The measurement program's whole value is that
   promoted text is exactly what shipped — that guarantee is void if the text
   cannot compile in the shipping configuration.
2. **Any lane that changes what compiles under which configuration is verified
   with a Release build.** `#if DEBUG` edits, harness extractions, gating changes.
   A green Debug suite is structurally incapable of catching a mis-set gate.
3. **A Release build belongs in the pre-merge gate**, not just before a release.
   Two days is how long it took to notice with an external auditor actively
   rebuilding the project. Without one it would have been found by a failed OTA.

**Related, same day and same shape:** gating `RouterIntent` (audit §6D) is
*exactly* this bug in the other direction — it was safe only because every
consumer already sat in a DEBUG region, and it was verified with a Release build
for that reason. That check is what found this.

### THE GATE SHIPPED WITH A FALSE PASS, caught on its FIRST real run 2026-08-01

Run against `main` immediately after merge, it printed **`GATE: PASS` while four
UI tests had failed and `xcodebuild` had exited 65.**

```
MessageIdentityUITests.testTranscriptNeverRendersDuplicateMessageIDs()
TalariaUITests.testDisconnectReturnsToStandaloneChat()
TalariaUITests.testPairedRelaunchSkipsPairingEntry()
TalariaUITestsLaunchTests.testLaunch()
** TEST FAILED **
```

Three defects, and the first is the one worth remembering:

1. **The "positive marker" was satisfiable by a no-op.** The XCUITest check
   matched `Executed N tests, with 0 failures` — and **zero is a number.** An
   empty sub-suite prints `Executed 0 tests, with 0 failures`, which matched.
   **A success marker that nothing-happening satisfies is not a success marker.**
2. It matched a string that occurs many times in a test log and passed on any one
   of them, rather than the single authoritative verdict (`** TEST SUCCEEDED **`).
3. It captured `xcodebuild`'s exit status and deliberately did not act on it.
   "Do not trust exit status ALONE" is correct; "ignore it" is not.

**The script was written to prevent absence-read-as-success and then committed the
same error one level up.** The reason is specific and worth naming: it was tested
against the failure I *expected* — the #218 Release break, which it caught — and
not against a failure I had not imagined. **Testing a checker against the bug that
motivated it proves only that it catches that bug.**

**Fixed:** success now requires the authoritative marker **AND** exit 0 **AND** a
count > 0; any explicit failure marker fails outright; failing test names print.
Verified by replaying the exact log that produced the false PASS — the new logic
rejects it four independent ways where the old logic passed it.

**The four failures were a harness flake, not a product bug** — the same tree
passed on re-run (1461 + 8, TEST SUCCEEDED, Release SUCCEEDED). Distinguishing
feature, now taught by the script itself: the failing run had **no assertion text
and no `.swift:NN: error:` line anywhere** — `testLaunch` passed, restarted, and
the suite then reported zero tests. A real failure names an assertion; a dead
runner marks everything failed silently. **This is NOT #164's mechanism** (that
one is a bare `.exists` at `AppTemplateUITests.swift:209`), so it is not
occurrence 5 of that item — it is a separate, less-characterised harness flake.

**Standing instruction on a flake:** re-run ONCE and record BOTH runs. Do not
re-run until green and report only the green one — that is how a real
intermittent regression gets laundered into "passes on my machine."

### CLOSED 2026-08-01 — `scripts/mac/lane-gate.sh`

One command, run before opening any PR: Debug suite (units + XCUITest) **plus a
Release build**. Documented in `CLAUDE.md` (Build / tooling) and `CONTRIBUTING.md`.

**It is verified to FAIL, which is the only interesting property of a gate.** The
#218 bug was re-injected — the three promoted clauses wrapped back in `#if DEBUG` —
and the gate returned `GATE: FAIL` with all three compile errors printed. Reverted,
then `GATE: PASS` on the real tree (1461 tests / 117 suites, 8 UI, Release
SUCCEEDED). A gate that has only ever been seen to pass is not known to work.

**The design constraint, and it is this session's lesson made executable: every
check passes only on a POSITIVE marker.** Absence of `BUILD FAILED` is not success
— a build that dies early, a missing toolchain, or a log that never got written all
produce a log containing no failure marker. The `require()` helper greps for the
success string and treats an empty or missing log as FAIL. Do not "simplify" it
into `! grep FAILED`; that is exactly the bug it was written against, the same
shape as `ls-remote | grep || echo absent` reporting a branch gone that was never
gone.

**Not wired to CI, deliberately:** there is no CI in this repo, and the toolchain
is a beta Xcode on one Mac. A hosted runner has no iOS 27 SDK. So the honest
mechanism is a script a human or agent runs, named in the two files anyone reads
before submitting — **not** a green badge that would have to lie about which
toolchain it used. If a self-hosted runner ever exists, this script is what it
should invoke.

**Residual risk, stated rather than papered over:** nothing *forces* the gate to
run. It is one command in the two documents that govern submissions, which is a
large improvement on a rule that lived nowhere, but it is not enforcement.

## 198. ✅ beta-4 deprecation sweep. 13 of 17 sites cleared; the remaining 8 are NOT mechanical.

> **CLOSED 2026-08-01** — duplicate entry for this item; the evidence is on the other `## 198` header. Two headers exist because the file's numbering convention changed mid-project (`## N.` → `## #N —`) and this item has one of each.

**STARTED 2026-07-31 after the Hermes audit named it the highest-severity unrouted
item. Clean-build inventory: 17 distinct sites, 10 symbols, 6 files.**

**Cleared (13 sites):**

- **FoundationModels / `GenerationError` → `LanguageModelError`.** Not cosmetic.
  `LanguageModelError` is the iOS 27 successor, and **#209's pooled data says it
  is what the device actually throws** — bucket E was 80.6% of all recorded
  errors. **So #210's typed cast was very likely failing because it tested the
  DEPRECATED type.** `isContextOverflow` now matches
  `LanguageModelError.contextSizeExceeded` first, whose payload carries
  `contextSize`/`tokenCount` as integers — no string parsing. #210's content
  check stays as the backstop: it caught the two real overflows in the record,
  and until a device run confirms which TYPE those arrived as, removing it would
  trade a measured behaviour for an inferred one.
- **MapKit / `CLGeocoder` + `.placemark` → `MKGeocodingRequest`,
  `MKReverseGeocodingRequest`, `MKMapItem.location`/`.address`.** Both request
  types' `mapItems` getter is `NS_SWIFT_UI_ACTOR`, so `MKMapItem` is
  MainActor-bound and NON-Sendable — the shape that already forced the
  `CLLocationManager`/`CMPedometer`/`MKLocalSearch` rewrites. Each lookup and its
  string extraction sit inside one MainActor hop.
- **AlarmKit `stopButton`** — behaviour-neutral by Apple's own message.

**BEHAVIOURAL DELTA, not buried:** `CLPlacemark` carried a `country` and
`MKAddressRepresentations` has none. `readLocation` used to answer
"Name, Locality, State, United States" and now answers "Name, Locality, State".
This is a READ tool whose output the model consumes, and #200-era work showed
tool-result phrasing changes behaviour — **small, but not a no-op, and it wants a
device eyeball rather than an assumption.**

**Two deliberate warnings remain by design:** the deprecated `GenerationError`
arms are quarantined in `@available`-annotated helpers reading "Delete with
GenerationError … (#198)". **This does NOT remove the beta-5 risk and is not
pretending to** — deprecated is not removed, the SDK still declares the type, and
nothing guarantees which one a failure arrives as. When a seed deletes it, both
helpers and one test go together and the four cases unique to the old enum become
unreachable by construction.

### The remaining 8 sites are refactors, not sweep items — the audit's scoping was half right

The audit called #198 "mechanical, file-scoped, safe to route to any executor".
**True for the 13 above; NOT true for what is left:**

- **`AVAudioSession.InterruptionType`/`InterruptionOptions` (4 sites).** The
  successor is TWO separate notifications (`DidBecomeInactive` +
  `ResumptionRecommendation`) replacing one notification with a type payload. The
  "should resume" decision moves from an option flag to its own notification —
  a structural rewrite of interruption handling, not a rename.
- **`installTap(onBus:bufferSize:format:block:)` (2 sites).** Deprecated with **no
  replacement named**, and it is the core capture tap feeding the speech
  analyzer. Replacing it blind is not viable.
- **`BGTaskScheduler.submit` (2 sites).** The successor `submitTaskRequest(_:)`
  is ASYNC and documented "do not call this method from the main thread" — while
  `beginLongSend` is MainActor-isolated and returns its handle synchronously,
  with `nil` signalling submit failure. Migrating changes the signature of a
  function wired into `ChatStore`'s send path. **That is the most load-bearing
  path in the app and it has thin coverage.**

**All three want their own lane with a device pass, not a sweep commit.** Filing
them as such is the point of stopping here rather than pushing a risky refactor
into a hygiene PR.

### RE-SCOPED 2026-08-01 — TWO of the three notes above were WRONG, verified against the beta-4 SDK

Both errors came from reading the compiler's summary rather than the interface —
the failure mode the standing rule on WWDC26 surfaces exists to prevent, applied
to deprecations instead of new API. Corrected by grepping the headers and by
compile-probing with `swiftc -typecheck`, which settles a signature question in
seconds without a full build.

**1. `installTap` — "no replacement named" is FALSE, and so was my first
correction of it.**

`AVAudioNode.h:117` carries
`API_DEPRECATED_WITH_REPLACEMENT("installTapOnBus:bufferSize:format:error:block")`,
and `:160` declares it. I then probed twice, failed twice, and concluded there
was **"no supported Swift spelling — blocked on Apple."** Owen pushed back:
*"lets not jump to its apple. twice we've done that, twice we've been wrong."*
He was right, and it was the third time.

**Asking the compiler for the signature instead of guessing at it settled it in
one step.** Assigning the method to a deliberately wrong type prints the real
imported form:

```
(AVAudioNodeBus, AVAudioFrameCount, AVAudioFormat?, (), @escaping AVAudioNodeTapBlock) throws -> ()
```

It **is** throwing, and the importer left a vestigial `()` where the `NSError**`
was. So it is callable today, and this **compiles clean with no deprecation
warning**:

```swift
try node.__installTap(onBus: 0, bufferSize: 1024, format: f, error: (), block: { _, _ in })
```

**So the migration is available and the decision is OURS, not Apple's.** The
genuine trade-off, which is a judgement call and not a blocker: the symbol is
`__`-prefixed (refined-for-Swift, awaiting an overlay AVFAudio does not yet
ship) and takes a meaningless `()` argument. Both say a later beta will change
this call site. Migrating now silences two warnings and buys brittleness;
holding keeps two harmless warnings. **Recommend holding, and re-probing after
any SDK bump** — but as a choice we made, recorded as such.

**The lesson, which outranks the finding:** two probes failing is not evidence of
absence. `let x: Int = someMethod` makes the compiler print the exact signature,
and that should be the FIRST move on any import question, not the last.

**2. `BGTaskScheduler.submit` — "the successor is async, so the signature must
change" is FALSE.**

`BGTaskScheduler.h:140` declares a **completion-handler** form; the
`NS_SWIFT_ASYNC_NAME(submitTaskRequest(_:))` on it names only the ASYNC
PROJECTION. The completion form remains callable, and **compile-probed from a
`@MainActor` SYNCHRONOUS function it type-checks clean.** `beginLongSend` does
not have to become async, and `ChatStore`'s send path does not have to change
shape.

**What does NOT dissolve, stated so this is not overclaimed:** `submit` throws
SYNCHRONOUSLY and `beginLongSend` returns `nil` on that failure. The
completion handler delivers the error AFTER the function has returned, so the
synchronous nil-on-failure signal cannot survive as-is. **The signature is safe;
the failure semantics still need a decision.** That is a smaller and much
better-defined problem than "the most load-bearing path in the app must change
signature", and it is now a tractable lane rather than a hazard.

**3. `AVAudioSession` interruption — the note holds.**
`AVAudioSessionResumptionRecommendation` exists at `AVAudioSession.h:612` as
described. Not disproven; still a structural rewrite.

## 217. ✅ CAN this model classify intent safely enough to drive a belt? A probe, not a belt lane.

> **CLOSED — header flipped 2026-08-01 (Hermes audit Part 1A).** ABANDONED per pre-registration; single-Bool follow-up PARKED at Owen's direction. Owed: nothing.

**FILED 2026-08-01, bars written first. NO production change — `ToolIntentRoute`
is untouched and nothing narrows any belt. Owen routes the run.**

**Why a probe first.** #216 priced the prize (calendar 6.1s → 3.5s, 2,269 → 976
input tokens, creates and composition untouched) and named the blocker:
`scopedBelt` keys on `promptTag`, which exists only inside the harness.
Production's router returns a **Bool**, so it can decide *whether* to arm and
never *what to arm with*. Fixing that means the router returns an intent — and
before any belt rides an intent, the intent has to be shown safe.

**The asymmetry that shapes the whole design.** A Bool router that is wrong
falls back to the full belt: today's behaviour, failure free. **An intent router
that is wrong arms the WRONG belt** — a turn needing `createCalendarEvent` while
holding only health tools is *strictly worse than arming everything*. So every
failure path lands on `.other`, and `.other` means the full belt. Pinned by
`RouterIntentTests`, including a total lenient parse (empty string, junk,
unknown future vocabulary → `.other`) and an assertion that `.other` is the
**only** non-scoping case, so no intent can be silently inert and score as a win
it did not earn.

**Design choices worth recording:**

- **A `String` with `@Guide(.anyOf:)`, not a `@Generable` enum.**
  `GenerationGuide.anyOf(_:)` was **verified present in the beta-4
  `swiftinterface`**, per the standing rule against trusting recall on WWDC26
  surfaces. And #209 already established how a required `String` misbehaves — a
  model with nothing to say emits `""` rather than omitting the key — so that
  case is handled rather than discovered.
- **ONE generation, not two.** #215 measured the router at ~1s on a turn it
  arms; a second generation would spend #216's entire latency prize before any
  belt narrowed. The cost is that the extra field might degrade the Bool, which
  is not something to argue about — it is the gate below.
- **`ToolIntentRouteV2` is a separate type.** Production's `ToolIntentRoute`
  stays exactly as it is, as the control, because the question is whether adding
  a field costs the Bool its 200/200.
- **The grid is a SEPARATE list from `routerBaselineProbes`** — #205's lesson,
  recorded in that file in as many words: adding rows to the pinned ten silently
  re-points a long-running series and moves a pre-registered bar.

**The grid deliberately includes four ARMED rows outside the vocabulary** —
contacts, past chats, places, device status. They are real device requests whose
correct answer is `other`, and they are where over-eager pattern-matching would
surface. A model that answers `calendar` to "when did I last text Sam about the
boat" is the failure this design exists to prevent.

**Bars, pre-registered (encoded in `classify-battery-run.py`, so the verdict is
computed rather than judged):**

- **Gate** — V2's Bool accuracy on the pinned ten **≥95%** (#202A's
  `BASELINE_GATE`, against a 200/200 history). Below it nothing else is worth
  reading: the Bool is load-bearing on every turn and worth more than the
  scoping.
- **Primary A** — scoped-intent accuracy **≥90%**.
- **Primary B, the bar the design lives or dies on** — **DANGEROUS answers
  ≤2%.** A *dangerous* answer is a scoped intent that is the wrong scoped
  intent, or any scoped intent on an `other` row. Answering `other` when a
  scoped intent was right is a **MISS, not a danger** — it arms the full belt,
  which is exactly today. Those two produce identical `correct/trials` and
  opposite verdicts, which is why `intentTally` records the whole distribution
  instead of a ratio.
- **Primary C** — out-of-vocabulary armed rows answer `other` **≥90%**.

**What would falsify the approach:** dangerous answers above 2%. The entire case
for an intent router is that its failures are free. A model that guesses a scoped
intent rather than saying `other` turns every misclassification into a disarmed
turn — worse than the belt we ship today, and **not worth 2.6 seconds.**

### VERDICT FILED 2026-08-01 — run `3CB9E45D`. **PRIMARY B FAILS at 12.5% against a 2% bar. The approach as specified is FALSIFIED.**

260 classifications, `endedCleanly: true`, **zero router errors across all 26
rows** — every number below is a real classification.

| bar | pre-registered | measured | |
|---|---|---|---|
| Gate | V2 Bool accuracy ≥95% | **100%** (100/100) | PASS |
| A | scoped-intent accuracy ≥90% | **100%** (100/100) | PASS |
| **B** | **dangerous ≤2%** | **12.5%** (20/160) | **FAIL — 6× the bar** |
| C | out-of-vocabulary `other` ≥90% | **66.7%** (40/60) | FAIL |

**The falsification I wrote in advance fired. I am recording that as the
verdict**, not as a surprise to be explained away.

**Two rows carry the entire failure, and both are DETERMINISTIC:**

| prompt | wanted | answered |
|---|---|---|
| "When did I last text Sam about the boat?" | `other` | **`reminder` 10/10** |
| "How much battery do I have left?" | `other` | **`health` 10/10** |

**Every one of the 16 grid rows answered the same value 10 times out of 10. Zero
variance in 160 classifications.** This is not a model that sometimes guesses
wrong — it is a **fixed mapping**. "Text Sam about the boat" *is* `reminder` to
this model; "battery" *is* `health`. A deterministic error is worse in that it
fires 100% of the time on those requests, and better in that it is addressable
rather than stochastic. It also means n=10 per row bought nothing here; n=1 would
have produced this table.

**The mechanism: nearest-neighbour substitution, not random guessing.** The model
answers `other` reliably when a request is FAR from every vocabulary entry —
phone number, coffee shop, haiku, arithmetic all 10/10 `other` — and substitutes
the closest entry when the request is NEAR one. Restricted to the four ARMED
out-of-vocabulary rows, `other` accuracy is **20/40 = 50%**: a coin flip.

**And it never erred in the safe direction. Zero safe misses** — not once did it
answer `other` where a scoped intent was right. The guide says in as many words
that *"Guessing is worse than answering other"*, and it guessed anyway. The bias
against `other` is strong and one-directional.

### What survives, and it is not nothing

- **Adding a second field cost the Bool NOTHING: 100/100 against its 200/200
  history.** The schema is safe to extend, and that is reusable by any future
  lane that wants more out of one router generation.
- **In-vocabulary classification is PERFECT: 100/100 across all five intents**,
  20/20 on each. The model can absolutely classify intent. It cannot decline to.

**So the defect is precisely located: the `other` escape hatch does not work when
the request is near a vocabulary entry.** That is a narrower and more tractable
problem than "the model can't classify intent" — which this run rules out.

### Two candidate causes, both cheap to test, and one honest caveat

1. **The vocabulary was INCOMPLETE.** `searchConversations` and `deviceStatus`
   are real belt domains I deliberately left out, so on those two rows the model
   had no correct scoped answer available. Completing the vocabulary
   (`conversations`, `device`, `contacts`, `places`) may make both rows correct.
2. **The `other` guide is too weak.** Guide wording has a strong measured history
   of moving routing behaviour — #207's image guide took reading prompts from 1/4
   to 4/4, and the signal without the guide moved nothing. A harder prohibition
   on guessing is a one-cell measurement.

**The caveat that neither fixes:** a vocabulary can never be complete. Any belt
has domains and any request can fall between them, so completing the list shrinks
the near-miss zone rather than closing it. **The escape hatch has to work on its
own merits**, which makes candidate 2 the load-bearing one and candidate 1 the
cheap confound to remove first. Testing 1 without 2 risks a run that passes
because the grid no longer contains a near miss — measuring the grid rather than
the model.

**Owed:** a #217B cell pair — completed vocabulary, and a strengthened `other`
guide — scored against THIS run as control, with at least two armed rows kept
deliberately outside whatever the new vocabulary is, or the bar becomes
unfalsifiable. **No belt rides an intent until B passes.**

### #217B FILED 2026-08-01 — a 2×2, because the two candidates must be separated, not confounded

**No production change. Owen routes the run.**

| | v1 guide (#217's) | v2 guide |
|---|---|---|
| **narrow vocabulary** | `narrow-v1` — **#217's exact cell, the control** | `narrow-v2` — guide effect |
| **full vocabulary** | `full-v1` — vocabulary effect | `full-v2` — the candidate |

Running the control **within this run** also fixes something #217 could not:
its 12.5% was a single-run number, and a cross-run comparison would have carried
the same thermal problem #215 and #216 both had to caveat.

**Why v2 is a different TACTIC and not a longer exclusion list.** #217's guide
*already named* contacts, past chats, places and device status as `other` cases,
and already said in as many words that guessing is worse. **The model ignored all
of it and answered `reminder` 10/10.** Listing exclusions is a measured failure
on this model, so v2 changes the frame instead: `other` becomes the DEFAULT
rather than the fallback, every category gets a positive test it must meet
("`health` only for the user's own body data…"), and the instruction is a rule
about certainty rather than an enumeration of exceptions.

**v2 deliberately does not mention messages, battery, music, navigation or
photos** — naming #217's two failures would teach to the test. Pinned by
`theSecondGuideIsADifferentTacticNotALongerList`, which fails if any of those
words appears.

**Three rows are out of vocabulary in EVERY cell** — "Play some music", "How long
will it take me to drive to the airport?", "Read the label on this bottle for
me". Armed device requests with no belt tool and no vocabulary entry in either
arm. **This is the trap the last verdict named:** without them, a full-vocabulary
cell could pass simply because the grid no longer contains a near miss, which
would measure the grid rather than the model.

**Scoring is per cell against the expectation that cell could express.** The four
added domains collapse to `other` under the narrow vocabulary
(`underNarrowVocabulary`), so the control is a faithful replication of #217
rather than a harsher re-scoring of it — pinned by
`addedDomainsCollapseToOtherUnderTheNarrowVocabulary`.

**n=5, down from 10, and the reason is a finding rather than a budget.** #217
produced **zero variance in 160 classifications** — all 16 rows single-valued
10/10. At that determinism n=10 bought nothing; n=5 still detects a split if the
larger schema introduces one, and pays for four cells instead of one. With
16 rows × 5, a single deterministic bad row scores 5/80 = 6.25% and **fails bar B
on its own** — which is correct, because a deterministic bad row fires on 100% of
those requests in production.

**Bars unchanged from #217, applied per cell:** gate ≥95%, A ≥90%, **B ≤2%**,
C ≥90%. **Promotion requires `full-v2` to clear all four** — and the main
effects then say whether the vocabulary, the guide, or only the pair did it.

**What would falsify the remedy:** `full-v2` still above 2% dangerous. That would
mean the escape hatch cannot be made to work by vocabulary or wording on this
model, and **intent-driven belt scoping should be abandoned** rather than
iterated — #216's 2.6 seconds are not worth a disarmed turn.

### #217B VERDICT FILED 2026-08-01 — run `8D724EC5`. **ALL FOUR CELLS FAIL. The pre-registered response is ABANDON, not iterate — and I am taking it.**

380 classifications, zero router errors across all 116 rows, gate **100% in every
cell** (50/50 ×4). Every row in every cell single-valued again: **zero variance in
380 classifications.**

| cell | dangerous (bar ≤2%) | `other` accuracy | scoped accuracy |
|---|---|---|---|
| `narrow-v1` (#217 control) | **10.5%** | 77.8% | 100% |
| `narrow-v2` (guide only) | **5.3%** | 88.9% | 100% |
| `full-v1` (vocab only) | **21.1%** | 40.0% | 92.9% |
| `full-v2` (candidate) | **15.8%** | 60.0% | 92.9% |

**The control replicated.** `narrow-v1` at 10.5% against #217's 12.5% — the same
two rows failing the same deterministic way (`reminder` for the Sam text,
`health` for battery). The rate moved only because the grid grew from 16 rows to
19; the behaviour is identical. **#217's verdict is now thermally controlled and
within-run.**

### The main effects, and one of them is backwards

**Guide v2 HELPS, consistently: 10.5% → 5.3% narrow, 21.1% → 15.8% full.** It
fixed the Sam-text row outright (`reminder` → `other`). Real, reproducible, and
**not enough** — the best cell in the entire 2×2 is still 2.6× the bar.

**Completing the vocabulary HURTS, and badly: 10.5% → 21.1%, and 5.3% → 15.8%.**
The hypothesis that #217 failed for want of vocabulary is not merely unsupported;
it is **falsified in the opposite direction.**

**The mechanism is `device`, and it is visible in one line:** answered **0/95** in
both narrow cells and **25/95 and 20/95** in the full ones. Adding it created a
new ATTRACTOR — a catch-all the model reaches for *instead of* `other`. It
swallowed "Play some music", "drive to the airport", "Read the label on this
bottle", and in `full-v1` even "How many steps have I taken today?", which is the
only reason scoped accuracy fell from 100% to 92.9%.

**So every word added to the vocabulary is a new wrong answer the model can
give.** That is the generalisable finding, and it inverts the intuition the lane
was built on.

### The bias underneath all of it

**Zero safe misses. In all four cells. Across 380 classifications, the model NEVER
once answered `other` where a scoped intent was right.** Every failure was a
commitment to a wrong category; not one was a retreat to safety.

This model does not decline on a multiway choice. It **always commits** — and the
`other` escape hatch that the entire safety argument rests on is therefore not
something wording or vocabulary can install. v2's guide made `other` the
explicit default and moved the rate by half, never toward abstention on a row it
had an opinion about.

### VERDICT: intent-driven belt scoping is ABANDONED

Pre-registered: *"`full-v2` still above 2% → abandoned rather than iterated."*
`full-v2` is **15.8%**. **Taking it.** The tempting read — "`narrow-v2` is one
row from zero" — is exactly the reasoning to distrust: a 19-row grid that finds
one deterministic bad row predicts many in unbounded user phrasing, and the
zero-safe-miss bias means every one of them disarms a turn rather than falling
back. **#216's 2.6 seconds do not buy that.**

### What survives, and one narrow path that is NOT this one

- **A second field costs the Bool nothing: 100% gate in all four cells, four
  different schemas.** Reusable by anything wanting more from one router
  generation.
- **In-vocabulary classification is excellent** (100% narrow, 92.9% full). The
  model can classify. It cannot abstain.
- **The Bool router CAN decline** — 200/200 lifetime, 100% here on toolless rows.
  Declining is available on a binary and not on a multiway choice.

**That last contrast suggests one surviving option, stated as a NEW hypothesis
and not a rescue of this one:** a single extra **Bool** — "does this turn want a
calendar event?" — rather than a multiway intent. It is the shape the model
demonstrably handles, it costs nothing extra (the gate proved the second field is
free), and #216's entire measured prize was on the calendar prompt. **It is
unmeasured, it needs its own probe with its own pre-registered bars, and it is
not what this lane tested.**

**PARKED 2026-08-01 at Owen's direction — recorded, NOT owed.** A notation so the
reasoning is not lost, not a queued lane. The honest baseline is that production
is fine and 2.6 seconds on one prompt is the entire prize. **Nothing should read
this as pending work** — that is the #190 failure mode, where an unclosed note
reads as a live blocker.

**Owed:** nothing from this lane. `RouterIntent`, the four probe types and the
grid stay as DEBUG-only measured artifacts — the record of a falsified approach,
which is worth more than a deletion.

## 216. ✅ the narrow belt, re-tried where it cannot lose. #214's closure was right about the evidence and wrong about the world.

> **CLOSED — header flipped 2026-08-01 (Hermes audit Part 1A).** Verdict filed 2026-08-01. Intent-router lane ran and was abandoned (#217). **Owed re-read is now lane #216A.**

**FILED 2026-08-01, bars written first. No production change — `routed-scoped` is
a measured cell. Owen routes the run and any promotion.**

**Why reopen a cell that was correctly closed.** #214 killed `armed-scopedv2`
because narrowing the belt took haiku grabs 8/10 → 0/10 and took clean
composition **8/10 → 0/10** with them. That verdict was right on its evidence. It
was measured on an UNROUTED battery, where the composition prompt is armed by
construction and therefore sees the narrow belt.

**#215 then measured what production actually does with that prompt: it routes
TOOLLESS 10/10.** A routed-toolless turn registers no belt at all. **So the
composition failure that closed #214 is unreachable once the router is in
front** — not mitigated, not traded against: structurally absent, because the
belt under test is never constructed on that turn.

**The target is measured, not assumed.** #215 priced production's residue and it
is one prompt:

| prompt | calls/trial | median | tools |
|---|---|---|---|
| remind | 1 | 3.7s | `createReminder` 10/10 |
| alarm | 1 | 3.3s | `scheduleAlarm` 10/10 |
| calendar | **3** | **6.4s** | create 10/10, `readCalendar` 7/10, `lookupContact` 7/10 |

**A +2.8s tax on every calendar turn for two lookups whose results change
nothing** — creates are 10/10 with or without them. `routed-scoped`'s belt
contains neither tool, so the mechanism is removal, not persuasion. **This is the
first lane in the series aimed at a LATENCY defect rather than a correctness
one**, because #215 showed the correctness defects on these prompts were the
instrument's.

**The cell.** Rides createonly's belt EXACTLY — the same belt scopedv2 rode, so
the lineage back through #214 and #200F is intact and this is a re-evaluation,
not a new unmeasured narrowing (pinned by `routedScopedNarrowsExactlyLikeCreateonly`).
It deliberately does NOT carry scopedv2's composition-licensing sentence: that
clause existed to repair the denial the belt caused, routing already repairs it,
and carrying it would make the cell differ from its control in two ways instead
of one. **Both arms route**, so the single variable is the belt an ARMED turn
sees. `routedProductionKeepsTheFullBelt` pins that the control is not narrowed
too — a `scopedBelt` regression that narrowed both would erase the contrast while
leaving every other assertion green.

**Bars, pre-registered:**

- **Gate** — control calendar calls/trial median **≥3**. #215 measured exactly 3;
  below that the overhead is absent tonight and the treatment has nothing to
  remove.
- **Primary A, the point** — treatment calendar calls/trial median **≤1**.
  Should hold by construction; failing it means something other than tool
  availability drives the lookups, which would be a more interesting finding
  than the lane.
- **Primary B, the promotion-killer** — treatment calendar creates **≥8/10**. A
  latency win must not buy the create rate.
- **Primary C** — treatment remind and alarm creates **≥9/10 each**. Both sit at
  10/10 with one call apiece; narrowing must not disturb a ceiling it was not
  aimed at.
- **Primary D, #214's objection measured rather than argued** — treatment haiku
  clean turns **≥8/10**. Composition should be untouched because the router sends
  it toolless in BOTH arms. Carrying the canary costs 20 generations to turn
  "unreachable by argument" into "unreachable, measured", and **#214 died on
  exactly this**, so a lane reopening it without measuring composition would
  deserve to be distrusted.

**What would falsify the premise:** haiku clean turns below 8/10, or ANY haiku
trial routing armed. Either means the composition objection reaches production
after all and #214's closure stands.

**Instrument added with the lane:** `call_economy_report` in the classifier.
#215's headline residue was computed by hand from the run record, which is the
wrong home for a lane's primary metric. It also reports same-tool repeats
explicitly — #215 saw zero in 80 trials, and "none" must be distinguishable from
"not measured".

### VERDICT FILED 2026-08-01 — run `5EE6ADBD`, corded @ whoGoesThere. **PRIMARY A FAILS. The lane succeeds anyway, and the failure is why.**

80 trials, `endedCleanly: true`, **zero ERROR, zero TIMEOUT.** Reap 60 recorded +
3 warm-up = 63, **exact.** All **80** routed trials carry `routeFailed: false` —
every route a real classification.

| bar | pre-registered | measured | |
|---|---|---|---|
| Gate | control calendar calls median ≥3 | **3** | PASS |
| **A** | **treatment calendar calls median ≤1** | **2** | **FAIL** |
| B | treatment calendar creates ≥8/10 | **10/10** | PASS |
| C | treatment remind + alarm ≥9/10 | **10/10, 10/10** | PASS |
| D | treatment haiku clean ≥8/10 | **10/10** (and 10/10 in the control) | PASS |

**Bar A failed as written and is not being redefined.** It said calls median ≤1.
It measured 2. The filing pre-registered what an A failure would mean —
"something other than tool availability drives the lookups, which would be a more
interesting finding than the lane" — and that is exactly what happened.

### The finding: the hunting DISPLACED. It did not disappear.

| calendar tool | control | treatment | |
|---|---|---|---|
| `readCalendar` | 7/10 | **0/10** | p = 0.0031 |
| `lookupContact` | 8/10 | **0/10** | p = 0.000714 |
| `currentLocation` | 1/10 | **10/10** | **p = 0.000119** |

**The belt did precisely what it was built to do** — both targeted tools went to
absolute zero. And the model then reached for the one hunting tool still on the
belt, going from **10% to 100%** usage. The "check something before creating"
impulse is not a preference for those two tools; it is a habit that **redirects
onto whatever remains.**

**That reframes every belt-narrowing result in the series.** #200F's 0/10 grabs
and #214's 0/10 grabs were read as the impulse being suppressed. On this
evidence it was being *rerouted* — and those cells only looked clean because
what it rerouted onto was not being counted. **Narrowing a belt does not remove
the behaviour; it chooses the behaviour's target.**

### The objective was achieved anyway, and by a wide margin

| calendar | control | treatment | |
|---|---|---|---|
| median latency | 6.1s | **3.5s** | **−43%** |
| worst case | 10.1s | **3.7s** | |
| median input tokens | 2,269 | **976** | **−57%** |
| gap to its own `remind` | +2.8s (#215) | **+0.5s** | |

**Nine of ten control trials are slower than the treatment's WORST trial**, and
the treatment is faster in **98 of 100** pairwise comparisons. The distributions
barely touch. The substitution costs one call, but `currentLocation` is a cheap
local read where `readCalendar` and `lookupContact` are EventKit and Contacts
queries — **so the count fell by one and the time fell by nearly half.**

Creates held at **10/10** (B) and composition was untouched at **10/10 clean in
both arms** (D), with the haiku routing toolless 10/10 in both — **#214's
objection measured, not argued, and absent.** `INVENTED LOCATION` stayed 0/10
even with `currentLocation` firing on every trial, so the substituted call binds
nothing into the event.

**Thermal, and it matters more here than in #215.** Control started `nominal` and
ended `fair`; the treatment ran entirely at `fair`. #215's win was a rate, where
thermal is a weak confound; **this win is a LATENCY claim, where thermal is a
direct one** — and it runs against the treatment, which ran hotter and was still
faster in 98/100 pairs. It cannot have manufactured this result. Matched-thermal
replication is owed before these seconds are quoted as lifetime numbers.

### NOT PROMOTABLE AS-IS — and the blocker is structural, not statistical

**`scopedBelt` keys on `promptTag`. Production has no `promptTag`.** The battery
knows each trial's intent because the harness told it; a live turn does not.
`routeNeedsDeviceTool` returns a **Bool**, so production can decide *whether* to
arm but not *what to arm with*.

**Shipping this needs the router to return an INTENT, not a Bool** — and #200F's
own comment said so a week ago ("production scoping would be router-driven — a
PROMOTION question, not this lane's"). This run's contribution is that the prize
is now priced: **−43% latency and −57% input tokens on calendar turns, at no cost
to creates or composition.** That is worth an intent-router lane; it was not
worth one on speculation.

**Owed:** an intent-returning router as its own lane, measured on route accuracy
before any belt rides it — a router that misclassifies intent would arm the wrong
belt, which is strictly worse than today's full belt. Matched-thermal replication
of these latencies. And a re-read of #200F/#214's grab results in light of the
substitution finding.

## 215. ✅ THE MISSING DENOMINATOR: the action battery has never routed, so no number it has ever produced describes the shipped app.

> **CLOSED — header flipped 2026-08-01 (Hermes audit Part 1A).** Verdict filed 2026-08-01, all four bars pass. Matched-thermal replication is device-list C4.

**FILED 2026-07-31, bars written first. No production change — `routed-production`
is a measured cell. Owen routes the run and any promotion.**

**This is #214's own verdict, acted on.** That lane closed with a finding bigger
than its result: `runActionBattery` does not route, every trial is armed by
construction, and "Write a haiku about sledding" is a baseline router row sitting
at **200/200 on `expected: false`**. In production that turn routes TOOLLESS, gets
an empty belt, and composes. **So the 8/10 control grab rate — the number that
justified days of lanes — measures a configuration we do not ship.** #204 had
filed this caveat a day earlier and it was not applied. Fixing the instrument is
the only way to know which of the remaining diseases are real.

**The cell.** `routed-production` is belt-and-instruction identity with `.armed`,
and differs in exactly one thing: `routeNeedsDeviceTool` runs first, and a turn
routed toolless gets no belt plus production's toolless text. Routing is a CELL,
not a run-level flag, so the contrast is WITHIN a run — same thermal state, same
slot rotation, per #200V. It is **not a treatment**: routing changes the belt, so
the two arms are two configurations, one of which we ship, not an A/B of any text.

**A defect found while building it, before it could produce a number.** The #196
rate battery's `armed-routed` cell built its toolless turn from
`instructionsText(for: .toollessLic2, …)`. On 2026-07-30 the #202D promotion added
clause v2 to production's toolless branch and created
`productionToollessInstructions` — whose doc comment says it exists "in ONE place
so the live path and the measured arm cannot drift apart." **Nothing re-pointed
the battery.** From that promotion until this lane, every routed-toolless trial in
the #196 instrument spoke a text production had stopped speaking — specifically
the `honesty-control` payload, measured at 9/10 BROKEN turns. Both batteries now
go through one seam (`routedTrialShape`), pinned by `RoutedTrialShapeTests`
including a directional assertion that production's text is a strict superset of
the stale one, so "agrees with production" cannot be satisfied by pointing both
sides at the stale text.

**And #213's disease, pre-empted in the new instrument.** `routeNeedsDeviceTool`
fails SAFE — a thrown generation returns `armed`. Recorded naively that is
indistinguishable from the router having looked at the prompt and decided, which
is exactly how #213's probe scored a crash as a correct answer. `routeFailed` is
sampled from `routerFailureTally` deltas around every route call and reported by
the classifier before any rate is read. Optional, so the 48 archived runs still
decode — pinned by a verbatim legacy-JSON test.

**Bars, pre-registered:**

- **Gate** — control (`armed`) haiku grabs **≥2/10**. Below that the disease is not
  present in this run and the routed arm has nothing to be compared against.
  Lifetime control range is 4/9–8/10.
- **Primary A** — the three create prompts route ARMED **≥9/10 each**. If the
  router does not arm an explicit create, nothing downstream is interpretable.
- **Primary B, the headline** — routed haiku grabs **0/10**, and it should be 0 *by
  construction*: a turn with no belt cannot call a tool.
- **Primary C** — routed create rates within **±2** of the control's, so routing is
  shown to cost nothing on the turns it correctly arms.

**What would falsify the reframing this lane rests on:** a routed haiku grab rate
that is NOT ~0. That would mean either the router misroutes composition far more
often than 200/200 says, or a belt-less turn can still emit a grab — and #214's
"the disease is largely an instrument property" conclusion, the reason this lane
exists at all, would be wrong. **Stated here so the result cannot be read
backwards.**

**Owed regardless of outcome:** every other battery wrapper is still unrouted, so
their numbers carry the same caveat. This lane fixes the action battery only; the
read-tool, motion, and destall wrappers each need the same treatment before their
rates can be called production rates.

### VERDICT FILED 2026-08-01 — run `F486F103`, corded @ whoGoesThere, debugger attached

80 trials, `endedCleanly: true`, **zero ERROR and zero TIMEOUT — no exclusions in
80 trials.** Reap `reminders=28 events=21 alarms=21 failures=0`; recorded creates
66 + 4 discarded warm-up artifacts = 70 reaped, **arithmetic exact.** `appBuild: 1`
is the corded signature; the proof of code identity is that `routed-production`
appears in `cells` at all.

**Instrument integrity first, since this lane is about the instrument:** all 40
routed trials carry `routeFailed: false` — not one `null` (which would mean the
field never landed) and not one `true`. **Every route below is a real
classification, not a fail-safe.** The hole #213 fell through was open here and
is now provably closed.

| bar | pre-registered | measured | |
|---|---|---|---|
| Gate | control haiku grabs ≥2/10 | **6/10** | PASS |
| Primary A | creates route ARMED ≥9/10 each | **10/10, 10/10, 10/10** | PASS |
| Primary B | routed haiku grabs **0/10** | **0/10** (p = 0.0108) | PASS |
| Primary C | routed creates within ±2 of control | **10/10 vs 10/10, delta 0** | PASS |

**All four bars pass. The falsification did not fire: #214's reframing is
CONFIRMED.**

**And the unregistered result is the bigger one.** #214 died on composition
content — the narrow belt took grabs to 0/10 and took clean haiku turns to 0/10
with it. Routing does not make that trade:

| | grabs | "I cannot write a haiku directly" | CLEAN haiku turns |
|---|---|---|---|
| `armed` (control) | 6/10 | 4/10 | **0/10** |
| `routed-production` | **0/10** | **0/10** | **10/10** |

**p = 1.08e-05** on clean turns. The control's ten haiku turns are six grabs plus
four disclaimer tics — **not one clean turn in ten.** The routed cell is ten
clean haikus, no tool calls, `cant=false` and `denial=false` on every one. The
belt was EMPTY on all ten, because the router classified them toolless 10/10.

**Why the 0/10 grab rate is not a behavioural claim:** a routed-toolless session
is constructed with no tools. A grab is a tool call. **It is arithmetically
impossible, not merely unlikely** — which is exactly what the pre-registration
said ("0/10 by construction") and why that bar was never the interesting one. The
interesting one was whether production pays for it in composition. It does not;
it is paid the other way.

**The thermal confound, and why it cannot explain this away.** The classifier
flags it correctly: control started `nominal` and ended `fair`; the routed cell
ran entirely at `fair`. That compromises any behavioural comparison — **but the
confound runs AGAINST the winner.** The routed cell ran in the hotter state and
still posted 10/10 clean against the control's 0/10 from the cooler one. A
confound that disfavours the arm that won cannot have manufactured the win.
Primary C is at ceiling in both arms (10/10 vs 10/10), so thermal has no room to
act there either. Replication at matched thermal state is still owed before this
is treated as a lifetime number.

**One thing routing did not fix:** the routed calendar cell shows
`currentLocation=1/10` against the control's 0/10 — a single spiral call on a
correctly-armed turn. n=1, inside noise, and precisely the residue #214 predicted
would survive: over-serving on turns the router CORRECTLY arms.

### What this means for the program — read this before starting another #200-series lane

**Production is already right on all four of these prompts: 40/40.** Three creates
at 10/10 and ten clean composition turns. The scoreboard that said "8/10 grabs,
composition broken" was reporting a configuration the app does not enter.

**So the grab disease and the disclaimer tic are BOTH instrument properties on
composition prompts** — not merely the grabs, which is all #214 claimed. Every
lane that treated either symptom on an unrouted battery was measuring a turn
production reaches only when the router says a device tool is needed.

**No promotion exists here, and that is the point.** `routed-production` IS
production; the cell measures what already ships. The finding is not "a fix
works," it is **"the instrument was wrong and the app was fine."**

**What is genuinely left** is unchanged from #214's prediction and is now the
whole of it: over-serving on turns that are CORRECTLY armed — #211's chaining,
the nine-`lookupContact` spiral, the single `currentLocation` above. Those turns
route armed in production, so their numbers were never inflated by this defect
and remain real.

### The same run also prices routing, and prices the residue — both unfiled until now

**What routing COSTS and what it BUYS,** median seconds and median input tokens
per turn, same run:

| prompt | unrouted | routed | delta |
|---|---|---|---|
| remind | 2.7s | 3.7s | **+1.0s** |
| alarm | 2.3s | 3.3s | **+1.0s** |
| calendar | 5.3s | 6.4s | **+1.1s** |
| haiku | 4.0s / 1,914 tok | **1.8s / 503 tok** | **−2.2s, −1,411 tok** |

**The router costs ~1s on a turn it arms and saves 2.2s plus 1,400 input tokens
on one it does not.** It pays for itself on composition and is cheap everywhere
else — the first time that trade has been measured rather than assumed.

**The residue, measured in production configuration:**

| prompt | calls/trial | tools called |
|---|---|---|
| remind | **1** | `createReminder` 10/10 |
| alarm | **1** | `scheduleAlarm` 10/10 |
| calendar | **3** | `createCalendarEvent` 10/10, `readCalendar` 7/10, `lookupContact` 7/10, `currentLocation` 1/10 |
| haiku (routed) | **0** | — |

**Remind and alarm are perfect: one call, one action.** The whole residue lives on
the calendar prompt, which spends **3 calls and 6.4s to do one thing** — a **+2.8s
tax** over remind, for two lookups whose results change nothing (creates are 10/10
with or without them).

**The nine-`lookupContact` spiral did NOT reproduce: zero same-tool repeats in 80
trials.** It is not "cured" on this evidence — one run cannot establish that — but
it is not the live problem, and a lane aimed at it would be aimed at a ghost. The
live problem is a fixed 2-call overhead, not a runaway.

**So the residual disease is a LATENCY defect, not a correctness one.** That is a
different lane from the one #214 anticipated, and it is worth saying plainly: the
creates were the thing we spent days on, and they are at ceiling.

**Owed:** replicate at matched thermal state.

**CORRECTION to this item's own owed list, made the same night.** It first read
"route the read-tool, motion, and destall wrappers before quoting any of their
rates as production rates." **That is wrong and would have cost device runs.**
This run's own data says routing is a **no-op on device-request prompts** —
creates were 10/10 in BOTH arms, because the router arms those turns anyway. The
read-tool and motion wrappers pass `promptSet`s that are entirely device
requests, so routing them cannot move a single number.

Routing matters for exactly one thing: a row the router would send TOOLLESS.
Today that is the **grab canary** (`includeGrabCanary: true`), which the spiral,
spiralfix, cardfix, datefix, calendar, deadend, grabfix and scopedv2 wrappers all
carry. **Those canary rows are the ones whose rates are not production rates** —
not the wrappers wholesale. The standing rule is in `CLAUDE.md` under
"Measurement discipline."

## 214. ✅ THE STRUCTURAL LANE: narrow belt CLOSED. Composition licensing falsified; the disease is partly an instrument property.

> **CLOSED — header flipped 2026-08-01 (Hermes audit Part 1A).** VERDICT FILED 2026-07-31 — narrow belt CLOSED, answered in both directions.

**FILED 2026-07-31. Dispatch `dispatch/OPUS-T27-214-scopedv2.md`, bars written
first. No production change — `armed-scopedv2` is a measured cell.**

**Why this and not another clause.** Every lane since #200 has treated an
EXPRESSION of one disease: the model over-serves when handed a full belt. Grabs
(#199), misroutes (#202), the lookup spiral (#200H), the searchConversations
spiral that blew the 8,192 ceiling (#200F), and today's chaining — motion question
→ `currentLocation` → `currentWeather` → `readHealth`, plus one trial spiralling
into **nine consecutive `lookupContact` calls**. Each fix was real and measured.
**None touched the cause, which is a ~12-tool belt on every armed turn.**

**The structural fix was already measured and it worked.** #200F, 2026-07-29:

| cell | haiku GRABS | calendar | haiku content |
|---|---|---|---|
| `armed` (control) | 4/9 | 5/8 | — |
| `armed-scoped` | **0/10** | 7/10 | **"cant" 10/10** |
| `armed-createonly` | **0/10** | **10/10** | **"cant" 10/10** |

Grabs to ZERO, calendar at a ceiling control never reached. Killed as a promotion
candidate by ONE thing: composition denial.

**What is new.** (1) Composition denial has its own measured cure — #196's
composition-licensing sentence, never applied to a narrow-belt cell. (2) Those
cells predate today's production: `createonly`'s remind 5/10 was held down by the
ask-stall and read-flee, and BOTH were fixed and promoted afterwards (#200S
optional schema, #200G find-first promoted the same day, #200O, #202, #202D).
**The combination has never been run.**

**The cell** rides `createonly`'s belt deliberately — #200F's own
createonly-vs-scoped delta showed removing the same-domain read converts half the
stalls into creates, and the other half was ask-interrogation, which find-first now
kills. Belt equality with `createonly` is PINNED
(`scopedv2NarrowsExactlyLikeCreateonly`) so the lane cannot silently stop being the
comparison it claims to be, and a regression to identity cannot turn it into a
no-op that still passes.

**Bars:** gate — control grabs ≥2/10 (lifetime 4/9–5/10). Primary A — treatment
grabs ≤1/10. **Primary B, the promotion-killer — treatment haiku content clean
≥8/10**, the bar that failed at 0/10 last time and the entire reason the lane
exists. Primary C — remind ≥8/10 and calendar ≥8/10, so the create path is not
traded away.

### VERDICT FILED 2026-07-31 — run `1835BBF9`, corded @ whoGoesThere, debugger attached

80 trials, `endedCleanly: true`, reap `reminders=30 events=21 alarms=21 failures=0`,
backstop ZERO leftovers. **Zero ERROR, zero TIMEOUT — no exclusions in 80 trials.**
(`appBuild: 1` is the corded signature: `ota-stage.sh` stamps the commit count,
a direct Xcode build uses the project default. The proof of code identity is that
`armed-scopedv2` appears in `cells` at all.)

| bar | pre-registered | measured | |
|---|---|---|---|
| **Gate** — control shows grabs | ≥2/10 | **8/10** | HOLDS |
| **Primary A** — treatment grabs | ≤1/10 | **0/10** | **HOLDS** |
| **Primary C** — create path | remind/calendar ≥8/10 | **10/10 / 10/10** (alarm 10/10) | HOLDS |
| **Primary B** — haiku content clean | ≥8/10 | **0/10** | **FAILS** |

**The narrow belt does NOT promote.** Per pre-registration, B is the
promotion-killer and it failed at the floor.

**The belt kills grabs outright and kills composition with them.** 8/10 → 0/10
grabs, and 8/10 → 0/10 poems. Control wrote verse in 8 of 10 (twice while ALSO
grabbing — "I've set a reminder for you to write a haiku… Here's"). The treatment
refused all ten, explicitly: *"I do not have the capability to create creative
content like poetry"*, *"I am an AI model developed by Apple, and I do not create
creative content"*, *"I cannot write a haiku without external tools"*.

**The licensing hypothesis is falsified with unusual force. The cell carried TWO
layers of explicit licensing and denied anyway:** production's own capabilities
line already says *"writing and composing … are your job and need no tool"*, and
#196's composition sentence was added on top (wiring verified — the case sits
third in the switch with no earlier catch-all, and the flag reaches the `hasTools`
branch). **A narrow belt overrides explicit prose licensing completely.** The
model reads the BELT as its job description, exactly as the #176B/#194 comment
says — and the clause written to prevent that does not survive belt narrowing.

### The finding that outranks the verdict: the disease is largely an INSTRUMENT property

**The action battery does not route** (`runActionBattery`: "NO per-trial routing").
Every trial is armed by construction. But **"Write a haiku about sledding" is a
baseline router row with `expected: false`, on a 200/200 series** — in production
that turn routes TOOLLESS, gets an EMPTY belt and the licensed bare branch, and
composes fine.

**So the 8/10 control grab rate measures a configuration production does not
use.** #204 already filed this caveat — "grabs are an instrument property, the
action battery does not route" — and **I did not apply it when designing this
lane.** That is the mistake here: not the wiring, not the bars, but treating a
known instrument artifact as the disease to be cured.

**What survives as real:** over-serving on turns that are CORRECTLY armed — the
#211 chaining (4/9 motion questions pulling in location/weather/health) and the
nine-consecutive-`lookupContact` spiral. Smaller, different, and not addressed by
belt size.

**Consequence for the program:** the local brain is in better shape than the
battery scoreboard implies, because the battery deliberately measures the
un-routed worst case. The router (#202, promoted) is doing the work the narrow
belt was proposed to do — and doing it without costing composition.

**Falsification, stated in advance.** Clears A and C but fails B ⇒ composition
licensing is insufficient, the narrow belt is dead as a general shape, and the
honest remaining option is a PRODUCT decision to ship fewer tools, not another
clause. Fails A ⇒ belt size is not the mechanism, #200F's 0/10 was
baseline-specific, and the over-serving disease needs a different theory entirely.
**Either outcome closes the question, which is the point of running it.**

## 213. ✅ the router probe could not record an error, and scored the fail-safe as CORRECT

> **CLOSED — header flipped 2026-08-01 (Hermes audit Part 1A).** FILED AND FIXED 2026-07-31; instrument re-verified 2026-08-01 (13/13 sites carry `errors:`).

**FILED AND FIXED 2026-07-31. Instrument integrity; no production behaviour change.**

`routeNeedsDeviceTool` catches everything and fails safe to `armed` — **correct for
a live turn**, and not changed here. But `RouterProbeRecord` had no error field, so
the probe could not tell that a generation threw. On a row with `expected: true`
the fail-safe MATCHED the expectation and was counted **correct**.

**Five of the ten baseline rows are `expected: true`.** So half the 200/200 series,
#202A's 6/6, and the image grid could not distinguish "the router judged right"
from "the router died and fell back."

**Why no filed verdict is believed wrong.** The other five rows are an accidental
control: on `expected: false` a failure scores as a MISS, and they sit at 100/100.
That bounds the real error rate near zero. **Nobody chose that safeguard** — it was
luck, and luck is not a measurement.

**Fixed:** a DEBUG-only `routerFailureTally`, sampled as a delta around each probe
row, recorded as `RouterProbeRecord.errors` and emitted in the `router:` grammar.
`errors == nil` means the run PREDATES #213, not zero — the classifier reports
pre-#213 runs as "NOT RECORDED" rather than counting them clean, and flags any
`expected: true` row with a nonzero count as **INFLATED**, instructing that its
correct-count be reduced before any bar is read.

**Honest scope:** this records failures from now on. It cannot retroactively clean
the existing 200/200 history — those runs simply do not contain the information,
and the classifier now says so out loud instead of implying they were clean.

### COVERAGE GAP FOUND BY EXTERNAL AUDIT, fixed 2026-07-31 (Hermes §3.1)

**The first cut wired ONE of four probe runners, and the commit message claimed
"each probe row".** That was my overstatement. Three runners still scored a router
throw as a correct answer on `expected: true` rows — and the worst of them is
`runRouterProbe`, **the legacy #196 probe whose 200/200 series the program quotes
as its baseline gate**; also `runImageRoutingProbe` (the instrument #207's
promotion ran on) and `runLongContextProbe`.

All four runners now sample the tally: **10 of 10 `recordProbe` call sites carry
`errors:`**. The deterministic lenrule row passes an explicit `errors: 0` — it runs
no generation and cannot throw, and nil there would have read as "not sampled",
the one thing it is not.

**COUNT UPDATE 2026-08-01 — now 13 of 13, and that is the evidence that matters.**
The "10 of 10" above was true when written; the number has moved twice since as
new probe runners landed (`runIntentRouterProbe` in the #217 lane, then the
#217B cells), **and every new call site carried `errors:` without being told to.**
For a source-level invariant no test can reach, holding across the next runners
added is the only evidence obtainable — a fixed count would just mean nobody had
tested it. Do not re-quote a bare number from this entry; count it:
`grep -rn "recordProbe" Talaria --include="*.swift"`. The two test-only sites in
`DeviceToolBeltTests` deliberately omit `errors:` — they pin nil = "not recorded"
decode semantics for legacy runs, and are not part of this count.

**The honest limit:** this is a SOURCE-LEVEL invariant that no test reaches. A new
probe runner added without sampling would silently reintroduce the gap. The
defence is a stated invariant on `RouterProbeRecord.errors` plus the classifier's
"NOT RECORDED" line, which reports unsampled rows rather than counting them clean.
**An external reader found this because the instrument's own claim was wider than
its wiring — the third consecutive audit to catch something at a boundary the
author had just worked on.**

## 212. ✅ WeatherKit returned nothing, 0/40. ROOT CAUSE FOUND AND FIXED 2026-07-31: the App SERVICE was never enabled.

> **CLOSED — header flipped 2026-08-01 (Hermes audit Part 1A).** CLOSED END TO END 2026-07-31 — 40/40 real forecasts.

**FILED 2026-07-31 from run `01FA0ECC` (build 1600, OTA Debug). NOT fixed.**

Every one of 40 `currentWeather` trials — both cells, bare and named place — failed
to produce a forecast. The tool was CALLED successfully each time; WeatherKit
itself failed, and the replies are the tool's own catch-all
(`"Weather lookup failed: … WeatherKit needs a network connection and the app's
WeatherKit capability."`).

**UPDATE 2026-07-31 — the profile hypothesis is REFUTED, and the record could not
answer the question.**

Signing is correct at EVERY layer, checked on the shipped artifact rather than the
source: `project.yml:56`, `Talaria/Talaria.entitlements`, the **signed binary**
(`codesign -d --entitlements` on `Talaria27.ipa` → `com.apple.developer.weatherkit
=> true`), and the **embedded provisioning profile**, which is the portal-side
grant and is valid to 2027-07-27. **So it is not the profile and not the App ID.**
My filed guess was wrong.

**What blocked the diagnosis: `BatteryToolCallRecord` never recorded what a tool
RETURNED** — only that it ran and what it was asked. The tool's own catch had
WeatherKit's `localizedDescription` in hand and the record kept only the model's
paraphrase. **Same blindness class as #209's buried cause, found twice in one
day.** Fixed: `ToolEventRelay.completed(_:result:)` records the tool's answer into
the battery store only — never the transcript, so it cannot leak internals the way
#197's dump did. Wired on the read tools first; `result == nil` means NOT CAPTURED,
never "empty".

### RESOLVED 2026-07-31 — the WeatherKit **App Service** was never enabled

**Root cause: `Capabilities` and `App Services` are two separate lists on the App
ID, and WeatherKit appears in BOTH.** The Capabilities entry was ticked — that is
what puts `com.apple.developer.weatherkit` into the provisioning profile and the
signed binary, which is why every entitlement check passed. The **App Services**
entry ("Access the Apple Weather service") was **unticked**, so the app was never
authorized against the service and the JWT authenticator refused every token.

It explains the entire evidence set at once: entitlement present at all four
layers, plan provisioned with a 500k quota, **0 calls ever used**, and a
`WDSJWTAuthenticatorServiceListener.Errors Code=2` with a NULL description.

**Owen ticked it; the raw probe returned `OK — Partly Cloudy, 88.66°F` on the
ALREADY-RUNNING build with no rebuild.** The grant is server-side, so the profile
and binary were never the problem and never needed regenerating.

### CLOSED END TO END 2026-07-31 — 40/40 real forecasts (addendum filed 2026-08-01)

**The read-tool battery that the "Still owed" paragraph below asks for was run,
and it returned `40/40` real forecasts** — the exact inverse of the 0/40 that
opened this item. Recorded in PR #206's body, which also banked two free
confirmations from the same run: #198's MapKit `MKGeocodingRequest` migration
exercised on device, and #209's optional-`place` path working.

That closes the gap the paragraph below correctly identified: the raw probe only
proved WeatherKit works *for this app*, not that `currentWeather` works through
the location provider + geocode + optional-`place` schema. It now has.

**Why this addendum exists, and it is the more useful half:** the 40/40 was
recorded in a PR body and **never written back here**, so from 2026-07-31 until
the 2026-08-01 external audit (§3) caught it, the system of record said an
end-to-end proof was outstanding that had already been obtained. A PR body is not
the tracker. **A result that closes an item closes it HERE, in the same session
it lands** — otherwise the next reader inherits a false open question, which is
the same class of failure as #209's buried cause and this item's own erased
diagnostic, just displaced into the documentation layer.

### The process failures this item cost, recorded because they are the point

**1. I found it four hours earlier and talked myself out of it.** The first DOM
query on the App ID page returned exactly this row — `checked: false`, text
"WeatherKit … Access the Apple Weather service." I re-queried more precisely, got
the *Capabilities* row at `checked: true`, and announced the first query had been
"a bad DOM selector." **It was not.** It had found the App Services row on a
hidden tab pane. Two queries, two different rows, both correct — and I retracted
the true one because the second felt more authoritative. **I never asked whether
they were looking at the same thing.**

**2. I stopped at "not our code" instead of searching.** After the raw probe
exonerated Talaria I concluded the search space was exhausted and recommended
support channels. Owen pushed back — *"that seems like a copout"* — and a single
web search returned the answer in the first result: the App Service is enabled
separately from the capability. **Thirty seconds of search after four hours of
inference.** "I have ruled out everything I can inspect" is not the same as "this
is unknowable", and treating a symptom as unique when it is a common, documented
setup error is a failure of curiosity, not of evidence.

**3. The honest-failure message erased the diagnostic** (recorded above) — the
fifth instance that day of a fix disabling its own instrument.

**Still owed** — **NO LONGER OWED; see "CLOSED END TO END" above. Kept verbatim
because the gap it names was real and correctly scoped.** The raw probe proves
WeatherKit works for this app. It does NOT prove `currentWeather` works end to
end — the tool path adds the location provider, the #198 MapKit geocode, and the
optional-`place` schema. A read-tool battery run is what closes that.

### DIAGNOSED 2026-07-31 — run `FA4947E7`, build 1606: the service rejects our token

The capture worked on its first run. **40 of 40 `currentWeather` calls returned the
identical error:**

```
Weather lookup failed: The operation couldn't be completed.
(WeatherDaemon.WDSJWTAuthenticatorServiceListener.Errors error 2.)
```

**WeatherKit's JWT authenticator rejected the app's token.** Read with the signing
evidence — entitlement present in the signed binary AND the provisioning profile —
this is a service-side AUTHORIZATION failure: the token is being rejected, not
omitted. It is not network (the same runs answered `readHealth` correctly, on a
build installed over the network minutes earlier) and not a missing capability.

**The remaining question is account-side and belongs to Owen, not the code:**
WeatherKit service enablement for this App ID, propagation delay after enabling, or
the account-level WeatherKit agreement. Which of those it is cannot be determined
from the device, and this item should not guess between them a second time.

**Fixed in code (the honest-failure part, #202D's rule):** the tool's message used
to blame "a network connection and the app's WeatherKit capability" — **both
verifiably fine**, sending the reader to check two things that are not broken.
An authenticator failure is now named as such and marked as not-retryable;
everything else reports the underlying description without inventing a cause.

**Instrument note:** this is the first question the #212 tool-result capture
answered, and it answered it on the first run. The cause had been produced 40 times
already and discarded 40 times.

### BILLING HYPOTHESIS FALSIFIED 2026-07-31 — run `3E53397E`, card updated first

Owen updated the expired card; the app was redeployed corded from `main`; the
read-tool battery re-ran. **Still 40/40 failures.** The expired payment method was
the only anomaly on an otherwise clean account — agreements both accepted (DPLA
July 5 2026), WeatherKit capability enabled on `org.aethyrion.talaria27`, plan
present with 500k quota and 0 used — and it was **not** the cause.

**Remaining candidates, none yet distinguishable:** propagation delay from the card
change, a service-side registration that never completed despite the capability
being set, or something account-wide that a Talaria-only test cannot separate.
**Next honest step is a minimal WeatherKit probe OUTSIDE Talaria** — if it fails
there too, it is the account, not the app, and no amount of Talaria work will move
it.

### AND MY FIX BLINDED THE INSTRUMENT THAT DIAGNOSED IT

The honest-failure rewrite made `currentWeather` return *"the weather service
rejected this app's credentials"*. That string is what `relay.completed(result:)`
captured — so the raw `WDSJWTAuthenticatorServiceListener` text went from **40
occurrences in run `FA4947E7` to ZERO in run `3E53397E`**. The verification run
could not have confirmed or refuted anything about the underlying error, because
the fix for the USER had erased the record for the INSTRUMENT.

**This is the fifth instance of today's recurring failure — something built
quietly disabled the thing meant to check it — and the first one I committed
AFTER cataloguing the other four.** Cataloguing a failure mode is not the same as
being immune to it.

**Fixed:** `lookup` now returns `(answer, diagnostic)`. The reply stays sanitised;
`relay.completed(result:)` always carries the raw text. That divergence is correct
by construction — the battery store is not a transcript (#197), so the constraint
that forbids leaking internals to the user is exactly what LICENSES recording them
here. **Any tool that sanitises its output must pass the unsanitised text to the
recorder, or it silently unmakes #212.**

**Why it went unnoticed:** no battery has ever called a READ tool (#209), so
`currentWeather` had never been exercised end-to-end by any instrument. It may have
been broken for a long time. The phone had network throughout — the same build
installed over Tailscale and `readHealth` answered correctly in the same minutes.

## 211. ✅ "How many steps have I taken today?" was answered WRONG 20/20. PROMOTED, 0/10 → 10/10.

> **CLOSED — header flipped 2026-08-01 (Hermes audit Part 1A).** PROMOTED 0/10 → 10/10; follow-on CLOSED 2026-07-31. **Read-path offer shape is now lane #211A.**

**VERDICT FILED 2026-07-31. Run `63C0EF12`, build 1602, `endedCleanly: true`,
reap `0/0/0` (read tools write nothing). Dispatch:
`dispatch/OPUS-T27-209-required-fields.md` (#211 addendum, bars written first).
PROMOTED — `MotionTool.productionDescription` no longer claims steps;
`armed-motionrollback` is the pinned control.**

| bar | pre-registered | measured | |
|---|---|---|---|
| **Gate** — control reproduces the disease | ≤2/10 step numbers | **0/10** | HOLDS |
| **Primary** — treatment returns a step count | ≥8/10 | **10/10**, all via `readHealth` | HOLDS |
| **Guard** — motion questions still reach `readMotion` | ≥8/10 | **9/9 valid** | HOLDS |

**Fisher exact two-tailed p = 1.08e-05.** Excluded and listed: 1 trial,
`armed-motionrollback/motiondirect t3`, TIMEOUT. Zero errors.

**Secondary, unbarred:** the offer-instead-of-act replies vanished — control
`stepsdirect` offered on **4/10** ("Would you like to check your steps for another
day?"), treatment **0/10**. Evidence that this instance of the #202-family shape
was DOWNSTREAM of tool choice, not a separate disease.

**The cost, recorded because it is real:** the treatment arm chained extra tools on
motion questions — **4 of 9** valid trials vs **0 of 10** in control. `t9` went
`readMotion → currentLocation → currentWeather → currentWeather` and injected
#212's weather failure into an answer about standing still; `t10` chained into
`readHealth` and appended an unasked-for health summary; `t6`/`t8` volunteered a
street address for a question that asked neither where nor whether. **Answers
stayed correct, so no bar broke** — but it is slower, chattier, and discloses
location nobody asked for. **This motivates the redirect cell deliberately NOT
built here**: naming what the tool is *for* may restore the confidence that
scoping removed. That is now an evidenced next lane, not a guess.

**FOLLOW-ON VERDICT FILED 2026-07-31 — CLOSED, hypothesis falsified and REPLICATED.
Runs `6AAA4AC4` (19:29) and `328502AD` (23:20), corded @ whoGoesThere, debugger
attached; both `endedCleanly`, zero exclusions across 80 trials.**

| bar | pre-registered | run 1 | run 2 | pooled | |
|---|---|---|---|---|---|
| Gate — control chains | ≥2/10 | 5/10 | 5/10 | **10/20** | HOLDS |
| **Primary** — treatment reduces it | ≤1/10 | 4/10 | 5/10 | **9/20** | **FAILS** |
| **Guard** — `stepsdirect` survives | ≥8/10 | 10/10 | 10/10 | **20/20** | HOLDS |

**Fisher exact two-tailed, pooled: p = 1.000.** Not a small effect — none.

**The hypothesis was wrong.** The reading was that scoping the description removed
the model's sense of what `readMotion` is FOR, so naming the boundary would confine
it. The chains say otherwise: they run `readMotion → currentLocation →
currentWeather` in BOTH arms. **The model is not confused about the tool — it is
building an unsolicited context report**, and a sentence about which tool owns
health metrics has no purchase on that.

**What the lane DID establish, and it is worth more than the verdict: #211's
promotion is robust.** `stepsdirect` answered 10/10 in three independent runs
across three builds — the promotion run plus both of these. The no-"step" wording
constraint held every time.

**RECORD-KEEPING FAILURE, logged because it is the point of this file:** run 1 was
scored on 2026-07-31 at 19:29, announced in conversation, and **never written
here** — the item still read "unrun" while two runs existed, and the second run was
launched under the belief that the lane was untouched. That is the #190
ghost-blocker shape, self-inflicted, four hours after correcting two other stale
headers. **An unfiled verdict is an unmade measurement.** The accident produced a
replication, which is luck, not method.

**Superseded note (kept for the record):** `armed-motionredirect` = the promoted text
plus one sentence, "For health metrics, use readHealth." **It deliberately does
NOT say "step".** The obvious phrasing — "for step counts, use readHealth" —
would reinstate the exact phrase whose presence caused the 0/10 misroute, which
is the confound the belt test caught in the first draft of the scoped text. The
redirect therefore points by DOMAIN, never by metric, and a test pins both that
constraint and that the text is the promoted description PLUS a sentence rather
than a third rewording.

Bars pre-registered in the dispatch: gate ≥2/10 chaining in control (measured
4/9); primary ≤1/10 chaining in treatment; **guard — `stepsdirect` must still
answer ≥8/10 in the treatment arm, and if the boundary sentence re-breaks #211's
win the cell does not promote regardless of what it does for chaining.** A fix
that trades a 10/10 answer for a tidier tool trace is a regression wearing a
win's clothes.

**Honesty note on the numbers:** all ten treatment replies are byte-identical
("You've taken 3,116 steps today."). Control replies varied in wording, so
sampling is stochastic — the uniformity is a low-entropy factual answer, not
determinism. Tool CHOICE is what the bars measure. The step count also coheres
across runs: 1,889 at 10:33, 3,116 at 17:33 the same day.

### The original filing

**FILED 2026-07-31 from run `01FA0ECC`. User-facing, deterministic.**

The most natural health question the app can be asked returns **no step count at
all — 0 of 20 trials produced a number** — while `readHealth` reported **1,889
steps in the same minute**.

**Mechanism: two tools advertise the same capability.**

| tool | description | args |
|---|---|---|
| `readMotion` | "Read **today's step count** and the user's current motion activity…" | `{}` — none |
| `readHealth` | "…**steps today**, active calories today, latest heart rate…" | `metric` |

The model picks `readMotion`, `CMPedometer` has no samples, and the turn reports
"no pedometer data" while HealthKit holds the answer.

**#209 already eliminated the obvious explanation.** If empty-schema friction drove
the choice, making `metric` optional should have shifted it. It did not move:
`readMotion` 10/10 in the promoted arm AND 10/10 in the required-field rollback.
**Description overlap drives the choice, not schema friction** — a measured
elimination, and the one thing that run established cleanly.

**Second-order finding:** several replies OFFER the right tool without calling it
("Would you like to check your health data for other metrics?"). That is the
#202-family offer-instead-of-act shape appearing on a READ path, where no
confirmation gate exists to excuse it.

**Unlike #209, this IS battery-measurable** — the effect is 0/20, not 1.4%. The fix
belongs in a measured cell with a real bar.

## 209. ✅ "ERROR" was never one disease: five mechanisms behind one excluded label

> **CLOSED — header flipped 2026-08-01 (Hermes audit Part 1A).** PR #199 — '#209 measured and closed'. `RequiredPropertyDecodeTests.swift` verified in tree.

**OPENED 2026-07-31. Instrument-only so far; no production change, no device run.**

Every battery since #196 has excluded ERROR trials from rates under a single
undifferentiated label, printing only the trial NUMBER and never the text. The text
was in the record the whole time — `endTrialError` stores `String(describing: error)`
in full, and only the Console emit truncates to 200 chars. Recovering the strings
from pasted classifier output shows **at least five distinct mechanisms**:

| bucket | verbatim | note |
|---|---|---|
| A | `Encountered content that cannot be completed into valid JSON Text: {"term":"Sam"Sam"}<ctrl43>` | GENERATION corruption — doubled fragment + leaked control token |
| B | `Provided 8,529 tokens, but the maximum allowed is 8,192.` | the **INPUT** ceiling; #208 falsified the OUTPUT cap, never this |
| C | `Insufficient system resources (7)` | device pressure |
| D | `ToolCallError(tool: Talaria.DeviceHealthTool(…` | cause buried, see below |
| E | `Error Domain=FoundationModels.LanguageModelError Code=-1` | undifferentiated |

**MEASURED 2026-07-31, and the first retraction below was ITSELF wrong — see the
"pooled over 48 runs" section further down, which is the authoritative one.**

**Two of my own claims retracted in the course of opening this item.**

1. ~~**The optional-field hypothesis was WRONG and was killed before it was
   built.**~~ **THIS RETRACTION IS RETRACTED.** It rested on bucket A's corrupt
   JSON, which the pooled data then showed is **1 occurrence in 108**, while
   bucket D is **13 of 13** missing-required-property. The original hypothesis was
   right. Generalising from the first sample seen is the same small-n error the
   batteries exist to prevent — made here in prose, where no bar could catch it.
2. **"D's cause is structurally absent" was WRONG.** Verified against the beta-4
   swiftinterface: `LanguageModelSession.ToolCallError` is a struct with TWO stored
   properties, `tool` and `underlyingError`, so `String(describing:)` reflects both.
   The cause has been in every record all along — rendered LAST, after a ~500-char
   dump of the live tool instance (the same dump that leaked in #197). Every console
   emit, grep and eyeball stopped short of it. **It also conforms to `LocalizedError`
   with an `errorDescription` we have never used.** No capture change is needed and
   no device build: this is a printing problem.

**Shipped:** `classify-battery-run.py` buckets every excluded trial by mechanism,
prints the cause in full, and digs the `underlyingError` tail out of D-bucket dumps
(discarding the tool noise). Verified against verbatim strings only — never invented
ones, the rule that caught the curly apostrophe and the passive voice. Rates, reap
arithmetic and exclusion semantics are unchanged.

**Owed / honest limits.**
- **The D extraction path is UNVERIFIED against real data.** No complete
  `ToolCallError` string survives anywhere on this machine — every capture was
  truncated. The script now says so per-row rather than showing nothing.
- **n=15 is far too small to rank these.** The recovered counts are a lower bound
  from pasted output, not a census; the raw run JSONs live on the phone. **Do not
  prioritise A/B/C/D/E by these numbers.** One battery with the new classifier gives
  the real frequencies.
- **Bucket B is the one that names a production-facing mechanism.** Production
  guards context overflow with condense-and-retry-once (#26,
  `LocalChatBackend.swift:514`), yet a run recorded 8,529 tokens escaping it —
  either the battery path bypasses the guard or condensation fell short. Unmeasured.

### POOLED OVER 48 RUNS (2026-07-31) — the authoritative numbers

The phone only retains 10 runs (`BatteryRunStore.maxRuns`), and the error-carrying
ones had aged out. **The Messages attachment store had all 48 ever sent** — nothing
needed re-exporting. Owen's question is what recovered the dataset.

**3,578 trials, 108 errors (3.02%), 10 timeouts.** One run (`20260728-194237`)
errored on **81 of 139** trials, all bucket E — a run where the model service died,
not a sample of normal failure. Reading composition through it is the cold-start
mistake again, so both columns are given:

| bucket | all 48 runs | excluding the broken run |
|---|---|---|
| **D** missing required property | 12.0% | **48.1%** |
| E LanguageModelError | 80.6% | 22.2% |
| F unclassified | 2.8% | 11.1% |
| B input overflow | 1.9% | 7.4% |
| C resource pressure | 1.9% | 7.4% |
| A JSON corruption | 0.9% | 3.7% |

**Every one of the 13 D causes is a missing required property**, and
`underlyingError` was present on **13 of 13** — the SDK reading is confirmed
against real data, and the extraction path is no longer unverified:

| property | tool | n | content emitted |
|---|---|---|---|
| `metric` | `DeviceHealthTool` | 5 | `{}` |
| `title` | `ReminderCreateTool` | 4 | `{"due": …, "list": ""}` |
| `place` | `WeatherTool` | 2 | `{}` |
| `title` | `CalendarEventTool` | 1 | `{}` |
| `durationMinutes` | `CalendarEventTool`**`RequiredFields`** | 1 | the pinned ROLLBACK cell |

**That last row is a natural experiment already in the data.** The required-fields
calendar twin threw the error its promoted counterpart structurally cannot, because
#200X made exactly that field optional. **#200X is vindicated on a mechanism its
rate evidence never touched — and a rollback twin turns out to be a control arm,
not just a revert.** That is now the stated reason to keep building them.

**`currentWeather` was a documented CONTRADICTION.** Its `@Guide` has said
"Optional… Leave empty for the user's current location" since it shipped, while the
type said required. The model obeyed the prose, emitted `{}`, and the turn died.
Week-plan finding 3 in its purest form: when behaviour resists an instruction, look
for a structural constraint saying the opposite.

### VERDICT 2026-07-31 — read-tool battery `01FA0ECC`: **INCONCLUSIVE**, gate failed

Run `01FA0ECC`, build **1600**, `endedCleanly: true`, reap `0/0/0` (read tools write
nothing). 80 trials, `[armed, armed-fieldrollback]` × 4 prompts × 10.

**The pre-registered evaluability gate FAILED: the rollback arm showed 0 of 20
missing-property errors on the bare prompts, against a gate of ≥3.** Per the
dispatch, no comparison is reported. The primary bar (production shows zero) held
but **VACUOUSLY** — the rollback showed zero too, so it evidences nothing.

**Why the provocation design failed, and it is a real correction: a required
`String` is satisfied by `""`.** The lane assumed a model with no value available
would emit `{}`. It does not — it emits an empty string, which decodes fine.
Omitting the KEY is a generation glitch, not a rational response to a bare prompt,
so **no prompt design provokes it.** "Provoke the condition rather than lower the
bar" was sound in principle and built on a wrong model of the condition.

**Consequence: this failure class is probably not battery-measurable by ANY prompt
design, and `RequiredPropertyDecodeTests` is the only honest instrument for it —
which is what the original no-efficacy-bar reasoning concluded before the addendum
talked itself out of it.** The change stands on the decode tests and on the
structural argument, not on a rate.

**What the run DID establish**, and it is not nothing: the promoted and rollback
arms behaved identically on tool CHOICE, which eliminates schema friction as the
driver of the #211 misroute. It also surfaced #211 and #212, neither of which any
instrument had ever been positioned to see.

**This disease is NOT battery-measurable, and no bar should pretend otherwise.**
Conditional rates: worst cell `armed/haiku` **5/350 = 1.4%**; pooled by prompt,
haiku 0.92%, calendar 0.53%, remind 0.13%, alarm/norway/canary 0.00%. At n=30 an
arm expects 0.4 hits and will read zero either way. Writing an efficacy bar here
would be the #201 mis-specification a fifth time — a gate above the disease's own
rate. **The guarantee is structural, so the proof belongs in a test, not a battery:**
`RequiredPropertyDecodeTests` replays the exact recorded payloads and pins that each
promoted schema accepts what its rollback twin still refuses.

## 207. ✅ image turns: the signal alone does NOTHING, the guide fixes it completely

> **CLOSED — header flipped 2026-08-01 (Hermes audit Part 1A).** CONFIRMED AND PROMOTED 2026-07-31.

**VERDICT FILED 2026-07-31. Run `C2E03F53`, n=10, `endedCleanly: true`. Dispatch:
`dispatch/OPUS-T27-207-image-routing.md`. NOT PROMOTED — one collateral band was
missing and is now built.**

| arm | image rows ARMED | #196 baseline |
|---|---|---|
| **img-none** (production) | **1/4** | 100/100 |
| **img-signal** (marker only) | **1/4** | 100/100 |
| **img-guide** (marker + guide) | **4/4** | **100/100** |

**REPRODUCTION GATE HOLDS:** production routes 3 of 4 image prompts toolless. The
one exception is *"scan this barcode"*, armed 10/10 in every arm — **"scan" is a
device verb the router already knows**, so the defect is specific to the *reading /
vision* phrasings a user would actually type with a photo.

**PRIMARY FAILS: the signal alone changes NOTHING — 1/4, byte-identical to
production.** Telling the router `[an image is attached]` moved zero rows. The cheap
seam I hoped would suffice does not.

**SECONDARY PASSES: img-guide is 4/4 with the #196 baseline untouched at 100/100.**

**THE TWO SEAMS ARE NOT INDEPENDENT — they are one mechanism in two places, and the
run makes that obvious in hindsight.** The guide example teaches `marker → armed`;
the signal supplies the marker. Neither works alone: the signal without the guide is
an unexplained token (1/4, measured), and the guide without the signal would teach a
pattern that never appears (predicted, untested). **So the promotion candidate is the
PAIR, which is exactly what `img-guide` is** — but the dispatch's parsimony rule
("if the signal clears it, the guide is not promoted") turned out to be unreachable
rather than merely unmet.

**WHY IT IS NOT PROMOTED: a collateral band was missing, and it is the degenerate
direction.** The fix marks **every** prompt when an image is attached, and the guide
teaches marker → armed. **Nothing in the grid covered "photo attached, request
unrelated to it"** — the shape where this would over-arm, which is #196's disease.
Two rows now added (`write a haiku about sledding`, `what's 2+2?`, both expected
TOOLLESS, both carrying the image signal) and run on all three arms. **Same class of
gap as #206's confounded rows and #205's appended baseline: I keep building grids
that cannot see the failure mode the change introduces.**

**DETERMINISM:** zero within-row variance across all 42 rows — greedy decode again.
The honest denominator is **4 image rows + 10 baseline rows per arm**, not 140
trials, and the bars were written in rows for that reason.

**CONFIRMED AND PROMOTED 2026-07-31 — run `64DC6275`, a strict superset of the
first (same rows plus the missing band). Suite 1379/1379.**

| band | img-none | img-signal | **img-guide** |
|---|---|---|---|
| image (want ARMED) | 1/4 | 1/4 | **4/4** |
| **image-wordsonly (want TOOLLESS)** | 2/2 | 2/2 | **2/2** |
| #196 baseline | 100/100 | 100/100 | **100/100** |

**The degenerate did NOT happen.** A photo carried alongside an unrelated request —
"write a haiku about sledding", "what's 2+2?" — still routes **TOOLLESS 2/2** under
the fix. That was the band the promotion rested on, and it was missing from the
first grid.

**Every number replicated exactly** across the two runs: img-none 1/4, img-signal
1/4, img-guide 4/4, baseline 100/100. **Two clean runs, so the standing "one clean
run does not promote" rule is satisfied.**

**PROMOTED — the PAIR, because neither half works alone:**

1. **`hasImage` is hoisted ABOVE the router call and passed in.** It used to be
   computed six lines BELOW and never handed over, which is the whole defect.
2. **`productionIncludesImageGuide = true`** — one added `@Guide` example teaching
   that an attached image is a device request.

**Rollback: the flag's `false`**, which restores the pinned `@Guide` byte-for-byte
and is reachable as the measured `img-signal` cell. Pinned by a test asserting the
shipped text is exactly what the `img-guide` arm ran, and that a turn with no image
is untouched.

**END-TO-END CONFIRMED ON DEVICE 2026-07-31, and it is the cleanest A/B this program
has produced.** Same prompt, same image, same handset, three minutes apart:

- **19:58, pre-fix build:** no tool chip. *"I can't see the image you've attached, so
  I can't read what's on it."* — the transcript placeholder's own instruction,
  followed faithfully. **This is what 0/4 looks like to a user.**
- **20:01, promoted build:** **`READIMAGETEXT` chip fires**, and the full text comes
  back accurately — including the struck-through "Moscow Washington", which OCR read
  faithfully rather than dropping.

**This closes the #202A→#202B gap for this lane.** #202A measured routing and looked
perfect; #202B then found the outcome was a lie. Here the outcome was verified
directly, and a thirty-second manual check answered what an instrument would have
cost a lane to build. **Worth generalising: when the user path is one tap, check the
user path.**

**Incidental datum:** OCR was accurate on the hard case — small text, dark
background, a photo of a screen. Vision quality is not a concern for this shape.

**Note on the pre-fix screenshot, because it nearly caused a wrong reading:** the
build on the handset at 19:58 predated the promotion commit (19:33 deploy vs 19:49
commit). Had that been read as "the fix failed" rather than "the fix isn't installed",
the lane would have chased a phantom. **Check what is actually deployed before
reading a device result** — the same discipline as asserting the compiled path.

**Standing note for the next router lane:** "scan this barcode" armed 10/10 in every
arm including production — **"scan" is a device verb the router already knew.** The
defect was always specific to reading/vision phrasings, and a grid built only from
verbs like "scan" would have found nothing.

## 206. ✅ ctx-a BREAKS at ~4,000 chars of context, and my "no truncation needed" verdict was wrong

> **CLOSED — header flipped 2026-08-01 (Hermes audit Part 1A).** Verdict corrected and re-stated, kept on the latency basis. Residual row set is device-list C2.

**Filed 2026-07-30 from run `5BB1C020`. This CORRECTS the #202C verdict filed
earlier the same day, which said long context "costs the router nothing" and
"truncation is NOT part of the ctx-a promotion". That was measured at ~590 chars
and does not survive contact with a realistic turn.**

| context | latency | accept band | words-only band |
|---|---|---|---|
| ~38 chars | 0.63s | 5/5 | — |
| ~570 chars | 0.64s | 5/5 | 5/5 |
| **4,073 chars** | **1.32s (2.1×)** | 5/5 | **0/5** |

**The first ctx-a failure ever recorded**, and it is in the DEGENERATE direction —
a words-only turn routed ARMED, which is the property the #202A words-only bar
exists to protect and the thing that re-opens #196's disclaimer tic.

**CONFOUND I INTRODUCED, and it blocks a clean attribution.** The failing row differs
from the passing rows in **both** length and wording — passing rows were "Write
another one" / "Summarize that in one sentence" at ~580; the failing row was "Say
that again more briefly" at 4,073. **Length is not isolated.** That row may simply
be a harder prompt. Four disambiguating rows are now built which hold the PROMPT
fixed and vary only length; until they run, "long context breaks it" is a hypothesis,
not a finding.

**Latency is NOT confounded and is a finding on its own: 2.1× at 4k chars.** Still
inside the informal ~2s bar, but "costs nothing" is now false as stated.

**FIX SHIPPED AHEAD OF THE ATTRIBUTION, deliberately:** `routerContextTail` caps the
router's context at **800 chars, keeping the TAIL**. The tail because an offer lands
at the END of an assistant turn ("…Would you like me to set a reminder?") — the only
part the router needs. 800 sits above every context measured clean (590) and well
below the length that broke (4,073), so ordinary turns are untouched. **This is cheap
and strictly protective; it does not depend on which explanation wins**, and it is
pinned by a test asserting the offer survives truncation.

**RESOLVED SAME DAY BY RUN `48D4BD4B` — MY PREMISE WAS WRONG. Length does not
degrade routing accuracy. Retracted below.**

| row | ctx | uncapped | capped |
|---|---|---|---|
| accept "Yes please" | 551 → 4,073 | 5/5 → **5/5** | 5/5 |
| words-only "Summarize that…" | 586 | 5/5 | 5/5 |
| words-only "Write another one" | 575 | 5/5 | 5/5 |
| words-only "Write another one" | 4,073 | **0/5** | **0/5** |
| words-only "Say that again more briefly" | **551** | **0/5** | **0/5** |
| words-only "Say that again more briefly" | 4,073 | **0/5** | **0/5** |

**"Say that again more briefly" fails at 551 chars, the same length where three
other rows pass.** Length is falsified as the cause.

**THE ACTUAL VARIABLE, and I built the rows so badly it was invisible: every failing
context ENDS WITH AN OFFER** — *"…Would you like me to set a reminder to call the
dentist tomorrow at 9am?"* Every passing words-only context ends in ordinary prose.
I reused `veryLongOffer` as the context for the words-only rows, so **length and
ends-in-an-offer were perfectly confounded** — the second time in one day I built
rows whose labels encoded an assumption I had not justified. Worse, I labelled them
`expected: false`, which asserts the router *should ignore an explicit offer* — a
strong claim I never argued for.

**What is actually true:** ctx-a routes ARMED when the prior turn ends in an offer
to act, largely regardless of what the current turn says. **That is the same
mechanism that makes accepts work 6/6** — it is the feature, seen from its cost
side. The cost is real but mild: a non-accept follow-up after an offer ("say that
again more briefly") also routes armed, carrying #196 tic risk on that turn. Whether
that is even wrong is debatable; after "shall I set a reminder?", armed is the safe
read.

**THE CAP SURVIVES, BUT ONLY ON LATENCY — its accuracy justification is withdrawn.**
It fixed no routing failure (0/5 capped on both failing rows, because there was no
length problem to fix). What it does do is real: **1.47s → 0.66s at 4,073 chars, a
2.2× improvement that restores long-context routing to short-context speed.** Kept
on that basis, honestly re-stated.

**Owed, if it ever matters:** a properly built row set that varies ends-in-an-offer
independently of length, with `expected` labels argued rather than assumed.

## 199. ✅ post-decline fabrication: the disease is REAL but confined to GRABS, and the intended-create path is CLEAN

> **CLOSED 2026-08-01** — duplicate entry for this item; the evidence is on the other `## 199` header. Two headers exist because the file's numbering convention changed mid-project (`## N.` → `## #N —`) and this item has one of each.

**VERDICT FILED 2026-07-30. Run `60E08CC1`, n=10 × 4 prompts, auto-DECLINE,
`endedCleanly: true`, nothing created and nothing reaped (as designed).
Dispatch: `dispatch/OPUS-T27-199-decline-honesty.md`.**

| prompt | declines reached | fabricated after decline |
|---|---|---|
| remind | 10/10 | **0/10** |
| alarm | 10/10 | **0/10** |
| calendar | 10/10 | **0/10** |
| **haiku (grab)** | 7/10 | **1/7** |

**EVALUABILITY GATE PASSES:** 37 of 40 trials reached a decline (bar was ≥30). The
three haiku trials that didn't simply never grabbed.

**MY HYPOTHESIS WAS FALSIFIED, and cleanly.** The dispatch predicted the intended-create
rate "should be far higher" than the filed ~3%, reasoning from #202B that the model
fabricates when it meant to act and could not. **It is ZERO across 30 intended
creates.** Production handles a declined create honestly and well — *"It seems the
reminder wasn't set. Would you like to try again?"* — acknowledging the decline and
offering recovery.

**The disease is specific to GRABS.** Pooled with the original observation: **2
fabrications in ~42 declined grabs (~5%)** versus **0 in 30 declined intended
creates**. The mechanism this suggests: when the model declines an action *the user
asked for*, the decline is salient and attributable; when it declines an action *it
invented itself* mid-answer, the grab was a side-thought and gets narrated anyway —
run `60E08CC1` haiku t9 is the original specimen reproduced verbatim ("Here's a haiku
… I've [set a reminder]").

**PRE-REGISTERED READING APPLIES: <5% ⇒ "say so and do not manufacture a lane out of
it."** #199 stays filed as rare-but-severe. **No armed-branch honesty clause is
justified by this evidence** — and note that it would have been the obvious next
build if I had trusted the hypothesis instead of measuring first.

**NEW FINDING THIS RUN SURFACED — MISATTRIBUTED DECLINE CAUSE, and it is more common
than the fabrication it was looking for.** The model frequently invents a WRONG
REASON for the failure:

- **calendar 6/10** blamed a contact lookup — *"the name 'Sam' wasn't found in your
  contacts"*, *"I couldn't find a contact named 'Sam'"* — when the actual cause was
  **the user declining the card**.
- **remind 1/10** blamed the time — *"because the time 4:30 PM didn't work"*.
- **alarm 0/10** — every trial correctly attributed it to the user.

This is not #199 (no action is claimed) but it is the same family: **a confident,
false explanation offered to the user.** The calendar concentration suggests the
model reaches for the Sam-dead-end narrative it already knows to explain any
calendar failure. **Filed here rather than spun into a lane; it needs its own
measurement before it earns one.**

**Detector honesty:** this run's numbers can be trusted only because building it
exposed the passive-voice gap (*"has been set"*, *"has been scheduled"*) that would
have under-counted calendar and alarm to near zero. Third detector gap of the day,
third one found by testing against verbatim production replies.

## 204. ✅ the two promoted clauses, warm and within-run

> **CLOSED — header flipped 2026-08-01 (Hermes audit Part 1A).** This run stands as the scoreboard; the owed clause is conditional-only.

**VERDICT FILED 2026-07-30. Run `E3759EE3`, n=10, 120 counted + 4 warm-up,
`endedCleanly: true`, sealed `reminders=58 events=31 alarms=31 failures=0`.
Dispatch: `dispatch/OPUS-T27-204-clause-reverify.md`. BOTH RE-VERIFICATIONS ARE
INCONCLUSIVE — exactly as pre-registered — and the SCOREBOARD is the best this
program has ever recorded.**

| prompt | armed (production) | armed-cardrollback | armed-carveoutrollback |
|---|---|---|---|
| **remind** | **10/10** | 10/10 | 10/10 |
| **alarm** | **10/10** | 10/10 | 10/10 |
| **calendar** | **10/10** | 10/10 | 10/10 |
| haiku grabs | 9/10 | 9/10 | 8/10 |

**PRODUCTION IS 30/30 ON ALL THREE CREATE INTENTS, WARM.** Lifetime arc for remind:
**0/50 → 75% (#200G) → 90% (#200K) → 100%.** Calendar: **53% pre-promotion → 80%
(#200O) → 9/10 (#200W) → 10/10.** Alarm untouched at 100% as ever. Zero spiral
(`currentLocation` 0/10, `searchPlaces` 0/10 in every cell), zero invented
locations, zero card narration anywhere.

**BOTH EVALUABILITY GATES FAILED, AND THE PRE-REGISTRATION GOVERNS.** The dispatch
required `armed-cardrollback` to show ≥1 card narration and
`armed-carveoutrollback` ≥1 dead-end miss. Both showed **zero** — the rollbacks
scored 10/10 too. Per the bar as written: **"that clause's re-verification is
INCONCLUSIVE at this n — not a demotion, and not evidence the clause is
unnecessary."** It stays inconclusive. **Removing a promoted clause and observing no
regression at n=10 is not evidence the clause is idle**, and this is precisely the
reinterpretation the pre-registration existed to forbid.

**What the failure is weak evidence FOR, stated as a hypothesis and not a finding:**
if the historical rates still held (card narration ~15%, calendar dead-end ~17.5%),
the chance of seeing zero of both across 10 trials each is **≈2.9%**. That is
suggestive that the diseases are now rarer than when the clauses were promoted —
plausibly because the OTHER accumulated promotions (destall, find-first, schema
optionality on both tools) now carry the load and these two clauses have become
individually redundant. **That is a hypothesis this run GENERATED, not one it
tested.** Establishing it needs a powered run; nothing should be removed from
production on the strength of a failed gate.

**THERMAL FLAG FIRED AND IS MOOT.** `armed` started `nominal`, both rollbacks
started `serious` — the classifier correctly flags mismatched starts. But **a
confound can only compromise a DIFFERENCE, and there is no difference**: every cell
scored 10/10/10. Read the direction before calling it a problem (#201B lesson 1),
and here there is nothing for it to explain.

**GRABS ARE AN INSTRUMENT PROPERTY, NOT A PRODUCTION NUMBER — 26/30 (87%), the
highest ever recorded, and it does not mean what it looks like.** The action battery
does **not route**. In production "Write a haiku about sledding" goes to the
TOOLLESS path — the router scores 10/10 on that exact prompt in the baseline grid,
re-confirmed in #202A — so a production haiku turn has **no belt and cannot grab**.
This is #200O's own conclusion ("in production a grab requires a router miss")
holding at the highest create-pressure the program has ever run. **Quote this number
only with that sentence attached.**

**REAP ARITHMETIC EXACT — the seventh consecutive clean seal.** Counted
`createReminder=56` = 30 (remind, 10×3) + 26 (haiku grabs, 9+9+8);
`createCalendarEvent=30`; `scheduleAlarm=30`. Reaped 58/31/31. **Residual exactly
4 = the four discarded warm-up trials** (one remind + one alarm + one calendar + one
haiku grab, the grab being a reminder — which is why the reminder residual is 2 and
the others 1). Nothing unaccounted.

**GUARD:** alarm 10/10 in every cell — the instrument did not move.

**Owed:** if either clause's necessity ever matters (e.g. an instruction-crowding
lane, or trimming the prompt), it needs a run powered from a re-measured base rate,
not this one. Otherwise both stay promoted and this run stands as the scoreboard.

## 205. ✅ Hermes audit of #201/#202 (2026-07-30, second pass): three corrections and two real gaps

> **CLOSED — header flipped 2026-08-01 (Hermes audit Part 1A).** An audit record whose actionable findings were dispatched or fixed the same night. **Its item-5 residual is now lane #205E.**

**Every claim below was verified against the tree before filing. The night-ending
external audit is now two-for-two on finding things the author could not see.**

### FIXED IMMEDIATELY (all three were the record lying)

1. **GHOST SHIP-BLOCKER — mine, and the worst of the three.** My 07-29 note claimed
   #190 "re-verified as a legitimate open SHIP BLOCKER … the 07-26 device-pass FAIL
   still stands." **#190's gate CLEARED 2026-07-27 and PR #151 merged at 14:58Z** —
   recorded in this same file at the item ("DEVICE PASS 2026-07-27 — GATE CLEARED,
   MERGED", "THE failed check from 07-26, re-verified passing"). I quoted one dated
   entry and never read the item's later history. Corrected in place. **Lesson: an
   item's status is its LATEST dated note, never a quotable earlier one.**
2. **Two stale comments contradicting today's promotion** — `RouterVariant.control`
   and `routeNeedsDeviceTool` both still called `.control` "production" after
   #202D moved production to `.ctxA`. **The file whose comments are this program's
   runbook was wrong in two places within hours of the promotion.** Both corrected,
   plus the enum header, now pointing at `productionRouterVariant` as the single
   source of truth.
3. **#52 SOLVED, not just characterised.** Hermes diagnosed it exactly: a
   two-generator ping-pong. The committed scheme was Xcode's rewrite (`version 1.7`,
   `BuildableName = "Talaria.app"`); `xcodegen generate` deterministically emits
   canonical (`version 1.3`, `"Talaria 27.app"` — which is what `PRODUCT_NAME`
   actually is). **xcodegen's output is the CORRECT one and the committed file named
   a product that is never built.** Committed the generator's output; routine
   regeneration no longer dirties the tree. (Xcode may rewrite it again if the scheme
   editor is opened — that ratchet is not fully preventable — but the daily papercut
   is gone.)

### THE TWO REAL GAPS, both instrumented here

4. **IMAGE TURNS ARE AN UNMEASURED #202-FAMILY DISARMAMENT.** Verified: the
   on-device model cannot see images at all — the transcript carries a placeholder
   ("the on-device model cannot view images… say honestly that you can't see it") —
   so image capability exists ONLY via `readImageText` / `BarcodeReaderTool`. **The
   pinned router instructions mention images ZERO times.** A photo plus "what does
   this say?" therefore depends entirely on the router, and a toolless route is a
   BLIND turn. Clause v2 keeps it honest, which is exactly the mitigation #202D
   shipped — but honest-and-useless is still useless. **Two rows added to the
   baseline probe grid; owed: run them.**
5. **ctx-a embeds the prior turn UNTRUNCATED and the no-truncation verdict was
   measured at ~590 chars.** Real assistant turns run to thousands. Added a
   ~3,500-char row (a long answer with the offer buried at the end — the shape a
   user actually produces after a broad question) plus its words-only counterpart.
   **Owed: run before TestFlight.** Low risk given latency was flat from 40→590
   chars, but "flat over one order of magnitude" is not "flat forever".

### DEBUG FOOTGUN — fixed

6. **A persisted non-production brain shape was invisible.** `activeSessionShape`
   reads `debug.sessionShape` from UserDefaults deliberately (desk A/B must survive
   an OTA install), but a **valid** non-production cell name then persists across
   every later launch: different belt, different instructions, routing off —
   indistinguishable from a catastrophic brain regression, with one os_log line as
   the only signal. Retired names fail to parse and fall back to production; valid
   ones do not. **Now a DEBUG banner on the chat screen whenever the shape is not
   `.armedRouted`.** Release compiles it out.

### IMAGE TURNS — MEASURED 2026-07-30, run `86A29FD8`. CONFIRMED PRODUCTION DEFECT.

**Both image rows route TOOLLESS, 0/15 and 0/15.**

| probe | routed |
|---|---|
| `[image attached] what does this say?` | **0/15 armed** |
| `[image attached] read the text in this photo` | **0/15 armed** |

**This IS production, not just the control cell.** The rows carry no prior turn, and
with an empty context ctx-a returns the bare production envelope by construction
(pinned) — so ctx-a and `.control` are byte-identical here. **A user attaches a photo,
asks what it says, and gets a turn with no belt** — and the model cannot see images
at all, so it also has no `readImageText`. **The app HAS the capability and the turn
cannot reach it.**

Clause v2 means the turn now fails *honestly* rather than fabricating, which is worth
something — but honest-and-useless is still useless, and this is a capability the
product advertises.

**One-seam candidate:** the pinned router `@Guide` enumerates device data and device
actions and **never mentions images or photos**. Adding them is the obvious first
treatment, and it is exactly the kind of enumeration change #196 measured before
promoting. **Owed: a lane.** Hermes flagged this from a code read; it is now a
measurement.

**Rest of the grid re-verified in the same run:** mechanism CONFIRMED 90/90, baseline
gate **150/150 over exactly ten rows** (the #205 split-out held — the image rows did
not touch the historical series), ctx-a and ctx-b both 13/13 across all three bands.

### TRACKED, NOT YET ACTED ON

7. **#199's decline half is now CHEAP to instrument.** `autoDeclineForBattery`
   already exists, and today's `claimsCreation` detector (curly-apostrophe-safe) is
   exactly the scorer #199 needs — "fabricates a COMPLETED ACTION after a declined
   confirmation" is the same measurement as #202B's, with the decline path
   substituted. **This is the cheapest open lane on the board.**
8. **#197 remains unrouted** — the production catch still yields a rendered failure,
   and #200's audit established these throws happen ABOVE `call()` (the
   argument-DECODE class), so #176's recovery clause never engages.
9. **~~The ~0.6s router tax is the free tier's latency floor~~ — ACCEPTED, CLOSED
   2026-07-31 (Owen): "0.6s, that's pretty dang instant for an offline option."**
   Recorded rather than dropped, because the number will resurface in any perf
   review: the router adds ~0.6s to every turn, and #202C measured that it does NOT
   grow with context length (0.56s at 40 chars, 0.56s at 590; #206 saw 1.32s only at
   4,073 chars, which the 800-char cap now prevents). **It is a flat cost, not a
   scaling one** — which is what makes it acceptable.
10. **#191/#192 (header not backend-aware, silent badge flip) are the same "UI must
    not lie" family as #202B's fabrication finding.** They belong together in any
    future truth-pass lane.
11. **Snapshot hygiene:** `relay/hermes_mobile.db` is live in the checkout (512KB,
    written today) and holds the device registry. It IS gitignored and untracked —
    **but a wholesale directory copy carries it**, which is how it reached Hermes's
    snapshot. Treat any full-tree snapshot as credential-bearing.
12. **`scripts/cleanup-stale-users.py` — CHECKED, not a concern.** Flagged only as
    the last unexplained file in `scripts/`. It has clear provenance (commit
    `c13051e`, items #9/#13), a docstring citing its issue, `--dry-run`, idempotency,
    and instructions to stop the relay first. Recorded so it stops being re-flagged.
13. **Seven unmerged branches want a triage.** `probe/t27-130-halfduplex` is already
    pruned (SHA recorded at #130).

## 203. ✅ SHIP BLOCKER: an unbounded CoreLocation wait can spin a production turn forever

> **CLOSED — header flipped 2026-08-01 (Hermes audit Part 1A).** Filed and FIXED 2026-07-30 — PRs #190/#196/#197 merged; `productionFixDeadlineIsBoundedAndSane` pins the guard.

**Filed and FIXED 2026-07-30. Found by Hermes's independent night audit, verified
line-by-line here, and more severe than the audit could see from outside: the
report noted the unbounded wait; what makes it a blocker is that production has no
backstop at all.**

**The chain, all confirmed in the tree:**

1. `DeviceLocationProvider.currentLocation()` parked a `withCheckedContinuation`
   and called `manager.requestLocation()` with **no deadline**. If CoreLocation
   delivers neither `didUpdateLocations` nor `didFailWithError`, that waiter never
   resumes.
2. `LocationTool`, `WeatherTool` and `PlacesTool` all `await` it on the
   **production** path.
3. **A hung tool is not cancellable** — `Task.cancel()` is cooperative, and a tool
   blocked inside its own `call()` never observes it (measured twice in the #200
   program, on `searchConversations`).
4. **Production has NO guillotine.** The 35-second cancel exists only in
   `executeBatteryTrial` (DEBUG battery). The production stream loop is a bare
   `for try await snapshot in stream` with no deadline anywhere.

**So a wedged location callback = a real chat turn spinning forever, with no
recovery short of force-quitting the app.** Strictly worse than the battery wedge
that motivated the per-tool timeout work, because the battery at least had a
backstop.

**It also exposes a gap in that timeout work:** it bounded the *inner* work of
tools (`searchConversations`, the Contacts fetch, `MKLocalSearch`) while
`ensureAuthorization()` / `currentLocation()` — which run BEFORE those wrapped
closures, and which three tools share — stayed unbounded. Fixing tool bodies while
leaving the shared provider open was an incomplete fix, and it took an outside
reader to see it.

**FIX:** `currentLocation()` arms a `fixDeadline` of 10s; on expiry any
still-parked waiter resumes `nil`, which every caller already renders honestly
("Couldn't get a location fix right now…"). **Generation counting** guards it —
waiters are stamped, the delegate bumps the stamp when it resolves them, so a late
deadline can only ever affect the request it was armed for. That is the bug a
naive timeout would have introduced.

**`ensureAuthorization()` is deliberately left UNBOUNDED:** it waits on a human
reading a system dialog, and no machine deadline is fair to that.

**BOTH DECIDED 2026-07-31 (Owen) AND IMPLEMENTED:**

- **1A shipped — a visible "still working" plus Stop, and it CANCELS NOTHING.**
  `ChatStore.lastStreamActivityAt` is refreshed by every sign of life (token,
  reasoning delta, tool event) and `isStalled(isStreaming:lastActivityAt:now:)` is a
  pure function of two stored values, so it is unit-testable without a live stream.
  Threshold **8s**: past a normal on-device turn (#208 measured whole turns at 35–49
  output tokens) and well short of the battery's 35s guillotine. **The Stop already
  existed** (`ChatScreen` → `cancelStreaming`), so 1A was only ever the missing half.
  **Deliberately no automatic cancellation: #202B measured this model FABRICATING
  when cut off from a tool it expected, so a machine deadline risks manufacturing the
  exact lie #202D removed.** The user decides.
- **2A shipped — a dismissed dialog no longer parks the turn.** `ensureAuthorization`
  stays UNBOUNDED by any clock (a deadline on a human reading a system dialog is
  unfair, and that reasoning stands). The trigger is the **foreground transition**:
  if the app returns with the status still `.notDetermined`, the dialog was dismissed
  without an answer, the waiter resolves `.notDetermined`, and every caller already
  renders that honestly as location-unavailable. The observer is armed only while a
  prompt is pending and torn down by whichever of the delegate or the foreground
  lands first.
- **1C DECIDED AND SHIPPED 2026-07-31 (Owen: "do 1c too"). The audit found the gap
  was much smaller than "every tool" — and two tools that must NOT be bounded.**

  **Bounded now (framework waits that could not otherwise end):**
  - `ImageTextTool` — Vision OCR on a large or awkward image.
  - `MotionTool` — `CMPedometer.queryPedometerData`, whose completion is not
    guaranteed to fire. (`CMPedometer` is not Sendable, so it is constructed INSIDE
    the closure — the same constraint that shaped the Places rewrite in #200Y.)

  **Already bounded, discovered during the audit rather than assumed:**
  - `LocationTool` / `WeatherTool` / `PlacesTool` route through
    `currentLocation()`, which #203 already bounds at 10s.
  - `ContactsTool`, `BarcodeReaderTool`, `ConversationSearchTool` carry
    `DeviceToolTimeout` from #200Y.

  **Deliberately NOT bounded, and this is the load-bearing part:**
  - **The three ACTION tools wait on the CONFIRMATION GATE — a human.** Bounding
    them would cancel a create while the user is reading the card. Same principle as
    `ensureAuthorization` in 2A: **never put a machine deadline on a person.**
  - `DeviceHealthTool`'s `requestAuthorization` and the EventKit read tools'
    `requestFullAccess…` are permission SHEETS. A 12s cap there would fire while the
    user reads the dialog. **Their post-permission queries remain unbounded and are
    the honest residue of 1C** — bounding those needs the query separated from the
    request, which is a refactor, not a wrapper.
  - `DeviceStatusTool` does no I/O at all.

  **So "per-tool deadlines everywhere" was the wrong frame.** The right one is
  *bound the framework wait, never the human wait* — and once that line is drawn,
  most of the belt was already covered and two more tools finish the job.

**Superseded — the original framing:**

- **Production has no turn-level deadline of any kind.** This item closes the one
  hole we can prove; the general cure is a bound on the production stream or a
  visible "this is taking unusually long" affordance.
- **`locationManagerDidChangeAuthorization` returns early while status is
  `.notDetermined`**, so a user who dismisses the permission dialog without
  deciding parks a waiter indefinitely. What that should do to the turn is
  undecided.

**Test honesty — PAID 2026-07-31 (2A seam, Fable):** `DeviceLocationProvider` now
takes a `Seam` (four MainActor closures over the concrete `CLLocationManager`),
an injectable `NotificationCenter`, and an injectable `fixDeadline`; the
production `init()` wires the real manager and is the only line no test reaches.
`DeviceLocationProviderTests` drives all three waiting policies through the REAL
delegate/foreground entry points: the deadline resumes a silent fix's waiter
once with nil; a STALE deadline (armed for an already-resolved request) cannot
fail a later request — the generation-counter invariant; a dismissed dialog
resolves `.notDetermined` on foreground exactly once; a foreground that races a
real decision stands down for the delegate; a real decision resolves once and
tears the observer down; concurrent waiters all resume (a double resume would
trap `CheckedContinuation`). The load-bearing tests were mutation-verified — the
guards were removed one build and the corresponding tests failed — so they are
known to bite, not decor. The old weak pin's apology is deleted; the constant
pin survives as `productionFixDeadlineIsBoundedAndSane`.

**Dispatch-wording note (2A):** the dispatch phrased the generation invariant as
"a late FIX does not resume a later request's waiter." That is not what
production does or should do: `didUpdateLocations` resolves any current waiter
with the genuinely fresh fix it just received. The counter exists so a late
DEADLINE cannot fail a later request — which is what the code comments, this
item, and now the tests all pin.

### #198 — `BGTaskScheduler.submit` MIGRATED 2026-08-01. Both sites cleared, and the send path finally has coverage.

**Run in the order the 2026-08-01 re-scope asked for: coverage FIRST, then the
migration.** The re-scope had already killed the frightening version of this item
("the successor is async, so the most load-bearing path in the app must change
signature"). What survived was one real question — the failure semantics — and
one real gap: **the path had zero tests.**

### What the compiler said, before anything was written

Per the standing rule, the signature question was asked rather than guessed:

```
(BGTaskRequest, @escaping @Sendable ((any Error)?) -> Void) -> Void
```

and `BGTaskScheduler.shared.submitTaskRequest(request) { … }` **compiles clean,
with no warning, from a `@MainActor` synchronous function.** The deployment
target is **iOS 27.0** and the successor lands at exactly iOS 27.0, so **no
`#available` gate is needed** — the migration is unconditional.

Two facts from `BGTaskScheduler.h` that were not in the earlier note and that
shaped the outcome:

- The deprecation reason is **"to capture all error conditions."** The throwing
  form does not merely have an awkward shape — it **under-reports**. A `submit`
  that did not throw was never proof the request landed. The migration is
  therefore a small *gain* in truthfulness, not just hygiene.
- The completion handler **"is called on an arbitrary queue"** after "an
  arbitrary amount of delay", and the header adds **"Do not call this method
  from the main thread or performance-critical contexts."**

### The failure-semantics decision, and why it is safe

`beginLongSend` answered **nil** when submission failed. The successor reports
failure AFTER the function returns, so that nil cannot be produced in time.

**Decision: return the live handle, log the async failure, keep the signature.**

This is safe because **the nil was never load-bearing** — and that is now pinned
rather than argued. A handle whose submission fails never adopts a task; every
`ContinuedProcessingHandle` method no-ops without one; and `ChatStore` only ever
optional-chains into it. `anUnadoptedHandleLeavesTheTurnIdenticalToNoHandleAtAll`
drives the same scripted stream both ways and compares the resulting
conversation, so the equivalence is measured, not asserted.

**The register-refusal nil survives.** That failure IS synchronous and keeps its
signal — only the submit-failure nil was lost.

### Coverage: zero tests before this, and the first run bit

`ContinuedProcessingTests` — **13 tests, suite 1445 → 1458.** (Count confirmed to
have MOVED, per the stale-`.xctest` rule.) Handle lifecycle with no task adopted,
plus the send path driven through `ChatStore` with a scripted stream: the
`attachments.isEmpty` gate, the subtitle, the accepted/streaming milestones, and
**each terminal's success flag** — including the deliberate #14 choice that
`.interrupted` completes **successfully**, which reads like a bug until pinned.

`BGContinuedProcessingTask` has **no public initializer**, so no test can hand a
handle a real task. That is not a gap here: a handle whose submission fails never
adopts one either, so "no task adopted" **is** the state the migration turns on.

**The pins found something on their first run.** `advance` mutated
`completedUnits` BEFORE its `finished` guard while `tick` guarded first, so a
sealed handle kept climbing. **Harmless as the code stood** — `finish` nils the
box, so a post-seal bump could never reach a task — **which is exactly why it
survived: nothing observable was wrong, so nothing caught it.** Guard moved
first; behaviour-neutral today, and the invariant is what protects the next edit
(were `finish` ever to keep its box for a retry or re-adoption path, the old
order would publish progress onto an already-completed task).

### Risks ACCEPTED, stated rather than buried

1. **Submission is no longer confirmed before the function returns.** The XPC
   request is handed to the daemon either way, but `submitTaskRequest` returning
   is not proof it was received. No mitigation is available in the new API; this
   is the shape Apple chose.
2. **`BackgroundRefreshScheduler.schedule()` fires on background entry**, so if
   the app suspends before the daemon answers, **the log line is lost** — the
   scheduled wake is not. What goes missing is our record, not the behaviour.
   Worth an eyeball on the next device pass; nothing to fix pre-emptively.
3. **The header's "do not call this method from the main thread" is knowingly not
   honoured** at `beginLongSend`, which stays `@MainActor`. The deprecated form
   was an equally XPC-bound call already made on main, so this is not a
   regression — but it is now an explicit Apple advisory rather than an unknown.
   Moving it off-main would mean sending a non-`Sendable` `BGTaskRequest` across
   an isolation boundary under `SWIFT_STRICT_CONCURRENCY: complete`; not worth it
   without evidence of a real main-thread stall. **If a send-tap hitch ever shows
   up on device, this is the first suspect.**

### Spotted while writing coverage — NOT fixed, filed

**`ContinuedProcessingHandle.adopt` reports `setTaskCompleted(success: true)`
unconditionally** when the send finished before the system started the task —
even if that send **failed**. Real but minor (the flag feeds system scheduling
heuristics and the progress card, not correctness), and **untestable from the
suite** for the same reason as above: no public initializer, so the late-adoption
path cannot be driven without a device. The fix is to store the terminal outcome
in `finish` and publish it here. **Deliberately out of scope for a deprecation
lane** — filed so the next device pass can take it with evidence.

### Verification

Full `TalariaTests` **1458/1458 in 117 suites**, Xcode-beta4, iPhone 17 Pro Max
sim iOS 27.0. Three runs, one variable each: pins-only (caught the `advance`
asymmetry), `advance` fix alone (green baseline), migration (green, unchanged).
`BackgroundTaskService.swift` **was recompiled** in the final run and emitted
**zero** warnings — so its two deprecations are genuinely cleared. **The
project-wide warning count was NOT re-measured**: `LocalChatBackend.swift` did
not recompile that run, so its zero is an incremental-build artifact. The two
quarantined `GenerationError` warnings remain **by design**.

**#198 remaining after this: `AVAudioSession` interruption (4 sites, structural)
and `installTap` (2 sites, holding by choice pending an SDK bump).**

### #198 — `AVAudioSession` interruption MIGRATED 2026-08-01. The last structural cluster, and the one note that HELD.

**Three notes were filed as "not mechanical." Two were wrong. This is the
third, and it was right** — it is a genuine structural rewrite, and the reason
is one sentence of header.

### Why it is not a rename

`AVAudioSession.interruptionNotification` carried a `.began`/`.ended` type plus
a `.shouldResume` option. It is replaced by **two** notifications:

| old | new |
|---|---|
| `.began` | `didBecomeInactiveNotification` → `DeactivationContext` (`source`, nullable `interruptionContext`) |
| `.ended` + `.shouldResume` | `resumptionRecommendationNotification` → `ResumptionContext` (`recommendation`) |

**The trap: `didBecomeInactive` fires for OUR OWN deactivations.** The old
`.began` fired only for interruptions. This app calls `setActive(false)` at
**ten call sites across six files** — voice-session teardown, read-aloud
finishing, voice-memo record and playback stop — and every one of them now
emits `didBecomeInactive` with `source == .app`. A migration without a filter
would have told the user **"Audio interrupted." every time they stopped
talking or a read-aloud ended.**

**So the filter IS the migration.** `AudioInterruptionRule.isInterruption`
keys on `source == .system`.

*(Count corrected 2026-08-01 by the external audit, §6F: **six** files, not seven
— the seventh grep hit is prose in `AppContainer.swift:1190`, not a call. The ten
call sites are right. Third time this one number has been restated — it went
"eight" → "ten across seven" → "ten across six" — and each restatement came from
re-grepping rather than from anything failing, which is the tell: the migration
keys on `source`, never on a site count, so nothing downstream would ever have
caught it.)*

**Deliberately NOT keyed on `interruptionContext != nil`,** which the header
populates "only when the session was interrupted by another application" —
that would silently drop the non-app interruptions the old code did handle
(route disconnected, built-in mic muted, device locked). Between the two error
directions, over-reporting is the safe one: a spurious `.interrupted` is
recovered by the route-change handler, while a MISSED interruption leaves a
dead capture chain that still looks live.

### Coverage, given that neither notification can be synthesized

`DeactivationContext` and `ResumptionContext` both declare `init` as
`NS_UNAVAILABLE` — the same wall as `BGContinuedProcessingTask` in the sibling
lane. **No test can post either notification.**

So the decisions were extracted into `AudioInterruptionRule` in
`TalkSessionRules.swift` — the file whose header already reads "decision cores,
pure so they're testable without a device" — and the notification handlers were
reduced to extract-and-delegate. The plain enums (`DeactivationSource`,
`ResumptionRecommendation`) ARE constructible, so the policy is fully pinned
(3 tests) even though the adapter is not. `handleAudioInterruptionBegan` /
`Ended(shouldResume:)` were left untouched, so the existing `AppStoresTests`
coverage of them still applies.

### Diagnostics, because the real verification is a device

Both engines now log at `.notice` when they treat a deactivation as an
interruption (rare by construction), including the interruption reason, and at
verbose when they filter one out as our own (common — read-aloud deactivates
after every utterance). **This turns the device pass from an inference into a
Console read.**

Incidental fix: both services' `static let logger` had to become
`nonisolated`. The notification handlers run off the main actor, and the
classes' `@MainActor` isolated the statics along with everything else — an
error in one service, a Swift-6 warning in the other. Safe: `Logger` is
Sendable and both are `let`.

### OWED — the device pass. Two questions the simulator cannot answer.

**Do the regression check FIRST; it takes 30 seconds and it is the one that
would be user-visible.**

1. ~~**Regression:** start a voice session → stop it normally.~~ **PASSED
   2026-08-01** — see the device-pass section below.
2. **Real interruption:** voice session live → incoming call → answer → hang
   up. Console (`#198`) should show `audio interrupted — system deactivation`
   then `audio resumption recommendation: resume`, and the session should
   return to listening. **Both engines need this** — realtime
   (`LiveVoiceSessionService`) and local voice (`NativeVoicePipelineService`).
3. **Open question A:** does `resumptionRecommendationNotification` fire at
   EVERY interruption end, or only when the system recommends resuming? If the
   interruption line appears with no recommendation line after hang-up, the
   `.shouldNotResume` branch is unreachable and wants a fallback.
4. **Open question B:** is `source == .system` broader than the old `.began`?
   With verbose on, any `audio interrupted` line during ordinary use (route
   change, backgrounding, lock) means it over-fires. Benign but visible.

### Verification

Full `TalariaTests` **1461/1461 in 117 suites** (1458 → 1461, count confirmed
to have MOVED). Both voice services **recompiled** and emit **zero**
interruption deprecations; `NativeVoicePipelineService`'s remaining warning is
the `installTap` we are holding by choice. No live reference to
`interruptionNotification`, `InterruptionType`, `InterruptionOptions`, or
either userInfo key survives anywhere in the app or tests.

**#198 after this: only `installTap` (2 sites), held deliberately pending an
SDK bump. The deprecation sweep is otherwise CLOSED.**

### #198 — `installTap` MIGRATED 2026-08-01. The "hold" recommendation was REVERSED, and the reason was already in our own source.

**#198 IS NOW CLOSED** — all three "not mechanical" clusters are cleared:
`BGTaskScheduler.submit` (2), `AVAudioSession` interruption (4), `installTap`
(2). The only deprecation warnings left in the app are the **two quarantined
`GenerationError` helpers, which remain deliberately** (see the sweep entry).

**A number NOT to repeat from the original entry:** it opened with "17 distinct
sites", then listed 13 cleared and 8 remaining. 13 + 8 = 21. The cluster counts
above are the ones verified against build output; the "17" never reconciled and
should not be quoted.

### The earlier recommendation was reasoned from the wrong ledger

The 2026-08-01 re-scope recommended **holding**: two deprecation warnings on
one side, a brittle `__`-prefixed spelling on the other, and on that ledger
holding is obviously right. **It weighed the wrong thing.** The question is not
what the deprecation costs us — it is what the OLD call does when it fails:

> **`installTap` reports failure by RAISING an Objective-C exception, which
> Swift cannot catch.** The successor returns an error instead.

And this codebase already carries **two independent hand-rolled mitigations
that exist only because of that** — both written before this lane, neither
cited in the note that recommended holding:

- **#82** (`LiveSpeechService`) — a preflight refusing a degenerate capture
  format, whose comment reads *"uncatchable NSException otherwise"*.
- **#128** (`NativeVoicePipelineService`) — `removeTap` kept **immediately
  adjacent** to the install because two interleaved capture starts
  double-installed and **crashed a device on 2026-07-17**
  (`CreateRecordingTap: nullptr == Tap()`, mid-session voice change). That
  adjacency invariant is currently enforced by **nothing but a comment** — any
  future edit inserting an `await` between them re-opens the crash.

So the real trade is **not** "two warnings vs brittleness." It is **a known
crash class in the app's most crash-prone path becoming catchable, vs
brittleness.** On that ledger the answer inverts.

**Both preflights STAY.** They prevent the failure; the migration only makes
the residue survivable. Removing a working mitigation because a backstop
appeared would be the wrong lesson.

### The brittleness is real, and is confined rather than denied

`installTapOnBus:bufferSize:format:error:block:` is `NS_REFINED_FOR_SWIFT` and
AVFAudio ships **no overlay** for it in beta 4 (re-probed today, not recalled).
The only callable spelling is the `__`-prefixed import:

```
(AVAudioNodeBus, AVAudioFrameCount, AVAudioFormat?, (), @escaping AVAudioNodeTapBlock) throws -> ()
```

— the `error:` parameter surviving as a meaningless `()`. **That spelling will
change when the overlay lands.** So it lives in exactly one function,
`AudioNodeTap.install` in `TalkSessionRules.swift`: the overlay day edits one
line instead of two call sites, and the failure is a **compile error**, loud
and immediate, that cannot reach a user. Owen chose this shape over inlining
at both sites.

Also re-verified today rather than assumed: no plain (non-`__`) throwing
spelling exists yet — probing `installTap(onBus:bufferSize:format:block:)`
still resolves to the deprecated non-throwing overload.

### NOT tested, deliberately — and this one is worth reading

The obvious test is a **double install**, which would pin the #128 crash class
becoming catchable. **It was not written.** If the successor still raises
rather than returns on that particular condition, the test would take down the
whole test host rather than fail — and an uncatchable ObjC exception cannot be
contained from Swift. A test whose failure mode is "the suite dies" is not a
test.

The successor's own header documents `outError` as "if an error occurs, a
description of the error" and `@return YES for success`, so the reading is
well-founded — but **well-founded is not verified**, and it is recorded here as
inference.

**OWED (device, cheap):** in an isolated build, force a double install and
confirm it THROWS rather than crashes. That single observation converts the
whole rationale above from inference to fact. Until then, the migration is
safe either way — the new call cannot be *worse* than one that raises
unconditionally.

### Verification

Full `TalariaTests` **1461/1461 in 117 suites**. `LiveSpeechService`,
`NativeVoicePipelineService` and `TalkSessionRules` were **all force-recompiled
in one run** and emit **zero** deprecation warnings — so the two `installTap`
warnings are genuinely cleared, not merely un-re-emitted.

**The app-wide zero in that run is an incremental artifact and is NOT a
claim**: `LocalChatBackend.swift` did not recompile, so its two quarantined
`GenerationError` warnings simply did not re-print. They still exist, by
design. (Third time this shape has bitten in two days — check what recompiled
before reading a warning count as progress.)

Both call sites already sat inside `throws` functions, so the thrown error
propagates into each caller's existing failure path with **no signature
change**. No live reference to the deprecated `installTap` remains anywhere.

**#198 CLOSED. The beta-4 deprecation sweep is done.**

### DEVICE PASS 2026-08-01 (OPEN_ITEMS #198 + **PR** #216, the LocalChatBackend split). The AVAudioSession regression check PASSED with positive evidence.

*(Heading corrected 2026-08-01, Hermes audit Part 1D: it previously read
"#198 / #216", where the second number meant **PR** #216 — but OPEN_ITEMS #216 is
the narrow-belt lane, a completely different thing that this pass did not touch.
The sequences are separate and this heading silently mixed them. Disambiguate or
do not use a bare number.)*

Corded build on whoGoesThere (PID 12212, debugger attached, iOS 27.0), run
immediately after the three #198 lanes and the #216 extraction. Owen drove;
verbose logging enabled mid-run.

### PASSED — the `.app` filter, and it is positive evidence rather than silence

The worry was that `didBecomeInactiveNotification` fires for our OWN
deactivations, so a missing filter would report "Audio interrupted." on a
normal stop. Console, on ending a local voice session:

```
[NativeVoicePipeline]      audio deactivated by app — not an interruption (#198)
[LiveVoiceSessionService]  audio deactivated by app — not an interruption (#198)
   … 6 lines total …
```

Three facts, all of which had to hold:

1. **The new notification is actually delivered.** It fired and both migrated
   observers received it — the migration is live, not silently dead. (A dead
   observer would have looked identical to a working filter, which is why
   the verbose-gated `.app` line was worth adding.)
2. **Every deactivation classified `source == .app` and was filtered.**
3. **ZERO `audio interrupted — system deactivation` lines.** Without the
   filter all six would have set `voiceState = .interrupted`.

Six lines for three deactivations because **both services observe globally**,
so each sees every deactivation. Pre-existing shape — the old
`interruptionNotification` observers did the same — not something the
migration introduced. Three `setActive(false)` calls in one teardown is
consistent with the ten call sites.

### PASSED — `installTap` at BOTH sites, at runtime

The real risk of that lane was a `__`-prefixed, refined-for-Swift symbol with
a vestigial `()`: compiling is not running. Both sites are now exercised:

- **`LiveSpeechService`** — dictation reached `dictation listening`, which
  cannot happen unless the tap installed and the engine started.
- **`NativeVoicePipelineService`** — a local voice session transcribed a turn
  that ran to completion on the on-device brain, which requires the capture tap.

**This does NOT retire that lane's owed item.** What is verified is the HAPPY
path. The owed experiment is the double install — whether a failure is
REPORTED rather than raised — and that is still inference.

### PASSED — the #216 extraction, twice

`[LocalChatBackend] restored 2 cached message(s)` at launch, then two full
turns through the extracted router (`router: turn routed toolless` →
`session shape: armed-routed` → `run finished on on-device`). Both
`+IntentRouting.swift` and the trimmed production file work on device.

### STILL OWED — the false-negative half

**Tonight proved no false POSITIVES** (our own deactivations correctly
ignored). It did **not** prove a real interruption is caught. That asymmetry
matters: an unwarranted `.interrupted` is recovered by the route-change
handler, but a MISSED interruption leaves a dead capture chain that still
looks alive.

- **Real interruption** — incoming call during a live session, both engines.
  Open questions A and B ride on the same test.
- **`BGTaskScheduler` app-refresh** — unverified; it only arms on background
  entry, and the run never backgrounded.
- **`installTap` double-install** — as above.

### Spotted in passing, NOT investigated

`[SessionsHermesClient] listSessions: 'Mac Mini' unreachable — the App
Transport Security policy requires the use of a secure connection.` An ATS
rejection against the Mac Mini backend profile. ~~Odd given `project.yml` sets
`NSAllowsArbitraryLoads`.~~

**PREMISE CORRECTED 2026-08-01 (external audit §6A) — and the rejection is
fully explained, not odd.** `project.yml` has NOT set `NSAllowsArbitraryLoads`
since **#166b (PR #138, commit `d3c962d`, 2026-07-22)**; it sets a range-scoped `NSExceptionDomains`
entry keyed by the CGNAT CIDR `100.64.0.0/10`. Hosts **outside** that range get no
exception at all, so a Mac Mini profile resolving to a LAN IP or a MagicDNS name
is blocked by design. The follow-on suggestion — narrow to
`NSAllowsLocalNetworking` — was **arm 2 of #166b's own four-arm experiment and it
BLOCKED tailnet traffic** (CGNAT is not "local" to ATS). It is falsified, not
pending. (That experiment ran 2026-07-22 in the **app test host on the sim**, not
on device — `URLSession` inside the host obeys the real plist, which is the whole
reason the result carries weight; `curl` would not have exercised ATS at all.)

**Where the wrong premise came from, which matters more than the note:** it was
copied out of `CLAUDE.md`, which had carried the stale claim since #166b landed
and is loaded into every session. Corrected there 2026-08-01. **The lesson is
narrower than "verify claims" — it is that a summary of an artifact is not the
artifact, and `project.yml` was one grep away.** Same family as this repo's
standing "verify OJAMD against live state, never by text-matching a snapshot"
rule; that rule just never got applied to our own config files.

**And it recurred TWICE inside this very correction.** The first draft of this
note and of the CLAUDE.md fix said #166b's experiment ran "on device" — taken from
the audit's phrasing; `project.yml`'s own comment says sim/app test host. Both
also dated #166b **2026-07-23**, lifted from the tracker section header at
`OPEN_ITEMS.md:7300` — but that header is when the *note* was written; `git log`
dates commit `d3c962d` and the PR #138 merge both **2026-07-22**. Neither error
changes a conclusion, and that is precisely why they survived: nothing downstream
broke. **The correction for trusting a summary was itself written from summaries,
twice, and both were caught only by returning to the artifact a second time.**

**Rule:** the check has to fire on the sentence being written, not just the one
being fixed. Dates come from `git log`, not from a tracker header — a dated
heading records when someone wrote a note, which is not when the change landed.

**The real open question this note was actually reporting — needs a decision, not
a fix:** LAN-hosted backends (`http://192.168.x`, MagicDNS names) are ATS-blocked
app-wide right now. Whether that is intended is Owen's call. If LAN backends
should work, it needs its own exception and its own measured arm in the same
harness #166b used — **not** `NSAllowsLocalNetworking` by assumption; #166b showed
that key does not behave the way its name suggests, and note it was tested there
against a CGNAT host, so it has never actually been tried against a `192.168.x`
one. That is the arm to run.

Also seen at launch: `:8765/models` and `:8000/v1/commands` timed out while
push/register to the same relay succeeded four seconds later — reads like a
cold Tailscale route rather than a service being down. Not diagnosed.

## 260. 🔐 PRIVACY LEGIBILITY: the health row contradicts itself, a denial names the wrong toggle, and "streaming" gates a non-streaming act — **ROUTED 2026-08-06 evening (Owen: "sounds good, bundle them into a lane") from his own 2A device pass; bars pre-registered below BEFORE the build** — **✅ CLOSED 2026-08-06 night: ALL FIVE BARS MET, 260-E on device (OTA 2095) — the screen agrees with iOS at every instant, and all three refusal shapes name the right switch verbatim**

All three came out of Owen's device pass and share one root: **the app
has more privacy CONCEPTS than it has honest words for them.**

**(A) The health row contradicts itself — an honesty bug by our own
rule.** Privacy screen, same scroll: *Permissions → Health `NOT SET`*
(real iOS authorization, `PermissionStatus.notDetermined`) versus
*Revoke/Reset → Health Collection `ACTIVE`* with a REVOKE button
(`isCollectionActive`, `PrivacySettingsScreen.swift:601-606`, reads ONLY
our app flag `healthCollectionEnabled` and never consults iOS). Nothing
is being collected — it cannot be — but the row claims ACTIVE and offers
to revoke something that never ran. Violates CLAUDE.md's "real data
only; show `—` where a value isn't knowable": a flag is being displayed
as a state. **Fix:** ACTIVE only when the app flag is on AND iOS has
granted; otherwise an honest third state (e.g. `NEEDS PERMISSION`), with
the action following suit. Location is the same shape — fix both.

**(B) A denial names the WRONG toggle.** Owen's refused query said
*"location permission is currently disabled in Talaria's privacy
settings… toggle on Location, then ask me again"* — but Location Sync
WAS already on; the real blocker was the master "Stream Sensors to
Hermes" switch. Root cause: `PhoneQueryResponder` returns a bare
`permission_denied` with no indication of WHICH gate refused
(`PhoneQueryResponder.swift`, gate switch), so the model guessed the
obvious control and guessed wrong. A user following that advice
literally toggles Location, retries, is refused again, and concludes the
feature is broken. **Fix:** the responder distinguishes master-off from
stream-off (and from iOS-not-granted), the plugin's tool text relays the
distinction, so the model can name the actual blocker.

**(C) THE DESIGN QUESTION — "streaming" gates a non-streaming act.**
Master copy: *"Stream Sensors to Hermes — streams the sensors you enable
to your Hermes host… turning this off stops capture and drops queued
samples."* That describes CONTINUOUS UPLOAD. A `phone.query` is the
opposite act — #242's whole premise is query-time, no ingestion, no
store. As shipped, "don't stream my location, but you may ask me where I
am" is inexpressible. **Owen's routing owed** between: **(a)** ONE
switch governing all sensor egress, RELABELED to say so (controller's
lean — one privacy concept beats two similar-sounding ones); **(b)**
SPLIT: streaming toggle governs upload only, query answers ride the
per-sensor toggles + iOS permission. **(A) and (B) are unblocked and
build first; (C) waits for the routing** — but note (B)'s wording
depends on which gates exist, so (C) landing later may re-touch it.

**BARS PRE-REGISTERED (before any code):**
- **260-A (honesty):** with iOS health NOT granted, the Revoke row never
  reads ACTIVE; it names the real state and offers the action that
  matches. Unit-pinned across the matrix (flag×iOS-status, both
  sensors).
- **260-B (right toggle):** with master OFF and location stream ON, a
  location query's refusal names the MASTER switch; with master ON and
  the stream off, it names that stream; with iOS ungranted, it says so.
  Three distinct payloads, unit-pinned app-side + relayed in the
  plugin's tool text.
- **260-C (no regression):** #258's and 2A's existing pins stay green
  unmodified; the gate table's BEHAVIOR is unchanged by (A)/(B) — only
  what the UI and the refusal SAY changes.
- **260-D (gate):** full lane gate PASS, unit count moved.
- **260-E (device, Owen):** the contradiction is gone from the Privacy
  screen, and a refused query tells him which switch to flip — the one
  that actually unblocks it.

> **Update 2026-08-06 (late evening) — (C) ROUTED: ONE switch, relabeled
> (Owen's pick, on the recommended option).** The master switch governs ALL
> sensor egress — continuous streaming AND query-time answers — and its copy
> must say so honestly; the per-sensor toggles and iOS permissions stay as the
> finer gates beneath it. Consequences: (B)'s three payloads stand exactly as
> barred (master-off / per-sensor-off / iOS-ungranted), and "don't stream but
> you may ask" stays inexpressible BY DESIGN — recorded as the accepted trade
> (one privacy concept beats two similar-sounding ones). **ALL THREE FIXES NOW
> UNBLOCKED — lane opens now** on `claude/t27-260-privacy-legibility` (reset to
> current main; the branch predates tonight's commits). Fold in tonight's pass
> data: the 2A-F ON leg proved the iOS health grant EXISTS while the
> Permissions row had read NOT SET in the earlier pass — the row has been
> inconsistent across sessions, so (A)'s matrix must treat both readings as
> real specimens, not assume the flag side is the only liar.

> **Update 2026-08-06 (night) — BUILT, GATED, MERGED, DEPLOYED same evening as
> the routing. Bars 260-A/B/C/D MET; 260-E rides Owen's next device pass.**
> TDD throughout (every new pin watched failing first). **App:** PR #275
> (merge `ff0f24c`, Owen: "approved") — `RevokeRowState.compute(flag, iOS)`
> is the revoke row's single pure source (ACTIVE requires BOTH truths;
> NEEDS PERMISSION / OFF IN iOS / — carry the action that unblocks each);
> `PhoneQueryResponder.deniedGate` is the one gate table `answer()` itself
> consults, and the link decorates denials with additive
> `denied_gate`/`denied_stream` fields (legacy conformers ride a protocol
> default and keep the exact pre-260 body — both skew directions degrade to
> shipped behavior); master switch relabeled **"Share Sensors with Hermes"**
> with a caption naming both acts it gates. **GATE: PASS — 1668 → 1687 units
> (+19: 10 revoke-matrix, 5 responder, 4 wire), 12 XCUITest, Release green;
> every pre-existing pin untouched** (260-C held by construction — the
> classifier is consulted by the same `answer()` path that already returned
> `.denied`, and `PhoneQueryAnswer` itself is unchanged). **Plugin:** repo
> `talaria-plugin` main @ `4205d1a` (50 → 60 pytest), deployed on Owen's "Go"
> — live checkout fast-forwarded, gateway bounced (fresh PID 31094, start
> 18:59:11, "✓ talaria connected" logged), worktree cleaned. Denial prose now
> names master vs the actual stream toggle (weather names Location); a bare
> pre-260 denial keeps the generic prose byte-identical. **OTA staged from
> merged main for Owen's phone. NOTE for the device pass: OTA 2085 sends no
> gate fields — the named-gate prose needs the NEW install; the health
> Permissions row will also read honestly only per-launch (HealthKit hides
> read grants — see the (A) caveat in `RevokeRowState`'s doc).**

> **Update 2026-08-06 (late night) — 260-E MET on device (Owen, OTA 2095);
> ITEM CLOSED.** All four legs, live: **(1)** Privacy screen consistent —
> Permissions Health ENABLED + Revoke ACTIVE agree (both derive from the same
> live iOS status now; a cold launch reads ACTIVE because the upload service's
> launch-time `requestAuthorization` resolves silently in seconds — the
> NEEDS-PERMISSION state exists for the window before any request completes);
> relabel live ("Share Sensors with Hermes", `// Sensor Sharing`, both-acts
> caption). **(2)** Master OFF, location query → the master prose VERBATIM
> ("That one switch gates ALL sensor sharing — streams and queries alike…").
> **(3)** Master ON + Location toggle OFF, WEATHER query → "the Location
> sensor toggle is off… enabling Location is what unblocks this" — the exact
> cross-toggle case that misled Owen originally, now naming the right switch.
> **(4)** Location back ON → real answer ("Current location: 19200 Crestwick
> St, Saucier"), one retry needed (see #263's wake-miss). **Residual
> observation, filed not fixed:** the Revoke rows read from the flag×iOS
> matrix only, so with the MASTER off they still say ACTIVE while the hero
> reads SENSORS OFF — the bar's matrix was met as written; whether master-off
> should demote the row's wording is Owen's call if it ever grates.
> **The pass also flushed out two infrastructure defects → #263 (plugin
> transport: split hub + wake-miss) and #264 (gateway bind race, comes up
> without the chat plane and never retries).**

## 259. 🔓 The `.html` artifact preview has NO CSP — an agent-authored HTML file can beacon out and reach tailnet services — **FILED 2026-08-06 from #258's independent security review (§6, out of that lane's scope); no lane opened** — **✅ CLOSED 2026-08-06 late night: 259-F MET on device (OTA 2100) — script demonstrably executed inside the network-blocked sheet**

**The defect, clinically:** the `.html` preview route renders
agent-authored markup with **no content-security policy**, so the
document may load and contact arbitrary external resources. The `.svg`
route hardened in #258 has one; `.html`, shipped since #99, does not.
Demonstrated live during #258's review (it was that review's control
arm). The view's existing protections — nil base URL, one-shot
navigation policy, no script bridge, ephemeral store, no popups — stop
navigation and persistence but **not subresource loads**, which never
reach the navigation delegate. ATS does not cover it either: our single
exception is for insecure HTTP to the tailnet range, and HTTPS to any
host is permitted by default.

**Decision owed from Owen (this is the whole item):** applying #258's
SVG policy verbatim works mechanically, but HTML artifacts plausibly
*want* inline script — an interactive artifact is half the point — and a
deny-by-default policy removes exactly that. Three options: same-as-SVG
(safest, kills interactivity); a script-permitting policy that still
blocks network destinations (keeps interactivity, stops the leak —
likely right); or leave as-is with the exposure documented. Bars
pre-register here when a lane opens.

> **Mechanics, demonstrated behavior and the reasoning live in the
> security addendum OUTSIDE this repo** (`~/Documents/Claude/talaria-security-addendum.md`,
> §A1) — Owen's call 2026-08-06: decisions and fixes in the tracker,
> attack-shaped detail out of the repo. See #261 for why.

> **DECISION 2026-08-06 (late evening), Owen: scripts ON, network BLOCKED.**
> The `.html` preview gets a CSP that permits inline script but denies all
> network destinations — interactivity (much of the point of an HTML artifact)
> survives; the beacon/tailnet reach dies. Lane queued AFTER #260 per Owen's
> ordering; bars pre-register in this entry when it opens.

**LANE OPENED 2026-08-06 (night). Mechanism chosen before code:** a meta-CSP
cannot be injected into a full agent-authored document without markup-fragile
string surgery (and content preceding the injection point loads unprotected),
so the block rides **WebKit content rules** — a compiled
`WKContentRuleList` on the preview's configuration blocking `http(s)`/`ws(s)`
URL loads at the network layer, markup-independent, with `data:` untouched so
inline images keep working. Inline script never passes through a blocker, so
interactivity survives by construction. The #99 sandbox (one-shot navigation
policy, no bridge, ephemeral store, no popups) already kills navigation-shaped
egress (links, forms, meta-refresh, window.open) and stays unmodified.

**BARS (pre-registered, before any code):**
- **259-A (the leak dies, EMPIRICALLY):** in-suite against REAL WebKit — an
  artifact whose inline script beacons a local in-process HTTP listener
  produces ZERO hits under the shipped configuration, while the SAME artifact
  in a no-rules control arm produces the hit (the control proves the harness
  live — #258's review standard, now inside the suite instead of a macOS CLI).
- **259-B (interactivity survives):** an artifact whose inline script mutates
  the document demonstrably EXECUTED under the shipped configuration —
  scripts-on is a bar, not a hope.
- **259-C (fail closed, never blank):** if rule compilation/attachment fails,
  the preview degrades to the CODE VIEW (the malformed-SVG precedent) — no
  path renders an HTML artifact scripts-enabled without the rules attached,
  and no path paints a blank pane.
- **259-D (no regression):** #99's policy pins and #258's SVG pins stay green
  UNMODIFIED; the SVG route may additionally gain the rules (same vehicle)
  but its CSP and validator behavior change not at all.
- **259-E (gate):** full `lane-gate.sh` PASS, unit count moved (state the
  arithmetic).
- **259-F (device, Owen):** an interactive HTML artifact from a real Hermes
  turn runs its script on the phone (something visibly dynamic), rendering
  inside the sheet as before.

> **Update 2026-08-06 (late night) — BUILT, GATED, MERGED (PR #276, merge
> `79481b8`, Owen: "merge it"). Bars 259-A..E MET; 259-F rides the next OTA
> (staged from merged main same night).** TDD; the mechanism is a compiled
> `WKContentRuleList` blocking `http(s)`/`ws(s)` at the network layer —
> `data:` untouched, inline script untouched — with `HTMLPreviewView`
> requiring the rules BY TYPE and `HTMLArtifactPreview` failing CLOSED to
> the code panel if compilation ever fails. **259-A verified empirically
> IN-SUITE**: a no-rules control arm leaks to a live in-process listener;
> the shipped configuration posts zero — and the zero only counts after the
> artifact's own script-ran marker proves the document was ALIVE, because
> **the first version of this test passed falsely**: a dangling weak
> `navigationDelegate` left the page blank, and a blank page can't beacon
> (#258's "green suite certified a blank pane", recurring — caught because
> 259-B failed loudly beside it). The generalized rule, now encoded in the
> test and on the production helper: assert the subject is alive before
> accepting silence as success. **GATE: PASS — 1687 → 1693 units (+6), 12
> XCUITest, Release green.**

> **Update 2026-08-06 late night — 259-F MET on device; ITEM CLOSED.** Owen, on OTA
> 2100 (main @ `79481b8`): asked Hermes for a 404 page, "techy, creative" —
> it produced `404-terminal.html`, an interactive rescue-shell page. His
> first report ("Able to view it on the phone… i wouldn't say its
> interactive") proved rendering but not script execution, so the artifact
> file was read from the host: its static markup is an EMPTY terminal, a
> clock stuck at `--:--:--`, incident `#0000` — every visible line of the
> terminal is inserted by the page's own JS (`typeLines`), and the clock
> ticks from a `setInterval`. Owen's confirmation, verbatim: *"Yes. Text
> types out at the bottom, red flashes on the http 404 badge at the top,
> time towards top right, Title header 404 jiggles."* The typed-out text
> and live clock are JavaScript (the badge flash and 404 jiggle are CSS and
> carry no script evidence on their own) — so scripts ran, in the sheet,
> under the shipped egress-blocked configuration. **Scripts on, network
> blocked, verified end to end on device. All six bars MET.**

## 258. 🖼️ ARTIFACT PANES v2: agent files appear WHILE the turn streams, and SVG renders instead of "unsupported" — **ROUTED + APPROVED 2026-08-06 (Owen: "5. approved" then "f1 looks good"); design proposal read and blessed; bars pre-registered below BEFORE the build** — **✅ CLOSED 2026-08-06 late evening: all five bars MET (258-E on device), white canvas DECIDED (stays white), chip relocation spun off to #262**

**Framing (established by the terrain map, `G-preview-panes-terrain.md`,
and the approved proposal `planning/superpowers/specs/2026-08-06-f1-artifact-panes-proposal.md`):
this is an ITERATION on shipped work, not a new subsystem.** #21 (SSE
reconstruction) and #99 (preview sheet) shipped 2026-07-12 — agent files
already open in a sheet with Markdown, syntax-highlighted code, and HTML
in a hardened WKWebView. Two gaps make it feel unlike the desktop's
artifact panel, and only those two are in scope:

1. **Mid-turn rendering.** `producedFiles` accumulates during streaming
   (`SessionsHermesClient.swift:321-373`) but is assigned to the message
   only at `run.completed` (`:442-448`) — the tool pill is live, the
   openable chip is not. Fix: stream artifacts as they arrive.
2. **SVG route.** `FilePreviewRoute` (`FilePreviewSheet.swift:21-56`)
   routes html/markdown/code/unsupported; **`.svg` falls to
   `.unsupported`** despite being the named differentiator. Fix: route it
   through the existing hardened WKWebView path.

**Deferred with reasons (Owen approved the deferrals):** revision chains
(needs a data-model change), cross-session gallery (browse feature; wants
Phase 3 media settled first), mermaid (bundling a JS renderer is a
supply-chain call, not a polish-lane call), Quick Look (pays off only
when real binaries arrive), widget/Live-Activity surface (decoration).

**BARS PRE-REGISTERED (before any code; a missed bar is a falsification):**
- **258-A (mid-turn):** in a live turn where the agent writes a Markdown
  file, the chip appears and is openable BEFORE `run.completed`, shows
  the content it had at that moment, and does NOT duplicate when the turn
  finishes (exactly one chip per written file).
- **258-B (svg):** an agent-written `.svg` opens and renders as a graphic;
  malformed SVG degrades to the code view — never a blank pane, never a
  crash.
- **258-C (no regression):** every existing #21/#99/#235/#237 test
  (reconstruction, preview routing, stream recovery, dedupe, stall)
  stays green UNMODIFIED — this lane may not edit those pins to pass.
- **258-D (gate):** full `lane-gate.sh` PASS, unit count MOVED by the new
  tests (state the arithmetic).
- **258-E (device, Owen):** ask Hermes to write a file on a real turn —
  the chip shows up while it is still talking; an SVG diagram renders.

**✅ BUILT + MERGED 2026-08-06 (PR #274, `270551c`), same day as the
approval.** Two commits + one security-fix commit; **GATE: PASS — 1650 →
1668 units** (+18: 5 streaming pins, 11 SVG pins, 2 from the fix round;
one pin was INVERTED in place so it doesn't move the count) + 12 XCUITest
+ Release green. **Bars 258-A/B/C/D MET** (258-C held by construction —
the T1 diff was 448 insertions / 0 deletions, so no existing pin could
have been edited); **258-E rides the OTA**.
- **Mid-turn:** new `StreamingUpdate` case yielded the moment
  `parseWrittenFile` produces an attachment; `.finished` MERGES on
  attachment `id` (run.completed's list leading) so a streamed chip and
  its final twin collapse to one row while a streamed-only chip can't
  vanish. Same path written twice still yields two chips — unchanged
  from pre-lane behavior; the lane changes WHEN chips appear, never how
  many.
- **SVG:** routed through the UNMODIFIED `HTMLPreviewView` behind
  `default-src 'none'; base-uri 'none'; form-action 'none'; style-src
  'unsafe-inline'; img-src data:`; malformed SVG detected at
  content-resolution time (routing is a pure function of the file NAME
  and has no bytes to judge) and degrades to the code view. `svgz`
  deliberately NOT routed (gzip; the stack is UTF-8 text end to end) and
  pinned so it reads as a decision.
- **🔒 The independent security review is the story of this lane.** Two
  things it established, both worth not re-litigating: the deny-by-
  default policy on the SVG wrapper **is genuinely enforced** (verified
  against real WebKit with a control arm proving the check was live —
  not assumed from the code), and the pre-render validator **does NOT
  constrain what the renderer builds** (it parses as strict XML; the web
  view parses as HTML). The wrapper is safe because of the POLICY, not
  because of validation — the code comment now says so and a pin holds
  it there. **If anyone ever proposes relaxing the policy because "the
  validator guarantees a clean tree" — it does not.** The review also
  caught a **BAR VIOLATION the suite was certifying green**: a
  namespace-prefixed `<svg:svg>` root passed the validator but paints a
  BLANK PANE (258-B says never blank). Fixed: prefixed roots reject to
  the code view; the test that pinned the acceptance was inverted.
  Fuller reasoning in the out-of-repo security addendum §A2.
- **⚠️ THE LESSON (implementer's own words, worth carrying):** *"I wrote
  a pin from how `XMLParser` reports names, never from how WebKit
  renders — so a green suite certified a blank pane."* Same family as
  the stale-incremental and zero-tests-under-`TEST SUCCEEDED` traps: the
  test agreed with the code and both were wrong about what the USER
  would see. When a pin describes rendering, it must be written from the
  renderer's semantics, not the parser's.
- Open for Owen's device pass beyond 258-E: the SVG canvas is WHITE
  (right for black-stroke diagrams, wrong for dark-authored SVGs — a
  judgment call worth an eyeball), and the CSP enforcement check ran on
  macOS WebKit rather than the iOS 27 sim (same engine core; a cheap
  repeat would close the last inch).

> **Update 2026-08-06 (late evening) — 258-E MET on device (Owen, OTA 2085, Mac
> profile; deepseek-flash + kimi runs).** Both halves:
> - **Mid-turn chip:** on BOTH prompts the chip appeared while the turn was
>   still streaming and was tappable before the reply finished. Owen: *"IF
>   YOU'RE FAST ENOUGH, you can tap it before the response loads. With Deepseek
>   flash though, damn, no chance - Switched to kimi and I barely beat it."* The
>   race is purely against model speed — designed behavior. Exactly one chip per
>   file after finish; the 258-A merge held on device.
> - **SVG:** `talaria-arch.svg` rendered as a real graphic (boxes, arrows,
>   grid, mono labels) — not "unsupported", not blank.
> - **NEW OBSERVATION (Owen's, filed not fixed):** *"The generated file doesn't
>   stay in line where its generated, its moved to the end of the response on
>   both a and b"* — the chip renders inline at the generation point mid-turn,
>   then RELOCATES to end-of-response when `.finished`'s run.completed list
>   takes the lead. One chip, no dupe — the bar held — but placement is not
>   stable across the finish boundary. Owen's call whether placement-stability
>   becomes a lane.
> - **White-canvas specimen observed live:** kimi authored a DARK SVG (slate
>   background baked into the file), so the predicted mismatch appeared — a
>   dark strip floating on the white preview canvas. Owen's aesthetic verdict
>   pending.

> **Closure 2026-08-06 (late evening):** Owen's two calls came back. **The SVG
> canvas STAYS WHITE** — a decision now, not a default: bare SVGs render on a
> light canvas the way browsers and GitHub treat them, and dark-authored SVGs
> bake their own background (tonight's specimen did exactly that). **The
> chip-relocation observation is PROMOTED to #262**, its own lane, queued
> behind #260. With 258-A..E all MET, this item CLOSES. One non-blocking
> nicety stays on the record: the CSP enforcement check ran on macOS WebKit
> rather than the iOS 27 sim — a cheap repeat closes that inch if anyone ever
> wants it.

## 90. 📝 DEVELOPMENT_TEAM placeholder — deferred to go-public cleanup — **✅ CLOSED 2026-08-06 late night (triage sweep): archived as terminal**

`project.yml` (and the generated pbxproj) carry the hard-coded Apple `DEVELOPMENT_TEAM`
(`DNL25ZFSD2`). Team IDs are not secrets — this one is embedded in every build's provisioning
profile and already sits throughout public git history, so scrubbing HEAD now buys nothing
(a history rewrite would break every open branch for zero security gain).

**Decision 2026-07-10:** leave as-is for the personal-fork phase. **If the repo goes properly
public / contributor-facing**, swap to a placeholder + developer-local override (e.g. gitignored
local signing config) as part of a broader signing-config cleanup, alongside bundle-ID
genericization. Until then, outside builders set their own team in Xcode per README §Setup
step 5. Whatever mechanism is chosen must survive `xcodegen generate` (same class of concern
as the `aps-environment` regen rule).

Logged 2026-07-10.

> **Update 2026-08-06 late night — ARCHIVED as a decision record (oldest-20 triage sweep, Owen's call).** The 2026-07-10 decision stands: leave as-is for the personal-fork phase; re-open only if the repo goes public/contributor-facing.

## 55. 💤 OJAMD service layer reverted to out-of-the-box (2026-07-04) — relay portion SUPERSEDED by NSSM reinstatement (#88, #98, #105); gateway/connector Startup-script arrangement still current — **✅ CLOSED 2026-08-06 late night (triage sweep): archived as terminal**

> **Audit 2026-07-13:** Confirmed the auditor's core finding but the scope was overstated — this is a *relay-only* reversal, not a full service-layer reversal. Item 55's own latest dated note (2026-07-08, "gateway operations recipe") still describes the gateway as a Startup-launched `pythonw` (via `Hermes_Gateway.vbs`) and predates the reversal, so it does not self-contradict. The contradiction comes from later items: #88 (RESOLVED 2026-07-09) verifies "the relay is NSSM-managed again (`HermesMobileRelay`... nssm.exe → uvicorn)"; #98's 2026-07-12 deploy note uses "elevated `Restart-Service HermesMobileRelay`"; #54's 2026-07-12 update references "the #98 deploy restart of `HermesMobileRelay`"; and #105 (Fixed 2026-07-12) retires the stray `Hermes_Relay.cmd` Startup script specifically because "the relay is NSSM-owned now," calling it "#55's competing-launch-layers problem in mirror image." All four citations verified verbatim at their cited lines. However, #103 (2026-07-11 post-mortem) and #105 itself both state the **gateway and connector are still on #55's Startup-script arrangement** ("HermesGateway now runs as a user pythonw process... not an NSSM service"; "the connector is a plain bat-launched process and the gateway runs as Owen's user pythonw... neither is a service") — so "SUPERSEDED by NSSM reinstatement" as a blanket claim overstates it; only the relay flipped back. (Side note: CLAUDE.md's "OJAMD services" section calling the gateway a "scheduled task" is itself inconsistent with #103/#105's more granular, dated account and is worth a spot-check next OJAMD pass — not something this audit can resolve.) Of item 55's 4 remaining checklist bullets: #1 (PYTHONUTF8 in both bats) is independently mooted by #87's source-level `encoding="utf-8"` fix across 17 subprocess sites (deployed + verified 2026-07-11, connector suite 104/1 skipped) — a durable fix that doesn't depend on the bat env var at all; #3 (reboot/login validation) was not technically validated but was effectively closed by #105's explicit "accepted, not fixed" policy call (Owen: attended-reboots-only, 2026-07-12). Bullets #2 (rework the "Restart All" shortcut, still described as referencing deleted services as of #54's 2026-07-04 evening note) and #4 (first real `hermes-update-safe.ps1` run) have **no confirming evidence anywhere in OPEN_ITEMS.md** and should be carried forward as genuinely open, not swept away by the supersession framing. Precedent for this kind of retroactive annotation already exists in this file: item 24i carries a "> **SUPERSEDED 2026-07-04 by #55**" blockquote added after the fact while keeping its own ✅ header — #55 deserves the equivalent treatment now that its relay premise has been reversed.

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

**Update 2026-07-08 — gateway operations recipe (learned the hard way):**
- **The gateway is a detached `pythonw`** launched at login by
  `Hermes_Gateway.vbs` (Startup shim → `%LOCALAPPDATA%\hermes\gateway-service\Hermes_Gateway.vbs`).
  **Restarting the Hermes desktop app does NOT restart it** — config changes require killing
  the process that owns `:8642` and relaunching via the vbs (`wscript.exe <real vbs path>`).
- **New MCP tools need TWO things:** the tool must be in the server's `tools/list` AND in
  the `tools.include` allowlist under the server's block in `HERMES_HOME\config.yaml`
  (`C:\Users\Owen\AppData\Local\hermes\config.yaml`). The hermes_mobile allowlist predated
  the #45 producer tools and silently filtered them; `send_inbox_item` + `get_inbox_verdict`
  were added 2026-07-08. Config is validated at gateway start only.
- **Boot window quirk:** right after a gateway start, MCP sessions can be listed-but-dead
  for ~1–3 min until the keepalive reconnects (a tool call in that window fails in 0.01s
  with `ClosedResourceError`); one retry after the keepalive cycle succeeds.
- Also: a relay socket can die with `WinError 64` accept-loop crash while the process
  lingers — kill the pid and relaunch `scripts\start-relay.bat` detached (quote-safe: launch
  the `O:\` bat directly; the Startup wrapper path contains spaces and silently no-ops if
  passed unquoted to `Start-Process`).

> **Update 2026-08-06 late night — ARCHIVED as graduated (oldest-20 triage sweep, Owen's call).** The service-layer facts live in CLAUDE.md's 'OJAMD services' section (the living copy). The one open bullet — a first real `hermes-update-safe.ps1` run — is moot: CLAUDE.md records 2026-08-04 that Owen's actual practice is bare `hermes update` and that this is fine.

---

## 83. 📝 Display Zoom "Larger Text" letterboxes T27 on iPhone18,2 — beta interplay, NOT app layout + toolchain-provenance rule — **✅ CLOSED 2026-08-06 late night (triage sweep): archived as terminal**

**The 2026-07-08 evening "text clipped on the left" chase, resolved.** With Display Zoom =
Larger Text, T27 renders in a **402×874pt window** (iPhone 17 Pro metrics) on the 440×956pt
17 Pro Max panel, positioned ~27pt off-screen-left with a black band right/bottom — measured
from native screenshots (window 1206px @ x≈−81 on the 1320px panel) and confirmed in-process
(`UIScreen.main.bounds` = 402×874). Default zoom renders correctly. **Not caused by the
#44–#49 wave** (receipt, tool chip, plist, scene manifest, launch screen all individually
exonerated — runtime `sizeThatFits` measurements, plist diffs, and a full-width Pro Max
*simulator* control on OS `380g`).

**Trigger matrix:** phone updated to iOS 27 beta `24A5380h`; tonight was the **first device
install built from Xcode-beta3** (SDK `24A5380g`, installed 7/2) — all prior installs were
Xcode-beta seed 1 (SDK `24A5355p`) and rendered fine under Larger Text, as does Talaria
prime (stable Xcode 26 SDK). Classic linked-on-or-after behavior flip meeting a beta bug
(likely interacting with `UIApplicationSupportsMultipleScenes: true` from the CarPlay
manifest). **Workarounds:** Display Zoom → Default (Owen's current state), or test
`UIRequiresFullScreen: true` in project.yml (untried); likely self-resolves on a future
beta seed — file Apple Feedback with the reproducer above.

**HARD RULE going forward: record which Xcode seed built each device install.** SDK flips
masquerade as app regressions — tonight's cost an entire evening. Multiple Xcode betas
coexist on the Mac (`Xcode-beta.app` = seed 1, `Xcode-beta3.app` = seed 3, GUI vs
`DEVELOPER_DIR` CLI can silently differ); when a device-only behavior "starts today,"
check `DTXcodeBuild`/`DTSDKBuild` in the installed app's Info.plist against the previous
install *before* auditing app code.

Logged 2026-07-08.

> **Update 2026-08-06 late night — ARCHIVED, framing obsolete (oldest-20 triage sweep, Owen's call).** The multi-beta toolchain-provenance scenario this item warns about no longer exists: Xcode-beta.app and Xcode-beta3.app were deleted 2026-07-24 (CLAUDE.md, Build/tooling). Whether the letterbox itself still reproduces under beta4 is a one-line re-test now queued in dispatch/DEVICE-PASS-RUNNING-LIST.md; if it does, file a NEW item — do not reopen this one.

---

## 34. 🔧 T6 — Mac-hosted Talaria backend (unlocks additive Apple connectors) — ACTIVE (un-deferred 2026-07-12); Phase 1 → #107 — **✅ CLOSED 2026-08-06 late night: SUBSUMED into #107 (triage reconciliation)**

> **Audit 2026-07-13:** Header's cross-reference is off by one item — 'Phase 1 → #106' should read '#107'; #106 is a different item entirely (P8 IR v0 / Lane D / PR #65). #107 (the correct Phase-1 tracker, matching the body text's own citations) confirms scaffolding merged via PR #79 but the Mini-execution checklist is still fully unchecked, so 🔧/merged-unverified remains the right status — only the number needs fixing.

**Update 2026-07-12:** un-deferred by Owen. Spec v0.2 committed at
`design/T6_MAC_BACKEND_SPEC.md` (architecture verified against the OJAMD deployment; Q1–Q5
decision defaults in §7); Phase 1 (re-home relay + connector, reboot-proof launchd
hardening for all four services) is tracked with a full execution + device checklist in
**#107**, ops runbook at `relay/docs/DEPLOY_MAC.md`. Phase 2 = #33's server-side connectors.
The "Windows brain, Mac hands" accelerator below is now a documented runbook section
(DEPLOY_MAC.md), still optional and independent. Non-goal reaffirmed: Phase 1 does NOT make
the Mac the phone's primary host — that reversal of the #1 consolidation stays deliberate.
Correction to the old note: #24f is NOT a Phase-1 work item — the live relay is DB-backed
and persistence is verified (#24f closed 2026-07-12).

**Deferred rationale (Owen, 2026-06-28, superseded 2026-07-12):** hold until the app is closer to feature-complete —
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

> **Update 2026-08-06 late night — ✅ SUBSUMED INTO #107 (oldest-20 triage sweep reconciliation).** #34's own header hands Phase 1 to #107 and Phase 2 to #33, and #107's closure ('T6 Phase 1+2 — EXECUTED + reboot-verified') covers the Mini checklist: 8 of 11 lines confirmed done with citations in #107/#114/#54; the Mac-relay sensor-delivery line was SUPERSEDED by #114's deliberate design (sensors pinned to OJAMD permanently — the 2026-07-16 device note confirms 'SENSORS badge stayed pinned to OJAMD while Mac was active'); the run-completion-APNs line is MOOT (#238 deleted the push-watch/APNs surface app-wide, commit e32f554, 2026-08-03); the optional 'Windows brain, Mac hands' accelerator was explicitly declined in the T6 spec and stays unbuilt by choice. Anything Mac-host that resurfaces files NEW items.

## 265. 🎨 Artifact chip anchor can split a word — the #262 pin is honest but lands mid-token ("The file lan ⟨card+chip⟩ ded at ~/…") — **FILED 2026-08-06 late night from Owen's first 262-E screenshots on OTA 2107** — **✅ CLOSED 2026-08-07: 265-E MET on device (OTA 2120), all bars MET**

Observed on the first #262 device run: Deepseek-flash narrated across the
write ("…The file landed at…") and the tool fired mid-word, so the anchor
(content length at fire time) split "landed" into "lan" / "ded" around the
tool card + chip. Placement is stable — the #262 bars all held — this is
purely where the split point falls when the model narrates THROUGH a tool
call instead of pausing at a sentence boundary.

**Fix shape (small, display-side):** when building the transcript layout,
snap each anchor BACK to the last whitespace/newline at-or-before the raw
offset before emitting the text split (clamp math otherwise unchanged;
equal-anchor grouping still applies after snapping). Pure function change
in `MessageBubble.transcriptLayout` — the stored anchor stays raw and
honest; only the rendered split moves. Bars pre-register here before any
code, per convention.

**BARS — written 2026-08-06 late night BEFORE any code:**
- **265-A (unit, the snap):** an anchor landing mid-word renders its split
  at the last whitespace at-or-before the raw offset — the haiku shape
  ("The file lan⟨items⟩ded at…") becomes "The file " ⟨items⟩ "landed at…".
  The STORED `anchorOffset` stays raw — pinned by asserting the model value
  is unchanged by rendering.
- **265-B (unit, ordering preserved):** snapping never reorders or
  un-groups — equal raw anchors still share a group after snapping; two
  different raw anchors that snap to the same boundary merge into one
  anchor point with tools-before-chips order preserved; a snapped anchor
  never moves before the walk cursor (the existing clamp still binds).
- **265-C (unit, degenerates):** an anchor already at a boundary is a
  no-op; an anchor inside a run with no whitespace before the cursor
  clamps to the cursor; out-of-range anchors clamp exactly as today
  (#10's clamp pin stays green untouched).
- **265-D (gate):** full lane gate green, unit count MOVED, Release
  included.
- **265-E (device, Owen):** re-run the narrate-through-a-write shape — the
  split lands on a word boundary (no "lan/ded"), and #262's stability
  semantics are unchanged (chip under the card, no movement, tappable).

> **Update 2026-08-07 — 265-E MET on device (OTA 2120); ITEM CLOSED, all
> bars MET.** Owen, same narrate-through-a-write prompt on Deepseek flash
> that produced the defect 12 hours earlier: *"chip stayed put. Locked to a
> word instead of splitting one."* The mid-token split is gone and #262's
> stability semantics held in the same turn. Lane total: filed from a device
> screenshot, bars pre-registered, RED witnessed with the exact device shape,
> GREEN, gated (1698→1705), merged (PR #278), OTA'd, and device-verified —
> inside one night.

## 262. 🎨 Artifact chip placement is not stable across the finish boundary — inline at the generation point mid-turn, then JUMPS to end-of-response at `run.completed` — **FILED + ROUTED 2026-08-06 late evening (from 258-E's device pass; Owen picked "lane, queued behind #260")** — **✅ CLOSED 2026-08-07: 262-E MET on device (OTA 2120), all five bars MET**

Observed by Owen on OTA 2085, both 258-E runs: *"The generated file doesn't
stay in line where its generated, its moved to the end of the response on both
a and b."* Mechanism: the streamed chip renders at the generation point (below
the tool-activity card) while text continues streaming beneath it; at
`run.completed` the `.finished` merge's canonical list takes the lead and the
chip re-anchors to end-of-response. Exactly one chip either way — #258's
dedupe bar held — the defect is PLACEMENT ONLY.

**Likely fix shape (to be validated when the lane opens):** anchor the chip
below the streaming text for the whole turn — the transcript's final layout —
so the finish boundary changes nothing. The alternative (pin the streamed
inline position permanently) fights `run.completed`'s list-led merge and makes
the final transcript depend on WHEN a tool fired mid-prose; lean away.

**Queued behind #260. Bars pre-register HERE before any code.**

**Update 2026-08-06 late night — lane opened; mechanism validated and the filed guess
FALSIFIED in both halves (recorded, not redefined):**
1. **There is no discrete `run.completed` re-anchor.** The chip renders in a
   fixed after-transcript section (`MessageBubble.hermesAttachments`, after
   `interleavedTranscript`) at every instant. At `.artifactProduced` time the
   streamed message happens to END at the generation point, so the chip
   momentarily sits below the write_file tool card; each subsequent
   `assistant.delta` grows the transcript's trailing text segment ABOVE the
   grid, pushing the chip down delta-by-delta until it lands at
   end-of-response. A fast model (Owen's Deepseek-flash run) makes the slide
   read as a jump. The `.finished` merge only dedupes the attachment list —
   it never changes where the grid renders.
2. **Consequently the filed "likely fix shape" — anchor the chip below the
   streaming text for the whole turn — describes CURRENT behavior.** It is a
   no-op, and the lean away from the inline pin was backwards. The fix that
   changes what Owen observed is the inline pin: the same anchoring
   convention tool chips have had since #10 ("the final transcript depends on
   WHEN a tool fired" is #10's shipped, accepted behavior for the very card
   this chip appears under).

**Fix shape (routed by the validation):** `MessageAttachment` gains optional
`anchorOffset: Int?` (synthesized Codable — pre-lane caches decode nil);
`ChatStore` stamps `content.count` at `.artifactProduced` (mirror of the tool
chip stamp); the transcript builder interleaves anchored attachments at their
offsets; unanchored attachments (old caches, Tier-2 fetchables appended at
finish) keep today's trailing grid; the `.finished` id-dedupe transfers the
streamed anchor onto the final-list twin.

**BARS — written 2026-08-06 late night BEFORE any production code:**
- **262-A (unit, placement + boundary):** for content with a write_file
  activity and an artifact anchored mid-content, the segment list places the
  artifact chip AT its anchor, between the surrounding text runs — and the
  list is IDENTICAL for the streaming and finished renders of the same data
  (the finish boundary changes nothing).
- **262-B (unit, conservation + degrade):** every attachment renders exactly
  once — anchored → inline, unanchored (nil anchor) → trailing grid with
  layout identical to today; an anchored attachment on a message with NO tool
  activities still renders (never vanishes).
- **262-C (unit, merge):** `.finished` delivering a same-id anchorless twin of
  a streamed anchored artifact resolves to ONE row carrying the STREAMED
  anchor; two genuine writes to one path stay two rows (258-A re-asserted).
- **262-D (gate):** full lane gate green — unit count MOVED, Release build
  included.
- **262-E (device, Owen):** fast-model artifact turn — the chip appears under
  the write_file card and DOES NOT MOVE while text streams beneath; tappable
  mid-turn; after relaunch/history reload the placement persists (anchor is
  persisted with the message).

> **Update 2026-08-06 late night — BUILT + GATED; PR #277 open, awaiting Owen.** TDD
> with every RED witnessed (compile RED for `transcriptLayout`/`anchorOffset`,
> runtime RED for the merge transfer). Bars 262-A/B/C MET in-suite; #10's
> segment pins and #258's merge pins stayed green. **262-D MET — GATE: PASS,
> 1693 → 1698 units (+5), 12 XCUITest, Release green.** Owen independently
> re-confirmed the defect on OTA 2100 mid-lane ("Chip still relocated and
> stayed at the bottom of the generated text" — that build predates the fix).
> 262-E rides the first OTA after merge.

> **Update 2026-08-06 late night — MERGED (PR #277, `6b2f6d6`, under Owen's
> tonight-scoped merge clearance); OTA 2107 staged and installed; first
> 262-E evidence IN (partial).** Owen's screenshots of the narrate-through-
> a-write prompt (Deepseek-flash, 10:31 PM) show the fix live: the
> write_file card AND the chip sit inline at the generation point with the
> narrative continuing beneath — on 2095/2100 that chip sat below the
> syllable check at end-of-response. **The same screenshots caught a
> cosmetic wart, filed as #265:** the raw anchor split the word "landed"
> ("The file lan" ⟨card+chip⟩ "ded at ~/…"). Placement stability held;
> the split POINT is the new item. **262-E still owed (a still image
> cannot show them): no movement DURING streaming, mid-turn tap opens the
> preview, and placement survives kill+relaunch. Queued in the 2026-08-07
> consolidated device run.**

> **Update 2026-08-07 — 262-E MET in full on OTA 2120; ITEM CLOSED, all five
> bars MET.** The three parts a still image could not show were run in the
> consolidated device session and all passed: no movement during streaming
> (Owen: *"chip stayed put"*), the mid-stream tap opened the preview without
> racing the model, and the placement survived kill + relaunch + history
> reload — confirming the anchor persists with the message, not just within
> a live turn. The word-split wart the first screenshots caught was fixed in
> the same window as #265 and verified in the same prompt.
