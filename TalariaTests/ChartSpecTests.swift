import Foundation
import Testing
@testable import Talaria

/// OPEN_ITEMS #100 PR 1 — `ChartSpec.decode` tolerance: every structural
/// problem returns nil (→ code-block fallback), never a crash or a guessed
/// chart; plus the Path B table-promotion predicate.
struct ChartSpecTests {

    // MARK: - Valid specs

    @Test func decodesFullLineSpec() throws {
        let json = """
        {"type":"line","title":"Resting HR, 7d",
         "x":{"label":"Day","values":["Mon","Tue","Wed"]},
         "y":{"label":"bpm"},
         "series":[{"name":"bpm","values":[58,61,57]}]}
        """
        let spec = try #require(ChartSpec.decode(fenceBody: json))
        #expect(spec.kind == .line)
        #expect(spec.title == "Resting HR, 7d")
        #expect(spec.xLabel == "Day")
        #expect(spec.xValues == ["Mon", "Tue", "Wed"])
        #expect(spec.yLabel == "bpm")
        #expect(spec.series.count == 1)
        #expect(spec.series.first?.name == "bpm")
        #expect(spec.series.first?.values == [58, 61, 57])
    }

    @Test(arguments: [("line", ChartKind.line), ("bar", .bar), ("area", .area), ("point", .point)])
    func decodesEachKind(type: String, expected: ChartKind) throws {
        let json = #"{"type":"\#(type)","x":{"values":["a","b"]},"series":[{"values":[1,2]}]}"#
        let spec = try #require(ChartSpec.decode(fenceBody: json))
        #expect(spec.kind == expected)
    }

    @Test func typeIsCaseAndWhitespaceInsensitive() throws {
        let json = #"{"type":" Bar ","x":{"values":["a","b"]},"series":[{"values":[1,2]}]}"#
        let spec = try #require(ChartSpec.decode(fenceBody: json))
        #expect(spec.kind == .bar)
    }

    @Test func optionalFieldsMayBeOmitted() throws {
        let json = #"{"type":"point","x":{"values":["a","b"]},"series":[{"values":[1,2]}]}"#
        let spec = try #require(ChartSpec.decode(fenceBody: json))
        #expect(spec.title == nil)
        #expect(spec.xLabel == nil)
        #expect(spec.yLabel == nil)
        #expect(spec.series.first?.name == nil)
    }

    @Test func numericXValuesBecomeStrings() throws {
        let json = #"{"type":"line","x":{"values":[1,2,3.5]},"series":[{"values":[4,5,6]}]}"#
        let spec = try #require(ChartSpec.decode(fenceBody: json))
        #expect(spec.xValues == ["1", "2", "3.5"])
    }

    @Test func unknownExtraKeysAreIgnored() throws {
        let json = #"{"type":"bar","legend":true,"x":{"values":["a","b"],"scale":"log"},"series":[{"values":[1,2],"color":"red"}]}"#
        #expect(ChartSpec.decode(fenceBody: json) != nil)
    }

    @Test func multiSeriesDecodes() throws {
        let json = """
        {"type":"line","x":{"values":["a","b","c"]},
         "series":[{"name":"one","values":[1,2,3]},{"name":"two","values":[4,5,6]}]}
        """
        let spec = try #require(ChartSpec.decode(fenceBody: json))
        #expect(spec.series.map(\.name) == ["one", "two"])
    }

    // MARK: - Failure paths (all nil, never a crash)

    @Test func malformedJSONFails() {
        #expect(ChartSpec.decode(fenceBody: #"{"type":"line","x":{"values":["a"#) == nil)
    }

    @Test func emptyBodyFails() {
        #expect(ChartSpec.decode(fenceBody: "") == nil)
        #expect(ChartSpec.decode(fenceBody: "   \n  ") == nil)
    }

    @Test func unknownTypeFails() {
        let json = #"{"type":"pie","x":{"values":["a","b"]},"series":[{"values":[1,2]}]}"#
        #expect(ChartSpec.decode(fenceBody: json) == nil)
    }

    @Test func missingTypeFails() {
        let json = #"{"x":{"values":["a","b"]},"series":[{"values":[1,2]}]}"#
        #expect(ChartSpec.decode(fenceBody: json) == nil)
    }

