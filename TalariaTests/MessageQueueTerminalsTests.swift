import Foundation
import Testing
@testable import Talaria

/// #306 mid-turn message queuing — the terminal matrix, the identity ruling,
/// and the fire discipline. Bars 306-A through 306-F plus 306-J's unit half;
/// bar 306-E doubles as #307's pin (the outbox draining into a live run
/// during the reconcile window).
///
/// The one-line rule under test: the queue auto-fires on exactly ONE
/// terminal — a turn that actually completed. Everything else holds and says
/// why. And the fire condition branches on the OBSERVED TERMINAL, never on
/// the user row's final status — rows 1, 2, and 10 of the matrix all leave
/// that row `.delivered` (trap 3).
struct MessageQueueTerminalsTests {

    @MainActor private static func makePersistence() -> UserDefaultsAppPersistenceStore {
        let suiteName = "message-queue-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return UserDefaultsAppPersistenceStore(defaults: defaults)
    }

    /// Manual-drive client: each `sendStreaming` records the message and
    /// hands its continuation to the TEST, so the turn's terminal is the
    /// test's own event — never a race against a scripted frame. Sends made
    /// while `autoFinishSends` is true (the drain/fire path's re-sends)
    /// complete immediately instead.
    @MainActor
    private final class ManualStreamClient: HermesClientProtocol {
        var connectionStatus: ConnectionStatus = .connected
        var currentConversation: Conversation?
        var currentRunIsServerRecoverable = true
        private(set) var sentMessages: [String] = []
        private(set) var continuations: [AsyncStream<StreamingUpdate>.Continuation] = []
        /// When true, a send completes with an immediate `.finished` — the
        /// mode the drain/fire's re-sends run under.
        var autoFinishSends = false
        /// When false, the stream yields no `.messageSent` — the shape of a
        /// turn that failed OUTRIGHT (`acceptedJobID == nil`, matrix row 6).
        var autoAccept = true
        var reconcileConversation: Conversation?
        private(set) var reconcileCallCount = 0
        /// #328 route 2: whether this client's plane can issue a real host
        /// stop. Default **false** — the ordinary sessions `chat/stream`
        /// shape, which is what the phone actually uses and what #328 is
        /// about. Set true to stand in for the `/v1/runs` plane.
        var hostStopIsIssuable = false

        @discardableResult
        func hardStopActiveRun() -> Bool { hostStopIsIssuable }

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
            sentMessages.append(message)
            let accept = autoAccept
            let autoFinish = autoFinishSends
            return AsyncStream { continuation in
                if accept { continuation.yield(.messageSent(jobID: UUID())) }
                if autoFinish {
                    continuation.yield(.finished(
                        Message(sender: .hermes, content: "auto-reply: \(message)", status: .delivered),
                        nil, nil
                    ))
                    continuation.finish()
                } else {
                    self.continuations.append(continuation)
                }
            }
        }

        func loadConversation() async -> Conversation {
            currentConversation ?? Conversation(title: Conversation.defaultTitle)
        }

        func clearConversation() async throws -> Conversation {
            Conversation(title: Conversation.defaultTitle)
        }

        func reconcileFromServer() async -> Conversation? {
            reconcileCallCount += 1
            return reconcileConversation
        }

        /// #368 (3E): these turns drop with a real run id (`R1`), so after
        /// the cutover their recovery is the run-status read. The fixture
        /// answers from the SAME `reconcileConversation` slot each test
        /// already sets — the newest hermes row in it — so every test here
        /// keeps its existing arrange step and now measures the #306 matrix
        /// on the path production takes.
        func resolveDroppedRun(runID: String, sessionID: String) async -> DroppedRunResolution? {
            reconcileCallCount += 1
            guard let reply = reconcileConversation?.messages.last(where: { $0.sender == .hermes }) else {
                return nil
            }
            return .answered(content: reply.content, usage: nil)
        }
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

    /// Starts a manual turn and holds until the stream is live.
    @MainActor
    private func startTurn(
        _ text: String, store: ChatStore, client: ManualStreamClient
    ) async -> Task<Bool, Never> {
        let priorStreams = client.continuations.count
        let task = Task { @MainActor in await store.sendMessage(text) }
        let live = await pollUntil { store.isStreaming && client.continuations.count > priorStreams }
        #expect(live, "the manual turn must be streaming before the test proceeds")
        return task
    }

    // MARK: - 306-A: the hold

