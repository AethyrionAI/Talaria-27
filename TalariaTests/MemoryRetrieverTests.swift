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
            MemoryCandidate(entryID: UUID(), sessionID: UUID(), chunkIndex: $0.id,
                            text: $0.text, sentAt: Date())
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
            $0.formUnion(EmbeddingService.contentTokens($1.text))
        }
        for query in corpus.queries where query.queryClass == "plain" {
            let shared = EmbeddingService.contentTokens(query.text).intersection(turnTokens)
            #expect(shared.isEmpty,
                    "plain query \(query.text.debugDescription) shares \(shared.sorted()) with a turn")
        }
    }

    // MARK: - Top-k shape

    /// Two chunks of one long turn are one memory, not two: admitting both spends the
    /// token budget twice on the same sentence. Distinct sessions are never adjacent even
    /// at the same chunk index.
    @Test func adjacentChunksOfTheSameSessionAreDeDuplicated() {
        let session = UUID()
        let text = "We decided to go with the blue paint for the hallway, not the grey."
        func chunk(_ index: Int, _ sessionID: UUID, _ body: String) -> MemoryCandidate {
            MemoryCandidate(entryID: UUID(), sessionID: sessionID, chunkIndex: index,
                            text: body, sentAt: Date())
        }
        let candidates = [chunk(0, session, text), chunk(1, session, text),
                          chunk(0, UUID(), text),
                          chunk(7, UUID(), "How many calories are in a medium banana?"),
                          chunk(8, UUID(), "What year did the Berlin Wall come down?"),
                          chunk(9, UUID(), "Set a timer for twelve minutes.")]
        let hits = MemoryRetriever.retrieve(query: "which colour did we pick for the hallway",
                                            candidates: candidates)
        let sameSession = hits.filter { $0.candidate.sessionID == session }
        #expect(sameSession.count <= 1,
                "adjacent chunks of one session must collapse, got \(sameSession.map(\.candidate.chunkIndex))")
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