    @Test func emptySeriesListFails() {
        let json = #"{"type":"line","x":{"values":["a","b"]},"series":[]}"#
        #expect(ChartSpec.decode(fenceBody: json) == nil)
    }

    @Test func missingSeriesFails() {
        let json = #"{"type":"line","x":{"values":["a","b"]}}"#
        #expect(ChartSpec.decode(fenceBody: json) == nil)
    }

    @Test func emptySeriesValuesFails() {
        let json = #"{"type":"line","x":{"values":["a","b"]},"series":[{"values":[]}]}"#
        #expect(ChartSpec.decode(fenceBody: json) == nil)
    }

    @Test func raggedSeriesLengthsFail() {
        let json = #"{"type":"line","x":{"values":["a","b","c"]},"series":[{"values":[1,2]}]}"#
        #expect(ChartSpec.decode(fenceBody: json) == nil)
    }

    @Test func oneRaggedSeriesAmongValidOnesFails() {
        let json = """
        {"type":"line","x":{"values":["a","b"]},
         "series":[{"values":[1,2]},{"values":[3]}]}
        """
        #expect(ChartSpec.decode(fenceBody: json) == nil)
    }

    @Test func missingXFails() {
        let json = #"{"type":"line","series":[{"values":[1,2]}]}"#
        #expect(ChartSpec.decode(fenceBody: json) == nil)
    }

    @Test func emptyXValuesFail() {
        let json = #"{"type":"line","x":{"values":[]},"series":[{"values":[]}]}"#
        #expect(ChartSpec.decode(fenceBody: json) == nil)
    }

    @Test func nonNumericSeriesValuesFail() {
        let json = #"{"type":"line","x":{"values":["a","b"]},"series":[{"values":["58","61"]}]}"#
        #expect(ChartSpec.decode(fenceBody: json) == nil)
    }

