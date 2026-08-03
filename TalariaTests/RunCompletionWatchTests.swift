import Foundation
import Testing
@testable import Talaria

/// OPEN_ITEMS #226 — the #38 run-completion watch is a structural no-op for
/// home-screen backgrounding.
///
/// **Measured on device 2026-08-02 (running list §D4, four attempts):** background
/// the app mid-run and you get **NOTHING** (short run) or **THREE identical
/// banners** at foreground (long run). Never one banner at the right time, which
/// is the entire point of #38.
///
/// Three independent legs produce that, and each is pinned here:
/// - **(a)** the watch only arms when a `PendingRun` exists — but `PendingRun` is
///   created **only on `.interrupted`**, so at the home-screen transition (stream
///   still healthy inside iOS's background grace) the hook silently no-ops.
/// - **(b)** every completion notification carried a **fresh UUID** identifier, so
///   duplicates stack instead of replacing.
/// - **(c)** the reconcile path had no single-flight — instance 3 of **#227**.
@MainActor
struct RunCompletionWatchTests {

    // MARK: - (a) what session the background transition should watch

    /// The defect: a healthy stream at the home-screen transition has no
    /// `PendingRun`, so the old `guard let … pendingRunSessionId` returned early
    /// and NO watch was ever posted. Short runs then finish in-process and the
    /// user gets no notification at all.
    @Test func aHealthyStreamAtBackgroundingIsStillWatchable() {
        #expect(ChatStore.watchableSessionId(
            pendingRunSessionId: nil,
            isStreaming: true,
            activeSessionID: "sess-live"
        ) == "sess-live")
    }

    /// A pending run still wins — it names the session actually orphaned, and on
    /// the lock-mid-stream path it is the only correct answer.
    @Test func aPendingRunOutranksTheStreamingSession() {
        #expect(ChatStore.watchableSessionId(
            pendingRunSessionId: "sess-orphaned",
            isStreaming: true,
            activeSessionID: "sess-live"
        ) == "sess-orphaned")
    }

    /// Nothing in flight ⇒ nothing to watch. Posting a watch for an idle app
    /// would arm the relay against a run that already finished and delivered —
    /// which is the ×3 mechanism, not a fix for it.
    @Test func anIdleAppWatchesNothing() {
        #expect(ChatStore.watchableSessionId(
            pendingRunSessionId: nil,
            isStreaming: false,
            activeSessionID: "sess-live"
        ) == nil)
    }

    /// Streaming but no known server session (on-device brain, or before the hop
    /// resolves) ⇒ nothing to watch. There is no id the relay could poll.
    @Test func streamingWithoutAServerSessionWatchesNothing() {
        #expect(ChatStore.watchableSessionId(
            pendingRunSessionId: nil,
            isStreaming: true,
            activeSessionID: nil
        ) == nil)
    }

    // MARK: - (b) the notification identifier

    /// THE ×3 leg that is pure presentation: a fresh `UUID()` per notification
    /// means iOS coalesces nothing, so the relay's insta-push and the reconcile's
    /// local notify stack as separate banners for the SAME run.
    @Test func twoNotificationsForOneRunShareAnIdentifier() {
        let first = LocalNotificationService.runCompletedIdentifier(runId: "run-abc")
        let second = LocalNotificationService.runCompletedIdentifier(runId: "run-abc")
        #expect(first == second, "same run must reuse its identifier so the banner REPLACES")
    }

    @Test func differentRunsKeepDistinctIdentifiers() {
        #expect(LocalNotificationService.runCompletedIdentifier(runId: "run-abc")
                != LocalNotificationService.runCompletedIdentifier(runId: "run-def"))
    }

    /// A run with no id must not collapse every notification onto one banner —
    /// that would trade three banners for one MISSING banner, which is the same
    /// bug wearing the other sign.
    @Test func anUnknownRunFallsBackToAUniqueIdentifier() {
        let first = LocalNotificationService.runCompletedIdentifier(runId: nil)
        let second = LocalNotificationService.runCompletedIdentifier(runId: nil)
        #expect(first != second)
        #expect(first.hasPrefix("hermes.run.completed."))
    }

    // MARK: - (c) single-flight — #227 instance 3

    /// A client that parks its reconcile until released, so two callers
    /// provably OVERLAP rather than merely running in sequence. Counting calls
    /// against an instant client proves nothing: the first would finish before
    /// the second began and a store with no guard at all would pass.
    @MainActor
    final class GatedReconcileClient: HermesClientProtocol {
        private(set) var calls = 0
        private var released = false
        var isParked: Bool { calls > 0 && !released }

        func release() { released = true }

        func reconcileFromServer() async -> Conversation? {
            calls += 1
            while !released {
                try? await Task.sleep(for: .milliseconds(5))
            }
            return nil // "not finished yet" — keeps the path simple
        }

        // Unused by this test; the protocol requires them.
        var connectionStatus: ConnectionStatus = .connected
        var currentConversation: Conversation?
        func connect() async {}
        func disconnect() async {}
        func send(message: String, attachments: [PendingAttachment], clientMessageID: UUID) async -> Message {
            Message(sender: .hermes, content: "", status: .delivered)
        }
        func sendStreaming(message: String, attachments: [PendingAttachment], clientMessageID: UUID) -> AsyncStream<StreamingUpdate> {
            AsyncStream { $0.finish() }
        }
        func loadConversation() async -> Conversation { Self.empty }
        func clearConversation() async throws -> Conversation { Self.empty }

        private static var empty: Conversation {
            Conversation(title: Conversation.defaultTitle, messages: [], lastActivity: .distantPast)
        }
    }

    /// #226 leg (c). Four call sites invoke `reconcilePendingRuns()` and a
    /// foreground transition can fire more than one. Without coalescing, two
    /// concurrent reconciles both find the same pending run and both can post a
    /// completion notification — the third banner in §D4's measured ×3.
    @Test func concurrentReconcilesCoalesceOntoOneServerFetch() async {
        let suite = "reconcile-single-flight-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let client = GatedReconcileClient()
        let store = ChatStore(
            hermesClient: client,
            persistence: UserDefaultsAppPersistenceStore(defaults: defaults)
        )
        store.seedPendingRunForTesting(sessionId: "sess-1", runId: "run-1")

        let first = Task { await store.reconcilePendingRuns() }
        // Wait until the first is genuinely INSIDE the client before the second
        // arrives — otherwise this test cannot distinguish coalescing from
        // sequencing, which is the failure mode it exists to rule out.
        var spins = 0
        while !client.isParked, spins < 2_000 {
            try? await Task.sleep(for: .milliseconds(1))
            spins += 1
        }
        #expect(client.isParked, "the first reconcile never reached the client")

        let second = Task { await store.reconcilePendingRuns() }
        try? await Task.sleep(for: .milliseconds(30))

        #expect(client.calls == 1,
                "concurrent reconciles hit the server \(client.calls) times — they are not single-flighted (#227)")

        client.release()
        await first.value
        await second.value
    }
}
