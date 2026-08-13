import Foundation

/// #338 — THE HONESTY GUARD's pure detector.
///
/// **The defect this exists for.** On 2026-08-12 the shipping app answered
/// *"Remind me to take out the trash at 8"* with the literal text
/// *"**Confirmation card:** A reminder to "take out the trash" at 8 AM has been
/// created."* — no confirmation card, no tool call, no reminder (#337 bar
/// 337-A; the same shape as #336's three fabricated battery rows). The app told
/// the user something happened that did not happen.
///
/// **What this type is.** A pure function over two facts the app already has:
/// the turn's final text, and the names of the tool calls that actually
/// executed this turn. No I/O, no actor, no model. It answers one question —
/// *does this text assert a COMPLETED device action that did not occur?* — and
/// says what it matched, so the firing can be counted (#338-E).
///
/// **What it deliberately does NOT do.** It does not make the model call the
/// tool, it does not rewrite the model's text, and it does not throw (#197: the
/// tool path never gains a throw). The response — appending a visibly distinct
/// correction — lives at the call site in `LocalChatBackend`.
///
/// **Design bias, stated once.** Bar 338-A weights the two error directions
/// unequally: *"a guard that fires on an honest offer trains the user to ignore
/// it."* So every ambiguity here resolves toward SILENCE. The fixtures in
/// `ActionClaimDetectorTests` are lifted verbatim from the real 2026-08-12
/// artifacts (`planning/reports/2026-08-12-333-runner-witnesses/`), not
/// invented, and the honest-offer rows outnumber the fabrications 24 to 4.
enum ActionClaimDetector {

    // MARK: - What a claim is

    /// The shape of completed-action assertion that matched.
    ///
    /// The distinction that matters is `isLicensedByAnyToolCall`: a READ tool
    /// can legitimately produce *"Lunch with Sam is now on your calendar"* (the
    /// model read the calendar and reported it), but nothing a read tool
    /// returns licenses *"I've set a reminder"* or the app's own
    /// `Confirmation card:` affordance appearing in prose.
    enum ClaimKind: String, Sendable, CaseIterable {
        /// *"I've set a reminder…"*, *"I created the event…"* — the model
        /// claiming authorship of a write. #336's three fabricated rows and
        /// four of the honest called-and-said-so rows are this shape.
        case firstPersonCreation
        /// *"…has been created"* — the passive perfect. The second half of the
        /// #337-A production reply.
        case passiveCompletion
        /// *"Your alarm is set for 6:30"* — present-state completion.
        case presentStateSet
        /// *"Lunch with Sam is now on your calendar"* — present-state location.
        case presentStateOn
        /// The literal `Confirmation card:` — the model imitating the app's own
        /// affordance in prose (#337-A's new dimension: a user cannot tell it
        /// from the real card except by the absence of buttons). In scope by
        /// the #338 entry's own words.
        case impersonatedCard

        /// True when ANY executed tool call — read tools included — makes the
        /// phrasing defensible, so the guard must stay quiet.
        ///
        /// A turn that called `getCalendarEvents` and answered *"Lunch with Sam
        /// is now on your calendar"* is honest reporting, not fabrication.
        /// A turn that called `getCalendarEvents` and answered *"I've created
        /// the event"* is still a lie — reading does not license authorship.
        var isLicensedByAnyToolCall: Bool {
            switch self {
            case .firstPersonCreation, .impersonatedCard: false
            case .passiveCompletion, .presentStateSet, .presentStateOn: true
            }
        }
    }

    /// One matched claim: the shape, and the normalized sentence it came from
    /// (so a firing can be read in a log without re-deriving it).
    struct Claim: Sendable, Equatable {
        let kind: ClaimKind
        let sentence: String
    }

    /// The action tools whose execution licenses a completion claim — pinned to
    /// `DeviceToolBelt.actionToolNames` by test, so the guard can never drift
    /// from the real belt.
    static let actionToolNames: Set<String> = DeviceToolBelt.actionToolNames

    // MARK: - The public surface