    @Test func overBudgetSeriesCountFails() {
        let count = ChartSpec.maxSeries + 1
        let series = (0..<count).map { _ in #"{"values":[1,2]}"# }.joined(separator: ",")
        let json = #"{"type":"bar","x":{"values":["a","b"]},"series":[\#(series)]}"#
        #expect(ChartSpec.decode(fenceBody: json) == nil)
    }

    @Test func atBudgetSeriesCountDecodes() {
        let series = (0..<ChartSpec.maxSeries).map { _ in #"{"values":[1,2]}"# }.joined(separator: ",")
        let json = #"{"type":"bar","x":{"values":["a","b"]},"series":[\#(series)]}"#
        #expect(ChartSpec.decode(fenceBody: json) != nil)
    }

    @Test func overBudgetPointCountFails() {
        let count = ChartSpec.maxPointsPerSeries + 1
        let xValues = (0..<count).map { #""\#($0)""# }.joined(separator: ",")
        let values = (0..<count).map(String.init).joined(separator: ",")
        let json = #"{"type":"line","x":{"values":[\#(xValues)]},"series":[{"values":[\#(values)]}]}"#
        #expect(ChartSpec.decode(fenceBody: json) == nil)
    }

    @Test func atBudgetPointCountDecodes() {
        let count = ChartSpec.maxPointsPerSeries
        let xValues = (0..<count).map { #""\#($0)""# }.joined(separator: ",")
        let values = (0..<count).map(String.init).joined(separator: ",")
        let json = #"{"type":"line","x":{"values":[\#(xValues)]},"series":[{"values":[\#(values)]}]}"#
        #expect(ChartSpec.decode(fenceBody: json) != nil)
    }

    // MARK: - Render support (PR 2)

    @Test func displayNamesFillUnnamedSeriesAndDedupe() {
        let spec = ChartSpec(
            kind: .line, title: nil, xLabel: nil, xValues: ["a", "b"], yLabel: nil,
            series: [
                .init(name: "bpm", values: [1, 2]),
                .init(name: nil, values: [3, 4]),
                .init(name: "bpm", values: [5, 6]),
            ]
        )
        #expect(spec.seriesDisplayNames == ["bpm", "Series 2", "bpm (2)"])
    }

    @Test func accessibilitySummaryNamesKindTitleSeriesAndRange() throws {
        let json = """
        {"type":"line","title":"Resting HR, 7d",
         "x":{"values":["Mon","Tue","Wed"]},
         "series":[{"name":"bpm","values":[58,61,57]}]}
        """
        let spec = try #require(ChartSpec.decode(fenceBody: json))
        #expect(spec.accessibilitySummary == "Line chart: Resting HR, 7d. Series bpm. 3 points from Mon to Wed.")
    }

    @Test func accessibilitySummaryWithoutOptionals() throws {
        let json = #"{"type":"point","x":{"values":["a","b"]},"series":[{"values":[1,2]},{"values":[3,4]}]}"#
        let spec = try #require(ChartSpec.decode(fenceBody: json))
        #expect(spec.accessibilitySummary == "Scatter chart. 2 series: Series 1, Series 2. 2 points from a to b.")
    }

    // MARK: - Path B: table promotion

    @Test func numericTableIsChartable() throws {
        let header = ["Day", "bpm"]
        let rows = [["Mon", "58"], ["Tue", "61"], ["Wed", "57"]]
        #expect(ChartSpec.isChartable(header: header, rows: rows))

        let spec = try #require(ChartSpec.promoted(header: header, rows: rows))
        #expect(spec.kind == .bar)
        #expect(spec.xLabel == "Day")
        #expect(spec.xValues == ["Mon", "Tue", "Wed"])
        #expect(spec.yLabel == "bpm")
        #expect(spec.series.count == 1)
        #expect(spec.series.first?.name == "bpm")
        #expect(spec.series.first?.values == [58, 61, 57])
    }

    @Test func multiColumnTablePromotesToMultipleSeries() throws {
        let header = ["Month", "Input", "Output"]
        let rows = [["May", "1200", "300"], ["Jun", "1500", "420"]]
        let spec = try #require(ChartSpec.promoted(header: header, rows: rows))
        #expect(spec.series.map(\.name) == ["Input", "Output"])
        #expect(spec.series.map(\.values) == [[1200, 1500], [300, 420]])
        // Multi-series: the legend names the series; no single y label applies.
        #expect(spec.yLabel == nil)
    }

    @Test func thousandsSeparatorsParse() {
        #expect(ChartSpec.numericCell("1,234") == 1234)
        #expect(ChartSpec.numericCell("1,234,567.5") == 1234567.5)
        #expect(ChartSpec.numericCell("-1,234") == -1234)
        // Commas that don't group as thousands are not numbers.
        #expect(ChartSpec.numericCell("1,2,3") == nil)
    }

    @Test func nonNumericCellsRejected() {
        #expect(ChartSpec.numericCell("") == nil)
        #expect(ChartSpec.numericCell("n/a") == nil)
        #expect(ChartSpec.numericCell("58%") == nil)
        #expect(ChartSpec.numericCell("5 bpm") == nil)
        #expect(ChartSpec.numericCell("nan") == nil)
        #expect(ChartSpec.numericCell("inf") == nil)
    }

    @Test func mixedColumnTableIsNotChartable() {
        let rows = [["Mon", "58"], ["Tue", "n/a"]]
        #expect(!ChartSpec.isChartable(header: ["Day", "bpm"], rows: rows))
    }

    @Test func singleRowTableIsNotChartable() {
        #expect(!ChartSpec.isChartable(header: ["Day", "bpm"], rows: [["Mon", "58"]]))
    }

    @Test func emptyTableIsNotChartable() {
        #expect(!ChartSpec.isChartable(header: ["Day", "bpm"], rows: []))
    }

    @Test func singleColumnTableIsNotChartable() {
        #expect(!ChartSpec.isChartable(header: ["bpm"], rows: [["58"], ["61"]]))
    }

    @Test func overBudgetTableIsNotChartable() {
        let header = ["x"] + (0..<(ChartSpec.maxSeries + 1)).map { "s\($0)" }
        let row = ["label"] + (0..<(ChartSpec.maxSeries + 1)).map { "\($0)" }
        #expect(!ChartSpec.isChartable(header: header, rows: [row, row]))
    }
}
