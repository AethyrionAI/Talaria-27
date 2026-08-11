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
    /// this class keeps no settings dependency (the
    /// `SessionsHermesClient.useRunsTransportProvider` precedent). The key is
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
    var autoAcceptForBattery = false

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
        let disposition = modeProvider().disposition(hasCaution: caution != nil)
        if disposition != .card {
            Self.logger.error("approval mode produced \(disposition.rawValue, privacy: .public) — this build ships no handling for it; staging the card")
        }
        guard continuation == nil else {
            Self.logger.warning("confirmation requested while another is pending — auto-declining the new one")
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
