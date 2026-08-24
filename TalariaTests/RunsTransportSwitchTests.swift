import Foundation
import Testing
@testable import Talaria

/// **#382 — the sessions turn transport is DELETED.**
///
/// This file held the #368 cutover-migration suite (six fixtures pinning the
/// one-shot `runsCutoverApplied` migration and the Developer switch's
/// stickiness). #382 deleted the switch, the migration, and the transport
/// they selected, so those tests were asserting on removed code — the #375
/// falsified-tests precedent. What replaces them is what the deletion
/// actually promises:
///
/// - **382-D:** old persisted blobs still carrying the retired keys decode
///   cleanly (#238's unknown-key shape) — a relaunch after the update must
///   not eat anyone's settings.
/// - **382-B (structural half):** `useRunsTransport` is absent from the
///   production tree, and the client spells no sessions-plane turn path.
///   The behavioral half lives in `RunsPlaneTransportTests.
///   aStreamedTurnNeverTouchesTheDeletedSessionsChatStream`, which watches
///   the wire itself.
struct RunsTransportSwitchTests {

    /// **382-D — a pre-deletion blob decodes, keys ignored.** The exact JSON
    /// an updated install carries: `useRunsTransport` and
    /// `runsCutoverApplied` present (every pre-#382 install encoded both,
    /// unconditionally), now unknown to the decoder.
    @Test func aBlobCarryingTheRetiredTransportKeysStillDecodes() throws {
        let legacy = """
        {"userName":"Owen","useRunsTransport":false,"runsCutoverApplied":true,"hapticFeedbackEnabled":false}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(UserSettings.self, from: legacy)
        #expect(decoded.userName == "Owen")
        #expect(decoded.hapticFeedbackEnabled == false)
    }

    /// **382-B, structural half** (the #399 source-reading pattern): the
    /// switch must not regrow. `useRunsTransport` appears in `Talaria/`
    /// source only inside `#382`-tombstone comments, and the client file
    /// spells no `chat/stream` path. Fails loudly if a source cannot be
    /// enumerated — a check that cannot run must say so.
    @Test func theSwitchAndTheSessionsTurnPathAreAbsentFromTheTree() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // TalariaTests/
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("Talaria")
        let files = try #require(
            FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
                .compactMap { $0 as? URL }
                .filter { $0.pathExtension == "swift" },
            "cannot enumerate Talaria/ — this check did not run"
        )
        #expect(!files.isEmpty, "cannot enumerate Talaria/ — this check did not run")

        var switchHits: [String] = []
        var chatStreamHits: [String] = []
        for file in files {
            guard let source = try? String(contentsOf: file, encoding: .utf8) else { continue }
            for (index, line) in source.components(separatedBy: "\n").enumerated() {
                if line.contains("useRunsTransport"), !line.contains("#382") {
                    switchHits.append("\(file.lastPathComponent):\(index + 1)")
                }
                // The PATH-LITERAL shape only (`…/chat/stream"`): historical
                // comments legitimately name the deleted route in prose, but
                // only request-building code spells it inside a string.
                if line.contains("chat/stream\"") {
                    chatStreamHits.append("\(file.lastPathComponent):\(index + 1)")
                }
            }
        }
        #expect(switchHits.isEmpty,
                "useRunsTransport regrew outside a #382 tombstone: \(switchHits)")
        #expect(chatStreamHits.isEmpty,
                "a sessions-plane chat/stream spelling regrew: \(chatStreamHits)")
    }
}
