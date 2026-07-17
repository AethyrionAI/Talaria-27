import Foundation

/// The chart types the inline chart surface renders (OPEN_ITEMS #100).
/// Decoded permissively from the spec's `type` (trimmed, case-insensitive);
/// anything unrecognized fails the whole decode so the fence falls back to a
/// code block — never a guessed chart type.
enum ChartKind: String, Equatable, Sendable {
    case line, bar, area, point
}

/// A chart specification carried by a ```chart fenced block (OPEN_ITEMS #100):
///
///     {"type":"line","title":"Resting HR, 7d",
///      "x":{"label":"Day","values":["Mon","Tue","Wed"]},
///      "y":{"label":"bpm"},
///      "series":[{"name":"bpm","values":[58,61,57]}]}
///
/// Decoding is tolerant in the house sense: one bad field never poisons the
/// render — it fails the whole decode cleanly and the parser keeps the
/// original fence as a code block, so the user always sees the data.
/// `decode(fenceBody:)` is the only entry point and returns nil for malformed
/// JSON, an unknown type, missing/empty x values, empty or ragged series,
/// non-finite values, or anything over the series/point budget.
struct ChartSpec: Equatable, Sendable {

    struct Series: Equatable, Sendable {
        var name: String?
        var values: [Double]
    }

    /// Budget caps — a phone should refuse a 50k-point line, not attempt it.
    /// Over-budget specs fail decode and fall back to the code block.
    static let maxSeries = 8
    static let maxPointsPerSeries = 500

    var kind: ChartKind
    var title: String?
    var xLabel: String?
    var xValues: [String]
    var yLabel: String?
    var series: [Series]

    init(kind: ChartKind, title: String?, xLabel: String?, xValues: [String], yLabel: String?, series: [Series]) {
        self.kind = kind
        self.title = title
        self.xLabel = xLabel
        self.xValues = xValues
        self.yLabel = yLabel
        self.series = series
    }

    /// Decodes and validates the body of a closed ```chart fence.
    static func decode(fenceBody: String) -> ChartSpec? {
        let trimmed = fenceBody.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return nil }
        return ChartSpec(validating: payload)
    }

    private init?(validating payload: Payload) {
        guard let type = payload.type,
              let kind = ChartKind(rawValue: type.trimmingCharacters(in: .whitespaces).lowercased()) else { return nil }

        let xValues = (payload.x?.values ?? []).map(\.text)
        guard !xValues.isEmpty, xValues.count <= Self.maxPointsPerSeries else { return nil }

        let series = (payload.series ?? []).map { Series(name: Self.normalized($0.name), values: $0.values ?? []) }
        guard !series.isEmpty, series.count <= Self.maxSeries else { return nil }
        guard series.allSatisfy({ $0.values.count == xValues.count }) else { return nil }
        guard series.allSatisfy({ $0.values.allSatisfy(\.isFinite) }) else { return nil }

        self.kind = kind
        self.title = Self.normalized(payload.title)
        self.xLabel = Self.normalized(payload.x?.label)
        self.xValues = xValues
        self.yLabel = Self.normalized(payload.y?.label)
        self.series = series
    }

    private static func normalized(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespaces), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    // MARK: - Wire payload

    /// Loose wire shape: everything optional so structural problems converge
    /// on the validating init's nil instead of scattering decode throws.
    private struct Payload: Decodable {
        struct AxisX: Decodable {
            var label: String?
            var values: [Tick]?
        }
        struct AxisY: Decodable {
            var label: String?
        }
        struct SeriesPayload: Decodable {
            var name: String?
            var values: [Double]?
        }

        var type: String?
        var title: String?
        var x: AxisX?
        var y: AxisY?
        var series: [SeriesPayload]?
    }

    /// An x-axis value that may arrive as a JSON string or number.
    private struct Tick: Decodable {
        var text: String

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let string = try? container.decode(String.self) {
                text = string
            } else if let int = try? container.decode(Int.self) {
                text = String(int)
            } else if let double = try? container.decode(Double.self) {
                text = String(double)
            } else {
                throw DecodingError.typeMismatch(
                    String.self,
                    .init(codingPath: decoder.codingPath, debugDescription: "x value is neither string nor number")
                )
            }
        }
    }
}

