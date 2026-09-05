import Foundation
import Testing
@testable import Talaria

/// #427 (the launch audit's A2) — **a late run-recovery verdict lands only in
/// the thread that owns it.**
///
/// The defect: `attemptRunStatusReconcile` awaits `GET /v1/runs/{id}` for
/// conversation A and then writes whatever came back into the store's LIVE
/// `conversation` — which is B, if the user opened another thread while the
/// read was in flight. `openSession` → `abandonPendingRun` cancels the
/// polling LOOP but never the single-flight pass, so the pass is
/// architecturally free to survive the walk-away and land on the arriving
/// thread.
///
/// Bars 427-A (the answer never lands in B), 427-B (B's own pending run is
/// untouched by A's verdict) and 427-C (the positive control — the gate
/// really does release and the happy path is unchanged) live here. Each
/// names the mutation that turns it red, because a test that cannot be made
/// to fail is not evidence.
@Suite("427 recovery ownership")
@MainActor
struct RecoveryOwnershipTests {

    // MARK: - 427-A

    /// **427-A.** A parked status read for thread A returns after the user has
    /// opened thread B. Nothing of A's may appear in B — not in the live
    /// transcript, not in the (single, global) conversation cache — and the
    /// superseded pass must fire no resolution of its own.
    ///
    /// Mutation: remove the post-await `recoveryStillOwned` guard from
    /// `attemptRunStatusReconcile` → `"A's late answer"` appears in B → RED.
    @Test
    func aLateAnswerForTheThreadYouLeftNeverLandsInTheThreadYouOpened() async throws {
        let client = GatedRecoveryClient()
        client.answers["run-A"] = .answered(content: "A's late answer", usage: nil)
        let store = makeStore(client: client)
        var resolved: [String] = []
        store.onRunResolved = { resolved.append($0) }

        await store.sendMessage("a question")                       // arms run-A on A
        #expect(store.pendingRunRunId == "run-A", "the fixture must arm a run-id-carrying pending run")

        let pass = Task { await store.reconcilePendingRuns() }
        await waitUntil { client.isInside("run-A") }
        #expect(client.isInside("run-A"), "the pass never parked — every assertion below is vacuous")

        await store.openSession("B")                                // the walk-away
        #expect(store.conversation?.id == client.bID,
                "the switch must be REAL (the protocol's default openSession returns A again)")
        #expect(resolved == ["A-session"], "walk-away fires onRunResolved for A exactly once")

        client.release("run-A")
        await pass.value

        #expect(store.conversation?.messages.map(\.content) == ["B's own history"])
        #expect(!(store.conversation?.messages.contains { $0.content == "A's late answer" } ?? true))
        #expect(resolved == ["A-session"], "the superseded pass fires nothing")
        let cached = try #require(store.persistence.loadConversationCache())
        #expect(!cached.messages.contains { $0.content == "A's late answer" },
                "the cache is ONE global slot — A's answer written here is A's answer persisted under B")
    }

    // MARK: - 427-B

    /// **427-B.** B has a pending run of its own by the time A's verdict
    /// arrives. A's verdict must touch none of it — and B's own recovery must
    /// still settle normally afterwards.
    ///
    /// Mutation: make `settlePendingRun` skip the token check → A's verdict
    /// clears B's pending run → RED on the still-armed assertion.
    @Test
    func aVerdictForTheDepartedThreadNeverSettlesTheArrivedThreadsOwnRun() async throws {
        let client = GatedRecoveryClient()
        client.answers["run-A"] = .answered(content: "A's late answer", usage: nil)
        client.answers["run-B"] = .answered(content: "B's answer", usage: nil)
        let store = makeStore(client: client)

        await store.sendMessage("a question")                       // arms run-A on A
        let passA = Task { await store.reconcilePendingRuns() }
        await waitUntil { client.isInside("run-A") }
        #expect(client.isInside("run-A"), "A's pass never parked — every assertion below is vacuous")

        await store.openSession("B")
        #expect(store.conversation?.id == client.bID, "the switch must be REAL")

        // B's own turn drops the same way. Its recovery is driven by B's OWN
        // reconcile loop, not a second `reconcilePendingRuns()` — the
        // single-flight would coalesce onto A's still-parked pass (that
        // cancellation is 427-D's bar, Task 2).
        client.nextRunID = "run-B"
        client.nextSessionID = "B-session"
        store.runRecoveryPollInterval = .milliseconds(10)
        await store.sendMessage("b question")
        #expect(store.pendingRunSessionId == "B-session", "B's own run is armed")
        await waitUntil { client.isInside("run-B") }
        #expect(client.isInside("run-B"), "B's loop never parked — the release below would prove nothing")

        client.release("run-A")
        await passA.value

        #expect(store.pendingRunSessionId == "B-session",
                "A's verdict must not settle B's pending run")
        #expect(store.pendingRunRunId == "run-B")
        #expect(!(store.conversation?.messages.contains { $0.content == "A's late answer" } ?? true))
        let bQuestion = store.conversation?.messages.first { $0.content == "b question" }
        #expect(bQuestion?.status == .working, "B's own turn is still awaiting its own answer")

        client.release("run-B")
        await waitUntil { store.pendingRunSessionId == nil }

        #expect(store.conversation?.messages.last?.content == "B's answer",
                "B's own recovery still lands, at B's tail")
        #expect(store.pendingRunSessionId == nil, "B settles on its own verdict")
        #expect(store.conversation?.messages.first { $0.content == "b question" }?.status == .sent)
    }

    // MARK: - 427-C

    /// **427-C — the positive control.** Nobody walks away: A's answer lands
    /// in A, at the tail, and the pending run settles. This is 3E-B's shape
    /// restated here so the gate itself is proven to release — without it a
    /// guard that refused EVERY verdict would pass 427-A and 427-B.
    ///
    /// No mutation: this is the arm that must never go red.
    @Test
    func withNoWalkAwayTheAnswerStillLandsInItsOwnThread() async throws {
        let client = GatedRecoveryClient()
        client.answers["run-A"] = .answered(content: "A's late answer", usage: nil)
        let store = makeStore(client: client)
        var resolved: [String] = []
        store.onRunResolved = { resolved.append($0) }

        await store.sendMessage("a question")
        let conversationID = store.conversation?.id
        let pass = Task { await store.reconcilePendingRuns() }
        await waitUntil { client.isInside("run-A") }
        #expect(client.isInside("run-A"), "the pass never parked — the control would prove nothing")

        client.release("run-A")
        await pass.value

        #expect(store.conversation?.id == conversationID, "the thread never changed")
        #expect(store.conversation?.messages.last?.content == "A's late answer")
        #expect(store.conversation?.messages.first { $0.content == "a question" }?.status == .sent)
        #expect(store.pendingRunSessionId == nil, "the pass settled its own run")
        #expect(resolved == ["A-session"], "settlement fires exactly one resolution")
        let cached = try #require(store.persistence.loadConversationCache())
        #expect(cached.messages.contains { $0.content == "A's late answer" })
    }

    // MARK: - Helpers

    /// Bounded pump. Every wait in this file has a ceiling: a condition that
    /// never becomes true must FAIL an explicit assertion at the call site,
    /// never hang the suite.
    private func waitUntil(limit: Int = 300, _ condition: () -> Bool) async {
        var pumps = 0
        while !condition(), pumps < limit {
            try? await Task.sleep(for: .milliseconds(10))
            pumps += 1
        }
    }

    private func makeStore(client: GatedRecoveryClient) -> ChatStore {
        let suiteName = "recovery-ownership-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = ChatStore(
            hermesClient: client,
            persistence: UserDefaultsAppPersistenceStore(defaults: defaults)
        )
        // The manually-driven pass is the only actor unless a test says
        // otherwise: a fast loop tick would park a SECOND call in the same
        // gate and the release would settle an ambiguity instead of a bar.
        store.runRecoveryPollInterval = .seconds(30)
        store.reconcilePollInterval = .seconds(30)
        return store
    }
}

