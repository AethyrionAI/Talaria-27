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
    @Test func aSingleOverCapSentenceSplitsOnWordBoundariesWithoutLoss() {
        let words = (1...130).map { "word\($0)" }        // no punctuation — one sentence
        let source = words.joined(separator: " ")
        let chunks = MemoryChunker.chunk(source, maxWords: 60)
        #expect(chunks.count >= 3)
        #expect(chunks.allSatisfy { $0.split(whereSeparator: \.isWhitespace).count <= 60 })
        #expect(chunks.flatMap { $0.split(whereSeparator: \.isWhitespace).map(String.init) } == words,
                "an over-cap sentence must split verbatim — no loss, no reorder")
    }
    @Test func tabsAndNewlinesCountAsWordSeparators() {
        let separators = [" ", "\t", "\n"]
        let words = (1...120).map { "w\($0)" }            // no punctuation
        var mixed = words[0]
        for (i, word) in words.dropFirst().enumerated() { mixed += separators[i % 3] + word }
        let chunks = MemoryChunker.chunk(mixed, maxWords: 60)
        #expect(!chunks.isEmpty)
        #expect(chunks.allSatisfy { $0.split(whereSeparator: \.isWhitespace).count <= 60 },
                "a tab or newline between words must not glue them into one token")
    }
    @Test func whitespaceOnlyYieldsNothing() { #expect(MemoryChunker.chunk("   \n ").isEmpty) }
}
