# #269-A — Plugin-link honesty (+ #353(b)) — design

**Date:** 2026-08-16 night · **Tracker:** #269 (bars A-A/B/C/E pre-registered
2026-08-09; D MET via #352; A-F + the A-A adaptation added tonight) · **#353
route (b)** folds in here (Owen) · **Design approved in discussion** ·
**Verified against:** `main` @ `9d15c0c`.

## Why

Two surfaces assert what they cannot know. The Server screen's PLUGIN LINK
row renders PAIRED from a Keychain token alone
(`TalariaLinkState.resolve`, `ServerSettingsScreen.swift:65-68` — "a token in
the active profile's slot is the whole signal"), so a phone pointed at a host
with no adapter still claims PAIRED — the #350 shape on this plane. And the
About status panel renders the deliberately retired relay (#346) as a
permanent red `Relay Link — ERROR` (#353) — a training-to-ignore-red surface.

## Verified premises (read at HEAD tonight)

1. **The probe seam is live-verified and side-effect-free.** Unauthenticated
   `POST /api/platforms/talaria/events` → **401** when the adapter is
   registered (auth rejection precedes verb dispatch — nothing drains,
   nothing acks) vs **503 platform_unavailable** when absent. Probed live
   2026-08-09; the 401 arm re-proven remotely on OJAMD during #271.
2. **`TalariaPlatformLink` owns the endpoint** (`eventsPath`, `:31`), the
   credential-scope discipline (`TurnContext`, #285), and already classifies
   outcomes internally (`DrainOutcome`) — no UI consults any of it.
3. **The state model's honesty bound:** "never installed", "on disk but not
   enabled", and "enabled but not restarted" are indistinguishable app-side —
   all 503. Only the agent can tell them apart (the #269 architecture: the
   agent narrates WHY, the app verifies WHETHER).
4. **About's `isHealthy` hero** keys on hostConfigured + direct-or-relay
   connection — untouched by the relay-row regroup.

## The design

**1. Probe** — `probeLinkState() async -> TalariaLinkProbeResult` on
`TalariaPlatformLink`: unauthenticated POST to `eventsPath` with a short
dedicated timeout (the #136 bootstrap-probe shape, ~4s), classified:

| wire outcome | observation |
|---|---|
| HTTP 401 | `.adapterLive` |
| HTTP 503 | `.adapterAbsent` |
| other HTTP status | `.indeterminate(status:)` — an unexpected status licenses nothing |
| transport error / timeout | `.hostUnreachable` |
| no gateway URL | `.notConfigured` |

The observation carries the raw status that licensed it (269-A-C).

**2. State model** — new `Talaria/Services/Live/TalariaLinkObservation.swift`:
the observation enum + a pure `TalariaLinkDisplayState.compose(observation:,
hasDeviceToken:)`:

| observation | token | display |
|---|---|---|
| adapterLive | yes | `LIVE · PAIRED` (accent) |
| adapterLive | no | `LIVE · NOT PAIRED` (muted) |
| adapterAbsent | any | `NOT LIVE` (forge — token never upgrades it) |
| hostUnreachable | any | `HOST UNREACHABLE` (muted) |
| indeterminate | any | `—` |
| notConfigured | any | `—` |
| (probe in flight) | — | `—` (existing decay behavior) |

`TalariaLinkState` (the token-only enum) is deleted; the row consumes the
composed state. Copy never claims a cause — the strings above are the whole
vocabulary (269-A-C).

**3. Server screen** — `refreshTalariaLinkState()` runs the Keychain read and
the probe concurrently, composes, renders. Refresh triggers unchanged
(appear + profile switch).

**4. About page (#353(b))** — the status panel gains a **Plugin Link** row
(same composed state, probed in the page's `.task`). Relay Link + Relay
Identity move under a `// Legacy Relay` section header. Severity derives from
measurement — pure function `legacyRelaySeverity(pluginLive: Bool,
relayReachable: Bool)`: plugin LIVE + relay unreachable → muted `OFFLINE`
(the phone-facing channel is up; not an error); plugin not live + relay
unreachable → red stands. No intent is asserted anywhere.

**5. Testing** — table tests for the classifier (stubbed HTTP: 401, 503,
418, refused connection), the composer, and the severity derivation; the
existing URLProtocol stub machinery covers the wire arms (mind the
[[urlprotocol-sse-stub-buffering]] sub-512B flush trap — plain HTTP responses
here, but pad if a stub misbehaves). Live arms: 401 against OJAMD (read-only,
no gate needed). Device arm: 269-A-F screenshot.

## Out of scope

Drawer footer + settings grid strip (#350 — its own bars, this machinery is
adoptable there later); `describe` envelope (plugin-repo contract, gated);
PairingStore/voice/relay client; any plugin-repo change.

## Bars

A-A (adapted: stubbed 503/transport arms, live 401 arm), A-B, A-C, A-E as
pre-registered 2026-08-09; A-F as pre-registered tonight. All in the #269
entry.
