import Foundation
import Testing
@testable import Talaria

/// **The Connect Host state machine — bars 309-B2, B4 and B6.**
///
/// Everything here is measured on `ConnectHostModel` with a counting
/// environment, which is the point: the old pairing tests read a store
/// AFTERWARDS and asked "is the record still there", so a commit that happened
/// and was then undone would have passed them. These count WRITES.
@MainActor
struct ConnectHostTests {

    /// Records every side effect the model is allowed to have.
    @MainActor
    final class Recorder {
        var commits: [ConnectHostModel.Draft] = []
        var probes: [(gateway: String, key: String)] = []
        var rechecks = 0
        var disconnects = 0
        var activations: [UUID] = []
        var host: ConnectedHost?
        var roster: [ConnectHostRosterEntry] = []
        var disconnectOutcome: HostDisconnectOutcome = .forgottenAndHostTold
        var scriptedOutcome: HostProbeOutcome = .connected(latencyMilliseconds: 18, modelsSeen: 14)

        func environment() -> ConnectHostModel.Environment {
            ConnectHostModel.Environment(
                probe: { [weak self] gateway, key in
                    guard let self else { return .noAnswer(detail: "NO ANSWER") }
                    self.probes.append((gateway, key))
                    return self.scriptedOutcome
                },
                commit: { [weak self] draft, _ in
                    guard let self else { return }
                    self.commits.append(draft)
                    // A real commit makes the host readable afterwards; the
                    // double does the same so `presentation` can move.
                    self.host = ConnectedHost(
                        profileID: UUID(),
                        name: draft.resolvedName,
                        address: AppContainer.displayAddress(draft.trimmedGateway),
                        hasStoredKey: true,
                        lastAnsweredAt: .now,
                        modelsSeen: 14,
                        reachability: .reachable(milliseconds: 18)
                    )
                },
                currentHost: { [weak self] in self?.host },
                roster: { [weak self] in self?.roster ?? [] },
                recheckCommitted: { [weak self] in
                    guard let self else { return .noAnswer(detail: "NO ANSWER") }
                    self.rechecks += 1
                    return self.scriptedOutcome
                },
                disconnect: { [weak self] in
                    guard let self else { return .forgottenHostNotTold }
                    self.disconnects += 1
                    self.host = nil
                    return self.disconnectOutcome
                },
                activate: { [weak self] id in self?.activations.append(id) }
            )
        }
    }

    private func filled(_ model: ConnectHostModel) {
        model.draft.gatewayBaseURL = "http://ojamd.tailnet.test:8642"
        model.draft.apiKey = "real-key"
    }

    // MARK: - 309-B2: the eight states

    /// Each of the eight is reachable, and each is reachable ONLY under its
    /// own conditions. Written as one test because the property is about the
    /// SET — eight separate tests could each pass while two states overlapped.
    @Test func eachOfTheEightStatesIsReachableAndDistinct() async {
        let recorder = Recorder()
        let model = ConnectHostModel(environment: recorder.environment())

        // A1 — empty. Not an error: this is the local-brain resting state.
        #expect(model.presentation == .empty)

        // A2 — filled, not checked.
        filled(model)
        #expect(model.presentation == .ready)

        // A3 — checking, inline.
        recorder.scriptedOutcome = .connected(latencyMilliseconds: 18, modelsSeen: 14)
        let checking = Task { await model.checkAndConnect() }
        // (the double answers synchronously, so observe the settled state)
        await checking.value

        // A4 — connected.
        #expect(model.presentation == .connected)

        // B2 — connected but quiet. SAVED ≠ REACHABLE.
        recorder.host?.reachability = .noAnswer
        model.refreshFromStores()
        #expect(model.presentation == .quiet)

        // …and `notChecked` is NOT `quiet` — a cold launch has not asked yet,
        // and rendering that as "not answering" is #350's defect.
        recorder.host?.reachability = .notChecked
        model.refreshFromStores()
        #expect(model.presentation == .connected)

        // B3 — the roster.
        model.isShowingHostList = true
        #expect(model.presentation == .hostList)
        model.isShowingHostList = false

        // B4 — the disconnect confirm, which shadows everything else.
        model.isConfirmingDisconnect = true
        #expect(model.presentation == .disconnectConfirm)
        model.isConfirmingDisconnect = false

        // B1 — failed in place.
        recorder.host = nil
        model.refreshFromStores()
        recorder.scriptedOutcome = .keyRefused(latencyMilliseconds: 16)
        await model.checkAndConnect()
        #expect(model.presentation == .failed)
    }

