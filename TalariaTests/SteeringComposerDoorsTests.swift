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
}
