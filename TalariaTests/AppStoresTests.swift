import Foundation
import HealthKit
import Testing
import UIKit
@testable import Talaria

@Suite(.serialized)
struct AppStoresTests {

    private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
        nonisolated(unsafe) static var requestHandler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

        override class func canInit(with request: URLRequest) -> Bool {
            true
        }

        override class func canonicalRequest(for request: URLRequest) -> URLRequest {
            request
        }

        override func startLoading() {
            guard let handler = Self.requestHandler else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }

            do {
                let (response, data) = try handler(request)
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
        }

        override func stopLoading() {}
    }

    private final class MutableBox<T>: @unchecked Sendable {
        var value: T

        init(_ value: T) {
            self.value = value
        }
    }

    private struct TimestampPayload: Decodable {
        let timestamp: Date
    }

    // #309 Lane B: `RecordingPairingService` and `makeSetupCode` are deleted
    // with `PairingServiceProtocol` and `PhonePairingCode`.

    @MainActor
    private final class RecordingHermesHostService: HermesHostServiceProtocol {
        var currentHost: HermesHostStatus?
        var fetchError: Error?

        func fetchCurrentHost() async throws -> HermesHostStatus? {
            if let fetchError {
                throw fetchError
            }
            return currentHost
        }
    }

    @MainActor
    private final class RecordingHermesClient: HermesClientProtocol {
        var connectionStatus: ConnectionStatus = .connected
        var currentConversation: Conversation?
        var sendCallCount = 0
        var lastClientMessageID: UUID?
        var nextResponse = Message(sender: .hermes, content: "Recorded response", status: .delivered)

        func connect() async {}

        func disconnect() async {}

        func send(message: String, attachments: [PendingAttachment] = [], clientMessageID: UUID) async -> Message {
            sendCallCount += 1
            lastClientMessageID = clientMessageID
            return nextResponse
        }

        func sendStreaming(message: String, attachments: [PendingAttachment] = [], clientMessageID: UUID) -> AsyncStream<StreamingUpdate> {
            AsyncStream { continuation in
                Task { @MainActor in
                    sendCallCount += 1
                    lastClientMessageID = clientMessageID
                    continuation.yield(.messageSent(jobID: UUID()))
                    continuation.yield(.finished(nextResponse, nil, nil))
                    continuation.finish()
                }
            }
        }

        func loadConversation() async -> Conversation {
            currentConversation ?? Conversation(title: "Hermes")
        }

        func clearConversation() async throws -> Conversation {
            let conversation = Conversation(title: "Hermes")
            currentConversation = conversation
            return conversation
        }

    }

    @MainActor
    private final class RecordingVoiceSessionService: VoiceSessionServiceProtocol {
        var voiceState: VoiceState = .idle { didSet { publishSnapshot() } }
        var connectionState: TalkConnectionState = .idle { didSet { publishSnapshot() } }
        var transcriptItems: [TranscriptItem] = [] { didSet { publishSnapshot() } }
        var sessionDuration: TimeInterval = 0 { didSet { publishSnapshot() } }
        var isMuted = false { didSet { publishSnapshot() } }
        var blockedReason: String? { didSet { publishSnapshot() } }
        var statusMessage: String? { didSet { publishSnapshot() } }
        var canStartSession = false { didSet { publishSnapshot() } }
        var latencyMetrics = TalkLatencyMetrics() { didSet { publishSnapshot() } }
        /// #310: carried on the snapshot so a readiness verdict is
        /// distinguishable from "never asked". It defaulted to
        /// `TalkReadinessInfo()` (all nil) implicitly, which is exactly what
        /// `markRelayUnavailable()` produces — see `readinessLandsReady`.
        var readinessInfo = TalkReadinessInfo() { didSet { publishSnapshot() } }

        var snapshot: TalkSessionSnapshot {
            TalkSessionSnapshot(
                voiceState: voiceState,
                connectionState: connectionState,
                transcriptItems: transcriptItems,
                sessionDuration: sessionDuration,
                isMuted: isMuted,
                blockedReason: blockedReason,
                statusMessage: statusMessage,
                canStartSession: canStartSession,
                latencyMetrics: latencyMetrics,
                voiceSessionID: nil,
                readiness: readinessInfo
            )
        }

        private let eventHub = TalkSessionEventHub()

        func events() -> AsyncStream<TalkSessionEvent> {
            eventHub.stream(initial: snapshot)
        }

        /// Readiness call counter.
        ///
        /// **#310 held this to ZERO on a gateway-only profile** — voice was
        /// #309 paths 11–12 on the relay, so a relayless profile could not
        /// ask. **#383 inverted that:** the bootstrap moved onto the talaria
        /// plugin, so the same switch must now count exactly ONE call. The
        /// counter did not change meaning; the plane underneath it did.
        var refreshReadinessCallCount = 0

        /// #310: when true, a readiness refresh lands a HOST-IS-READY verdict
        /// instead of this fixture's historical blocked one.
        ///
        /// **This knob exists because a bar failed to fail.** The first
        /// version of what is now
        /// `aSwitchNeverLeavesThePreviousProfilesReadinessOnScreen`
        /// PASSED against a build with the relay gate deliberately removed:
        /// the blocked-plus-empty-readiness state this fixture produced was
        /// byte-identical to what `TalkStore.markRelayUnavailable()` produces,
        /// so "we refreshed against a live relay" and "we refused to ask" were
        /// indistinguishable to the assertions. A fixture whose success state
        /// coincides with the failure state cannot discriminate, and a bar
        /// that cannot discriminate is not evidence. Verified: with this set,
        /// the same mutation goes RED.
        var readinessLandsReady = false

        func refreshReadiness() async {
            refreshReadinessCallCount += 1
            if readinessLandsReady {
                voiceState = .idle
                connectionState = .ready
                blockedReason = nil
                statusMessage = "Ready"
                canStartSession = true
                readinessInfo = TalkReadinessInfo(hostOnline: true, configured: true, ready: true)
                return
            }
            voiceState = .disconnected
            connectionState = .blocked
            blockedReason = "OpenAI Realtime is not configured on this Hermes host."
            statusMessage = blockedReason
            canStartSession = false
        }

        func startSession() async {}

        func endSession() async {
            voiceState = .idle
            connectionState = .idle
        }

        func toggleMute() async {
            isMuted.toggle()
        }

        func manuallyInterruptAssistantOutput() {
            voiceState = .listening
            statusMessage = "Listening"
        }

        @discardableResult
        func sendImage(_ imageData: Data, mimeType: String, triggerResponse: Bool) -> Bool {
            true
        }

        func emitAssistantTurn(_ text: String) {
            transcriptItems.append(TranscriptItem(speaker: .hermes, text: text, isPartial: false))
        }

        private func publishSnapshot() {
            eventHub.publish(snapshot: snapshot)
        }
    }

    // ── #309 Lane A (2026-08-25): NINE RELAY-SESSION TESTS TOMBSTONED ──
    //
    // Deleted here, not repointed, because the production behaviour they
    // pinned is deleted: `AppSessionStore.bootstrap()`,
    // `refreshAccessTokenIfNeeded()` and `recoverSessionByReRegistering()`
    // spoke `device/register` / `session` / `auth/refresh` to a relay retired
    // on both hosts. A test that outlives its mechanism is a test nobody can
    // make fail honestly (#310's `relaylessProfileMarksRealtimeVoice…` is the
    // precedent this file already carries).
    //
    // What went, and where the surviving guard is:
    //   · sessionBootstrapPersistsStateAndTokens
    //   · sessionBootstrapReRegistersWhenPersistedStateExistsButAccessTokenIsMissing
    //   · bootstrapSelfHealsWhenRefreshTokenIsDead            (#15's ladder)
    //   · tokenRefreshReportsMissingRefreshToken
    //   · tokenRefreshDistinguishesRejectionFromTransientFailure
    //   · concurrentTokenRefreshesCoalesceIntoOneRelayCall     (single-flight)
    //   · sessionRecoveryReRegistersKnownInstallationAndReloadsIdentity
    //   · sessionRecoveryRefusesNeverRegisteredInstallation
    //   · sessionRecoveryAttemptsAreRateLimited
    // — together with their doubles (`RecordingSessionBootstrapService`,
    // `ScriptedSessionBootstrapService`, `makeScriptedSessionStore`).
    //
    // NOT tombstoned, and deliberately so: the Keychain-slot behaviour these
    // tests also touched keeps live pins — `pairingStorePersistsRelayConfiguration
    // AndTokens` and `pairingStoreDisconnectClearsRelayConfigurationAndSession`
    // still exercise `applyPairedSession` / `clearSession` end to end, and the
    // 401-refresh LADDER keeps its production copy pinned by
    // `liveHermesHostServiceRefreshesExpiredAccessTokenDuringFetch`.
    // `InstallationIdentityTests` PORTED rather than tombstoning (309-A2).

    @Test @MainActor
    func settingsStorePersistsEnvironmentChanges() async throws {
        let suiteName = "settings-store-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let persistence = UserDefaultsAppPersistenceStore(defaults: defaults)
        let settingsStore = SettingsStore(persistence: persistence)

        settingsStore.settings.environment = .staging

        let reloaded = persistence.loadUserSettings()
        #expect(reloaded?.environment == .staging)
    }

    @Test @MainActor
    func sleepDurationUsesStableWakeDayBucket() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let bucketDay = calendar.date(from: DateComponents(year: 2026, month: 4, day: 5))!
        let intervals: [HealthQueryCore.SleepInterval] = [
            .init(
                value: HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                startDate: calendar.date(from: DateComponents(year: 2026, month: 4, day: 4, hour: 23, minute: 0))!,
                endDate: calendar.date(from: DateComponents(year: 2026, month: 4, day: 5, hour: 7, minute: 0))!
            ),
            .init(
                value: HKCategoryValueSleepAnalysis.asleepREM.rawValue,
                startDate: calendar.date(from: DateComponents(year: 2026, month: 4, day: 5, hour: 13, minute: 0))!,
                endDate: calendar.date(from: DateComponents(year: 2026, month: 4, day: 5, hour: 13, minute: 30))!
            ),
            .init(
                value: HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                startDate: calendar.date(from: DateComponents(year: 2026, month: 4, day: 5, hour: 23, minute: 0))!,
                endDate: calendar.date(from: DateComponents(year: 2026, month: 4, day: 6, hour: 6, minute: 0))!
            ),
        ]

        let hours = HealthQueryCore.aggregateSleepDuration(
            intervals: intervals,
            attributedTo: bucketDay,
            calendar: calendar
        )

        #expect(hours == 8.5)
        #expect(HealthQueryCore.sleepBucketDay(for: calendar.date(from: DateComponents(year: 2026, month: 4, day: 5, hour: 18))!, calendar: calendar) == bucketDay)
    }

    @Test @MainActor
    func chatStorePassesClientMessageIDAndSkipsPendingDuplicate() async throws {
        let hermesClient = RecordingHermesClient()
        let suiteName = "chat-store-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let persistence = UserDefaultsAppPersistenceStore(defaults: defaults)
        let chatStore = ChatStore(hermesClient: hermesClient, persistence: persistence)

        await chatStore.sendMessage("Hello Hermes")

        #expect(hermesClient.sendCallCount == 1)
        #expect(hermesClient.lastClientMessageID != nil)

        chatStore.conversation = Conversation(
            title: "Hermes",
            messages: [
                Message(sender: .user, content: "Still waiting", status: .sending),
            ]
        )

        await chatStore.sendMessage("Still waiting")

        #expect(hermesClient.sendCallCount == 1)
        #expect(chatStore.conversation?.messages.count == 1)
    }

    @Test @MainActor
    func chatStorePreservesStreamingArtifactsAfterConversationRefresh() async throws {
        final class StreamingArtifactClient: HermesClientProtocol {
            var connectionStatus: ConnectionStatus = .connected
            var currentConversation: Conversation?

            func connect() async {}
            func disconnect() async {}

            func send(message: String, attachments: [PendingAttachment] = [], clientMessageID: UUID) async -> Message {
                Message(sender: .hermes, content: "unused", status: .delivered)
            }

            func sendStreaming(message: String, attachments: [PendingAttachment] = [], clientMessageID: UUID) -> AsyncStream<StreamingUpdate> {
                let jobID = UUID()
                let finalMessageID = UUID()
                currentConversation = Conversation(
                    title: "Hermes",
                    messages: [
                        Message(id: clientMessageID, sender: .user, content: message, status: .sent),
                        Message(id: finalMessageID, sender: .hermes, content: "Patched answer", jobID: jobID, status: .delivered),
                    ]
                )

                let diff = CodeDiff(
                    files: [
                        FileDiff(
                            path: "src/example.py",
                            status: "modified",
                            additions: 2,
                            deletions: 1,
                            patch: "@@ -1 +1 @@\n-old\n+new"
                        ),
                    ],
                    summary: "1 file changed, 2 insertions(+), 1 deletion(-)"
                )

                return AsyncStream { continuation in
                    Task { @MainActor in
                        continuation.yield(.messageSent(jobID: jobID))
                        continuation.yield(.toolActivity(ToolCallEvent(name: "🔍 Searching files")))
                        continuation.yield(.finished(
                            Message(
                                id: finalMessageID,
                                sender: .hermes,
                                content: "Patched answer",
                                jobID: jobID,
                                status: .delivered
                            ),
                            nil,
                            diff
                        ))
                        continuation.finish()
                    }
                }
            }

            func loadConversation() async -> Conversation {
                currentConversation ?? Conversation(title: "Hermes")
            }

            func clearConversation() async throws -> Conversation {
                let conversation = Conversation(title: "Hermes")
                currentConversation = conversation
                return conversation
            }

        }

        let suiteName = "chat-store-stream-artifacts-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let persistence = UserDefaultsAppPersistenceStore(defaults: defaults)
        let hermesClient = StreamingArtifactClient()
        let chatStore = ChatStore(hermesClient: hermesClient, persistence: persistence)

        await chatStore.sendMessage("Fix the bug")

        let hermesMessage = chatStore.conversation?.messages.last(where: { $0.sender == .hermes })
        #expect(hermesMessage?.toolActivities.count == 1)
        #expect(hermesMessage?.codeDiff?.fileCount == 1)
        #expect(hermesMessage?.codeDiff?.summary == "1 file changed, 2 insertions(+), 1 deletion(-)")
    }

    @Test @MainActor
    func chatStorePreservesStreamingPlaceholderDuringConversationRefresh() async throws {
        final class PlaceholderRefreshClient: HermesClientProtocol {
            var connectionStatus: ConnectionStatus = .connected
            var currentConversation: Conversation?

            func connect() async {}
            func disconnect() async {}

            func send(message: String, attachments: [PendingAttachment] = [], clientMessageID: UUID) async -> Message {
                Message(sender: .hermes, content: "unused", status: .delivered)
            }

            func sendStreaming(message: String, attachments: [PendingAttachment] = [], clientMessageID: UUID) -> AsyncStream<StreamingUpdate> {
                AsyncStream { continuation in
                    Task { @MainActor in
                        continuation.finish()
                    }
                }
            }

            func loadConversation() async -> Conversation {
                currentConversation ?? Conversation(title: "Hermes")
            }

            func clearConversation() async throws -> Conversation {
                Conversation(title: "Hermes")
            }

        }

        let suiteName = "chat-store-placeholder-refresh-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let persistence = UserDefaultsAppPersistenceStore(defaults: defaults)
        let hermesClient = PlaceholderRefreshClient()
        let chatStore = ChatStore(hermesClient: hermesClient, persistence: persistence)

        let userMessage = Message(sender: .user, content: "Waiting", status: .sending)
        let placeholder = Message(sender: .hermes, content: "", status: .sending, isStreaming: true)
        chatStore.conversation = Conversation(title: "Hermes", messages: [userMessage, placeholder])
        hermesClient.currentConversation = Conversation(title: "Hermes", messages: [userMessage])

        await chatStore.loadConversation()

        #expect(chatStore.conversation?.messages.count == 2)
        #expect(chatStore.conversation?.messages.last?.isStreaming == true)
    }

    @Test @MainActor
    func chatStoreKeepsAcceptedMessagePendingUntilTerminalResultArrives() async throws {
        final class PendingUntilFinishedClient: HermesClientProtocol {
            var connectionStatus: ConnectionStatus = .connected
            var currentConversation: Conversation?

            func connect() async {}
            func disconnect() async {}

            func send(message: String, attachments: [PendingAttachment] = [], clientMessageID: UUID) async -> Message {
                Message(sender: .hermes, content: "unused", status: .delivered)
            }

            func sendStreaming(message: String, attachments: [PendingAttachment] = [], clientMessageID: UUID) -> AsyncStream<StreamingUpdate> {
                AsyncStream { continuation in
                    Task { @MainActor in
                        continuation.yield(.messageSent(jobID: UUID()))
                        try? await Task.sleep(for: .milliseconds(50))
                        continuation.yield(.finished(Message(sender: .hermes, content: "Done", status: .delivered), nil, nil))
                        continuation.finish()
                    }
                }
            }

            func loadConversation() async -> Conversation {
                currentConversation ?? Conversation(title: "Hermes")
            }

            func clearConversation() async throws -> Conversation {
                Conversation(title: "Hermes")
            }

        }

        let suiteName = "chat-store-pending-until-finished-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let persistence = UserDefaultsAppPersistenceStore(defaults: defaults)
        let hermesClient = PendingUntilFinishedClient()
        let chatStore = ChatStore(hermesClient: hermesClient, persistence: persistence)

        let task = Task { await chatStore.sendMessage("Hello") }
        try? await Task.sleep(for: .milliseconds(10))

        let userMessage = try #require(chatStore.conversation?.messages.first(where: { $0.sender == .user }))
        #expect(userMessage.status == .sending)

        await task.value
    }

    @Test @MainActor
    func chatStoreRefreshesConversationWhenStreamingInterruptedAfterJobAccepted() async throws {
        // The "run committed server-side, stream dropped" recovery path fires on
        // `.interrupted`, not `.failed` — a hard failure deliberately no longer
        // reconciles (#13). Recovery flows through reconcilePendingRuns() →
        // reconcileFromServer(), so that's what the mock exercises and counts.
        final class StreamingInterruptedClient: HermesClientProtocol {
            var connectionStatus: ConnectionStatus = .connected
            var currentConversation: Conversation?
            var reconcileFromServerCallCount = 0
            let jobID = UUID()
            let userID = UUID()
            let assistantID = UUID()

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
                        continuation.yield(.messageSent(jobID: jobID))
                        continuation.yield(.interrupted(sessionId: "probe-session", runId: nil))
                        continuation.finish()
                    }
                }
            }

            func loadConversation() async -> Conversation {
                currentConversation ?? Conversation(title: "Hermes")
            }

            func clearConversation() async throws -> Conversation {
                Conversation(title: "Hermes")
            }

            func reconcileFromServer() async -> Conversation? {
                reconcileFromServerCallCount += 1
                let conversation = Conversation(
                    title: "Hermes",
                    messages: [
                        Message(id: userID,
                                clientMessageID: currentConversation?.messages.first(where: { $0.sender == .user })?.clientMessageID,
                                sender: .user, content: "Fix it", status: .delivered),
                        Message(id: assistantID, sender: .hermes, content: "Recovered after polling", jobID: jobID, status: .delivered),
                    ]
                )
                currentConversation = conversation
                return conversation
            }

        }

        let suiteName = "chat-store-stream-interrupted-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let persistence = UserDefaultsAppPersistenceStore(defaults: defaults)
        let hermesClient = StreamingInterruptedClient()
        let chatStore = ChatStore(hermesClient: hermesClient, persistence: persistence)

        await chatStore.sendMessage("Fix it")

        // The in-store reconcile loop ticks on a 2s cadence; drive one pass
        // deterministically the way app foregrounding does.
        await chatStore.reconcilePendingRuns()

        #expect(hermesClient.reconcileFromServerCallCount == 1)
        #expect(chatStore.conversation?.messages.last?.content == "Recovered after polling")
        #expect(chatStore.pendingMessageSentAt == nil)
        #expect(chatStore.isStreaming == false)
    }

    @Test @MainActor
    func reconcileLoopStopsAtItsWallClockBudgetNotItsAttemptCount() async throws {
        // #145 Part C. The loop budgeted ATTEMPTS — `maxAttempts = 60 // 60 x 2s
        // = ~2 min` — while each attempt makes an UNBOUNDED gateway fetch. On a
        // black-holed host (#136: DROP, so every request eats the full 60s
        // URLSession timeout) the real ceiling was 60 × (2s + 60s) ≈ 62 MINUTES,
        // not 2. The loop is armed from the foreground chain and keeps grinding
        // long after the outage ends — one of the three reasons #145 outlives
        // the outage that caused it.
        //
        // The pin: with a client that NEVER resolves and is slower than the poll
        // interval, the loop must stop on elapsed WALL TIME. An attempt counter
        // cannot bound a loop whose per-attempt cost is unbounded.
        //
        // Asserts on ATTEMPTS OBSERVED, never on a stopwatch reading — a timing
        // assertion here would be flaky on a loaded machine and land straight in
        // #183's territory.
        final class NeverResolvingClient: HermesClientProtocol {
            var connectionStatus: ConnectionStatus = .connected
            var currentConversation: Conversation?
            var reconcileFromServerCallCount = 0
            let jobID = UUID()

            func connect() async {}
            func disconnect() async {}

            func send(message: String, attachments: [PendingAttachment] = [], clientMessageID: UUID) async -> Message {
                Message(sender: .hermes, content: "unused", status: .delivered)
            }

            func sendStreaming(message: String, attachments: [PendingAttachment] = [], clientMessageID: UUID) -> AsyncStream<StreamingUpdate> {
                currentConversation = Conversation(
                    title: "Hermes",
                    messages: [Message(clientMessageID: clientMessageID, sender: .user, content: message, status: .sent)]
                )
                return AsyncStream { continuation in
                    Task { @MainActor in
                        continuation.yield(.messageSent(jobID: jobID))
                        continuation.yield(.interrupted(sessionId: "wedge-session", runId: nil))
                        continuation.finish()
                    }
                }
            }

            func loadConversation() async -> Conversation { currentConversation ?? Conversation(title: "Hermes") }
            func clearConversation() async throws -> Conversation { Conversation(title: "Hermes") }

            /// Stands in for the black-holed host: slower than the poll interval
            /// and never resolving, so an attempt-counted loop would run its full
            /// count and a wall-clock loop must not.
            func reconcileFromServer() async -> Conversation? {
                reconcileFromServerCallCount += 1
                try? await Task.sleep(for: .milliseconds(40))
                return nil
            }
        }

        let suiteName = "chat-store-reconcile-budget-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let persistence = UserDefaultsAppPersistenceStore(defaults: defaults)
        let hermesClient = NeverResolvingClient()
        let chatStore = ChatStore(hermesClient: hermesClient, persistence: persistence)

        // Shrink the real budget rather than simulate it: same code path, same
        // arithmetic, ~300ms instead of ~2 minutes.
        chatStore.reconcileWallClockBudget = .milliseconds(300)
        chatStore.reconcilePollInterval = .milliseconds(50)

        await chatStore.sendMessage("wedge me")

        // Bounded pump — wait for the loop to retire itself rather than sleeping
        // a fixed duration. Cap is generous; the assertion is on attempts.
        var pumps = 0
        while chatStore.hasActiveReconcileLoop, pumps < 200 {
            pumps += 1
            try? await Task.sleep(for: .milliseconds(25))
        }

        #expect(chatStore.hasActiveReconcileLoop == false, "the reconcile loop never retired inside its wall-clock budget")
        // 300ms budget ÷ (50ms sleep + 40ms fetch) ≈ 3 attempts. The old
        // attempt-counted loop would have run all 60 regardless of elapsed time.
        #expect(hermesClient.reconcileFromServerCallCount < 60,
                "loop ran \(hermesClient.reconcileFromServerCallCount) attempts — it is still counting attempts, not wall time")
        #expect(hermesClient.reconcileFromServerCallCount >= 1,
                "loop never attempted a reconcile — the test proved nothing")
    }

    // MARK: #237 — run idempotence (a resolved run never resolves twice)

    /// Fixture: yields .interrupted for a KNOWN runId, HOLDS the stream
    /// continuation so the test can deliver a LATE duplicate interrupt after
    /// the run has already resolved — the observed 12:49 double-notification
    /// shape (the dying stream's corpse re-arming a second PendingRun).
    @MainActor
    private final class LateInterruptClient: HermesClientProtocol {
        var connectionStatus: ConnectionStatus = .connected
        var currentConversation: Conversation?
        var replyAvailable = false
        let jobID = UUID()

        func connect() async {}
        func disconnect() async {}

        func send(message: String, attachments: [PendingAttachment] = [], clientMessageID: UUID) async -> Message {
            Message(sender: .hermes, content: "unused", status: .delivered)
        }

        func sendStreaming(message: String, attachments: [PendingAttachment] = [], clientMessageID: UUID) -> AsyncStream<StreamingUpdate> {
            // Every stream — including the "corpse" — yields .interrupted for
            // the SAME runId and finishes. The first arms recovery; any later
            // one models the dying stream's duplicate reaching the same
            // .interrupted handler after resolution.
            if currentConversation == nil {
                currentConversation = Conversation(
                    title: "Hermes",
                    messages: [Message(clientMessageID: clientMessageID, sender: .user, content: message, status: .sent)]
                )
            } else {
                currentConversation?.messages.append(
                    Message(clientMessageID: clientMessageID, sender: .user, content: message, status: .sent))
            }
            return AsyncStream { continuation in
                Task { @MainActor in
                    continuation.yield(.messageSent(jobID: self.jobID))
                    continuation.yield(.interrupted(sessionId: "late-dup-session", runId: "run-dup-1"))
                    continuation.finish()
                }
            }
        }

        func loadConversation() async -> Conversation { currentConversation ?? Conversation(title: "Hermes") }
        func clearConversation() async throws -> Conversation { Conversation(title: "Hermes") }

        func reconcileFromServer() async -> Conversation? {
            guard replyAvailable else { return nil }
            var convo = currentConversation ?? Conversation(title: "Hermes")
            convo.messages.append(Message(sender: .hermes, content: "Resolved once", status: .delivered))
            currentConversation = convo
            return convo
        }

        /// #368 (3E): this run HAS an id — that is the whole point of the
        /// #237 bar — so after the cutover its recovery is the run-status
        /// read, not the session re-read. The fixture answers on the same
        /// `replyAvailable` gate so the test keeps measuring what it always
        /// measured (a resolved run never re-arms and never resolves twice),
        /// now on the path production actually takes.
        func resolveDroppedRun(runID: String, sessionID: String) async -> DroppedRunResolution? {
            guard replyAvailable else { return nil }
            return .answered(content: "Resolved once", usage: nil)
        }
    }

    @Test @MainActor
    func lateDuplicateInterruptNeverResolvesTwice() async throws {
        let suiteName = "chat-store-late-dup-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let persistence = UserDefaultsAppPersistenceStore(defaults: defaults)
        let hermesClient = LateInterruptClient()
        let chatStore = ChatStore(hermesClient: hermesClient, persistence: persistence)
        chatStore.reconcileWallClockBudget = .milliseconds(120)
        chatStore.reconcilePollInterval = .milliseconds(30)
        // #368: the pending run carries an id, so the loop reads the
        // run-recovery pair rather than the legacy one above.
        chatStore.runRecoveryWallClockBudget = .milliseconds(120)
        chatStore.runRecoveryPollInterval = .milliseconds(30)
        var resolvedCount = 0
        chatStore.onRunResolved = { _ in resolvedCount += 1 }

        await chatStore.sendMessage("long turn")
        var pumps = 0
        while chatStore.pendingRunSessionId == nil, pumps < 100 {
            pumps += 1
            try? await Task.sleep(for: .milliseconds(20))
        }
        #expect(chatStore.pendingRunSessionId == "late-dup-session")

        hermesClient.replyAvailable = true
        await chatStore.reconcilePendingRuns()
        #expect(chatStore.pendingRunSessionId == nil)
        #expect(resolvedCount == 1)

        // The corpse delivers its late duplicate (same runId, fresh stream) —
        // the guard must swallow it: no new PendingRun, no second resolution.
        await chatStore.sendMessage("corpse echo")
        pumps = 0
        while pumps < 15 {
            pumps += 1
            try? await Task.sleep(for: .milliseconds(20))
        }
        #expect(chatStore.pendingRunSessionId == nil, "a resolved run must not re-arm")
        await chatStore.reconcilePendingRuns()
        #expect(resolvedCount == 1, "a resolved run must not resolve twice")
    }

    // MARK: #237 — the dedupe sweep (adopted-echo corruption heals on load)

    private func echoRow(_ sender: MessageSender, _ content: String, ts: TimeInterval,
                         activities: [ToolActivity] = []) -> Message {
        Message(sender: sender, content: content,
                timestamp: Date(timeIntervalSince1970: ts),
                status: .delivered, toolActivities: activities)
    }

    @Test func sweepCollapsesAQuadrupledThread() {
        let original = [
            echoRow(.user, "smoke test plex", ts: 1_000),
            echoRow(.hermes, "", ts: 1_001,
                    activities: [ToolActivity(label: "terminal", startedAt: Date(timeIntervalSince1970: 1_001), isActive: false, detail: nil)]),
            echoRow(.hermes, "Done. Report saved.", ts: 1_060),
        ]
        // Four adoptions' worth of fresh-identity copies (distinct UUIDs,
        // identical triples) — Owen's 32→128 shape in miniature.
        let quadrupled = original + original.map { Message(sender: $0.sender, content: $0.content, timestamp: $0.timestamp, status: .delivered, toolActivities: $0.toolActivities) }
            + original.map { Message(sender: $0.sender, content: $0.content, timestamp: $0.timestamp, status: .delivered, toolActivities: $0.toolActivities) }
            + original.map { Message(sender: $0.sender, content: $0.content, timestamp: $0.timestamp, status: .delivered, toolActivities: $0.toolActivities) }
        let swept = Conversation.dedupingAdoptedEchoes(quadrupled)
        #expect(swept.count == original.count)
        #expect(swept.map(\.content) == original.map(\.content))
        // Idempotent: sweeping the swept is identity.
        #expect(Conversation.dedupingAdoptedEchoes(swept).map(\.id) == swept.map(\.id))
    }

    @Test func sweepPreservesDistinctTimestampRepeats() {
        // A user really can send the same text twice — different timestamps.
        let twice = [echoRow(.user, "ping", ts: 1_000), echoRow(.hermes, "pong", ts: 1_001),
                     echoRow(.user, "ping", ts: 2_000), echoRow(.hermes, "pong", ts: 2_001)]
        #expect(Conversation.dedupingAdoptedEchoes(twice).count == 4)
    }

    // MARK: - #248: the adoption merge's unconfirmed-locals selection
    //
    // Owen's build-1987 dupe: the gateway transcript carries NO
    // clientMessageID, so the just-sent local user row failed both id
    // confirmations and was re-appended BELOW the recovered reply. The
    // selection gains a content-claim tier for user rows: each refreshed
    // user row lacking clientMessageID confirms at most ONE
    // content-identical local user row.

    /// 248-A — Owen's exact shape: server echoes the user row (server id,
    /// no clientMessageID) plus the reply; the optimistic local must read
    /// as CONFIRMED, not get re-appended.
    @Test func adoptedServerCopyConfirmsTheLocalUserRowByContent() {
        let clientID = UUID()
        let local = [Message(id: clientID, clientMessageID: clientID, sender: .user,
                             content: "What model are you using", status: .working)]
        let refreshed = [
            Message(sender: .user, content: "What model are you using", status: .delivered),
            Message(sender: .hermes, content: "deepseek-v4-flash, via the deepseek provider", status: .delivered),
        ]
        #expect(ChatStore.unconfirmedLocalMessages(local: local, refreshed: refreshed).isEmpty)
    }

    /// 248-B — repeat safety: two identical in-flight sends, server has ONE
    /// so far — exactly one local row stays unconfirmed (dequeue counting).
    @Test func contentClaimConfirmsAtMostOneLocalPerServerRow() {
        let firstID = UUID(), secondID = UUID()
        let local = [
            Message(id: firstID, clientMessageID: firstID, sender: .user, content: "yes", status: .working),
            Message(id: secondID, clientMessageID: secondID, sender: .user, content: "yes", status: .sending),
        ]
        let refreshed = [Message(sender: .user, content: "yes", status: .delivered)]
        let unconfirmed = ChatStore.unconfirmedLocalMessages(local: local, refreshed: refreshed)
        #expect(unconfirmed.count == 1)
    }

    /// 248-C — pin: an echoed clientMessageID confirms its row regardless of
    /// content (the pre-#248 tiers are untouched).
    @Test func echoedClientMessageIDStillConfirms() {
        let clientID = UUID()
        let local = [Message(id: clientID, clientMessageID: clientID, sender: .user,
                             content: "original text", status: .working)]
        let refreshed = [Message(clientMessageID: clientID, sender: .user,
                                 content: "server-normalized text", status: .delivered)]
        #expect(ChatStore.unconfirmedLocalMessages(local: local, refreshed: refreshed).isEmpty)
    }

    /// 248-D — pin: with an empty refresh, a just-sent local survives — the
    /// vanish-protection this pass exists for.
    @Test func inFlightSendSurvivesAnEmptyRefresh() {
        let clientID = UUID()
        let local = [Message(id: clientID, clientMessageID: clientID, sender: .user,
                             content: "hello", status: .sending)]
        #expect(ChatStore.unconfirmedLocalMessages(local: local, refreshed: []).count == 1)
    }

    /// 281-A — the SURPLUS claim. A refreshed user row that already confirms
    /// a local twin BY ID (tier 1, which returns without decrementing) must
    /// not also mint a content claim: the claim is spare, and the genuinely
    /// new user row carrying the same text ate it and was filtered out of the
    /// merge. On the Hermes path every previously-adopted row has this shape
    /// — `mapStoredMessage` sets a stable server-derived id and never a
    /// `clientMessageID` — so a re-sent prompt vanished from the transcript.
    @Test func anAlreadyIDConfirmedRefreshedRowMintsNoContentClaim() {
        let historyID = UUID(), freshID = UUID()
        let local = [
            Message(id: historyID, sender: .user, content: "How many are left", status: .delivered),
            Message(id: freshID, clientMessageID: freshID, sender: .user,
                    content: "How many are left", status: .sending),
        ]
        let refreshed = [Message(id: historyID, sender: .user,
                                 content: "How many are left", status: .delivered)]
        let unconfirmed = ChatStore.unconfirmedLocalMessages(local: local, refreshed: refreshed)
        #expect(unconfirmed.map(\.id) == [freshID])
    }

    /// **282-A (tracker #282 — NOT GitHub PR #282)** — the DEMAND side, case
    /// (a). A `.failed` user row the host never stored sits ABOVE a later
    /// identical prompt that succeeded. The server echoes ONE copy of the
    /// SUCCESSFUL turn, which mints one claim (its stable id is not in
    /// `localIDs`, so #281's supply gate lets it through, correctly). The
    /// claim's consumer is chosen by LOCAL ORDER, so the `.failed` row — the
    /// one row the user can still see and still retry — eats it and is
    /// filtered out of the merge. It silently leaves the transcript.
    ///
    /// Owen's 2026-08-09 ruling: only an IN-FLIGHT row may consume. `.failed`
    /// is settled (`MessageStatus.swift:22`), so the `.sending` successor —
    /// the row the echo actually corresponds to — takes the claim instead.
    ///
    /// **WATCHED RED 2026-08-09 against unmodified production, verbatim:**
    /// ```
    /// ✘ Test aFailedRowNoLongerEatsALaterIdenticalPromptsClaim() recorded an issue at
    ///   AppStoresTests.swift:1289:9: Expectation failed: unconfirmed.map(\.id) == [failedID]
    /// ↳ unconfirmed.map(\.id) == [failedID] → false
    /// ↳   unconfirmed.map(\.id) → [2222529F-27AD-4AE2-863C-AB9000F87A1E]
    /// ↳   [failedID] → [6086E267-4B34-4CDD-9FE7-6969688B7EBE]
    /// ```
    /// The returned id is the SUCCESSOR's, not the failed row's — the stated
    /// reason, not a compile error and not a different assertion.
    ///
    /// **RE-ENABLED 2026-08-11 by the RANKING lane (tracker #282, Owen's
    /// 2026-08-10 ruling: rank the consumers, do not ban them).** The 2026-08-09
    /// halt disabled this because the ban-style guard was never written; the
    /// ranking supersedes that guard and turns this assertion GREEN by a
    /// different mechanism. The `.sending` successor is IN FLIGHT, so it
    /// outranks the settled `.failed` row for the single claim and the failed
    /// row survives. Assertions byte-unchanged from the 2026-08-09 run quoted
    /// above; **re-watched RED against unmodified production 2026-08-11**
    /// before the ranking landed.
    ///
    /// This bar covers case (a) **in its common shape only** — see 282R-A's
    /// note on the accepted gap when the successor has itself settled.
    @Test func aFailedRowNoLongerEatsALaterIdenticalPromptsClaim() {
        let failedID = UUID(), successID = UUID(), serverID = UUID()
        let local = [
            Message(id: failedID, clientMessageID: failedID, sender: .user,
                    content: "Summarize the thread", status: .failed),
            Message(id: successID, clientMessageID: successID, sender: .user,
                    content: "Summarize the thread", status: .sending),
        ]
        let refreshed = [Message(id: serverID, sender: .user,
                                 content: "Summarize the thread", status: .delivered)]
        let unconfirmed = ChatStore.unconfirmedLocalMessages(local: local, refreshed: refreshed)
        #expect(unconfirmed.map(\.id) == [failedID])
    }

    // MARK: - tracker #282, the RANKING lane (Owen's ruling 2026-08-10)
    //
    // The demand side is RANKED, not banned: in-flight rows take a claim
    // first, and a settled row may still consume one that no in-flight row
    // wants. 282R-A pins the first half, 282R-B the second — and the second is
    // the whole difference from the ban-style guard measured on 2026-08-10,
    // which turned three populations from a silent swallow into a visible
    // duplicate (tracker #282's measurement PR).

    /// **282R-A — the ranking holds.** One settled and one in-flight local
    /// user row of identical content; the server has stored exactly one copy
    /// and echoes no `clientMessageID`, so a single claim is minted and both
    /// rows reach the content tier. **The IN-FLIGHT row takes it**, and the
    /// settled row survives the merge.
    ///
    /// Deliberately `.delivered` rather than `.failed` for the settled row:
    /// 282-A already covers the `.failed` shape, and this bar is about
    /// SETTLEDNESS as the rank key, not about failure. Statuses are explicit
    /// on every fixture row because `Message.status` defaults to `.sent`,
    /// which is settled — a fixture that omits it is not testing what its
    /// author thinks.
    ///
    /// **WATCHED RED 2026-08-11 against unmodified production**: without the
    /// ranking the consumer is chosen by LOCAL ORDER, so the settled row —
    /// first in the array — ate the claim and the returned survivor was the
    /// in-flight row's id.
    ///
    /// **THE ACCEPTED GAP, named here because a lane that quietly closes it
    /// has exceeded Owen's per-change go.** Ranking decides only between an
    /// in-flight and a settled candidate. When BOTH candidates have settled —
    /// the retry already `.sent`/`.delivered`, or itself `.failed` — the tie
    /// breaks on local order exactly as before and the older row still eats
    /// the claim. That residual stays OPEN by ruling; closing it needs an
    /// identity the gateway transcript does not carry.
    @Test func anInFlightRowOutranksASettledOneForTheSameContentClaim() {
        let settledID = UUID(), inFlightID = UUID(), serverID = UUID()
        let local = [
            Message(id: settledID, clientMessageID: settledID, sender: .user,
                    content: "Where did that file go", status: .delivered),
            Message(id: inFlightID, clientMessageID: inFlightID, sender: .user,
                    content: "Where did that file go", status: .sending),
        ]
        let refreshed = [Message(id: serverID, sender: .user,
                                 content: "Where did that file go", status: .delivered)]
        let unconfirmed = ChatStore.unconfirmedLocalMessages(local: local, refreshed: refreshed)
        #expect(unconfirmed.map(\.id) == [settledID])
    }

    /// **282R-B — a settled row STILL confirms when nothing else wants the
    /// claim.** This is the anti-ban bar: falsifying it means the lane
    /// rebuilt the ban-style guard, whose measured cost was three populations
    /// converting from a silent swallow into a visible duplicate.
    ///
    /// Two turns, two distinct texts, two claims. The older row has SETTLED
    /// `.delivered` and the newer is `.sending`; the in-flight row's claim is
    /// keyed on its own content, so it never competes for the settled row's.
    /// Both must confirm — nothing survives, nothing is re-appended.
    ///
    /// Green at HEAD by construction (order-keyed allocation reaches the same
    /// answer when there is no contention); it is pinned so that a later
    /// narrowing of this tier cannot pass unnoticed.
    @Test func aSettledRowStillConsumesAClaimNoInFlightRowWants() {
        let settledID = UUID(), inFlightID = UUID()
        let local = [
            Message(id: settledID, clientMessageID: settledID, sender: .user,
                    content: "older ask", status: .delivered),
            Message(id: inFlightID, clientMessageID: inFlightID, sender: .user,
                    content: "newer ask", status: .sending),
        ]
        let refreshed = [
            Message(sender: .user, content: "older ask", status: .delivered),
            Message(sender: .hermes, content: "an answer", status: .delivered),
            Message(sender: .user, content: "newer ask", status: .delivered),
        ]
        #expect(ChatStore.unconfirmedLocalMessages(local: local, refreshed: refreshed).isEmpty)
    }

    /// **282R-B, the lone-settled-row arm.** The narrowest statement of the
    /// same rule: one settled local user row, one claimable server row, no
    /// in-flight candidate anywhere. The settled row consumes the claim and is
    /// confirmed. Under the superseded ban this returns one survivor, which is
    /// the duplicate 282-B/282-D/282-E each measured at store level.
    @Test func aLoneSettledRowIsStillConfirmedByTheContentClaim() {
        let settledID = UUID()
        let local = [Message(id: settledID, clientMessageID: settledID, sender: .user,
                             content: "the only ask", status: .delivered)]
        let refreshed = [Message(sender: .user, content: "the only ask", status: .delivered)]
        #expect(ChatStore.unconfirmedLocalMessages(local: local, refreshed: refreshed).isEmpty)
    }

    // MARK: - #247 B2: the profile-switch verdict (bars 247-B)

    /// The exact strings are the product surface — pinned.
    @Test func switchVerdictNamesEveryOutcome() {
        #expect(AppContainer.profileSwitchNotice(
            newProfileName: "Mac Mini", verdict: .online,
            previousProfileName: "OJAMD", previousVerdict: .online
        ) == "Mac Mini: gateway online.")
        #expect(AppContainer.profileSwitchNotice(
            newProfileName: "Mac Mini", verdict: .unkeyed,
            previousProfileName: nil, previousVerdict: nil
        ) == "Mac Mini: gateway answering, but its API key was rejected.")
        #expect(AppContainer.profileSwitchNotice(
            newProfileName: "Mac Mini", verdict: .unreachable,
            previousProfileName: "OJAMD", previousVerdict: .online
        ) == "Mac Mini: gateway unreachable.")
        #expect(AppContainer.profileSwitchNotice(
            newProfileName: "Mac Mini", verdict: .unreachable,
            previousProfileName: nil, previousVerdict: nil
        ) == "Mac Mini: gateway unreachable.")
    }

    /// The all-hosts-dead diagnosis — the sentence Owen had to derive by RDP
    /// elimination. Both dead ⇒ the problem is the phone, and the app says so.
    @Test func switchVerdictDiagnosesTheAllHostsDeadShape() {
        #expect(AppContainer.profileSwitchNotice(
            newProfileName: "Mac Mini", verdict: .unreachable,
            previousProfileName: "OJAMD", previousVerdict: .unreachable
        ) == "Mac Mini is unreachable — and so is OJAMD. Every host is failing; check this phone's network or Tailscale.")
    }

    @Test func sweepDedupesEmptyShellsOnlyWhenActivitiesMatch() {
        let shellA = echoRow(.hermes, "", ts: 1_000,
                             activities: [ToolActivity(label: "terminal", startedAt: Date(timeIntervalSince1970: 1_000), isActive: false, detail: nil)])
        let shellAdup = echoRow(.hermes, "", ts: 1_000,
                                activities: [ToolActivity(label: "terminal", startedAt: Date(timeIntervalSince1970: 1_000), isActive: false, detail: nil)])
        let shellB = echoRow(.hermes, "", ts: 1_000,
                             activities: [ToolActivity(label: "read_file", startedAt: Date(timeIntervalSince1970: 1_000), isActive: false, detail: nil)])
        let swept = Conversation.dedupingAdoptedEchoes([shellA, shellAdup, shellB])
        #expect(swept.count == 2)
        #expect(swept.last?.toolActivities.first?.label == "read_file")
    }

    // MARK: #235 F3 — tail placement for recovered replies

    /// Owen's placement rule: a recovered reply DISPLACED by later exchanges
    /// moves to the tail and is stamped with the prompt it answers; an
    /// undisplaced reply is untouched — byte-identical adoption.
    @Test func displacedRecoveredReplyMovesToTailWithMarker() {
        let reply = Message(sender: .hermes, content: "the late answer", status: .delivered)
        let later1 = Message(sender: .user, content: "next question", status: .delivered)
        let later2 = Message(sender: .hermes, content: "next answer", status: .delivered)
        let placed = ChatStore.placingRecoveredReply(
            reply.id, prompt: "So what's the holdup?", in: [reply, later1, later2])
        #expect(placed.last?.id == reply.id)
        #expect(placed.last?.recoveredForPrompt == "So what's the holdup?")
        #expect(placed.map(\.id) == [later1.id, later2.id, reply.id])
    }

    @Test func undisplacedRecoveredReplyIsUntouched() {
        let q = Message(sender: .user, content: "question", status: .delivered)
        let reply = Message(sender: .hermes, content: "answer", status: .delivered)
        let placed = ChatStore.placingRecoveredReply(reply.id, prompt: "question", in: [q, reply])
        #expect(placed.map(\.id) == [q.id, reply.id])
        #expect(placed.last?.recoveredForPrompt == nil)
    }

    @Test func placementWithUnknownReplyIDIsIdentity() {
        let q = Message(sender: .user, content: "question", status: .delivered)
        let placed = ChatStore.placingRecoveredReply(UUID(), prompt: nil, in: [q])
        #expect(placed.map(\.id) == [q.id])
    }

    /// Prompt text is clipped to 60 chars for the marker.
    @Test func markerPromptIsClipped() {
        let reply = Message(sender: .hermes, content: "late", status: .delivered)
        let later = Message(sender: .user, content: "x", status: .delivered)
        let long = String(repeating: "p", count: 200)
        let placed = ChatStore.placingRecoveredReply(reply.id, prompt: long, in: [reply, later])
        #expect(placed.last?.recoveredForPrompt?.count == 60)
    }

    @Test @MainActor
    func budgetExpiryKeepsPendingRunAndSingleShotResolves() async throws {
        // #235 F2: the loop's budget expiring must NOT orphan the run —
        // pendingRun survives retirement, and ONE reconcilePendingRuns() call
        // (the unstarved foreground / chat-appear single-shot) resolves it
        // once the reply exists server-side. Owen's 9:50 shape: the run
        // outlived the 120s budget, the answer landed later, nothing looked.
        final class LateReplyClient: HermesClientProtocol {
            var connectionStatus: ConnectionStatus = .connected
            var currentConversation: Conversation?
            var replyAvailable = false
            var reconcileFromServerCallCount = 0
            let jobID = UUID()

            func connect() async {}
            func disconnect() async {}

            func send(message: String, attachments: [PendingAttachment] = [], clientMessageID: UUID) async -> Message {
                Message(sender: .hermes, content: "unused", status: .delivered)
            }

            func sendStreaming(message: String, attachments: [PendingAttachment] = [], clientMessageID: UUID) -> AsyncStream<StreamingUpdate> {
                currentConversation = Conversation(
                    title: "Hermes",
                    messages: [Message(clientMessageID: clientMessageID, sender: .user, content: message, status: .sent)]
                )
                return AsyncStream { continuation in
                    Task { @MainActor in
                        continuation.yield(.messageSent(jobID: jobID))
                        continuation.yield(.interrupted(sessionId: "late-session", runId: nil))
                        continuation.finish()
                    }
                }
            }

            func loadConversation() async -> Conversation { currentConversation ?? Conversation(title: "Hermes") }
            func clearConversation() async throws -> Conversation { Conversation(title: "Hermes") }

            /// Nil until the flag flips — the run is still going server-side.
            func reconcileFromServer() async -> Conversation? {
                reconcileFromServerCallCount += 1
                guard replyAvailable else { return nil }
                var convo = currentConversation ?? Conversation(title: "Hermes")
                convo.messages.append(Message(sender: .hermes, content: "Late but real answer", status: .delivered))
                currentConversation = convo
                return convo
            }
        }

        let suiteName = "chat-store-late-reply-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let persistence = UserDefaultsAppPersistenceStore(defaults: defaults)
        let hermesClient = LateReplyClient()
        let chatStore = ChatStore(hermesClient: hermesClient, persistence: persistence)
        chatStore.reconcileWallClockBudget = .milliseconds(120)
        chatStore.reconcilePollInterval = .milliseconds(30)

        await chatStore.sendMessage("long turn")
        var pumps = 0
        while chatStore.hasActiveReconcileLoop, pumps < 200 {
            pumps += 1
            try? await Task.sleep(for: .milliseconds(25))
        }
        #expect(chatStore.hasActiveReconcileLoop == false)
        #expect(chatStore.pendingRunSessionId == "late-session",
                "budget expiry must keep the pending run, not orphan it")

        hermesClient.replyAvailable = true
        await chatStore.reconcilePendingRuns()
        #expect(chatStore.pendingRunSessionId == nil, "the single-shot must resolve once the reply exists")
        #expect(chatStore.conversation?.messages.last?.content == "Late but real answer")
    }

    @Test @MainActor
    func openSessionAbandonsPendingRunFromPreviousSession() async throws {
        // #184: `reconcileFromServer()` takes no session argument — once
        // openSession has switched the client's internal session, a pendingRun
        // left over from S1 gets compared against S2's server view, smearing
        // S1's partial reasoning and a nonsense turnDuration onto an S2 reply
        // and persisting both. Switching sessions must abandon the run and
        // stand its relay watch down (#38).
        final class SessionSwitchClient: HermesClientProtocol {
            var connectionStatus: ConnectionStatus = .connected
            var currentConversation: Conversation?
            var reconcileFromServerCallCount = 0

            func connect() async {}
            func disconnect() async {}

            func send(message: String, attachments: [PendingAttachment] = [], clientMessageID: UUID) async -> Message {
                Message(sender: .hermes, content: "unused", status: .delivered)
            }

            func sendStreaming(message: String, attachments: [PendingAttachment] = [], clientMessageID: UUID) -> AsyncStream<StreamingUpdate> {
                AsyncStream { continuation in
                    Task { @MainActor in
                        continuation.yield(.messageSent(jobID: UUID()))
                        continuation.yield(.interrupted(sessionId: "S1", runId: nil))
                        continuation.finish()
                    }
                }
            }

            func loadConversation() async -> Conversation {
                currentConversation ?? Conversation(title: "Hermes")
            }

            func clearConversation() async throws -> Conversation {
                Conversation(title: "Hermes")
            }

            func openSession(_ id: String) async throws -> Conversation {
                Conversation(title: "S2", messages: [
                    Message(sender: .hermes, content: "S2 history", status: .delivered),
                ])
            }

            func reconcileFromServer() async -> Conversation? {
                reconcileFromServerCallCount += 1
                // An S2 reply timestamped after the S1 send — exactly what the
                // stale pending run's filter would adopt.
                return Conversation(title: "S2", messages: [
                    Message(sender: .hermes, content: "S2 reply", status: .delivered),
                ])
            }
        }

        let suiteName = "chat-store-open-session-pending-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let persistence = UserDefaultsAppPersistenceStore(defaults: defaults)
        let hermesClient = SessionSwitchClient()
        let chatStore = ChatStore(hermesClient: hermesClient, persistence: persistence)
        var resolvedRuns: [String] = []
        chatStore.onRunResolved = { resolvedRuns.append($0) }

        await chatStore.sendMessage("probe")
        #expect(chatStore.pendingRunSessionId == "S1")

        await chatStore.openSession("S2")

        #expect(chatStore.pendingRunSessionId == nil, "openSession must abandon the departing session's pending run")
        #expect(resolvedRuns == ["S1"], "the relay watch for S1 must stand down (#38)")

        await chatStore.reconcilePendingRuns()
        #expect(hermesClient.reconcileFromServerCallCount == 0, "no reconcile may fire against S2")
    }

    @Test @MainActor
    func resetAbandonsPendingRunAndStream() async throws {
        // #184: reset() runs on the pairing lifecycle (its only two callers) —
        // pair or unpair mid-stream and `conversation` goes nil while the
        // streaming task keeps running and the pendingRun stays armed, then
        // initialize() runs against a DIFFERENT host. Cross-host leakage, the
        // serious half of the finding.
        let suiteName = "chat-store-reset-abandon-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let persistence = UserDefaultsAppPersistenceStore(defaults: defaults)
        let hermesClient = BlackHoleStreamingChatClient()
        let chatStore = ChatStore(hermesClient: hermesClient, persistence: persistence)
        var resolvedRuns: [String] = []
        chatStore.onRunResolved = { resolvedRuns.append($0) }

        // Send #1 interrupts, arming the pending run; send #2 streams into a
        // black hole and stays live until torn down.
        await chatStore.sendMessage("arm the pending run")
        #expect(chatStore.pendingRunSessionId == "S1")
        let streamingSend = Task { @MainActor in await chatStore.sendMessage("now stream") }
        let streaming = await pollUntil { chatStore.isStreaming }
        #expect(streaming)

        chatStore.reset()

        #expect(chatStore.pendingRunSessionId == nil, "reset() must abandon the pending run")
        #expect(chatStore.isStreaming == false, "reset() must tear down streaming state")
        #expect(resolvedRuns == ["S1"], "the abandoned run's relay watch must stand down (#38)")
        let cancelled = await pollUntil { hermesClient.streamCancelled }
        #expect(cancelled, "reset() must cancel the in-flight streaming task")
        // Cleanup, not an assertion: on the buggy path reset() leaves the
        // black-holed stream running and `await streamingSend.value` would
        // wedge the suite — cut it so the test ends either way.
        chatStore.cancelStreaming()
        _ = await streamingSend.value
    }

    // MARK: - #291 / #294 — what a Stop leaves behind

    /// #291 bars A and B. `cancelStreaming` finalized ONLY the assistant
    /// placeholder, leaving the user's own optimistic row at `.sending` —
    /// which is exactly the predicate the poll loop's exhaustion branch
    /// tests (`hasPendingMessages`), so ~60s after a deliberate Stop every
    /// `.sending` user row flipped to `.failed` and `onSendFailed` fired an
    /// error haptic, on a turn the host received and partly answered.
    ///
    /// The whole suite was blind to this: every stop test asserted the
    /// assistant placeholder and none asserted the user row. This one
    /// asserts the USER row, and asserts the exact predicate — no user row
    /// left `.sending` — rather than sleeping out the 60s window.
    @Test @MainActor
    func stopSettlesTheUserRowOfTheTurnItStopped() async throws {
        let suiteName = "chat-store-stop-settles-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let persistence = UserDefaultsAppPersistenceStore(defaults: defaults)
        let hermesClient = StoppableStreamingChatClient(script: .partialProse("Half an ans"))
        let chatStore = ChatStore(hermesClient: hermesClient, persistence: persistence)
        var sendFailures = 0
        chatStore.onSendFailed = { sendFailures += 1 }

        let sendTask = Task { @MainActor in await chatStore.sendMessage("stop me") }
        let streamed = await pollUntil {
            chatStore.conversation?.messages.contains { $0.sender == .hermes && !$0.content.isEmpty } == true
        }
        #expect(streamed, "the fixture must reach mid-answer before the Stop")

        chatStore.cancelStreaming()
        _ = await sendTask.value

        let userRows = chatStore.conversation?.messages.filter { $0.sender == .user } ?? []
        #expect(userRows.count == 1)
        #expect(
            userRows.first?.status == .delivered,
            "291-A: the host received this turn — `.sending` and `.failed` are both lies"
        )
        #expect(
            chatStore.conversation?.messages.contains { $0.sender == .user && $0.status == .sending } == false,
            "291-A: no user row may stay `.sending` — that is the poll loop's failure predicate"
        )
        // #291 close-out: this is a CANARY, not coverage, for 291-B. `setPollingEnabled`
        // is never called anywhere in this file, so `restartPendingPollingIfNeeded`
        // early-returns on `isPollingEnabled == false` and the poll loop's exhaustion
        // branch (the one that flips a stuck row to `.failed` and fires `onSendFailed`)
        // never runs here regardless of whether the fix above is present. `sendFailures`
        // is therefore guaranteed 0 in this test file, buggy code included. The bar this
        // test actually proves is the "291-A" assertion immediately above — asserting no
        // user row is left `.sending` is asserting `hasPendingMessages == false`
        // (`ChatStore.hasPendingMessages` is exactly that predicate), which is what
        // keeps the exhaustion branch — and therefore the error haptic — from ever
        // firing when polling IS enabled elsewhere in the app.
        #expect(sendFailures == 0, "291-B: a user-initiated Stop must never fire the error haptic")
    }

    /// #291 bar C and #294 bar C in one relaunch: a fresh `ChatStore` over
    /// the same persistence runs the cold-load scrubber
    /// (`finalizeStaleSendsFromCache`), which flips a `.sending` user row to
    /// `.failed`. A stopped turn must survive that pass unchanged — and the
    /// empty assistant bubble the Stop refused to persist must not be back.
    @Test @MainActor
    func stoppedTurnSurvivesRelaunchWithoutTurningFailed() async throws {
        let suiteName = "chat-store-stop-relaunch-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let persistence = UserDefaultsAppPersistenceStore(defaults: defaults)
        let hermesClient = StoppableStreamingChatClient(script: .silentAfterAccept)
        let chatStore = ChatStore(hermesClient: hermesClient, persistence: persistence)

        let sendTask = Task { @MainActor in await chatStore.sendMessage("stop me early") }
        let armed = await pollUntil { chatStore.isStreaming }
        #expect(armed)

        chatStore.cancelStreaming()
        _ = await sendTask.value

        // The relaunch: a brand-new store reading the cache this Stop wrote.
        let relaunched = ChatStore(
            hermesClient: StoppableStreamingChatClient(script: .silentAfterAccept),
            persistence: persistence
        )
        await relaunched.loadConversationIfNeeded()

        let restored = relaunched.conversation?.messages ?? []
        #expect(
            restored.first(where: { $0.sender == .user })?.status == .delivered,
            "291-C: the settled row must survive a relaunch — the scrubber only rescues `.sending`"
        )
        #expect(
            restored.contains { $0.sender == .hermes } == false,
            "294-C: relaunch after an early Stop shows no empty assistant bubble"
        )
    }

    /// #294 bar A. `isStreaming = false` / `status = .delivered` were set
    /// unconditionally, so a Stop taken during the thinking phase — no
    /// content, no tool activity — persisted a terminal empty assistant row.
    /// The cold-load scrubber that exists for exactly this shape only
    /// catches `.sending`, so it sailed through and survived relaunch.
    @Test @MainActor
    func stopBeforeTheFirstTokenLeavesNoEmptyAssistantRow() async throws {
        let suiteName = "chat-store-stop-empty-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let persistence = UserDefaultsAppPersistenceStore(defaults: defaults)
        let hermesClient = StoppableStreamingChatClient(script: .silentAfterAccept)
        let chatStore = ChatStore(hermesClient: hermesClient, persistence: persistence)

        let sendTask = Task { @MainActor in await chatStore.sendMessage("stop me early") }
        let armed = await pollUntil { chatStore.isStreaming }
        #expect(armed)

        chatStore.cancelStreaming()
        _ = await sendTask.value

        #expect(
            chatStore.conversation?.messages.contains { $0.sender == .hermes } == false,
            "294-A: a Stop with no content and no tool activity leaves no assistant row"
        )
        let cached = persistence.loadConversationCache()?.messages ?? []
        #expect(
            cached.contains { $0.sender == .hermes } == false,
            "294-A: and does not write one to the conversation cache either"
        )
    }

    /// #294 bar B — the trap. The emptiness guard must not eat a real
    /// partial answer: a Stop mid-sentence keeps every character that
    /// streamed, terminal and non-streaming.
    @Test @MainActor
    func stopWithPartialContentKeepsThatContent() async throws {
        let suiteName = "chat-store-stop-partial-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let persistence = UserDefaultsAppPersistenceStore(defaults: defaults)
        let hermesClient = StoppableStreamingChatClient(script: .partialProse("Half an ans"))
        let chatStore = ChatStore(hermesClient: hermesClient, persistence: persistence)

        let sendTask = Task { @MainActor in await chatStore.sendMessage("stop me mid-answer") }
        let streamed = await pollUntil {
            chatStore.conversation?.messages.contains { $0.sender == .hermes && !$0.content.isEmpty } == true
        }
        #expect(streamed)

        chatStore.cancelStreaming()
        _ = await sendTask.value

        let reply = chatStore.conversation?.messages.last { $0.sender == .hermes }
        #expect(reply?.content == "Half an ans", "294-B: the partial answer must survive the Stop")
        #expect(reply?.status == .delivered)
        #expect(reply?.isStreaming == false)
    }

    /// #294 bar B, the other half: a Stop during a tool call has no prose
    /// but does have visible activity — the row stays, with its chips
    /// resolved rather than left spinning.
    ///
    /// **#296 extended this test in place rather than writing a parallel one,
    /// because #294's guarantees and #296's are about the same row and must
    /// be read together.** #294 said KEEP the row; #296 says do not let
    /// keeping it become a claim that the tool succeeded. Everything #294
    /// asserted still holds below, unchanged — the count, the resolved
    /// `isActive`, the `.delivered` status. What is added is the marker and
    /// the rail state derived from it. #294-B's assertions describe a
    /// two-state world (`isActive` false meant "done"); after #296 there is a
    /// third state, and `isActive == false` alone no longer decides the glyph.
    ///
    /// This is also the **read-before-clear ordering pin** for
    /// `cancelStreaming`: the store marks still-active activities and clears
    /// the flag in two separate passes, and a fused loop that cleared first
    /// would leave `failure` nil — the assertion below is what catches it.
    @Test @MainActor
    func stopDuringAToolCallKeepsTheActivityRow() async throws {
        let suiteName = "chat-store-stop-tool-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let persistence = UserDefaultsAppPersistenceStore(defaults: defaults)
        let hermesClient = StoppableStreamingChatClient(script: .toolActivityOnly("read_file"))
        let chatStore = ChatStore(hermesClient: hermesClient, persistence: persistence)

        let sendTask = Task { @MainActor in await chatStore.sendMessage("stop me mid-tool") }
        let toolStarted = await pollUntil {
            chatStore.conversation?.messages.contains { !$0.toolActivities.isEmpty } == true
        }
        #expect(toolStarted)

        chatStore.cancelStreaming()
        _ = await sendTask.value

        let reply = try #require(chatStore.conversation?.messages.last { $0.sender == .hermes })
        #expect(reply.toolActivities.count == 1, "294-B: tool activity with no prose is still something to keep")
        #expect(reply.toolActivities.allSatisfy { $0.isActive == false })
        #expect(reply.status == .delivered)

        // #296-A. Everything above is unchanged; this is what was missing.
        let stopped = try #require(reply.toolActivities.first)
        #expect(
            stopped.failure != nil,
            "296-A: a tool the user stopped is not a tool that finished"
        )
        #expect(stopped.failure == ToolActivity.stoppedByUser)
        // …and stated against the derivation that actually drives the glyph,
        // so this is a claim about what renders, not just about a field.
        #expect(
            ToolActivityRail.state(of: stopped) == .interrupted,
            "296-A: the rail must not draw this as a completed call"
        )
        #expect(ToolActivityRail.summaryState(of: reply.toolActivities) == .interrupted)
        // The input summary is the more useful half and must survive being
        // told why the call ended.
        #expect(stopped.label == "read_file")
    }

    /// #296 bar B, row (i) — the regression bar. A tool resolved by a NAMED
    /// `tool.completed` genuinely finished; a later Stop on the same turn
    /// must not retroactively relabel it. Without this test the cheapest way
    /// to "fix" #296 is to stop drawing the ✓ at all, which trades one lie
    /// for another.
    @Test @MainActor
    func stopAfterANamedToolCompletionLeavesThatToolCompleted() async throws {
        let suiteName = "chat-store-stop-after-completion-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let persistence = UserDefaultsAppPersistenceStore(defaults: defaults)
        let hermesClient = StoppableStreamingChatClient(script: .toolThenNamedCompletion("read_file"))
        let chatStore = ChatStore(hermesClient: hermesClient, persistence: persistence)

        let sendTask = Task { @MainActor in await chatStore.sendMessage("read then stop") }
        let resolved = await pollUntil {
            chatStore.conversation?.messages.contains {
                $0.toolActivities.contains { !$0.isActive }
            } == true
        }
        #expect(resolved)

        chatStore.cancelStreaming()
        _ = await sendTask.value

        let reply = try #require(chatStore.conversation?.messages.last { $0.sender == .hermes })
        let done = try #require(reply.toolActivities.first)
        #expect(
            done.failure == nil,
            "296-B: a tool that reported its own completion before the Stop still finished"
        )
        #expect(ToolActivityRail.state(of: done) == .completed)
        #expect(
            ToolActivityRail.summaryState(of: reply.toolActivities) == .completed,
            "296-B: the ✓ stays where the ✓ is earned"
        )
    }

    /// #296 bar B, row (ii) — the SAME guarantee down a different code path.
    /// A chip is also resolved implicitly when prose starts arriving
    /// (`.textDelta` clears every in-flight activity, because the model
    /// cannot be answering and still be waiting on the tool). That happens in
    /// `ChatStore`'s `.textDelta` arm, not its `.toolActivity` arm, so a fix
    /// that only understood named completions would mark this one stopped.
    @Test @MainActor
    func stopAfterProseResolvedAToolLeavesThatToolCompleted() async throws {
        let suiteName = "chat-store-stop-after-prose-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let persistence = UserDefaultsAppPersistenceStore(defaults: defaults)
        let hermesClient = StoppableStreamingChatClient(
            script: .toolThenProse(name: "read_file", text: "The file says ")
        )
        let chatStore = ChatStore(hermesClient: hermesClient, persistence: persistence)

        let sendTask = Task { @MainActor in await chatStore.sendMessage("read then talk then stop") }
        let proseArrived = await pollUntil {
            chatStore.conversation?.messages.contains {
                $0.sender == .hermes && !$0.content.isEmpty && !$0.toolActivities.isEmpty
            } == true
        }
        #expect(proseArrived)

        chatStore.cancelStreaming()
        _ = await sendTask.value

        let reply = try #require(chatStore.conversation?.messages.last { $0.sender == .hermes })
        #expect(reply.content == "The file says ", "294-B: the partial answer is still kept")
        let done = try #require(reply.toolActivities.first)
        #expect(
            done.failure == nil,
            "296-B: prose arriving means the tool finished — the Stop landed after it, not on it"
        )
        #expect(ToolActivityRail.state(of: done) == .completed)
        #expect(ToolActivityRail.summaryState(of: reply.toolActivities) == .completed)
    }

    /// #296-C1 at the store. A `tool.completed` carrying the host's error
    /// text lands on the resolving activity's `failure` — and, the half that
    /// matters just as much, leaves `detail` alone. `detail` is the call's
    /// INPUT summary (#11); overwriting it would trade "what the call
    /// touched" for "why it stopped" and lose the more useful of the two.
    @Test @MainActor
    func aHostReportedToolErrorLandsOnFailureAndLeavesDetailAlone() async throws {
        let suiteName = "chat-store-tool-error-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let persistence = UserDefaultsAppPersistenceStore(defaults: defaults)
        let client = ScriptedStreamChatClient(script: [
            .toolActivity(ToolCallEvent(name: "terminal", phase: .started, detail: "cat missing.txt")),
            .toolActivity(ToolCallEvent(name: "terminal", phase: .completed, detail: "exit_code 1: no such file")),
            .finished(Message(sender: .hermes, content: "That file is not there.", status: .delivered), nil, nil),
        ])
        let chatStore = ChatStore(hermesClient: client, persistence: persistence)

        await chatStore.sendMessage("cat missing.txt")

        let reply = try #require(chatStore.conversation?.messages.last { $0.sender == .hermes })
        let activity = try #require(reply.toolActivities.first)
        #expect(activity.failure == "exit_code 1: no such file", "296-C1: the host's own account of the failure survives")
        #expect(activity.detail == "cat missing.txt", "296-C1: and it does NOT overwrite the input summary")
        #expect(activity.isActive == false)
        #expect(ToolActivityRail.state(of: activity) == .interrupted)
    }

    /// The other side of 296-C1, and it is 296-B in miniature: an EMPTY
    /// `error` on a `tool.completed` is a host saying nothing went wrong.
    /// Writing `""` into `failure` would make a successful call render as
    /// interrupted — #296's defect pointed the other way.
    @Test @MainActor
    func anEmptyHostErrorDoesNotMarkACompletedToolInterrupted() async throws {
        let suiteName = "chat-store-empty-tool-error-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let persistence = UserDefaultsAppPersistenceStore(defaults: defaults)
        let client = ScriptedStreamChatClient(script: [
            .toolActivity(ToolCallEvent(name: "terminal", phase: .started, detail: "echo hi")),
            .toolActivity(ToolCallEvent(name: "terminal", phase: .completed, detail: "")),
            .finished(Message(sender: .hermes, content: "hi", status: .delivered), nil, nil),
        ])
        let chatStore = ChatStore(hermesClient: client, persistence: persistence)

        await chatStore.sendMessage("echo hi")

        let reply = try #require(chatStore.conversation?.messages.last { $0.sender == .hermes })
        let activity = try #require(reply.toolActivities.first)
        #expect(activity.failure == nil)
        #expect(ToolActivityRail.state(of: activity) == .completed)
    }

    // MARK: - #295 — the expiration path's own settle + identifier capture

    /// #295 bar A (partial — this task only parameterizes the settle value;
    /// the recovery route itself arms in Task 2). The continued-send
    /// expiration handler calls `cancelStreaming(hardStopHost: false)` — the
    /// SYSTEM revoking the background budget, not the user tapping Stop —
    /// and the turn's user row must read `.working`, not `.delivered`: the
    /// host may still be generating a reply, so `.delivered` would claim an
    /// answer that hasn't arrived.
    ///
    /// #295 review follow-up: `.working` is now honest ONLY when recovery
    /// actually armed (a gate this test didn't originally exercise — it had
    /// no `journal`, so `activeSessionID` was always nil and no session id
    /// could ever resolve). Wired a journal with a real hop so this test
    /// keeps testing what its own name promises: a genuinely-recoverable
    /// turn settling `.working`. The gate's negative case (`.delivered` when
    /// nothing is watching) is `localBrainExpirationArmsNoRecoveryAndPreservesThePartial`.
    @Test @MainActor
    func expirationPathSettlesTheUserRowWorking() async throws {
        let suiteName = "chat-store-expiration-settles-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let persistence = UserDefaultsAppPersistenceStore(defaults: defaults)
        let journal = ConversationJournalStore(persistence: persistence)
        journal.beginHop(apiSessionId: "expiration-settle-session", primingUsage: nil)
        let hermesClient = StoppableStreamingChatClient(script: .partialProse("Half an ans"))
        let chatStore = ChatStore(hermesClient: hermesClient, persistence: persistence, journal: journal)

        let sendTask = Task { @MainActor in await chatStore.sendMessage("expire me") }
        let streamed = await pollUntil {
            chatStore.conversation?.messages.contains { $0.sender == .hermes && !$0.content.isEmpty } == true
        }
        #expect(streamed, "the fixture must reach mid-answer before expiration fires")

        chatStore.cancelStreaming(hardStopHost: false)
        _ = await sendTask.value

        let userRows = chatStore.conversation?.messages.filter { $0.sender == .user } ?? []
        #expect(userRows.count == 1)
        #expect(
            userRows.first?.status == .working,
            "295-A: the SYSTEM cut the app off mid-turn — the host may still answer, so `.delivered` would be a lie"
        )
    }

    /// #295 bar B pin. Distinct from the pre-existing
    /// `stopSettlesTheUserRowOfTheTurnItStopped` (which pins the haptic
    /// suppression under the OLD unparameterized call) — this one exercises
    /// the new `as:` parameter's default explicitly, so the expiration
    /// path's `.working` addition above cannot silently flip the
    /// user-initiated Stop's own terminal.
    @Test @MainActor
    func explicitStopStillSettlesTheUserRowDelivered() async throws {
        let suiteName = "chat-store-explicit-stop-delivered-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let persistence = UserDefaultsAppPersistenceStore(defaults: defaults)
        let hermesClient = StoppableStreamingChatClient(script: .partialProse("Half an ans"))
        let chatStore = ChatStore(hermesClient: hermesClient, persistence: persistence)

        let sendTask = Task { @MainActor in await chatStore.sendMessage("stop me for real") }
        let streamed = await pollUntil {
            chatStore.conversation?.messages.contains { $0.sender == .hermes && !$0.content.isEmpty } == true
        }
        #expect(streamed)

        chatStore.cancelStreaming()
        _ = await sendTask.value

        let userRows = chatStore.conversation?.messages.filter { $0.sender == .user } ?? []
        #expect(userRows.count == 1)
        #expect(userRows.first?.status == .delivered, "295-B: a user-initiated Stop is unaffected — still `.delivered`")
    }

    /// #295: `activeStreamRun` is the session id a later `cancelStreaming`
    /// needs to arm real recovery (Task 2's `PendingRun`) — captured as soon
    /// as the send path learns the session id and cleared on every terminal
    /// path. (Review follow-up: this used to be a `(sessionId:runId:)` tuple;
    /// `runId` was dropped as provably-always-nil dead weight — see the
    /// property's own doc.) The session id source is the shared journal's
    /// active hop
    /// (`activeSessionID`), the same value `SessionsHermesClient
    /// .ensureHopForTurn()` records before ANY stream event is yielded in
    /// production — so wiring a real `ConversationJournalStore` with a hop
    /// already begun models that ordering faithfully rather than inventing a
    /// test-only channel. Two phases, two different terminal paths: the
    /// expiration path's own terminal (`cancelStreaming`), then a clean
    /// `.finished` completion — both must leave `activeStreamRun` nil.
    @Test @MainActor
    func activeStreamRunIsCapturedDuringAStreamAndClearedOnTerminalPaths() async throws {
        // Phase 1: mid-stream capture, cleared by cancelStreaming(hardStopHost: false).
        let suiteName1 = "chat-store-active-stream-run-cancel-\(UUID().uuidString)"
        let defaults1 = UserDefaults(suiteName: suiteName1)!
        defaults1.removePersistentDomain(forName: suiteName1)
        let persistence1 = UserDefaultsAppPersistenceStore(defaults: defaults1)
        let journal1 = ConversationJournalStore(persistence: persistence1)
        journal1.beginHop(apiSessionId: "capture-session", primingUsage: nil)
        let hermesClient1 = StoppableStreamingChatClient(script: .partialProse("Half an ans"))
        let chatStore1 = ChatStore(hermesClient: hermesClient1, persistence: persistence1, journal: journal1)

        #expect(chatStore1.activeStreamRun == nil, "nothing has streamed yet")
        let sendTask1 = Task { @MainActor in await chatStore1.sendMessage("capture me") }
        let streamed = await pollUntil {
            chatStore1.conversation?.messages.contains { $0.sender == .hermes && !$0.content.isEmpty } == true
        }
        #expect(streamed)
        #expect(
            chatStore1.activeStreamRun == "capture-session",
            "295: the send path captured the active hop's session id mid-stream"
        )

        chatStore1.cancelStreaming(hardStopHost: false)
        _ = await sendTask1.value
        #expect(chatStore1.activeStreamRun == nil, "295: cancelStreaming is a terminal path — must clear the capture")

        // Phase 2: a normal .finished completion is also a terminal path.
        let suiteName2 = "chat-store-active-stream-run-finish-\(UUID().uuidString)"
        let defaults2 = UserDefaults(suiteName: suiteName2)!
        defaults2.removePersistentDomain(forName: suiteName2)
        let persistence2 = UserDefaultsAppPersistenceStore(defaults: defaults2)
        let journal2 = ConversationJournalStore(persistence: persistence2)
        journal2.beginHop(apiSessionId: "capture-session-2", primingUsage: nil)
        let hermesClient2 = RecordingHermesClient()
        let chatStore2 = ChatStore(hermesClient: hermesClient2, persistence: persistence2, journal: journal2)

        await chatStore2.sendMessage("finish me")
        #expect(chatStore2.activeStreamRun == nil, "295: a clean .finished completion must also clear the capture")
    }

    // MARK: - #295 Task 2 — the expiration path arms the real recovery

    /// #295 bar A: the core of the lane. `cancelStreaming(hardStopHost: false)`
    /// must mirror the `.interrupted` arm's mechanics (:905-951, the reference
    /// implementation) instead of finalizing the placeholder as a terminal
    /// `.delivered` bubble the way an explicit Stop does — the host run is
    /// still generating (we deliberately did NOT tell it to stop), so
    /// `.delivered` here would be the silent hole this lane exists to close.
    /// Drives the whole recovery loop end-to-end, including the one thing a
    /// private `PendingRun.partialReasoning` can't be asserted on directly:
    /// once the reconcile loop adopts the server's reply, the reasoning
    /// streamed before the drop must reappear on it — proving it actually
    /// rode the PendingRun, not just that a PendingRun exists.
    ///
    /// #295 review follow-up: `ExpiringReconcileClient` explicitly opts into
    /// `currentRunIsServerRecoverable == true` — this test's whole point is
    /// the GATE saying yes (a real Hermes-plane turn), the mirror image of
    /// `localBrainExpirationArmsNoRecoveryAndPreservesThePartial` below,
    /// which pins the gate saying no. Bar 295-A stays intact under the gate.
    @Test @MainActor
    func expirationPathArmsTheRealRecovery() async throws {
        final class ExpiringReconcileClient: HermesClientProtocol {
            var connectionStatus: ConnectionStatus = .connected
            var currentConversation: Conversation?
            var replyAvailable = false
            // #295 review follow-up: this client models a real Hermes-plane
            // turn — the gate must see that and arm recovery.
            let currentRunIsServerRecoverable = true

            func connect() async {}
            func disconnect() async {}

            func send(message: String, attachments: [PendingAttachment] = [], clientMessageID: UUID) async -> Message {
                Message(sender: .hermes, content: "unused", status: .delivered)
            }

            func sendStreaming(message: String, attachments: [PendingAttachment] = [], clientMessageID: UUID) -> AsyncStream<StreamingUpdate> {
                currentConversation = Conversation(
                    title: "Hermes",
                    messages: [Message(clientMessageID: clientMessageID, sender: .user, content: message, status: .sent)]
                )
                return AsyncStream { continuation in
                    continuation.yield(.reasoningDelta("thinking about the attachment upload"))
                    // Never finishes — the run stays live server-side until
                    // expiration cuts the app off, same shape
                    // `StoppableStreamingChatClient` models for an explicit Stop.
                }
            }

            func loadConversation() async -> Conversation { currentConversation ?? Conversation(title: "Hermes") }
            func clearConversation() async throws -> Conversation { Conversation(title: "Hermes") }

            func reconcileFromServer() async -> Conversation? {
                guard replyAvailable else { return nil }
                var convo = currentConversation ?? Conversation(title: "Hermes")
                convo.messages.append(Message(sender: .hermes, content: "Recovered answer", status: .delivered))
                currentConversation = convo
                return convo
            }
        }

        let suiteName = "chat-store-expiration-arms-recovery-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let persistence = UserDefaultsAppPersistenceStore(defaults: defaults)
        let journal = ConversationJournalStore(persistence: persistence)
        journal.beginHop(apiSessionId: "arm-recovery-session", primingUsage: nil)
        let hermesClient = ExpiringReconcileClient()
        let chatStore = ChatStore(hermesClient: hermesClient, persistence: persistence, journal: journal)
        chatStore.reconcileWallClockBudget = .milliseconds(120)
        chatStore.reconcilePollInterval = .milliseconds(30)

        let sendTask = Task { @MainActor in await chatStore.sendMessage("expire me with attachments") }
        let reasoningStreamed = await pollUntil {
            chatStore.conversation?.messages.contains { $0.sender == .hermes && ($0.reasoning?.isEmpty == false) } == true
        }
        #expect(reasoningStreamed, "the fixture must reach mid-reasoning before expiration fires")

        chatStore.cancelStreaming(hardStopHost: false)
        _ = await sendTask.value

        #expect(
            chatStore.conversation?.messages.contains { $0.sender == .hermes } == false,
            "295-A: the placeholder is REMOVED, not finalized as a terminal `.delivered` bubble"
        )
        let userRows = chatStore.conversation?.messages.filter { $0.sender == .user } ?? []
        #expect(userRows.first?.status == .working)
        #expect(chatStore.pendingRunSessionId == "arm-recovery-session", "295-A: PendingRun minted from the captured session")
        #expect(chatStore.hasActiveReconcileLoop, "295-A: the reconcile loop must be armed")

        var pumps = 0
        while chatStore.hasActiveReconcileLoop, pumps < 200 {
            pumps += 1
            try? await Task.sleep(for: .milliseconds(25))
        }
        #expect(chatStore.hasActiveReconcileLoop == false, "budget exhausted with no reply yet")
        #expect(chatStore.pendingRunSessionId == "arm-recovery-session", "budget expiry must not orphan the pending run")

        hermesClient.replyAvailable = true
        await chatStore.reconcilePendingRuns()
        #expect(chatStore.pendingRunSessionId == nil, "the single-shot resolves once the reply exists")
        #expect(chatStore.conversation?.messages.last?.content == "Recovered answer")
        #expect(
            chatStore.conversation?.messages.last?.reasoning == "thinking about the attachment upload",
            "295-A: reasoning captured before the drop must survive on the PendingRun into the recovered reply"
        )
    }

    /// #295 bar B pin (Task 2's half): an explicit, user-initiated Stop
    /// (`hardStopHost: true`, the default) must mint NO `PendingRun` and arm
    /// no reconcile loop — only the expiration path (`hardStopHost: false`)
    /// does that. Distinct from `explicitStopStillSettlesTheUserRowDelivered`
    /// (Task 1's pin, which only checks the user row's status) — this test
    /// exists because Task 2 is what actually adds code capable of minting a
    /// PendingRun from `cancelStreaming`, and that code must stay gated on
    /// `hardStopHost`.
    @Test @MainActor
    func explicitStopMintsNoPendingRunAndArmsNoReconcileLoop() async throws {
        let suiteName = "chat-store-explicit-stop-no-recovery-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let persistence = UserDefaultsAppPersistenceStore(defaults: defaults)
        let journal = ConversationJournalStore(persistence: persistence)
        journal.beginHop(apiSessionId: "explicit-stop-session", primingUsage: nil)
        let hermesClient = StoppableStreamingChatClient(script: .partialProse("Half an ans"))
        let chatStore = ChatStore(hermesClient: hermesClient, persistence: persistence, journal: journal)

        let sendTask = Task { @MainActor in await chatStore.sendMessage("stop me for real") }
        let streamed = await pollUntil {
            chatStore.conversation?.messages.contains { $0.sender == .hermes && !$0.content.isEmpty } == true
        }
        #expect(streamed)

        chatStore.cancelStreaming()
        _ = await sendTask.value

        #expect(chatStore.pendingRunSessionId == nil, "295-B: a user-initiated Stop must mint no PendingRun")
        #expect(chatStore.hasActiveReconcileLoop == false, "295-B: a user-initiated Stop must arm no reconcile loop")
    }

    /// #295 carried finding, from Task 1's self-review: `activeStreamRun` is
    /// written ONLY inside the stream's `for await` loop, and
    /// `SessionsHermesClient` never yields `.messageSent` — so on an
    /// attachment turn whose OWN upload outlasts the background budget,
    /// expiration can fire before a single `StreamingUpdate` is ever
    /// processed, leaving `activeStreamRun` nil at the exact moment
    /// `cancelStreaming` needs a sessionId to mint `PendingRun`. This test
    /// drives exactly that shape — a client that never yields anything at
    /// all — and pins the resolution: `activeSessionID` (the journal's
    /// active hop, set by `ensureHopForTurn()` before the turn's POST even
    /// goes out, and confirmed synchronously correct in this window by Task
    /// 1's report) is the fallback that still arms recovery.
    @Test @MainActor
    func expirationArmsRecoveryEvenWithZeroStreamingUpdatesProcessed() async throws {
        final class SilentStreamingChatClient: HermesClientProtocol {
            var connectionStatus: ConnectionStatus = .connected
            var currentConversation: Conversation?
            // #382 bar 382-A: the POST captured a run id before the stream
            // went silent — expiration must feed it into recovery.
            var activeRunID: String? { "run-zero-events" }
            // #295 review follow-up: this models a Hermes-plane attachment
            // upload (the one shape that can hit zero processed events before
            // expiration) — the gate must see that and still arm recovery.
            let currentRunIsServerRecoverable = true

            func connect() async {}
            func disconnect() async {}

            func send(message: String, attachments: [PendingAttachment] = [], clientMessageID: UUID) async -> Message {
                Message(sender: .hermes, content: "unused", status: .delivered)
            }

            func sendStreaming(message: String, attachments: [PendingAttachment] = [], clientMessageID: UUID) -> AsyncStream<StreamingUpdate> {
                // Deliberately yields nothing, ever — models expiration firing
                // before the stream has delivered even one event.
                AsyncStream { _ in }
            }

            func loadConversation() async -> Conversation { currentConversation ?? Conversation(title: "Hermes") }
            func clearConversation() async throws -> Conversation { Conversation(title: "Hermes") }
        }

        let suiteName = "chat-store-expiration-zero-events-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let persistence = UserDefaultsAppPersistenceStore(defaults: defaults)
        let journal = ConversationJournalStore(persistence: persistence)
        journal.beginHop(apiSessionId: "zero-event-session", primingUsage: nil)
        let hermesClient = SilentStreamingChatClient()
        let chatStore = ChatStore(hermesClient: hermesClient, persistence: persistence, journal: journal)

        let sendTask = Task { @MainActor in await chatStore.sendMessage("upload that outlasts the budget") }
        let placeholderAppeared = await pollUntil { chatStore.streamingMessageID != nil }
        #expect(placeholderAppeared)
        #expect(chatStore.activeStreamRun == nil, "the stream has not yielded a single event yet")

        chatStore.cancelStreaming(hardStopHost: false)
        _ = await sendTask.value

        #expect(
            chatStore.pendingRunSessionId == "zero-event-session",
            "295 carried finding: the activeSessionID fallback must arm recovery when activeStreamRun never got a chance to capture"
        )
        #expect(
            chatStore.pendingRunRunId == "run-zero-events",
            "382-A: the expiration arm must feed cancelledRunID into recovery — nil strands the pending run on the positional session re-read instead of its own status read"
        )
        #expect(chatStore.hasActiveReconcileLoop, "reconcile loop must be armed")
        #expect(
            chatStore.conversation?.messages.contains { $0.sender == .hermes } == false,
            "placeholder removed, not finalized as a terminal `.delivered` bubble"
        )
        let userRows = chatStore.conversation?.messages.filter { $0.sender == .user } ?? []
        #expect(userRows.first?.status == .working)
    }

    /// #295 hazard 2 pin: `abandonActiveRun()` must stay UNCONDITIONAL on the
    /// expiration path (releasing the router's routing lock, #192) while
    /// `hardStopActiveRun()` must stay GATED off it (never hard-killing a
    /// host run the user didn't ask to stop) — and neither call may interfere
    /// with the SAME `cancelStreaming` call's ability to arm the reconcile
    /// loop. Investigation (see the task report): `abandonActiveRun` is
    /// already, by #283's review ruling, lock-release-only and network-free
    /// — it never touches `SessionsHermesClient.activeRunContext` (only
    /// `hardStopActiveRun`/the run's own terminal `defer` clear that), and
    /// `reconcileFromServer()` reads `journal.activeHop`, not
    /// `activeRunContext` — so the two concerns (releasing the routing lock,
    /// arming recovery) are already independent. This test fails if a future
    /// edit gates `abandonActiveRun` behind `hardStopHost` (wedging routing
    /// until force quit on every expiration) or fires `hardStopActiveRun` on
    /// the expiration path (hard-killing an unstopped run).
    @Test @MainActor
    func expirationCancelReleasesRoutingLockWithoutHardStoppingTheHost() async throws {
        let suiteName = "chat-store-expiration-abandon-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let persistence = UserDefaultsAppPersistenceStore(defaults: defaults)
        let journal = ConversationJournalStore(persistence: persistence)
        journal.beginHop(apiSessionId: "abandon-session", primingUsage: nil)
        let hermesClient = StoppableStreamingChatClient(script: .partialProse("Half an ans"))
        let chatStore = ChatStore(hermesClient: hermesClient, persistence: persistence, journal: journal)

        let sendTask = Task { @MainActor in await chatStore.sendMessage("expire and release the lock") }
        let streamed = await pollUntil {
            chatStore.conversation?.messages.contains { $0.sender == .hermes && !$0.content.isEmpty } == true
        }
        #expect(streamed)

        chatStore.cancelStreaming(hardStopHost: false)
        _ = await sendTask.value

        #expect(hermesClient.abandonActiveRunCallCount == 1, "the routing lock must still release on the expiration path")
        #expect(hermesClient.hardStopActiveRunCallCount == 0, "the expiration path must never hard-kill the host run")
        #expect(chatStore.pendingRunSessionId == "abandon-session", "releasing the lock must not interfere with arming recovery")
        #expect(chatStore.hasActiveReconcileLoop)
    }

    // MARK: - #295 review follow-up (Owen's ruling) — gate the arm to server-recoverable turns

    /// #295 gate pin (Owen's ruling): a LOCAL-brain turn (on-device / PCC,
    /// #30) can NEVER be recovered server-side — nothing is committed to any
    /// host, so arming a `PendingRun` for it would be worse than the silent
    /// hole this lane closes for Hermes turns. Two failure modes, both real:
    /// (1) `reconcileFromServer()` would never find a matching reply for
    /// THIS turn, so `performReconcilePendingRuns` (fired on every
    /// foreground/appear) re-arms a fresh budget window indefinitely; (2)
    /// worse, `reconcileFromServer()` resolves against `journal.activeHop`,
    /// NOT `pending.sessionId` — so once the conversation's NEXT Hermes turn
    /// lands on a fresh hop, `attemptReconcile`'s filter (`sender == .hermes
    /// && timestamp > pending.sentAt`) matches THAT reply and wrongly stamps
    /// it with THIS dead local turn's `partialReasoning`/`turnDuration`,
    /// re-paired via `placingRecoveredReply` with THIS turn's prompt —
    /// cross-hop corruption, sequential, no concurrency needed. This test
    /// wires exactly the shape the corruption needs (an EARLIER Hermes hop
    /// already on the journal) and pins that the gate — `currentRunIsServerRecoverable`,
    /// read before `abandonActiveRun()` clears the signal it's built from —
    /// stops it: no `PendingRun`, no loop, AND the partial is preserved
    /// (finalized like an explicit Stop) rather than destroyed the way the
    /// recovery arm's placeholder removal would have.
    @Test @MainActor
    func localBrainExpirationArmsNoRecoveryAndPreservesThePartial() async throws {
        /// Models `LocalChatBackend`: never overrides `currentRunIsServerRecoverable`
        /// (protocol default `false`) or `reconcileFromServer()` (default `nil`)
        /// — exactly like the real on-device/PCC client, which has no server
        /// to reconcile against. Streams a partial, then goes silent —
        /// held-open-until-Stop, mirroring `StoppableStreamingChatClient`'s
        /// shape for the Hermes plane.
        final class LocalBrainStreamingChatClient: HermesClientProtocol {
            var connectionStatus: ConnectionStatus = .connected
            var currentConversation: Conversation?

            func connect() async {}
            func disconnect() async {}

            func send(message: String, attachments: [PendingAttachment] = [], clientMessageID: UUID) async -> Message {
                Message(sender: .hermes, content: "unused", status: .delivered)
            }

            func sendStreaming(message: String, attachments: [PendingAttachment] = [], clientMessageID: UUID) -> AsyncStream<StreamingUpdate> {
                AsyncStream { continuation in
                    continuation.yield(.textDelta("Half a local ans"))
                    // Never finishes — the app is suspended mid on-device
                    // generation; there is no host still producing anything.
                }
            }

            func loadConversation() async -> Conversation { currentConversation ?? Conversation(title: "Hermes") }
            func clearConversation() async throws -> Conversation { Conversation(title: "Hermes") }
        }

        let suiteName = "chat-store-expiration-local-brain-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let persistence = UserDefaultsAppPersistenceStore(defaults: defaults)
        let journal = ConversationJournalStore(persistence: persistence)
        // The exact shape the corruption sequence needs: an EARLIER Hermes
        // turn already left a real, non-nil hop on the journal, even though
        // THIS turn never touches Hermes at all.
        journal.beginHop(apiSessionId: "earlier-hermes-hop", primingUsage: nil)
        let hermesClient = LocalBrainStreamingChatClient()
        let chatStore = ChatStore(hermesClient: hermesClient, persistence: persistence, journal: journal)

        let sendTask = Task { @MainActor in await chatStore.sendMessage("local turn that expires") }
        let streamed = await pollUntil {
            chatStore.conversation?.messages.contains { $0.sender == .hermes && !$0.content.isEmpty } == true
        }
        #expect(streamed)

        chatStore.cancelStreaming(hardStopHost: false)
        _ = await sendTask.value

        #expect(chatStore.pendingRunSessionId == nil, "a local-brain turn must arm NO recovery — nothing is committed server-side")
        #expect(chatStore.hasActiveReconcileLoop == false)
        let reply = chatStore.conversation?.messages.last { $0.sender == .hermes }
        #expect(
            reply?.content == "Half a local ans",
            "the partial must be PRESERVED, not destroyed the way the recovery arm's placeholder removal would have"
        )
        let userRows = chatStore.conversation?.messages.filter { $0.sender == .user } ?? []
        #expect(
            userRows.first?.status == .delivered,
            "295 gate fix: no recovery is coming, so `.working` would be a lie nothing ever scrubs — settle `.delivered` like an explicit Stop"
        )
    }

    /// #295 Task 3 (the ordering pin, carried from the fix re-review):
    /// `cancelStreaming` reads `hermesClient.currentRunIsServerRecoverable` as
    /// its FIRST statement — deliberately ahead of `streamingTask?.cancel()`,
    /// `hardStopActiveRun()` and `abandonActiveRun()` — because
    /// `abandonActiveRun()` is documented (`ChatBackendRouter`) to nil the
    /// router's `runningBrain`, i.e. the very signal the real gate is built
    /// from. Every OTHER double in this file answers
    /// `currentRunIsServerRecoverable` with a constant, so none of them can
    /// tell the difference between "read before the clear" and "read after
    /// the clear" — a future refactor that moved the read line down past
    /// `abandonActiveRun()` would leave the whole suite GREEN while every
    /// production Hermes expiration silently fell to the `.delivered`
    /// branch, bar 295-A dead with no test failing. `RecoverabilityFlipsOnAbandonClient`
    /// closes that hole directly: it starts `true` (a live Hermes-plane
    /// turn) and flips to `false` the instant `abandonActiveRun()` OR
    /// `hardStopActiveRun()` is called on it, modeling the hazard without
    /// going through the router. If `cancelStreaming` ever reads the flag
    /// after either call, this test observes `false` and fails.
    ///
    /// RED evidence (task report): moving the
    /// `let turnIsServerRecoverable = hermesClient.currentRunIsServerRecoverable`
    /// line to just after `hermesClient.abandonActiveRun()` turns this test
    /// red — `pendingRunSessionId` comes back nil and `hasActiveReconcileLoop`
    /// false, i.e. the expiration path silently takes the non-recoverable
    /// branch. Restored immediately after confirming.
    @Test @MainActor
    func expirationGateReadsRecoverabilityBeforeAbandonActiveRunClearsIt() async throws {
        final class RecoverabilityFlipsOnAbandonClient: HermesClientProtocol {
            var connectionStatus: ConnectionStatus = .connected
            var currentConversation: Conversation?
            /// Starts `true` (a live, server-recoverable Hermes turn) and
            /// flips to `false` the moment either teardown call fires — the
            /// exact shape `ChatBackendRouter.runningBrain` going nil takes
            /// in production, modeled directly on the client so the test
            /// doesn't need the router.
            private(set) var currentRunIsServerRecoverable = true

            func connect() async {}
            func disconnect() async {}

            func abandonActiveRun() {
                currentRunIsServerRecoverable = false
            }

            @discardableResult
            func hardStopActiveRun() -> Bool {
                currentRunIsServerRecoverable = false
                return hostStopIsIssuable
            }
            /// #328 route 2: whether this double's plane can issue a real host
            /// stop. Default false — the sessions `chat/stream` shape.
            var hostStopIsIssuable = false

            func send(message: String, attachments: [PendingAttachment] = [], clientMessageID: UUID) async -> Message {
                Message(sender: .hermes, content: "unused", status: .delivered)
            }

            func sendStreaming(message: String, attachments: [PendingAttachment] = [], clientMessageID: UUID) -> AsyncStream<StreamingUpdate> {
                AsyncStream { continuation in
                    continuation.yield(.textDelta("Half an ans"))
                    // Never finishes — held open until cancelStreaming(hardStopHost: false),
                    // same shape StoppableStreamingChatClient uses for an explicit Stop.
                }
            }

            func loadConversation() async -> Conversation { currentConversation ?? Conversation(title: "Hermes") }
            func clearConversation() async throws -> Conversation { Conversation(title: "Hermes") }
            func reconcileFromServer() async -> Conversation? { nil }
        }

        let suiteName = "chat-store-ordering-pin-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let persistence = UserDefaultsAppPersistenceStore(defaults: defaults)
        let journal = ConversationJournalStore(persistence: persistence)
        journal.beginHop(apiSessionId: "ordering-pin-session", primingUsage: nil)
        let hermesClient = RecoverabilityFlipsOnAbandonClient()
        let chatStore = ChatStore(hermesClient: hermesClient, persistence: persistence, journal: journal)

        let sendTask = Task { @MainActor in await chatStore.sendMessage("pin the recoverability read order") }
        let streamed = await pollUntil {
            chatStore.conversation?.messages.contains { $0.sender == .hermes && !$0.content.isEmpty } == true
        }
        #expect(streamed, "the fixture must reach mid-answer before expiration fires")

        chatStore.cancelStreaming(hardStopHost: false)
        _ = await sendTask.value

        #expect(
            chatStore.pendingRunSessionId == "ordering-pin-session",
            "295 ordering pin: cancelStreaming must read currentRunIsServerRecoverable BEFORE abandonActiveRun() clears it — a read taken after would see false and silently arm no recovery"
        )
        #expect(
            chatStore.hasActiveReconcileLoop,
            "295 ordering pin: the reconcile loop must still be armed — proves the gate saw `true`, not the post-clear `false`"
        )
    }

    // #309 (2026-08-25, Owen's ruling 1 — LiveHermesClient deleted as
    // production-dead): two tests were DELETED here. Neither was repointed,
    // and in both cases the reason is that the behaviour changed rather than
    // moved — which is the part worth writing down.
    //
    // 1. `liveHermesClientRefreshesConversationBeforeResolvingFinishedStreamMessage`
    //    pinned the relay streaming tail: a `done` frame carrying no message,
    //    then a re-fetch of `conversations/current`, then the final message
    //    picked out of the refreshed transcript by matching jobId (three
    //    requests, no more). Every moving part of that is relay-plane —
    //    `jobs/{id}/events`, a server-owned "current conversation", a job id.
    //    The runs plane resolves its own tail from `assistant.completed` /
    //    `run.completed` and never reads the session transcript back, so
    //    there is no client-level re-fetch left to pin. What survived is the
    //    STORE-level shape of the same worry — run committed server-side,
    //    stream dropped, refresh before believing the local copy — and it is
    //    pinned live by `chatStoreRefreshesConversationWhenStreamingInterruptedAfterJobAccepted`
    //    (reconcilePendingRuns -> reconcileFromServer) plus #295's ordering
    //    pin, `expirationGateReadsRecoverabilityBeforeAbandonActiveRunClearsIt`.
    //
    // 2. `liveHermesClientRejectsOversizedAggregateAttachmentPayloadBeforeSending`
    //    pinned a REJECTION: four over-budget attachments, zero requests
    //    issued, a failed message reading "The attachment was too large for
    //    Hermes to process." That behaviour was deliberately replaced, not
    //    lost. `AttachmentInlining.aggregateAttachmentBudget` (900 KB) now
    //    carries the same ~1 MB server-body rationale, and an attachment that
    //    cannot fit ships an omission stub inside its BEGIN/END frame instead
    //    of failing the turn — #43's "never silently short the user an
    //    attachment", the degrade-honestly rule (#180) applied to a size cap.
    //    The successor is pinned by `AttachmentInliningTests` and, on the same
    //    four-attachment shape this test used, by
    //    `AttachmentDownscaleTests.fourImagesNoLongerOverrunTheAggregateBudget`.
    //    Rewriting this test against the runs plane would have asserted a
    //    rejection the app no longer performs, and should not.

    @Test @MainActor
    func chatStoreRetriesAttachmentOnlyMessageWithRestoredAttachments() async throws {
        final class AttachmentRetryClient: HermesClientProtocol {
            var connectionStatus: ConnectionStatus = .connected
            var currentConversation: Conversation?
            var lastMessage: String?
            var lastAttachments: [PendingAttachment] = []

            func connect() async {}
            func disconnect() async {}

            func send(message: String, attachments: [PendingAttachment], clientMessageID: UUID) async -> Message {
                lastMessage = message
                lastAttachments = attachments
                return Message(sender: .hermes, content: "unused", status: .delivered)
            }

            func sendStreaming(message: String, attachments: [PendingAttachment], clientMessageID: UUID) -> AsyncStream<StreamingUpdate> {
                lastMessage = message
                lastAttachments = attachments
                return AsyncStream { continuation in
                    Task { @MainActor in
                        continuation.yield(.messageSent(jobID: UUID()))
                        continuation.yield(.finished(Message(sender: .hermes, content: "Retried", status: .delivered), nil, nil))
                        continuation.finish()
                    }
                }
            }

            func loadConversation() async -> Conversation {
                currentConversation ?? Conversation(title: "Hermes")
            }

            func clearConversation() async throws -> Conversation {
                Conversation(title: "Hermes")
            }

        }

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("attachment-retry-\(UUID().uuidString).txt")
        let retryData = try #require("retry me".data(using: .utf8))
        try retryData.write(to: tempURL)
        let attachment = try #require(PendingAttachment.file(at: tempURL))

        let suiteName = "chat-store-attachment-retry-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let persistence = UserDefaultsAppPersistenceStore(defaults: defaults)
        let hermesClient = AttachmentRetryClient()
        let chatStore = ChatStore(hermesClient: hermesClient, persistence: persistence)

        let failedMessage = Message(
            sender: .user,
            content: "[1 attachment]",
            status: .failed,
            attachments: [MessageAttachment(from: attachment)]
        )
        chatStore.conversation = Conversation(title: "Hermes", messages: [failedMessage])

        await chatStore.retryMessage(failedMessage)

        #expect(hermesClient.lastMessage == "")
        #expect(hermesClient.lastAttachments.count == 1)
        #expect(hermesClient.lastAttachments.first?.fileName == attachment.fileName)
    }

    @Test @MainActor
    func chatStorePreservesUserAttachmentPreviewMetadataAfterRefresh() async throws {
        final class AttachmentRoundTripClient: HermesClientProtocol {
            var connectionStatus: ConnectionStatus = .connected
            var currentConversation: Conversation?

            func connect() async {}
            func disconnect() async {}

            func send(message: String, attachments: [PendingAttachment], clientMessageID: UUID) async -> Message {
                Message(sender: .hermes, content: "unused", status: .delivered)
            }

            func sendStreaming(message: String, attachments: [PendingAttachment], clientMessageID: UUID) -> AsyncStream<StreamingUpdate> {
                currentConversation = Conversation(
                    title: "Hermes",
                    messages: [
                        Message(
                            id: UUID(),
                            clientMessageID: clientMessageID,
                            sender: .user,
                            content: "",
                            status: .sent,
                            attachments: attachments.map {
                                MessageAttachment(
                                    kind: $0.kind.rawValue,
                                    fileName: $0.fileName,
                                    mimeType: $0.mimeType,
                                    thumbnailBase64: $0.thumbnailBase64
                                )
                            }
                        ),
                        Message(sender: .hermes, content: "I saw the attachment.", status: .delivered),
                    ]
                )

                return AsyncStream { continuation in
                    Task { @MainActor in
                        continuation.yield(.messageSent(jobID: UUID()))
                        continuation.yield(.finished(Message(sender: .hermes, content: "I saw the attachment.", status: .delivered), nil, nil))
                        continuation.finish()
                    }
                }
            }

            func loadConversation() async -> Conversation {
                currentConversation ?? Conversation(title: "Hermes")
            }

            func clearConversation() async throws -> Conversation {
                Conversation(title: "Hermes")
            }

        }

        let image = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16)).image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
        }
        let attachment = try #require(PendingAttachment.image(image))

        let suiteName = "chat-store-attachment-roundtrip-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let persistence = UserDefaultsAppPersistenceStore(defaults: defaults)
        let hermesClient = AttachmentRoundTripClient()
        let chatStore = ChatStore(hermesClient: hermesClient, persistence: persistence)

        await chatStore.sendMessage("", attachments: [attachment])

        let userMessage = try #require(chatStore.conversation?.messages.first(where: { $0.sender == .user }))
        let mergedAttachment = try #require(userMessage.attachments.first)
        #expect(mergedAttachment.thumbnailBase64 != nil)
        #expect(mergedAttachment.localStoragePath != nil)
    }

    /// #185: echoes the user's attachments back the way the relay does —
    /// display fields only (the client-only paths never round-trip), with
    /// ids either re-minted (the generic echo) or preserved and reordered
    /// (the id-priority probe).
    @MainActor
    private final class AttachmentEchoClient: HermesClientProtocol {
        var connectionStatus: ConnectionStatus = .connected
        var currentConversation: Conversation?
        var preservesIDs = false
        var reversesEchoOrder = false

        func connect() async {}
        func disconnect() async {}

        func send(message: String, attachments: [PendingAttachment] = [], clientMessageID: UUID) async -> Message {
            Message(sender: .hermes, content: "unused", status: .delivered)
        }

        func sendStreaming(message: String, attachments: [PendingAttachment] = [], clientMessageID: UUID) -> AsyncStream<StreamingUpdate> {
            var echoed = attachments.map {
                MessageAttachment(
                    id: preservesIDs ? $0.id : UUID(),
                    kind: $0.kind.rawValue,
                    fileName: $0.fileName,
                    mimeType: $0.mimeType,
                    thumbnailBase64: $0.thumbnailBase64
                )
            }
            if reversesEchoOrder {
                echoed.reverse()
            }
            currentConversation = Conversation(
                title: "Hermes",
                messages: [
                    Message(
                        id: UUID(),
                        clientMessageID: clientMessageID,
                        sender: .user,
                        content: "",
                        status: .sent,
                        attachments: echoed
                    ),
                    Message(sender: .hermes, content: "I saw the attachments.", status: .delivered),
                ]
            )

            return AsyncStream { continuation in
                Task { @MainActor in
                    continuation.yield(.messageSent(jobID: UUID()))
                    continuation.yield(.finished(Message(sender: .hermes, content: "I saw the attachments.", status: .delivered), nil, nil))
                    continuation.finish()
                }
            }
        }

        func loadConversation() async -> Conversation {
            currentConversation ?? Conversation(title: "Hermes")
        }

        func clearConversation() async throws -> Conversation {
            Conversation(title: "Hermes")
        }
    }

    /// Two picker rounds staging the same file name into distinct local
    /// copies — the only real #185 trigger (voice memos carry second-
    /// resolution timestamps and photos carry UUID names).
    @MainActor
    private func makeSameNamedPickerAttachments() throws -> (PendingAttachment, PendingAttachment) {
        let fileManager = FileManager.default
        let dirA = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let dirB = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: dirA, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: dirB, withIntermediateDirectories: true)
        let urlA = dirA.appendingPathComponent("report.txt")
        let urlB = dirB.appendingPathComponent("report.txt")
        try Data("alpha bytes".utf8).write(to: urlA)
        try Data("beta bytes".utf8).write(to: urlB)
        let first = try #require(PendingAttachment.file(at: urlA))
        let second = try #require(PendingAttachment.file(at: urlB))
        #expect(first.localStoragePath != second.localStoragePath)
        return (first, second)
    }

    @Test @MainActor
    func mergeResolvesDuplicateFileNamesToDistinctLocalAttachments() async throws {
        // #185: `first(where: fileName ==)` never dequeued its match, so N
        // same-named remote attachments all aliased localAttachments[0] —
        // the second bubble opened the first bubble's bytes, ShareLink
        // handed out the wrong file, and a #21 Tier 2 re-fetch targeted the
        // wrong remote path. Each local entry must be claimable once.
        let (first, second) = try makeSameNamedPickerAttachments()

        let suiteName = "chat-store-duplicate-names-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let persistence = UserDefaultsAppPersistenceStore(defaults: defaults)
        let hermesClient = AttachmentEchoClient()
        let chatStore = ChatStore(hermesClient: hermesClient, persistence: persistence)

        await chatStore.sendMessage("", attachments: [first, second])

        let userMessage = try #require(chatStore.conversation?.messages.first(where: { $0.sender == .user }))
        #expect(userMessage.attachments.count == 2)
        let mergedPaths = userMessage.attachments.map(\.localStoragePath)
        #expect(mergedPaths == [first.localStoragePath, second.localStoragePath],
                "same-named attachments must keep their own local bytes, not alias the first match")
    }

    @Test @MainActor
    func mergeMatchesEchoedAttachmentIDsBeforeFileNames() async throws {
        // #185: when the echo preserves attachment ids (`MessageAttachment.id`
        // survives the round trip), identity must outrank the (fileName,
        // mimeType) fallback — the same precedence the sibling message-level
        // merge already models (id, then clientMessageID, then jobID).
        let (first, second) = try makeSameNamedPickerAttachments()

        let suiteName = "chat-store-id-priority-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let persistence = UserDefaultsAppPersistenceStore(defaults: defaults)
        let hermesClient = AttachmentEchoClient()
        hermesClient.preservesIDs = true
        hermesClient.reversesEchoOrder = true
        let chatStore = ChatStore(hermesClient: hermesClient, persistence: persistence)

        await chatStore.sendMessage("", attachments: [first, second])

        let userMessage = try #require(chatStore.conversation?.messages.first(where: { $0.sender == .user }))
        #expect(userMessage.attachments.count == 2)
        for merged in userMessage.attachments {
            let expected = merged.id == first.id ? first : second
            #expect(merged.localStoragePath == expected.localStoragePath,
                    "an id-preserving echo must pair each attachment with ITS local entry, whatever the order")
        }
    }

    @Test @MainActor
    func talkStoreReflectsBlockedReadinessState() async throws {
        let voiceService = RecordingVoiceSessionService()
        let talkStore = TalkStore(voiceService: voiceService)

        await talkStore.refreshReadiness()

        #expect(talkStore.connectionState == .blocked)
        #expect(talkStore.voiceState == .disconnected)
        #expect(talkStore.canStartSession == false)
        #expect(talkStore.blockedReason == "OpenAI Realtime is not configured on this Hermes host.")
    }

    @Test @MainActor
    func talkStoreUpdatesFromVoiceEventStream() async throws {
        let voiceService = RecordingVoiceSessionService()
        let talkStore = TalkStore(voiceService: voiceService)

        try? await Task.sleep(for: .milliseconds(25))
        voiceService.emitAssistantTurn("Event-driven reply")
        try? await Task.sleep(for: .milliseconds(25))

        #expect(talkStore.transcriptItems.count == 1)
        #expect(talkStore.transcriptItems.first?.text == "Event-driven reply")
    }

    // #383: `liveVoiceSessionServiceRefreshesExpiredAccessTokenDuringReadiness`
    // was DELETED here, not repointed, and the distinction matters.
    //
    // It pinned the relay's 401 -> refresh -> retry ladder (#15/#94) on the
    // voice path: one refresh call, two requests, then a ready state. Voice no
    // longer has relay access tokens to refresh — it bootstraps over the
    // talaria plugin with the device token the platform link already holds,
    // and that link re-pairs itself once on 401 and then gives up.
    //
    // Rewriting it to pass against the new transport would have produced a
    // test that exercises nothing: the ladder it was written to catch does not
    // exist to break. Voice stopped being a second auth plane, and this test
    // was the second auth plane's regression guard — it retires with it.

    @Test @MainActor
    func liveVoiceSessionServiceInterruptsAssistantPlaybackOnSpeechStart() async throws {
        let sentEvents = MutableBox([[String: Any]]())
        let voiceService = LiveVoiceSessionService(
            realtimeEventTransportOverride: { data in
                guard let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    return false
                }
                sentEvents.value.append(payload)
                return true
            }
        )

        voiceService.connectionState = .connected
        voiceService.handleDataChannelEvent(
            [
                "type": "response.created",
                "response": ["id": "resp_123"],
            ]
        )
        voiceService.handleDataChannelEvent(
            [
                "type": "conversation.item.created",
                "item": [
                    "id": "item_123",
                    "role": "assistant",
                    "type": "message",
                ],
            ]
        )
        voiceService.handleDataChannelEvent(
            [
                "type": "response.output_text.delta",
                "delta": "Testing interruption handling.",
            ]
        )
        voiceService.handleDataChannelEvent(["type": "output_audio_buffer.started"])
        try? await Task.sleep(for: .milliseconds(25))

        voiceService.handleDataChannelEvent(["type": "input_audio_buffer.speech_started"])

        #expect(sentEvents.value.count == 3)
        #expect(sentEvents.value[0]["type"] as? String == "response.cancel")
        #expect(sentEvents.value[0]["response_id"] as? String == "resp_123")
        #expect(sentEvents.value[1]["type"] as? String == "output_audio_buffer.clear")
        #expect(sentEvents.value[2]["type"] as? String == "conversation.item.truncate")
        #expect(sentEvents.value[2]["item_id"] as? String == "item_123")
        #expect(sentEvents.value[2]["content_index"] as? Int == 0)
        let audioEndMs = try #require(sentEvents.value[2]["audio_end_ms"] as? Int)
        #expect(audioEndMs >= 0)
        #expect(voiceService.voiceState == .listening)
        #expect(voiceService.statusMessage == "Listening")
        #expect(voiceService.transcriptItems.last?.isPartial == false)
    }

    @Test @MainActor
    func liveVoiceSessionServiceDoesNotInterruptWhenAssistantIsNotSpeaking() async throws {
        let sentEvents = MutableBox([[String: Any]]())
        let voiceService = LiveVoiceSessionService(
            realtimeEventTransportOverride: { data in
                guard let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    return false
                }
                sentEvents.value.append(payload)
                return true
            }
        )

        voiceService.connectionState = .connected
        voiceService.handleDataChannelEvent(
            [
                "type": "response.created",
                "response": ["id": "resp_456"],
            ]
        )
        voiceService.handleDataChannelEvent(
            [
                "type": "conversation.item.created",
                "item": [
                    "id": "item_456",
                    "role": "assistant",
                    "type": "message",
                ],
            ]
        )

        voiceService.handleDataChannelEvent(["type": "input_audio_buffer.speech_started"])

        #expect(sentEvents.value.isEmpty)
        #expect(voiceService.voiceState == .listening)
    }

    // MARK: - #138-O the onset gate (card V5)

    /// **The fix #138 elected on 2026-09-02.** Every unambiguous phantom in five
    /// archives trips 0.36–0.60 s after `audio.started` on the speakerphone
    /// route, the speaker is dead at a cancel (Owen's ear, 09-02), and the
    /// residual is therefore ONSET-only. The gate disables the local uplink
    /// track for a named 800 ms from each `audio.started` and re-enables it.
    ///
    /// **Why the pre-existing barge-in pins above are untouched and still
    /// green, rather than rewritten.** The gate suppresses only what it
    /// actually MUTED: with no uplink to disable there is nothing muted, so a
    /// `speech_started` describes audio the server genuinely received over a
    /// live uplink and cancelling is correct. Those pins drive a service that
    /// never stood up a peer connection, so the gate never arms in them — and
    /// that is the production invariant, not a test accommodation. A gate that
    /// suppressed barge-in on a window it had not enforced would be claiming a
    /// mute that never happened.
    private final class FakeUplink: OnsetGateUplink {
        var isEnabled = true
    }

    @MainActor
    private func makeGatedVoiceService() -> (LiveVoiceSessionService, FakeUplink, MutableBox<[[String: Any]]>) {
        let sent = MutableBox([[String: Any]]())
        let service = LiveVoiceSessionService(
            realtimeEventTransportOverride: { data in
                guard let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    return false
                }
                sent.value.append(payload)
                return true
            }
        )
        let uplink = FakeUplink()
        service.onsetGateUplinkOverride = uplink
        service.connectionState = .connected
        return (service, uplink, sent)
    }

    /// The server's order for one spoken reply, up to and including the event
    /// that arms the gate.
    @MainActor
    private func beginAssistantPlayback(
        _ service: LiveVoiceSessionService,
        itemID: String = "item_onset"
    ) {
        service.handleDataChannelEvent(["type": "response.created", "response": ["id": "resp_onset"]])
        service.handleDataChannelEvent([
            "type": "conversation.item.created",
            "item": ["id": itemID, "role": "assistant", "type": "message"],
        ])
        service.handleDataChannelEvent(["type": "response.output_audio_transcript.delta", "delta": "Hello there."])
        service.handleDataChannelEvent(["type": "output_audio_buffer.started"])
    }

    /// 138-O-A, behaviour half: the mute lands on the playback event itself
    /// (not a hop later — the phantom trips at +0.36 s, so a deferred mute
    /// would miss the earliest ones) and the window closes on its own.
    @Test @MainActor
    func theOnsetGateMutesTheUplinkAtPlaybackStartAndRestoresItAfterTheWindow() async throws {
        let (service, uplink, _) = makeGatedVoiceService()

        beginAssistantPlayback(service)

        #expect(uplink.isEnabled == false, "the uplink must be muted by the playback event itself")
        #expect(service.onsetGateIsHolding)

        let restored = await pollUntil { uplink.isEnabled }
        #expect(restored, "the window must close on its own — a gate that never releases is #130's half-duplex")
        #expect(service.onsetGateIsHolding == false)
    }

    /// **138-O-B — re-armed only by a NEW playback.** The 09-02 08:19 archive
    /// showed the loop: phantom cancels reply, reply 2 starts, phantom cancels
    /// reply 2. A gate that re-armed on the CANCEL would hold the uplink down
    /// across the user's own next turn and read as a dead microphone.
    @Test @MainActor
    func theOnsetGateIsReArmedOnlyByANewPlaybackNeverByACancel() async throws {
        let (service, uplink, _) = makeGatedVoiceService()
        let clock = ContinuousClock()

        beginAssistantPlayback(service)
        let armedAt = clock.now
        #expect(uplink.isEnabled == false)

        // +0.5 s — inside the window: the server cancels the reply and the
        // transcript finalizes. Neither may extend the window or start a new one.
        try await Task.sleep(until: armedAt + .milliseconds(500), clock: clock)
        service.handleDataChannelEvent(["type": "output_audio_buffer.cleared"])
        service.handleDataChannelEvent([
            "type": "response.output_audio_transcript.done",
            "transcript": "Hello there.",
        ])

        // The ORIGINAL schedule still governs: released by +0.8 s. The budget
        // is anchored to the ARMING instant, not to "however long the previous
        // step took" — a re-arm at +0.5 s would move the release to +1.3 s and
        // has to be caught however slow the host is.
        let budget = max((armedAt + .milliseconds(1_100)) - clock.now, .milliseconds(1))
        let restored = await pollUntil(timeout: budget) { uplink.isEnabled }
        #expect(restored, "a cancel inside the window must not extend it")
        #expect(service.onsetGateIsHolding == false)

        // And with the gate idle, none of the three arms it either.
        service.handleDataChannelEvent(["type": "output_audio_buffer.cleared"])
        service.handleDataChannelEvent([
            "type": "response.output_audio_transcript.done",
            "transcript": "Hello there.",
        ])
        await service.handleAudioRouteChange(.categoryChange)
        #expect(uplink.isEnabled, "a cancel, a finalization or a route change must never arm the gate")
        #expect(service.onsetGateIsHolding == false)

        // Only the next playback re-arms it.
        service.handleDataChannelEvent(["type": "output_audio_buffer.started"])
        #expect(uplink.isEnabled == false, "the next playback must re-arm the gate")
        #expect(service.onsetGateIsHolding)
    }

    /// **138-O-C, the inside arm.** The track is muted, so the server should
    /// never raise this at all — but the app side is pinned too, because a
    /// `speech_started` the gate cannot have caused must not be allowed to cut
    /// the reply, and the state must stay `.speaking` (the assistant is).
    @Test @MainActor
    func aSpeechStartedInsideTheOnsetWindowRaisesNoBargeIn() async throws {
        let (service, uplink, sent) = makeGatedVoiceService()

        beginAssistantPlayback(service, itemID: "item_inside")
        try await Task.sleep(for: .milliseconds(300))

        #expect(
            uplink.isEnabled == false,
            "the window must still be open at +0.3s — otherwise this check did not run"
        )
        service.handleDataChannelEvent(["type": "input_audio_buffer.speech_started"])

        #expect(sent.value.isEmpty, "a speech_started inside the muted window must not cancel the assistant")
        #expect(service.voiceState == .speaking, "the assistant is still speaking — the state must not flip")
    }

    /// **138-O-C, the after arm.** Real barge-in is the thing this fix must not
    /// cost. At +2 s the window is long closed and the full cancel/clear/
    /// truncate sequence must be identical to the pre-gate behaviour.
    @Test @MainActor
    func aSpeechStartedAfterTheOnsetWindowStillCancelsTheAssistant() async throws {
        let (service, uplink, sent) = makeGatedVoiceService()
        let clock = ContinuousClock()

        beginAssistantPlayback(service, itemID: "item_late")
        let armedAt = clock.now
        try await Task.sleep(until: armedAt + .seconds(2), clock: clock)

        #expect(uplink.isEnabled, "the window must be long closed at +2s")
        service.handleDataChannelEvent(["type": "input_audio_buffer.speech_started"])

        #expect(sent.value.count == 3)
        #expect(sent.value[0]["type"] as? String == "response.cancel")
        #expect(sent.value[1]["type"] as? String == "output_audio_buffer.clear")
        #expect(sent.value[2]["type"] as? String == "conversation.item.truncate")
        #expect(sent.value[2]["item_id"] as? String == "item_late")
        #expect(service.voiceState == .listening)
    }

    private static var onsetGateRepoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // TalariaTests/
            .deletingLastPathComponent()   // repo root
    }

    /// **138-O-D — no capture-state lie.** The mic is not off and the audio
    /// session is untouched; one TRACK is disabled. #302/#415's `capture chain
    /// HOT/COLD` markers mean "microphone buffers are/are not leaving the
    /// device", and an operator reading a device archive must not find the gate
    /// impersonating them — a COLD line at every playback onset would read as
    /// the capture chain collapsing eight times a session.
    ///
    /// Structural because the failure it guards is a line ADDED later by
    /// someone who thinks the gate should announce itself in the same vocabulary.
    @Test @MainActor
    func theOnsetGateNeverTouchesTheCaptureChainOrItsMarkers() async throws {
        let source = try #require(
            try? String(
                contentsOf: Self.onsetGateRepoRoot
                    .appendingPathComponent("Talaria/Services/Live/LiveVoiceSessionService.swift"),
                encoding: .utf8
            ),
            "cannot read LiveVoiceSessionService.swift — this check did not run"
        )
        let marker = "// MARK: - #138-O the onset gate (card V5)"
        let sectionStart = try #require(
            source.range(of: marker),
            "the onset gate's section marker is gone — this check did not run"
        )
        let rest = String(source[sectionStart.upperBound...])
        let section = rest.range(of: "// MARK: -").map { String(rest[..<$0.lowerBound]) } ?? rest
        #expect(section.contains("armOnsetGate"), "the gate is not in its own section — this check did not run")

        for forbidden in [
            "capture chain",
            "AudioSessionOffMain",
            "configureAudioSession",
            "forceSpeakerIfNeeded",
            "peerConnection",
            "#if DEBUG",
            "verboseLogging",
        ] {
            #expect(!section.contains(forbidden), "the onset gate must not reach \(forbidden)")
        }
        // The two capture-chain emissions are #302-A's and stay exactly two:
        // the gate adds none, in its section or anywhere else.
        #expect(source.components(separatedBy: "capture chain HOT").count - 1 == 1)
        #expect(source.components(separatedBy: "capture chain COLD").count - 1 == 1)

        // The behavioural half: arming and releasing move no app state.
        let (service, uplink, _) = makeGatedVoiceService()
        beginAssistantPlayback(service)
        #expect(uplink.isEnabled == false)
        #expect(service.connectionState == .connected)
        #expect(service.voiceState == .speaking)
        #expect(service.isMuted == false, "the gate mutes a TRACK, never the app's mic state")
        #expect(service.audioRouteSummary == nil, "the gate must not disturb the published route")

        let restored = await pollUntil { uplink.isEnabled }
        #expect(restored)
        #expect(service.connectionState == .connected)
        #expect(service.isMuted == false)
    }

    /// The window is one named constant, and it is the fix's only tunable.
    @Test func theOnsetGateWindowIsOneNamedConstant() {
        #expect(LiveVoiceSessionService.onsetGateWindowMilliseconds == 800)
    }

    @Test @MainActor
    func liveVoiceSessionServiceRecoversFromInterruptionsWithoutEndingSession() async throws {
        let voiceService = LiveVoiceSessionService(
        )

        voiceService.connectionState = .connected
        voiceService.voiceState = .speaking

        voiceService.handleAudioInterruptionBegan()

        #expect(voiceService.voiceState == .interrupted)
        #expect(voiceService.statusMessage == "Audio interrupted.")

        await voiceService.handleAudioInterruptionEnded(shouldResume: true)

        #expect(voiceService.connectionState == .connected)
        #expect(voiceService.voiceState == .listening)
        #expect(voiceService.statusMessage == "Listening")
    }

    @Test @MainActor
    func liveVoiceSessionServiceRecoversFromRouteChangesDuringActiveSession() async throws {
        let voiceService = LiveVoiceSessionService(
        )

        voiceService.connectionState = .connected
        voiceService.voiceState = .interrupted

        await voiceService.handleAudioRouteChange(.oldDeviceUnavailable)

        #expect(voiceService.connectionState == .connected)
        #expect(voiceService.voiceState == .listening)
        #expect(voiceService.statusMessage == "Audio route changed.")
    }

    @Test @MainActor
    func liveVoiceSessionServiceKeepsUserTranscriptOrderedWhenTranscriptionFinishesLate() async throws {
        let voiceService = LiveVoiceSessionService(
        )

        voiceService.connectionState = .connected
        voiceService.handleDataChannelEvent([
            "type": "input_audio_buffer.committed",
            "item_id": "user_item_1",
        ])
        voiceService.handleDataChannelEvent([
            "type": "response.created",
            "response": ["id": "resp_late_user"],
        ])
        voiceService.handleDataChannelEvent([
            "type": "conversation.item.created",
            "item": [
                "id": "assistant_item_1",
                "role": "assistant",
                "type": "message",
            ],
        ])
        voiceService.handleDataChannelEvent([
            "type": "response.output_text.delta",
            "delta": "Let me check that.",
        ])

        voiceService.handleDataChannelEvent([
            "type": "conversation.item.input_audio_transcription.completed",
            "item_id": "user_item_1",
            "transcript": "What should I focus on today?",
        ])

        #expect(voiceService.transcriptItems.count == 2)
        #expect(voiceService.transcriptItems[0].speaker == .user)
        #expect(voiceService.transcriptItems[0].text == "What should I focus on today?")
        #expect(voiceService.transcriptItems[0].isPartial == false)
        #expect(voiceService.transcriptItems[1].speaker == .hermes)
        #expect(voiceService.transcriptItems[1].text == "Let me check that.")
    }

    @Test @MainActor
    func liveVoiceSessionServiceIgnoresLateRealtimeErrorsAfterIntentionalEnd() async throws {
        let voiceService = LiveVoiceSessionService(
        )

        voiceService.connectionState = .connected
        voiceService.voiceState = .speaking

        await voiceService.endSession()
        voiceService.handleDataChannelEvent([
            "type": "error",
            "error": ["message": "Connection lost."],
        ])

        #expect(voiceService.connectionState == .idle)
        #expect(voiceService.voiceState == .idle)
        #expect(voiceService.statusMessage == nil)
    }

    @Test @MainActor
    func liveVoiceSessionServiceSwallowsNoOpCancelRaceWithoutFailingSession() async throws {
        // #119a: a barge-in cancel racing an already-completed response must
        // not banner the backend string or flag the connection failed — that
        // false `.failed` was also what wedged the header on CONNECTING
        // mid-conversation (#119b).
        let voiceService = LiveVoiceSessionService(
        )

        voiceService.connectionState = .connected
        voiceService.voiceState = .listening
        voiceService.statusMessage = "Listening"

        voiceService.handleDataChannelEvent([
            "type": "error",
            "error": ["message": "Cancellation failed: no active response found"],
        ])

        #expect(voiceService.connectionState == .connected)
        #expect(voiceService.voiceState == .listening)
        #expect(voiceService.statusMessage == "Listening")
        #expect(voiceService.blockedReason == nil)

        // Every other failure still surfaces honestly.
        voiceService.handleDataChannelEvent([
            "type": "error",
            "error": ["message": "Session expired."],
        ])

        #expect(voiceService.connectionState == .failed)
        #expect(voiceService.voiceState == .disconnected)
        #expect(voiceService.blockedReason == "Session expired.")
    }

    // #309 (2026-08-25, Owen's ruling 1 — LiveHermesClient deleted as
    // production-dead): `liveHermesClientRefreshesExpiredAccessTokenDuringConversationLoad`
    // was DELETED here rather than repointed. It pinned the relay's
    // 401 → refresh-once → retry ladder (#15/#94) on
    // `LiveHermesClient.performAuthorizedRequest`, and the same ladder had a
    // live copy in `LiveHermesHostService` that this file pinned instead.
    //
    // **2026-08-25, #309 Lane C: THAT PIN IS NOW TOMBSTONED TOO —
    // `liveHermesHostServiceRefreshesExpiredAccessTokenDuringFetch` is gone
    // with the service it measured.** Lane A had already removed the ladder's
    // last production rung (`accessTokenRefresher` defaulted to `{ nil }`, so
    // the test kept the argument alive by itself); this lane deleted
    // `LiveHermesHostService` outright with relay row 7's adapt. There is no
    // 401 → refresh → retry shape left anywhere in the app: the relay session
    // tokens that ladder renewed are gone, and the gateway plane's credential
    // is a static API key with nothing to refresh.
    //
    // What replaces it is not a port — it is the pin for the NEW mechanism.
    // The four tests below measure `GatewayHermesHostService` on the three
    // outcomes the store renders differently, plus the durability property the
    // relay's host record used to supply for free.

    /// **309-C2** — a reachable gateway is a reachable HOST, and every field
    /// of the record it produces is either measured or drawn from the profile.
    ///
    /// RED against `main`: the type does not exist there.
    @Test @MainActor
    func gatewayHostProbeReportsAReachableHostFromAHealthAnswer() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)

        let requestCount = MutableBox(0)
        let seenAuthorization = MutableBox<String?>(nil)
        StubURLProtocol.requestHandler = { request in
            requestCount.value += 1
            let url = try #require(request.url)
            // The trailing slash on the configured base must not produce
            // `//health` — a shape that 404s on the api_server.
            #expect(url.absoluteString == "http://ojamd.tailnet.test:8642/health")
            seenAuthorization.value = request.value(forHTTPHeaderField: "Authorization")
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let data = #"{"status":"ok","version":"0.20.5","model":"kimi-k2"}"#.data(using: .utf8)!
            return (response, data)
        }
        defer { StubURLProtocol.requestHandler = nil }

        let profileID = UUID()
        let service = GatewayHermesHostService(
            baseURLProvider: { "http://ojamd.tailnet.test:8642/" },
            apiKeyProvider: { "gateway-key" },
            displayNameProvider: { "OJAMD" },
            identityProvider: { profileID },
            session: session
        )

        let host = try #require(await service.fetchCurrentHost())

        #expect(requestCount.value == 1)
        #expect(seenAuthorization.value == "Bearer gateway-key")
        #expect(host.isOnline)
        #expect(host.id == profileID)
        // The name is the PROFILE's — the gateway has none to report, and the
        // relay's `displayName` was the connector's enrollment label.
        #expect(host.resolvedDisplayName == "OJAMD")
        #expect(host.hostname == "ojamd.tailnet.test")
        #expect(host.hermesVersion == "0.20.5")
        #expect(host.hermesModel == "kimi-k2")
        // Real data only (#45): the gateway reports neither, and inventing a
        // connector version for a retired connector is exactly the failure
        // this rule exists to stop.
        #expect(host.platform == nil)
        #expect(host.connectorVersion == nil)
    }

    /// **309-C2** — a host that answers but refuses the key is a FAILURE, not
    /// an offline host. `HermesHostStore` renders the two differently
    /// (`.unreachable` with the message vs `.notConnected`), and a rejected
    /// key that read as "offline" would send the user to check their network.
    @Test @MainActor
    func gatewayHostProbeSurfacesARejectedKeyAsAnHonestFailure() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)

        StubURLProtocol.requestHandler = { request in
            let url = try #require(request.url)
            let response = HTTPURLResponse(url: url, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        defer { StubURLProtocol.requestHandler = nil }

        let service = GatewayHermesHostService(
            baseURLProvider: { "http://ojamd.tailnet.test:8642" },
            apiKeyProvider: { "wrong-key" },
            session: session
        )

        // …and the store turns that into the unreachable state, carrying the
        // service's own sentence rather than a manufactured one.
        let store = HermesHostStore(hostService: service)
        await store.refresh()
        #expect(store.currentHost == nil)
        #expect(store.connectionState == .unreachable)
        #expect(store.lastErrorMessage == "The Hermes host rejected this device's API key.")
    }

    /// **309-C2** — an unconfigured profile asks NOTHING and reports no host.
    ///
    /// Not an error: `.notConnected` is the honest state for "you have not set
    /// a host up yet", and throwing here would paint a fresh install as broken
    /// — the misattribution #412 filed against this surface's Inbox twin.
    @Test @MainActor
    func gatewayHostProbeWithNoGatewayConfiguredAsksNothingAndReportsNoHost() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)

        let requestCount = MutableBox(0)
        StubURLProtocol.requestHandler = { request in
            requestCount.value += 1
            let url = try #require(request.url)
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data("{}".utf8))
        }
        defer { StubURLProtocol.requestHandler = nil }

        let service = GatewayHermesHostService(
            baseURLProvider: { "   " },
            apiKeyProvider: { "gateway-key" },
            session: session
        )

        let host = try await service.fetchCurrentHost()
        #expect(host == nil)
        #expect(requestCount.value == 0)

        let store = HermesHostStore(hostService: service)
        await store.refresh()
        #expect(store.connectionState == .notConnected)
        #expect(store.lastErrorMessage == nil)
    }

    /// **309-C2** — the host record's identity is STABLE across refreshes.
    ///
    /// The relay supplied a durable host UUID; the gateway supplies none, so
    /// the service derives one. A fresh `UUID()` per probe would make every
    /// poll a host CHANGE — `HermesHostStatus` is `Hashable` and the widget
    /// hook fires on the record changing — which is the App Group I/O storm
    /// `relaylessRefreshAnnouncesAHostChangeOnlyOnATransition` was written
    /// after. Derived from the base URL with FNV-1a rather than `Hasher`,
    /// because Swift's hashing is seeded per process: a `Hasher` id would be
    /// stable within every test run and different on the user's next launch.
    @Test @MainActor
    func gatewayHostProbeIdentityIsStableForAHostAndDistinctBetweenHosts() {
        let first = GatewayHermesHostService.stableIdentity(for: "http://ojamd.tailnet.test:8642")
        let again = GatewayHermesHostService.stableIdentity(for: "http://ojamd.tailnet.test:8642")
        let other = GatewayHermesHostService.stableIdentity(for: "http://mac-mini.tailnet.test:8642")

        #expect(first == again)
        #expect(first != other)
    }

    // #238: the retired notificationsEnabled key survives in persisted JSON on
    // every existing install — decoding must skip it, not throw. Green BEFORE
    // the removal (decodeIfPresent path) and AFTER (unknown-key skip): the
    // same test pins both worlds.
    @Test func settingsJSONCarryingRetiredNotificationsKeyStillDecodes() throws {
        let legacy = """
        {"userName":"Owen","notificationsEnabled":false,"hapticFeedbackEnabled":false}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(UserSettings.self, from: legacy)
        #expect(decoded.userName == "Owen")
        #expect(decoded.hapticFeedbackEnabled == false)
    }

    /// **400-A — the persistence roundtrip keeps the user's mid-turn send
    /// choice.** Found by the 2026-08-23 Opus-week audit: the hand-written
    /// `encode(to:)` omitted the key, so `.steer` worked all session and
    /// silently reverted to `.queue` on relaunch. The fix deleted the
    /// hand-written encode outright — a synthesized encode is derived from
    /// CodingKeys and cannot omit a case (400-B) — so this test is the pin
    /// against any hand-written encode ever returning.
    @Test func settingsRoundtripKeepsTheMidTurnSendChoice() throws {
        var settings = UserSettings()
        settings.midTurnSendAction = .steer
        let encoded = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(UserSettings.self, from: encoded)
        #expect(decoded.midTurnSendAction == .steer,
                "the encode path dropped midTurnSendAction — the user's choice reverts on relaunch (#400)")
    }

    /// **396-P-A — the voice-sensitivity pick survives persistence**, and a
    /// pre-#396 blob (no key) lands on `.normal`.
    @Test func settingsRoundtripKeepsTheVoiceSensitivityChoice() throws {
        var settings = UserSettings()
        settings.voiceSensitivity = .noisy
        let decoded = try JSONDecoder().decode(UserSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded.voiceSensitivity == .noisy,
                "the pick reverted across a persistence roundtrip (#396)")

        let legacy = #"{"userName":"Owen"}"#.data(using: .utf8)!
        #expect(try JSONDecoder().decode(UserSettings.self, from: legacy).voiceSensitivity == .normal)
    }

    @Test @MainActor
    func settingsStoreSanitizesDisallowedReleaseEnvironmentToProduction() async throws {
        let suiteName = "settings-store-release-policy-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let persistence = UserDefaultsAppPersistenceStore(defaults: defaults)
        persistence.saveUserSettings(
            UserSettings(
                userName: "Alex",
                avatarInitials: "A",
                hapticFeedbackEnabled: true,
                environment: .staging,
                autoConnectOnLaunch: true
            )
        )

        let settingsStore = SettingsStore(
            persistence: persistence,
            environmentPolicy: AppEnvironmentPolicy(allowsEnvironmentOverrides: false)
        )

        #expect(settingsStore.settings.environment == .production)
        #expect(settingsStore.availableEnvironments == [.production])
    }

    // **TOMBSTONED 2026-08-25 (#309 Lane B).**
    // `settingsStorePersistsCustomRelayConfiguration` wrote a relay URL into
    // `UserSettings` and read it back. `RelayConfiguration` is deleted — its
    // last live reader was a Developer-screen row printing a relay origin for
    // hosts that have none.
    //
    // The PERSISTENCE property it was really about — the settings store
    // round-trips a mutation through `UserDefaults` — keeps its own pins
    // above (`settingsStorePersistsEnvironmentChanges` and siblings), and the
    // decode tolerance the deleted key now needs is
    // `aLegacyUserSettingsBlobWithARelayConfigurationStillDecodes`
    // (ServerSettingsTests).

    @Test
    func relayDecoderParsesFractionalSecondsWithoutTimezone() throws {
        let data = #"{"timestamp":"2026-03-31T18:58:36.197800"}"#.data(using: .utf8)!
        let payload = try RelayCoders.makeDecoder().decode(TimestampPayload.self, from: data)
        let expected = Date(timeIntervalSince1970: 1774983516.1978)

        #expect(abs(payload.timestamp.timeIntervalSince(expected)) < 0.000_001)
    }

    @Test
    func relayDecoderParsesTimezoneQualifiedDates() throws {
        let data = #"{"timestamp":"2026-03-31T18:58:36Z"}"#.data(using: .utf8)!
        let payload = try RelayCoders.makeDecoder().decode(TimestampPayload.self, from: data)

        #expect(payload.timestamp == Date(timeIntervalSince1970: 1774983516))
    }

    /// #352 (bar 352-F): the retired upload pipeline's persisted artifacts —
    /// the outbox blob (a pending GPS fix + up to 500 health samples) and the
    /// HealthKit query anchors — are removed on store init. Unconditional and
    /// idempotent; no surviving path recreates either key family.
    @Test @MainActor
    func initPurgesRetiredSensorOutboxAndAnchorKeys() {
        let suiteName = "purge-352-\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: suiteName)!
        defer { suite.removePersistentDomain(forName: suiteName) }
        suite.set(Data("junk".utf8), forKey: "hermes.sensorOutboxState")
        suite.set(Data("anchor".utf8), forKey: "hermes.healthAnchor.stepCount")

        _ = UserDefaultsAppPersistenceStore(defaults: suite)

        #expect(suite.data(forKey: "hermes.sensorOutboxState") == nil)
        #expect(suite.data(forKey: "hermes.healthAnchor.stepCount") == nil)
    }

    /// #352 (bar 352-F): the widget's stored health fallback fields are
    /// nilled — the widget queries HealthKit live each pass, and a
    /// months-stale snapshot number shown as current would lie. Pure
    /// transform pinned here; the App-Group wrapper is a thin caller.
    @Test
    func clearingRetiredHealthMetricsNilsAllFourFieldsAndNothingElse() {
        var data = HermesWidgetData.empty
        data.steps = 5000
        data.activeCalories = 300
        data.sleepHours = 7.5
        data.heartRate = 62
        data.hostName = "keep-me"

        let cleared = SharedWidgetDataStore.clearingRetiredHealthMetrics(data)

        #expect(cleared.steps == nil)
        #expect(cleared.activeCalories == nil)
        #expect(cleared.sleepHours == nil)
        #expect(cleared.heartRate == nil)
        #expect(cleared.hostName == "keep-me")
    }

    // **TOMBSTONED 2026-08-25 (#309 Lane B) — two tests, one deletion.**
    //
    // `phonePairingCodeNormalizesAndFormatsManualEntry` pinned the 8-character
    // relay alphabet (`ABCD-EFGH`, no I/O/0/1) that `PhonePairingCode` parsed.
    // `pairingStorePersistsRelayConfigurationAndTokens` pinned that a redeem
    // wrote the pairing record and both relay JWTs. Neither type exists: the
    // code was minted by a CLI verb Lane D deleted and redeemed at a relay
    // retired on both hosts (#412 is the entry where the flow's two dead ends
    // were finally written down).
    //
    // **Ported, not lost.** The code-shape pin becomes
    // `ConnectHostPayloadTests` — which is a stronger contract than this one
    // was, because it pins BYTES shared with another repository rather than an
    // alphabet this repo invented. The credential-write pin becomes
    // `ConnectHostTests.aGreenProbeCommitsExactlyOnce`, which counts writes
    // instead of reading the record afterwards.


    @Test @MainActor
    func hostStoreMarksReachabilityErrorsWithoutPretendingHostIsOffline() async throws {
        let service = RecordingHermesHostService()
        service.fetchError = APIClientError.requestFailed("Relay unreachable.")

        let hostStore = HermesHostStore(hostService: service)

        await hostStore.refresh()

        #expect(hostStore.currentHost == nil)
        #expect(hostStore.connectionState == .unreachable)
        #expect(hostStore.lastErrorMessage == "Relay unreachable.")
    }

    @Test @MainActor
    func hostStoreKeepsKnownOnlineHostDuringRefreshErrors() async throws {
        let service = RecordingHermesHostService()
        service.currentHost = HermesHostStatus(
            id: UUID(),
            displayName: "Home Mac mini",
            hostname: "test-host",
            platform: "macos",
            connectorVersion: "0.1.0",
            hermesCommand: "hermes",
            hermesVersion: "hermes 1.2.3",
            hermesModel: "gpt-5.4-mini",
            lastSeenAt: .now,
            lastConnectedAt: .now,
            isOnline: true
        )

        let hostStore = HermesHostStore(hostService: service)

        await hostStore.refresh()
        service.fetchError = APIClientError.requestFailed("Relay unreachable.")
        await hostStore.refresh()

        #expect(hostStore.currentHost?.resolvedDisplayName == "Home Mac mini")
        #expect(hostStore.connectionState == .online)
        #expect(hostStore.lastErrorMessage == "Relay unreachable.")
    }

    // **TOMBSTONED 2026-08-25 (#309 Lane B) — three tests, one plane.**
    //
    // `pairingStoreDisconnectClearsRelayConfigurationAndSession`,
    // `pairingWipesStaleKeychainIdentityAndRecordsMintedUser` and
    // `validateRestoredIdentityFlagsResurrectedStaleUser` all measured the
    // #3/#46 stale-identity guard: a reinstall could resurrect a previous
    // relay user from the Keychain, so a redeem adopted its new identity on a
    // clean slate and `validateRestoredIdentity()` flagged a survivor.
    //
    // **The defect they guard cannot occur on the gateway plane, and that is
    // why they are tombstoned rather than ported.** There is no minted
    // identity to resurrect: a gateway credential is a key the USER pasted,
    // not a user id a server issued, so "the Keychain's identity disagrees
    // with the pairing's" has no two things to disagree. What survives of the
    // clean-slate rule — a connect writes one profile's slots and only after
    // the remote step passed — is `ConnectHostTests`, and Disconnect's own
    // wipe of BOTH credential families is
    // `disconnectClearsOnlyTheTargetProfilesCredentials` there.
    //
    // The Keychain-slot mechanics they exercised end to end keep a live pin in
    // `theRelayResiduePurgeIsScopedAndDoesNotWiden` (BackendProfilesTests),
    // which additionally proves the sweep does not widen onto the gateway key.


    @Test @MainActor
    func inboxStorePersistsReadAndDismissState() async throws {
        let suiteName = "inbox-store-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let persistence = UserDefaultsAppPersistenceStore(defaults: defaults)

        let inboxStore = InboxStore(
            inboxService: MockInboxService(),
            persistence: persistence
        )

        await inboxStore.loadInbox(force: true)
        let originalItems = inboxStore.items

        guard let firstItem = originalItems.first, let secondItem = originalItems.dropFirst().first else {
            Issue.record("Expected demo inbox items")
            return
        }

        await inboxStore.performPrimaryAction(for: firstItem)
        await inboxStore.dismiss(secondItem)

        let reloadedStore = InboxStore(
            inboxService: MockInboxService(),
            persistence: persistence
        )

        await reloadedStore.loadInbox(force: true)

        #expect(reloadedStore.items.contains(where: { $0.stableIdentifier == firstItem.stableIdentifier && $0.isRead }))
        #expect(!reloadedStore.items.contains(where: { $0.stableIdentifier == secondItem.stableIdentifier }))
    }

    @Test @MainActor
    func chatStoreLoadsLatestUsageFromConversationMetadata() async {
        let hermesClient = RecordingHermesClient()
        hermesClient.currentConversation = Conversation(
            title: "Hermes",
            messages: [
                Message(sender: .user, content: "Hello"),
                Message(sender: .hermes, content: "Hi")
            ],
            latestUsage: TokenUsage(
                promptTokens: 3200,
                completionTokens: 240,
                totalTokens: 3440
            )
        )

        let suiteName = "chat-usage-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let persistence = UserDefaultsAppPersistenceStore(defaults: defaults)

        let chatStore = ChatStore(hermesClient: hermesClient, persistence: persistence)
        await chatStore.loadConversation()

        #expect(chatStore.lastTokenUsage?.promptTokens == 3200)
        #expect(chatStore.currentContextTokens == 3200)
    }

    @Test @MainActor
    func chatStoreInfersHermesAlignedContextWindowFallback() {
        #expect(ChatStore.inferredContextWindow(for: "gpt-5.4-mini") == 128_000)
        #expect(ChatStore.inferredContextWindow(for: "claude-sonnet-4.6") == 1_000_000)
    }

    /// #349 follow-up (Owen's OJAMD pass): deepseek-v4 is a 1M-token family
    /// — the blanket deepseek → 128K arm is a V3-era number and made the
    /// gauge read 68% on a ~9%-full window. V4 first, generic second.
    @Test @MainActor
    func chatStoreInfersDeepseekV4MillionTokenWindow() {
        #expect(ChatStore.inferredContextWindow(for: "deepseek-v4-flash") == 1_000_000)
        #expect(ChatStore.inferredContextWindow(for: "deepseek-v4") == 1_000_000)
        #expect(ChatStore.inferredContextWindow(for: "deepseek-chat") == 128_000)
    }

    // MARK: - CTX denominator reconciliation (#4)

    @Test @MainActor
    func reportedContextWindowParsesModelSwitchResponse() {
        let response = """
        Model switched to `kimi-k2.6`
        Provider: kimi-coding
        Context: 262,144 tokens
        """
        #expect(ChatStore.reportedContextWindow(in: response) == 262_144)
        #expect(ChatStore.reportedContextWindow(in: "Context: 1,000,000 tokens") == 1_000_000)
        #expect(ChatStore.reportedContextWindow(in: "Model switched to `x`") == nil)
        #expect(ChatStore.reportedContextWindow(in: "Context: 0 tokens") == nil)
    }

    @Test @MainActor
    func failedCatalogRefreshPreservesHermesReportedWindow() {
        let suiteName = "chat-ctx-preserve-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let persistence = UserDefaultsAppPersistenceStore(defaults: defaults)
        let chatStore = ChatStore(hermesClient: MockHermesClient(), persistence: persistence)

        chatStore.replaceCommandCatalog(SlashCommand.allBuiltIn, activeModel: "kimi-k2.6", contextWindow: 190_000)
        // A transient catalog-fetch failure (relay offline) must not demote
        // the denominator to the nominal table (#4).
        chatStore.restoreBuiltInCatalog()
        #expect(chatStore.contextWindow == 190_000)
        #expect(chatStore.activeModelName == "kimi-k2.6")

        // The real reset path (unpair) still clears it.
        chatStore.resetCommandCatalog()
        #expect(chatStore.contextWindow == nil)
    }

    // MARK: - Inline tool-call transcript segments (#10)

    @Test @MainActor
    func transcriptSegmentsAnchorToolChipsInline() {
        // "Looking…" streams (9 chars), a tool fires, then the answer streams.
        let content = "Looking… Here is the answer."
        let tool = ToolActivity(label: "read_file", isActive: false, anchorOffset: 9)
        let segments = MessageBubble.transcriptSegments(content: content, activities: [tool])

        #expect(segments.count == 3)
        guard case .text(let head, 0) = segments[0],
              case .tools(let group, 9) = segments[1],
              case .text(let tail, 9) = segments[2]
        else {
            Issue.record("unexpected segment shape")
            return
        }
        #expect(head == "Looking… ")
        #expect(group.map(\.label) == ["read_file"])
        #expect(tail == "Here is the answer.")
    }

    @Test @MainActor
    func transcriptSegmentsGroupSameAnchorAndLeadWithPreTextTools() {
        // Two calls before any content share one leading group.
        let tools = [
            ToolActivity(label: "search", isActive: false, anchorOffset: 0),
            ToolActivity(label: "read_file", isActive: false, anchorOffset: 0),
        ]
        let segments = MessageBubble.transcriptSegments(content: "Answer.", activities: tools)

        #expect(segments.count == 2)
        guard case .tools(let group, 0) = segments[0],
              case .text(let text, 0) = segments[1]
        else {
            Issue.record("unexpected segment shape")
            return
        }
        #expect(group.map(\.label) == ["search", "read_file"])
        #expect(text == "Answer.")
    }

    @Test @MainActor
    func transcriptSegmentsClampOutOfRangeAnchors() {
        // A stale cache / server reload can carry anchors past the content.
        let tool = ToolActivity(label: "write_file", isActive: false, anchorOffset: 999)
        let segments = MessageBubble.transcriptSegments(content: "Short.", activities: [tool])

        #expect(segments.count == 2)
        guard case .text("Short.", 0) = segments[0],
              case .tools(let group, 6) = segments[1]
        else {
            Issue.record("unexpected segment shape")
            return
        }
        #expect(group.count == 1)
    }

    // MARK: - Inline artifact chip anchoring (#262)

    @Test @MainActor
    func anchoredArtifactChipStaysAtItsAnchorWhileContentGrows() {
        // 262-A. Mid-stream moment: "Writing… " has streamed (9 chars),
        // write_file fired, the artifact landed. Then the answer streams on.
        let midStream = "Writing… "
        let full = "Writing… Here is the file, plus discussion streamed after it."
        let tool = ToolActivity(label: "write_file", isActive: false, anchorOffset: 9)
        var artifact = MessageAttachment(kind: "file", fileName: "out.md", mimeType: "text/markdown")
        artifact.anchorOffset = 9

        let mid = MessageBubble.transcriptLayout(
            content: midStream, activities: [tool], attachments: [artifact]
        )
        let done = MessageBubble.transcriptLayout(
            content: full, activities: [tool], attachments: [artifact]
        )

        // Mid-stream: head text, tool card, chip — the chip under the card.
        #expect(mid.trailingAttachments.isEmpty)
        guard mid.segments.count == 3,
              case .text(_, 0) = mid.segments[0],
              case .tools(_, 9) = mid.segments[1],
              case .artifacts(let midChips, 9) = mid.segments[2]
        else {
            Issue.record("unexpected mid-stream segment shape")
            return
        }
        #expect(midChips.map(\.id) == [artifact.id])

        // Finished: identical prefix — the trailing text renders BENEATH the
        // chip; the finish boundary moved nothing.
        #expect(done.trailingAttachments.isEmpty)
        guard done.segments.count == 4,
              case .text(let head, 0) = done.segments[0],
              case .tools(_, 9) = done.segments[1],
              case .artifacts(let doneChips, 9) = done.segments[2],
              case .text(let tail, 9) = done.segments[3]
        else {
            Issue.record("unexpected finished segment shape")
            return
        }
        #expect(head == "Writing… ")
        #expect(doneChips.map(\.id) == [artifact.id])
        #expect(tail == "Here is the file, plus discussion streamed after it.")
    }

    @Test @MainActor
    func unanchoredAttachmentsKeepTheTrailingGridAndEveryChipRendersOnce() {
        // 262-B. A nil anchor (pre-lane cache, Tier 2 fetchable appended at
        // finish) keeps today's trailing grid; an anchored one goes inline;
        // every attachment appears exactly once across the two.
        let tool = ToolActivity(label: "write_file", isActive: false, anchorOffset: 5)
        var anchored = MessageAttachment(kind: "file", fileName: "new.md", mimeType: "text/markdown")
        anchored.anchorOffset = 5
        let legacy = MessageAttachment(kind: "file", fileName: "old.md", mimeType: "text/markdown")

        let layout = MessageBubble.transcriptLayout(
            content: "Done. All set.", activities: [tool], attachments: [anchored, legacy]
        )

        #expect(layout.trailingAttachments.map(\.id) == [legacy.id])
        let inline = layout.segments.flatMap { segment -> [UUID] in
            if case .artifacts(let chips, _) = segment { return chips.map(\.id) }
            return []
        }
        #expect(inline == [anchored.id])
    }

    @Test @MainActor
    func anchoredArtifactWithoutToolActivitiesStillRenders() {
        // 262-B. No tool chips on the message must not vanish an anchored
        // artifact — it still renders (inline, at its clamped anchor).
        var artifact = MessageAttachment(kind: "file", fileName: "solo.md", mimeType: "text/markdown")
        artifact.anchorOffset = 6

        let layout = MessageBubble.transcriptLayout(
            content: "Here. And more prose after.", activities: [], attachments: [artifact]
        )

        #expect(layout.trailingAttachments.isEmpty)
        guard layout.segments.count == 3,
              case .text(_, 0) = layout.segments[0],
              case .artifacts(let chips, 6) = layout.segments[1],
              case .text(_, 6) = layout.segments[2]
        else {
            Issue.record("unexpected segment shape")
            return
        }
        #expect(chips.map(\.id) == [artifact.id])
    }

    @Test @MainActor
    func attachmentAnchorRoundTripsAndOldCachesDecodeNil() throws {
        // 262-E's persistence half: the anchor rides the conversation cache,
        // and pre-lane JSON (no key) still decodes — as unanchored.
        var artifact = MessageAttachment(kind: "file", fileName: "out.md", mimeType: "text/markdown")
        artifact.anchorOffset = 12
        let data = try JSONEncoder().encode(artifact)
        let decoded = try JSONDecoder().decode(MessageAttachment.self, from: data)
        #expect(decoded.anchorOffset == 12)

        let legacyJSON = """
        {"id":"\(UUID().uuidString)","kind":"file","fileName":"old.md","mimeType":"text/markdown"}
        """
        let legacy = try JSONDecoder().decode(MessageAttachment.self, from: Data(legacyJSON.utf8))
        #expect(legacy.anchorOffset == nil)
    }

    @Test @MainActor
    func messageCodableRoundTripsToolActivities() throws {
        // #10: the tool timeline must survive the conversation cache.
        let message = Message(
            sender: .hermes,
            content: "Done.",
            toolActivities: [
                ToolActivity(label: "write_file", isActive: false, detail: "path: notes.md", anchorOffset: 0),
            ]
        )
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(Message.self, from: data)
        #expect(decoded.toolActivities.count == 1)
        #expect(decoded.toolActivities.first?.label == "write_file")
        #expect(decoded.toolActivities.first?.detail == "path: notes.md")
        #expect(decoded.toolActivities.first?.anchorOffset == 0)
    }

    // MARK: - Anchor word-boundary snap (#265)
    //
    // The device-caught shape (#262's first screenshots, OTA 2107): the model
    // narrated THROUGH the write ("…The file landed at…") so the raw anchor —
    // content length at fire time — fell inside "landed" and split it into
    // "lan" / "ded" around the card + chip. The stored anchor stays raw and
    // honest; only the RENDERED split snaps back to the last whitespace at-or-
    // before it, composed with the existing cursor clamp and equal-anchor
    // grouping.

    /// Compact segment dump, so a shape mismatch reports what actually came
    /// back instead of a bare "unexpected".
    @MainActor
    private func describe(_ segments: [MessageBubble.TranscriptSegment]) -> String {
        segments.map { segment in
            switch segment {
            case .text(let text, let offset): "text@\(offset):\(text.debugDescription)"
            case .tools(let group, let offset): "tools@\(offset):\(group.map(\.label))"
            case .artifacts(let group, let offset): "artifacts@\(offset):\(group.map(\.fileName))"
            }
        }.joined(separator: " | ")
    }

    @Test @MainActor
    func midWordAnchorSnapsTheRenderedSplitBackToTheWordBoundary() {
        // 265-A. "The file lan⟨card+chip⟩ded at ~/notes.md" must render as
        // "The file " ⟨card+chip⟩ "landed at ~/notes.md".
        let content = "The file landed at ~/notes.md"
        let tool = ToolActivity(label: "write_file", isActive: false, anchorOffset: 12)
        var artifact = MessageAttachment(kind: "file", fileName: "notes.md", mimeType: "text/markdown")
        artifact.anchorOffset = 12

        let layout = MessageBubble.transcriptLayout(
            content: content, activities: [tool], attachments: [artifact]
        )

        guard layout.segments.count == 4,
              case .text(let head, let headOffset) = layout.segments[0],
              case .tools(let tools, let toolOffset) = layout.segments[1],
              case .artifacts(let chips, let chipOffset) = layout.segments[2],
              case .text(let tail, let tailOffset) = layout.segments[3]
        else {
            Issue.record("unexpected segment shape: \(describe(layout.segments))")
            return
        }
        #expect(head == "The file ")
        #expect(headOffset == 0)
        #expect(tools.map(\.label) == ["write_file"])
        #expect(toolOffset == 9)
        #expect(chips.map(\.id) == [artifact.id])
        #expect(chipOffset == 9)
        #expect(tail == "landed at ~/notes.md")
        #expect(tailOffset == 9)

        // The STORED anchor stays raw — rendering moves the split, not the model.
        #expect(tool.anchorOffset == 12)
        #expect(artifact.anchorOffset == 12)
        #expect(tools.first?.anchorOffset == 12)
        #expect(chips.first?.anchorOffset == 12)
    }

    @Test @MainActor
    func equalMidWordAnchorsStillShareOneGroupAfterSnapping() {
        // 265-B. Two calls at the same raw mid-word anchor stay ONE group;
        // snapping moves the group, it does not split it.
        let tools = [
            ToolActivity(label: "write_file", isActive: false, anchorOffset: 12),
            ToolActivity(label: "read_file", isActive: false, anchorOffset: 12),
        ]
        let segments = MessageBubble.transcriptSegments(
            content: "The file landed at ~/notes.md", activities: tools
        )

        guard segments.count == 3,
              case .text(let head, _) = segments[0],
              case .tools(let group, let toolOffset) = segments[1],
              case .text(let tail, let tailOffset) = segments[2]
        else {
            Issue.record("unexpected segment shape: \(describe(segments))")
            return
        }
        #expect(head == "The file ")
        #expect(group.map(\.label) == ["write_file", "read_file"])
        #expect(toolOffset == 9)
        #expect(tail == "landed at ~/notes.md")
        #expect(tailOffset == 9)
    }

    @Test @MainActor
    func distinctRawAnchorsThatSnapToOneBoundaryMergeToolsBeforeChips() {
        // 265-B. The device shape: the call fires at 12, the file lands at 14
        // — both inside "landed". They merge into ONE anchor point, and the
        // card still renders above the chip it produced.
        let tool = ToolActivity(label: "write_file", isActive: false, anchorOffset: 12)
        var artifact = MessageAttachment(kind: "file", fileName: "notes.md", mimeType: "text/markdown")
        artifact.anchorOffset = 14

        let layout = MessageBubble.transcriptLayout(
            content: "The file landed at ~/notes.md", activities: [tool], attachments: [artifact]
        )

        guard layout.segments.count == 4,
              case .text(let head, _) = layout.segments[0],
              case .tools(let tools, let toolOffset) = layout.segments[1],
              case .artifacts(let chips, let chipOffset) = layout.segments[2],
              case .text(let tail, _) = layout.segments[3]
        else {
            Issue.record("unexpected segment shape: \(describe(layout.segments))")
            return
        }
        #expect(head == "The file ")
        #expect(tools.map(\.label) == ["write_file"])
        #expect(chips.map(\.id) == [artifact.id])
        #expect(toolOffset == 9)
        #expect(chipOffset == 9)
        #expect(tail == "landed at ~/notes.md")
        #expect(artifact.anchorOffset == 14)
    }

    @Test @MainActor
    func snappedAnchorNeverMovesBeforeTheWalkCursor() {
        // 265-B. A stale cache can carry anchors out of order; a snap must
        // never rewind past text already emitted — the existing clamp binds
        // after the snap, so the late anchor joins the group at the cursor.
        let tools = [
            ToolActivity(label: "write_file", isActive: false, anchorOffset: 22),
            ToolActivity(label: "read_file", isActive: false, anchorOffset: 8),
        ]
        let segments = MessageBubble.transcriptSegments(
            content: "Alpha bravo charlie delta echo", activities: tools
        )

        guard segments.count == 3,
              case .text(let head, _) = segments[0],
              case .tools(let group, let toolOffset) = segments[1],
              case .text(let tail, let tailOffset) = segments[2]
        else {
            Issue.record("unexpected segment shape: \(describe(segments))")
            return
        }
        #expect(head == "Alpha bravo charlie ")
        #expect(group.map(\.label) == ["write_file", "read_file"])
        #expect(toolOffset == 20)
        #expect(tail == "delta echo")
        #expect(tailOffset == 20)
    }

    @Test @MainActor
    func anchorAlreadyAtAWordBoundaryIsUnchangedBySnapping() {
        // 265-C degenerate, and a pin: an anchor that already sits on a
        // boundary must not move — neither the first-character-of-a-word case
        // nor the anchor-lands-on-the-whitespace case.
        let atWordStart = MessageBubble.transcriptSegments(
            content: "Alpha bravo",
            activities: [ToolActivity(label: "write_file", isActive: false, anchorOffset: 6)]
        )
        guard atWordStart.count == 3,
              case .text("Alpha ", 0) = atWordStart[0],
              case .tools(_, 6) = atWordStart[1],
              case .text("bravo", 6) = atWordStart[2]
        else {
            Issue.record("unexpected word-start shape: \(describe(atWordStart))")
            return
        }

        let onWhitespace = MessageBubble.transcriptSegments(
            content: "Done. All set.",
            activities: [ToolActivity(label: "write_file", isActive: false, anchorOffset: 5)]
        )
        guard onWhitespace.count == 3,
              case .text("Done.", 0) = onWhitespace[0],
              case .tools(_, 5) = onWhitespace[1],
              case .text(" All set.", 5) = onWhitespace[2]
        else {
            Issue.record("unexpected whitespace-anchor shape: \(describe(onWhitespace))")
            return
        }
    }

    @Test @MainActor
    func anchorInsideARunWithNoWhitespaceBeforeItClampsToTheCursor() {
        // 265-C degenerate: nothing to snap back TO, so the split falls to the
        // walk cursor (0 here) rather than cutting the token.
        let segments = MessageBubble.transcriptSegments(
            content: "Antidisestablishmentarianism is a long word",
            activities: [ToolActivity(label: "write_file", isActive: false, anchorOffset: 10)]
        )

        guard segments.count == 2,
              case .tools(let group, let toolOffset) = segments[0],
              case .text(let text, let textOffset) = segments[1]
        else {
            Issue.record("unexpected segment shape: \(describe(segments))")
            return
        }
        #expect(group.map(\.label) == ["write_file"])
        #expect(toolOffset == 0)
        #expect(text == "Antidisestablishmentarianism is a long word")
        #expect(textOffset == 0)
    }

    @Test @MainActor
    func outOfRangeAnchorsStillClampToContentEndAfterSnapping() {
        // 265-C degenerate, and a pin on #10's clamp: an anchor past the end
        // is bounded to the content end, which is a boundary — no snap.
        var artifact = MessageAttachment(kind: "file", fileName: "out.md", mimeType: "text/markdown")
        artifact.anchorOffset = 999

        let layout = MessageBubble.transcriptLayout(
            content: "Short.", activities: [], attachments: [artifact]
        )

        guard layout.segments.count == 2,
              case .text("Short.", 0) = layout.segments[0],
              case .artifacts(let chips, 6) = layout.segments[1]
        else {
            Issue.record("unexpected segment shape: \(describe(layout.segments))")
            return
        }
        #expect(chips.map(\.id) == [artifact.id])
    }

    // MARK: - Offline-first launch (#136)
    //
    // The device-caught shape: Windows Firewall silently DROPS packets to
    // listener-less ports (no TCP refusal), so every relay/shim request hangs
    // the full URLSession timeout instead of failing fast. The launch splash
    // must drop on local-state-ready — never on relay convergence.

    /// A relay that never answers. `wait()` suspends until the gate opens and
    /// honors task cancellation the way URLSession does (throws
    /// `CancellationError`), so cancelled launch probes unwind instead of
    /// landing stale results.
    @MainActor
    private final class BlackHoleGate {
        private(set) var isOpen = false

        func open() { isOpen = true }

        func wait() async throws {
            while !isOpen {
                try await Task.sleep(for: .milliseconds(10))
            }
        }
    }

    /// #389: a health service that PARKS inside `reloadCapabilities()`.
    ///
    /// This is the seam that turns #389's race into a deterministic fact.
    /// `PermissionsStore.reloadCapabilities()` awaits
    /// `healthService.refreshAuthorizationStatus()`, and that call sits
    /// BETWEEN the hoisted widget write (`AppContainer.swift:1633`) and
    /// `await hostStore.refresh()`. Holding it open means the activation is
    /// provably parked after the write and before the fetch — no timing luck
    /// involved.
    private final class GatedHealthService: HealthServiceProtocol {
        let gate: BlackHoleGate
        private(set) var refreshCallCount = 0
        var authorizationStatus: PermissionStatus = .notDetermined

        init(gate: BlackHoleGate) { self.gate = gate }

        func requestAuthorization() async -> PermissionStatus { authorizationStatus }

        func refreshAuthorizationStatus() async {
            refreshCallCount += 1
            try? await gate.wait()
        }
    }

    @MainActor
    private final class BlackHoleHermesHostService: HermesHostServiceProtocol {
        let gate: BlackHoleGate
        var fetchCallCount = 0
        var host: HermesHostStatus?

        init(gate: BlackHoleGate, host: HermesHostStatus? = nil) {
            self.gate = gate
            self.host = host
        }

        func fetchCurrentHost() async throws -> HermesHostStatus? {
            fetchCallCount += 1
            try await gate.wait()
            return host
        }
    }

    @MainActor
    private final class BlackHoleInboxService: InboxServiceProtocol {
        let gate: BlackHoleGate
        var fetchCallCount = 0

        init(gate: BlackHoleGate) {
            self.gate = gate
        }

        func fetchInbox() async throws -> [InboxItem] {
            fetchCallCount += 1
            try await gate.wait()
            return [InboxItem(type: .alert, title: "Landed after uplink", body: "Delivered by background init")]
        }

        func submitAction(itemID: UUID, actionID: String) async throws -> InboxActionResult {
            InboxActionResult(itemID: itemID, actionID: actionID, status: .completed, completedAt: .now)
        }
    }

    /// Chat client for the #184 teardown tests: send #1 interrupts (arming a
    /// pendingRun for "S1"), later sends stream into a black hole and stay
    /// live until the consuming task is cancelled — which is recorded, so a
    /// test can assert teardown actually cancelled the stream rather than
    /// abandoning it mid-air.
    @MainActor
    private final class BlackHoleStreamingChatClient: HermesClientProtocol {
        var connectionStatus: ConnectionStatus = .connected
        var currentConversation: Conversation?
        var sendCount = 0
        var streamCancelled = false
        var reconcileFromServerCallCount = 0

        func connect() async {}
        func disconnect() async {}

        func send(message: String, attachments: [PendingAttachment] = [], clientMessageID: UUID) async -> Message {
            Message(sender: .hermes, content: "unused", status: .delivered)
        }

        func sendStreaming(message: String, attachments: [PendingAttachment] = [], clientMessageID: UUID) -> AsyncStream<StreamingUpdate> {
            sendCount += 1
            if sendCount == 1 {
                return AsyncStream { continuation in
                    Task { @MainActor in
                        continuation.yield(.messageSent(jobID: UUID()))
                        continuation.yield(.interrupted(sessionId: "S1", runId: nil))
                        continuation.finish()
                    }
                }
            }
            return AsyncStream { continuation in
                continuation.onTermination = { @Sendable reason in
                    if case .cancelled = reason {
                        Task { @MainActor in self.streamCancelled = true }
                    }
                }
                continuation.yield(.messageSent(jobID: UUID()))
                continuation.yield(.textDelta("still streaming"))
                // Never finishes — the run stays live until torn down.
            }
        }

        func loadConversation() async -> Conversation {
            currentConversation ?? Conversation(title: "Hermes")
        }

        func clearConversation() async throws -> Conversation {
            Conversation(title: "Hermes")
        }

        func reconcileFromServer() async -> Conversation? {
            reconcileFromServerCallCount += 1
            return nil
        }
    }

    /// #291/#294: accepts the turn, streams exactly what its script says,
    /// and then stays live forever — the state a Stop tap lands in. Because
    /// the stream never finishes, `sendMessage` only returns once the store
    /// tears it down, which makes the Stop the test's own event rather than
    /// a race against a terminal frame.
    private final class StoppableStreamingChatClient: HermesClientProtocol {
        enum Script: Sendable {
            /// Stop during the thinking phase: accepted, not one token.
            case silentAfterAccept
            /// Stop mid-answer: a real partial the fix must not eat.
            case partialProse(String)
            /// Stop during a tool call: no prose, but visible activity.
            case toolActivityOnly(String)
            /// #296 bar B, row (i): the tool GENUINELY finished — a named
            /// `tool.completed` resolved its chip — and only then is the turn
            /// stopped. The finished call must keep its ✓.
            case toolThenNamedCompletion(String)
            /// #296 bar B, row (ii): the same outcome by the OTHER road — the
            /// chip is resolved implicitly because prose started arriving.
            /// Different code path in `ChatStore` (`.textDelta`, not
            /// `.toolActivity`), so handling only row (i) is a half-fix.
            case toolThenProse(name: String, text: String)
        }

        let script: Script
        var connectionStatus: ConnectionStatus = .connected
        var currentConversation: Conversation?
        /// #295 hazard 2 pin: distinguishes the walk-away teardown
        /// (`abandonActiveRun`, must fire unconditionally) from the explicit
        /// Stop tap's real server-side interrupt (`hardStopActiveRun`, must
        /// stay gated on `hardStopHost`). Overriding both (instead of relying
        /// on the protocol's default no-ops) makes the ordering/gating
        /// observable to a test.
        private(set) var abandonActiveRunCallCount = 0
        private(set) var hardStopActiveRunCallCount = 0
        /// #295 review follow-up: this double models a live Hermes-plane
        /// turn (partial prose / tool activity accepted server-side, held
        /// open until a Stop) — every existing use of it predates the gate
        /// and expects the pre-gate `hardStopHost: false` behavior where one
        /// is exercised, so it opts in rather than falling to the protocol's
        /// conservative `false` default.
        let currentRunIsServerRecoverable = true

        init(script: Script) {
            self.script = script
        }

        func connect() async {}
        func disconnect() async {}

        func abandonActiveRun() {
            abandonActiveRunCallCount += 1
        }

        @discardableResult
        func hardStopActiveRun() -> Bool {
            hardStopActiveRunCallCount += 1
            return hostStopIsIssuable
        }
        /// #328 route 2: default false — nothing was issued.
        var hostStopIsIssuable = false

        func send(message: String, attachments: [PendingAttachment] = [], clientMessageID: UUID) async -> Message {
            Message(sender: .hermes, content: "unused", status: .delivered)
        }

        func sendStreaming(message: String, attachments: [PendingAttachment] = [], clientMessageID: UUID) -> AsyncStream<StreamingUpdate> {
            let script = script
            return AsyncStream { continuation in
                continuation.yield(.messageSent(jobID: UUID()))
                switch script {
                case .silentAfterAccept:
                    break
                case .partialProse(let text):
                    continuation.yield(.textDelta(text))
                case .toolActivityOnly(let name):
                    continuation.yield(.toolActivity(ToolCallEvent(name: name)))
                case .toolThenNamedCompletion(let name):
                    continuation.yield(.toolActivity(ToolCallEvent(name: name)))
                    continuation.yield(.toolActivity(ToolCallEvent(name: name, phase: .completed)))
                case .toolThenProse(let name, let text):
                    continuation.yield(.toolActivity(ToolCallEvent(name: name)))
                    continuation.yield(.textDelta(text))
                }
                // Never finishes — the run stays live until the Stop.
            }
        }

        func loadConversation() async -> Conversation {
            currentConversation ?? Conversation(title: "Hermes")
        }

        func clearConversation() async throws -> Conversation {
            Conversation(title: "Hermes")
        }
    }

    /// #296: emits a literal script of `StreamingUpdate`s and then FINISHES.
    /// The counterpart to `StoppableStreamingChatClient` — that one models a
    /// turn held open for a Stop; this one models an ordinary turn that runs
    /// to completion, which is what 296-C1 needs: the host's error text rides
    /// a `tool.completed` on a turn nobody interrupted.
    private final class ScriptedStreamChatClient: HermesClientProtocol {
        let script: [StreamingUpdate]
        var connectionStatus: ConnectionStatus = .connected
        var currentConversation: Conversation?

        init(script: [StreamingUpdate]) {
            self.script = script
        }

        func connect() async {}
        func disconnect() async {}

        func send(message: String, attachments: [PendingAttachment] = [], clientMessageID: UUID) async -> Message {
            Message(sender: .hermes, content: "unused", status: .delivered)
        }

        func sendStreaming(message: String, attachments: [PendingAttachment] = [], clientMessageID: UUID) -> AsyncStream<StreamingUpdate> {
            let script = script
            return AsyncStream { continuation in
                continuation.yield(.messageSent(jobID: UUID()))
                for update in script {
                    continuation.yield(update)
                }
                continuation.finish()
            }
        }

        func loadConversation() async -> Conversation {
            currentConversation ?? Conversation(title: "Hermes")
        }

        func clearConversation() async throws -> Conversation {
            Conversation(title: "Hermes")
        }
    }

    /// A fully wired bare container whose every host surface rides a
    /// black-hole gate, paired with a valid Keychain-local session.
    ///
    /// **#309 Lane A dropped `bootstrapGate` / `bootstrapService`** with the
    /// relay session bootstrap they modelled. What the harness still black-
    /// holes — host presence and the inbox fetch — is the traffic that
    /// actually survives into Lane C.
    @MainActor
    private struct LaunchHarness {
        let container: AppContainer
        let secureStore: MockSecureStore
        let hostGate: BlackHoleGate
        let inboxGate: BlackHoleGate
        let hostService: BlackHoleHermesHostService
        let inboxService: BlackHoleInboxService
        /// #310: held so a test can count `talk/readiness` calls — the store
        /// owns the service privately, so the harness is the only place a
        /// test can reach it.
        let voiceService: RecordingVoiceSessionService

        func openAllGates() {
            hostGate.open()
            inboxGate.open()
        }
    }

    @MainActor
    private func makeLaunchHarness(
        suiteName: String,
        chatClient: (any HermesClientProtocol)? = nil,
        seedAccessToken: Bool = true,
        /// **#411**: whether the ACTIVE profile holds gateway credentials —
        /// the capability the lifecycle entry points now gate their
        /// host-backed work on. A bare container holds no profiles store, so
        /// this drives `AppContainer.gatewayCredentialsProbe` (the seam that
        /// exists for exactly this). Defaults true, which is the pre-#411
        /// behaviour for a paired install and keeps every inherited caller
        /// measuring what it measured before.
        gatewayCredentials: Bool = true,
        /// #389: injected so a test can PARK the activation chain inside
        /// `reloadCapabilities()` — between the hoisted widget write and the
        /// host fetch. Defaulted, so every existing caller is unchanged.
        healthService: (any HealthServiceProtocol)? = nil
    ) async -> LaunchHarness {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let persistence = UserDefaultsAppPersistenceStore(defaults: defaults)

        let secureStore = MockSecureStore()
        // **#309 Lane B re-keyed this fixture from the relay plane onto the
        // gateway one, and kept #369's shape.** `seedAccessToken: false` was
        // "a pairing record present with an EMPTY access-token slot" — the
        // pre-first-unlock Keychain read, indistinguishable upstream of
        // `retrieve` from a missing item. The same defect has the same shape
        // on the gateway plane, with the GATEWAY KEY as the credential that
        // reads empty: `credentialsUnreadableHold` is about that slot now.
        if seedAccessToken {
            await secureStore.store(
                key: BackendProfileScopedKeys.gatewayAPIKey(nil), value: "launch-gateway-key")
        }

        let hostGate = BlackHoleGate()
        let inboxGate = BlackHoleGate()

        let hostService = BlackHoleHermesHostService(
            gate: hostGate,
            host: HermesHostStatus(
                id: UUID(),
                displayName: "OJAMD",
                hostname: "ojamd.tailnet.test",
                platform: "windows",
                connectorVersion: "1.0.0",
                hermesCommand: "hermes",
                hermesVersion: "1.0.0",
                hermesModel: nil,
                lastSeenAt: .now,
                lastConnectedAt: .now,
                isOnline: true
            )
        )
        let hostStore = HermesHostStore(hostService: hostService)
        let inboxService = BlackHoleInboxService(gate: inboxGate)
        let voiceService = RecordingVoiceSessionService()
        let container = AppContainer(
            hostStore: hostStore,
            chatStore: ChatStore(hermesClient: chatClient ?? RecordingHermesClient(), persistence: persistence),
            inboxStore: InboxStore(
                inboxService: inboxService,
                persistence: persistence
            ),
            permissionsStore: PermissionsStore(
                locationService: MockLocationService(),
                healthService: healthService ?? MockHealthService(),
                    mediaService: MockMediaService()
            ),
            settingsStore: SettingsStore(persistence: persistence),
            talkStore: TalkStore(voiceService: voiceService),
        )
        container.gatewayCredentialsProbe = { gatewayCredentials }
        return LaunchHarness(
            container: container,
            secureStore: secureStore,
            hostGate: hostGate,
            inboxGate: inboxGate,
            hostService: hostService,
            inboxService: inboxService,
            voiceService: voiceService
        )
    }

    /// **#309 Lane B — the splash is a LAUNCH surface, and a host-lifecycle
    /// reset must never re-raise it.**
    ///
    /// Both host seams set `isInitialized = false` on purpose: the host-backed
    /// work genuinely has to run again. But `shouldShowLaunchSplash` was
    /// `hasGatewayCredentials && !isInitialized`, so committing credentials
    /// from inside the Connect Host wizard flipped BOTH terms in one beat and
    /// threw a full-screen splash over the user — for as long as the fresh
    /// `initialize()`'s host half took, which against an unreachable address
    /// is the full timeout.
    ///
    /// **Found by the UI journeys, not by reasoning:** all three connect
    /// journeys failed the full-bundle gate at step 3 and passed in isolation,
    /// because in isolation the splash cleared before the assertion looked.
    ///
    /// **This test drives DISCONNECT, and that is deliberate — the first draft
    /// drove `handleHostConnected()` and the mutation SURVIVED it.** That
    /// handler chases its own flag flip with an `await initialize()`, so on a
    /// harness container the whole window closes inside one MainActor chunk
    /// and a poll can never see it: a green test that measured timing rather
    /// than the rule. `handleHostDisconnected()` performs the SAME flip and
    /// does not re-initialize, so the state it leaves is exactly the one the
    /// wizard's user stood in — observable, and not a race.
    ///
    /// Mutation that must turn this RED: drop
    /// `&& !hasCompletedFirstInitialize` from `shouldShowLaunchSplash`.
    /// (Verified: it does.)
    @Test @MainActor
    func aHostLifecycleResetNeverRaisesTheLaunchSplashAgain() async {
        let harness = await makeLaunchHarness(
            suiteName: "309-B-splash-\(UUID().uuidString)")
        harness.openAllGates()
        let container = harness.container

        // A host-bearing launch DOES start on the splash — assert it, or the
        // whole test could pass against a surface that never appears at all.
        #expect(container.shouldShowLaunchSplash,
                "fixture precondition: a host-bearing launch starts on the splash")
        await container.initialize()
        #expect(container.shouldShowLaunchSplash == false)

        // The flag flip, in the seam that leaves it observable. The harness's
        // credential probe still reports a host, which is what isolates the
        // `isInitialized` term as the only thing that changed.
        await container.handleHostDisconnected()
        #expect(container.hasGatewayCredentials,
                "fixture precondition: the probe still reports a host, so only isInitialized moved")
        #expect(container.shouldShowLaunchSplash == false,
                "a host-lifecycle reset re-raised the launch splash over the user")

        // …and the connect seam, whose commit is where the defect was seen.
        await container.handleHostConnected()
        #expect(container.shouldShowLaunchSplash == false)
    }

    /// **#309 Lane B — `initialize()`'s share drain is a LAUNCH step, because
    /// it NAVIGATES.**
    ///
    /// `drainShareInbox()` ends with `router.popToRoot()`. That is right at
    /// launch: a staged share belongs in the composer, and the composer is the
    /// root. It is wrong from `handleHostConnected()`, which re-runs
    /// `initialize()` while the user is standing inside the Connect Host
    /// wizard — with anything queued in the app group, committing the
    /// credentials threw them out of step 2 into chat.
    ///
    /// **The behavioural evidence is the UI journeys**, which is where this was
    /// found and where it is measured: the share inbox lives in the shared APP
    /// GROUP, which — unlike the per-test defaults suite and Keychain service
    /// — is NOT isolated between UI tests, so the drain only ever had anything
    /// to do in a full-bundle run. Alone, all three journeys passed.
    ///
    /// This pins the RULE by its name, so the reason survives the fix.
    @Test @MainActor
    func theLaunchShareDrainRunsOnceAndNotOnEveryReInitialize() {
        #expect(AppContainer.launchStepsShouldDrainShareInbox(hasCompletedFirstInitialize: false))
        #expect(AppContainer.launchStepsShouldDrainShareInbox(hasCompletedFirstInitialize: true) == false)
    }

    /// Polls `condition` until it holds or the deadline passes; returns
    /// whether it held so the caller's `#expect` names the failing site.
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

    // MARK: - #180: profile switch resets host-fed stores

    /// #180 — the defect was the WIRING, not the stores. Each host-fed
    /// store (skills, cron jobs, insights) resolves its URL per-fetch, but
    /// its cached rows survived `handleActiveProfileChanged`, so the cron
    /// editor's picker could offer Host A's skills for a job created on
    /// Host B. The store-level `reset()` is pinned in each store's own
    /// tests; THIS test pins the call path — a reset() nobody calls is a
    /// control on a path the defect does not take.
    @Test @MainActor
    func profileSwitchResetsHostFedStores() async throws {
        let harness = await makeLaunchHarness(
            suiteName: "profile-switch-resets-host-fed-stores"
        )
        harness.openAllGates()
        let container = harness.container

        let skillsService = SkillsStoreTests.FixtureSkillsService()
        skillsService.listResult = .success([Skill(name: "old-host-skill", description: nil, category: nil)])
        let skillsStore = SkillsStore(service: skillsService)
        await skillsStore.refresh()

        let cronService = CronJobsStoreTests.FixtureCronJobService()
        cronService.listResult = .success([try JSONDecoder().decode(CronJob.self, from: Data("""
        {"id": "aaa111aaa111", "name": "Old host job", "state": "scheduled",
         "schedule": {"kind": "interval", "minutes": 30}}
        """.utf8))])
        let cronStore = CronJobsStore(service: cronService)
        await cronStore.refresh()

        let insightsService = InsightsStoreTests.FixtureInsightsService()
        insightsService.fetchResult = .success(SessionStatsFetch(
            rows: [SessionStatsRow(id: "old-host-session", usage: SessionUsage(inputTokens: 1, outputTokens: 1))],
            isTruncated: false
        ))
        let insightsStore = InsightsStore(service: insightsService)
        await insightsStore.refresh()

        container.skillsStore = skillsStore
        container.cronJobsStore = cronStore
        container.insightsStore = insightsStore
        #expect(skillsStore.hasLoaded)
        #expect(cronStore.hasLoaded)
        #expect(insightsStore.hasLoaded)

        await container.handleActiveProfileChanged(to: BackendProfile(
            name: "New Host",
            gatewayBaseURL: "http://new-host:8642"
        ))

        #expect(skillsStore.skills.isEmpty)
        #expect(!skillsStore.hasLoaded)
        #expect(cronStore.jobs.isEmpty)
        #expect(!cronStore.hasLoaded)
        #expect(insightsStore.rows.isEmpty)
        #expect(!insightsStore.hasLoaded)
    }

    // MARK: - #310: a gateway-only profile makes no relay calls on activation
    //
    // Bars 310-C/D/E, pre-registered in OPEN_ITEMS #310 before this code.
    //
    // **These bars could not be WRITTEN before the type change, and that is
    // #310's own thesis rather than a shortcut in the RED procedure.**
    // `relayBaseURL: nil` does not compile against `main`, so "RED first
    // against main" here means RED against main-plus-the-optional-type: with
    // the type changed and the gate absent, `relaylessProfileActivation…`
    // counts 1 bootstrap register, 1 host fetch, 1 inbox fetch and 1
    // readiness call. Verified in that state before the gate landed.

    /// A plain main-actor counter box. A class so an escaping `@MainActor`
    /// closure mutates the test's own count rather than a copy.
    ///
    /// **#309 Lane C renamed it from `RelayRequestCounter` and deleted
    /// `makeCountingRelayClient`** — there is no `RelayAPIClient` left to
    /// count. See `relayBearingProfileActivationBehavesExactlyLikeAGatewayOnlyOne`
    /// for what replaced the counting.
    @MainActor
    private final class MainActorCounter {
        var count = 0
    }

    /// **309-C2/C3 — a gateway-only profile's switch REFRESHES the host plane,
    /// and does it behind the switch rather than inside it.**
    ///
    /// This is 310-C's slot, and the claim has moved twice. 310-C asserted
    /// ZERO relay requests on a relay-less activation; #309 Lane A kept that
    /// claim after deleting the relay block outright. Lane C re-homes the
    /// three deleted steps onto the gateway (`/health`), the plugin inbox
    /// cache, and `/v1/skills` — so "zero" is no longer the interesting
    /// number, and the relay counter that carried it cannot exist: the client
    /// is deleted. **What replaces it is a positive measurement** — the switch
    /// does the work again — plus the structural fact that no relay client
    /// remains to call (the tombstones, and `git grep RelayAPIClient`).
    ///
    /// The counts are polled rather than asserted straight after `await`,
    /// because the refresh is DETACHED on purpose (see the next test).
    @Test @MainActor
    func gatewayOnlyProfileActivationRefreshesTheHostPlaneAfterTheSwitch() async throws {
        let harness = await makeLaunchHarness(suiteName: "309-gateway-only-activation")
        harness.openAllGates()
        let container = harness.container

        // **The install HOLDS gateway credentials** — the fixture's own
        // precondition, asserted so the test cannot pass for the wrong reason
        // (a refresh that happens because nothing is configured proves
        // nothing). #309 Lane B re-keyed this from the two relay facts it used
        // to name: a pairing record and a relay access token, neither of which
        // exists.
        #expect(container.hasGatewayCredentials)

        await container.handleActiveProfileChanged(to: BackendProfile(
            name: "Gateway only",
            gatewayBaseURL: "http://gateway-only:8642"
        ))

        let refreshed = await pollUntil(timeout: .seconds(3)) {
            harness.hostService.fetchCallCount == 1 && harness.inboxService.fetchCallCount == 1
        }
        await container.profileSwitchRefreshTask?.value

        #expect(refreshed, "the switch must re-home host presence and the inbox onto the gateway plane")
        // 383-G: a relay-less activation asks the voice host too — that line
        // changed sides when voice moved to the talaria plugin.
        #expect(harness.voiceService.refreshReadinessCallCount == 1)
    }

    /// **309-C2's structural pin, and 309-A4's claim in the form that still
    /// has teeth** — a relay-BEARING profile's switch behaves EXACTLY like a
    /// gateway-only one.
    ///
    /// Lane A's `relayBearingProfileActivationAlsoMakesZeroRelayCalls` proved
    /// #365's residual was gone by counting relay-client requests. With the
    /// client deleted that count is zero by construction, and a test whose
    /// subject cannot exist is the "green result that proves nothing" shape
    /// arriving by deletion — the exact trap Lane A named when it retired
    /// 310-D's `isBootstrapping` sampler.
    ///
    /// So the claim is restated as the property that is now load-bearing:
    /// **`relayBaseURL` changes NOTHING about a switch.** Under the pre-Lane-A
    /// code this is #365 exactly (the relay-bearing arm ran a doomed chain the
    /// gateway-only arm skipped); under this code the two arms are
    /// indistinguishable, and this test is what would go red if a relay-shaped
    /// branch were ever reintroduced.
    @Test @MainActor
    func relayBearingProfileActivationBehavesExactlyLikeAGatewayOnlyOne() async throws {
        let harness = await makeLaunchHarness(suiteName: "309-relay-bearing-activation")
        harness.openAllGates()
        let container = harness.container

        #expect(container.hasGatewayCredentials)

        await container.handleActiveProfileChanged(to: BackendProfile(
            name: "Has a relay",
            gatewayBaseURL: "http://has-relay:8642"
        ))

        let refreshed = await pollUntil(timeout: .seconds(3)) {
            harness.hostService.fetchCallCount == 1 && harness.inboxService.fetchCallCount == 1
        }
        await container.profileSwitchRefreshTask?.value

        #expect(refreshed, "a relay-bearing switch must take the same gateway path as a gateway-only one")
        #expect(harness.voiceService.refreshReadinessCallCount == 1)

        // POSITIVE CONTROLS — the switch still switches. Without these,
        // `handleActiveProfileChanged` returning immediately would pass the
        // assertions above.
        #expect(container.chatStore.activeModelName == nil)
    }

    /// **310-D, rewritten by #309 Lane A, and the line Lane C's re-home had to
    /// keep** — the switch cannot stall on a dead host, because it does not
    /// wait for one.
    ///
    /// **The old instrument is gone with its mechanism.** 310-D sampled
    /// `sessionStore.isBootstrapping`, the switch's own clause of
    /// `shouldShowLaunchSplash`, and #365's stall was a bootstrap parked in a
    /// black hole holding it true. There is no bootstrap and no
    /// `isBootstrapping` any more, so sampling it would be sampling a
    /// constant.
    ///
    /// What replaces it is stronger and needs no sampler: **run the switch
    /// with every host gate SHUT and never opened, and require it to
    /// complete.** Under the pre-Lane-A code this is exactly #365. Under Lane
    /// A's code it was structural, because nothing on the switch touched a
    /// host at all. **Under THIS lane's code it is a live requirement again:**
    /// the switch re-homes host presence, the inbox and the catalog onto the
    /// gateway, and a black-holed gateway hangs precisely the way a
    /// black-holed relay did. Awaiting any of the three inside the handler
    /// reds this test — which is why they are detached.
    ///
    /// The gates are opened AFTER the verdict is taken, never before: a bar
    /// whose failure mode is a hang reports no verdict at all (the trap that
    /// cost 47 minutes on 2026-08-19 and put the TCC grant inside
    /// `lane-gate.sh`), so the failing arm gets a clean, terminating RED.
    @Test @MainActor
    func aProfileSwitchCompletesWithEveryHostSurfaceBlackHoled() async throws {
        let harness = await makeLaunchHarness(suiteName: "309-switch-under-blackhole")
        let container = harness.container
        // Gates deliberately NOT opened. Every host surface hangs forever.

        let completions = MainActorCounter()
        let switchTask = Task { @MainActor in
            await container.handleActiveProfileChanged(to: BackendProfile(
                name: "Has a relay",
                gatewayBaseURL: "http://has-relay:8642"
            ))
            completions.count += 1
        }

        let completed = await pollUntil(timeout: .seconds(3)) { completions.count == 1 }
        // Release the black holes so a FAILING arm terminates instead of
        // wedging the suite, then take the verdict.
        harness.openAllGates()
        await switchTask.value
        await container.profileSwitchRefreshTask?.value

        #expect(completed, "the switch did not complete against a black-holed host — #365 is back")
    }

    /// **383-G** — a profile with no relay STILL ASKS the voice host.
    ///
    /// **This replaces #310's `relaylessProfileMarksRealtimeVoiceUnavailable…`,
    /// and the replacement is the point.** That test was correct when written:
    /// voice bootstrapped over the relay (#309 paths 11–12), so a relayless
    /// profile genuinely could not ask, and `markRelayUnavailable()` was the
    /// honest answer. **#383 moved the bootstrap onto the talaria plugin, and
    /// then #310's own migration cleared `relayBaseURL` on every profile** —
    /// so the gate's else-branch became the ONLY branch and every profile
    /// switch declared realtime voice dead.
    ///
    /// The old test PINNED that behaviour, which is why nothing went red when
    /// the premise died. A test written against a mechanism outlives the
    /// mechanism unless someone goes looking.
    @Test @MainActor
    func aProfileWithNoRelayStillAsksTheVoiceHostRatherThanDeclaringItDead() async throws {
        let harness = await makeLaunchHarness(
            suiteName: "383-relayless-voice-still-asks"
        )
        harness.openAllGates()
        let container = harness.container
        harness.voiceService.readinessLandsReady = true

        await container.handleActiveProfileChanged(to: BackendProfile(
            name: "Gateway only",
            gatewayBaseURL: "http://gateway-only:8642"
        ))

        // The call counter is the load-bearing assertion: it separates "we
        // asked and the host said yes" from "we refused to ask". Against the
        // pre-fix build this reads 0 and the state below reads blocked.
        #expect(harness.voiceService.refreshReadinessCallCount == 1)
        #expect(container.talkStore.connectionState == .ready)
        #expect(container.talkStore.canStartSession)
        #expect(container.talkStore.blockedReason == nil)
    }

    /// **383-I / 310-E's surviving requirement** — a switch never leaves the
    /// PREVIOUS profile's verdict on screen.
    ///
    /// #310's failure mode is unchanged and still forbidden: switching away
    /// from a host that answered "Ready" must not keep showing that host's
    /// answer. What changed is how the requirement is met — by ASKING the new
    /// host, not by assuming the answer. This is the bar that stops 383-G's
    /// fix from degenerating into "always optimistic".
    @Test @MainActor
    func aSwitchNeverLeavesThePreviousProfilesReadinessOnScreen() async throws {
        let harness = await makeLaunchHarness(
            suiteName: "383-switch-clears-stale-readiness"
        )
        harness.openAllGates()
        let container = harness.container
        // The new host will answer UNAVAILABLE (fixture default).
        harness.voiceService.readinessLandsReady = false

        // Land a READY verdict first — the stale value the bug would keep.
        container.talkStore.connectionState = .ready
        container.talkStore.canStartSession = true
        container.talkStore.blockedReason = nil
        container.talkStore.readiness = TalkReadinessInfo(hostOnline: true, configured: true, ready: true)

        await container.handleActiveProfileChanged(to: BackendProfile(
            name: "Gateway only",
            gatewayBaseURL: "http://gateway-only:8642"
        ))

        // Asked — and this is the ONLY assertion here that the pre-fix build
        // fails, because `markRelayUnavailable()` produced a blocked state
        // indistinguishable from a blocked REFRESH. Stated rather than
        // discovered: the fixture's own doc comment records that trap.
        #expect(harness.voiceService.refreshReadinessCallCount == 1)
        #expect(container.talkStore.connectionState == .blocked)
        #expect(!container.talkStore.canStartSession)
        #expect(container.talkStore.blockedReason?.isEmpty == false)
        // Readiness returns to UNKNOWN, not to a fabricated false: we did not
        // learn the host is unconfigured, we learned we could not ask it.
        #expect(container.talkStore.readiness.ready == nil)
        #expect(container.talkStore.readiness.configured == nil)
        #expect(container.talkStore.readiness.hostOnline == nil)
        // 383-H: whatever the new blocked reason says, it must not name the
        // relay — that component is retired on both hosts.
        #expect(container.talkStore.blockedReason?.lowercased().contains("relay") != true)
    }

    /// **310-E's store half, re-keyed by #309 Lane C bar C6 — and the reason
    /// the gate is not only at the switch.** `ConnectHermesHostScreen` and
    /// `InboxScreen` each run their own `.task { await refresh()/loadInbox()
    /// }`, so a gate that lived only in `handleActiveProfileChanged` would be
    /// walked straight past by opening the tab. That argument is unchanged;
    /// what changed is the capability the gate asks about — the GATEWAY's
    /// credentials, not a relay URL.
    ///
    /// **The message half of 310-E is deliberately inverted here, and the
    /// inversion is #412's fix.** #310 required a nil host WITH a stated
    /// reason, on the argument that silence is indistinguishable from "asked,
    /// nothing there". On the gateway plane those two ARE the same state —
    /// the gateway is the host, and the plugin inbox has no other source — so
    /// the message is gone and the honest states are `.notConnected` and an
    /// empty inbox. On the Inbox that message was the whole of what Owen saw
    /// on his phone: `InboxScreen` renders any `lastErrorMessage` as
    /// "Inbox Unreachable", so a capability gate was reporting through a
    /// failure surface.
    @Test @MainActor
    func hostFedStoresRefuseToFetchAndStayHONESTWhenTheProfileHasNoGatewayCredentials() async throws {
        let hostGate = BlackHoleGate()
        hostGate.open()
        let hostService = BlackHoleHermesHostService(gate: hostGate, host: nil)
        let hostStore = HermesHostStore(
            hostService: hostService,
            hasGatewayCredentials: { false }
        )
        await hostStore.refresh()
        #expect(hostService.fetchCallCount == 0)
        #expect(hostStore.currentHost == nil)
        // NOT an error state: "you have not set a host up" is `.notConnected`
        // ("No Host / Set up from your Hermes machine"), never `.unreachable`.
        #expect(hostStore.lastErrorMessage == nil)
        #expect(hostStore.connectionState == .notConnected)

        let defaults = UserDefaults(suiteName: "309-credential-less-inbox")!
        defaults.removePersistentDomain(forName: "309-credential-less-inbox")
        let persistence = UserDefaultsAppPersistenceStore(defaults: defaults)
        let inboxGate = BlackHoleGate()
        inboxGate.open()
        let inboxService = BlackHoleInboxService(gate: inboxGate)
        let inboxStore = InboxStore(
            inboxService: inboxService,
            persistence: persistence,
            hasGatewayCredentials: { false }
        )
        await inboxStore.loadInbox(force: true)
        #expect(inboxService.fetchCallCount == 0)
        // 309-C6's pin, and the direct answer to #412: a credential-less
        // profile lands on the EMPTY state, not on "COULD NOT REACH THE …".
        // `InboxScreen` branches on `lastErrorMessage != nil`, so this one
        // assertion is what separates the two screens the user sees.
        #expect(inboxStore.lastErrorMessage == nil)
        #expect(inboxStore.items.isEmpty)
    }

    /// **The regression #310's own gate caught, re-keyed with the gate.**
    ///
    /// A gated `refresh()` must not announce a host CHANGE on every call.
    /// `onHostChanged` does real main-actor work — `updateWidgetData()` writes
    /// the App Group container and a command-catalog Task is spawned
    /// (`AppContainer.makeDefault`) — and
    /// `ChatScreen.monitorConnectionStatus()` polls `refresh()` on a cadence
    /// the whole time chat is on screen. The first version of the #310 guard
    /// fired the hook unconditionally, which turned an idle chat screen on a
    /// gateway-only profile into periodic App Group I/O and stalled a
    /// streaming turn past its 40 s budget
    /// (`testQueuedChipCancelRemovesHeldMessageWithNothingPosted`).
    ///
    /// **Note what did NOT catch it:** 2357 unit tests (they call `refresh()`
    /// once), a clean Release build, and an isolated re-run of the failing
    /// UI test — which PASSED, and would have licensed calling it a #236
    /// flake. Only a control gate with the lane's code stashed separated the
    /// two. This test exists so the next reader gets the cheap version.
    @Test @MainActor
    func gatedRefreshAnnouncesAHostChangeOnlyOnATransition() async throws {
        let gate = BlackHoleGate()
        gate.open()
        let hostService = BlackHoleHermesHostService(
            gate: gate,
            host: HermesHostStatus(
                id: UUID(), displayName: "OJAMD", hostname: "ojamd.test",
                platform: "windows", connectorVersion: "1.0.0",
                hermesCommand: "hermes", hermesVersion: "1.0.0", hermesModel: nil,
                lastSeenAt: .now, lastConnectedAt: .now, isOnline: true
            )
        )
        var hasCredentials = true
        let store = HermesHostStore(
            hostService: hostService,
            hasGatewayCredentials: { hasCredentials }
        )

        let changes = MainActorCounter()
        store.onHostChanged = { changes.count += 1 }

        // A credentialed refresh lands a host and announces it.
        await store.refresh()
        #expect(store.currentHost != nil)
        #expect(changes.count == 1)

        // The profile loses its credentials: ONE transition (host → nil) is news.
        hasCredentials = false
        await store.refresh()
        #expect(store.currentHost == nil)
        #expect(changes.count == 2)

        // Every subsequent poll is NOT news. This is the bar: the count must
        // stay put across many ticks, which is what the chat screen does.
        for _ in 0..<10 {
            await store.refresh()
        }
        #expect(changes.count == 2)
        #expect(store.lastErrorMessage == nil)
        // And the host was never actually asked, across all of it.
        #expect(hostService.fetchCallCount == 1)
    }

    /// Positive control for the store gate — with gateway credentials, both
    /// fetch. Without this, deleting the fetches would pass the tests above.
    ///
    /// **This is also 309-C6's other half, and the one Owen's device needed:**
    /// a profile that has a gateway and a key gets its WORKING plugin inbox.
    /// Under the pre-lane gate this arm asserted `hasRelay`, which #310's own
    /// migration had cleared on every profile — so the inbox was starved on
    /// every install and the control could not see it.
    @Test @MainActor
    func hostFedStoresStillFetchWhenTheProfileHasGatewayCredentials() async throws {
        let hostGate = BlackHoleGate()
        hostGate.open()
        let hostService = BlackHoleHermesHostService(gate: hostGate, host: nil)
        let hostStore = HermesHostStore(
            hostService: hostService,
            hasGatewayCredentials: { true }
        )
        await hostStore.refresh()
        #expect(hostService.fetchCallCount == 1)
        #expect(hostStore.lastErrorMessage == nil)

        let defaults = UserDefaults(suiteName: "309-credentialed-inbox")!
        defaults.removePersistentDomain(forName: "309-credentialed-inbox")
        let persistence = UserDefaultsAppPersistenceStore(defaults: defaults)
        let inboxGate = BlackHoleGate()
        inboxGate.open()
        let inboxService = BlackHoleInboxService(gate: inboxGate)
        let inboxStore = InboxStore(
            inboxService: inboxService,
            persistence: persistence,
            hasGatewayCredentials: { true }
        )
        await inboxStore.loadInbox(force: true)
        #expect(inboxService.fetchCallCount == 1)
        #expect(inboxStore.items.isEmpty == false)
        #expect(inboxStore.lastErrorMessage == nil)
    }

    // MARK: - #309 row 16's adapt: the composer's catalog on `/v1/skills` (309-C3)

    /// **309-C3** — the composer's catalog is built from the HOST'S SKILLS
    /// merged with the built-ins, through the same `SkillsStore` the Skills
    /// browser reads.
    ///
    /// RED against `main`: there, `performCommandCatalogRefresh` builds a
    /// `RelayAPIClient` and asks the relay for `commands`, so a fixture skills
    /// store changes nothing about the catalog.
    ///
    /// **Personalities and quick commands are the RULED accepted loss
    /// (2026-08-19) and this test pins the honest degradation** — the catalog
    /// gains exactly the built-ins plus the skills, and nothing invents a row
    /// for a plane that no longer answers.
    @Test @MainActor
    func commandCatalogMergesTheHostsSkillsWithTheBuiltIns() async throws {
        let harness = await makeLaunchHarness(
            suiteName: "309-catalog-skills-\(UUID().uuidString)"
        )
        harness.openAllGates()
        let container = harness.container

        let skillsService = SkillsStoreTests.FixtureSkillsService()
        skillsService.listResult = .success([
            Skill(name: "deploy", description: "Ship the current branch", category: "Ops")
        ])
        container.skillsStore = SkillsStore(service: skillsService)

        await container.refreshCommandCatalog(force: true)

        let skillCommand = SlashCommand.fromSkill(name: "deploy", description: "Ship the current branch")
        #expect(container.chatStore.commandCatalog.contains { $0.id == skillCommand.id })
        // The built-ins survive the merge — the skills are added to
        // `localCommands`, never a replacement for them.
        for local in SlashCommand.localCommands {
            #expect(container.chatStore.commandCatalog.contains { $0.id == local.id })
        }
        // Nothing beyond built-ins + the one skill: no personality row, no
        // quick-command row, no placeholder for either.
        #expect(container.chatStore.commandCatalog.count == SlashCommand.localCommands.count + 1)
    }

    /// **309-C3's failure arm** — a catalog refresh that FAILS keeps the
    /// built-ins on screen and must not demote the CTX denominator.
    ///
    /// #4's rule, carried over from the relay implementation verbatim: the
    /// host is offline by design much of the time, and a transient fetch
    /// failure that reset `contextWindow` would swap a host-reported value for
    /// the nominal client-side table without anything on screen changing.
    @Test @MainActor
    func aFailedCatalogRefreshKeepsBuiltInsAndTheHostReportedContextWindow() async throws {
        let harness = await makeLaunchHarness(
            suiteName: "309-catalog-failure-\(UUID().uuidString)"
        )
        harness.openAllGates()
        let container = harness.container

        container.chatStore.replaceCommandCatalog(
            SlashCommand.localCommands,
            activeModel: "kimi-k2",
            contextWindow: 262_144
        )

        let skillsService = SkillsStoreTests.FixtureSkillsService()
        skillsService.listResult = .failure(SkillsServiceError.timeout)
        container.skillsStore = SkillsStore(service: skillsService)

        await container.refreshCommandCatalog(force: true)

        #expect(container.chatStore.commandCatalog == SlashCommand.allBuiltIn)
        #expect(container.chatStore.activeModelName == "kimi-k2")
        #expect(container.chatStore.contextWindow == 262_144)
    }

    /// **309-C3's capability gate** — no gateway credentials, no catalog
    /// fetch, and no reset of what is already on screen.
    ///
    /// The catalog is a gateway read now, so it asks the gateway's own
    /// question (#411/Lane A's predicate). Resetting here instead of returning
    /// would blank a hostless install's composer on every foreground.
    @Test @MainActor
    func aHostlessInstallDoesNotFetchOrResetTheCommandCatalog() async throws {
        let harness = await makeLaunchHarness(
            suiteName: "309-catalog-hostless-\(UUID().uuidString)",
            gatewayCredentials: false
        )
        harness.openAllGates()
        let container = harness.container

        container.chatStore.replaceCommandCatalog(
            SlashCommand.localCommands,
            activeModel: "local",
            contextWindow: 4096
        )

        let skillsService = SkillsStoreTests.FixtureSkillsService()
        skillsService.listResult = .success([Skill(name: "deploy", description: nil, category: nil)])
        container.skillsStore = SkillsStore(service: skillsService)

        await container.refreshCommandCatalog(force: true)

        #expect(skillsService.listCallCount == 0)
        #expect(container.chatStore.activeModelName == "local")
        #expect(container.chatStore.contextWindow == 4096)
    }

    @Test @MainActor
    func bootstrapProbeSessionUsesShortTimeouts() {
        // #136 non-negotiable 4: launch/bootstrap probes must converge in
        // seconds against a black-holed host (firewall DROP → no TCP
        // refusal → the full request timeout, -1001) — never URLSession's
        // default 60s.
        // #309 Lane C: the budget moved out of the deleted `RelayAPIClient`
        // into `BootstrapProbeSession`, unchanged. Its reader is now the
        // gateway host probe — same probe class, same hazard.
        let session = BootstrapProbeSession.make()
        #expect(session.configuration.timeoutIntervalForRequest == BootstrapProbeSession.requestTimeout)
        #expect(session.configuration.timeoutIntervalForResource == BootstrapProbeSession.resourceTimeout)
        #expect(session.configuration.timeoutIntervalForRequest <= 5)
        #expect(session.configuration.waitsForConnectivity == false)
    }

    @Test @MainActor
    func launchCriticalPathIsLocalOnly() {
        // #136 non-negotiable 1: nothing before `isInitialized = true` may
        // touch the network — the splash drops on local-state-ready.
        for step in AppContainer.LaunchInitStep.criticalPath {
            #expect(!step.touchesNetwork, "critical-path step \(step) must not touch the network")
        }

        // The #123 share drain stays on the critical path, before any
        // relay-gated work (#136 non-negotiable 6).
        #expect(AppContainer.LaunchInitStep.criticalPath.contains(.drainShareInbox))

        // The partition is total: every step lives in exactly one list.
        let partitioned = AppContainer.LaunchInitStep.criticalPath
            + AppContainer.LaunchInitStep.backgroundLaunchRefresh
        #expect(partitioned.count == AppContainer.LaunchInitStep.allCases.count)
        #expect(Set(partitioned) == Set(AppContainer.LaunchInitStep.allCases))

        // #309 Lane A: the #3/#46 ordering assertion that stood here
        // (`.sessionBootstrap` strictly before `.validateRestoredIdentity`)
        // is gone with both of its operands. The constraint was real — an
        // identity check that ran before the session loaded compared against
        // nothing — but there is no session load left to order against, and a
        // `firstIndex(of:)` pair on two absent cases would pass vacuously,
        // which is worse than not asserting it.
    }

    @Test @MainActor
    func backgroundLaunchRefreshHasNoGhostSteps() {
        // #287: the list must literal-match what `runBackgroundLaunchRefresh`
        // actually executes. `pushTokenRegistration` sat here for six days
        // after #238 deleted push registration wholesale, and NOTHING caught
        // it — the partition check above compares against `allCases`, which
        // shrinks by exactly one when a ghost is removed, so it is true both
        // with and without one. Only a literal pin can see this.
        //
        // This test is exactly why #309 Lane A had to edit the enum rather
        // than leave two dead cases in it: `.sessionBootstrap` and
        // `.validateRestoredIdentity` would have become ghosts the moment
        // their steps left the function.
        //
        // Order is significant; do not loosen this to `Set` equality to make
        // a future step's friction go away — that friction is the point.
        #expect(AppContainer.LaunchInitStep.backgroundLaunchRefresh == [
            .hostRefresh, .inboxLoad, .commandCatalogRefresh, .gatewayModelSeed,
        ])
    }

    // MARK: - #369, re-keyed by #411: an unreadable credential is a HOLD
    //
    // The MECHANISM is unchanged — hold the network half, name the hold, retry
    // when the credential lands. What #309 Lane A changed is WHICH credential:
    // the relay access token is no longer read by anything at launch, so the
    // hold now waits on the ACTIVE PROFILE'S GATEWAY CREDENTIALS, which arrive
    // asynchronously from the Keychain and not at all before first unlock.

    /// **369-A.** The launch path used to answer a nil credential by calling
    /// `clearLocalPairing()` — a destructive answer to a reading that cannot
    /// distinguish "no item" from "Keychain locked" (`KeychainSecureStore`
    /// collapses every non-`errSecSuccess` OSStatus into nil). Its own three
    /// siblings — foreground activation, system launch, background refresh —
    /// all logged BLOCKED and returned; only this one destroyed.
    ///
    /// Mutation that must turn this RED: make `initialize()`'s hold branch
    /// clear the profile's gateway credentials instead of holding.
    ///
    /// **#309 Lane B re-pointed the subject from the relay pairing record to
    /// the profile's ENDPOINT.** The defect is unchanged and so is its shape —
    /// a credential the Keychain would not hand over must never be read as
    /// "the user unpaired" — but what a launch could destroy is now the
    /// profile that names the host, not a redeemed record.
    @Test @MainActor
    func anUnreadableCredentialAtLaunchNeverDestroysTheHost() async {
        let harness = await makeLaunchHarness(
            suiteName: "369-hold-\(UUID().uuidString)",
            seedAccessToken: false,
            gatewayCredentials: false
        )
        let container = harness.container
        let hostBefore = container.profilesStore?.activeProfile?.gatewayBaseURL

        await container.initialize()

        #expect(container.credentialsUnreadableHold,
                "fixture precondition: the launch HELD rather than proceeding")
        #expect(container.profilesStore?.activeProfile?.gatewayBaseURL == hostBefore,
                "an unreadable credential slot must never forget a healthy host")
    }

    /// **369-B.** The obvious fix — stop clearing, return early — ships a worse
    /// bug: `shouldShowLaunchSplash` is `isPaired && !isInitialized`, and
    /// `initialize()` has exactly one caller, so a paired install would sit on
    /// the full-screen splash for the process's whole life. The local critical
    /// path is credential-free by design (#136), so it runs; only the
    /// host-backed half is deferred, and the hold is NAMED rather than silent.
    @Test @MainActor
    func anUnreadableCredentialHoldsTheHostHalfWithoutStrandingTheSplash() async {
        let harness = await makeLaunchHarness(
            suiteName: "369-splash-\(UUID().uuidString)",
            seedAccessToken: false,
            gatewayCredentials: false
        )
        let container = harness.container

        await container.initialize()

        #expect(container.shouldShowLaunchSplash == false,
                "the launch splash must drop — a held credential is not a reason to hide the app forever")
        #expect(container.credentialsUnreadableHold,
                "the hold must be named in state so it can be surfaced (#180) and retried")

        // Bounded window rather than a bare read: `startBackgroundLaunchRefresh`
        // spawns a Task, so "it never started" is only honest if it survives
        // the spawn. The host fetch counter increments BEFORE the black-hole
        // gate, so a started refresh is visible here even with the gate closed.
        let hostHalfRan = await pollUntil(timeout: .milliseconds(300)) {
            harness.hostService.fetchCallCount > 0
        }
        #expect(hostHalfRan == false,
                "the host-backed half must not run on a credential the app could not read")
    }

    /// **369-C.** A hold that is never retried is just a quieter stall. Once
    /// the credential reads — the post-first-unlock case the existing
    /// `protectedDataDidBecomeAvailable` / `didBecomeActive` hooks exist for —
    /// the hold clears and the host half runs, exactly once.
    @Test @MainActor
    func theCredentialHoldIsRetriedOnceTheCredentialBecomesReadable() async {
        let credentialsReadable = MainActorCounter()  // 0 = not yet readable
        let harness = await makeLaunchHarness(
            suiteName: "369-retry-\(UUID().uuidString)",
            seedAccessToken: false,
            gatewayCredentials: false
        )
        let container = harness.container
        container.gatewayCredentialsProbe = { credentialsReadable.count > 0 }
        harness.openAllGates()
        await container.initialize()
        #expect(container.credentialsUnreadableHold, "fixture precondition: the launch held")

        // First unlock: the gateway credentials become readable.
        credentialsReadable.count = 1
        await container.retryCredentialHoldIfNeeded()

        #expect(container.credentialsUnreadableHold == false,
                "a readable credential must clear the hold")
        let hostHalfRan = await pollUntil { harness.hostService.fetchCallCount > 0 }
        #expect(hostHalfRan, "the deferred host-backed half must actually run on retry")

        // Single-flight: a second retry (both hooks fire on one unlock) must
        // not start a second refresh.
        await container.retryCredentialHoldIfNeeded()
        #expect(harness.hostService.fetchCallCount == 1, "a second retry must not double-run the host half")
    }

    /// **369-D / #411's mirror of 369-B.** A held launch is not a dead one:
    /// the LOCAL critical path completes and the app is fully usable. This is
    /// the assertion that makes the hold honest rather than a quieter version
    /// of the `isPaired` gate it replaced — and it is exactly what a hostless
    /// install (the launch pivot's DEFAULT user) gets on every launch.
    @Test @MainActor
    func aHeldLaunchStillFinishesTheLocalCriticalPath() async {
        let harness = await makeLaunchHarness(
            suiteName: "411-held-launch-local-\(UUID().uuidString)",
            seedAccessToken: false,
            gatewayCredentials: false
        )
        let container = harness.container
        let widgetBefore = SharedWidgetDataStore.read().updatedAt

        await container.initialize()

        #expect(container.credentialsUnreadableHold, "fixture precondition: the launch held")
        // `isInitialized` is private; `shouldShowLaunchSplash` is its one
        // observable consequence on a paired install and reads false only
        // once the critical path set it.
        #expect(container.shouldShowLaunchSplash == false)
        #expect(container.chatStore.conversation != nil, "loadConversationIfNeeded must have run")
        #expect(SharedWidgetDataStore.read().updatedAt != widgetBefore, "updateWidgetData must have run")
    }

    @Test @MainActor
    func foregroundWritesWidgetSnapshotEvenWhenTheNetworkChainNeverCompletes() async throws {
        // #145 Part B — THE regression pin for the property that forced a phone
        // restart. `reconcileLiveActivities()` and `updateWidgetData()` were
        // sequenced LAST in `handleAppDidBecomeActive`, behind ~8 network awaits.
        // So the app could not refresh its visible state until the whole chain
        // drained, and sat frozen on stale content for MINUTES after the host was
        // healthy again. That is the difference between "the app is slow" and
        // "the app is broken and I restarted my phone."
        //
        // Both writes are synchronous, local and idempotent (verified: they read
        // store state into SharedWidgetDataStore / LiveActivityService and touch
        // no network), so hoisting them costs nothing and gates nothing.
        let harness = await makeLaunchHarness(
            suiteName: "foreground-uiwrite-\(UUID().uuidString)"
        )
        let container = harness.container

        // A marker no other suite can produce. SharedWidgetDataStore is REAL
        // app-group UserDefaults shared process-wide, so asserting on a bare
        // "did it write" would pass on another test's write — #183's shape.
        let marker = "t27-145-partB-\(UUID().uuidString)"
        container.chatStore.conversation = Conversation(
            title: "Hermes",
            messages: [Message(sender: .hermes, content: marker, status: .delivered)]
        )

        // Gates stay CLOSED. `hostStore.refresh()` is step 2 of the chain and
        // never returns — the black-holed-host shape from #136.
        let activation = Task { @MainActor in await container.handleAppDidBecomeActive() }

        let wroteWhileBlocked = await pollUntil {
            (SharedWidgetDataStore.read().lastMessagePreview ?? "").contains(marker)
        }
        #expect(wroteWhileBlocked,
                "the widget snapshot must be written without waiting for the network chain to drain")

        // Proves the chain really was blocked — otherwise this test would pass
        // for the wrong reason on a build where the fetch returned instantly.
        //
        // #389: this POLLS rather than asserting at an instant, and the
        // difference is the whole of that entry. The widget write is
        // deliberately hoisted AHEAD of the network chain
        // (`AppContainer.swift:1633`), and TWO awaits — `reconcilePendingRuns()`
        // and `reloadCapabilities()` — sit between it and `hostStore.refresh()`.
        // So observing the write says nothing yet about the fetch: this poller
        // and the activation share the MainActor, and the poller can win.
        //
        // **Raising `pollUntil`'s timeout would NOT have been a fix** (389-A):
        // it changes how often the race is lost, not whether it exists. And
        // the guard keeps its meaning (389-B) — on a build where
        // `hostStore.refresh()` returns without ever being reached, this still
        // fails, it just fails for the real reason instead of for a schedule.
        let reachedTheFetch = await pollUntil { harness.hostService.fetchCallCount > 0 }
        #expect(reachedTheFetch,
                "the activation never reached the host fetch, so nothing was actually blocked")

        harness.openAllGates()
        await activation.value
    }

    /// **#389 — the race, made a deterministic FACT rather than a flake.**
    ///
    /// The test above used to assert `fetchCallCount > 0` at the instant the
    /// widget write became observable. That passed most of the time and failed
    /// on 2026-08-21 when an unrelated lane perturbed suite timing — which is
    /// the signature of a race, not of a defect in the lane that exposed it.
    ///
    /// This pins the ordering directly instead of racing it. With the health
    /// service HELD OPEN, the activation is provably parked inside
    /// `reloadCapabilities()` — after the hoisted UI writes, before
    /// `hostStore.refresh()`. So at that moment the widget snapshot is
    /// **written** and the fetch has **not happened**, every run, on any
    /// machine.
    ///
    /// It is therefore two things at once: the reproduction 389-C demanded
    /// before any fix, and a permanent positive pin on #145 Part B's actual
    /// property — *the visible state is refreshed before the network chain is
    /// touched.* The old test could only ever assert that indirectly.
    @Test @MainActor
    func theWidgetWriteLandsBeforeTheHostFetchIsEvenReached() async throws {
        let healthGate = BlackHoleGate()
        let harness = await makeLaunchHarness(
            suiteName: "389-ordering-\(UUID().uuidString)",
            healthService: GatedHealthService(gate: healthGate)
        )
        let container = harness.container

        let marker = "t27-389-ordering-\(UUID().uuidString)"
        container.chatStore.conversation = Conversation(
            title: "Hermes",
            messages: [Message(sender: .hermes, content: marker, status: .delivered)]
        )

        let activation = Task { @MainActor in await container.handleAppDidBecomeActive() }

        let wroteWhileParked = await pollUntil {
            (SharedWidgetDataStore.read().lastMessagePreview ?? "").contains(marker)
        }
        #expect(wroteWhileParked, "the hoisted widget write did not land")

        // 🔴 The assertion the old test could not make safely. The chain is
        // HELD inside reloadCapabilities(), so this is not "the fetch hasn't
        // happened yet, probably" — it is "the fetch cannot have happened."
        #expect(harness.hostService.fetchCallCount == 0,
                "the host fetch ran before/while capabilities were still loading — the #145 Part B hoist has moved")

        // Releasing the park lets the chain continue, and the fetch is then
        // reachable — which is what makes the count above an ORDERING fact
        // rather than a broken-chain artifact.
        healthGate.open()
        let reachedTheFetch = await pollUntil { harness.hostService.fetchCallCount > 0 }
        #expect(reachedTheFetch, "after the park was released the chain never reached the fetch")

        harness.openAllGates()
        activation.cancel()
        await activation.value
    }

    @Test
    func testRunsAreDetectedFromEitherFlavourOfTestEnvironment() {
        // #144. XCTest sets `XCTestConfigurationFilePath` in the process it
        // HOSTS — that covers unit tests. A UI test runs the app as a SEPARATE
        // process which never sees it, so the `UITEST_` prefix the target
        // already uses is the only signal available there.
        #expect(TestRunGuard.isRunningUnderTest(["XCTestConfigurationFilePath": "/tmp/x.xctestconfiguration"]))
        #expect(TestRunGuard.isRunningUnderTest(["UITEST_DEFAULTS_SUITE": "suite-1"]))
        #expect(TestRunGuard.isRunningUnderTest(["UITEST_ANYTHING_AT_ALL": "1"]))
        #expect(TestRunGuard.isRunningUnderTest(["HOME": "/Users/owen"]) == false)
        #expect(TestRunGuard.isRunningUnderTest([:]) == false)
    }

    @Test
    func aShippedBuildCannotBeTalkedOutOfLivePairingByAnEnvironmentVariable() {
        // #144's safety property. Detecting a test run is a DIAGNOSTIC
        // convenience; it must never become a production off-switch. With
        // environment overrides disallowed — a shipped build — the detection is
        // ignored outright.
        let testish = ["XCTestConfigurationFilePath": "/tmp/x", "UITEST_DEFAULTS_SUITE": "s"]

        #expect(TestRunGuard.mustUseMockPairing(
            environment: testish, explicitMockRequested: false, allowsEnvironmentOverrides: false) == false)

        #expect(TestRunGuard.mustUseMockPairing(
            environment: testish, explicitMockRequested: false, allowsEnvironmentOverrides: true))

        // The pre-existing UITEST_PAIRING_MODE contract keeps working unchanged.
        #expect(TestRunGuard.mustUseMockPairing(
            environment: [:], explicitMockRequested: true, allowsEnvironmentOverrides: true))

        // A clean environment on a dev build still gets the LIVE service —
        // otherwise this guard would break real pairing on the simulator.
        #expect(TestRunGuard.mustUseMockPairing(
            environment: ["HOME": "/Users/owen"], explicitMockRequested: false, allowsEnvironmentOverrides: true) == false)
    }

    @Test @MainActor
    func aForegroundActivationCannotOutliveItsSharedDeadline() async throws {
        // #145 Part E(a) — ONE shared deadline around the whole chain.
        //
        // Part A bounded each CALL (20s interactive). It did not bound the
        // SUM: ten guarded awaits plus `refreshDormantProfileTokensIfNeeded`'s
        // serial N-loop, so a degraded host could still hold an activation for
        // minutes while every individual call behaved. E(a) caps the total.
        //
        // Deliberately NOT a stopwatch assertion (the spec forbids it, and
        // #183 is what that lands in). The pin is BEHAVIOURAL: against a
        // dependency that never answers, the activation RETURNS and says it
        // was cut short. Without the deadline it never returns at all — so
        // this is written with a settle box and a bounded poll, which FAILS
        // cleanly rather than hanging the suite.
        let harness = await makeLaunchHarness(
            suiteName: "foreground-deadline-\(UUID().uuidString)"
        )
        let container = harness.container
        container.foregroundActivationBudget = .milliseconds(150)

        // Gates CLOSED — the chain parks on the host fetch and cannot finish.
        let returned = MutableBox(false)
        let activation = Task { @MainActor in
            await container.handleAppDidBecomeActive()
            returned.value = true
        }

        let settled = await pollUntil(timeout: .seconds(5)) { returned.value }
        #expect(settled, "the activation never returned — the shared deadline did not bound the chain")
        #expect(container.foregroundActivationsCutShort == 1,
                "the deadline fired but was not recorded — a silent cut is indistinguishable from a fast success")

        harness.openAllGates()
        await activation.value
    }

    @Test @MainActor
    func aHealthyActivationIsNeverCutShort() async throws {
        // The other half of the pin, and the one that stops the deadline from
        // becoming a bug of its own: a chain that completes normally must
        // finish on its own terms and record NO cut. A deadline that fires on
        // healthy runs would silently truncate real refreshes — worse than the
        // slow chain it replaced.
        let harness = await makeLaunchHarness(
            suiteName: "foreground-deadline-healthy-\(UUID().uuidString)"
        )
        let container = harness.container
        harness.openAllGates()

        await container.handleAppDidBecomeActive()

        #expect(container.foregroundActivationsCutShort == 0)
    }

    @Test @MainActor
    func foregroundActivationsSupersedeRatherThanStack() async throws {
        // #145 Part D. Every scene activation queued another full twelve-await
        // chain, and nothing coalesced or superseded. Under an outage that
        // multiplies the wedge by however many times the user tried to wake the
        // app — which is exactly what a person does when an app looks frozen.
        // The bug got WORSE the more the user fought it.
        //
        // The pin is peak concurrency, not a call count: two activations both
        // legitimately touch the host, so counting fetches cannot tell
        // "superseded" from "stacked". Peak can.
        let harness = await makeLaunchHarness(
            suiteName: "foreground-supersede-\(UUID().uuidString)"
        )
        let container = harness.container

        // Gates CLOSED — chain one parks on the host fetch and cannot finish.
        let first = Task { @MainActor in await container.handleAppDidBecomeActive() }
        let firstEntered = await pollUntil { container.liveForegroundActivations >= 1 }
        #expect(firstEntered, "the first activation never started")

        // Second activation arrives while the first is still parked.
        let second = Task { @MainActor in await container.handleAppDidBecomeActive() }
        _ = await pollUntil { container.peakConcurrentForegroundActivations > 1 }

        #expect(container.peakConcurrentForegroundActivations == 1,
                "two foreground chains ran at once — activations are stacking (\(container.peakConcurrentForegroundActivations) live at peak)")

        harness.openAllGates()
        await first.value
        await second.value

        // Nothing is left running once both callers return.
        let settled = await pollUntil { container.liveForegroundActivations == 0 }
        #expect(settled, "an activation chain outlived its caller")
    }

    @Test @MainActor
    func blackHoledHostDoesNotHoldTheLaunchSplash() async throws {
        let harness = await makeLaunchHarness(
            suiteName: "launch-blackhole-\(UUID().uuidString)"
        )
        let container = harness.container
        #expect(container.shouldShowLaunchSplash)

        let initTask = Task { @MainActor in await container.initialize() }

        // The splash must drop on local-state-ready — with every host
        // surface still black-holed (#136 non-negotiable 1/7).
        let splashDropped = await pollUntil { !container.shouldShowLaunchSplash }
        #expect(splashDropped, "splash must drop without awaiting the black-holed host")

        // Nothing host-backed has landed yet.
        #expect(container.hostStore.currentHost == nil)
        #expect(container.inboxStore.items.isEmpty)

        // Host comes back: the background launch refresh lands state live.
        harness.openAllGates()
        let backgroundLanded = await pollUntil {
            container.hostStore.isHostOnline && !container.inboxStore.items.isEmpty
        }
        #expect(backgroundLanded, "the background half must land host + inbox state once the host answers")

        // #309 Lane A: this test used to end by proving
        // `bootstrap → validateRestoredIdentity` ordering, via a black-hole
        // service that reported a DIFFERENT relay user than the pairing
        // minted. Both halves of that are deleted; the flag can no longer be
        // raised on this path, so asserting it stays false would be asserting
        // that nothing writes it — a tautology, not a pin. The identity
        // check itself keeps its own direct pin in
        // `validateRestoredIdentityFlagsResurrectedStaleUser`.

        await initTask.value
    }

    /// **#411's launch-half pin.** A hostless install runs the WHOLE local
    /// critical path on cold launch — the case that ran none of it before,
    /// because `initialize()` opened with `guard pairingStore.isPaired`.
    ///
    /// Mutation that must turn this RED: put any gate —
    /// `hasGatewayCredentials`, or anything else — back in front of the local
    /// block in `initialize()`.
    @Test @MainActor
    func aHostlessInstallStillRunsTheWholeLocalCriticalPathAtLaunch() async throws {
        let harness = await makeLaunchHarness(
            suiteName: "411-hostless-launch-\(UUID().uuidString)",
            gatewayCredentials: false
        )
        let container = harness.container
        // The hostless shape — the install the four gates locked out entirely.
        // `gatewayCredentials: false` above is what makes it hostless; this
        // line asserts it rather than arranging it, because a fixture that
        // silently became host-bearing would make every claim below vacuous.
        #expect(container.hasGatewayCredentials == false,
                "fixture precondition: no host is configured")

        let widgetBefore = SharedWidgetDataStore.read().updatedAt
        await container.initialize()

        #expect(container.chatStore.conversation != nil,
                "loadConversationIfNeeded must run for an unpaired install (#411)")
        #expect(SharedWidgetDataStore.read().updatedAt != widgetBefore,
                "updateWidgetData must run for an unpaired install (#411)")
        // A second initialize() is a no-op — the re-entry guard is the only
        // thing that may short-circuit the local path, and it only can once
        // the path has actually completed.
        await container.initialize()
        #expect(harness.hostService.fetchCallCount == 0,
                "a hostless install must still make no host calls")
    }

    /// **#411's foreground-half pin**, and the sibling of the launch one
    /// above: a hostless install refreshes its LOCAL state on every
    /// foreground, and asks no host anything.
    @Test @MainActor
    func aHostlessInstallStillRefreshesLocalStateOnForeground() async throws {
        let harness = await makeLaunchHarness(
            suiteName: "411-hostless-foreground-\(UUID().uuidString)",
            gatewayCredentials: false
        )
        let container = harness.container
        #expect(container.hasGatewayCredentials == false,
                "fixture precondition: no host is configured")
        let widgetBefore = SharedWidgetDataStore.read().updatedAt

        await container.handleAppDidBecomeActive()

        #expect(SharedWidgetDataStore.read().updatedAt != widgetBefore,
                "the hoisted widget write must run with no host configured (#145 Part B × #411)")
        // The host half stayed shut — and this is what makes the test a gate
        // check rather than a "does anything happen" check.
        #expect(harness.hostService.fetchCallCount == 0)
        #expect(harness.voiceService.refreshReadinessCallCount == 0,
                "voice readiness is host-backed and must stay behind the capability gate")
    }

    /// The POSITIVE CONTROL for both #411 pins above: with gateway
    /// credentials present, the host half still runs. Without this, deleting
    /// the host-backed work outright would pass every zero asserted above.
    @Test @MainActor
    func aCredentialedInstallStillRunsTheHostHalfOnForeground() async throws {
        let harness = await makeLaunchHarness(
            suiteName: "411-credentialed-foreground-\(UUID().uuidString)"
        )
        harness.openAllGates()
        let container = harness.container

        await container.handleAppDidBecomeActive()

        #expect(harness.hostService.fetchCallCount >= 1)
        #expect(harness.voiceService.refreshReadinessCallCount >= 1)
    }

    @Test @MainActor
    func launchRefreshIsSingleFlight() async throws {
        let harness = await makeLaunchHarness(
            suiteName: "launch-singleflight-\(UUID().uuidString)"
        )
        let container = harness.container

        let first = Task { @MainActor in await container.initialize() }
        let second = Task { @MainActor in await container.initialize() }

        let refreshStarted = await pollUntil { harness.hostService.fetchCallCount >= 1 }
        #expect(refreshStarted)

        harness.openAllGates()
        await first.value
        await second.value
        let settled = await pollUntil { container.hostStore.isHostOnline }
        #expect(settled)

        #expect(harness.hostService.fetchCallCount == 1, "concurrent initialize() must run the host half once")
    }

    @Test @MainActor
    func resetDuringBackgroundInitLandsNoStaleState() async throws {
        let harness = await makeLaunchHarness(
            suiteName: "launch-resetrace-\(UUID().uuidString)"
        )
        let container = harness.container
        // The HOST probe is the in-flight black hole the reset must supersede
        // (it is the first step of the background half since #309 Lane A).

        let initTask = Task { @MainActor in await container.initialize() }
        let hostProbeInFlight = await pollUntil { harness.hostService.fetchCallCount >= 1 }
        #expect(hostProbeInFlight)

        // Unpair while the host probe hangs (#136 non-negotiable 5 — the
        // reset site must cancel/supersede in-flight background init).
        await container.handleHostDisconnected()

        harness.openAllGates()
        await initTask.value
        // Give any stray continuation a beat to (incorrectly) land.
        try? await Task.sleep(for: .milliseconds(200))

        #expect(container.hostStore.currentHost == nil, "no stale host state may land after reset")
        #expect(container.hostStore.lastErrorMessage == nil, "a cancelled probe must not smear an error over reset state")
        #expect(container.inboxStore.items.isEmpty, "no stale inbox items may land after reset")
    }

    @Test @MainActor
    func rePairSupersedesInFlightBackgroundInit() async throws {
        let harness = await makeLaunchHarness(
            suiteName: "launch-repair-\(UUID().uuidString)"
        )
        let container = harness.container

        let initTask = Task { @MainActor in await container.initialize() }
        let refreshStarted = await pollUntil { harness.hostService.fetchCallCount >= 1 }
        #expect(refreshStarted)

        // Re-pair while the first host probe hangs black-holed (#136
        // non-negotiable 5 — the reset site supersedes, and the fresh
        // initialize() must actually re-run the host half rather than
        // silently skipping it on the single-flight gate).
        let rePairTask = Task { @MainActor in await container.handleHostConnected() }
        let secondRefreshStarted = await pollUntil { harness.hostService.fetchCallCount >= 2 }
        #expect(secondRefreshStarted, "re-pair must supersede the in-flight refresh and run a fresh one")

        harness.openAllGates()
        await initTask.value
        await rePairTask.value

        let settled = await pollUntil { container.hostStore.isHostOnline }
        #expect(settled)
        // #309 Lane B: the identity-mismatch assertion that stood here is
        // gone with `PairingStore`. It was already the weakest line in this
        // test — a check that nothing wrote a flag nothing writes. What the
        // test is actually about is the reset race, asserted above.
    }

    @Test @MainActor
    func rePairMidStreamCancelsStreamAndAbandonsPendingRun() async throws {
        // #184: the cross-HOST half. Both pairing handlers reason about this
        // race class for the bootstrap (#136 above) and missed it for the
        // stream: chatStore.reset() nil'd `conversation` while the streaming
        // task kept running and the pendingRun stayed armed, then
        // initialize() ran against a DIFFERENT host.
        let chatClient = BlackHoleStreamingChatClient()
        let harness = await makeLaunchHarness(
            suiteName: "launch-stream-repair-\(UUID().uuidString)",
            chatClient: chatClient
        )
        let container = harness.container
        harness.openAllGates()

        // Send #1 interrupts, arming the pending run; send #2 streams into a
        // black hole and stays live into the re-pair.
        await container.chatStore.sendMessage("arm the pending run")
        #expect(container.chatStore.pendingRunSessionId == "S1")
        let streamingSend = Task { @MainActor in await container.chatStore.sendMessage("now stream") }
        let streaming = await pollUntil { container.chatStore.isStreaming }
        #expect(streaming)

        await container.handleHostConnected()

        #expect(container.chatStore.pendingRunSessionId == nil, "re-pair must abandon the departing host's pending run")
        #expect(container.chatStore.isStreaming == false, "re-pair must tear down the departing host's streaming state")
        let cancelled = await pollUntil { chatClient.streamCancelled }
        #expect(cancelled, "the streaming task must be cancelled, not left running against the old host")
        // Cleanup, not an assertion: on the buggy path reset() leaves the
        // black-holed stream running and `await streamingSend.value` would
        // wedge the suite — cut it so the test ends either way.
        container.chatStore.cancelStreaming()
        _ = await streamingSend.value
    }
}
