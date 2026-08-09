# Public claim inventory — 2026-08-09

**Item:** #140 (bar 140-B's evidence) · **Written:** 2026-08-09 · **Read at HEAD** `bfbd154`

Every capability sentence on the five public surfaces, with `file:line`, one of three
marks, and a citation. **This is the artifact that makes the next sweep impossible to
half-finish** — the failure #140 exists because of was never bad writing; it was that no
sweep began by listing the surfaces it owed.

## How to read the marks

| mark | means |
|---|---|
| **VERIFIED** | true at HEAD, with a `file:line` in source or a tracker item that proves it. **No sentence carries this mark without a citation.** |
| **HEDGED** | the capability is real but the sentence overstates it, names the wrong mechanism, or rests on something not yet proven. Copy must soften to what is proven. |
| **REMOVED** | the sentence asserts something the app does not do. It comes out. |

> ⚠️ **HEDGED and REMOVED are marks, not edits.** `docs/` is a live public website and
> `README.md`/`SECURITY.md` are the repo's public face. Every proposed replacement line is
> staged in `handoffs/DRAFT-140-COPY.md` (gitignored) and **awaits Owen's read of the exact
> text.** Nothing marked here has been written to a public file by this lane.

**Scope:** capability and factual claims. Navigation labels, CSS, the Nous Research
non-affiliation disclaimer, and the MIT licence line are excluded as non-claims.

## Headline

