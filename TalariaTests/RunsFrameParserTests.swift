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
    /// ⚠️ This is C1, not C2. It proves the CLIENT keeps the value, and says
    /// nothing about whether the host ever sends one — that is unverified on
    /// the wire and owed a device turn.
    @Test func toolCompletedCarriesTheHostError() {
        let e = SessionsHermesClient.parseRunsFrame(
            #"{"event":"tool.completed","run_id":"r1","timestamp":2.0,"tool":"terminal","error":"[Command interrupted] exit_code 130"}"#
        )
        #expect(e == .toolCompleted(name: "terminal", error: "[Command interrupted] exit_code 130"))
    }

    /// The ordinary frame — no `error` key at all — still parses, with a nil
    /// error rather than a throw. That is the shape the sessions-plane host
    /// was verified to send, and the runs plane is assumed to match until
    /// 296-C2 says otherwise.
    @Test func toolCompletedWithoutAnErrorKeyParsesWithNilError() {
        let e = SessionsHermesClient.parseRunsFrame(
            #"{"event":"tool.completed","run_id":"r1","timestamp":2.0,"tool":"terminal"}"#
        )
        #expect(e == .toolCompleted(name: "terminal", error: nil))
    }

    @Test func garbageReturnsNil() {
        #expect(SessionsHermesClient.parseRunsFrame("not json") == nil)
        #expect(SessionsHermesClient.parseRunsFrame(#"{"no_event_key":true}"#) == nil)
    }
}
