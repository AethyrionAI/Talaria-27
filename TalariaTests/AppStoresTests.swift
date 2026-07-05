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

    private func makeSetupCode(_ code: String = "ABCD-EFGH") -> String {
        code
    }

    @MainActor
    private final class RecordingSessionBootstrapService: SessionBootstrapServiceProtocol {
        var registerCallCount = 0
        var lastLoadedAccessToken: String?

        func registerDevice(_ request: DeviceRegistrationRequest) async throws -> SessionBootstrapResponse {
            registerCallCount += 1
            return SessionBootstrapResponse(
                state: AppSessionState(
                    deviceID: UUID(),
                    installationID: request.installationID,
                    deviceRegistered: true,
                    connectionStatus: .connected,
                    syncStatus: .synced,
                    isMockMode: false,
                    backendEndpoint: request.relayBaseURLString,
                    lastSyncAt: nil,
                    pushTokenRegistered: false
                ),
                tokens: AuthTokens(
                    accessToken: "recording-access-token",
                    refreshToken: "recording-refresh-token",
                    expiresAt: .distantFuture
                )
            )
        }

        func loadSession(accessToken: String?) async throws -> AppSessionState {
            lastLoadedAccessToken = accessToken
            return AppSessionState(
                userID: UUID(),
                displayName: "Hermes User",
                deviceID: UUID(),
                installationID: UUID(),
                deviceRegistered: true,
                connectionStatus: .connected,
                syncStatus: .synced,
                isMockMode: false,
                backendEndpoint: AppEnvironment.development.baseURLString,
                lastSyncAt: .now,
                pushTokenRegistered: false
            )
        }

        func refreshAuth(refreshToken: String) async throws -> AuthTokens {
            AuthTokens(
                accessToken: "refreshed-access-token",
                refreshToken: "refreshed-refresh-token",
                expiresAt: .distantFuture
            )
        }

        func revokeCurrentSession(accessToken: String?) async throws {}
    }

    @MainActor
    private final class RecordingPairingService: PairingServiceProtocol {
        private(set) var lastMintedUserID: UUID?

        func normalizePairingCode(_ rawCode: String) throws -> String {
            try PhonePairingCode.normalize(rawCode)
        }

        func redeemPairingCode(
            _ normalizedCode: String,
            request: DeviceRegistrationRequest
        ) async throws -> PairingRedeemResult {
            let mintedUserID = UUID()
            lastMintedUserID = mintedUserID
            return PairingRedeemResult(
                configuration: PairedRelayConfiguration(
                    baseURLString: request.relayBaseURLString,
                    hostDisplayName: URL(string: request.relayBaseURLString)?.host ?? request.relayBaseURLString,
                    pairedAt: .now,
                    relayUserID: mintedUserID
                ),
                state: AppSessionState(
                    userID: mintedUserID,
                    displayName: "Morgan",
                    deviceID: UUID(),
                    installationID: request.installationID,
                    deviceRegistered: true,
                    connectionStatus: .connected,
                    syncStatus: .synced,
                    isMockMode: false,
                    backendEndpoint: request.relayBaseURLString,
                    lastSyncAt: .now,
                    pushTokenRegistered: false
                ),
                tokens: AuthTokens(
                    accessToken: "paired-access-token-\(normalizedCode)",
                    refreshToken: "paired-refresh-token-\(normalizedCode)",
                    expiresAt: .distantFuture
                )
            )
        }
    }

    @MainActor
    private final class RecordingHermesHostService: HermesHostServiceProtocol {
        var currentHost: HermesHostStatus?
        var fetchError: Error?

        func fetchCurrentHost(accessToken: String?) async throws -> HermesHostStatus? {
            if let fetchError {
                throw fetchError
            }
            return currentHost
        }

        func createEnrollmentCode(accessToken: String?) async throws -> HostEnrollmentCode {
            HostEnrollmentCode(
                setupCode: "HC1:test-setup-code",
                expiresAt: .distantFuture,
                relayHost: "relay.example.test"
            )
        }

        func revokeCurrentHost(accessToken: String?) async throws {
            currentHost = nil
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

        func injectVoiceTranscript(voiceSessionId: UUID) async throws -> Conversation {
            currentConversation ?? Conversation(title: "Hermes")
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
                voiceSessionID: nil
            )
        }

        private let eventHub = TalkSessionEventHub()

        func events() -> AsyncStream<TalkSessionEvent> {
            eventHub.stream(initial: snapshot)
        }

        func refreshReadiness() async {
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

    @Test @MainActor
    func sessionBootstrapPersistsStateAndTokens() async throws {
        let suiteName = "session-bootstrap-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let persistence = UserDefaultsAppPersistenceStore(defaults: defaults)
        let secureStore = MockSecureStore()
        let sessionStore = AppSessionStore(
            bootstrapService: MockSessionBootstrapService(),
            syncCoordinator: MockSyncCoordinator(),
            secureStore: secureStore,
            persistence: persistence,
            notificationService: MockNotificationService(),
            environmentProvider: { .development }
        )

        await sessionStore.bootstrap()

        #expect(sessionStore.state.deviceRegistered)
        #expect(sessionStore.state.connectionStatus == .connected)
        #expect(await secureStore.retrieve(key: "session.accessToken") != nil)
        #expect(persistence.loadSessionState()?.deviceRegistered == true)
    }

    @Test @MainActor
    func sessionBootstrapReRegistersWhenPersistedStateExistsButAccessTokenIsMissing() async throws {
        let suiteName = "session-bootstrap-missing-token-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let persistence = UserDefaultsAppPersistenceStore(defaults: defaults)
        persistence.saveSessionState(
            AppSessionState(
                userID: UUID(),
                displayName: "Hermes User",
                deviceID: UUID(),
                installationID: UUID(),
                deviceRegistered: true,
                connectionStatus: .connected,
                syncStatus: .synced,
                isMockMode: false,
                backendEndpoint: AppEnvironment.development.baseURLString,
                lastSyncAt: .now,
                pushTokenRegistered: false
            )
        )

        let bootstrapService = RecordingSessionBootstrapService()
        let secureStore = MockSecureStore()
        let sessionStore = AppSessionStore(
            bootstrapService: bootstrapService,
            syncCoordinator: MockSyncCoordinator(),
            secureStore: secureStore,
            persistence: persistence,
            notificationService: MockNotificationService(),
            environmentProvider: { .development }
        )

        await sessionStore.bootstrap()

        #expect(bootstrapService.registerCallCount == 1)
        #expect(bootstrapService.lastLoadedAccessToken == "recording-access-token")
        #expect(await secureStore.retrieve(key: "session.accessToken") == "recording-access-token")
    }

    /// Bootstrap service whose refresh/register behavior is scripted per test —
    /// the #15 recovery-ladder tests need refresh rejections, register
    /// failures, and slow refreshes on demand.
    @MainActor
    private final class ScriptedSessionBootstrapService: SessionBootstrapServiceProtocol {
        var registerCallCount = 0
        var refreshCallCount = 0
        var refreshDelayMilliseconds = 0
        var refreshError: Error?
        var registerError: Error?
        /// Access tokens loadSession must reject with a 401, simulating a
        /// relay that no longer honors them.
        var rejectedAccessTokens: Set<String> = []
        let sessionUserID = UUID()

        func registerDevice(_ request: DeviceRegistrationRequest) async throws -> SessionBootstrapResponse {
            registerCallCount += 1
            if let registerError { throw registerError }
            return SessionBootstrapResponse(
                state: AppSessionState(
                    userID: sessionUserID,
                    deviceID: UUID(),
                    installationID: request.installationID,
                    deviceRegistered: true,
                    connectionStatus: .connected,
                    syncStatus: .synced,
                    isMockMode: false,
                    backendEndpoint: request.relayBaseURLString,
                    lastSyncAt: nil,
                    pushTokenRegistered: false
                ),
                tokens: AuthTokens(
                    accessToken: "scripted-recovered-access",
                    refreshToken: "scripted-recovered-refresh",
                    expiresAt: .distantFuture
                )
            )
        }

        func loadSession(accessToken: String?) async throws -> AppSessionState {
            if let accessToken, rejectedAccessTokens.contains(accessToken) {
                throw RelayAPIClient.ClientError.unauthorized("Expired or invalid access token.")
            }
            return AppSessionState(
                userID: sessionUserID,
                displayName: "Hermes User",
                deviceID: UUID(),
                installationID: UUID(),
                deviceRegistered: true,
                connectionStatus: .connected,
                syncStatus: .synced,
                isMockMode: false,
                backendEndpoint: AppEnvironment.development.baseURLString,
                lastSyncAt: .now,
                pushTokenRegistered: false
            )
        }

        func refreshAuth(refreshToken: String) async throws -> AuthTokens {
            refreshCallCount += 1
            if refreshDelayMilliseconds > 0 {
                try? await Task.sleep(for: .milliseconds(refreshDelayMilliseconds))
            }
            if let refreshError { throw refreshError }
            return AuthTokens(
                accessToken: "scripted-refreshed-access",
                refreshToken: "scripted-refreshed-refresh",
                expiresAt: .distantFuture
            )
        }

        func revokeCurrentSession(accessToken: String?) async throws {}
    }

    @MainActor
    private func makeScriptedSessionStore(
        suiteName: String,
        bootstrapService: ScriptedSessionBootstrapService,
        secureStore: MockSecureStore,
        registered: Bool
    ) -> AppSessionStore {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let persistence = UserDefaultsAppPersistenceStore(defaults: defaults)
        if registered {
            persistence.saveSessionState(
                AppSessionState(
                    userID: UUID(),
                    displayName: "Hermes User",
                    deviceID: UUID(),
                    installationID: UUID(),
                    deviceRegistered: true,
                    connectionStatus: .connected,
                    syncStatus: .synced,
                    isMockMode: false,
                    backendEndpoint: AppEnvironment.development.baseURLString,
                    lastSyncAt: .now,
                    pushTokenRegistered: false
                )
            )
        }
        return AppSessionStore(
            bootstrapService: bootstrapService,
            syncCoordinator: MockSyncCoordinator(),
            secureStore: secureStore,
            persistence: persistence,
            notificationService: MockNotificationService(),
            environmentProvider: { .development }
        )
    }

    @Test @MainActor
    func tokenRefreshReportsMissingRefreshToken() async throws {
        let bootstrapService = ScriptedSessionBootstrapService()
        let sessionStore = makeScriptedSessionStore(
            suiteName: "token-refresh-missing-\(UUID().uuidString)",
            bootstrapService: bootstrapService,
            secureStore: MockSecureStore(),
            registered: true
        )

        let outcome = await sessionStore.refreshAccessTokenIfNeeded()

        #expect(outcome == .missingRefreshToken)
        #expect(bootstrapService.refreshCallCount == 0)
    }

    @Test @MainActor
    func tokenRefreshDistinguishesRejectionFromTransientFailure() async throws {
        let bootstrapService = ScriptedSessionBootstrapService()
        let secureStore = MockSecureStore()
        await secureStore.store(key: "session.accessToken", value: "stale-access")
        await secureStore.store(key: "session.refreshToken", value: "stale-refresh")
        let sessionStore = makeScriptedSessionStore(
            suiteName: "token-refresh-classify-\(UUID().uuidString)",
            bootstrapService: bootstrapService,
            secureStore: secureStore,
            registered: true
        )

        bootstrapService.refreshError = URLError(.notConnectedToInternet)
        #expect(await sessionStore.refreshAccessTokenIfNeeded() == .transientFailure)

        bootstrapService.refreshError = RelayAPIClient.ClientError.requestFailed("relay 500")
        #expect(await sessionStore.refreshAccessTokenIfNeeded() == .transientFailure)

        bootstrapService.refreshError = RelayAPIClient.ClientError.unauthorized("Invalid refresh token.")
        #expect(await sessionStore.refreshAccessTokenIfNeeded() == .rejected)

        // Failed refreshes never clobber the stored tokens.
        #expect(await secureStore.retrieve(key: "session.accessToken") == "stale-access")
        #expect(await secureStore.retrieve(key: "session.refreshToken") == "stale-refresh")

        bootstrapService.refreshError = nil
        #expect(await sessionStore.refreshAccessTokenIfNeeded() == .refreshed)
        #expect(await secureStore.retrieve(key: "session.accessToken") == "scripted-refreshed-access")
        #expect(await secureStore.retrieve(key: "session.refreshToken") == "scripted-refreshed-refresh")
    }

    @Test @MainActor
    func concurrentTokenRefreshesCoalesceIntoOneRelayCall() async throws {
        let bootstrapService = ScriptedSessionBootstrapService()
        bootstrapService.refreshDelayMilliseconds = 50
        let secureStore = MockSecureStore()
        await secureStore.store(key: "session.refreshToken", value: "stale-refresh")
        let sessionStore = makeScriptedSessionStore(
            suiteName: "token-refresh-coalesce-\(UUID().uuidString)",
            bootstrapService: bootstrapService,
            secureStore: secureStore,
            registered: true
        )

        // Talk + sensors 401ing at once must not race the rotation: with
        // rotate-on-refresh, the second caller's stale refresh token would
        // be rejected server-side.
        let first = Task { await sessionStore.refreshAccessTokenIfNeeded() }
        let second = Task { await sessionStore.refreshAccessTokenIfNeeded() }

        #expect(await first.value == .refreshed)
        #expect(await second.value == .refreshed)
        #expect(bootstrapService.refreshCallCount == 1)
    }

    @Test @MainActor
    func sessionRecoveryReRegistersKnownInstallationAndReloadsIdentity() async throws {
        let bootstrapService = ScriptedSessionBootstrapService()
        let secureStore = MockSecureStore()
        await secureStore.store(key: "session.accessToken", value: "stale-access")
        await secureStore.store(key: "session.refreshToken", value: "dead-refresh")
        let sessionStore = makeScriptedSessionStore(
            suiteName: "session-recovery-\(UUID().uuidString)",
            bootstrapService: bootstrapService,
            secureStore: secureStore,
            registered: true
        )

        let recovered = await sessionStore.recoverSessionByReRegistering()

        #expect(recovered)
        #expect(bootstrapService.registerCallCount == 1)
        #expect(await secureStore.retrieve(key: "session.accessToken") == "scripted-recovered-access")
        #expect(await secureStore.retrieve(key: "session.refreshToken") == "scripted-recovered-refresh")
        // The reloaded session user is what PairingStore.validateRestoredIdentity
        // compares against the pairing's minted user.
        #expect(sessionStore.state.userID == bootstrapService.sessionUserID)
    }

    @Test @MainActor
    func sessionRecoveryRefusesNeverRegisteredInstallation() async throws {
        let bootstrapService = ScriptedSessionBootstrapService()
        let sessionStore = makeScriptedSessionStore(
            suiteName: "session-recovery-unregistered-\(UUID().uuidString)",
            bootstrapService: bootstrapService,
            secureStore: MockSecureStore(),
            registered: false
        )

        let recovered = await sessionStore.recoverSessionByReRegistering()

        #expect(!recovered)
        #expect(bootstrapService.registerCallCount == 0)
    }

    @Test @MainActor
    func sessionRecoveryAttemptsAreRateLimited() async throws {
        let bootstrapService = ScriptedSessionBootstrapService()
        bootstrapService.registerError = URLError(.cannotConnectToHost)
        let sessionStore = makeScriptedSessionStore(
            suiteName: "session-recovery-ratelimit-\(UUID().uuidString)",
            bootstrapService: bootstrapService,
            secureStore: MockSecureStore(),
            registered: true
        )

        #expect(await sessionStore.recoverSessionByReRegistering() == false)
        #expect(await sessionStore.recoverSessionByReRegistering() == false)

        // The second attempt inside the cooldown window never hits the relay.
        #expect(bootstrapService.registerCallCount == 1)
    }

    @Test @MainActor
    func bootstrapSelfHealsWhenRefreshTokenIsDead() async throws {
        // The #15 launch shape: stored access token is expired (relay 401s
        // it), the refresh token is rejected, and the old code parked the app
        // in an error state until a manual re-pair. Bootstrap must now walk
        // the ladder down to silent re-registration and come back connected.
        let bootstrapService = ScriptedSessionBootstrapService()
        bootstrapService.rejectedAccessTokens = ["expired-access"]
        bootstrapService.refreshError = RelayAPIClient.ClientError.unauthorized("Invalid refresh token.")
        let secureStore = MockSecureStore()
        await secureStore.store(key: "session.accessToken", value: "expired-access")
        await secureStore.store(key: "session.refreshToken", value: "dead-refresh")
        let sessionStore = makeScriptedSessionStore(
            suiteName: "bootstrap-self-heal-\(UUID().uuidString)",
            bootstrapService: bootstrapService,
            secureStore: secureStore,
            registered: true
        )

        await sessionStore.bootstrap()

        #expect(bootstrapService.registerCallCount == 1)
        #expect(sessionStore.state.connectionStatus == .connected)
        #expect(sessionStore.state.syncStatus == .synced)
        #expect(await secureStore.retrieve(key: "session.accessToken") == "scripted-recovered-access")
        #expect(await secureStore.retrieve(key: "session.refreshToken") == "scripted-recovered-refresh")
    }

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
    func settingsStorePersistsLocationSyncPreferenceChanges() async throws {
        let suiteName = "settings-store-location-sync-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let persistence = UserDefaultsAppPersistenceStore(defaults: defaults)
        let settingsStore = SettingsStore(persistence: persistence)

        settingsStore.settings.locationSyncPreference = .backgroundAllowed

        let reloaded = persistence.loadUserSettings()
        #expect(reloaded?.locationSyncPreference == .backgroundAllowed)
    }

    @Test @MainActor
    func sleepDurationUsesStableWakeDayBucket() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let bucketDay = calendar.date(from: DateComponents(year: 2026, month: 4, day: 5))!
        let intervals: [LiveHealthService.SleepInterval] = [
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

        let hours = LiveHealthService.aggregateSleepDuration(
            intervals: intervals,
            attributedTo: bucketDay,
            calendar: calendar
        )

        #expect(hours == 8.5)
        #expect(LiveHealthService.sleepBucketDay(for: calendar.date(from: DateComponents(year: 2026, month: 4, day: 5, hour: 18))!, calendar: calendar) == bucketDay)
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

            func injectVoiceTranscript(voiceSessionId: UUID) async throws -> Conversation {
                currentConversation ?? Conversation(title: "Hermes")
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

            func injectVoiceTranscript(voiceSessionId: UUID) async throws -> Conversation {
                currentConversation ?? Conversation(title: "Hermes")
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

            func injectVoiceTranscript(voiceSessionId: UUID) async throws -> Conversation {
                currentConversation ?? Conversation(title: "Hermes")
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
    func chatStoreRefreshesConversationWhenStreamingFailsAfterJobAccepted() async throws {
        final class StreamingFailureClient: HermesClientProtocol {
            var connectionStatus: ConnectionStatus = .connected
            var currentConversation: Conversation?
            var loadConversationCallCount = 0
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
                        continuation.yield(.failed("Stream interrupted"))
                        continuation.finish()
                    }
                }
            }

            func loadConversation() async -> Conversation {
                loadConversationCallCount += 1
                let conversation = Conversation(
                    title: "Hermes",
                    messages: [
                        Message(id: userID, sender: .user, content: "Fix it", status: .delivered),
                        Message(id: assistantID, sender: .hermes, content: "Recovered after polling", jobID: jobID, status: .delivered),
                    ]
                )
                currentConversation = conversation
                return conversation
            }

            func clearConversation() async throws -> Conversation {
                Conversation(title: "Hermes")
            }

            func injectVoiceTranscript(voiceSessionId: UUID) async throws -> Conversation {
                currentConversation ?? Conversation(title: "Hermes")
            }
        }

        let suiteName = "chat-store-stream-failure-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let persistence = UserDefaultsAppPersistenceStore(defaults: defaults)
        let hermesClient = StreamingFailureClient()
        let chatStore = ChatStore(hermesClient: hermesClient, persistence: persistence)

        await chatStore.sendMessage("Fix it")

        #expect(hermesClient.loadConversationCallCount == 1)
        #expect(chatStore.conversation?.messages.last?.content == "Recovered after polling")
        #expect(chatStore.pendingMessageSentAt == nil)
        #expect(chatStore.isStreaming == false)
    }

    @Test @MainActor
    func liveHermesClientRefreshesConversationBeforeResolvingFinishedStreamMessage() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)

        let conversationID = UUID()
        let userMessageID = UUID()
        let assistantMessageID = UUID()
        let jobID = UUID()
        let requestCount = MutableBox(0)

        StubURLProtocol.requestHandler = { request in
            requestCount.value += 1
            let url = try #require(request.url)

            switch url.absoluteString {
            case "https://relay.example.com/v1/messages":
                let response = HTTPURLResponse(url: url, statusCode: 202, httpVersion: nil, headerFields: nil)!
                let data = #"""
                {"data":{
                  "replyState":"pending",
                  "jobId":"\#(jobID.uuidString.lowercased())",
                  "conversation":{
                    "id":"\#(conversationID.uuidString)",
                    "title":"Hermes",
                    "updatedAt":"2026-04-05T18:00:00Z",
                    "messages":[
                      {
                        "id":"\#(userMessageID.uuidString)",
                        "clientMessageId":"\#(userMessageID.uuidString)",
                        "role":"user",
                        "text":"Look at this",
                        "timestamp":"2026-04-05T18:00:00Z",
                        "deliveryStatus":"sent"
                      }
                    ]
                  },
                  "userMessage":{
                    "id":"\#(userMessageID.uuidString)",
                    "clientMessageId":"\#(userMessageID.uuidString)",
                    "role":"user",
                    "text":"Look at this",
                    "timestamp":"2026-04-05T18:00:00Z",
                    "deliveryStatus":"sent",
                    "jobId":"\#(jobID.uuidString.lowercased())"
                  }
                }}
                """#.data(using: .utf8)!
                return (response, data)

            case "https://relay.example.com/v1/jobs/\(jobID.uuidString.lowercased())/events":
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/event-stream"])!
                let data = """
                event: text_delta
                data: {"jobId":"\(jobID.uuidString.lowercased())","delta":"Recovered ","kind":"text_delta"}

                event: done
                data: {"jobId":"\(jobID.uuidString.lowercased())","status":"completed"}

                """.data(using: .utf8)!
                return (response, data)

            case "https://relay.example.com/v1/conversations/current":
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                let data = #"""
                {"data":{
                  "conversation":{
                    "id":"\#(conversationID.uuidString)",
                    "title":"Hermes",
                    "updatedAt":"2026-04-05T18:00:01Z",
                    "messages":[
                      {
                        "id":"\#(userMessageID.uuidString)",
                        "clientMessageId":"\#(userMessageID.uuidString)",
                        "role":"user",
                        "text":"Look at this",
                        "timestamp":"2026-04-05T18:00:00Z",
                        "deliveryStatus":"delivered",
                        "jobId":"\#(jobID.uuidString.lowercased())"
                      },
                      {
                        "id":"\#(assistantMessageID.uuidString)",
                        "role":"hermes",
                        "text":"Recovered after refresh",
                        "timestamp":"2026-04-05T18:00:01Z",
                        "deliveryStatus":"delivered",
                        "jobId":"\#(jobID.uuidString.lowercased())"
                      }
                    ]
                  }
                }}
                """#.data(using: .utf8)!
                return (response, data)

            default:
                Issue.record("Unexpected URL: \(url.absoluteString)")
                throw URLError(.badURL)
            }
        }

        defer {
            StubURLProtocol.requestHandler = nil
        }

        let apiClient = RelayAPIClient(
            baseURLProvider: { "https://relay.example.com/v1" },
            session: session
        )
        let hermesClient = LiveHermesClient(
            apiClient: apiClient,
            accessTokenProvider: { "token" },
            allowDemoFallback: false
        )

        var updates: [StreamingUpdate] = []
        for await update in hermesClient.sendStreaming(
            message: "Look at this",
            attachments: [],
            clientMessageID: userMessageID
        ) {
            updates.append(update)
        }

        let finishedMessage = try #require(
            updates.compactMap { update -> Message? in
                guard case .finished(let message, _, _) = update else { return nil }
                return message
            }.last
        )
        #expect(finishedMessage.content == "Recovered after refresh")
        #expect(requestCount.value == 3)
    }

    @Test @MainActor
    func liveHermesClientRejectsOversizedAggregateAttachmentPayloadBeforeSending() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let requestCount = MutableBox(0)

        StubURLProtocol.requestHandler = { request in
            requestCount.value += 1
            let url = try #require(request.url)
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, #"{"data":{"conversation":{"id":"00000000-0000-0000-0000-000000000000","title":"Hermes","updatedAt":"2026-04-05T18:00:00Z","messages":[]}}}"#.data(using: .utf8)!)
        }

        defer {
            StubURLProtocol.requestHandler = nil
        }

        let tempDirectory = FileManager.default.temporaryDirectory
        let oversizedData = Data(repeating: 0x41, count: 300 * 1024)
        var attachments: [PendingAttachment] = []

        for index in 0 ..< 4 {
            let url = tempDirectory.appendingPathComponent("oversized-\(index)-\(UUID().uuidString).txt")
            try oversizedData.write(to: url)
            attachments.append(try #require(PendingAttachment.file(at: url)))
        }

        let apiClient = RelayAPIClient(
            baseURLProvider: { "https://relay.example.com/v1" },
            session: session
        )
        let hermesClient = LiveHermesClient(
            apiClient: apiClient,
            accessTokenProvider: { "token" },
            allowDemoFallback: false
        )

        let response = await hermesClient.send(
            message: "Here are several attachments",
            attachments: attachments,
            clientMessageID: UUID()
        )

        #expect(requestCount.value == 0)
        #expect(response.status == .failed)
        #expect(response.content == "The attachment was too large for Hermes to process. Try a smaller image.")
    }

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

            func injectVoiceTranscript(voiceSessionId: UUID) async throws -> Conversation {
                currentConversation ?? Conversation(title: "Hermes")
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

            func injectVoiceTranscript(voiceSessionId: UUID) async throws -> Conversation {
                currentConversation ?? Conversation(title: "Hermes")
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

    @Test @MainActor
    func liveVoiceSessionServiceRefreshesExpiredAccessTokenDuringReadiness() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)

        let accessToken = MutableBox("expired-token")
        let refreshCallCount = MutableBox(0)
        let requestCount = MutableBox(0)

        StubURLProtocol.requestHandler = { request in
            requestCount.value += 1
            let url = try #require(request.url)
            #expect(url.absoluteString == "https://relay.example.com/v1/talk/readiness")

            let authHeader = request.value(forHTTPHeaderField: "Authorization")
            if authHeader == "Bearer expired-token" {
                let response = HTTPURLResponse(url: url, statusCode: 401, httpVersion: nil, headerFields: nil)!
                let data = #"{"error":{"code":"unauthorized","message":"expired or invalid access token","retryable":false}}"#.data(using: .utf8)!
                return (response, data)
            }

            #expect(authHeader == "Bearer refreshed-token")
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let data = #"""
            {"data":{
              "ready":true,
              "hostOnline":true,
              "configured":true,
              "blockedReason":null,
              "preferredModels":["gpt-realtime-1.5"],
              "selectedModel":"gpt-realtime-1.5",
              "voice":"verse",
              "voiceContextUpdatedAt":"2026-04-01T20:40:47.636600Z"
            }}
            """#.data(using: .utf8)!
            return (response, data)
        }

        defer {
            StubURLProtocol.requestHandler = nil
        }

        let apiClient = RelayAPIClient(
            baseURLProvider: { "https://relay.example.com/v1" },
            session: session
        )
        let voiceService = LiveVoiceSessionService(
            apiClient: apiClient,
            accessTokenProvider: { accessToken.value },
            accessTokenRefresher: {
                refreshCallCount.value += 1
                accessToken.value = "refreshed-token"
                return accessToken.value
            },
            urlSession: session
        )

        await voiceService.refreshReadiness()

        #expect(refreshCallCount.value == 1)
        #expect(requestCount.value == 2)
        #expect(voiceService.canStartSession)
        #expect(voiceService.connectionState == .ready)
        #expect(voiceService.statusMessage == "Hermes talk is ready.")
        #expect(voiceService.blockedReason == nil)
    }

    @Test @MainActor
    func liveVoiceSessionServiceInterruptsAssistantPlaybackOnSpeechStart() async throws {
        let sentEvents = MutableBox([[String: Any]]())
        let apiClient = RelayAPIClient(
            baseURLProvider: { "https://relay.example.com/v1" }
        )
        let voiceService = LiveVoiceSessionService(
            apiClient: apiClient,
            accessTokenProvider: { "token" },
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
        let apiClient = RelayAPIClient(
            baseURLProvider: { "https://relay.example.com/v1" }
        )
        let voiceService = LiveVoiceSessionService(
            apiClient: apiClient,
            accessTokenProvider: { "token" },
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

    @Test @MainActor
    func liveVoiceSessionServiceRecoversFromInterruptionsWithoutEndingSession() async throws {
        let apiClient = RelayAPIClient(
            baseURLProvider: { "https://relay.example.com/v1" }
        )
        let voiceService = LiveVoiceSessionService(
            apiClient: apiClient,
            accessTokenProvider: { "token" }
        )

        voiceService.connectionState = .connected
        voiceService.voiceState = .speaking

        voiceService.handleAudioInterruptionBegan()

        #expect(voiceService.voiceState == .interrupted)
        #expect(voiceService.statusMessage == "Audio interrupted.")

        voiceService.handleAudioInterruptionEnded(shouldResume: true)

        #expect(voiceService.connectionState == .connected)
        #expect(voiceService.voiceState == .listening)
        #expect(voiceService.statusMessage == "Listening")
    }

    @Test @MainActor
    func liveVoiceSessionServiceRecoversFromRouteChangesDuringActiveSession() async throws {
        let apiClient = RelayAPIClient(
            baseURLProvider: { "https://relay.example.com/v1" }
        )
        let voiceService = LiveVoiceSessionService(
            apiClient: apiClient,
            accessTokenProvider: { "token" }
        )

        voiceService.connectionState = .connected
        voiceService.voiceState = .interrupted

        voiceService.handleAudioRouteChange(.oldDeviceUnavailable)

        #expect(voiceService.connectionState == .connected)
        #expect(voiceService.voiceState == .listening)
        #expect(voiceService.statusMessage == "Audio route changed.")
    }

    @Test @MainActor
    func liveVoiceSessionServiceKeepsUserTranscriptOrderedWhenTranscriptionFinishesLate() async throws {
        let apiClient = RelayAPIClient(
            baseURLProvider: { "https://relay.example.com/v1" }
        )
        let voiceService = LiveVoiceSessionService(
            apiClient: apiClient,
            accessTokenProvider: { "token" }
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
        let apiClient = RelayAPIClient(
            baseURLProvider: { "https://relay.example.com/v1" }
        )
        let voiceService = LiveVoiceSessionService(
            apiClient: apiClient,
            accessTokenProvider: { "token" }
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
    func liveHermesClientRefreshesExpiredAccessTokenDuringConversationLoad() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)

        let accessToken = MutableBox("expired-token")
        let refreshCallCount = MutableBox(0)
        let requestCount = MutableBox(0)
        let conversationID = UUID()

        StubURLProtocol.requestHandler = { request in
            requestCount.value += 1
            let url = try #require(request.url)
            #expect(url.absoluteString == "https://relay.example.com/v1/conversations/current")

            let authHeader = request.value(forHTTPHeaderField: "Authorization")
            if authHeader == "Bearer expired-token" {
                let response = HTTPURLResponse(url: url, statusCode: 401, httpVersion: nil, headerFields: nil)!
                let data = #"{"error":{"code":"unauthorized","message":"expired or invalid access token","retryable":false}}"#.data(using: .utf8)!
                return (response, data)
            }

            #expect(authHeader == "Bearer refreshed-token")
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let data = #"""
            {"data":{
              "conversation":{
                "id":"\#(conversationID.uuidString)",
                "title":"Hermes",
                "updatedAt":"2026-04-03T21:15:00Z",
                "messages":[]
              }
            }}
            """#.data(using: .utf8)!
            return (response, data)
        }

        defer {
            StubURLProtocol.requestHandler = nil
        }

        let apiClient = RelayAPIClient(
            baseURLProvider: { "https://relay.example.com/v1" },
            session: session
        )
        let hermesClient = LiveHermesClient(
            apiClient: apiClient,
            accessTokenProvider: { accessToken.value },
            accessTokenRefresher: {
                refreshCallCount.value += 1
                accessToken.value = "refreshed-token"
                return accessToken.value
            },
            allowDemoFallback: false
        )

        let conversation = await hermesClient.loadConversation()

        #expect(refreshCallCount.value == 1)
        #expect(requestCount.value == 2)
        #expect(conversation.id == conversationID)
        #expect(hermesClient.connectionStatus == .connected)
    }

    @Test @MainActor
    func liveHermesHostServiceRefreshesExpiredAccessTokenDuringFetch() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)

        let accessToken = MutableBox("expired-token")
        let refreshCallCount = MutableBox(0)
        let requestCount = MutableBox(0)
        let hostID = UUID()

        StubURLProtocol.requestHandler = { request in
            requestCount.value += 1
            let url = try #require(request.url)
            #expect(url.absoluteString == "https://relay.example.com/v1/hosts/current")

            let authHeader = request.value(forHTTPHeaderField: "Authorization")
            if authHeader == "Bearer expired-token" {
                let response = HTTPURLResponse(url: url, statusCode: 401, httpVersion: nil, headerFields: nil)!
                let data = #"{"error":{"code":"unauthorized","message":"expired or invalid access token","retryable":false}}"#.data(using: .utf8)!
                return (response, data)
            }

            #expect(authHeader == "Bearer refreshed-token")
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let data = #"""
            {"data":{
              "host":{
                "id":"\#(hostID.uuidString)",
                "displayName":"Home Mac mini",
                "hostname":"test-host",
                "platform":"macos",
                "connectorVersion":"0.1.0",
                "hermesCommand":"/usr/local/bin/hermes",
                "hermesVersion":"hermes 0.7.0",
                "lastSeenAt":"2026-04-03T21:15:00Z",
                "lastConnectedAt":"2026-04-03T21:10:00Z",
                "isOnline":true
              }
            }}
            """#.data(using: .utf8)!
            return (response, data)
        }

        defer {
            StubURLProtocol.requestHandler = nil
        }

        let apiClient = RelayAPIClient(
            baseURLProvider: { "https://relay.example.com/v1" },
            session: session
        )
        let hostService = LiveHermesHostService(
            apiClient: apiClient,
            accessTokenRefresher: {
                refreshCallCount.value += 1
                accessToken.value = "refreshed-token"
                return accessToken.value
            }
        )

        let host = try await hostService.fetchCurrentHost(accessToken: accessToken.value)

        #expect(refreshCallCount.value == 1)
        #expect(requestCount.value == 2)
        #expect(host?.id == hostID)
        #expect(host?.isOnline == true)
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
                notificationsEnabled: true,
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

    @Test @MainActor
    func settingsStorePersistsCustomRelayConfiguration() async throws {
        let suiteName = "settings-store-relay-config-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let persistence = UserDefaultsAppPersistenceStore(defaults: defaults)
        let settingsStore = SettingsStore(
            persistence: persistence,
            buildConfiguration: AppBuildConfiguration(
                hostedRelayBaseURL: nil,
                hostedRelayEnabled: false,
                supportURL: nil,
                termsOfServiceURL: nil,
                privacyPolicyURL: nil
            )
        )

        settingsStore.settings.relayConfiguration = RelayConfiguration(
            relayMode: .custom,
            customRelayBaseURL: "https://demo.example.com/v1",
            hostedRelayBaseURL: nil,
            hostedRelayEnabled: false
        )

        let reloaded = persistence.loadUserSettings()
        #expect(reloaded?.relayConfiguration.activeBaseURLString == "https://demo.example.com/v1")
    }

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

    @Test @MainActor
    func persistenceStorePersistsAndClearsHealthQueryAnchors() async throws {
        let suiteName = "health-anchors-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let persistence = UserDefaultsAppPersistenceStore(defaults: defaults)
        let anchorData = Data([0x01, 0x02, 0x03])

        persistence.saveHealthQueryAnchorData(anchorData, for: "steps")
        persistence.saveHealthQueryAnchorData(Data([0x04]), for: "heart_rate")

        #expect(persistence.loadHealthQueryAnchorData(for: "steps") == anchorData)
        #expect(persistence.loadHealthQueryAnchorData(for: "heart_rate") == Data([0x04]))

        persistence.clearHealthQueryAnchorData()

        #expect(persistence.loadHealthQueryAnchorData(for: "steps") == nil)
        #expect(persistence.loadHealthQueryAnchorData(for: "heart_rate") == nil)
    }

    @Test
    func phonePairingCodeNormalizesAndFormatsManualEntry() throws {
        let normalized = try PhonePairingCode.normalize("ab cd-efgh")

        #expect(normalized == "ABCDEFGH")
        #expect(PhonePairingCode.format("ab cd-efgh") == "ABCD-EFGH")
        #expect(PhonePairingCode.isComplete("ABCD-EFGH"))
    }

    @Test @MainActor
    func pairingStorePersistsRelayConfigurationAndTokens() async throws {
        let suiteName = "pairing-store-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let persistence = UserDefaultsAppPersistenceStore(defaults: defaults)
        let secureStore = MockSecureStore()
        let sessionStore = AppSessionStore(
            bootstrapService: MockSessionBootstrapService(),
            syncCoordinator: MockSyncCoordinator(),
            secureStore: secureStore,
            persistence: persistence,
            notificationService: MockNotificationService(),
            environmentProvider: { .production }
        )
        let pairingStore = PairingStore(
            pairingService: RecordingPairingService(),
            sessionStore: sessionStore,
            persistence: persistence,
            environmentProvider: { .production },
            relayBaseURLProvider: { "https://relay.example.test/v1" }
        )

        let setupCode = makeSetupCode()
        let didPair = await pairingStore.pair(using: setupCode)

        #expect(didPair)
        #expect(pairingStore.pairedRelayConfiguration?.hostDisplayName == "relay.example.test")
        #expect(persistence.loadPairedRelayConfiguration()?.baseURLString == "https://relay.example.test/v1")
        #expect(await secureStore.retrieve(key: "session.accessToken") == "paired-access-token-ABCDEFGH")
        #expect(sessionStore.state.displayName == "Morgan")
    }

    @Test @MainActor
    func hostStoreGeneratesEnrollmentCodeAndClearsOnRevoke() async throws {
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
            isOnline: false
        )

        let hostStore = HermesHostStore(
            hostService: service,
            accessTokenProvider: { "access-token" }
        )

        await hostStore.refresh()
        #expect(hostStore.currentHost?.resolvedDisplayName == "Home Mac mini")

        await hostStore.generateEnrollmentCode()
        #expect(hostStore.activeEnrollmentCode?.setupCode == "HC1:test-setup-code")

        await hostStore.revokeCurrentHost()
        #expect(hostStore.currentHost == nil)
        #expect(hostStore.activeEnrollmentCode == nil)
    }

    @Test @MainActor
    func hostStoreMarksReachabilityErrorsWithoutPretendingHostIsOffline() async throws {
        let service = RecordingHermesHostService()
        service.fetchError = RelayAPIClient.ClientError.requestFailed("Relay unreachable.")

        let hostStore = HermesHostStore(
            hostService: service,
            accessTokenProvider: { "access-token" }
        )

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

        let hostStore = HermesHostStore(
            hostService: service,
            accessTokenProvider: { "access-token" }
        )

        await hostStore.refresh()
        service.fetchError = RelayAPIClient.ClientError.requestFailed("Relay unreachable.")
        await hostStore.refresh()

        #expect(hostStore.currentHost?.resolvedDisplayName == "Home Mac mini")
        #expect(hostStore.connectionState == .online)
        #expect(hostStore.lastErrorMessage == "Relay unreachable.")
    }

    @Test @MainActor
    func pairingStoreDisconnectClearsRelayConfigurationAndSession() async throws {
        let suiteName = "pairing-store-disconnect-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let persistence = UserDefaultsAppPersistenceStore(defaults: defaults)
        let secureStore = MockSecureStore()
        let sessionStore = AppSessionStore(
            bootstrapService: MockSessionBootstrapService(),
            syncCoordinator: MockSyncCoordinator(),
            secureStore: secureStore,
            persistence: persistence,
            notificationService: MockNotificationService(),
            environmentProvider: { .production }
        )
        let pairingStore = PairingStore(
            pairingService: RecordingPairingService(),
            sessionStore: sessionStore,
            persistence: persistence,
            environmentProvider: { .production },
            relayBaseURLProvider: { "https://relay.example.test/v1" }
        )

        let setupCode = makeSetupCode()
        _ = await pairingStore.pair(using: setupCode)

        await pairingStore.disconnect()

        // Clear-on-disconnect guard (#3): the Keychain must hold NO relay
        // identity after an unpair — both token keys gone, config gone from
        // both stores.
        #expect(pairingStore.pairedRelayConfiguration == nil)
        #expect(persistence.loadPairedRelayConfiguration() == nil)
        #expect(await secureStore.retrieve(key: "session.accessToken") == nil)
        #expect(await secureStore.retrieve(key: "session.refreshToken") == nil)
        #expect(sessionStore.state.deviceRegistered == false)
    }

    // MARK: - Stale Keychain identity (#3 / #46)

    @Test @MainActor
    func pairingWipesStaleKeychainIdentityAndRecordsMintedUser() async throws {
        let suiteName = "pairing-store-stale-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let persistence = UserDefaultsAppPersistenceStore(defaults: defaults)
        let secureStore = MockSecureStore()

        // Simulate a reinstall-resurrected identity: stale tokens in the
        // Keychain, a stale pairing config, and a stale session user.
        let staleUserID = UUID()
        await secureStore.store(key: "session.accessToken", value: "stale-access-token")
        await secureStore.store(key: "session.refreshToken", value: "stale-refresh-token")
        persistence.savePairedRelayConfiguration(
            PairedRelayConfiguration(
                baseURLString: "https://old.relay.test/v1",
                hostDisplayName: "old.relay.test",
                pairedAt: .distantPast,
                relayUserID: staleUserID
            )
        )
        persistence.saveSessionState(AppSessionState(userID: staleUserID, deviceRegistered: true))

        let sessionStore = AppSessionStore(
            bootstrapService: MockSessionBootstrapService(),
            syncCoordinator: MockSyncCoordinator(),
            secureStore: secureStore,
            persistence: persistence,
            notificationService: MockNotificationService(),
            environmentProvider: { .production }
        )
        let pairingService = RecordingPairingService()
        let pairingStore = PairingStore(
            pairingService: pairingService,
            sessionStore: sessionStore,
            persistence: persistence,
            environmentProvider: { .production },
            relayBaseURLProvider: { "https://relay.example.test/v1" }
        )

        let didPair = await pairingStore.pair(using: makeSetupCode())

        // No stale survivor: tokens are the freshly minted ones, the pairing
        // records the minted relay user, and the session matches it.
        #expect(didPair)
        #expect(await secureStore.retrieve(key: "session.accessToken") == "paired-access-token-ABCDEFGH")
        #expect(await secureStore.retrieve(key: "session.refreshToken") == "paired-refresh-token-ABCDEFGH")
        #expect(pairingStore.pairedRelayConfiguration?.relayUserID == pairingService.lastMintedUserID)
        #expect(sessionStore.state.userID == pairingService.lastMintedUserID)
        #expect(pairingStore.identityMismatchDetected == false)
        pairingStore.validateRestoredIdentity()
        #expect(pairingStore.identityMismatchDetected == false)
    }

    @Test @MainActor
    func validateRestoredIdentityFlagsResurrectedStaleUser() async throws {
        let suiteName = "pairing-store-mismatch-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let persistence = UserDefaultsAppPersistenceStore(defaults: defaults)
        let sessionStore = AppSessionStore(
            bootstrapService: MockSessionBootstrapService(),
            syncCoordinator: MockSyncCoordinator(),
            secureStore: MockSecureStore(),
            persistence: persistence,
            notificationService: MockNotificationService(),
            environmentProvider: { .production }
        )

        let pairedUserID = UUID()
        persistence.savePairedRelayConfiguration(
            PairedRelayConfiguration(
                baseURLString: "https://relay.example.test/v1",
                hostDisplayName: "relay.example.test",
                pairedAt: .now,
                relayUserID: pairedUserID
            )
        )
        let pairingStore = PairingStore(
            pairingService: RecordingPairingService(),
            sessionStore: sessionStore,
            persistence: persistence,
            environmentProvider: { .production },
            relayBaseURLProvider: { "https://relay.example.test/v1" }
        )

        // Session restored as a DIFFERENT user than the pairing minted —
        // the reinstall-resurrection signature (#46).
        sessionStore.state.userID = UUID()
        pairingStore.validateRestoredIdentity()
        #expect(pairingStore.identityMismatchDetected)

        // Matching identity clears the flag.
        sessionStore.state.userID = pairedUserID
        pairingStore.validateRestoredIdentity()
        #expect(pairingStore.identityMismatchDetected == false)

        // Pre-#3 pairings (no recorded user) can't be validated — no flag.
        persistence.clearPairedRelayConfiguration()
        pairingStore.pairedRelayConfiguration = PairedRelayConfiguration(
            baseURLString: "https://relay.example.test/v1",
            hostDisplayName: "relay.example.test",
            pairedAt: .now
        )
        sessionStore.state.userID = UUID()
        pairingStore.validateRestoredIdentity()
        #expect(pairingStore.identityMismatchDetected == false)
    }

    @Test @MainActor
    func inboxStorePersistsReadAndDismissState() async throws {
        let suiteName = "inbox-store-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let persistence = UserDefaultsAppPersistenceStore(defaults: defaults)
        let sessionStore = AppSessionStore(
            bootstrapService: MockSessionBootstrapService(),
            syncCoordinator: MockSyncCoordinator(),
            secureStore: MockSecureStore(),
            persistence: persistence,
            notificationService: MockNotificationService(),
            environmentProvider: { .development }
        )
        await sessionStore.bootstrap()

        let inboxStore = InboxStore(
            inboxService: MockInboxService(),
            persistence: persistence,
            sessionStore: sessionStore
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
            persistence: persistence,
            sessionStore: sessionStore
        )

        await reloadedStore.loadInbox(force: true)

        #expect(reloadedStore.items.contains(where: { $0.stableIdentifier == firstItem.stableIdentifier && $0.isRead }))
        #expect(!reloadedStore.items.contains(where: { $0.stableIdentifier == secondItem.stableIdentifier }))
    }

    @Test
    func sensorOutboxStateDeduplicatesLocationAndWindowedHealthSnapshots() {
        var outbox = SensorOutboxState()
        let now = Date(timeIntervalSince1970: 1_774_983_516)

        outbox.enqueue(
            location: LocationUpdate(
                latitude: 40.0,
                longitude: -73.0,
                altitude: nil,
                accuracy: 20,
                timestamp: now
            )
        )
        outbox.enqueue(
            location: LocationUpdate(
                latitude: 41.0,
                longitude: -74.0,
                altitude: nil,
                accuracy: 15,
                timestamp: now.addingTimeInterval(30)
            )
        )

        outbox.enqueue(
            healthSamples: [
                HealthSnapshot.Sample(
                    metric: "steps",
                    value: 1000,
                    unit: "count",
                    startAt: now,
                    endAt: now.addingTimeInterval(300)
                ),
                HealthSnapshot.Sample(
                    metric: "steps",
                    value: 1200,
                    unit: "count",
                    startAt: now,
                    endAt: now.addingTimeInterval(600)
                ),
                HealthSnapshot.Sample(
                    metric: "heart_rate",
                    value: 72,
                    unit: "bpm",
                    startAt: now,
                    endAt: nil
                )
            ]
        )

        #expect(outbox.pendingLocation?.latitude == 41.0)
        #expect(outbox.pendingHealthSamples.count == 2)
        #expect(outbox.pendingHealthSamples.first(where: { $0.metric == "steps" })?.value == 1200)
    }

    @Test @MainActor
    func persistenceStoreRoundTripsSensorOutboxState() {
        let suiteName = "sensor-outbox-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let persistence = UserDefaultsAppPersistenceStore(defaults: defaults)
        let date = Date(timeIntervalSince1970: 1_774_983_516)
        let outbox = SensorOutboxState(
            pendingLocation: .init(
                latitude: 40.0,
                longitude: -73.0,
                altitude: 12,
                accuracy: 20,
                recordedAt: date
            ),
            pendingHealthSamples: [
                .init(
                    metric: "heart_rate",
                    value: 72,
                    unit: "bpm",
                    startAt: date,
                    endAt: nil
                )
            ]
        )

        persistence.saveSensorOutboxState(outbox)

        let reloaded = persistence.loadSensorOutboxState()
        #expect(reloaded == outbox)
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
    func selectModelStoresHermesReportedWindowNotTheTable() async {
        @MainActor
        final class SwitchResponseClient: HermesClientProtocol {
            var connectionStatus: ConnectionStatus = .connected
            var currentConversation: Conversation?
            func connect() async {}
            func disconnect() async {}
            func send(message: String, attachments: [PendingAttachment], clientMessageID: UUID) async -> Message {
                Message(sender: .hermes, content: "unused", status: .delivered)
            }
            func sendStreaming(message: String, attachments: [PendingAttachment], clientMessageID: UUID) -> AsyncStream<StreamingUpdate> {
                AsyncStream { $0.finish() }
            }
            func loadConversation() async -> Conversation { Conversation(title: "Hermes") }
            func clearConversation() async throws -> Conversation { Conversation(title: "Hermes") }
            func injectVoiceTranscript(voiceSessionId: UUID) async throws -> Conversation { Conversation(title: "Hermes") }
            func switchModel(_ identifier: String) async throws -> String? {
                "Model switched to `kimi-k2.6`\nContext: 190,000 tokens"
            }
        }

        let suiteName = "chat-ctx-denominator-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let persistence = UserDefaultsAppPersistenceStore(defaults: defaults)
        let chatStore = ChatStore(hermesClient: SwitchResponseClient(), persistence: persistence)

        let ok = await chatStore.selectModel("kimi-k2.6")

        // The Hermes-reported window wins — NOT inferredContextWindow's
        // nominal 262,144 for kimi (#4).
        #expect(ok)
        #expect(chatStore.activeModelName == "kimi-k2.6")
        #expect(chatStore.contextWindow == 190_000)
        #expect(chatStore.resolvedContextWindow(fallbackModelName: "kimi-k2.6") == 190_000)
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
}
