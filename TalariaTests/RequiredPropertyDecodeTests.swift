import FoundationModels
import Testing
@testable import Talaria

/// #209 — the missing-required-property decode failure, pinned from the exact
/// payloads production recorded.
///
/// Thirteen trials across the retained run JSONs died on
/// `GeneratedContent does not contain a property 'X'`, and the run records
/// carry the content the model actually emitted. Those payloads are reproduced
/// VERBATIM below — not invented — so these tests fail for the same reason real
/// turns did.
///
/// The optional/required pairs are the point: each rollback twin still throws
/// on the payload that killed production, and each promoted schema accepts it.
/// That is the guarantee this change actually makes — the failure class becomes
/// structurally impossible, not merely less likely. It is not a rate claim: at
/// 1.4% on the worst cell (`armed/haiku`, 5/350) no battery we can run could
/// resolve the difference, which is exactly why the proof belongs here.
struct RequiredPropertyDecodeTests {

    // MARK: readHealth — `metric`, 5 occurrences, every one with content `{}`

    @Test func emptyObjectDecodesForTheOptionalMetricSchema() throws {
        let content = try GeneratedContent(json: "{}")
        let args = try DeviceHealthTool.Arguments(content)
        #expect(args.metric == nil)
    }

    @Test func emptyObjectStillKillsTheRequiredMetricRollback() throws {
        let content = try GeneratedContent(json: "{}")
        #expect(throws: (any Error).self) {
            _ = try DeviceHealthToolRequiredMetric.Arguments(content)
        }
    }

    @Test func anExplicitMetricIsUnchangedByTheOptionalSchema() throws {
        let content = try GeneratedContent(json: #"{"metric": "steps"}"#)
        #expect(try DeviceHealthTool.Arguments(content).metric == "steps")
    }

    /// nil and "" must reach the SAME place, or the fix would silently change
    /// behaviour for well-formed calls instead of only rescuing broken ones.
    @Test func omittedAndEmptyMetricNormalizeIdentically() {
        #expect(DeviceHealthTool.normalizedMetric(nil) == "")
        #expect(DeviceHealthTool.normalizedMetric("") == "")
        #expect(DeviceHealthTool.normalizedMetric("  SUMMARY ") == "summary")
    }

    // MARK: currentWeather — `place`, 2 occurrences, content `{}`
    //
    // The starkest case: this tool's @Guide has always said "Optional… Leave
    // empty", while the type said required. The model obeyed the prose.

    @Test func emptyObjectDecodesForTheOptionalPlaceSchema() throws {
        let content = try GeneratedContent(json: "{}")
        #expect(try WeatherTool.Arguments(content).place == nil)
    }

    @Test func emptyObjectStillKillsTheRequiredPlaceRollback() throws {
        let content = try GeneratedContent(json: "{}")
        #expect(throws: (any Error).self) {
            _ = try WeatherToolRequiredPlace.Arguments(content)
        }
    }

    @Test func anExplicitPlaceIsUnchangedByTheOptionalSchema() throws {
        let content = try GeneratedContent(json: #"{"place": "Biloxi"}"#)
        #expect(try WeatherTool.Arguments(content).place == "Biloxi")
    }

    // MARK: `title` stays REQUIRED — a deliberate decision, pinned as one
    //
    // Four reminder trials and one calendar trial died on a missing `title`,
    // and the reminder payloads below are verbatim: the model had already
    // produced `due` and `list` and dropped only the field carrying what the
    // reminder is ABOUT. Optionality is the wrong fix — a defaulted title
    // would invent user data, which #202D measured as the worst failure mode
    // available. The schema should demand exactly what the tool cannot
    // default, and this pins that these two still refuse.

    @Test func reminderWithoutATitleStillRefusesToDecode() throws {
        let content = try GeneratedContent(json: #"{"due": "2026-07-29T10:00", "list": ""}"#)
        #expect(throws: (any Error).self) {
            _ = try ReminderCreateTool.Arguments(content)
        }
    }

    @Test func calendarEventWithoutATitleStillRefusesToDecode() throws {
        let content = try GeneratedContent(json: "{}")
        #expect(throws: (any Error).self) {
            _ = try CalendarEventTool.Arguments(content)
        }
    }

    /// The promoted calendar tool must still accept the payload its ROLLBACK
    /// twin died on — `durationMinutes` absent. This is the #200X natural
    /// experiment that the error records surfaced, pinned so it cannot regress.
    @Test func promotedCalendarAcceptsWhatTheRequiredFieldsTwinRejected() throws {
        let json = #"{"location": "19200 Crestwick St, Saucier, MS, United States", "startsAt": "2026-07-31T12:00", "title": "Lunch with Sam"}"#
        let content = try GeneratedContent(json: json)
        let args = try CalendarEventTool.Arguments(content)
        #expect(args.title == "Lunch with Sam")
        #expect(args.durationMinutes == nil)
        #expect(throws: (any Error).self) {
            _ = try CalendarEventToolRequiredFields.Arguments(content)
        }
    }
}