    /// Every completed-action claim the text makes, in reading order.
    ///
    /// Pure text scan — it knows nothing about tool calls, which is what makes
    /// the honest called-and-said-so rows testable as CLAIMS in their own
    /// right (they are, and they are correct, because a call executed).
    static func claims(in text: String) -> [Claim] {
        let normalized = normalize(text)
        guard !normalized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        var found: [Claim] = []
        for sentence in sentences(of: normalized) {
            found.append(contentsOf: claims(inSentence: sentence))
        }
        return found
    }

    /// **The guard's question.** Did this turn's text assert a completed device
    /// action that did not occur?
    ///
    /// - Parameters:
    ///   - text: the turn's final model text (NOT the app's appended blocks —
    ///     the guard must never read its own output back in).
    ///   - executedToolNames: names of every tool call ADMITTED this turn, in
    ///     the order the relay emitted them. Refused calls are absent by
    ///     construction (`ToolEventRelay.started` returns before emitting).
    ///   - priorActionToolExecutedInConversation: whether ANY action tool has
    ///     executed at some point in THIS conversation — see the parameter's
    ///     own note below. Defaults to `false`, which is the strict reading:
    ///     a caller that does not know stays as loud as it was.
    /// - Returns: the first unfulfilled claim, or `nil` when the text is
    ///   honest — or when a tool call licenses it (bar 338-D).
    ///
    /// **THE EARLIER-TURN CORRECTION (review finding, 2026-08-12).** As first
    /// shipped this read only THIS turn's calls, so the commonest honest
    /// exchange in the app fired: the user taps Confirm, the reminder is really
    /// written, and on the NEXT turn they ask *"did that go through?"* — a turn
    /// with zero tool calls by construction. The app answered *"Yes, the
    /// reminder is set for 8 PM"* and then appended *"Nothing was created."*
    /// **A guard whose correction is itself false is worse than no guard.**
    ///
    /// The license is deliberately NARROW: it extends only to the three kinds
    /// `isLicensedByAnyToolCall` already treats as licensable — the passive and
    /// present-state tiers, which are exactly the shapes an honest follow-up
    /// uses. `firstPersonCreation` and `impersonatedCard` are NOT licensed by
    /// conversation history, because 6 of 6 true positives in the real corpus
    /// are `firstPersonCreation`: licensing it for the rest of a conversation
    /// in which one action ever succeeded would blind the guard to the exact
    /// shape it exists to catch.
    ///
    /// **THE TRADE HAS TWO HALVES AND BOTH ARE RECORDED. The false-NEGATIVE
    /// half is the larger and permanent one.** Because the latch is set by ANY
    /// action tool and licenses ALL THREE licensable kinds, **one successful
    /// reminder retires the passive and both present-state tiers for the rest
    /// of that conversation — including for a different artifact the model
    /// subsequently fabricates.** Verified quiet at
    /// `priorActionToolExecutedInConversation == true`: *"Lunch with Sam is now
    /// on your calendar for Friday."* · *"The reminder has been created for
    /// 8 PM."* · *"Your alarm is set for 6:30 AM."* · and #337-A's passive half
    /// on its own. The false-POSITIVE half is the smaller residual: a
    /// past-tense authorship claim about an earlier turn's real write still
    /// fires. Both are labelled rows in `ActionClaimDetectorTests`
    /// (`reviewFindings`), not hidden.
    static func unfulfilledClaim(
        in text: String,
        executedToolNames: [String],
        priorActionToolExecutedInConversation: Bool = false
    ) -> Claim? {
        // 338-D, the production-safety floor: a turn that executed an ACTION
        // tool staged a real confirmation card. Whatever it said afterwards,
        // this guard has nothing to add and must not fire.
        let executedAnAction = executedToolNames.contains { actionToolNames.contains($0) }
        if executedAnAction { return nil }
        // A call THIS turn, or an action tool anywhere in this conversation,
        // both license the same three kinds — the difference between them is
        // only which turn made the phrasing defensible.
        let licensesPresentState = !executedToolNames.isEmpty || priorActionToolExecutedInConversation
        return claims(in: text).first { claim in
            !(claim.kind.isLicensedByAnyToolCall && licensesPresentState)
        }
    }

