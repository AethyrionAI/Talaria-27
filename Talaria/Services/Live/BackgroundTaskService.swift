import BackgroundTasks
import Foundation
import os

private let bgLog = Logger(subsystem: "org.aethyrion.talaria", category: "BackgroundTasks")

/// `BGTask` is documented thread-safe (`setTaskCompleted` / `expirationHandler`
/// / `progress` may be touched off the launch-handler queue) but isn't marked
/// Sendable — box it so handlers can hop to the main actor under Swift 6.
private struct BGTaskBox<T: BGTask>: @unchecked Sendable {
    let task: T
}

/// Guarantees `setTaskCompleted` is called exactly once when the work path and
/// the expiration handler race.
private final class CompletionGate: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = false

    /// Returns true the first time only.
    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if completed { return false }
        completed = true
        return true
    }
}

// MARK: - BGAppRefreshTask (#14)

/// Native background wake — the safety net complementing relay APNs (which
/// stays the real-time path, #24f caveats and all). One refresh pass drains
/// the sensor outbox, runs one reconcile fetch, and rewrites widget data, so
/// background work survives app exit even when push is degraded or the
/// desktop connection is down. Discretionary by design: iOS decides when a
/// pass runs (can be hours) — this is a safety net, not real-time delivery.
enum BackgroundRefreshScheduler {

    /// Must match the entry in BGTaskSchedulerPermittedIdentifiers (project.yml).
    static let taskIdentifier = "org.aethyrion.talaria27.refresh"

    /// Registers the launch handler. MUST run before the app finishes
    /// launching — called from application(_:didFinishLaunchingWithOptions:).
    static func register() {
        let registered = BGTaskScheduler.shared.register(
            forTaskWithIdentifier: taskIdentifier,
            using: nil
        ) { task in
            guard let refresh = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(BGTaskBox(task: refresh))
        }
        if !registered {
            bgLog.notice("app-refresh register refused (already registered or not permitted)")
        }
    }

    /// Arms the next refresh window. Called on scene background entry; also
    /// re-armed after each pass so the chain continues while the app stays
    /// backgrounded.
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
            bgLog.notice("app-refresh scheduled (earliest +15m)")
        } catch {
            // Expected on Simulator (scheduler unavailable) — never fatal.
            bgLog.notice("app-refresh submit failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func handle(_ box: BGTaskBox<BGAppRefreshTask>) {
        // Chain the next window first so a crash mid-pass can't break the chain.
        schedule()

        let gate = CompletionGate()
        let work = Task { @MainActor in
            await AppContainer.sharedDefault().handleBackgroundRefresh()
            if gate.claim() {
                box.task.setTaskCompleted(success: true)
                bgLog.notice("app-refresh pass completed")
            }
        }
        box.task.expirationHandler = {
            bgLog.notice("app-refresh expired — cancelling pass")
            work.cancel()
            if gate.claim() {
                box.task.setTaskCompleted(success: false)
            }
        }
    }
}

// MARK: - BGContinuedProcessingTask (#14)

/// One `BGContinuedProcessingTask` wrapped around a deliberately-backgroundable
/// long send (the #38 path; a Tier-2 file download slots in here once #21's
/// app-side fetch lands). Verified constraints honored: the task is submitted
/// in the FOREGROUND from an explicit user action (tapping send), and progress
/// must keep moving — the system shows a progress UI and kills tasks whose
/// progress stalls.
@MainActor
final class ContinuedProcessingHandle {
    /// Coarse milestones across a send's lifecycle (out of 100 units).
    enum Milestone: Int64 {
        case submitted = 5
        case accepted = 25
        case streaming = 60
    }

    fileprivate var box: BGTaskBox<BGContinuedProcessingTask>?
    private var completedUnits: Int64 = Milestone.submitted.rawValue
    private var finished = false

    /// Fired when the system revokes the task (user tapped the system stop
    /// button, or the budget ran out). The stream would die on suspension
    /// anyway — callers use this to finalize partial content immediately.
    var onExpiration: (@MainActor () -> Void)?

    fileprivate func adopt(_ box: BGTaskBox<BGContinuedProcessingTask>) {
        guard !finished else {
            // The send finished before the system started the task.
            box.task.setTaskCompleted(success: true)
            return
        }
        self.box = box
        box.task.progress.totalUnitCount = 100
        box.task.progress.completedUnitCount = completedUnits
        // @Sendable for the same reason as the launch handler: the system
        // fires expiration off-main; an isolation-inheriting closure traps.
        box.task.expirationHandler = { @Sendable [weak self] in
            Task { @MainActor in
                guard let self, !self.finished else { return }
                self.finished = true
                self.onExpiration?()
                self.box?.task.setTaskCompleted(success: false)
                self.box = nil
            }
        }
    }

    func advance(to milestone: Milestone) {
        completedUnits = max(completedUnits, milestone.rawValue)
        guard !finished else { return }
        box?.task.progress.completedUnitCount = completedUnits
    }

    /// Nudges progress inside the streaming band on every delta / tool event
    /// so a long turn doesn't read as stalled. Caps at 95 — a very long tail
    /// after the cap can still be culled by the system; acceptable for a
    /// safety net whose recovery path (reconcile) exists anyway.
    func tick() {
        guard !finished else { return }
        completedUnits = min(completedUnits + 1, 95)
        box?.task.progress.completedUnitCount = completedUnits
    }

    func finish(success: Bool) {
        guard !finished else { return }
        finished = true
        if let box {
            box.task.progress.completedUnitCount = 100
            box.task.setTaskCompleted(success: success)
        }
        box = nil
    }
}

enum ContinuedProcessing {
    /// Identifier family — covered by the wildcard entry in
    /// BGTaskSchedulerPermittedIdentifiers (`org.aethyrion.talaria27.continued.*`).
    static let identifierPrefix = "org.aethyrion.talaria27.continued"

    /// Wraps one long send. Returns nil when the scheduler refuses (Simulator,
    /// system resources) — callers just proceed without background continuation.
    @MainActor
    static func beginLongSend(subtitle: String) -> ContinuedProcessingHandle? {
        let identifier = "\(identifierPrefix).send.\(UUID().uuidString.lowercased())"
        let handle = ContinuedProcessingHandle()

        // Continued-processing tasks are exempt from the register-before-
        // launch rule: register the concrete identifier just before submitting.
        // @Sendable: breaks @MainActor isolation inheritance from this
        // MainActor-isolated function — BGTaskScheduler invokes the launch
        // handler on its own queue, and an inherited-isolation closure traps
        // (dispatch_assert_queue_fail) the moment the system starts the task.
        // Everything inside is queue-safe: BGTask is documented thread-safe,
        // and handle work hops to the main actor explicitly.
        let registered = BGTaskScheduler.shared.register(
            forTaskWithIdentifier: identifier,
            using: nil
        ) { @Sendable task in
            guard let continued = task as? BGContinuedProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            let box = BGTaskBox(task: continued)
            Task { @MainActor in
                handle.adopt(box)
            }
        }
        guard registered else {
            bgLog.notice("continued-processing register refused")
            return nil
        }

        let request = BGContinuedProcessingTaskRequest(
            identifier: identifier,
            title: "Sending to Hermes",
            subtitle: subtitle
        )
        // .fail rather than .queue: a send starts immediately or not at all —
        // never a stale queued progress card.
        request.strategy = .fail
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            bgLog.notice("continued-processing submit failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        return handle
    }
}
