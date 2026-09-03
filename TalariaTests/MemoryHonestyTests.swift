import Foundation
import Testing
@testable import Talaria

/// **#422 bar 422-H (offline arm) — the honesty guard learns the MEMORY
/// claim.**
///
/// #338's guard exists because the app told the user a device write had
/// happened when nothing was written. Local memory adds a SECOND artifact the
/// model can claim to have written and did not: *"Got it, I'll remember
/// that."* Talaria stores only what the user explicitly asks it to store
/// (*"Remember that…"*), so a turn that saved no note and promised to remember
/// is the same defect in a new place.
///
/// **It is a worse place, which is why it gets its own kind.** A fabricated
/// reminder is discoverable — the user opens Reminders and sees nothing. A
/// fabricated MEMORY is discoverable only weeks later, when the thing the app
/// promised to remember turns out never to have existed. There is no card, no
/// second app, and no absence to notice until it matters.
///
/// **Shape: 417-D's positive controls.** Every must-fire row is paired with a
/// must-stay-quiet row, so a detector that simply says yes cannot pass; and the
/// `savedNote` row is the mutation target named by 422-H — remove the
/// short-circuit in `unfulfilledClaim` and
/// `aClaimOnATurnThatDidSaveANoteIsLicensed` is the ONLY test that reds.
///
/// `@MainActor` because `LocalChatBackend` is.
@MainActor
@Suite("422-H honesty")
struct MemoryHonestyTests {

    private func makeBackend() -> LocalChatBackend {
        LocalChatBackend(
            persistence: UserDefaultsAppPersistenceStore(
                defaults: UserDefaults(suiteName: "memory-honesty-tests")!
            ),
            intelligence: LocalIntelligenceService()
        )
    }

    // MARK: - The claim fires (must-fire controls)

