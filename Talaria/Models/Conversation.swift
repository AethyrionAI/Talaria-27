import Foundation

struct Conversation: Codable, Identifiable, Hashable, Sendable {
    /// Placeholder title for a not-yet-labeled conversation. On-device title
    /// generation (#4.8) only ever fires while the title still equals this,
    /// so a manual `/title` is never overwritten.
    ///
    /// **#415-SWEEP:** renamed Hermes → Talaria under Owen's standing naming
    /// ruling. This string is user-visible — it is what the drawer shows
    /// before on-device titling produces a real one — and the assistant that
    /// answers may be entirely local, so naming the placeholder after the
    /// host was wrong on its own terms.
    static let defaultTitle = "Talaria"

    /// The pre-#415-SWEEP placeholder, still carried by every conversation
    /// created before that build.
    ///
    /// Renaming `defaultTitle` alone would have been a silent regression, not
    /// a cosmetic change: the `#4.8` gate is an EQUALITY test against the
    /// current constant, so those rows would have stopped matching it — they
    /// would display the OLD name forever *and* never become eligible for
    /// auto-titling again. A naming sweep that permanently strands "Hermes"
    /// in the sessions drawer has defeated its own purpose, so placeholder
    /// checks go through `isPlaceholderTitle` and accept both.
    static let legacyDefaultTitle = "Hermes"

    /// Whether a title is still the un-named placeholder (either vintage).
    ///
    /// Use this for the `#4.8` generation gate and for any merge that treats
    /// "still a placeholder" as "safe to overwrite" — never a bare
    /// `== defaultTitle`, which is blind to pre-#415 rows.
    static func isPlaceholderTitle(_ title: String) -> Bool {
        title == defaultTitle || title == legacyDefaultTitle
    }

    let id: UUID
    var title: String
    var messages: [Message]
    var lastActivity: Date
    var latestUsage: TokenUsage?

    /// #349: gates the gauge's numerator. `promptTokens` IS context
    /// occupancy only when the turn it describes made no tool calls — on
    /// agentic turns the wire's `input_tokens` is the SUM of billed input
    /// across every internal model call (wire-measured 2026-08-18: 46,953 on
    /// a thread whose true depth was ~23.5K; 287K-on-a-128K-window in the
    /// production filing), so the gauge renders ABSENT rather than a wrong
    /// number (#25). The usage is PASSED IN because the store-level feed
    /// (`ChatStore.lastTokenUsage`) has channels no message row carries —
    /// the #322 cancel final-status read and the cached-metadata restore —
    /// and all of them describe the LATEST settled turn, whose tool
    /// activities live on the latest hermes message. A tool-using turn gates
    /// the gauge even mid-stream; there is no stale carry-forward (an older
    /// toolless reading would UNDERSTATE current depth, the false-low that
    /// removes the ceiling warning when it matters).
    func contextOccupancyTokens(for usage: TokenUsage?) -> Int? {
        guard let prompt = usage?.promptTokens else { return nil }
        // TURN-scoped, not last-message: a REFETCHED turn splits into rows
        // (the tool-call row carries the activities, the prose tail carries
        // none), and a last-message gate un-hid the gauge with the summed
        // input on reopen — Owen's OJAMD device pass, 2026-08-18 evening.
        // Any tool activity since the last user-authored message hides it.
        for message in messages.reversed() {
            if message.sender == .user || message.sender == .voiceUser { break }
            if !message.toolActivities.isEmpty { return nil }
        }
        return prompt
    }

    /// One-line on-device preview generated alongside the title (#4.8).
    /// nil until the first completed exchange has been summarized (and in
    /// pre-#4.8 caches).
    var generatedPreview: String?

    init(
        id: UUID = UUID(),
        title: String,
        messages: [Message] = [],
        lastActivity: Date = .now,
        latestUsage: TokenUsage? = nil,
        generatedPreview: String? = nil
    ) {
        self.id = id
        self.title = title
        self.messages = messages
        self.lastActivity = lastActivity
        self.latestUsage = latestUsage
        self.generatedPreview = generatedPreview
    }

    var lastMessage: Message? {
        messages.last
    }

    var previewText: String {
        lastMessage?.content ?? "No messages yet"
    }

    /// #237: heal adopted-echo corruption. Pre-fix reconciles unioned whole
    /// transcripts with fresh identities (32 → 128 on the observed thread),
    /// so identity alone cannot find the copies — first occurrence wins for
    /// rows sharing (sender, trimmed content, timestamp), with empty-content
    /// tool-shell rows additionally keyed on their activity labels so two
    /// DIFFERENT shells at one timestamp both survive. A genuinely repeated
    /// user message differs in timestamp and is untouched. Idempotent.
    static func dedupingAdoptedEchoes(_ messages: [Message]) -> [Message] {
        var seen = Set<String>()
        return messages.filter { message in
            let content = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            var key = "\(message.sender)|\(content)|\(message.timestamp.timeIntervalSince1970)"
            if content.isEmpty {
                key += "|\(message.toolActivities.map(\.label).joined(separator: ","))"
            }
            return seen.insert(key).inserted
        }
    }
}