    // MARK: - Normalization (bar 338-B)

    /// Curly apostrophes the model actually writes, folded to `'`.
    ///
    /// **This is bar 338-B and it is not decoration.** On the night #338 was
    /// filed, a straight-quote search read *"I've set…"* as "no claim" and
    /// produced a wrong reading inside the investigation itself. Of the three
    /// #336 fabricated rows, TWO carry `U+2019` and one carries `U+0027` — the
    /// model mixes them within a single battery cell, so a detector that
    /// handles only one form misses two thirds of the evidence.
    private static let apostropheVariants: [Character] = ["\u{2019}", "\u{2018}", "\u{00B4}", "\u{02BC}", "\u{2032}"]
    /// Curly double quotes — the #337-A production reply quotes the reminder
    /// title, and the artifacts carry both forms.
    private static let quoteVariants: [Character] = ["\u{201C}", "\u{201D}", "\u{201E}", "\u{2033}"]
    /// Non-breaking and thin spaces. `U+202F` appears in a real artifact row
    /// (*"6:30\u{202F}AM"*) — a plain `" "` split would fuse the tokens.
    private static let spaceVariants: [Character] = ["\u{00A0}", "\u{202F}", "\u{2009}", "\u{2007}", "\u{2005}"]
    /// Dashes the model uses as clause separators.
    private static let dashVariants: [Character] = ["\u{2014}", "\u{2013}"]
    /// Markdown emphasis, stripped so `**created**` reads as `created` and
    /// `**Confirmation card:**` reads as `confirmation card:`.
    private static let markdownMarks: Set<Character> = ["*", "_", "`", "#"]

    /// Lowercased, de-curled, de-markdowned text. Pure and exposed for test.
    static func normalize(_ text: String) -> String {
        var out = String()
        out.reserveCapacity(text.count)
        for character in text {
            if markdownMarks.contains(character) { continue }
            if apostropheVariants.contains(character) { out.append("'"); continue }
            if quoteVariants.contains(character) { out.append("\""); continue }
            if spaceVariants.contains(character) { out.append(" "); continue }
            if dashVariants.contains(character) { out.append(" "); continue }
            out.append(character)
        }
        return out.lowercased()
    }

    // MARK: - Sentence splitting

    /// Splits normalized text into sentence-ish spans.
    ///
    /// Scoping matters: *"I've set a reminder. Anything else?"* must not be
    /// silenced by the trailing question mark, and
    /// *"Here's the confirmation: … Would you like me to create this
    /// reminder?"* must not fire because an earlier line mentioned a reminder.
    ///
    /// A period is NOT a break when the character before it is a lone letter —
    /// that keeps `a.m.` / `p.m.` / initials intact, which matters because
    /// splitting *"at 8 a.m. has been created"* would strand the verb phrase
    /// away from its noun and turn a real claim into a miss.
    static func sentences(of normalized: String) -> [String] {
        var out: [String] = []
        var current = String()
        let characters = Array(normalized)
        for (index, character) in characters.enumerated() {
            current.append(character)
            let isBreak: Bool
            switch character {
            case "!", "?", ";", "\n":
                isBreak = true
            case ".":
                // "a.m." / "p.m." / "J. Smith" — a period after a lone letter
                // is an abbreviation, not a sentence end.
                let previous = index >= 1 ? characters[index - 1] : " "
                let beforePrevious = index >= 2 ? characters[index - 2] : " "
                isBreak = !(previous.isLetter && !beforePrevious.isLetter)
            default:
                isBreak = false
            }
            if isBreak {
                let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { out.append(trimmed) }
                current = ""
            }
        }
        let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { out.append(trimmed) }
        return out
    }

    // MARK: - Token matching

