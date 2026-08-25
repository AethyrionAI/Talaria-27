import Foundation
import Testing
@testable import Talaria

/// #329 — reconcile-first-then-decide (Owen's 329-C ruling, 2026-08-24).
///
/// A cold launch over an in-flight turn used to flip the restored `.sending`
/// row straight to `.failed` + Retry — a second submission of a live
/// question, measured as a duplicated answer on device (trial 1). The fix:
/// the pending run's identity persists (`PendingRunRecord`), and on cold
/// load the app consults `GET /v1/runs/{id}` BEFORE classifying. These tests
/// drive the whole path through `loadConversationIfNeeded()` against a real
/// `UserDefaultsAppPersistenceStore`, exactly as a relaunch does.
///
/// 329-A honesty note, recorded per the bar's own instruction: the DUPLICATE
/// itself (tap Retry, original answer also lands) is reproduced here only as
/// its structural negation — while recovery runs the row is never `.failed`,
/// so no Retry affordance exists to tap. The affirmative duplicate needs the
/// device (329-F).
@MainActor
struct ColdLaunchRunRecoveryTests {

    // MARK: - Harness

    private static func isolatedPersistence() -> UserDefaultsAppPersistenceStore {
        let suiteName = "cold-launch-recovery-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return UserDefaultsAppPersistenceStore(defaults: defaults)
    }

    /// Seeds the crash-shaped world: a cached conversation holding a
    /// `.sending` user row, and (optionally) the pending-run record a dying
    /// process would have left beside it.
    private static func seedCrashState(
        into persistence: UserDefaultsAppPersistenceStore,
        rowID: UUID,
        record: Bool,
        recordConversationID: UUID? = nil
    ) -> Conversation {
        let conversation = Conversation(
            title: "Hermes",
            messages: [
                Message(id: rowID, sender: .user, content: "still going?", status: .sending),
            ]
        )
        persistence.saveConversationCache(conversation)
        if record {
            persistence.savePendingRunRecord(PendingRunRecord(
                sessionId: "crash-session",
                runId: "run-crash-fixture",
                userMessageID: rowID,
                conversationID: recordConversationID ?? conversation.id,
                sentAt: Date(timeIntervalSinceNow: -30),
                partialReasoning: nil
            ))
        }
        return conversation
    }

    private static func makeStore(
        client: ColdLaunchRecoveryClient,
        persistence: UserDefaultsAppPersistenceStore
    ) -> ChatStore {
        let journal = ConversationJournalStore(persistence: persistence)
        let store = ChatStore(hermesClient: client, persistence: persistence, journal: journal)
        store.runRecoveryPollInterval = .milliseconds(20)
        store.runRecoveryWallClockBudget = .seconds(2)
        return store
    }

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

    private func userRowStatus(_ store: ChatStore, _ rowID: UUID) -> MessageStatus? {
        store.conversation?.messages.first(where: { $0.id == rowID })?.status
    }

    // MARK: - 329-A / 329-C, the alive arm

    @Test func restoredRowIsNotClassifiedFailedWhileTheRunIsAlive() async {
        let persistence = Self.isolatedPersistence()
        let rowID = UUID()
        _ = Self.seedCrashState(into: persistence, rowID: rowID, record: true)
        let client = ColdLaunchRecoveryClient(
            resolution: .answered(content: "the answer that was in flight", usage: nil),
            resolvesAfterCalls: 3
        )
        let store = Self.makeStore(client: client, persistence: persistence)

        await store.loadConversationIfNeeded()

        #expect(
            userRowStatus(store, rowID) == .working,
            "329-C: a row with a persisted run record is held, never guessed failed"
        )

