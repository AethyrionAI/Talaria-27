import Foundation
import Testing
@testable import Talaria

/// #422 bar 422-D — the memory block's size cap and the shape of the text it
/// injects.
///
/// Two things are being pinned here, and only one of them is arithmetic:
///
/// - **The cap follows the RUNTIME window, never a constant.** `contextSize`
///   is read live (8,192 on the phone, 32,768 on PCC, 0 on a simulator with
///   no model), so a hardcoded 800 would be wrong on three of those four.
/// - **Shortening is TRUNCATION, never paraphrase** (ruling 1). The composers
///   quote the user's own words with the date they were said and label them
///   as quoted-and-possibly-stale; nothing in this path may re-word a stored
///   turn. The property test proves the trimmed head is a literal PREFIX of
///   its source, and it runs the real
///   `LocalIntelligenceService.trimmed(_:toTokenBudget:)` — the one shortener
///   the ruling allows — rather than a test-local stand-in.
@Suite("422-D budget")
struct MemoryBudgetTests {

    // MARK: - Builders

    /// Deterministic-looking filler that cannot collide with any assertion
    /// substring below (every word is `w<number>`).
    static func words(_ count: Int) -> String {
        (0 ..< count).map { "w\($0)" }.joined(separator: " ")
    }

    // MARK: - The brief's three bars

    @Test func theCapFollowsTheRuntimeWindow() {
        #expect(MemoryBudget.memoryBlockTokens(contextSize: 8192) == 800)
        #expect(MemoryBudget.memoryBlockTokens(contextSize: 4096) == 400)
        #expect(MemoryBudget.memoryBlockTokens(contextSize: 32768) == 2048)
        #expect(MemoryBudget.memoryBlockTokens(contextSize: 1024) == 256)
    }

    @Test func hitsAreQuotedWithTheirDateNeverLabelledFact() {
        let prefix = MemoryBudget.composeHitsPrefix([
            (text: "My dentist is Dr. Patel.", sentAt: Date(timeIntervalSince1970: 0))
        ])
        #expect(prefix.contains("you said: \"My dentist is Dr. Patel.\""))
        #expect(prefix.contains("(quoted, may be out of date)"))
        #expect(!prefix.lowercased().contains("fact:"))
    }

    @Test func notesBlockCarriesTheDisagreementInstruction() {
        let block = MemoryBudget.composeNotesBlock([
            (text: "I'm allergic to shellfish", createdAt: Date())
        ])
        #expect(block.contains("Things the user asked you to remember"))
        #expect(block.contains("if two disagree, say which is newer and quote both"))
    }

    // MARK: - Truncation, never paraphrase (ruling 1)

    /// A trimmed hit is a literal PREFIX of its source with a visible cut
    /// marker. This is the executable form of "no paraphrase anywhere in the
    /// memory path": a paraphrase could not satisfy `hasPrefix`.
    @Test @MainActor func aTrimmedHitIsAPrefixOfItsSourceWithAVisibleCut() async {
        let intelligence = LocalIntelligenceService()
        let source = Self.words(400)
        let sentAt = Date(timeIntervalSince1970: 1_700_000_000)

        let trimmed = await MemoryBudget.trimmedHits(
            [(text: source, sentAt: sentAt)],
            maxTokens: MemoryBudget.maxHitTokens,
            using: intelligence
        )

        #expect(trimmed.count == 1)
        guard let head = trimmed.first?.text else {
            Issue.record("trimmedHits dropped the only hit")
            return
        }
        #expect(head.count < source.count, "a 400-word hit must actually be shortened at a 100-token cap")
        #expect(head.hasSuffix("…"), "the cut has to be visible to the reader")
        #expect(source.hasPrefix(String(head.dropLast())), "truncation, never paraphrase")
        #expect(trimmed.first?.sentAt == sentAt, "the date rides through untouched")
    }

