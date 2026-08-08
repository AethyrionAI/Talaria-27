# #285 Profile-Activation Atomicity Fix — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (inline — see
> "Execution mode" below for why this lane is NOT subagent-driven). Steps use checkbox
> (`- [ ]`) syntax for tracking.

**Goal:** Make a backend-profile switch an atomic transport boundary: one logical transport
turn belongs to exactly ONE profile/host, and after a newer activation supersedes it, no
old-profile async completion mutates current-profile state.

**Architecture:** Three coordinated changes, all instances of one idea — *resolve profile
context once per logical unit, then guard side effects on currentness*:
1. `TalariaPlatformLink` gets an immutable per-turn `TurnContext` (scope + endpoint + all
   three Keychain keys + an epoch) resolved synchronously at turn start; `stop()` bumps the
   epoch and every side-effect step (POSTs, delivery, ack/answer, Keychain writes/deletes)
   checks currentness first. Superseded → abandon; never mix.
2. `BackendProfilesStore.setActiveProfile`'s handler dispatch becomes serialized and
   cancel-superseding (the proven `AppContainer.startBackgroundBootstrap` #136 idiom), and
   `AppContainer.handleActiveProfileChanged` gains cancellation checkpoints so a superseded
   activation stops writing shared state (`hermesAPIKey`, key box, store resets, link
   restart). Rapid A→B→C is last-writer-wins by construction.
3. The #283 runs driver resolves its endpoint ONCE per turn (`ResolvedEndpoint` snapshot)
   and threads it through the whole request family (history GET, submit, events, status
   polls, stop), so a mid-turn switch cannot redirect later requests.

**Tech Stack:** Swift 6 / SwiftUI iOS 27 beta, Swift Testing (`@Test`/`#expect`),
Xcode-beta4 (`DEVELOPER_DIR=/Applications/Xcode-beta4.app/Contents/Developer`), xcodegen,
sim UDID `47F68496-24F9-45D9-93D3-1C778DB6B557`.

## Global Constraints

- **Bars pre-registered in OPEN_ITEMS #285 (verbatim):** (285-A) one transport turn cannot
  mix profile A/B keys or endpoints (deterministic suspension harness, not sleeps);
  (285-B) superseded drain cannot deliver/ACK/answer/write credentials after invalidation;
  (285-C) rapid A→B→C is last-writer-wins (active profile, `hermesAPIKey`, key box, scoped
  stores, link all = C; late B completion cannot overwrite); (285-D) existing
  platform-link + profile-switch tests stay green; gate + Release green.
- **The RED tests get INVERTED, not deleted** (`ProfileSwitchAtomicityTests.swift`). The
  parked-lane warning is binding: a partial fix that snapshots the keys but leaves
  activation unserialized turns 5 reproducible failures into 2 and reads as progress —
  ALL THREE parts ship together or the lane does not close.
- **The runs adjacency is in scope** (tracker #285 update note): "whatever per-turn
  snapshot 285 lands should cover the runs driver's request family, not just the platform
  link."
- **No relay/connector changes** (the ⛔ no-harden rule). Everything here is app-side.
- `xcodegen generate` after any file add/remove; revert the xcscheme drift it causes
  (`git checkout -- Talaria.xcodeproj/xcshareddata/xcschemes/Talaria.xcscheme`).
- Test runs: suite-level `-only-testing` selectors only (method selectors silently run 0
  tests); plain `test`, never `test-without-building`; read the executed count every run.
- THE CLOSE-OUT RULE: every doc line the fix falsifies (notably `AppContainer.swift`
  ~:2190 "park the drain before the scope moves") is corrected in the same commit family.

## Execution mode

Inline (superpowers:executing-plans), NOT subagent-driven. Owen parked this for a Fable
budget precisely because the hazard is a *cross-task* invariant — a per-task subagent
holding only its own slice is the partial-fix failure mode the tracker warns about. One
context holds all three parts.

## Branch mechanics

Work in the existing worktree `.claude/worktrees/t27-285-profile-atomicity` (branch
`claude/t27-285-profile-atomicity`, currently based at `c4067a3`). Rebase onto current
`main` first — main has since merged PR #279 (runs transport, `6784139`) and seven docs
commits. Expected conflict: `OPEN_ITEMS.md` (both sides touched the #285 area; resolution =
main's surroundings + the branch's #285 CONFIRMED/PARKED status updates). The branch is
local-only with no PR, so rebase is safe.

---

### Task 0: Rebase, regenerate, and RE-CONFIRM RED on post-#283 main

The RED verdicts were produced against `c4067a3`. Main has moved (runs transport merged).
Before fixing anything, prove the defect still reproduces on the code being fixed.

**Files:**
- Modify: branch state only (rebase), `Talaria.xcodeproj/project.pbxproj` (via xcodegen)

- [ ] **Step 0.1:** In `.claude/worktrees/t27-285-profile-atomicity`:
  `git fetch . main:refs/heads/nothing-needed` is unnecessary (same repo); run
  `git rebase main` directly. Resolve `OPEN_ITEMS.md` conflicts: keep main's text for
  everything except the #285 entry body, where the branch's CONFIRMED/PARKED update notes
  win (append them to main's entry rather than replacing main's header line).
- [ ] **Step 0.2:** `xcodegen generate` then
  `git checkout -- Talaria.xcodeproj/xcshareddata/xcschemes/Talaria.xcscheme`. Verify the
  pbxproj still lists `ProfileSwitchAtomicityTests.swift`.
- [ ] **Step 0.3:** Run the RED suite:
  ```bash
  DEVELOPER_DIR=/Applications/Xcode-beta4.app/Contents/Developer \
    xcodebuild -project Talaria.xcodeproj -scheme Talaria -configuration Debug \
    -destination 'platform=iOS Simulator,id=47F68496-24F9-45D9-93D3-1C778DB6B557' \
    -only-testing:TalariaTests/ProfileSwitchAtomicityTests test
  ```
  Expected: **6 tests, all passing** (they assert the BROKEN behavior). If any repro no
  longer reproduces, STOP — that is a finding (something on main changed the mechanism);
  record it in the tracker before proceeding.
- [ ] **Step 0.4:** Commit the rebase resolution if the rebase produced changes needing a
  commit (usually not; rebase rewrites in place). Note the new base SHA for the record.

### Task 1: TalariaPlatformLink — immutable TurnContext + epoch guards (bars 285-A, 285-B)

**Files:**
- Modify: `Talaria/Services/Live/TalariaPlatformLink.swift` (whole transport section)
- Modify: `Talaria/Stores/AppContainer.swift:976-1021` (link construction — `apiKey:`
  closure removed)
- Modify: `TalariaTests/TalariaPlatformLinkTests.swift` (constructor migration: seed the
  mock store with the API key instead of passing a closure)
- Modify: `TalariaTests/ProfileSwitchAtomicityTests.swift` (invert repros 1, 2, 3, 3b;
  keep provenance + control)

**Interfaces:**
- Produces: `TalariaPlatformLink.DrainOutcome` gains `case superseded`.
- Produces: constructor loses `apiKey:` — the link now reads the key itself from
  `secureStore` under `BackendProfileScopedKeys.gatewayAPIKey(<frozen scope>)`, which is
  byte-what production's closure did. Call sites: `AppContainer.swift:986` (delete the
  closure argument), both `makeLink` helpers in the two test files.
- Produces: `stop()` bumps a private `epoch`; turns capture it in their context.

**Design (locked):**

```swift
/// #285: everything profile-scoped one logical turn needs, resolved ONCE —
/// synchronously, so no suspension can split the resolution — at turn start.
/// A turn carries this context to completion or abandonment; it NEVER
/// re-resolves live profile state after its first await.
private struct TurnContext {
    let scopeID: UUID?
    let gatewayBaseURL: String
    let tokenKey: String
    let deviceIDKey: String
    let apiKeyKey: String
    /// The link epoch at turn start. `stop()` bumps the epoch, so
    /// `epoch == context.epoch` failing means this turn was superseded —
    /// it must not deliver, ack, answer, POST, or touch the Keychain again
    /// (finishing the Keychain step it is INSIDE is allowed — a credential
    /// pair is written/dropped whole or not at all).
    let epoch: Int
}

/// Bumped by every stop(). A turn that outlives its epoch abandons at the
/// next side-effect checkpoint instead of completing cross-profile (#285).
private var epoch = 0

/// nil when no gateway URL is configured (the .notConfigured outcome).
private func makeTurnContext() -> TurnContext? {
    // Both closure reads are synchronous @MainActor calls with no await
    // between them — atomic on the actor by construction.
    guard var base = gatewayBaseURL(), !base.isEmpty else { return nil }
    while base.hasSuffix("/") { base.removeLast() }
    let scope = credentialScopeID()
    return TurnContext(
        scopeID: scope,
        gatewayBaseURL: base,
        tokenKey: BackendProfileScopedKeys.talariaDeviceToken(scope),
        deviceIDKey: BackendProfileScopedKeys.talariaDeviceID(scope),
        apiKeyKey: BackendProfileScopedKeys.gatewayAPIKey(scope),
        epoch: epoch
    )
}

private func isCurrent(_ context: TurnContext) -> Bool { epoch == context.epoch }
```

Threading (every `tokenKey`/`deviceIDKey`/`gatewayBaseURL()`/`endpointURL()` use inside a
turn goes through the context; the computed vars `tokenKey`/`deviceIDKey` and the
zero-argument `endpointURL()` are DELETED so no future call site can re-resolve live):

- `func ensurePaired() async -> Bool` becomes a thin wrapper: build a context (nil →
  false), delegate to `ensurePaired(context:)`.
- `private func ensurePaired(context: TurnContext) async -> Bool` — both retrieves use
  `context.tokenKey` / `context.deviceIDKey`; delegates to `pair(context:)`.
- `private func pair(context: TurnContext) async -> Bool` — reads the API key via
  `await secureStore.retrieve(key: context.apiKeyKey)`. **Checkpoint before the POST**
  (`guard isCurrent(context) else { return false }` — a superseded turn must not mint a
  device row the client will discard; that is #288's orphan source). **Checkpoint before
  the store-pair** — then `store(tokenKey)` + `store(deviceIDKey)` back-to-back with no
  checkpoint between them (a pair is written whole).
- `drainOnce(wait:)` — builds the context (nil → `.notConfigured`), passes it down.
- `private func drain(context:wait:allowRepair:)` — retrieves via frozen keys; the
  notConfigured-vs-failed branch after `ensurePaired` failure reads
  `await secureStore.retrieve(key: context.apiKeyKey)` instead of the old `apiKey()`.
  **Checkpoint before the drain POST** (superseded → `.superseded`). On 401 self-repair:
  **checkpoint before the delete-pair**, then BOTH deletes (frozen keys) with no
  checkpoint between them — a pair is dropped whole; **checkpoint before the re-pair**
  and **before the recursive drain**. After the 200: **checkpoint before the delivery
  block** (`onItemsReceived` + `ack`), and **a checkpoint per `answer(...)`** in the
  query loop (each answer is its own POST).
- `ack`/`answer` take `context` and use `post(context:...)`.
- `private func post(_ body:, context: TurnContext, bearer: String)` — builds the URL from
  `context.gatewayBaseURL + Self.eventsPath`; no live re-resolution.
- `func stop()` — add `epoch += 1` as the first line (before `isRunning = false`).
- `DrainOutcome` gains `case superseded`; `start()`'s loop handles it as
  `case .superseded: break` (the `while` guard exits next check — `isRunning` is already
  false whenever a turn comes back superseded).

The **turn boundary decision, explicit:** a turn that was already inside a Keychain
mutation when superseded FINISHES that atomic step under its frozen keys
(snapshot-and-complete for the step), then abandons at the next checkpoint
(invalidate-and-abandon for everything after). "Mixed" in the invariant means mixed
*profiles*, which frozen keys make impossible — not mixed strategies.

- [ ] **Step 1.1: Invert the four repro tests** in `ProfileSwitchAtomicityTests.swift`
  (this is the failing-test step — they now assert the FIXED behavior and must FAIL
  against current code). Keep `GatedSecureStore`, `WireRecorder`, the park/flip/release
  choreography, the anti-vacuous `pendingCount` guards, and the control test byte-for-byte.
  Update `makeLink` (drop `apiKey:`, seed `apiKeyKeyA`/`apiKeyKeyB` values are already
  seeded). New names + assertions:
  - `ensurePairedStraddlesTwoProfilesAcrossItsFirstAwait` →
    `ensurePairedCompletesEntirelyOnItsBirthProfileAcrossASwitch`. Stub returns
    `{"device_id":"dev-fromA","device_token":"tok-fromA"}`. After park→flip→release:
    ```swift
    #expect(secure.trace == [
        "retrieve(A.deviceToken)", "retrieve(A.deviceID)", "retrieve(A.apiKey)",
        "store(A.deviceToken)", "store(A.deviceID)",
    ])  // identical to the control's shape — the switch changed NOTHING
    #expect(paired == true)
    #expect(secure.peek(key: Self.tokenKeyA) == "tok-fromA")
    #expect(secure.peek(key: Self.deviceIDKeyA) == "dev-fromA")
    #expect(secure.peek(key: Self.tokenKeyB) == nil)
    #expect(secure.peek(key: Self.deviceIDKeyB) == nil)
    #expect(wire.all.count == 1)
    #expect(wire.all.first?.host == "gateway-a.local")
    #expect(wire.all.first?.body.contains("apikey-A") == true)
    ```
    (Note: A is seeded fully paired in this test today, so `ensurePaired` would
    short-circuit under frozen keys. Remove the `deviceIDKeyA` seed — same arrangement the
    control already uses — so the turn takes the `pair()` path.)
  - `profileACredentialsArePostedToProfileBsGateway` →
    `aDrainTurnSpeaksOnlyToItsBirthProfilesGateway`. Same park (2nd `deviceIDKeyA`
    retrieve — under frozen keys the trace to the park is unchanged), flip, release:
    ```swift
    #expect(posted.count == 1)
    #expect(posted.first?.host == "gateway-a.local")   // was gateway-b.local in RED
    #expect(posted.first?.body.contains("\"auth\":\"tok-A\"") == true)
    #expect(posted.first?.body.contains("\"device_id\":\"dev-A\"") == true)
    #expect(outcome == .idle)
    ```
  - `stopDoesNotUnwindOrContainAnInFlightTurn` →
    `stopContainsAnInFlightTurnNoCrossProfileReadsNoSideEffects`. Park the drain's own
    token read (occurrence 2), flip + `stop()`, release. `stop()` still cannot unwind the
    parked continuation (`pendingCount == 1` after stop stays asserted — that mechanism is
    real and documented); what changes is what the resumed turn may do:
    ```swift
    #expect(secure.trace == [
        "retrieve(A.deviceToken)", "retrieve(A.deviceID)",
        "retrieve(A.deviceToken)", "retrieve(A.deviceID)",   // frozen key — was B.deviceID in RED
    ])
    #expect(wire.all.isEmpty)          // the superseded turn never POSTs
    #expect(received.items.isEmpty)    // and never delivers
    ```
  - `aStoppedTurnStillDeletesTheNewProfilesCredential` →
    `aStoppedTurnFinishesItsOwnCredentialDropAndNeverTouchesTheNewProfile`. Same
    arrangement (A stale-paired, B validly paired, 401 script, park first delete), flip +
    stop, release:
    ```swift
    #expect(secure.trace.contains("delete(A.deviceToken)"))
    #expect(secure.trace.contains("delete(A.deviceID)"))       // pair dropped WHOLE
    #expect(secure.trace.contains("delete(B.deviceID)") == false)
    #expect(secure.peek(key: Self.tokenKeyA) == nil)
    #expect(secure.peek(key: Self.deviceIDKeyA) == nil)        // A cleanly unpaired
    #expect(secure.peek(key: Self.tokenKeyB) == "tok-B")       // B untouched
    #expect(secure.peek(key: Self.deviceIDKeyB) == "dev-B")
    #expect(wire.all.count == 1)                               // ONLY the 401'd drain —
    #expect(wire.trace.filter { $0.contains("\"pair\"") }.isEmpty)  // no orphan mint (#288)
    ```
    The wait condition changes from `trace.contains("delete(B.deviceID)")` to
    `trace.contains("delete(A.deviceID)")`.
  - The provenance test and the control keep their names and assertions; update the
    provenance test's doc comment (it no longer "falsifies a comment" — it documents WHY
    the epoch exists: `stop()` can never run before the scope moves, so containment must
    live in the link).
- [ ] **Step 1.2:** Run the suite; expected: the four inverted tests FAIL (current code
  still mixes profiles), provenance + control PASS. Read the count: 6.
- [ ] **Step 1.3:** Implement the design above in `TalariaPlatformLink.swift`. Delete the
  `apiKey` stored property + init parameter, the two computed key vars, and the
  no-argument `endpointURL()`.
- [ ] **Step 1.4:** Migrate the two other construction sites: `AppContainer.swift:986`
  (delete the `apiKey:` argument and its comment — fold the comment's point into the
  construction-site note: the link reads the Keychain itself, per-turn, #285);
  `TalariaPlatformLinkTests.makeLink` + the second inline construction (`:188`) — delete
  `apiKey:` and add `secureStore.seed`/equivalent for
  `BackendProfileScopedKeys.gatewayAPIKey(Self.scope) → "test-key"` (check `MockSecureStore`'s
  seeding API in that file; it already seeds paired tokens in several tests).
- [ ] **Step 1.5:** Run both suites together:
  `-only-testing:TalariaTests/ProfileSwitchAtomicityTests -only-testing:TalariaTests/TalariaPlatformLinkTests test`
  Expected: **19 tests pass** (6 + 13), count read from output.
- [ ] **Step 1.6:** Commit:
  `fix(#285): TalariaPlatformLink turns carry an immutable TurnContext — frozen scope/endpoint/keys + epoch supersession; RED repros 1/2/3/3b INVERTED to pin the fixed behavior`

### Task 2: Serialized, cancel-superseding activation (bar 285-C)

**Files:**
- Modify: `Talaria/Stores/BackendProfilesStore.swift:144-156` (`setActiveProfile`)
- Modify: `Talaria/Stores/AppContainer.swift:2184-2289` (`handleActiveProfileChanged`
  checkpoints + the falsified :2190 comment)
- Test: `TalariaTests/ProfileSwitchAtomicityTests.swift` (two new tests)

**Interfaces:**
- Consumes: nothing from Task 1 (independent mechanism, same file for tests).
- Produces: `BackendProfilesStore` gains private `activationGeneration: Int` and
  `activationTask: Task<Void, Never>?`. `setActiveProfile`'s signature and synchronous
  semantics (scope moves in the same turn, returns `Bool`) are UNCHANGED.

**Design (locked):** in `setActiveProfile`, replace
`Task { await onActiveProfileChanged?(target) }` with:

```swift
// #285: activation side effects are SERIALIZED and cancel-superseding —
// the #136 bootstrap idiom. A rapid A→B→C switch must not interleave two
// handlers' awaits; the superseded dispatch is cancelled (its handler
// checkpoints on Task.isCancelled) and the newer one waits out the corpse
// so nothing stale lands after it. Last writer wins, always.
activationGeneration += 1
let generation = activationGeneration
let predecessor = activationTask
predecessor?.cancel()
activationTask = Task { [weak self] in
    await predecessor?.value
    guard let self, self.activationGeneration == generation, !Task.isCancelled else { return }
    await self.onActiveProfileChanged?(target)
}
```

In `handleActiveProfileChanged`, insert `guard !Task.isCancelled else { return }`
checkpoints — the handler runs inside the store's activation task, so cancellation IS the
supersession signal:
1. After the `await secureStore.retrieve(...)` and before `gatewayKeyCache?.set` /
   `hermesAPIKey =` / `chatAPIKeyBox?.value =` (the shared credential boxes).
2. Inside the `if pairingStore.isPaired…` block, after `sessionStore.bootstrap()` and
   after `hostStore.refresh()` (before `lastKnownHostOnline =`).
3. After the `refreshCommandCatalog`/`seedActiveModelFromGateway`/`refreshReadiness`/
   `refreshDirectHealth` cluster, before the `talariaPlatformLink?.start()` block — a
   superseded handler must never restart the link; the winning activation's own handler
   does that.

Also rewrite the falsified comment at ~:2190. Replacement text:

```swift
// #251-2A/#285: supersede the platform link's in-flight turn. The scope has
// ALREADY moved (setActiveProfile assigns state synchronously, before this
// handler ever runs — see ProfileSwitchAtomicityTests' provenance test), so
// stop() is not a barrier ahead of the switch and cannot be one. It does not
// need to be: stop() bumps the link's turn epoch, and a superseded turn
// abandons at its next side-effect checkpoint instead of completing
// cross-profile. Restarted at the end of THIS handler iff still current.
```

- [ ] **Step 2.1: Write the two failing tests** (same file, after the repros):
  - `rapidSwitchesRunTheHandlerOnlyForTheLastWriter`: real `BackendProfilesStore`
    (UserDefaults suite fixture like the provenance test), three profiles A (migrated
    seed), B, C. Handler records profile names into an array box. Call
    `setActiveProfile(B.id)` then IMMEDIATELY (same synchronous turn)
    `setActiveProfile(C.id)`. `await waitUntil { !invocations.isEmpty }` plus a settle
    sleep (150ms). Assert: `invocations == ["C"]` (B's dispatch was superseded before its
    handler ran — the generation guard), and `store.activeProfileID == C.id`.
  - `aSupersededMidFlightHandlerIsCancelledAndTheWinnerRunsAfterItExits`: handler parks on
    a `CheckedContinuation` gate (reuse the `GatedSecureStore` continuation idiom in a
    small `GatedHandlerBox`: records `enter(name)`/`exit(name, wasCancelled)` events,
    parks on first enter). `setActiveProfile(B.id)`; `waitUntil { box.entered.contains("B") }`;
    `setActiveProfile(C.id)`; release the gate; settle. Assert the event log is exactly
    `["enter(B)", "exit(B cancelled=true)", "enter(C)", "exit(C cancelled=false)"]` —
    serialized, B saw cancellation after resuming, C entered only after B exited.
- [ ] **Step 2.2:** Run: both FAIL against current code (first: invocations == ["B","C"]
  or interleaved; second: no cancellation, possible overlap). Count moved to 8.
- [ ] **Step 2.3:** Implement the store dispatch + AppContainer checkpoints + comment.
- [ ] **Step 2.4:** Run `ProfileSwitchAtomicityTests` (8 pass) + the neighbors that touch
  this seam: `-only-testing:TalariaTests/BackendProfilesTests`
  `-only-testing:TalariaTests/ServerSettingsTests`
  `-only-testing:TalariaTests/BackendProfileRoutingTests`. All green, counts read.
  (`ServerSettingsTests:37` appends from the handler on a single switch — single-switch
  behavior is unchanged by serialization; if it flakes on timing, fix the TEST's wait,
  not the dispatch.)
- [ ] **Step 2.5:** Commit:
  `fix(#285): profile activation serializes and supersedes — #136 idiom on setActiveProfile dispatch, cancellation checkpoints in handleActiveProfileChanged, falsified 'park the drain' comment corrected`

### Task 3: Runs driver — per-turn ResolvedEndpoint (the #283 adjacency)

**Files:**
- Modify: `Talaria/Services/Live/SessionsHermesClient.swift` (`ResolvedEndpoint` type,
  `resolveTurnEndpoint`, `makeRequest`/`getJSON`/`postJSON` endpoint parameter,
  `activeRunContext` tuple gains `endpoint`)
- Modify: `Talaria/Services/Live/SessionsHermesClient+RunsTransport.swift` (thread the
  snapshot through `streamTurnViaRuns`, `syncTurnViaRuns`, `fetchRunsHistory`,
  `pollRunToTerminal`, `readRunStatus`, `deliverPolledTerminal`, `hardStopActiveRun`)
- Test: `TalariaTests/RunsPlaneTransportTests.swift` (harness records host; one new test)

**Interfaces:**
- Produces:
  ```swift
  /// #285 (runs adjacency): one turn's endpoint, resolved once at turn start.
  struct ResolvedEndpoint: Sendable, Equatable {  // runs-path-visible
      let baseURL: String
      let apiKey: String
  }
  func resolveTurnEndpoint(profileID: UUID?) throws -> ResolvedEndpoint
  ```
  (implementation: `let resolved = try resolveEndpoint(profileID: requestProfileID(profileID));
  return ResolvedEndpoint(baseURL: resolved.baseURL, apiKey: resolved.apiKey)`)
- Produces: `makeRequest(path:method:body:accept:endpoint:)` overload taking
  `ResolvedEndpoint` (the existing `profileID:` variant becomes
  `makeRequest(..., endpoint: try resolveTurnEndpoint(profileID: profileID))` — one
  resolution path). `getJSON`/`postJSON` gain `endpoint: ResolvedEndpoint? = nil`
  parameters; non-nil wins over `profileID`.
- Produces: `activeRunContext` becomes
  `(runID: String, profileID: UUID?, endpoint: ResolvedEndpoint)`;
  `setActiveRunContext(runID:profileID:endpoint:)`. `hardStopActiveRun`'s stop POST uses
  `context.endpoint` so a stop issued after a switch still addresses the run's actual
  host.

Threading map (every runs-turn request carries the snapshot; sessions-plane callers are
untouched):
- `streamTurnViaRuns`: after `ensureHopForTurn()`,
  `let endpoint = try resolveTurnEndpoint(profileID: hop.profileID)`; add
  `var capturedEndpoint: ResolvedEndpoint?` beside `capturedProfileID` for the catch
  path's recovery poll. Pass `endpoint:` to: `fetchRunsHistory`, the submit `postJSON`,
  the events `makeRequest`, both `deliverPolledTerminal` calls, and the catch-path
  recovery (`capturedEndpoint` — when nil, the throw happened before resolution and no
  request went out, so the recovery-poll guard on `runSubmitted` already keeps it dead).
- `syncTurnViaRuns`: same snapshot at top; thread to `fetchRunsHistory`, submit,
  `pollRunToTerminal`.
- `fetchRunsHistory(sessionId:profileID:endpoint:excludingTrailing:)` →
  `fetchSessionConversation` gains `endpoint: ResolvedEndpoint? = nil` and passes it to
  its `getJSON`.
- `pollRunToTerminal(runID:profileID:endpoint:budget:)` → `readRunStatus` likewise.
- The stale-hop retry recursion re-resolves on the fresh hop (correct — a NEW turn).

- [ ] **Step 3.1:** Harness: add `host: String` to `RecordedRequest`
  (`request.url?.host ?? "?"` in `startLoading`) — additive, no existing assertion
  changes.
- [ ] **Step 3.2: Write the failing test** in `RunsPlaneTransportTests`:
  `aMidTurnProfileSwitchCannotRedirectALiveTurnsRequests`. Client built with a mutable
  base-URL box:
  ```swift
  let baseURLBox = MutableBox("http://hermes.test")   // simple @MainActor final class
  // in makeClient-equivalent construction: baseURLProvider: { baseURLBox.value }
  ```
  Script: history GET 200 `{"data":[]}`; submit POST 202 `{"run_id":"run-pin"}`; events
  subscribe 503 (the existing subscribe-miss arm's shape, which drops the turn into the
  status poll); status GET: first call `{"status":"running"}`, second
  `{"status":"completed","output":"pinned","usage":{...}}` via `nextIndex(for:)`. In the
  script's submit handler, flip `baseURLBox.value = "http://hermes-b.test"` (the switch
  lands mid-turn, before every poll). Collect the turn; assert:
  ```swift
  let hosts = Set(RunsStubURLProtocol.requests().map(\.host))
  #expect(hosts == ["hermes.test"])            // every request, including all polls
  #expect(finishedPayload(updates)?.message.content == "pinned")
  ```
  Run: FAILS on current code (poll requests carry `hermes-b.test`).
- [ ] **Step 3.3:** Implement the threading map above.
- [ ] **Step 3.4:** Run the full runs suites:
  `-only-testing:TalariaTests/RunsPlaneTransportTests` (and its sibling suites in that
  file — they run together). Expected: all previous tests + the new one green; count
  MOVED by 1.
- [ ] **Step 3.5:** Commit:
  `fix(#285): runs turns pin their endpoint at birth — ResolvedEndpoint snapshot threaded through submit/events/status/history/stop, mid-turn switch cannot redirect a live turn (the #283 adjacency)`

### Task 4: Full verification + close-out

**Files:**
- Modify: `OPEN_ITEMS.md` (#285 entry: fix recorded, bars evidenced; #288 entry: fix
  landed, re-run now actionable), `RED-REPORT.md` (inversion addendum header)

- [ ] **Step 4.1:** Full gate, backgrounded, in the worktree:
  ```bash
  cd .claude/worktrees/t27-285-profile-atomicity && nohup scripts/mac/lane-gate.sh > /tmp/285-gate.log 2>&1 &
  ```
  Poll the log. Required: `GATE: PASS`, unit count MOVED from main's baseline (1798 + the
  new tests: 6 stayed, +2 store tests, +1 runs test → expect ~1801; read the actual
  number), 12 XCUITest, Release build succeeded.
- [ ] **Step 4.2:** Tracker close-out per THE CLOSE-OUT RULE, one commit:
  - #285 entry: status line → FIXED, with the three-part fix summary, bar-by-bar evidence
    (test names + gate line), the inversion note ("the RED tests now assert the fixed
    behavior; RED-REPORT.md preserves the pre-fix traces"), and the residual honesty
    note: 285-C's full-chain claim (hermesAPIKey/key box/stores/link all = C) is
    established by the serialization proof + code-reviewed checkpoints — the store-level
    arm is unit-tested, the AppContainer chain arm holds by construction (serialized
    handlers cannot interleave), no AppContainer unit harness exists.
  - #288 entry: add dated note — #285's fix shipped (superseded turns abandon before the
    pair POST; the orphan-mint path is closed), the post-fix re-run (288-C) is now
    actionable on Owen's schedule.
  - `RED-REPORT.md`: prepend a dated two-line note: the defect is fixed as of <commit>,
    the repro tests were inverted in place, this file preserves the pre-fix evidence.
- [ ] **Step 4.3:** Push the branch, draft the PR body (do NOT submit — external
  submissions wait on Owen's read of the exact text, standing rule). Hand Owen the push +
  PR command in a runnable block, plus the PR body text.

## Self-review notes

- Spec coverage: 285-A → Task 1 (inverted repros 1/2 + frozen context); 285-B → Task 1
  (inverted 3/3b + checkpoints); 285-C → Task 2 (two new tests + checkpoints); 285-D →
  Steps 1.5/2.4/3.4/4.1; runs adjacency → Task 3; falsified comment → Task 2; #288
  cross-link → Tasks 1 (pair checkpoint) + 4 (tracker note).
- Type consistency: `TurnContext` private to the link; `ResolvedEndpoint` internal
  (runs-path-visible); `DrainOutcome.superseded` handled in `start()`'s switch.
- The `.superseded` case is deliberately NOT surfaced in UI — a superseded turn is
  followed by the new profile's fresh loop; there is nothing for a user to act on.
