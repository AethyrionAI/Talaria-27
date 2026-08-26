import Foundation
import os

/// The shared confirm gate for side-effecting device tools (#29). Authority
/// rule (shipped for AlarmKit in #16, now generalized): the model can NEVER
/// silently mutate the phone — every write is staged, rendered as a card in
/// the chat transcript, and executed only after the user's explicit approve.
///
/// FM tool calls are async, so the gate is plain structured concurrency: the
/// tool suspends on an awaited continuation until the user decides. Deny
/// resolves the tool with a "user declined" result the model reacts to
/// conversationally. The gate defaults CLOSED: if the app dies with a
/// confirmation pending, the continuation dies with the process and nothing
/// was ever created.
@MainActor
@Observable
final class ToolConfirmationCenter {

    /// One editable line on the confirmation card. `key` is what the tool
    /// reads back after approval, so edited values are what get created.
    struct Field: Identifiable {
        let id = UUID()
        let key: String
        let label: String
        var value: String
    }

    struct PendingConfirmation: Identifiable {
        let id = UUID()
        /// e.g. "Create this reminder?"
        let title: String
        /// One-line consequence statement, e.g. "It will ring through Silent mode."
        let detail: String?
        /// #233: forge-amber warning line, e.g. "EARLY MORNING — 4:00 AM".
        /// Nil on every card that stages nothing unusual.
        let caution: String?
        var fields: [Field]
    }

    enum Decision: Sendable {
        case approved([String: String])
        case declined
    }

    private static let logger = Logger(subsystem: "org.aethyrion.talaria", category: "ToolConfirmationCenter")

    /// The card the chat transcript renders. Nil when the gate is idle.
    private(set) var pending: PendingConfirmation?
    private var continuation: CheckedContinuation<Decision, Never>?

    /// #224 Phase 0: the gate's approval mode, read through a provider so
    /// this class keeps no settings dependency (the provider-closure
    /// pattern #283's transport seam established, since retired by #382). The key is
    /// GLOBAL — `UserSettings.approvalMode`, ruling 2 — because the gate
    /// governs THIS PHONE's writes, which happen identically whichever host a
    /// turn came from and happen at all when no host is configured.
    ///
    /// `.manual` is the only value the settings layer can produce in this
    /// build (`ApprovalMode.selectable == [.manual]`, and the decoder clamps
    /// through `ApprovalMode.resolved(_:)`), so the disposition below is
    /// always `.card` and the gate behaves exactly as it did before #224.
    /// Phase 1 is the lane that gives `.autoApprove` and `.refuse` real
    /// paths; this is the single production call site it edits.
    @ObservationIgnored var modeProvider: @MainActor () -> ApprovalMode = { .manual }

    /// #323-D: whether App Lock is currently COVERING the app. When it is,
    /// the lock outranks the mode and this gate stages the card without ever
    /// asking `modeProvider` what it would rather do.
    ///
    /// **Why short-circuit BEFORE the provider instead of after it.** Today
    /// `.manual` is the only mode the settings layer can produce, so a gate
    /// placed after the consult would be unobservable — it would pass for the
    /// wrong reason and keep passing after someone deleted it. Reading the
    /// lock first makes the property testable NOW, against a mode (#224
    /// Phase 1's `.autoApprove`) that does not yet ship: bar 323-D spies on
    /// the provider and goes red the moment this line is removed.
    ///
    /// That is the 2026-08-18 ruling's *"a subsystem nobody wired becomes
    /// structurally impossible"* applied before the subsystem exists — which
    /// is the only time it is cheap.
    @ObservationIgnored var lockStateProvider: @MainActor () -> Bool = { false }

    #if DEBUG
    /// #196 battery: headless sessions can never answer a card, and the
    /// continuation is deliberately non-cancellable — so the rate battery
    /// flips this on for its run. Every action-tool grab resolves instantly
    /// as .declined, which doubles as recovery-clause measurement (does the
    /// model answer anyway, or loop the denial?). Never set outside the
    /// battery.
    var autoDeclineForBattery = false

    /// #200 action battery: the inverse mode — every staged confirmation
    /// resolves instantly as .approved with the staged values, so an
    /// APPROPRIATE create actually executes (real EventKit/AlarmKit writes).
    /// Mutually exclusive with `autoDeclineForBattery` by launcher
    /// discipline; if both are ever set, decline wins (fail-safe:
    /// never-create, matching the gate's default-closed design). Never set
    /// outside the battery.
    ///
    /// `@ObservationIgnored` because no view reads it (only tool code does)
    /// and because #331 hangs a `didSet` off it — the macro's tracked storage
    /// and property observers do not mix.
    @ObservationIgnored var autoAcceptForBattery = false {
        didSet { Self.batteryWritesArmed = autoAcceptForBattery }
    }

