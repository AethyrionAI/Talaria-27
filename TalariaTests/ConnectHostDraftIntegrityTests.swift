import Foundation
import Testing
@testable import Talaria

/// **#405 × #406, ported to Connect Host by #309 Lane B (2026-08-25).**
///
/// These pins were `RelayDraftIntegrityTests`, and they existed because a
/// hand-typed host URL was scrambled BY THE APP, deterministically:
/// `ConnectHermesScreen` stored every keystroke through
/// `RelayConfiguration.init`, which CANONICALIZES — at the mid-draft
/// `"http://"` the trailing-slash strip plus the empty-path rule rewrote it to
/// `"http:/v1"`, the field re-read the store, and the remaining keystrokes
/// appended (`http:/v1127.0.0.1:8000/v1`, measured byte-identical across four
/// gate runs). #406 then found the cost of the store write itself: every
/// character fired a session clear plus ~2 doomed HTTP attempts.
///
/// **The screen, the store and the canonicalizing type are all deleted. The
/// two defects are not — they are properties of any two-field host form, and
/// Connect Host is one.** So the pins moved rather than going with the code:
///
/// - the WHAT (a draft is never canonicalized under the cursor) is now a
///   BEHAVIOURAL test on `ConnectHostModel` rather than a source grep — the
///   model holds the draft, so the property can be measured instead of
///   inferred from the absence of a call;
/// - the WHEN (stores are written at commit moments only) is bar 309-B4's
///   commit-on-probe-pass, and lives in `ConnectHostTests`.
///
/// The source-grep pin that survives here is the structural one #406 needed:
/// the Connect Host views must bind the MODEL's draft, never a store.
@MainActor
struct ConnectHostDraftIntegrityTests {

    // MARK: - #405: the draft is never rewritten under the cursor

    /// The exact input that produced the measured scramble. Typing
    /// `http://100.79.222.100:8642` one character at a time must leave the
    /// draft byte-identical to what was typed at EVERY intermediate step —
    /// most of which are not valid URLs, which is the whole point.
    @Test func aCharacterByCharacterAddressIsNeverRewrittenMidDraft() async {
        let model = ConnectHostModel(environment: .inert())
        let target = "http://100.79.222.100:8642"

        var typed = ""
        for character in target {
            typed.append(character)
            model.draft.gatewayBaseURL = typed
            #expect(model.draft.gatewayBaseURL == typed,
                    "the draft was rewritten at '\(typed)' — #405's scramble")
        }
        #expect(model.draft.gatewayBaseURL == target)
    }

    /// The specific mid-draft that broke: `"http://"` normalizes SUCCESSFULLY
    /// under the old rules (trailing-slash strip + empty-path), which is why a
    /// "normalize when valid" mirror resolved a half-typed URL into a
    /// confidently wrong one. The model must treat it as a draft, not a value.
    @Test func theDoubleSlashDraftSurvivesVerbatimAndBlocksTheCheck() async {
        let model = ConnectHostModel(environment: .inert())
        model.draft.gatewayBaseURL = "http://"
        model.draft.apiKey = "some-key"

        #expect(model.draft.gatewayBaseURL == "http://")
        // …and it is REFUSED rather than silently repaired: `canCheck` is
        // false, so the probe never runs against a host the user did not type.
        #expect(model.canCheck == false)
        #expect(model.validationMessage != nil)
    }

    /// Mid-draft prefixes say NOTHING while the user is still typing — an
    /// empty field is not an error, and neither is a half-typed scheme once a
    /// scheme is present. Only a non-empty address that cannot be a URL
    /// complains.
    @Test func validationIsSilentOnAnEmptyFieldAndSpeaksOnlyOnRealNonsense() async {
        let model = ConnectHostModel(environment: .inert())

        model.draft.gatewayBaseURL = ""
        #expect(model.validationMessage == nil, "an empty field is not an error state")

        model.draft.gatewayBaseURL = "100.79.222.100:8642"
        #expect(model.validationMessage == ConnectHostCopy.addressNeedsScheme)

        model.draft.gatewayBaseURL = "http://100.79.222.100:8642"
        #expect(model.validationMessage == nil)
    }

    // MARK: - #406: the views bind the DRAFT, never a store

    /// Structural pin, ported from
    /// `pairingRelayFieldBindsTheLocalDraftNotTheStores`. A store-backed
    /// binding on either field brings #406's per-keystroke request burst back,
    /// and a behavioural test cannot see it — the burst is in the STORE, not
    /// in the draft.
    @Test func theConnectHostFieldsBindTheModelDraftNotAStore() throws {
        let source = try Self.source("Talaria/Features/Settings/ConnectHostComponents.swift")
        #expect(source.contains("$model.draft.gatewayBaseURL"),
                "the gateway field must bind the model's draft")
        #expect(source.contains("$model.draft.apiKey"),
                "the key field must bind the model's draft")
        for storeWrite in ["settingsStore.settings", "profilesStore.upsert", "saveGatewayAPIKey"] {
            #expect(!source.contains(storeWrite),
                    "the fields write a store per keystroke — #406's burst is back via \(storeWrite)")
        }
    }

    /// The wizard and the Settings screen must both go through the MODEL.
    /// A second, view-local commit path is how the two surfaces would start
    /// disagreeing about when something is saved.
    @Test func neitherConnectHostSurfaceWritesCredentialsItself() throws {
        for path in ["Talaria/Features/Settings/ConnectHostScreen.swift",
                     "Talaria/Features/Onboarding/ConnectHostWizard.swift"] {
            let source = try Self.source(path)
            #expect(!source.contains("saveGatewayAPIKey"),
                    "\(path) writes the Keychain directly — the commit must go through the model")
            #expect(!source.contains("profilesStore.upsert"),
                    "\(path) writes the profile directly — the commit must go through the model")
        }
    }

    private static func source(_ relativePath: String) throws -> String {
        let path = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(relativePath)
        return try #require(
            try? String(contentsOf: path, encoding: .utf8),
            "\(relativePath) unreadable — this pin must fail loudly, not vacuously"
        )
    }
}

extension ConnectHostModel.Environment {
    /// A world that answers nothing and records nothing — for tests whose
    /// subject is the draft, not the probe.
    @MainActor
    static func inert() -> ConnectHostModel.Environment {
        ConnectHostModel.Environment(
            probe: { _, _ in .noAnswer(detail: "NO ANSWER") },
            commit: { _, _ in }
        )
    }
}
