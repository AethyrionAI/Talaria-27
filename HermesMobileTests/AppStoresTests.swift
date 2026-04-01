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
        settingsStore.settings.analyticsEnabled = true

        let reloaded = persistence.loadUserSettings()
        #expect(reloaded?.environment == .staging)
        #expect(reloaded?.analyticsEnabled == true)
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
                analyticsEnabled: false,
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
}
