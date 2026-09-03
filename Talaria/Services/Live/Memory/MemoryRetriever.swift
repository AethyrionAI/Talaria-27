import Foundation

/// One indexed chunk offered to the scorer.
///
/// Text and provenance, nothing else — see `MemoryRetriever` for why there is no vector.
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
/// **The score is lexical only — the embedder was deleted by measurement, 2026-09-03.**
/// Bar 422-R's pre-registered mutation M-R scored a lexical-only arm against the labelled
/// corpus and it was not lower on ANY of the bar's three numbers (better on p@1 and top-3
/// recall, identical on false-admit), so the rule fired and Owen deleted the embedder from
/// the shape. Nothing in the memory path embeds and no stored row carries a vector; the
/// full numbers live in the 422 RESULT block.
enum MemoryRetriever {

    // MARK: - The gates around retrieval

    /// Bare accepts and anaphoric follow-ups refer to the PREVIOUS turn, so their own tokens
    /// describe nothing the store holds — searching on them retrieves noise at full
    /// confidence.
    ///
    /// Deliberately an exact set rather than a length threshold, the same shape and for the
    /// same reason as `LocalChatBackend.shortAffirmatives`. A token-count rule was the first
    /// draft and the corpus falsified it in both directions: `LexicalTokenizer.contentTokens("another one")`
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
        // Internal runs of whitespace collapse too: "another  one" is the same anaphor.
        let normalized = prompt
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "[\\p{P}\\p{S}]+$", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .lowercased()
        if anaphoricFollowUps.contains(normalized) { return true }
        // Nothing content-bearing to search on at all (punctuation, an emoji, stop words).
        return LexicalTokenizer.contentTokens(prompt).isEmpty
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
    /// **Below four candidates the relative rule cannot fire at all** — see the comment on
    /// the small-store branch. The anchor carries admission there instead.
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
                      score: LexicalTokenizer.lexicalOverlap(query: query, chunk: candidate.text))
        }

        // **A store too small for a distribution.** With the sample standard deviation the
        // largest z attainable over `n` values is `(n-1)/√n`, which does not reach the
        // default 1.5 until n = 4 — so on a one-, two- or three-row store the relative
        // rule admitted NOTHING, however perfectly a row matched. That is the FIRST-RUN
        // path: the user saves their first memory, asks about it, and is told there is
        // nothing there. Below the threshold the anchor alone decides; it is not an open
        // door, because a row still has to share a content token to score above zero.
        let admissible: [MemoryHit]
        if scored.count < 4 {
            admissible = scored.filter { $0.score > 0 }
        } else {
            let scores = scored.map(\.score)
            let mean = scores.reduce(0, +) / Float(scores.count)
            let variance = scores.reduce(Float(0)) { $0 + ($1 - mean) * ($1 - mean) }
                / Float(max(scores.count - 1, 1))
            let sd = variance.squareRoot()
            // A flat distribution has no standout — a hundred identical rows. Admitting
            // the arbitrary maximum of a flat set is the false-admit this guard refuses.
            guard sd > 0 else { return [] }
            admissible = scored.filter { $0.score > 0 && ($0.score - mean) / sd >= z }
        }

        // **The tie-break is part of the answer, not a detail.** `sorted(by:)` is not
        // stable in Swift, and 13 of the 75 answerable corpus queries tie at rank 1 — so
        // score alone leaves p@1 dependent on the order the rows came back from a fetch,
        // which is SwiftData's business rather than a property of the scorer. Measured
        // over adversarial orderings the same corpus scores anywhere from 59 to 68 of 75.
        //
        // Newer first, because between two equally-matching memories the later one is the
        // more likely to still be true — a repaint supersedes the colour before it. Then
        // chunk order within a turn, then the id, so the order is total.
        let admitted = admissible.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            if $0.candidate.sentAt != $1.candidate.sentAt {
                return $0.candidate.sentAt > $1.candidate.sentAt
            }
            if $0.candidate.chunkIndex != $1.candidate.chunkIndex {
                return $0.candidate.chunkIndex < $1.candidate.chunkIndex
            }
            return $0.candidate.entryID.uuidString < $1.candidate.entryID.uuidString
        }

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