    @Test @MainActor
    func holdWhileStreamingHoldsWithoutPosting() async throws {
        let persistence = Self.makePersistence()
        let client = ManualStreamClient()
        let store = ChatStore(hermesClient: client, persistence: persistence)

        let sendTask = await startTurn("turn one", store: store, client: client)

        #expect(store.holdComposedTurn("follow-up while streaming"))

        // Held — not posted: no new sendStreaming, no transcript row.
        #expect(client.sentMessages == ["turn one"])
        let held = try #require(store.currentThreadHeldTurn)
        #expect(held.reason == .heldDuringTurn)
        #expect(held.phase == .held)
        #expect(held.transcriptRowID == nil)
        #expect(store.conversation?.messages.contains {
            $0.content == "follow-up while streaming"
        } == false)
        // Persisted immediately — the sendMessage precedent: nothing can die
        // holding the only copy.
        #expect(persistence.loadComposeOutboxState().pendingTurns.contains {
            $0.id == held.id && $0.text == "follow-up while streaming"
        })

        // End the stream with NO terminal frame — the hold stays held.
        client.continuations.last?.finish()
        _ = await sendTask.value
        #expect(client.sentMessages == ["turn one"])
    }

    @Test @MainActor
    func holdIsDepthOnePerThread() async throws {
        let persistence = Self.makePersistence()
        let client = ManualStreamClient()
        let store = ChatStore(hermesClient: client, persistence: persistence)

        let sendTask = await startTurn("turn one", store: store, client: client)
        #expect(store.holdComposedTurn("first hold"))
        // O4: depth 1 — "a next message, not a mailbox".
        #expect(store.holdComposedTurn("second hold") == false)
        #expect(store.currentThreadHeldTurn?.text == "first hold")

        client.continuations.last?.finish()
        _ = await sendTask.value
    }

    @Test @MainActor
    func holdRefusedWhenNoTurnIsInFlight() async throws {
        let persistence = Self.makePersistence()
        let client = ManualStreamClient()
        let store = ChatStore(hermesClient: client, persistence: persistence)

        // C2: the readiness question is `isTranscriptBusy` — nothing in
        // flight means nothing to wait on; the caller sends normally.
        #expect(store.holdComposedTurn("nothing to wait on") == false)
        #expect(store.currentThreadHeldTurn == nil)
        #expect(persistence.loadComposeOutboxState().isEmpty)
    }

    // MARK: - 306-B: fire-once on completion

    @Test @MainActor
    func heldTurnFiresExactlyOnceOnCompletion() async throws {
        let persistence = Self.makePersistence()
        let client = ManualStreamClient()
        let store = ChatStore(hermesClient: client, persistence: persistence)

        let sendTask = await startTurn("turn one", store: store, client: client)
        #expect(store.holdComposedTurn("the follow-up"))
        let entryID = try #require(store.currentThreadHeldTurn?.id)

        // Two `.finished` frames — the #237 shape: a duplicate terminal
        // report must not double the fire.
        let reply = Message(sender: .hermes, content: "answer one", status: .delivered)
        client.autoFinishSends = true
        client.continuations.last?.yield(.finished(reply, nil, nil))
        client.continuations.last?.yield(.finished(reply, nil, nil))
        client.continuations.last?.finish()
        _ = await sendTask.value

        let fired = await pollUntil { client.sentMessages.contains("the follow-up") }
        #expect(fired, "306-B: the held message must post after `.finished`")
        // Let any second fire attempt drain through the main actor.
        try? await Task.sleep(for: .milliseconds(150))
        #expect(
            client.sentMessages.filter { $0 == "the follow-up" }.count == 1,
            "306-B: the SEND COUNT is the assertion — exactly one post"
        )
        #expect(store.currentThreadHeldTurn == nil)

        // The identity ruling: exactly one row, whose clientMessageID was
        // minted by sendMessage — a fresh id, never the entry's.
        let rows = store.conversation?.messages.filter {
            $0.sender == .user && $0.content == "the follow-up"
        } ?? []
        #expect(rows.count == 1)
        let row = try #require(rows.first)
        #expect(row.clientMessageID != nil)
        #expect(row.clientMessageID != entryID)
    }

    // MARK: - 306-C: Stop does not fire (O2 — the defining behavior)

    @Test @MainActor
    func stopNeverFiresAndRestoresTextToTheComposer() async throws {
        let persistence = Self.makePersistence()
        let client = ManualStreamClient()
        let store = ChatStore(hermesClient: client, persistence: persistence)
        // The composer is empty at Stop time — the restore's clean case.
        store.composerLiveText = { "" }

        let sendTask = await startTurn("stop me", store: store, client: client)
        #expect(store.holdComposedTurn("held behind the stop"))

        store.cancelStreaming()
        _ = await sendTask.value

        #expect(
            client.sentMessages == ["stop me"],
            "306-C: sendStreaming must never be re-invoked by a Stop"
        )
        // O2: the text RESTORES to the composer — the entry leaves the queue
        // and rides the #48 composer seed (seed-only, never auto-send).
        #expect(store.currentThreadHeldTurn == nil)
        #expect(store.pendingComposerSeed == "held behind the stop")

        // And it stays that way — no delayed fire.
        try? await Task.sleep(for: .milliseconds(150))
        #expect(client.sentMessages == ["stop me"])
    }

    @Test @MainActor
    func stopWithDivergedComposerKeepsLiveTextAndSurfacesTheHold() async throws {
        // Trap 7: the user typed NEW text after queueing. Last writer must
        // not win — the live text keeps the composer, the held text stays on
        // the chip for explicit restore.
        let persistence = Self.makePersistence()
        let client = ManualStreamClient()
        let store = ChatStore(hermesClient: client, persistence: persistence)
        store.composerLiveText = { "newly typed thought" }

        let sendTask = await startTurn("stop me", store: store, client: client)
        #expect(store.holdComposedTurn("the original held text"))

        store.cancelStreaming()
        _ = await sendTask.value

        #expect(client.sentMessages == ["stop me"])
        // The composer is NOT overwritten…
        #expect(store.pendingComposerSeed == nil)
        // …and the held text is still on the chip, surfaced for the user.
        let held = try #require(store.currentThreadHeldTurn)
        #expect(held.text == "the original held text")
        #expect(held.phase == .surfaced)
    }

    // MARK: - 306-D: three `.delivered` terminals, one fire (trap 3)

    @Test @MainActor
    func completedTerminalFiresAndLeavesRowDelivered() async throws {
        let persistence = Self.makePersistence()
        let client = ManualStreamClient()
        let store = ChatStore(hermesClient: client, persistence: persistence)

        let sendTask = await startTurn("arm one", store: store, client: client)
        #expect(store.holdComposedTurn("after completion"))
        client.autoFinishSends = true
        client.continuations.last?.yield(.finished(
            Message(sender: .hermes, content: "done", status: .delivered), nil, nil
        ))
        client.continuations.last?.finish()
        _ = await sendTask.value

        #expect(store.conversation?.messages.first {
            $0.sender == .user && $0.content == "arm one"
        }?.status == .delivered)
        let fired = await pollUntil { client.sentMessages.contains("after completion") }
        #expect(fired, "306-D arm 1: the completed terminal is the ONE that fires")
    }

    @Test @MainActor
    func stopTerminalLeavesRowDeliveredAndDoesNotFire() async throws {
        let persistence = Self.makePersistence()
        let client = ManualStreamClient()
        let store = ChatStore(hermesClient: client, persistence: persistence)
        store.composerLiveText = { "diverged so the hold stays visible" }

        let sendTask = await startTurn("arm two", store: store, client: client)
        #expect(store.holdComposedTurn("after stop"))
        store.cancelStreaming()
        _ = await sendTask.value

        // Same final row status as completion — which is exactly why the
        // fire must branch on the observed terminal, never on status.
        #expect(store.conversation?.messages.first {
            $0.sender == .user && $0.content == "arm two"
        }?.status == .delivered)
        try? await Task.sleep(for: .milliseconds(150))
        #expect(!client.sentMessages.contains("after stop"), "306-D arm 2: Stop must not fire")
    }

    @Test @MainActor
    func unrecoverableExpirationLeavesRowDeliveredSurfacesAndDoesNotFire() async throws {
        let persistence = Self.makePersistence()
        let client = ManualStreamClient()
        client.currentRunIsServerRecoverable = false
        let store = ChatStore(hermesClient: client, persistence: persistence)

        let sendTask = await startTurn("arm three", store: store, client: client)
        #expect(store.holdComposedTurn("after expiration"))
        // The continued-send expiration on a NON-recoverable plane (#295):
        // settles `.delivered` — the third `.delivered` terminal.
        store.cancelStreaming(hardStopHost: false)
        _ = await sendTask.value

        #expect(store.conversation?.messages.first {
            $0.sender == .user && $0.content == "arm three"
        }?.status == .delivered)
        try? await Task.sleep(for: .milliseconds(150))
        #expect(
            !client.sentMessages.contains("after expiration"),
            "306-D arm 3: `.delivered` here means settled, not answered — no fire"
        )
        // Row 10: HOLD + SURFACE — nothing is coming; the user decides.
        #expect(store.currentThreadHeldTurn?.phase == .surfaced)
    }

    @Test @MainActor
    func recoverableExpirationHoldsWithoutSurfacing() async throws {
        // Matrix row 9: a real reconcile is watching — identical to row 3.
        let persistence = Self.makePersistence()
        let client = ManualStreamClient()
        client.currentRunIsServerRecoverable = true
        // Recovery arming needs a session id to recover WITH — the journal
        // hop is that id's source (`activeSessionID`), as on the live path.
        let journal = ConversationJournalStore(persistence: persistence)
        let store = ChatStore(hermesClient: client, persistence: persistence, journal: journal)
        store.reconcileWallClockBudget = .seconds(30)
        store.reconcilePollInterval = .seconds(30)
        await store.loadConversationIfNeeded()
        journal.beginHop(apiSessionId: "api_row9", primingUsage: nil)

        let sendTask = await startTurn("expiring turn", store: store, client: client)
        #expect(store.holdComposedTurn("waiting on recovery"))
        store.cancelStreaming(hardStopHost: false)
        _ = await sendTask.value

        #expect(store.isTranscriptBusy, "recovery must be armed (pendingRun live)")
        let held = try #require(store.currentThreadHeldTurn)
        #expect(held.phase == .held, "row 9: HOLD — not surfaced, not fired")
        #expect(!client.sentMessages.contains("waiting on recovery"))
    }

    // MARK: - 306-E: a live pendingRun blocks the fire (and #307)

    @Test @MainActor
    func livePendingRunBlocksFireAndDrainUntilReconcileAdopts() async throws {
        let persistence = Self.makePersistence()
        let client = ManualStreamClient()
        let store = ChatStore(hermesClient: client, persistence: persistence)
        // Keep the self-arming reconcile loop patient so the test drives
        // resolution explicitly.
        store.reconcileWallClockBudget = .seconds(30)
        store.reconcilePollInterval = .seconds(30)

        // An `.unreachable` park from an earlier turn — #307's other actor.
        client.autoAccept = false
        let offlineTask = Task { @MainActor in await store.sendMessage("offline turn") }
        let parked = await pollUntil { client.continuations.count == 1 }
        #expect(parked)
        client.continuations[0].yield(.unreachable("down"))
        client.continuations[0].finish()
        _ = await offlineTask.value
        #expect(store.hasQueuedComposeTurns)
        client.autoAccept = true

        // The dropped-stream turn: committed server-side, stream lost.
        let sentBefore = Date.now
        let sendTask = await startTurn("turn two", store: store, client: client)
        #expect(store.holdComposedTurn("held follow"))
        client.continuations.last?.yield(.interrupted(sessionId: "S1", runId: "R1"))
        client.continuations.last?.finish()
        _ = await sendTask.value

        // The #278 window: isStreaming false, run very much alive.
        #expect(store.isStreaming == false)
        #expect(store.isTranscriptBusy)

        // #307: the reachability path must NOT drain into the live run.
        client.autoFinishSends = true
        await store.refreshDirectHealth()
        await store.drainComposeOutboxIfPossible()
        #expect(
            client.sentMessages == ["offline turn", "turn two"],
            "#307: the outbox drained into a live run during the reconcile window"
        )
        #expect(
            !client.sentMessages.contains("held follow"),
            "306-E: the fire must wait for the pendingRun to resolve"
        )

        // The dropped run's reply lands server-side; reconcile adopts it.
        var serverConvo = Conversation(title: Conversation.defaultTitle)
        serverConvo.messages = [
            Message(sender: .user, content: "turn two",
                    timestamp: sentBefore.addingTimeInterval(1), status: .delivered),
            Message(sender: .hermes, content: "the dropped run's answer",
                    timestamp: sentBefore.addingTimeInterval(30), status: .delivered),
        ]
        client.reconcileConversation = serverConvo
        await store.reconcilePendingRuns()

        // The adopted reply is the DROPPED run's — the queued turn was never
        // posted, so it cannot have been adopted as the answer.
        #expect(store.conversation?.messages.contains {
            $0.sender == .hermes && $0.content == "the dropped run's answer"
        } == true)

        // Resolution clears the run; the fire (and the parked turn's drain)
        // now proceed, oldest-first.
        let drained = await pollUntil { client.sentMessages.contains("held follow") }
        #expect(drained, "the held message fires once the reconcile resolves")
        let offlineIdx = try #require(client.sentMessages.lastIndex(of: "offline turn"))
        let heldIdx = try #require(client.sentMessages.lastIndex(of: "held follow"))
        #expect(offlineIdx < heldIdx, "one store, one order — oldest first")
    }

    @Test @MainActor
    func reconcileBudgetExpirySurfacesInsteadOfFiring() async throws {
        // Matrix row 3's tail: budget out, no adoption → SURFACE, never
        // silently fire.
        let persistence = Self.makePersistence()
        let client = ManualStreamClient()
        let store = ChatStore(hermesClient: client, persistence: persistence)
        store.reconcileWallClockBudget = .milliseconds(80)
        store.reconcilePollInterval = .milliseconds(10)
        // #368 (3E): this pending run carries an id (`R2`), so the loop reads
        // the run-recovery pair. Shortened to the same values — the bar is
        // "budget expiry SURFACEs", and which knob names the budget is not
        // what it measures.
        store.runRecoveryWallClockBudget = .milliseconds(80)
        store.runRecoveryPollInterval = .milliseconds(10)

        let sendTask = await startTurn("dropped turn", store: store, client: client)
        #expect(store.holdComposedTurn("held past the budget"))
        client.continuations.last?.yield(.interrupted(sessionId: "S1", runId: "R2"))
        client.continuations.last?.finish()
        _ = await sendTask.value

        let surfaced = await pollUntil {
            store.currentThreadHeldTurn?.phase == .surfaced
        }
        #expect(surfaced, "row 3: budget expiry with no adoption SURFACEs the hold")
        #expect(!client.sentMessages.contains("held past the budget"))
    }

    // MARK: - Rows 6/7: failed terminals

    @Test @MainActor
    func outrightFailureSurfacesTheHold() async throws {
        let persistence = Self.makePersistence()
        let client = ManualStreamClient()
        client.autoAccept = false
        let store = ChatStore(hermesClient: client, persistence: persistence)

        let sendTask = await startTurn("failing turn", store: store, client: client)
        #expect(store.holdComposedTurn("follow-up to a failure"))
        client.continuations.last?.yield(.failed("boom"))
        client.continuations.last?.finish()
        _ = await sendTask.value

        // Row 6: HOLD + SURFACE — auto-firing would send a non-sequitur into
        // a session whose last turn errored.
        #expect(store.currentThreadHeldTurn?.phase == .surfaced)
        try? await Task.sleep(for: .milliseconds(150))
        #expect(!client.sentMessages.contains("follow-up to a failure"))
    }

    @Test @MainActor
    func failureAfterAcceptKeepsHolding() async throws {
        let persistence = Self.makePersistence()
        let client = ManualStreamClient()
        let store = ChatStore(hermesClient: client, persistence: persistence)

        let sendTask = await startTurn("accepted turn", store: store, client: client)
        #expect(store.holdComposedTurn("waiting on the poll"))
        client.continuations.last?.yield(.failed("stream died post-accept"))
        client.continuations.last?.finish()
        _ = await sendTask.value

        // Row 7: the turn is NOT over — the poll loop owns it.
        #expect(store.currentThreadHeldTurn?.phase == .held)
        #expect(!client.sentMessages.contains("waiting on the poll"))
    }

    // MARK: - 306-F: no transcript row before the send

    @Test @MainActor
    func noRowExistsThroughHoldEditAndCancel() async throws {
        let persistence = Self.makePersistence()
        let client = ManualStreamClient()
        let store = ChatStore(hermesClient: client, persistence: persistence)

        let sendTask = await startTurn("turn one", store: store, client: client)

        #expect(store.holdComposedTurn("draft one"))
        #expect(store.conversation?.messages.contains { $0.content == "draft one" } == false)

        // Edit hands the text back and removes the entry — still no row.
        #expect(store.editHeldTurn() == "draft one")
        #expect(store.currentThreadHeldTurn == nil)
        #expect(store.conversation?.messages.contains { $0.content == "draft one" } == false)

        // Re-hold, then cancel — the affordance 306-J pins: removed, nothing
        // posted.
        #expect(store.holdComposedTurn("draft two"))
        store.cancelHeldTurn()
        #expect(store.currentThreadHeldTurn == nil)
        #expect(persistence.loadComposeOutboxState().pendingTurns.isEmpty)

        client.autoFinishSends = true
        client.continuations.last?.yield(.finished(
            Message(sender: .hermes, content: "done", status: .delivered), nil, nil
        ))
        client.continuations.last?.finish()
        _ = await sendTask.value

        // Nothing left to fire.
        try? await Task.sleep(for: .milliseconds(150))
        #expect(client.sentMessages == ["turn one"])
        #expect(store.conversation?.messages.contains { $0.content == "draft two" } == false)
    }

    // MARK: - 306-J: the door vocabulary (unit half)

    @Test
    func composerDoorIsExhaustiveAndNeverSaysSent() {
        // C1 made testable: the enum carries all three doors, every door
        // renders, and no rendered string for an unposted message contains
        // any form of "sent".
        #expect(Set(ComposerDoor.allCases) == Set([.queued, .steered, .interrupted]))
        for door in ComposerDoor.allCases {
            #expect(!door.displayName.isEmpty)
            #expect(!door.waitingStatusLine.isEmpty)
            #expect(!door.displayName.localizedCaseInsensitiveContains("sent"))
            #expect(!door.waitingStatusLine.localizedCaseInsensitiveContains("sent"))
        }
        #expect(!ComposerDoor.surfacedStatusLine.localizedCaseInsensitiveContains("sent"))

        let waiting = QueuedTurnChipModel(text: "queued text", door: .queued, isSurfaced: false)
        let surfaced = QueuedTurnChipModel(text: "queued text", door: .queued, isSurfaced: true)
        #expect(waiting.statusLine == ComposerDoor.queued.waitingStatusLine)
        #expect(surfaced.statusLine == ComposerDoor.surfacedStatusLine)
        #expect(!waiting.statusLine.localizedCaseInsensitiveContains("sent"))
        #expect(!surfaced.statusLine.localizedCaseInsensitiveContains("sent"))
    }

    // MARK: - #315: the composer's DOOR during the reconcile window

    /// Drives the store into the real #278 window: a turn goes out, its
    /// stream is `.interrupted` (committed server-side, connection lost), and
    /// what is left is `streamingMessageID == nil` with a live `pendingRun`.
    /// The reconcile budget is kept patient so the window does not close
    /// underneath the assertions.
    @MainActor
    private func enterReconcileWindow(
        turn: String = "dropped turn",
        store: ChatStore,
        client: ManualStreamClient
    ) async throws {
        store.reconcileWallClockBudget = .seconds(30)
        store.reconcilePollInterval = .seconds(30)
        let sendTask = await startTurn(turn, store: store, client: client)
        client.continuations.last?.yield(.interrupted(sessionId: "S315", runId: "R315"))
        client.continuations.last?.finish()
        _ = await sendTask.value
        #expect(store.isStreaming == false, "the window's first half: no stream")
        #expect(store.isTranscriptBusy, "the window's other half: the run is live")
    }

    /// The composer's commit, entered THROUGH the door — the door decides,
    /// then `ChatScreen.queueComposedMessage()`'s body runs (hold; fall
    /// through to a post only when the transcript is genuinely idle).
    ///
    /// The post arms REPORT rather than perform. Performing one against the
    /// manual-drive client parks the caller on a stream nothing will finish,
    /// so the pre-fix run HANGS instead of failing — and a hang carries no
    /// verdict at all. What the bar asks is which door the composer chose;
    /// `"posted"` is that answer, and it is the answer #315 forbids here.
    @MainActor
    private func commitThroughTheDoor(_ text: String, store: ChatStore) -> String {
        let door = ChatInputBar.resolveDoor(
            store: store,
            canSend: !text.isEmpty,
            canQueueMessage: store.currentThreadHeldTurn == nil,
            isSlashMode: text.hasPrefix("/"),
            sendBlockedByAttachments: false
        )
        switch door {
        case .queueCommit:
            if store.holdComposedTurn(text) { return "held" }
            return store.isTranscriptBusy ? "refused" : "posted"
        case .send:
            return "posted"
        case .busyNoCommit, .blockedByAttachments, .inert:
            return "refused"
        }
    }

    // MARK: - 315-A: the door itself

    /// **315-A.** In the reconcile window the composer must offer the
    /// QUEUE/HOLD path, never plain Send — a plain Send there posts into the
    /// live `pendingRun`, and `attemptReconcile` can then pair the dropped
    /// run's recovery with the manual turn's reply (#307's mechanism,
    /// user-driven). RED before the fix: the door read `isStreaming`, which
    /// is false for this entire window.
    @Test @MainActor
    func reconcileWindowDoorOffersTheQueueNeverPlainSend() async throws {
        let persistence = Self.makePersistence()
        let client = ManualStreamClient()
        let store = ChatStore(hermesClient: client, persistence: persistence)
        try await enterReconcileWindow(store: store, client: client)

        #expect(
            ChatInputBar.resolveDoor(
                store: store, canSend: true, canQueueMessage: true,
                isSlashMode: false, sendBlockedByAttachments: false
            ) == .queueCommit,
            "#315: the composer offered plain Send into a live pendingRun"
        )
        // The two arms that must NOT re-open plain Send by falling through:
        // the thread's single hold slot is taken, and a slash draft (which
        // is never held — #306's own refusal).
        #expect(
            ChatInputBar.resolveDoor(
                store: store, canSend: true, canQueueMessage: false,
                isSlashMode: false, sendBlockedByAttachments: false
            ) == .busyNoCommit,
            "#315: a taken hold slot re-opened plain Send inside the window"
        )
        #expect(
            ChatInputBar.resolveDoor(
                store: store, canSend: true, canQueueMessage: true,
                isSlashMode: true, sendBlockedByAttachments: false
            ) == .busyNoCommit,
            "#315: a slash draft posted into a live run"
        )
    }

    // MARK: - 315-B: a turn committed THROUGH the door fires once, after adoption

    /// **315-B.** Bar 306-E's fixture, entered through the door and with the
    /// commit made DURING the window rather than while streaming. The held
    /// turn must not post until `attemptReconcile` adopts the dropped run's
    /// reply, and then exactly once — the #307 mechanism must not find a new
    /// way in through the door #315 opens.
    @Test @MainActor
    func turnCommittedThroughTheDoorFiresOnceAfterReconcileAdopts() async throws {
        let persistence = Self.makePersistence()
        let client = ManualStreamClient()
        let store = ChatStore(hermesClient: client, persistence: persistence)
        let sentBefore = Date.now
        try await enterReconcileWindow(turn: "turn two", store: store, client: client)

        // The manual send #315 is about: composed and committed mid-window.
        let outcome = commitThroughTheDoor("manual mid-window turn", store: store)
        #expect(outcome == "held", "#315: the mid-window commit was posted, not held")
        #expect(
            !client.sentMessages.contains("manual mid-window turn"),
            "#315: the manual turn reached the wire while a run was live"
        )
        #expect(store.currentThreadHeldTurn?.phase == .held)

        // Reachability alone must not shake it loose (#307's guard).
        client.autoFinishSends = true
        await store.refreshDirectHealth()
        await store.drainComposeOutboxIfPossible()
        #expect(client.sentMessages == ["turn two"])

        // The dropped run's reply lands server-side; the reconcile adopts it.
        var serverConvo = Conversation(title: Conversation.defaultTitle)
        serverConvo.messages = [
            Message(sender: .user, content: "turn two",
                    timestamp: sentBefore.addingTimeInterval(1), status: .delivered),
            Message(sender: .hermes, content: "the dropped run's answer",
                    timestamp: sentBefore.addingTimeInterval(30), status: .delivered),
        ]
        client.reconcileConversation = serverConvo
        await store.reconcilePendingRuns()

        #expect(store.conversation?.messages.contains {
            $0.sender == .hermes && $0.content == "the dropped run's answer"
        } == true, "the adopted reply must be the DROPPED run's, not the manual turn's")

        let fired = await pollUntil { client.sentMessages.contains("manual mid-window turn") }
        #expect(fired, "the held turn fires once the reconcile resolves")
        // Exactly once — a second fire would be the duplicate #306's release
        // discipline exists to prevent.
        try? await Task.sleep(for: .milliseconds(150))
        #expect(
            client.sentMessages.filter { $0 == "manual mid-window turn" }.count == 1,
            "#315/306: the held turn fired more than once"
        )
    }

    // MARK: - 315-C: no regression on the doors #315 does not touch

    /// **315-C.** An idle transcript still offers plain Send (and the #8
    /// blocked/inert arms are untouched); a STREAMING transcript still offers
    /// exactly what #306 T5 shipped — the queue-commit control beside Stop,
    /// suppressed for a slash draft or a taken hold slot.
    @Test @MainActor
    func idleAndStreamingDoorsAreUnchanged() async throws {
        let persistence = Self.makePersistence()
        let client = ManualStreamClient()
        let store = ChatStore(hermesClient: client, persistence: persistence)
        await store.loadConversationIfNeeded()

        #expect(store.isTranscriptBusy == false)
        #expect(ChatInputBar.resolveDoor(
            store: store, canSend: true, canQueueMessage: true,
            isSlashMode: false, sendBlockedByAttachments: false
        ) == .send, "idle: plain Send, unchanged")
        #expect(ChatInputBar.resolveDoor(
            store: store, canSend: true, canQueueMessage: true,
            isSlashMode: true, sendBlockedByAttachments: false
        ) == .send, "idle: a slash draft still posts — the door never held those")
        #expect(ChatInputBar.resolveDoor(
            store: store, canSend: false, canQueueMessage: true,
            isSlashMode: false, sendBlockedByAttachments: true
        ) == .blockedByAttachments, "#8's dimmed arrow, unchanged")
        #expect(ChatInputBar.resolveDoor(
            store: store, canSend: false, canQueueMessage: true,
            isSlashMode: false, sendBlockedByAttachments: false
        ) == .inert, "idle with an empty composer: no commit control")

        let sendTask = await startTurn("streaming turn", store: store, client: client)
        #expect(store.isStreaming)
        #expect(ChatInputBar.resolveDoor(
            store: store, canSend: true, canQueueMessage: true,
            isSlashMode: false, sendBlockedByAttachments: false
        ) == .queueCommit, "streaming: #306 T5's third state, unchanged")
        #expect(ChatInputBar.resolveDoor(
            store: store, canSend: true, canQueueMessage: true,
            isSlashMode: true, sendBlockedByAttachments: false
        ) == .busyNoCommit, "streaming: a slash draft is still refused, not held")
        #expect(ChatInputBar.resolveDoor(
            store: store, canSend: true, canQueueMessage: false,
            isSlashMode: false, sendBlockedByAttachments: false
        ) == .busyNoCommit, "streaming: depth 1 — a taken slot offers Stop only")

        client.continuations.last?.yield(.finished(
            Message(sender: .hermes, content: "done", status: .delivered), nil, nil
        ))
        client.continuations.last?.finish()
        _ = await sendTask.value
    }

    // MARK: - #321: Stop inside the reconcile window is a WHOLE Stop

    /// A transcript state, reduced to the parts a user can see, so bar 321-C
    /// can compare two Stops for equality instead of eyeballing two lists of
    /// assertions. Row identity (`UUID`) is deliberately excluded — it differs
    /// between two independent runs by construction and is not user-visible.
    ///
    /// **#327 bar 327-C — WIDENED to carry tool-activity state, and this is
    /// the whole reason #327 exists.** The projection shipped omitting it, so
    /// it could not fail on the ONE field where the two Stop paths actually
    /// diverge: 321-C passed, honestly, while being too broad. A projection
    /// that omits a field will report equality forever and read as rigorous
    /// doing it — **naming the fields IS the bar.** `Activity` carries exactly
    /// what `ToolActivityRail.state(of:)` reads, plus the label, so a
    /// divergence names the tool it happened on.
    private struct StopOutcome: Equatable, CustomStringConvertible {
        struct Activity: Equatable {
            let label: String
            let isActive: Bool
            let failure: String?
            /// The rendered answer, not a re-derivation of it — bar 327-B's
            /// "assert through the real mapping" clause, pinned inside the
            /// projection so no future comparison can drop it.
            let renderedState: ToolActivityRail.StepState
        }
        struct Row: Equatable {
            let sender: MessageSender
            let content: String
            let status: MessageStatus
            let isStreaming: Bool
            let activities: [Activity]
            let summaryState: ToolActivityRail.StepState?
        }
        let rows: [Row]
        let isStreaming: Bool
        let isTranscriptBusy: Bool
        let hasPendingRun: Bool
        let hasActiveReconcileLoop: Bool
        let composerSeed: String?
        let heldTurnPhase: ComposeOutboxState.Phase?

        var description: String {
            let renderedRows = rows.map { row in
                let acts = row.activities
                    .map { "\($0.label)[active:\($0.isActive) fail:\($0.failure ?? "nil") → \($0.renderedState)]" }
                    .joined(separator: ",")
                return "\(row.sender)/\(row.content)/\(row.status)/streaming:\(row.isStreaming)"
                    + "/acts:[\(acts)]/summary:\(row.summaryState.map { "\($0)" } ?? "none")"
            }
            return "rows=\(renderedRows) "
                + "streaming=\(isStreaming) busy=\(isTranscriptBusy) pendingRun=\(hasPendingRun) "
                + "reconcileLoop=\(hasActiveReconcileLoop) seed=\(composerSeed ?? "nil") held=\(String(describing: heldTurnPhase))"
        }

        @MainActor init(_ store: ChatStore) {
            rows = (store.conversation?.messages ?? []).map { message in
                Row(
                    sender: message.sender,
                    content: message.content,
                    status: message.status,
                    isStreaming: message.isStreaming,
                    activities: message.toolActivities.map {
                        Activity(
                            label: $0.label,
                            isActive: $0.isActive,
                            failure: $0.failure,
                            renderedState: ToolActivityRail.state(of: $0)
                        )
                    },
                    summaryState: message.toolActivities.isEmpty
                        ? nil : ToolActivityRail.summaryState(of: message.toolActivities)
                )
            }
            isStreaming = store.isStreaming
            isTranscriptBusy = store.isTranscriptBusy
            hasPendingRun = store.pendingRunSessionId != nil
            hasActiveReconcileLoop = store.hasActiveReconcileLoop
            composerSeed = store.pendingComposerSeed
            heldTurnPhase = store.currentThreadHeldTurn?.phase
        }
    }

    /// **321-A + 321-B.** The finding and the fix, in one test and in the
    /// order the bars name them.
    ///
    /// RED at HEAD: `cancelStreaming` never touched `pendingRun` — the only
    /// writer that cleared it was `abandonPendingRun`, whose callers are the
    /// walk-away paths — so the first `#expect` below failed and the composer
    /// stayed on the busy door until the reconcile budget expired (up to
    /// ~120s after the user tapped Stop).
    ///
    /// The tail is 321-E's own clause, asserted rather than assumed: nothing
    /// may arm a recovery for a run the user abandoned.
    @Test @MainActor
    func windowStopAbandonsThePendingRunAndFreesTheComposer() async throws {
        let persistence = Self.makePersistence()
        let client = ManualStreamClient()
        let store = ChatStore(hermesClient: client, persistence: persistence)
        store.composerLiveText = { "" }
        try await enterReconcileWindow(store: store, client: client)
        #expect(store.pendingRunSessionId == "S315", "fixture: the window's run must be live before the Stop")
        #expect(store.isTranscriptBusy)
        #expect(store.hasActiveReconcileLoop)

        store.cancelStreaming()

        #expect(store.pendingRunSessionId == nil,
                "321-A/B: Stop must ABANDON the pendingRun — this is the assertion that is RED at HEAD")
        #expect(store.isTranscriptBusy == false,
                "321-B: the composer's other busy half must clear in the same call")
        #expect(store.hasActiveReconcileLoop == false,
                "321-B: 'free the composer immediately' includes ending the live recovery")
        #expect(
            ChatInputBar.resolveDoor(
                store: store, canSend: true, canQueueMessage: true,
                isSlashMode: false, sendBlockedByAttachments: false
            ) == .send,
            "321-B: the composer's door is the IDLE one — #315's queue door is gone with the run"
        )

        // 321-E: the abandoned run must not be re-adopted by the foreground
        // reconcile chain, and must not re-arm the loop it just lost.
        await store.reconcilePendingRuns()
        #expect(client.reconcileCallCount == 0,
                "321-E: an abandoned run must not be reconciled — nothing is watching it any more")
        #expect(store.hasActiveReconcileLoop == false,
                "321-E: nothing may arm a recovery for a run the user abandoned")
    }

    /// **321-C — one Stop story.** Ruling (b): the transcript a window Stop
    /// produces is pinned EQUAL to the transcript a live-stream Stop
    /// produces. Same fixture text, same client, same empty composer; only
    /// the moment of the Stop differs.
    ///
    /// The equality is reachable because both arms converge on the same
    /// shape: a live-stream Stop taken before any prose REMOVES the
    /// placeholder (#294) and settles the user row `.delivered`, and the
    /// window's placeholder was already removed by the `.interrupted` arm
    /// (#295) — so the abandon only has to settle the row the same way.
    @Test @MainActor
    func aWindowStopProducesTheSameTranscriptStateAsALiveStreamStop() async throws {
        let liveStopped: StopOutcome
        do {
            let client = ManualStreamClient()
            let store = ChatStore(hermesClient: client, persistence: Self.makePersistence())
            store.composerLiveText = { "" }
            let sendTask = await startTurn("one stop story", store: store, client: client)
            store.cancelStreaming()
            _ = await sendTask.value
            liveStopped = StopOutcome(store)
        }

        let windowStopped: StopOutcome
        do {
            let client = ManualStreamClient()
            let store = ChatStore(hermesClient: client, persistence: Self.makePersistence())
            store.composerLiveText = { "" }
            try await enterReconcileWindow(turn: "one stop story", store: store, client: client)
            store.cancelStreaming()
            windowStopped = StopOutcome(store)
        }

        #expect(
            windowStopped == liveStopped,
            "321-C: a window Stop must look exactly like a live-stream Stop.\n  window: \(windowStopped)\n  live:   \(liveStopped)"
        )
        // Named explicitly so a future regression says WHICH half moved
        // rather than only that the two diverged.
        //
        // **Row count amended 2026-08-11 by #328 route 2, and the amendment is
        // the point of the bar rather than an exception to it.** It was 1 (the
        // user row alone). It is now 2: neither arm's Stop reaches the host on
        // the sessions plane, so BOTH append the honest `.system` notice — and
        // the fact that both do is exactly what keeps ruling (b)'s one Stop
        // story true. A count that moved on only ONE arm would fail the
        // equality above, which is the assertion that matters.
        #expect(windowStopped.rows.count == 2)
        #expect(windowStopped.rows.first?.status == .delivered,
                "321-C: the abandoned turn's user row settles where a stopped turn's does")
        #expect(windowStopped.rows.last?.sender == .system,
                "#328 route 2: the honest notice is the second row, on both arms")
        #expect(windowStopped.hasPendingRun == false)
        #expect(windowStopped.isTranscriptBusy == false)
    }

    /// **321-D.** Ruling (c): a message committed through #315's door and then
    /// Stopped comes BACK to the composer as text — it mints no transcript
    /// row and never auto-fires.
    ///
    /// RED at HEAD for a second reason beyond the pendingRun: `cancelStreaming`
    /// opens with `terminatedALiveTurn = streamingMessageID != nil`, which is
    /// false for this entire window, so `resolveHeldTurn` was never called at
    /// all and the hold sat in the outbox with no chip and no restore.
    @Test @MainActor
    func aMidWindowHoldIsRestoredToTheComposerOnStop() async throws {
        let persistence = Self.makePersistence()
        let client = ManualStreamClient()
        let store = ChatStore(hermesClient: client, persistence: persistence)
        store.composerLiveText = { "" }
        try await enterReconcileWindow(store: store, client: client)

        #expect(commitThroughTheDoor("held behind the window stop", store: store) == "held")
        #expect(store.currentThreadHeldTurn?.phase == .held)

        store.cancelStreaming()

        #expect(store.currentThreadHeldTurn == nil,
                "321-D: the hold leaves the queue — it is text again, not a queued turn")
        #expect(store.pendingComposerSeed == "held behind the window stop",
                "321-D: the held text lands back in the composer (#48 seed, seed-only)")
        #expect(
            store.conversation?.messages.contains { $0.content == "held behind the window stop" } != true,
            "321-D: a restored hold mints NO transcript row"
        )
        // And it does not fire, then or later — the busy gate is down now, so
        // a fire would be reachable if anything scheduled one.
        client.autoFinishSends = true
        try? await Task.sleep(for: .milliseconds(200))
        #expect(client.sentMessages == ["dropped turn"],
                "321-D: a Stopped hold must never auto-fire (#306 T3 row 2)")
    }

    /// **321-C/D, trap 7.** The other half of "the same treatment": with the
    /// user's own text live in the composer, a window Stop must SURFACE the
    /// hold on the chip rather than overwrite what they typed — byte-for-byte
    /// what `stopWithDivergedComposerKeepsLiveTextAndSurfacesTheHold` pins for
    /// a live-stream Stop.
    @Test @MainActor
    func aMidWindowHoldWithADivergedComposerSurfacesInsteadOfOverwriting() async throws {
        let persistence = Self.makePersistence()
        let client = ManualStreamClient()
        let store = ChatStore(hermesClient: client, persistence: persistence)
        store.composerLiveText = { "newly typed thought" }
        try await enterReconcileWindow(store: store, client: client)

        #expect(commitThroughTheDoor("the original held text", store: store) == "held")
        store.cancelStreaming()

        #expect(store.pendingComposerSeed == nil, "trap 7: last writer must not win")
        let held = try #require(store.currentThreadHeldTurn)
        #expect(held.text == "the original held text")
        #expect(held.phase == .surfaced)
        #expect(store.pendingRunSessionId == nil, "321-B still holds on the diverged arm")
    }

    /// **321-E, the guard the other direction.** The abandon is gated on an
    /// explicit Stop. A DEFENSIVE cancel — nothing streaming, nothing pending
    /// — must still restore nothing and surface nothing (#306's reason for
    /// `terminatedALiveTurn` in the first place), and the continued-send
    /// EXPIRATION path (`hardStopHost: false`) must leave a live window's
    /// recovery exactly where it found it: the system revoking a background
    /// budget is not the user abandoning a run.
    @Test @MainActor
    func neitherADefensiveCancelNorAnExpirationAbandonsTheWindow() async throws {
        let persistence = Self.makePersistence()
        let client = ManualStreamClient()
        let store = ChatStore(hermesClient: client, persistence: persistence)
        store.composerLiveText = { "" }

        // Arm 1: a defensive cancel on a wholly idle store.
        await store.loadConversationIfNeeded()
        store.cancelStreaming()
        #expect(store.pendingComposerSeed == nil)
        #expect(store.currentThreadHeldTurn == nil)

        // Arm 2: the expiration path meeting a live window.
        try await enterReconcileWindow(store: store, client: client)
        #expect(commitThroughTheDoor("held through an expiration", store: store) == "held")
        store.cancelStreaming(hardStopHost: false)
        #expect(store.pendingRunSessionId == "S315",
                "321-E: a SYSTEM-revoked budget must not throw away a live recovery — only a user Stop abandons")
        #expect(store.isTranscriptBusy)
        #expect(store.currentThreadHeldTurn?.phase == .held,
                "321-E: the hold keeps HOLDING while the reconcile still owns the run (#306 row 3)")
        #expect(store.pendingComposerSeed == nil)
    }

    // MARK: - #327: a Stop in the window must not leave a killed call as ✓

    /// The one tool activity a reconcile-window Stop can EVER meet, built the
    /// way production builds it.
    ///
    /// **Measured, not assumed** (probe on `f7c493d`, recorded at #327): the
    /// window cannot hold an ACTIVE activity, because `armPendingRunRecovery`
    /// removes the placeholder — and its activities with it — on the way in,
    /// and it is one of only two writers of `pendingRun`. So the chip has to
    /// arrive the other way: from HISTORY RESTORE, through the ordinary
    /// refresh merge, on a tool-calls-only assistant row.
    ///
    /// The row's shape is copied from `SessionsHermesClient.decodeStoredMessage`
    /// rather than invented — `isActive: false`, `failure: nil`, `.delivered`,
    /// empty content (that decoder explicitly keeps a tool-calls-only row:
    /// *"the text lands on a later row"*). If that decoder ever stops
    /// hardcoding those, this fixture is what should be updated to match it.
    @MainActor
    private static func historyRestoredToolCallRow(
        _ label: String, at timestamp: Date
    ) -> Message {
        Message(
            sender: .hermes,
            content: "",
            timestamp: timestamp,
            status: .delivered,
            toolActivities: [ToolActivity(label: label, startedAt: timestamp, isActive: false)]
        )
    }

    /// Drives the window and then lets a refresh land the run's history row,
    /// exactly as a foreground/appear refresh does on device.
    @MainActor
    private func enterWindowThenRefreshHistory(
        turn: String,
        toolLabel: String,
        store: ChatStore,
        client: ManualStreamClient
    ) async throws {
        try await enterReconcileWindow(turn: turn, store: store, client: client)
        var server = Conversation(title: Conversation.defaultTitle)
        server.messages = [
            Message(sender: .user, content: turn, status: .delivered),
            Self.historyRestoredToolCallRow(toolLabel, at: .now)
        ]
        client.currentConversation = server
        await store.loadConversation()
        #expect(store.pendingRunSessionId == "S315",
                "fixture: the refresh must not have resolved the window — the run is still live")
    }

    /// **327-A + 327-B.** The finding and the fix.
    ///
    /// RED at `f7c493d`: `cancelStreaming` writes its marker only inside
    /// `else if let sid = streamingMessageID …`, and `streamingMessageID` is
    /// nil for the whole window by definition (#278) — so nothing was marked,
    /// `failure` stayed nil, and `ToolActivityRail.state(of:)` drew the
    /// checkmark on a call the user had just killed. That is what Owen saw.
    ///
    /// 327-B is asserted through the REAL mapping (`state(of:)` and
    /// `summaryState(of:)` on the store's own activity), not on a hand-built
    /// `ToolActivity` — the #296 C1-D precedent: pin the mapping, not the ends.
    @Test @MainActor
    func aWindowStopMarksTheKilledCallInsteadOfLeavingItCompleted() async throws {
        let client = ManualStreamClient()
        let store = ChatStore(hermesClient: client, persistence: Self.makePersistence())
        store.composerLiveText = { "" }
        try await enterWindowThenRefreshHistory(
            turn: "sleep 90 && echo Done", toolLabel: "terminal", store: store, client: client
        )

        let before = try #require(
            store.conversation?.messages.first(where: { !$0.toolActivities.isEmpty })?.toolActivities.first,
            "fixture: the refresh must have landed the run's tool-call row"
        )
        #expect(ToolActivityRail.state(of: before) == .completed,
                "fixture: history restores a chip as ✓ — that is the state the Stop has to correct")

        store.cancelStreaming()

        let after = try #require(
            store.conversation?.messages.first(where: { !$0.toolActivities.isEmpty })?.toolActivities.first,
            "327-A: the Stop must not delete the row it cannot resolve"
        )
        #expect(after.failure == ToolActivity.stoppedByUser,
                "327-A: RED at f7c493d — the window Stop wrote no marker at all, so a killed call kept rendering ✓")
        #expect(after.isActive == false)
        #expect(ToolActivityRail.state(of: after) == .interrupted,
                "327-B: the rail then draws the truth, through the real mapping")
        #expect(
            ToolActivityRail.summaryState(of:
                store.conversation?.messages.first(where: { !$0.toolActivities.isEmpty })?.toolActivities ?? []
            ) == .interrupted,
            "327-B: and the collapsed chip follows"
        )
    }

    /// **327-A's scope guard, and it is 296-B restated.** The marking is
    /// confined to the ABANDONED RUN's rows (`timestamp > pendingRun.sentAt`).
    /// An earlier turn's activity — including the orphaned-but-active case
    /// `ToolActivityRail.summaryState`'s own comment names and deliberately
    /// renders `.completed` — is a different turn's business and must survive
    /// this Stop untouched.
    ///
    /// Without the scope this test is RED in the other direction: a blanket
    /// sweep would stamp "Stopped" on work that finished before the user ever
    /// pressed anything.
    @Test @MainActor
    func aWindowStopLeavesAnEarlierTurnsToolActivityAlone() async throws {
        let client = ManualStreamClient()
        let store = ChatStore(hermesClient: client, persistence: Self.makePersistence())
        store.composerLiveText = { "" }

        // An older turn, settled long before this run was sent.
        var seeded = Conversation(title: Conversation.defaultTitle)
        let old = Date(timeIntervalSinceNow: -3600)
        seeded.messages = [
            Message(sender: .user, content: "earlier question", timestamp: old, status: .delivered),
            Message(
                sender: .hermes, content: "earlier answer", timestamp: old, status: .delivered,
                toolActivities: [
                    ToolActivity(label: "read_file", startedAt: old, isActive: false),
                    // The orphan: a `tool.started` nobody ever resolved. 296-B
                    // says it stays `.completed`; this Stop must not touch it.
                    ToolActivity(label: "orphaned_call", startedAt: old, isActive: true)
                ]
            )
        ]
        client.currentConversation = seeded
        await store.loadConversation()

        try await enterWindowThenRefreshHistory(
            turn: "sleep 90 && echo Done", toolLabel: "terminal", store: store, client: client
        )
        store.cancelStreaming()

        let earlier = try #require(
            store.conversation?.messages.first(where: { $0.content == "earlier answer" })
        )
        #expect(earlier.toolActivities.map(\.failure) == [nil, nil],
                "296-B: an earlier turn's activities are not this Stop's business")
        #expect(earlier.toolActivities.last?.isActive == true,
                "296-B: including the orphan — it stays exactly as it shipped")
        #expect(
            store.conversation?.messages.last(where: { $0.toolActivities.contains { $0.label == "terminal" } })?
                .toolActivities.first?.failure == ToolActivity.stoppedByUser,
            "327-A: the abandoned run's own call IS marked, in the same call"
        )
    }

    /// **327-C — the widened projection, shown RED.**
    ///
    /// 321-C compared an `Equatable` `StopOutcome` that omitted tool-activity
    /// state, so it could not fail on the one field where the two Stop paths
    /// diverge. It passed while being too broad, and #327 shipped underneath
    /// it. With the field named, the same comparison — a live-stream Stop and
    /// a window Stop, each taken with a tool call unresolved — is RED at
    /// `f7c493d`: the live arm's chip reads `Stopped`/`.interrupted`, the
    /// window arm's reads `nil`/`.completed`.
    ///
    /// The two arms converge on the same rendered row after the fix, which is
    /// ruling (b)'s one Stop story holding for the case that actually broke it.
    @Test @MainActor
    func bothStopsAgreeOnWhatHappenedToAnUnresolvedToolCall() async throws {
        let liveStopped: StopOutcome
        do {
            let client = ManualStreamClient()
            let store = ChatStore(hermesClient: client, persistence: Self.makePersistence())
            store.composerLiveText = { "" }
            let sendTask = await startTurn("sleep 90 && echo Done", store: store, client: client)
            client.continuations.last?.yield(
                .toolActivity(ToolCallEvent(name: "terminal", phase: .started, detail: "sleep 90"))
            )
            _ = await pollUntil {
                store.conversation?.messages.contains { !$0.toolActivities.isEmpty } == true
            }
            store.cancelStreaming()
            client.continuations.last?.finish()
            _ = await sendTask.value
            liveStopped = StopOutcome(store)
        }

        let windowStopped: StopOutcome
        do {
            let client = ManualStreamClient()
            let store = ChatStore(hermesClient: client, persistence: Self.makePersistence())
            store.composerLiveText = { "" }
            try await enterWindowThenRefreshHistory(
                turn: "sleep 90 && echo Done", toolLabel: "terminal", store: store, client: client
            )
            store.cancelStreaming()
            windowStopped = StopOutcome(store)
        }

        let liveChip = liveStopped.rows.flatMap(\.activities)
        let windowChip = windowStopped.rows.flatMap(\.activities)
        #expect(
            liveChip == windowChip,
            "327-C: the two Stops must agree about the call they both killed.\n  window: \(windowChip)\n  live:   \(liveChip)"
        )
        #expect(windowChip.map(\.renderedState) == [.interrupted],
                "327-C: and the agreed answer is the honest one, not the checkmark")
        #expect(liveChip.map(\.failure) == [ToolActivity.stoppedByUser],
                "327-D: the live-stream Stop's own marker behaviour is unchanged by this lane")
    }

    // MARK: - #328 route 2: say what Stop actually did

    /// **328-R2-A.** The seam reports its outcome, and the outcome is what the
    /// surface keys on. `false` is the ordinary sessions `chat/stream` turn —
    /// no `activeRunContext`, nothing sent — which is the default path the
    /// phone uses and the whole of #328.
    @Test @MainActor
    func theStopSeamReportsWhetherItActuallyIssuedAHostStop() async throws {
        let client = ManualStreamClient()
        #expect(client.hardStopActiveRun() == false,
                "328-R2-A: a sessions chat/stream turn issues nothing — and now says so")
        client.hostStopIsIssuable = true
        #expect(client.hardStopActiveRun() == true,
                "328-R2-A: a plane that can issue one reports true")
    }

    /// **328-R2-B — RED at `f7c493d`.** Owen ran `sleep 90 && echo Done`,
    /// pressed Stop, and the host ran the whole command and answered on
    /// reopen. The composer freed, so the app looked like it obeyed. Nothing
    /// in the transcript said otherwise; now something does.
    @Test @MainActor
    func aStopThatNeverReachedTheHostSaysSo() async throws {
        let client = ManualStreamClient()
        let store = ChatStore(hermesClient: client, persistence: Self.makePersistence())
        store.composerLiveText = { "" }
        let sendTask = await startTurn("sleep 90 && echo Done", store: store, client: client)

        store.cancelStreaming()
        client.continuations.last?.finish()
        _ = await sendTask.value

        let notice = store.conversation?.messages.last
        #expect(notice?.sender == .system,
                "328-R2-B: RED at f7c493d — the app said nothing about a stop it never delivered")
        #expect(notice?.content == ChatStore.hostKeepsRunningAfterStopNotice)
        #expect(notice?.content.contains("may still be working") == true,
                "328-R2-B: and what it says is the true part — the agent is not necessarily stopped")
    }

    /// **328-R2-B, the window arm.** Owen's actual sitting was a Stop taken in
    /// the reconcile window, so the surface has to be there too — and it is
    /// the same surface, because it keys on the outcome rather than on which
    /// Stop path ran.
    @Test @MainActor
    func aWindowStopThatNeverReachedTheHostSaysSoToo() async throws {
        let client = ManualStreamClient()
        let store = ChatStore(hermesClient: client, persistence: Self.makePersistence())
        store.composerLiveText = { "" }
        try await enterReconcileWindow(turn: "sleep 90 && echo Done", store: store, client: client)

        store.cancelStreaming()

        #expect(store.conversation?.messages.last?.content == ChatStore.hostKeepsRunningAfterStopNotice)
    }

    /// **328-R2-C — the three arms where it must NOT appear.** A caveat
    /// attached to every Stop would be an apology, and #180's bar is that the
    /// user can TELL what Stop did, not that Stop is sorry for existing.
    @Test @MainActor
    func theHonestNoticeStaysAwayWhereTheStopIsRealOrNothingIsRunning() async throws {
        // (i) The runs plane: #304's stop is a real, device-proven hard
        // interrupt. It must not acquire a caveat it does not need.
        do {
            let client = ManualStreamClient()
            client.hostStopIsIssuable = true
            let store = ChatStore(hermesClient: client, persistence: Self.makePersistence())
            store.composerLiveText = { "" }
            let sendTask = await startTurn("real stop", store: store, client: client)
            store.cancelStreaming()
            client.continuations.last?.finish()
            _ = await sendTask.value
            #expect(
                store.conversation?.messages.contains { $0.sender == .system } != true,
                "328-R2-C(i): a Stop that WAS issued says nothing extra"
            )
        }

        // (ii) Nothing is left generating — the on-device brain finishes or
        // dies in-process the moment the app stops watching.
        do {
            let client = ManualStreamClient()
            client.currentRunIsServerRecoverable = false
            let store = ChatStore(hermesClient: client, persistence: Self.makePersistence())
            store.composerLiveText = { "" }
            let sendTask = await startTurn("local turn", store: store, client: client)
            store.cancelStreaming()
            client.continuations.last?.finish()
            _ = await sendTask.value
            #expect(
                store.conversation?.messages.contains { $0.sender == .system } != true,
                "328-R2-C(ii): no host is still running, so there is nothing to caveat"
            )
        }

        // (iii) The continued-send expiration is the SYSTEM revoking a
        // background budget — not a user Stop, and #295 deliberately leaves
        // the host alone there.
        do {
            let client = ManualStreamClient()
            let store = ChatStore(hermesClient: client, persistence: Self.makePersistence())
            store.composerLiveText = { "" }
            try await enterReconcileWindow(store: store, client: client)
            store.cancelStreaming(hardStopHost: false)
            #expect(
                store.conversation?.messages.contains { $0.sender == .system } != true,
                "328-R2-C(iii): an expiration is not a Stop and must not speak as one"
            )
        }
    }
}
