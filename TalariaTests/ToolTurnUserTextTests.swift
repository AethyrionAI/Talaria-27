import Foundation
import Testing
@testable import Talaria

/// OPEN_ITEMS #340 bar 340-U-B — the per-turn `userText` seam.
///
/// Task 1 shipped `DeviceActionParsing.detectDue(in:now:)`, which resolves a
/// due date out of the USER's own sentence. Task 3 will call it from
/// `ReminderCreateTool.performCreate` when the model leaves `due` empty. But
/// `performCreate` only ever sees the model's arguments — nothing in the tool
/// belt has ever carried the user's words. This file pins the seam that does:
/// the turn-boundary call both production paths already make.
///
/// **Why the seam rides `beginTurn` rather than a new call.** `beginToolTurn()`
/// → `relay.beginTurn()` is the ONE place a production turn starts (#225/#228),
/// and #343's lesson is that turn-scoped state which is set anywhere else leaks
/// across turns invisibly. Hanging the user's text off the existing boundary
/// makes "cleared for the next turn" structural rather than remembered — which
/// is exactly what the second row below pins.
///
/// `@MainActor` for the same reason `ToolCallInstrumentTests` is: the relay is
/// MainActor-isolated, and every tool already hops to it.
@MainActor
struct ToolTurnUserTextTests {

    // MARK: - The relay field (rows 1–2)

    /// The user's own sentence reaches the belt for the current turn.
    @Test func beginTurnCarriesTheUserText() {
        let relay = ToolEventRelay()

        relay.beginTurn(userText: "remind me at 4")

        #expect(relay.currentTurnUserText == "remind me at 4")
    }

    /// **A stale sentence must never leak into the next turn.** The argument is
    /// defaulted so every existing `beginTurn()` caller compiles unchanged —
    /// which means the instruments' per-trial reset (#343) calls the no-argument
    /// form dozens of times in a row. If that form left the previous turn's text
    /// in place, a battery trial (or, in production, a turn whose text the caller
    /// declined to pass) would resolve a due date from a sentence the user wrote
    /// several turns ago. Clearing is the whole point of the default, not a
    /// side effect of it.
    @Test func aTurnWithNoTextClearsTheLastOne() {
        let relay = ToolEventRelay()

        relay.beginTurn(userText: "remind me at 4")
        relay.beginTurn()

        #expect(relay.currentTurnUserText == nil)
    }

    /// The field is turn-scoped, so a second turn REPLACES rather than appends
    /// or keeps the first. (The clearing row above cannot see this: a caller
    /// that ignored its argument entirely would pass it.)
    @Test func aSecondTurnReplacesTheText() {
        let relay = ToolEventRelay()

        relay.beginTurn(userText: "remind me at 4")
        relay.beginTurn(userText: "remind me tomorrow at 9")

        #expect(relay.currentTurnUserText == "remind me tomorrow at 9")
    }

    // MARK: - Source witnesses (row 3)

    /// **Both production turn paths pass the USER's message, not the assembled
    /// prompt.** This is the pin that matters most and the one no runtime test
    /// in this target can make: `send` and `streamTurn` need a live
    /// `LanguageModelSession`, so what they hand the relay is only checkable by
    /// reading production's own source.
    ///
    /// `promptText` is the negative half and it is a real hazard, not a
    /// hypothetical one: by the time `beginToolTurn()` is reached, `turnInput`
    /// has been rewritten by `Self.prefixed(turnInput, with: memoryPrefix)`, so
    /// its `promptText` carries the memory block and any instruction prefix
    /// ahead of the user's words. Feeding THAT to a date detector would let a
    /// remembered "your dentist appointment is Thursday at 3" set the due date
    /// of a reminder the user asked for with no time at all.
    ///
    /// **What this row does NOT say, since 2026-09-06 (bar 340-F3).** It pins
    /// what the two paths HAND the seam — `message`, the user's own bubble.
    /// What the seam then hands the BELT is narrower on exactly one path: a
    /// synthesized voice transcript is reduced to its `User:` lines by
    /// `LocalChatBackend.beltUserText(from:)` inside `beginToolTurn`, so the
    /// assistant's own words can never set a reminder's due date. That
    /// narrowing is pinned in `VoiceTranscriptTests`; this row was deliberately
    /// left byte-identical, because its hazard (`promptText`, carrying the
    /// memory prefix) is a different and larger one.
    ///
    /// Same source-witness shape as `MemoryInjectionTests`, deliberately: the
    /// body is bounded at the next method declaration rather than by a
    /// character count, because `send` and `streamTurn` carry near-identical
    /// lines and a window that overran would read one function's text as the
    /// other's.
    @Test func bothTurnPathsPassTheUsersOwnMessage() throws {
        for anchor in ["func send(", "func streamTurn("] {
            let body = try Self.backendFunctionBody(from: anchor)
            #expect(body.contains("beginToolTurn(userText: message)"),
                    "\(anchor) must hand the relay the user's own words")
            #expect(!body.contains("beginToolTurn(userText: promptText)"),
                    "\(anchor) must NOT hand the relay the assembled prompt — a memory or instruction prefix would be mined for dates")
        }
    }

    /// **The control for the witness above, and it has two halves.**
    ///
    /// A source pin that reads an empty string passes every `!body.contains(…)`
    /// assertion vacuously, and a pin that reads the WHOLE file passes every
    /// `body.contains(…)` assertion for the wrong reason — one function's line
    /// satisfying the other function's pin. So this asserts the extraction is
    /// both non-empty and correctly BOUNDED, using a marker unique to each turn
    /// path: `send` locks its tool-activity flag as `sawToolActivity`,
    /// `streamTurn` as `sawObservableActivity`, and neither name appears in the
    /// other's body.
    @Test func theSourceWitnessReadsOneBoundedFunctionBody() throws {
        let send = try Self.backendFunctionBody(from: "func send(")
        let stream = try Self.backendFunctionBody(from: "func streamTurn(")

        #expect(send.contains("sawToolActivity"),
                "the witness read no `send` body at all — a vacuous pin")
        #expect(!send.contains("sawObservableActivity"),
                "the witness overran `send` into `streamTurn` — its pins would pass on the wrong function's text")
        #expect(stream.contains("sawObservableActivity"),
                "the witness read no `streamTurn` body at all — a vacuous pin")
        #expect(!stream.contains("sawToolActivity"),
                "the witness overran `streamTurn` — its pins would pass on the wrong function's text")
    }

    // MARK: - source helper

    /// One function's body, bounded at the NEXT method declaration rather than
    /// by a character count.
    ///
    /// **⟵ HOISTED 2026-09-04 (#340 Task 3).** This used to be a private copy
    /// of `MemoryInjectionTests.backendFunctionBody(from:)`, byte-identical to
    /// it; Task 3 needed a third user and the right answer to a third copy is
    /// one implementation. Both former copies now delegate here, and
    /// `RepoSourceWitness` carries the reasoning about why the body is bounded
    /// rather than character-counted.
    private static func backendFunctionBody(from anchor: String) throws -> String {
        try RepoSourceWitness.functionBody(from: anchor)
    }
}
