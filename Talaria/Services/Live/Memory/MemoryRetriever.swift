import Foundation

/// One indexed chunk offered to the scorer.
///
/// No vector, and no embedder id: Owen deleted the embedder from the shape on 2026-09-03
/// after mutation M-R measured it to buy nothing (see `MemoryRetriever`). Task 8b drops the
/// matching store columns.
struct MemoryCandidate: Sendable {
    let entryID: UUID
    let sessionID: UUID
    let chunkIndex: Int
    let text: String
    let sentAt: Date
}

struct MemoryHit: Sendable {
    let candidate: MemoryCandidate
    let score: Float
}

/// #422 (bar 422-R): retrieval over the user's own stored turns.
///
/// Nothing here authors text. The retriever RANKS stored chunks and returns them verbatim;
/// ruling 1's structural pin — no model session, generation call or guided-output macro
/// anywhere under `Talaria/Services/Live/Memory/` — is what keeps that true as the module
/// grows. (Deliberately paraphrased rather than quoting the banned tokens: naming them here
/// would make this very file the grep's only hit.)
///
/// **Why the score is lexical only.** The shape was hybrid — `0.7 · cosine + 0.3 · lexical`
/// — until mutation M-R was run against the labelled corpus on 2026-09-02. Bar 422-R's
/// pre-registered rule was that lexical-only must score STRICTLY LOWER on at least one of
/// p@1 / false-admit / top-3, or the embedder buys nothing. It scored lower on none:
///
/// | arm | p@1 | false-admit (adversarial) | top-3 |
/// |---|---|---|---|
/// | hybrid `0.7/0.3` | 0.827 (62/75) | 0.750 (9/12) | 0.920 (69/75) |
/// | lexical-only | 0.853 (64/75) | 0.750 (9/12) | 0.973 (73/75) |
///
/// Better on two, identical on the third. The cause is structural rather than a bad
/// weighting: the anchor already requires a lexical hit, so the cosine term never ADMITTED
/// anything — it only re-ranked within the anchored set, and `NLEmbedding.sentenceEmbedding`
/// scores interrogative FORM so heavily that it re-ranked it worse. Owen ruled the embedder
/// deleted on 2026-09-03.
enum MemoryRetriever {

    // MARK: - The gates around retrieval

    /// Bare accepts and anaphoric follow-ups refer to the PREVIOUS turn, so their own tokens
    /// describe nothing the store holds — searching on them retrieves noise at full
    /// confidence.
    ///
    /// Deliberately an exact set rather than a length threshold, the same shape and for the
    /// same reason as `LocalChatBackend.shortAffirmatives`. A token-count rule was the first
    /// draft and the corpus falsified it in both directions: `contentTokens("another one")`
    /// is `{another, one}` — two tokens, so the anaphor passes through — while four
    /// ANSWERABLE 422-R queries carry exactly one content token ("who is my dentist",
    /// "when is our anniversary", "what do I collect", "what are we saving up for") and
    /// would have been skipped outright.
    static let anaphoricFollowUps: Set<String> = [
        "again", "and again", "another", "another one", "continue", "do it again", "go on",
        "keep going", "more", "next", "next one", "one more", "one more time", "same again",
        "say that again", "that one", "the same", "this one", "try again",
    ]

    static func shouldSkip(_ prompt: String) -> Bool {
        if LocalChatBackend.isShortAffirmative(prompt) { return true }
        let normalized = prompt
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "[\\p{P}\\p{S}]+$", with: "", options: .regularExpression)
            .lowercased()
        if anaphoricFollowUps.contains(normalized) { return true }
        // Nothing content-bearing to search on at all (punctuation, an emoji, stop words).
        return EmbeddingService.contentTokens(prompt).isEmpty
    }

    /// A question ABOUT the store rather than a question the store might answer. The caller
    /// uses it to decide whether an empty retrieval deserves the "nothing was saved" notice
    /// rather than silence.
    static let memoryQuestionPrefixes = [
        "what do you remember", "what did i tell you", "what do you know about me",
        "do you remember", "what have i told you", "remind me what i said",
    ]

    static func isMemoryShapedQuestion(_ prompt: String) -> Bool {
        let p = prompt.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return memoryQuestionPrefixes.contains { p.hasPrefix($0) }
    }

    // MARK: - The scorer

    /// Lexical score, RELATIVE admission, top-k de-duplicated by adjacent chunk.
    ///
    /// **Relative, not absolute** (design §2.3): no overlap floor exists to be set — an
    /// overlap of 1/3 is decisive for a three-token query and meaningless for a
    /// twelve-token one. Admission is therefore `z` standard deviations above the mean of
    /// THIS query's own score distribution, so a query is measured against how the rest of
    /// the store answered it.
    ///
    /// **The anchor.** A distribution always has a maximum, so the relative rule ALONE
    /// admits on every no-answer query — measured, not assumed. Requiring a non-zero
    /// overlap is what makes an admission mean "the store contains these words." Under a
    /// purely lexical score that floor is implied by any `z >= 0` (a zero-overlap candidate
    /// cannot sit above its own distribution's mean), and it is kept explicit anyway so the
    /// guarantee does not quietly depend on the sign of a tuning constant.
    ///
    /// The earlier hybrid draft also anchored the top 2% by score regardless of overlap;
    /// on the corpus that clause was strictly worse on all three bar numbers (p@1 0.680 vs
    /// 0.827, false-admit 12/12 vs 9/12, top-3 0.933 vs 0.920) because it re-admitted
    /// exactly the score artifacts the anchor exists to reject. It is not coming back.
    static func retrieve(query: String,
                         candidates: [MemoryCandidate],
                         topK: Int = 3,
                         z: Float = 1.5) -> [MemoryHit] {
        guard !shouldSkip(query) else { return [] }
        guard !candidates.isEmpty else { return [] }

        let scored = candidates.map { candidate in
            MemoryHit(candidate: candidate,
                      score: EmbeddingService.lexicalOverlap(query: query, chunk: candidate.text))
        }

        let scores = scored.map(\.score)
        let mean = scores.reduce(0, +) / Float(scores.count)
        let variance = scores.reduce(Float(0)) { $0 + ($1 - mean) * ($1 - mean) }
            / Float(max(scores.count - 1, 1))
        let sd = variance.squareRoot()
        // A flat distribution has no standout — one candidate, or a hundred identical ones.
        // Admitting the arbitrary maximum of a flat set is the false-admit this guard
        // exists to refuse.
        guard sd > 0 else { return [] }

        let admitted = scored
            .filter { $0.score > 0 && ($0.score - mean) / sd >= z }
            .sorted { $0.score > $1.score }

        // Two chunks of one turn are one memory: admitting both spends the block's token
        // budget twice on the same sentence.
        var out: [MemoryHit] = []
        for hit in admitted {
            guard out.count < topK else { break }
            let adjacent = out.contains {
                $0.candidate.sessionID == hit.candidate.sessionID
                    && abs($0.candidate.chunkIndex - hit.candidate.chunkIndex) <= 1
            }
            if !adjacent { out.append(hit) }
        }
        return out
    }
}
