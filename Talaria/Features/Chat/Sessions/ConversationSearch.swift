import Foundation

/// In-app conversation search (#96): pure matching + snippet extraction over
/// the two corpora Talaria actually has — (a) the local `ConversationJournal`
/// (title + full turn text; the durable primary record per #93) and (b) the
/// already-fetched Hermes server-session list (title + preview, the only text
/// the Sessions API exposes; message bodies live server-side and are NOT
/// fetched per keystroke). Matching is case- and diacritic-insensitive via
/// the `localizedStandard` family. Real data only: every surfaced string
/// exists verbatim in the corpus; missing fields stay nil and render "—".
enum ConversationSearch {

    /// One matching turn from the local journal.
    struct LocalHit: Identifiable, Hashable, Sendable {
        /// The entry's index in the journal — stable within one result set.
        let id: Int
        let role: ConversationJournal.Entry.Role
        /// A window of the REAL entry text around the first match — never a
        /// paraphrase. Leading/trailing "…" mark truncation honestly.
        let snippet: String
    }

    /// One matching fetched server session. Field optionality mirrors what
    /// the Sessions API actually returned — the view renders "—" for nil.
    struct ServerHit: Identifiable, Hashable, Sendable {
        let id: String
        let title: String?
        let preview: String?
        let messageCount: Int
        let lastActive: Date?
        let isActive: Bool

        /// Primary row line: the title, else the preview standing in for it,
        /// else an honest "—".
        var displayTitle: String {
            title ?? preview ?? "—"
        }

        /// Secondary row line: the preview — unless it already serves as the
        /// title (title-less session), in which case there is nothing else
        /// real to show.
        var displayDetail: String {
            guard title != nil else { return "—" }
            return preview ?? "—"
        }
    }

    /// Case/diacritic-insensitive containment ("cafe" finds "Café" and
    /// vice versa), locale-aware.
    static func matches(_ query: String, in text: String) -> Bool {
        text.localizedStandardContains(query)
    }

    /// Matching turns from the local journal, in transcript order. An empty
    /// (or whitespace-only) query matches nothing — the search screen shows
    /// its prompt state instead of dumping the corpus.
    static func searchJournal(
        entries: [ConversationJournal.Entry],
        query: String
    ) -> [LocalHit] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return entries.enumerated().compactMap { index, entry in
            guard matches(trimmed, in: entry.text) else { return nil }
            return LocalHit(
                id: index,
                role: entry.role,
                snippet: snippet(of: entry.text, around: trimmed)
            )
        }
    }

    /// Matching sessions from the already-fetched server list, in fetch
    /// (recency) order. Matches on title + preview — the only session text
    /// the API returns; synthesized strings are never matched.
    static func searchSessions(
        _ sessions: [HermesSessionInfo],
        query: String
    ) -> [ServerHit] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return sessions.compactMap { info in
            let title = nonEmpty(info.title)
            let preview = nonEmpty(info.preview)
            let hit = (title.map { matches(trimmed, in: $0) } ?? false)
                || (preview.map { matches(trimmed, in: $0) } ?? false)
            guard hit else { return nil }
            return ServerHit(
                id: info.id,
                title: title,
                preview: preview,
                messageCount: info.messageCount,
                lastActive: info.lastActive,
                isActive: info.isActive
            )
        }
    }

    /// A bounded window of the real text centered on the first match, with
    /// newlines collapsed for a single-block row. Falls back to a plain
    /// prefix if the range lookup disagrees with the containment check.
    static func snippet(of text: String, around query: String, radius: Int = 60) -> String {
        let collapsed = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let match = collapsed.localizedStandardRange(of: query) else {
            return String(collapsed.prefix(radius * 2))
        }
        let start = collapsed.index(match.lowerBound, offsetBy: -radius, limitedBy: collapsed.startIndex)
            ?? collapsed.startIndex
        let end = collapsed.index(match.upperBound, offsetBy: radius, limitedBy: collapsed.endIndex)
            ?? collapsed.endIndex
        var window = String(collapsed[start..<end])
        if start > collapsed.startIndex { window = "…" + window }
        if end < collapsed.endIndex { window += "…" }
        return window
    }

    /// Session time label: today → clock, within a week → weekday, older →
    /// date, unknown → "—" (real-data-only rule).
    static func timeLabel(for date: Date?) -> String {
        guard let date else { return "—" }
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return timeFormatter.string(from: date)
        }
        if calendar.isDateInYesterday(date) {
            return weekdayFormatter.string(from: date)
        }
        if let days = calendar.dateComponents([.day], from: date, to: .now).day, days < 7 {
            return weekdayFormatter.string(from: date)
        }
        return dateFormatter.string(from: date)
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    // DateFormatter is documented thread-safe on modern OS releases;
    // nonisolated(unsafe) satisfies Swift 6.2 strict concurrency (the
    // MarkdownParser / ChatStore regex precedent).
    nonisolated(unsafe) private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter(); formatter.dateFormat = "HH:mm"; return formatter
    }()
    nonisolated(unsafe) private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter(); formatter.dateFormat = "EEE"; return formatter
    }()
    nonisolated(unsafe) private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter(); formatter.dateFormat = "M/d"; return formatter
    }()
}