        let adopted = await pollUntil {
            store.conversation?.messages.contains {
                $0.sender == .hermes && $0.content == "the answer that was in flight"
            } == true
        }
        #expect(adopted, "the existing reconcile adopts the in-flight answer")
        #expect(client.resolveCallCount >= 3, "the status read was consulted, repeatedly, until the verdict")
        #expect(userRowStatus(store, rowID) == .sent, "adoption settles the user row")
        let replies = store.conversation?.messages.filter { $0.sender == .hermes }.count
        #expect(replies == 1, "exactly one answer — the duplicate shape is structurally gone")
        #expect(persistence.loadPendingRunRecord() == nil, "a settled run clears its record")
    }

    // MARK: - 329-C, the host-said-failed arm

    @Test func hostReportedFailureClassifiesTheRowFailedHonestly() async {
        let persistence = Self.isolatedPersistence()
        let rowID = UUID()
        _ = Self.seedCrashState(into: persistence, rowID: rowID, record: true)
        let client = ColdLaunchRecoveryClient(resolution: .failed("the host's own words"))
        let store = Self.makeStore(client: client, persistence: persistence)

        await store.loadConversationIfNeeded()
        let settled = await pollUntil { self.userRowStatus(store, rowID) == .failed }

        #expect(settled, "a host-verified failure flips the row — honestly, from the verdict")
        #expect(
            store.conversation?.messages.contains {
                $0.sender == .system && $0.content == "the host's own words"
            } == true,
            "the host's failure text surfaces, as the recovery path already does"
        )
        #expect(persistence.loadPendingRunRecord() == nil, "the settled record clears")
    }

    // MARK: - 329-C, the host-forgot arm

    @Test func aRunTheHostForgotSettlesTheRowFailedWhenRecoveryConcludes() async {
        let persistence = Self.isolatedPersistence()
        let rowID = UUID()
        _ = Self.seedCrashState(into: persistence, rowID: rowID, record: true)
        let client = ColdLaunchRecoveryClient(resolution: .gone)
        let store = Self.makeStore(client: client, persistence: persistence)

        await store.loadConversationIfNeeded()
        let settled = await pollUntil { self.userRowStatus(store, rowID) == .failed }

        #expect(settled, "a 404'd run ends recovery and the row settles failed — deferred, not guessed")
        #expect(persistence.loadPendingRunRecord() == nil, "concluded recovery clears the record")
    }

    // MARK: - the unreachable-host arm (today's behavior, deferred)

    @Test func anUnreachableHostSettlesFailedOnlyAfterTheBudget() async {
        let persistence = Self.isolatedPersistence()
        let rowID = UUID()
        _ = Self.seedCrashState(into: persistence, rowID: rowID, record: true)
        let client = ColdLaunchRecoveryClient(resolution: .gone, resolvesAfterCalls: Int.max)
        let store = Self.makeStore(client: client, persistence: persistence)
        store.runRecoveryWallClockBudget = .milliseconds(200)

        await store.loadConversationIfNeeded()
        #expect(userRowStatus(store, rowID) == .working, "while the budget runs, the row is held")

        let settled = await pollUntil { self.userRowStatus(store, rowID) == .failed }
        #expect(settled, "an unanswerable host ends in today's honest terminal — failed + Retry")
        #expect(persistence.loadPendingRunRecord() == nil)
    }

    // MARK: - the no-record control (pre-fix caches)

    @Test func aSendingRowWithNoRecordStillFlipsFailedAtLoad() async {
        let persistence = Self.isolatedPersistence()
        let rowID = UUID()
        _ = Self.seedCrashState(into: persistence, rowID: rowID, record: false)
        let client = ColdLaunchRecoveryClient(resolution: .gone)
        let store = Self.makeStore(client: client, persistence: persistence)

        await store.loadConversationIfNeeded()

        #expect(
            userRowStatus(store, rowID) == .failed,
            "pre-fix caches keep today's behavior — nothing to consult, nothing pends forever"
        )
        #expect(client.resolveCallCount == 0, "no record, no status read")
    }

    // MARK: - the wrong-conversation guard (#307's corruption, refused)

    @Test func aRecordForAnotherConversationNeitherArmsNorShieldsTheRow() async {
        let persistence = Self.isolatedPersistence()
        let rowID = UUID()
        _ = Self.seedCrashState(
            into: persistence, rowID: rowID, record: true,
            recordConversationID: UUID()
        )
        let client = ColdLaunchRecoveryClient(resolution: .answered(content: "someone else's answer", usage: nil))
        let store = Self.makeStore(client: client, persistence: persistence)

        await store.loadConversationIfNeeded()

        #expect(userRowStatus(store, rowID) == .failed, "a foreign record shields nothing here")
        try? await Task.sleep(for: .milliseconds(100))
        #expect(client.resolveCallCount == 0, "and arms nothing — adoption into the wrong thread is refused")
        #expect(
            store.conversation?.messages.contains { $0.content == "someone else's answer" } != true,
            "no cross-thread adoption"
        )
    }

    // MARK: - 329-B's neighbor: the queued arm is untouched

    @Test func queuedRowScrubIsUntouchedByThePresenceOfARecord() async {
        let persistence = Self.isolatedPersistence()
        let rowID = UUID()
        var conversation = Self.seedCrashState(into: persistence, rowID: rowID, record: true)
        conversation.messages.append(
            Message(sender: .user, content: "an orphaned queued turn", status: .queued)
        )
        persistence.saveConversationCache(conversation)
        let client = ColdLaunchRecoveryClient(resolution: .answered(content: "x", usage: nil), resolvesAfterCalls: Int.max)
        let store = Self.makeStore(client: client, persistence: persistence)

        await store.loadConversationIfNeeded()

        let queuedRow = store.conversation?.messages.first { $0.content == "an orphaned queued turn" }
        #expect(queuedRow?.status == .failed, "#90's orphaned-queued scrub is not this lane's business")
        #expect(userRowStatus(store, rowID) == .working, "while the record's own row is held")
    }

    // MARK: - the record's lifecycle (arm persists, settle clears)

    @Test func armingRecoveryPersistsTheRecordAndSettlingClearsIt() async {
        let persistence = Self.isolatedPersistence()
        let rowID = UUID()
        _ = Self.seedCrashState(into: persistence, rowID: rowID, record: false)
        let client = ColdLaunchRecoveryClient(resolution: .answered(content: "settled", usage: nil))
        let store = Self.makeStore(client: client, persistence: persistence)
        await store.loadConversationIfNeeded()

        store.armPendingRunRecovery(
            placeholderID: UUID(),
            sessionId: "arm-session",
            runId: "arm-run",
            userMessageID: rowID
        )
        let record = persistence.loadPendingRunRecord()
        #expect(record?.runId == "arm-run", "arming with a run id persists the durable record")
        #expect(record?.conversationID == store.conversation?.id)

        let cleared = await pollUntil { persistence.loadPendingRunRecord() == nil }
        #expect(cleared, "settling the run clears the record — the didSet choke point, not a scattered edit")
    }
}