    @Test("422-H: a memory claim on a turn that saved nothing fires",
          arguments: ["Got it, I'll remember that.",
                      "I've noted that your sister lives in Austin.",
                      "I'll keep that in mind."])
    func aMemoryClaimWithNoSavedNoteFires(reply: String) {
        let claim = ActionClaimDetector.unfulfilledClaim(
            in: reply, executedToolNames: [], savedNote: false)
        #expect(claim?.kind == .memoryCreation,
                "nothing was stored — this reply is a promise the app cannot keep: \(String(describing: claim))")
    }

    @Test("422-H: the PASSIVE memory form fires too",
          arguments: ["That's been noted.",
                      "This has been saved to memory.",
                      "That has been noted.",
                      "Your note has been saved."])
    func thePassiveMemoryFormFires(reply: String) {
        // The passive tier's memory twin: the same *"…has been created"* shape
        // #337-A's production reply used, wearing a memory verb — and, since
        // review round 1, gated on a memory NOUN as its subject.
        #expect(ActionClaimDetector.unfulfilledClaim(
            in: reply, executedToolNames: [], savedNote: false)?.kind == .memoryCreation)
    }

    @Test("422-H/338-B: a CURLY apostrophe fires exactly as the straight one does")
    func curlyApostrophesFire() {
        // Bar 338-B is not decoration — of the three #336 fabricated rows, two
        // carry U+2019. The memory family inherits the same normalization or
        // it misses two thirds of what the model actually writes.
        let curly = ActionClaimDetector.unfulfilledClaim(
            in: "Got it, I\u{2019}ll remember that.", executedToolNames: [], savedNote: false)
        let straight = ActionClaimDetector.unfulfilledClaim(
            in: "Got it, I'll remember that.", executedToolNames: [], savedNote: false)
        #expect(curly?.kind == .memoryCreation)
        #expect(curly?.kind == straight?.kind)
    }

    // MARK: - The guard stays quiet (must-stay-quiet controls)

    @Test("422-H: honest disclaimers and unrelated replies stay quiet",
          arguments: ["I can't remember things between chats unless you ask me to.",
                      "Sure \u{2014} what would you like me to do?"])
    func honestOrUnrelatedRepliesStayQuiet(reply: String) {
        #expect(ActionClaimDetector.unfulfilledClaim(
            in: reply, executedToolNames: [], savedNote: false) == nil,
                "a guard that fires on an honest disclaimer trains the user to ignore it (bar 338-A)")
    }

    @Test("422-H: an OFFER to remember is not a claim to have remembered")
    func anOfferToRememberStaysQuiet() {
        // The honest half of the same vocabulary. #338's design bias — every
        // ambiguity resolves toward SILENCE — applies unchanged here.
        for offer in ["Would you like me to remember that?",
                      "I can remember that for you if you ask me to.",
                      "Just say \"Remember that\u{2026}\" and I'll store it."] {
            #expect(ActionClaimDetector.unfulfilledClaim(
                in: offer, executedToolNames: [], savedNote: false) == nil,
                    "fired on an honest offer: \(offer)")
        }
    }

    // MARK: - The licence (the 422-H mutation target)

    @Test("422-H: a claim on a turn that DID save a note is licensed")
    func aClaimOnATurnThatDidSaveANoteIsLicensed() {
        #expect(ActionClaimDetector.unfulfilledClaim(
            in: "Got it, I'll remember that.", executedToolNames: [], savedNote: true) == nil,
                "the note really was written — appending \"Nothing was saved\" would be the lie")
    }

    @Test("422-H: the memory kind is licensed ONLY by a saved note")
    func theMemoryKindIsNeverLicensedByAToolCall() {
        // Deliberately unlike the present-state tiers: neither a read tool this
        // turn nor an action tool earlier in the conversation says anything
        // about whether a NOTE was stored, so neither may silence this kind.
        #expect(!ActionClaimDetector.ClaimKind.memoryCreation.isLicensedByAnyToolCall)
        #expect(ActionClaimDetector.unfulfilledClaim(
            in: "Got it, I'll remember that.",
            executedToolNames: ["getCalendarEvents"],
            priorActionToolExecutedInConversation: true,
            savedNote: false)?.kind == .memoryCreation)
    }

    // MARK: - The memory family does not steal the action family

    @Test("422-H: an ACTION reply is never read as a memory claim")
    func anActionReplyIsNotAMemoryClaim() {
        // An honest offer — #338 keeps it silent, and it must not become loud
        // by acquiring a memory reading.
        let offer = ActionClaimDetector.unfulfilledClaim(
            in: "I'll set a reminder for 8 PM.", executedToolNames: [], savedNote: false)
        #expect(offer?.kind != .memoryCreation)
        #expect(offer == nil, "an offer to act is not a completed action (#338-A)")

        // #336's fabricated alarm row stays exactly the kind it always was.
        #expect(ActionClaimDetector.unfulfilledClaim(
            in: "I\u{2019}ve set the alarm for 6:30.", executedToolNames: [], savedNote: false)?.kind
            == .firstPersonCreation)
    }

    // MARK: - RECALL is never corrected (review round 1, 2026-09-03)

    @Test("422-H: an ACCURATE recall is never corrected",
          arguments: ["Yes, I remember that.",
                      "I remember that your sister lives in Austin.",
                      "I remembered that you like coffee.",
                      "I've remembered that you like coffee."])
    func accurateRecallIsNeverCorrected(reply: String) {
        // **The defect this row exists for.** On a RETRIEVAL turn `savedNote`
        // is `false` by construction — nothing is written, the memory is only
        // read — so a tier that read these as claims appended "Nothing was
        // saved to memory… the reply above is inaccurate" to a reply that was
        // accurate. #338's own worst case, reached through the one turn shape
        // local memory exists to produce.
        //
        // RED WITNESS: restore `[["i"], memoryVerbs, memoryNouns], maxGap: 0`
        // (with `remember`/`remembered` in the verb set) and all four fire.
        #expect(ActionClaimDetector.unfulfilledClaim(
            in: reply, executedToolNames: [], savedNote: false) == nil,
                "recall is not a write — correcting it is the guard lying about the model")
    }

    // MARK: - A DEVICE write never gets the MEMORY correction

    @Test("422-H: a passive DEVICE claim is never read as a memory claim",
          arguments: ["Your changes have been saved.",
                      "The file has been saved.",
                      "Your reminder has been saved."])
    func aDeviceWriteIsNeverGivenTheMemoryCorrection(reply: String) {
        // Before the passive tier was noun-gated these all matched aux +
        // `been` + memory verb, so a DEVICE fabrication was answered with
        // "Nothing was saved to memory" — a true sentence about the wrong
        // subject, which is its own dishonesty.
        //
        // What they fall to instead is the device tiers' business, not this
        // suite's; the assertion is only that memory does not claim them.
        #expect(ActionClaimDetector.unfulfilledClaim(
            in: reply, executedToolNames: [], savedNote: false)?.kind != .memoryCreation)
    }

    // MARK: - The negated promise (the one negation that IS a claim)

    @Test("422-H: \"I won't forget that\" is a memory claim, not a negation",
          arguments: ["I won't forget that.",
                      "I'll never forget that.",
                      "I will not forget that.",
                      "Don't worry, I won't forget that."])
    func theNegatedPromiseFrameFires(reply: String) {
        // These are natural replies to the "keep in mind…" / "FYI…" prompts
        // bar 422-H's device arm targets, and the sentence-level negation
        // silencer runs ahead of every tier — so without the exemption the
        // whole family is unreachable rather than merely unmatched.
        #expect(ActionClaimDetector.unfulfilledClaim(
            in: reply, executedToolNames: [], savedNote: false)?.kind == .memoryCreation)
    }

    @Test("422-H: every OTHER negation still stays quiet",
          arguments: ["I can't remember things between chats unless you ask me to.",
                      "I won't be able to remember that.",
                      "I don't have memory between sessions.",
                      "You won't forget that.",
                      "I'm not going to forget.",
                      "I won't forget to remind you at 8."])
    func otherNegationsStayQuiet(reply: String) {
        // The exemption is a FRAME — the negation attached to `forget`, an
        // object after it, and a FIRST-PERSON subject. "You won't forget that"
        // is the model addressing the USER, and "I won't be able to remember
        // that" is an honest disclaimer; both must survive untouched.
        #expect(ActionClaimDetector.unfulfilledClaim(
            in: reply, executedToolNames: [], savedNote: false) == nil,
                "the exemption must not become a general negation hole")
    }

    @Test("422-H: the negated promise is licensed by a saved note like any other")
    func theNegatedPromiseIsLicensedBySavedNote() {
        #expect(ActionClaimDetector.unfulfilledClaim(
            in: "I won't forget that.", executedToolNames: [], savedNote: true) == nil)
    }

    @Test("422-H: a QUOTED negated promise buys no exemption")
    func aQuotedNegatedPromiseBuysNoExemption() {
        // The exemption is judged on the quote-stripped tokens, so the model
        // quoting someone else's promise cannot unlock the silencer — which
        // keeps #338's "silencers read the whole sentence" behaviour intact
        // for every sentence that does not match the frame itself.
        #expect(ActionClaimDetector.unfulfilledClaim(
            in: "You wrote \"I won't forget that\" in your note.",
            executedToolNames: [], savedNote: false) == nil)
    }

    // MARK: - The correction copy (Owen's naming ruling)

    @Test("422-H: the correction text is pinned")
    func theCorrectionTextIsPinned() {
        #expect(LocalChatBackend.memoryCorrectionNotice ==
            "\u{26A0}\u{FE0F} **Nothing was saved to memory.** Talaria only remembers what you ask "
            + "it to with \"Remember that\u{2026}\" \u{2014} the reply above is inaccurate.")
    }

    @Test("422-H: the memory correction obeys every property the action one does")
    func theMemoryCorrectionIsWellFormed() {
        let notice = LocalChatBackend.memoryCorrectionNotice
        #expect(notice.contains("\u{26A0}\u{FE0F}"), "visibly distinct, not prose that blends in")
        // Naming ruling (CLAUDE.md, Owen 08-27): the outward identity is
        // TALARIA. This string is user-facing and says nothing about a host.
        #expect(notice.contains("Talaria"))
        #expect(!notice.contains("Hermes"))
        // It must not itself read as a claim, or a corrected reply replayed as
        // history would arm the guard again.
        #expect(ActionClaimDetector.claims(in: notice).isEmpty,
                "the correction must be claim-free: \(ActionClaimDetector.claims(in: notice))")
        // …and it must not promise that asking again will work.
        let lowered = notice.lowercased()
        #expect(!lowered.contains("try again"))
        #expect(!lowered.contains("ask me again"))
    }

    // MARK: - #338's ruling clause: APPEND, never rewrite

    @Test("422-H/338: the correction is APPENDED \u{2014} the model's reply survives verbatim")
    func theMemoryCorrectionIsAppendedNeverRewritten() {
        let backend = makeBackend()
        let reply = "Got it, I'll remember that."
        let out = backend.honestyGuardedReply(
            modelText: reply, settledText: reply, executedToolNames: [], savedNote: false)
        #expect(out == reply + "\n\n" + LocalChatBackend.memoryCorrectionNotice)
        #expect(out.hasPrefix(reply),
                "silent rewriting is its own trust problem \u{2014} #338 says APPEND")
        #expect(backend.honestyGuardFireCount == 1)
        #expect(backend.lastHonestyGuardClaim?.kind == .memoryCreation)
    }

    @Test("422-H: a turn that DID save a note leaves the reply BYTE-untouched")
    func aSavedNoteLeavesTheReplyUntouched() {
        let backend = makeBackend()
        let reply = "Got it, I'll remember that."
        #expect(backend.honestyGuardedReply(
            modelText: reply, settledText: reply, executedToolNames: [], savedNote: true) == reply)
        #expect(backend.honestyGuardFireCount == 0)
        #expect(backend.lastHonestyGuardClaim == nil)
    }

    @Test("422-H: the two corrections never cross-wire")
    func theTwoCorrectionsDoNotCross() {
        let backend = makeBackend()
        // An ACTION fabrication gets the action copy — "Nothing was saved to
        // memory" would be a true sentence about the wrong subject, which is
        // its own kind of dishonesty.
        let fabrication = "I\u{2019}ve set the alarm for 6:30."
        let action = backend.honestyGuardedReply(
            modelText: fabrication, settledText: fabrication, executedToolNames: [])
        #expect(action.contains(LocalChatBackend.honestyCorrectionNotice))
        #expect(!action.contains(LocalChatBackend.memoryCorrectionNotice))

        // …and the memory fabrication gets the memory copy, never the action's
        // "No reminder, alarm, or event was written".
        let memory = backend.honestyGuardedReply(
            modelText: "I'll keep that in mind.", settledText: "I'll keep that in mind.",
            executedToolNames: [])
        #expect(memory.contains(LocalChatBackend.memoryCorrectionNotice))
        #expect(!memory.contains(LocalChatBackend.honestyCorrectionNotice))
    }

    @Test("422-H: an empty reply still carries the memory correction, not an empty bubble")
    func anEmptyReplyStillCarriesTheCorrection() {
        #expect(LocalChatBackend.appendingCorrection(
            LocalChatBackend.memoryCorrectionNotice, to: "")
            == LocalChatBackend.memoryCorrectionNotice)
    }

    // MARK: - The production seam

    @Test("422-H: the production `recorder:` overload carries savedNote through")
    func theProductionOverloadCarriesSavedNote() {
        // The overload both turn paths call. Task 11 wires the real value off
        // the explicit-note path; the default is `false`, which is the strict
        // reading — a caller that does not know stays as loud as it was.
        let backend = makeBackend()
        let reply = "Got it, I'll remember that."
        let recorder = LocalChatBackend.TurnToolCallRecorder()

        let corrected = backend.honestyGuardedReply(
            modelText: reply, settledText: reply, recorder: recorder)
        #expect(corrected.contains(LocalChatBackend.memoryCorrectionNotice),
                "the default must be the STRICT reading")

        let licensed = backend.honestyGuardedReply(
            modelText: reply, settledText: reply, recorder: recorder, savedNote: true)
        #expect(licensed == reply)
        #expect(backend.honestyGuardFireCount == 1, "only the unlicensed call fired")
    }

    // MARK: - Fix round 1 (Important, item 2): the ACTUAL call sites, witnessed
    //
    // `theProductionOverloadCarriesSavedNote` above proves the OVERLOAD wires
    // `savedNote` through correctly — but nothing pinned that `send` and
    // `streamTurn` actually PASS a real expression at their own call sites.
    // Hardcoding either to `savedNote: false` (silently reverting the round-1
    // fix) keeps every other test in the suite green, because none of them
    // drive a real `send`/`streamTurn` turn (the sim cannot generate, #324).
    // Read the live source, in the shape of
    // `GuardrailImageDegradeTests.theDegradeHasNoSecondComposeImplementation`.

    @Test("fix round 1: send() passes the real savedNote expression, not a hardcoded false")
    func sendWitnessesTheRealSavedNoteExpression() throws {
        let body = try Self.backendFunctionBody(from: "func send(", limit: 6000)
        #expect(body.contains("savedNote: turnInput.savedNote != nil"),
                "send()'s honestyGuardedReply call must wire the STORE-derived value, not a stand-in")
    }

    @Test("fix round 1: streamTurn() passes the real savedNote expression, not a hardcoded false")
    func streamTurnWitnessesTheRealSavedNoteExpression() throws {
        let body = try Self.backendFunctionBody(from: "func streamTurn(", limit: 10000)
        #expect(body.contains("savedNote: turnInput.savedNote != nil"),
                "streamTurn()'s honestyGuardedReply call must wire the STORE-derived value, not a stand-in")
    }

    /// Also pins that BOTH `composeTurnInput` calls in `send`/`streamTurn`
    /// feed `savedNoteThisTurn(clientMessageID:)` in — the other half of
    /// the round-1 fix (`ComposedTurnInput.savedNote` reading the STORE,
    /// never re-deriving from the text).
    @Test("fix round 1: both turn paths derive savedNote from the STORE, not the text")
    func bothTurnPathsDeriveSavedNoteFromTheStore() throws {
        let sendBody = try Self.backendFunctionBody(from: "func send(", limit: 1500)
        let streamBody = try Self.backendFunctionBody(from: "func streamTurn(", limit: 3500)
        for body in [sendBody, streamBody] {
            #expect(body.contains("savedNoteThisTurn(clientMessageID:"),
                    "composeTurnInput's savedNote argument must come from the store read, not ExplicitMemoryIntent.parse")
        }
    }

    // MARK: - source helpers (mirrors GuardrailImageDegradeTests' pattern)

    private static func backendSource() throws -> String {
        let path = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Talaria/Services/Live/LocalChatBackend.swift")
        return try #require(
            try? String(contentsOf: path, encoding: .utf8),
            "LocalChatBackend.swift unreadable — these pins must fail loudly, not vacuously"
        )
    }

    private static func backendFunctionBody(from anchor: String, limit: Int) throws -> String {
        let source = try backendSource()
        let range = try #require(
            source.range(of: anchor),
            "\(anchor) is gone — re-point this pin at its successor")
        return String(source[range.upperBound...].prefix(limit))
    }
}
