# FABLE LANE M — Backend Profiles (server switcher)

**Repo:** `AethyrionAI/Talaria-27` · **Branch prefix:** `claude/t27-lane-m-*`
**Dispatch date:** 2026-07-15 · **Supersedes:** nothing (new lane)
**Tracks:** OPEN_ITEMS #114 · **Interlocks:** #107 (two of its acceptance
criteria cannot close without this lane) · **Spec:** planning doc summarized
here — this file is authoritative for Fable.
**Delivery:** THREE PRs, in order. PR 1 must be a behavior-preserving refactor.
PR 2 and PR 3 stack.

---

## Mission

Talaria has two live backends and can only talk to one. OJAMD (Windows) is the
production brain — sensors, scheduled runs, Windows toolsets. The Mac Mini is
now live (#107) and holds capabilities that **cannot exist on Windows**:
iMessage send+read, Apple Notes read+write, Xcode toolsets, macOS agent files.
Both were verified working on the Mini on 2026-07-15. They are unreachable from
the phone.

Owen's model, verbatim: *"After it's set up, you tap the profile switch, pick the
one you want, and bam — you're now talking to the Mac. Have a Windows need?
Switch profiles and bam, ask away."*

Build **named backend profiles**: add a second profile without wiping the first,
switch between them non-destructively, and let each profile's host do what only
it can do.

---

## The blocker this lane exists to solve

**`PairingStore.pair()` (`Talaria/Stores/PairingStore.swift:84-99`) clears the
existing paired relay configuration.** It redeems the new code FIRST, then
clears + saves (correct ordering — that's #94's finding, do not regress it). The
clear is deliberate: #3 stale-identity protection. Today it is right, because one
app = one relay.

Under profiles it is precisely Owen's stated failure mode: pairing the Mac would
wipe OJAMD. **The clean-slate must become per-profile** — pairing profile B
redeems into B's slot and clears only B's prior record; A's pairing, tokens, and
Keychain mirror are untouched. #3's protection is preserved *within* each profile
(re-pairing OJAMD still wipes OJAMD's old identity).

`#41`'s Keychain mirror + rehydration extends per-profile (entries keyed by
profile UUID). `#42`'s decode-failure logging should keep working per-profile.

---

## Non-negotiable constraints (house rules)

- **Single-profile behavior is sacred.** With exactly one profile (the migrated
  state every existing install lands in), the app must behave identically to
  current main. Guard test where feasible.
- **Never wipe another profile.** Any code path that clears credentials must be
  profile-scoped. This is the lane's whole point — a regression here is a P0.
- **Real data only.** Reachability dots reflect actual probes; `—` for unknown.
  No fabricated "online" states.
- **File-scoped commits.** `pbxproj`/scheme regen in its own commit. No
  `OPEN_ITEMS.md` edits in feature commits.
- **xcodegen:** any file add/remove → `xcodegen generate` on the Mac side. After
  EVERY regen verify `aps-environment: development` survived in
  `Talaria/Talaria.entitlements`, plus WeatherKit (CarPlay key stays commented) —
  standing #44/#48 trap.
- **Cloud can't build.** Author for the Mac review-then-build loop. Note any API
  you could not compile-verify.
- **Swift 6 isolation:** repo precedent — block-based `NotificationCenter`
  observers are task-isolated (use selector-based); mutating calls inside
  `#expect` fail (hoist to locals).
- **Tests:** Swift Testing (`@Test`), matching repo convention.
- **Keychain hygiene:** deleting a profile deletes its Keychain items. The active
  profile and the sensor-destination profile cannot be deleted.

---

## PR 1 — Profile model + migration (invisible refactor)

**Acceptance: zero observable behavior change.** One profile exists; everything
routes through it; the app looks and acts exactly as today.

### M-1. Model

```
BackendProfile:
  id             UUID
  name           String        ("OJAMD", "Mac Mini")
  gatewayBaseURL URL           gatewayAPIKey  Keychain(profile-keyed)
  relayBaseURL   URL           relayTokens    Keychain(profile-keyed)
  shimBaseURL    URL?          shimToken      Keychain(profile-keyed)?
  note           String?       (free text, e.g. "Apple ecosystem / Xcode / iMessage")
```

- `UserSettings` gains `activeProfileID` + `sensorDestinationProfileID`.
- Session records gain `profileID` — birth host, **immutable** (session IDs are
  server-scoped; this makes existing reality explicit).

### M-2. Migration (one-shot, idempotent)

- Current config → profile **"OJAMD"**, set active + sensor destination.
- Source of truth for seeds: `UserSettings.swift:353` `defaultHermesAPIBaseURL =
  "http://ojamd:8642"` and `:357` `defaultModelsShimBaseURL = "http://ojamd:8765"`
  — these global constants **stop being app-wide truth** and become that
  profile's seed values.
- Existing sessions backfill `profileID` = OJAMD profile.
- Existing Keychain entries migrate to profile-keyed entries (must survive
  delete/reinstall per #41; do not strand the user's pairing).

### M-3. Per-profile clean-slate (the #94/#3 surgery)

Refactor `PairingStore.pair()` to scope its clear to the target profile.
**Preserve redeem-first ordering** — a failed redeem must still leave the
existing record intact (#94). Add a test proving pairing profile B leaves
profile A's record and Keychain mirror untouched.

### M-4. PR 1 tests

Migration idempotence; single-profile parity; per-profile clean-slate isolation;
redeem-first ordering preserved; Keychain round-trip per profile.

---

## PR 2 — Multi-profile routing (behavior, still no new UI)

Unobservable without PR 3's UI — carry it with unit tests.

### M-5. Session-host affinity

Every session is created on / streamed from / reconciled against its birth
profile forever. Drawer shows all sessions; sessions whose `profileID` ≠ active
get a profile badge. Reconnect/fetch resolve the base URL from the session's
profile, **not** the active one.

### M-6. Active profile semantics

Active = default target for NEW sessions + the relay-plane interactive surfaces:
device-files fetch (#21), inbox polling, talk mode. Shim/model surfaces read the
active profile's shim (prevents the #1 incoherence class: chat on one box, model
defaults on another).

### M-7. Push routing

Each relay holds the device token from its own pairing and watches its own
gateway. Route an incoming push by the referenced session's `profileID`.
Completion push must work for BOTH hosts regardless of which is active.

### M-8. Sensors stay pinned

Outbox drains to `sensorDestinationProfileID` (default OJAMD), **independent of
the active profile** — production context must not go dark when Owen switches to
the Mac. Dual-delivery is Tier 2, out of scope.
*Collision:* #104 (sensor-outbox churn) touches this path — see Collision surface.

### M-9. Token freshness

Dormant-profile tokens refreshed opportunistically (foreground, >7d since last
refresh) so the 30-day refresh TTL never strands a profile. Must not thrash on
every foreground.

### M-10. Inbox

v1 polls the ACTIVE relay only. Items on the inactive relay wait for switch-back
or its push. Merged inbox = Tier 2. **Keep the strict-decoder discipline** — one
bad `kind` row poisons the whole fetch.

### M-11. PR 2 tests

Session routes to birth profile after a switch; push routes by session profileID;
sensor destination ignores active-profile changes; dormant refresh fires once.

---

## PR 3 — Settings surgery + UX

### M-12. NEW: Settings → Server

Profile cards: name, host, active check, reachability dot (gateway answer + shim
`/healthz`), paired/unpaired state. Tap = activate (confirm sheet). Add / edit /
delete. Per-profile pair flow **reuses the existing QR pairing screen**.

### M-13. RETIRE the "use hosted" surface

`Talaria/Models/UserSettings.swift:4-15` (`hostedRelayBaseURL`,
`hostedRelayEnabled`, `APP_HOSTED_RELAY_ENABLED`) +
`Talaria/Features/Settings/RelaySettingsScreen.swift`. Owen: never used, never
will be.

### M-14. RETIRE the Relay/Direct switch

`Talaria/Features/Settings/UplinkSettingsScreen.swift:137`
(`modeSegment("Relay", active: !isDirect …)`). Per **#108**'s iPad lesson,
relay-only cannot reach the Sessions API — the key is a separate plane the
pairing QR doesn't carry, so Direct is the only workable mode. Profiles make it
moot: every profile is Direct-with-its-own-key by construction.
**Keep #108's "paired — add your key in Uplink" nudge**, retargeted per-profile —
an unkeyed profile must say so, not fail silently.

### M-15. RETOOL the New Chat warning

`Talaria/Features/Chat/ChatScreen.swift:107-118` — a "Clear Conversation"
confirmationDialog reading *"This will archive the current conversation and start
a new session. This cannot be undone."* with a `.destructive` Clear button.
Triggers: `:255` ("New Conversation"), `:368` (`sessionsModel.onNewChat`),
`:1166`. Also reached by ⌘N (Lane J).

The copy is wrong on its face — archiving is non-destructive and the conversation
remains in the drawer. **Owen: retool or remove.** Recommended: drop the dialog
for the plain case (New Chat just starts one). If a menu is wanted, that is where
M-16 lives.

### M-16. "New chat on <profile>"

Start a session on a named non-active profile **without flipping the default** —
fire a task at the Mac without leaving OJAMD-land. Owen explicitly wants this in
v1. Natural home: the New Chat surface freed up by M-15.

### M-17. PR 3 tests

Activation flow; delete guards (active + sensor-dest undeletable); unkeyed-profile
nudge; New-chat-on-profile creates a session with the right `profileID` and does
not change `activeProfileID`.

---

## Collision surface

- **`ChatStore.swift`** — M-5/M-6 touch it. **#110** is a queued micro-fix and is
  **NOT on main** (verified 2026-07-15). Its item text says `ChatStore.swift:517`
  but the call has drifted to **`:528`** (`self.speechOutput?.finishStream(`);
  `SpeechOutputService` exposes both `stop()` (:73) and `finishStream()` (:112).
  Don't fold #110 in — just expect that line neighborhood to move.
- **Sensor path** — **#104** (outbox rewritten to UserDefaults on every tick, main
  actor) overlaps M-8. Do not fold #104's fix in; just don't make its churn worse.
- **`UplinkSettingsScreen.swift`** — **VERIFIED 2026-07-15: #108's nudge branch is
  NOT merged.** `origin/claude/t27-hermes-switch-nudge` @ ef5dbd9 ("surface a
  'paired but unkeyed' notice so the Hermes switch isn't silently locked") is not an
  ancestor of main. So M-14's "keep the nudge" instruction has nothing to keep —
  **implement the unkeyed-profile notice as part of M-14**, per-profile, and treat
  ef5dbd9 as reference art (it solves the single-profile case). Owen's call whether
  to merge ef5dbd9 first; if it lands before this lane, rebase and generalize it
  instead of reimplementing.
- **`SessionsDrawer.swift` / `ConversationListPane`** — M-5's badges touch the
  Lane J split-view sidebar. Lane J's regular-width sidebar must stay correct.
- **Lane F** surfaces (search/pin/archive) exist once — don't duplicate.

---

## Device verification prerequisites (Owen, not Fable)

Mac backend is live and waiting:
- gateway `http://100.79.222.100:8642` · relay `http://100.79.222.100:8000/v1`
  · shim `http://100.79.222.100:8765`
- APNs armed (`org.aethyrion.talaria27`); relay/connector/shim launchd-persistent.
- Pairing the phone to the Mac relay = `hermes-mobile pair-phone` on the Mini.

---

## Definition of done

whoGoesThere holds **OJAMD + Mac Mini profiles simultaneously**; switching is
non-destructive in both directions; #107's dev-device-pairing criterion closes;
and from Talaria chat on the Mac profile, *"send an iMessage to Shelley: …"*
reaches the Mini and delivers.

---

## Out of scope (explicitly)

- **Tier 2:** dual sensor delivery; merged multi-relay inbox; per-gateway
  capability/toolset cards; scheduled dispatch to non-active profiles (#98
  interplay); per-profile talk configs.
- **Photon** — evaluated and rejected (#107). Do not reintroduce.
- **The "Windows brain, Mac hands" MCP bridge** — documented in
  `relay/docs/DEPLOY_MAC.md`, deliberately not built (Owen). This lane is the
  chosen shape.
- **Confirm-gating agent terminal calls.** The Mini's agent can shell to `imsg`;
  today the guard is a skill instruction ("confirm before send"), not app-side
  enforcement. Whether Talaria's #4 confirm pattern should cover agent-initiated
  sends is an OPEN QUESTION for Owen — flag it, don't build it.
- **#104 / #110** — separate items; don't fold in.
