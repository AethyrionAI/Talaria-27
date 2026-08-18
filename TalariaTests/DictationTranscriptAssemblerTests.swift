import Testing
@testable import Talaria

/// #360 — the transcript assembler must be correct under BOTH readings of
/// the SDK contract: cumulative-snapshot results (each text spans the whole
/// utterance so far) AND range-scoped results with progressive finalization
/// (a result's text covers only its range; multiple finals per session).
/// These tests assert the desired semantics, so they are RED against the
/// verbatim pre-#360 extraction by design (bar 360-A).
struct DictationTranscriptAssemblerTests {

    // MARK: - 360-A(1): a mid-stream final must not behead later volatiles

    @Test
    func volatileAfterMidStreamFinalKeepsTheFinalizedPrefix() {
        var assembler = DictationTranscriptAssembler()
        assembler.acceptVolatile("Tell me a")
        assembler.acceptFinal("Tell me a s")
        // Range-scoped mode: the next volatile covers only the unfinalized
        // range. The finalized prefix must survive.
        assembler.acceptVolatile("hort story about")
        #expect(assembler.transcript == "Tell me a short story about")
    }

    // MARK: - 360-A(2): a second final accumulates instead of replacing

    @Test
    func secondFinalAccumulates() {
        var assembler = DictationTranscriptAssembler()
        assembler.acceptFinal("Tell me a s")
        assembler.acceptFinal("hort story, please.")
        #expect(assembler.transcript == "Tell me a short story, please.")
    }

    // MARK: - 360-A(3): cumulative snapshots must not double

    @Test
    func cumulativeSnapshotVolatileIsNotDoubled() {
        var assembler = DictationTranscriptAssembler()
        assembler.acceptFinal("Tell me a story")
        // Cumulative mode: the volatile REPEATS everything finalized so far.
        assembler.acceptVolatile("Tell me a story about a lighthouse")
        #expect(assembler.transcript == "Tell me a story about a lighthouse")
    }

    @Test
    func cumulativeFinalIsNotDoubled() {
        var assembler = DictationTranscriptAssembler()
        assembler.acceptFinal("Tell me a story")
        assembler.acceptFinal("Tell me a story about a lighthouse.")
        #expect(assembler.transcript == "Tell me a story about a lighthouse.")
    }

    // MARK: - 360-A(4): the finished transcript carries everything

    @Test
    func finishedTranscriptCarriesFinalizedAndVolatileTail() {
        var assembler = DictationTranscriptAssembler()
        assembler.acceptFinal("Tell me a short story,")
        // Continuation ranges carry their own leading whitespace — the
        // recognizer owns token spacing (see the assembler's doc).
        assembler.acceptVolatile(" about 150 words")
        // Stream ends here (user stop / endpoint): everything heard so far
        // is the utterance.
        #expect(assembler.transcript == "Tell me a short story, about 150 words")
    }

    // MARK: - 360-C: equivalence under the one-final-then-end shape

    @Test
    func singleRangeShapeMatchesCurrentBehavior() {
        var assembler = DictationTranscriptAssembler()
        assembler.acceptVolatile("What's")
        #expect(assembler.transcript == "What's")
        assembler.acceptVolatile("What's my step")
        #expect(assembler.transcript == "What's my step")
        assembler.acceptFinal("What's my step count?")
        #expect(assembler.transcript == "What's my step count?")
    }

    // MARK: - joins respect existing whitespace

    @Test
    func rangeJoinDoesNotDoubleWhitespace() {
        var assembler = DictationTranscriptAssembler()
        assembler.acceptFinal("Tell me a story ")
        assembler.acceptVolatile("about a lighthouse")
        #expect(assembler.transcript == "Tell me a story about a lighthouse")
    }

    @Test
    func emptyVolatileClearsTheTailOnly() {
        var assembler = DictationTranscriptAssembler()
        assembler.acceptFinal("Tell me a story")
        assembler.acceptVolatile("about")
        assembler.acceptVolatile("")
        #expect(assembler.transcript == "Tell me a story")
    }
}
