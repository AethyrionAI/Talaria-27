# Talaria — Open Items / Follow-ups

**Compiled:** 2026-06-23 · **From:** the models-shim / Phase-B wiring session.
**Landed this session (on `main`, merge `98a9a89`):** T1 (Settings→Models dual-write
picker), T2 (regex + copy fixes), shim cache-bust. See the merge commit for detail.

Status legend: 🔧 in progress · ⛔ blocked · 💤 dormant · 🐛 bug · 📝 note / decision · ✅ done.

> **Accuracy audit — 2026-07-13.** All 112 items were re-checked against `origin/main` (tip `cca1345`), merged-PR/closed-issue state, and on-disk code. Corrections are flagged inline as `> **Audit 2026-07-13:**` blockquotes. Summary: 65 items accurate as-was; 13 status-flips (3 shown ✅ but actually open — #17/#18/#31; 7 shown open but actually done — #37/#47/#48/#49/#55/#76/#94; 3 header-vs-body contradictions — #25/#79/#102); 34 'merged-unverified' items whose 'built in cloud / not compiled / needs merge' wording was stale (PRs since merged — device-verify is the only work left). Full write-up: `design/OPEN_ITEMS_AUDIT_2026-07-13.md`.
>
> **Eve session 2026-07-13.** Device+sim pass: #18/#50/#53/#63/#64/#65/#71 device-verified → ✅; #66 FAILED → 🐛; #61 fail root-caused + fixed (branch); PCC send-crash (#72) + churn (#111) closed by a `pccGrantConfirmed` stopgap (branch); iPad Hermes-switch diagnosed (provisioning + nudge branch); #93 fidelity gate still owed (sim skips it). New cloud dispatches: #104, #110. Build ✅ at cf5609f (iOS 27 sim), suite 582/582.

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

> **Audit 2026-07-13:** Stale wording — 'Production reads the Keychain... only' is no longer accurate. `AppContainer.swift:292-314` shows a 3-tier token provider: (1) Keychain shim token, (2) `#if DEBUG` `TALARIA_SHIM_TOKEN`, (3) fallback to the Hermes API key — the zero-token dual-auth fallback OPEN_ITEMS item #14 shipped (line 749, 'Resolved 2026-06-26') and CLAUDE.md's Auth section now documents as current. Body text should describe the 3-tier fallback, not 'Keychain… only'.

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

## 21. 🔧 Present/download agent-generated files — Tier 1 ✅; Tier 2 relay route ✅; Tier 2 app-side fetch MERGED (PR #99, 2026-07-16) — dual-host device pass owed

> **Tier 2 app-side MERGED 2026-07-16 (PR #99, branch `claude/fable-t27-21-agent-appfetch-prvsf2`,
> 10 commits).** Built to the probe verdict (binaries never ride SSE; `write_file` never fires for
> them): two-layer trigger — content-absent write tools still stage/fetch, but the load-bearing
> path is the announcement scan (case-insensitive `MobileDL/<segments>` harvest from tool payloads
> + final prose, deduped vs Tier 1, attached at run.completed). Lane M compliant: attachments
> stamped with the hop's birth `profileID`; fetch via `ProfileRelaySessionFactory.downloadAgentFile`
> (profile-scoped bearer, that profile's relay; dormant 401 → one refresh+retry, active 401 → #15
> ladder). Bonus fix: Windows `write_file` path tails (`lastPathComponentAcrossHosts`).
> Mac loop: regen clean (entitlements survived), BUILD SUCCEEDED first compile, one test-target
> fix (a `#"..."#` raw literal whose JSON contained `"#` — closed the string mid-line; now
> ##-delimited), full suite **671 tests / 55 suites green**.
>
> **Device pass (dual-host, queued):** `probe-t21.pdf` already sits in the Mac's MobileDL as a
> fixture — task the Mac, tap the chip, preview + ShareLink; repeat against OJAMD. Two things to
> eyeball: (1) announcement-scan noise — ANY turn mentioning a MobileDL path grows a bubble (the
> listing behavior as specced); if it grates, narrowing to write-shaped tools is a small follow-up.
> (2) One relay-side check: confirm the device-files route rejects traversal (`MobileDL/../x`) —
> the client regex admits `..` as a segment, so the server whitelist is the enforcement boundary.

> **Dispatch spec 2026-07-13 (eve):** `dispatch/FABLE-T27-21-agent-files-tier2-appfetch.md` (probe-first). Note: the OJAMD binary-`write_file` probe can't run from cloud CC — it's a local/after-work step. App-side fetch still to build.

> **Audit 2026-07-13:** Header's 'Tier 2 (relay) follow-up' is stale wording — the relay route (GET /v1/device/files, relay/app/main.py:976) has been built, deployed, and smoke-tested live on OJAMD since 2026-06-27 per this item's own note. The real outstanding piece is Tier 2 APP-SIDE fetch (a RelayAPIClient download call + content-absent branch in parseWrittenFile) — confirmed absent from the working tree; no movement on it since the 2026-06-27 note.

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

## 24. 🔧 OJAMD server-side work — 422 → Mac-side; Private Relay onboarding doc shipped (README.md + docs/index.html, 2026-07-10) — diagnostics-panel check (#24e) still open; relay-JWT persistence CLOSED 2026-07-12 (#24f) (bind/firewall/persistence/update-stability ✅)

> **Audit 2026-07-13:** 24e's 'documented in onboarding/setup instructions' ask is done, not open as the rollup header implies — README.md's '6 — Pair on first launch' + 'Network notes' sections (README.md:131,168, added 2026-07-10 in commit 9964f02) and docs/index.html:451 both carry the iCloud Private Relay warning, on top of the pre-existing CLAUDE.md gotcha. Only the 'checked in the diagnostics panel' half of 24e remains open: `grep -rn "Private Relay" Talaria/` is empty and DiagnosticsSettingsScreen.swift's relay rows check pairing/session state only — so 🔧 stays correct, but 'doc … remains' is stale wording. 24f's 2026-07-12 closure is independently corroborated by commit 6630908 ('#98 DEPLOYED, #24f CLOSED … #24 rollup header updated to reflect #24f closure'), and that same commit is what left the doc wording stale. 24a/b/c/d/g/h/j check out as claimed; 24i's ✅ is already self-flagged SUPERSEDED 2026-07-04 by #55 inline.

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

### 24f. ✅ Relay JWT signing secret + device registry not persisted across restarts — RESOLVED 2026-07-12

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

**Closed 2026-07-12.** The one remaining config check is done. Pinned `DATABASE_URL=sqlite:///O:/Hermes/Talaria/relay/hermes_mobile.db` (absolute) in the live OJAMD relay `.env`, and verified through `app.config.Settings.from_env()` that it resolves to the **same** live `hermes_mobile.db` (no orphaned pairings). Restart-survives-pairing confirmed by the #98 deploy restart: the connector re-authed against the freshly-restarted DB-backed relay with no re-pair and no 4401 (auth is opaque tokens hashed into `auth_sessions`; nothing regenerated on restart). DB-backed persistence across restart is now empirically confirmed on OJAMD. Nothing left server-side.

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

**Discord — SET UP / CLOSED (2026-07-09, Owen):** `DISCORD_BOT_TOKEN` present in `.env` (verified this session), bot created + invited, gateway serving it. Same `HermesGateway` process, no new service.

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

## 31. 🔧 Paste image into the chat composer — #43 send-side fix merged to main; full paste-then-send flow not yet re-verified on device

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

## 33. 📝 Apple app integrations — device-side EventKit shipped (#69/#70); Mac-host layer LIVE 2026-07-15: iMessage ✅ Notes ✅, FindMy parked, Photon rejected

> **Update 2026-07-15:** the server-side layer is no longer gated — #107 Phase 2 executed.
> iMessage (imsg sender / BlueBubbles reader) and Notes (memo + AppleScript) verified end-to-end
> agent-driven on the Mini. FindMy parked (pyicloud path documented in #107). Reminders skill
> exists server-side (`remindctl`, not installed) but is redundant with device-side EventKit.
> Reaching these from the phone = Part 2 profile switcher (#114).

> **Audit 2026-07-13:** The device-side EventKit half this item frames as forward-looking scope ('near-term scope if pursued') is already merged and device-verified under OPEN_ITEMS #69/#70 (GitHub #28/#29, PRs #34/#35, both Merged=YES) — `DeviceCalendarTools.swift` explicitly notes it 'pulls main-repo #33 forward device-side.' Recommend cross-referencing #69/#70 here so the item doesn't read as unstarted. The Mac-connector (server-side) half remains genuinely open, correctly gated on T6/#34/#107.

**Update 2026-07-12 (server-side layer):** T6 is un-deferred and in motion — Phase 1
(Mac relay + connector, #107) unblocks this item's Mac-only connectors, worked as #107's
Phase-2 checklist lines. Two additions to the plan below: (1) upstream Hermes now ships
**Photon iMessage** alongside the classic `imsg` connector — evaluate on the Mini and prefer
whichever the macOS toolset treats as first-class today (Q2 in the spec); BlueBubbles keeps
running but a single-automated-sender rule applies (two writers can race Messages). (2) The
TCC grants must target the **launchd context** (LaunchAgent-spawned processes have their own
TCC identity) — runbook `relay/docs/DEPLOY_MAC.md` Phase 2 has the trap writeup. The
"Windows brain, Mac hands" bridge can deliver iMessage tools to the phone's production
(OJAMD) brain without re-homing — also in the runbook.

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

## 34. 🔧 T6 — Mac-hosted Talaria backend (unlocks additive Apple connectors) — ACTIVE (un-deferred 2026-07-12); Phase 1 → #107

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

## 47. ⏸️ Configure OpenAI Realtime talk on the Hermes host — key/config deployed + confirmed minting on OJAMD 2026-07-08, then PARKED behind the unrelated #82 audio-capture wedge

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

## 51. 🔧 CLI `build-for-testing` can't resolve TalariaTests' test host — blocks CLI test-compilation validation

> **Audit 2026-07-13:** Downgraded from a first-pass 'RESOLVED' flip to stale-wording after adversarial re-check. `project.yml:305-311` on main DOES now carry an explicit `TEST_HOST`/`BUNDLE_LOADER` override with a comment naming the exact PRODUCT_NAME-has-a-space bug this item diagnosed — but no one has re-run `xcodebuild build-for-testing` to confirm the 'could not find test host' error is actually gone (no PR/issue/commit/dated note records it), and sibling #52 scheme-drift is still open. Stays 🔧, not ✅. The 'Next:' paragraph is stale — `project.yml` no longer relies on xcodegen auto-derivation; it has an explicit override to verify against a real Mac `build-for-testing` run.

**Found 2026-07-04** (Mac, reviewing Fable's PRs). `xcodebuild build` of the `Talaria` app scheme succeeds, but `xcodebuild build-for-testing -scheme Talaria` fails with `Could not find test host for TalariaTests: TEST_HOST evaluates to ".../Debug-iphonesimulator/Talaria.app/Talaria"` — identically on `generic/platform=iOS Simulator` and on a concrete simulator id, and after a fresh `xcodegen generate`. So it is NOT the stale scheme (#52) and NOT a destination issue; the app target builds fine standalone. `project.yml` looks correct (`TalariaTests` = `bundle.unit-test`, `dependencies: [target: Talaria]`, app `scheme.testTargets: [TalariaTests]`), so xcodegen should auto-wire TEST_HOST/BUNDLE_LOADER — the failure is downstream of that.

**Impact:** PR reviews on the Mac can compile/verify the app target from the CLI but cannot compile the *test* targets — so test additions (e.g. the store PRs appending to `AppStoresTests.swift`) are diff-reviewed but not CLI-compiled. Xcode's GUI test runner resolves the host differently, so in-app test runs are unaffected.

**Next:** inspect the generated `TalariaTests` build settings (actual TEST_HOST/BUNDLE_LOADER values) and whether the app target is built as a dependency of the test action; compare against a known-good xcodegen unit-test setup. Until fixed, PR reviews use the app-build + diff bar and Owen runs the suite in Xcode.

## 52. 🔧 Committed `Talaria.xcscheme` is stale vs `xcodegen generate`

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

## 55. 💤 OJAMD service layer reverted to out-of-the-box (2026-07-04) — relay portion SUPERSEDED by NSSM reinstatement (#88, #98, #105); gateway/connector Startup-script arrangement still current

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

---

## 56. 🔧 Wave 2 Issue E (GitHub #6) — "Ask Hermes" App Intent — MERGED (PR #11), core device-verified 2026-07-11; sub-checks remain

> **Audit 2026-07-13:** PR #11 (GitHub #6) merged this to main 2026-07-06; header's 'BUILT IN CLOUD, not compiled' is stale — a 2026-07-11 device pass (commits f35edb9, b05fef9) CORE VERIFIED both Siri actions. 🔧 remains correct only because >25s long-run hand-off, Siri Stop, and tailnet-unreachable error surface are still unchecked, not because the build is missing.

**Device pass 2026-07-11: CORE VERIFIED — phrase mystery solved, no code defect.** The intent works: both actions present and functional in Shortcuts, and "Hey Siri, ask Talaria twenty-seven" produced the "What should I ask Hermes?" prompt. Root cause of every voice miss: `.applicationName` resolves to `CFBundleDisplayName: Talaria27` (project.yml), so the registered phrase is "Ask Talaria27" — NOT "Ask Hermes" (→ Siri contacts) or "Ask Talaria" (→ Siri mythology facts). Apple requires the applicationName token in every phrase, so the utterance is permanently bound to the display name; making plain "Ask Talaria" work means renaming the app — a deliberate product decision, not a patch. Remaining sub-checks before full flip: >25s long-run hand-off, Siri Stop, tailnet-unreachable error surface.

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

## 57. 🔧 Wave 2 Issue G (GitHub #8) — attachment text-inlining + Extract Text OCR — MERGED (PR #11); device verify owed

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

## 58. 🔧 Wave 2 Issue F (GitHub #7) — Control Center / Lock Screen controls — Ask-control wiring FIXED (PR #100, 2026-07-16); device re-verify owed

> **MERGED 2026-07-16 (PR #100, `007417b`).** Root cause exactly as localized: both extension-local
> launch intents paired `static let openAppWhenRun = true` with the `OpenURLIntent` returned from
> `perform()` — Apple's control-opens-app-to-URL shape is the `OpenURLIntent` ALONE, and setting
> both makes Control Center silently swallow the tap. Fix drops the member (protocol default
> false) from `OpenHermesChatIntent` + `OpenHermesVoiceIntent`; `.notice` instrumentation in both
> `perform()`s (subsystem `org.aethyrion.talaria27.widgets`, public privacy) so Console can answer
> "did perform fire?". `HermesControlsTests` pins openAppWhenRun/isDiscoverable false + stable
> `kind` strings (HermesControls.swift compiles into the test bundle via project.yml — the
> extension isn't an importable module). Loop: regen pbxproj-only, entitlements survived, suite
> **647 tests / 55 suites green**. → **Device re-verify owed:** tap Ask Hermes from Control Center
> on whoGoesThere — expect app launch to chat + the perform log line in Console. Talk control
> stays #82 wedge-excused until the next beta seed.

> **Audit 2026-07-13:** PR #11 (GitHub #7) merged this to main 2026-07-06; header's 'BUILT IN CLOUD, not compiled' is stale. The item's own 2026-07-11 device pass (commits f35edb9, b05fef9) already ran on a compiled build and localized a real bug: the Ask control's action wiring in HermesControls.swift (Talk control is separately wedge-blocked on item #82, not a code defect). 🔧 stays correct as a live, localized bug — 'Small, well-bounded fix' per the item's own text — not because the build is missing.

**Device pass 2026-07-11: PARTIAL FAIL** — Talk control inert (EXPECTED under the #82 audio wedge, don't chase). Ask Hermes control also inert — NOT expected; suspect the deep-link path (#77, registered-unverified) rather than the control itself. Triage: fire the `hermes://` URL directly (Safari/Shortcuts) to split control-vs-deeplink before touching code.

**Localized 2026-07-11:** `hermes://` AND `hermes://chat` both open the app from Safari — scheme and route proven good (#77 base verified in passing). The dead Ask control is therefore the Control Center widget's own action wiring in `HermesControls`. Small, well-bounded fix; Fable-sized. Talk control stays wedge-excused (#82) until the next beta seed.

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

## 59. 🔧 Wave 2 Issue H (GitHub #9) — voice-memo attachments — MERGED (PR #11); device verify owed

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
## 60. 🔧 Wave 3 / 4.15 — `_thinking` channel: PROBED — root cause is gateway-side (emits the answer under `_thinking`); real reasoning lives in `run.completed.reasoning_content`

> **App-side half MERGED (`b88914f`): SessionsHermesClient adopts `run.completed` reasoning; answer-mirror never attaches.** Remaining: the gateway-side root cause (streaming reasoning deltas) — upstream Hermes code, update-unsafe to patch; re-probe on v0.18.2 (Mac gateway available) to see if upstream fixed the emitter, else it's an upstream ask, not a patch.

**PROBE 2026-07-13 — COMPLETE.** Mac-side `curl -N` against the OJAMD gateway Sessions API (`100.110.102.59:8642`), raw SSE captured and dissected. Root cause found; the app is NOT the culprit.

- **Delta key = `delta`** — the same field name as `assistant.delta`. Not `content`/`text`/`message`/`preview`; the parser's first guess was right all along.
- **Single cumulative terminal event, not increments.** Exactly ONE `tool.progress` (`tool_name:"_thinking"`) at `seq 43`, arriving *after* all 40 `assistant.delta` chunks (seq 3–42), carrying the whole text at once (dlen = full answer). Wire-mode hedge resolves to **cumulative snapshot** — `incrementalReasoningDelta` is never exercised by this host.
- **The `_thinking` delta is byte-identical to the assembled answer** ("They weigh exactly the same … Equal"). The mirror bug is reproduced on the wire.
- **Verdict: gateway-side defect.** The app reads `delta` correctly; the gateway populates the `_thinking` event with the ANSWER text rather than reasoning. The "app fallback key-chain grabbed a response-bearing field" hypothesis is **DEAD**.
- **Real reasoning exists and is distinct — but never streams.** It is delivered only in `run.completed.messages[].reasoning_content` (with a duplicate `reasoning` field): genuine CoT ("The user is asking me to reason through the classic riddle … a pound is a unit of weight/mass …"), nothing like the answer. The streaming `_thinking` channel never carries it.

**Fix tracks (probe done — the "do NOT edit app code before the probe" guardrail is now lifted):**
1. **Gateway (root cause, live UX):** make the API-server SSE emitter stream the model's `reasoning_content` deltas over the `_thinking` channel instead of the assistant answer. Emit site is Hermes gateway code on OJAMD (`~/.hermes/hermes-agent/gateway/…`). This is the real fix — live reasoning in the chevron.
2. **App fallback (cheap, non-live, belt-and-suspenders):** on `run.completed`, adopt `messages[].reasoning_content` into `Message.reasoning`, and distrust a `_thinking` delta that equals the assembled answer. Corrects the pane even if the gateway/model regresses. Dispatchable to Fable in Talaria-27.

Raw capture retained this session at `/tmp/sse_capture.txt` (Mac).

**UPDATE 2026-07-13 (eve) — upstream checked, app-side lane dispatched:**
- **Upstream already knows.** Issue #13007 is this exact bug ("reasoning.available SSE event sends full reply text instead of extracted reasoning content"); PR #13326 is the conversation_loop fix — open, bot-reviewed only, now conflicting after a refactor moved the emit site. 10+ overlapping open PRs attempt api-server reasoning streaming (#30509 wires `reasoning_callback`; also #11482/#13401/#15169/#23638/#24946/#57094/#60906/#61259). None merged; review activity is bots. **Decision (Owen): file NOTHING upstream** — no PR, no comments. Fix track 1 (gateway) is therefore "wait for upstream, arrives via `hermes update`."
- **Mechanism note for the future:** the agent already extracts live reasoning deltas on every streaming turn (`_fire_reasoning_delta` → `agent.reasoning_callback`, fired from all provider paths); the api_server just never sets `reasoning_callback` (the web UI does — `tui_gateway/server.py:3876`). When upstream wires it, `_thinking` becomes plural live real deltas — the app's existing streaming path + incremental hedge light up unchanged.
- **Fix track 2 DISPATCHED:** `dispatch/FABLE-T27-60-reasoning-adoption.md` — adopt `run.completed.messages[].reasoning_content` (extend `RunCompletedEnvelope`; last-assistant wins; `reasoning_content` over `reasoning`), pure `reasoningMirrorsAnswer` fold-guard (#110 semantics) at both client attach sites AND ChatStore's nil-fallback resurrection (~467–473), answer-mirror never attaches. Forward-compat pinned by test: distinct `_thinking` deltas are still adopted.

**UPDATE 2026-07-14 — fix track 2 BUILT (branch `claude/fable-t27-60-reasoning-50yncq`), cloud-written, NOT compiled.** Exactly the dispatch scope, no new files (no xcodegen): `SessionsHermesClient` gains `decodeRunReasoning` (last assistant in `run.completed.messages[]`; `reasoning_content` over `reasoning`, blank = absent, trimmed) + `reasoningMirrorsAnswer` (the #110 whitespace-fold, copied from `shouldRetractSpeech`); attach precedence at `run.completed` = structured wins → distinct assembled `_thinking` kept (forward-compat) → mirror never attaches, same guard at the stream-end fallback; ChatStore's ~473 nil-fallback now refuses a placeholder mirror. `ReasoningChannelTests` extended (+15 tests): mirror-fn units, ChatStore side-door pair, and a new serialized `RunCompletedReasoningTests` sub-suite driving the REAL SSE parse loop through a stubbed URLSession (decode variants incl. malformed-JSON no-throw, all four precedence cases). `_thinking` parser, hedge, interrupted/reconcile paths, `reasoningSummary` untouched per the hard constraints. **Mac owed:** CLI build + full suite (no xcodegen — verify `git status` clean after build), then device: genuine CoT in the chevron or no chevron, never the mirror.

**UPDATE 2026-07-13 (late) — Mac loop GREEN, MERGED as PR #94 (main `dc3f568`).** Diff review on-scope (fold verified byte-identical to `SpeechOutputService`'s at :245); TEST BUILD SUCCEEDED first try; 618 tests / 51 suites, `ReasoningChannelTests` + `RunCompletedReasoningTests` green (34ms — the URLProtocol stub is not flaky); TEST EXECUTE SUCCEEDED; tree clean post-build (no regen, as designed). New suite baseline: **618/51**. Note: the run showed a benign 600s "Failure collecting diagnostics from simulator" timeout AFTER the verdict — environmental, not a test issue. **Remaining owed: device-verify on whoGoesThere** — Reasoning chevron shows genuine CoT distinct from the answer, or no chevron for a no-reasoning turn; the mirror must be gone in both cases. Track 1 (gateway) remains wait-for-upstream.

**DEVICE-VERIFY 2026-07-13 (late): PASS** — whoGoesThere, Xcode build post-merge, DeepSeek-V4-Pro, 10-tool-call smoke-test turn. Mid-stream the pane flashes the live mirror (expected — live delta path deliberately untouched); at completion it resolves to genuine `reasoning_content` ("Let me compile the smoke test results…"), structurally distinct from the answer. The mirror never survives the finish. **Fix track 2 CLOSED.**
- **Enhancement candidate (wire-confirmed 2026-07-13, `/tmp/sse_tool_turn.txt` on Mac):** on tool-using turns the `run.completed` transcript carries reasoning per assistant message — the genuine plan-CoT rides the INTERMEDIATE entries (e.g. "The user wants me to check… I'll use the terminal"), while last-assistant-wins surfaces only the final compile step. Follow-up: `decodeRunReasoning` aggregates non-blank `reasoning_content` across ALL assistant entries (join with blank line, mirror-guard the aggregate) — matches web-UI semantics. ~10 lines in `decodeRunReasoning` + test updates. **Handoff written: `dispatch/HANDOFF-T27-60B-reasoning-aggregation.md`** (self-contained, for Claude Desktop/Code on the Mac). **60B MERGED 2026-07-13 (late) as PR #95 (main `07f6782`)** — Claude Code built it (branch `claude/60b-reasoning-aggregation-xanqnx`), Mac loop green: TEST BUILD SUCCEEDED; **621 tests / 51 suites** (new baseline), `RunCompletedReasoningTests` aggregation fixtures pass; TEST EXECUTE SUCCEEDED (the benign 600s post-verdict diagnostics stall recurred — pattern confirmed, verdict above it is the truth); tree clean, no regen. Mirror guard now gates the structured aggregate too. **Device-verify owed:** a multi-tool turn's chevron shows the plan chain THEN the compile step, not the compile step alone. **DEVICE-VERIFY 2026-07-13 (late): PASS** — whoGoesThere rebuild, multi-tool turn; post-completion the chevron shows the full aggregated reasoning (plan chain + compile step). **60B closed.** App-side work on #60 is COMPLETE; the only live thread is track 1 (gateway `_thinking` stream fix) = wait-for-upstream, arrives via `hermes update`, app adopts it automatically (forward-compat pinned by test).

**UPDATE 2026-07-14 — 60B BUILT (branch `claude/60b-reasoning-aggregation-xanqnx`), cloud-written, NOT compiled.** Exactly the handoff scope, no new files (no xcodegen): `decodeRunReasoning` now aggregates non-blank reasoning across ALL assistant entries in transcript order (`\n\n`-joined; per-entry `reasoning_content`-over-`reasoning`, trim, blank-=-absent unchanged), and the `run.completed` attach mirror-guards the structured aggregate — a single-entry answer-restatement counts as absent and falls through to the assembled-deltas branch (stream-end fallback, ChatStore, `_thinking` parser/hedge untouched per the hard constraints). `RunCompletedReasoningTests`: `lastAssistantEntryWins` (wrong by design now) replaced by `aggregatesReasoningAcrossAssistantEntries` (capture-modeled plan/tool/compile fixture) + blank-and-tool-row skip + per-entry mixed-key + mirroring-aggregate fall-through pins; all prior decode/precedence tests and the forward-compat pin untouched. **Mac owed (handoff loop steps 2–6):** CLI build + suite (baseline 618/51, N grows; `git status` clean post-build), PR merge (`gh pr merge --merge`, never squash), then device-verify on whoGoesThere: a multi-tool turn's chevron shows the PLAN chain followed by the compile step, not the compile step alone.

> **Audit 2026-07-13:** Branch claude/wave-3-on-device-intelligence-rxht4l = PR #12, merged to main 2026-07-06. The body's closing line ('not yet compiled — needs xcodegen generate + CLI build + device verify') is stale — a 2026-07-11 device pass on the compiled build already ran and FAILED (reasoning pane mirrors the final answer verbatim; commits f35edb9, 373f65d). Header title itself is still accurate (probe genuinely owed); 🔧 stays correct as an open investigation, not because the build is missing — per the item's own 'Do NOT edit app code before the probe' instruction, this is diagnosis-pending, not yet a fix-in-progress.

**Device pass 2026-07-11: FAIL** — reasoning pane mirrors the final answer verbatim (markdown differences only). Consistent with the fallback key chain grabbing a response-bearing field (`message`/`preview`?) — or the gateway synthesizing `_thinking` from output. Next step is exactly this entry's prescribed OJAMD probe: `curl -N` a reasoning-model streaming turn, pin the real delta key. Do NOT edit app code before the probe.

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

## 61. 🔧 Wave 3 / 4.8 — on-device titles + previews via FoundationModels — dedup fix MERGED 2026-07-17; device re-verify owed

> **MERGED 2026-07-17 (`588d885`, direct merge, loop-validated 755/62).** Recovery note for the
> record: the fix branch `claude/t27-61-fallback-card-dedup` (07d8d9a) was deleted in error during
> the 2026-07-17 branch cleanup (misjudged as superseded by Lane H without reading this item),
> caught during the dispatch sweep, restored from local git objects, merged through the full loop.
> Lesson: cleanup checks the ITEM TEXT, not the memory of it. → Device re-verify owed:
> attachment-only/empty user turn → card title and preview are distinct, neither echoes the
> reply's first line.

> **2026-07-13 (eve): device FAIL confirmed → ROOT-CAUSED + FIXED (branch).** Title+preview both echoed the model's first line — the truncation fallback borrowed the reply's first line for BOTH fields when the user turn had no meaningful line (attachment-only/empty). Fix + fail-first test on `claude/t27-61-fallback-card-dedup` (07d8d9a); full suite 583/583. Merge + device re-verify owed.

> **Audit 2026-07-13:** Header 🔧 is correct (2026-07-13 Lane H/PR #83 note leaves device re-verify owed), but the older 'Same not-compiled caveat as #60' line is stale — PR #12 (original) and PR #83 (Lane H guard) are both merged (PR_INDEX), and this item's own 2026-07-11/07-12 notes already record real on-device runs, not a pre-compile state.

**Device pass 2026-07-11: FAIL** — title and preview show the same repeated raw text. Localize which path ran (guided generation vs deterministic fallback) via logs before touching code. Possibly same on-device-model degeneracy family as #102 (local brain phrase-looping in the same session).

**Device evidence 2026-07-12 evening:** `on-device conversation card generated (#4.8)` observed in the whoGoesThere log — the GUIDED path succeeds at least sometimes. Earlier same-day chats showed pure truncation-fallback cards (raw first lines as title/preview) with nothing in the log to explain why; note the model-UNAVAILABLE path is the one card path that logs NOTHING (guard trips and generation failures both log) — worth a one-line logger fix, natural rider on the #110/#111 micro-PR.

**MERGED 2026-07-13 (Lane H, PR #83).** Degenerate-card guard live: repetition / identical / containment / prefix-echo checks discard bad guided cards for the known-good fallback, and EVERY path now logs which guard tripped and which path produced it (`guided card degenerate` / `mixed card degenerate` / `FALLBACK card carries repetition` — the last one means the chat text itself was degenerate, #102 feeding #61). All three generation sites got token caps; temperatures untouched per spec. DEVICE RE-VERIFY OWED: fresh chat, first exchange → `/title`; if a card still degenerates, the log line names the path — that answer is the point.

**Localized 2026-07-11 (source read):** guided generation runs at temperature 0.2–0.3 (`LocalIntelligenceService.swift:74/114/173`) — near-greedy, repetition-prone on the small on-device model. Not yet log-confirmed vs the guardrail-fallback path; Lane H adds a degenerate-card guard that protects both and logs which tripped. Spec: `dispatch/FABLE-LANE-H-local-brain-gen-health.md`.

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

## 66. 🔧 Spotlight tap-through — CSSearchableItemActionType handler LANDED 2026-07-17 (round 2); device re-verify owed

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

## 67. 🔧 Wave 4.5 — LocalChatBackend: on-device chat brain (GitHub #26)

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

## 68. 🔧 Wave 4.5 — ChatBackendRouter: two brains, one seam (GitHub #27)

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

## 72. 🔧 Wave 4.5 — PCC tier: PrivateCloudComputeLanguageModel behind gates (GitHub #30)

> **Stopgap merged 2026-07-16 (PR #104):** `pccGrantConfirmed = false` gates every PCC surface,
> so the SIGTRAP-on-send is unreachable and the tier picker honestly omits PCC. When the SBP →
> capability-request pipeline grants the entitlement: flip the gate (or wire it to a real
> signal), rebuild, and the picker/routing/status paths re-enable themselves — then close
> #111's re-verify note in the same pass.

> **2026-07-13 (eve): crash + stopgap (branch).** Selecting PCC β and sending SIGTRAP-crashed (reproducible) — the entitlement isn't granted, so constructing/using `PrivateCloudComputeLanguageModel` traps (uncatchable; `send()`'s catch can't rescue it). Stopgap on `claude/t27-pcc-crash-stopgap` (c595bf4): a master `pccGrantConfirmed = false` gate — no PCC model constructed until the grant lands, so PCC leaves the picker and can't crash. Flip the flag when Apple grants. Suite 582/582.

> **Audit 2026-07-13:** PR #37 (GitHub #30) confirmed merged to main. LocalChatBackend.swift's isPrivateCloudAvailable/isPrivateCloudUsable (lines 153/162) are the exact symbols item #111 (2026-07-12 device-pass log, whoGoesThere) observed compiling and executing on-device — repeatedly failing PCC XPC session establishment for the ungranted com.apple.developer.private-cloud-compute entitlement. Correction: 'Needs Mac: compile-check the 27-beta surface' is stale — it has compiled and is running on-device already; only Apple's entitlement grant plus the resulting functional device checklist remain owed. project.yml still carries no private-cloud-compute entitlement, so that part of the item stands. Status is more precisely 'blocked externally' (the item's own words) than plain in-progress.

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

## 74. 🔧 Wave 5 — CarPlay voice upgrade: auto-start, observation tracking, routing (GitHub #19)

> **Audit 2026-07-13:** PR #40 (`claude/w5-19-carplay-voice`→main, merged) and GitHub #19 (closed) confirm the code landed; `Talaria/CarPlay/CarPlayVoiceManager.swift` (nonisolated `maxTranscriptTitleLength`/`blockedTitle`, matching the described compile fix) and `TalariaTests/CarPlayVoiceStateTests.swift` are on main, and `project.yml:61` shows the CarPlay entitlement commented out per the hotfix. The item's own Mac-session note already confirms xcodegen/build/tests done, so the trailing 'Needs Mac: xcodegen generate... CLI build + tests' text is stale; the genuinely open work is the CarPlay Simulator functional pass (entitlement currently disabled) and filing Apple's discretionary grant — keep 🔧, this item is effectively blocked on that external approval.

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

> **Audit 2026-07-13:** PR #43 (`claude/talaria-27-issue-42-042f8a`→main, merged) and GitHub #42 (closed) confirm this landed; `Talaria/Core/HUD/HUDComponents.swift:476` has `hudSingleLine(minScale:)` on main. The 'BUILT IN CLOUD, not compiled or device-verified' claim is stale (merge already implies build+test pass); the real remaining work is only the on-device/sim acceptance pass (narrow widths, both brains, long model name, Dynamic Type sweep) — keep emoji 🔧 as merged-unverified.

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

## 77. 🔧 hermes:// URL scheme registered + ask?q= payload route (GitHub #48)

> **Audit 2026-07-13:** PR #51 merged to main (GitHub #48 closed); code confirmed on main (`project.yml`/`Info.plist` CFBundleURLTypes hermes scheme, `ChatStore.pendingComposerSeed`/`seedComposer`/`consumeComposerSeed`, `AppEntry.handleDeeplink` ask?q= route). The 'not compiled' wording above is stale, but 🔧 correctly stands since no device-verification note has been added.

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

> **Audit 2026-07-13:** PR #52 merged to main (GitHub #44 closed); code confirmed on main (`MessageBubble.swift` `.contextMenu`/`SelectableTextSheet`, `ChatStore.regenerateReply`/`extractTurnForEditing`/`EditableTurn`). The 'not compiled'/'Needs Mac: CLI build + tests' wording above is stale, but 🔧 correctly stands since no device-verification note has been added.

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

## 80. 🔧 Inbox wired + agent-initiated producer tools (GitHub #45)

> **Audit 2026-07-13:** The 2026-07-10 note's claims 'gh#58 app-side hardening BUILT, not compiled' and 'xcodegen regen owed' are stale — Lane C (PR #59, `claude/lane-c-dispatch-5bbw9k`) has since merged to main (commit `80b534a` and docs commit `3607bdd` both present in `git log origin/main`; `TalariaTests/InboxDecodingTests.swift` confirmed in the working tree). The decoder hardening is compiled and on main, not merely cloud-written. Still correctly 🔧/merged-unverified, not ✅: the original #45 device checklist (silent-push wake, verdict readback, alert push) remains unchecked, the gh#58 client fix's own device re-check is unconfirmed, and GitHub #58's server-side `kind`-validation half is still OPEN (ISSUE_INDEX).

**Update 2026-07-08 (cloud session, branch `claude/t27-45-inbox-wiring`):**
iOS half BUILT IN CLOUD (not compiled/device-verified); connector half
**tested green here** (`connector/tests` — 101 passed incl. 10 new).
- **Entry point:** tray button in the Chat toolbar (forge unread pip — real
  data, only when unread items exist) → `Route.inbox` → `InboxScreen`. The
  screen's `toolbarVisibility(.hidden)` removed (predates any call site —
  back button needed now); loads on appear, pull-to-refresh from the list
  AND the empty/unreachable states.
- **Mock gutted:** `InboxStore` fallback to `DemoData.sampleInboxItems`
  removed → honest "INBOX UNREACHABLE — PULL TO RETRY" state.
  `ResilientInboxService` **deleted** (only call site was the fallback);
  `MockInboxService`/`DemoData` survive as test doubles + the UITest-mode
  wiring only. Orphan-audit `--self-test` re-run: still green.
  (`LiveHermesClient.allowDemoFallback` is a separate legacy-relay-path
  fallback — untouched, out of #45 scope.)
- **Silent push → item surfaces:** `handleRemoteNotificationWake` now calls
  `inboxStore.loadInbox(force: true)`.
- **Producer tools** (`connector … mcp_server.py`): `send_inbox_item(title,
  body, kind, priority, notify)` → `POST /internal/inbox/create`, then
  best-effort `POST /v1/push/send` (silent default / alert / none — the
  push/send route's first programmatic caller); `get_inbox_verdict(item_id)`
  → `GET /internal/inbox/{id}/actions` (empty = pending). Auth = the
  relay's INTERNAL_API_KEY via new `ConnectorSecrets.internal_api_key`
  (secrets.json, hand-editable) or `HERMES_MOBILE_INTERNAL_API_KEY` env.
  Relay untouched — routes were already live on OJAMD.
- **New files:** `connector/tests/test_inbox_producer.py` (no Xcode impact);
  iOS deletes 1 file → **xcodegen regen owed** (with the entitlement
  re-verify, stacking on #46's).

**OPS (Owen, box-side):** confirm OJAMD's relay env doesn't still ship
`INTERNAL_API_KEY="replace-me"` (`config.py:60`); put the real key in
`~/.hermes-mobile/secrets.json` as `internal_api_key` so the tools can auth.
**Device checklist:** tray opens Inbox; relay stopped → UNREACHABLE (never
demo rows); agent `send_inbox_item` (silent) → item present on next open
without manual refresh; approve → `get_inbox_verdict` reads it back;
`notify="alert"` → visible push.

**✅ VERIFIED END-TO-END 2026-07-08 (evening).** Full chain live: Hermes agent →
gateway → hermes_mobile MCP → connector `send_inbox_item` → relay
`/internal/inbox/create` + `/v1/push/send` (its first programmatic caller) → item
in DB → rendered in the device tray (Owen: two items visible). Along the way:
- **OPS done:** relay `.env` had a real `INTERNAL_API_KEY` (len 43) and `config.py`
  `load_dotenv`s it; the key was injected into `~/.hermes-mobile/secrets.json` as
  `internal_api_key` (backup taken). Gateway `tools.include` allowlist had to be
  extended + gateway process cycled (→ #55 update for the recipe).
- **Gap found & fixed:** `LiveInboxService` was the only relay consumer without
  the #15 401-recovery refresher → a stale access token rendered as "Inbox
  Unreachable" while every other surface silently refreshed. Fixed `17a7b0f`
  (gh#56, closed): same `performAuthorizedRequest` ladder + refresher injection
  as `LiveHermesHostService`, construction moved below the refresher in
  `AppContainer`.
- **Poison-row incident:** a smoke-test item posted straight to
  `/internal/inbox/create` with `kind='note'` (outside the app enum
  alert/approval/notification/reminder/suggestion — the raw route doesn't
  validate; the connector tool does) made the strict iOS decoder fail the WHOLE
  feed → hours of phantom "unreachable". Row re-kinded in DB. Hardening filed
  **open** as gh#58: decode items individually, skip+log bad rows; optionally
  validate `kind` at the relay route.
**Still unchecked from the device checklist:** silent-push wake populating
without manual refresh; approve → verdict readback; `notify="alert"` visible push.

**Update 2026-07-10 (Lane C item 4, cloud session, branch
`claude/lane-c-dispatch-5bbw9k`):** gh#58 app-side hardening BUILT, not compiled.
`LiveInboxService.InboxResponse` now decodes row-by-row: a bad row is skipped via a
never-throwing best-effort probe that salvages its raw `id`/`kind` for an always-on
per-row os_log line (plus a kept/skipped summary) — the poison row is nameable in the
relay DB instead of anonymous. Good rows survive in order; an all-bad payload decodes
to an EMPTY inbox, not "unreachable". `InboxDecodingTests` (new file — xcodegen regen
owed) covers mixed payloads, all five kinds, non-object rows, and id/kind capture.
The optional relay-route `kind` validation half of gh#58 remains open (server-side).
Device re-check once merged: re-insert a bad-kind row → tray shows the good rows +
Console names the skipped one.

---

## 81. 🔧 Lock-screen reply to Hermes — UNTextInputNotificationAction (GitHub #47)

> **MERGED (branch `claude/t27-47-lockscreen-reply` is an ancestor of main — verified 2026-07-16).** Device checklist owed (long-press push → Reply → headless post → next push carries Reply). Note for the checklist: with #114 profiles, verify the headless reply posts to the push's SESSION birth profile.

**Update 2026-07-08 (cloud session, branch `claude/t27-47-lockscreen-reply`):**
Relay half **tested green here** (72 passed); iOS half BUILT IN CLOUD, not
compiled or device-verified. Completion pushes (#38) were tap-to-open only —
now a push is a conversation: long-press → Reply → type → the reply posts
into that session headless, and the resulting completion push again carries
Reply (the loop closes).
- **Relay:** `send_run_completion_push` now passes
  `category="HERMES_RUN_COMPLETED"` into `send_alert_push`'s previously
  unused `category:` param. Test updated (stub records category + lockstep
  assertion).
- **iOS:** `NotificationReplyAction` (AppEntry) — category id lockstep with
  the relay, `UNTextInputNotificationAction` id `HERMES_REPLY`, registered
  every launch incl. scene-less; `didReceive` routes
  `UNTextInputNotificationResponse` → new
  `AppContainer.handleNotificationReply(_:sessionID:)`:
  `UIBackgroundTask` assertion + completionHandler deferred until the send
  finishes; bounded 2s Keychain key-restore wait (AskHermesIntent pattern);
  busy guard (one run at a time); `openSession(sessionID)` adopts the
  pushed thread; `sendMessage` full pipeline; then the **explicit
  `postPushWatch`** the issue called out (scene-less launches never trip
  `watchPendingRunIfNeeded`). Watch armed only on
  `.answered`/`.pending` outcomes (reusing `AskHermesIntent.resolveOutcome`)
  — the relay watcher's completion check is positional
  (assistant-after-last-user), so arming after a FAILED send would
  insta-push a stale reply; on `.answered` the insta-fire is deliberate
  (it's what announces the finished answer to the locked phone, with Reply).
  `.failed` → new `LocalNotificationService.notifyReplyFailed` — the typed
  text never vanishes silently.
- No new iOS files (no regen owed by this branch; the stack still owes one
  from #46/#45).

**Device checklist:** run finishes while locked → push has Reply on
long-press; typed reply lands in the right session (verify in-app
transcript); the NEXT completion push also has Reply; reply while relay
watch TTL expired; reply with wrong/expired API key → "Reply not sent"
notice; reply while another run streams → busy notice. NOTE the
"Approve/Deny slash commands" claim from discovery was refuted — nothing
here pretends they exist.

**Update 2026-07-08:** merged to main via PR #55 (carrying two build fixes: `import UIKit`
in AppContainer for the background-task API, and the completion-handler `didReceive`
delegate converted to the **async** variant — Swift 6 wouldn't send the non-Sendable
handler into the `@MainActor` send; the async form preserves the await-before-return
ordering, with the minor side effect that the tap path now awaits `handleNotificationTap`).
**Relay half is DEPLOYED on OJAMD** (`ojamd-deploy`; `HERMES_RUN_COMPLETED` live at
`main.py:390`). The device checklist above has NOT been run — the evening went to the
#83 letterbox chase and #82 voice regression instead.

---

## 82. 🔧 Voice capture wedge — root cause was OUR read-aloud session hijack, NOT the OS seed — fix merged (PR #106) + device CONFIRMED 2026-07-16; residuals spun out to #118/#119

> **DEVICE CONFIRMED 2026-07-16 (whoGoesThere, `probe/t27-fix84-verify` = #106 fix +
> instrumentation + STOCK VPIO):** Owen held a full two-way voice conversation — live
> transcript, Hermes replies, TTS back. VPIO verdict sealed: voice processing was ENABLED on
> this build and worked, so the `auou/vpio` render errors were a VICTIM of the session hijack,
> not a seed bug — echo cancellation is intact, no Apple Feedback owed for the render errors,
> and the vpio-bypass probe is obsolete. Residual observations from the confirm run filed
> separately: capture stays live after leaving the app (#118); 'Cancellation failed' banner +
> header stuck on CONNECTING during an active conversation (#119). Probe branches
> (`probe/t27-vpio-bypass`, `probe/no-vpio`, `diagnostics/voice-probes`, `probe/t27-fix84-verify`)
> are disposable once #118/#119 don't need them.

> **ROOT CAUSE FOUND + FIX MERGED 2026-07-16 (PR #106).** The 'beta-OS-wide wedge' framing is
> DISPROVEN. Instrumented device run (13 tagged `setActive` sites, Hermes's Discord-works
> observation as the tell): the chat read-aloud `SpeechOutputService` (`managesAudioSession ==
> true`) was calling `setActive(false)` dozens of times a minute during native voice sessions —
> `talkStore.onSessionStateChanged` fires on every state tick, AppContainer's callback called
> `speechOutput.stop()` each time, and `stop()` reached `releaseAudioSessionIfIdle()`
> unconditionally. The shared session died under the live mic (route → 'no input → Speaker' →
> flatline tripwire). The famous 'tears down and rebuilds ~3× then works' was pre-#105
> categoryChange→restartCapture churn ACCIDENTALLY re-activating the session — a thrash-heal
> loop that #105's correct churn fix removed, converting it into a clean mic death.
> Fix (PR #106): `didActivateAudioSession` — the service releases only a session it activated
> (pure `shouldReleaseAudioSession`, 4 tests) — plus edge-triggered talk callback. Suite 691/58.
> **Device confirm owed** on `probe/t27-fix84-verify` (fix + 🔊 instrumentation + STOCK
> `.voiceChat`/VPIO): expect no `@SpeechOutputService#2` spam mid-session and a working mic. The
> `auou/vpio` render errors are presumed a victim of the hijack, not a cause — if they return on
> the verify run, `probe/t27-vpio-bypass` (mode `.default`, skip `setVoiceProcessingEnabled`) is
> the ready fallback. Apple Feedback filing should WAIT for the verify verdict — the repro we
> would have filed was our own bug.

**Found 2026-07-08 evening on whoGoesThere.** Talk in Talaria-27 no longer works; Diagnostics
truthfully shows connected/ready. **Isolated to T27**: Talaria prime on the same phone has
working voice AND working voice-to-transcript (Owen-verified) — clearing relay, OpenAI key,
connector, network, and phone OS as causes.

**Relay-side signature (from OJAMD logs + `voice_sessions` table, 00:55–01:04 UTC):**
`talk/readiness` 200s → `POST /v1/talk/session` 200, **realtime session minted**
(`sess_…`, `last_error: None`) → the app itself calls
`POST /v1/talk/session/{id}/end` **2–37 seconds later**. Clean deliberate teardown, not a
crash and not a server error — the app's voice flow is *deciding* to bail after setup
(AVAudioSession activation, WebRTC connect, or routing logic).

**Suspects, ordered:** (1) **Wave 5's audio work** — the native fallback voice pipeline
(#73/PR#39) and CarPlay voice (#74/PR#40) both rework T27's audio-session/routing and never
shipped to prime; (2) **the beta-3 SDK relink** (see #83 — tonight's build is the first
linked against SDK `24A5380g`; linked-on-or-after behavior changes are in play this week).
**Open discriminator for Owen:** did T27 voice work after Wave 5 landed on-device but
*before* tonight's build? Yes → Wave 5 exonerated, SDK relink becomes prime suspect.
**Next session:** instrument/inspect the T27 talk flow's post-mint path
(`LiveVoiceSessionService` and the Wave 5 backend router) for the error that triggers
`session/end`; prime is the healthy control.

**Update 2026-07-08 (late) — timeline pinned from the record:** voice worked on device
**July 5** ("Voice first test successful" session); **Wave 5 merged July 7 ~2 PM**
(`5330eaa` PR#39, `895f549` PR#40) — i.e., the working build predates Wave 5's audio code.
Owen did not test voice on the July 7 (Wave 5 + seed-1 SDK) build, so both suspects sit
inside the failure window with the ordering above unchanged. The July 8 *morning* "setup
no longer shows" report (the old #75 stub from the reconciliation session) is explained
away: the relay was down all morning (port 8000 dead until 13:33) — dead readiness hides
the setup UI; not this bug. **Single-variable experiment queued:** build pre-Wave-5
commit `6820860` with the SAME beta-3 toolchain, install, test voice — works → Wave 5
code convicted; broken → SDK relink convicted.

**2026-07-08 (late):** the A/B ran and was contaminated — pre-Wave-5 probe failed identically,
then Prime (healthy control) failed too. Server side exonerated end-to-end via three OJAMD
probes (mint/WS-text, WS-audio+VAD, full WebRTC). Session concluded "iOS silently revoked
mic + speech permissions; toggling restores" — **that conclusion is now superseded (below);
the toggle likely worked by tearing down the app's audio clients, not by fixing permissions.**
Note: the `diagnostics/voice-probes` branch carries the probe scripts (still valuable) plus an
OPEN_ITEMS closure asserting the permission root cause — **do not merge its OPEN_ITEMS text
as-written**; rework against this entry first.

**2026-07-09 — PARKED by Owen (voice is optional; CarPlay voice inherits this when resumed).**
With the #84 instrumentation on-device, the real failure surfaced: **any Talaria audio-capture
path wedges the system-wide capture stack until reboot (sometimes two)** — after one Talaria
capture attempt, even Apple's Voice Memos is deaf. Signature: route shows
`iPhone Microphone → Speaker` for ~1.5 s at session start, then drops to `No input → Speaker`.

Falsified tonight, each with device evidence (do not re-litigate):
permissions wedge (Diagnostics panel reads both permissions enabled via the real APIs);
VPIO/voice-processing (composer dictation uses `.record`/`.measurement` — no VPIO, no WebRTC,
no BT options — and wedges identically; probe branch `probe/no-vpio` @ `3d5721e` was cut but
NEVER TESTED — do not merge); app-code regression (Prime’s old pre-Wave-5 stable build fails
identically: Voice Memos pass → dictation fail → Voice Memos dead); TCC-record corruption
(both phones fail; TCC doesn’t sync). Reboot restores capture; the next Talaria attempt
re-wedges it. No newer beta seed available as of 2026-07-09.

**Test A RESOLVED (2026-07-09, later that night):** Owen ran the sequence with Discord —
reboot ×2 → Voice Memos pass → Discord composer mic FAIL → capture wedged, identical to
Talaria. **The seed breaks ALL third-party capture; Talaria is fully exonerated.** The Apple
Feedback repro is now Talaria-free: reboot → Voice Memos works → any third-party mic → dead.

**On resume:** (1) Test A — any third-party recorder after a clean reboot; (2) retest on the
next beta seed; (3) file Apple Feedback with the minimal repro (reboot → Voice Memos works →
one Talaria dictation → Voice Memos dead); (4) #84 branch (`claude/t27-84-talk-preflight`,
`c9e909e`, compiles green under Xcode 27.0, 13/13 tests) stays UNMERGED — its device checklist
is blocked on this wedge, and it owes one fix: the preflight misclassifies “no input came up”
as “permission denied” (needs a third state: permissions OK but no mic input — try rebooting).

---

## 83. 📝 Display Zoom "Larger Text" letterboxes T27 on iPhone18,2 — beta interplay, NOT app layout + toolchain-provenance rule

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

---

## 84. 🔧 Talk-mode preflight + mic flatline tripwire + route display — merged to main (PR #62); device checklist owed

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

## 85. 🔧 hermes_delegate MCP path — advertising gated + URL normalized (built in cloud; OJAMD deploy owed)

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

## 86. 🔧 Relay QueuePool exhaustion — session-across-await audit + pool hygiene (built in cloud; OJAMD deploy owed)

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

## 90. 📝 DEVELOPMENT_TEAM placeholder — deferred to go-public cleanup

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

## 93. 🔧 P1 continuity fabric — journal primary, hop transplant, compose outbox (Lane A)

> **Sim run 2026-07-13 (eve): fidelity gate still owed.** Full suite green on the iOS 27 sim, but `CondenserFidelityTests` (the fidelity acceptance) SKIPPED — 'Requires the on-device Apple Intelligence model'. A skip is not a pass; the gate still needs whoGoesThere.

> **Audit 2026-07-13:** PR #61 merged (commit 5ab3477) with xcodegen regen (828ecf4) and a post-merge iOS compile fix (818d1be) — the 'NOT compiled' claim and the 'Next Mac session' merge/xcodegen checklist above are stale; that work is done (Lane C #59 -> Lane B #60 -> Lane A #61, exact order specified). No device-verified note exists anywhere in this file for Lane A/continuity fabric, and no note confirms CondenserFidelityTests actually RAN (vs. skipped) on Apple Intelligence hardware — 🔧/merged-unverified is correct, only the compiled-status wording needs fixing.

**Built 2026-07-10 in the cloud (Fable, Lane A — `dispatch/FABLE-LANE-A-continuity-fabric.md`),
branch `claude/talaria-27-lane-a-to5zv3`. NOT compiled, NOT device-verified.** Greenlit by the #89
probe; the condenser-fidelity acceptance suite below is the probe's residual-risk guardrail.

**What landed:**
- **Journal = durable primary** (`Models/ConversationJournal.swift` + `Stores/ConversationJournalStore.swift`):
  conversation identity is a local UUID owned by the journal; entries re-derive from the settled
  transcript at every ChatStore persistence point (streamed finish, reconcile, polling, #44
  truncation, voice) via `LocalChatBackend.transcriptTurns` — one mapping, no drift. Persisted at
  `hermes.conversationJournal`.
- **`apiSessionId` decoupled:** `SessionsHermesClient`'s single session var is GONE. The server
  session id is a per-hop handle (`ConversationJournal.ServerHop`) with a `seenEntryCount`
  waterline; `ensureSession()` → `ensureHopForTurn()`. Hop persists across relaunch (a live server
  session resumes without re-priming); a 404 on a REUSED hop swaps the handle and retries ONCE on a
  fresh transplanted hop (`SessionsClientError.sessionNotFound`). `switchModel` ends the hop so the
  user's next message hops under the new model WITH context — a model switch is a brain hop now.
- **Transplant at every hop** (`Services/Support/ContextTransplanter.swift` + 
  `LocalIntelligenceService.condensedContextBrief`): fresh session → priming turn 0 composed from
  the journal (guided-generation facts brief, corrections-at-latest + prune-distractors
  instructions, temp 0.2); deterministic verbatim-tail fallback (newest turns, per-entry cap,
  honest omission marker) when the model is unavailable — never fabricated condensation. Budget
  1,500 tokens enforced by measurement (binary-search tail fit; non-additive-token ratchet).
  Priming posts over SSE so `run.completed` usage is captured (real numbers or none).
- **Local turns mark the hop stale on purpose:** journal entries from on-device/PCC/voice turns
  don't bump the waterline, so the next Hermes turn re-hops with the full (condensed) context —
  the brain-hop continuity story.
- **Offline compose outbox** (`Models/ComposeOutboxState.swift`, `hermes.composeOutboxState`):
  transport-level failures now stream `.unreachable` (vs `.failed`); text-only turns park as
  `.queued` transcript rows + persisted outbox (SensorUpload pattern), drain FIFO on reachability
  (the chat screen's ~10s health probe + cold load), one live send at a time, re-queue stops the
  drain. Attachment turns still fail honestly (no durable wire form, v1). Siri intent reports a
  queued turn honestly (new `.queued` outcome).
- **Priming cost in receipts:** `.contextPrimed(TokenUsage?)` → system notice row in the
  transcript ("[Context transplanted into a fresh session — N tokens]", `Message.isContextPriming`
  + usage + servingModel), PRIMING line in StatusCard session totals
  (`SessionUsageTotals.primingTokens/primingHops`), and priming included in the session cost
  estimate (`ModelPricingCatalog.estimatedSessionCost`).
- **Identity-churn fix:** `ChatStore.mergeConversationMetadata` now preserves the LOCAL
  conversation UUID — refresh/reconcile used to mint a new `Conversation.id` every fetch, which
  would have reset the journal (dropping the hop) and already orphaned #27 brain pins.

**Tests (Swift Testing):** `CondenserFidelityTests.swift` — the REQUIRED acceptance suite: messy
transcript (2 corrections + 2 distractors) → asserts latest-corrected-values, distractor pruning,
and token budget on the REAL on-device condenser. Model-gated via an async `.enabled` trait: runs
on Apple Intelligence hardware, skips honestly elsewhere — **a skip is NOT a pass; the Mac run is
the acceptance gate.** Fallback + wire-format halves run everywhere. `ContinuityFabricTests.swift`
— deterministic: journal identity/waterline/adopt/truncate-clamp/persistence, outbox
dedupe/persist/clear, ChatStore priming-notice + totals + queue/drain/orphan-hygiene + the
identity-stability regression.

**Next Mac session:**
1. Merge order per handoff: Lane C first (ChatScreen overlap), then this. `xcodegen generate` —
   **4 new source files** (ConversationJournal, ConversationJournalStore, ComposeOutboxState,
   ContextTransplanter) **+ 2 new test files** (CondenserFidelityTests,
   ContinuityFabricTests); re-verify `aps-environment`/WeatherKit survive regen (#44/#48 trap);
   regen commit SEPARATE.
2. CLI build + full test run. **CondenserFidelityTests must RUN (not skip) — needs Apple
   Intelligence on.** If the condenser fails fidelity/pruning, that's the #89 residual risk
   firing: tune `condensedContextBrief` instructions before shipping, do not weaken the tests.
3. Device checklist: (a) kill/relaunch mid-conversation → next turn resumes the SAME server
   session (no priming notice); (b) stop the gateway, relaunch, restart gateway → next turn shows
   the transplant notice + priming tokens in StatusCard; (c) model switch mid-conversation → next
   turn hops with notice, new model answers WITH context; (d) local-brain turns then back to
   Hermes → transplant carries the local exchange; (e) airplane mode → send parks `.queued`,
   reconnect → auto-sends; (f) session totals show PRIMING row + cost including priming.
4. Priming preamble wording: reconcile `ContextTransplanter.primingText` with the probe's
   validated phrasing (`talaria-probe/probe.py` on OJAMD) if they differ materially.

**Update (same session) — adversarial review pass, six findings fixed:** (1) `switchModel` no
longer routes through `ensureHopForTurn` — a stale hop at switch time would have paid for a
transplant that `endHop()` immediately discarded (double priming per switch); command turns now
reuse the current hop or a bare throwaway session. (2) The sync-send path (voice context POST)
surfaced no priming receipt — `appendVoiceTranscript` now detects the hop change after the send
and appends the transplant notice, so that spend hits the transcript + totals too. (3)
`isUnreachableError` narrowed: `.timedOut`/`.networkConnectionLost` can fire AFTER the body
reached the server (the run may have committed), and queued turns auto-resend — those stay
`.failed` so a human decides about the retry. **Device-checklist consequence: a dead host behind
Tailscale can surface as `.timedOut` → honest `.failed` + retry, NOT `.queued`; checklist item
(e) uses airplane mode (`.notConnectedToInternet`), which queues.** (4) `sendMessage` now returns
whether it dispatched and resets the drain flag before its guards — the drain could previously
destroy a queued turn whose re-send tripped the duplicate guard (row + outbox entry both already
removed, flag stale). (5) Drain FIFO restore matches the re-queued turn by id, not last-by-text.
(6) A priming hop whose run reported no usage now still counts in
`SessionUsageTotals.primingHops`. Regression tests added for (4) and (6).

Logged 2026-07-10.

## 94. ✅ Pairing hardening — pair() already redeems before clearing the old record (no ordering bug found)

> **Audit 2026-07-13:** Independently re-verified, refutation attempted and failed. `Talaria/Stores/PairingStore.swift` (HEAD `cca1345`) redeems the new code FIRST (`try await pairingService.redeemPairingCode(...)`, lines 84-87) and only clears/saves afterward (lines 95-99), all inside the same `do` block — a throw from redeem (network/relay failure) jumps straight to `catch` (line 107) and never reaches the clear/save code. This is exactly the "redeem FIRST, then clear+save atomically" fix shape the item proposes as still-needed. `git blame` traces lines 63-111 to commit `9964f02` (2026-07-10 14:58:15 -0500), the shallow-clone boundary commit — and critically, `git show 560b560:Talaria/Stores/PairingStore.swift` (560b560 is the exact commit, 2026-07-11 12:59:24 -0500, whose diff added item #94's text to OPEN_ITEMS.md) shows the SAME already-correct ordering. So the item's factual claim was wrong at the moment it was authored, not merely stale later. Checked for alternate culprits and found none: `LivePairingService.redeemPairingCode` (Services/Live/LivePairingService.swift) is a pure network POST + response decode with zero local Keychain/UserDefaults mutation, so no clearing happens inside redeem either; the only production call site of `pair(using:)` is `ConnectHermesScreen.swift:338`, with no pre-clear wrapper. Item #46 (✅, "Verified on device 2026-07-05") independently corroborates that this same clear-after-redeem "clean slate on pair()" logic has been live since before #94 was even logged. Recommend closing; no code change required.

`PairingStore.pair()` calls `clearPairedRelayConfiguration()` BEFORE redeeming the new code (deliberate, for #3 stale-identity protection) — so a pair attempt that fails midway destroys the existing pairing and saves nothing. This is the likely mechanism behind the 2026-07-10 "total wipe" (a failed PAIR DEVICE tap during the frozen/wedged chaos): defaults copy + keychain mirror both gone, nothing for #41 rehydration to restore. Fix shape: redeem FIRST, then clear+save atomically (preserving the stale-identity wipe semantics on SUCCESS only). Small, low-urgency — recoverable by one re-pair — but it converts a transient network/relay failure into credential loss.

Logged 2026-07-11.

## 95. 👀 WATCH — credential-staleness fix set, verify across future reboots

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

## 99. 🔧 Interactive artifact / HTML preview — Lane I MERGED (PR #78), device-verify owed

> **Audit 2026-07-13:** PR #78 (`claude/t27-lane-i-ajkjno` → main) merged same session, 2026-07-12 04:16:49 -0500, merge commit 0bf97c5 (independently confirmed as an ancestor of current main tip cca1345 via `git merge-base --is-ancestor`). Implementation commits 6917979/57bba54/8e3f8c2/a5c9785 — all tagged `(#99)` — plus xcodegen regen 516ae7f (the PR branch's tip, i.e. the merge's second parent) are all confirmed ancestors of the merge. `Talaria/Features/Chat/HTMLPreviewView.swift`, `FilePreviewSheet.swift`, and `TalariaTests/FilePreviewTests.swift` are tracked on main today. Merge commit message: "CLI sim build SUCCEEDED, FilePreviewTests 17/17 passed... Known v1 follow-up: remote subresource fetches not yet blocked (needs WKContentRuleList)" — simulator build + unit tests only, no physical-device pass, with a residual gap. No mention of Lane I / PR #78 / HTMLPreviewView / FilePreviewSheet / a device pass appears anywhere else in this file, despite 9 further doc commits touching OPEN_ITEMS.md afterward (#107/#108/#110/#111/#112 etc.) through 2026-07-12 22:08 that never backfilled #99. Status is genuinely merged-unverified, not done — device-verify and the WKContentRuleList gap remain real open work, so the 🔧 marker is correct and this is not a status flip to ✅; only the body wording (which still describes the pre-build "spec revised, GATE CLEARED" stage) is stale and should say the lane shipped.

Both competitors render generated HTML/interactive content in-app; Talaria reconstructs agent files into a ShareLink bubble only. Natural successor to the P8 IR v0 rung: render agent-written single-file HTML (and later the IR) in an in-app preview surface (WKWebView, new-files-heavy). GATE CLEARED 2026-07-12: Lane D merged (#106); spec revised on top of the landed IR at `dispatch/FABLE-LANE-I-preview-surface.md` — preview sheet takes a generic content view so the future P8 rung slots into the same chrome. Sandboxed WKWebView (no bridges, navigation locked to initial content), text/code preview reuses the #92 stack, ShareLink relocates into the sheet toolbar.

Logged 2026-07-11.

## 100. 🔧 Inline charts / data viz — BOTH PRs MERGED (#108 + #109, 2026-07-17); device pass owed

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

## 101. 📝 Cross-chat memory / durable-facts layer (post-#93 successor)

Both competitors personalize across conversations; the continuity fabric (#93, merged) preserves context within a conversation but doesn't carry durable user facts into new chats. Shape: a lightweight durable-facts store extending the condenser/journal, priming fresh sessions. Direct extension of Lane A's merged work — dispatchable as its own lane once #93's device checklist verifies, to avoid reworking unverified foundations.

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

## 104. 🔧 Sensor outbox persistence churn — full rewrite on every tick, main actor, unbounded backlog

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

## 107. 🔧 T6 Phase 1+2 — Mac Mini backend EXECUTED + reboot-verified; ONLY the from-Talaria-chat send (Shelley message) remains

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

## 108. 🔧 iPad support — universal foundation + native split view (Lane J)

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

## 109. 📝 True iPad multi-window — gated on a store-layer concurrent-scene audit (J-2 follow-up)

Lane J PR 1 ships single-window-by-policy (`SingleWindowPolicy`, #108): `UIApplicationSupportsMultipleScenes` must stay true for CarPlay, so "New Window" / Stage Manager "+" affordances exist but a second app window scene is destroyed on connect. Lifting this properly requires auditing `ChatStore`/`AppContainer` (and every `@State`-held presentation shell: sessions drawer, model selector, composer text) for concurrent scene observation — two windows sharing one `@Observable` store graph means shared composer drafts, shared drawer state, racing scroll proxies, and double-driven streaming UI. Also decide per-window vs shared conversation identity (probably: second window = same conversation read-only, or independent conversation via scene-scoped selection). Until then the refusal stands. Cheap first rung if ever wanted: allow a second window only for the DEBUG GenUI harness (#106) or a future preview surface (#99), which don't touch ChatStore.

Logged 2026-07-12.

## 110. ✅ Read-aloud retracts the collapsed loop — DEVICE-VERIFIED 2026-07-18

> **DEVICE-VERIFIED 2026-07-18 (Owen's device, via the #134 forced-trip harness):** with read-aloud ON, the trip spoke ONLY the single collapsed on-screen line — the repeated loop tail was NOT droned. #110 retraction (`shouldRetractSpeech` / `finishStream(finishedContent:)`, PR #86) confirmed on device.

> **MERGED 2026-07-13 as PR #86 (`a62dc8c`)** — discovered 2026-07-16 when a fresh dispatch found the work shipped (Fable audit branch `claude/fable-t27-110-readaloud-wbsvmy` @ 3c15f1d verifies every acceptance line against the tree; implementation seam: `shouldRetractSpeech` static + `finishStream(finishedContent:)`, five decision tests + suite green via PR #94's Mac run 618/51). Remaining: organic-only device verify (deterministic repro defeated by base-model guardrails per #102). **Ledger lesson: this entry sat 🔧 with no merge note for 3 days and caused a dead dispatch** — merge notes are not optional.

> **Dispatch spec 2026-07-13 (eve):** `dispatch/FABLE-T27-110-readaloud-retract.md` — cloud-safe, pure-decision-fn test gate. Ready to send to CC.

Fell out of Lane H's adversarial review (PR #83), outside its file scope (touches `ChatStore`/`SpeechOutputService`, which Lane H deliberately never contacted): with auto read-aloud ON, a #102 breaker trip rewrites the bubble to one copy of the looped phrase — but the utterances already enqueued during streaming still SPEAK the full run of copies. The user sees the fixed transcript while hearing the loop the breaker just cut.

**Exact fix (documented in PR #83):** at `ChatStore.swift:517`, call `stop()` instead of `finishStream` when the finished content is shorter than the streamed text — a finished reply shorter than what streamed means content was retracted, so flushing the remaining queue is wrong by construction. Small, self-contained, no collision surface with anything in flight.

Only reachable when a breaker trip and auto read-aloud coincide, so low urgency — but when it fires it's maximally weird (eyes and ears disagree). Good candidate to ride along with the next `ChatStore`-touching lane, or as a standalone micro-PR.

Logged 2026-07-13 (Mac session, Lane H merge train).

## 111. 🐛 PCC availability check churns doomed ModelManager sessions on every UI tick (#30 follow-up)

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

## 112. ✨ Midnight Marquee collection — 7 themes / 8 palettes, first adaptive theme, +13 app icons (Lane L)

Claude-Design drop landed 2026-07-12: the **Midnight Marquee** collection becomes the gallery's fifth section. Handoffs committed to `design/themes/` (`midnight-marquee-final-lineup.html` is authoritative; both `*-options.html` files are provenance/rejected alternatives). Lane spec: `dispatch/FABLE-LANE-L-midnight-marquee.md`.

**Scope:**
- **6 standard themes** (SE batch-4 pattern: palette entry + catalog definition + art direction + bespoke orb each): Lucha Libre (Rudo Nocturno), Kaiju Attack (Code Red Tokyo), Pulp Noir (Dime Novel — **light**), Casino Lucky 7s (House Felt), Cosmic Bowling (Carpet Classic), Sticker-Bomb Toybox (Kidcore Shelf — **light**).
- **Comic Book — the app's FIRST ADAPTIVE THEME** (product decision, Owen 2026-07-12): ONE gallery entry that follows the system light/dark appearance. Villain Variant (dark, ink + kapow yellow/panic red) ↔ Sunday Funnies (light, Ben-Day CMY on newsprint). Architectural first: scheme-aware palette resolution (two ThemeIDs, one AppearanceTheme), `preferredColorScheme` = nil for adaptive only, widget-side fork, live re-skin on system toggle. Also the collection's most animated theme — Event Horizon-tier art direction budget.
- **13 icons → 31 total**: the 5 Special Edition icons `AppIconCatalog` reserved a section for (updated `app-icons.html` rev now carries their SVGs) + 8 Midnight Marquee icons (`midnight-marquee-app-icons.html`), incl. both Comic Book variants as separate selectable icons.

**Not in scope:** Haunted VHS stays cut (device verdict 2026-07-11; `.phosphor` orb remains orphaned reusable data). SE themes Aquarium/Forge already shipped (batch 4) — the zip's SE files were byte-identical to repo.

Logged 2026-07-12 (dispatch-prep session).

**MERGED 2026-07-13** — PR #84 (`7f295f8`), 16 commits (12 Fable phase-scoped + Mac review loop's pbxproj regen and 3 build fixes: missing SwiftUI import in the widget timeline provider, and two `displayLabel` overload ambiguities in app + tests — the "compile-clean tracer" verdict missed all three, the loop earning its keep). Suite: **582/582 green across 49 suites** (+12 over baseline). All 39 icon PNGs pure additions; 14 existing icons re-rendered byte-identical.

**Owed on device (whoGoesThere):** Comic Book live-switch (Settings → toggle system appearance foregrounded → villain↔funnies re-skin without relaunch), the two documented seams for Owen's verdict — (a) picker card previews the presented-surface variant while a fixed theme forces the scheme, (b) cold light-mode launch flashes the villain half for one frame before the mirror lands — plus new-icon spot check and light-chrome pass on Pulp Noir / Sticker-Bomb.

**2026-07-13 follow-up (`48770cd`):** icon picker was a silent no-op on iPad — iPadOS reads `CFBundleIcons~ipad` exclusively for alternate-icon support and we only declared the base key (iPhone unaffected). Fixed via YAML anchor/alias in `project.yml` so both keys stay byte-identical with a single edit point. **Shelley's iPad icon-picker check rides her next install.**

## 113. 🔧 Connector supervision — cloud half MERGED (PR #113, 2026-07-18); watchdog INSTALL + forensics owed (Owen/OJAMD)

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

## 114. 🔧 Backend Profiles — server switcher (T6 Part 2): second profile without wiping the first

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

## 116. 🔧 Shim plane — kill the manual token paste + make the probe honest — BOTH HALVES MERGED (PRs #101 + #102, 2026-07-16); DoD device pass owed

> **Loop verdict 2026-07-16:** PR #101 (server half) merged `544b500` — relay suite **124/124**
> and connector suite **115/115** re-run green on the Mac (Fable's Linux run had 114 + 1
> macOS-only skip; the skip runs here). PR #102 (app half) merged `a8b27e0` — loop merged main
> into the branch BEFORE the regen, so the branch tree == merged main tree (tree SHAs verified
> identical `a846d93`); full suite on that exact tree **687 tests / 58 suites green**. Post-merge
> validation satisfied by construction. New baseline: 687/58.
> **Deploy still owed before the DoD device pass:** restart relay + connector on the Mini's live
> checkout (blocked at loop time — the working copy was on `fix/voice-native-blocked`; restart
> after it returns to main) and the OJAMD `ojamd-deploy` rebase (Owen's gate). DoD pass: forget
> Mac pairing → re-pair via QR → auto-fill lands → shim dot honest (NO KEY vs ONLINE) → models
> surface works. Then repeat pairing against OJAMD once it's deployed there.

> **Update 2026-07-16 (Fable lane, PR 1 of 2 — server half built):** connector now ships a
> provisioning descriptor `{shim_base_url, shim_token, gateway_base_url}` on ws hello and
> re-sends on idle heartbeat when anything changed (token file re-read lazily; absent file →
> shim fields omitted; gateway API key EXCLUDED by design). URLs default to the relay-URL
> host (`PUBLIC_BASE_URL` is phone-reachable by definition) with
> `TALARIA_SHIM_BASE_URL`/`TALARIA_GATEWAY_BASE_URL`/`TALARIA_PROVISIONING_HOST` env
> overrides; loopback falls back to the machine hostname. Relay stores it on `hermes_hosts`
> (`provisioning_data` JSON + `provisioning_updated_at`, additive migration — DB-backed per
> the #24f lesson; hello WITHOUT the key preserves the stored bundle, explicit `{}` clears
> it) and serves `GET /v1/device/provisioning` (device-bearer auth, same class as
> `/v1/device/files`; explicit empty shape when nothing reported). Suites: relay 124 passed
> (117 baseline + 7 new), connector 114 passed + 1 macOS-only skip on Linux (104 + 10 new).
> OJAMD deploy rides the `ojamd-deploy` rebase (Owen's gate); Mac deploy = restart relay +
> connector on the Mini's live checkout. PR 2 (app half: auto-fill on pair, honest
> authenticated shim probe, re-provision affordance) follows stacked on this branch.
>
> **Update 2026-07-16 (Fable lane, PR 2 of 2 — app half built):** new
> `Services/Support/ProvisioningService.swift` — after a successful `pair()` the
> `onProfileTokensMinted` hook (fires only after the redeem, so #94 redeem-first and the
> per-profile clean slate are untouched) pulls `GET /device/provisioning` with the fresh
> profile-scoped tokens and fills EMPTY fields only: shim URL + shim token (Keychain,
> `BackendProfileScopedKeys.shimToken(scope)`; active profile routes through
> `saveModelsShimToken` so the in-memory box updates too) and an empty gateway URL — never
> the gateway key, never a manual value. Honest probe: `ServerSettingsScreen` shim probe is
> now two-step (`/healthz` reachability → authed `GET /models?refresh=0`), pure
> `classifyShimProbe(healthzStatus:authedStatus:)` for tests; answering-but-unkeyed renders
> NO KEY like the gateway. "Refresh Provisioning" context-menu action on paired cards =
> `.refresh` mode (rotates the shim token; URLs still fill-empty-only) + honest summary
> notice. Extended within the #114 static-probe/accumulator-box pattern — no
> `withTaskGroup`. Tests: `ProvisioningServiceTests` (7) + shim classifier in
> `ServerSettingsTests`. **Cloud-written, NOT compiled** — next Mac session: merge PR 1 →
> PR 2, `xcodegen generate` (1 new source + 1 new test file), CLI build + tests, then the
> DoD device pass (forget Mac pairing → re-pair via QR → auto-fill within seconds → probe
> shows authenticated-online → models surface works; restart Mini relay+connector first).

Two related gaps surfaced during #114 device verification (2026-07-16):

1. **Provisioning:** the shim token (`~/.hermes/talaria_shim_token` on each host) had to be
   manually located on the host and pasted into the profile — bad for Owen every time, worse
   for any future user installing the stack. The pairing QR configures the relay plane only
   (#108); the gateway key at least has the Uplink nudge. The shim has nothing.
   **Candidate design (preferred):** post-pair provisioning bundle — after a successful pairing
   redeem, the app pulls a host-provisioning payload from the relay (connector supplies it via
   the internal API: shim base URL + shim token, possibly gateway base URL), authenticated by
   the fresh pairing token, and auto-fills the profile. Alternative: fold the shim fields into
   the QR payload itself (connector `pair-phone` change). Decide whether the gateway API key
   joins the bundle or deliberately stays a manual gate.
2. **Probe honesty:** `SHIM ONLINE` comes from unauthenticated `/healthz`, so the dot is green
   with a missing/wrong token. Give the shim probe the gateway treatment: when a token is
   present, make an authenticated call and render answering-but-unkeyed distinctly
   (ServerSettingsScreen probe layer, small).

Server-side touches ride the fork (relay internal API + connector), app-side is a small lane
or rides the next Settings lane. Logged 2026-07-16.

---

## 117. 🔧 Health-drain give-up paths hammered the connector — no-backoff loop (PR #85 follow-up) — MERGED PR #103

Found by Fable re-reviewing the merged #104 work against its spec (2026-07-16): in
`drainOutboxIfPossible()`'s health phase, every give-up outcome (transient failure,
busy-retry exhaustion, stalled poison isolation) ended in a bare `break` that only exits
the `switch` — the `while` loop then re-sent the same failing chunk back-to-back with **no
backoff for as long as the outage lasted**. That is the #113 dead-connector shape from the
app side, and it also made the #104 drain-end flush unreachable while wedged.

Fix (`SensorUploadService.swift`, MERGED as PR #103 @ `4ec97dc`): trailing loop-break
mirroring the location phase's idiom — give-up paths exit the drain and keep the backlog
for the next trigger, with honest deferral notes ("retries exhausted" / "upload failed").
Injectable `busyBackoffWait` seam (2/4/8s ladder) for deterministic tests. 4 regression
tests (`SensorDrainGiveUpTests`, circuit-breaker-guarded so a reintroduced loop fails on
attempt counts). Mac loop 2026-07-16: BUILD SUCCEEDED, full suite **647 tests / 55 suites
green**. M-8 destination routing untouched.

Device verify owed: during a connector outage the diagnostics panel should show drains
deferring instead of continuous POST traffic. Cross-refs: #104 (parent), #113 (the
server-side twin — connector supervision), #24a (chunking semantics preserved).

Logged 2026-07-16.

---

## 118. 🔧 Voice capture background teardown — MERGED (Lane V, PR #112, 2026-07-18); device re-verify owed

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

## 119. 🔧 Voice UI cancel-race banner + CONNECTING header — MERGED (Lane V, PR #112, 2026-07-18); device re-verify owed

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

## 120. 🔧 Chat message list — duplicate ForEach IDs — FIXED in lane (PR #116, 2026-07-18); device check owed

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

## 121. ✨ Reasoning on resume — restore thinking panes from stored messages — MERGED (PR #120) 2026-07-19

The #25 wire probe (2026-07-16) found `GET /api/sessions/{id}/messages` carries `reasoning` +
`reasoning_content` per row — fetched on every resume, currently discarded. Live turns restore
reasoning via `run.completed` (#60 / PRs #94+#95); resumed sessions render permanently empty
panes. Decode the fields (tolerant), map into the same message property the live path writes,
and apply the SAME #60 answer-mirror guard (reasoning identical to content → dropped). No new
UI — the existing pane renders when the field is populated.

> **Dispatch spec 2026-07-17:** `dispatch/FABLE-T27-121-reasoning-on-resume.md` — **READY TO
> SEND.** Cross-ref #60 (the answer-mirror trap is restated in the spec as non-negotiable).

> **MERGED 2026-07-19 as PR #120** (branch `claude/fable-t27-121-resume-tlccml`, 1 commit,
> mod-only — no regen). Stored `reasoning`/`reasoning_content` rows now decode tolerantly and
> populate the same message property the live path writes; #60 answer-mirror guard verified
> applied on BOTH resume decode paths (`SessionsHermesClient.swift` ~356/359 and ~417).
> Combined-main gate 893/77 green. → ✅ on device verify: resume a session with prior
> reasoning turns, confirm panes render collapsed and no answer-mirror duplicates appear.

Logged 2026-07-17.

---

## 122. ✨ Session cost & usage surface — MERGED (PR #121) 2026-07-19

The #25 probe proved session-level `input_tokens` / `output_tokens` / `cache_*` /
`reasoning_tokens` / `estimated_cost_usd` / `actual_cost_usd` / `api_call_count` are served on
the sessions list + detail endpoints — cumulative billing figures, banned as a context meter,
perfect as a cost readout. Compact per-session usage row on the existing session metadata
surface: cost (actual preferred, `~` for estimated), tokens in/out, api calls; absent data hides
the row (never $0.00 for unknown). No aggregation, no new screens; a spend-over-time chart is a
future #100 rider only.

> **Dispatch spec 2026-07-17:** `dispatch/FABLE-T27-122-session-cost.md` — **READY TO SEND.**

> **MERGED 2026-07-19 as PR #121** (GitHub PR number — distinct from this item number;
> branch `claude/fable-t27-122-session-cost-8x527x`, 5 commits, mod-only — no regen).
> `SessionUsage` decode + cumulative usage threaded through the sessions list; spend row on
> Sessions settings (actual cost preferred, `~` estimated, absent data hides the row — never
> $0.00 for unknown). Combined-main gate 893/77 green. → ✅ on device verify: spend row
> shows real figures against live gateway sessions and hides on sessions without usage data.

Logged 2026-07-17.

---

## 123. ✨ Share extension — send anything into a Hermes session (free tier)

Inbound share sheet: URL/image/PDF/text from any app → app-group envelope → drained into the
composer as `PendingAttachment`s on next activation. New `TalariaShare` target modeled on
TalariaWidgets; NO network in the extension. The habit-forming missing half of the agent-files
pipeline.

> **Dispatch spec 2026-07-17:** `dispatch/FABLE-T27-123-share-extension.md` — **READY TO SEND.**
> Note: adds a TARGET — the regen is substantial; both targets' entitlements verified post-regen.

**UPDATE 2026-07-19 — BUILT + suite-green + sim-smoked in lane (branch
`claude/t27-123-share-extension`), Mac-compiled; device checks owed.** Dispatch scope exactly:
- **Core:** `ShareEnvelope` (ISO-8601 JSON contract) + `SharedInboxStore` over app-group
  `SharedInbox/` in `TalariaShare/ShareInboxCore.swift` — compiled into the app as a single
  file so widgets stay untouched. Blobs-first/`envelope.json`-last completeness marker; drain
  sorts by createdAt, dedupes by id, and corrupt/oversize/stale-incomplete dirs are skipped
  AND cleaned (tolerant, house rule); 20MB write cap; traversal-safe blob names.
- **Target:** `TalariaShare` appex modeled on TalariaWidgets — app group in its OWN
  entitlements + project.yml declaration (strip trap covered for BOTH targets). Dictionary
  activation rule (1 URL / 4 images / 1 file / text — NO TRUEPREDICATE) pinned from the
  BUILT appex by `ShareExtensionConfigTests` (#108 built-plist pattern). Sheet = minimal
  self-contained SwiftUI; NO network/HealthKit/location. Honesty gate IN the sheet: the MIME
  tables moved to `StageableTypeCatalog` (ShareInboxCore; `PendingAttachment` forwards,
  byte-identical) so wrong-type and over-20MB payloads (the 25MB-video case) are refused
  with visible reasons instead of vanishing at drain time.
- **App side:** `ShareInboxDrainer` on scene-activate BEFORE the pairing gate (free-tier
  surface) + cold-launch net in `initialize()`; blobs re-materialize through the EXISTING
  `PendingAttachment.file(at:)` staging path. ChatStore share-seed slot is SEPARATE from the
  #48 ask-seed: merges queued shares, APPENDS to a draft (never destroys it), deep-routes to
  chat. Known v1 simplification: drain file IO runs on the main actor (same class of work as
  the picker path, bounded by the 20MB cap) — revisit only if a real hitch shows.
- **Verified here:** full suite 845/72 green (baseline 755/62 + the 22 new tests;
  TEST SUCCEEDED incl. active UITests) after the regen; pbxproj diff PURE INSERTIONS,
  widgets/tests untouched; both targets' entitlements survived. Sim integration smoke: a
  hand-planted envelope in the sim's app-group container was consumed on cold launch and the
  composer showed note + URL, focused, UNPAIRED on the on-device brain.

**Device checklist (Owen, whoGoesThere):** Safari URL → composer text; Photos photo →
image chip; Files PDF → file chip; two rapid shares → both land in order; 25MB video →
polite refusal in the sheet; share while force-quit → lands on next launch; `hermes://ask`
regression (separate seed slots).

Logged 2026-07-17.

---

## 124. ✨ Face ID app lock (free tier)

`.deviceOwnerAuthentication` (passcode fallback, never biometry-only), scene-root overlay on
launch + return-to-foreground with grace-period setting, obscured app-switcher snapshot, Siri
intent path unaffected. `NSFaceIDUsageDescription` via project.yml info.properties (the #58
INFOPLIST_KEY lesson).

> **Dispatch spec 2026-07-17:** `dispatch/FABLE-T27-124-faceid-lock.md` — **READY TO SEND.**

**Built 2026-07-19 (Mac session, branch `claude/t27-124-faceid-lock`), TDD fail-first:**
pure `AppLockStateMachine` in `Services/Support/AppLockCore.swift` (scenePhase × grace ×
toggle × auth matrix, 16 tests; grace clock keys on `.background`, NOT `.inactive` — the
Face ID sheet itself is `.inactive` and would re-trigger its own lock otherwise);
`AppLockController` + `BiometricAppLockAuthenticator` in `Core/AppLock/` (fresh `LAContext`
per attempt; capability degradation: no-biometry→passcode-policy label, no-passcode→toggle
disabled AND a stale enabled flag neutralized so the app can't brick itself; auto-prompt
once per lock episode, retry button after fail/cancel). Cover lives in a **dedicated
UIWindow at `.alert + 1`** (not a root ZStack — sheets/alerts present ABOVE the root view,
so a ZStack overlay would leave an open sheet readable over the "lock"; the same window is
the scenePhase-driven app-switcher snapshot obscurer). Intent-bypass decision pinned in
`AppLockController`'s header comment (headless Ask Hermes runs while locked; anything
landing in the UI hits the cover). Settings: `UserSettings.appLockEnabled/appLockGracePeriod`
(default off/immediate, legacy-decode-safe) + Privacy screen App Lock section (adaptive
capability label, immediate/1 min/5 min grace segments). `NSFaceIDUsageDescription` in
project.yml info.properties; regen verified — entitlements intact. Lane V (#118) voice-end
already in main; no ordering interaction.

**Device checklist (whoGoesThere):**
- [ ] Toggle on → background → reopen → Face ID prompt appears over content.
- [ ] Fail twice / cancel → retry button → system sheet passcode fallback unlocks.
- [ ] App switcher shows the obscured splash-style snapshot, not chat content.
- [ ] Grace 1 min: background <1 min → no prompt; >1 min → prompt.
- [ ] Siri "Ask Hermes" works while locked; tapping its result lands on the lock.
- [ ] Backgrounding with a sheet open (Settings) → reopen → cover is ABOVE the sheet.
- [ ] Incoming push while locked: banner arrives, UI stays locked.

Logged 2026-07-17. Built 2026-07-19 — suite 870/76 green (was 845/72) + UI tests green.

---

## 125. ✨ Health trends view — native, on-device (free-tier flagship)

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

## 126. ✨ Daily briefing — app half (connected-tier centerpiece)

Host cron synthesizes health + calendar + threads → inbox `notification` with markdown body
(may carry ```chart fences — dormant Path A wakes scoped to briefings), optional `speakable`,
`category: "briefing"`. App: detail view via MarkdownContentView, read-aloud via the existing
gated SpeechOutputService, latest-briefing widget via SharedWidgetDataStore, hermes:// deep
link. Host half = Owen's cron config against the JSON contract in the spec/PR.

> **Dispatch spec 2026-07-17:** `dispatch/FABLE-T27-126-daily-briefing.md` — **READY TO SEND.**

Logged 2026-07-17.

---

## 127. 🔧 Monetization scaffold — MERGED DORMANT + gate walk DEVICE VERIFIED 2026-07-17 (fail-open live-confirmed on BOTH hosts: gate forced on, existing OJAMD + Mac pairings kept working, profile switch + chat clean); ASC product + sandbox purchase owed pre-flip

> **MERGED 2026-07-18 (PR #114, `62d169b`), fully dormant** — `MonetizationConfiguration.isEnabled
> = false`, one-line flip at launch. Loop-verified against every trap in the dispatch: gate wraps
> the paywall at the PRESENTATION site (ContentView swaps `ConnectedPaywallView` for
> `ConnectHermesHostScreen` on `.showPaywall`; the pairing screen itself untouched); the pure
> `ConnectGate.verdict` matrix pins fail-OPEN for existing pairings and cached-entitled unknowns,
> fail-closed only for new connects with no entitlement evidence; both product-kind scan paths
> behind `MonetizationConfiguration.productKind` (subscription nil-expiry errs toward the payer);
> price only via StoreKit `displayPrice`; DEBUG override in Developer settings. **20 new tests
> (MonetizationGateTests); suite 800/67 — new baseline.** Tree-identity validated. → **Owed
> (Owen, pre-flip):** App Store Connect product `org.aethyrion.talaria27.connected` + sandbox
> tester (steps in the PR body); device sandbox purchase + restore round-trip; DEBUG-override
> gate walk. Benign loop note: a sim-side stale `hermes.sessionUsageIndex` value exercised the
> #25 tolerant decode (logged + recovered) — the tolerance working, nothing owed.

Free = standalone (on-device model, voice, OCR, widgets, trends, share, lock). Paid "Connected"
= the connect-your-own-host feature set (pairing, profiles, uplink, inbox, realtime).
EntitlementService (StoreKit 2, both product-type paths behind a constant), gate wraps CONNECT
ENTRY POINTS only — existing pairings fail OPEN on transient entitlement failure; new connects
fail closed. Paywall sheet (displayPrice, restore, dismissible), DEBUG override, and the whole
gate lands DORMANT behind `monetizationEnabled=false` until launch.

> **Dispatch spec 2026-07-17:** `dispatch/FABLE-T27-127-monetization-scaffold.md` — **READY TO
> SEND.** StoreKit greenfield verified. App Store Connect product setup = Owen, steps in the PR.

**Update (2026-07-17): scaffold BUILT on `claude/fable-t27-127-monetization-spgkzl` —
cloud-written, NOT compiled.** What landed:

- **Pure core** (`Services/Support/MonetizationGate.swift`): `MonetizationConfiguration`
  (`isEnabled = false` **DORMANT** — the flip-at-launch line; product id
  `org.aethyrion.talaria27.connected`; `productKind` constant selecting
  non-consumable vs annual-sub, BOTH paths implemented everywhere it's consulted),
  `ConnectGate.verdict` (the pinned matrix: dormant → allow; existing pairing →
  ALWAYS allow; new connect: entitled → allow, not-entitled → paywall even over a
  stale cache, unknown → cached-paid fails open / else closed), `EntitlementScan`
  (per-kind transaction classification + definitive-only cache updates),
  `PaywallPresentation` (displayPrice-or-"—", always dismissible, unlock-only
  auto-close), DEBUG override combinators + `MonetizationDebugSettings`
  (UserDefaults, compiles out of Release).
- **Service trio**: `Services/Protocols/EntitlementServiceProtocol.swift`,
  `Services/Live/EntitlementService.swift` (StoreKit 2 —
  `Transaction.currentEntitlements` launch scan + `Transaction.updates` listener,
  started from `makeDefault()` even while dormant for transaction hygiene; purchase +
  `AppStore.sync()` restore; last-known cache in UserDefaults),
  `Services/Mocks/MockEntitlementService.swift` (scriptable).
- **Gate wiring**: `AppContainer.connectGateVerdict(for:)` is the one seam. Entry
  points: the `.connectHost` pairing-flow branch in `MainTabView.routeDestination`
  (covers all four `navigate(.connectHost)` call sites; the paired-host MANAGEMENT
  screen stays ungated — a live pairing is never severed), Server `Add Profile` +
  pair-unpaired-profile (re-pair of a paired profile = existing → passes), Uplink
  first-key save (`keySaveAttempt` static, rotation ungated).
- **Paywall**: `Features/Paywall/ConnectedPaywallView.swift` (+`ConnectedPaywallSheet`
  wrapper) — theme-tokened, Connected feature list, `Product.displayPrice` only,
  purchase/restore/"Not now", pending (Ask to Buy) surfaced, always dismissible.
- **DEBUG driver**: Developer screen "// Monetization" section — Connect Gate toggle
  (activates the dormant gate for that build; can never deactivate a launched gate) +
  entitlement override picker (SYSTEM keeps real StoreKit so sandbox round-trips work
  with the gate live) + honest STOREKIT status row.
- **Tests**: `TalariaTests/MonetizationGateTests.swift` — dormancy pinned (the test
  fails loudly on flip day, delete it in the launch commit), full gate matrix, both
  product-kind scan paths, cache rule, override combinators, paywall rules, key-save
  classification, mock unlock semantics.

**Next Mac session checklist:**
- [ ] Merge, `xcodegen generate` (6 new source + 1 new test file; re-verify
      `aps-environment` + weatherkit + widget-HealthKit survive regen per #44/#48 —
      no project.yml changes were made, in-app purchase needs no entitlement key)
- [ ] CLI build + full suite — green ≥ 755/62 (post-#113 baseline 780/65)
- [ ] Compile-risk shortlist: `product.purchase()` may warn deprecated on the iOS 27
      SDK in favor of `purchase(confirmIn:)` (warning-only expected); switch-expression
      assignments in `DeveloperSettingsScreen.entitlementStatusLabel`; `@Observable`
      conformance to the `EntitlementServiceProtocol` existential
- [ ] Device: Developer → Connect Gate ON + override LOCKED → paywall at Server "Add
      Profile", Server "Pair" (unpaired profile), Uplink first-key save, and the
      pairing flow via Uplink "Pair Device" / Chat / System Settings; override
      UNLOCKED → all pass; gate OFF → dormant (production behavior)
- [ ] Device fail-open check: gate ON + LOCKED with an EXISTING pairing — chat,
      sensors, re-pair, key rotation all keep working; only NEW connects gated
- [ ] Sandbox (after Owen's App Store Connect setup): override SYSTEM, purchase +
      restore round-trip; price renders from displayPrice (never hardcoded)
- [ ] Owen (App Store Connect): create the in-app purchase with product id EXACTLY
      `org.aethyrion.talaria27.connected` (non-consumable to start — flip
      `MonetizationConfiguration.productKind` if pricing lands on the annual sub),
      create a sandbox tester account; steps also in the PR body
- [ ] Launch day: flip `MonetizationConfiguration.isEnabled = true`, delete the
      `scaffoldShipsDormant` test in the same commit

Logged 2026-07-17.

---

## 128. 🔧 Voice capture crash — double installTap via actor reentrancy — FIXED (2026-07-17); device re-verify owed

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

## 129. 🐛 Voice preview mid-session routes through the CHAT TTS instance — category yank under a live engine (the #128 trigger)

> **Dispatch spec 2026-07-17:** `dispatch/FABLE-T27-129-preview-instance.md` — **READY TO SEND** (micro; option (a) selection function, audio law restated).

`VoiceSettingsScreen:187` `speechOutput.previewVoice()` uses the chat instance
(`managesAudioSession = true`); during an active voice session each preview flips the shared
session to `.playback` and back under the running capture engine — the interruption/route burst
that lit #128's race, and even crash-free it degrades the live session. The `isBlocked` gate
protects `speak()` but not `previewVoice()`. Decide + fix (small): (a) while a session is
active, route previews through `nativeSpeechOutput` (gate off, no session management — preview
plays over the live session; probably the right UX), or (b) apply `isBlocked` to preview and
show 'end the session to preview voices'. Either is a micro-PR; (a) preferred pending Owen's
call.

Logged 2026-07-17.

---

## 130. 🎧 In-session TTS fidelity — voiceChat downlink processing makes voices muddy vs previews; VPIO render-err flood

> **Dispatch spec 2026-07-17:** `dispatch/FABLE-T27-130-halfduplex-probe.md` — **READY TO SEND** (A/B probe branch, DO-NOT-MERGE label; Owen's on-device verdict decides #130).

Device observation 2026-07-17 (post-#128, conversation working): in-session TTS is noticeably
less crisp than the settings previews. Cause is structural, not a bug: previews play on a
`.playback` session (full fidelity); session TTS rides `.playAndRecord` + `.voiceChat`, whose
voice-processing chain telephony-tunes the DOWNLINK (AGC, bandwidth shaping, receiver EQ) so
echo cancellation has a reference. Same log shows a continuous `auou/vpio render err: -1` flood
— nonfatal now (#106 keeps the session alive) but CPU-noisy and plausibly part of the quality
loss; `mBuffers dataByteSize (0)` interleaved.

Options (design decision, prototype before choosing):
(a) **Half-duplex + `.default` mode** — the vpio-bypass probe PROVED raw capture works on this
    seed; drop VP entirely, gate transcription while TTS speaks (pipeline already tracks
    speaking state for barge-in). Crisp TTS, quieter logs; trade: talk-over barge-in degrades to
    tap-or-gap interruption. Sensitivity note from the probe run ("very sensitive") predates
    #106 — re-evaluate on the fixed session.
(b) Keep `.voiceChat`, accept telephony TTS (status quo; every voice-chat app sounds like this).
(c) Hybrid: `.videoChat` mode or VP-with-ducking-config tuning — marginal gains, same chain.

Owen's call after an (a) prototype run. Dispatchable as a small probe branch first.

Logged 2026-07-17.

---

## 131. 🐛 Composer mic (dictation) inert — silent-swallow catch FOUND + instrumented 2026-07-17; next device tap names the failing error. SUSPECT CORRECTION: Lane V touched LiveVoiceSessionService (realtime), NOT LiveSpeechService (dictation, untouched since the wedge era) — the original Lane-V attribution was wrong

Device 2026-07-17: pressing the composer mic does nothing (OJAMD and Mac Mini, monetization gate
on — gate almost certainly irrelevant: the button calls `toggleDictation()` on `speechService` =
`LiveSpeechService`, which Lane V's async-setActive rider REWROTE the same day (+102/-45). Prime
suspect: rider regression in the dictation start path (activation reordering / early-return
guard). Discriminators owed: (a) dev-override gate OFF → retry (rule the gate out formally);
(b) confirm mic worked on the pre-tonight build. Investigate the rider's LiveSpeechService diff
first; likely a micro-fix.

Logged 2026-07-17.

---

## 132. 🐛 Image attachments dropped HERMES-SIDE — app exonerated by wire probe (2026-07-17); host model-vision/config question for Owen

> **Wire probe 2026-07-17 (curl direct to OJAMD `:8642`, zero app involvement):** (1) parts array
> with an INVALID image → HTTP 400 'prepare image failed: failed to decode image' — the gateway is
> image-aware and validates; (2) parts array with a VALID 1×1 PNG → request accepted, turn ran,
> and the model reports **'No image came through'**. Validated, then dropped before the model.
> The app's wire encoding was also read end-to-end and is correct (`ChatTurnBody` → parts array
> with `image_url` data-URLs; attachment-only display text is '[1 attachment]', so the stored
> '[screenshot]' was likely Owen's typed caption — immaterial now). **Ownership: Hermes-side.**
> Candidates: active model lacks vision and the gateway strips images post-validation without
> surfacing it (worst kind of silent), or tonight's hermes update broke prepared-image →
> model-call attachment. **Next (Owen/host):** check the active model's vision capability in the
> hermes config; re-probe after pointing a session at a known-vision model. The 07-13 paste→send
> pass suggests this worked pre-update — if a vision model was active then, tonight's update is
> the regression window. App-side follow-up only if Hermes turns out to REQUIRE a different wire
> shape than the OpenAI-style parts the app sends (nothing suggests so — the 400 proves the shape
> parses).

Device 2026-07-17 (blocked the #61 card re-verify): attachment-only send (screenshot, no text)
→ the model reported receiving only the literal text "[screenshot]" with no image attached. The
streaming client DOES carry `attachments: [PendingAttachment]` end-to-end (verified in
`SessionsHermesClient.sendStreaming`/`streamTurn` signatures), so the drop is either in the
attachment→wire encoding, the gateway's handling of image parts, or an attachment-only-specific
path (text+image may behave differently — discriminator owed: send image WITH text and ask what
arrived). "[screenshot]" literal appears nowhere in the app source (grep verified) — determine
who synthesizes it (app placeholder text vs gateway part-stringification); that answers which
side owns the fix. History note: paste→send round-trip passed device verify 2026-07-13, so if
text+image also fails, the regression window is this week's merges; if only attachment-only
fails, it may never have worked.

Logged 2026-07-17.

---

## 133. 🔧 Dormant-relay push registration idempotency — MERGED (PR #123, merge `0bc2e0c`, 2026-07-20); device pass owed (M-7 follow-up)

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

## 136. 🔧 Offline-first launch — MERGED (PR #122, 2026-07-19); device pass owed

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

## 137. ✨ Sensor opt-in redesign — kill the post-pair permissions wall (public-app posture)

**Approved by Owen 2026-07-20.** The Wave 4.5 redesign (#71) removed the pairing wall from
first launch, but `PermissionsOnboardingScreen` still runs as an all-at-once permission wall
immediately after a successful pair — health front and center. For a public app that is the
wrong shape even for the Connected tier: it torches adoption of the optional sensor/MCP layer
by demanding the scariest grants at the moment of least trust.

**Design:** pairing grants CHAT, nothing else. Remove `PermissionsOnboardingScreen` from the
post-pair flow entirely. Sensors become a deliberate second decision: a "Sensor Streaming"
master opt-in in Settings, OFF by default, with per-sensor enables that request OS
authorization contextually at enable time (the #69 device-tool-belt pattern — one grant, in
context, user-driven). The capture/drain loop is gated on the opt-in, not on pairing.

**Grandfathering (non-negotiable):** existing paired devices already streaming sensors must
migrate with the master toggle ON — the redesign must not silently turn off streaming for
users who already consented. One-shot migration keyed on existing sensor activity/grants.

**Kept intact:** #23 revoke affordances; HealthKit check-before-request rule; the
Hermes-gating of the upload path (opt-in gates capture on top of it, not instead of it).

**Dispatch spec:** `dispatch/FABLE-T27-137-sensor-optin.md`

Logged 2026-07-20.
