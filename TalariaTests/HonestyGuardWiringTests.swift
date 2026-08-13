import Foundation
import Testing
@testable import Talaria

/// #338 — the honesty guard's PRODUCTION half: the settle-point application,
/// the counter (#338-E), the log line, and the composition the user sees.
///
/// `ActionClaimDetectorTests` pins the pure detector against the real
/// artifacts. This file pins what `LocalChatBackend` does with its verdict —
/// the half a table of strings cannot reach: that the model's text survives
/// verbatim, that a normal turn is untouched, that a firing is counted, and
/// that the guard is an identity function whenever a tool call ran.
///
/// `@MainActor` because the backend is.
@MainActor
struct HonestyGuardWiringTests {

    private func makeBackend() -> LocalChatBackend {
        LocalChatBackend(
            persistence: UserDefaultsAppPersistenceStore(
                defaults: UserDefaults(suiteName: "honesty-guard-wiring-tests")!
            ),
            intelligence: LocalIntelligenceService()
        )
    }

    /// The #337-A production reply, verbatim.
    private static let productionDefect =
        "**Confirmation card:** A reminder to \"take out the trash\" at 8 AM has been created."

    // MARK: - The response shape (#338's ruling clause)

    @Test("338: the model's text survives VERBATIM as the prefix — nothing is rewritten or deleted")
    func modelTextIsNeverRewritten() {
        let backend = makeBackend()
        let out = backend.honestyGuardedReply(
            modelText: Self.productionDefect,
            settledText: Self.productionDefect,
            executedToolNames: [])
        #expect(out.hasPrefix(Self.productionDefect),
                "silent rewriting is its own trust problem — the entry says APPEND")
        #expect(out.contains(LocalChatBackend.honestyCorrectionNotice))
        #expect(out == Self.productionDefect + "\n\n" + LocalChatBackend.honestyCorrectionNotice)
    }

    @Test("338: the correction is one named constant and it is visibly distinct")
    func theCorrectionIsOneNamedConstant() {
        let notice = LocalChatBackend.honestyCorrectionNotice
        #expect(!notice.isEmpty)
        #expect(notice.contains("\u{26A0}\u{FE0F}"), "a visibly distinct marker, not prose that blends in")
        // It must not itself read as a completed-action claim — otherwise a
        // corrected reply replayed as history could arm the guard again.
        #expect(ActionClaimDetector.claims(in: notice).isEmpty,
                "the correction must be claim-free: \(ActionClaimDetector.claims(in: notice))")
        // It must not promise a retry will work — #337 measured 0/90 creations.
        let lowered = notice.lowercased()
        #expect(!lowered.contains("try again"))
        #expect(!lowered.contains("ask me again"))
    }

    @Test("338: an empty model reply still gets an honest correction, not an empty bubble")
    func emptySettledTextStillCarriesTheCorrection() {
        #expect(LocalChatBackend.appendingHonestyCorrection(to: "")
                == LocalChatBackend.honestyCorrectionNotice)
    }

    @Test("338: the correction attaches to the SETTLED text, so an appended block survives")
    func theCorrectionFollowsTheSettledText() {
        let backend = makeBackend()
        let settled = Self.productionDefect + "\n\nI can read your calendar and reminders."
        let out = backend.honestyGuardedReply(
            modelText: Self.productionDefect, settledText: settled, executedToolNames: [])
        #expect(out.hasPrefix(settled))
        #expect(out.hasSuffix(LocalChatBackend.honestyCorrectionNotice))
    }

    // MARK: - 338-D: production safety

    @Test("338-D: a normal successful turn is untouched — the guard is an identity function")
    func normalTurnIsUntouched() {
        let backend = makeBackend()
        let honest = "Here\u{2019}s a haiku about sledding:\n\nSnow flies fast,  \nLaughter echoes down the hill\u{2014}  \nWinter\u{2019}s wild ride."
        #expect(backend.honestyGuardedReply(
            modelText: honest, settledText: honest, executedToolNames: []) == honest)
        #expect(backend.honestyGuardFireCount == 0)
        #expect(backend.lastHonestyGuardClaim == nil)
    }

    @Test("338-D: an honest OFFER is untouched")
    func honestOfferIsUntouched() {
        let backend = makeBackend()
        let offer = "Here\u{2019}s the confirmation:\n\n- **Title**: Test Talaria  \n- **Time**: 4:30 PM today  \n\nWould you like me to create this reminder?"
        #expect(backend.honestyGuardedReply(
            modelText: offer, settledText: offer, executedToolNames: []) == offer)
        #expect(backend.honestyGuardFireCount == 0)
    }

    @Test("338-D: a turn that DID execute its action tool is untouched",
          arguments: ["createReminder", "createCalendarEvent", "scheduleAlarm"])
    func executedActionTurnIsUntouched(_ tool: String) {
        let backend = makeBackend()
        // The real F6C46C82 row that DID call the tool and DID say so.
        let honestClaim = "I\u{2019}ve set a reminder for you to test Talaria at 4:30 PM. Anything else?"
        #expect(backend.honestyGuardedReply(
            modelText: honestClaim, settledText: honestClaim, executedToolNames: [tool]) == honestClaim)
        #expect(backend.honestyGuardFireCount == 0)
        // …and it is untouched even alongside read calls in the same turn.
        #expect(backend.honestyGuardedReply(
            modelText: honestClaim, settledText: honestClaim,
            executedToolNames: ["currentWeather", tool, "readCalendar"]) == honestClaim)
        #expect(backend.honestyGuardFireCount == 0)
    }

    @Test("338-D: the guard returns text on every path and never throws")
    func theGuardNeverThrows() {
        // #197's rule, stated as a type fact: `honestyGuardedReply` is not
        // `throws`, so no caller on the tool path can gain a throw from it.
        // The test that would BITE is a compile failure, so this asserts the
        // behavioural half — every input yields a string.
        let backend = makeBackend()
        for text in ["", " ", Self.productionDefect, "I've set a reminder.", "haiku"] {
            let out = backend.honestyGuardedReply(
                modelText: text, settledText: text, executedToolNames: [])
            #expect(out.hasPrefix(text) || out == LocalChatBackend.honestyCorrectionNotice)
        }
    }

    // MARK: - 338-E: counted

    @Test("338-E: every firing increments the counter and records the claim")
    func firingsAreCounted() {
        let backend = makeBackend()
        #expect(backend.honestyGuardFireCount == 0)

        _ = backend.honestyGuardedReply(
            modelText: Self.productionDefect, settledText: Self.productionDefect,
            executedToolNames: [])
        #expect(backend.honestyGuardFireCount == 1)
        #expect(backend.lastHonestyGuardClaim?.kind == .impersonatedCard)

        // #336's fabricated alarm row.
        _ = backend.honestyGuardedReply(
            modelText: "I\u{2019}ve set the alarm for 6:30. Let me know if you need anything else!",
            settledText: "I\u{2019}ve set the alarm for 6:30. Let me know if you need anything else!",
            executedToolNames: [])
        #expect(backend.honestyGuardFireCount == 2)
        #expect(backend.lastHonestyGuardClaim?.kind == .firstPersonCreation)

        // A quiet turn must not move the counter.
        _ = backend.honestyGuardedReply(
            modelText: "Would you like me to set an alarm for 6:30?",
            settledText: "Would you like me to set an alarm for 6:30?",
            executedToolNames: [])
        #expect(backend.honestyGuardFireCount == 2)
    }

    @Test("338-E: the log line is stable and carries the grep key")
    func logLineShape() {
        let line = LocalChatBackend.honestyGuardLogLine(
            kind: .impersonatedCard, executedCalls: 0, fireCount: 1)
        #expect(line == "honesty-guard FIRED impersonatedCard — 0 tool call(s) executed this turn, 1 firing(s) this session (#338)")
        // Every claim kind renders.
        for kind in ActionClaimDetector.ClaimKind.allCases {
            let rendered = LocalChatBackend.honestyGuardLogLine(kind: kind, executedCalls: 2, fireCount: 7)
            #expect(rendered.contains("honesty-guard FIRED"))
            #expect(rendered.contains(kind.rawValue))
            #expect(rendered.contains("(#338)"))
        }
    }

    // MARK: - The defect, end to end through the production composition

    // MARK: - THE WIRING ITSELF (review finding, 2026-08-12)
    //
    // Every test above this line hands `honestyGuardedReply` an array it built
    // by hand, so NOTHING pinned where production's array comes from. The
    // reviewer's demonstration: delete both `if event.phase == .started`
    // blocks and the whole suite stayed green — while the guard, now reading an
    // always-empty array, fires on every honest tool-executing turn and tells
    // the user "Nothing was created" about a reminder that exists.
    //
    // `TurnToolCallRecorder` exists so there is ONE such filter, and these
    // tests hold it. RED witness for each is named in its own comment.

    private func makeRelay() -> ToolEventRelay {
        let relay = ToolEventRelay()
        relay.governor = ToolCallGovernor()
        return relay
    }

    @Test("338 wiring: the recorder is populated from .started events — and ONLY those")
    func theRecorderReadsStartedEventsOnly() throws {
        let relay = makeRelay()
        let recorder = LocalChatBackend.TurnToolCallRecorder()
        recorder.install(on: relay) { _ in }

        // The real emit path, not a hand-built event: `started` is what the
        // tools call, and it is what decides whether anything is emitted.
        try relay.started("createReminder", detail: "test Talaria")
        #expect(recorder.executedToolNames == ["createReminder"])

        // RED WITNESS for the `.started` filter: remove the guard in
        // `TurnToolCallRecorder.record` and `completed` doubles every name.
        relay.completed("createReminder")
        #expect(recorder.executedToolNames == ["createReminder"],
                "a completed event describes the SAME call — counting it inflates the turn's tool count")

        try relay.started("getCalendarEvents")
        relay.completed("getCalendarEvents")
        #expect(recorder.executedToolNames == ["createReminder", "getCalendarEvents"],
                "names accumulate in emit order")
    }

    @Test("338 wiring: the recorder forwards every event to the caller's observer")
    func theRecorderForwardsWhatItObserves() throws {
        let relay = makeRelay()
        let recorder = LocalChatBackend.TurnToolCallRecorder()
        // Production's forwarding closure is what paints tool chips and sets
        // the #197 activity flag — recording must not consume the event.
        final class Box: @unchecked Sendable { var events: [ToolCallEvent] = [] }
        let box = Box()
        recorder.install(on: relay) { box.events.append($0) }

        try relay.started("createReminder")
        relay.completed("createReminder")
        #expect(box.events.count == 2, "the chip channel must still see both phases")
        let phases = box.events.map { event -> String in
            switch event.phase {
            case .started: "started"
            case .completed: "completed"
            }
        }
        #expect(phases == ["started", "completed"])
    }

    @Test("338 wiring: a governor-REFUSED call never reaches the recorder")
    func refusedCallsAreAbsentByConstruction() throws {
        let relay = makeRelay()
        let recorder = LocalChatBackend.TurnToolCallRecorder()
        recorder.install(on: relay) { _ in }
        relay.beginTurn()

        // Drive the #225 governor past its same-tool repeat cap, then confirm
        // the refused calls left no trace. A refused call that recorded would
        // silence the guard on exactly the turns #337 is about — the model
        // asks, is refused, and claims it did it anyway.
        //
        // Bounded below #232's throw: refusals 1…3 stay strings, the fourth
        // throws, so six attempts is safely inside the string arm.
        var admitted = 0
        var refused = 0
        for _ in 0..<6 {
            let admission = try relay.started("createReminder")
            if case .refused = admission { refused += 1 } else { admitted += 1 }
        }
        #expect(refused > 0, "the governor must actually refuse for this test to mean anything")
        #expect(admitted > 0, "…and admit some, or the comparison below is vacuous")
        #expect(recorder.executedToolNames.count == admitted,
                "refused calls are absent by construction — `started` returns before emitting")
        #expect(recorder.executedToolNames.allSatisfy { $0 == "createReminder" })
    }

    @Test("338 wiring: the recorder survives a #232 phase-cut retry")
    func theRecorderSurvivesThePhaseCutRetry() throws {
        // The property that makes production correct across #232 / #229 / #197:
        // ONE recorder for the whole turn, created outside the retry loop. A
        // tool that ran before the cut staged a real confirmation card, so the
        // guard must stay quiet for that turn even though the retried leg runs
        // toolless.
        //
        // RED WITNESS: move `let toolCallRecorder = TurnToolCallRecorder()`
        // inside `while true` in either turn path and the retried leg starts
        // from empty — this test's final expectation goes red.
        let backend = makeBackend()
        let relay = makeRelay()
        let recorder = LocalChatBackend.TurnToolCallRecorder()
        recorder.install(on: relay) { _ in }

        // Leg 1: the tool runs, then the turn is cut.
        try relay.started("createReminder", detail: "take out the trash")
        // Leg 2: the retried, toolless leg. The relay is re-armed exactly as
        // production re-enters the loop — the RECORDER is not replaced.
        recorder.install(on: relay) { _ in }
        #expect(recorder.executedToolNames == ["createReminder"],
                "the pre-cut call must survive into the retried leg")

        // …and the guard, given that recorder, is silent on the retried leg's
        // claim, because the card really was staged.
        let claim = "I\u{2019}ve set a reminder to take out the trash at 8 PM."
        #expect(backend.honestyGuardedReply(
            modelText: claim, settledText: claim,
            executedToolNames: recorder.executedToolNames) == claim)
        #expect(backend.honestyGuardFireCount == 0)
    }

    @Test("338 wiring: an EMPTY recorder is what makes the guard fire — the failure mode itself")
    func anEmptyRecorderIsTheFailureMode() {
        // States the reviewer's point as an assertion: if the `.started` filter
        // is broken so nothing is ever recorded, THIS is what the user gets on
        // an honest tool-executing turn. The test above is what prevents it.
        let backend = makeBackend()
        let honest = "I\u{2019}ve set a reminder to take out the trash at 8 PM."
        let withRecording = backend.honestyGuardedReply(
            modelText: honest, settledText: honest, executedToolNames: ["createReminder"])
        let withoutRecording = backend.honestyGuardedReply(
            modelText: honest, settledText: honest, executedToolNames: [])
        #expect(withRecording == honest)
        #expect(withoutRecording.contains(LocalChatBackend.honestyCorrectionNotice))
        #expect(withRecording != withoutRecording,
                "the recorder is load-bearing: these two differ by a false statement to the user")
    }

    // MARK: - The conversation-scoped latch (the earlier-turn fix)

    @Test("338 wiring: an executed ACTION tool sets the conversation latch; a read tool does not")
    func theConversationLatchTracksActionTools() throws {
        let relay = makeRelay()
        #expect(!relay.actionToolExecutedThisConversation)

        try relay.started("getCalendarEvents")
        #expect(!relay.actionToolExecutedThisConversation,
                "reading does not license a completion claim in a later turn")

        try relay.started("createReminder")
        #expect(relay.actionToolExecutedThisConversation)

        // Conversation-scoped, NOT turn-scoped — the whole point.
        relay.beginTurn()
        #expect(relay.actionToolExecutedThisConversation,
                "a new TURN must not clear it — the follow-up question is the next turn")

        relay.endConversationToolState()
        #expect(!relay.actionToolExecutedThisConversation,
                "a fresh conversation has no earlier turn to license anything")
    }

    @Test("338 wiring: the honest follow-up about an EARLIER turn's reminder is not corrected")
    func theEarlierTurnFollowUpIsNotCorrected() {
        // The exchange this fix exists for, end to end through the production
        // composition: turn 1 created the reminder, turn 2 executes nothing.
        let backend = makeBackend()
        let followUp = "Yes, the reminder is set for 8 PM."
        let settled = LocalChatBackend.settledReplyContent(
            followUp, appendingCapabilityAnswer: false)

        let corrected = backend.honestyGuardedReply(
            modelText: followUp, settledText: settled, executedToolNames: [],
            priorActionToolExecutedInConversation: false)
        #expect(corrected.contains(LocalChatBackend.honestyCorrectionNotice),
                "with no history at all this IS a fabrication and must be corrected")

        let honest = backend.honestyGuardedReply(
            modelText: followUp, settledText: settled, executedToolNames: [],
            priorActionToolExecutedInConversation: true)
        #expect(honest == settled, "the reminder exists — appending \"Nothing was created\" would be a lie")
        #expect(backend.honestyGuardFireCount == 1, "only the first call fired")
    }

    @Test("338: the #337-A reply composed through the settle point comes out honest")
    func theProductionDefectIsCorrected() {
        let backend = makeBackend()
        // Exactly what `send`/`streamTurn` do: settle first, then guard.
        let settled = LocalChatBackend.settledReplyContent(
            Self.productionDefect, appendingCapabilityAnswer: false)
        let userSees = backend.honestyGuardedReply(
            modelText: Self.productionDefect, settledText: settled, executedToolNames: [])
        #expect(userSees != Self.productionDefect, "the user must not see the bare lie")
        #expect(userSees.contains("has been created"), "the model's own words are still there to diagnose")
        // Reference the CONSTANT, never a copy of its text: this assertion was
        // written against the lane's proposed wording and went RED the moment
        // Owen ruled on the final copy (2026-08-12). The property under test is
        // "the correction is present", not "the correction says these words" —
        // `theCorrectionIsOneNamedConstant` owns the wording's properties.
        #expect(userSees.contains(LocalChatBackend.honestyCorrectionNotice))
        #expect(backend.honestyGuardFireCount == 1)
    }
}