    /// #331: a process-wide mirror of the armed flag. The containment gate
    /// lives in `LocalChatBackend.beginBatteryRun`, which is a static with no
    /// reference to this instance, and it has to know whether the run about
    /// to start will WRITE — a battery that only measures text must not be
    /// refused for want of calendar access it never needs.
    nonisolated(unsafe) static var batteryWritesArmed = false

    /// **#372(a) — how many times this process has produced a DECLINE.**
    ///
    /// #372 filed that the shipping blurb's decline half — *"if they decline,
    /// accept that gracefully"* — **has never been exercised by a measurement**,
    /// and the reason it went unnoticed for so long is that no instrument could
    /// SEE a decline. `toolCallsAdmitted` counts calls the governor let
    /// through, which is a different fact: a trial can admit a call and still
    /// never reach the gate, and a trial can reach the gate under a mode that
    /// approves. Reading "the half was exercised" off the call count is the
    /// #215 error one layer down — inferring the configuration from a number
    /// that does not carry it.
    ///
    /// So this counts the thing itself, at every site that can produce
    /// `.declined`, and instruments read a per-trial DELTA off it. A trial with
    /// a zero delta did not exercise the decline half, and per #215 must not be
    /// scored as though it had — which is what
    /// `LocalChatBackend.declineHalfRow` enforces.
    ///
    /// `nonisolated(unsafe)` for the same reason `batteryWritesArmed` is: the
    /// readers are `nonisolated` static instrument helpers with no reference to
    /// this instance. Monotonic within a process; instruments never reset it,
    /// they subtract.
    nonisolated(unsafe) static var batteryDeclineCount = 0

    /// The same count for THIS gate only. Instruments cannot use it — they
    /// reach the gate through tools they do not own — but tests can, and that
    /// is the point: an exact-equality assertion against the process-global
    /// counter is a flake generator, because Swift Testing runs suites in
    /// parallel and another suite's decline lands in the window. The negative
    /// control ("an approval must not move it") is only writable against a
    /// count nothing else can touch.
    private(set) var declineCount = 0

    /// The ONE place either counter moves. Every `.declined` this class can
    /// produce routes through here — the battery auto-decline, the defensive
    /// second-request decline, and the user's own `decline()` — because a
    /// counter incremented at two of three sites reports a lower rate than the
    /// truth and reads exactly like a clean result.
    ///
    /// Both counters move together in one statement pair, so the instance count
    /// the tests assert on and the static the instruments read cannot drift
    /// apart — a test passing against a mirror that had stopped mirroring is
    /// the failure this shape exists to make impossible.
    private func noteDecline() {
        declineCount += 1
        Self.batteryDeclineCount += 1
    }

    /// #200: every artifact created under auto-accept carries this marker —
    /// injected into the "title"/"request" field at approval — so the run
    /// teardown can find and delete everything the battery created.
    /// `nonisolated` because the #200F echo cleaner below reads it from
    /// nonisolated tool code — an immutable String constant is safe from
    /// any context.
    nonisolated static let batteryArtifactMarker = "[T27-battery]"
    #endif

    /// #200F: echo cleaner for tool SUCCESS texts. Auto-accept injects the
    /// reap marker into the approved values so the STORE WRITE is findable —
    /// but #200E caught the success text carrying it back into the model's
    /// context (armed/haiku/t5 replied "[T27-battery] ,"), contaminating
    /// later turns through the transcript. Tools clean every echoed value
    /// through this before building their result string: the artifact keeps
    /// the marker, the model never sees it. Identity in release builds and
    /// on unmarked input, so normal-mode echoes (including user edits) pass
    /// through byte-for-byte.
    nonisolated static func strippingBatteryMarker(_ value: String) -> String {
        #if DEBUG
        guard value.contains(batteryArtifactMarker) else { return value }
        // Mirror the injection forms — prefix ("MARKER title"), suffix
        // ("request MARKER"), and mid-string when a marked label lands
        // inside a larger echo (the alarm summary) — collapsing the one
        // adjacent space the injection added.
        return value
            .replacingOccurrences(of: "\(batteryArtifactMarker) ", with: "")
            .replacingOccurrences(of: " \(batteryArtifactMarker)", with: "")
            .replacingOccurrences(of: batteryArtifactMarker, with: "")
        #else
        return value
        #endif
    }

