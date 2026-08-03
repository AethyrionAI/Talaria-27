import Foundation
import Testing
@testable import Talaria

/// OPEN_ITEMS #230 — `currentWeather` learns "tomorrow."
///
/// The tool's contract was live conditions + TODAY's forecast; "tomorrow" was
/// unmeetable by the whole belt, and the unmet demand displaced into
/// `searchConversations` (#216's mechanism) and became #225's spiral, then
/// #232's grind. Lane 1 measured the cost: the same belt answered a meetable
/// weather question in ~6s and burned ~2.5min on the unmeetable one. Bar 3.1
/// (device): prompt 1 answers with a REAL forecast in < 15s, ≤ 3 calls.
///
/// These tests pin the pure halves: day parsing and the tomorrow line. The
/// WeatherKit fetch stays a thin tail (sim has no entitlement).
struct WeatherTomorrowTests {

    // MARK: - Day parsing

    @Test func absentAndTodaySpellingsMeanToday() {
        #expect(WeatherTool.requestedDay(from: nil) == .today)
        #expect(WeatherTool.requestedDay(from: "") == .today)
        #expect(WeatherTool.requestedDay(from: "today") == .today)
        #expect(WeatherTool.requestedDay(from: "now") == .today)
        #expect(WeatherTool.requestedDay(from: " Today ") == .today)
    }

    @Test func tomorrowSpellingsMeanTomorrow() {
        #expect(WeatherTool.requestedDay(from: "tomorrow") == .tomorrow)
        #expect(WeatherTool.requestedDay(from: "Tomorrow") == .tomorrow)
        #expect(WeatherTool.requestedDay(from: " TOMORROW ") == .tomorrow)
    }

    /// Real-data-only: a day the tool cannot serve is named back honestly,
    /// never silently answered with today's numbers — the date-relabel is
    /// exactly the #199-suspect shape from the verbose-off control.
    @Test func anythingElseIsUnsupported() {
        #expect(WeatherTool.requestedDay(from: "friday") == .unsupported)
        #expect(WeatherTool.requestedDay(from: "next week") == .unsupported)
    }

    // MARK: - The contract text

    /// The description must ADVERTISE tomorrow, or the model keeps treating
    /// the demand as unmeetable and displacing (#216). Pinned so a description
    /// edit is a deliberate act.
    @Test func theDescriptionAdvertisesTomorrow() {
        #expect(WeatherTool.productionDescription.lowercased().contains("tomorrow"))
    }

    // MARK: - The tomorrow line (pure)

    @Test func tomorrowLineCarriesTheRealForecastNumbers() {
        let line = WeatherTool.tomorrowForecastLine(
            label: "Gulfport", condition: "Mostly cloudy",
            high: "88°F", low: "77°F", precipPercent: 56)
        #expect(line == "Tomorrow at Gulfport: Mostly cloudy, high 88°F, low 77°F, 56% chance of precipitation")
    }

    @Test func unsupportedDayAnswerNamesTheLimitHonestly() {
        let answer = WeatherTool.unsupportedDayAnswer(requested: "friday")
        #expect(answer.contains("today") && answer.contains("tomorrow"))
        #expect(answer.contains("friday"))
    }
}