    /// Drops every `"…"` span, so the model quoting the USER — or quoting a
    /// reminder's own title — cannot arm a claim (#338's entry: *"It must NOT
    /// fire … on the model quoting the user"*).
    ///
    /// Runs on NORMALIZED text, where the curly forms are already folded to
    /// `"`. The apostrophe is untouched, so `i've` survives.
    ///
    /// **An unterminated opener strips to the end of the sentence**, and that
    /// is not an edge case: `sentences(of:)` breaks on the period INSIDE a
    /// quotation — *"You wrote: "I've set a reminder already." Do you want
    /// another one?"* splits with the closing quote on the far side of the
    /// break, leaving the first sentence holding a dangling opener. Balanced
    /// pairs alone would read that half as the model's own claim.
    ///
    /// Each quote becomes a SPACE rather than nothing, so the spans on either
    /// side cannot fuse into a token that never existed.
    static func strippingQuotedSpans(from sentence: String) -> String {
        guard sentence.contains("\"") else { return sentence }
        var out = String()
        out.reserveCapacity(sentence.count)
        var insideQuotes = false
        for character in sentence {
            if character == "\"" {
                insideQuotes.toggle()
                out.append(" ")
                continue
            }
            if !insideQuotes { out.append(character) }
        }
        return out
    }

    /// Words of a sentence, apostrophes kept inside the word so `i've` stays
    /// one token and can never be confused with `i`.
    static func tokens(of sentence: String) -> [String] {
        sentence
            .split(whereSeparator: { !($0.isLetter || $0.isNumber || $0 == "'") })
            .map(String.init)
    }

    /// An ordered token pattern: each step names its accepted words, and
    /// `maxGap` is how many tokens may sit between consecutive steps.
    ///
    /// Regex-free on purpose — `Regex` is not `Sendable`, and this shape is
    /// both cheaper to read and impossible to get accidentally greedy.
    private struct TokenPattern {
        let steps: [Set<String>]
        let maxGap: Int
        /// When non-empty, the token immediately AFTER the last step must be
        /// one of these — the discriminator that keeps *"I set the alarm"*
        /// (a claim) apart from *"I set out to…"*.
        var requiredFollower: Set<String> = []

        func matches(_ tokens: [String]) -> Bool {
            guard let first = steps.first else { return false }
            for start in tokens.indices where first.contains(tokens[start]) {
                var cursor = start
                var matched = true
                for step in steps.dropFirst() {
                    var next = cursor + 1
                    var advanced = false
                    while next <= min(cursor + 1 + maxGap, tokens.count - 1) {
                        if step.contains(tokens[next]) { advanced = true; break }
                        next += 1
                    }
                    if !advanced { matched = false; break }
                    cursor = next
                }
                guard matched else { continue }
                if requiredFollower.isEmpty { return true }
                let follower = cursor + 1
                if follower < tokens.count, requiredFollower.contains(tokens[follower]) { return true }
            }
            return false
        }
    }

    // MARK: - The pattern tables

    /// The device artifacts a claim has to be ABOUT. Without this, present-state
    /// phrasing fires on ordinary conversation.
    private static let artifactNouns: Set<String> = [
        "reminder", "reminders", "alarm", "alarms", "calendar", "calendars",
        "event", "events", "timer", "timers", "meeting", "meetings",
        "appointment", "appointments",
    ]

    private static let creationVerbsPerfect: Set<String> =
        ["set", "created", "added", "scheduled", "made", "put", "placed"]
    private static let creationVerbsPast: Set<String> =
        ["set", "created", "added", "scheduled", "made"]
    private static let determiners: Set<String> =
        ["a", "an", "the", "your", "that", "this", "it", "two", "three"]

    private static let firstPersonPatterns: [TokenPattern] = [
        // "I've set…", "I've already created…", "I've just added…"
        .init(steps: [["i've"], creationVerbsPerfect], maxGap: 1),
        // "I have set…", "I have already scheduled…"
        .init(steps: [["i"], ["have"], creationVerbsPerfect], maxGap: 1),
        // "I set the alarm", "I created your event" — gap 0 and a determiner
        // after, so "I can set" and "I will create" cannot reach it.
        .init(steps: [["i"], creationVerbsPast], maxGap: 0, requiredFollower: determiners),
    ]

    private static let passivePatterns: [TokenPattern] = [
        // "…has been created", "…have been scheduled"
        .init(steps: [["has", "have"], ["been"], creationVerbsPerfect], maxGap: 0),
    ]

