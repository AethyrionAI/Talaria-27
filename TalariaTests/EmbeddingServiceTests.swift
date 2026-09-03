import Testing
@testable import Talaria

@Suite("422-C embedder")
struct EmbeddingServiceTests {
    /// Pins the acquisition retry measured 09-02 (sim 24A5423a, in-bundle): the FIRST
    /// NLEmbedding.sentenceEmbedding(for:) call in a process returns nil ("Unable to locate
    /// Asset for sentence embedding model for local en."), the second returns the 512-dim
    /// embedder — five identical calls, R1 nil and R2-R5 512, with nothing else in the process.
    /// It is a first-call retry, NOT the contextual warm-up the design lane inferred; that probe
    /// interposed an NLContextualEmbedding construction between the two calls and never
    /// discriminated them. Delete this test the day a runtime's FIRST call returns the embedder
    /// — and say so in the entry.
    @Test func theFirstCallRetryMakesTheSentenceEmbedderAvailable() {
        let service = EmbeddingService()
        let v = service.embed("remember that my dentist is on Friday")
        #expect(v?.count == 512, "sentence embedder returned \(v?.count ?? -1) dims")
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