Counted mechanically from the tables below, not by hand
(`python3 scratchpad/count.py`, one row = one inventory entry; a few rows group a
contiguous range such as README's repository-layout block).

| | README.md | SECURITY.md | index.html | setup.html | screens.html | **total** |
|---|---|---|---|---|---|---|
| **VERIFIED** | 52 | 21 | 51 | 23 | 25 | **172** |
| **HEDGED** | 5 | 1 | 3 | 1 | 3 | **13** |
| **REMOVED** | 1 | 0 | 0 | 0 | 0 | **1** |
| *Owen-owed absence* | 0 | 1 | 0 | 1 | 0 | **2** |
| **rows** | **58** | **23** | **54** | **25** | **28** | **188** |

**Zero rows left unmarked. Zero rows marked VERIFIED without a citation.**

The two "Owen-owed absence" rows are not claims — they record the **missing**
privacy-policy link, which is #166a's hard stop condition and is absent from every
surface. They are listed so the gap is inventoried rather than invisible.

**14 rows are not VERIFIED. All 14 have staged replacement copy in
`handoffs/DRAFT-140-COPY.md`.**

**Owen-owed, on every surface: there is no privacy-policy link anywhere.**
`grep -rniE 'privacy.?polic' README.md SECURITY.md docs/*.html` returns nothing. It is
#166a's hard stop condition. **No URL is invented here.**

---

## 1. `README.md` — 52 claims (46 V / 5 H / 1 R)

| line | claim (abbrev.) | mark | citation |
|---|---|---|---|
| 6 | "fully on-device chat brain (Apple's FoundationModels)" | VERIFIED | `Talaria/Services/Chat/LocalChatBackend.swift`; CLAUDE.md §Measurement discipline (#216) |
| 6 | on-device streaming chat | VERIFIED | same |
| 6 | "device tool belt (calendar, reminders, contacts, weather, health, alarms — every action confirmed in-app)" | VERIFIED | `project.yml:165-175` purpose strings; `:175` AlarmKit (#16) |
| 6 | "zero host setup and no data leaving the phone" | VERIFIED | #136 (closed, device-verified 2026-07-20 under a relay+shim black-hole) |
| 8 | pairing adds full agent, desktop roster, server sessions, sensor pipeline via a relay sidecar | VERIFIED | `relay/`; README:62-73 architecture |
| 10 | "targeting iOS 27, Swift 6.2 / strict concurrency"; iOS 26 line frozen | VERIFIED | `project.yml`; CLAUDE.md §Build/tooling |
| 22 | streaming chat: reasoning/answer channels separated, background continuation, reconciliation | VERIFIED | CLAUDE.md §SSE taxonomy (verified Phase 0) — reasoning is a separate channel |
| 23 | on-device chat: FoundationModels, no host; PCC tier shows only when entitlement + availability pass | VERIFIED | memory `ios27-beta4-fm-sdk-surfaces` (availability ≠ generability; the check is real) |
| 24 | tool calls & agent files working | VERIFIED | CLAUDE.md §Agent-generated files (#21) |
| 25 | inbox/directives & daily briefing, approve-or-dismiss in place | VERIFIED | relay directives channel; README:70-72 |
| 26 | sensor pipeline "deliberate opt-in (off by default) with per-sensor grants"; resume-from-background flaky | VERIFIED | #137 |
| 27 | roster from the gateway's API; pick = per-turn model lock, immediate; shim retired | VERIFIED | `ModelsSettingsScreen.swift:84`; `SessionsHermesClient.swift:1952,1964`; #223 Lane 5 |
| 28 | widgets & Live Activities; alarm LA; **lock-screen controls** | VERIFIED | #254 (`OPEN_ITEMS.md:8198`) — downgraded to WATCH 2026-08-05, controls confirmed working repeatedly on build 2034. **NOT #58, whose header is stale — see §6.** |
| 29 | share extension: URLs, images, files, text "into Hermes from any app" | **HEDGED** | Extension is real (`project.yml:453-455`), but "into Hermes" is false for the hostless default user. #255 de-branding |
| 30 | notifications "Removed by design — posts none, registers for no push" | VERIFIED | #238; `aps-environment` absent from `project.yml` **and** all three `.entitlements` (re-verified 2026-08-09) |
| 31 | voice mode: realtime speech-to-speech + on-device fallback; echo tuning in progress | VERIFIED | `VoiceEngineRouter.swift:62` |
| 32 | CarPlay parked — scene + voice manager built, disabled pending Apple's grant | VERIFIED | `project.yml:61` (entitlement commented out); `:364-370` (scene manifest present) |
| 34 | "There is no TestFlight or App Store distribution — you build and sign it yourself" | VERIFIED | true at HEAD. **Falsified on submission day** — recorded in `LAUNCH_PASS-2026-07-20.md` §P-4 Definition of Ready (#8/#166) |
| 36 | "pairing is optional. On-device chat works out of the box." | VERIFIED | #136 |
| 42 | on-device chat behind the same client seam; condensation instead of errors | VERIFIED | `LocalChatBackend.swift`; CLAUDE.md #216 |
| 43 | streaming via Sessions API (SSE): markdown, code blocks, inline images, agent file downloads | VERIFIED | `CLEAN_CHAT_PATH.md`; #21 |
| 44 | voice "falls back to an on-device engine **when the relay is unpaired or unreachable**" | **HEDGED** | **Mechanism falsified by #221.** `VoiceEngineRouter.swift:62,121,189,233` — `realtimeIsPermitted(for:)` gates on the BRAIN and is consulted *before* pairing. Reachability is secondary |
| 45 | inbox/directives; verdict lands back on the host | VERIFIED | relay |
| 46 | "location, **11 HealthKit metrics**, and CoreMotion activity" | VERIFIED | `LiveHealthService.swift` — 10 `quantityType(forIdentifier:)` + `HKCategoryType(.sleepAnalysis)` at `:523` = 11 exactly |
| 47 | "the pick rides every turn as a model lock **and pins the live session through the gateway itself**" | **REMOVED** | **There is no session pin.** `ModelsSettingsScreen.swift:84` — *"no shim POST, no session pin, nothing to await."* Zero POSTs to `/api/sessions/{id}/model` in Swift. **This site survived commit `9b6008c`, which corrected the same claim at `:27`, `:75`, `index.html:182` and `screens.html:150` — see §5.** |
| 48 | agent files as tappable share bubbles | VERIFIED | #21 Tier 1 |
| 49 | widgets & LA; "lock-screen toggle controls" | VERIFIED | #254 |
| 50 | share extension: URL, **up to four images**, a file, or plain text | VERIFIED | `project.yml:454` `NSExtensionActivationSupportsImageWithMaxCount: 4`; `:453` URL=1; `:455` file=1 |
| 51 | "Siri & App Intents — **ask Hermes** or start a voice session hands-free; conversations index into Spotlight" | **HEDGED** | Intents exist (`Talaria/Intents/AskHermesIntent.swift`, `StartVoiceSessionIntent.swift`) and Spotlight is real (`Talaria/Services/Live/SpotlightIndexingService.swift`). Two gaps: the spoken copy says "Hermes" (#255), and bar **56-U-H (device) is UNMET** (`OPEN_ITEMS.md:859`) |
| 52 | device tool belt incl. WeatherKit + AlarmKit; every action confirmed in-app | VERIFIED | `project.yml:52` weatherkit; `:175` AlarmKit; #28/#16 |
| 53 | multi-host profiles, each with its own key in the Keychain | VERIFIED | `AppContainer.swift:347` `KeychainSecureStore(serviceName: "org.aethyrion.talaria.session")` |
| 54 | full settings suite; theme channel browser; "30+ alternate app icons"; optional Face ID lock | VERIFIED | `AppIconStore.swift:69` `setAlternateIconName`; `Talaria/Core/AppLock/AppLockController.swift`; 30 `ThemePaletteDefinition(` in `Shared/ThemePaletteCore.swift` |
| 62-73 | architecture diagram: **two** services (`:8642` chat, `:8000` relay) | VERIFIED | CLAUDE.md §Architecture. Agrees with `SECURITY.md:15` — bar 140-C's specific failure condition is clear |
| 75 | chat direct to Sessions API, never transits relay; per-turn lock on each request; shim retired parenthetical | VERIFIED | corrected by `9b6008c`; CLAUDE.md §Architecture |
| 83 | requirements: iOS 27 beta, Xcode 27 beta, Apple Developer account | VERIFIED | CLAUDE.md §Build/tooling |
| 84 | host OS macOS or Windows, Linux untested | VERIFIED | CLAUDE.md §OJAMD + Mac Mini |
| 85 | hermes-agent installed and configured | VERIFIED | upstream dependency |
| 86 | Tailscale recommended | VERIFIED | CLAUDE.md §Architecture |
| 87 | relay & connector: Python 3.11+, uvicorn | VERIFIED | `relay/pyproject.toml`, `connector/pyproject.toml` |
| 89 | `DEVELOPER_DIR` note; "Cannot find in scope" ⇒ stable SDK | VERIFIED | CLAUDE.md §Build/tooling |
| 105 | `hermes gateway run` starts Sessions API on `:8642`; bind `0.0.0.0` | VERIFIED | CLAUDE.md §OJAMD services |
| 107 | "Do not run `hermes gateway install` on Windows" | VERIFIED | CLAUDE.md §OJAMD services |
| 113-114 | relay deploy: `pip install -e .`, uvicorn on `:8000` | VERIFIED | `relay/` |
| 121 | `INTERNAL_API_KEY` — change from default, relay warns | VERIFIED | `SECURITY.md:54` |
| 122 | `PUBLIC_BASE_URL` | VERIFIED | relay config |
| 123 | `AGENT_FILES_DIR` enables in-chat downloads | VERIFIED | #21 Tier 2 |
| 124 | `GATEWAY_API_KEY` = your `API_SERVER_KEY` | VERIFIED | CLAUDE.md §Auth |
| 125 | `APNS_*` "Legacy remote push (current app builds don't register for push — safe to omit)" | VERIFIED | #238; matches `SECURITY.md:36-50`'s unused-surface framing |
| 131 | connector owns the durable relay connection, registers `hermes_mobile` MCP, prints pairing codes | VERIFIED | `connector/README.md`; `connector/pyproject.toml:19` (`hermes-mobile` CLI still exists — re-checked by `9b6008c`) |
| 147-151 | xcodegen; "regenerate whenever Swift files are added or removed" | VERIFIED | CLAUDE.md §Hard-won gotchas |
| 155 | first launch works immediately in on-device mode — no account, no cloud login | VERIFIED | #136 |
| 157-158 | `hermes-mobile pair-phone` prints QR + short-lived 8-char code | VERIFIED | `connector/` |
| 159 | gateway URL + `API_SERVER_KEY` "**`~/.hermes/.env` on macOS**, `%LOCALAPPDATA%\hermes\.env` on Windows" | **HEDGED** | Windows half VERIFIED (CLAUDE.md §Auth pins `C:\Users\Owen\AppData\Local\hermes\.env`). **macOS half UNVERIFIED by this lane** — CLAUDE.md pins only Windows and records that `C:\Users\Owen\.hermes\.env` does *not* exist. Same claim at `setup.html:190` |
| 161 | iCloud Private Relay intercepts HTTP to Tailscale IPs | VERIFIED | CLAUDE.md §Hard-won gotchas |
| 169 | scoped ATS exception → CGNAT `100.64.0.0/10`; TLS on elsewhere; "front with `tailscale serve` (HTTPS + MagicDNS), you can remove even this exception" | **HEDGED** | The *shipped config* is VERIFIED (`project.yml:345-348`). Two problems: (a) the **mechanism is disputed in-repo** — #166b (exception load-bearing, four-arm **sim** experiment) vs #167 (exception inert, bare IPs unpoliced); bar **140-D** decides it and needs a device. (b) the MagicDNS half **invites the trap without naming it** — a MagicDNS name over plain HTTP is blocked under *both* readings |
| 184 | `tools/models-shim/` "Legacy … retired — current app builds are gateway-native" | VERIFIED | #223 Lane 5 |
| 176-199 | repository layout (other rows) | VERIFIED | directory listing at HEAD |
| 205-208 | network notes: both ports reachable, bind `0.0.0.0`, Windows firewall, Private Relay off | VERIFIED | CLAUDE.md §OJAMD services + §Hard-won gotchas |

---

## 2. `SECURITY.md` — 22 claims (21 V / 1 H / 0 R)

**This file was swept 2026-08-09 by `9b6008c` and is now the healthiest of the five.**
Everything the #140 dispatch's §3.1–3.3 flagged is DONE. One residue.

| line | claim | mark | citation |
|---|---|---|---|
| 8 | private vulnerability reporting via GitHub advisories | VERIFIED | repo setting |
| 15 | "**both** host services — Sessions API `:8642` and relay `:8000` — on a Tailscale tailnet… none intended to be exposed to the public internet" | VERIFIED | corrected by `9b6008c`; agrees with `README.md:62-73` (bar 140-C) |
| 17-24 | the dated "Corrected 2026-08-09" note: shim was a third service, retired 2026-08-04, stop it if you run one | VERIFIED | #223 Lane 5 |
| 30 | phone talks directly to `:8642` with Bearer auth; chat does not pass through the relay | VERIFIED | CLAUDE.md §Architecture |
| 34 | relay carries pairing/auth, sensor ingestion, inbox/directives, scheduled runs, agent-file downloads, voice WebRTC bootstrap | VERIFIED | corrected by `9b6008c` — APNs removed from this list |
| 36-50 | **APNs is unused surface**: app has no `aps-environment`, never calls `registerForRemoteNotifications`, never obtains a token; relay still creates an APNs client and persists `apns_token`; "not a known vulnerability… unused credential-accepting surface" | VERIFIED | app side re-verified 2026-08-09 (`aps-environment` absent from `project.yml` + all three `.entitlements`); relay side per `9b6008c` (`relay/app/main.py:230`, `:420`); #238 |
| 52 | Bearer token for iOS clients, connector credential for WebSocket | VERIFIED | relay auth |
| 53 | `CONNECTOR_SETUP_SECRET` gates new connector registration | VERIFIED | relay config |
| 54 | `INTERNAL_API_KEY` gates internal admin endpoints; warns on default | VERIFIED | relay startup |
| 55 | token lifecycle; "persisted (hashed) in the relay's SQLite database and survive restarts" | VERIFIED | CLAUDE.md §Hard-won gotchas — registry survives restarts, verified across 4+ relay restarts (#24f is DEAD) |
| 61 | connector authenticates to relay with a setup-obtained credential | VERIFIED | connector |
| 62 | sensor data in SQLite at `~/.hermes-mobile/state/sensors.db` | VERIFIED | connector |
| 63 | `query_sensor_data` opens a **read-only** SQLite connection | VERIFIED | connector MCP tool |
| 64 | OpenAI API key in `~/.hermes-mobile/secrets.json`, used only for Realtime voice | VERIFIED | explicitly re-checked and left standing by `9b6008c` |
| 68 | service URLs configured during onboarding, persisted locally, not hardcoded | VERIFIED | `AppContainer.swift` |
| 69 | credentials in the iOS Keychain, service `org.aethyrion.talaria.session`, mirrored so pairing survives reinstall | VERIFIED | `AppContainer.swift:347` |
| 70 | "**Read-only** HealthKit access" | VERIFIED | `LiveHealthService.swift:70` — `toShare: []`. **No `healthStore.save` anywhere in `Talaria/` or `Shared/`.** This is also the evidence for dropping `NSHealthUpdateUsageDescription` (166i) |
| 71 | camera/mic just-in-time; frames to OpenAI via WebRTC **only when the selected brain permits**; brain choice is a privacy control | VERIFIED | corrected by `9b6008c`; `VoiceEngineRouter.swift:121` `realtimeIsPermitted(for:)`, wired at `:62`, `:189`, `:233` (#221) |
| 75 | ATS Known Limitation — scoped exception, TLS elsewhere, Tailscale WireGuard encryption, remove-if-HTTPS, **"(Verified 2026-07-22: … the exception is load-bearing, and the CIDR scoping was confirmed with an outside-range negative control.)"** | **HEDGED** | The shipped config is VERIFIED (`project.yml:345-348`). **The parenthetical publishes the #166b side of a live in-repo contradiction as settled fact** — #167 says the exception is inert and bare IPs are unpoliced; #166b's decisive arms ran on **sim**, and #167's own closing note says only device traffic tests ATS. Bar **140-D** decides it. Meanwhile: drop the parenthetical, add the MagicDNS trap (true under both readings) |
| 76 | MCP tool token in URL: short-lived, server-to-server, invalidated at session end | VERIFIED | relay voice bootstrap |
| 77 | sensor data retained 90 days locally on the connector host | VERIFIED | connector retention |
| 81 | security updates apply to latest `main`; no backports | VERIFIED | policy statement |
| — | **MISSING: no privacy-policy link** | **Owen-owed** | #166a hard stop condition. `grep -rniE 'privacy.?polic'` over all five surfaces returns nothing. **Do not invent a URL** |

---

## 3. `docs/index.html` — 47 claims (44 V / 3 H / 0 R)

| line | claim | mark | citation |
|---|---|---|---|
| 7, 9 | meta/og: "complete on-device chat brain, and a client for the Hermes agent you host yourself" | VERIFIED | as README:6 |
| 82 | "WORKING ALPHA · iOS 27 · SWIFT 6" | VERIFIED | `project.yml` |
| 85 | complete chat brain on device — streaming, sessions, read-aloud, tool belt that moves your calendar and sets alarms; "It works in airplane mode." | VERIFIED | #136; `project.yml:175` AlarmKit |
| 86 | paired tier grows roster, server sessions, live sensor feed. "**No cloud.** No relay you don't own." | **HEDGED** | Realtime voice on the `.hermes` brain **does** reach OpenAI (`SECURITY.md:71`; #221). Defensible as "no Talaria-operated cloud", indefensible as read. **Owen's decision** — the same call as #221's open realtime-indicator question |
| 91 | "NO APP STORE · NO TESTFLIGHT · YOU BUILD AND SIGN IT YOURSELF" | VERIFIED | true at HEAD; falsified on submission day — recorded in P-4 Definition of Ready |
| 107 | "Install it and it already works — a host is the upgrade, not the entry fee." | VERIFIED | #136 |
| 117 | SOLO: local backend on FoundationModels, same client seam, condensation instead of errors, "Nothing leaves the phone" | VERIFIED | `LocalChatBackend.swift`; #136 |
| 119 | streaming chat, sessions drawer, persistence | VERIFIED | `LocalChatBackend.swift` |
| 120 | read-aloud; sessions history survives relaunch | VERIFIED | #110; local session store |
| 121 | device tool belt in the SOLO column | VERIFIED | `project.yml:150-175`; the belt is device-local |
| 122 | "Siri and App Intents; conversations index into Spotlight" — **in the ZERO-HOST-SETUP column** | **HEDGED** | **Source supports the hostless routing, better than the dispatch assumed:** `AskHermesIntent.swift:81-83` — `needsReachabilityPreflight` returns *false* when no gateway key is set, so a hostless turn skips the host probe entirely and goes to `chatStore.sendMessage` → `ChatBackendRouter`. The doc comment at `:74-80` names this the "self-contained-first posture… the DEFAULT user" (bar 56-U-G). **But** bar **56-U-H is Owen's device bar and is UNMET** (`OPEN_ITEMS.md:859`), and the spoken copy is "What should I ask **Hermes**?" (`:41`) / "**Hermes** is still working on it" (`:70`) — nonsense to a user with no Hermes (#255). Hedge or device-check; it may not stay as-is |
| 123 | "Works in airplane mode — nothing leaves the phone" | VERIFIED | #136 |
| 133 | PAIRED: point at a Hermes host over Tailscale; chat straight to Sessions API; relay carries the rest; multiple profiles | VERIFIED | CLAUDE.md §Architecture |
| 135 | full desktop provider roster, live from the gateway | VERIFIED | `/api/model/options` (CLAUDE.md route table) |
| 136 | server sessions synced with the agent you already run | VERIFIED | Sessions API |
| 137 | sensor pipeline: location, 11 HealthKit metrics, CoreMotion | VERIFIED | `LiveHealthService.swift` (10 + sleepAnalysis) |
| 138 | inbox and directives | VERIFIED | relay |
| 139 | realtime WebRTC voice + agent-file downloads in chat | VERIFIED | #21; `VoiceEngineRouter.swift` |
| 140 | multiple host profiles, each with its own Keychain key | VERIFIED | `AppContainer.swift:347` |
| 162 | status: streaming chat — channels separated, background continuation, reconciliation after stream loss | VERIFIED | CLAUDE.md §SSE taxonomy |
| 167 | on-device chat — FoundationModels, no host; PCC tier gated on the real check | VERIFIED | memory `ios27-beta4-fm-sdk-surfaces` |
| 172 | tool calls & agent files — generated files as tappable share bubbles | VERIFIED | #21 |
| 177 | inbox/directives — approvals, reminders, daily briefing; verdict goes back to host | VERIFIED | relay |
| 182 | model picking — roster from the gateway's own API; per-turn model lock; immediate | VERIFIED | corrected by `9b6008c`; `ModelsSettingsScreen.swift:84` |
| 187 | widgets & LA — status/health/briefing widgets; alarm LA; **lock-screen controls** | VERIFIED | #254 |
| 192 | share extension — URLs, images, files, text | VERIFIED | `project.yml:453-455` |
| 197 | sensor pipeline — deliberate opt-in, off by default, per-sensor grants; resume flaky | VERIFIED | #137 |
| 202 | voice mode — realtime speech-to-speech plus on-device fallback; echo tuning in progress | VERIFIED | `VoiceEngineRouter.swift:62`. **Note: this row claims no trigger, so it is clean where `:240` is not** |
| 207 | notifications — REMOVED BY DESIGN; posts none, registers for no push | VERIFIED | #238; entitlements re-verified |
| 212 | CarPlay — PARKED; scene and voice manager built but disabled | VERIFIED | `project.yml:61`, `:364-370` |
| 215 | "no TestFlight and no App Store build. You clone it, generate the project, and sign it" | VERIFIED | true at HEAD; see `:91` |
| 224 | "Every action the agent takes on your device is confirmed in-app before it fires. Nothing runs behind your back." | VERIFIED | #16/#28 confirmation flow |
| 230 | cap 01 on-device brain | VERIFIED | `LocalChatBackend.swift` |
| 235 | cap 02 streaming chat — SSE, markdown, code blocks, inline images, agent file downloads | VERIFIED | `CLEAN_CHAT_PATH.md` |
| 240 | cap 03 voice mode — "…falling back to an on-device engine **when the relay is unreachable**" | **HEDGED** | Same #221 mechanism error as `README.md:44`. The engine is chosen by the **brain selection first** — `VoiceEngineRouter.swift:121` |
| 245 | cap 04 device tool belt — calendar, reminders, contacts, WeatherKit, health, media + AlarmKit | VERIFIED | `project.yml:52`, `:165-175` |
| 250 | cap 05 sensor pipeline — 11 HealthKit metrics; "you own all the data" | VERIFIED | `LiveHealthService.swift`; `SECURITY.md:62` |
| 255 | cap 06 inbox & directives | VERIFIED | relay |
| 260 | cap 07 widgets & LA + lock-screen toggle controls | VERIFIED | #254 |
| 265 | cap 08 share extension — URL, up to four images, a file, or plain text | VERIFIED | `project.yml:453-455` |
| 270 | cap 09 multi-host profiles; switching is one tap | VERIFIED | `AppContainer.swift:347` |
| 283 | chat connects directly, never transits the relay; both services restart independently | VERIFIED | CLAUDE.md §Architecture |
| 301 | "SSE streaming and sync, the model roster, per-turn model lock, bearer auth with your API_SERVER_KEY" | VERIFIED | `SessionsHermesClient.swift:1952,1964` |
| 318 | relay: pairing/auth, sensor ingestion, directives, scheduled runs, agent-file downloads, voice WebRTC bootstrap | VERIFIED | matches `SECURITY.md:34` |
| 330-332 | "RETIRED · models shim · :8765 — current builds never call it. Model picking is native to the gateway now." | VERIFIED | #223 Lane 5 |
| 340 | Tailscale reaches both services without public exposure | VERIFIED | CLAUDE.md §Architecture |
| 344 | bearer token on the gateway; per-profile key in the Keychain, never in a config file | VERIFIED | `AppContainer.swift:347` |
| 348 | "If the relay is down, chat keeps working. If both are down, the on-device brain takes over." | VERIFIED | #136 (device-verified under a relay+shim black-hole) |
| 359, 361 | "Thirty channels"; each is a full art direction (gradient, texture, grid, orb, glow scale, three accent slots) | VERIFIED | **30** `ThemePaletteDefinition(` in `Shared/ThemePaletteCore.swift`; CLAUDE.md §Design system |
| 417 | "STYLISED PREVIEW · REAL PALETTE VALUES" | VERIFIED | the `THEMES` array at `:511-541` mirrors the app's palette values |
| 434 | "30+ alternate app icons, and an optional Face ID lock" | VERIFIED | `AppIconStore.swift:69`; `AppLockController.swift` (#124) |
| 446, 447 | "Thirteen screens, no filler"; settings suite named | VERIFIED | 13 entries in `screens.html`'s `SHOTS` array (`:128-166`) |
| 479 | "On-device mode needs nothing but the build. Pairing a host adds four steps." | VERIFIED | `setup.html` steps 1-4 are all HOST · OPTIONAL |
| 494 | "Talaria-27 is the active line, targeting iOS 27 · the iOS 26 line is frozen" | VERIFIED | README:10 |

---

## 4. `docs/setup.html` — 21 claims (20 V / 1 H / 0 R)

| line | claim | mark | citation |
|---|---|---|---|
| 7 | meta: build for your own iPhone, optionally pair a self-hosted Hermes | VERIFIED | README:6-8 |
| 53 | "Build the app and it works on its own. Everything before step five exists only to give the phone a host — do it later, or never." | VERIFIED | #136 |
| 57-58 | shortest path: clone → `xcodegen generate` → open → set signing team → run | VERIFIED | CLAUDE.md §Build/tooling |
| 69 | iOS 27 beta, Xcode 27 beta with the iOS 27 SDK, Apple Developer account | VERIFIED | CLAUDE.md §Build/tooling (release Xcode cannot build iOS 27) |
| 73 | macOS or Windows; Linux untested; "only needed if you're pairing" | VERIFIED | README:84 |
| 77 | hermes-agent installed and configured, working profile | VERIFIED | upstream |
| 81 | Tailscale recommended, or any private network | VERIFIED | CLAUDE.md §Architecture |
| 85 | Python 3.11+ and uvicorn on the host | VERIFIED | `relay/pyproject.toml` |
| 101 | step 1 — install Hermes, confirm `hermes` in PATH | VERIFIED | upstream |
| 112 | step 2 — `hermes gateway run` starts `:8642`, "the connection the phone uses for chat, sessions and the model roster"; NSSM/launchd; bind `0.0.0.0` | VERIFIED | CLAUDE.md §OJAMD services |
| 115 | "Do not run `hermes gateway install` on Windows" | VERIFIED | CLAUDE.md §OJAMD services |
| 127 | step 3 — relay carries everything phone-facing except chat (list matches `SECURITY.md:34`, **no APNs**) | VERIFIED | `SECURITY.md:34` |
| 128-130 | relay deploy commands | VERIFIED | `relay/` |
| 134 | `INTERNAL_API_KEY` | VERIFIED | `SECURITY.md:54` |
| 138 | `PUBLIC_BASE_URL` | VERIFIED | relay config |
| 142 | `AGENT_FILES_DIR` | VERIFIED | #21 Tier 2 |
| 146 | `GATEWAY_API_KEY` | VERIFIED | CLAUDE.md §Auth |
| 159 | step 4 — connector owns the relay connection, registers `hermes_mobile` MCP, prints pairing codes | VERIFIED | `connector/README.md` |
| 174 | step 5 — sources listed explicitly, regenerate on add/remove; Xcode 27 beta; set signing team | VERIFIED | CLAUDE.md §Hard-won gotchas |
| 178 | `DEVELOPER_DIR` heads-up | VERIFIED | CLAUDE.md §Build/tooling |
| 190 | step 6 — on-device works immediately; `hermes-mobile pair-phone`; "**`~/.hermes/.env` on macOS**; `%LOCALAPPDATA%\hermes\.env` on Windows" | **HEDGED** | Windows half VERIFIED (CLAUDE.md §Auth). **macOS half UNVERIFIED by this lane.** Same claim as `README.md:159` |
| 208 | iCloud Private Relay — "iOS refuses to route to them at all" | VERIFIED | CLAUDE.md §Hard-won gotchas |
| 213 | port 8642 fight — a `hermes gateway install` scheduled task competes | VERIFIED | CLAUDE.md §OJAMD services |
| 218 | wrong SDK — set `DEVELOPER_DIR` to the beta toolchain | VERIFIED | CLAUDE.md §Build/tooling |
| — | **MISSING: no privacy-policy link** | **Owen-owed** | #166a |

---

## 5. `docs/screens.html` — 29 claims (26 V / 3 H / 0 R)

**Two of the three hedges here are sites the 2026-08-09 amendment banner did not list.**

| line | claim | mark | citation |
|---|---|---|---|
| 58-59 | "SCREEN GALLERY · 13 SCREENS / Every screen, at full size" | VERIFIED | 13 `SHOTS` entries, `:128-166` |
| 129 | HANDSHAKE — "the only screen you can skip entirely… the app is fully usable if you never come here at all" | VERIFIED | #136 |
| 130 | 8-char code from `hermes-mobile pair-phone`; relay URL by hand; device-bound key in the Keychain | VERIFIED | `connector/`; `AppContainer.swift:347` |
| 132 | CHAT — reasoning/answer separate; live tool card with per-step duration; destructive actions wait for confirmation | VERIFIED | CLAUDE.md §SSE taxonomy; #16/#28 |
| 133 | live context meter; model chip switches roster mid-session without restart; calendar diffs/file bubbles/inline images; background continuation reconciles | VERIFIED | #21; #223 Lane 5 |
| 135 | VOICE — "**WebRTC to the relay when it's reachable, an on-device engine when it isn't.**" | **HEDGED** | **Same #221 mechanism error as `README.md:44` and `index.html:240`, and this site is on neither the dispatch's §3.6 list nor the amendment banner's.** `VoiceEngineRouter.swift:121` gates on the brain first |
| 136 | notes — "server-side voice through the relay's WebRTC bootstrap"; "**on-device fallback engine when unpaired or offline**"; echo tuning in progress | **HEDGED** | Same. The bootstrap and the tuning caveat are VERIFIED; the *trigger* clause is the #221 error |
| 138 | DIRECTIVES — to-dos, approvals, reminders, daily briefing in an in-app inbox; verdict lands back on the host | VERIFIED | relay |
| 139 | scheduled runs; "**No push notifications: the app registers for none, by design**"; Live Activities and widgets carry state to the lock screen | VERIFIED | #238; #254 |
| 141 | SETTINGS — the ten screens named; "no config file editing to get a working setup" | VERIFIED | `Talaria/Features/Settings/` |
| 142 | multi-host profiles with per-profile Keychain keys; optional Face ID lock; 30+ alternate icons | VERIFIED | `AppContainer.swift:347`; `AppLockController.swift`; `AppIconStore.swift:69` |
| 144 | SYSTEM — build, storage, permissions, on-device brain availability | VERIFIED | `Talaria/Features/Settings/` |
| 145 | FoundationModels availability + PCC tier check; permissions surfaced with what each unlocks | VERIFIED | memory `ios27-beta4-fm-sdk-surfaces` |
| 147 | UPLINK — gateway URL + `API_SERVER_KEY`; "chat talks straight to this — nothing in between" | VERIFIED | CLAUDE.md §Architecture |
| 148 | per-profile Keychain storage; relay URL kept separate because the services fail independently | VERIFIED | CLAUDE.md §What this is (chat and sensors are independent paths) |
| 150 | MODELS — roster from the gateway's own API; "a pick applies as a per-turn model lock and takes effect immediately" | VERIFIED | corrected by `9b6008c`; `ModelsSettingsScreen.swift:84` |
| 151 | "No third service — the old models shim on `:8765` is retired"; "switching mid-session doesn't restart anything" | VERIFIED | #223 Lane 5 |
| 153 | MODEL·ACTIVE — "the transition state — **what's pinned**, what's about to take over, and what the next turn will actually use" | **HEDGED** | Residue of the session-pin vocabulary that `9b6008c` removed from four other sites. Nothing is "pinned" — `ModelsSettingsScreen.swift:84`. Harm is low (it reads as UI description, not mechanism) but the word is the one we retired |
| 154 | "per-turn lock is explicit, so you always know which model answered" | VERIFIED | `SessionsHermesClient.swift:1952,1964` |
| 156 | VOICE settings — engine choice, server-side voice selection, half-duplex behaviour | VERIFIED | #130 |
| 157 | "realtime relay engine or the on-device fallback"; mic behaviour, mute and barge-in thresholds | VERIFIED | `VoiceEngineRouter.swift`. **No trigger claimed, so this note is clean where `:135`/`:136` are not** |
| 159 | APPEARANCE — full-bleed channel browser, live app as the preview; "30 channels, three accent slots each, plus 30+ alternate app icons" | VERIFIED | 30 `ThemePaletteDefinition(`; CLAUDE.md §Design system |
| 160 | each channel = gradient, texture, grid, orb style, glow scale; accent slot picks the lead hue; light channels named (Paper Tape, Winter Frost, Sticker-Bomb Toybox, Sunday Funnies) | VERIFIED | `ThemePaletteCatalog`; the four named `light:true` entries at `index.html:514,515,538,540` |
| 162 | SESSIONS — local and server sessions in one list, **per-session cost**, prune | VERIFIED | `SessionsSettingsScreen.swift:232,367-373` (#122) |
| 163 | on-device sessions persist locally and survive relaunch; server sessions sync | VERIFIED | local session store; Sessions API |
| 165 | DIAGNOSTICS — connection health, port status, session counts, service state, without touching the host terminal | VERIFIED | `Talaria/Features/Settings/` |
| 166 | "tells you which of the two services is down, not just that something is" | VERIFIED | agrees with the two-service architecture |
| 128-166 | 13 screenshots labelled as the app's screens | VERIFIED-with-caveat → treated as VERIFIED here | the "real captures from hardware" claim was removed in the PR #266 bake; the renders are labelled honestly as stylized. **Refresh is P-4's batch and is explicitly out of #140's scope (bar 140-E)** |

---

## 6. Two traps this inventory exists to stop

**6.1 — `#58`'s header would have produced a FALSE correction.** `OPEN_ITEMS.md:870`
still reads *"controls DEAD on device 2026-07-25."* **#254** (`OPEN_ITEMS.md:8198`,
downgraded to WATCH 2026-08-05 on build 2034) records both Control Center buttons
confirmed working, repeatedly. The README/Pages "lock-screen controls" rows at
`README.md:28`, `:49`, `index.html:187`, `:260` and `screens.html:139` are **DEFENSIBLE
and are marked VERIFIED on #254's evidence.** #58's header needs #254 folded in — see the
tracker corrections handed to the orchestrator.

**6.2 — the amendment banner's own list was incomplete.** `9b6008c` corrected the
session-pin claim at four sites and named those four. It missed **`README.md:47`**, where
the same claim survives in different words ("pins the live session through the gateway
itself"), and the vocabulary residue at **`screens.html:153`**. Neither the dispatch body's
§3.5 list nor the banner would have caught them; **re-deriving against HEAD did.** That is
the lane's own lesson landing on itself twice in one night.

---

## 7. What this inventory does not settle

- **Bar 140-D — the ATS mechanism.** `#166b` vs `#167` are mutually exclusive and both
  live in this repo. **Not resolved here; it needs a device.** Two sites (`SECURITY.md:75`,
  `README.md:169`) are HEDGED pending it, and the fallback — publish the observed fact,
  drop the mechanism — is drafted.
- **Bar 56-U-H — the Siri device check.** Source supports the hostless path
  (`AskHermesIntent.swift:81-83`); the device pass is Owen's and is unmet.
- **The macOS `~/.hermes/.env` path** (`README.md:159`, `setup.html:190`) — unverified by
  this lane, HEDGED rather than corrected, because guessing at it is exactly the failure
  mode #140 exists to stop.
- **The `docs/img/` renders** — bar 140-E keeps them out. They are old, not false.
- **The privacy-policy URL** — Owen's, on every surface.
