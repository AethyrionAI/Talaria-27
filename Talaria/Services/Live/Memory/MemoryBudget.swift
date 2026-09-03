import Foundation

/// #422 bar 422-D — how much of the context window local memory may spend,
/// and the exact text it spends it on.
///
/// Two rules shape everything here:
///
/// - **The cap is derived from the RUNTIME window, never hardcoded.**
///   `memoryBlockTokens(contextSize:)` is a tenth of the live window, rounded
///   down to a whole hundred tokens and clamped to 256…2048, so the same call
///   yields 800 on the phone's 8,192-token on-device window, 400 on a 4,096
///   window and 2,048 on PCC's 32,768.
/// - **Shortening is TRUNCATION, never paraphrase** (ruling 1). Nothing in
///   this file re-words a stored turn: the composers quote it, date it, and
///   label it as quoted-and-possibly-stale, and the only shortener is
///   `LocalIntelligenceService.trimmed(_:toTokenBudget:)` — the one the
///   ruling allows — with a visible `…` marking the cut. A trimmed chunk is
///   always a literal prefix of its source.
///
/// The trimming entry points take the `LocalIntelligenceService` rather than
/// reaching for one: `trimmed(_:toTokenBudget:)` is a `@MainActor` instance
/// method measured with the model's own tokenizer, so it cannot be called
/// from a free static function. Passing it in also keeps the token estimate
/// in exactly one place — `measuredTokenCount(of:)` — which is why `fits`
/// takes the service too. A second estimator here could disagree with the
/// trimmer about what "800 tokens" means.
enum MemoryBudget {

    // MARK: - The cap

    /// A tenth of the live context window — rounded DOWN to a whole hundred
    /// tokens — clamped to 256…2048.
    ///
    /// The rounding is not cosmetic and it is not what the plan's own sketch
    /// said. A bare `contextSize / 10` returns **819** on the phone's 8,192
    /// window and **409** on 4,096, while the pre-registered bar (and the
    /// design doc's own worked numbers) call for **800** and **400**. The
    /// RED run caught the two disagreeing; the bar is the specification, so
    /// the tenth is floored to a hundred. It also stops the cap from
    /// advertising a precision the token estimate underneath it does not
    /// have.
    ///
    /// The clamp is applied last, which is why PCC's 32,768 window
    /// (3,276 → 3,200) still lands on 2,048 and a simulator's 0 lands on the
    /// 256 floor.
    static func memoryBlockTokens(contextSize: Int) -> Int {
        let tenth = contextSize / 10
        let wholeHundreds = (tenth / 100) * 100
        return min(2048, max(256, wholeHundreds))
    }

    /// Per-hit head-trim cap. Retrieval is top-k 3, so three of these plus
    /// the preamble sit comfortably inside the 800-token phone budget.
    static let maxHitTokens = 100

    /// Owen's defaults for the explicit-notes block (doc §7).
    static let maxNotes = 8
    static let maxNotesTokens = 300

    // MARK: - The pinned strings

    static let notesPreamble = "## Things the user asked you to remember\nTreat these as things the user told you, quoted; if two disagree, say which is newer and quote both."
    static let hitsPreamble = "## From your earlier chats (quoted, may be out of date)"
    static let noMemoriesMatch = "No saved memories match this question."

    static func justSavedPrefix(_ verbatim: String) -> String {
        "The user just asked you to remember this and it HAS been saved: \"\(verbatim)\""
    }

    // MARK: - Composers

    private static let day: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    /// The explicit-notes block, newest note first — the caller owns that
    /// order; this keeps at most `maxNotes` of them.
    static func composeNotesBlock(_ notes: [(text: String, createdAt: Date)]) -> String {
        let kept = notes.prefix(maxNotes)
        guard !kept.isEmpty else { return "" }
        return notesPreamble + "\n" + kept.map {
            "On \(day.string(from: $0.createdAt)) the user said: \"\($0.text)\""
        }.joined(separator: "\n")
    }

    /// The retrieved-turns block. Every line carries the date the user said
    /// it and the preamble says the quotes may be stale — the model is never
    /// handed a memory dressed as a present-tense fact.
    static func composeHitsPrefix(_ hits: [(text: String, sentAt: Date)]) -> String {
        guard !hits.isEmpty else { return "" }
        return hitsPreamble + "\n" + hits.map {
            "On \(day.string(from: $0.sentAt)) you said: \"\($0.text)\""
        }.joined(separator: "\n") + "\n\n"
    }

    // MARK: - Truncation (the only allowed shortening)

    /// Head-trims each hit to `maxTokens`, leaving its date untouched.
    @MainActor
    static func trimmedHits(
        _ hits: [(text: String, sentAt: Date)],
        maxTokens: Int = maxHitTokens,
        using intelligence: LocalIntelligenceService
    ) async -> [(text: String, sentAt: Date)] {
        var trimmed: [(text: String, sentAt: Date)] = []
        trimmed.reserveCapacity(hits.count)
        for hit in hits {
            let head = await truncated(hit.text, toTokenBudget: maxTokens, using: intelligence)
            trimmed.append((text: head, sentAt: hit.sentAt))
        }
        return trimmed
    }

    /// The notes block, kept inside its own token budget by the same
    /// truncation the hits use.
    @MainActor
    static func composeNotesBlock(
        _ notes: [(text: String, createdAt: Date)],
        toTokenBudget budget: Int = maxNotesTokens,
        using intelligence: LocalIntelligenceService
    ) async -> String {
        let block = composeNotesBlock(notes)
        guard !block.isEmpty else { return "" }
        return await truncated(block, toTokenBudget: budget, using: intelligence)
    }

    /// Whether `block` fits `tokens`, measured with the trimmer's own
    /// tokenizer so the two can never disagree.
    @MainActor
    static func fits(_ block: String, in tokens: Int, using intelligence: LocalIntelligenceService) async -> Bool {
        guard !block.isEmpty else { return true }
        return await intelligence.measuredTokenCount(of: block) <= tokens
    }

    /// Truncates to `budget` tokens and marks the cut with `…`.
    ///
    /// The trim reserves one token for that marker, so the returned string —
    /// marker included — still fits `budget`. Text already inside the budget
    /// comes back byte-identical and unmarked.
    @MainActor
    private static func truncated(
        _ text: String,
        toTokenBudget budget: Int,
        using intelligence: LocalIntelligenceService
    ) async -> String {
        let head = await intelligence.trimmed(text, toTokenBudget: max(1, budget - 1))
        guard head != text else { return text }
        return head + "…"
    }
}
