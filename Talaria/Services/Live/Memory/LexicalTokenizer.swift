import Foundation

/// #422 (bar 422-R): the lexical scorer behind local memory retrieval.
///
/// Tokenizing, stemming and overlap — the whole scorer. Pure and deterministic: no model,
/// no asset, no acquisition window, nothing that can be unavailable at launch, which is why
/// the store needs no repair pass and a row is ready the moment it is written.
///
/// It was `EmbeddingService` until 2026-09-03; `MemoryRetriever` carries the ruling that
/// removed the rest of it.
enum LexicalTokenizer {

    /// The 53 words 422-R's corpus was first scored with (2026-09-02): articles,
    /// pronouns, auxiliaries, question words and prepositions.
    private static let coreStopWords: Set<String> = ["the","a","an","and","or","of","to","in","on","at","is","are","was","were","my","your",
        "i","me","you","it","its","this","that","do","does","did","what","when","where","who","which","how","for","with","about",
        "have","has","had","be","been","we","our","us","they","them","he","she","his","her","not","no","yes","please"]

    /// **422-S (2026-09-04): the light verbs, modals and discourse words a question is
    /// carried BY, never about.** Measured before this set existed: *"can you tell me who
    /// my dentist is"* tokenized to `{can, tell, dentist}`, overlap is normalised by the
    /// query's token count, and ties fall newest-first — so any newer turn that said
    /// "can" or "tell" outranked the dentist row, and under relative admission the dentist
    /// row was not admitted at all. Only 13 of the 107 corpus queries carry such a word,
    /// which is how 422-R scored 60/75 as written and 50/75 under a "can you tell me"
    /// frame. With this set the corpus scores 62/75 · 72/75 under every frame tried.
    ///
    /// Function words only. A verb a memory can be ABOUT — mow, run, drink, cook —
    /// stays content; "won" stays content (a real result, see `contractionFragments`).
    /// `remember`/`forget` are here because every *"Remember that …"* turn in the store
    /// shares them, and a question is never about remembering itself.
    private static let functionWords: Set<String> = [
        "can", "could", "would", "should", "will", "shall", "may", "might", "must",
        "tell", "told", "know", "knew", "think", "thought", "like", "want", "wanted",
        "need", "needed", "get", "got", "give", "gave", "let", "lets", "say", "said",
        "ask", "asked", "remind", "reminded", "show", "help", "find", "make", "made",
        "look", "see", "saw", "use", "used", "mean", "meant",
        "just", "really", "very", "much", "more", "most", "some", "any", "all", "also",
        "but", "then", "than", "from", "out", "into", "over", "there", "here", "now",
        "again", "still", "ever", "one", "thing", "things", "something", "anything",
        "everything", "nothing", "way", "sure", "okay", "yeah", "thanks", "thank",
        "hello", "hey", "remember", "remembered", "forget", "forgot",
    ]

    static let stopWords: Set<String> = coreStopWords.union(functionWords)

    /// What the split leaves behind when a contraction meets a non-alphanumeric separator:
    /// "don't" becomes "don" + "t". The "t" dies on the length filter, but "don" is three
    /// characters and passes — so a turn about coffee and a query about anything else share
    /// a token for free, and every apostrophe in the store is a small dose of noise.
    /// Deliberately omits "can" and "won", which are also real words: the corpus's plain
    /// no-answer query "who won the world cup in 2018" must keep its verb.
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
    /// **Iterated to a FIXPOINT, which is the whole reason `stem` and `stemOnce` are
    /// separate.** One pass tries `-ing`/`-ed`/`-ly`/`-er` before `-s`, so a plural stops
    /// one derivation short of its own singular: "mornings" → "morning" while "morning" →
    /// "morn", "families" → "family" while "family" → "fami". Eleven such pairs occur in
    /// the 422-R corpus and roughly 12% of dictionary plural/singular pairs are affected.
    /// Re-applying until nothing changes makes both sides land together. It terminates
    /// because every rule strictly shortens the word and none fires below five characters.
    ///
    /// It is not a linguist's stemmer and does not try to be: "water" becomes "wat" and
    /// "brother" becomes "broth". That is harmless because BOTH sides of every comparison
    /// pass through it — overlap needs the two stems to AGREE, not to be words. The
    /// guards that do matter are the ones that keep it from disagreeing with itself:
    /// a 5-character floor before stemming at all, a 3-character floor on what is left,
    /// and un-doubling after `ing`/`ed` so "running" and "run" meet.
    static func stem(_ word: String) -> String {
        var current = word
        while true {
            let next = stemOnce(current)
            // Every rule strictly SHORTENS (`ies`→`y` is net −2, the rest drop 2–3 and
            // may undouble one more), so a result that is not shorter is the fixpoint.
            // Looping on that invariant rather than a fixed iteration count makes
            // returning a non-fixpoint structurally impossible, and termination follows
            // from the length strictly decreasing.
            guard next.count < current.count else { return current }
            current = next
        }
    }

    private static func stemOnce(_ word: String) -> String {
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

    /// Normalized by the QUERY's token count on purpose: the question asks how much of
    /// what the user just asked for this chunk contains, and normalizing by the chunk
    /// would punish a long turn for the words it also happens to hold.
    static func lexicalOverlap(query: String, chunk: String) -> Float {
        let q = contentTokens(query); guard !q.isEmpty else { return 0 }
        let c = contentTokens(chunk)
        return Float(q.intersection(c).count) / Float(q.count)
    }
}
