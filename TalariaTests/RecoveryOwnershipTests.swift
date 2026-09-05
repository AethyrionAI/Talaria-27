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
/// really does release and the happy path is unchanged) live here, together
/// with four bars the first review added: the same-thread REPLACEMENT (the
/// verdict is superseded with nobody having walked away, and the loop must
/// not tear itself down over it), the two halves of what the superseded arm
/// RECORDS (`resolvedRunIDs` on a terminal verdict, nothing on `.gone`), and
/// the thread clause in isolation.
///
/// Each names the mutation that turns it red, because a test that cannot be
/// made to fail is not evidence — **and every mutation named here was
/// measured, which the first two were not.** Both of the originally-written
/// mutations came back GREEN: with nested guards, removing one is a no-op
/// while another still refuses the same write. The corrected forms say
/// exactly which guards come out together.
@Suite("427 recovery ownership")
@MainActor
struct RecoveryOwnershipTests {

    // MARK: - 427-A

    /// **427-A.** A parked status read for thread A returns after the user has
    /// opened thread B. Nothing of A's may appear in B — not in the live
    /// transcript, not in the (single, global) conversation cache — and the
    /// superseded pass must fire no resolution of its own.
    ///
    /// Mutation (**M2** — measured, and not the one first written here):
    /// remove BOTH the post-await `recoveryStillOwned` guard from
    /// `attemptRunStatusReconcile` AND `adoptRecoveredRun`'s own re-check →
    /// `"A's late answer"` appears in B → RED. Removing the post-await guard
    /// ALONE is inert on this bar and was measured green: `adoptRecoveredRun`
    /// catches the stale token one frame later. **With nested guards, a
    /// mutation that removes an inner one is a no-op while the outer stands,
    /// and a mutation that removes the outer one is a no-op while an inner
    /// one does the same job** — isolating a guard means removing every
    /// guard that shadows it, and saying so.
    /// (The post-await guard's OWN contribution — the `resolvedRunIDs` entry
    /// no other site writes — is pinned separately, by
    /// `aSupersededTerminalVerdictStillDisarmsALateDuplicateInterrupt`.)
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
    /// Mutation (**M3** — measured): M2 (the post-await guard and
    /// `adoptRecoveredRun`'s re-check both removed) **plus**
    /// `settlePendingRun`'s token check → A's verdict clears B's pending run
    /// → RED on the still-armed assertions. Removing `settlePendingRun`'s
    /// check alone is inert and was measured green: with the post-await guard
    /// standing, `settlePendingRun` is never reached with a stale token at
    /// all. The M2 → M3 delta is exactly this bar's own assertions plus
    /// `onRunResolved` and the cache write, which is the isolation asked for.
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

    // MARK: - 427-A′ (the same-thread replacement)