    /// A hit already inside the cap is returned byte-identical — no marker, no
    /// re-wording, no formatter pass.
    @Test @MainActor func aShortHitIsReturnedUntouched() async {
        let intelligence = LocalIntelligenceService()
        let source = "My dentist is Dr. Patel."
        let trimmed = await MemoryBudget.trimmedHits(
            [(text: source, sentAt: Date(timeIntervalSince1970: 0))],
            maxTokens: MemoryBudget.maxHitTokens,
            using: intelligence
        )
        #expect(trimmed.first?.text == source)
        #expect(trimmed.first?.text.hasSuffix("…") == false)
    }

    // MARK: - The cap holds over random hit sets

    /// Property: for the retrieval shape this plan ships (top-k 3, each hit
    /// head-trimmed to `maxHitTokens`), the composed block never exceeds the
    /// runtime cap on the phone's 8,192-token window. Measured with the same
    /// estimator the trimmer uses — `measuredTokenCount(of:)` — because a
    /// second estimator would let the two disagree about what "800 tokens"
    /// means.
    @Test @MainActor func theComposedHitsBlockNeverExceedsTheRuntimeCap() async {
        let intelligence = LocalIntelligenceService()
        let cap = MemoryBudget.memoryBlockTokens(contextSize: 8192)

        for iteration in 0 ..< 50 {
            let hits = (0 ..< Int.random(in: 1 ... 3)).map { _ in
                (
                    text: Self.words(Int.random(in: 5 ... 400)),
                    sentAt: Date(timeIntervalSince1970: Double.random(in: 0 ... 1_800_000_000))
                )
            }
            let trimmed = await MemoryBudget.trimmedHits(
                hits,
                maxTokens: MemoryBudget.maxHitTokens,
                using: intelligence
            )
            let block = MemoryBudget.composeHitsPrefix(trimmed)
            let fits = await MemoryBudget.fits(block, in: cap, using: intelligence)
            #expect(fits, "iteration \(iteration): composed block overflowed the \(cap)-token cap")
        }
    }

    // MARK: - Notes cap (8 notes / 300 tokens)

    @Test func theNotesCapsAreTheOnesOwenChose() {
        #expect(MemoryBudget.maxNotes == 8)
        #expect(MemoryBudget.maxNotesTokens == 300)
    }

    /// The caller passes notes newest-first; the block keeps the first eight
    /// and the whole block is truncated — never re-worded — to 300 tokens.
    @Test @MainActor func theNotesBlockKeepsEightNotesInsideThreeHundredTokens() async {
        let intelligence = LocalIntelligenceService()
        let notes = (1 ... 20).map { index in
            (
                text: "Note number \(index): \(Self.words(40))",
                createdAt: Date(timeIntervalSince1970: Double(index) * 86_400)
            )
        }

        let block = MemoryBudget.composeNotesBlock(notes)
        #expect(block.contains("Note number 8:"))
        #expect(!block.contains("Note number 9:"), "the ninth note is over the cap")

        let capped = await MemoryBudget.composeNotesBlock(
            notes,
            toTokenBudget: MemoryBudget.maxNotesTokens,
            using: intelligence
        )
        let fits = await MemoryBudget.fits(capped, in: MemoryBudget.maxNotesTokens, using: intelligence)
        #expect(fits, "the notes block must fit its own 300-token cap")
        #expect(capped.hasSuffix("…"), "eight 40-word notes cannot fit 300 tokens uncut")
        #expect(block.hasPrefix(String(capped.dropLast())), "truncation, never paraphrase")
    }

    // MARK: - The honest-empty string

    @Test func theEmptyCaseSaysSoInTalariasOwnWords() {
        #expect(MemoryBudget.noMemoriesMatch == "No saved memories match this question.")
        #expect(MemoryBudget.composeHitsPrefix([]).isEmpty)
        #expect(MemoryBudget.composeNotesBlock([]).isEmpty)
        #expect(MemoryBudget.justSavedPrefix("call mum on Sunday")
            .contains("\"call mum on Sunday\""))
    }
}
