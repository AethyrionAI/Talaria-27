import Foundation
import NaturalLanguage
import Accelerate
import os

final class EmbeddingService {
    static let embedderID = "nl.sentence.en.r1"
    private static let logger = Logger(subsystem: "org.aethyrion.talaria", category: "EmbeddingService")

    private var sentence: NLEmbedding?
    private let acquire: () -> NLEmbedding?

    /// True once the embedder is held. Lets a caller or a test observe acquisition without
    /// embedding anything.
    var isAvailable: Bool { sentence != nil }

    /// Every call to `acquire` this service has made — in `init` and in `embed(_:)` alike.
    /// Observable so a test can report the REAL cost of acquisition (and so the deletion
    /// condition on the bounded-window test is something a run can print rather than infer).
    private(set) var acquisitionAttempts = 0

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
        sentence = acquireAtInit()
    }

    /// Test seam. The closure controls WHEN acquisition succeeds — it does NOT remove the
    /// NaturalLanguage dependency: the successful value is still a real `NLEmbedding`, so the
    /// seam tests must obtain the runtime's embedder once before they can drive it. Performs the
    /// SAME acquisition as the public `init` (plain call plus one retry) so both the init retry
    /// and `embed`'s self-heal are pinnable through it.
    // harness-visible
    init(acquire: @escaping () -> NLEmbedding?) {
        self.acquire = acquire
        sentence = acquireAtInit()
    }

    /// The init-time acquisition, shared by BOTH inits on purpose: the seam tests then pin the
    /// very code the production init runs, so deleting the retry here fails a test.
    private func acquireAtInit() -> NLEmbedding? { attempt() ?? attempt() }

    private func attempt() -> NLEmbedding? {
        acquisitionAttempts += 1
        return acquire()
    }

    /// Re-attempts acquisition once per call while the embedder is still absent, so a runtime whose
    /// asset lands later in the process self-heals instead of staying dead for the app's lifetime.
    /// Returns nil until acquisition succeeds — callers fall back to the lexical scorer.
    func embed(_ text: String) -> [Float]? {
        if sentence == nil { sentence = attempt() }
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
        // `.isNormal` rejects zero, subnormal, infinite AND NaN denominators in one test — a NaN
        // anywhere in either vector must score 0, never propagate NaN into the ranking.
        guard denom.isNormal else { return 0 }
        return dot / denom
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

    /// Copy-based on purpose. `Data.withUnsafeBytes { $0.bindMemory(to: Float.self) }` assumes the
    /// buffer is 4-byte aligned, which a SwiftData blob — or a SLICE of one, whose `startIndex` is
    /// not 0 — does not promise. A malformed length returns `[]` rather than silently truncating:
    /// a truncated vector scores a plausible cosine and would be indistinguishable from a merely
    /// unrelated chunk, so the corruption would never surface.
    static func decode(_ d: Data) -> [Float] {
        let stride = MemoryLayout<Float>.stride
        guard d.count % stride == 0 else {
            logMalformedBlobOnce(byteCount: d.count)
            return []
        }
        var out = [Float](repeating: 0, count: d.count / stride)
        _ = out.withUnsafeMutableBytes { d.copyBytes(to: $0) }
        return out
    }

    /// One line per process: a corrupt store would otherwise log once per row per query.
    /// The unsynchronised flag can race into logging twice, which is harmless and cheaper than
    /// a lock on a diagnostic.
    nonisolated(unsafe) private static var didLogMalformedBlob = false
    private static func logMalformedBlobOnce(byteCount: Int) {
        guard !didLogMalformedBlob else { return }
        didLogMalformedBlob = true
        logger.error("memory vector blob malformed (\(byteCount, privacy: .public) bytes)")
    }
}
