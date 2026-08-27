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
        // The Phase-0 pins (`approvalModeExposesAllThreeAfterPhases12` and
        // siblings — renamed from `approvalModeExposesOnlyManual` when #224
        // Phases 1+2 shipped the modes on 2026-08-26)
        // enforce the on-device enum directly; this arm records the
        // separation from THIS side: the host state is not an ApprovalMode
        // and never routes through its clamp.
        #expect(ApprovalMode.selectable == [.manual], "the on-device gate's pin, read from here")
        #expect(HostApprovalModeState.selectableModes.count == 3)
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
