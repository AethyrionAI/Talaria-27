# #309 — Plugin-native pairing: the handshake design

**Written 2026-08-25 (Fable, per Owen's ruling: "design the plugin-native
pairing handshake"). This is a DESIGN DOC — no code rides it. Owen rules on
it before any lane opens (#309 ruling 2, filed 2026-08-25). Facts below were
read from source at main @ `e106943a` and plugin checkout
`~/.hermes/plugins/talaria` @ `e669549`; line cites are to those.**

> **⚖️ RULED 2026-08-25 night — ALL FIVE QUESTIONS ANSWERED; the code
> gate is OPEN (full ruling text in tracker #309):** posture RATIFIED
> (with the clarification that nothing is "reimplemented" — the typed arm
> was always the real handshake; first-credential delivery is the one
> irreducibly manual step); ambition = **SKIPPABLE FIRST-RUN WIZARD +
> the always-available manual Settings path** (Owen's own reframe —
> read WITH #31: a front door, never a wall; this GROWS Lane B, and a
> Claude Design spec from Owen feeds it); cleanups BOTH as recommended
> (Q3, Q4 = delete); lanes ALL FOUR, order A → D∥ → C → B-after-spec
> (Owen delegated the election — "Your call"). §6 is now read through
> the wizard ruling; §7's order note is superseded by this one.

---

## 0. The one-sentence design

**Pairing a new device IS acquiring `{gateway URL, API_SERVER_KEY}` into a
profile — nothing more exists to hand-shake, because everything downstream
already self-assembles from those two values.** The work is therefore a
credential-acquisition UX (typed + QR), a deletion map for the relay client
family, and a small host-side QR generator — not a new protocol.

## 1. What already exists (read from source, not designed here)

The relay's pairing handshake has a plugin-native successor **already
shipped end-to-end**, which this design largely ratifies rather than
invents:

- **The plugin's `pair` verb** (`envelope.py:240`) — authorized by the
  gateway API key itself (`pair_requires_api_key`), takes `install_id` +
  `device_name`, returns `{device_id, device_token}`.
  `store.create_paired_device` (`store.py:158`) atomically rotates any
  active row for the same install — re-pairing is idempotent per install,
  and outbox rows follow the install to its new identity (351-D).
- **The app already speaks it.** `TalariaPlatformLink.ensurePaired`
  (`TalariaPlatformLink.swift:128`) self-pairs whenever the profile holds a
  gateway API key and the Keychain lacks a device token — both halves
  written whole, #285 epoch-checkpointed, one re-pair per 401. **No user
  step exists on this plane at all.**
- **Route + verb auth** (`envelope.py:78-113`): the platform-events route
  accepts Bearer = API key OR any active device token; device verbs
  (`drain`/`ack`/`query_result`/`unpair`/`talk_*`) require device token +
  matching `device_id`; only `pair` demands the root key.
- **Voice** rides the same device token since #383 (`talk_readiness`,
  `talk_session_create/end`) — the relay's `talk/*` paths are re-homed and
  `LiveVoiceSessionService` is confirmed relay-free (#309's 2026-08-25
  register block).
- **A manual escape hatch nobody consumes:** `hermes talaria pair`
  (`admin.py:15,43` → `store.create_pairing`, `store.py:55`) mints a device
  row with **no install_id** and prints the plaintext token once. The app
  has no UI to paste it; it predates the `pair` verb. See Q4.
  **⟵ CORRECTED 2026-08-25 night (#412, Owen's device find on 3063):
  "no UI" understates it — the Pairing & Devices screen
  (`ConnectHermesHostScreen.swift:118`) ADVERTISES this CLI ("Prints a
  pairing code — scan it with Pair New Device below") while its scanner
  accepts only the 8-char relay alphabet and redeems against the retired
  relay. The arm is not merely unconsumed; it is falsely advertised by a
  flow that dead-ends twice. Strengthens Q4: make it real or delete both
  halves, and §6's screen replacement inherits #412's pin.**

**The consequence:** the chat plane (`/v1/runs`, `/api/sessions*`)
authenticates by Bearer `API_SERVER_KEY` and by nothing else — the gateway
has no per-device credential concept, and building one would be Hermes-core
work we never do. So any device that chats must hold the root key, and any
"pairing" indirection that tries to keep the root key off the phone is
theater. The ruled posture — *"the gateway key IS the pairing"*
(#251/#269, restated as the disposition table's row 6) — is not a
compromise; it is the only honest reading of the auth topology. The device
token the plugin mints is the **derived, lesser, per-device-revocable**
credential, and it derives automatically.

## 2. What the relay handshake actually delivered — and why none of it is missed

`LivePairingService.redeemPairingCode` (`LivePairingService.swift:56`)
posts `phone-pairing/redeem` and receives: a relay **user id**, a relay
**device id**, relay **access/refresh JWTs** with expiry, and the relay's
own **backendEndpoint**. Every one of those is relay-plane identity for
relay-plane calls — the redeem never carried the gateway URL or the API
key, which were always typed into the profile separately. With both hosts'
relays retired, the handshake mints credentials for a service that no
longer answers, and **a new device today has NO working path through
`ConnectHermesScreen`** (the pair button requires a valid relay URL + an
8-char code minted by the retired shell's "Settings → Devices → Pair
Phone" pane).

The bootstrap chain that consumed those tokens
(`LiveSessionBootstrapService`: `device/register`, `session`,
`auth/refresh`, `auth/revoke`) was the diagnosed cause of #365's
full-screen stall (disposition report finding 3). **Honest update from
the 2026-08-25 dependency sweep: that finding was written against
pre-#310 HEAD and is PARTIALLY mitigated today.**
`handleActiveProfileChanged` now gates the bootstrap on
`profile.hasRelay && isPaired && accessToken != nil`
(`AppContainer.swift:2336`), so a gateway-only profile switches
instantly. **But a profile that still carries its relay-era
`relayBaseURL` — which describes every profile paired before the
retirement, i.e. the daily-driver ones — still runs the doomed chain on
every profile switch, and cold launch still reaches
`sessionStore.bootstrap()` unconditionally through
`startBackgroundBootstrap` (the `initialize()` path checks only
`isPaired`, never `hasRelay` — a gap the sweep confirmed at HEAD).** So
deleting the family still removes real doomed traffic on real installs;
it just no longer rescues gateway-only profiles, which #310 already
rescued.

## 3. The handshake, concretely

### 3a. Acquisition arms

- **Arm 1 — typed entry (exists; keep as the base arm).** The profile
  editor's gateway URL + API key fields. Proposed upgrade: a
  **probe-and-confirm** step — on commit, `GET /health` with the key;
  green check or a named failure (#264's `gateway_state.json` guidance
  stays ops-side; the app only needs reachable-and-authorized). Read-only,
  app-side, not hardening.
- **Arm 2 — QR scan (the new-device UX).** Reuse
  `SetupCodeScannerView`. Payload: versioned JSON, e.g.
  `{"talaria":1,"gateway":"http://100.110.102.59:8642","key":"<API_SERVER_KEY>","name":"OJAMD"}`.
  Scanning it fills the same fields Arm 1 types and runs the same
  probe-and-confirm; the QR is sugar, not a second code path.
  **Generator: a plugin CLI addition — `hermes talaria pair-qr`** — that
  renders the payload as an ANSI QR in the terminal (plus optional PNG
  path). Rationale for the terminal over the dashboard: the plugin's
  dashboard half is deliberately read-only status
  (`dashboard/manifest.json`), and a web page that renders the root key
  on demand is a strictly worse exposure than the terminal of the owner
  who can already `cat .env`. The Electron desktop-plugin pane is a
  fine v2 home if Owen wants a clickable one later.
- **Arm 3 — one-time-token indirection: REJECTED.** Redeeming a
  short-lived token for the API key would add a minting/redemption
  surface (new persistent state, new expiry logic — hardening-shaped) to
  protect a key that must land on the phone anyway, and buys zero
  privilege separation while the chat plane accepts only the root key.
  Revisit only if upstream Hermes ever grows per-device API credentials.

### 3b. What "unpair" becomes

Local forget of the profile's credentials **plus** a best-effort plugin
`unpair` POST (the verb ships; `store.deactivate` revokes the device
token host-side). Row 9's "unpair becomes 'forget the key', local"
disposition, upgraded one notch by the verb that now exists. Host-side
recourse for a lost phone: `hermes talaria unpair` + rotating
`API_SERVER_KEY` in `.env` — worth one line in the README at #308's
publication scrub.

### 3c. What `isPaired` means afterwards

"The active profile holds gateway credentials" (and, if Owen elects
probe-and-confirm, "…which have been seen working"). The relay-specific
notion — redeemed code, JWT freshness, `deviceRegistered` — dissolves.
§5 carries the reader-by-reader map.

## 4. Migration for existing pairings

**There is no migration ceremony — by construction.** Existing profiles
already hold the gateway URL, the API key, and the plugin device
token/device id in scoped Keychain slots (`BackendProfileScopedKeys`);
none of that moves or changes shape. What the deletion lanes do to the
relay-era residue:

- **Relay JWTs (`AuthTokens`), relay user/device identity
  (`AppSessionState`), paired-relay config:** deleted with their readers.
  Proposed hygiene: a one-time, idempotent Keychain cleanup at profile
  load that deletes the known dead keys — cheap, honest, and it keeps
  the "half-paired" ghost states #133 taught us about from ever being
  read again. (The relay's own DB rows are host-side and follow #144:
  deactivate, never delete — but that is the relay's concern, not the
  app's.)
- **`BackendProfile.relayBaseURL` (optional since #310):** delete the
  property. Codable decode simply ignores the stored JSON key — no
  persisted-state migration needed. Timing is Q3.
- **Existing device rows in the plugin store:** untouched. Rotation
  continues to key off `install_id` exactly as today.

## 5. The relay client family's deletion, mapped

> Blast radius verified by a dedicated dependency sweep (Sonnet agent,
> 2026-08-25, this session, main @ `e106943a`, 123 tool calls); the
> disposition table
> (`planning/reports/2026-08-19-309-relay-path-dispositions.md`, accepted
> 12 DELETE / 4 ADAPT) remains the path-level authority. Line cites
> below are the sweep's.

### 5a. Delete outright

Services + protocols + mocks: `LivePairingService`,
`LiveSessionBootstrapService`, `LiveHermesHostService`,
`ResilientSessionBootstrapService`, `ProfileRelaySession` (whose factory
is a FOURTH constructor of the bootstrap service, for dormant-profile
refresh), `RelayAPIClient`, `PairingServiceProtocol`,
`SessionBootstrapServiceProtocol`, `HermesHostServiceProtocol`, the three
mocks. Models: `AppSessionState`, `AuthTokens`,
`PairedRelayConfiguration`, `PairingRedeemResult`,
`DeviceRegistrationRequest`, `SessionBootstrapResponse`,
`RelaySetupCodePayload` (`PhonePairingCode`). Stores: `PairingStore`,
`HermesHostStore`, and `AppSessionStore` **except** its
installation-identity logic (§5d). UI: `ConnectHermesScreen`,
`ConnectHermesHostScreen` (both replaced by §6's Connect Host), with
`SetupCodeScannerView` RETAINED but re-pointed at the new QR payload
(it is a thin VisionKit wrapper with exactly one call site).

### 5b. Edit, not delete (the load-bearing ones)

- **`AppContainer.swift`** — the largest surface (~20 `pairingStore.*`
  sites): client construction (:419-439), `allowsFallback` closures
  (:456, :592), `hasHermesHost` (:636), `reportAppStateIfNeeded`
  (:2039 — path 10, already double-gated, now deleted whole),
  `refreshCommandCatalog`'s `hasRelay` branch (:2350 — path 16's adapt
  point), dormant-token refresh, sensor-opt-in migration — and the four
  lifecycle gates (§5c).
- **`ContentView.swift:232,256-265`** — `.connectHost` routing +
  paywall-attempt classification re-derived from profile capability.
- **`ChatScreen.swift:63-65,836-837`** — the offline banner is gated on
  RELAY pairing state while describing the DIRECT gateway transport (the
  sweep's words: it "misdescribes direct-Hermes reachability today").
  Re-derive from gateway reachability; this fixes a live misattribution,
  not just a compile error.
- **Settings family** (`SettingsChannelsScreen`, `SettingsChannels`,
  `SessionsSettingsScreen`, `ServerSettingsScreen`, `AboutSettingsContent`,
  `UplinkSettingsScreen`) — every `isPaired` /
  `identityMismatchDetected` / `expectedRelayUserID` site; the profile
  editor drops `relayBaseURL` + its validation; the per-profile
  Pair/Re-Pair/Forget-Pairing controls become Connect-Host actions;
  `AboutSettingsContent`'s "Relay Identity" row dies.
- **`BackendProfile.swift`** — `relayBaseURL`/`hasRelay`/
  `resolvedRelayBaseURL` go; of `BackendProfileScopedKeys`, the relay
  slots (`accessToken`, `refreshToken`, `pairedRelayConfiguration`,
  `sessionState`) go while `gatewayAPIKey`/`talariaDeviceToken`/
  `talariaDeviceID` stay. NOTE the Keychain slot family has TWO
  writers today (`AppSessionStore` for the active profile,
  `ProfileRelaySessionFactory` for dormant ones) — the §4 hygiene
  cleanup must cover both writers' slots, scoped and legacy alike.
- **`LiveVoiceSessionService.swift`** — already relay-free (#383) but
  still borrows `RelayAPIClient.ClientError` at four sites (:986,
  :1045, :1055, :1447). **Extract the error enum first** or the
  RelayAPIClient deletion breaks voice compilation.
- **`AppRootView.swift:27,52`** — splash logic re-keyed.
- Two things deliberately NOT in the radius (do not sweep them up):
  `ResilientHermesClient` and `TalariaPlatformLink`/inbox — gateway-native
  already; only the predicate closures AppContainer feeds them change.

### 5c. 🔴 THE SWEEP'S NEW FINDING — the four lifecycle gates (filed as #411)

`initialize()` (:1344), `runForegroundActivation()` (:1645),
`handleSystemLaunch()` (:1732), `handleBackgroundRefresh()` (:1760) —
plus `retryCredentialHoldIfNeeded()` (:1414) — **all hard-guard their
entire bodies on `pairingStore.isPaired`.** A gateway-only (or fully
hostless) install therefore never runs host/skills/voice-readiness
refresh, live-activity reconciliation, widget-data refresh, share-inbox
drain, or dormant-token refresh through ANY lifecycle transition — only
whatever individual screens redundantly do in their own `.task`. The
codebase already knows this trap: `TalariaPlatformLink`'s scene wiring
(:1010-1016) explicitly refuses the `isPaired` gate for exactly this
reason — but the four entry points never got the same treatment. Judged
against the launch pivot (the DEFAULT user is hostless), this is a
standing defect TODAY, independent of any deletion. **The deletion
lanes must replace these gates with capability-appropriate ones (local
work: always; gateway work: profile-has-credentials), not merely delete
the guard** — and #411 tracks verifying how much of the local critical
path is actually reachable today for unpaired installs via the
redundant per-screen paths before anyone quotes a user impact.

### 5d. Must SURVIVE the deletion

- **Installation identity** (`AppSessionStore.swift:73-98` + 
  `InstallationIdentityTests`): the durable `installationID` is the
  #133/#143 duplicate-push fix AND the `install_id` the plugin's
  `create_paired_device` rotation keys on. It moves to a small
  dedicated owner; its tests port, not tombstone.
- `SetupCodeScannerView` (re-pointed), the gateway credential slots,
  and `saveGatewayAPIKey`/`gatewayAPIKey` in AppContainer.

### 5e. Test blast radius (headline numbers)

`AppStoresTests.swift` is the bulk: 10× `AppSessionState`, 6×
`AuthTokens`, 18× `RelayAPIClient`, 7× `MockSessionBootstrapService`,
5× `PairingStore`, incl. the load-bearing MARK sections (#3/#46 stale
identity, #136 offline-first, #310 gateway-only-no-relay-calls, #369
credential-hold). Plus `BackendProfilesTests` (key-format pins),
`ProfileSwitchAtomicityTests` (1152 lines of switch races),
`ServerSettingsTests`, `InstallationIdentityTests` (ports, per §5d),
two one-ref files, and the whole `AppTemplateUITests.swift` XCUITest
pairing suite (703 lines). **The #310 and #136 sections are the
regression armor for exactly the behavior these lanes change — they get
REWRITTEN to pin the new shape, never deleted as "relay tests."**

## 6. The pairing screen's future (#406/#405 implications)

`ConnectHermesScreen` as it stands — relay URL draft, 8-char code boxes,
"Find this on your host under Settings → Devices → Pair Phone" — is
retired with the family. Its replacement ("**Connect Host**" working
name) keeps the shell and swaps the organs:

- Gateway URL field — **reusing #406's commit-time draft pattern
  verbatim** (the pattern shipped days ago and is exactly right here:
  draft-local edits, stores written at commit moments only).
- API key field (secure entry).
- QR scan arm (same scanner view, new payload; #405's
  falsely-valid-mid-draft normalization lesson applies to the gateway
  URL field's validation and its pins carry over in spirit).
- Probe-and-confirm (if elected, Q2) before the profile commits.
- The `END-TO-END ENCRYPTED · DEVICE-BOUND KEY` footnote must be re-cut
  to something TRUE for the new shape (Bearer over Tailscale; honest
  copy per the real-data-only rule).

The #31/#137 stance is untouched: no pairing wall, local brain first,
Hermes stays a Settings-level upgrade.

## 7. Proposed lane structure (for election, not begun)

- **Lane A — kill the doomed bootstrap AND re-key the lifecycle gates
  (paths 1–4 + #411).** Delete `LiveSessionBootstrapService` (all four
  constructors' worth), the bootstrap await in
  `handleActiveProfileChanged`, and the cold-launch background
  bootstrap; replace the four `isPaired` lifecycle guards with
  capability-appropriate gates (local work: always; gateway work:
  profile-has-credentials). One lane because it is one region of
  AppContainer and the gate replacement is what makes the deletion safe
  rather than a regression (§5c). The #310/#136 test sections rewrite
  to pin the new shape.
- **Lane B — Connect Host screen** (§6) + unified unpair (today's
  "Revoke Host" and "Disconnect" are two different relay endpoints on
  one screen — they collapse into local-forget + plugin `unpair`) +
  Keychain hygiene (§4) + `relayBaseURL` property deletion (per Q3) +
  the ChatScreen banner re-derivation. App-side only.
- **Lane C — the small adapts + deletes:** extract
  `RelayAPIClient.ClientError` for voice FIRST (§5b), then row 7
  (`hosts/current` → gateway `/health`), row 16 (`commands` →
  `/v1/skills`, degrading honestly per #180 —
  personalities/quick-commands are a RULED loss), row 10
  (`device/app-state` beacon delete), row 5 confirm-gone, and the
  final `RelayAPIClient`/`ProfileRelaySession` deletion once nothing
  references them.
- **Lane D — host-side `pair-qr`** (plugin repo; rides the established
  plugin deploy path — OJAMD brief + Owen's transmission; live-install
  go per experiment as always).
- Already running/landed independently: `LiveHermesClient` deletion
  (paths 13–15; its own lane, this session).

A→B→C→D order is proposed but only A's position is argued for (it
deletes the remaining doomed traffic and the #411 starvation together);
B–D commute. Note C's ClientError extraction must precede C's (or any
lane's) RelayAPIClient deletion.

## Questions for Owen

1. **Ratify the posture:** the QR (and the typed arm) carry the root
   `API_SERVER_KEY` — "the gateway key IS the pairing," now applied to
   UX. The alternative (token indirection, Arm 3) is rejected above with
   reasons. OK to proceed on that basis?
2. **Connect Host ambition:** bare fields · fields + probe-and-confirm
   (recommended) · full wizard? (Recommendation: probe-and-confirm; a
   wizard is ceremony the two-field reality doesn't need.)
3. **`relayBaseURL` property deletion:** with Lane B, or deferred to a
   later hygiene pass? (Recommendation: with Lane B — #310 already made
   it optional; keeping a dead field invites a new reader.)
4. **The CLI's no-install-id pairing arm** (`hermes talaria pair` →
   `create_pairing`): delete it (the `pair` verb + `pair-qr` cover
   everything, and an un-rotatable manual row is a small wart) or keep
   as an escape hatch? (Recommendation: delete, in Lane D.)
5. **Lane election + order** (§7): which lanes, and A-first confirmed?