    /// The A3 state is genuinely observable — the fields must stay on screen
    /// while the check runs, so `isChecking` has to be visible mid-flight
    /// rather than only in the settled result.
    @Test func theCheckingStateIsObservableWhileTheProbeIsInFlight() async {
        let gate = ProbeGate()
        let recorder = Recorder()
        var environment = recorder.environment()
        environment.probe = { _, _ in
            await gate.wait()
            return .connected(latencyMilliseconds: 18, modelsSeen: 14)
        }
        let model = ConnectHostModel(environment: environment)
        filled(model)

        let running = Task { await model.checkAndConnect() }
        let entered = await pollUntilTrue { model.presentation == .checking }
        #expect(entered, "the screen never showed the CHECKING state")
        #expect(model.ladder == .running)
        // The draft is still readable — design A3's "the fields dim but stay
        // put so a typo is still visible".
        #expect(model.draft.trimmedGateway == "http://ojamd.tailnet.test:8642")

        await gate.open()
        await running.value
        #expect(model.presentation == .connected)
    }

    // MARK: - 309-B4: commit-on-probe-pass

    @Test func aGreenProbeCommitsExactlyOnce() async {
        let recorder = Recorder()
        let model = ConnectHostModel(environment: recorder.environment())
        filled(model)
        recorder.scriptedOutcome = .connected(latencyMilliseconds: 18, modelsSeen: 14)

        await model.checkAndConnect()

        #expect(recorder.probes.count == 1)
        #expect(recorder.probes.first?.gateway == "http://ojamd.tailnet.test:8642")
        #expect(recorder.probes.first?.key == "real-key")
        #expect(recorder.commits.count == 1)
        #expect(model.host?.modelsSeen == 14)
    }

    /// **The bar, stated as a measurement.** Every failure arm: the probe ran,
    /// and NOTHING was written. "NOTHING WAS SAVED. YOU ARE STILL ON-DEVICE."
    /// is true of all three.
    @Test func aFailedProbeWritesNothingOnEveryArm() async {
        for outcome: HostProbeOutcome in [
            .noAnswer(detail: "TIMED OUT"),
            .keyRefused(latencyMilliseconds: 16),
            .notHermes(latencyMilliseconds: 9),
        ] {
            let recorder = Recorder()
            let model = ConnectHostModel(environment: recorder.environment())
            filled(model)
            recorder.scriptedOutcome = outcome

            await model.checkAndConnect()

            #expect(recorder.probes.count == 1, "the probe must still run for \(outcome)")
            #expect(recorder.commits.isEmpty, "a failed probe COMMITTED for \(outcome)")
            #expect(model.host == nil)
            #expect(model.presentation == .failed)
            #expect(model.failure == outcome)
        }
    }

    /// The guilty field is the one the failure blames, and only it — design
    /// B1's "only the guilty field is flagged".
    @Test func onlyTheGuiltyFieldIsFlagged() async {
        let cases: [(HostProbeOutcome, ConnectHostField)] = [
            (.keyRefused(latencyMilliseconds: 16), .apiKey),
            (.noAnswer(detail: "TIMED OUT"), .gatewayURL),
            (.notHermes(latencyMilliseconds: 9), .gatewayURL),
        ]
        for (outcome, expected) in cases {
            let recorder = Recorder()
            let model = ConnectHostModel(environment: recorder.environment())
            filled(model)
            recorder.scriptedOutcome = outcome
            await model.checkAndConnect()
            #expect(model.guiltyField == expected, "wrong field blamed for \(outcome)")
        }
    }