// MARK: - Render support

extension ChartSpec {
    /// Legend / scale-domain names, unique and stable: a series without a
    /// name becomes "Series N", and duplicate names get a numeric suffix
    /// (Swift Charts scale domains require unique values).
    var seriesDisplayNames: [String] {
        var seen: [String: Int] = [:]
        return series.enumerated().map { index, series in
            let base = series.name ?? "Series \(index + 1)"
            let count = seen[base, default: 0]
            seen[base] = count + 1
            return count == 0 ? base : "\(base) (\(count + 1))"
        }
    }

    /// One-line VoiceOver summary — the chart must not be an unlabeled blob.
    var accessibilitySummary: String {
        let kindName: String
        switch kind {
        case .line: kindName = "Line chart"
        case .bar: kindName = "Bar chart"
        case .area: kindName = "Area chart"
        case .point: kindName = "Scatter chart"
        }
        var parts: [String] = [title.map { "\(kindName): \($0)" } ?? kindName]
        let names = seriesDisplayNames
        parts.append(names.count == 1 ? "Series \(names[0])" : "\(names.count) series: \(names.joined(separator: ", "))")
        if let first = xValues.first, let last = xValues.last {
            parts.append(xValues.count == 1
                ? "1 point at \(first)"
                : "\(xValues.count) points from \(first) to \(last)")
        }
        return parts.joined(separator: ". ") + "."
    }
}

// MARK: - Table promotion (Path B)

extension ChartSpec {
    /// Path B (OPEN_ITEMS #100): a parsed pipe table whose first column is
    /// labels and whose remaining columns are all numeric can be charted with
    /// zero model cooperation. True exactly when `promoted(header:rows:)`
    /// succeeds.
    static func isChartable(header: [String], rows: [[String]]) -> Bool {
        promoted(header: header, rows: rows) != nil
    }

    /// Builds a bar-chart spec from a numeric table: first column → x labels,
    /// each remaining column → one series named by its header. Nil when the
    /// table has fewer than 2 data rows or 2 columns, any non-numeric cell,
    /// or is over the series/point budget.
    static func promoted(header: [String], rows: [[String]]) -> ChartSpec? {
        guard header.count >= 2, header.count - 1 <= maxSeries else { return nil }
        guard rows.count >= 2, rows.count <= maxPointsPerSeries else { return nil }
        guard rows.allSatisfy({ $0.count == header.count }) else { return nil }

        var columns: [[Double]] = Array(repeating: [], count: header.count - 1)
        for row in rows {
            for (index, cell) in row.dropFirst().enumerated() {
                guard let value = numericCell(cell) else { return nil }
                columns[index].append(value)
            }
        }

        return ChartSpec(
            kind: .bar,
            title: nil,
            xLabel: normalized(header[0]),
            xValues: rows.map { $0[0] },
            yLabel: header.count == 2 ? normalized(header[1]) : nil,
            series: columns.enumerated().map {
                Series(name: normalized(header[$0.offset + 1]), values: $0.element)
            }
        )
    }

    /// Parses a table cell as a finite number. Thousands separators are
    /// stripped only when they group correctly ("1,234,567" yes, "1,2,3" no).
    static func numericCell(_ cell: String) -> Double? {
        var trimmed = cell.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.wholeMatch(of: /-?\d{1,3}(?:,\d{3})+(?:\.\d+)?/) != nil {
            trimmed = trimmed.replacingOccurrences(of: ",", with: "")
        }
        guard let value = Double(trimmed), value.isFinite else { return nil }
        return value
    }
}
