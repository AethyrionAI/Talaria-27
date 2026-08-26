import Foundation
import os

// MARK: - What the screen is looking at

/// The host this phone is currently set up to talk to, as the resting card
/// renders it. Every field is either stored or MEASURED — nothing here is
/// asserted (#350's lesson, and #180's ruled convention).
struct ConnectedHost: Equatable, Sendable {
    var profileID: UUID?
    var name: String
    /// Host + port as the card prints it, e.g. `100.110.102.59:8642`.
    var address: String
    /// The key is never shown again after commit — only whether one is held.
    var hasStoredKey: Bool
    /// When the host last actually answered. `nil` = never measured in this
    /// launch, which the card SAYS rather than guessing "just now".
    var lastAnsweredAt: Date?
    var modelsSeen: Int?
    /// **SAVED ≠ REACHABLE, with a third value that matters more than either.**
    /// `.notChecked` is what a freshly-launched app honestly knows about a
    /// stored host before it has asked — and rendering that as `.noAnswer`
    /// would be #350's defect on a new surface: a claim of failure made before
    /// the question was put. Only a MEASURED `.noAnswer` earns design B2.
    var reachability: ConnectHostRosterEntry.Reachability
}

/// One row of the multi-host list (design B3) — the `BackendProfile` list
/// wearing the new clothes.
struct ConnectHostRosterEntry: Identifiable, Equatable, Sendable {
    enum KeyState: Equatable, Sendable {
        case stored
        case missing

        /// "NO KEY" is an honest state, not a failure — the design says so.
        var label: String {
            switch self {
            case .stored: "KEY OK"
            case .missing: "NO KEY"
            }
        }
    }

    enum Reachability: Equatable, Sendable {
        /// The latency is optional because the two measurements differ: the
        /// Connect Host ladder times its own round trip, while the standing
        /// host refresh only records that one landed. Printing a borrowed or
        /// stale number would be worse than printing none.
        case reachable(milliseconds: Int?)
        case noAnswer
        /// Never probed in this launch. The design's own note: status per host
        /// is MEASURED or "NOT CHECKED" — never guessed.
        case notChecked

        var label: String {
            switch self {
            case .reachable(let ms?): "REACHABLE · \(ms)MS"
            case .reachable: "REACHABLE"
            case .noAnswer: "NO ANSWER"
            case .notChecked: "NOT CHECKED"
            }
        }
    }

    let id: UUID
    var name: String
    var address: String
    var isActive: Bool
    var keyState: KeyState
    var reachability: Reachability
}

/// What a disconnect actually managed to do (#309 Lane B, bar 309-B6).
enum HostDisconnectOutcome: Equatable, Sendable {
    /// Both halves: the plugin took the `unpair`, and the credentials are gone.
    case forgottenAndHostTold
    /// The local forget happened; the host was not told. **The copy says so**
    /// — see `ConnectHostCopy.disconnectedHostNotTold`.
    case forgottenHostNotTold
}

/// The eight resting states of the Connect Host surface (design A1–A4,
/// B1–B4), as ONE value.
///
/// Modelled as an enum rather than assembled at render time from four
/// booleans, because the design's whole argument is that these states are
/// *distinguishable*: SAVED ≠ REACHABLE, empty ≠ error, a failed check ≠ a
/// disconnected host. Booleans let two of them be true at once and the screen
/// then has to pick — which is how a surface starts hiding its own
/// degradation (#180).
enum ConnectHostPresentation: Equatable, Sendable {
    case empty              // A1 — nothing entered; running locally
    case ready              // A2 — both values typed, not checked yet
    case checking           // A3 — inline, fields dimmed but present
    case connected          // A4 — the resting card
    case failed             // B1 — failure in place, guilty field flagged
    case quiet              // B2 — saved, not answering right now
    case hostList           // B3 — more than one machine
    case disconnectConfirm  // B4 — the one action, both halves spelled out
}

// MARK: - The model

/// The Connect Host state machine — shared by the Settings screen and the
/// wizard, so the two surfaces cannot disagree about what happened.
///
/// **Commit-on-probe-pass (bar 309-B4) lives here.** `checkAndConnect()` calls
/// `commit` on exactly one path: a `.connected` outcome. Every other outcome
/// leaves the stores untouched, which is what makes B1's *"NOTHING WAS SAVED.
/// YOU ARE STILL ON-DEVICE."* a measured claim rather than a reassurance.
/// #406's commit-time draft pattern, extended one notch: the commit moment is
/// the green probe.
@MainActor
@Observable
final class ConnectHostModel {

