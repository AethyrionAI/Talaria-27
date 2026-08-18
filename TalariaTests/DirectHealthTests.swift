import Foundation
import Testing
@testable import Talaria

/// #361 bars 361-A/B/C — the offline banner's inputs stay honest: a turn's
/// terminal is connectivity EVIDENCE (both directions), and the direct-health
/// probe is never starved behind a hanging host/relay sweep.
struct DirectHealthTests {

    @MainActor private static func makePersistence() -> UserDefaultsAppPersistenceStore {
        let suiteName = "direct-health-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return UserDefaultsAppPersistenceStore(defaults: defaults)
    }

    /// The house manual-drive client: `connectionStatus` is scripted, and —
    /// mirroring the real client, which writes `.connected`/`.error` from
    /// its own traffic — the test flips it before yielding a terminal.
    @MainActor
    private final class HealthManualClient: HermesClientProtocol {
        var connectionStatus: ConnectionStatus = .disconnected
        var currentConversation: Conversation?
        var currentRunIsServerRecoverable = true
        private(set) var continuations: [AsyncStream<StreamingUpdate>.Continuation] = []

        func connect() async {}
        func disconnect() async {}

        func send(message: String, attachments: [PendingAttachment], clientMessageID: UUID) async -> Message {
            Message(sender: .hermes, content: "unused", status: .delivered)
        }

        func sendStreaming(
            message: String,
            attachments: [PendingAttachment],
            clientMessageID: UUID
        ) -> AsyncStream<StreamingUpdate> {
            AsyncStream { continuation in
                continuation.yield(.messageSent(jobID: UUID()))
                self.continuations.append(continuation)
            }
        }

        func loadConversation() async -> Conversation {
            currentConversation ?? Conversation(title: Conversation.defaultTitle)
        }

        func clearConversation() async throws -> Conversation {
            Conversation(title: Conversation.defaultTitle)
        }

        func reconcileFromServer() async -> Conversation? { nil }
    }

    @MainActor
    private func pollUntil(
        timeout: Duration = .seconds(5),
        _ condition: @MainActor () -> Bool
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while clock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    // MARK: - 361-A: a completed turn corrects a stale .error snapshot

    @Test @MainActor
    func completedTurnFlipsAStaleErrorSnapshotToConnected() async throws {
        let client = HealthManualClient()
        let store = ChatStore(hermesClient: client, persistence: Self.makePersistence())

        // Seed the stale snapshot the device showed: one failed probe.
        client.connectionStatus = .error
        await store.refreshDirectHealth()
        #expect(store.directConnectionStatus == .error)

        // A real turn then streams and completes — the client (like the real
        // one) has marked its own status connected from the traffic.
        let sendTask = Task { @MainActor in await store.sendMessage("hello") }
        let live = await pollUntil { !client.continuations.isEmpty }
        #expect(live)
        let stream = try #require(client.continuations.last)
        client.connectionStatus = .connected
        stream.yield(.finished(Message(sender: .hermes, content: "hi", status: .delivered), nil, nil))
        stream.finish()
        _ = await sendTask.value

        #expect(store.directConnectionStatus == .connected,
                "the terminal is connectivity evidence — no probe should be needed (#361-A)")
    }

    // MARK: - 361-C: a failed turn is evidence in the other direction

    @Test @MainActor
    func failedTurnFlipsAStaleConnectedSnapshotToError() async throws {
        let client = HealthManualClient()
        let store = ChatStore(hermesClient: client, persistence: Self.makePersistence())

        client.connectionStatus = .connected
        await store.refreshDirectHealth()
        #expect(store.directConnectionStatus == .connected)

        let sendTask = Task { @MainActor in await store.sendMessage("hello") }
        let live = await pollUntil { !client.continuations.isEmpty }
        #expect(live)
        let stream = try #require(client.continuations.last)
        client.connectionStatus = .error
        stream.yield(.failed("host fell over"))
        stream.finish()
        _ = await sendTask.value

        #expect(store.directConnectionStatus == .error,
                "traffic can take the banner offline too — not only the probe (#361-C)")
    }

    // MARK: - 361-B: the tick's direct half is never starved by the sweep

    /// A hang the TEST can release — a leaked continuation strands the
    /// ticker's internal task and wedges the whole test host at exit (the
    /// settle-box rule: never arm a wait you cannot resolve).
    @MainActor
    private final class ReleasableHang {
        private var continuations: [CheckedContinuation<Void, Never>] = []
        private(set) var waiterCount = 0
        func wait() async {
            waiterCount += 1
            await withCheckedContinuation { continuations.append($0) }
        }
        func release() {
            for continuation in continuations { continuation.resume() }
            continuations.removeAll()
        }
    }

    @Test @MainActor
    func directHealthCompletesWhileHostRefreshHangs() async {
        let ticker = ChatHealthTicker()
        let hang = ReleasableHang()
        var directRan = false
        let tickDone = Task { @MainActor in
            await ticker.tick(
                hostRefresh: { await hang.wait() },
                directRefresh: { directRan = true }
            )
        }
        let finished = await pollUntil { directRan }
        #expect(finished, "the direct probe must not wait on the sweep (#361-B)")
        _ = await tickDone.value
        hang.release()
    }

    @Test @MainActor
    func hangingHostRefreshDoesNotPileUp() async {
        let ticker = ChatHealthTicker()
        let hang = ReleasableHang()
        await ticker.tick(hostRefresh: { await hang.wait() }, directRefresh: {})
        await ticker.tick(hostRefresh: { await hang.wait() }, directRefresh: {})
        await ticker.tick(hostRefresh: { await hang.wait() }, directRefresh: {})
        let started = await pollUntil { hang.waiterCount >= 1 }
        #expect(started)
        #expect(hang.waiterCount == 1, "single-flight: a hanging sweep must not stack copies of itself (#361-B)")
        hang.release()
    }
}
