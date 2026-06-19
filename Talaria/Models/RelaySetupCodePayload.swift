import Foundation

enum PhonePairingCodeError: LocalizedError {
    case invalidFormat

    var errorDescription: String? {
        switch self {
        case .invalidFormat:
            "Enter the 8-character code from `hermes-mobile pair-phone`."
        }
    }
}

enum PhonePairingCode {
    private static let allowedCharacters = Set("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
    private static let codeLength = 8
    private static let separatorIndex = 4

    static func normalize(_ rawCode: String) throws -> String {
        let normalized = rawCode
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")

        guard normalized.count == codeLength else {
            throw PhonePairingCodeError.invalidFormat
        }

        guard normalized.allSatisfy({ allowedCharacters.contains($0) }) else {
            throw PhonePairingCodeError.invalidFormat
        }

        return normalized
    }

    static func format(_ rawCode: String) -> String {
        let filtered = rawCode
            .uppercased()
            .filter { allowedCharacters.contains($0) }
        let limited = String(filtered.prefix(codeLength))
        guard limited.count > separatorIndex else {
            return limited
        }

        let first = limited.prefix(separatorIndex)
        let second = limited.dropFirst(separatorIndex)
        return "\(first)-\(second)"
    }

    static func isComplete(_ rawCode: String) -> Bool {
        (try? normalize(rawCode)) != nil
    }
}
