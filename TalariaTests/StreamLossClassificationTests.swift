import Foundation
import Testing
@testable import Talaria

// #382 TOMBSTONE: `StreamLossClassificationTests` — three wire fixtures
// (240-A accepted-but-pre-`run.started` drop, the pre-response park, and
// the post-`run.started` zombie) driven against the sessions-plane
// `chat/stream` endpoint — went with the plane they scripted. The
// SCENARIOS are transport-independent and survive on the runs plane, where
// they are pinned in `RunsPlaneTransportTests`:
// `anAcceptedSubmitWhoseEventsStreamDiesArmsRecoveryNotParking` (the 240-A
// shape, now with the run id the sessions plane never had),
// `aSubmitThatNeverReachesTheHostStillParksAsUnreachable`, and the
// pre-existing `droppedStreamOnALiveRunArmsRecovery` (the zombie shape).

// MARK: - #246: the zombie stream — silence past the stall threshold

/// Filed from Owen's build-1978 backgrounding test (the first 235-E run):
/// a stream that goes zombie — socket open, bytes never coming, no terminal
/// event — never ended, so recovery never armed and the spinner sat until a
/// manual leave/re-enter. The guard makes prolonged silence THROW, and the
/// existing post-2xx catch converts the throw into `.interrupted` with all
/// of #235/#237's machinery downstream.
@Suite(.serialized)
struct StreamStallGuardTests {

    /// A scriptable line source: yields the given lines, then either goes
    /// silent forever (`thenSilent`) or completes.
    private struct ScriptedLines: AsyncSequence, Sendable {
        let lines: [String]
        let thenSilent: Bool

        struct AsyncIterator: AsyncIteratorProtocol {
            var remaining: [String]
            let thenSilent: Bool
            mutating func next() async throws -> String? {
                if remaining.isEmpty {
                    if thenSilent {
                        // Silence, not termination: park until cancelled.
                        while !Task.isCancelled {
                            try await Task.sleep(for: .milliseconds(20))
                        }
                        return nil
                    }
                    return nil
                }
                return remaining.removeFirst()
            }
        }

        func makeAsyncIterator() -> AsyncIterator {
            AsyncIterator(remaining: lines, thenSilent: thenSilent)
        }
    }

    /// 246-A: one line, then silence past the threshold — the line is
    /// delivered, then the guard THROWS `StreamStallError` instead of
    /// blocking forever.
    @Test
    func silencePastTheThresholdThrowsAfterDeliveringWhatArrived() async {
        let guarded = SessionsHermesClient.stallGuardedLines(
            ScriptedLines(lines: ["data: hello"], thenSilent: true),
            threshold: .milliseconds(200)
        )
        var received: [String] = []
        do {
            for try await line in guarded { received.append(line) }
            Issue.record("a silent stream must throw, not finish cleanly")
        } catch {
            #expect(error is SessionsHermesClient.StreamStallError)
        }
        #expect(received == ["data: hello"])
    }

    /// 246-B: lines flowing within the threshold pass through untouched and
    /// the sequence completes normally — a healthy stream never trips it.
    @Test
    func flowingLinesPassThroughAndCompleteWithoutTripping() async throws {
        let lines = (0 ..< 20).map { "data: line-\($0)" }
        let guarded = SessionsHermesClient.stallGuardedLines(
            ScriptedLines(lines: lines, thenSilent: false),
            threshold: .milliseconds(500)
        )
        var received: [String] = []
        for try await line in guarded { received.append(line) }
        #expect(received == lines)
    }
}
