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
}
