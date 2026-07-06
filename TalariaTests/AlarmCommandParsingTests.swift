import Foundation
import Testing
@testable import Talaria

/// #16: the /alarm argument grammar. Parsing is pure and nonisolated — no
/// AlarmKit runtime involved, so the whole surface pins down deterministically.
struct AlarmCommandParsingTests {

    // MARK: - Durations (countdown timers)

    @Test func parsesMinuteDuration() async throws {
        let request = try #require(AlarmService.parse("25m"))
        #expect(request.kind == .countdown(1_500))
        #expect(request.label == nil)
        #expect(request.kindNoun == "timer")
    }

    @Test func parsesCompoundDurationWithLabel() async throws {
        let request = try #require(AlarmService.parse("1h30m slow roast"))
        #expect(request.kind == .countdown(5_400))
        #expect(request.label == "slow roast")
    }

    @Test func parsesSecondsAndMinSuffix() async throws {
        #expect(AlarmService.parse("90s")?.kind == .countdown(90))
        #expect(AlarmService.parse("10min tea")?.kind == .countdown(600))
        #expect(AlarmService.parse("10min tea")?.label == "tea")
    }

    // MARK: - Wall-clock times (alarms)

    @Test func parsesColonTimeAsNextOccurrence() async throws {
        let request = try #require(AlarmService.parse("6:30"))
        #expect(request.kind == .fixedTime(hour: 6, minute: 30))
        #expect(request.kindNoun == "alarm")
    }

    @Test func parsesMeridiemForms() async throws {
        #expect(AlarmService.parse("6:30pm")?.kind == .fixedTime(hour: 18, minute: 30))
        #expect(AlarmService.parse("7pm")?.kind == .fixedTime(hour: 19, minute: 0))
        #expect(AlarmService.parse("12am")?.kind == .fixedTime(hour: 0, minute: 0))
        #expect(AlarmService.parse("12pm")?.kind == .fixedTime(hour: 12, minute: 0))
        #expect(AlarmService.parse("18:45")?.kind == .fixedTime(hour: 18, minute: 45))
    }

    @Test func foldsStandaloneMeridiemToken() async throws {
        let request = try #require(AlarmService.parse("6:30 pm wake up"))
        #expect(request.kind == .fixedTime(hour: 18, minute: 30))
        #expect(request.label == "wake up")
    }

    // MARK: - Rejections

    @Test func rejectsAmbiguousAndInvalidInput() async throws {
        // Bare numbers are ambiguous (7 o'clock? 7 minutes?) — rejected.
        #expect(AlarmService.parse("7") == nil)
        #expect(AlarmService.parse("") == nil)
        #expect(AlarmService.parse("soon") == nil)
        // Out-of-range clock values.
        #expect(AlarmService.parse("25:00") == nil)
        #expect(AlarmService.parse("6:75") == nil)
        #expect(AlarmService.parse("13pm") == nil)
        // Zero-length timer.
        #expect(AlarmService.parse("0m") == nil)
    }

    // MARK: - Next occurrence

    @Test func nextOccurrenceRollsToTomorrowWhenPast() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let reference = calendar.date(from: DateComponents(year: 2026, month: 7, day: 6, hour: 12))!

        let morning = try #require(AlarmService.nextOccurrence(hour: 6, minute: 30, after: reference, calendar: calendar))
        #expect(calendar.dateComponents([.day, .hour, .minute], from: morning) == DateComponents(day: 7, hour: 6, minute: 30))

        let evening = try #require(AlarmService.nextOccurrence(hour: 18, minute: 0, after: reference, calendar: calendar))
        #expect(calendar.dateComponents([.day, .hour, .minute], from: evening) == DateComponents(day: 6, hour: 18, minute: 0))
    }
}
