import Foundation

/// Lenient ISO-8601 coders for the app's hand-rolled JSON paths.
///
/// **#309 Lane C moved this out of `RelayAPIClient.swift` when that client was
/// deleted (2026-08-25).** The name is the last thing about it that still says
/// "relay": its live readers are `LiveVoiceSessionService` (whose own comment
/// already noted "this is a coder, not a transport; nothing here speaks to the
/// relay any more") and three decoding tests. What it actually encodes is a
/// tolerance — a timestamp with no zone suffix is read as UTC, and both the
/// fractional and whole-second internet-date shapes parse — which the plugin's
/// `isoformat` output needs as much as the relay's did.
///
/// Renaming it is deliberately NOT done here: the relay vocabulary sweep
/// belongs to #309 Lane B, which retires the rest of it in one pass, and a
/// half-renamed vocabulary is harder to finish than an unrenamed one.
enum RelayCoders {
    private static func internetDateTimeStyle() -> Date.ISO8601FormatStyle {
        Date.ISO8601FormatStyle(timeZone: .gmt)
    }

    private static func internetDateTimeFractionalStyle() -> Date.ISO8601FormatStyle {
        Date.ISO8601FormatStyle(includingFractionalSeconds: true, timeZone: .gmt)
    }

    private static func normalizedRelayDateStrings(for value: String) -> [String] {
        if value.hasSuffix("Z") || value.range(of: #"[+-]\d{2}:\d{2}$"#, options: .regularExpression) != nil {
            return [value]
        }

        return ["\(value)Z"]
    }

    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)

            if let date = parseRelayDate(value) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported date: \(value)"
            )
        }
        return decoder
    }

    static func parseRelayDate(_ value: String) -> Date? {
        for candidate in normalizedRelayDateStrings(for: value) {
            if let date = try? internetDateTimeFractionalStyle().parse(candidate) {
                return date
            }

            if let date = try? internetDateTimeStyle().parse(candidate) {
                return date
            }
        }

        return nil
    }
}
