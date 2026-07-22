import Foundation
import UIKit
import os

private let containerLog = Logger(subsystem: "org.aethyrion.talaria", category: "AppContainer")

@MainActor
@Observable
final class AppContainer {
    static let apnsTokenDefaultsKey = "hermes.apns.deviceToken"
    private static let sharedDefaultContainer = AppContainer.makeDefault()

    let router = TabRouter()
    let sessionStore: AppSessionStore
    let pairingStore: PairingStore
    let hostStore: HermesHostStore
    let chatStore: ChatStore
    let inboxStore: InboxStore
    let permissionsStore: PermissionsStore
    let settingsStore: SettingsStore
    let talkStore: TalkStore
    /// Local read-aloud TTS for Hermes replies (#2). Created here (not via
    /// init) so every construction path gets one; wired in makeDefault().
    let speechOutput = SpeechOutputService()
    /// #129: the native voice pipeline's TTS instance — no session
    /// management, no isBlocked gate — so mid-session voice previews play
    /// OVER the live Talk session instead of re-categorizing the shared
    /// audio session under it (the #128 trigger). Replaced in makeDefault()
    /// with the instance the pipeline actually speaks through; the default
    /// here keeps bare test containers session-safe.
    private(set) var nativeSpeechOutput: SpeechOutputService = {
        let service = SpeechOutputService()
        service.managesAudioSession = false
        return service
    }()
    /// #123: drains the share-extension inbox on foreground. Created here so
    /// every construction path gets one; free-tier surface — its drain runs
    /// BEFORE (and independent of) the pairing-gated foreground work.
    let shareInboxDrainer = ShareInboxDrainer()
    /// On-device FoundationModels intelligence (#4.8 × #4.15): conversation
    /// titles + previews, reasoning condensation. Cheap to create (no model
    /// load until first use); wired to ChatStore in makeDefault(). Shared
    /// with LocalChatBackend (#26) so the tokenizer-facing helpers have one
    /// home — injected via init since #27.
    let localIntelligence: LocalIntelligenceService
    /// #27: the two-brain router in front of ChatStore's client seam. Nil in
    /// bare test containers that construct stores directly.
    private(set) var chatBackendRouter: ChatBackendRouter?
    /// #26/#31: the on-device brain, kept for the standalone availability
    /// state (and the #30 PCC tier). Nil in bare test containers.
    private(set) var localChatBackend: LocalChatBackend?
    /// #97: the pin/archive overlay for server-session rows, consumed by the
    /// sessions drawer + conversation search. Nil in bare test containers
    /// that construct stores directly.
    private(set) var conversationListState: ConversationListStateStore?
    /// Lane M (#114): the named backend profiles — active + sensor
    /// destination + per-profile credential scoping. Nil in bare test
    /// containers that construct stores directly (legacy single-backend
    /// behavior).
    private(set) var profilesStore: BackendProfilesStore?
    /// Lane M: session→birth-profile index, written by the Sessions client.
    private(set) var sessionProfileIndex: SessionProfileIndexStore?
    /// Lane M PR 2: per-profile relay access for non-active backends —
    /// pinned sensors (M-8), per-relay push (M-7), dormant refresh (M-9).
    private(set) var profileRelaySessions: ProfileRelaySessionFactory?
    /// Lane M PR 2: in-memory gateway API keys for EVERY profile (Keychain
    /// reads are async; per-session endpoint resolution is sync).
    fileprivate var gatewayKeyCache: ProfileGatewayKeyCache?
    /// Lane M: the concrete Sessions client, kept for the surfaces that are
    /// profile-aware by nature (M-16's new-chat-on-profile override).
    private(set) var sessionsChatClient: SessionsHermesClient?
    /// #156a: the Tasks (scheduled cron jobs) store — rides the ACTIVE
    /// profile's gateway endpoint, same auth as the Sessions chat client.
    /// Nil in bare test containers that construct stores directly.
    private(set) var cronJobsStore: CronJobsStore?
    /// #156b: the installed-skills browser store — same gateway endpoint +
    /// auth plane as the cron jobs store; read-only (`GET /v1/skills` is the
    /// only skill route). Nil in bare test containers.
    private(set) var skillsStore: SkillsStore?
    /// #116: post-pair provisioning bundle — auto-fills a profile's shim
    /// URL/token (+ empty gateway URL) from the relay after a successful
    /// pair, and backs the Server screen's "Refresh Provisioning" action.
    private(set) var provisioningService: ProvisioningService?
    /// #127: the Connected-tier entitlement source (StoreKit 2). Nil in bare
    /// test containers; `connectGateVerdict(for:)` treats nil as unknown,
    /// which only matters once the (dormant) gate is active.
    private(set) var entitlementService: (any EntitlementServiceProtocol)?
    /// M-9 thrash guard: dormant-refresh attempts this process, so a failing
    /// relay isn't re-tried on every foreground.
    private var dormantRefreshAttempts: [UUID: Date] = [:]
    /// #125: on-device Health Trends daily-bucket queries, gated on the
    /// LiveHealthService auth surface. Nil in bare test containers that
    /// construct stores directly.
    private(set) var healthTrendsService: (any HealthTrendsServiceProtocol)?
    /// #17: Spotlight donation for sessions + agent files, strictly behind the
    /// Privacy toggle (default OFF); wired in makeDefault().
    let spotlightIndexing = SpotlightIndexingService()
    /// #16: AlarmKit executor behind the /alarm confirm gate. Stateless until
    /// first use (authorization requested on first schedule).
    let alarmService = AlarmService()
    /// #47: honest failure notices for lock-screen replies (the typed text
    /// must never vanish silently on a headless send failure).
    private let localNotifications = LocalNotificationService()
    /// #29: the shared confirm gate for side-effecting device tools — stages
    /// a card in the chat transcript and suspends the tool until the user
    /// decides. Defaults closed (app death = nothing created).
    let toolConfirmationCenter = ToolConfirmationCenter()
    let modelsShimClient: ModelsShimClient
    let sensorUploadService: SensorUploadService?
    private let apiClient: RelayAPIClient?
    /// #136: short-timeout client for launch/bootstrap-class probes (command
    /// catalog, push register). Nil in bare test containers — probe calls
    /// fall back to `apiClient`.
    private let probeAPIClient: RelayAPIClient?
    private let notificationService: (any NotificationServiceProtocol)?
    private let secureStore: (any SecureStoreProtocol)?
    private(set) var hermesAPIKey: String = ""
    private(set) var modelsShimToken: String = ""
    private var _chatAPIKeyBox: MutableHermesAPIKeyBox?
    private var _shimTokenBox: MutableShimTokenBox?
    private var isInitialized = false
    /// #136: the relay-backed half of launch, running behind the live UI.
    /// Doubles as the single-flight gate and the splash suppressor; exposed
    /// read-only so tests can await background completion deterministically.
    private(set) var backgroundBootstrapTask: Task<Void, Never>?
    /// #136: bumped by every reset/supersede site — a background bootstrap
    /// only touches container state while its generation is current.
    private var bootstrapGeneration = 0
    /// #136: a superseded run may still be unwinding its cancelled awaits;
    /// the next run drains it first so a half-dead bootstrap can't
    /// interleave with the fresh one.
    private var supersededBootstrapDrain: Task<Void, Never>?
    private var lastCommandCatalogRefreshAt: Date?
    private var lastKnownHostOnline = false
    /// Edge tracker for the talk-session read-aloud cutoff (#84): the
    /// onSessionStateChanged callback fires on every state tick during a
    /// session, but the read-aloud stop() belongs only on the OFF->ON edge.
    private var lastKnownTalkSessionActive = false

    private static let commandCatalogRefreshInterval: TimeInterval = 60

    init(
        sessionStore: AppSessionStore,
        pairingStore: PairingStore,
        hostStore: HermesHostStore,
        chatStore: ChatStore,
        inboxStore: InboxStore,
        permissionsStore: PermissionsStore,
        settingsStore: SettingsStore,
        talkStore: TalkStore,
        modelsShimClient: ModelsShimClient,
        sensorUploadService: SensorUploadService? = nil,
        apiClient: RelayAPIClient? = nil,
        probeAPIClient: RelayAPIClient? = nil,
        notificationService: (any NotificationServiceProtocol)? = nil,
        secureStore: (any SecureStoreProtocol)? = nil,
        localIntelligence: LocalIntelligenceService = LocalIntelligenceService(),
        chatBackendRouter: ChatBackendRouter? = nil
    ) {
        self.sessionStore = sessionStore
        self.pairingStore = pairingStore
        self.hostStore = hostStore
        self.chatStore = chatStore
        self.inboxStore = inboxStore
        self.permissionsStore = permissionsStore
        self.settingsStore = settingsStore
        self.talkStore = talkStore
        self.modelsShimClient = modelsShimClient
        self.sensorUploadService = sensorUploadService
        self.apiClient = apiClient
        self.probeAPIClient = probeAPIClient
        self.notificationService = notificationService
        self.secureStore = secureStore
        self.localIntelligence = localIntelligence
        self.chatBackendRouter = chatBackendRouter
    }

    static func sharedDefault() -> AppContainer {
        sharedDefaultContainer
    }

    var shouldShowLaunchSplash: Bool {
        if pairingStore.isPaired && !isInitialized { return true }
        // #136: a bootstrap riding the launch background task must NOT hold
        // the splash — the critical path is local-only by design. Bootstraps
        // outside that task (profile-switch re-home, unpaired forced
        // re-registration) keep today's splash.
        return sessionStore.isBootstrapping && backgroundBootstrapTask == nil
    }

    // MARK: - Launch partition (#136)

    /// The launch-path partition: which init steps may run before the splash
    /// drops. Pure data so tests can assert no network-touching step ever
    /// creeps in front of `isInitialized = true`, and that the relay-backed
    /// steps keep their load-bearing order (#3/#46: identity validation
    /// strictly after bootstrap). `initialize()` and
    /// `runBackgroundBootstrap(generation:)` mirror these lists step for
    /// step — a new init step belongs in exactly one list.
    enum LaunchInitStep: CaseIterable, Sendable {
        // Critical path — local-only, in order.
        case reloadCapabilities
        case loadConversationCache
        case startSensorService
        case reconcileLiveActivities
        case updateWidgetData
        case drainShareInbox
        // Background bootstrap — relay/shim-backed, in order.
        case sessionBootstrap
        case validateRestoredIdentity
        case hostRefresh
        case inboxLoad
        case commandCatalogRefresh
        case shimModelSeed
        case pushTokenRegistration
        case sensorForegroundRefresh

        /// Whether the step can touch the network. `validateRestoredIdentity`
        /// is itself local but rides the background list for ordering
        /// (#3/#46); `loadConversationCache` is the persisted-cache restore
        /// (its no-cache fallback fetch rides the chat path, whose timeouts
        /// #136 deliberately leaves alone). `sensorForegroundRefresh` drains
        /// the sensor outbox — an inline relay upload — which is why it is
        /// NOT on the critical path even though `startSensorService` is.
        var touchesNetwork: Bool {
            switch self {
            case .reloadCapabilities, .loadConversationCache, .startSensorService,
                 .reconcileLiveActivities, .updateWidgetData, .drainShareInbox,
                 .validateRestoredIdentity:
                false
            case .sessionBootstrap, .hostRefresh, .inboxLoad, .commandCatalogRefresh,
                 .shimModelSeed, .pushTokenRegistration, .sensorForegroundRefresh:
                true
            }
        }

        /// The steps allowed to run before `isInitialized = true` drops the
        /// splash (#136 non-negotiable 1). Local-only, by construction.
        static let criticalPath: [LaunchInitStep] = [
            .reloadCapabilities, .loadConversationCache, .startSensorService,
            .reconcileLiveActivities, .updateWidgetData, .drainShareInbox,
        ]

        /// The relay-backed steps the background task runs, in order
        /// (#136 non-negotiable 2). Degraded is the DEFAULT launch posture —
        /// these upgrade it as each lands.
        static let backgroundBootstrap: [LaunchInitStep] = [
            .sessionBootstrap, .validateRestoredIdentity, .hostRefresh, .inboxLoad,
            .commandCatalogRefresh, .shimModelSeed, .pushTokenRegistration,
            .sensorForegroundRefresh,
        ]
    }

    // MARK: - Connect gate (#127)

