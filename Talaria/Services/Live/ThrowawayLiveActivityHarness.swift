#if DEBUG
import ActivityKit
import Foundation

/// **#250 R2 — the Debug-only, on-demand Live Activity trigger.**
///
/// Device row §R2 (*the Dynamic Island wears the selected icon*) sat as a
/// standing watch for days because the island is untriggerable on demand —
/// Owen's own words: he cannot consistently bring it up in real use. This
/// starts a **throwaway instance of the REAL activity** so R2 becomes a
/// two-minute check.
///
/// Two properties are load-bearing, and both are bars:
///
/// 1. **It drives the production `LiveActivityService`** — the same
///    `startToolCall` / `updateToolProgress` / `endActivity` entry points, the
///    same `HermesActivityAttributes`, the same `Activity.request`. It does
///    **not** go through `LiveActivityPreviews`' SwiftUI scaffolding and it does
///    **not** build a parallel mock attributes type: R2's question is what the
///    *real* activity renders in the island's leading icon slot, so a harness
///    that renders anything else answers a different question (250T-B).
/// 2. **It ends itself.** Live Activities draw on a system budget; a leaked
///    throwaway would make the REAL run activity flaky, and that failure would
///    read as a #250 regression while being the harness's fault. The auto-end
///    is therefore not polish. It ends on a second tap *and* on a timeout,
///    whichever comes first, and the timeout deliberately outlives the
///    Developer screen — which is why the app-lifetime `shared` instance exists
///    rather than a `@State` on the view.
///
/// The content is labelled so it can never be mistaken for a real run.
@MainActor
@Observable
final class ThrowawayLiveActivityHarness {

    /// App-lifetime owner. The auto-end must survive the Developer screen being
    /// dismissed — a view-owned harness would drop its timer on `deinit` and
    /// leak exactly the activity this type exists to avoid leaking.
    static let shared = ThrowawayLiveActivityHarness()

    /// Deliberately unmistakable in the island, on the Lock Screen, and in any
    /// screenshot that leaves the device.
    static let toolLabel = "#250 R2 THROWAWAY"
    static let statusLabel = "THROWAWAY — not a real run"

    /// Why a throwaway ended. Both routes are asserted by 250T-B.
    enum EndReason: String, Sendable {
        /// The user tapped the button a second time ("End throwaway").
        case secondTap
        /// The auto-end window elapsed — the budget guard.
        case timeout
    }

    /// The production service, not a double. `internal` so the bar can reach
    /// `hasActiveActivity` through it.
    let service: LiveActivityService

    /// How long a throwaway may live before it ends itself.
    let autoEndAfter: Duration

    private(set) var isRunning = false
    private(set) var endCount = 0
    private(set) var lastEndReason: EndReason?

    private var autoEndTask: Task<Void, Never>?

    init(service: LiveActivityService = LiveActivityService(),
         autoEndAfter: Duration = .seconds(60)) {
        self.service = service
        self.autoEndAfter = autoEndAfter
    }

    /// What the button does: first tap starts, second tap ends.
    func toggle() {
        if isRunning {
            end(.secondTap)
        } else {
            start()
        }
    }

    /// Starts a throwaway through the production path and arms the auto-end.
    ///
    /// Re-entrant taps are ignored rather than stacking activities — two
    /// requests would leave the first one un-tracked and therefore un-endable
    /// by `endActivity()`'s handle, which is the leak shape this guards.
    func start() {
        guard !isRunning else { return }
        isRunning = true

        // PRODUCTION ENTRY POINTS. Do not inline `Activity.request` here: if the
        // harness builds its own activity, 250T-B stops proving anything about
        // what a real run puts in the island.
        service.startToolCall(toolName: Self.toolLabel)
        service.updateToolProgress(Self.statusLabel, toolName: Self.toolLabel)

        autoEndTask?.cancel()
        autoEndTask = Task { [autoEndAfter] in
            try? await Task.sleep(for: autoEndAfter)
            guard !Task.isCancelled else { return }
            self.end(.timeout)
        }
    }

    /// Ends the throwaway and disarms the auto-end. Safe to call when nothing
    /// is running (the second tap and the timeout race each other by design).
    func end(_ reason: EndReason) {
        autoEndTask?.cancel()
        autoEndTask = nil
        guard isRunning else { return }
        isRunning = false
        endCount += 1
        lastEndReason = reason
        service.endActivity()
    }
}
#endif
