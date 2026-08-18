import Foundation
import Testing
@testable import Talaria

/// #357 bars 357-E/F/I — the pure halves of the 3C app slice: the turn-phase
/// tracker the composer keys on, and the door resolver for a plain mid-turn
/// send under Owen's queue|steer setting.
struct SteeringComposerDoorsTests {

    // MARK: - 357-F: phase tracking

    @Test func startsAwaitingFirstSignal() {
        #expect(RunTurnPhaseTracker().phase == .awaitingFirstSignal)
    }

    @Test func toolStartedOpensTheSteerWindow() {
        var t = RunTurnPhaseTracker()
        t.noteToolStarted()
        #expect(t.phase == .toolInFlight)
    }

    @Test func toolCompletedClosesTheWindowToProse() {
        var t = RunTurnPhaseTracker()
        t.noteToolStarted()
        t.noteToolCompleted()
        #expect(t.phase == .prose)
    }

    @Test func proseDeltaEndsToolInFlight() {
        // Matches ChatStore's `.textDelta` semantics: prose flowing
        // deactivates tool chips — the steer window is over.
        var t = RunTurnPhaseTracker()
        t.noteToolStarted()
        t.noteProseDelta()
        #expect(t.phase == .prose)
    }

    @Test func reasoningIsASeparateChannelAndKeepsTheWindowOpen() {
        // `_thinking` flows DURING tool execution (the SSE taxonomy's
        // standing rule) — it must not read as prose.
        var t = RunTurnPhaseTracker()
        t.noteToolStarted()
        t.noteReasoningDelta()
        #expect(t.phase == .toolInFlight)
    }

    @Test func serialToolsReopenTheWindow() {
        var t = RunTurnPhaseTracker()
        t.noteToolStarted()
        t.noteToolCompleted()
        t.noteToolStarted()
        #expect(t.phase == .toolInFlight)
    }

    @Test func duplicateAndOrphanEventsAreTolerated() {
        var t = RunTurnPhaseTracker()
        // A completed with no started (out-of-order stream) must not trap
        // or invent a window.
        t.noteToolCompleted()
        #expect(t.phase == .prose)
        // Duplicate starts stay one window (tools run serially).
        t.noteToolStarted()
        t.noteToolStarted()
        #expect(t.phase == .toolInFlight)
    }

    // MARK: - 357-E/I: the door resolver