    /// A check cannot start without both values — so a half-filled form never
    /// costs a doomed request (#406's lesson, at the button rather than the
    /// keystroke).
    @Test func anIncompleteFormNeverProbes() async {
        let recorder = Recorder()
        let model = ConnectHostModel(environment: recorder.environment())

        model.draft.gatewayBaseURL = "http://ojamd.tailnet.test:8642"
        await model.checkAndConnect()
        #expect(recorder.probes.isEmpty, "probed with no key")

        model.draft.gatewayBaseURL = ""
        model.draft.apiKey = "real-key"
        await model.checkAndConnect()
        #expect(recorder.probes.isEmpty, "probed with no address")

        model.draft.gatewayBaseURL = "ojamd:8642" // no scheme
        await model.checkAndConnect()
        #expect(recorder.probes.isEmpty, "probed an address the app knows it cannot form")
    }

    /// "Check now" re-measures and writes nothing — the resting card's refresh
    /// must not be able to re-commit or clear credentials.
    @Test func checkNowMeasuresWithoutCommitting() async {
        let recorder = Recorder()
        let model = ConnectHostModel(environment: recorder.environment())
        filled(model)
        await model.checkAndConnect()
        let commitsAfterConnect = recorder.commits.count

        await model.recheck()

        #expect(recorder.rechecks == 1)
        #expect(recorder.commits.count == commitsAfterConnect, "Check now re-committed")
        #expect(recorder.probes.count == 1, "Check now used the candidate probe instead of the stored one")
    }

