import Testing
import Foundation
@testable import Talaria

/// #422 (bar 422-R): the retriever, scored against the labelled corpus.
///
/// Every number is REPORTED with its denominator on a `422-R:` line so a run's log carries
/// the measurement and not only the verdict: **precision@1 ≥ 0.80** and **top-3 recall
/// ≥ 0.90** on answerable queries, and the false-admit rate on BOTH no-answer classes.
///
/// **Two classes, one gated.** `plain` no-answer queries are ordinary unrelated questions
/// that share no content token with any turn; `adversarial` ones are authored near-misses
/// of a real turn ("when is my next dermatologist appointment" against "My passport renewal
/// appointment is booked for next Tuesday"). Owen accepted the adversarial miss on
/// 2026-09-03 and set the plain class as the gated one, so the bar test asserts ≤ 0.10 on
/// `plain` and the adversarial rate rides every log line un-gated.
///
/// A simulator process shares the Mac's filesystem, so `#filePath` resolves to the
/// checked-in corpus — the same route `InstrumentRegistryTests` already takes.
///
/// No embedder is constructed anywhere in this suite: retrieval is lexical-only since the
/// 2026-09-03 ruling, which is also why these tests are synchronous.
@Suite("422-R retrieval")
struct MemoryRetrieverTests {

    // MARK: - The corpus

    /// `meta` rides the same file; `Decodable` ignores keys no property claims, so it is
    /// deliberately not modelled here.
    struct Corpus: Decodable {
        struct Turn: Decodable { let id: Int; let text: String }
        struct Query: Decodable {
            let text: String
            let relevant: Int?
            /// `"adversarial"` / `"plain"` on no-answer queries, absent on answerable ones.
            let queryClass: String?
            enum CodingKeys: String, CodingKey {
                case text, relevant
                case queryClass = "class"
            }
        }
        let turns: [Turn]
        let queries: [Query]
    }

    static let corpusURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("planning/reports/2026-09-02-422-retrieval-corpus.json")

    static func loadCorpus() throws -> Corpus {
        try JSONDecoder().decode(Corpus.self, from: Data(contentsOf: corpusURL))
    }

    /// Distinct `sessionID`s on purpose: adjacent-chunk de-duplication is pinned by its own
    /// test, and it must not silently suppress corpus hits here.
    private func candidates(_ corpus: Corpus) -> [MemoryCandidate] {
        corpus.turns.map {
            // Deterministic `sentAt`, ascending with the turn id: the tie-break reads it,
            // so `Date()` per row would make the reported numbers depend on how fast the
            // loop ran.
            MemoryCandidate(entryID: UUID(), sessionID: UUID(), chunkIndex: $0.id,
                            text: $0.text,
                            sentAt: Date(timeIntervalSince1970: 1_000 + Double($0.id)))
        }
    }

    // MARK: - One scoring pass, shared by the bar tests

    private struct CorpusScore {
        let correct: Int, recalled: Int, answerable: Int
        let adversarialAdmits: Int, adversarialTotal: Int
        let plainAdmits: Int, plainTotal: Int

        var precisionAt1: Float { Float(correct) / Float(answerable) }
        var topThreeRecall: Float { Float(recalled) / Float(answerable) }
        var adversarialRate: Float { Float(adversarialAdmits) / Float(adversarialTotal) }
        var plainRate: Float { Float(plainAdmits) / Float(plainTotal) }

        var line: String {
            "422-R: p@1 \(correct)/\(answerable) = \(fmt(precisionAt1)) · "
                + "top-3 recall \(recalled)/\(answerable) = \(fmt(topThreeRecall)) · "
                + "false-admit adversarial \(adversarialAdmits)/\(adversarialTotal) = \(fmt(adversarialRate)), "
                + "plain \(plainAdmits)/\(plainTotal) = \(fmt(plainRate))"
        }
        private func fmt(_ v: Float) -> String { String(format: "%.3f", v) }
    }

