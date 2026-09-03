import Foundation

/// One indexed chunk offered to the scorer. `vector` is EMPTY for every row indexed before
/// the embedder acquired, and for every row of a non-English user — a normal state, not a
/// corrupt one, which is why the scorer routes those to the lexical term instead of
/// discarding them.
struct MemoryCandidate: Sendable {
    let entryID: UUID
    let sessionID: UUID
    let chunkIndex: Int
    let text: String
    let sentAt: Date
    let embedderID: String
    let vector: [Float]
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
enum MemoryRetriever {

    /// The hybrid weights. Mutation M-R drives these to `0` / `1` to measure what the
    /// embedder buys over the lexical scorer alone; the arm's numbers ride the 422 RESULT
    /// block.
    static let embeddingWeight: Float = 0.7
    static let lexicalWeight: Float = 0.3

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

    /// A candidate carrying the lexical term the anchor rule re-reads, so the anchor costs
    /// no second tokenization pass over the chunk.
    private struct ScoredCandidate {
        let hit: MemoryHit
        let lexical: Float
    }

    /// Hybrid score, RELATIVE admission, lexical anchor, top-k de-duplicated by adjacent
    /// chunk.
    ///
    /// **Relative, not absolute** (design §2.3): no cosine floor exists to be set — the same
    /// cosine that means "this is the memory" for one query means "this is any sentence" for
    /// another, because `NLEmbedding.sentenceEmbedding` scores interrogative FORM heavily.
    /// Admission is therefore `z` standard deviations above the mean of THIS query's own
    /// score distribution.
    ///
    /// **The anchor is doing most of the gating, and that is measured.** The relative rule
    /// alone admits on every no-answer query in the corpus, because a distribution always
    /// has a maximum. Requiring a non-zero lexical overlap is what makes an admission mean
    /// "the store contains these words," and it is the only anchor clause: an earlier draft
    /// also anchored the top 2% by score regardless of overlap, and on the corpus that
    /// clause was strictly worse on all three bar numbers (p@1 0.680 vs 0.827, false-admit
    /// 12/12 vs 9/12, top-3 0.933 vs 0.920) — it re-admitted exactly the pure-cosine
    /// artifacts the anchor exists to reject.
    static func retrieve(query: String,
                         queryVector: [Float]?,
                         candidates: [MemoryCandidate],
                         liveEmbedderID: String,
                         topK: Int = 3,
                         z: Float = 1.5) -> [MemoryHit] {
        guard !shouldSkip(query) else { return [] }

        // Bar 422-C's rule: a row whose `embedderID` is not the live embedder's is never
        // scored — its vector came out of a different model, so its cosine against a live
        // query vector is a number with no meaning. An EMPTY vector is not such a row: it
        // is the pre-backfill / non-English state, it carries `embedderID == ""`, and it is
        // scored on the lexical term alone rather than dropped.
        let scorable = candidates.filter { $0.vector.isEmpty || $0.embedderID == liveEmbedderID }
        guard !scorable.isEmpty else { return [] }

        let scored: [ScoredCandidate] = scorable.map { candidate in
            var cosine: Float = 0
            if let queryVector, !candidate.vector.isEmpty, candidate.embedderID == liveEmbedderID {
                cosine = EmbeddingService.cosine(queryVector, candidate.vector)
            }
            let lexical = EmbeddingService.lexicalOverlap(query: query, chunk: candidate.text)
            return ScoredCandidate(hit: MemoryHit(candidate: candidate,
                                                  score: embeddingWeight * cosine + lexicalWeight * lexical),
                                   lexical: lexical)
        }

        let scores = scored.map(\.hit.score)
        let mean = scores.reduce(0, +) / Float(scores.count)
        let variance = scores.reduce(Float(0)) { $0 + ($1 - mean) * ($1 - mean) }
            / Float(max(scores.count - 1, 1))
        let sd = variance.squareRoot()
        // A flat distribution has no standout — one candidate, or a hundred identical ones.
        // Admitting the arbitrary maximum of a flat set is the false-admit this guard exists
        // to refuse.
        guard sd > 0 else { return [] }

        let admitted = scored
            .filter { $0.lexical > 0 && ($0.hit.score - mean) / sd >= z }
            .sorted { $0.hit.score > $1.hit.score }

        // Two chunks of one turn are one memory: admitting both spends the block's token
        // budget twice on the same sentence.
        var out: [MemoryHit] = []
        for candidate in admitted {
            guard out.count < topK else { break }
            let adjacent = out.contains {
                $0.candidate.sessionID == candidate.hit.candidate.sessionID
                    && abs($0.candidate.chunkIndex - candidate.hit.candidate.chunkIndex) <= 1
            }
            if !adjacent { out.append(candidate.hit) }
        }
        return out
    }
}