    @Test func queueSettingAlwaysQueues() {
        #expect(ComposerDoor.resolvePlainSend(
            setting: .queue, streamLostRunLive: false,
            runIDAvailable: true, steerAttemptOutstanding: false
        ) == .queued)
    }

    @Test func steerSettingSteersWithALiveRunID() {
        #expect(ComposerDoor.resolvePlainSend(
            setting: .steer, streamLostRunLive: false,
            runIDAvailable: true, steerAttemptOutstanding: false
        ) == .steered)
    }

    @Test func steerSettingQueuesWhenNoRunIDYet() {
        // Before the submit ACK there is nothing to steer — the send still
        // has an honest landing (the queue), and the UI names it.
        #expect(ComposerDoor.resolvePlainSend(
            setting: .steer, streamLostRunLive: false,
            runIDAvailable: false, steerAttemptOutstanding: false
        ) == .queued)
    }

    @Test func steerSettingQueuesWhileASteerIsOutstanding() {
        // Depth-1, the #306 spirit: one steer in flight at a time; the next
        // send is the next message.
        #expect(ComposerDoor.resolvePlainSend(
            setting: .steer, streamLostRunLive: false,
            runIDAvailable: true, steerAttemptOutstanding: true
        ) == .queued)
    }

    @Test func row3StreamLostRunLiveQueuesRegardlessOfSetting() {
        // #357-I / #306/#307: the run is unreachable for steering and firing
        // into a live pendingRun is the reconcile corruption.
        for setting in MidTurnSendAction.allCases {
            #expect(ComposerDoor.resolvePlainSend(
                setting: setting, streamLostRunLive: true,
                runIDAvailable: true, steerAttemptOutstanding: false
            ) == .queued)
        }
    }

    // MARK: - 357-E: the explicit door menu (which doors are even offered)

    @Test func allThreeDoorsOfferedMidTurnWhenEverythingIsFree() {
        #expect(ComposerDoor.explicitDoors(
            streamLostRunLive: false, runIDAvailable: true,
            steerAttemptOutstanding: false, holdSlotFree: true
        ) == [.queued, .steered, .interrupted])
    }

    @Test func row3OffersQueueOnly() {
        // #357-I: stream-lost/run-live offers QUEUE only — no steer (the run
        // is unreachable) and no interrupt (no fire into a live pendingRun).
        #expect(ComposerDoor.explicitDoors(
            streamLostRunLive: true, runIDAvailable: true,
            steerAttemptOutstanding: false, holdSlotFree: true
        ) == [.queued])
    }

    @Test func outstandingSteerRemovesTheSteerDoorOnly() {
        // Depth-1: while one steer is unresolved the menu stops offering a
        // second, but queue and interrupt stay reachable.
        #expect(ComposerDoor.explicitDoors(
            streamLostRunLive: false, runIDAvailable: true,
            steerAttemptOutstanding: true, holdSlotFree: true
        ) == [.queued, .interrupted])
    }

    @Test func noRunIDRemovesTheSteerDoorOnly() {
        #expect(ComposerDoor.explicitDoors(
            streamLostRunLive: false, runIDAvailable: false,
            steerAttemptOutstanding: false, holdSlotFree: true
        ) == [.queued, .interrupted])
    }

    @Test func occupiedHoldRemovesTheQueueDoorOnly() {
        // The #306 hold is depth-1; a taken slot closes the queue door but
        // the running turn can still be steered or interrupted.
        #expect(ComposerDoor.explicitDoors(
            streamLostRunLive: false, runIDAvailable: true,
            steerAttemptOutstanding: false, holdSlotFree: false
        ) == [.steered, .interrupted])
    }

    // MARK: - 357-E/G: the door status chip (the steer attempt's on-screen state)

    @Test func steeringChipNamesTheDoorAndNeverSaysApplied() {
        let chip = DoorStatusChipModel(text: "reply PLUM", state: .steering)
        #expect(chip.doorName == ComposerDoor.steered.displayName)
        #expect(chip.statusLine == ComposerDoor.steered.waitingStatusLine)
        // 357-G: submitted must not read as applied — the ACK is submit-only.
        #expect(!chip.statusLine.localizedCaseInsensitiveContains("applied"))
    }

    @Test func steeredChipReadsApplied() {
        let chip = DoorStatusChipModel(text: "reply PLUM", state: .steered)
        #expect(chip.doorName == ComposerDoor.steered.displayName)
        #expect(chip.statusLine.localizedCaseInsensitiveContains("applied"))
    }

    @Test func interruptingChipCarriesTheBarLabel() {
        // 357-H's prescribed label, verbatim.
        let chip = DoorStatusChipModel(text: "new question", state: .interrupting)
        #expect(chip.doorName == ComposerDoor.interrupted.displayName)
        #expect(chip.statusLine == "Stopped — sending as a new message")
    }

    @Test func chipVocabularyNeverSaysSent() {
        // 306-J extended to the status chip: no form of "sent" for a message
        // that has not been posted. ("sending" in the interrupt label is the
        // in-progress post the bar itself prescribes — and contains no "sent".)
        for state in [DoorStatusChipModel.State.steering, .steered, .interrupting] {
            let chip = DoorStatusChipModel(text: "x", state: state)
            #expect(!chip.doorName.localizedCaseInsensitiveContains("sent"))
            #expect(!chip.statusLine.localizedCaseInsensitiveContains("sent"))
        }
    }

    // MARK: - 357-E/G/H: the store's chip derivation (pure)

    @Test func noAttemptNoChip() {
        #expect(ChatStore.doorStatusChip(steerAttempt: nil, interruptResendText: nil) == nil)
    }

    @Test func outstandingSteerDerivesSteeringChip() {
        let chip = ChatStore.doorStatusChip(
            steerAttempt: ChatStore.SteerAttempt(text: "reply PLUM"),
            interruptResendText: nil
        )
        #expect(chip == DoorStatusChipModel(text: "reply PLUM", state: .steering))
    }

    @Test func landedSteerDerivesSteeredChip() {
        var attempt = ChatStore.SteerAttempt(text: "reply PLUM")
        attempt.landed = true
        let chip = ChatStore.doorStatusChip(steerAttempt: attempt, interruptResendText: nil)
        #expect(chip == DoorStatusChipModel(text: "reply PLUM", state: .steered))
    }

    @Test func interruptWinsOverALingeringSteerAttempt() {
        // An interrupt fired while a steer attempt is still winding down is
        // the user's LATEST action — the chip reports it, not the steer.
        let chip = ChatStore.doorStatusChip(
            steerAttempt: ChatStore.SteerAttempt(text: "old steer"),
            interruptResendText: "new question"
        )
        #expect(chip == DoorStatusChipModel(text: "new question", state: .interrupting))
    }
}
