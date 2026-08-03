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
                    lastSyncAt: nil
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
                lastSyncAt: .now
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
                    lastSyncAt: .now
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
                lastSyncAt: .now
            )
        )

        let bootstrapService = RecordingSessionBootstrapService()
        let secureStore = MockSecureStore()
        let sessionStore = AppSessionStore(
            bootstrapService: bootstrapService,
            syncCoordinator: MockSyncCoordinator(),
            secureStore: secureStore,
            persistence: persistence,
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
                    lastSyncAt: nil
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
                lastSyncAt: .now
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
                    lastSyncAt: .now
                )
            )
        }
        return AppSessionStore(
            bootstrapService: bootstrapService,
            syncCoordinator: MockSyncCoordinator(),
            secureStore: secureStore,
            persistence: persistence,
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

        await voiceService.handleAudioInterruptionEnded(shouldResume: true)

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

        await voiceService.handleAudioRouteChange(.oldDeviceUnavailable)

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
    func liveVoiceSessionServiceSwallowsNoOpCancelRaceWithoutFailingSession() async throws {
        // #119a: a barge-in cancel racing an already-completed response must
        // not banner the backend string or flag the connection failed — that
        // false `.failed` was also what wedged the header on CONNECTING
        // mid-conversation (#119b).
        let apiClient = RelayAPIClient(
            baseURLProvider: { "https://relay.example.com/v1" }
        )
        let voiceService = LiveVoiceSessionService(
            apiClient: apiClient,
            accessTokenProvider: { "token" }
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

    @Test @MainActor
    func settingsStorePersistsCustomRelayConfiguration() async throws {
        let suiteName = "settings-store-relay-config-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let persistence = UserDefaultsAppPersistenceStore(defaults: defaults)
        let settingsStore = SettingsStore(
            persistence: persistence,
            buildConfiguration: AppBuildConfiguration(
                supportURL: nil,
                termsOfServiceURL: nil,
                privacyPolicyURL: nil
            )
        )

        settingsStore.settings.relayConfiguration = RelayConfiguration(
            customRelayBaseURL: "https://demo.example.com/v1"
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

    @MainActor
    private final class BlackHoleSessionBootstrapService: SessionBootstrapServiceProtocol {
        let gate: BlackHoleGate
        var registerCallCount = 0
        var loadCallCount = 0
        /// The user the relay reports for this session once it finally
        /// answers. Mismatching the paired user proves
        /// `validateRestoredIdentity` ran strictly AFTER bootstrap (#3/#46).
        var sessionUserID = UUID()

        init(gate: BlackHoleGate) {
            self.gate = gate
        }

        func registerDevice(_ request: DeviceRegistrationRequest) async throws -> SessionBootstrapResponse {
            registerCallCount += 1
            try await gate.wait()
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
                    lastSyncAt: nil
                ),
                tokens: AuthTokens(
                    accessToken: "blackhole-access-token",
                    refreshToken: "blackhole-refresh-token",
                    expiresAt: .distantFuture
                )
            )
        }

        func loadSession(accessToken: String?) async throws -> AppSessionState {
            loadCallCount += 1
            try await gate.wait()
            return AppSessionState(
                userID: sessionUserID,
                displayName: "Hermes User",
                deviceID: UUID(),
                installationID: UUID(),
                deviceRegistered: true,
                connectionStatus: .connected,
                syncStatus: .synced,
                isMockMode: false,
                backendEndpoint: AppEnvironment.production.baseURLString,
                lastSyncAt: .now
            )
        }

        func refreshAuth(refreshToken: String) async throws -> AuthTokens {
            throw RelayAPIClient.ClientError.requestFailed("no refresh in black-hole launch tests")
        }

        func revokeCurrentSession(accessToken: String?) async throws {}
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

        func fetchCurrentHost(accessToken: String?) async throws -> HermesHostStatus? {
            fetchCallCount += 1
            try await gate.wait()
            return host
        }

        func createEnrollmentCode(accessToken: String?) async throws -> HostEnrollmentCode {
            HostEnrollmentCode(
                setupCode: "HC1:blackhole-setup-code",
                expiresAt: .distantFuture,
                relayHost: "relay.example.test"
            )
        }

        func revokeCurrentHost(accessToken: String?) async throws {}
    }

    @MainActor
    private final class BlackHoleInboxService: InboxServiceProtocol {
        let gate: BlackHoleGate
        var fetchCallCount = 0

        init(gate: BlackHoleGate) {
            self.gate = gate
        }

        func fetchInbox(accessToken: String?) async throws -> [InboxItem] {
            fetchCallCount += 1
            try await gate.wait()
            return [InboxItem(type: .alert, title: "Landed after uplink", body: "Delivered by background init")]
        }

        func submitAction(itemID: UUID, actionID: String, accessToken: String?) async throws -> InboxActionResult {
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

    /// A fully wired bare container whose every relay surface rides a
    /// black-hole gate, paired with a valid Keychain-local session so the
    /// launch guards pass.
    @MainActor
    private struct LaunchHarness {
        let container: AppContainer
        let bootstrapGate: BlackHoleGate
        let hostGate: BlackHoleGate
        let inboxGate: BlackHoleGate
        let bootstrapService: BlackHoleSessionBootstrapService
        let hostService: BlackHoleHermesHostService
        let inboxService: BlackHoleInboxService
        let pairedUserID: UUID

        func openAllGates() {
            bootstrapGate.open()
            hostGate.open()
            inboxGate.open()
        }
    }

    @MainActor
    private func makeLaunchHarness(
        suiteName: String,
        sessionUserMatchesPairedUser: Bool,
        chatClient: (any HermesClientProtocol)? = nil
    ) async -> LaunchHarness {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let persistence = UserDefaultsAppPersistenceStore(defaults: defaults)

        let secureStore = MockSecureStore()
        await secureStore.store(key: "session.accessToken", value: "launch-access-token")
        await secureStore.store(key: "session.refreshToken", value: "launch-refresh-token")

        let pairedUserID = UUID()
        persistence.savePairedRelayConfiguration(
            PairedRelayConfiguration(
                baseURLString: "https://relay.example.test/v1",
                hostDisplayName: "relay.example.test",
                pairedAt: .now,
                relayUserID: pairedUserID
            )
        )

        let bootstrapGate = BlackHoleGate()
        let hostGate = BlackHoleGate()
        let inboxGate = BlackHoleGate()

        let bootstrapService = BlackHoleSessionBootstrapService(gate: bootstrapGate)
        bootstrapService.sessionUserID = sessionUserMatchesPairedUser ? pairedUserID : UUID()

        let sessionStore = AppSessionStore(
            bootstrapService: bootstrapService,
            syncCoordinator: MockSyncCoordinator(),
            secureStore: secureStore,
            persistence: persistence,
            environmentProvider: { .production }
        )
        let pairingStore = PairingStore(
            pairingService: RecordingPairingService(),
            sessionStore: sessionStore,
            persistence: persistence,
            environmentProvider: { .production },
            relayBaseURLProvider: { "https://relay.example.test/v1" }
        )
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
        let hostStore = HermesHostStore(
            hostService: hostService,
            accessTokenProvider: { await sessionStore.currentAccessToken() }
        )
        let inboxService = BlackHoleInboxService(gate: inboxGate)
        let container = AppContainer(
            sessionStore: sessionStore,
            pairingStore: pairingStore,
            hostStore: hostStore,
            chatStore: ChatStore(hermesClient: chatClient ?? RecordingHermesClient(), persistence: persistence),
            inboxStore: InboxStore(
                inboxService: inboxService,
                persistence: persistence,
                sessionStore: sessionStore
            ),
            permissionsStore: PermissionsStore(
                locationService: MockLocationService(),
                healthService: MockHealthService(),
                    mediaService: MockMediaService()
            ),
            settingsStore: SettingsStore(persistence: persistence),
            talkStore: TalkStore(voiceService: RecordingVoiceSessionService()),
            modelsShimClient: ModelsShimClient(baseURLProvider: { nil }, tokenProvider: { nil })
        )
        return LaunchHarness(
            container: container,
            bootstrapGate: bootstrapGate,
            hostGate: hostGate,
            inboxGate: inboxGate,
            bootstrapService: bootstrapService,
            hostService: hostService,
            inboxService: inboxService,
            pairedUserID: pairedUserID
        )
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
            suiteName: "profile-switch-resets-host-fed-stores",
            sessionUserMatchesPairedUser: true
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
            gatewayBaseURL: "http://new-host:8642",
            relayBaseURL: "http://new-host:8000/v1"
        ))

        #expect(skillsStore.skills.isEmpty)
        #expect(!skillsStore.hasLoaded)
        #expect(cronStore.jobs.isEmpty)
        #expect(!cronStore.hasLoaded)
        #expect(insightsStore.rows.isEmpty)
        #expect(!insightsStore.hasLoaded)
    }

    @Test @MainActor
    func bootstrapProbeSessionUsesShortTimeouts() {
        // #136 non-negotiable 4: launch/bootstrap probes must converge in
        // seconds against a black-holed host (firewall DROP → no TCP
        // refusal → the full request timeout, -1001) — never URLSession's
        // default 60s.
        let session = RelayAPIClient.makeBootstrapProbeSession()
        #expect(session.configuration.timeoutIntervalForRequest == RelayAPIClient.bootstrapProbeRequestTimeout)
        #expect(session.configuration.timeoutIntervalForResource == RelayAPIClient.bootstrapProbeResourceTimeout)
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

        // #3/#46: identity validation stays ordered strictly after bootstrap.
        let background = AppContainer.LaunchInitStep.backgroundBootstrap
        let bootstrapIndex = background.firstIndex(of: .sessionBootstrap)
        let validateIndex = background.firstIndex(of: .validateRestoredIdentity)
        #expect(bootstrapIndex != nil && validateIndex != nil)
        if let bootstrapIndex, let validateIndex {
            #expect(bootstrapIndex < validateIndex)
        }

        // The partition is total: every step lives in exactly one list.
        let partitioned = AppContainer.LaunchInitStep.criticalPath + background
        #expect(partitioned.count == AppContainer.LaunchInitStep.allCases.count)
        #expect(Set(partitioned) == Set(AppContainer.LaunchInitStep.allCases))
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
            suiteName: "foreground-uiwrite-\(UUID().uuidString)",
            sessionUserMatchesPairedUser: true
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
        #expect(harness.hostService.fetchCallCount > 0,
                "the activation never reached the host fetch, so nothing was actually blocked")

        harness.openAllGates()
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
            suiteName: "foreground-deadline-\(UUID().uuidString)",
            sessionUserMatchesPairedUser: true
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
            suiteName: "foreground-deadline-healthy-\(UUID().uuidString)",
            sessionUserMatchesPairedUser: true
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
            suiteName: "foreground-supersede-\(UUID().uuidString)",
            sessionUserMatchesPairedUser: true
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
    func blackHoledRelayDoesNotHoldTheLaunchSplash() async throws {
        let harness = await makeLaunchHarness(
            suiteName: "launch-blackhole-\(UUID().uuidString)",
            sessionUserMatchesPairedUser: false
        )
        let container = harness.container
        #expect(container.shouldShowLaunchSplash)

        let initTask = Task { @MainActor in await container.initialize() }

        // The splash must drop on local-state-ready — with every relay
        // surface still black-holed (#136 non-negotiable 1/7).
        let splashDropped = await pollUntil { !container.shouldShowLaunchSplash }
        #expect(splashDropped, "splash must drop without awaiting the black-holed relay")

        // Nothing relay-backed has landed yet, and the #3/#46 identity check
        // (strictly after bootstrap) has not run.
        #expect(container.pairingStore.identityMismatchDetected == false)
        #expect(container.hostStore.currentHost == nil)
        #expect(container.inboxStore.items.isEmpty)

        // Relay comes back: background init lands state live.
        harness.openAllGates()
        let backgroundLanded = await pollUntil {
            container.hostStore.isHostOnline && !container.inboxStore.items.isEmpty
        }
        #expect(backgroundLanded, "background init must land host + inbox state once the relay answers")

        // The relay session reported a DIFFERENT user than the pairing
        // minted — only the post-bootstrap validation can see that, so the
        // flag proves bootstrap → validateRestoredIdentity ordering held.
        let identityValidated = await pollUntil { container.pairingStore.identityMismatchDetected }
        #expect(identityValidated, "validateRestoredIdentity must run after bootstrap completes")

        await initTask.value
    }

    @Test @MainActor
    func launchBootstrapIsSingleFlight() async throws {
        let harness = await makeLaunchHarness(
            suiteName: "launch-singleflight-\(UUID().uuidString)",
            sessionUserMatchesPairedUser: true
        )
        let container = harness.container

        let first = Task { @MainActor in await container.initialize() }
        let second = Task { @MainActor in await container.initialize() }

        let bootstrapStarted = await pollUntil { harness.bootstrapService.registerCallCount >= 1 }
        #expect(bootstrapStarted)

        harness.openAllGates()
        await first.value
        await second.value
        let settled = await pollUntil { container.hostStore.isHostOnline }
        #expect(settled)

        #expect(harness.bootstrapService.registerCallCount == 1, "concurrent initialize() must run bootstrap once")
    }

    @Test @MainActor
    func resetDuringBackgroundInitLandsNoStaleState() async throws {
        let harness = await makeLaunchHarness(
            suiteName: "launch-resetrace-\(UUID().uuidString)",
            sessionUserMatchesPairedUser: true
        )
        let container = harness.container
        // Bootstrap answers immediately; the HOST probe is the in-flight
        // black hole the reset must supersede.
        harness.bootstrapGate.open()

        let initTask = Task { @MainActor in await container.initialize() }
        let hostProbeInFlight = await pollUntil { harness.hostService.fetchCallCount >= 1 }
        #expect(hostProbeInFlight)

        // Unpair while the host probe hangs (#136 non-negotiable 5 — the
        // ~1847 reset site must cancel/supersede in-flight background init).
        await container.handlePairingRemoved()

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
            suiteName: "launch-repair-\(UUID().uuidString)",
            sessionUserMatchesPairedUser: true
        )
        let container = harness.container

        let initTask = Task { @MainActor in await container.initialize() }
        let bootstrapStarted = await pollUntil { harness.bootstrapService.registerCallCount >= 1 }
        #expect(bootstrapStarted)

        // Re-pair while the first bootstrap hangs black-holed (#136
        // non-negotiable 5 — the ~1271 reset site supersedes, and the fresh
        // initialize() must actually re-run bootstrap, not silently skip it
        // on AppSessionStore's isBootstrapping re-entry guard).
        let rePairTask = Task { @MainActor in await container.handlePairingActivated() }
        let secondBootstrapStarted = await pollUntil { harness.bootstrapService.registerCallCount >= 2 }
        #expect(secondBootstrapStarted, "re-pair must supersede the in-flight bootstrap and run a fresh one")

        harness.openAllGates()
        await initTask.value
        await rePairTask.value

        let settled = await pollUntil { container.hostStore.isHostOnline }
        #expect(settled)
        #expect(container.pairingStore.identityMismatchDetected == false)
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
            sessionUserMatchesPairedUser: true,
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

        await container.handlePairingActivated()

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
