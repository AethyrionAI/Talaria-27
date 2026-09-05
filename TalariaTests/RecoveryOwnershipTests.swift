import Foundation
import Testing
@testable import Talaria

/// #427 (the launch audit's A2) — **a late run-recovery verdict lands only in
/// the thread that owns it.**
///
/// The defect: `attemptRunStatusReconcile` awaits `GET /v1/runs/{id}` for
/// conversation A and then writes whatever came back into the store's LIVE
/// `conversation` — which is B, if the user opened another thread while the
/// read was in flight. `openSession` → `abandonPendingRun` cancelled the
/// polling LOOP but never the single-flight pass, so the pass was
/// architecturally free to survive the walk-away and land on the arriving
/// thread. **That door is closed as of Task 2** (`abandonPendingRun` and
/// `abandonReconcileWindowOnStop` now cancel `reconcileInFlight` and bump
/// `recoveryGeneration`); the token remains the thing that decides what a
/// verdict may WRITE, because a cancelled task can already be past its own
/// cancellation check.
///
/// Bars 427-A (the answer never lands in B), 427-B (B's own pending run is
/// untouched by A's verdict) and 427-C (the positive control — the gate
/// really does release and the happy path is unchanged) live here, together
/// with four bars the first review added: the same-thread REPLACEMENT (the
/// verdict is superseded with nobody having walked away, and the loop must
/// not tear itself down over it), the two halves of what the superseded arm
/// RECORDS (`resolvedRunIDs` on a terminal verdict, nothing on `.gone`), and
/// the thread clause in isolation — and Task 2's four: 427-D (the walk-away
/// releases the in-flight pass instead of leaving the arriving thread to
/// coalesce onto it), 427-E (the LEGACY session re-read carries the same
/// token), 427-F (Stop is protected exactly as the walk-away is) and 427-W
/// (a source witness enumerating every guarded write).
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
    ///
    /// **The `pendingRunSessionId` pair is a STAYS-NIL pin and has no
    /// isolating mutation** — recorded rather than dressed up. The bar asks
    /// for nil "for the right reason", so the nil is asserted twice: once
    /// straight after the walk-away (which is what cleared it) and once after
    /// the release (the superseded pass re-armed nothing and re-cleared
    /// nothing). No mutation in this lane can turn either red — nothing on
    /// the recovery path arms a pending run, and `settlePendingRun`'s
    /// `pendingRun = nil` is a no-op against a nil — so these two lines are
    /// regression coverage for a future write, not evidence of this one.
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
        #expect(store.pendingRunSessionId == nil,
                "the WALK-AWAY cleared A's pending run — asserted HERE so the same assertion after the release is a nil for that reason and not the pass's")

        client.release("run-A")
        await pass.value

        #expect(store.conversation?.messages.map(\.content) == ["B's own history"])
        #expect(!(store.conversation?.messages.contains { $0.content == "A's late answer" } ?? true))
        #expect(resolved == ["A-session"], "the superseded pass fires nothing")
        #expect(store.pendingRunSessionId == nil,
                "and it re-armed no watch and re-cleared nothing — bar 427-A's own clause, stays-nil (see the note above: no mutation reds this)")
        #expect(store.pendingRunRunId == nil)
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
        // reconcile loop, not a second `reconcilePendingRuns()` — before
        // Task 2 the single-flight would have COALESCED onto A's still-parked
        // pass, and this bar predates that fix and does not depend on it
        // (427-D is the bar for the release itself).
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

    // MARK: - 427-D (the walk-away releases the in-flight pass)

    /// **427-D.** The walk-away must CANCEL the single-flight pass and clear
    /// the handle, not merely stop watching it. Otherwise the arriving
    /// thread's own foreground reconcile — `AppContainer` fires one on every
    /// foreground and on appear — coalesces onto the departed thread's parked
    /// read (`reconcilePendingRuns`'s `await running.value`) and is stuck
    /// behind an answer it can never use.
    ///
    /// **How "promptly" is measured, because a stopwatch would be flaky.**
    /// The second call is launched into a `Task` that sets a latch when it
    /// returns, and the bar is: the latch is set within a bounded pump of
    /// 1 s **with run-A's gate never released** — a quarter of the
    /// fixture's own 4 s park ceiling, so the two outcomes are an order of
    /// magnitude apart rather than a photo finish. The gate assertion is what
    /// makes it a real discriminator: a second call that returned only
    /// because someone released the read would prove nothing.
    ///
    /// **⚠️ DISCLOSED RELAXATION of a pre-registered bound.** Bar 427-D was
    /// written as *"bounded: < 100 ms"*; the bar AS RUN is **≤ 1 s**
    /// (`waitUntil(limit: 100)` = 100 pumps × 10 ms). A missed bar is a
    /// falsification, never a redefinition, so this is recorded as a
    /// deviation rather than quietly met: 100 ms would be the tightest
    /// wall-clock bar in the suite, on a Mac that routinely runs three lanes'
    /// simulators at once, and the discriminator does not need it — 1 s
    /// against the fixture's 4 s park is still a 4× separation, and the
    /// measured GREEN returns in **0.028–0.062 s**, an order of magnitude
    /// inside even the original figure. The bound was NOT tightened back:
    /// a bar that fails on host load is a bar that teaches people to re-roll.
    /// This is also the suite's only wall-clock assertion — if it ever
    /// flakes, raise this pump limit, never the fixture's park ceiling.
    ///
    /// Mutation (**MD** — the two lines together, and the report says why
    /// neither alone suffices): delete `reconcileInFlight?.cancel()` AND
    /// `reconcileInFlight = nil` from `abandonPendingRun` → the second call
    /// parks on A's read for the full 4 s and the latch is unset at 1 s →
    /// RED. Keeping either line alone leaves this bound green — `= nil` sends
    /// the second caller down a fresh task, and `cancel()` alone makes the
    /// stale task unwind fast enough to satisfy it — so the mutation is named
    /// as the pair.
    @Test
    func aSecondReconcileAfterTheWalkAwayNeverParksOnTheDepartedThreadsRead() async throws {
        let client = GatedRecoveryClient()
        client.answers["run-A"] = .answered(content: "A's late answer", usage: nil)
        let store = makeStore(client: client)

        await store.sendMessage("a question")                       // arms run-A on A
        #expect(store.pendingRunRunId == "run-A", "the fixture must arm a run-id-carrying pending run")

        let passA = Task { await store.reconcilePendingRuns() }
        await waitUntil { client.isInside("run-A") }
        #expect(client.isInside("run-A"), "the pass never parked — every assertion below is vacuous")

        await store.openSession("B")                                // the walk-away
        #expect(store.conversation?.id == client.bID,
                "the switch must be REAL (the protocol's default openSession returns A again)")

        // The arriving thread's own foreground reconcile.
        let latch = Latch()
        let passB = Task { @MainActor in
            await store.reconcilePendingRuns()
            latch.isSet = true
        }
        await waitUntil(limit: 100) { latch.isSet }                 // ≤ 1 s

        #expect(latch.isSet,
                "the arriving thread's reconcile coalesced onto the departed thread's parked read")
        // What this observes is that the TEST never released run-A's gate —
        // not that the read was still suspended at that instant, which it
        // need not be: a cancelled park unwinds immediately through `try?`.
        // That is the claim the bound needs. A second call that returned
        // because someone released the read would prove nothing; a second
        // call that returned with the gate never opened returned for its own
        // reasons.
        #expect(client.isInside("run-A"),
                "run-A's gate was never released — so the prompt return cannot be explained by A's read having been let go")
        #expect(client.resolveCalls.filter { $0 == "run-A" }.count == 1,
                "one read for run-A, ever — the second pass must not issue another")

        client.release("run-A")
        await passA.value
        await passB.value

        #expect(store.conversation?.messages.map(\.content) == ["B's own history"])
        #expect(!(store.conversation?.messages.contains { $0.content == "A's late answer" } ?? true))
    }

    // MARK: - 427-E (the legacy session re-read)

    /// **427-E.** The LEGACY leg — a pending run with no run id, reconciled by
    /// re-reading the whole session — carries the same token. It needs it
    /// more than the run-status leg does: that one APPENDS one row, this one
    /// REPLACES the live conversation with the server's view of a session
    /// (`conversation = mergeConversationMetadata(from:into:)`), and it does
    /// its own inline teardown rather than calling `settlePendingRun`, so
    /// Task 1's guards cover none of it.
    ///
    /// **The arming route is behavioural, not a reach-in** (Task 0, step 3):
    /// `StreamingUpdate.interrupted(sessionId:runId:)` takes `String?`, so the
    /// fixture yields `runId: nil` and `attemptReconcile` routes to
    /// `attemptSessionReconcile`. Five tests in `AppStoresTests` already arm
    /// it this way; what is new here is parking the re-read so the user can
    /// walk away mid-flight.
    ///
    /// **The bar's METADATA clause, and it is the stronger half.** 427-E was
    /// pre-registered as "no `mergeConversationMetadata` write — B's `title`
    /// and `latestUsage` unchanged", and the transcript assertions alone do
    /// not say that: the merge writes conversation-level fields as well as
    /// rows. Both are real discriminators here by construction —
    /// `mergeConversationMetadata` carries the LOCAL title forward only when
    /// the refreshed one is a placeholder (`"A, as the host sees it"` is
    /// not), and it carries the local usage forward only when the refreshed
    /// one is nil (the fixture gives A's server view a usage precisely so it
    /// is not). Unguarded, B's title becomes the host's name for A and B's
    /// gauge adopts A's tokens.
    ///
    /// Mutation (**ME**): delete the `recoveryOwnershipMiss` guard from
    /// `attemptSessionReconcile` → the server's view of A replaces B's
    /// transcript, its title and its usage → RED. Nothing else in the tree
    /// refuses this write, so unlike 427-A/427-B the single-guard mutation is
    /// the isolating one.
    @Test
    func aLateSessionReReadForTheThreadYouLeftNeverLandsInTheThreadYouOpened() async throws {
        let client = GatedRecoveryClient()
        client.nextRunID = nil                                      // no run id ⇒ the legacy leg
        client.serverConversation = Conversation(
            title: "A, as the host sees it",
            messages: [
                Message(sender: .user, content: "a question", timestamp: Date().addingTimeInterval(-60)),
                Message(sender: .hermes, content: "A's late answer",
                        timestamp: Date().addingTimeInterval(600), status: .delivered)
            ],
            // Non-nil on purpose: the merge only carries the LOCAL usage
            // forward when the server's is nil, so a nil here would make the
            // `latestUsage` assertion below pass in both directions.
            latestUsage: TokenUsage(promptTokens: 4271, completionTokens: 427, totalTokens: 4698)
        )
        let store = makeStore(client: client)
        var resolved: [String] = []
        store.onRunResolved = { resolved.append($0) }

        await store.sendMessage("a question")                       // arms A with NO run id
        #expect(store.pendingRunSessionId == "A-session", "the fixture must arm a pending run")
        #expect(store.pendingRunRunId == nil, "and it must carry no run id — this is the legacy leg's bar")

        let pass = Task { await store.reconcilePendingRuns() }
        await waitUntil { client.isInside(GatedRecoveryClient.sessionReconcileKey) }
        #expect(client.isInside(GatedRecoveryClient.sessionReconcileKey),
                "the session re-read never parked — every assertion below is vacuous")

        await store.openSession("B")                                // the walk-away
        #expect(store.conversation?.id == client.bID, "the switch must be REAL")

        client.release(GatedRecoveryClient.sessionReconcileKey)
        await pass.value

        // Measured during the RED run and recorded so nobody reads this as
        // the bar: the id survives the unguarded merge too, because #90's
        // `mergeConversationMetadata` deliberately keeps the LOCAL id
        // ("conversation identity is LOCAL and durable"). So this is a
        // precondition on the store, and the transcript assertions below are
        // what actually fail when the merge lands in B.
        #expect(store.conversation?.id == client.bID, "the store is still on B")
        #expect(store.conversation?.messages.map(\.content) == ["B's own history"])
        #expect(!(store.conversation?.messages.contains { $0.content == "A's late answer" } ?? true))
        // The bar's metadata half. The title is the stronger of the two: an
        // unguarded merge renames the thread the user is LOOKING at to the
        // host's name for the one they left.
        #expect(store.conversation?.title == "B",
                "no `mergeConversationMetadata` write — an unguarded merge would rename B to the host's title for A")
        #expect(store.conversation?.latestUsage == nil,
                "and B's gauge would have adopted A's token usage with it")
        #expect(resolved == ["A-session"], "the walk-away's own resolution and no other")
        let cached = try #require(store.persistence.loadConversationCache())
        #expect(!cached.messages.contains { $0.content == "A's late answer" },
                "the cache is ONE global slot — A's rows written here are A's rows persisted under B")
    }

    // MARK: - 427-F (Stop)

    /// **427-F.** Stop inside the #278 reconcile window gets the same
    /// protection as the walk-away (Owen's ruling 3). Nothing of the
    /// abandoned run may land after the user pressed Stop, and the user row
    /// settles `.delivered` exactly as #321 ruling (b) says.
    ///
    /// **Deviation from the brief, recorded:** it prescribes
    /// `cancelStreaming(hardStopHost: false)`, which does NOT reach
    /// `abandonReconcileWindowOnStop` — `abandonsTheReconcileWindow` is
    /// `hardStopHost && streamingMessageID == nil && pendingRun != nil`, and
    /// the `false` path is the background-expiration arm that deliberately
    /// KEEPS the recovery armed (`cancelStreaming`'s own doc says so). The
    /// explicit Stop is `hardStopHost: true`, the default.
    ///
    /// Mutation (**MF** — three lines, and the report says why): delete
    /// `recoveryGeneration &+= 1` from `abandonReconcileWindowOnStop`, plus
    /// the two belts that mask it — the `reconcileInFlight?.cancel()` /
    /// `= nil` pair beside it, and `recoveryOwnershipMiss`'s
    /// `.pendingRunCleared` arm (`guard let pending = pendingRun` → `return
    /// nil`) → A's answer is adopted into the thread the user just stopped →
    /// RED. On this path the token's pending-run clause would refuse the
    /// write anyway — Stop clears `pendingRun` — which is why the mutation
    /// has to take that clause out too before it can ask about the rest.
    ///
    /// **The isolating control the Task 2 review sketched WAS stageable, and
    /// the final fix wave RAN it — this comment used to claim "no fixture can
    /// stage this from outside the store", which was wrong.** Two runs, one
    /// test each:
    /// - **MFa** — the `reconcileInFlight?.cancel()` / `= nil` pair removed
    ///   AND the `.pendingRunCleared` arm removed, the generation bump
    ///   **KEPT** → **GREEN** (0 issues). Every other belt is gone, so the
    ///   bump is the only thing that can be refusing the write.
    /// - **MFb** — MFa plus `recoveryGeneration &+= 1` removed → **RED**
    ///   (3 issues: A's answer in the transcript, a second `onRunResolved`,
    ///   A's answer in the cache).
    ///
    /// So the bump is load-bearing on the Stop leg **in its own right**, not
    /// merely as a member of a set. What remains genuinely un-staged is the
    /// narrower ordering it was added for — a token captured before the
    /// `pendingRun` clear, on an unmutated tree — and that is defence in
    /// depth pinned by argument.
    @Test
    func aStopInsideTheReconcileWindowInvalidatesTheReadItLeftInFlight() async throws {
        let client = GatedRecoveryClient()
        client.answers["run-A"] = .answered(content: "A's late answer", usage: nil)
        let store = makeStore(client: client)
        var resolved: [String] = []
        store.onRunResolved = { resolved.append($0) }

        await store.sendMessage("a question")
        #expect(store.pendingRunRunId == "run-A", "the window is open")
        let pass = Task { await store.reconcilePendingRuns() }
        await waitUntil { client.isInside("run-A") }
        #expect(client.isInside("run-A"), "the pass never parked — every assertion below is vacuous")

        store.cancelStreaming()                                     // the explicit Stop

        #expect(store.pendingRunRunId == nil, "#321 ruling (a): Stop abandons the window")
        #expect(resolved == ["A-session"], "the abandon fires exactly one resolution")
        #expect(store.conversation?.messages.first { $0.content == "a question" }?.status == .delivered,
                "#321 ruling (b): the window Stop's user row settles where a live Stop's does")

        client.release("run-A")
        await pass.value

        #expect(!(store.conversation?.messages.contains { $0.content == "A's late answer" } ?? true),
                "the answer to a run the user stopped never lands")
        #expect(store.conversation?.messages.first { $0.content == "a question" }?.status == .delivered,
                "and the settled row is not re-opened by the late verdict")
        #expect(store.pendingRunRunId == nil, "the superseded pass re-arms nothing")
        #expect(resolved == ["A-session"], "and fires no resolution of its own")
        let cached = try #require(store.persistence.loadConversationCache())
        #expect(!cached.messages.contains { $0.content == "A's late answer" })
    }

    // MARK: - 427-W (the source witness)

    /// **427-W.** Every write a recovery pass makes after its read sits behind
    /// the token — enumerated by reading production's own bytes, because no
    /// runtime test can prove a NEGATIVE about a function nobody called.
    /// 427-A…F each drive one path; this one says there are no others.
    ///
    /// Each function is pinned to the predicate it actually calls rather than
    /// to a union of both: the two run-status entry points need the MISS (the
    /// notice names which clause refused), the three write helpers need only
    /// the boolean. A union check would keep passing if a site swapped one for
    /// the other and stopped naming the reason.
    ///
    /// The body is bounded at the next member's doc comment (`\n    ///`).
    /// **That boundary terminates at the next DOC COMMENT, not at the
    /// anchor's closing brace** — so a member that grows an undocumented
    /// neighbour beneath it would silently widen every slice, and a pin could
    /// then be satisfied by that neighbour's guard. Two checks close the gap
    /// rather than the comment claiming it is closed: the slice must contain
    /// no second `func ` declaration (a widened slice has swallowed one), and
    /// it must contain the anchor's own distinctive line — a fingerprint that
    /// appears **exactly once in the whole file**, so a slice pointing
    /// anywhere else cannot satisfy it. Two of the five fingerprints used to
    /// fail that second condition (`resolveHeldTurn(after: .reconciled)`
    /// occurs twice, `mergeConversationMetadata(` six times) despite the
    /// comment above them promising "a line only that body has"; they were
    /// swapped for unique ones, with the counts recorded in the lane report.
    @Test(.enabled(if: RepoSourceWitness.repoSourcesAreReadable,
                   "reads the repo's own sources — simulator only"))
    func everyWriteBehindTheRecoveryReadIsGuardedByTheOwnershipToken() throws {
        let store = "Talaria/Stores/ChatStore.swift"
        // anchor · the predicate that site calls · a line that occurs exactly
        // once in the whole file, and inside this body
        let sites: [(String, String, String)] = [
            ("private func attemptRunStatusReconcile(", "recoveryOwnershipMiss(",
             "hermesClient.resolveDroppedRun("),
            ("private func appendRunFailureNotice(", "recoveryStillOwned(",
             "Message(sender: .system, content: text"),
            ("private func adoptRecoveredRun(", "recoveryStillOwned(",
             "stableRecoveredRunMessageID("),
            ("private func settlePendingRun(", "recoveryStillOwned(",
             "if !adopted, let restoredRowID = pending.restoredRowID"),
            ("private func attemptSessionReconcile(", "recoveryOwnershipMiss(",
             "Self.placingRecoveredReply(")
        ]

        let wholeFile = try RepoSourceWitness.source(store)
        for (anchor, needle, fingerprint) in sites {
            let body = try RepoSourceWitness.functionBody(from: anchor, in: store, boundary: "\n    ///")
            #expect(wholeFile.components(separatedBy: fingerprint).count == 2,
                    "\(anchor) — \(fingerprint) is not unique in \(store); a fingerprint that appears twice cannot tell a correct slice from a widened one")
            #expect(body.contains(fingerprint),
                    "\(anchor) — the extracted body does not contain \(fingerprint); the pin is reading the wrong slice")
            #expect(!body.contains("func "),
                    "\(anchor) — the slice swallowed another declaration: the boundary stops at the next DOC COMMENT, so an undocumented neighbour widens it and its guard could satisfy this pin")
            #expect(body.contains(needle),
                    "\(anchor) — a recovery write that does not pass \(needle) can land in a thread the verdict does not own (#427)")
        }
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