    /// Everything the model needs from the app, as closures — so the state
    /// machine is testable without a container, and so a test can COUNT
    /// commits (which is how bar 309-B4 is measured rather than asserted).
    struct Environment {
        /// Probes a CANDIDATE host — values the user just typed or scanned,
        /// which no store has seen.
        var probe: @MainActor (_ gatewayBaseURL: String, _ apiKey: String) async -> HostProbeOutcome
        var commit: @MainActor (_ draft: Draft, _ outcome: HostProbeOutcome) async -> Void
        var currentHost: @MainActor () -> ConnectedHost?
        var roster: @MainActor () -> [ConnectHostRosterEntry]
        /// Re-measures the COMMITTED host. Separate from `probe` because the
        /// committed key is never in this model's memory — "never shown again"
        /// is structural here, not a promise the view keeps.
        var recheckCommitted: @MainActor () async -> HostProbeOutcome
        var disconnect: @MainActor () async -> HostDisconnectOutcome
        var activate: @MainActor (_ profileID: UUID) async -> Void

        init(
            probe: @escaping @MainActor (String, String) async -> HostProbeOutcome,
            commit: @escaping @MainActor (Draft, HostProbeOutcome) async -> Void,
            currentHost: @escaping @MainActor () -> ConnectedHost? = { nil },
            roster: @escaping @MainActor () -> [ConnectHostRosterEntry] = { [] },
            recheckCommitted: @escaping @MainActor () async -> HostProbeOutcome = { .noAnswer(detail: "NO ANSWER") },
            disconnect: @escaping @MainActor () async -> HostDisconnectOutcome = { .forgottenHostNotTold },
            activate: @escaping @MainActor (UUID) async -> Void = { _ in }
        ) {
            self.probe = probe
            self.commit = commit
            self.currentHost = currentHost
            self.roster = roster
            self.recheckCommitted = recheckCommitted
            self.disconnect = disconnect
            self.activate = activate
        }
    }

    /// The two values plus the label, held LOCALLY until a green probe. No
    /// keystroke reaches a store — #406's rule, and the reason a mistyped
    /// address costs zero doomed requests here.
    struct Draft: Equatable, Sendable {
        var gatewayBaseURL: String = ""
        var apiKey: String = ""
        var name: String = ""

