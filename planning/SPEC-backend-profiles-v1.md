# Backend Profiles v1 — server switcher (T6 Part 2)  → OPEN_ITEMS #114

Status: DRAFT v3, review-corrected 2026-07-15 (all cross-refs verified against
OPEN_ITEMS + source at main 5ded719). Ready for Owen's nod → Fable lane.

## 0. Why now

Mac Mini backend is LIVE (#107): relay/connector/shim/gateway persistent, APNs
armed, and the Apple layer verified agent-driven — iMessage send+read, Notes
read+write. Those capabilities exist on the Mini today and are unreachable from
the phone. This lane is the last mile.

Owen's model: capability-based hosts, not interchangeable ones.
  OJAMD    = production brain — sensors, Windows toolsets, scheduled runs.
  Mac Mini = Apple-ecosystem hands — iMessage, Notes, Xcode toolsets, agent files.
"Tap the profile switch, pick the one you want, bam — you're talking to the Mac.
Windows need? Switch back."

## 1. The blocker this must solve (corrected — was mis-cited as #91)

**#94 / #3 clean-slate-on-pair.** `PairingStore.pair()` (Talaria/Stores/
PairingStore.swift:84-99) redeems the new code, then CLEARS the existing paired
relay configuration — deliberate, for #3 stale-identity protection. Today that is
correct: one app, one relay. Under profiles it is exactly Owen's stated failure
mode — "configure a second profile without wiping everything from the first."

Required change: the clean-slate becomes **per-profile**. Pairing profile B
redeems into B's slot and clears only B's prior record; A's pairing, tokens, and
Keychain mirror are untouched. #3's stale-identity protection is preserved
WITHIN each profile (re-pairing OJAMD still wipes OJAMD's old identity).
#41's Keychain mirror + rehydration extends per-profile (entries keyed by
profile UUID); #94's redeem-before-clear ordering must survive the refactor.

## 2. Model

BackendProfile:
  id             UUID
  name           String        ("OJAMD", "Mac Mini")
  gatewayBaseURL URL           gatewayAPIKey  Keychain(profile-keyed)
  relayBaseURL   URL           relayTokens    Keychain(profile-keyed; access+refresh, one-time QR pair)
  shimBaseURL    URL?          shimToken      Keychain(profile-keyed)?
  note           String?       ("Apple ecosystem / Xcode / iMessage")

UserSettings: + activeProfileID, + sensorDestinationProfileID.
Session records: + profileID (birth host, immutable).

## 3. Semantics

- **Session-host affinity:** every session is created on / streamed from /
  reconciled against its birth profile forever (session IDs are server-scoped —
  this makes reality explicit). Drawer badges non-active-host sessions.
- **Active profile** = default for NEW sessions + target for relay-plane
  interactive surfaces (device-files fetch, inbox polling, talk mode).
- **Switching is non-destructive both ways** and never re-pairs; it retargets.
- **Pairing:** one-time QR pair per relay (`hermes-mobile pair-phone` on each
  host). Dormant-profile tokens refreshed opportunistically (foreground, >7d)
  so the 30-day refresh TTL never strands a profile.
- **Push:** each relay holds the device token from its own pairing and watches
  its own gateway; the app routes an incoming push by the referenced session's
  profileID. Completion push works for BOTH hosts regardless of which is active.
- **Sensors:** outbox drains to sensorDestinationProfileID (default = OJAMD),
  independent of the active profile — production context never goes dark when
  Owen switches to the Mac. Dual-delivery = Tier 2.
- **Inbox:** v1 polls the ACTIVE relay only. Merged inbox = Tier 2.
- **Shim/model surfaces** read the active profile's shim (prevents the #1
  incoherence class: chat on one box, model defaults on another).
- **On-device brain toggle stays orthogonal.** End state for the picker:
  On-device / Hermes·OJAMD / Hermes·Mac Mini.
- **"New chat on <profile>"** (Owen: IN for v1): start a session on a named
  non-active profile without flipping the default — fire a task at the Mac
  without leaving OJAMD-land.

## 4. Settings surgery (all three verified in source)

- **NEW:** Settings → Server. Profile cards: name, host, active check,
  reachability dot (gateway answer + shim /healthz), paired/unpaired state.
  Tap = activate (confirm sheet). Per-profile pair flow reuses the existing QR
  screen. Add/edit/delete.
- **RETIRE the "use hosted" surface** — never used, never will be.
  `Talaria/Models/UserSettings.swift:4-15` (`hostedRelayBaseURL`,
  `hostedRelayEnabled`, `APP_HOSTED_RELAY_ENABLED`) +
  `Talaria/Features/Settings/RelaySettingsScreen.swift`.
- **RETIRE the Relay/Direct switch** —
  `Talaria/Features/Settings/UplinkSettingsScreen.swift:137`
  (`modeSegment("Relay", active: !isDirect …)`). Per #108's iPad lesson, Direct
  is the only workable mode (relay-only can't reach the Sessions API — the key
  is a separate plane the pairing QR doesn't carry). Profiles make it moot:
  every profile is Direct-with-its-own-key by construction. Keep #108's
  "paired — add your key in Uplink" nudge, retargeted per-profile.
- **RETOOL the New Chat warning** —
  `Talaria/Features/Chat/ChatScreen.swift:107-118`, a "Clear Conversation"
  confirmationDialog reading *"This will archive the current conversation and
  start a new session. This cannot be undone."* with a `.destructive` Clear
  button. Triggered by New Conversation (`:255`), `sessionsModel.onNewChat`
  (`:368`), and `:1166`. The copy is wrong on its face — archiving is
  non-destructive and the conversation stays in the drawer. Owen: retool or
  remove. Recommend: drop the dialog for the plain case (New Chat just starts
  one), and if a menu is wanted, that's where "New chat on <profile>" lives.

- **Migration:** current config → profile "OJAMD" (active + sensor destination),
  sessions backfilled to it; Mac Mini added and paired manually.

## 5. Tier 2 (successor item)

Dual sensor delivery; merged multi-relay inbox; per-gateway capability/toolset
cards; scheduled dispatch to non-active profiles (#98 interplay); per-profile
talk configs.

## 6. Definition of done

whoGoesThere holds OJAMD + Mac profiles simultaneously; switching is
non-destructive in both directions; #107's dev-device pairing line closes; and
from Talaria chat on the Mac profile, "send an iMessage to Shelley: …" hits the
#4 confirm gate and delivers.

## 7. Decisions (Owen, 2026-07-14/15)

D1. Relay plane FOLLOWS the profile (profile stores its own pairing).
D2. Sensors pinned to production; do NOT follow the switch.
D3. "New chat on <profile>" ships in v1.
D4. Inbox = active relay only in v1.
D5. Sessions never migrate hosts; backfill = OJAMD.
D6. Per-profile Keychain entries die with their profile; active + sensor-dest
    profiles cannot be deleted.
D7. Photon rejected (#107) — irrelevant here, noted so it isn't reconsidered.