    /// **The case the token exposes rather than closes.** Two dropped turns
    /// on ONE thread: run-A's status read is parked when a second
    /// `.interrupted` arms run-B through `armPendingRunRecovery` — the only
    /// site that replaces `pendingRun` without cancelling anything. Nobody
    /// walked away, so neither `abandonPendingRun` nor
    /// `abandonReconcileWindowOnStop` ran, and `Task.isCancelled` is false.
    ///
    /// A's verdict is therefore superseded by the PENDING-RUN clause with the
    /// thread unchanged, and the loop's exit — not the token — is what
    /// decides what happens next. Before the fix `.superseded` broke the
    /// while, which dropped the loop into its budget-expired tail:
    /// `resolveHeldTurn(after: .reconcileBudgetExpired)` on B's turn, a
    /// restored-row settle, and `reconcileTask = nil` — leaving run-B armed
    /// with nothing watching it, so B's answer could never land. The
    /// constraint the token exists to enforce, arriving indirectly.
    ///
    /// Mutation: restore `if outcome != .keepPolling { break }` as the loop's
    /// only exit test (i.e. delete the `.superseded` → `continue` arm) →
    /// `hasActiveReconcileLoop` false and B's answer never arrives → RED.
    /// A second, independent mutation: drop `|| outcome == .superseded` from
    /// `performReconcilePendingRuns` → this bar stays green (its watcher is
    /// the loop, not the single-flight) and that arm is pinned by argument
    /// only — recorded here so the next reader does not mistake one for both.
    @Test
    func aReplacementRunOnTheSameThreadKeepsTheWatcherItInherited() async throws {
        let client = GatedRecoveryClient()
        client.answers["run-A"] = .answered(content: "A's late answer", usage: nil)
        client.answers["run-B"] = .answered(content: "B's answer", usage: nil)
        let store = makeStore(client: client)
        // Here the reconcile LOOP is the actor, not a hand-driven
        // `reconcilePendingRuns()`: the tail under test belongs to the loop,
        // and only the loop's own read can reach it. Set before the first
        // send — `startReconcileLoopIfNeeded` reads the interval once.
        store.runRecoveryPollInterval = .milliseconds(10)

        await store.sendMessage("a question")
        #expect(store.pendingRunRunId == "run-A")
        #expect(store.hasActiveReconcileLoop, "arming a pending run starts its watcher")
        await waitUntil { client.isInside("run-A") }
        #expect(client.isInside("run-A"), "the loop's own read never parked — every assertion below is vacuous")

        // The second dropped turn. Same thread, same session, new run.
        client.nextRunID = "run-B"
        await store.sendMessage("b question")
        #expect(store.pendingRunRunId == "run-B", "the replacement is armed")
        #expect(store.pendingRunSessionId == "A-session", "on the same thread and the same session")
        #expect(store.conversation?.id != client.bID, "nobody walked away — this bar is not the walk-away")

        client.release("run-A")
        await waitUntil { client.isInside("run-B") }

        #expect(client.isInside("run-B"),
                "the inherited loop must go on to read run-B — otherwise nothing is watching it")
        #expect(store.hasActiveReconcileLoop,
                "a superseded verdict must not tear down the watcher its replacement inherited")
        #expect(store.pendingRunRunId == "run-B", "A's verdict settles nothing of B's")
        #expect(!(store.conversation?.messages.contains { $0.content == "A's late answer" } ?? true))
        #expect(store.conversation?.messages.first { $0.content == "b question" }?.status == .working,
                "B's own turn is still awaiting its own answer")

        client.release("run-B")
        await waitUntil { store.pendingRunSessionId == nil }

        #expect(store.conversation?.messages.last?.content == "B's answer",
                "B's own recovery still lands, at B's tail")
        #expect(store.pendingRunSessionId == nil, "B settles on its own verdict")
        #expect(store.conversation?.messages.first { $0.content == "b question" }?.status == .sent)
        #expect(!(store.conversation?.messages.contains { $0.content == "A's late answer" } ?? true),
                "A's answer is nowhere, at either end of the run")
        #expect(client.resolveCalls == ["run-A", "run-B"],
                "two reads, in that order — ONE loop went round, never two loops racing")
    }

    // MARK: - 427-A″ (what the superseded arm itself records)

    /// **The one assertion only the post-await guard can satisfy.** Every
    /// other bar in this file survives that guard's deletion, because
    /// `adoptRecoveredRun` and `settlePendingRun` refuse the same writes one
    /// frame later. What no other site does is the superseded arm's
    /// `resolvedRunIDs.insert(runID)` — and #237 reads that set through real
    /// behaviour: a late duplicate `.interrupted` naming a run already
    /// recorded is torn down quietly instead of re-arming a pending run for a
    /// turn the host has already finished.
    ///
    /// The fixture's verdict for run-A is `.answered` — TERMINAL — so the
    /// insert is legitimately the superseded arm's to make. A `.gone` verdict
    /// records nothing (see the sibling bar below), which is why this test
    /// pins the terminal case explicitly rather than "any superseded pass".
    ///
    /// Mutation: remove the post-await `recoveryStillOwned` guard from
    /// `attemptRunStatusReconcile` — that one alone, the mutation this file
    /// once wrongly attributed to 427-A → run-A is never recorded → the late
    /// duplicate re-arms a pending run → RED.
    @Test
    func aSupersededTerminalVerdictStillDisarmsALateDuplicateInterrupt() async throws {
        let client = GatedRecoveryClient()
        client.answers["run-A"] = .answered(content: "A's late answer", usage: nil)
        let store = makeStore(client: client)

        await store.sendMessage("a question")
        let pass = Task { await store.reconcilePendingRuns() }
        await waitUntil { client.isInside("run-A") }
        #expect(client.isInside("run-A"), "the pass never parked — every assertion below is vacuous")

        await store.openSession("B")
        #expect(store.conversation?.id == client.bID, "the switch must be REAL")

        client.release("run-A")
        await pass.value
        #expect(store.pendingRunRunId == nil, "the walk-away already cleared A's run; the pass added nothing")

        // The dying stream's late duplicate: the SAME run id, arriving after
        // the superseded pass recorded it.
        client.nextRunID = "run-A"
        client.nextSessionID = "A-session"
        await store.sendMessage("the late duplicate")

        #expect(store.pendingRunRunId == nil,
                "a run the superseded arm recorded as resolved must NOT re-arm a recovery (#237)")
        #expect(store.pendingRunSessionId == nil)
        #expect(!store.hasActiveReconcileLoop,
                "and no watcher is armed for a run the host has already finished with")
        #expect(!(store.conversation?.messages.contains { $0.content == "A's late answer" } ?? true),
                "still nothing of A's in B")
    }

    /// The same arm's other half: a `.gone` verdict on a superseded pass
    /// records NOTHING. The owned path answers `.gone` with `.unrecoverable`
    /// and writes no entry, and a pass that lost its thread must not claim
    /// more than the pass that kept it would have — so the late duplicate
    /// below still arms an ordinary recovery.
    ///
    /// Mutation: hoist `resolvedRunIDs.insert(runID)` back above the
    /// `switch resolution` in the superseded arm → `.gone` is recorded → the
    /// late duplicate is swallowed → RED.
    @Test
    func aSupersededGoneVerdictRecordsNothing() async throws {
        let client = GatedRecoveryClient()
        client.answers["run-A"] = .gone
        let store = makeStore(client: client)

        await store.sendMessage("a question")
        let pass = Task { await store.reconcilePendingRuns() }
        await waitUntil { client.isInside("run-A") }
        #expect(client.isInside("run-A"), "the pass never parked — every assertion below is vacuous")

        await store.openSession("B")
        #expect(store.conversation?.id == client.bID, "the switch must be REAL")

        client.release("run-A")
        await pass.value

        client.nextRunID = "run-A"
        client.nextSessionID = "A-session"
        await store.sendMessage("a fresh drop naming the same run")

        #expect(store.pendingRunRunId == "run-A",
                "`.gone` is not a resolution — nothing was recorded, so this drop recovers normally")
        #expect(store.pendingRunSessionId == "A-session")
    }

    // MARK: - 427-A‴ (the conversationID clause, alone)

    /// **The thread clause, isolated.** In 427-A and 427-B the pending-run
    /// clause has already failed by the time the thread clause is consulted,
    /// so deleting the thread comparison leaves both of them green — the
    /// clause was carried by its neighbours. Here the pending run is
    /// untouched (same session, same run id, nothing cancelled, generation
    /// unmoved) and the store's live `conversation` is a different thread, so
    /// `conversationID` is the only thing that can refuse the write.
    ///
    /// **Route** (recorded because there is no natural one): the test assigns
    /// `store.conversation` directly, under `@testable`. That is deliberately
    /// NOT a walk-away — `abandonPendingRun` would clear the pending run and
    /// the bar with it. It is the shape of any site that swaps the live
    /// thread without going through the walk-away primitive, and the token's
    /// thread clause is the only thing standing between such a site and a
    /// cross-thread write. (`seedPendingRunForTesting` was the other
    /// candidate; it mints `conversationID: conversation?.id`, so it cannot
    /// produce the mismatch without a signature change.)
    ///
    /// Mutation: delete `if conversation?.id != token.conversationID { return
    /// .threadChanged }` from `recoveryOwnershipMiss` → A's answer is adopted
    /// into the thread that is showing → RED.
    @Test
    func aVerdictForARunWhoseThreadIsNoLongerShowingWritesNothingHere() async throws {
        let client = GatedRecoveryClient()
        client.answers["run-A"] = .answered(content: "A's late answer", usage: nil)
        let store = makeStore(client: client)
        var resolved: [String] = []
        store.onRunResolved = { resolved.append($0) }

        await store.sendMessage("a question")
        let armedThread = try #require(store.conversation?.id)
        let pass = Task { await store.reconcilePendingRuns() }
        await waitUntil { client.isInside("run-A") }
        #expect(client.isInside("run-A"), "the pass never parked — every assertion below is vacuous")

        let elsewhere = Conversation(id: UUID(), title: "elsewhere", messages: [])
        #expect(elsewhere.id != armedThread)
        store.conversation = elsewhere

        // Every OTHER clause still holds — this is what makes the bar an
        // isolation rather than a repeat of 427-A.
        #expect(store.pendingRunSessionId == "A-session")
        #expect(store.pendingRunRunId == "run-A")

        client.release("run-A")
        await pass.value

        #expect(store.conversation?.messages.isEmpty == true,
                "the verdict belongs to a thread this is not — nothing lands here")
        #expect(!(store.conversation?.messages.contains { $0.content == "A's late answer" } ?? true))
        #expect(store.pendingRunRunId == "run-A", "a superseded pass settles nothing either")
        #expect(store.pendingRunSessionId == "A-session")
        #expect(resolved.isEmpty, "and fires no resolution")
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
        // Bounded park — 4 s ceiling, and a REAL early exit: `for … where`
        // does not stop when the condition turns false, it merely skips the
        // body, so the released gate used to spin out its remaining
        // iterations before returning. A gate the test forgets to release
        // must not hang the suite; the `isInside` assertions are what make
        // a park that ended early visible rather than silently vacuous.
        var pumps = 0
        while gates[runID]?.released != true, pumps < 400 {
            try? await Task.sleep(for: .milliseconds(10))
            pumps += 1
        }
        return answers[runID]
    }
}
