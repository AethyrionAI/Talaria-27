import Foundation

// MARK: - The App Lock gate (#302 / #323)
//
// ONE consultable lock state, ruled 2026-08-18: "a single AppLockState every
// subsystem consults — voice start, new inference turns, approval-gated
// actions. One mechanism, one bar per consumer, so the #323 class (a
// subsystem nobody wired) becomes structurally impossible."
//
// **What was missing was never the verdict.** `AppLockStateMachine` has
// computed locked/unlocked correctly since #124 (`AppLockCore.swift`'s
// `cover(configuration:)`). What did not exist was anything OUTSIDE the cover
// window that could read it: App Lock was an opaque `UIWindow` at
// `.alert + 1` and nothing else. `scenePhase` stayed `.active`, no store
// paused, no service was gated — so `cover=locked` and "the app is active"
// were simultaneously true and only the first was visible to the user.
//
// That is not a theory. On device (build 2484, 2026-08-10) it measured as: a
// microphone hot for 34.9 s behind the cover (#302), a complete inference
// turn routed, run and committed to the transcript, and a sensor pipeline
// that collected GPS + health and tried to upload them — the uploads failing
// only because the host happened to be off (#323).
//
// This type is deliberately small and has no dependencies. It holds a Bool
// and a set of waiters; the policy lives with each consumer, and the
// controller is its only writer.

/// The lock state every non-UI subsystem consults, plus the suspension point
/// that implements defer-until-unlock.
///
/// Written by `AppLockController.refreshCover()` and nothing else. Read by
/// `TalkStore` (voice start), `ChatStore` (new inference turns) and
/// `ToolConfirmationCenter` (approvals).
///
/// **Deliberately NOT read by `PhoneQueryResponder` / `TalariaPlatformLink`.**
/// A host-driven `talaria_phone_query` keeps answering while covered, by the
/// same ruling — the agent is the owner's, and the cover hides the answer
/// from whoever is holding the phone either way. Bar 323-C is the tripwire
/// that goes red if a later lane wires it in.
@MainActor
@Observable
final class AppLockGate {

    /// True exactly while `AppLockController.cover == .locked`.
    ///
    /// **`.obscured` is NOT locked, and that distinction is load-bearing.**
    /// The app-switcher snapshot, a pulled notification shade, an incoming
    /// call and the Face ID sheet's own inactivity blip all produce
    /// `.obscured`. Gating on it would defer the user's work every time they
    /// glanced at Control Center — an availability defect traded for a
    /// privacy one. Bar 302-D pins it.
    private(set) var isLocked: Bool = false

    /// Parked callers waiting for the cover to COME UP, keyed so a cancelled
    /// wait can remove its own entry without disturbing the others.
    @ObservationIgnored
    private var unlockWaiters: [UUID: CheckedContinuation<Void, Never>] = [:]

    /// #415 — the mirror set: callers waiting for the cover to COME DOWN.
    ///
    /// **Why the gate grows a second direction rather than the consumers
    /// growing an observer.** `deferUntilUnlocked` samples `isLocked` once,
    /// at the instant of start, and a Control Center tap on a warm process
    /// clears that sample **1.2 s before App Lock arms** — so the cover comes
    /// down on top of an in-flight start and nothing re-parks it (#415, from
    /// `whoGoesThere-415.logarchive`: mic hot 272 ms and 2.4 s AFTER
    /// `locked=true`). A consumer that must react to the cover ARMING needs a
    /// suspension point, and this is the seam that already exists:
    /// `AppLockController.refreshCover()` remains the only writer, and the
    /// answer still comes from one state rather than a second observer, a
    /// notification, or a poll.
    @ObservationIgnored
    private var lockWaiters: [UUID: CheckedContinuation<Void, Never>] = [:]

    init(isLocked: Bool = false) {
        self.isLocked = isLocked
    }

    /// The controller's single publish point.
    func setLocked(_ locked: Bool) {
        guard locked != isLocked else { return }
        isLocked = locked
        // Release under a drained copy: a resumed continuation can re-enter
        // `waitUntilUnlocked()` / `waitUntilLocked()` synchronously, and
        // mutating the dictionary while iterating it would be exactly that
        // bug. Written out twice rather than through an `inout` helper for
        // the same reason — a re-entrant caller must never find an
        // exclusivity violation waiting for it.
        if locked {
            let released = lockWaiters
            lockWaiters.removeAll()
            for continuation in released.values {
                continuation.resume()
            }
        } else {
            let released = unlockWaiters
            unlockWaiters.removeAll()
            for continuation in released.values {
                continuation.resume()
            }
        }
    }

