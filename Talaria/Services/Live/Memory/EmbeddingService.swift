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

    /// What the split leaves behind when a contraction meets a non-alphanumeric separator:
    /// "don't" becomes "don" + "t". The "t" dies on the length filter, but "don" is three
    /// characters and passes — so a turn about coffee and a query about anything else share
    /// a token for free, and every apostrophe in the store is a small dose of noise.
    /// Deliberately omits "can" and "won", which are also real words: "who won the world cup"
    /// must keep its verb.
    static let contractionFragments: Set<String> = [
        "ain", "aren", "couldn", "didn", "doesn", "don", "hadn", "hasn", "haven", "isn",
        "mustn", "needn", "shan", "shouldn", "wasn", "weren", "wouldn",
    ]

    /// One pass, longest suffix first. `es` is tried before `s` so "boxes" reaches "box",
    /// and falls THROUGH to `s` when the stem is not sibilant so that "lives" reaches
    /// "live" rather than "liv" — which matters because "live" is itself too short to
    /// stem, and a rule that moves the plural but not the singular manufactures exactly
    /// the mismatch the stemmer exists to remove.
    private static let stemSuffixes: [(suffix: String, replacement: String)] = [
        ("ies", "y"), ("ing", ""), ("ed", ""), ("ly", ""), ("er", ""), ("es", ""), ("s", ""),
    ]
    private static let sibilantStemEndings = ["s", "x", "z", "ch", "sh"]

    /// A light, deterministic suffix stemmer. Authorized by Owen 2026-09-03 after 422-R
    /// measured exact-match tokens as a limiting factor (`lives`/`live`, `mowed`/`mow`,
    /// `allergies`/`allergic` all missed).
    ///
    /// It is not a linguist's stemmer and does not try to be: "water" becomes "wat" and
    /// "brother" becomes "broth". That is harmless because BOTH sides of every comparison
    /// pass through it — overlap needs the two stems to AGREE, not to be words. The
    /// guards that do matter are the ones that keep it from disagreeing with itself:
    /// a 5-character floor before stemming at all, a 3-character floor on what is left,
    /// and un-doubling after `ing`/`ed` so "running" and "run" meet.
    static func stem(_ word: String) -> String {
        guard word.count >= 5 else { return word }
        for (suffix, replacement) in stemSuffixes {
            guard word.hasSuffix(suffix) else { continue }
            // "address" is not a plural.
            if suffix == "s", word.hasSuffix("ss") { continue }
            var base = String(word.dropLast(suffix.count)) + replacement
            if suffix == "es", !sibilantStemEndings.contains(where: { base.hasSuffix($0) }) { continue }
            guard base.count >= 3 else { continue }
            if suffix == "ing" || suffix == "ed" { base = undoubled(base) }
            return base
        }
        return word
    }

    /// "runn" → "run", "stopp" → "stop". English does not double l, s or z for this
    /// reason ("calling" → "call"), and a doubled vowel is not a doubling at all.
    private static func undoubled(_ base: String) -> String {
        guard base.count >= 2 else { return base }
        let last = base[base.index(before: base.endIndex)]
        let penultimate = base[base.index(base.endIndex, offsetBy: -2)]
        guard last == penultimate, !"aeiou".contains(last), !"lsz".contains(last) else { return base }
        return String(base.dropLast())
    }

    static func contentTokens(_ text: String) -> Set<String> {
        Set(text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
            .filter { $0.count > 2 && !stopWords.contains($0) && !contractionFragments.contains($0) }
            .map(stem))
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