    /// The committed key is never handed back to the model — which is what
    /// makes "never shown again" structural rather than a promise the view
    /// keeps. `recheckCommitted` exists precisely so the key can stay in the
    /// Keychain.
    @Test func theCommittedKeyIsNeverReadBackIntoTheDraft() async {
        let recorder = Recorder()
        let model = ConnectHostModel(environment: recorder.environment())
        filled(model)
        await model.checkAndConnect()

        model.beginEditingAddress()
        #expect(model.draft.apiKey.isEmpty,
                "editing the address must not re-populate the key — re-entry replaces it wholesale")
        #expect(model.draft.gatewayBaseURL.contains("ojamd.tailnet.test"))
    }

    /// The reveal toggle is a PRE-COMMIT affordance; a green check closes it.
    @Test func revealingTheKeyDoesNotSurviveACommit() async {
        let recorder = Recorder()
        let model = ConnectHostModel(environment: recorder.environment())
        filled(model)
        model.isKeyRevealed = true

        await model.checkAndConnect()

        #expect(model.isKeyRevealed == false)
    }

    // MARK: - 309-B6: disconnect

    @Test func disconnectForgetsLocallyAndReportsWhetherTheHostWasTold() async {
        for outcome: HostDisconnectOutcome in [.forgottenAndHostTold, .forgottenHostNotTold] {
            let recorder = Recorder()
            let model = ConnectHostModel(environment: recorder.environment())
            filled(model)
            await model.checkAndConnect()
            #expect(model.host != nil)

            recorder.disconnectOutcome = outcome
            model.isConfirmingDisconnect = true
            await model.confirmDisconnect()

            // The LOCAL forget happens either way — that is the half the phone
            // controls, and it must not be contingent on the host answering.
            #expect(recorder.disconnects == 1)
            #expect(model.host == nil)
            #expect(model.presentation == .empty)
            #expect(model.draft == ConnectHostModel.Draft(), "the draft must not survive a disconnect")
            // …and the outcome is REPORTED rather than assumed.
            #expect(model.lastDisconnectOutcome == outcome)
        }
    }

    /// The copy follows the mechanism in all three measured states — the
    /// deferred-revoke decision, in one assertion.
    @Test func theDisconnectBlurbMatchesWhatTheAppCanActuallyDo() {
        func host(_ reachability: ConnectHostRosterEntry.Reachability) -> ConnectedHost {
            ConnectedHost(profileID: UUID(), name: "OJAMD", address: "ojamd:8642",
                          hasStoredKey: true, lastAnsweredAt: nil, modelsSeen: nil,
                          reachability: reachability)
        }

        // Reachable: the POST goes out now, so the promise is safe to make.
        let reachable = ConnectHostScreen.disconnectBlurb(for: host(.reachable(milliseconds: 18)))
        #expect(reachable.contains("tells OJAMD to drop this phone"))

        // Measured NOT answering: the promise would be a lie — the unpair is
        // authorised by the credential this action deletes, so it cannot be
        // queued for later.
        let quiet = ConnectHostScreen.disconnectBlurb(for: host(.noAnswer))
        #expect(quiet.contains("can't be told"))
        #expect(quiet.contains("hermes talaria unpair"))
        #expect(!quiet.contains("is told when it's next reachable"),
                "the design's deferred-revoke promise must not survive without the queue behind it")

        // Never asked: neither claim is earned.
        let unknown = ConnectHostScreen.disconnectBlurb(for: host(.notChecked))
        #expect(unknown.contains("if it answers"))
    }

    /// **The ported #94/#3 property: a disconnect touches ONE profile's
    /// slots.** Asserted on the key SET rather than on a store afterwards,
    /// because the set is where the isolation actually lives — every entry is
    /// derived from the target scope, so naming another profile's slot from
    /// that code is impossible rather than merely not done.
    @Test func disconnectClearsOnlyTheTargetProfilesCredentials() {
        let target = UUID()
        let bystander = UUID()

        let cleared = Set(AppContainer.disconnectClearedKeys(scope: target))

        // BOTH credential families — a surviving device token would let the
        // phone re-pair to the host it just left.
        #expect(cleared.contains(BackendProfileScopedKeys.gatewayAPIKey(target)))
        #expect(cleared.contains(BackendProfileScopedKeys.talariaDeviceToken(target)))
        #expect(cleared.contains(BackendProfileScopedKeys.talariaDeviceID(target)))
        #expect(cleared.count == 3, "the set widened — a disconnect took something else too")

        // Nothing belonging to another profile.
        for key in AppContainer.disconnectClearedKeys(scope: bystander) {
            #expect(!cleared.contains(key), "a disconnect names another profile's slot: \(key)")
        }
        // And nothing outside the two families: the shim token is user config,
        // and the installation identity is #133/#143's durable id.
        #expect(!cleared.contains(BackendProfileScopedKeys.shimToken(target)))
        #expect(!cleared.contains("talaria.installationID"))

        // The LEGACY (unscoped) profile is a real target too — Owen's own
        // install is that one, and a disconnect there must clear the bare key
        // strings rather than a scoped spelling of them.
        #expect(AppContainer.disconnectClearedKeys(scope: nil).contains("hermes.apiServerKey"))
    }

    // MARK: - The roster (B3)

    @Test func theRosterReportsMeasuredStatusOrSaysItHasNotAsked() async {
        let recorder = Recorder()
        let active = UUID()
        let dormant = UUID()
        recorder.roster = [
            ConnectHostRosterEntry(id: active, name: "OJAMD", address: "100.110.102.59:8642",
                                   isActive: true, keyState: .stored,
                                   reachability: .reachable(milliseconds: 18)),
            ConnectHostRosterEntry(id: dormant, name: "Dev box", address: "100.88.203.41:8642",
                                   isActive: false, keyState: .missing, reachability: .notChecked),
        ]
        let model = ConnectHostModel(environment: recorder.environment())

        let rows = model.rosterEntries
        #expect(rows.count == 2)
        #expect(rows[0].reachability.label == "REACHABLE · 18MS")
        #expect(rows[0].keyState.label == "KEY OK")
        // "NOT CHECKED" and "NO KEY" are honest states, not failures — the
        // design says so in as many words.
        #expect(rows[1].reachability.label == "NOT CHECKED")
        #expect(rows[1].keyState.label == "NO KEY")

        await model.activate(profileID: dormant)
        #expect(recorder.activations == [dormant])
    }

    // MARK: - Helpers

    /// A gate a probe can park on, so the in-flight state is observable
    /// without a sleep.
    private actor ProbeGate {
        private var continuations: [CheckedContinuation<Void, Never>] = []
        private var opened = false

        func wait() async {
            if opened { return }
            await withCheckedContinuation { continuations.append($0) }
        }

        func open() {
            opened = true
            let waiting = continuations
            continuations = []
            for continuation in waiting { continuation.resume() }
        }
    }

    private func pollUntilTrue(
        timeout: Duration = .seconds(3),
        _ condition: @MainActor () -> Bool
    ) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }
}
