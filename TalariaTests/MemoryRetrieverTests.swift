import Testing
import Foundation
@testable import Talaria

/// #422 (bar 422-R): the retriever, scored against the labelled corpus.
///
/// The bar is three numbers over two query classes, and each is REPORTED with its
/// denominator on a `422-R:` line so a run's log carries the measurement rather than
/// only its verdict: **precision@1 ≥ 0.80** on answerable queries, **false-admit
/// rate ≤ 0.10** on no-answer queries, **top-3 recall ≥ 0.90** on answerable queries.
///
/// A simulator process shares the Mac's filesystem, so `#filePath` resolves to the
/// checked-in corpus — the same route `InstrumentRegistryTests` and
/// `MemoryBackfillRunnerTests` already take.
@Suite("422-R retrieval")
struct MemoryRetrieverTests {

    // MARK: - The corpus

    /// `meta` (provenance + the privacy filter the corpus chore applied) rides the same
    /// file; `Decodable` ignores keys no property claims, so it is deliberately not
    /// modelled here.
    struct Corpus: Decodable {
        struct Turn: Decodable { let id: Int; let text: String }
        struct Query: Decodable { let text: String; let relevant: Int? }
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

    // MARK: - The embedder

    /// The runtime's sentence embedder, acquired over a bounded window. 422-C measured the
    /// variable to be ELAPSED TIME, not attempt count: the first call in a process reliably
    /// returns nil and a cold run can stay nil for several back-to-back calls. Every corpus
    /// number below is meaningless if this returns a service that never acquired — the
    /// scorer would silently degrade to lexical-only and the run would report the mutation
    /// arm's numbers under the hybrid arm's name. So the callers `#require` a real vector
    /// before scoring anything.
    private func acquiredEmbedder(budget: Duration = .seconds(3)) async -> (EmbeddingService, Double) {
        let clock = ContinuousClock()
        let start = clock.now
        let service = EmbeddingService()
        repeat {
            if service.embed("remember that my dentist is on Friday") != nil { break }
            try? await Task.sleep(for: .milliseconds(50))
        } while clock.now - start < budget
        return (service, Double((clock.now - start) / .milliseconds(1)))
    }

    /// Every corpus turn as a candidate, embedded by the live embedder. Distinct
    /// `sessionID`s on purpose: adjacent-chunk de-duplication is pinned by its own test,
    /// and it must not silently suppress corpus hits here.
    private func candidates(_ corpus: Corpus, _ embedder: EmbeddingService) -> [MemoryCandidate] {
        corpus.turns.map { turn in
            MemoryCandidate(entryID: UUID(), sessionID: UUID(), chunkIndex: turn.id,
                            text: turn.text, sentAt: Date(),
                            embedderID: EmbeddingService.embedderID,
                            vector: embedder.embed(turn.text) ?? [])
        }
    }

    /// One scoring pass over the whole corpus. Shared by the three bar tests so all three
    /// numbers come off the same denominators and the same vectors.
    private struct CorpusScore {
        let precisionAt1: Float, falseAdmitRate: Float, topThreeRecall: Float
        let correct: Int, answerable: Int, admits: Int, noAnswer: Int, recalled: Int
        var line: String {
            "422-R: p@1 \(correct)/\(answerable) = \(fmt(precisionAt1)) · "
                + "false-admit \(admits)/\(noAnswer) = \(fmt(falseAdmitRate)) · "
                + "top-3 recall \(recalled)/\(answerable) = \(fmt(topThreeRecall))"
        }
        private func fmt(_ v: Float) -> String { String(format: "%.3f", v) }
    }

    private func scoreCorpus() async throws -> CorpusScore {
        let corpus = try Self.loadCorpus()
        let (embedder, ms) = await acquiredEmbedder()
        let cands = candidates(corpus, embedder)

        // The cold-start guard. Without it a nil embedder reports lexical-only numbers as
        // hybrid ones — the exact confusion mutation M-R exists to measure.
        try #require(cands.first?.vector.isEmpty == false,
                     "no turn vector after \(ms) ms — the corpus numbers would be lexical-only by accident")
        let probe = try #require(embedder.embed(corpus.queries[0].text),
                                 "no query vector after \(ms) ms")
        #expect(probe.count == 512)