    private func scoreCorpus() throws -> CorpusScore {
        let corpus = try Self.loadCorpus()
        let cands = candidates(corpus)
        var correct = 0, recalled = 0
        var adversarialAdmits = 0, adversarialTotal = 0
        var plainAdmits = 0, plainTotal = 0

        for query in corpus.queries {
            let hits = MemoryRetriever.retrieve(query: query.text, candidates: cands)
            guard let gold = query.relevant else {
                let admitted = !hits.isEmpty
                if query.queryClass == "plain" {
                    plainTotal += 1
                    if admitted { plainAdmits += 1 }
                } else {
                    adversarialTotal += 1
                    if admitted { adversarialAdmits += 1 }
                }
                continue
            }
            if hits.first?.candidate.chunkIndex == gold { correct += 1 }
            if hits.contains(where: { $0.candidate.chunkIndex == gold }) { recalled += 1 }
        }

        let answerable = corpus.queries.filter { $0.relevant != nil }.count
        // Denominators are part of the bar. A corpus edit that silently dropped a class
        // would otherwise turn a rate into a different measurement wearing the same name.
        #expect(answerable == 75)
        #expect(adversarialTotal == 12)
        #expect(plainTotal == 20)

        return CorpusScore(correct: correct, recalled: recalled, answerable: answerable,
                           adversarialAdmits: adversarialAdmits, adversarialTotal: adversarialTotal,
                           plainAdmits: plainAdmits, plainTotal: plainTotal)
    }

    // MARK: - Bar 422-R

    @Test func precisionAt1IsAtLeast0_80OnAnswerableQueries() throws {
        let s = try scoreCorpus()
        print(s.line)
        #expect(s.precisionAt1 >= 0.80, "p@1 \(s.correct)/\(s.answerable)")
    }

    @Test func topThreeRecallIsAtLeast0_90OnAnswerableQueries() throws {
        let s = try scoreCorpus()
        print(s.line)
        #expect(s.topThreeRecall >= 0.90, "top-3 recall \(s.recalled)/\(s.answerable)")
    }

    /// The gated class. The adversarial rate is reported on the same line and deliberately
    /// NOT asserted: Owen accepted that miss on 2026-09-03 after an exhaustive search showed
    /// no configuration of this scorer reaches 0.10 on it without dropping p@1 to 0.560.
    @Test func falseAdmitRateIsAtMost0_10OnPlainNoAnswerQueries() throws {
        let s = try scoreCorpus()
        print(s.line)
        #expect(s.plainRate <= 0.10, "plain false admits \(s.plainAdmits)/\(s.plainTotal)")
    }

