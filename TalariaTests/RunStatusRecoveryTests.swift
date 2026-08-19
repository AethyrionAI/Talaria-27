import Foundation
import Testing
@testable import Talaria

/// #368 (Phase 3 slice 3E) — the recovery collapse.
///
/// Bars 3E-B (the collapse itself, with two negative controls the OLD
/// machinery fails), 3E-C (durability past the legacy 120 s budget) and
/// 3E-D (exactly once) live here. Each test names the mutation that turns
/// it red, because a test that cannot be made to fail is not evidence.
@Suite("Run-status recovery (#368 / 3E)")
struct RunStatusRecoveryTests {

    // MARK: - The pure mapper (verdicts, no network)

    @Test
    func completedWithTextIsAnAnswerCarryingItsOwnUsage() throws {
        let body = Data("""
        {"status":"completed","output":"the run's own words",
         "usage":{"input_tokens":11,"output_tokens":7,"total_tokens":18}}
        """.utf8)
        let snapshot = try #require(SessionsHermesClient.RunStatusSnapshot(body))
        guard case .answered(let content, let usage) =
            SessionsHermesClient.resolution(from: snapshot) else {
            Issue.record("a completed run carrying text must resolve as .answered")
            return
        }
        #expect(content == "the run's own words")
        #expect(usage?.totalTokens == 18)
    }

