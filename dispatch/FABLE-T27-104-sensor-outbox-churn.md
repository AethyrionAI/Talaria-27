# FABLE T27-104 — Sensor-outbox churn hardening (#104)

**OPEN_ITEMS:** #104 (sensor-outbox persistence churn)
**Branch prefix:** `claude/t27-104-`
**Cloud-safe:** fully local (persistence + encoding). No relay, OJAMD, Tailscale,
or device access needed to design or verify — unit tests are the acceptance
gate; the thermal/CPU pass is a later on-device confirmation.

## Objective

`SensorUploadService.persistOutboxState()` (→ `UserDefaultsAppPersistenceStore
.saveSensorOutboxState`) encodes and rewrites the WHOLE outbox on **every**
location update, motion-activity change, and health snapshot, inside `@MainActor`
tasks. Cost scales linearly with backlog, and there is **no backlog cap** — so a
connector outage (see #103) turns routine sensor ticks into a sustained CPU/IO
loop (heat + UI jank). Harden the write path without touching the drain/relay
semantics.

## Grounding — read these BEFORE designing

- `Talaria/Services/Live/SensorUploadService.swift` — `@MainActor` class.
  `outboxState` holds `pendingLocation` + `pendingHealthSamples:
  [PendingHealthSample]` (deduped by `dedupeKey`). `persistOutboxState()` is
  called from `Task { @MainActor in … }` on each location update (~line 283) and
  each health snapshot (~line 316). `start()` loads, `resetOutbox()` clears.
- `Talaria/Services/Support/UserDefaultsAppPersistenceStore.swift` —
  `saveSensorOutboxState(_:)` / `loadSensorOutboxState()` (JSON-encodes
  `SensorOutboxState` into UserDefaults). Both sides of the round-trip.
- `Talaria/Services/Protocols/AppPersistenceStoreProtocol.swift` — the store is
  injected via this protocol, so a spy/mock store is the unit-test seam (count
  saves, capture states).
- The drain path (send-to-relay on reachability) is OUT OF SCOPE — do not touch
  it. This lane only changes WHEN/HOW the outbox is written to disk and bounded.

## Deliverables

### 1. Debounce / coalesce persistence
- Persist at most once per short interval (a few seconds) OR on a chunk
  boundary — not on every single tick. A crash-loss window of a few seconds of
  sensor samples is explicitly acceptable (stated in the item).
- **Must flush pending writes on teardown** — `stop()`, background/resign-active,
  and a successful drain — so nothing beyond the debounce window is lost.
- Inject the clock/scheduler (or a `now:` provider) so the interval is testable
  deterministically; no real `sleep` in tests.

### 2. Cap the backlog
- Cap `pendingHealthSamples` with **oldest-drop** when the cap is exceeded, and
  set an honest diagnostics note/flag when a drop happens (surfaced wherever the
  outbox status is already reported — see `pendingHealthCount` usage ~line 247).
- Location stays single-slot (already coalesced). Pick a sane cap constant and
  justify it in the PR.

### 3. Move the encode off the main actor
- Snapshot `SensorOutboxState` on the main actor (value copy), then encode +
  write **off** `@MainActor` (detached task / nonisolated helper). `SensorOutboxState`
  must be `Sendable` to cross the boundary — confirm/annotate (it is a Codable
  value type). The main actor must not block on `JSONEncoder().encode`.

### 4. Tests (Swift Testing) — the acceptance gate
- Debounce: N rapid ticks within the interval ⇒ **≤1** save (spy store); a save
  DOES land after the interval; `stop()`/teardown **flushes** a pending write.
- Cap: appending past the cap drops the OLDEST, `count == cap`, diagnostics flag
  set; under the cap, no drop, no flag.
- Round-trip / back-compat: a `SensorOutboxState` persisted by the OLD shape
  still decodes (additive-only changes; mirror the `voiceMemoAudioPath` #59
  precedent).

## Hard constraints

- File-scoped to `SensorUploadService.swift` + `UserDefaultsAppPersistenceStore.swift`
  (+ a new `TalariaTests/SensorOutboxChurnTests.swift`). No collision with Lanes
  D/F/G/H (per the item).
- Do NOT change drain/relay/send semantics, the sensor-collection callbacks, or
  the dedupe logic — only the write cadence, the cap, and the encode isolation.
- `SensorOutboxState` Codable stays decode-compatible with existing caches
  (additive only).
- New test file ⇒ PR notes the Mac runs `xcodegen generate` + re-verifies
  `aps-environment` survives the regen (#44/#48 trap).
- File-scoped commits; no `OPEN_ITEMS.md` edits; no pbxproj in feature commits.
- Cloud can't build: check every Swift-6 concurrency move (Sendable snapshot,
  detached encode, actor hops) against the iOS 27 SDK; be suspicious of
  Foundation bridging shortcuts — the review loop keeps catching those.

## Acceptance

- All new `@Test` suites green (Swift Testing ✔ line); full suite still green.
- Debounce, cap+diagnostics, and off-main encode all covered by tests as above.
- Behavior preserved: samples still persist and drain; only the write cadence,
  bound, and isolation change.
- Device-verify owed (later, on-device): during a simulated connector outage the
  device no longer heats / the main thread no longer churns on sensor ticks.
- PR titled `#104 — sensor-outbox churn hardening`.