/// A one-way flag a `Task` can set. `Task`'s closure is `@Sendable`, so a
/// captured local `var` cannot be mutated inside one; a main-actor class
/// reference can (and `@MainActor` makes the class itself `Sendable`). Used
/// by 427-D to observe that a call RETURNED without timing how long it took.
@MainActor
private final class Latch {
    var isSet = false
}

/// `RunStatusRecoveryTests.RunRecoveryClient` (`:346-449`) with four
/// changes, and only four:
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
///    fixture can arm A's run and then B's — and `nextRunID` is OPTIONAL, so
///    a test can arm the legacy (run-id-less) leg through the ordinary
///    `.interrupted` route rather than by reaching into the store.
/// 4. `reconcileFromServer` parks on a gate of its own (427-E), but ONLY when
///    a test has given it something to return — otherwise it stays the
///    immediate `nil` the other six bars were written against.
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

    /// The legacy session re-read has no run id to key a gate on, so it parks
    /// on this one. Named, not a literal, because two files' worth of
    /// assertions read it.
    static let sessionReconcileKey = "session-reconcile"

    /// Keyed by run id, so A's read and B's read park independently.
    var gates: [String: Gate] = [:]
    var answers: [String: DroppedRunResolution] = [:]
    private(set) var resolveCalls: [String] = []

    /// What the LEGACY leg's `reconcileFromServer` hands back. `nil` (the
    /// default) keeps that method the immediate no-op it has always been.
    var serverConversation: Conversation?

    var nextRunID: String? = "run-A"
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

    /// The legacy instrument. Empty unless a test sets `serverConversation`:
    /// six of the bars here arm run-id-carrying pending runs, so a call at all
    /// would mean the run-status leg was not taken, and giving THOSE a 4 s
    /// park would turn a routing mistake into a slow suite instead of a loud
    /// one. 427-E sets it and parks like the run-status leg does.
    func reconcileFromServer() async -> Conversation? {
        guard serverConversation != nil else { return nil }
        resolveCalls.append(Self.sessionReconcileKey)
        await park(Self.sessionReconcileKey)
        return serverConversation
    }

    func resolveDroppedRun(runID: String, sessionID: String) async -> DroppedRunResolution? {
        resolveCalls.append(runID)
        await park(runID)
        return answers[runID]
    }

    /// Bounded park — 4 s ceiling, and a REAL early exit: `for … where`
    /// does not stop when the condition turns false, it merely skips the
    /// body, so the released gate used to spin out its remaining
    /// iterations before returning. A gate the test forgets to release
    /// must not hang the suite; the `isInside` assertions are what make
    /// a park that ended early visible rather than silently vacuous.
    ///
    /// `try?` on the sleep is deliberate: a CANCELLED pass (which is what
    /// #427's walk-away now does to an in-flight read) unwinds this loop
    /// immediately and still returns the host's answer, so the token — not
    /// the cancellation — is what has to refuse the write.
    private func park(_ key: String) async {
        gates[key, default: Gate()].entered = true
        var pumps = 0
        while gates[key]?.released != true, pumps < 400 {
            try? await Task.sleep(for: .milliseconds(10))
            pumps += 1
        }
    }
}