    private static let presentStateSetPatterns: [TokenPattern] = [
        // "is set for", "is now scheduled for", "are set for"
        .init(steps: [["is", "are", "was", "were"], ["set", "scheduled"], ["for"]], maxGap: 1),
    ]

    private static let presentStateOnPatterns: [TokenPattern] = [
        // "is now on your calendar", "is in your reminders"
        .init(steps: [["is", "are"], ["on", "in"], ["your"], artifactNouns], maxGap: 1),
        // "added to your calendar"
        .init(steps: [["added"], ["to"], ["your"], artifactNouns], maxGap: 0),
    ]

    /// Sentence-level silencers. Any one of them and the sentence cannot be a
    /// completed-action assertion at all.
    private static let negationTokens: Set<String> = [
        "not", "no", "never", "cannot", "can't", "cant", "won't", "wont",
        "don't", "dont", "doesn't", "doesnt", "didn't", "didnt",
        "haven't", "havent", "hasn't", "hasnt", "isn't", "isnt",
        "wasn't", "wasnt", "couldn't", "couldnt", "wouldn't", "wouldnt",
        "unable", "failed", "without", "unfortunately",
    ]

    /// The model restating the USER's request rather than asserting its own
    /// act. Real row: *"Your request to set an alarm for 6:30 has been
    /// received."* — an honest acknowledgement that must stay quiet.
    private static let attributionPatterns: [TokenPattern] = [
        .init(steps: [["you"], ["asked", "said", "requested", "wanted"]], maxGap: 0),
        .init(steps: [["your", "the"], ["request", "ask"]], maxGap: 0),
    ]

    /// Future / offer markers. Applied ONLY to the present-state tiers: the
    /// perfect tenses are unambiguous, but *"I'll set an alarm — it is set for
    /// 6:30 once you confirm"* is an offer, not a claim.
    private static let offerPatterns: [TokenPattern] = [
        .init(steps: [["i'll", "i'd"]], maxGap: 0),
        .init(steps: [["i"], ["will", "would", "can", "could", "should"]], maxGap: 0),
        .init(steps: [["would", "do", "did"], ["you"]], maxGap: 1),
        .init(steps: [["shall", "should"], ["i"]], maxGap: 0),
        .init(steps: [["want", "like"], ["me"], ["to"]], maxGap: 0),
        .init(steps: [["going", "about"], ["to"]], maxGap: 0),
        // Review finding: `if` and `until` were missing from this row, so
        // *"…the alarm is set for 6:30 if you confirm"* read as a claim. The
        // adjacent `you` is what keeps these narrow — an unanchored `after`
        // would silence *"I've set a reminder for after you get home"*, which
        // is a real fabrication shape.
        .init(steps: [["once", "after", "when", "if", "until", "unless"], ["you"]], maxGap: 1),
    ]

    /// **The EXPLANATORY FRAME (review finding, 2026-08-12).** A sentence whose
    /// FIRST word is a subordinating conjunction of condition or time is
    /// describing how the feature works, or what will happen if the user acts —
    /// it is not an assertion that anything happened this turn.
    ///
    /// **Why this matters more than it looks.** Capability questions route
    /// TOOLLESS (#215), so `executedToolNames` is empty on them BY
    /// CONSTRUCTION, and the app's own instructions teach the model this exact
    /// vocabulary — *"The user sees a confirmation card…"* appears in every
    /// action tool's description and again in the assembled instructions
    /// (`cardNarrationClause`, `cardCorrectionClause`, and the armed-tool
    /// enumeration — `LocalChatBackend.swift:2149`/`:2204`/`:2209` at this
    /// commit; the SYMBOL NAMES are the durable citation, since these line
    /// numbers have already drifted twice under edits above them). A model paraphrasing its own instructions into *"Once a
    /// reminder has been created it appears in the Reminders app"* is the
    /// LIKELY case, not an exotic one, and the shipped detector fired on it.
    ///
    /// **The rule is POSITIONAL on purpose.** Only the sentence-initial slot
    /// counts, because that is the slot that scopes the whole sentence as a
    /// conditional or general rule. An unanchored keyword search would silence
    /// *"I've set the alarm, and I can move it if you like"* — a real claim
    /// with a conditional tail.
    ///
    /// **Three words are deliberately ABSENT, and the reasoning is the same
    /// each time: they open sentences whose MAIN clause is commonly a genuine
    /// claim.** `as` — *"As requested, I've set a reminder"*. `while` —
    /// *"While you were out, I set the alarm"*. `before` — *"Before I forget,
    /// I've set a reminder for 8"*. Every one of those is a fabrication this
    /// guard exists to catch, and every one would go dark. The words that ARE
    /// here scope the whole sentence rather than a preamble to it.
    private static let explanatoryOpeners: Set<String> = [
        "if", "once", "when", "whenever", "after", "until", "unless",
    ]

