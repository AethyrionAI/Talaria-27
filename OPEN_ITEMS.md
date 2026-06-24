# Talaria — Open Items / Follow-ups

**Compiled:** 2026-06-23 · **From:** the models-shim / Phase-B wiring session.
**Landed this session (on `main`, merge `98a9a89`):** T1 (Settings→Models dual-write
picker), T2 (regex + copy fixes), shim cache-bust. See the merge commit for detail.

Status legend: 🔧 in progress · ⛔ blocked · 💤 dormant · 🐛 bug · 📝 note / decision · ✅ done.

---

## 1. 🔧 T4 — Host reconciliation (chat gateway ↔ shim)

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

---

## 2. ⛔ T3 — Settings screens build (BLOCKED)

Needs the Claude Design deliverable: the 8-screen **`Settings.dc.html`** (from
`TalariaSettings.zip`) placed at **`design/Settings.dc.html`** in the repo. Then build the
6 non-MODELS screens (01 SYSTEM, 02 UPLINK, 05 VOICE, 06 APPEARANCE-HUD, 07 SESSIONS,
08 DIAGNOSTICS). MODELS (03/04) is already done (T1). **Blocker: hand off the design file.**

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

## 5. 📝 Host-status display quirk

In Settings, the host orb briefly showed "OFFLINE · STANDBY" (amber) while the Connection
row's "Status" read "CONNECTED". Likely transient / two sources of truth for host health.
Worth a glance; not a blocker.

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

## 10. 🐛 Top-center model chip shows a placeholder, not the active model

The ChatScreen top-center `ModelSelector` chip displays the hardcoded placeholder
("CLAUDE OPUS 4.6") instead of the actually-selected/active model. It should reflect the
real active model — seed it on launch from the gateway's active model / the shim's current
`model` (e.g. `kimi-k2.7-code`) and keep it in sync after a pick. Today `activeModelName`
is nil until a `/model` switch is detected over chat, so a fresh launch shows the
placeholder and the chip's `availableModels` is still the opus/sonnet/haiku stub.

---

## 11. 🐛 Settings back-nav exits Settings instead of popping

Navigating into some Settings sub-screens and tapping Back exits Settings entirely instead
of returning to the previous screen. Back should pop to the prior screen within the
Settings stack. Audit the Settings navigation (NavigationStack push vs sheet presentation;
the custom HUD back buttons' `dismiss()` vs an explicit path pop). Owen to pinpoint which
screens on-device.




---

## 12. 🐛 Sensor data stale / not collecting on-device

First on-device run shows sensor data via the MCP bridge (Location, HealthKit, Activity)
but everything is **stale since June 16**. The relay path (iPhone → Hermes) works — the
MCP calls return cached data — but the phone's local SQLite hasn't had fresh samples
written. This is a fresh install on whoGoesThere.

Likely causes (investigate in order):
1. **Permissions not granted.** The Permissions screen (Settings → Permissions) has
   Location, Health, Notifications, Microphone — all showed "NOT SET" / "ENABLE" in the
   simulator. On the physical device, did all four get enabled? HealthKit in particular
   requires explicit per-type authorization.
2. **Background collection not running.** The `SensorUploadService` may need an active
   session or a relay enrollment to start its background timer. Check whether the service
   is instantiated (it's optional in AppContainer) and whether it starts collecting on
   permission grant.
3. **Relay enrollment.** The model mentioned "OJAMD connector being unenrolled/paused."
   If sensor upload requires an active relay enrollment, re-enroll.

The data coming back (steps 4937, walking 3198m, location at Saucier) is real but week-old.
Fresh collection needs to flow before sensors are useful.

---

## 13. 🐛 Model identification is unreliable — app displays config, not reality

On-device conversation reveals model identity is wrong at multiple levels:

1. **Top chip** says "CLAUDE OPUS…" — hardcoded placeholder (→ Open Item #10).
2. **The app displayed "kimi"** as the active model/provider (from the shim config), but
   the model that **actually responded is MiniMax-M3** (which is vocal about its own
   identity). This is not a cosmetic issue — the routing itself sent the request to a
   different model than what the config/shim reports. Either Hermes is aliasing
   `kimi-k2.7-code` to MiniMax under the hood, or the config pointer has drifted from
   what's actually being served.
3. **The Hermes system header** reported `kimi-k2.6` (stale session pin from an earlier
   test) while the persistent default is `kimi-k2.7-code`.

**Root problem:** Talaria currently echoes whatever the shim config says (provider slug +
model id) without verifying what actually answered. Hermes supports dozens of providers
and models — anthropic, deepseek, kimi, minimax, openai, nous, etc. The app must work
with **all of them**, not assume the config is correct.

**What needs to happen:**
- **Talaria (app):** the model display should reflect what's actually being served, not
  just parrot the shim's config slug. Options: (a) parse the gateway's response headers
  for the real model id / provider, (b) ask the model to self-identify on session start,
  (c) add a lightweight `/status` or `/whoami` endpoint to the gateway that returns the
  actual routed model after resolution.
- **Hermes (upstream):** investigate why `kimi-k2.7-code` via `kimi-coding` resolved to
  MiniMax-M3. Is this a provider alias, a fallback chain, or a config bug? The shim and
  gateway need to agree on what's actually being served.
- **General:** model identification must be provider-agnostic. Don't tie display logic to
  any single provider's naming convention.

---

## 14. 📝 Shim token onboarding — needs a frictionless flow

Currently the shim bearer token lives in `~/.hermes/talaria_shim_token` on the mini and
must be manually copied to the phone (Universal Clipboard / AirDrop / paste). This is a
dev-only workflow — real users (even Owen) shouldn't have to SSH into a server and cat a
file.

Possible approaches (pick one or combine):
- **QR code on the shim.** Add a `/pair` or `/qr` endpoint to the shim that renders a
  QR code containing the token (or a short-lived pairing URL). The app scans it once.
  Protected by requiring local-network access or a one-time PIN.
- **Derive from the existing Hermes API key.** If the shim could accept the same API key
  the app already stores for the Sessions API, no second token is needed. Would require
  the shim to validate against the same key store.
- **Pairing handshake.** During the existing relay pairing flow (the 8-digit code), have
  the shim token piggyback on the pairing response so it's automatically stored.
- **mDNS/Bonjour discovery + auto-pair.** The shim advertises on the local network; the
  app discovers it and exchanges tokens automatically (like AirPlay).

The goal: zero manual token entry for the end user. The shim URL can default to
auto-discovery or the tailnet IP; the token should be exchanged, not typed.


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
