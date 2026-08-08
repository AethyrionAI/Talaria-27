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

    @Test func approvalAndSubagentAreIgnoredNotDropped() {
        #expect(SessionsHermesClient.parseRunsFrame(#"{"event":"approval.request","run_id":"r1","command":"rm -rf /tmp/x","choices":["once"]}"#) == .ignored("approval.request"))
        #expect(SessionsHermesClient.parseRunsFrame(#"{"event":"subagent.start","run_id":"r1"}"#) == .ignored("subagent.start"))
    }

    @Test func garbageReturnsNil() {
        #expect(SessionsHermesClient.parseRunsFrame("not json") == nil)
        #expect(SessionsHermesClient.parseRunsFrame(#"{"no_event_key":true}"#) == nil)
    }
}