    /// The impersonated affordance, matched on the raw normalized sentence
    /// because the COLON is the tell — `Here's the confirmation:` is an honest
    /// offer preamble that appears 20+ times in the artifacts, while
    /// `Confirmation card:` is the app's own UI name being worn as prose.
    ///
    /// **It must OPEN the sentence (review finding, 2026-08-12).** #337-A's
    /// production reply led with it — `**Confirmation card:** A reminder to…` —
    /// and that LABEL POSITION is the impersonation: it is where the app's own
    /// card would sit. Mid-sentence the same words are the app's vocabulary
    /// being explained, and the shipped detector fired on the honest sentence
    /// *"Every action is staged as a confirmation card: nothing is written
    /// until you tap Confirm."*
    private static let impersonatedCardMarker = "confirmation card:"

    /// The sentence from its first LETTER, which is what "label position"
    /// actually means.
    ///
    /// **This exists because the first version of the position test was a bare
    /// `hasPrefix` and a single markdown bullet defeated it (round-2 review).**
    /// `normalize` strips `*`, `_`, `` ` `` and `#`, so `**Confirmation card:**`
    /// folded correctly — but `-`, `>`, emoji and leading spaces all survive,
    /// and `- **Confirmation card:** A reminder … has been created.` fell
    /// through to `passiveCompletion`. Which the conversation latch LICENSES.
    /// So on the second turn of a conversation where one reminder had really
    /// been created, **the production defect's exact shape went completely
    /// silent** — one bullet and one earlier success away from invisible.
    ///
    /// Dropping to the first letter cannot over-reach: it stops at the first
    /// letter, so a mid-sentence mention is still mid-sentence.
    ///
    /// **Two things this does NOT do, both found by later review and both
    /// recorded rather than papered over.** It must be applied to the
    /// QUOTE-STRIPPED sentence — a leading `"` is a non-letter, so on the raw
    /// sentence a quoted illustration read as label position (round 3; see the
    /// call site). And **single-letter list markers still defeat it**: `i. `,
    /// `a. `, `A. `, `a) ` leave the first letter AS the marker, and
    /// `sentences(of:)`'s abbreviation rule (which exists to keep `a.m.` and
    /// `J. Smith` intact) refuses to split them off. `ii.`, `iv.` and `1.` are
    /// fine. That is N1's own residue, a MISS rather than a lie, reachable
    /// only at `priorActionToolExecutedInConversation == true` — pinned as a
    /// KNOWN-LIMIT row in `ActionClaimDetectorTests`.
    static func labelPositionBody(of sentence: String) -> Substring {
        sentence.drop { !$0.isLetter }
    }

    // MARK: - Per-sentence scoring

