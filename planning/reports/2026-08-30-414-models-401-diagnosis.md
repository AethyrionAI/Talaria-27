# #414 — `GET /v1/models` 401s against OJAMD: code-only diagnosis

**Lane:** read-only, app-side. No network probes, no builds, no repo mutation.
**Date:** 2026-08-30. **Tree:** `main` @ `e8b96097`.

---

## VERDICT

**Top candidate, HIGH confidence: `AppContainer.probeGatewayVerdict(baseURL: previous.gatewayBaseURL, key: nil)` — the #247-B2 profile-switch verdict's PREVIOUS-host arm. It is a DELIBERATELY UNAUTHENTICATED `GET /v1/models`, fired at the profile you just switched AWAY from, once per switch.** `Talaria/Stores/AppContainer.swift:2318` passes `key: nil`; `:2239` then omits the `Authorization` header entirely; the function's own docstring at `:2229-2232` states the intent in so many words — *"Unauthenticated probes still classify reachability: a live gateway answers 401/403 (`.unkeyed`)"*. **The app has a call site whose documented, intended, SUCCESSFUL outcome is a 401.**

The host side confirms the log line is the one this produces. In `~/.hermes/hermes-agent/gateway/platforms/api_server.py`, the bearer check at `:1954-1966` falls through to `logger.warning("API server rejected invalid API key: %s", self._request_audit_log_suffix(request))` **when the `Authorization` header is ABSENT as well as when it is wrong** — there is no separate "missing key" branch. And `_request_audit_context` (`:1848-1866`) emits exactly `remote` / `method` / `path` / `user_agent`, which is the shape #414 quotes (`100.68.60.11`, `Talaria%2027/3087`). So a headerless probe is indistinguishable in that log from a bad-key request — **which is precisely why this has been undiagnosable from the gateway log alone.**

Timeline fit is strong and independent. #414's two 401s are 18:12:26 and 19:05:58 on 2026-08-26. `OPEN_ITEMS.md:4471-4508` records Owen on build 3087 that same evening at ~18:14 reporting the approval-mode gate **"on BOTH hosts"** (i.e. he was switching profiles to read each one), and later **"Switching to ojamd, I now have the three options!!"**. Every switch AWAY from OJAMD yields exactly one unauthenticated `/v1/models` at OJAMD. Two switches away, two 401s, ~53 minutes apart, no user-visible symptom — the previous-host verdict is only ever *read* when the NEW host is `.unreachable` (`AppContainer.swift:2200-2226`), so on a healthy switch it is discarded silently.

**Secondary finding, and it settles #414's own hedge by measurement rather than inference: Lane B did NOT fix this.** "Lane B's Keychain work" is **#309 Lane B, bar 309-B9** → `Talaria/Services/Support/RelayCredentialHygiene.swift`, squash `373ec733` (2026-08-26 03:39). It purges four DEAD relay slots and **explicitly guarantees `gatewayAPIKey` survives** (`:44-54`, pinned by test). `git show 373ec733` over `AppContainer.swift`, `ServerSettingsScreen.swift`, `UplinkSettingsScreen.swift` returns **zero** changed lines matching `v1/models`, `gatewayAPIKey`, `probeGateway`, `Authorization`, or `hermesAPIKey`. And build 3087 **contains** Lane B (`handoffs/HANDOFF-2026-08-23-SUN-NIGHT-BUILD-LIST.md:969` — "build 3087 staged (the whole batch)", card "#309-B ★"), yet 3087 is the build observed 401ing. **The hedge can be struck: post-Lane-B is measured, not unmeasured.**

**Confidence caveat, stated up front:** candidate #2 below (Server-screen sweep of a keyless profile) produces the *identical* log line and cannot be separated from candidate #1 by the gateway log. It is ranked lower only because it needs a profile that holds a gateway URL **and** no key, which #309 Lane B's commit-on-probe-pass (309-B4) and Disconnect (which clears the URL with the key) both work against. The 10-second eyeball in §5 separates them.

---

## 1. Call-site table — every `/v1/models` request the app can emit

`grep -rn "v1/models"` over the tree finds **five** production emitters (plus test/doc mentions). No widget, extension, or share-target emitter exists.

