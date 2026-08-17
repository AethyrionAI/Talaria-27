# #269-A Plugin-Link Honesty Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The PLUGIN LINK row and the About status panel render measured link state (the 401-vs-503 events-route probe) instead of keychain assertions, and the retired relay stops reading permanent red (bars 269-A-A/B/C/E/F; #353(b)).

**Architecture:** A pure observation/composition unit (new file, table-tested), a side-effect-free unauthenticated probe on `TalariaPlatformLink` (wire-tested through the existing `StubURLProtocol` fixture), then two consuming screens. Five tasks, tree green at every commit.

**Tech Stack:** SwiftUI / Swift Testing, xcodegen, `scripts/mac/lane-gate.sh`.

## Global Constraints

- Spec: `planning/superpowers/2026-08-16-269A-plugin-link-honesty-design.md`; bars in the #269 entry (A-A adapted + A-F, dated 2026-08-16).
- `DEVELOPER_DIR=/Applications/Xcode-beta5.app/Contents/Developer`; `xcodegen generate` after file adds, pbxproj committed same commit.
- **Never touch:** the drawer footer / settings grid strip (#350), `PairingStore`, voice, the plugin repo, `PhoneQueryResponder`.
- The probe is UNAUTHENTICATED and side-effect-free — no bearer, no TurnContext, no re-pair, no Keychain writes.
- Copy vocabulary is closed (269-A-C): `—`, `LIVE · PAIRED`, `LIVE · NOT PAIRED`, `NOT LIVE`, `HOST UNREACHABLE`, `OFFLINE` (legacy relay). No string names a cause.
- Branch `claude/t27-269A-plugin-link-honesty` off synced `origin/main`; PR opens DO-NOT-MERGE.
- Suite runs on CC-lane-1 (UDID `79402942-3DD4-4187-9710-044C784840FE`), TCC calendar+reminders granted immediately before each run.

---

### Task 1: The observation/composition unit (pure, table-tested)

**Files:**
- Create: `Talaria/Services/Live/TalariaLinkObservation.swift`
- Test: `TalariaTests/TalariaLinkObservationTests.swift` (new)

**Interfaces:**
- Produces: `TalariaLinkObservation` (`.adapterLive(status:)`, `.adapterAbsent(status:)`, `.indeterminate(status:)`, `.hostUnreachable`, `.notConfigured`; `static func classify(status: Int) -> TalariaLinkObservation`); `TalariaLinkDisplayState` (`.unknown/.livePaired/.liveNotPaired/.notLive/.hostUnreachable`; `var label: String`; `static func compose(observation: TalariaLinkObservation?, hasDeviceToken: Bool) -> TalariaLinkDisplayState`); `TalariaLinkObservation.legacyRelayReadsAsError(pluginLive: Bool, relayReachable: Bool) -> Bool`.

- [ ] **Step 1: Write the failing tests** (whole new file):

```swift
import Testing
@testable import Talaria

/// #269-A: the honest-link vocabulary. Every case is a table row — the
/// classifier, the composer, and the #353(b) severity rule are pure.
struct TalariaLinkObservationTests {

    @Test func classifierMapsTheVerifiedSeam() {
        #expect(TalariaLinkObservation.classify(status: 401) == .adapterLive(status: 401))
        #expect(TalariaLinkObservation.classify(status: 503) == .adapterAbsent(status: 503))
        // An unexpected status licenses nothing (269-A-C).
        #expect(TalariaLinkObservation.classify(status: 418) == .indeterminate(status: 418))
        #expect(TalariaLinkObservation.classify(status: 200) == .indeterminate(status: 200))
    }

    @Test func composeNeverLetsTheTokenDecideAlone() {
        // 269-A-B: a token + an absent adapter is NOT LIVE, never PAIRED.
        #expect(TalariaLinkDisplayState.compose(
            observation: .adapterAbsent(status: 503), hasDeviceToken: true) == .notLive)
        #expect(TalariaLinkDisplayState.compose(
            observation: .adapterLive(status: 401), hasDeviceToken: true) == .livePaired)
        #expect(TalariaLinkDisplayState.compose(
            observation: .adapterLive(status: 401), hasDeviceToken: false) == .liveNotPaired)
        #expect(TalariaLinkDisplayState.compose(
            observation: .hostUnreachable, hasDeviceToken: true) == .hostUnreachable)
        #expect(TalariaLinkDisplayState.compose(
            observation: .indeterminate(status: 200), hasDeviceToken: true) == .unknown)
        #expect(TalariaLinkDisplayState.compose(
            observation: .notConfigured, hasDeviceToken: true) == .unknown)
        #expect(TalariaLinkDisplayState.compose(
            observation: nil, hasDeviceToken: true) == .unknown)
    }

    @Test func labelsAreTheClosedVocabulary() {
        #expect(TalariaLinkDisplayState.unknown.label == "—")
        #expect(TalariaLinkDisplayState.livePaired.label == "LIVE · PAIRED")
        #expect(TalariaLinkDisplayState.liveNotPaired.label == "LIVE · NOT PAIRED")
        #expect(TalariaLinkDisplayState.notLive.label == "NOT LIVE")
        #expect(TalariaLinkDisplayState.hostUnreachable.label == "HOST UNREACHABLE")
    }

    @Test func legacyRelaySeverityDerivesFromMeasurementOnly() {
        // #353(b): red is reserved for "the phone-facing channel is down."
        #expect(TalariaLinkObservation.legacyRelayReadsAsError(pluginLive: true, relayReachable: false) == false)
        #expect(TalariaLinkObservation.legacyRelayReadsAsError(pluginLive: false, relayReachable: false) == true)
        #expect(TalariaLinkObservation.legacyRelayReadsAsError(pluginLive: true, relayReachable: true) == false)
        #expect(TalariaLinkObservation.legacyRelayReadsAsError(pluginLive: false, relayReachable: true) == false)
    }
}
```

- [ ] **Step 2: xcodegen + run to verify FAIL** — `xcodegen generate`, then targeted run (`'-only-testing:TalariaTests/TalariaLinkObservationTests'`): expected compile failure ("cannot find TalariaLinkObservation").

- [ ] **Step 3: Implement** (whole new file):

```swift
import Foundation

/// #269-A: what one probe of the talaria events route actually observed.
/// The seam (verified live 2026-08-09, re-proven on OJAMD during #271):
/// an UNAUTHENTICATED POST answers 401 when the adapter is registered
/// (auth rejection precedes verb dispatch — nothing drains) and 503 when
/// the platform is absent. "Never installed", "on disk but not enabled",
/// and "enabled but not restarted" are all 503 — indistinguishable here
/// by design, which is why no case names a cause (the agent narrates WHY,
/// the app verifies WHETHER).
enum TalariaLinkObservation: Equatable {
    case adapterLive(status: Int)
    case adapterAbsent(status: Int)
    case indeterminate(status: Int)
    case hostUnreachable
    case notConfigured

    static func classify(status: Int) -> TalariaLinkObservation {
        switch status {
        case 401: .adapterLive(status: status)
        case 503: .adapterAbsent(status: status)
        default: .indeterminate(status: status)
        }
    }

    /// #353(b): the legacy relay rows read as an ERROR only when the relay
    /// is unreachable AND the plugin channel is not measured live — red is
    /// reserved for "the phone-facing channel is down," never for a tier
    /// whose replacement is answering.
    static func legacyRelayReadsAsError(pluginLive: Bool, relayReachable: Bool) -> Bool {
        !relayReachable && !pluginLive
    }
}

/// The display vocabulary — closed on purpose (269-A-C): every string maps
/// to an observation; none names a cause the app cannot distinguish.
enum TalariaLinkDisplayState: Equatable {
    case unknown
    case livePaired
    case liveNotPaired
    case notLive
    case hostUnreachable

    var label: String {
        switch self {
        case .unknown: "—"
        case .livePaired: "LIVE · PAIRED"
        case .liveNotPaired: "LIVE · NOT PAIRED"
        case .notLive: "NOT LIVE"
        case .hostUnreachable: "HOST UNREACHABLE"
        }
    }

    /// Two facts, composed, never conflated: the credential is only ever
    /// the SECOND word, and only when the observation earned the first.
    static func compose(
        observation: TalariaLinkObservation?,
        hasDeviceToken: Bool
    ) -> TalariaLinkDisplayState {
        switch observation {
        case .adapterLive: hasDeviceToken ? .livePaired : .liveNotPaired
        case .adapterAbsent: .notLive
        case .hostUnreachable: .hostUnreachable
        case .indeterminate, .notConfigured, nil: .unknown
        }
    }
}
```

- [ ] **Step 4: Run to verify PASS** (same targeted invocation, trailing-`()`-per-test not needed at suite granularity; confirm 4 tests ran).
- [ ] **Step 5: Commit** — `git add Talaria/Services/Live/TalariaLinkObservation.swift TalariaTests/TalariaLinkObservationTests.swift Talaria.xcodeproj/project.pbxproj && git commit -m "feat(#269-A): TalariaLinkObservation — classifier, composer, #353(b) severity rule (table-tested)"`

---

### Task 2: `probeLinkState()` on TalariaPlatformLink (wire-tested)

**Files:**
- Modify: `Talaria/Services/Live/TalariaPlatformLink.swift` (add near the Transport MARK, `:436`)
- Test: `TalariaTests/TalariaPlatformLinkTests.swift` (append; reuse `makeLink` `:54-74` + `StubURLProtocol`)

**Interfaces:**
- Consumes: Task 1's `TalariaLinkObservation`.
- Produces: `func probeLinkState() async -> TalariaLinkObservation` on `TalariaPlatformLink`.

- [ ] **Step 1: Write the failing tests** (append to the file; `defer { StubURLProtocol.handler = nil }` per the file's convention):

```swift
    // MARK: - Link probe (#269-A)

    @Test func probeClassifies401AsAdapterLiveAndSendsNoBearer() async {
        defer { StubURLProtocol.handler = nil }
        let recorder = RequestRecorder()
        let link = await makeLink(secureStore: MockSecureStore()) { request in
            recorder.record(request.value(forHTTPHeaderField: "Authorization") ?? "NONE")
            return (401, Data(#"{"error":"missing_bearer"}"#.utf8))
        }
        #expect(await link.probeLinkState() == .adapterLive(status: 401))
        #expect(recorder.all == ["NONE"])  // unauthenticated by design
    }

    @Test func probeClassifies503AsAdapterAbsent() async {
        defer { StubURLProtocol.handler = nil }
        let link = await makeLink(secureStore: MockSecureStore()) { _ in
            (503, Data(#"{"error":"platform_unavailable"}"#.utf8))
        }
        #expect(await link.probeLinkState() == .adapterAbsent(status: 503))
    }

    @Test func probeClassifiesUnexpectedStatusAsIndeterminate() async {
        defer { StubURLProtocol.handler = nil }
        let link = await makeLink(secureStore: MockSecureStore()) { _ in
            (418, Data())
        }
        #expect(await link.probeLinkState() == .indeterminate(status: 418))
    }

    @Test func probeClassifiesTransportFailureAsHostUnreachable() async {
        defer { StubURLProtocol.handler = nil }
        // The file's stub convention: a nil handler result fails the load.
        let link = await makeLink(secureStore: MockSecureStore()) { _ in nil }
        #expect(await link.probeLinkState() == .hostUnreachable)
    }

    @Test func probeWithNoGatewayURLIsNotConfigured() async {
        defer { StubURLProtocol.handler = nil }
        StubURLProtocol.handler = { _ in (401, Data()) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let link = TalariaPlatformLink(
            gatewayBaseURL: { nil },
            installID: { "install-abc" },
            deviceName: { "TestPhone" },
            credentialScopeID: { Self.scope },
            secureStore: MockSecureStore(),
            responder: nil,
            onItemsReceived: { _ in },
            session: URLSession(configuration: configuration)
        )
        #expect(await link.probeLinkState() == .notConfigured)
    }
```

(Adapt the recorder/`makeLink` details to the file's actual helpers if their shapes differ — `RequestRecorder` exists at `:28-47`; if the stub cannot return nil, use its existing transport-failure convention, found where the drain's `.failed` case is tested.)

- [ ] **Step 2: Run to verify FAIL** — compile failure ("no member probeLinkState").
- [ ] **Step 3: Implement** (in TalariaPlatformLink, after the `post` helper):

```swift
    // MARK: - Link probe (#269-A)

    /// Short and dedicated: a probe answers a screen's `.task`, not a
    /// long-poll.
    private static let probeTimeout: TimeInterval = 4

    /// Read-only, side-effect-free liveness probe — an UNAUTHENTICATED POST
    /// to the events route. Auth rejection precedes verb dispatch, so a
    /// registered adapter answers 401 without draining or acking anything;
    /// an absent platform answers 503 (the verified 2026-08-09 seam).
    /// Deliberately NOT a TurnContext turn: it never re-pairs, never touches
    /// the Keychain, and cannot be superseded into side effects because it
    /// has none.
    func probeLinkState() async -> TalariaLinkObservation {
        guard var base = gatewayBaseURL(), !base.isEmpty else { return .notConfigured }
        while base.hasSuffix("/") { base.removeLast() }
        guard let url = URL(string: base + Self.eventsPath) else { return .notConfigured }
        var request = URLRequest(url: url, timeoutInterval: Self.probeTimeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{}".utf8)
        guard let (_, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse
        else { return .hostUnreachable }
        return TalariaLinkObservation.classify(status: http.statusCode)
    }
```

- [ ] **Step 4: Run to verify PASS** (targeted TalariaPlatformLinkTests; count moved +5).
- [ ] **Step 5: Commit** — `git add Talaria/Services/Live/TalariaPlatformLink.swift TalariaTests/TalariaPlatformLinkTests.swift && git commit -m "feat(#269-A): side-effect-free unauthenticated link probe on TalariaPlatformLink (wire-tested 401/503/418/transport/unconfigured)"`

---

### Task 3: Server screen PLUGIN LINK row consumes the composed state

**Files:**
- Modify: `Talaria/Features/Settings/ServerSettingsScreen.swift` (`TalariaLinkState` enum `:46-69` deleted; `@State` `:84`; `talariaLinkPanel`/`talariaLinkColor`/`refreshTalariaLinkState` `:503-547`)
- Test: wherever `TalariaLinkState` is pinned (`rg -n "TalariaLinkState" TalariaTests/` — migrate each assertion to the Task-1 compose table if it pins behavior the table already covers, delete if duplicate; name each disposition in the commit message)

**Interfaces:**
- Consumes: `TalariaLinkDisplayState.compose`, `container.talariaPlatformLink?.probeLinkState()`, `container.talariaDeviceToken(for:)`.

- [ ] **Step 1: Delete the `TalariaLinkState` enum** (`:46-69`) and retype the state: `@State private var talariaLink: TalariaLinkDisplayState = .unknown`.
- [ ] **Step 2: Rewrite the refresh** (comment updated — the old one described the keychain-read decay; the new one adds the probe):

```swift
    private func refreshTalariaLinkState() async {
        // Drop to "—" while the reads are in flight: on a profile switch the
        // held value describes the profile we just left (#269-A keeps the
        // honest-decay behavior and adds the probe half).
        talariaLink = .unknown
        guard let profile = container.profilesStore?.activeProfile else { return }
        async let token = container.talariaDeviceToken(for: profile)
        async let observation = container.talariaPlatformLink?.probeLinkState()
        talariaLink = TalariaLinkDisplayState.compose(
            observation: await observation,
            hasDeviceToken: (await token)?.isEmpty == false
        )
    }
```

- [ ] **Step 3: Update `talariaLinkColor`:**

```swift
    private var talariaLinkColor: Color {
        switch talariaLink {
        case .livePaired: Design.Brand.accent
        case .notLive: Design.Brand.forge
        case .unknown, .liveNotPaired, .hostUnreachable: Design.Colors.mutedForeground
        }
    }
```

- [ ] **Step 4: Migrate/delete the old enum's tests** per the Files note; compile + full unit suite green; count stated.
- [ ] **Step 5: Commit** — `git commit -m "feat(#269-A): PLUGIN LINK renders measured state — probe + credential composed, keychain never decides alone (269-A-B)"`

---

### Task 4: About page — Plugin Link row + Legacy Relay regroup (#353(b))

**Files:**
- Modify: `Talaria/Features/Settings/AboutSettingsContent.swift` (statusPanel `:89-105`, relayStatus `:137-144`, `.task` `:57-61`)

**Interfaces:**
- Consumes: Task 1's types, `probeLinkState()`, `container.talariaDeviceToken(for:)`, existing `statusRow`/`RowStatus`/`rowDivider`.

- [ ] **Step 1: Add state + probe to `.task`:**

```swift
    @State private var pluginLink: TalariaLinkDisplayState = .unknown
```

and in `.task` (after `reloadCapabilities`):

```swift
            if let profile = container.profilesStore?.activeProfile {
                async let token = container.talariaDeviceToken(for: profile)
                async let observation = container.talariaPlatformLink?.probeLinkState()
                pluginLink = TalariaLinkDisplayState.compose(
                    observation: await observation,
                    hasDeviceToken: (await token)?.isEmpty == false
                )
            }
```

- [ ] **Step 2: Restructure the panels.** `statusPanel` keeps Hermes API + new Plugin Link + Location; Relay Link + Relay Identity move to a new section directly below:

```swift
    private var statusPanel: some View {
        VStack(spacing: 0) {
            statusRow("Hermes API", hermesAPIStatus)
            rowDivider
            statusRow("Plugin Link", pluginLinkStatus)
            rowDivider
            statusRow("Location", locationStatus)
        }
        .hudPanel(
            cornerRadius: Design.CornerRadius.lg,
            borderColor: Design.Colors.accentTint(0.12),
            fill: Design.Colors.background.opacity(0.5),
            innerGlow: false
        )
    }

    private var pluginLinkStatus: RowStatus {
        switch pluginLink {
        case .livePaired:
            RowStatus(text: pluginLink.label, color: Design.Brand.accent, blinks: false)
        case .notLive:
            RowStatus(text: pluginLink.label, color: Design.Brand.forge, blinks: false)
        case .unknown, .liveNotPaired, .hostUnreachable:
            RowStatus(text: pluginLink.label, color: Design.Colors.mutedForeground, blinks: false)
        }
    }

    // MARK: Legacy relay (#353(b))
    //
    // The relay is a retiring tier (#346/#223). Red here is reserved for
    // "the phone-facing channel is down": with the plugin link measured
    // LIVE, an unreachable relay renders muted OFFLINE — a fact, not an
    // alarm. With the plugin NOT live the relay is the only channel and an
    // outage stays red. Derivation:
    // TalariaLinkObservation.legacyRelayReadsAsError (table-tested).

    private var legacyRelayPanel: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            MonoLabel("// Legacy Relay", size: 10, tracking: Design.Tracking.monoXWide,
                      color: Design.Colors.mutedForeground)

            VStack(spacing: 0) {
                statusRow("Relay Link", relayStatus)
                rowDivider
                statusRow("Relay Identity", identityStatus)
            }
            .hudPanel(
                cornerRadius: Design.CornerRadius.lg,
                borderColor: Design.Colors.accentTint(0.12),
                fill: Design.Colors.background.opacity(0.5),
                innerGlow: false
            )
        }
    }
```

Insert `legacyRelayPanel` in `body` between `statusPanel` and `voicePanel`.

- [ ] **Step 3: Derive relay severity.** Replace `relayStatus` (`:137-144`):

```swift
    private var relayStatus: RowStatus {
        let pluginLive = pluginLink == .livePaired || pluginLink == .liveNotPaired
        switch sessionStore.state.connectionStatus {
        case .connected:
            return RowStatus(text: "LINKED", color: Design.Brand.accent, blinks: false)
        case .connecting:
            return RowStatus(text: "CONNECTING", color: Design.Brand.forge, blinks: true)
        case .disconnected, .error:
            if TalariaLinkObservation.legacyRelayReadsAsError(
                pluginLive: pluginLive, relayReachable: false) {
                return RowStatus(text: "ERROR", color: Design.Colors.danger, blinks: false)
            }
            return RowStatus(text: "OFFLINE", color: Design.Colors.mutedForeground, blinks: false)
        }
    }
```

(The old `.disconnected` STANDBY/blinking arm collapses into the derived pair — a permanently-blinking forge pip against a retired relay was the same training-to-ignore cost in miniature.)

- [ ] **Step 4: Compile + full unit suite green.**
- [ ] **Step 5: Commit** — `git commit -m "feat(#269-A,#353): About gains a measured Plugin Link row; relay rows regroup as Legacy Relay with derived severity (269-A-F)"`

---

### Task 5: Live 401 arm, gate, PR

- [ ] **Step 1: Live arm (269-A-A, read-only, no gate needed):**

```bash
curl -s -o /dev/null -w '%{http_code}\n' -X POST -H 'Content-Type: application/json' -d '{}' http://100.110.102.59:8642/api/platforms/talaria/events
```

Expected: `401`. Record the output verbatim in the PR body. Also the refused-port arm: same command against `http://100.110.102.59:12399` → curl error (transport), matching `.hostUnreachable`.

- [ ] **Step 2: Gate** — TCC grants, then `TALARIA_SIM_NAME=CC-lane-1 nohup scripts/mac/lane-gate.sh > /tmp/gate-269A.log 2>&1 &`; poll for `GATE: PASS`; count stated and MOVED (up: +9-ish new tests, minus any migrated `TalariaLinkState` pins — reconcile exactly).
- [ ] **Step 3: PR** — title `feat(#269-A): plugin-link honesty — measured link state + legacy-relay severity (#353(b))`; body: bars A-A(adapted)/B/C/E/F with per-bar evidence, the closed copy vocabulary, the live-arm outputs, count reconciliation, **DO NOT MERGE — awaiting Owen's review**. Report URL and stop. Device arm (A-F screenshot: no red relay row on the current rig) runs post-merge with Owen.

---

## Self-review record

- Spec coverage: probe (T2), state model (T1), Server screen (T3), About + #353(b) (T4), testing incl. stubbed 503/transport + live 401 (T1/T2/T5), out-of-scope list enforced by Global Constraints. Bars: A-A→T1/T2/T5, A-B→T1/T3, A-C→T1's closed vocabulary + T3/T4 consuming only `label`, A-E→T5, A-F→T1 (severity table) + T4 + post-merge screenshot.
- Verify-at-implementation points (named, not placeholders): the stub's transport-failure convention (T2 Step 1 note), `TalariaLinkState` test pins (T3 Step 4 grep), `RequestRecorder`'s exact shape.
- Type consistency: `probeLinkState() async -> TalariaLinkObservation` and `compose(observation:hasDeviceToken:)` used identically in T2/T3/T4.