    /// The `plain` class is DEFINED by zero content-token overlap with every turn, so this
    /// pins the corpus rather than the scorer — and it is the test that keeps the plain
    /// false-admit number honest. Under a lexical-only scorer that number is 0 BY
    /// CONSTRUCTION; if a future tokenizer change (or a re-added semantic term) breaks the
    /// zero-overlap property, the rate would start meaning something else entirely and this
    /// test says so out loud instead of letting the bar quietly change definition.
    @Test func everyPlainNoAnswerQuerySharesNoContentTokenWithAnyTurn() throws {
        let corpus = try Self.loadCorpus()
        let turnTokens = corpus.turns.reduce(into: Set<String>()) {
            $0.formUnion(LexicalTokenizer.contentTokens($1.text))
        }
        for query in corpus.queries where query.queryClass == "plain" {
            let shared = LexicalTokenizer.contentTokens(query.text).intersection(turnTokens)
            #expect(shared.isEmpty,
                    "plain query \(query.text.debugDescription) shares \(shared.sorted()) with a turn")
        }
    }

    // MARK: - Top-k shape

    /// Twenty rows nothing in the query touches, so the three that DO match stand out far
    /// enough above their own distribution to be admitted at all.
    ///
    /// That padding is the point of this fixture. The first version of this test used six
    /// candidates and asserted only `sameSession.count <= 1` — and on that fixture
    /// `retrieve` returned an EMPTY array (three ties at 0.333 against three zeros peaks at
    /// z = 0.913, under the 1.5 bar), so the assertion passed over nothing and the
    /// de-duplication branch was executed by no test in the suite. `#require(!hits.isEmpty)`
    /// is what keeps it honest.
    private func hallwayFixture(session: UUID) -> [MemoryCandidate] {
        let hallway = "We decided to go with the blue paint for the hallway, not the grey."
        func row(_ index: Int, _ sessionID: UUID, _ body: String) -> MemoryCandidate {
            MemoryCandidate(entryID: UUID(), sessionID: sessionID, chunkIndex: index,
                            text: body, sentAt: Date(timeIntervalSince1970: 1_000 + Double(index)))
        }
        let filler = [
            "How many calories are in a medium banana?", "What year did the Berlin Wall come down?",
            "Set a timer for twelve minutes.", "Explain how photosynthesis works in simple terms.",
            "Suggest a name for a new houseplant.", "Mute notifications for the next hour.",
            "What's 340 divided by 8?", "Draft a two-sentence out-of-office reply.",
            "How far away is the moon from Earth?", "Play some rain sounds to help me focus.",
            "Convert 5 miles to kilometers for me.", "What's the square root of 144?",
            "Write a limerick about a grumpy cat.", "Turn the living room lights down to 20 percent.",
            "My commute takes about forty minutes each way on the train.",
            "I water the office plants every Monday morning.", "I collect vinyl records, mostly 70s jazz.",
            "I meal-prep on Sundays for the whole work week.", "I'm training for a half marathon in the spring.",
            "My favorite coffee order is an oat milk flat white, no sugar.",
        ]
        return [row(0, session, hallway), row(1, session, hallway), row(0, UUID(), hallway)]
            + filler.enumerated().map { row($0.offset, UUID(), $0.element) }
    }

    /// Two chunks of one long turn are one memory, not two: admitting both spends the
    /// token budget twice on the same sentence. Distinct sessions are never adjacent even
    /// at the same chunk index — so the OTHER session's identical text must survive.
    ///
    /// RED by deleting the `adjacent` check in `retrieve`: the same-session count goes to 2.
    @Test func adjacentChunksOfTheSameSessionAreDeDuplicated() throws {
        let session = UUID()
        let hits = MemoryRetriever.retrieve(query: "which colour did we pick for the hallway",
                                            candidates: hallwayFixture(session: session))
        try #require(!hits.isEmpty, "the fixture must actually admit something, or this test proves nothing")
        let sameSession = hits.filter { $0.candidate.sessionID == session }
        #expect(sameSession.count == 1,
                "adjacent chunks of one session must collapse to one, got \(sameSession.map(\.candidate.chunkIndex))")
        #expect(hits.count == 2, "the other session's identical text is a DIFFERENT memory and must survive")
    }

    // MARK: - A store too small for a distribution

    /// Rows that all answer "when is my dentist appointment" equally (overlap 1.0), so the
    /// score distribution is a flat pair against zeros — the case the fixed `count < 4`
    /// threshold missed.
    private func dentistRows(total: Int, matching: Int = 2) -> [MemoryCandidate] {
        let matches = ["My dentist is Dr. Patel on Lamar, appointments are usually Tuesday mornings.",
                       "The dentist appointment got moved to the afternoon."]
        let noise = ["Set a timer for twelve minutes.", "What's the square root of 144?",
                     "Play some rain sounds to help me focus.", "How far away is the moon from Earth?",
                     "Suggest a name for a new houseplant.", "Convert 5 miles to kilometers for me.",
                     "What year did the Berlin Wall come down?", "Mute notifications for the next hour."]
        return (0 ..< total).map { i in
            let text = i < matching ? matches[i % matches.count] : noise[(i - matching) % noise.count]
            // Descending `sentAt`, so the FIRST match is the newest and the tie-break puts
            // it first — the assertion on order is then about the scorer, not about luck.
            return MemoryCandidate(entryID: UUID(), sessionID: UUID(), chunkIndex: i, text: text,
                                   sentAt: Date(timeIntervalSince1970: 10_000 - Double(i)))
        }
    }

    /// Relative admission is arithmetically impossible on a small store, and this is the
    /// FIRST-RUN path. With the sample standard deviation the largest attainable z is a
    /// function of how many rows SHARE the top score: for a single outlier it is (n−1)/√n
    /// (reaching 1.5 at n = 4), but for TWO equally-matching rows it is 0.87 · 1.10 · 1.29 ·
    /// 1.46 at n = 4 · 5 · 6 · 7 — under 1.5 until n = 8. A fixed `count < 4` threshold
    /// therefore only moved the cliff: a five-row store with two dentist rows still
    /// retrieved nothing.
    ///
    /// So the rule is the general shape rather than a count: when relative admission admits
    /// NOTHING and the store is smaller than 8 rows, the anchor admits on its own.
    ///
    /// RED before that change: n = 5 and n = 7 return an empty array.
    @Test func aSmallStoreWithTwoEquallyMatchingRowsRetrievesBoth() throws {
        for total in [5, 7] {
            let rows = dentistRows(total: total)
            let hits = MemoryRetriever.retrieve(query: "when is my dentist appointment",
                                                candidates: rows)
            #expect(hits.count == 2, "a \(total)-row store with two matches must return both, got \(hits.count)")
            #expect(hits.map(\.candidate.text) == [rows[0].text, rows[1].text],
                    "best first, then newest — got \(hits.map(\.candidate.text))")
        }
    }

    /// The single-outlier cases the first fix already covered, kept: one perfect match in a
    /// one-, two- or three-row store.
    @Test func aStoreWithFewerThanFourRowsStillRetrievesAPerfectMatch() throws {
        let dentist = "My dentist is Dr. Patel on Lamar, appointments are usually Tuesday mornings."
        let noise = ["Set a timer for twelve minutes.", "What's the square root of 144?"]
        for count in 1 ... 3 {
            var rows = [MemoryCandidate(entryID: UUID(), sessionID: UUID(), chunkIndex: 0,
                                        text: dentist, sentAt: Date(timeIntervalSince1970: 1_000))]
            for i in 0 ..< (count - 1) {
                rows.append(MemoryCandidate(entryID: UUID(), sessionID: UUID(), chunkIndex: 0,
                                            text: noise[i],
                                            sentAt: Date(timeIntervalSince1970: 2_000 + Double(i))))
            }
            let hits = MemoryRetriever.retrieve(query: "who is my dentist", candidates: rows)
            #expect(hits.count == 1, "a \(count)-row store must still answer, got \(hits.count)")
            #expect(hits.first?.candidate.text == dentist)
        }
    }

    /// The anchor still applies below the threshold — a small store is not an open door.
    @Test func aTinyStoreStillRefusesAQueryNothingMatches() {
        let rows = ["Set a timer for twelve minutes.", "What's the square root of 144?"]
            .enumerated().map {
                MemoryCandidate(entryID: UUID(), sessionID: UUID(), chunkIndex: $0.offset,
                                text: $0.element, sentAt: Date(timeIntervalSince1970: 1_000))
            }
        #expect(MemoryRetriever.retrieve(query: "who is my dentist", candidates: rows).isEmpty)
    }

    /// At n ≥ 8 the fallback is off and the relative rule alone governs. Two matches among
    /// eight non-matching rows reach z = 1.897, so they are admitted BY the relative rule —
    /// the fallback is not what returns them, and the boundary is therefore not a cliff in
    /// the other direction either.
    @Test func atEightRowsOrMoreTheRelativeRuleAdmitsOnItsOwn() {
        let rows = dentistRows(total: 10)
        let hits = MemoryRetriever.retrieve(query: "when is my dentist appointment", candidates: rows)
        #expect(hits.count == 2)
        #expect(hits.map(\.candidate.text) == [rows[0].text, rows[1].text])
    }

    /// …and what the relative rule yields on a FLAT distribution at n ≥ 8, pinned as the
    /// behaviour it is rather than assumed. Ten rows that all match equally have sd = 0:
    /// nothing stands out, so nothing is admitted, and the small-store fallback deliberately
    /// does not rescue it — at ten rows "everything matches equally" is a reason to stay
    /// silent rather than to inject ten identical memories.
    @Test func aFlatDistributionAtEightRowsOrMoreAdmitsNothing() {
        let text = "My dentist is Dr. Patel on Lamar, appointments are usually Tuesday mornings."
        let rows = (0 ..< 10).map { i in
            MemoryCandidate(entryID: UUID(), sessionID: UUID(), chunkIndex: i, text: text,
                            sentAt: Date(timeIntervalSince1970: 10_000 - Double(i)))
        }
        #expect(MemoryRetriever.retrieve(query: "when is my dentist appointment", candidates: rows).isEmpty)
    }

    // MARK: - Determinism

    /// `sorted(by:)` is NOT stable in Swift, and 13 of the 75 answerable corpus queries tie
    /// at rank 1 — so without an explicit tie-break the reported p@1 depends on the order
    /// the candidate array happened to arrive in, which is a fetch's business and not a
    /// property of the scorer. Under adversarial ordering the same corpus scores anywhere
    /// from 59 to 68 of 75.
    ///
    /// RED by removing the secondary sort keys: shuffling changes the hit list.
    @Test func theHitListDoesNotDependOnCandidateOrder() throws {
        let session = UUID()
        let fixture = hallwayFixture(session: session)
        let reference = MemoryRetriever.retrieve(query: "which colour did we pick for the hallway",
                                                 candidates: fixture)
        try #require(!reference.isEmpty)
        var generator = SystemRandomNumberGenerator()
        for _ in 0 ..< 12 {
            let shuffled = fixture.shuffled(using: &generator)
            let hits = MemoryRetriever.retrieve(query: "which colour did we pick for the hallway",
                                                candidates: shuffled)
            #expect(hits.map(\.candidate.entryID) == reference.map(\.candidate.entryID),
                    "the hit list must not depend on the order the rows were fetched in")
        }
    }

    // MARK: - The gates around retrieval

    /// Retrieval on a bare accept or an anaphoric follow-up searches the store with the
    /// wrong words — "another one" is about the PREVIOUS turn, and its own tokens describe
    /// nothing. Deliberately exact sets rather than a length threshold, the shape
    /// `LocalChatBackend.shortAffirmatives` already uses: a token-count rule measured on
    /// the 422-R corpus skips four answerable queries ("who is my dentist",
    /// "when is our anniversary", "what do I collect", "what are we saving up for") while
    /// still passing "another one" through.
    @Test func anaphorsAndShortAffirmativesSkipRetrieval() {
        #expect(MemoryRetriever.shouldSkip("yes please"))
        #expect(MemoryRetriever.shouldSkip("another one"))
        #expect(MemoryRetriever.shouldSkip("say that again"))
        #expect(MemoryRetriever.shouldSkip("another  one"), "internal whitespace must normalize too")
        #expect(MemoryRetriever.shouldSkip("another one ."), "a detached trailing stop must not defeat the set")
        #expect(!MemoryRetriever.shouldSkip("where does my sister live"))
        #expect(!MemoryRetriever.shouldSkip("who is my dentist"))
        #expect(!MemoryRetriever.shouldSkip("what do I collect"))
    }

    @Test func memoryShapedQuestionsAreDetected() {
        #expect(MemoryRetriever.isMemoryShapedQuestion("what do you remember about my sister"))
        #expect(MemoryRetriever.isMemoryShapedQuestion("what did I tell you about the hallway"))
        #expect(!MemoryRetriever.isMemoryShapedQuestion("write a haiku about rain"))
    }
}
