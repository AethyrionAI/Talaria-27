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

    /// #234: THE observed input, pinned verbatim. A PIN, not a fix — the tool
    /// half was always correct; the defect was argument-time nearest-fit one
    /// boundary up (the model snapping to 'tomorrow' because the guide
    /// advertised no third state).
    @Test func dayAfterTomorrowIsPinnedUnsupported() {
        #expect(WeatherTool.requestedDay(from: "day after tomorrow") == .unsupported)
        #expect(WeatherTool.requestedDay(from: " Day After Tomorrow ") == .unsupported)
        #expect(WeatherTool.requestedDay(from: "the day after tomorrow") == .unsupported)
    }

    /// #234-A: the guide must name the beyond-tomorrow boundary AND the
    /// pass-through rule — the model needs an ADVERTISED way to express a
    /// later day, or it snaps to the nearest advertised value. Same pinning
    /// pattern as `theDescriptionAdvertisesTomorrow`: a guide edit is a
    /// deliberate act.
    @Test func theDayGuideNamesTheBoundaryAndThePassThroughRule() {
        let guide = WeatherTool.dayGuideText.lowercased()
        #expect(guide.contains("beyond tomorrow"))
        #expect(guide.contains("pass") && guide.contains("unchanged"))
        #expect(guide.contains("never substitute"))
        #expect(guide.contains("day after tomorrow"))
    }

    // MARK: - The contract text

    /// The description must ADVERTISE tomorrow, or the model keeps treating
    /// the demand as unmeetable and displacing (#216). Pinned so a description
    /// edit is a deliberate act.
    @Test func theDescriptionAdvertisesTomorrow() {
        #expect(WeatherTool.productionDescription.lowercased().contains("tomorrow"))
    }

    // MARK: - The tomorrow line (pure)

    @Test func tomorrowLineCarriesTheRealForecastNumbersAndItsDate() {
        // #234-B: the line names its own calendar date, so a relay that
        // mislabels the day contradicts itself on its face.
        var comps = DateComponents(); comps.year = 2026; comps.month = 8; comps.day = 5
        let date = Calendar(identifier: .gregorian).date(from: comps)!
        let line = WeatherTool.tomorrowForecastLine(
            label: "Gulfport", condition: "Mostly cloudy",
            high: "88°F", low: "77°F", precipPercent: 56, date: date)
        #expect(line == "Tomorrow (Aug 5) at Gulfport: Mostly cloudy, high 88°F, low 77°F, 56% chance of precipitation")
    }

    @Test func unsupportedDayAnswerNamesTheLimitHonestly() {
        let answer = WeatherTool.unsupportedDayAnswer(requested: "friday")
        #expect(answer.contains("today") && answer.contains("tomorrow"))
        #expect(answer.contains("friday"))
    }
}
