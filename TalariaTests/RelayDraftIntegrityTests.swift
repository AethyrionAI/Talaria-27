import Foundation
import Testing
@testable import Talaria

/// #405 — a hand-typed relay URL was scrambled BY THE APP, deterministically.
///
/// `ConnectHermesScreen`'s per-keystroke binding stored every draft through
/// `RelayConfiguration.init`, which CANONICALIZES: at the mid-draft
/// `"http://"` the trailing-slash strip plus the empty-path rule rewrite it
/// to `"http:/v1"`, the field re-reads the store, and the user's remaining
/// keystrokes append — `http:/v1127.0.0.1:8000/v1`, measured byte-identical
/// across four gate runs on the 24A5423a runtime. Canonicalizing a DRAFT is
/// the defect; canonicalization belongs on the read side
/// (`activeBaseURLString`), where it already lives.
struct RelayDraftIntegrityTests {

    /// The characterization the fix depends on, pinned so nobody "repairs"
    /// the init instead: the canonicalizing init is BY DESIGN for whole
    /// values (`defaultValue`, migration), and it genuinely rewrites the
    /// mid-draft this way. If this ever stops holding, #405's mechanism
    /// note is stale and the structural pin below may be obsolete.
    @Test func theCanonicalizingInitRewritesAMidDraftExactlyAsMeasured() {
        #expect(RelayConfiguration(customRelayBaseURL: "http://").customRelayBaseURL == "http:/v1")
    }

    /// Direct property assignment is the draft-preserving storage the
    /// pairing screen must use. A didSet normalizer added to the property
    /// would re-introduce #405 through the back door — this goes RED first.
    @Test func directAssignmentPreservesAMidDraftVerbatim() {
        var configuration = RelayConfiguration()
        configuration.customRelayBaseURL = "http://"
        #expect(configuration.customRelayBaseURL == "http://")
    }

    /// The hole that made the SECOND canonicalizer bite: normalization
    /// SUCCEEDS on the mid-draft "http://" (trailing-slash strip + the
    /// empty-path→"/v1" rule), so any "normalized when valid, raw while
    /// mid-edit" mirror resolves a half-typed URL into a confidently wrong
    /// one. Pinned so the next mirror author reads this instead of
    /// re-deriving the assumption.
    @Test func normalizationIsFalselyValidOnTheDoubleSlashDraft() {
        var configuration = RelayConfiguration()
        configuration.customRelayBaseURL = "http://"
        #expect(configuration.activeBaseURLString == "http:/v1")
    }

