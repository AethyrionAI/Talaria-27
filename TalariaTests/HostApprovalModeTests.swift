import Foundation
import Testing
@testable import Talaria

/// #224 app half (bars 224-APP-A..F) — the host's persistent approval mode
/// as a three-valued, response-driven state. UNKNOWN is the default branch
/// (#180 rule 5); the on-device `ApprovalMode` enum is deliberately not
/// touched (its Phase-0 pins stand untouched beside these).
struct HostApprovalModeTests {

    // MARK: - 224-APP-B: the three-valued mapping

    @Test func anUnsupportedAnswerIsTheHostPredatesState() {
        let (state, message) = HostApprovalModeState.from(.unsupported)
        #expect(state == .unsupported)
        #expect(message == nil)
    }

    @Test func anUnreachableAnswerStaysUnknownNeverOptimistic() {
        let (state, message) = HostApprovalModeState.from(.unreachable)
        #expect(state == .unknown)
        #expect(message == nil)
    }

    @Test func aHealthyReplyCarriesTheHostsReportedMode() {
        let payload = Data(#"{"ok": true, "mode": "off", "changed": false, "message": "Approval mode: off (persistent profile setting)."}"#.utf8)
        let (state, message) = HostApprovalModeState.from(.ok(payload))
        #expect(state == .mode("off"))
        #expect(message == nil, "an ok reply needs no surfaced message")
    }

    // 224-APP-E: a refusal lands on the host's REPORTED mode, message surfaced.
    @Test func aRefusedSetLandsOnTheReportedModeWithTheHostsWords() {
        let payload = Data(#"{"ok": false, "mode": "manual", "changed": false, "message": "Approval mode is managed and cannot be changed."}"#.utf8)
        let (state, message) = HostApprovalModeState.from(.ok(payload))
        #expect(state == .mode("manual"), "never the mode the user tapped")
        #expect(message == "Approval mode is managed and cannot be changed.")
    }

    @Test func garbageBytesFoldToUnknownNeverACrashOrAGuess() {
        let (state, message) = HostApprovalModeState.from(.ok(Data("not json".utf8)))
        #expect(state == .unknown)
        #expect(message == nil)
    }

    // MARK: - the picker's offer set

    @Test func theSelectableModesAreUpstreamsThree() {
        #expect(HostApprovalModeState.selectableModes == ["manual", "smart", "off"])
    }

    // MARK: - 224-APP-C: the on-device gate enum is untouched

    @Test func theHostStateIsADistinctTypeFromTheOnDeviceGate() {
        // **Updated 2026-08-26 by #224 Phases 1+2, and the update is the
        // point of the bar rather than a break in it.**
        //
        // 224-APP-C read `ApprovalMode.selectable == [.manual]` from here as a
        // shorthand for "the host lane did not touch the on-device enum" —
        // true of THAT lane, and false the moment Owen elected Phases 1+2,
        // which touch it deliberately. The gate caught this; a targeted run
        // that did not include this suite did not.
        //
        // What 224-APP-C actually claims survives untouched and is what this
        // now asserts DIRECTLY: the host state is a different TYPE, carrying
        // raw wire strings, and it never routes through the on-device enum or
        // its clamp. Asserting the separation beats asserting a literal that
        // belongs to the other lane — a pin on someone else's constant fails
        // when they legitimately change it, which is noise, not a finding.
        #expect(HostApprovalModeState.selectableModes == ["manual", "smart", "off"])
        #expect(HostApprovalModeState.selectableModes.count == 3)
        // The host's modes are STRINGS off the wire; the gate's are a Swift
        // enum. They happen to spell the same three words — that is upstream
        // parity, not a shared type — and nothing converts between them: a
        // host read lands as `.mode(String)`, never as an `ApprovalMode`, so
        // no host answer can move this phone's own gate.
        let (hostState, _) = HostApprovalModeState.from(
            .ok(Data(#"{"ok":true,"mode":"off"}"#.utf8)))
        #expect(hostState == .mode("off"))
        #expect(UserSettings().approvalMode == .manual,
                "a host reporting off must not have moved the on-device default")
    }

    // MARK: - 224-APP-B/D structural: the screen consumes the state honestly

    @Test func theServerScreenRendersTheThreeValuedStateWithPinnedCopy() throws {
        let screenPath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Talaria/Features/Settings/ServerSettingsScreen.swift")
        let source = try #require(
            try? String(contentsOf: screenPath, encoding: .utf8),
            "ServerSettingsScreen.swift unreadable — this pin must fail loudly, not vacuously"
        )
        #expect(
            source.components(separatedBy: "hostApprovalMode").count - 1 >= 3,
            "the picker section must exist and consume the three-valued state"
        )
        #expect(
            source.contains("approvalPredatesFootnote"),
            "the host-predates state ships its pinned remedy copy"
        )
        #expect(
            source.contains("case .unknown"),
            "UNKNOWN gets its own branch — the default, never the else (#180 rule 5)"
        )
    }
}

/// The pinned copy — substring pins in the #396 style, so the strings can
/// be reworded only by a commit that says so.
struct HostApprovalCopyPins {
    @Test func predatesFootnoteNamesTheRemedy() {
        #expect(ServerSettingsScreen.approvalPredatesFootnote.contains("after the host updates"))
    }

    @Test func captionNamesTheUpstreamCommandItMirrors() {
        #expect(ServerSettingsScreen.approvalCaption.contains("/approvals"))
    }
}
