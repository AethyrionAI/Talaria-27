import Testing
import Foundation
import NaturalLanguage
@testable import Talaria

@Suite("422-C embedder")
struct EmbeddingServiceTests {

    /// Polls `embed` until it yields a vector or the budget runs out, timing with a monotonic
    /// clock. The clock starts BEFORE the service is constructed, so the reported time covers
    /// `init`'s own acquisition attempts too — the thing that actually costs.
    private func firstVector(budget: Duration = .seconds(3))
        async throws -> (service: EmbeddingService, vector: [Float]?, ms: Double) {
        let clock = ContinuousClock()
        let start = clock.now
        let service = EmbeddingService()
        repeat {
            if let v = service.embed("remember that my dentist is on Friday") {
                return (service, v, Double((clock.now - start) / .milliseconds(1)))
            }
            try await Task.sleep(for: .milliseconds(50))
        } while clock.now - start < budget
        return (service, nil, Double((clock.now - start) / .milliseconds(1)))
    }

    /// Pins the measured acquisition shape (sim 24A5423a, in-bundle): the FIRST
    /// NLEmbedding.sentenceEmbedding(for:) call in a process returns nil, logging "Unable to
    /// locate Asset for sentence embedding model for local en.". Usually the very next call
    /// returns the 512-dim embedder — but in 1 of 6 fresh-build runs three back-to-back calls
    /// all returned nil, each in ~0.5-2.5 ms: the shape of a CACHED NEGATIVE, i.e. the variable
    /// is elapsed time, not attempt count. So availability is pinned over a bounded WINDOW,
    /// which is also the production behaviour, rather than as a tuned retry count.
    ///
    /// Delete this test the day clean-build runs print "1 acquisition attempt" consistently —
    /// that is a runtime whose FIRST call returns the embedder. Say so in the entry.
    @Test func theSentenceEmbedderBecomesAvailableWithinTheBoundedWindow() async throws {
        let r = try await firstVector()
        print("422-C: first vector after \(r.service.acquisitionAttempts) acquisition attempt(s), "
            + "\(String(format: "%.1f", r.ms)) ms to first vector")
        #expect(r.vector?.count == 512,
                "sentence embedder returned \(r.vector?.count ?? -1) dims after \(r.service.acquisitionAttempts) acquisition attempt(s) in \(r.ms) ms")
        #expect(r.service.isAvailable, "isAvailable must be true once a vector has been produced")
        #expect(r.service.acquisitionAttempts >= 1)
    }

    /// A real embedder for the seam closures. The seam controls WHEN acquisition succeeds, not
    /// WHAT it returns, so these tests still need the runtime's embedder once.
    private func realEmbedder() async throws -> NLEmbedding {
        _ = try await firstVector()
        return try #require(NLEmbedding.sentenceEmbedding(for: .english),
                            "no sentence embedder available to drive the seam")
    }

    /// Pins `init`'s retry: one nil then a real embedder must leave the service available after
    /// construction alone, having asked exactly twice. RED by deleting `?? attempt()` from init.
    @Test func initRetriesAcquisitionOnceWhenTheFirstCallReturnsNil() async throws {
        let real = try await realEmbedder()
        var calls = 0
        let service = EmbeddingService(acquire: {
            calls += 1
            return calls < 2 ? nil : real
        })
        #expect(service.isAvailable, "init must retry once when the first acquisition returns nil")
        #expect(calls == 2, "init must ask exactly twice, got \(calls)")
        #expect(service.acquisitionAttempts == 2)
        #expect(service.embed("remember that my dentist is on Friday")?.count == 512)
        #expect(calls == 2, "a held embedder must not be re-acquired")
    }

    /// Pins `embed`'s self-heal: when init's two attempts both fail, every later `embed` must
    /// re-attempt until the embedder arrives. RED by deleting embed's re-attempt line.
    @Test func embedReAcquiresOnEveryCallUntilTheEmbedderArrives() async throws {
        let real = try await realEmbedder()
        var calls = 0
        let service = EmbeddingService(acquire: {
            calls += 1
            return calls < 4 ? nil : real
        })
        #expect(service.isAvailable == false, "init's two attempts both fail in this arm")
        #expect(calls == 2, "init must ask exactly twice, got \(calls)")

        #expect(service.embed("first") == nil)
        #expect(calls == 3, "the first embed must re-attempt acquisition, got \(calls)")

        #expect(service.embed("remember that my dentist is on Friday")?.count == 512)
        #expect(calls == 4, "the second embed must re-attempt again, got \(calls)")
        #expect(service.isAvailable, "a successful re-acquire must be retained")
        #expect(service.acquisitionAttempts == 4)
    }

    @Test func cosineOfAVectorWithItselfIsOne() {
        #expect(abs(EmbeddingService.cosine([1, 2, 3], [1, 2, 3]) - 1) < 0.0001)
    }

    /// A NaN must score 0, never propagate into the ranking as a NaN comparison.
    @Test func cosineOfANaNVectorIsZero() {
        #expect(EmbeddingService.cosine([Float.nan, 1, 2], [1, 2, 3]) == 0)
        #expect(EmbeddingService.cosine([0, 0, 0], [1, 2, 3]) == 0)
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

    /// A blob whose length is not a whole number of Floats is CORRUPT, and a truncated vector
    /// would score a plausible cosine — indistinguishable from an unrelated chunk.
    @Test func aMalformedBlobDecodesToEmpty() {
        #expect(EmbeddingService.decode(Data(count: 6)) == [])
        #expect(EmbeddingService.decode(Data(count: 1)) == [])
        #expect(EmbeddingService.decode(Data()) == [])
    }

    /// A slice of a larger buffer has a non-zero `startIndex` and no alignment promise — the
    /// exact shape SwiftData hands back. Copy-based decode must still be correct.
    @Test func aSliceOfALargerBufferRoundTrips() {
        let whole = EmbeddingService.encode([1, 2, 3, 4])
        let tail = whole[(whole.startIndex + 4)...]
        #expect(tail.count == 12)
        #expect(EmbeddingService.decode(tail) == [2, 3, 4])
        #expect(EmbeddingService.decode(Data(tail)) == [2, 3, 4])
    }
}
