import Foundation
import NaturalLanguage
import Accelerate

final class EmbeddingService {
    static let embedderID = "nl.sentence.en.r1"
    private var sentence: NLEmbedding?
    private let acquire: () -> NLEmbedding?

    /// True once the embedder is held. Lets a caller observe acquisition without embedding
    /// anything — and lets a test watch the per-call self-heal in `embed(_:)` take effect.
    var isAvailable: Bool { sentence != nil }

    /// 422-C's measured acquisition behaviour (probe 2026-09-02, sim `24A5423a`, IN-BUNDLE):
    /// the FIRST `NLEmbedding.sentenceEmbedding(for:)` call in a process returns `nil` and logs
    /// *"Unable to locate Asset for sentence embedding model for local en."*; the second and every
    /// later call returns a working 512-dim embedder (R1 nil, R2–R5 512, five identical calls and
    /// nothing else in the process). No `NLContextualEmbedding`, no `requestAssets`, no `async`,
    /// no network.
    ///
    /// But an immediate retry is NOT a guarantee: in 1 of 6 fresh-build runs three back-to-back
    /// calls all returned nil, each in ~0.5–2.5 ms — the shape of a CACHED NEGATIVE, i.e. the
    /// variable is ELAPSED TIME, not attempt count. So `init` takes the cheap two attempts and
    /// `embed(_:)` carries the real guarantee by re-attempting on every call. Deliberately no
    /// sleep here: `init` may run on the main thread at launch.
    ///
    /// The earlier "contextual warm-up" reading was a MIS-ATTRIBUTION: the design lane's probe
    /// interposed a contextual construction between call 1 and call 2 and never discriminated the
    /// two explanations. In-bundle on this sim the contextual path in fact throws at every stage.
    ///
    /// Device retry behaviour is UNMEASURED (DE1 carries it), which is why `embed(_:)` re-attempts
    /// acquisition rather than trusting `init` alone.
    init() {
        acquire = { NLEmbedding.sentenceEmbedding(for: .english) }
        sentence = acquire() ?? acquire()
    }

    /// Test seam — drives acquisition without the NaturalLanguage runtime, so the self-heal
    /// contract can be pinned on any machine. Deliberately does NOT pre-acquire: the service
    /// starts with no embedder, leaving `embed(_:)`'s per-call re-attempt as the only thing
    /// that can make it available.
    // harness-visible
    init(acquire: @escaping () -> NLEmbedding?) {
        self.acquire = acquire
    }

    /// Re-attempts acquisition once per call while the embedder is still absent, so a runtime whose
    /// asset lands later in the process self-heals instead of staying dead for the app's lifetime.
    /// Returns nil until acquisition succeeds — callers fall back to the lexical scorer.
    func embed(_ text: String) -> [Float]? {
        if sentence == nil { sentence = acquire() }
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
