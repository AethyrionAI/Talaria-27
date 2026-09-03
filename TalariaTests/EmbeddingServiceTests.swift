import Testing
import Foundation
import NaturalLanguage
@testable import Talaria

@Suite("422-C embedder")
struct EmbeddingServiceTests {

    /// Polls `embed` within a bounded window, stopping at the first non-nil vector.
    /// Mirrors production, where `embed(_:)` re-attempts acquisition on every call.
    private func acquireVector(_ service: EmbeddingService,
                               budgetSeconds: Double = 3.0) async throws -> (vector: [Float]?, attempts: Int, ms: Double) {
        let start = Date()
        var attempts = 0
        repeat {
            attempts += 1
            if let v = service.embed("remember that my dentist is on Friday") {
                return (v, attempts, Date().timeIntervalSince(start) * 1000)
            }
            try await Task.sleep(for: .milliseconds(50))
        } while Date().timeIntervalSince(start) < budgetSeconds
        return (nil, attempts, Date().timeIntervalSince(start) * 1000)
    }

    /// Pins the measured acquisition shape (sim 24A5423a, in-bundle): the FIRST
    /// NLEmbedding.sentenceEmbedding(for:) call in a process returns nil, logging "Unable to
    /// locate Asset for sentence embedding model for local en.". Usually the very next call
    /// returns the 512-dim embedder — but in 1 of 6 fresh-build runs three back-to-back calls
    /// all failed, returning in ~0.5-2.5 ms each: the shape of a CACHED NEGATIVE, i.e. the
    /// variable is elapsed time, not attempt count. So this pins availability over a bounded
    /// WINDOW, which is also the production behaviour (`embed` re-attempts per call) rather
    /// than a tuned retry count. Delete this test the day a runtime's FIRST call returns the
    /// embedder — and say so in the entry.
    @Test func theFirstCallRetryMakesTheSentenceEmbedderAvailable() async throws {
        let service = EmbeddingService()
        let r = try await acquireVector(service)
        print("422-C: sentence embedder acquired after \(r.attempts) attempt(s), \(String(format: "%.1f", r.ms)) ms")
        #expect(r.vector?.count == 512,
                "sentence embedder returned \(r.vector?.count ?? -1) dims after \(r.attempts) attempt(s) in \(r.ms) ms")
        #expect(service.isAvailable, "isAvailable must be true once a vector has been produced")
    }

    /// Pins the self-heal CONTRACT without the NaturalLanguage runtime: while the embedder is
    /// absent, `embed(_:)` re-attempts acquisition on every call — so a runtime whose asset
    /// lands late self-heals instead of staying dead for the process's life. RED-checked by
    /// deleting the re-attempt from `embed`: acquisition then never happens and all three
    /// calls return nil.
    @Test func embedReAcquiresOnEveryCallUntilTheEmbedderArrives() async throws {
        // A real embedder to hand back on the third acquisition, obtained through the same
        // bounded window so this test never depends on suite ordering.
        _ = try await acquireVector(EmbeddingService())
        let real = try #require(NLEmbedding.sentenceEmbedding(for: .english),
                                "no sentence embedder available to drive the seam")

        var calls = 0
        let service = EmbeddingService(acquire: {
            calls += 1
            return calls < 3 ? nil : real
        })

        #expect(service.isAvailable == false, "the seam must start with no embedder")
        #expect(service.embed("first") == nil)
        #expect(service.embed("second") == nil)
        #expect(service.embed("remember that my dentist is on Friday")?.count == 512)
        #expect(calls == 3, "embed must re-attempt acquisition once per call while absent, got \(calls)")
        #expect(service.isAvailable, "a successful re-acquire must be retained")
    }

    @Test func cosineOfAVectorWithItselfIsOne() {
        #expect(abs(EmbeddingService.cosine([1, 2, 3], [1, 2, 3]) - 1) < 0.0001)
    }
    @Test func lexicalOverlapCountsContentWordsOnly() {
        let o = EmbeddingService.lexicalOverlap(query: "who is my dentist", chunk: "My dentist is Dr. Patel on Lamar.")
        #expect(o == 1.0, "'dentist' is the only content word in the query and it is present")
        #expect(EmbeddingService.lexicalOverlap(query: "who is my dentist", chunk: "write a haiku about rain") == 0)
    }
    @Test func vectorsRoundTripThroughData() {
        let v: [Float] = [0.5, -1.25, 3]
        #expect(EmbeddingService.decode(EmbeddingService.encode(v)) == v)
    }
}
