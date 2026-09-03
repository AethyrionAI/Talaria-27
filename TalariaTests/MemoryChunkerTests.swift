import Testing
@testable import Talaria

@Suite("422-B chunker")
struct MemoryChunkerTests {
    @Test func aShortTurnIsOneChunk() {
        #expect(MemoryChunker.chunk("My dentist is Dr. Patel on Lamar.") == ["My dentist is Dr. Patel on Lamar."])
    }
    @Test func aLongTurnSplitsOnSentenceBoundariesUnderTheWordCap() {
        let sentence = "This sentence has exactly eight words in it. "
        let long = String(repeating: sentence, count: 20)      // 160 words
        let chunks = MemoryChunker.chunk(long, maxWords: 60)
        #expect(chunks.count >= 3)
        #expect(chunks.allSatisfy { $0.split(separator: " ").count <= 60 })
        #expect(chunks.joined(separator: " ").split(separator: " ").count == long.split(separator: " ").count,
                "chunking must lose no words — verbatim is the whole point")
    }
    @Test func whitespaceOnlyYieldsNothing() { #expect(MemoryChunker.chunk("   \n ").isEmpty) }
}