/// The cold-launch shape: nothing streams — the world begins at a restored
/// cache. Modeled on `RunRecoveryClient`; only the status read matters.
@MainActor
private final class ColdLaunchRecoveryClient: HermesClientProtocol {
    var connectionStatus: ConnectionStatus = .connected
    var currentConversation: Conversation?

    private let resolution: DroppedRunResolution
    private let resolvesAfterCalls: Int
    private(set) var resolveCallCount = 0

    init(resolution: DroppedRunResolution, resolvesAfterCalls: Int = 1) {
        self.resolution = resolution
        self.resolvesAfterCalls = resolvesAfterCalls
    }

    func connect() async {}
    func disconnect() async {}

    func send(message: String, attachments: [PendingAttachment] = [], clientMessageID: UUID) async -> Message {
        Message(sender: .hermes, content: "unused", status: .delivered)
    }

    func sendStreaming(message: String, attachments: [PendingAttachment] = [], clientMessageID: UUID) -> AsyncStream<StreamingUpdate> {
        AsyncStream { $0.finish() }
    }

    func loadConversation() async -> Conversation {
        currentConversation ?? Conversation(title: "Hermes")
    }

    func clearConversation() async throws -> Conversation { Conversation(title: "Hermes") }

    func resolveDroppedRun(runID: String, sessionID: String) async -> DroppedRunResolution? {
        resolveCallCount += 1
        guard resolveCallCount >= resolvesAfterCalls else { return nil }
        return resolution
    }
}
