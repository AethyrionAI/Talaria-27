import Foundation
import Testing
@testable import Talaria

/// #371 — history-restored ✓ chips asserted completions the app never
/// witnessed. The session transcript carries no per-call outcome, so a
/// reconstructed activity's `isActive: false` is a DEFAULT, not an
/// observation (#327's own comment says so). Owen's ruling: a PROVENANCE
/// LABEL — "completed while away" — never a network verification.
@MainActor
struct ToolProvenanceTests {

    private func reconstructed(_ label: String = "write_file") -> ToolActivity {
        ToolActivity(label: label, isActive: false, provenance: .reconstructed)
    }

    private func witnessed(_ label: String = "write_file") -> ToolActivity {
        ToolActivity(label: label, isActive: false)
    }

    // MARK: - 371-B: the parallel decision functions

    @Test func anAllReconstructedCompletionMakesTheSofterClaim() {
        #expect(ToolActivityRail.summaryIsReconstructed([reconstructed()]))
    }

    @Test func aWitnessedCompletionKeepsThePlainCheckmark() {
        #expect(!ToolActivityRail.summaryIsReconstructed([witnessed()]))
        #expect(ToolActivityRail.summaryState(of: [witnessed()]) == .completed)
    }

    @Test func aMixedSetTakesTheHonestDirection() {
        #expect(
            ToolActivityRail.summaryIsReconstructed([witnessed(), reconstructed()]),
            "over-claiming witness for even one unobserved completion is the defect"
        )
    }

    // MARK: - 371-C: interrupted wins outright

    @Test func aReconstructedStopRendersInterruptedNeverCompletedWhileAway() {
        var stopped = reconstructed()
        stopped.failure = ToolActivity.stoppedByUser
        #expect(ToolActivityRail.state(of: stopped) == .interrupted)
        #expect(!ToolActivityRail.summaryIsReconstructed([stopped]),
                "#327's marked stops keep their interrupted rendering")
        #expect(!ToolActivityRail.stepIsReconstructed(stopped))
    }

    // MARK: - 371-A: the producer stamps what it reconstructs

    @Test func transcriptReconstructionStampsProvenance() throws {
        let json = Data("""
        {"role":"assistant","content":"done.","timestamp":1760000000,
         "tool_calls":[{"function":{"name":"write_file"}}]}
        """.utf8)
        let stored = try JSONDecoder().decode(
            SessionsHermesClient.SessionMessagesResponse.StoredMessage.self,
            from: json
        )
        let message = try #require(
            SessionsHermesClient.mapStoredMessage(stored, sessionId: "probe-session")
        )
        let activity = try #require(message.toolActivities.first)
        #expect(
            activity.provenance == .reconstructed,
            "371-A: the transcript rebuild is the one site that mints unwitnessed completions"
        )
        #expect(activity.isActive == false)
        #expect(activity.failure == nil)
    }

    // MARK: - 371-D: provenance never joins the dedupe key

    @Test func provenanceIsNotPartOfTheAdoptedEchoKey() {
        let timestamp = Date(timeIntervalSince1970: 1_760_000_000)
        let shell = { (provenance: ToolActivity.Provenance?) in
            Message(
                sender: .hermes,
                content: "",
                timestamp: timestamp,
                status: .delivered,
                toolActivities: [
                    ToolActivity(label: "write_file", isActive: false, provenance: provenance),
                ]
            )
        }
        let deduped = Conversation.dedupingAdoptedEchoes([shell(nil), shell(.reconstructed)])
        #expect(
            deduped.count == 1,
            "two rows differing only in provenance are the same row — #237's duplicate must not resurrect"
        )
    }

    // MARK: - roundtrip + legacy shape

    @Test func provenanceSurvivesACodableRoundtrip() throws {
        let encoded = try JSONEncoder().encode([reconstructed()])
        let decoded = try JSONDecoder().decode([ToolActivity].self, from: encoded)
        #expect(decoded.first?.provenance == .reconstructed)
    }

    @Test func aProvenancelessJSONDecodesAsWitnessed() throws {
        let legacy = Data("""
        [{"id":"1B7C4C6B-6C4B-4B6B-8B6B-1B7C4C6B4B6B","label":"write_file",
          "startedAt":760000000,"isActive":false,"anchorOffset":0}]
        """.utf8)
        let decoded = try JSONDecoder().decode([ToolActivity].self, from: legacy)
        #expect(decoded.first?.provenance == nil, "nil = witnessed, the historical value")
    }

    // MARK: - 371-E structural: the view consumes the parallel functions

    @Test func theRailRendersTheProvenanceDistinctionVisuallyAndForVoiceOver() throws {
        let railPath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Talaria/Features/Chat/ToolActivityRail.swift")
        let source = try #require(
            try? String(contentsOf: railPath, encoding: .utf8),
            "ToolActivityRail.swift unreadable — this pin must fail loudly, not vacuously"
        )
        let consumptions = source.components(separatedBy: "summaryIsReconstructed").count - 1
        #expect(
            consumptions >= 4,
            "the glyph AND the accessibility label must consume the decision (definition + wrapper + 2 view sites minimum) — #296's lesson: the non-visual reader must not get the checkmark version of the lie"
        )
        #expect(
            source.components(separatedBy: "completedWhileAwayPhrase").count - 1 >= 2,
            "the ruled copy reaches the view through the pinned constant"
        )
    }
}
