import Foundation

// #126: daily-briefing recognition + content derivation. A briefing is an
// ordinary inbox item whose payload carries `category: "briefing"`; every
// other contract field is optional and absence degrades gracefully (#58).
extension InboxItem {
    enum BriefingPayloadKey {
        static let category = "category"
        static let speakable = "speakable"
    }

    static let briefingCategoryValue = "briefing"

    /// Keys on the payload category alone — tolerant of the producer sending
    /// an unexpected `kind`; an absent category is a normal item.
    var isBriefing: Bool {
        payload?[BriefingPayloadKey.category] == Self.briefingCategoryValue
    }

    /// Read-aloud source: the producer's `speakable` when non-blank, else the
    /// body with fenced blocks removed (chart JSON read aloud is noise —
    /// SpeechOutputService only strips fence MARKERS, not contents).
    var briefingSpeakableText: String {
        if let speakable = payload?[BriefingPayloadKey.speakable]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !speakable.isEmpty {
            return speakable
        }
        return Self.strippingFencedBlocks(from: body)
    }

    /// The widget shows the LATEST briefing regardless of how many arrive.
    static func latestBriefing(in items: [InboxItem]) -> InboxItem? {
        items.filter(\.isBriefing).max { $0.timestamp < $1.timestamp }
    }

    /// Removes fenced blocks — markers AND contents. Same line-based toggle
    /// as `LocalIntelligenceService.meaningfulLines`, but keeps prose lines
    /// verbatim (speech wants sentences, not title-trimmed fragments). An
    /// unterminated fence drops the tail, matching the parser's refusal to
    /// treat an open fence as prose.
    static func strippingFencedBlocks(from text: String) -> String {
        var kept: [Substring] = []
        var inFence = false
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                inFence.toggle()
                continue
            }
            if !inFence { kept.append(line) }
        }
        return kept.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
