import Testing
import Foundation
@testable import Talaria

/// #422 (bar 422-R): the lexical tokenizer behind memory retrieval.
///
/// Owen authorized the stemmer on 2026-09-03 after 422-R measured exact-match tokens as a
/// limiting factor.
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
        #expect(LexicalTokenizer.stem("lives") == LexicalTokenizer.stem("live"))
        #expect(LexicalTokenizer.stem("mowed") == LexicalTokenizer.stem("mow"))
        #expect(LexicalTokenizer.stem("running") == LexicalTokenizer.stem("run"))
        #expect(LexicalTokenizer.stem("appointments") == LexicalTokenizer.stem("appointment"))
        #expect(LexicalTokenizer.stem("usually") == LexicalTokenizer.stem("usual"))
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
        #expect(LexicalTokenizer.stem("lives") == "live")
        #expect(LexicalTokenizer.stem("boxes") == "box")
        #expect(LexicalTokenizer.stem("address") == "address")
        #expect(LexicalTokenizer.stem("run") == "run")
        #expect(LexicalTokenizer.stem("allergies") == "allergy")
    }

    /// "don't" splits to "don" + "t". The "t" dies on the length filter but "don" is three
    /// characters and would pass, so every apostrophe in the store would donate a shared
    /// token to unrelated text. "won" and "can" are deliberately NOT fragments — they are
    /// ordinary words, and a question like "who won the world cup" must keep its verb.
    @Test func contractionFragmentsAreDroppedButRealWordsSurvive() {
        #expect(!LexicalTokenizer.contentTokens("I don't drink coffee after 2pm").contains("don"))
        #expect(LexicalTokenizer.contentTokens("I don't drink coffee after 2pm").contains("drink"))
        #expect(LexicalTokenizer.contentTokens("who won the world cup").contains("won"))
    }

    /// **422-S (2026-09-04): light verbs, modals and discourse words are not content.**
    ///
    /// *"can you tell me who my dentist is"* used to tokenize to `{can, tell, dentist}`,
    /// so a stored *"Can you tell me a joke about cats?"* scored 2/3 against it and the
    /// dentist row 1/3 — the joke was quoted and the dentist dropped. The question is
    /// ABOUT the dentist; the verbs that carry it are the same on every question the
    /// user will ever ask, which is the definition of a stop word.
    ///
    /// "won" survives on purpose (the test above) — it is not a function word.
    @Test func lightVerbsAndModalsAreNotContentTokens() {
        let natural = LexicalTokenizer.contentTokens("can you tell me who my dentist is")
        #expect(natural == ["dentist"], "got \(natural.sorted())")
        let aside = LexicalTokenizer.contentTokens("just so you know, I think I like tea")
        #expect(!aside.contains("know"), "got \(aside.sorted())")
        #expect(!aside.contains("think"), "got \(aside.sorted())")
        #expect(aside.contains("tea"), "the thing the sentence is ABOUT survives")
        // The verbs a memory is ABOUT are still content: a user who says they mow the
        // lawn on Fridays has said something about mowing.
        #expect(LexicalTokenizer.contentTokens("I mow the lawn on Fridays").contains("mow"))
    }

    /// The end-to-end consequence: a question and a stored turn that share only a
    /// morphological variant now overlap, where they scored a flat zero before.
    @Test func overlapSurvivesAMorphologicalVariant() {
        let overlap = LexicalTokenizer.lexicalOverlap(
            query: "how often does the lawn get mowed",
            chunk: "The lawn guy comes every other Friday to mow the front and back.")
        #expect(overlap > 0, "mowed/mow must overlap, got \(overlap)")
    }

    /// Re-homed from the embedder's own suite when that was deleted with it (2026-09-03).
    /// The pin survives because `lexicalOverlap` does: normalization is by
    /// the QUERY's content tokens, and a chunk sharing none of them scores a flat zero.
    @Test func lexicalOverlapCountsContentWordsOnly() {
        let o = LexicalTokenizer.lexicalOverlap(query: "who is my dentist", chunk: "My dentist is Dr. Patel on Lamar.")
        #expect(o == 1.0, "'dentist' is the only content token in the query")
        #expect(LexicalTokenizer.lexicalOverlap(query: "who is my dentist", chunk: "write a haiku about rain") == 0)
    }

    /// The stemmer must be IDEMPOTENT — `stem(stem(w)) == stem(w)` — or a plural and its
    /// singular land one derivation apart. One pass tries `-ing`/`-ed`/`-ly`/`-er` before
    /// `-s`, so "mornings" stops at "morning" while "morning" itself goes on to "morn";
    /// eleven such pairs occur in the 422-R corpus alone. Iterating to a fixpoint is the
    /// fix, and it moved none of the corpus numbers.
    ///
    /// RED by stemming a single pass instead of to a fixpoint.
    @Test func stemmingIsIdempotentSoPluralsMeetTheirSingulars() {
        for (plural, singular) in [("mornings", "morning"), ("families", "family"),
                                   ("trackers", "tracker"), ("meetings", "meeting")] {
            #expect(LexicalTokenizer.stem(plural) == LexicalTokenizer.stem(singular),
                    "\(plural)/\(singular) → \(LexicalTokenizer.stem(plural))/\(LexicalTokenizer.stem(singular))")
        }
        for word in ["mornings", "families", "running", "appointments", "usually", "address"] {
            let once = LexicalTokenizer.stem(word)
            #expect(LexicalTokenizer.stem(once) == once, "stem(\(word)) = \(once) must be a fixpoint")
        }
    }
}