    private static func claims(inSentence sentence: String) -> [Claim] {
        // A question is never an assertion of completion. This one line is
        // what keeps the 15 honest offers from A7AB9960 silent.
        if sentence.hasSuffix("?") { return [] }

        // **THE THREE SENTENCE-LEVEL SILENCERS BELOW READ THE WHOLE SENTENCE;
        // EVERYTHING AFTER THEM READS IT WITH QUOTED SPANS REMOVED.**
        // Round-2 review: the strip used to run first, above all three, so a
        // `not` / a `you asked` / an `Once…` sitting INSIDE a quotation was
        // deleted before it could be consulted, and three honest sentences
        // fired — *"Your note says "I have not set the alarm" and the alarm is
        // set for 6:30."* among them. A silencer is a reason to stay quiet;
        // deleting reasons to stay quiet can only ever add false positives,
        // which is the error direction that makes the app's own correction the
        // false statement.
        //
        // **`offerPatterns` is deliberately NOT one of these three** (round-3
        // review noted the doc once read as though it were). It is a
        // TIER-SCOPED suppressor and reads the stripped tokens, because an
        // offer marker inside a quotation is the model quoting an offer, not
        // making one: *"The card says "would you like me to set it" and the
        // alarm is set for 6:30"* asserts the alarm outside the quotation.
        //
        // The COST of reading these three unstripped, stated because it is
        // real: a negation — or an opener — quoted from the user can silence a
        // claim the model makes outside the quotation. Both are labelled
        // KNOWN-LIMIT rows in `ActionClaimDetectorTests`. That direction is a
        // miss; the other was a lie.
        let rawTokens = tokens(of: sentence)
        if rawTokens.contains(where: negationTokens.contains) { return [] }
        if attributionPatterns.contains(where: { $0.matches(rawTokens) }) { return [] }
        // Review finding: a sentence-initial `if` / `once` / `after` / … frames
        // the whole sentence as a condition or a general rule. Checked here,
        // ahead of EVERY tier including the perfect tenses, because the shape
        // it catches — *"Once a reminder has been created…"* — is a passive.
        if let opener = rawTokens.first, explanatoryOpeners.contains(opener) { return [] }

        // From here on the quoted spans are gone, so the model quoting the
        // user — or quoting a reminder's own title — cannot arm a claim.
        let scannable = strippingQuotedSpans(from: sentence)

        var found: [Claim] = []
        // Round-3 review: label position is judged on the STRIPPED sentence.
        // `labelPositionBody` drops every non-letter, INCLUDING a leading
        // quotation mark, so judging it unstripped read a quoted illustration —
        // *"Confirmation card: A reminder has been created" is what the card
        // would show.* — as the app's own affordance being worn as prose. Worst
        // possible direction: `impersonatedCard` is licensed by neither a tool
        // call nor the conversation latch, so it fired at BOTH latch states
        // with no way to license it away, on capability prose that routes
        // toolless by construction. It was also the last claim tier still
        // reading the unstripped sentence — the exact asymmetry the round-2
        // silencer-scope fix removed. #337-A survives because only its TITLE is
        // quoted, never its marker.
        if labelPositionBody(of: scannable).hasPrefix(impersonatedCardMarker) {
            found.append(Claim(kind: .impersonatedCard, sentence: sentence))
        }
        let tokens = tokens(of: scannable)
        // Everything below has to be ABOUT a device artifact.
        guard tokens.contains(where: artifactNouns.contains) else { return found }

        if firstPersonPatterns.contains(where: { $0.matches(tokens) }) {
            found.append(Claim(kind: .firstPersonCreation, sentence: sentence))
            return found
        }
        // Review finding — ORDER. This ran AFTER the passive tier had already
        // returned, so *"I'll create a reminder titled …has been created"* was
        // read as a completed action despite opening with `i'll`. An offer
        // marker anywhere in the sentence now beats the passive and
        // present-state tiers alike. It stays BELOW the first-person tier on
        // purpose: these patterns are unanchored, and *"I've set the alarm and
        // I can change it"* must still fire.
        if offerPatterns.contains(where: { $0.matches(tokens) }) { return found }
        if passivePatterns.contains(where: { $0.matches(tokens) }) {
            found.append(Claim(kind: .passiveCompletion, sentence: sentence))
            return found
        }
        if presentStateSetPatterns.contains(where: { $0.matches(tokens) }) {
            found.append(Claim(kind: .presentStateSet, sentence: sentence))
            return found
        }
        if presentStateOnPatterns.contains(where: { $0.matches(tokens) }) {
            found.append(Claim(kind: .presentStateOn, sentence: sentence))
        }
        return found
    }
}