    /// #399-shape structural pin: AppContainer's relay-config mirror must
    /// copy the RAW text onto the active profile — mirroring
    /// `activeBaseURLString` is #405's scramble via the second door (the
    /// didSet handler overwrites the profile a beat after every keystroke).
    /// Reverting the mirror to `activeBaseURLString` turns this RED.
    @Test func relayMirrorCopiesTheRawTextNeverTheNormalizedForm() throws {
        let containerPath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Talaria/Stores/AppContainer.swift")
        let source = try #require(
            try? String(contentsOf: containerPath, encoding: .utf8),
            "AppContainer.swift unreadable — this pin must fail loudly, not vacuously"
        )
        guard let handlerRange = source.range(of: "onRelayConfigurationChanged = {") else {
            Issue.record("the relay-config mirror handler is gone — re-point this pin at its successor")
            return
        }
        let handlerBody = String(source[handlerRange.upperBound...].prefix(2000))
        #expect(
            !handlerBody.contains("activeBaseURLString"),
            "the mirror resolves drafts through normalization — #405's false-valid hole"
        )
        #expect(
            handlerBody.contains("configuration.customRelayBaseURL"),
            "the mirror must copy the raw text"
        )
    }

    /// #399-shape structural pin: the pairing screen must never store a
    /// draft through the canonicalizing init. Reverting `setRelayURL` to
    /// `RelayConfiguration(customRelayBaseURL:)` turns this RED.
    @Test func pairingScreenNeverStoresADraftThroughTheCanonicalizingInit() throws {
        let screenPath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Talaria/Features/Onboarding/ConnectHermesScreen.swift")
        let source = try #require(
            try? String(contentsOf: screenPath, encoding: .utf8),
            "ConnectHermesScreen.swift unreadable — this pin must fail loudly, not vacuously"
        )
        let occurrences = source.components(separatedBy: "RelayConfiguration(customRelayBaseURL").count - 1
        #expect(
            occurrences == 0,
            "the pairing screen stores drafts through the canonicalizing init (#405's scramble) — found \(occurrences) construction(s)"
        )
    }

    // MARK: - #406 — commit-time refresh (the WHEN, where #405 pinned the HOW)

    /// #406: per-keystroke edits stay in a LOCAL draft. The old binding
    /// wrote the profile + settings on every keystroke, and the settings
    /// write fired `refreshUnpairedRelayContext()` — a session clear plus
    /// ~2 doomed HTTP attempts per character against `http:`, `http:/`, …
    /// Restoring a store-writing binding on the relay field turns this RED.
    @Test func pairingRelayFieldBindsTheLocalDraftNotTheStores() throws {
        let source = try Self.pairingScreenSource()
        #expect(
            source.contains("text: $relayURLDraft"),
            "the relay field must bind the local draft, not a store-backed binding"
        )
        #expect(
            !source.contains("customRelayURLBinding"),
            "the per-keystroke store-writing binding is back — #406's request burst returns with it"
        )
    }

    /// #406: the pair attempt is a commit moment, and the ORDER is the bar —
    /// the redeem must see the committed URL, so the commit sits between the
    /// validation guard and `pairingStore.pair`.
    @Test func pairAttemptCommitsTheDraftBeforeRedeeming() throws {
        let source = try Self.pairingScreenSource()
        guard let funcRange = source.range(of: "func completePairing") else {
            Issue.record("completePairing is gone — re-point this pin at the pair path's successor")
            return
        }
        let body = String(source[funcRange.upperBound...].prefix(1200))
        guard let commitRange = body.range(of: "commitRelayDraft()") else {
            Issue.record("the pair attempt never commits the relay draft — the redeem reads a stale store")
            return
        }
        guard let pairRange = body.range(of: "pairingStore.pair(") else {
            Issue.record("pairingStore.pair not found near completePairing — re-point this pin")
            return
        }
        #expect(
            commitRange.lowerBound < pairRange.lowerBound,
            "the commit must land BEFORE the redeem, or pairing runs against the pre-draft URL"
        )
    }

    /// #406: screen dismissal is the other commit moment, and again the
    /// ORDER is the bar — the commit resolves the target profile through
    /// `pairingTargetProfileID`, so it must run BEFORE that id is cleared.
    /// Deleting the dismissal commit (or reordering it after the clear)
    /// turns this RED.
    @Test func screenDismissalCommitsTheDraftBeforeClearingThePairTarget() throws {
        let source = try Self.pairingScreenSource()
        guard let disappearRange = source.range(of: ".onDisappear") else {
            Issue.record("the screen's onDisappear is gone — re-point this pin at the dismissal path")
            return
        }
        let block = String(source[disappearRange.upperBound...].prefix(400))
        guard let commitRange = block.range(of: "commitRelayDraft()") else {
            Issue.record("dismissal never commits the relay draft — a typed-but-unpaired URL is lost")
            return
        }
        guard let clearRange = block.range(of: "pairingTargetProfileID = nil") else {
            Issue.record("the pair-target clear moved out of onDisappear — re-point this pin")
            return
        }
        #expect(
            commitRange.lowerBound < clearRange.lowerBound,
            "the commit must run BEFORE the target id clears, or it writes the wrong profile's slot"
        )
    }

    private static func pairingScreenSource() throws -> String {
        let screenPath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Talaria/Features/Onboarding/ConnectHermesScreen.swift")
        return try #require(
            try? String(contentsOf: screenPath, encoding: .utf8),
            "ConnectHermesScreen.swift unreadable — these pins must fail loudly, not vacuously"
        )
    }
}