    @Test
    func completedWithNoTextIsNotAnEmptyAnswer() throws {
        // #235 F1 reused rather than restated: a terminal status carrying no
        // answer must never paint an empty bubble. Mutation: return
        // `.answered(content: output, ...)` unconditionally — this goes red.
        for body in [#"{"status":"completed","output":""}"#,
                     #"{"status":"completed","output":"   \n "}"#,
                     #"{"status":"completed"}"#] {
            let snapshot = try #require(SessionsHermesClient.RunStatusSnapshot(Data(body.utf8)))
            #expect(SessionsHermesClient.resolution(from: snapshot) == .endedWithoutAnswer,
                    "\(body) must not resolve as an answer")
        }
    }

    @Test
    func failedCarriesTheHostsOwnWordsAndInventsNoneOfItsOwn() throws {
        let stringy = try #require(SessionsHermesClient.RunStatusSnapshot(
            Data(#"{"status":"failed","error":"provider refused the request"}"#.utf8)))
        guard case .failed(let text) = SessionsHermesClient.resolution(from: stringy) else {
            Issue.record("a failed run must resolve as .failed"); return
        }
        #expect(text.contains("provider refused the request"))

        // 296-C1: the wire's `error` is a UNION, and a bare `true` carries
        // exactly one bit. The mapper must report that bit, never invent a
        // reason for it.
        let boolean = try #require(SessionsHermesClient.RunStatusSnapshot(
            Data(#"{"status":"failed","error":true}"#.utf8)))
        guard case .failed(let bareText) = SessionsHermesClient.resolution(from: boolean) else {
            Issue.record("a failed run with a boolean error must still resolve as .failed"); return
        }
        #expect(!bareText.isEmpty)
    }

    @Test
    func everyOtherTerminalStatusEndsWithoutAnAnswer() throws {
        for status in ["cancelled", "stopped", "some_future_terminal_name"] {
            let snapshot = try #require(SessionsHermesClient.RunStatusSnapshot(
                Data(#"{"status":"\#(status)"}"#.utf8)))
            #expect(SessionsHermesClient.resolution(from: snapshot) == .endedWithoutAnswer)
        }
    }

    // MARK: - 3E-B: the collapse, with the two controls the old path fails

    @Test @MainActor
    func droppedRunResolvesFromItsOwnStatusAndNeverReReadsTheSession() async throws {
        // Bar 3E-B. The client offers BOTH instruments; the store must reach
        // for the run-status one and leave the session re-read untouched.
        //
        // Negative control (i) is baked into the fixture: the session list
        // this client would return carries a NEWER, UNRELATED hermes row.
        // The legacy positional filter ("newest hermes row after sentAt")
        // adopts exactly that row — so if the fork ever regresses, the
        // adopted content changes and this goes red on the content assertion
        // as well as the call-count one.
        let client = RunRecoveryClient(
            resolution: .answered(
                content: "the run's own answer",
                usage: TokenUsage(promptTokens: 30, completionTokens: 12, totalTokens: 42)
            )
        )
        let store = makeStore(client: client)

        await store.sendMessage("do the thing")
        await store.reconcilePendingRuns()

        #expect(client.resolveCallCount == 1)
        #expect(client.reconcileFromServerCallCount == 0,
                "3E-B: a run WITH an id must never fall back to the positional session re-read")
        let reply = try #require(store.conversation?.messages.last)
        #expect(reply.sender == .hermes)
        #expect(reply.content == "the run's own answer")
        #expect(reply.usage?.totalTokens == 42)
        #expect(store.lastTokenUsage?.totalTokens == 42)
        #expect(store.pendingRunSessionId == nil)

        // The prompt stops being "working" the moment its answer lands.
        let prompt = try #require(store.conversation?.messages.first(where: { $0.sender == .user }))
        #expect(prompt.status != .working)
    }

    @Test @MainActor
    func aHostClockBehindTheClientStillResolves() async throws {
        // Bar 3E-B, negative control (ii) — the #293(b) skew shape. The
        // legacy filter compares a CLIENT `sentAt` with strict `>` against
        // HOST timestamps, so a phone running ahead of its host can never
        // match; the run-status path has no timestamp predicate at all.
        //
        // The fixture makes the skew extreme on purpose: every hermes row
        // the session re-read could offer is stamped an hour in the PAST.
        let client = RunRecoveryClient(
            resolution: .answered(content: "resolved despite the skew", usage: nil),
            sessionRowTimestamp: Date(timeIntervalSinceNow: -3600)
        )
        let store = makeStore(client: client)

        await store.sendMessage("do the thing")
        await store.reconcilePendingRuns()

        #expect(store.conversation?.messages.last?.content == "resolved despite the skew")
        #expect(store.pendingRunSessionId == nil)
    }

    // MARK: - 3E-C: durability past the legacy budget

    @Test @MainActor
    func theRunIdLoopUsesItsOwnBudgetNotTheLegacyOne() async throws {
        // Bar 3E-C. Scaled, not slept: the legacy budget is set far SHORTER
        // than the run-recovery one, and the run goes terminal after enough
        // passes that only the longer budget can still be running.
        //
        // Mutation that turns this red: have `startReconcileLoopIfNeeded`
        // read `reconcileWallClockBudget` unconditionally again — the loop
        // then retires before pass 20 and nothing is ever adopted.
        let client = RunRecoveryClient(
            resolution: .answered(content: "late but adopted", usage: nil),
            resolvesAfterCalls: 20
        )
        let store = makeStore(client: client)
        store.reconcileWallClockBudget = .milliseconds(30)
        store.reconcilePollInterval = .milliseconds(5)
        store.runRecoveryWallClockBudget = .seconds(5)
        store.runRecoveryPollInterval = .milliseconds(5)

        await store.sendMessage("a long tool-using turn")
        await store.reconcilePendingRuns()

        var pumps = 0
        while store.hasActiveReconcileLoop, pumps < 400 {
            try? await Task.sleep(for: .milliseconds(10))
            pumps += 1
        }
        #expect(store.hasActiveReconcileLoop == false, "the loop never retired")
        #expect(client.resolveCallCount >= 20)
        #expect(store.conversation?.messages.last?.content == "late but adopted")
    }

    @Test @MainActor
    func aRunTheHostHasForgottenRetiresTheLoopInsteadOfGrindingItsBudget() async throws {
        // `.gone` is a verdict, not a "not yet" — polling on would be #145's
        // shape wearing a new face. Mutation: map `.gone` to `.keepPolling`
        // and the loop runs its full budget, making `resolveCallCount` climb
        // past 1 and `hasActiveReconcileLoop` stay true here.
        let client = RunRecoveryClient(resolution: .gone)
        let store = makeStore(client: client)
        // A budget the loop could burn hundreds of reads inside, if it kept
        // polling: 5s at 5ms is ~1000 passes.
        store.runRecoveryWallClockBudget = .seconds(5)
        store.runRecoveryPollInterval = .milliseconds(5)

        await store.sendMessage("do the thing")
        await store.reconcilePendingRuns()
        await pumpUntilLoopRetires(store)

        #expect(store.hasActiveReconcileLoop == false, "the loop never retired")
        #expect(client.resolveCallCount <= 3,
                "a 404'd run must stop the loop, not grind its budget — got \(client.resolveCallCount) reads")
    }

    // MARK: - 3E-D: exactly once

    @Test @MainActor
    func asecondPassOverTheSameTerminalStatusAddsNoSecondRow() async throws {
        // Bar 3E-D. Identity is derived from the run id, so a racing second
        // pass computes the same UUID and finds the row already there.
        // Mutation: mint a fresh `UUID()` for the adopted reply — the second
        // pass then appends a duplicate and this goes red.
        let client = RunRecoveryClient(
            resolution: .answered(content: "adopted once", usage: nil)
        )
        let store = makeStore(client: client)

        await store.sendMessage("do the thing")
        await store.reconcilePendingRuns()
        let afterFirst = store.conversation?.messages.count ?? 0

        // Re-arm the SAME run and resolve it again — the shape a late
        // duplicate `.interrupted` plus a foreground pass produces.
        let prompt = try #require(store.conversation?.messages.first(where: { $0.sender == .user }))
        store.armPendingRunRecovery(
            placeholderID: UUID(),
            sessionId: "probe-session",
            runId: RunRecoveryClient.runID,
            userMessageID: prompt.id
        )
        await store.reconcilePendingRuns()

        #expect(store.conversation?.messages.count == afterFirst,
                "3E-D: the same run resolving twice must not add a second reply")
        #expect(store.conversation?.messages.filter { $0.content == "adopted once" }.count == 1)
    }

    @Test @MainActor
    func aFailedRunSurfacesTheHostsWordsRatherThanPollingOnInSilence() async throws {
        let client = RunRecoveryClient(resolution: .failed("The Hermes run failed."))
        let store = makeStore(client: client)
        // Scaled so the loop's own tick lands inside the pump window — the
        // manual pass resolves first, and the loop retires on its next tick
        // when it finds no pending run (the same posture the legacy path
        // has always had; 3E does not change it).
        store.runRecoveryPollInterval = .milliseconds(5)
        store.runRecoveryWallClockBudget = .seconds(5)

        await store.sendMessage("do the thing")
        await store.reconcilePendingRuns()
        await pumpUntilLoopRetires(store)

        let last = try #require(store.conversation?.messages.last)
        #expect(last.sender == .system)
        #expect(last.content == "The Hermes run failed.")
        #expect(store.pendingRunSessionId == nil)
        #expect(store.hasActiveReconcileLoop == false)
    }

    @Test @MainActor
    func aRunThatEndedWithNothingToShowClaimsNothing() async throws {
        let client = RunRecoveryClient(resolution: .endedWithoutAnswer)
        let store = makeStore(client: client)
        store.runRecoveryPollInterval = .milliseconds(5)
        store.runRecoveryWallClockBudget = .seconds(5)

        await store.sendMessage("do the thing")
        let before = store.conversation?.messages.count ?? 0
        await store.reconcilePendingRuns()
        await pumpUntilLoopRetires(store)

        #expect(store.conversation?.messages.count == before,
                "a cancelled/stopped run must add no row at all")
        #expect(store.pendingRunSessionId == nil)
        #expect(store.hasActiveReconcileLoop == false)
    }

    // MARK: - Fixtures

    /// The `.interrupted` arm arms the reconcile loop before any manual pass
    /// runs, so a loop that has ALREADY resolved is still alive until its
    /// next tick notices. Pump rather than assert on a stopwatch (#183's
    /// territory) — the bar is "it retires", not "it retires by frame N".
    @MainActor
    private func pumpUntilLoopRetires(_ store: ChatStore, limit: Int = 200) async {
        var pumps = 0
        while store.hasActiveReconcileLoop, pumps < limit {
            try? await Task.sleep(for: .milliseconds(10))
            pumps += 1
        }
    }

    @MainActor
    private func makeStore(client: RunRecoveryClient) -> ChatStore {
        let suiteName = "run-status-recovery-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return ChatStore(
            hermesClient: client,
            persistence: UserDefaultsAppPersistenceStore(defaults: defaults)
        )
    }
}