| # | Call site | Client type | Credential slot | Header when key is empty/absent | When it fires |
|---|---|---|---|---|---|
| A | `AppContainer.probeGatewayVerdict` `Stores/AppContainer.swift:2233-2252`, called at `:2315` (new) and **`:2318` (previous, `key: nil`)** | bare `URLSession.shared`, 5 s | NEW arm: `hermesAPIKey` (the container mirror, freshly written at `:2300`). **PREVIOUS arm: hard-coded `nil`.** | **Omitted** (`:2239` `if let key, !key.isEmpty`) | On **every active-profile switch** after the first in a process (`onActiveProfileChanged` → `handleActiveProfileChanged`, `AppContainer.swift:897`, `:2271`). `lastActivatedProfile` starts nil, so the first activation has no previous arm. |
| B | `ServerSettingsScreen.probeGateway` `Features/Settings/ServerSettingsScreen.swift:690-706`, fed by `probeAllProfiles` `:648-680` | bare `URLSession.shared`, 5 s | **Keychain direct, per profile**: `container.gatewayAPIKey(for:)` → `secureStore.retrieve(BackendProfileScopedKeys.gatewayAPIKey(profile.credentialScopeID))` (`AppContainer.swift:2480-2483`). Not the cache, not the box. | **Omitted** (`:695`) | Once per **Settings → Server appear** (`.task` at `:134`). Sweeps **every** profile concurrently. The sibling `.task(id: activeProfileID)` at `:141` does NOT re-probe (link state + approval mode only). |
| C | `UplinkSettingsScreen.probe` `Features/Settings/UplinkSettingsScreen.swift:437-471`, called at `:426` | injectable `URLSession`, 5 s | `container.hermesAPIKey` — the **active-profile mirror** | **Omitted** (`:453-455`) | Manual **Test Connection** tap only. |
| D | `SessionsHermesClient.connect()` `Services/Live/SessionsHermesClient.swift:251-260` → `getJSON(path:"/v1/models")` `:1291` → `makeRequest` `:1313-1326` | the shared chat-plane `URLSession` (`makeChatPlaneSession`) | `apiKeyProvider()` = `hermesAPIKeyBox.value` (`AppContainer.swift:632`), via `resolveEndpoint(profileID: nil)` `:1443-1467` | **NO REQUEST IS SENT** — `resolveEndpoint` **throws** `notConfigured` on an empty key (`:1463-1466`) | `ChatStore.refreshDirectHealth()` `Stores/ChatStore.swift:3095`, on the chat screen's health tick — **every 10 s, relaxing to 30 s** (`ChatHealthPollPolicy`) while the app is active. |
| E | `HostReachability.probe` `Services/Support/HostReachability.swift:106,144-170`, called from `Intents/AskHermesIntent.swift:142` | `makeProbeSession()`, 4 s | `container.hermesAPIKey`, **after** `waitForAPIKeyRestore` (`AskHermesIntent.swift:135,360-369`) | **Omitted** (`:157-158`) — but the call is **gated on a non-empty key** (`needsReachabilityPreflight`, `:98-100`), so in practice the header is always present | Siri / App-Intent "Ask Hermes" turns, and only when a Hermes host is configured. |

### The eliminations that matter

