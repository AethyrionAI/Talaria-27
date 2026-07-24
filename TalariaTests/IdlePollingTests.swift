import Foundation
import Testing
@testable import Talaria

/// #175 — idle chattiness. A wire capture on 2026-07-23 logged, inside roughly
/// a minute of an open and otherwise idle app, six `GET /v1/models` and three
/// `GET /api/sessions?limit=50&order=recent&min_messages=1`.
///
/// Those two counts had two DIFFERENT mechanisms, which is why the fix is in
/// two places:
///
/// - **Six `/v1/models` = a deliberate timer.** `ChatScreen.monitorConnectionStatus()`
///   slept a flat 10 s and called `ChatStore.refreshDirectHealth()`, whose
///   `connect()` probe IS the `/v1/models` GET. Six ticks a minute, six
///   requests — the arithmetic is exact.
/// - **Three `/api/sessions` = no timer at all.** Nothing polls that endpoint.
///   Every fetch is a view appearing — the chat seams on appear, the
///   persistent sidebar on mount, settings screens wanting a count — and none
///   of them knew about the others. A missing shared cache, not a cadence.
struct IdlePollingTests {

    // MARK: The timer half

    @Test func healthProbeRelaxesOnceTheStatusHolds() {
        // The capture's cadence: still the responsive one while things move.
        #expect(ChatHealthPollPolicy.interval(consecutiveUnchangedProbes: 0) == 10)
        #expect(ChatHealthPollPolicy.interval(consecutiveUnchangedProbes: 2) == 10)

        // …and relaxed once it has held. 6 requests/minute → 2.
        #expect(ChatHealthPollPolicy.interval(consecutiveUnchangedProbes: 3) == 30)
        #expect(ChatHealthPollPolicy.interval(consecutiveUnchangedProbes: 99) == 30)
    }

    @Test func aBurstOfSteadyProbesCostsFarFewerRequestsPerMinute() {
        // Replays a minute of idle through the policy exactly as the loop
        // consumes it, and counts the requests it would have made.
        func requestsInOneMinute() -> Int {
            var elapsed: TimeInterval = 0
            var unchanged = 0
            var requests = 0
            while true {
                elapsed += ChatHealthPollPolicy.interval(consecutiveUnchangedProbes: unchanged)
                if elapsed > 60 { break }
                requests += 1
                unchanged += 1  // idle: the status never moves
            }
            return requests
        }
        // The capture measured six. Anything at or above that is no fix.
        #expect(requestsInOneMinute() < 6)
    }

    @Test func probingIsForegroundOnly() {
        // A `.task` is not cancelled by backgrounding — the view never
        // disappears — so without this the loop kept firing until iOS
        // suspended the process.
        #expect(ChatHealthPollPolicy.shouldProbe(scenePhase: .active))
        #expect(!ChatHealthPollPolicy.shouldProbe(scenePhase: .inactive))
        #expect(!ChatHealthPollPolicy.shouldProbe(scenePhase: .background))
    }

    // MARK: The no-shared-cache half

    private struct StubError: Error {}

    @MainActor
    private final class CountingSessionClient: HermesClientProtocol {
        var connectionStatus: ConnectionStatus = .connected
        var currentConversation: Conversation?
        var listSessionsCalls = 0
        var sessions: [HermesSessionInfo] = []
        var shouldThrow = false

        func connect() async {}
        func disconnect() async {}
        func send(message: String, attachments: [PendingAttachment], clientMessageID: UUID) async -> Message {
            Message(sender: .hermes, content: "ok", status: .delivered)
        }
        func sendStreaming(
            message: String,
            attachments: [PendingAttachment],
            clientMessageID: UUID
        ) -> AsyncStream<StreamingUpdate> {
            AsyncStream { $0.finish() }
        }
        func loadConversation() async -> Conversation { Conversation(title: "Hermes") }
        func clearConversation() async throws -> Conversation { Conversation(title: "Hermes") }
        func listSessions() async throws -> [HermesSessionInfo] {
            listSessionsCalls += 1
            if shouldThrow { throw StubError() }
            return sessions
        }
    }

    @MainActor private func makePersistence(_ label: String) -> UserDefaultsAppPersistenceStore {
        let suiteName = "idle-polling-\(label)-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return UserDefaultsAppPersistenceStore(defaults: defaults)
    }

    private static func info(id: String) -> HermesSessionInfo {
        HermesSessionInfo(
            id: id, title: nil, preview: nil, model: nil, source: nil,
            messageCount: 0, lastActive: nil, isActive: false
        )
    }

    @Test @MainActor
    func independentAppearancesCoalesceOntoOneFetch() async {
        let client = CountingSessionClient()
        client.sessions = [Self.info(id: "api_1")]
        let store = ChatStore(hermesClient: client, persistence: makePersistence("idle-poll-coalesce"))

        // Three views appearing around launch — the capture's exact count.
        let a = await store.loadSessions()
        let b = await store.loadSessions()
        let c = await store.loadSessions()

        #expect(client.listSessionsCalls == 1)
        // …and every caller still gets the real list, not an empty placeholder.
        #expect(a.map(\.id) == ["api_1"])
        #expect(b.map(\.id) == ["api_1"])
        #expect(c.map(\.id) == ["api_1"])
    }

    @Test @MainActor
    func aChangedListStillFetchesForReal() async {
        let client = CountingSessionClient()
        client.sessions = [Self.info(id: "api_1")]
        let store = ChatStore(hermesClient: client, persistence: makePersistence("idle-poll-force"))

        _ = await store.loadSessions()
        #expect(client.listSessionsCalls == 1)

        // Opening / clearing / starting a session changes the list server-side.
        // Serving those from the snapshot would be a stale count, not a saved
        // request.
        client.sessions = [Self.info(id: "api_1"), Self.info(id: "api_2")]
        let fresh = await store.loadSessions(force: true)
        #expect(client.listSessionsCalls == 2)
        #expect(fresh.map(\.id) == ["api_1", "api_2"])
    }

    @Test @MainActor
    func aFailedFetchDoesNotPoisonTheSnapshotWindow() async {
        let client = CountingSessionClient()
        client.shouldThrow = true
        let store = ChatStore(hermesClient: client, persistence: makePersistence("idle-poll-failure"))

        #expect(await store.loadSessions().isEmpty)
        #expect(client.listSessionsCalls == 1)

        // A throw records nothing, so the next appearance genuinely retries
        // rather than being told to wait out a TTL that was never earned.
        client.shouldThrow = false
        client.sessions = [Self.info(id: "api_1")]
        #expect(await store.loadSessions().map(\.id) == ["api_1"])
        #expect(client.listSessionsCalls == 2)
    }
}