/// A client whose streamed turn commits a run and then drops — the exact
/// `.interrupted(sessionId:runId:)` shape the runs driver yields — and which
/// offers BOTH recovery instruments so a test can prove which one was used.
@MainActor
private final class RunRecoveryClient: HermesClientProtocol {
    static let runID = "run_3e_fixture"

    var connectionStatus: ConnectionStatus = .connected
    var currentConversation: Conversation?

    private let resolution: DroppedRunResolution
    /// How many `resolveDroppedRun` calls return nil before the verdict lands.
    private let resolvesAfterCalls: Int
    private let sessionRowTimestamp: Date

    private(set) var resolveCallCount = 0
    private(set) var reconcileFromServerCallCount = 0

    private let userID = UUID()

    init(
        resolution: DroppedRunResolution,
        resolvesAfterCalls: Int = 1,
        sessionRowTimestamp: Date = .now
    ) {
        self.resolution = resolution
        self.resolvesAfterCalls = resolvesAfterCalls
        self.sessionRowTimestamp = sessionRowTimestamp
    }

    func connect() async {}
    func disconnect() async {}

    func send(message: String, attachments: [PendingAttachment] = [], clientMessageID: UUID) async -> Message {
        Message(sender: .hermes, content: "unused", status: .delivered)
    }

