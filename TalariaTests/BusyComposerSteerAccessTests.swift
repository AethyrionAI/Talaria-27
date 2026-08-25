import Foundation
import Testing
@testable import Talaria

/// #381 — steer was unreachable exactly when you'd want it: the composer's
/// `.busyNoCommit` arm rendered Stop and nothing else, while the resolver
/// (`ComposerDoor.explicitDoors`) correctly reported `[.steered,
/// .interrupted]` with the hold slot taken. The model was right; the view
/// never asked. These tests pin the new view-side gate
/// (`busyAuxiliaryDoors`) and, structurally, that the `.busyNoCommit` arm
/// actually consults it through a shared menu body.
struct BusyComposerSteerAccessTests {

    private func doorsWithHoldTaken() -> [ComposerDoor] {
        ComposerDoor.explicitDoors(
            streamLostRunLive: false,
            runIDAvailable: true,
            steerAttemptOutstanding: false,
            holdSlotFree: false
        )
    }

    // 381-A: the affordance exists for exactly the ruled state.
    @Test func holdTakenSendableDraftOffersSteerAndInterrupt() {
        let doors = ComposerDoor.busyAuxiliaryDoors(
            explicitDoors: doorsWithHoldTaken(),
            canSend: true,
            isSlashMode: false
        )
        #expect(doors == [.steered, .interrupted])
    }

    // 381-B: the collapsed causes of busyNoCommit stay distinguished.
    @Test func anEmptyDraftGetsNoMenu() {
        let doors = ComposerDoor.busyAuxiliaryDoors(
            explicitDoors: doorsWithHoldTaken(),
            canSend: false,
            isSlashMode: false
        )
        #expect(doors.isEmpty, "nothing to steer with")
    }

    @Test func aSlashDraftGetsNoMenu() {
        let doors = ComposerDoor.busyAuxiliaryDoors(
            explicitDoors: doorsWithHoldTaken(),
            canSend: true,
            isSlashMode: true
        )
        #expect(doors.isEmpty, "dispatch hard-refuses slash steers; the menu must not offer one")
    }

    // 381-C: row 3 stays closed — the helper keys on the resolver's answer.
    @Test func theReconcileWindowWithATakenSlotOffersNothing() {
        let row3 = ComposerDoor.explicitDoors(
            streamLostRunLive: true,
            runIDAvailable: true,
            steerAttemptOutstanding: false,
            holdSlotFree: false
        )
        #expect(row3.isEmpty, "the #307 guard — precondition of this test")
        let doors = ComposerDoor.busyAuxiliaryDoors(
            explicitDoors: row3, canSend: true, isSlashMode: false
        )
        #expect(doors.isEmpty)
    }

    // An outstanding steer attempt leaves only the interrupt door.
    @Test func anOutstandingSteerLeavesOnlyInterrupt() {
        let doors = ComposerDoor.busyAuxiliaryDoors(
            explicitDoors: ComposerDoor.explicitDoors(
                streamLostRunLive: false,
                runIDAvailable: true,
                steerAttemptOutstanding: true,
                holdSlotFree: false
            ),
            canSend: true,
            isSlashMode: false
        )
        #expect(doors == [.interrupted])
    }

    // Defensive: a state named no-commit never offers the queue door.
    @Test func theQueueDoorIsFilteredEvenIfPresent() {
        let doors = ComposerDoor.busyAuxiliaryDoors(
            explicitDoors: [.queued, .steered, .interrupted],
            canSend: true,
            isSlashMode: false
        )
        #expect(!doors.contains(.queued))
    }

    /// 381-A/D structural: the `.busyNoCommit` view arm consults the helper
    /// through a `Menu` sharing `queueCommitButton`'s door items — so the
    /// two sites cannot drift and the entry copy stays the pinned verbatim.
    @Test func busyNoCommitArmRendersTheSteerMenu() throws {
        let barPath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Talaria/Features/Chat/ChatInputBar.swift")
        let source = try #require(
            try? String(contentsOf: barPath, encoding: .utf8),
            "ChatInputBar.swift unreadable — this pin must fail loudly, not vacuously"
        )
        guard let armRange = source.range(of: "case .busyNoCommit:") else {
            Issue.record("the .busyNoCommit arm is gone — re-point this pin at its successor")
            return
        }
        let armBody = String(source[armRange.upperBound...].prefix(800))
        #expect(
            armBody.contains("busyAuxiliaryDoors") && armBody.contains("Menu"),
            "381-A: the busy arm must offer the steer menu the resolver already licenses"
        )
    }
}
