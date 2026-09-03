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

    @Test("422-H: the PASSIVE memory form fires too")
    func thePassiveMemoryFormFires() {
        // The passive tier's memory twin: the same *"…has been created"* shape
        // #337-A's production reply used, wearing a memory verb.
        #expect(ActionClaimDetector.unfulfilledClaim(
            in: "That's been noted.", executedToolNames: [], savedNote: false)?.kind
            == .memoryCreation)
        #expect(ActionClaimDetector.unfulfilledClaim(
            in: "Your preference has been saved.", executedToolNames: [], savedNote: false)?.kind
            == .memoryCreation)
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
}