/// `RunStatusRecoveryTests.RunRecoveryClient` (`:346-449`) with three
/// changes, and only three:
///
/// 1. `resolveDroppedRun` PARKS on a per-run gate the test releases, so the
///    store can be driven while a status read is genuinely in flight.
/// 2. `openSession(_:)` is implemented. **This is the fixture's founding pin
///    (Task 0, step 2):** `HermesClientProtocol`'s default is
///    `await loadConversation()`, which returns conversation A again — a
///    fixture that inherits it turns "the user opened another thread" into
///    "the user reopened the same thread" and every 427 assertion passes
///    vacuously.
/// 3. The run/session identifiers the stream commits are settable, so one
///    fixture can arm A's run and then B's.
@MainActor
private final class GatedRecoveryClient: HermesClientProtocol {
    struct Gate {
        var entered = false
        var released = false
    }

    var connectionStatus: ConnectionStatus = .connected
    var currentConversation: Conversation?

    /// Conversation B's identity — what `openSession` hands back, and what
    /// every test asserts on BEFORE releasing a gate.
    let bID = UUID()

    /// Keyed by run id, so A's read and B's read park independently.
    var gates: [String: Gate] = [:]
    var answers: [String: DroppedRunResolution] = [:]
    private(set) var resolveCalls: [String] = []

    var nextRunID = "run-A"
    var nextSessionID = "A-session"

    func isInside(_ runID: String) -> Bool {
        gates[runID]?.entered == true && gates[runID]?.released != true
    }

    func release(_ runID: String) {
        gates[runID, default: Gate()].released = true
    }

    func connect() async {}
    func disconnect() async {}

    func send(message: String, attachments: [PendingAttachment] = [], clientMessageID: UUID) async -> Message {
        Message(sender: .hermes, content: "unused", status: .delivered)
    }

    func sendStreaming(message: String, attachments: [PendingAttachment] = [], clientMessageID: UUID) -> AsyncStream<StreamingUpdate> {
        let sessionID = nextSessionID
        let runID = nextRunID
        return AsyncStream { continuation in
            Task { @MainActor in
                continuation.yield(.interrupted(sessionId: sessionID, runId: runID))
                continuation.finish()
            }
        }
    }

    func openSession(_ id: String) async throws -> Conversation {
        Conversation(
            id: bID,
            title: "B",
            messages: [Message(sender: .hermes, content: "B's own history", status: .delivered)]
        )
    }

    func loadConversation() async -> Conversation {
        currentConversation ?? Conversation(title: Conversation.defaultTitle)
    }

    func clearConversation() async throws -> Conversation {
        Conversation(title: Conversation.defaultTitle)
    }

    var currentRunIsServerRecoverable: Bool { true }

    var activeRunID: String? { nextRunID }

    /// The legacy instrument is deliberately empty here: every pending run
    /// this fixture arms carries a run id, so a call to this at all would
    /// mean the run-status leg was not taken.
    func reconcileFromServer() async -> Conversation? { nil }

    func resolveDroppedRun(runID: String, sessionID: String) async -> DroppedRunResolution? {
        resolveCalls.append(runID)
        gates[runID, default: Gate()].entered = true
        // Bounded park — 4 s ceiling. A gate the test forgets to release
        // must not hang the suite; the `isInside` assertions are what make
        // a park that ended early visible rather than silently vacuous.
        for _ in 0..<400 where gates[runID]?.released != true {
            try? await Task.sleep(for: .milliseconds(10))
        }
        return answers[runID]
    }
}
