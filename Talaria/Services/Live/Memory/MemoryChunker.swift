import Foundation
import NaturalLanguage

enum MemoryChunker {
    /// Verbatim chunks on sentence boundaries, each ≤ `maxWords`. A single
    /// sentence longer than the cap is split on word boundaries — still verbatim.
    static func chunk(_ text: String, maxWords: Int = 60) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = trimmed
        var sentences: [String] = []
        tokenizer.enumerateTokens(in: trimmed.startIndex..<trimmed.endIndex) { range, _ in
            let s = trimmed[range].trimmingCharacters(in: .whitespacesAndNewlines)
            if !s.isEmpty { sentences.append(s) }
            return true
        }
        var chunks: [String] = [], current: [String] = [], currentWords = 0
        func flush() { if !current.isEmpty { chunks.append(current.joined(separator: " ")); current = []; currentWords = 0 } }
        for sentence in sentences {
            let words = sentence.split(separator: " ").map(String.init)
            if words.count > maxWords {
                flush()
                for start in stride(from: 0, to: words.count, by: maxWords) {
                    chunks.append(words[start..<min(start + maxWords, words.count)].joined(separator: " "))
                }
                continue
            }
            if currentWords + words.count > maxWords { flush() }
            current.append(sentence); currentWords += words.count
        }
        flush()
        return chunks
    }
}
