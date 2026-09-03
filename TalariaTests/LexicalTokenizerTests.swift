import Testing
import Foundation
@testable import Talaria

/// #422 (bar 422-R): the lexical tokenizer behind memory retrieval.
///
/// Owen authorized the stemmer on 2026-09-03 after 422-R measured exact-match tokens as a
/// limiting factor. It lives on `EmbeddingService` only because `contentTokens` still does;
/// Task 8b re-homes both when the embedder is deleted, so these tests move with it.
///
/// The stemmer is NOT a linguist's stemmer and these tests must not be read as claiming it
/// is. "water" becomes "wat" and "brother" becomes "broth". That is harmless because both
/// sides of every comparison pass through it — overlap needs the two stems to AGREE, not to
/// be words. What is asserted below is exactly that agreement.
@Suite("422-R lexical tokenizer")
struct LexicalTokenizerTests {

    /// The pairs the corpus actually missed before the stemmer existed. Each is a
    /// morphological variant that a user's question and their own stored turn would spell
    /// differently — and an exact-match tokenizer scored 0 on every one.
    @Test func morphologicalVariantsCollapseToTheSameToken() {
        #expect(EmbeddingService.stem("lives") == EmbeddingService.stem("live"))
        #expect(EmbeddingService.stem("mowed") == EmbeddingService.stem("mow"))
        #expect(EmbeddingService.stem("running") == EmbeddingService.stem("run"))
        #expect(EmbeddingService.stem("appointments") == EmbeddingService.stem("appointment"))
        #expect(EmbeddingService.stem("usually") == EmbeddingService.stem("usual"))
    }

    /// The guards that keep the stemmer from disagreeing with ITSELF, which is the only way
    /// a consistent-but-lossy stemmer can do damage.
    ///
    /// - `es` falls through to `s` on a non-sibilant stem, so "lives" reaches "live" and not
    ///   "liv" — "live" is four characters and below the stemming floor, so a rule that
    ///   moved the plural but not the singular would manufacture the very mismatch this
    ///   stemmer exists to remove.
    /// - `ss` is not a plural.
    /// - Under the five-character floor a short word is returned untouched.
    @Test func theStemmerSelfConsistencyGuardsHold() {
        #expect(EmbeddingService.stem("lives") == "live")
        #expect(EmbeddingService.stem("boxes") == "box")
        #expect(EmbeddingService.stem("address") == "address")
        #expect(EmbeddingService.stem("run") == "run")
        #expect(EmbeddingService.stem("allergies") == "allergy")
    }

    /// "don't" splits to "don" + "t". The "t" dies on the length filter but "don" is three
    /// characters and would pass, so every apostrophe in the store would donate a shared
    /// token to unrelated text. "won" and "can" are deliberately NOT fragments — the plain
    /// no-answer query "who won the world cup in 2018" must keep its verb.
    @Test func contractionFragmentsAreDroppedButRealWordsSurvive() {
        #expect(!EmbeddingService.contentTokens("I don't drink coffee after 2pm").contains("don"))
        #expect(EmbeddingService.contentTokens("I don't drink coffee after 2pm").contains("drink"))
        #expect(EmbeddingService.contentTokens("who won the world cup").contains("won"))
    }

    /// The end-to-end consequence: a question and a stored turn that share only a
    /// morphological variant now overlap, where they scored a flat zero before.
    @Test func overlapSurvivesAMorphologicalVariant() {
        let overlap = EmbeddingService.lexicalOverlap(
            query: "how often does the lawn get mowed",
            chunk: "The lawn guy comes every other Friday to mow the front and back.")
        #expect(overlap > 0, "mowed/mow must overlap, got \(overlap)")
    }
}
