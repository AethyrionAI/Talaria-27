import Foundation
import Testing
@testable import Talaria

struct RunsFrameParserTests {
    @Test func messageDeltaParses() {
        let e = SessionsHermesClient.parseRunsFrame(#"{"event":"message.delta","run_id":"r1","timestamp":1.0,"delta":"Hel"}"#)
        #expect(e == .messageDelta("Hel"))
    }

    @Test func toolStartedCarriesPreviewButNeverArgs() {
        let e = SessionsHermesClient.parseRunsFrame(#"{"event":"tool.started","run_id":"r1","timestamp":1.0,"tool":"write_file","preview":"O:\\Hermes\\out.txt"}"#)
        #expect(e == .toolStarted(name: "write_file", preview: #"O:\Hermes\out.txt"#))
    }

    @Test func runCompletedKeepsRawJSONForUsageDecode() throws {
        let raw = #"{"event":"run.completed","run_id":"r1","timestamp":2.0,"output":"KUMQUAT","usage":{"input_tokens":10,"output_tokens":2,"total_tokens":12}}"#
        let e = try #require(SessionsHermesClient.parseRunsFrame(raw))
        guard case let .runCompleted(output, rawJSON) = e else {
            Issue.record("expected runCompleted, got \(e)"); return
        }
        #expect(output == "KUMQUAT")
        let usage = SessionsHermesClient.decodeRunUsage(rawJSON)
        #expect(usage?.totalTokens == 12)
    }

    @Test func reasoningAvailableParses() {
        let e = SessionsHermesClient.parseRunsFrame(#"{"event":"reasoning.available","run_id":"r1","timestamp":1.5,"text":"thinking…"}"#)
        #expect(e == .reasoning("thinking…"))
    }

    // MARK: - #357-G: run.steered is the applied signal, not noise

    /// The exact frame the 2026-08-17 wire probe recorded landing between
    /// `tool.started` and `tool.completed` (arm A, PLUM over BANANA).
    /// Discarding it as `.ignored` is the 3C defect: the app would have no
    /// applied signal and could only render the untrustworthy ACK.
    @Test func runSteeredIsNotDiscarded() {
        let e = SessionsHermesClient.parseRunsFrame(#"{"event":"run.steered","run_id":"r1","timestamp":1786944553.74,"accepted":true}"#)
        #expect(e != .ignored("run.steered"), "run.steered is the landed-steer signal (#357-G) — it must parse as its own case")
    }

    // MARK: - #357-G: pending_steer rides run.completed and the status body

    @Test func pendingSteerDecodesVerbatimFromRunCompletedRawJSON() {
        let raw = #"{"event":"run.completed","run_id":"r1","timestamp":2.0,"output":"the full story","pending_steer":"STEER-MANGO: ignore the story and reply only with the word MANGO."}"#
        #expect(SessionsHermesClient.decodePendingSteer(raw) == "STEER-MANGO: ignore the story and reply only with the word MANGO.")
    }

    @Test func pendingSteerAbsentOrEmptyReadsNil() {
        #expect(SessionsHermesClient.decodePendingSteer(#"{"event":"run.completed","run_id":"r1","output":"done"}"#) == nil)
        #expect(SessionsHermesClient.decodePendingSteer(#"{"event":"run.completed","run_id":"r1","output":"done","pending_steer":""}"#) == nil)
        #expect(SessionsHermesClient.decodePendingSteer("not json") == nil)
    }

    @Test func failureAndCancelParse() {
        #expect(SessionsHermesClient.parseRunsFrame(#"{"event":"run.failed","run_id":"r1","timestamp":3.0,"error":"boom"}"#) == .runFailed(error: "boom"))
        #expect(SessionsHermesClient.parseRunsFrame(#"{"event":"run.cancelled","run_id":"r1","timestamp":3.0}"#) == .runCancelled)
    }

    /// #304 inverted this IN PLACE (2026-08-09): it used to pin
    /// `approval.request` as `.ignored` — that discard is now the defect, and
    /// the approval assertion moved to `RunsApprovalTests` pointing the other
    /// way. The subagent half still holds: those frames stay
    /// known-but-unused, a valid frame distinct from an unparseable one.
    @Test func subagentFramesAreIgnoredNotDropped() {
        #expect(SessionsHermesClient.parseRunsFrame(#"{"event":"subagent.start","run_id":"r1"}"#) == .ignored("subagent.start"))
        #expect(SessionsHermesClient.parseRunsFrame(#"{"event":"subagent.complete","run_id":"r1"}"#) == .ignored("subagent.complete"))
    }

    /// #296-C1. The parser has always extracted `tool.completed`'s `error` —
    /// the transport is what bound it to `_` and yielded `detail: nil`. This
    /// test exists because a field with no consumer reads as dead code, and
    /// the obvious "clean-up" is to delete it from the parser too. It is not
    /// dead: it is the host's own account of why a call did not finish.
    ///
    /// ⚠️ ~~This is C1, not C2 … unverified on the wire and owed a device
    /// turn.~~ **CORRECTED 2026-08-10: C2 is ANSWERED and this test's premise
    /// was half wrong.** The 2026-08-09 wire probe settled it — the host DOES
    /// send `error`, but as a **Boolean**, never as text. So no host has yet
    /// been observed sending the String this fixture feeds.
    ///
    /// The test still earns its place, and is deliberately left GREEN and
    /// unmodified: it is now the **forward-compatibility arm** of the union
    /// (bar C1-B). A future host build may upgrade the flag to a real message,
    /// and when it does this is the test that says the message must survive
    /// verbatim rather than being flattened into the generic. The Boolean the
    /// host actually sends is pinned separately, below.
    @Test func toolCompletedCarriesTheHostError() {
        let e = SessionsHermesClient.parseRunsFrame(
            #"{"event":"tool.completed","run_id":"r1","timestamp":2.0,"tool":"terminal","error":"[Command interrupted] exit_code 130"}"#
        )
        #expect(e == .toolCompleted(name: "terminal", error: "[Command interrupted] exit_code 130"))
    }

    /// The ordinary frame — no `error` key at all — still parses, with a nil
    /// error rather than a throw. That is the shape the sessions-plane host
    /// was verified to send. ~~and the runs plane is assumed to match until
    /// 296-C2 says otherwise.~~ **CORRECTED 2026-08-10 — 296-C2 has now said
    /// otherwise:** the runs plane does NOT match, it sends `"error": true` on
    /// a failed or stopped call. This frame remains the shape of an ordinary
    /// SUCCESS, so the assertion stands; what changed is that it is no longer
    /// the only shape this parser must handle.
    @Test func toolCompletedWithoutAnErrorKeyParsesWithNilError() {
        let e = SessionsHermesClient.parseRunsFrame(
            #"{"event":"tool.completed","run_id":"r1","timestamp":2.0,"tool":"terminal"}"#
        )
        #expect(e == .toolCompleted(name: "terminal", error: nil))
    }

    // MARK: - #296-C1, REOPENED BY THE WIRE (2026-08-10)

    /// **The frame the host actually sends.** The 2026-08-09 probe on the Mac's
    /// `:8642` (`POST /v1/runs` with a tool call that fails ordinarily, raw SSE
    /// read off `GET /v1/runs/{id}/events`) caught the third option nobody
    /// pre-registered: `error` arrives as a JSON **boolean**, carrying the FACT
    /// of a failure and no words for it. `payload["error"] as? String` returns
    /// nil for a `Bool`, so a failed — or DENIED — tool reached the chip as a
    /// clean completion and rendered a ✓. #296's own defect, arriving through
    /// #296's own plumbing.
    ///
    /// The fixture is the captured frame's **byte-shape verbatim** — spaces
    /// after the colons, float `timestamp`, the `duration` key, and an
    /// unquoted `true` — with only `run_id` shortened. A fixture that
    /// re-typed the JSON compactly would still have caught this one, but the
    /// point of a wire-capture test is that it cannot quietly drift from the
    /// wire.
    ///
    /// The expected text is pinned as a LITERAL rather than read from the
    /// production constant, for two reasons: it kept this test compiling
    /// against unmodified HEAD so the RED failed on the value (`nil`) instead
    /// of on a missing symbol, and it is user-facing copy — a test that reads
    /// the constant cannot notice the constant changing.
    @Test func toolCompletedBooleanErrorIsAFailureNotACleanCompletion() throws {
        let e = try #require(SessionsHermesClient.parseRunsFrame(
            #"{"event": "tool.completed", "run_id": "run-r1", "timestamp": 1786304648.615377, "tool": "terminal", "duration": 0.13, "error": true}"#
        ))
        guard case let .toolCompleted(name, error) = e else {
            Issue.record("expected toolCompleted, got \(e)"); return
        }
        #expect(name == "terminal")
        #expect(
            error != nil,
            "296-C1: `error: true` is the host reporting a failure — dropping it renders a failed tool as a clean ✓"
        )
        // No fabricated reason: the wire carries no message, so the detail says
        // that something failed and does not invent why.
        #expect(error == "The host reported an error.")
    }

    /// C1-C, the arm that keeps the fix honest in the other direction:
    /// `error: false` is a host saying nothing went wrong, and must behave
    /// exactly like an absent key. A fix that treated ANY `Bool` as a failure
    /// would turn every clean completion into an interrupted chip — #296's
    /// defect inverted, which is 296-B's whole concern.
    @Test func toolCompletedWithErrorFalseParsesWithNilError() {
        let e = SessionsHermesClient.parseRunsFrame(
            #"{"event": "tool.completed", "run_id": "run-r1", "timestamp": 2.0, "tool": "terminal", "duration": 0.05, "error": false}"#
        )
        #expect(e == .toolCompleted(name: "terminal", error: nil))
    }

    /// C1-C, the tolerant tail. A type this build has never seen on that field
    /// is "no failure reported", never a throw and never a guess — the same
    /// forward-tolerance the rest of this parser is built on.
    @Test func toolCompletedWithAnUnexpectedErrorTypeIsTreatedAsAbsent() {
        #expect(
            SessionsHermesClient.parseRunsFrame(
                #"{"event":"tool.completed","run_id":"r1","timestamp":2.0,"tool":"terminal","error":{"code":7}}"#
            ) == .toolCompleted(name: "terminal", error: nil)
        )
        #expect(
            SessionsHermesClient.parseRunsFrame(
                #"{"event":"tool.completed","run_id":"r1","timestamp":2.0,"tool":"terminal","error":7}"#
            ) == .toolCompleted(name: "terminal", error: nil)
        )
    }

    // MARK: - #296-C1: the SECOND site — the status snapshot

    /// `RunStatusSnapshot` reads the same field with the same `as? String` and
    /// drops a Bool the same way. It is the quieter of the two sites — the
    /// dropped value there produced `runFailureText("")`, i.e. an honest
    /// generic rather than a lie — but it is the same type bug, and a host that
    /// only ever says `true` should not read as "reported nothing".
    @Test func runStatusSnapshotBooleanErrorIsCarriedNotDropped() throws {
        let snapshot = try #require(SessionsHermesClient.RunStatusSnapshot(
            Data(#"{"object":"hermes.run","run_id":"run-r1","status":"failed","error":true}"#.utf8)
        ))
        #expect(snapshot.status == "failed")
        #expect(snapshot.error == "The host reported an error.")
    }

    /// C1-B at the second site: a String still carries verbatim.
    @Test func runStatusSnapshotStringErrorStillCarriesVerbatim() throws {
        let snapshot = try #require(SessionsHermesClient.RunStatusSnapshot(
            Data(#"{"object":"hermes.run","run_id":"run-r1","status":"failed","error":"provider timed out"}"#.utf8)
        ))
        #expect(snapshot.error == "provider timed out")
    }

    /// C1-C at the second site: absent and `false` both stay "no error".
    @Test func runStatusSnapshotWithoutAnErrorReportsNone() throws {
        let absent = try #require(SessionsHermesClient.RunStatusSnapshot(
            Data(#"{"object":"hermes.run","run_id":"run-r1","status":"completed","output":"done"}"#.utf8)
        ))
        #expect(absent.error == nil)
        let negative = try #require(SessionsHermesClient.RunStatusSnapshot(
            Data(#"{"object":"hermes.run","run_id":"run-r1","status":"completed","error":false}"#.utf8)
        ))
        #expect(negative.error == nil)
    }

    @Test func garbageReturnsNil() {
        #expect(SessionsHermesClient.parseRunsFrame("not json") == nil)
        #expect(SessionsHermesClient.parseRunsFrame(#"{"no_event_key":true}"#) == nil)
    }
}