        var trimmedGateway: String {
            gatewayBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var trimmedKey: String {
            apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var trimmedName: String {
            name.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        /// The label the connected card shows: the scanned/typed name, else
        /// the address's host component (spec §3.4). Never blank.
        var resolvedName: String {
            if !trimmedName.isEmpty { return trimmedName }
            if let host = URL(string: trimmedGateway)?.host, !host.isEmpty { return host }
            return trimmedGateway.isEmpty ? "Hermes host" : trimmedGateway
        }
    }

    private static let logger = Logger(
        subsystem: TalariaLog.subsystem, category: "ConnectHostModel")

    // MARK: Observable state

    var draft = Draft()
    /// The reveal toggle exists ONLY before a commit. After it, the key reads
    /// "IN KEYCHAIN" forever and re-entry replaces it wholesale (spec §3.5).
    var isKeyRevealed = false
    var isShowingHostList = false
    var isConfirmingDisconnect = false

    private(set) var isChecking = false
    private(set) var ladder: HostProbeLadder?
    private(set) var failure: HostProbeOutcome?
    private(set) var host: ConnectedHost?
    private(set) var lastDisconnectOutcome: HostDisconnectOutcome?

    private let environment: Environment
    private var checkTask: Task<Void, Never>?

    init(environment: Environment) {
        self.environment = environment
        self.host = environment.currentHost()
    }

    // MARK: Derived

    /// The ONE value the two surfaces render from (bar 309-B2).
    var presentation: ConnectHostPresentation {
        if isConfirmingDisconnect { return .disconnectConfirm }
        if isShowingHostList { return .hostList }
        if isChecking { return .checking }
        if failure != nil { return .failed }
        if let host {
            // SAVED ≠ REACHABLE. Both are resting states; neither is an error
            // — and `.notChecked` rests on the CONNECTED card with an honest
            // status label rather than being rounded down to "not answering".
            return host.reachability == .noAnswer ? .quiet : .connected
        }
        return canCheck ? .ready : .empty
    }

    /// Both values present and the address plausibly a URL. Deliberately NOT a
    /// reachability claim — the button's job is to start the check, and
    /// pre-judging an address the user can see is how #405's mid-draft
    /// normalization bug felt to the person typing.
    var canCheck: Bool {
        !draft.trimmedGateway.isEmpty
            && !draft.trimmedKey.isEmpty
            && validationMessage == nil
    }

    /// The one field a failure flags (design B1: "only the guilty field is
    /// flagged"). `nil` when there is no failure to blame anything for.
    var guiltyField: ConnectHostField? {
        failure?.guiltyField
    }

    /// Address-shape validation, mid-draft-safe: an empty field says nothing
    /// (the user is still typing), and only a non-empty non-URL complains.
    var validationMessage: String? {
        let gateway = draft.trimmedGateway
        guard !gateway.isEmpty else { return nil }
        guard gateway.hasPrefix("http://") || gateway.hasPrefix("https://") else {
            return ConnectHostCopy.addressNeedsScheme
        }
        guard GatewayHermesHostService.probeURL(gatewayBaseURL: gateway) != nil else {
            return ConnectHostCopy.addressNotAURL
        }
        return nil
    }

    var rosterEntries: [ConnectHostRosterEntry] {
        environment.roster()
    }

    // MARK: Intents

    /// Fills the draft from a scanned `hermes talaria pair-qr` payload. The QR
    /// is SUGAR on the typed arm: it writes the same three fields and then the
    /// same probe runs — there is no second code path (design doc §3a).
    func apply(_ payload: TalariaPairPayload) {
        draft.gatewayBaseURL = payload.gatewayBaseURL
        draft.apiKey = payload.apiKey
        if let name = payload.name { draft.name = name }
        failure = nil
        ladder = nil
    }

    /// Seeds the draft for an EDIT of the committed host. The key is never
    /// seeded — it is not readable back into a field by design; re-entry
    /// replaces it wholesale.
    func beginEditingAddress() {
        guard let host else { return }
        draft.gatewayBaseURL = host.address.contains("://") ? host.address : "http://\(host.address)"
        draft.name = host.name
        draft.apiKey = ""
        failure = nil
        ladder = nil
        self.host = nil
    }

    /// Fire-and-forget entry point for the views: owns the task so Cancel has
    /// something real to cancel (design A3's Cancel is a live control, not a
    /// decoration).
    func startCheck() {
        guard canCheck, !isChecking else { return }
        checkTask?.cancel()
        checkTask = Task { [weak self] in
            await self?.checkAndConnect()
            self?.checkTask = nil
        }
    }

    /// Runs the ladder and commits ONLY on a green verdict.
    func checkAndConnect() async {
        guard canCheck, !isChecking else { return }
        isChecking = true
        isKeyRevealed = false
        ladder = .running
        failure = nil
        defer { isChecking = false }

        let outcome = await environment.probe(draft.trimmedGateway, draft.trimmedKey)
        guard !Task.isCancelled else { return }
        ladder = outcome.ladder

        guard outcome.isConnected else {
            // NOTHING is written here. Not the profile, not the Keychain, not
            // the active-profile pointer — bar 309-B4.
            failure = outcome
            Self.logger.notice("check: failed — stores untouched")
            return
        }

        await environment.commit(draft, outcome)
        host = environment.currentHost()
        failure = nil
        Self.logger.notice("check: green — credentials committed")
    }

    func cancelCheck() {
        checkTask?.cancel()
        checkTask = nil
        isChecking = false
        ladder = nil
    }

    /// The resting card's "Check now" — re-measures the COMMITTED host and
    /// writes nothing but the measurement. `LAST ANSWERED` is this, which is
    /// why the card can print a timestamp without asserting one (#350).
    func recheck() async {
        guard host != nil, !isChecking else { return }
        isChecking = true
        ladder = .running
        defer { isChecking = false }

        let outcome = await environment.recheckCommitted()
        ladder = outcome.ladder
        // The refreshed record comes from the app, not from this model's
        // arithmetic — `currentHost` is the single source, and it has just
        // been handed the measurement.
        host = environment.currentHost()
    }

    func confirmDisconnect() async {
        let outcome = await environment.disconnect()
        lastDisconnectOutcome = outcome
        isConfirmingDisconnect = false
        host = environment.currentHost()
        draft = Draft()
        ladder = nil
        failure = nil
    }

    func activate(profileID: UUID) async {
        await environment.activate(profileID)
        host = environment.currentHost()
    }

    /// Re-reads the committed host from the app — call on appear, so a screen
    /// re-entered after a profile switch shows that profile's host.
    func refreshFromStores() {
        host = environment.currentHost()
    }
}
