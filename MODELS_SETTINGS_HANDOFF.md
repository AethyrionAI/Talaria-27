# Talaria — Models Screen + Settings Handoff

**Date:** 2026-06-23 · **Branch:** `feat/phase-b-wiring` (HEAD `e019415`, clean) ·
**For:** a fresh Claude Code session (no prior context assumed).

Prior context docs in repo root: `HUD_REDESIGN_HANDOFF.md`, `PHASE_B_HANDOFF.md`,
`HANDOFF_RENAME_TALARIA.md`. This one supersedes the model-picker portions.

---

## 0. TL;DR — what to build

The backend for the model picker is **done and live** (a "models shim" — see §3).
Your job: wire the Talaria **Settings → MODELS** screen to it, fix two known
selector bugs, and build out the rest of the Settings screens. Tasks are in §5,
prioritized. **T1 is the through-line; T2 rides with it.**

Desired MODELS screen (Owen's spec): show the available models compiled within a
freshness window, a **Refresh models** button, a check/symbol on the active model,
and tapping a model applies to **both** the current session and the persistent
default.

---

## 1. Environment & build

- **Repo:** `/Users/owenjones/Documents/Claude/Talaria` · GitHub `ChronoRixun/Talaria`
- **Host:** Owen's Mac mini (zsh). You have shell via Desktop Commander.
- **Project gen:** XcodeGen. `project.yml` is the **source of truth**. After adding/
  removing files or editing `project.yml`, run `xcodegen generate`.
  **NEVER hand-edit `Talaria.xcodeproj`.**
- **Build:**
  ```sh
  cd /Users/owenjones/Documents/Claude/Talaria
  xcodebuild -project Talaria.xcodeproj -scheme Talaria \
    -destination 'id=47F68496-24F9-45D9-93D3-1C778DB6B557' build
  ```
  Require `** BUILD SUCCEEDED **`. Target: iPhone 17 Pro Max / iOS 26
  (sim id `47F68496-24F9-45D9-93D3-1C778DB6B557`).
- **Bundle:** `org.aethyrion.talaria` · Team "James Jones".
- **Deploy to sim:** terminate → install → launch (installing over a *running* app
  only foregrounds the old process). Built app at:
  `~/Library/Developer/Xcode/DerivedData/Talaria-bkmofmhhchhruzcdudrizbbblrae/Build/Products/Debug-iphonesimulator/Talaria for Hermes Desktop.app`
- idb taps work; idb **keyboard injection does not**. SwiftUI popovers are finicky
  under idb taps.

---

## 2. Current state (done)

- HUD redesign (cyan `#54e6f0`, Chakra Petch/Space Grotesk/JetBrains Mono) — on `main`.
- Model selector wired, sessions drawer wired, connectivity-banner fix — on this branch.
- **Models shim built, tested, running under launchd, committed `e019415`** — see §3.
- Captured real model list fixture: `tools/models-shim/model_options.sample.json`.

---

## 3. The Models Shim — backend contract (READ THIS)

A minimal Tailscale-bound HTTP service on the mini that exposes Hermes's model list
and persistent set-default **without** the privileged dashboard plane. Source +
README: `tools/models-shim/` (`shim.py`, `*.plist`, `README.md`, sample JSON).

- **Running as:** LaunchAgent `com.aethyrion.talaria.modelsshim` (RunAtLoad+KeepAlive).
- **Base URL:** `http://100.79.222.100:8765` (mini tailnet IP).
- **Auth:** `Authorization: Bearer <token>`; token at `~/.hermes/talaria_shim_token`
  on the mini (0600). **Do not commit the token.** App stores it in Keychain;
  add a Settings field to paste it once.

### Routes
| Method | Path | Notes |
|---|---|---|
| GET | `/healthz` | No auth. `{ok, service}`. |
| GET | `/models?refresh=0\|1` | Payload below + `compiled_at` (ISO8601), `ttl_seconds` (3600), `refreshed`. `refresh=1` busts the 1h per-provider disk cache → **slow, ~20–60s** (it re-hits every provider's live `/v1/models`). This is the "Refresh models" button. |
| POST | `/models/default` | Body `{provider, model, confirm_expensive?}`. Sets persistent main default (new-session scope; writes `~/.hermes/config.yaml`). Returns `{ok:true, scope:"main", provider, model, base_url, gateway_tools, stale_aux}` **or** `{ok:false, confirm_required:true, confirm_message, provider, model}` (expensive-model guard — re-POST with `confirm_expensive:true`) **or** `{ok:false, error}` with a 4xx/5xx. |

### `GET /models` payload shape
```jsonc
{
  "providers": [
    {
      "slug": "nous", "name": "Nous Portal",
      "is_current": false, "is_user_defined": false,
      "models": ["anthropic/claude-opus-4.8", "openai/gpt-5.5", ...],
      "total_models": 25, "source": "...", "authenticated": true,
      "pricing": {...}, "free_tier": ..., "unavailable_models": [...], "capabilities": {...}
    }
    // ... 36 providers total; ~28 have authenticated:false (skeleton rows)
  ],
  "model": "kimi-k2.7-code",        // current persistent default
  "provider": "kimi-for-coding",
  "compiled_at": "2026-06-23T03:39:43Z", "ttl_seconds": 3600, "refreshed": false
}
```
- `models[]` are **bare ids**: nous ids are **slashed** (`anthropic/claude-opus-4.8`);
  kimi ids are **bare** (`kimi-k2.7-code`). Both forms are valid — see §4.
- 8 authenticated providers: **nous(25), anthropic(10), nvidia(124), copilot(9),
  deepseek(4), zai(10), kimi-coding(8), minimax-oauth(3)**. Render authenticated
  first; either hide `authenticated:false` rows or show them as "needs setup".
- Offline/dev: render against `tools/models-shim/model_options.sample.json`.

---

## 4. Hermes facts you MUST respect

- **The gateway (`:8642`, what the app chats against) exposes no real model list** —
  only a `hermes-agent` pseudo-model on `/v1/models`. Never source the list there;
  use the shim.
- **Current-session switch** = send a chat message `/model <id>` to
  `POST /api/sessions/{id}/chat` (gateway). It's a **per-session pinned override,
  effective next turn**. A **NEW session reverts to the config default.** (Already
  wired — see `ChatStore.detectModelSwitch`.)
- **Persistent default (applies to NEW sessions)** = shim `POST /models/default`.
  Does not affect a running session.
- Therefore Owen's "applies to current and/or next session" =
  **on tap, do BOTH**: `/model <id>` (current) + `POST /models/default` (next).

---

## 5. Agenda (prioritized)

### T1 — Wire Settings → MODELS to the shim  ⭐ primary
1. **Shim client** (new `Talaria/Services/Live/ModelsShimClient.swift`): `GET /models`
   (cache payload + `compiled_at`), `POST /models/default`. Config = base URL + bearer
   token. Default URL `http://100.79.222.100:8765`. Token from Keychain.
2. **DTOs** (Codable, snake_case CodingKeys): `ModelOptionsPayload {providers, model,
   provider, compiledAt, ttlSeconds, refreshed}`, `ProviderRow {slug, name, isCurrent,
   models:[String], totalModels, authenticated, pricing?, freeTier?, capabilities?}`.
3. **UI** (reuse `Core/HUD/` primitives + `Core/Design.swift` tokens; match design
   screens 03/04 — see T3): providers (authenticated first) → models grouped; check
   on the row whose id == top-level `model` (and provider == `provider`); "compiled
   N min ago" from `compiledAt`; **Refresh models** button → `?refresh=1` with an
   async spinner + disabled state (warn 20–60s).
4. **Tap = dual write:** (a) current session via the existing ChatStore `/model` path
   (`selectModel`/`switchModel`), (b) shim `POST /models/default`. On
   `confirm_required`, show a confirm dialog then re-POST with `confirm_expensive:true`.
5. **Settings entry:** add fields (under UPLINK or MODELS) for shim URL + token paste.
- **Acceptance:** build green; screen lists real providers/models from the mini;
  current model checked; refresh updates `compiled_at`; tapping a model both
  hot-swaps the active chat (verify the `/model` echo shows the full id) and persists
  the default (re-GET `/models` shows new top-level `model`).

### T2 — Fix the two selector bugs (do alongside T1)
- **Regex:** `Talaria/Stores/ChatStore.swift` `detectModelSwitch` (~L649–660). The
  capture classes `[A-Za-z0-9._-]+` (L652, L653, and any sibling branches) drop `/`,
  so `anthropic/claude-opus-4.8` is captured as just `anthropic`. Add `/` →
  `[A-Za-z0-9._/-]+` (keep `-` last). Fix **every** alternation branch.
- **Backwards copy:** `Talaria/Features/Chat/Model/ModelSelector.swift` L40 (comment),
  L141 `"APPLIES ON NEXT SESSION"`, L143–150 "Start New Session" button; and
  `Talaria/Features/Chat/ChatScreen.swift` L150–151 (comment). Current copy is
  **inverted**: `/model` applies to the CURRENT session (next turn); the persistent
  default is what governs NEW sessions. Reframe to match the T1 dual-write behavior.
- **Acceptance:** switching to a slashed id shows the full id (not "anthropic") in the
  active-model display; copy matches actual behavior.

### T3 — Settings screens build (Claude Design → SwiftUI)
- **Prereq:** place the Claude Design 8-screen `Settings.dc.html` at `design/Settings.dc.html`
  (it's the `TalariaSettings.zip` deliverable — currently OUTSIDE the repo; ask Owen /
  copy it in). Screens: 01 SYSTEM, 02 UPLINK, 03 MODELS, 04 MODELS, 05 VOICE,
  06 APPEARANCE—HUD, 07 SESSIONS, 08 DIAGNOSTICS.
- Rework `Talaria/Features/Settings/SettingsScreen.swift` into an index → drill-down
  matching the design, using HUD tokens. Build the **6 non-MODELS** screens here;
  MODELS (03/04) is T1.
- **Acceptance:** Settings is a navigable index → drill-down matching the design; builds.

### T4 — Architecture reconciliation (settle early — affects T1 correctness)
- The shim runs on the **mini** and reflects the **mini's** Hermes config
  (default `kimi-k2.7-code`, 8 providers). If the app's chat gateway is a *different*
  host (prior notes show OJAMD `100.110.102.59:8642`), the picker list won't match the
  chat backend. **Resolve:** point the app's gateway at the mini for dev (ties to the
  parked "run `:8642` locally on the mini" dev-loop idea), OR run the shim on OJAMD too.
- **Validate id round-trip** across naming: confirm what `provider` string the picker
  sends per row. The no-op set test used `provider:"kimi-for-coding"` + `model:"kimi-k2.7-code"`
  and round-tripped OK, but the dashboard **slug** is `kimi-coding` (and `minimax-oauth`
  vs `minimax`). Check `_normalize_main_model_assignment` in
  `~/.hermes/hermes-agent/hermes_cli/web_server.py` to confirm slug→config-provider
  mapping, so the POST body uses the right `provider`.

### T5 — Repo hygiene
- Once T1/T2 land and the build is green, merge `feat/phase-b-wiring` → `main`. Branch
  carries: model selector, sessions drawer, connectivity-banner fix, model picker, shim.
- Sanity: confirm the shim returns after a reboot / Tailscale restart (KeepAlive +
  bind-retry should handle it):
  `curl -s -H "Authorization: Bearer $(cat ~/.hermes/talaria_shim_token)" http://100.79.222.100:8765/healthz`

---

## 6. Key files
- Picker UI: `Talaria/Features/Chat/Model/ModelSelector.swift` (173 lines)
- Chat host + selector seams: `Talaria/Features/Chat/ChatScreen.swift`
- Switch detection + store: `Talaria/Stores/ChatStore.swift` (`detectModelSwitch` ~L649)
- Gateway client: `Talaria/Services/Live/SessionsHermesClient.swift`
- Protocol + resilient wrapper: `Talaria/Services/Protocols/HermesClientProtocol.swift`,
  `Talaria/Services/Support/ResilientHermesClient.swift`
- Settings: `Talaria/Features/Settings/` (`SettingsScreen.swift`, `SettingsSectionView.swift`,
  `ConnectHermesHostScreen.swift`)
- HUD tokens/primitives: `Talaria/Core/Design.swift`, `Talaria/Core/HUD/`
  (`HUDComponents.swift`, `HUDEffects.swift`, `ReactorOrb.swift`)
- Shim (backend): `tools/models-shim/` + fixture `model_options.sample.json`

## 7. Verify the shim quickly
```sh
TOKEN=$(cat ~/.hermes/talaria_shim_token)
curl -s http://100.79.222.100:8765/healthz
curl -s -H "Authorization: Bearer $TOKEN" http://100.79.222.100:8765/models | python3 -m json.tool | head
# launchd status:
launchctl print gui/$(id -u)/com.aethyrion.talaria.modelsshim | grep -E "state|pid"
```

## 8. Gotchas
- `xcodegen generate` after any new file / `project.yml` change; never touch `.xcodeproj`.
- Add new Swift files to the right `project.yml` source group or they won't compile in.
- Refresh (`?refresh=1`) is genuinely slow — always async + spinner, never block UI.
- Keep the shim token out of git. Bind stays tailnet-only.
- A new chat session reverts to the config default — so persisting via `/models/default`
  is what makes a choice "stick" for future chats; `/model` only pins the live one.
