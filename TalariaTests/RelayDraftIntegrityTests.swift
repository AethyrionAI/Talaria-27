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
}