        let answerable = corpus.queries.filter { $0.relevant != nil }
        let noAnswer = corpus.queries.filter { $0.relevant == nil }
        var correct = 0, recalled = 0, admits = 0
        for query in answerable {
            let hits = MemoryRetriever.retrieve(query: query.text,
                                                queryVector: embedder.embed(query.text),
                                                candidates: cands,
                                                liveEmbedderID: EmbeddingService.embedderID)
            if hits.first?.candidate.chunkIndex == query.relevant { correct += 1 }
            if hits.contains(where: { $0.candidate.chunkIndex == query.relevant }) { recalled += 1 }
        }
        for query in noAnswer {
            let hits = MemoryRetriever.retrieve(query: query.text,
                                                queryVector: embedder.embed(query.text),
                                                candidates: cands,
                                                liveEmbedderID: EmbeddingService.embedderID)
            if !hits.isEmpty { admits += 1 }
        }
        return CorpusScore(precisionAt1: Float(correct) / Float(answerable.count),
                           falseAdmitRate: Float(admits) / Float(noAnswer.count),
                           topThreeRecall: Float(recalled) / Float(answerable.count),
                           correct: correct, answerable: answerable.count,
                           admits: admits, noAnswer: noAnswer.count, recalled: recalled)
    }

    // MARK: - Bar 422-R, the three numbers

    @Test func precisionAt1IsAtLeast0_80OnAnswerableQueries() async throws {
        let s = try await scoreCorpus()
        print(s.line)
        #expect(s.precisionAt1 >= 0.80, "p@1 \(s.correct)/\(s.answerable)")
    }

    @Test func falseAdmitRateIsAtMost0_10OnNoAnswerQueries() async throws {
        let s = try await scoreCorpus()
        print(s.line)
        #expect(s.falseAdmitRate <= 0.10, "false admits \(s.admits)/\(s.noAnswer)")
    }

    @Test func topThreeRecallIsAtLeast0_90OnAnswerableQueries() async throws {
        let s = try await scoreCorpus()
        print(s.line)
        #expect(s.topThreeRecall >= 0.90, "top-3 recall \(s.recalled)/\(s.answerable)")
    }

    // MARK: - Bar 422-C's scoring rule

    /// A row whose `embedderID` is not the live embedder's is never scored: its vector came
    /// out of a different model, so its cosine against a live query vector is a number with
    /// no meaning. This candidate carries a NON-EMPTY vector on purpose — the empty-vector
    /// case is the opposite ruling, pinned by the next test.
    @Test func aRowWithAForeignEmbedderIDIsNeverScored() async throws {
        let corpus = try Self.loadCorpus()
        let (embedder, ms) = await acquiredEmbedder()
        let vector = try #require(embedder.embed(corpus.turns[2].text),
                                  "no vector after \(ms) ms — this arm needs a NON-empty foreign vector")
        let foreign = MemoryCandidate(entryID: UUID(), sessionID: UUID(), chunkIndex: 2,
                                      text: corpus.turns[2].text, sentAt: Date(),
                                      embedderID: "some.other.embedder", vector: vector)
        #expect(MemoryRetriever.retrieve(query: corpus.turns[2].text,
                                         queryVector: embedder.embed(corpus.turns[2].text),
                                         candidates: [foreign],
                                         liveEmbedderID: EmbeddingService.embedderID).isEmpty)
    }

    /// Rows with an EMPTY vector are normal, not corrupt: everything indexed before the
    /// embedder acquired lands that way, and for a non-English user EVERY row does. They
    /// carry `embedderID == ""` after M1's fix wave. Such a row must still be scored — on
    /// the lexical term alone — or memory is dead for a whole class of user.
    @Test func anEmptyVectorCandidateIsScoredLexicallyRatherThanDropped() async throws {
        let (embedder, _) = await acquiredEmbedder()
        let texts = ["My dentist is Dr. Patel on Lamar, appointments are usually Tuesday mornings.",
                     "We decided to go with the blue paint for the hallway, not the grey.",
                     "I usually run on Saturday mornings along the river trail.",
                     "Our anniversary is October 14th, we got married in 2015.",
                     "The dog's name is Biscuit and he takes his heart pill at 8pm.",
                     "My car is due for an oil change at 42,000 miles."]
        let unembedded = texts.enumerated().map { index, text in
            MemoryCandidate(entryID: UUID(), sessionID: UUID(), chunkIndex: index, text: text,
                            sentAt: Date(), embedderID: "", vector: [])
        }
        // A live query vector, so the arm proves the CANDIDATE's empty vector routes to the
        // lexical term — not that a missing query vector does.
        let hits = MemoryRetriever.retrieve(query: "who is my dentist",
                                            queryVector: embedder.embed("who is my dentist"),
                                            candidates: unembedded,
                                            liveEmbedderID: EmbeddingService.embedderID)
        #expect(hits.first?.candidate.chunkIndex == 0,
                "an empty-vector row that lexically matches must be admitted, got \(hits.map(\.candidate.chunkIndex))")
    }

    // MARK: - Top-k shape

    /// Two chunks of one long turn are one memory, not two: admitting both spends the
    /// token budget twice on the same sentence. Distinct sessions are never adjacent even
    /// at the same chunk index.
    @Test func adjacentChunksOfTheSameSessionAreDeDuplicated() async throws {
        let (embedder, _) = await acquiredEmbedder()
        let session = UUID()
        let text = "We decided to go with the blue paint for the hallway, not the grey."
        func chunk(_ index: Int, _ sessionID: UUID, _ body: String) -> MemoryCandidate {
            MemoryCandidate(entryID: UUID(), sessionID: sessionID, chunkIndex: index, text: body,
                            sentAt: Date(), embedderID: EmbeddingService.embedderID,
                            vector: embedder.embed(body) ?? [])
        }
        let candidates = [chunk(0, session, text), chunk(1, session, text),
                          chunk(0, UUID(), text),
                          chunk(7, UUID(), "How many calories are in a medium banana?"),
                          chunk(8, UUID(), "What year did the Berlin Wall come down?"),
                          chunk(9, UUID(), "Set a timer for twelve minutes.")]
        let hits = MemoryRetriever.retrieve(query: "which colour did we pick for the hallway",
                                            queryVector: embedder.embed("which colour did we pick for the hallway"),
                                            candidates: candidates,
                                            liveEmbedderID: EmbeddingService.embedderID)
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
