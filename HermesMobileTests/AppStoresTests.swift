import Foundation
import Testing
@testable import HermesMobile

struct AppStoresTests {

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
                    backendEndpoint: request.environment.baseURLString,
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
        func normalizePairingCode(_ rawCode: String) throws -> String {
            try PhonePairingCode.normalize(rawCode)
        }

        func redeemPairingCode(
            _ normalizedCode: String,
            request: DeviceRegistrationRequest
        ) async throws -> PairingRedeemResult {
            PairingRedeemResult(
                configuration: PairedRelayConfiguration(
                    baseURLString: request.environment.baseURLString,
                    hostDisplayName: URL(string: request.environment.baseURLString)?.host ?? request.environment.baseURLString,
                    pairedAt: .now
                ),
                state: AppSessionState(
                    userID: UUID(),
                    displayName: "Morgan",
                    deviceID: UUID(),
                    installationID: request.installationID,
                    deviceRegistered: true,
                    connectionStatus: .connected,
                    syncStatus: .synced,
                    isMockMode: false,
                    backendEndpoint: request.environment.baseURLString,
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

        func fetchCurrentHost(accessToken: String?) async throws -> HermesHostStatus? {
            currentHost
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

        func send(message: String, clientMessageID: UUID) async -> Message {
            sendCallCount += 1
            lastClientMessageID = clientMessageID
            return nextResponse
        }

        func loadConversation() async -> Conversation {
            currentConversation ?? Conversation(title: "Hermes")
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
    func chatStorePassesClientMessageIDAndSkipsPendingDuplicate() async throws {
        let hermesClient = RecordingHermesClient()
        let chatStore = ChatStore(hermesClient: hermesClient)

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
            environmentProvider: { .production }
        )

        let setupCode = makeSetupCode()
        let didPair = await pairingStore.pair(using: setupCode)

        #expect(didPair)
        #expect(pairingStore.pairedRelayConfiguration?.hostDisplayName == "hermes-mobile-relay-dylan.fly.dev")
        #expect(persistence.loadPairedRelayConfiguration()?.baseURLString == AppEnvironment.production.baseURLString)
        #expect(await secureStore.retrieve(key: "session.accessToken") == "paired-access-token-ABCDEFGH")
        #expect(sessionStore.state.displayName == "Morgan")
    }

    @Test @MainActor
    func hostStoreGeneratesEnrollmentCodeAndClearsOnRevoke() async throws {
        let service = RecordingHermesHostService()
        service.currentHost = HermesHostStatus(
            id: UUID(),
            displayName: "Home Mac mini",
            hostname: "dylans-mac-mini",
            platform: "macos",
            connectorVersion: "0.1.0",
            hermesCommand: "hermes",
            hermesVersion: "hermes 1.2.3",
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
            environmentProvider: { .production }
        )

        let setupCode = makeSetupCode()
        _ = await pairingStore.pair(using: setupCode)

        await pairingStore.disconnect()

        #expect(pairingStore.pairedRelayConfiguration == nil)
        #expect(persistence.loadPairedRelayConfiguration() == nil)
        #expect(await secureStore.retrieve(key: "session.accessToken") == nil)
        #expect(sessionStore.state.deviceRegistered == false)
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
}