    func sendStreaming(message: String, attachments: [PendingAttachment] = [], clientMessageID: UUID) -> AsyncStream<StreamingUpdate> {
        currentConversation = Conversation(
            title: "Hermes",
            messages: [
                Message(id: userID, clientMessageID: clientMessageID, sender: .user, content: message, status: .sent),
            ]
        )
        return AsyncStream { continuation in
            Task { @MainActor in
                continuation.yield(.interrupted(sessionId: "probe-session", runId: Self.runID))
                continuation.finish()
            }
        }
    }

    func loadConversation() async -> Conversation {
        currentConversation ?? Conversation(title: "Hermes")
    }

    func clearConversation() async throws -> Conversation { Conversation(title: "Hermes") }

    var currentRunIsServerRecoverable: Bool { true }

    /// The legacy instrument. Deliberately offers a TEMPTING candidate — a
    /// hermes row the positional filter would happily adopt — so any
    /// regression to the session re-read shows up as wrong CONTENT, not just
    /// as a call count.
    func reconcileFromServer() async -> Conversation? {
        reconcileFromServerCallCount += 1
        return Conversation(
            title: "Hermes",
            messages: [
                Message(id: userID, sender: .user, content: "do the thing", status: .delivered),
                Message(
                    sender: .hermes,
                    content: "AN UNRELATED LATER TURN'S REPLY",
                    timestamp: sessionRowTimestamp,
                    status: .delivered
                ),
            ]
        )
    }

    func resolveDroppedRun(runID: String, sessionID: String) async -> DroppedRunResolution? {
        resolveCallCount += 1
        guard resolveCallCount >= resolvesAfterCalls else { return nil }
        return resolution
    }
}