    /// Suspends until the cover is no longer `.locked`. Returns immediately
    /// when already unlocked, so every call site can await unconditionally
    /// and the unlocked path costs nothing (bars 302-G / 323-E).
    ///
    /// **Cancellation is honoured**, and not as a nicety: a non-cancellable
    /// await is how a parked caller becomes a stranded waiter that outlives
    /// the reason it was waiting. A cancelled wait resumes immediately — it
    /// does NOT throw — so callers keep their existing control flow and
    /// re-check their own generation counter afterwards, which is what
    /// `TalkStore` already does for #139.
    func waitUntilUnlocked() async {
        guard isLocked else { return }
        let id = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                // Re-check inside the body. Two races close here: the gate
                // may have unlocked between the `guard` above and this
                // closure, and the task may already have been cancelled
                // before `withTaskCancellationHandler` ran its operation —
                // in which case `onCancel` fires with nothing registered and
                // would leave this caller parked forever.
                guard isLocked, !Task.isCancelled else {
                    continuation.resume()
                    return
                }
                unlockWaiters[id] = continuation
            }
        } onCancel: {
            // `onCancel` is nonisolated, so the removal hops back. By then
            // the body above has already run to completion (same actor, no
            // suspension between them), so the entry is either registered —
            // and removed and resumed here — or the caller already resumed
            // itself through the guard.
            Task { @MainActor [weak self] in
                self?.unlockWaiters.removeValue(forKey: id)?.resume()
            }
        }
    }

    /// #415 — suspends until the cover BECOMES `.locked`. The exact mirror of
    /// `waitUntilUnlocked()`, cancellation included, and for the same reason:
    /// a cover watch that could not be cancelled would outlive the voice
    /// session it was armed for and park — then resume — a session the user
    /// ended minutes ago.
    ///
    /// Returns immediately when the cover is already down, so a caller that
    /// arms a watch on an already-locked app is not silently never-armed.
    func waitUntilLocked() async {
        guard !isLocked else { return }
        let id = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                guard !isLocked, !Task.isCancelled else {
                    continuation.resume()
                    return
                }
                lockWaiters[id] = continuation
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.lockWaiters.removeValue(forKey: id)?.resume()
            }
        }
    }

    #if DEBUG
    /// Test-only visibility. Bars 302-F and 323-A both need to distinguish
    /// "parked" from "returned without running", which is unobservable from
    /// the outside — a caller that never started and a caller still waiting
    /// look identical at the call site.
    ///
    /// **Counts UNLOCK waiters only, and that is deliberate** (#415): the
    /// bars written against it — 302-E's park, 302-G's `== 0` negative
    /// control — mean "parked behind the cover", and a cover watch armed on
    /// an unlocked app would silently change every one of their answers.
    var parkedWaiterCount: Int { unlockWaiters.count }

    /// #415 — armed cover watches. Separate from `parkedWaiterCount` so a
    /// leaked watch is measurable without redefining what "parked" means.
    var armedCoverWatchCount: Int { lockWaiters.count }
    #endif
}

/// Whether a send defers behind App Lock, or is one of the ruling's named
/// exemptions (#323-B).
///
/// A default-deny enum rather than a `Bool` flag: a new call site gets the
/// gate by writing nothing, and an exemption has to be spelled out at the
/// call site where a reader will see it. That asymmetry is the point — the
/// #323 class is "a subsystem nobody wired", and the cure is that wiring is
/// what you get for free.
enum AppLockSendPolicy: Equatable, Sendable {
    /// Everything by default: the turn waits until the cover comes down.
    case deferWhileLocked
    /// #124's recorded decision, preserved deliberately: App Intents (Ask
    /// Hermes from Siri/Shortcuts) BYPASS this lock. The intent path has no
    /// UI, so a locked phone can still ask Hermes headlessly, exactly like a
    /// lock-screen Siri query — the same principle the 2026-08-18 ruling
    /// applies to `talaria_phone_query`.
    ///
    /// **Not a loophole, a ruling with a test.** Bar 323-B pins it, so a
    /// later lane that "simplifies away" this parameter goes red instead of
    /// silently reversing #124.
    case bypassLock
}
