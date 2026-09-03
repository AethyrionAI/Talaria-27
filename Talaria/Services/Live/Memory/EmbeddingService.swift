import Foundation
import NaturalLanguage
import Accelerate

final class EmbeddingService {
    static let embedderID = "nl.sentence.en.r1"
    private var sentence: NLEmbedding?

    /// 422-C's measured acquisition behaviour (probe 2026-09-02, sim `24A5423a`, IN-BUNDLE):
    /// the FIRST `NLEmbedding.sentenceEmbedding(for:)` call in a process returns `nil` and logs
    /// *"Unable to locate Asset for sentence embedding model for local en."*; the second and every
    /// later call returns a working 512-dim embedder (R1 nil, R2–R5 512, five identical calls and
    /// nothing else in the process). So a single immediate retry is the whole fix — no
    /// `NLContextualEmbedding`, no `requestAssets`, no `async`, no network.
    ///
    /// The earlier "contextual warm-up" reading was a MIS-ATTRIBUTION: the design lane's probe
    /// interposed a contextual construction between call 1 and call 2 and never discriminated the
    /// two explanations. In-bundle on this sim the contextual path in fact throws at every stage.
    ///
    /// Device retry behaviour is UNMEASURED (DE1 carries it), which is why `embed(_:)` re-attempts
    /// acquisition rather than trusting `init` alone.
    init() {
        sentence = NLEmbedding.sentenceEmbedding(for: .english)
            ?? NLEmbedding.sentenceEmbedding(for: .english)
    }

    /// Re-attempts acquisition once per call while the embedder is still absent, so a runtime whose
    /// asset lands later in the process self-heals instead of staying dead for the app's lifetime.
    /// Returns nil until acquisition succeeds — callers fall back to the lexical scorer.
    func embed(_ text: String) -> [Float]? {
        if sentence == nil { sentence = NLEmbedding.sentenceEmbedding(for: .english) }
        guard let sentence, let v = sentence.vector(for: text) else { return nil }
        return v.map(Float.init)
    }

    static func cosine(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0, na: Float = 0, nb: Float = 0
        vDSP_dotpr(a, 1, b, 1, &dot, vDSP_Length(a.count))
        vDSP_dotpr(a, 1, a, 1, &na, vDSP_Length(a.count))
        vDSP_dotpr(b, 1, b, 1, &nb, vDSP_Length(b.count))
        let denom = sqrt(na) * sqrt(nb)
        return denom == 0 ? 0 : dot / denom
    }

    static let stopWords: Set<String> = ["the","a","an","and","or","of","to","in","on","at","is","are","was","were","my","your",
        "i","me","you","it","its","this","that","do","does","did","what","when","where","who","which","how","for","with","about",
        "have","has","had","be","been","we","our","us","they","them","he","she","his","her","not","no","yes","please"]

    static func contentTokens(_ text: String) -> Set<String> {
        Set(text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
            .filter { $0.count > 2 && !stopWords.contains($0) })
    }

    static func lexicalOverlap(query: String, chunk: String) -> Float {
        let q = contentTokens(query); guard !q.isEmpty else { return 0 }
        let c = contentTokens(chunk)
        return Float(q.intersection(c).count) / Float(q.count)
    }

    static func encode(_ v: [Float]) -> Data { v.withUnsafeBufferPointer { Data(buffer: $0) } }
    static func decode(_ d: Data) -> [Float] { d.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) } }
}