- **D is eliminated by ARITHMETIC, not by argument.** It runs 2–6 times a minute while the chat screen is up. A persistent 401 there would be hundreds of lines per hour, not 410 lifetime; it would also flip `directConnectionStatus = .error`, paint the offline banner, and log `Sessions API /v1/models failed:` (`:257`). And its credential is the *same box the runs plane uses* — chat working against OJAMD proves that key is valid. It can only 401 in a sub-second window (see candidate #4).
- **E is eliminated by its own gate.** `needsReachabilityPreflight` returns false on an empty key, so E never emits a headerless request; it can only 401 with a genuinely wrong stored key, which chat disproves.
- **C is eliminated by visibility.** A 401 there renders `ConnectionTestFailure.authRejected` right under the button (`:479-481`). It cannot be the *quiet* failure #414 describes.

---

## 2. Resolution-path diff — the 401ing path vs. the known-good path

**Known-good comparator: the Connect Host probe ladder, `GET /api/model/options`.**
`Services/Live/GatewayHermesHostService+ConnectProbe.swift:37-88`.

```
probeCandidateHost(gatewayBaseURL:apiKey:)
  request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")   // :54 — UNCONDITIONAL
```

**Known-good comparator 2: the runs plane (chat).**
`SessionsHermesClient.resolveTurnEndpoint` `:1286` → `resolveEndpoint` `:1443` → `makeRequest` `:1320`:

```
request.setValue("Bearer \(resolved.apiKey)", forHTTPHeaderField: "Authorization")   // UNCONDITIONAL
// …but resolveEndpoint has already THROWN if the key is empty (:1463-1466)
```

| | Runs plane / `makeRequest` (works) | `/api/model/options` ladder (works) | The four `/v1/models` probes (A, B, C, E) |
|---|---|---|---|
| Slot | `apiKeyProvider()` → `hermesAPIKeyBox`, or `profileEndpointResolver` → `ProfileGatewayKeyCache` for a birth-profile-pinned session | caller-supplied; `AppContainer+ConnectHost.swift:309` reads Keychain direct | A: `nil` (previous arm) / mirror (new arm) · B: Keychain direct per profile · C/E: mirror |
| Empty-key behaviour | **THROWS** — no request leaves the device | sends `Bearer ` (empty) — still a *present* header | **sends the request with NO `Authorization` header at all** |
| Result at the gateway | `notConfigured` surfaced in-app | 401 → `.keyRefused`, rendered as a verdict | **401 + one `API server rejected invalid API key` log line, invisible in-app** |

**That row is the whole mechanism.** Three shapes of "no credential" exist in this codebase — *throw*, *send an empty bearer*, *send no header* — and only the third one manufactures a silent server-side auth-failure log. All four `/v1/models` probes chose the third, each independently, each with a defensible local rationale (`if !key.isEmpty` reads like hygiene). Candidate A goes further and makes the headerless request the **intended** one.

Secondary diff worth recording: **the probe ladder was moved OFF `/v1/models` onto `/api/model/options`** by #309 Lane B bar 309-B3 (`OPEN_ITEMS-ARCHIVE.md` ~:42594). The four sites above are the ones that did not make that move.

---

## 3. Ranked candidates

### #1 — The profile-switch PREVIOUS-host probe is unauthenticated by design (HIGH)
**Evidence:** `AppContainer.swift:2318` (`key: nil`), `:2239` (header omitted), `:2229-2232` (docstring states the 401 is the expected answer), `:2200-2226` (`profileSwitchNotice` reads `previousVerdict` only when the NEW host is `.unreachable` ⇒ silent on a healthy switch). Introduced by `29a9812b` (2026-08-04, #247/#248).
**Predicts:** exactly one 401 per switch away from a host, at the host being LEFT, temporally isolated (no paired 200 at the same host in the same instant); zero during steady-state use; **the same pattern on the Mac gateway, not OJAMD-only**; the count over any window equals (profile switches in that window − one per process launch); chat and the picker entirely unaffected.
**Falsified by:** OJAMD 401s at wall-clock times when no profile switch occurred (e.g. a run of 401s minutes apart during a single uninterrupted chat session), or a 401 count that materially exceeds the plausible switch count. **Rate caution:** 410 lines since 2026-08-04 would be ~19/day, which is high; since the OJAMD log's retention window is unknown this is not yet a falsification, but it is the number that could become one. If the log demonstrably reaches back before 2026-08-04, some of the 410 belong to candidate #2, which predates it by six weeks (`78d49a02`, 2026-07-16).

### #2 — The Server screen sweeps a keyless profile, headerless (MEDIUM)
**Evidence:** `ServerSettingsScreen.swift:648-680` (sweeps **all** profiles), `:658` (Keychain-direct read, returns `nil` for a profile with no stored key), `:695` (header omitted on nil/empty). Fires once per Settings → Server appear.
**Predicts:** 401 bursts exactly at Settings → Server visits, one per keyless profile per visit; requires a profile holding a **non-empty `gatewayBaseURL` and no gateway key**; the screen would be rendering that profile as **"NO KEY"** / `.unkeyed` right now (`:305-306`, `:323`).
**Falsified by:** every profile in Settings → Server reading as keyed. Note #309 Lane B narrows this candidate's population without touching its code: 309-B4 commits URL and key together, and Disconnect clears the URL **with** the key (`AppContainer+ConnectHost.swift:359-383`), so URL-without-key is now hard to create — but a profile that reached that state *before* 2026-08-26 persists.

### #3 — A stale key crosses a profile switch on the health poll (LOW)
**Evidence:** `handleActiveProfileChanged` runs *after* `profilesStore.activeProfile` has already flipped, so `baseURLProvider` (`AppContainer.swift:628-632`) returns the NEW host while `hermesAPIKeyBox` still holds the OLD profile's key until `:2295-2300` completes its `await secureStore.retrieve`. A `refreshDirectHealth` tick landing inside that await window sends **Profile A's key to Profile B's host** — a genuinely *wrong non-empty* key, which is the one way path D can 401.
**Predicts:** at most one 401 per switch, tightly co-timed with a switch, and (unlike #1) it would 401 the host being switched **TO**, and would briefly paint the chat pip `.error`.
**Falsified by:** the arithmetic — a ~10–100 ms window against a 10 s poll is ~1 % per switch, so 410 occurrences would need ~40,000 switches. Keep it filed as a real (if rare) correctness wrinkle, not as this bug.

### #4 — Test Connection tapped before/without a key (LOW)
**Evidence:** `UplinkSettingsScreen.swift:426,453-455`. **Predicts:** one 401 per tap, and a visible "The host rejected this API key" under the button. **Falsified by:** Owen not reporting that message; a silent 410-line accumulation is inconsistent with a surface this loud.

### #5 — A per-profile Keychain scope mismatch (VERY LOW — checked and found clean)
`BackendProfileScopedKeys.gatewayAPIKey(scope)` = `"hermes.apiServerKey"` unscoped for a legacy profile (`usesLegacyCredentialKeys == true` ⇒ `credentialScopeID == nil`, `BackendProfile.swift:100-104`) and `"hermes.apiServerKey.<uuid>"` otherwise (`:193`, `:210-213`). **Writer and reader derive the scope identically** (`saveHermesAPIKey` `:2176` vs `gatewayAPIKey(for:)` `:2482`; bootstrap restore `:1144-1152`). No mismatch found. Recorded so the next lane does not re-open it.

---

## 4. Lane B assessment — did the Keychain hygiene touch this path?

**"Lane B" = #309 Lane B** (`OPEN_ITEMS-ARCHIVE.md:41419`, lane squash **`373ec733`**, 2026-08-26 03:39). The Keychain half is **bar 309-B9** (`OPEN_ITEMS-ARCHIVE.md` ~:42650) → `Talaria/Services/Support/RelayCredentialHygiene.swift`.

**What it does:** an idempotent purge of four *dead relay* slots — `accessToken`, `refreshToken` (Keychain) and `pairedRelayConfiguration`, `sessionState` (UserDefaults + mirror) — for **every** scope including legacy `nil` (`:34-40`, `:73-83`).

**What it explicitly does NOT touch:** `gatewayAPIKey`, `shimToken`, `talariaDeviceToken`, `talariaDeviceID` — enumerated in `survivingKeychainKeys` (`:44-54`) and pinned by a test whose whole job is to red if the purge widens.

**Direct check on the failing path:**
```
git show 373ec733 -- Talaria/Stores/AppContainer.swift \
    Talaria/Features/Settings/ServerSettingsScreen.swift \
    Talaria/Features/Settings/UplinkSettingsScreen.swift
  | grep '^[+-].*\(v1/models\|gatewayAPIKey\|probeGateway\|Authorization\|hermesAPIKey\)'
→ (no output)
```
**Zero lines.** Lane B changed neither the credential resolution nor the header construction of any `/v1/models` emitter.

**And it is already measured, not merely unlikely:** build **3087 contains Lane B** (`handoffs/HANDOFF-2026-08-23-SUN-NIGHT-BUILD-LIST.md:969` — "MORNING BOARD: build 3087 staged (the whole batch)", card `#309-B ★`; Lane B squashed 03:39, 3087 staged that morning), and 3087 is the build #414 observed 401ing at 18:12 and 19:05 the same day. **#414's "may already be fixed by Lane B's Keychain work and merely UNMEASURED post-3087" should be struck: it is measured, and it is not fixed.**

The one thing Lane B *did* do adjacent to this: bar 309-B3 moved the Connect Host probe ladder onto `GET /api/model/options` with an unconditional bearer (`GatewayHermesHostService+ConnectProbe.swift:54`), and 309-B4 made URL+key commit atomically — which shrinks candidate #2's population without touching its code.

---

## 5. THE ONE DISCRIMINATING MEASUREMENT

**Read Settings → Server on the device and count the profiles that show a gateway address AND read "NO KEY".** No code, no build, no wire capture — the screen already renders exactly this (`ServerSettingsScreen.swift:305-306,323`; `keyState: .missing` in the roster, `AppContainer+ConnectHost.swift:295-303`).

- **Zero keyless-but-addressed profiles ⇒ candidate #2 is dead and candidate #1 stands alone**, because #1 is the only remaining site that can emit a headerless `/v1/models` at a host that is otherwise fully credentialed.
- **One or more ⇒ both are live**, and the tie-breaker is the second measurement below.

**Confirmatory measurement (only if the eyeball leaves it ambiguous), and it also needs no new code:** in a *same-day* device logarchive, grep `org.aethyrion.talaria27` for the existing line `AppContainer.swift:2325` emits — `profile switch verdict: … (#247)` — and align its timestamps with the gateway's 401 timestamps. Each OJAMD 401 should sit **within ~5 s before** a switch-verdict line whose named new profile is *not* OJAMD. Mind the memory note: logd evicts app-subsystem rows in hours, so this must be collected the same day as the 401s.

**Do not** add a log line to the probe first. The measurement that identifies the mechanism already exists on both sides; the only thing missing is correlating them.

---

## 6. Tracker-ready block for #414

```
🔎 MECHANISM NAMED FROM CODE (2026-08-30, read-only lane) — and it is BY DESIGN.
- The 401s are `AppContainer.probeGatewayVerdict(baseURL: previous.gatewayBaseURL,
  key: nil)` — #247-B2's profile-switch verdict, PREVIOUS-host arm. `AppContainer.swift:2318`
  passes nil; `:2239` then omits the Authorization header; `:2229-2232` says the 401 IS the
  expected answer. One headerless GET /v1/models per switch AWAY from a host, silent in-app
  (the previous verdict is only read when the NEW host is unreachable, :2200-2226).
- HOST-SIDE CONFIRMED: api_server.py:1954-1966 logs "API server rejected invalid API key"
  for an ABSENT header as well as a wrong one — no separate missing-key branch — and
  _request_audit_context (:1848-1866) emits exactly the remote/method/path/user_agent shape
  §3(e) quoted. That is why the gateway log alone could never name this.
- FIT: #414's 18:12:26 and 19:05:58 land inside the 08-26 runbook evening where the tracker
  itself records Owen reading the approval gate "on BOTH hosts" and then "Switching to ojamd"
  (OPEN_ITEMS.md:4471-4508). Two switches away from OJAMD, two 401s.
- ⚖️ THE LANE-B HEDGE IS STRUCK — MEASURED, NOT UNMEASURED. Lane B = #309-B9
  RelayCredentialHygiene, which explicitly PRESERVES gatewayAPIKey (:44-54, test-pinned);
  `git show 373ec733` over AppContainer/ServerSettings/UplinkSettings returns ZERO lines
  touching v1/models, gatewayAPIKey, probeGateway, Authorization or hermesAPIKey. And build
  3087 CONTAINS Lane B (handoff 08-23 line 969, "the whole batch", card #309-B ★) — so 3087's
  401s are post-Lane-B. Not fixed.
- RUNNER-UP (medium): ServerSettingsScreen.probeGateway (:690-706, header omitted at :695)
  sweeps EVERY profile on screen-appear with a Keychain-direct key; a profile holding a URL
  and no key emits the identical line. Same log signature, so the gateway log cannot separate
  them.
- ELIMINATED: SessionsHermesClient.connect() (:251) — resolveEndpoint THROWS on an empty key
  (:1463), so it never sends a headerless request, and at 2-6 probes/min a real 401 there
  would be hundreds/hour plus an offline banner. AskHermesIntent's preflight — gated on a
  non-empty key (:98-100). Scope mismatch — writer and reader derive credentialScopeID
  identically; checked clean.
- 🎯 DISCRIMINATOR, no code needed: open Settings → Server and count profiles that show an
  address AND "NO KEY". Zero ⇒ the runner-up is dead and the switch probe stands alone.
  Confirmatory: align the existing `profile switch verdict: … (#247)` log line
  (AppContainer.swift:2325) against the gateway 401 timestamps in a SAME-DAY logarchive.
- ⚠️ Rate caution: 410 lines since #247-B2 landed (29a9812b, 2026-08-04) is ~19/day. If the
  OJAMD log reaches back before 08-04, part of the 410 belongs to the Server-screen sweep
  (78d49a02, 2026-07-16). The log's retention window is the number that would falsify a
  single-cause story.
- Not harmful today (no user-visible effect, chat and the picker are on other routes/slots),
  but it manufactures a security-shaped warning in the host's audit log on every switch —
  which is the cost worth naming when a fix is scoped.
```

### If a fix is ever scoped (NOT built here)
The minimal, behaviour-preserving change is to give the previous-host arm the same treatment #309 Lane B gave the Connect Host ladder: probe the PREVIOUS profile with **its own stored key** (`gatewayAPIKey(for: previous)`) instead of `nil`. Reachability classification is unchanged — a live gateway still answers 2xx/401/403 and a dead one still fails transport — but the request stops being an auth failure by construction. Cost: one Keychain read on the switch path. The same reasoning applies to `ServerSettingsScreen.probeGateway`, which already *has* the key and only omits the header when it is genuinely absent — there the honest fix is to skip the probe (or send an empty bearer, as the ladder does) rather than to emit a headerless request.