    /// Stages a confirmation and suspends the calling tool until the user
    /// decides. Tools run serially per session; if a second request somehow
    /// arrives while one is pending, it auto-declines (defensive — the gate
    /// never queues silently).
    func requestConfirmation(title: String, detail: String? = nil, caution: String? = nil, fields: [Field]) async -> Decision {
        #if DEBUG
        // Decline is checked FIRST: if both battery flags are ever set the
        // fail-safe direction is never-create.
        if autoDeclineForBattery {
            Self.logger.notice("confirmation auto-declined (#196 battery): \(title, privacy: .public)")
            noteDecline()
            recordBatteryOutcome("declined")
            return .declined
        }
        if autoAcceptForBattery {
            var values = Dictionary(uniqueKeysWithValues: fields.map { ($0.key, $0.value) })
            // Tag the created artifact for the teardown reap: titles get the
            // marker as a prefix; the alarm "request" gets it as a SUFFIX,
            // because the alarm grammar needs its time token first and
            // everything after the time becomes the label.
            for key in ["title", "request"] {
                if let value = values[key], !value.isEmpty {
                    values[key] = key == "title"
                        ? "\(Self.batteryArtifactMarker) \(value)"
                        : "\(value) \(Self.batteryArtifactMarker)"
                }
            }
            Self.logger.notice("confirmation auto-accepted (#200 battery): \(title, privacy: .public)")
            recordBatteryOutcome("accepted")
            return .approved(values)
        }
        #endif
        // #224 Phase 0. `.card` is the only disposition with an
        // implementation in this build, and the only one settings can
        // produce. If a later lane arms a mode without also building its
        // handling, the gate must NOT act on it: it stages the card anyway
        // and says so in the log. That is the default-CLOSED direction this
        // gate was designed around — an unhandled mode costs a prompt, never
        // an unapproved write.
        if lockStateProvider() {
            // #323-D. Nothing auto-resolves behind the cover — not an
            // approve, not a refuse. The card stages and the tool suspends
            // exactly as it does under `.manual`, so the user answers it when
            // they unlock and see it. That is the ruling's in-flight policy
            // (work finishes, the user still decides), not a refusal.
            Self.logger.notice("approval staged while App Lock covers the app — mode NOT consulted (#323-D)")
        } else {
            let disposition = modeProvider().disposition(hasCaution: caution != nil)
            if disposition != .card {
                Self.logger.error("approval mode produced \(disposition.rawValue, privacy: .public) — this build ships no handling for it; staging the card")
            }
        }
        guard continuation == nil else {
            Self.logger.warning("confirmation requested while another is pending — auto-declining the new one")
            #if DEBUG
            noteDecline()
            #endif
            return .declined
        }
        return await withCheckedContinuation { newContinuation in
            continuation = newContinuation
            pending = PendingConfirmation(title: title, detail: detail, caution: caution, fields: fields)
            Self.logger.notice("confirmation staged: \(title, privacy: .public)")
        }
    }

    /// Approve with the card's CURRENT field values (edits included).
    func approve() {
        guard let pending else { return }
        let values = Dictionary(uniqueKeysWithValues: pending.fields.map { ($0.key, $0.value) })
        resolve(.approved(values))
    }

    func decline() {
        resolve(.declined)
    }

    /// The card's editable-field write path (bound from the UI).
    func updateField(id: Field.ID, value: String) {
        guard var pending, let index = pending.fields.firstIndex(where: { $0.id == id }) else { return }
        pending.fields[index].value = value
        self.pending = pending
    }

    private func resolve(_ decision: Decision) {
        pending = nil
        let waiting = continuation
        continuation = nil
        waiting?.resume(returning: decision)
        if case .declined = decision {
            Self.logger.notice("confirmation declined")
            #if DEBUG
            noteDecline()
            recordBatteryOutcome("declined")
            #endif
        } else {
            Self.logger.notice("confirmation approved")
            #if DEBUG
            recordBatteryOutcome("accepted")
            #endif
        }
    }

    #if DEBUG
    /// #200: confirmation outcomes are capture data. One classifiable
    /// `battery: confirm=…` line + one record per gate resolution, carrying
    /// the SAME trial tag the relay's tool lines use — so the paste and the
    /// results page can pair each outcome with the tool invocation that
    /// staged it. No-op outside a battery (nil tag), so the resolve() calls
    /// above cost nothing in normal runs.
    private func recordBatteryOutcome(_ outcome: String) {
        guard let tag = ToolEventRelay.batteryTrialTag else { return }
        LocalChatBackend.batteryEmit("battery: confirm=\(outcome) \(tag)")
        LocalChatBackend.batteryRecorder.recordConfirmation(outcome)
    }
    #endif
}
