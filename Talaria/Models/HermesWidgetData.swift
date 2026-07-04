import Foundation

/// Snapshot of app state shared between the main app and widget extension
/// via App Group UserDefaults. Updated by the main app whenever state changes;
/// read by widget timeline providers to render Home Screen and CarPlay widgets.
struct HermesWidgetData: Codable, Sendable {
    var hostName: String?
    var hostOnline: Bool = false
    var lastMessagePreview: String?
    var lastMessageSender: String?   // "assistant", "user", "system"
    var lastMessageAt: Date?
    // Sentence-bounded summary of the last message (see `summarize`). Optional —
    // absent in snapshots written before the field existed; widgets fall back
    // to `lastMessagePreview` (#14).
    var lastMessageSummary: String?
    var voiceSessionActive: Bool = false
    var steps: Int?
    var activeCalories: Int?
    var sleepHours: Double?
    var heartRate: Int?
    var updatedAt: Date = .now
    // Active app appearance (raw AppearanceTheme/AppearanceAccent values) so
    // widgets set to "Match App" can resolve the same ThemePalette. Optional -
    // absent in pre-theme snapshots, resolved as Deep Field x cyan.
    var appearanceTheme: String?
    var appearanceAccent: String?

    static let empty = HermesWidgetData()

    /// Builds `lastMessageSummary` from a raw message body: the first one or
    /// two complete sentences (split at real ". " boundaries), capped at 160
    /// characters, with a word-boundary truncation fallback when no sentence
    /// break fits — glanceable instead of a mid-word 120-char prefix (#14).
    static func summarize(_ content: String) -> String {
        let flattened = content
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let cap = 160

        let sentences = flattened.components(separatedBy: ". ")
        if sentences.count > 1 {
            var summary = ""
            for sentence in sentences.prefix(2) {
                let candidate = summary.isEmpty ? sentence : summary + ". " + sentence
                guard candidate.count <= cap else { break }
                summary = candidate
            }
            if !summary.isEmpty {
                // The split consumed the boundary's period — restore terminal
                // punctuation unless the sentence already ends with some.
                let terminal: Set<Character> = [".", "!", "?"]
                if let last = summary.last, !terminal.contains(last) {
                    summary += "."
                }
                return summary
            }
        }

        // No sentence break fits inside the cap — word-boundary truncation.
        if flattened.count <= cap { return flattened }
        var truncated = String(flattened.prefix(cap))
        if let lastSpace = truncated.lastIndex(of: " ") {
            truncated = String(truncated[..<lastSpace])
        }
        return truncated + "…"
    }
}