    /// The one seam every gated connect entry point asks. Composes the
    /// dormant config flag (+ the DEBUG Developer-screen override) with the
    /// entitlement service's live + cached state into `ConnectGate`'s pure
    /// verdict. While `MonetizationConfiguration.isEnabled` is false and no
    /// DEBUG override is set, this always returns `.allow`.
    func connectGateVerdict(for attempt: ConnectAttempt) -> ConnectGateVerdict {
        var monetizationActive = MonetizationConfiguration.isEnabled
        var state = entitlementService?.entitlementState ?? .unknown
        let cached = entitlementService?.cachedEntitlement
        #if DEBUG
        monetizationActive = MonetizationDebugRules.effectiveGateActive(
            configuredEnabled: monetizationActive,
            debugGateEnabled: MonetizationDebugSettings.gateEnabled
        )
        state = MonetizationDebugRules.effectiveEntitlementState(
            real: state,
            override: MonetizationDebugSettings.entitlementOverride
        )
        #endif
        return ConnectGate.verdict(
            monetizationActive: monetizationActive,
            attempt: attempt,
            state: state,
            cachedEntitlement: cached
        )
    }

    static func makeDefault(
        defaults: UserDefaults? = nil,
        processEnvironment: [String: String] = ProcessInfo.processInfo.environment
    ) -> AppContainer {
        let resolvedDefaults: UserDefaults
        if let defaults {
            resolvedDefaults = defaults
        } else if let suiteName = processEnvironment["UITEST_DEFAULTS_SUITE"] {
            resolvedDefaults = UserDefaults(suiteName: suiteName) ?? .standard
        } else {
            resolvedDefaults = .standard
        }

        let buildConfiguration = AppBuildConfiguration.current()
        // #135: UI-test runs build unsigned (CODE_SIGNING_ALLOWED=NO), and
        // the entitlement-stripped build can't write the iOS 27 simulator
        // keychain — paired tokens vanished on write and initialize()'s
        // no-access-token guard un-paired the app instantly. UI tests get a
        // defaults-suite-backed store (relaunch-durable via
        // UITEST_DEFAULTS_SUITE); the reinstall-survival keychain mirror is
        // meaningless there and stays nil.
        let secureStore: any SecureStoreProtocol
        let keychainMirror: KeychainSecureStore?
        if let uiTestKeychainService = processEnvironment["UITEST_KEYCHAIN_SERVICE"] {
            secureStore = UITestSecureStore(
                serviceName: uiTestKeychainService,
                defaults: resolvedDefaults
            )
            keychainMirror = nil
        } else {
            let keychain = KeychainSecureStore(serviceName: "org.aethyrion.talaria.session")
            secureStore = keychain
            keychainMirror = keychain
        }
        // Keychain-mirrored so the pairing config survives clean reinstalls,
        // like the session tokens already do (#41).
        let persistence = UserDefaultsAppPersistenceStore(
            defaults: resolvedDefaults,
            keychainMirror: keychainMirror
        )
        let settingsStore = SettingsStore(
            persistence: persistence,
            buildConfiguration: buildConfiguration
        )
        // Lane M (#114): the backend profiles. Construction runs the one-shot
        // migration — the first launch after this ships mints an "OJAMD"
        // profile from the pre-profile settings values (which stop being
        // app-wide truth and become that profile's seeds), keeping the
        // legacy credential keys so nothing in the Keychain moves.
        let profilesStore = BackendProfilesStore(
            persistence: persistence,
            migrationSeeds: BackendProfilesStore.MigrationSeeds(
                gatewayBaseURL: settingsStore.settings.hermesAPIBaseURL,
                relayBaseURL: settingsStore.settings.relayConfiguration.activeBaseURLString,
                shimBaseURL: settingsStore.settings.modelsShimBaseURL
            )
        )
        let sessionProfileIndex = SessionProfileIndexStore(persistence: persistence)
        // #25: session→last-run-usage index — the CTX gauge's resume cache.
        let sessionUsageIndex = SessionUsageIndexStore(persistence: persistence)
        // Seed the runtime theme from the persisted appearance prefs before the
        // first frame renders, so a saved non-cyan accent never flashes cyan.
        // (Live updates are mirrored from the app root via ThemeRuntime.apply.)
        ThemeRuntime.shared.apply(settingsStore.settings)
        // Sync the verbose-logging bridge from the persisted flag at launch —
        // otherwise the Developer toggle is the only writer and the bridge can
        // drift from UserSettings across restores (#29).
        TalariaLog.setVerbose(settingsStore.settings.verboseLogging)
        let syncCoordinator = MockSyncCoordinator()
        let notificationService = LiveNotificationService()
        let allowMockFallbacks = AppEnvironmentPolicy.currentBuild.allowsEnvironmentOverrides
        let usesMockPairingService = processEnvironment["UITEST_PAIRING_MODE"] == "mock"
        let pairingService: any PairingServiceProtocol
        var activePairingStore: PairingStore?

        if processEnvironment["UITEST_PAIRING_MODE"] == "mock" {
            pairingService = MockPairingService()
        } else {
            pairingService = LivePairingService()
        }

        let relayBaseURLProvider: @MainActor () -> String = {
            activePairingStore?.pairedRelayConfiguration?.baseURLString
                ?? profilesStore.activeProfile?.relayBaseURL
                ?? ""
        }
        let apiClient = RelayAPIClient(baseURLProvider: relayBaseURLProvider)
        // #136: launch/bootstrap probes ride a dedicated short-timeout
        // session so a black-holed relay fails in seconds and background
        // init converges quickly instead of chaining 60s hangs. Probe-class
        // surfaces only — SSE, file downloads, and sensor uploads keep the
        // default-session client.
        let bootstrapProbeClient = RelayAPIClient(
            baseURLProvider: relayBaseURLProvider,
            session: RelayAPIClient.makeBootstrapProbeSession()
        )

        let sessionBootstrapService = ResilientSessionBootstrapService(
            primary: LiveSessionBootstrapService(apiClient: bootstrapProbeClient),
            fallback: MockSessionBootstrapService(),
            allowsFallback: { allowMockFallbacks && (activePairingStore?.isPaired != true || usesMockPairingService) }
        )

        let sessionStore = AppSessionStore(
            bootstrapService: sessionBootstrapService,
            syncCoordinator: syncCoordinator,
            secureStore: secureStore,
            persistence: persistence,
            notificationService: notificationService,
            environmentProvider: { settingsStore.settings.environment },
            credentialScopeProvider: { profilesStore.activeProfile?.credentialScopeID }
        )

        let runtimePairingStore = PairingStore(
            pairingService: pairingService,
            sessionStore: sessionStore,
            persistence: persistence,
            environmentProvider: { settingsStore.settings.environment },
            relayBaseURLProvider: { profilesStore.activeProfile?.relayBaseURL },
            profileResolver: { id in profilesStore.resolvedProfile(id: id) }
        )
        activePairingStore = runtimePairingStore

        // #15: one 401-recovery ladder for every relay-token consumer (host,
        // sensors, talk). Refresh first; if the refresh token itself is dead,
        // silently re-register this installation (the relay preserves the
        // device→user binding) and re-validate identity before handing the
        // fresh token back. Returns nil when nothing was recovered — the
        // stored token just 401'd, so retrying with it would only burn a
        // doomed request.
        let relayAccessTokenRefresher: @MainActor () async -> String? = {
            switch await sessionStore.refreshAccessTokenIfNeeded() {
            case .refreshed:
                return await sessionStore.currentAccessToken()
            case .transientFailure:
                return nil
            case .missingRefreshToken, .rejected:
                guard await sessionStore.recoverSessionByReRegistering() else { return nil }
                runtimePairingStore.validateRestoredIdentity()
                // A recovered session that authenticates as the wrong relay
                // user is the #46 half-broken state — flag it (Diagnostics
                // shows RE-PAIR) and fail the request instead of quietly
                // acting as someone else.
                guard !runtimePairingStore.identityMismatchDetected else { return nil }
                return await sessionStore.currentAccessToken()
            }
        }

        let hostService: any HermesHostServiceProtocol
        if usesMockPairingService {
            hostService = MockHermesHostService()
        } else {
            hostService = LiveHermesHostService(
                apiClient: bootstrapProbeClient,
                accessTokenRefresher: relayAccessTokenRefresher
            )
        }

        // #45: the Inbox is a live surface now — no mock fallback. Real items
        // or an honest unreachable state; MockInboxService survives only for
        // the UITest harness (and unit tests), never a production path.
        // Constructed after relayAccessTokenRefresher so the Inbox rides the
        // same 401-recovery ladder as every other relay consumer.
        let inboxService: any InboxServiceProtocol = usesMockPairingService
            ? MockInboxService()
            : LiveInboxService(
                apiClient: bootstrapProbeClient,
                accessTokenRefresher: relayAccessTokenRefresher
            )

        let hostStore = HermesHostStore(
            hostService: hostService,
            accessTokenProvider: { await sessionStore.currentAccessToken() }
        )

        let hermesAPIKeyBox = MutableHermesAPIKeyBox()

        // #26/#27: shared on-device intelligence — also the P1 condenser.
        let localIntelligence = LocalIntelligenceService()

        // P1 (#90): the durable journal (conversation identity + hop handle)
        // and the transplant composer — one journal instance shared between
        // the Sessions client (reads the hop at send time) and ChatStore
        // (re-syncs it as the settled transcript changes).
        let journalStore = ConversationJournalStore(persistence: persistence)
        let transplanter = ContextTransplanter(intelligence: localIntelligence)

        // Lane M PR 2: sync per-profile endpoint resolution needs every
        // profile's gateway key in memory — loaded from the Keychain at
        // startup (below) and updated on save/switch.
        let gatewayKeyCache = ProfileGatewayKeyCache()

        let sessionsClient = SessionsHermesClient(
            baseURLProvider: {
                let raw = (profilesStore.activeProfile?.gatewayBaseURL ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return raw.isEmpty ? nil : raw
            },
            apiKeyProvider: { hermesAPIKeyBox.value },
            journal: journalStore,
            transplanter: transplanter,
            activeProfileIDProvider: { profilesStore.activeProfileID },
            profileIndex: sessionProfileIndex,
            usageIndex: sessionUsageIndex,
            profileEndpointResolver: { profileID in
                guard let profile = profilesStore.profile(id: profileID) else { return nil }
                let baseURL = profile.gatewayBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !baseURL.isEmpty,
                      let key = gatewayKeyCache.key(forScope: profile.credentialScopeID),
                      !key.isEmpty else { return nil }
                return (baseURL, key)
            },
            chatProfilesProvider: {
                // Every profile with a usable chat endpoint lists sessions
                // (M-5). The active profile always participates — its key
                // rides the box, which may be ahead of the cache briefly.
                profilesStore.profiles.filter { profile in
                    guard !profile.gatewayBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        return false
                    }
                    if profile.id == profilesStore.activeProfileID { return true }
                    return gatewayKeyCache.key(forScope: profile.credentialScopeID)?.isEmpty == false
                }
            }
        )
        let hermesClient = ResilientHermesClient(
            primary: sessionsClient,
            fallback: MockHermesClient(),
            allowsFallback: { allowMockFallbacks && (activePairingStore?.isPaired != true || usesMockPairingService) }
        )

        // #26/#27: the on-device brain + the two-brain router. The retry
        // wrapper stays on the Hermes side only — retries are a network
        // concern the local brain doesn't have. ChatStore talks to the router
        // as its one `any HermesClientProtocol`.
        let localChatBackend = LocalChatBackend(
            persistence: persistence,
            intelligence: localIntelligence
        )
        let chatBackendRouter = ChatBackendRouter(
            hermes: hermesClient,
            local: localChatBackend,
            // Routing signal: the direct chat path needs the Sessions API
            // key. (The key restores from the Keychain asynchronously below;
            // until it lands, a keyed device may briefly route local — the
            // chat screen's health probe re-resolves within seconds.)
            isHermesConfigured: { [hermesAPIKeyBox] in !hermesAPIKeyBox.value.isEmpty },
            // Picker-visibility signal: any Hermes host has ever been set up.
            hasHermesHost: { [hermesAPIKeyBox] in
                activePairingStore?.isPaired == true || !hermesAPIKeyBox.value.isEmpty
            }
        )

        // Talaria models-shim client (OJAMD tailnet). Auth priority:
        //  1. Dedicated shim token from Keychain (legacy / explicit override)
        //  2. DEBUG launch-env TALARIA_SHIM_TOKEN (simulator convenience)
        //  3. Hermes API server key (same key used for chat — zero-config)
        // Option 3 means the user never has to manually copy a second token;
        // the shim accepts both its own token AND the API server key (#14).
        let shimTokenBox = MutableShimTokenBox()
        let modelsShimClient = ModelsShimClient(
            baseURLProvider: {
                let raw = (profilesStore.activeProfile?.shimBaseURL ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return raw.isEmpty ? nil : raw
            },
            tokenProvider: { [hermesAPIKeyBox] in
                if !shimTokenBox.value.isEmpty { return shimTokenBox.value }
                #if DEBUG
                if let envToken = processEnvironment["TALARIA_SHIM_TOKEN"], !envToken.isEmpty {
                    return envToken
                }
                #endif
                // Fall back to the Hermes API key — the shim accepts it as an
                // alternate bearer token (see tools/models-shim/shim.py).
                if !hermesAPIKeyBox.value.isEmpty { return hermesAPIKeyBox.value }
                return nil
            }
        )

        // Lane M PR 2: per-profile relay access for the non-active backends.
        let profileRelaySessions = ProfileRelaySessionFactory(
            persistence: persistence,
            secureStore: secureStore,
            profileResolver: { profilesStore.profile(id: $0) },
            activeProfileIDProvider: { profilesStore.activeProfileID }
        )
        profileRelaySessions.onTokensRefreshed = { profilesStore.stampTokenRefresh(profileID: $0) }

        // M-8: the sensor outbox drains to the PINNED destination profile,
        // independent of the active one — production context must not go
        // dark when Owen switches to the Mac. When the destination IS the
        // active profile (the default, and the only pre-Lane-M state) every
        // provider resolves exactly as before, through the live stores.
        let sensorDestinationIsActive: @MainActor () -> Bool = {
            profilesStore.sensorDestinationProfileID == profilesStore.activeProfileID
        }
        let sensorRelayClient = RelayAPIClient {
            if sensorDestinationIsActive() {
                return activePairingStore?.pairedRelayConfiguration?.baseURLString
                    ?? profilesStore.activeProfile?.relayBaseURL
                    ?? ""
            }
            guard let destination = profilesStore.sensorDestinationProfileID else { return "" }
            return profileRelaySessions.relayBaseURL(forProfileID: destination) ?? ""
        }
        let liveLocationService = LiveLocationService()
        liveLocationService.updateSyncPreference(settingsStore.settings.locationSyncPreference)
        let liveHealthService = LiveHealthService(persistence: persistence)
        let liveMotionService = LiveMotionService()
        let sensorUploadService: SensorUploadService? = usesMockPairingService ? nil : SensorUploadService(
            apiClient: sensorRelayClient,
            accessTokenProvider: {
                if sensorDestinationIsActive() {
                    return await sessionStore.currentAccessToken()
                }
                guard let destination = profilesStore.sensorDestinationProfileID else { return nil }
                return await profileRelaySessions.accessToken(forProfileID: destination)
            },
            accessTokenRefresher: {
                if sensorDestinationIsActive() {
                    return await relayAccessTokenRefresher()
                }
                guard let destination = profilesStore.sensorDestinationProfileID else { return nil }
                return await profileRelaySessions.refreshAccessToken(forProfileID: destination)
            },
            persistence: persistence,
            isPairedProvider: {
                if sensorDestinationIsActive() {
                    return activePairingStore?.isPaired == true
                }
                guard let destination = profilesStore.sensorDestinationProfileID else { return false }
                return profileRelaySessions.isPaired(profileID: destination)
            },
            isSensorStreamingEnabled: { settingsStore.settings.sensorStreamingEnabled },
            isHealthCollectionEnabled: { settingsStore.settings.healthCollectionEnabled },
            isLocationCollectionEnabled: { settingsStore.settings.locationCollectionEnabled },
            isMotionCollectionEnabled: { settingsStore.settings.motionCollectionEnabled },
            locationService: liveLocationService,
            healthService: liveHealthService,
            motionService: liveMotionService
        )
        // #18: two voice engines behind TalkStore's one seam. The Realtime
        // (relay + OpenAI WebRTC) engine wins when the relay is paired and
        // talk is configured; the native pipeline (SpeechAnalyzer → the chat
        // brain router → AVSpeechSynthesizer) takes over when talk is
        // unconfigured, the relay is unreachable, or the device was never
        // paired. The native pipeline's TTS instance manages no audio session
        // (the pipeline owns .playAndRecord) and rides the same persisted
        // read-aloud voice/rate as the chat read-aloud path.
        // #129: created unconditionally (mock voice path included) so the
        // Voice settings screen always has a session-less instance to route
        // mid-session previews through; stored on the container below.
        let nativeSpeechOutput = SpeechOutputService()
        nativeSpeechOutput.managesAudioSession = false
        nativeSpeechOutput.voiceIdentifierProvider = {
            settingsStore.settings.readAloudVoiceIdentifier
        }
        nativeSpeechOutput.rateProvider = {
            settingsStore.settings.readAloudRate
        }
        let voiceService: any VoiceSessionServiceProtocol
        if usesMockPairingService {
            voiceService = MockVoiceSessionService()
        } else {
            let nativeVoice = NativeVoicePipelineService(
                // The #18 amendment: the ACTIVE backend, never a hardcoded
                // SessionsHermesClient — with the local brain routed, this is
                // a fully offline voice assistant.
                backendProvider: { chatBackendRouter },
                speechOutput: nativeSpeechOutput
            )
            voiceService = VoiceEngineRouter(
                realtime: LiveVoiceSessionService(
                    apiClient: apiClient,
                    accessTokenProvider: { await sessionStore.currentAccessToken() },
                    accessTokenRefresher: relayAccessTokenRefresher
                ),
                native: nativeVoice,
                isRelayPaired: { activePairingStore?.isPaired == true }
            )
        }

        let container = AppContainer(
            sessionStore: sessionStore,
            pairingStore: runtimePairingStore,
            hostStore: hostStore,
            chatStore: ChatStore(hermesClient: chatBackendRouter, persistence: persistence, journal: journalStore),
            inboxStore: InboxStore(
                inboxService: inboxService,
                persistence: persistence,
                sessionStore: sessionStore
            ),
            permissionsStore: PermissionsStore(
                locationService: liveLocationService,
                healthService: liveHealthService,
                notificationService: notificationService,
                mediaService: processEnvironment["UITEST_PAIRING_MODE"] != nil ? MockMediaService() : LiveMediaService(),
                motionService: liveMotionService
            ),
            settingsStore: settingsStore,
            talkStore: TalkStore(voiceService: voiceService),
            modelsShimClient: modelsShimClient,
            sensorUploadService: sensorUploadService,
            apiClient: apiClient,
            probeAPIClient: bootstrapProbeClient,
            notificationService: notificationService,
            secureStore: secureStore,
            localIntelligence: localIntelligence,
            chatBackendRouter: chatBackendRouter
        )

        container.chatAPIKeyBox = hermesAPIKeyBox
        container.shimTokenBox = shimTokenBox

        // #113: repeated drain retry-exhaustion (the dead-connector shape)
        // surfaces as ONE deduped local inbox alert; the next successful
        // delivery clears it. Weak: the service is owned by the container.
        sensorUploadService?.onConnectorOutageAlert = { [weak container] raised in
            guard let container else { return }
            if raised {
                container.inboxStore.raiseConnectorOutageAlert()
            } else {
                container.inboxStore.clearConnectorOutageAlert()
            }
        }

        // #125: Health Trends reads behind the grant LiveHealthService already
        // established — never a new scope request.
        container.healthTrendsService = LiveHealthTrendsService(
            isAuthorized: { liveHealthService.authorizationStatus == .authorized }
        )

        // #97: pin/archive overlay for server-session rows — same persistence
        // seam as every other store, read by the drawer + search surfaces.
        container.conversationListState = ConversationListStateStore(persistence: persistence)

        // Lane M (#114): backend profiles + session→profile index.
        container.profilesStore = profilesStore
        container.sessionProfileIndex = sessionProfileIndex
        container.profileRelaySessions = profileRelaySessions
        container.gatewayKeyCache = gatewayKeyCache
        container.sessionsChatClient = sessionsClient
        // #156a: Tasks — the cron-jobs surface talks to the same :8642
        // gateway with the same API key as chat; no relay, no new services
        // (#161). Bare test containers skip this (nil store → honest
        // unavailable state).
        container.cronJobsStore = CronJobsStore(
            service: CronJobService(
                baseURLProvider: {
                    let raw = (profilesStore.activeProfile?.gatewayBaseURL ?? "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    return raw.isEmpty ? nil : raw
                },
                apiKeyProvider: { hermesAPIKeyBox.value }
            )
        )
        // #156b: Skills — the read-only installed-skills browser rides the
        // same gateway endpoint and key as Tasks (#161: zero new
        // infrastructure). Also feeds the cron editor's skills picker (D5).
        container.skillsStore = SkillsStore(
            service: SkillsService(
                baseURLProvider: {
                    let raw = (profilesStore.activeProfile?.gatewayBaseURL ?? "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    return raw.isEmpty ? nil : raw
                },
                apiKeyProvider: { hermesAPIKeyBox.value }
            )
        )
        // #21 Tier 2: fetchable agent-file bubbles download from the
        // announcing session's birth-profile relay (Lane M — never a global
        // relay base), authed with that profile's pairing-minted device
        // bearer. A nil birth profile is a pre-Lane-M record and collapses to
        // the active profile. The factory refuses to rotate the ACTIVE
        // profile's tokens (AppSessionStore owns that single-flight refresh),
        // so an active-profile 401 runs the #15 recovery ladder here and
        // retries once.
        container.chatStore.agentFileDownloader = { profileID, remotePath in
            guard let resolvedID = profileID ?? profilesStore.activeProfileID else {
                throw RelayAPIClient.FileDownloadError.unauthorized
            }
            do {
                return try await profileRelaySessions.downloadAgentFile(remotePath: remotePath, profileID: resolvedID)
            } catch RelayAPIClient.FileDownloadError.unauthorized where resolvedID == profilesStore.activeProfileID {
                guard let fresh = await relayAccessTokenRefresher(), !fresh.isEmpty else {
                    throw RelayAPIClient.FileDownloadError.unauthorized
                }
                return try await profileRelaySessions.apiClient(forProfileID: resolvedID)
                    .downloadFile(path: remotePath, accessToken: fresh)
            }
        }
        // M-6: activating a profile re-homes the relay-plane surfaces and
        // credential boxes onto the new backend.
        profilesStore.onActiveProfileChanged = { [weak container] profile in
            await container?.handleActiveProfileChanged(to: profile)
        }
        // #116: the post-pair provisioning bundle. The fetch rides the
        // profile's OWN relay + freshly minted access token (works for the
        // active and dormant slots alike); fills are profile-scoped and the
        // ACTIVE profile's shim token also lands in the in-memory box the
        // shim client reads.
        let provisioningService = ProvisioningService(
            profileResolver: { profilesStore.profile(id: $0) },
            upsertProfile: { profilesStore.upsert($0) },
            readShimToken: { profile in
                await secureStore.retrieve(key: BackendProfileScopedKeys.shimToken(profile.credentialScopeID))
            },
            writeShimToken: { [weak container] value, profile in
                if profile.id == profilesStore.activeProfileID {
                    await container?.saveModelsShimToken(value)
                } else {
                    await secureStore.store(
                        key: BackendProfileScopedKeys.shimToken(profile.credentialScopeID),
                        value: value
                    )
                }
            },
            fetchDescriptor: { profile in
                guard let token = await profileRelaySessions.accessToken(forProfileID: profile.id),
                      !token.isEmpty else {
                    throw ProvisioningService.ServiceError.notPaired
                }
                let client = profileRelaySessions.apiClient(forProfileID: profile.id)
                let response: DeviceProvisioningResponse = try await client.get(
                    path: "device/provisioning",
                    accessToken: token
                )
                return response.provisioning
            }
        )
        container.provisioningService = provisioningService

        // #127: the Connected-tier entitlement source. Started even while
        // the gate is dormant — the Transaction.updates listener is StoreKit
        // hygiene (unfinished transactions re-deliver until observed), and a
        // launch-time scan keeps the last-known cache warm for flip day.
        let entitlementService = EntitlementService()
        container.entitlementService = entitlementService
        entitlementService.start()

        // M-9: a successful pair mints fresh relay tokens — stamp freshness.
        // #116: …and the relay can now answer the provisioning fetch — key
        // the profile automatically (fill-empty-only: a manual value is never
        // clobbered, and a redeem failure never reaches here — the #94
        // redeem-first ordering is untouched upstream in pair()).
        runtimePairingStore.onProfileTokensMinted = { profileID in
            profilesStore.stampTokenRefresh(profileID: profileID)
            guard let resolvedID = profileID ?? profilesStore.activeProfileID else { return }
            Task { @MainActor in
                do {
                    _ = try await provisioningService.applyProvisioning(profileID: resolvedID, mode: .fillEmptyOnly)
                } catch {
                    containerLog.notice("provisioning auto-fill skipped: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
        // Keychain hygiene: a deleted profile's credential slot dies with it.
        // The migrated (legacy-keyed) profile is undeletable in practice —
        // it's active/sensor-destination until another profile takes over —
        // but scoped deletion is correct for it too.
        profilesStore.onProfileDeleted = { profile in
            let scope = profile.credentialScopeID
            persistence.clearPairedRelayConfiguration(profileScope: scope)
            persistence.clearSessionState(profileScope: scope)
            Task { @MainActor in
                await secureStore.delete(key: BackendProfileScopedKeys.accessToken(scope))
                await secureStore.delete(key: BackendProfileScopedKeys.refreshToken(scope))
                await secureStore.delete(key: BackendProfileScopedKeys.gatewayAPIKey(scope))
                await secureStore.delete(key: BackendProfileScopedKeys.shimToken(scope))
            }
        }

        // #27: per-conversation brain preferences key off the live
        // conversation, which ChatStore owns — wire the lookup now that both
        // exist. (The router was built first; ChatStore sits on top of it.)
        chatBackendRouter.conversationIDProvider = { [weak container] in
            container?.chatStore.conversation?.id
        }

        // #28/#29: the device tool belt — the read set plus the confirm-gated
        // action set. Providers read ChatStore / Spotlight state, so the belt
        // installs after the container exists; installTools invalidates the
        // local session so the next turn picks the tools up.
        let toolRelay = ToolEventRelay()
        var deviceTools = DeviceToolBelt.makeReadTools(
            relay: toolRelay,
            conversationProvider: { [weak container] in
                container?.chatStore.conversation
            },
            sessionCacheProvider: { [weak container] in
                (container?.spotlightIndexing.sessionEntities.values).map { entities in
                    entities.map {
                        ConversationSearchTool.CachedSession(id: $0.id, title: $0.title, preview: $0.preview)
                    }
                } ?? []
            },
            spotlightEnabledProvider: {
                settingsStore.settings.spotlightIndexingEnabled
            }
        )
        deviceTools += DeviceToolBelt.makeActionTools(
            relay: toolRelay,
            confirmations: container.toolConfirmationCenter,
            alarmService: container.alarmService
        )
        localChatBackend.installTools(deviceTools, relay: toolRelay)
        // #31: the chat screen reads the standalone availability state off
        // the backend directly.
        container.localChatBackend = localChatBackend

        // #30: PCC tier gates — the picker entry appears only when the
        // entitlement + availability check actually passes, the router
        // consults quota per new message, and locally-routed turns carry
        // their tier to the backend.
        chatBackendRouter.isPrivateCloudSelectable = { [weak localChatBackend] in
            localChatBackend?.isPrivateCloudAvailable ?? false
        }
        chatBackendRouter.isPrivateCloudUsable = { [weak localChatBackend] in
            localChatBackend?.isPrivateCloudUsable ?? false
        }
        chatBackendRouter.applyLocalTier = { [weak localChatBackend] brain in
            localChatBackend?.setPreferredTier(privateCloud: brain == .privateCloud)
        }

        // Restore the persisted Hermes Sessions-API keys into the in-memory
        // cache (every profile — sync endpoint resolution needs them) and
        // the active-profile box, so the chat client can pick them up on
        // first send without blocking startup.
        Task { @MainActor [weak container, hermesAPIKeyBox] in
            for profile in profilesStore.profiles {
                let scope = profile.credentialScopeID
                guard let stored = await secureStore.retrieve(key: BackendProfileScopedKeys.gatewayAPIKey(scope)) else {
                    continue
                }
                gatewayKeyCache.set(stored, forScope: scope)
                if profile.id == profilesStore.activeProfileID {
                    hermesAPIKeyBox.value = stored
                    container?.hermesAPIKey = stored
                    // #27: the restored key flips the routing signal — update
                    // the brain indicator without waiting for the next probe.
                    container?.chatBackendRouter?.refreshActiveBrain()
                }
            }
        }

        // Restore the persisted models-shim bearer token (same pattern).
        Task { @MainActor [weak container, shimTokenBox] in
            let scope = profilesStore.activeProfile?.credentialScopeID
            if let stored = await secureStore.retrieve(key: BackendProfileScopedKeys.shimToken(scope)) {
                shimTokenBox.value = stored
                container?.modelsShimToken = stored
            }
        }

        // Pre-unlock staleness recovery: a post-reboot background launch
        // (location relaunch) runs BEFORE first unlock, when Keychain and
        // protected UserDefaults read as empty. Everything cached at
        // construction — the pairing config, these key boxes — then reads as
        // absent for the process's whole lifetime, and foregrounding that
        // same process shows "not paired / no key" even though nothing was
        // lost. Re-read whenever protected data becomes available (and on
        // activation, covering the zombie-foreground case). Idempotent: only
        // acts on values that are currently empty.
        let refreshCredentialState: @MainActor () -> Void = { [weak container, hermesAPIKeyBox, shimTokenBox] in
            guard UIApplication.shared.isProtectedDataAvailable else { return }
            container?.pairingStore.reloadPersistedConfigurationIfNeeded()
            // #137: a migration deferred by a pre-unlock launch lands here,
            // after the pairing re-read it depends on.
            container?.migrateSensorStreamingOptInIfNeeded()
            if hermesAPIKeyBox.value.isEmpty {
                Task { @MainActor in
                    let scope = profilesStore.activeProfile?.credentialScopeID
                    if let stored = await secureStore.retrieve(key: BackendProfileScopedKeys.gatewayAPIKey(scope)), !stored.isEmpty {
                        gatewayKeyCache.set(stored, forScope: scope)
                        hermesAPIKeyBox.value = stored
                        container?.hermesAPIKey = stored
                        container?.chatBackendRouter?.refreshActiveBrain()
                        containerLog.notice("credential refresh: Sessions API key re-read after protected data became available")
                    }
                }
            }
            if shimTokenBox.value.isEmpty {
                Task { @MainActor in
                    let scope = profilesStore.activeProfile?.credentialScopeID
                    if let stored = await secureStore.retrieve(key: BackendProfileScopedKeys.shimToken(scope)), !stored.isEmpty {
                        shimTokenBox.value = stored
                        container?.modelsShimToken = stored
                    }
                }
            }
        }
        NotificationCenter.default.addObserver(
            forName: UIApplication.protectedDataDidBecomeAvailableNotification,
            object: nil, queue: .main
        ) { _ in
            Task { @MainActor in refreshCredentialState() }
        }
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil, queue: .main
        ) { _ in
            Task { @MainActor in refreshCredentialState() }
        }

        // #118 (privacy): leaving the app must not leave the capture chain --
        // and the system mic indicator -- live. There is no background-audio
        // voice mode; backgrounding ends the voice session through the same
        // path as the user's end tap (transcript capture, Live Activity
        // teardown, overlay dismissal), on WHICHEVER engine is driving.
        // CarPlay is the one exemption: CarPlay voice runs with the phone UI
        // backgrounded by design (#19). The notification payload is never
        // touched (Swift 6 region-isolation landmine) -- the closure only
        // hops to the main actor.
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil, queue: .main
        ) { [weak container] _ in
            Task { @MainActor [weak container] in
                guard let container else { return }
                guard TalkBackgroundRule.shouldEndSession(
                    isSessionActive: container.talkStore.isSessionActive,
                    routeHasCarAudio: TalkAudioRoute.currentRouteHasCarAudio()
                ) else { return }
                containerLog.notice("#118: app backgrounded with a live voice session — ending it")
                await container.talkStore.endSession()
                container.router.isVoiceOverlayPresented = false
            }
        }

        let refreshUnpairedRelayContext: @MainActor () async -> Void = { [weak sessionStore, weak container] in
            // Never act on a pre-unlock reading of "unpaired": clearing the
            // session + force-registering off unreadable credentials would
            // destroy a healthy identity.
            guard UIApplication.shared.isProtectedDataAvailable else { return }
            guard container?.pairingStore.isPaired == false else { return }
            await sessionStore?.clearSession()
            guard let relayBaseURL = container?.profilesStore?.activeProfile?.relayBaseURL,
                  !relayBaseURL.isEmpty else { return }
            _ = relayBaseURL
            await sessionStore?.bootstrap(forceRegistration: true)
            await container?.inboxStore.loadInbox(force: true)
        }

        settingsStore.onEnvironmentChanged = { _ in
            await refreshUnpairedRelayContext()
        }
        settingsStore.onRelayConfigurationChanged = { configuration in
            // Lane M: the legacy relay-config surface (Relay settings screen,
            // onboarding QR auto-fill) still writes UserSettings — mirror the
            // resolved URL onto the ACTIVE profile, which is what pairing and
            // the relay client actually read now. One-way, every writer
            // covered, so the two records can't drift.
            profilesStore.updateActiveProfile { profile in
                // Normalized when valid; the raw text while mid-edit, so a
                // partially typed URL never snaps the bound field to "".
                profile.relayBaseURL = configuration.activeBaseURLString ?? configuration.customRelayBaseURL
            }
            await refreshUnpairedRelayContext()
        }

        runtimePairingStore.onPairingChanged = { [weak container] isPaired in
            if isPaired {
                await container?.handlePairingActivated()
            } else {
                await container?.handlePairingRemoved()
            }
        }

        // Read-aloud (#2): wire the TTS service to persisted voice/rate prefs,
        // gate it off while a Talk session owns the .playAndRecord audio
        // session, and let ChatStore feed streamed replies when auto-read is on.
        container.speechOutput.isBlocked = { [weak container] in
            container?.talkStore.isSessionActive == true
        }
        container.speechOutput.voiceIdentifierProvider = {
            settingsStore.settings.readAloudVoiceIdentifier
        }
        container.speechOutput.rateProvider = {
            settingsStore.settings.readAloudRate
        }
        container.chatStore.speechOutput = container.speechOutput
        container.chatStore.autoReadAloudEnabled = {
            settingsStore.settings.readAloudAutoPlay
        }
        // #129: hand Settings the pipeline's own session-less instance for
        // mid-session voice previews (selection in previewInstance).
        container.nativeSpeechOutput = nativeSpeechOutput

        // On-device intelligence (#4.8 × #4.15): titles/previews + reasoning
        // condensation ride the chat turn lifecycle inside ChatStore.
        container.chatStore.localIntelligence = container.localIntelligence

        // #14: attachment sends (the deliberately-backgroundable long path,
        // #38) ride a BGContinuedProcessingTask — system progress UI, and the
        // run survives the user leaving the app.
        container.chatStore.beginContinuedSend = { subtitle in
            ContinuedProcessing.beginLongSend(subtitle: subtitle)
        }

        // Failed sends buzz. Same user gate as the sent/received haptics
        // (ChatScreen fires those; the failure terminals live in ChatStore).
        container.chatStore.onSendFailed = {
            if settingsStore.settings.hapticFeedbackEnabled {
                HapticEngine.error()
            }
        }

        // Keep widget data fresh while app is foregrounded
        container.chatStore.onConversationChanged = { [weak container] in
            container?.updateWidgetData()
            // #17: newly staged agent files ride the same change signal —
            // donation itself is gated by the Privacy toggle inside the service.
            container?.spotlightIndexing.donateAgentFiles(from: container?.chatStore.conversation)
        }

        // #17: Spotlight donation, strictly behind the Privacy toggle
        // (default OFF). Sessions donate whenever the list is fetched.
        container.spotlightIndexing.isEnabled = {
            settingsStore.settings.spotlightIndexingEnabled
        }
        container.chatStore.onSessionsLoaded = { [weak container] sessions in
            container?.spotlightIndexing.donateSessions(sessions)
        }
        // Run-completion push watch (#38): when a stream detaches while the
        // app is leaving the foreground, ask the relay to watch the session
        // and fire APNs on completion; when the app reconciles the run on its
        // own, withdraw the watch so no stale push arrives.
        container.chatStore.onRunDetached = { [weak container] sessionId in
            Task { await container?.postPushWatch(sessionId: sessionId) }
        }
        container.chatStore.onRunResolved = { [weak container] sessionId in
            Task { await container?.cancelPushWatch(sessionId: sessionId) }
        }
        container.talkStore.onSessionStateChanged = { [weak container] in
            guard let container else { return }
            container.updateWidgetData()
            // A Talk session STARTING takes the audio session — cut any
            // in-flight read-aloud instead of colliding with it (#2). Edge-
            // triggered (#84): this callback fires on every state tick during
            // a session, and each stop() used to reach setActive(false) on the
            // shared session, killing the live mic. The release itself is also
            // gated in SpeechOutputService now (didActivateAudioSession);
            // this edge guard removes the wasted per-tick stop() churn.
            let isActive = container.talkStore.isSessionActive
            if isActive, !container.lastKnownTalkSessionActive {
                container.speechOutput.stop()
            }
            container.lastKnownTalkSessionActive = isActive
        }
        container.hostStore.onHostChanged = { [weak container] in
            guard let container else { return }
            let isOnline = container.hostStore.isHostOnline
            let becameOnline = isOnline && container.lastKnownHostOnline == false
            container.lastKnownHostOnline = isOnline
            container.updateWidgetData()
            Task { [weak container] in
                await container?.refreshCommandCatalog(force: becameOnline)
            }
        }

        // #137: grandfather already-streaming devices before the first
        // sensor start can read the new opt-out defaults. Synchronous local
        // work only (#136); deferred internally while protected data is
        // sealed and re-run by refreshCredentialState above.
        container.migrateSensorStreamingOptInIfNeeded()

        return container
    }

    func initialize() async {
        guard pairingStore.isPaired else {
            containerLog.warning("initialize: ABORT — not paired")
            return
        }
        guard !isInitialized else {
            containerLog.verbose("initialize: SKIP — already initialized")
            return
        }
        guard await sessionStore.currentAccessToken() != nil else {
            containerLog.warning("initialize: ABORT — no access token, clearing pairing")
            await pairingStore.clearLocalPairing()
            return
        }

        // #136: the critical path is LOCAL-ONLY (see LaunchInitStep) — the
        // splash drops on local-state-ready, never on relay convergence. A
        // black-holed host (firewall DROP, no TCP refusal — every request
        // hangs the full URLSession timeout, error -1001) must not strand
        // the launch splash; a cold launch with ZERO hosts reachable lands
        // on a fully functional app in splash-minimum time.
        await permissionsStore.reloadCapabilities()
        await chatStore.loadConversationIfNeeded()
        containerLog.notice("initialize: starting sensor service")
        sensorUploadService?.start()
        reconcileLiveActivities()
        updateWidgetData()
        // #123: cold-launch safety net for a share queued while the app was
        // dead — idempotent with the scene-activate drain (the inbox empties
        // on first pass, so a double invocation is a no-op). Free-tier
        // surface: stays on the critical path, before any relay-gated work.
        drainShareInbox()
        isInitialized = true
        // Degraded is the DEFAULT launch posture — the relay-backed half
        // runs behind the live UI and upgrades state as each step lands.
        startBackgroundBootstrap()
    }

    // MARK: - Background bootstrap (#136)

    /// Launches the relay-backed half of launch behind the live UI.
    /// Single-flight: a second `initialize()` (or any re-entry) while one is
    /// in flight must not double-run bootstrap.
    private func startBackgroundBootstrap() {
        guard backgroundBootstrapTask == nil else { return }
        bootstrapGeneration += 1
        let generation = bootstrapGeneration
        let predecessor = supersededBootstrapDrain
        supersededBootstrapDrain = nil
        backgroundBootstrapTask = Task { [weak self] in
            // A superseded run may still be unwinding its cancelled awaits —
            // drain it first so its in-flight bootstrap can't interleave
            // with (or silently short-circuit, via AppSessionStore's
            // isBootstrapping re-entry guard) this run's fresh one.
            await predecessor?.value
            await self?.runBackgroundBootstrap(generation: generation)
            guard let self, self.bootstrapGeneration == generation else { return }
            self.backgroundBootstrapTask = nil
        }
    }

    /// Cancels + supersedes any in-flight background bootstrap. Every
    /// `isInitialized = false` reset site calls this (#136 non-negotiable
    /// 5), as does a profile switch — a half-dead run must neither land
    /// stale state past the reset nor block the next run's single-flight
    /// gate.
    private func cancelBackgroundBootstrap() {
        bootstrapGeneration += 1
        guard let task = backgroundBootstrapTask else { return }
        task.cancel()
        backgroundBootstrapTask = nil
        // Keep a handle so the NEXT run can wait out the unwinding corpse —
        // chained, in case resets stack up before another run starts.
        if let existingDrain = supersededBootstrapDrain {
            supersededBootstrapDrain = Task {
                await existingDrain.value
                await task.value
            }
        } else {
            supersededBootstrapDrain = task
        }
    }

    /// The relay-backed launch steps, in `LaunchInitStep.backgroundBootstrap`
    /// order. Every state write is generation-guarded: a reset that
    /// superseded this run wins, and nothing stale lands after it.
    private func runBackgroundBootstrap(generation: Int) async {
        func isCurrent() -> Bool {
            bootstrapGeneration == generation && !Task.isCancelled
        }

        await sessionStore.bootstrap()
        guard isCurrent() else { return }
        // #3/#46: a reinstall can resurrect a previous relay identity from the
        // Keychain — verify the bootstrapped session's user matches the one
        // this pairing minted before relay-backed features run on it. MUST
        // stay ordered strictly after bootstrap.
        pairingStore.validateRestoredIdentity()
        if sessionStore.state.connectionStatus != .connected {
            // Relay bootstrap failed (e.g. the relay restarted and invalidated this
            // device's tokens → 401 on register/session/refresh). Do NOT strand the
            // launch splash: the direct chat path (:8642, API-key auth) is independent
            // of the relay session, so we continue into the app in a degraded state and
            // let the user reach Settings to re-pair / retry rather than being hard
            // locked at launch. Relay-backed features (sensor upload, inbox, push) stay
            // degraded until a valid session is restored; re-pairing re-runs initialize().
            // (#136: the splash no longer waits for this path at all — this
            // hardening covers relays that ANSWER with a failure; the
            // background task + short-timeout probes cover the black hole.)
            containerLog.warning("initialize: relay bootstrap not connected (is \(String(describing: self.sessionStore.state.connectionStatus), privacy: .public)) — entering degraded mode; direct chat still available")
        }
        await hostStore.refresh()
        guard isCurrent() else { return }
        lastKnownHostOnline = hostStore.isHostOnline
        await inboxStore.loadInbox()
        guard isCurrent() else { return }
        await refreshCommandCatalog(force: true)
        guard isCurrent() else { return }
        // Seed the model chip label from the shim if the command catalog didn't
        // provide an active model name (e.g. relay offline). Best-effort: if the
        // shim is unreachable or the token isn't set, the chip shows "HERMES".
        if chatStore.activeModelName == nil {
            await seedActiveModelFromShim()
            guard isCurrent() else { return }
        }
        await registerStoredPushTokenIfNeeded()
        guard isCurrent() else { return }
        // #136: the sensor foreground refresh drains the outbox — an inline
        // relay upload — so it rides here, not the splash critical path
        // (start() itself stays on the critical path: capture + HealthKit
        // auth must begin at launch).
        containerLog.notice("initialize: background bootstrap running sensor handleAppDidBecomeActive")
        await sensorUploadService?.handleAppDidBecomeActive()
        guard isCurrent() else { return }
        updateWidgetData()
    }

    /// #123: drain the share-extension inbox into the composer and deep-route
    /// to chat. Runs on every foreground BEFORE the pairing-gated work —
    /// shares are a free-tier surface and must land with no Hermes host at
    /// all (the on-device brain answers). Seed-only: the user still sends.
    func drainShareInbox() {
        guard let result = shareInboxDrainer.drain() else { return }
        containerLog.notice("Share inbox: staged \(result.envelopeCount) share(s) into the composer")
        chatStore.seedComposerFromShare(text: result.text, attachments: result.attachments)
        router.activeSheet = nil
        router.popToRoot()
        router.selectedTab = .chat
    }

    func handleAppDidBecomeActive() async {
        guard pairingStore.isPaired else {
            containerLog.warning("handleAppDidBecomeActive: BLOCKED — not paired")
            return
        }
        guard await sessionStore.currentAccessToken() != nil else {
            containerLog.warning("handleAppDidBecomeActive: BLOCKED — no access token")
            return
        }
        containerLog.verbose("handleAppDidBecomeActive: paired + token OK, proceeding")

        await permissionsStore.reloadCapabilities()
        await hostStore.refresh()
        lastKnownHostOnline = hostStore.isHostOnline
        await refreshCommandCatalog(force: true)
        // Seed the model chip from the shim if the catalog didn't provide one
        // (e.g. relay offline). This path runs even when initialize() aborts.
        if chatStore.activeModelName == nil {
            await seedActiveModelFromShim()
        }
        await registerStoredPushTokenIfNeeded()
        await sensorUploadService?.handleAppDidBecomeActive()
        talkStore.handleAppDidBecomeActive()
        await talkStore.refreshReadiness()
        await chatStore.reconcilePendingRuns()
        // #4.15: a turn that finished while backgrounded skipped reasoning
        // condensation (foreground-only work) — catch it up now.
        await chatStore.condensePendingReasoning()
        // M-9: keep dormant profiles' relay tokens alive.
        await refreshDormantProfileTokensIfNeeded()
        reconcileLiveActivities()
        await reportAppStateIfNeeded("foreground")
        updateWidgetData()
    }

    // MARK: - Lock-screen reply (#47)

    /// A typed reply from a completion push's text-input action. Headless by
    /// design — no scene mounts, so nothing here may touch UI state, and the
    /// #38 scene-phase hook (`watchPendingRunIfNeeded`) never runs: the
    /// completion watch for the reply's own run is re-armed explicitly, which
    /// is what makes the loop close (the next completion push again carries
    /// Reply).
    func handleNotificationReply(_ text: String, sessionID: String?) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Keep iOS from suspending the scene-less process mid-send — the
        // delegate callback's grace window alone is short.
        let backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "hermes.lockscreen.reply")
        defer {
            if backgroundTask != .invalid {
                UIApplication.shared.endBackgroundTask(backgroundTask)
            }
        }

        // Cold scene-less launch: the Keychain key restore is async — same
        // bounded wait AskHermesIntent uses.
        await waitForHermesAPIKeyRestore()

        // One run at a time (AskHermesIntent's rule): stacking a second
        // stream would tangle ChatStore's placeholder bookkeeping. The typed
        // text must not vanish silently — say so.
        guard !chatStore.isStreaming else {
            localNotifications.notifyReplyFailed(
                reason: "Hermes is still working on another run. Open Talaria to send it."
            )
            return
        }

        let sentAt = Date()
        if let sessionID, !sessionID.isEmpty {
            // Adopt the pushed session so the reply continues THAT thread
            // (and the app opens into it later).
            await chatStore.openSession(sessionID)
        } else {
            await chatStore.loadConversationIfNeeded()
        }

        await chatStore.sendMessage(trimmed)

        // Re-arm the relay watch so THIS run's completion pushes (again with
        // a Reply action). Only after a committed turn: the watcher's
        // completion check is positional — assistant-after-last-user — so
        // arming after a failed send would insta-push a stale reply. For a
        // run that already finished in-process the insta-fire is the point:
        // it's what announces the answer to the locked phone.
        switch AskHermesIntent.resolveOutcome(
            messages: chatStore.conversation?.messages ?? [],
            sentAfter: sentAt
        ) {
        case .answered, .pending:
            if let watchSession = sessionID ?? chatStore.pendingRunSessionId {
                await postPushWatch(sessionId: watchSession)
            }
        case .failed(let errorText):
            localNotifications.notifyReplyFailed(reason: errorText)
        case .queued:
            // Parked in the offline compose outbox (#90): nothing was accepted
            // server-side, so there's no run to push-watch and it isn't a
            // failure. The outbox drain arms its own watch when it later sends.
            break
        }
    }

    /// Bounded wait for the async Keychain key restore on cold scene-less
    /// launches (mirrors AskHermesIntent.waitForAPIKeyRestore).
    private func waitForHermesAPIKeyRestore() async {
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(2)
        while hermesAPIKey.isEmpty, clock.now < deadline, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    /// User tapped a completion notification — bring the app to chat and
    /// reconcile so the finished reply is fetched. `sessionID` (from the
    /// remote push payload) targets the specific conversation; local
    /// completion notifications pass nil and land on the active one.
    func handleNotificationTap(sessionID: String?) async {
        guard pairingStore.isPaired else { return }
        router.activeSheet = nil
        router.popToRoot()
        router.selectedTab = .chat
        if let sessionID, !sessionID.isEmpty {
            await chatStore.openSession(sessionID)
        }
        await chatStore.reconcilePendingRuns()
    }

    func handleRemoteNotificationWake() async {
        containerLog.notice("handleRemoteNotificationWake: entered")
        guard pairingStore.isPaired else {
            containerLog.warning("handleRemoteNotificationWake: BLOCKED — not paired")
            return
        }
        guard await sessionStore.currentAccessToken() != nil else {
            containerLog.warning("handleRemoteNotificationWake: BLOCKED — no access token")
            return
        }

        // A push that woke us almost always means a run finished server-side;
        // reconcile so the reply is fetched and the completion notification
        // can fire.
        await chatStore.reconcilePendingRuns()

        // #45: a silent push is also how an agent-posted inbox item announces
        // itself — refresh so the item is waiting before the user ever opens
        // the app.
        await inboxStore.loadInbox(force: true)

        await permissionsStore.reloadCapabilities()
        await hostStore.refresh()
        lastKnownHostOnline = hostStore.isHostOnline
        await registerStoredPushTokenIfNeeded()
        await sensorUploadService?.handleAppDidBecomeActive()
        talkStore.handleAppDidBecomeActive()
        await talkStore.refreshReadiness()
        reconcileLiveActivities()
        updateWidgetData()
    }

    func handleSystemLaunch() async {
        containerLog.notice("handleSystemLaunch: entered")
        // Pre-first-unlock launches (post-reboot location relaunch) cannot
        // read credentials — every guard below would misfire on absence that
        // isn't real. Defer everything; the protected-data observer picks up
        // once the user unlocks.
        guard UIApplication.shared.isProtectedDataAvailable else {
            containerLog.warning("handleSystemLaunch: BLOCKED — protected data unavailable (pre-first-unlock launch); deferring")
            return
        }
        guard pairingStore.isPaired else {
            containerLog.warning("handleSystemLaunch: BLOCKED — not paired")
            return
        }
        guard await sessionStore.currentAccessToken() != nil else {
            containerLog.warning("handleSystemLaunch: BLOCKED — no access token")
            return
        }
        containerLog.notice("handleSystemLaunch: guards passed, starting sensor service")

        sensorUploadService?.start()
        await sensorUploadService?.handleSystemLaunch()
        await registerStoredPushTokenIfNeeded()
        await talkStore.refreshReadiness()
        reconcileLiveActivities()
        await reportAppStateIfNeeded("foreground")
    }

    /// #17: donate the currently-known content immediately — called when the
    /// Privacy toggle flips on, so the index fills without waiting for the
    /// next organic session-list fetch.
    func refreshSpotlightDonations() async {
        guard settingsStore.settings.spotlightIndexingEnabled else { return }
        spotlightIndexing.donateAgentFiles(from: chatStore.conversation)
        _ = await chatStore.loadSessions() // fires onSessionsLoaded → donation
    }

    /// #14: one BGAppRefreshTask pass — the native safety net complementing
    /// relay APNs (which stays the real-time path). Drains the sensor outbox,
    /// runs one reconcile fetch (the existing local "run finished" notification
    /// fires on found completions), and rewrites widget data.
    func handleBackgroundRefresh() async {
        containerLog.notice("handleBackgroundRefresh: entered")
        guard pairingStore.isPaired else {
            containerLog.warning("handleBackgroundRefresh: BLOCKED — not paired")
            return
        }
        guard await sessionStore.currentAccessToken() != nil else {
            containerLog.warning("handleBackgroundRefresh: BLOCKED — no access token")
            return
        }
        // Cold background launches never mount the scene, so initialize()'s
        // .task hook doesn't run — start the sensor pipeline the same way
        // handleSystemLaunch does (idempotent for the warm case).
        sensorUploadService?.start()
        await sensorUploadService?.handleSystemLaunch()
        // In-memory pendingRun survives warm relaunches only — on a cold
        // background launch there is nothing pending by design (the sessions
        // drawer stays the authoritative recovery surface).
        await chatStore.reconcilePendingRuns()
        updateWidgetData()
    }

    /// Pairing-lifecycle reset seam (internal so the #136 reset-race tests
    /// can drive it): wired to `PairingStore.onPairingChanged` in
    /// `makeDefault`.
    func handlePairingActivated() async {
        isInitialized = false
        // #136: supersede any in-flight background bootstrap — the fresh
        // initialize() below must run its own, on the new pairing's state.
        cancelBackgroundBootstrap()
        chatStore.reset()
        inboxStore.reset()
        await initialize()

        // Start sensor data pipeline
        sensorUploadService?.start()
        await talkStore.refreshReadiness()
    }

    /// The push-token pipeline has two independent stages, and conflating them
    /// produced contradictory Settings readouts (Notifications vs Diagnostics).
    /// This is the single source of truth both screens render from:
    ///   1. iOS issues an APNs device token (requires the aps-environment
    ///      entitlement; cached under `apnsTokenDefaultsKey` when delivered).
    ///   2. The relay accepts that token via POST push/register
    ///      (`sessionStore.state.pushTokenRegistered`).
    enum PushTokenPipelineState {
        /// iOS has not delivered an APNs device token on this install.
        case notIssued
        /// A token is held locally but the relay registration is unconfirmed.
        case awaitingRelay
        /// The relay has confirmed the push registration.
        case registered
    }

    var pushTokenPipelineState: PushTokenPipelineState {
        if sessionStore.state.pushTokenRegistered { return .registered }
        return cachedAPNsDeviceToken == nil ? .notIssued : .awaitingRelay
    }

    /// The APNs device token most recently delivered by iOS, if any.
    var cachedAPNsDeviceToken: String? {
        guard let token = UserDefaults.standard.string(forKey: Self.apnsTokenDefaultsKey),
              !token.isEmpty else { return nil }
        return token
    }

    /// Registers the APNs device token with the relay so it can send silent push notifications.
    func registerPushTokenIfNeeded(_ token: String) async {
        guard let notificationService else { return }
        // M-7: any paired profile makes push registration worth running —
        // the ACTIVE profile may legitimately be an unpaired one while a
        // dormant profile still wants its completion pushes.
        let anyProfilePaired = pairingStore.isPaired
            || (profilesStore?.profiles.contains { profileRelaySessions?.isPaired(profileID: $0.id) == true } ?? false)
        guard anyProfilePaired else { return }

        // Respect the user's in-app notifications toggle.
        // If disabled, deactivate any existing registration on the relays
        // so the user actually stops receiving pushes.
        guard settingsStore.settings.notificationsEnabled else {
            // Always attempt deactivation — the relay may have an active
            // registration from a previous session even if the local flag is false.
            await deactivatePushRegistration()
            await deactivateDormantPushRegistrations()
            await notificationService.markPushTokenRegistered(false)
            sessionStore.state.pushTokenRegistered = false
            return
        }

        let normalizedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedToken.isEmpty else { return }

        await notificationService.updatePushToken(normalizedToken)
        await registerPushTokenWithActiveRelay(normalizedToken, notificationService: notificationService)

        // M-7: every paired relay holds this device's token from its own
        // pairing and watches its own gateway — completion pushes must work
        // for BOTH hosts regardless of which is active. Runs even when the
        // active profile's registration deferred (no token / no deviceID).
        await registerPushTokenWithDormantRelays(normalizedToken)
    }

    /// The pre-Lane-M active-relay registration path, verbatim — only the
    /// dormant fan-out moved out from under its early returns.
    private func registerPushTokenWithActiveRelay(
        _ normalizedToken: String,
        notificationService: any NotificationServiceProtocol
    ) async {
        // #136: push registration is a launch/bootstrap-class probe (tiny
        // POST, retried on next launch) — the short-timeout client keeps
        // background init converging against a black-holed relay.
        guard pairingStore.isPaired, let apiClient = probeAPIClient ?? apiClient else { return }

        guard let accessToken = await sessionStore.currentAccessToken() else {
            containerLog.notice("registerPushToken: no relay access token — registration deferred")
            await notificationService.markPushTokenRegistered(false)
            sessionStore.state.pushTokenRegistered = false
            return
        }

        if notificationService.isPushTokenRegistered,
           notificationService.currentPushToken == normalizedToken {
            sessionStore.state.pushTokenRegistered = true
            return
        }

        guard let deviceID = sessionStore.state.deviceID else {
            containerLog.notice("registerPushToken: no deviceID in session state — registration deferred")
            await notificationService.markPushTokenRegistered(false)
            sessionStore.state.pushTokenRegistered = false
            return
        }

        #if DEBUG
        let pushEnvironment = "development"
        #else
        let pushEnvironment = "production"
        #endif

        struct PushRegisterBody: Encodable {
            let deviceId: String
            let apnsToken: String
            let pushEnvironment: String
            let bundleId: String
        }

        let body = PushRegisterBody(
            deviceId: deviceID.uuidString.lowercased(),
            apnsToken: normalizedToken,
            pushEnvironment: pushEnvironment,
            bundleId: Bundle.main.bundleIdentifier ?? "org.aethyrion.talaria"
        )

        struct PushRegisterResponse: Decodable {
            let data: PushData?
            struct PushData: Decodable { let registered: Bool }
        }

        do {
            let _: PushRegisterResponse = try await apiClient.post(
                path: "push/register",
                body: body,
                accessToken: accessToken
            )
            containerLog.notice("registerPushToken: relay accepted push registration")
            await notificationService.markPushTokenRegistered(true)
            sessionStore.state.pushTokenRegistered = true
        } catch {
            // Non-critical — token will be retried on next app launch
            containerLog.notice("registerPushToken: relay push/register failed: \(error.localizedDescription, privacy: .public)")
            await notificationService.markPushTokenRegistered(false)
            sessionStore.state.pushTokenRegistered = false
        }
    }

    /// M-7: best-effort push registration on every paired NON-ACTIVE relay.
    /// Failures are logged only — the active-relay path above stays the
    /// authoritative UX signal.
    private func registerPushTokenWithDormantRelays(_ token: String) async {
        guard let profilesStore, let profileRelaySessions else { return }

        #if DEBUG
        let pushEnvironment = "development"
        #else
        let pushEnvironment = "production"
        #endif

        struct PushRegisterBody: Encodable {
            let deviceId: String
            let apnsToken: String
            let pushEnvironment: String
            let bundleId: String
        }
        struct PushRegisterResponse: Decodable {
            let data: PushData?
            struct PushData: Decodable { let registered: Bool }
        }

        for profile in profilesStore.profiles where profile.id != profilesStore.activeProfileID {
            guard profileRelaySessions.isPaired(profileID: profile.id),
                  let profileState = profileRelaySessions.sessionState(forProfileID: profile.id),
                  let deviceID = profileState.deviceID else { continue }
            // #133: mirror the active path's short-circuit — this relay
            // already acked exactly this token, so there is nothing to send.
            guard DormantPushRegistrationPolicy.shouldRegister(
                recordedToken: profileState.registeredPushToken,
                currentToken: token
            ) else { continue }
            guard var accessToken = await profileRelaySessions.accessToken(forProfileID: profile.id) else { continue }

            let body = PushRegisterBody(
                deviceId: deviceID.uuidString.lowercased(),
                apnsToken: token,
                pushEnvironment: pushEnvironment,
                bundleId: Bundle.main.bundleIdentifier ?? "org.aethyrion.talaria"
            )
            let client = profileRelaySessions.apiClient(forProfileID: profile.id)
            do {
                do {
                    let _: PushRegisterResponse = try await client.post(path: "push/register", body: body, accessToken: accessToken)
                } catch RelayAPIClient.ClientError.unauthorized {
                    // Dormant tokens go stale between visits — one refresh,
                    // one retry, then give up quietly.
                    guard let refreshed = await profileRelaySessions.refreshAccessToken(forProfileID: profile.id) else {
                        continue
                    }
                    accessToken = refreshed
                    let _: PushRegisterResponse = try await client.post(path: "push/register", body: body, accessToken: accessToken)
                }
                profileRelaySessions.markPushTokenRegistered(true, profileID: profile.id, token: token)
                containerLog.notice("registerPushToken: dormant relay '\(profile.name, privacy: .public)' accepted push registration")
            } catch {
                containerLog.notice("registerPushToken: dormant relay '\(profile.name, privacy: .public)' failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - In-app permission revocation (#6 / OPEN_ITEMS #23)
    //
    // The app can't rescind an iOS grant, so in-app revoke means durably
    // stopping Talaria's USE of it: collection halts immediately, and the
    // persisted UserSettings flag keeps SensorUploadService.start() from
    // resurrecting it on the next launch. Camera/Photos stay deep-link-only.

    /// #137: the master sensor-streaming opt-in. Enabling starts the
    /// capture/drain loop (the upload path stays Hermes-gated underneath);
    /// disabling stops it and drops the queued outbox — #6 revoke parity.
    func setSensorStreamingEnabled(_ enabled: Bool) async {
        settingsStore.settings.sensorStreamingEnabled = enabled
        if enabled {
            restartSensorPipelineIfPaired()
        } else {
            sensorUploadService?.stop()
            sensorUploadService?.resetOutbox()
        }
        await permissionsStore.reloadCapabilities()
    }

    /// Revoke (`false`) or restore (`true`) the app's HealthKit use.
    /// Enabling requests the OS grant contextually first (#137 / the #69
    /// pattern) — a no-op after the install's first decision (read-only
    /// types re-prompt never; the start() re-assert below restores the
    /// in-memory status).
    func setHealthCollectionEnabled(_ enabled: Bool) async {
        settingsStore.settings.healthCollectionEnabled = enabled
        if enabled {
            await permissionsStore.requestPermission(for: .health)
            restartSensorPipelineIfPaired()
        } else {
            await sensorUploadService?.disableHealthCollection()
        }
        await permissionsStore.reloadCapabilities()
    }

    /// Revoke (`false`) or restore (`true`) the app's location use. Revoking
    /// also resets the sync preference to foreground-only so a later
    /// re-enable doesn't silently resume background sync.
    func setLocationCollectionEnabled(_ enabled: Bool) async {
        settingsStore.settings.locationCollectionEnabled = enabled
        if enabled {
            await permissionsStore.requestPermission(for: .location)
            restartSensorPipelineIfPaired()
        } else {
            sensorUploadService?.disableLocationCollection()
            settingsStore.settings.locationSyncPreference = .foregroundOnly
            permissionsStore.updateLocationSyncPreference(.foregroundOnly)
        }
        await permissionsStore.reloadCapabilities()
    }

    /// Revoke (`false`) or restore (`true`) the app's motion use (#137 —
    /// motion joins the #6 per-sensor gates). Enabling requests the OS grant
    /// contextually first (the #69 pattern; no-op when already determined).
    func setMotionCollectionEnabled(_ enabled: Bool) async {
        settingsStore.settings.motionCollectionEnabled = enabled
        if enabled {
            await permissionsStore.requestPermission(for: .motion)
            restartSensorPipelineIfPaired()
        } else {
            sensorUploadService?.disableMotionCollection()
        }
        await permissionsStore.reloadCapabilities()
    }

    /// Revoke (`false`) or restore (`true`) push notifications. The existing
    /// register path deactivates the relay registration when the flag is off
    /// and re-registers the cached APNs token when it's on.
    func setNotificationsEnabled(_ enabled: Bool) async {
        settingsStore.settings.notificationsEnabled = enabled
        await registerPushTokenIfNeeded(cachedAPNsDeviceToken ?? "")
        await permissionsStore.reloadCapabilities()
    }

    /// Re-enabling a sensor rides the normal start() wiring, which is gated
    /// on the collection flags — a stop/start rebuilds exactly the enabled set.
    private func restartSensorPipelineIfPaired() {
        guard pairingStore.isPaired else { return }
        sensorUploadService?.stop()
        sensorUploadService?.start()
    }

    /// #137 one-shot grandfathering — see SensorStreamingGrandfathering.
    /// Deferred while protected data is sealed (post-reboot background
    /// launch): pairing reads as absent there, and stamping the migration
    /// done on that false negative would silently stop a streaming device.
    /// Re-invoked from the protected-data recovery closure, so the deferral
    /// resolves on the same seam the #46 credential staleness does.
    func migrateSensorStreamingOptInIfNeeded() {
        guard UIApplication.shared.isProtectedDataAvailable else {
            containerLog.notice("sensor opt-in migration deferred — protected data unavailable")
            return
        }
        pairingStore.reloadPersistedConfigurationIfNeeded()
        var settings = settingsStore.settings
        if SensorStreamingGrandfathering.migrateIfNeeded(
            settings: &settings,
            isPaired: pairingStore.isPaired,
            hadPersistedSettings: settingsStore.hadPersistedSettings
        ) {
            settingsStore.settings = settings
            containerLog.notice("sensor opt-in migration: grandfathered streaming ON (active pairing)")
        }
    }

    /// Tells the relay to deactivate push registrations for this device.
    private func deactivatePushRegistration() async {
        guard let apiClient,
              let accessToken = await sessionStore.currentAccessToken() else { return }

        struct DeactivateResponse: Decodable {
            let deactivated: Bool?
        }

        _ = try? await apiClient.post(
            path: "push/deactivate",
            accessToken: accessToken
        ) as DeactivateResponse
    }

    /// M-7: the user's notifications toggle governs EVERY paired relay, not
    /// just the active one. Best-effort, like the active path.
    private func deactivateDormantPushRegistrations() async {
        guard let profilesStore, let profileRelaySessions else { return }

        struct DeactivateResponse: Decodable {
            let deactivated: Bool?
        }

        for profile in profilesStore.profiles where profile.id != profilesStore.activeProfileID {
            guard profileRelaySessions.isPaired(profileID: profile.id),
                  let accessToken = await profileRelaySessions.accessToken(forProfileID: profile.id) else { continue }
            _ = try? await profileRelaySessions.apiClient(forProfileID: profile.id).post(
                path: "push/deactivate",
                accessToken: accessToken
            ) as DeactivateResponse
            profileRelaySessions.markPushTokenRegistered(false, profileID: profile.id)
        }
    }

    private func registerStoredPushTokenIfNeeded() async {
        guard let storedToken = UserDefaults.standard.string(forKey: Self.apnsTokenDefaultsKey) else {
            return
        }
        await registerPushTokenIfNeeded(storedToken)
    }

    // MARK: - Run-completion push watch (#38)
    //
    // Chat rides the direct :8642 path, so the relay never sees a run happen.
    // These calls are the bridge: on detach the app names the session it
    // walked away from, the relay polls the gateway's messages endpoint, and
    // an APNs alert (payload `session_id`) fires when the reply lands. All
    // best-effort — a failed watch just means no push, and the existing
    // foreground reconcile still recovers the reply.

    /// Asks the relay to watch the currently pending run, if there is one.
    /// Called on the background transition; the stream-detach callback
    /// (`onRunDetached`) covers the lock-mid-stream case where the scene
    /// phase change has already passed.
    func watchPendingRunIfNeeded() async {
        guard let sessionId = chatStore.pendingRunSessionId else { return }
        await postPushWatch(sessionId: sessionId)
    }

    /// M-7: a watch must be posted to the relay that watches the session's
    /// BIRTH gateway — a run on the Mac can't be watched by OJAMD's relay.
    /// Returns nil for the active profile (and for pre-profile sessions,
    /// which all live on the migrated/active backend): those take the
    /// original sessionStore-backed path.
    private func dormantWatchProfileID(forSessionID sessionId: String) -> UUID? {
        guard let profilesStore, let sessionProfileIndex else { return nil }
        let target = sessionProfileIndex.index.routingProfileID(
            forSessionID: sessionId,
            activeProfileID: profilesStore.activeProfileID
        )
        guard let target, target != profilesStore.activeProfileID else { return nil }
        return target
    }

    func postPushWatch(sessionId: String) async {
        guard settingsStore.settings.notificationsEnabled else { return }

        struct WatchBody: Encodable { let sessionId: String }
        struct WatchResponse: Decodable {}

        if let dormantProfileID = dormantWatchProfileID(forSessionID: sessionId) {
            // M-7: the session lives on a non-active backend — its own relay
            // holds this device's push registration and watches its gateway.
            guard let profileRelaySessions,
                  profileRelaySessions.sessionState(forProfileID: dormantProfileID)?.pushTokenRegistered == true,
                  let accessToken = await profileRelaySessions.accessToken(forProfileID: dormantProfileID)
            else { return }
            do {
                let _: WatchResponse = try await profileRelaySessions.apiClient(forProfileID: dormantProfileID).post(
                    path: "push/watch",
                    body: WatchBody(sessionId: sessionId),
                    accessToken: accessToken
                )
                containerLog.notice("postPushWatch: dormant-profile relay watching session for completion push")
            } catch {
                containerLog.notice("postPushWatch: dormant-profile watch failed (no completion push this run): \(error.localizedDescription, privacy: .public)")
            }
            return
        }

        guard sessionStore.state.pushTokenRegistered,
              let apiClient,
              let accessToken = await sessionStore.currentAccessToken()
        else { return }

        do {
            let _: WatchResponse = try await apiClient.post(
                path: "push/watch",
                body: WatchBody(sessionId: sessionId),
                accessToken: accessToken
            )
            containerLog.notice("postPushWatch: relay watching session for completion push")
        } catch {
            containerLog.notice("postPushWatch: failed (no completion push this run): \(error.localizedDescription, privacy: .public)")
        }
    }

    func cancelPushWatch(sessionId: String) async {
        struct CancelBody: Encodable { let sessionId: String }
        struct CancelResponse: Decodable {}

        if let dormantProfileID = dormantWatchProfileID(forSessionID: sessionId) {
            guard let profileRelaySessions,
                  let accessToken = await profileRelaySessions.accessToken(forProfileID: dormantProfileID) else { return }
            _ = try? await profileRelaySessions.apiClient(forProfileID: dormantProfileID).post(
                path: "push/watch/cancel",
                body: CancelBody(sessionId: sessionId),
                accessToken: accessToken
            ) as CancelResponse
            return
        }

        guard let apiClient,
              let accessToken = await sessionStore.currentAccessToken() else { return }

        _ = try? await apiClient.post(
            path: "push/watch/cancel",
            body: CancelBody(sessionId: sessionId),
            accessToken: accessToken
        ) as CancelResponse
    }

    /// Fetches the dynamic slash command catalog from the connected Hermes host.
    /// Merges built-in commands, gateway commands, skills, and personality options.
    func refreshCommandCatalog(force: Bool = false) async {
        if !force,
           let lastCommandCatalogRefreshAt,
           Date().timeIntervalSince(lastCommandCatalogRefreshAt) < Self.commandCatalogRefreshInterval {
            return
        }

        // #136: the catalog fetch is a launch/bootstrap-class probe — ride
        // the short-timeout client so a black-holed relay fails in seconds.
        guard let token = await sessionStore.currentAccessToken(),
              let client = probeAPIClient ?? apiClient else { return }

        struct CatalogResponse: Decodable {
            let commands: [RemoteCommand]?
            let skills: [RemoteSkill]?
            let personalities: [RemotePersonality]?
            let quickCommands: [RemoteQuickCommand]?
            let activeModel: ActiveModel?

            struct RemoteCommand: Decodable {
                let name: String
                let description: String
                let category: String?
                let args: String?
            }
            struct RemoteSkill: Decodable {
                let name: String
                let description: String
            }
            struct RemotePersonality: Decodable {
                let name: String
                let description: String
            }
            struct RemoteQuickCommand: Decodable {
                let name: String
                let description: String
            }
            struct ActiveModel: Decodable {
                let name: String
                let provider: String?
                let contextWindow: Int?
            }
        }

        do {
            let response: CatalogResponse = try await client.get(
                path: "commands",
                accessToken: token
            )

            var catalog = SlashCommand.localCommands
            var catalogIDs = Set(catalog.map(\.id))
            let remoteCommands = response.commands ?? []
            let skills = response.skills ?? []
            let personalities = response.personalities ?? []
            let quickCommands = response.quickCommands ?? []

            // Add remote built-in commands (skip any that overlap with local)
            for cmd in remoteCommands {
                let command = SlashCommand.fromRemote(
                    name: cmd.name,
                    description: cmd.description,
                    category: cmd.category ?? "Agent",
                    args: cmd.args
                )
                if catalogIDs.insert(command.id).inserted {
                    catalog.append(command)
                }
            }

            // Add skill commands
            for skill in skills {
                let command = SlashCommand.fromSkill(name: skill.name, description: skill.description)
                if catalogIDs.insert(command.id).inserted {
                    catalog.append(command)
                }
            }

            // `/personality <name>` suggestions only appear once the user starts
            // typing `/personality`, keeping the top-level dropdown manageable.
            for personality in personalities {
                let command = SlashCommand.fromPersonality(
                    name: personality.name,
                    description: personality.description
                )
                if catalogIDs.insert(command.id).inserted {
                    catalog.append(command)
                }
            }

            // Hermes docs say quick commands resolve at dispatch time and are not
            // included in built-in autocomplete tables, but we still track them so
            // typed commands can be considered part of the known catalog.
            for quickCommand in quickCommands {
                let command = SlashCommand.fromQuickCommand(
                    name: quickCommand.name,
                    description: quickCommand.description
                )
                if catalogIDs.insert(command.id).inserted {
                    catalog.append(command)
                }
            }

            if remoteCommands.isEmpty && skills.isEmpty && personalities.isEmpty && quickCommands.isEmpty {
                chatStore.resetCommandCatalog()
            } else {
                chatStore.replaceCommandCatalog(
                    catalog,
                    activeModel: response.activeModel?.name,
                    contextWindow: response.activeModel?.contextWindow
                )
                lastCommandCatalogRefreshAt = .now
            }
        } catch {
            // Fallback to built-in list — catalog is a nice-to-have. Keep the
            // active model + Hermes-reported context window: the catalog rides
            // the relay, and a transient fetch failure must not demote the CTX
            // denominator to the nominal client-side table (#4).
            chatStore.restoreBuiltInCatalog()
        }
    }

    /// Best-effort seed for the model chip label. Uses the shim's cached model
    /// list (no refresh — fast) and extracts the `model` field (the persistent
    /// default id). Only called when the command catalog didn't supply one.
    private func seedActiveModelFromShim() async {
        do {
            // #136: launch/bootstrap-class probe — the short timeout keeps a
            // black-holed shim (:8765) from stalling background init.
            let options = try await modelsShimClient.fetchModels(
                refresh: false,
                timeout: RelayAPIClient.bootstrapProbeRequestTimeout
            )
            // #46: harvest the pricing this payload always carried.
            ModelPricingCatalog.shared.ingest(options)
            if let currentModel = options.model, !currentModel.isEmpty {
                chatStore.replaceCommandCatalog(
                    chatStore.commandCatalog,
                    activeModel: currentModel
                )
                containerLog.verbose("seedActiveModelFromShim: seeded '\(currentModel)'")
            }
        } catch {
            // Shim unreachable / not configured — chip will show fallback ("HERMES")
            containerLog.notice("seedActiveModelFromShim: shim unavailable — \(error.localizedDescription, privacy: .public)")
        }
    }

    func reportAppStateIfNeeded(_ state: String) async {
        guard pairingStore.isPaired, let apiClient, let accessToken = await sessionStore.currentAccessToken() else {
            return
        }

        struct AppStateBody: Encodable {
            let state: String
        }

        struct AppStateResponse: Decodable {}

        _ = try? await apiClient.post(
            path: "device/app-state",
            body: AppStateBody(state: state),
            accessToken: accessToken
        ) as AppStateResponse
    }

    /// Snapshots current app state into the App Group shared container
    /// so Home Screen widgets and CarPlay widgets can display it.
    func updateWidgetData() {
        let lastMessage = chatStore.conversation?.messages.last
        var data = SharedWidgetDataStore.read()
        data.hostName = hostStore.currentHost?.resolvedDisplayName
        data.hostOnline = hostStore.isHostOnline
        data.voiceSessionActive = talkStore.isSessionActive
        data.updatedAt = .now
        // Appearance snapshot for "Match App" widget themes. Uses the effective
        // theme so automatic (seasonal) mode carries into widgets too (issue #24).
        data.appearanceTheme = settingsStore.settings.effectiveAppearanceTheme().rawValue
        data.appearanceAccent = settingsStore.settings.appearanceAccent.rawValue
        if let msg = lastMessage {
            data.lastMessagePreview = String(msg.content.prefix(120))
            data.lastMessageSummary = HermesWidgetData.summarize(msg.content)
            data.lastMessageSender = msg.sender.rawValue
            data.lastMessageAt = msg.timestamp
        }
        // #126: latest briefing for the widget — the push-wake path already
        // orders loadInbox(force:) before this call.
        data.stampBriefing(from: inboxStore.items)
        SharedWidgetDataStore.write(data)
    }

    /// Pairing-lifecycle reset seam (internal so the #136 reset-race tests
    /// can drive it): wired to `PairingStore.onPairingChanged` in
    /// `makeDefault`.
    func handlePairingRemoved() async {
        isInitialized = false
        // #136: a half-flight background bootstrap must not land relay
        // state into the freshly reset stores below.
        cancelBackgroundBootstrap()
        await talkStore.endSessionIfNeeded()
        talkStore.reset()
        sensorUploadService?.stop()
        sensorUploadService?.resetOutbox()
        router.selectedTab = .chat
        router.activeSheet = nil
        router.resetAll()
        chatStore.reset()
        inboxStore.reset()
        hostStore.reset()
        lastKnownHostOnline = false
        lastCommandCatalogRefreshAt = nil
        LiveActivityService.endAllActivities()
        SharedWidgetDataStore.write(.empty)
    }

    private func reconcileLiveActivities() {
        if talkStore.isSessionActive || chatStore.isStreaming {
            return
        }
        LiveActivityService.endAllActivities()
    }

    // MARK: - Hermes Sessions API key

    /// The active profile's credential scope (Lane M) — nil resolves the
    /// legacy key strings (the migrated profile, and bare test containers).
    private var activeCredentialScope: UUID? {
        profilesStore?.activeProfile?.credentialScopeID
    }

    /// Persists the Hermes API server key in the Keychain (under the ACTIVE
    /// profile's slot) and updates the in-memory copy that the chat client
    /// reads on each request.
    func saveHermesAPIKey(_ value: String) async {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        hermesAPIKey = trimmed
        chatAPIKeyBox?.value = trimmed
        gatewayKeyCache?.set(trimmed, forScope: activeCredentialScope)
        // #27: the key is the chat-routing signal — re-resolve the brain
        // indicator immediately instead of waiting for the next health probe.
        chatBackendRouter?.refreshActiveBrain()
        guard let secureStore else { return }
        let key = BackendProfileScopedKeys.gatewayAPIKey(activeCredentialScope)
        if trimmed.isEmpty {
            await secureStore.delete(key: key)
        } else {
            await secureStore.store(key: key, value: trimmed)
        }
    }

    // MARK: - Lane M: profile switching (M-6) + dormant freshness (M-9)

    /// Re-homes the app onto a newly activated profile. NON-DESTRUCTIVE by
    /// construction: nothing is cleared — the previous profile's pairing,
    /// tokens, and sessions stay in their slots, and the current conversation
    /// keeps working via its birth-profile affinity (M-5). Only the
    /// relay-plane interactive surfaces (inbox, host status, push watch
    /// arming) and the shim/model surfaces re-resolve.
    func handleActiveProfileChanged(to profile: BackendProfile) async {
        containerLog.notice("profile switch: activating '\(profile.name, privacy: .public)'")
        // #136: the launch background bootstrap may still be in flight
        // against the OLD profile's stores — supersede it before rebinding
        // scope, or its late completions would land cross-profile.
        cancelBackgroundBootstrap()
        // Rebind the credential-scoped stores FIRST — their persistence
        // writes resolve the live scope.
        sessionStore.rebindToCurrentScope()
        pairingStore.rebindToActiveProfile()

        // Swap the in-memory credential boxes to the new profile's slots.
        let scope = profile.credentialScopeID
        if let secureStore {
            let gatewayKey = await secureStore.retrieve(key: BackendProfileScopedKeys.gatewayAPIKey(scope)) ?? ""
            gatewayKeyCache?.set(gatewayKey, forScope: scope)
            hermesAPIKey = gatewayKey
            chatAPIKeyBox?.value = gatewayKey
            let shimToken = await secureStore.retrieve(key: BackendProfileScopedKeys.shimToken(scope)) ?? ""
            modelsShimToken = shimToken
            shimTokenBox?.value = shimToken
        }
        chatBackendRouter?.refreshActiveBrain()

        // Relay-plane + model surfaces re-home (M-6/M-10). The conversation
        // and journal are deliberately untouched.
        inboxStore.reset()
        hostStore.reset()
        lastKnownHostOnline = false
        lastCommandCatalogRefreshAt = nil
        chatStore.resetCommandCatalog()

        if pairingStore.isPaired, await sessionStore.currentAccessToken() != nil {
            await sessionStore.bootstrap()
            pairingStore.validateRestoredIdentity()
            await hostStore.refresh()
            lastKnownHostOnline = hostStore.isHostOnline
            await inboxStore.loadInbox(force: true)
            await registerStoredPushTokenIfNeeded()
        }
        await refreshCommandCatalog(force: true)
        if chatStore.activeModelName == nil {
            await seedActiveModelFromShim()
        }
        await talkStore.refreshReadiness()
        await chatStore.refreshDirectHealth()
        updateWidgetData()
    }

    /// M-9: opportunistically refresh DORMANT profiles' relay tokens on
    /// foreground so the 30-day refresh TTL never strands one. The policy
    /// (paired, non-active, >7d since last known refresh, ≥6h between
    /// attempts) keeps this from thrashing.
    func refreshDormantProfileTokensIfNeeded() async {
        guard let profilesStore, let profileRelaySessions else { return }
        let due = DormantTokenRefreshPolicy.profilesDue(
            profiles: profilesStore.profiles,
            activeProfileID: profilesStore.activeProfileID,
            isPaired: { profileRelaySessions.isPaired(profileID: $0.id) },
            lastAttempts: dormantRefreshAttempts
        )
        for profile in due {
            dormantRefreshAttempts[profile.id] = .now
            _ = await profileRelaySessions.refreshAccessToken(forProfileID: profile.id)
        }
    }

    fileprivate var chatAPIKeyBox: MutableHermesAPIKeyBox? {
        get { _chatAPIKeyBox }
        set { _chatAPIKeyBox = newValue }
    }

    // MARK: - Models shim token

    /// Lane M (M-12): a profile's stored gateway API key, for the Server
    /// screen's editor prefill. Reads the Keychain directly — the cache may
    /// not have been populated for never-activated profiles.
    func gatewayAPIKey(for profile: BackendProfile) async -> String? {
        guard let secureStore else { return nil }
        return await secureStore.retrieve(key: BackendProfileScopedKeys.gatewayAPIKey(profile.credentialScopeID))
    }

    /// #116: a profile's stored models-shim token — the Server screen's
    /// honest shim probe follows /healthz with an authenticated call.
    func shimToken(for profile: BackendProfile) async -> String? {
        guard let secureStore else { return nil }
        return await secureStore.retrieve(key: BackendProfileScopedKeys.shimToken(profile.credentialScopeID))
    }

    /// Lane M (M-12): saves a gateway API key into a NAMED profile's slot.
    /// The active profile takes the full `saveHermesAPIKey` path (box +
    /// routing signal); other profiles update the Keychain + cache so the
    /// per-session endpoint resolver picks the key up immediately.
    func saveGatewayAPIKey(_ value: String, for profile: BackendProfile) async {
        guard profile.id != profilesStore?.activeProfileID else {
            await saveHermesAPIKey(value)
            return
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        gatewayKeyCache?.set(trimmed, forScope: profile.credentialScopeID)
        guard let secureStore else { return }
        let key = BackendProfileScopedKeys.gatewayAPIKey(profile.credentialScopeID)
        if trimmed.isEmpty {
            await secureStore.delete(key: key)
        } else {
            await secureStore.store(key: key, value: trimmed)
        }
    }

    /// Persists the models-shim bearer token in the Keychain (under the
    /// ACTIVE profile's slot) and updates the in-memory copy that
    /// `ModelsShimClient` reads on each request.
    func saveModelsShimToken(_ value: String) async {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        modelsShimToken = trimmed
        shimTokenBox?.value = trimmed
        guard let secureStore else { return }
        let key = BackendProfileScopedKeys.shimToken(activeCredentialScope)
        if trimmed.isEmpty {
            await secureStore.delete(key: key)
        } else {
            await secureStore.store(key: key, value: trimmed)
        }
    }

    fileprivate var shimTokenBox: MutableShimTokenBox? {
        get { _shimTokenBox }
        set { _shimTokenBox = newValue }
    }
}

/// Reference-typed holder so the chat client's @MainActor closure captures by
/// reference. The AppContainer rewrites `value` whenever the user updates the
/// API key in Settings, and the next request picks it up without recreating
/// the client.
@MainActor
final class MutableHermesAPIKeyBox {
    var value: String = ""
}

/// Lane M PR 2: in-memory gateway API keys for every profile, keyed by
/// credential scope. The Keychain is the durable store (async); this cache is
/// what the Sessions client's SYNCHRONOUS per-profile endpoint resolution
/// reads. Loaded at startup, updated on save and profile switch.
@MainActor
final class ProfileGatewayKeyCache {
    private var keys: [String: String] = [:]

    private static func cacheKey(_ scope: UUID?) -> String {
        scope?.uuidString ?? "legacy"
    }

    func key(forScope scope: UUID?) -> String? {
        keys[Self.cacheKey(scope)]
    }

    func set(_ value: String?, forScope scope: UUID?) {
        let cacheKey = Self.cacheKey(scope)
        if let value, !value.isEmpty {
            keys[cacheKey] = value
        } else {
            keys.removeValue(forKey: cacheKey)
        }
    }
}
