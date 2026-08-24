import Foundation
import UIKit
import os

private let containerLog = Logger(subsystem: "org.aethyrion.talaria", category: "AppContainer")

@MainActor
@Observable
final class AppContainer {
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

    /// #223 Lane 5: the active profile's persisted model pick (nil = follow
    /// the host default). Reads live from the profiles store so the picker,
    /// the chat client, and profile switches all see one truth.
    var activeModelSelection: ModelSelection? {
        guard let profile = profilesStore?.activeProfile,
              let provider = profile.selectedModelProvider, !provider.isEmpty,
              let modelID = profile.selectedModelID, !modelID.isEmpty else { return nil }
        return ModelSelection(provider: provider, modelID: modelID)
    }

    /// #223 Lane 5: persist a pick (or nil to follow the host default) on the
    /// active profile and arm the live client's per-turn lock. The header
    /// updates optimistically; each turn's `runtime` block corrects it with
    /// the RESOLVED model afterward.
    func applyModelSelection(_ selection: ModelSelection?) {
        profilesStore?.updateActiveProfile {
            $0.selectedModelProvider = selection?.provider
            $0.selectedModelID = selection?.modelID
        }
        sessionsChatClient?.modelSelection = selection
        if let selection {
            chatStore.replaceCommandCatalog(chatStore.commandCatalog, activeModel: selection.displayName)
        }
    }
    /// #156a: the Tasks (scheduled cron jobs) store — rides the ACTIVE
    /// profile's gateway endpoint, same auth as the Sessions chat client.
    /// Nil in bare test containers that construct stores directly.
    var cronJobsStore: CronJobsStore? // harness-visible setter (#180 wiring test)
    /// #156b: the installed-skills browser store — same gateway endpoint +
    /// auth plane as the cron jobs store; read-only (`GET /v1/skills` is the
    /// only skill route). Nil in bare test containers.
    var skillsStore: SkillsStore? // harness-visible setter (#180 wiring test)
    /// #156d: the Insights (session usage/cost) store — same gateway
    /// endpoint + auth plane as Tasks and Skills; read-only over
    /// `GET /api/sessions`. Nil in bare test containers.
    var insightsStore: InsightsStore? // harness-visible setter (#180 wiring test)
    /// #127: the Connected-tier entitlement source (StoreKit 2). Nil in bare
    /// test containers; `connectGateVerdict(for:)` treats nil as unknown,
    /// which only matters once the (dormant) gate is active.
    private(set) var entitlementService: (any EntitlementServiceProtocol)?
    /// M-9 thrash guard: dormant-refresh attempts this process, so a failing
    /// relay isn't re-tried on every foreground.
    private var dormantRefreshAttempts: [UUID: Date] = [:]
    #if DEBUG
    /// #137: the live persistence store, exposed for the Developer screen's
    /// migration-stamp reset only. DEBUG-only so the release container's
    /// surface is unchanged.
    fileprivate(set) var debugPersistence: (any AppPersistenceStoreProtocol)?
    #endif
    /// #17: Spotlight donation for sessions + agent files, strictly behind the
    /// Privacy toggle (default OFF); wired in makeDefault().
    let spotlightIndexing = SpotlightIndexingService()
    /// #16: AlarmKit executor behind the /alarm confirm gate. Stateless until
    /// first use (authorization requested on first schedule).
    let alarmService = AlarmService()
    /// #29: the shared confirm gate for side-effecting device tools — stages
    /// a card in the chat transcript and suspends the tool until the user
    /// decides. Defaults closed (app death = nothing created).
    let toolConfirmationCenter = ToolConfirmationCenter()
    /// #302/#323: the ONE App Lock state every non-UI subsystem consults.
    /// Written only by `AppLockController` (wired in `AppEntry`), read by
    /// `TalkStore`, `ChatStore` and `ToolConfirmationCenter`. An init
    /// parameter rather than an inline property because the stores that read
    /// it are constructed BEFORE the container that owns it.
    let appLockGate: AppLockGate
    /// #304: the HOST-approval card's store — a SIBLING of the device gate
    /// above, deliberately not a reuse of it (different actor: the host's own
    /// gated action on a `/v1/runs` run, answered over the network). Wired in
    /// makeDefault (`sendAnswer` → the router's routing-lock forward;
    /// `chatStore.hostApprovals` → this). Always reachable since #382 — the
    /// runs plane is the only turn transport; the old `useRunsTransport` (#382-deleted)
    /// Developer switch is gone (O6's "default stays OFF" was 3A-era).
    let hostApprovalStore = HostApprovalStore()
    /// #251-2A: the talaria platform transport — auto-pairs with the ACTIVE
    /// profile's gateway key, drains the plugin's durable outbox into the
    /// Inbox, and answers the gateway's phone queries. Optional: nil in bare
    /// test containers and under the #144 mock-pairing gate. Foreground-only
    /// by design (spec §2.1) — see the scene observers in `makeDefault`.
    private(set) var talariaPlatformLink: TalariaPlatformLink?
    private let apiClient: RelayAPIClient?
    /// #136: short-timeout client for launch/bootstrap-class probes (command
    /// catalog). Nil in bare test containers — probe calls fall back to
    /// `apiClient`.
    private let probeAPIClient: RelayAPIClient?
    private let secureStore: (any SecureStoreProtocol)?
    private(set) var hermesAPIKey: String = ""
    private var _chatAPIKeyBox: MutableHermesAPIKeyBox?
    private var isInitialized = false
    /// #369: a launch found the pairing intact but the credential slot
    /// unreadable. Declared here (rather than inferred) so the state has a
    /// name to surface (#180) and a condition to retry on.
    private(set) var credentialsUnreadableHold = false
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
    /// #227 instance 1: single-flight for the command-catalog fetch — a cold
    /// launch fired ~3 concurrent /v1/commands, one won, the extras starved
    /// on the connector leg and burned their 5s as −1001 log noise. Shape
    /// copied from ChatStore's `reconcileInFlight` / AppSessionStore's
    /// `tokenRefreshTasks` (the entry's instruction: copy, don't invent a
    /// third shape). Concurrent callers JOIN the live fetch — that satisfies
    /// force-callers too, since the data they want is the data being fetched.
    private var commandCatalogRefreshTask: Task<Void, Never>?

    init(
        sessionStore: AppSessionStore,
        pairingStore: PairingStore,
        hostStore: HermesHostStore,
        chatStore: ChatStore,
        inboxStore: InboxStore,
        permissionsStore: PermissionsStore,
        settingsStore: SettingsStore,
        talkStore: TalkStore,
        appLockGate: AppLockGate = AppLockGate(),
        apiClient: RelayAPIClient? = nil,
        probeAPIClient: RelayAPIClient? = nil,
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
        self.appLockGate = appLockGate
        self.apiClient = apiClient
        self.probeAPIClient = probeAPIClient
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
        case reconcileLiveActivities
        case updateWidgetData
        case drainShareInbox
        // Background bootstrap — relay/shim-backed, in order.
        case sessionBootstrap
        case validateRestoredIdentity
        case hostRefresh
        case inboxLoad
        case commandCatalogRefresh
        case gatewayModelSeed

        /// Whether the step can touch the network. `validateRestoredIdentity`
        /// is itself local but rides the background list for ordering
        /// (#3/#46); `loadConversationCache` is the persisted-cache restore
        /// (its no-cache fallback fetch rides the chat path, whose timeouts
        /// #136 deliberately leaves alone). (#352 deleted the two sensor
        /// steps — `startSensorService` / `sensorForegroundRefresh` — with
        /// the upload pipeline.)
        var touchesNetwork: Bool {
            switch self {
            case .reloadCapabilities, .loadConversationCache,
                 .reconcileLiveActivities, .updateWidgetData, .drainShareInbox,
                 .validateRestoredIdentity:
                false
            case .sessionBootstrap, .hostRefresh, .inboxLoad, .commandCatalogRefresh,
                 .gatewayModelSeed:
                true
            }
        }

        /// The steps allowed to run before `isInitialized = true` drops the
        /// splash (#136 non-negotiable 1). Local-only, by construction.
        static let criticalPath: [LaunchInitStep] = [
            .reloadCapabilities, .loadConversationCache,
            .reconcileLiveActivities, .updateWidgetData, .drainShareInbox,
        ]

        /// The relay-backed steps the background task runs, in order
        /// (#136 non-negotiable 2). Degraded is the DEFAULT launch posture —
        /// these upgrade it as each lands.
        static let backgroundBootstrap: [LaunchInitStep] = [
            .sessionBootstrap, .validateRestoredIdentity, .hostRefresh, .inboxLoad,
            .commandCatalogRefresh, .gatewayModelSeed,
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
        let allowMockFallbacks = AppEnvironmentPolicy.currentBuild.allowsEnvironmentOverrides
        // #144: a test run must never enrol as a LIVE device. This used to read
        // `UITEST_PAIRING_MODE == "mock"` alone, which relied on every test
        // author remembering to set it — five of nine UI-test launches did not,
        // and the Mac relay accumulated 97 junk device rows with live push
        // registrations. The guard now DETECTS the test run instead, so the safe
        // path is the default and the live path has to be earned.
        let usesMockPairingService = TestRunGuard.mustUseMockPairing(
            environment: processEnvironment,
            explicitMockRequested: processEnvironment["UITEST_PAIRING_MODE"] == "mock",
            allowsEnvironmentOverrides: allowMockFallbacks
        )
        let pairingService: any PairingServiceProtocol
        var activePairingStore: PairingStore?
        // #383: the voice host. Captured by reference like `activePairingStore`
        // above and assigned where the link is minted, further down — voice is
        // constructed before it exists.
        var activeTalariaLink: TalariaPlatformLink?

        if usesMockPairingService {
            pairingService = MockPairingService()
        } else {
            pairingService = LivePairingService()
        }

        // #310: `""` still means "no relay" here, because `RelayAPIClient`
        // takes a non-optional provider and every one of its callers is a
        // relay-plane caller that the gate upstream should already have
        // stopped. The empty string is the LAST line of defence, not the
        // gate — see `handleActiveProfileChanged`.
        let relayBaseURLProvider: @MainActor () -> String = {
            if let paired = activePairingStore?.pairedRelayConfiguration?.baseURLString {
                return paired
            }
            return profilesStore.activeProfile.flatMap(\.resolvedRelayBaseURL) ?? ""
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

        // #144: the PRIMARY must be the mock under test, not just the fallback.
        //
        // `ResilientSessionBootstrapService` tries `primary` FIRST and falls back
        // only on a thrown error. The relay is up during a test run, so the live
        // call SUCCEEDS — which means `allowsFallback` never fires and the device
        // row is created regardless. Routing the guard through `allowsFallback`
        // alone looks like a fix and does nothing; the live registration has to
        // not be attempted at all.
        let sessionBootstrapPrimary: any SessionBootstrapServiceProtocol =
            usesMockPairingService
                ? MockSessionBootstrapService()
                : LiveSessionBootstrapService(apiClient: bootstrapProbeClient)
        let sessionBootstrapService = ResilientSessionBootstrapService(
            primary: sessionBootstrapPrimary,
            fallback: MockSessionBootstrapService(),
            allowsFallback: { allowMockFallbacks && (activePairingStore?.isPaired != true || usesMockPairingService) }
        )

        let sessionStore = AppSessionStore(
            bootstrapService: sessionBootstrapService,
            syncCoordinator: syncCoordinator,
            secureStore: secureStore,
            persistence: persistence,
            environmentProvider: { settingsStore.settings.environment },
            credentialScopeProvider: { profilesStore.activeProfile?.credentialScopeID }
        )

        let runtimePairingStore = PairingStore(
            pairingService: pairingService,
            sessionStore: sessionStore,
            persistence: persistence,
            environmentProvider: { settingsStore.settings.environment },
            relayBaseURLProvider: { profilesStore.activeProfile.flatMap(\.resolvedRelayBaseURL) },
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

        // #45: the Inbox is a live surface — no demo fallback; MockInboxService
        // survives only for the UITest harness (and unit tests), never a
        // production path.
        // #251-2A: the feed is the talaria drain's local cache, not the relay
        // — `LiveInboxService` and its 401-recovery ladder went with the relay
        // inbox route. Nothing here fetches, so there is no longer a fetch that
        // can fail: #45's "unreachable" Inbox state is now dead UI (its copy
        // still names the relay — InboxScreen.unreachableState, left for the
        // Inbox UI pass rather than adjusted blind here).
        let inboxService: any InboxServiceProtocol = usesMockPairingService
            ? MockInboxService()
            : TalariaPlatformInboxService(persistence: persistence)

        // #310: the ONE capability predicate the relay-fed stores share. It
        // resolves per call rather than being captured, so a profile switch
        // or a Server-settings edit changes the answer with no rewiring.
        let relayAvailabilityProvider: @MainActor () -> Bool = {
            profilesStore.activeProfile?.hasRelay == true
        }

        let hostStore = HermesHostStore(
            hostService: hostService,
            accessTokenProvider: { await sessionStore.currentAccessToken() },
            relayAvailabilityProvider: relayAvailabilityProvider
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

        // #190: keyed local-session storage. A nil store (container-creation
        // failure) degrades sessions to the pre-#190 single slot — logged in
        // the store, never a boot crash.
        let localSessionStore = SwiftDataLocalSessionStore.make()
        // #190: the ONE standalone-thread discriminator, shared by the
        // legacy-cache adoption + live-row listing (backend) and the
        // walk-away persist (ChatStore). No configured host means every
        // thread is local by construction; with a host configured, a thread
        // is local iff the store already knows its id — membership IS
        // origin, established when a thread's first assistant turn settles
        // on a local brain (ChatStore.recordLocalOriginAfterSettledTurn) and
        // durable across process death because it lives in the store itself.
        // #190B: the old rule scanned for ANY local-brained assistant turn,
        // so #192's mixed paired-mode threads — a Hermes session the brain
        // flipped under mid-conversation — kept upserting into the local
        // store, violating this rule's own charter.
        let isLocalThread: @MainActor (Conversation) -> Bool = { [hermesAPIKeyBox] conversation in
            if hermesAPIKeyBox.value.isEmpty { return true }
            return localSessionStore?.hasSession(withID: conversation.id) == true
        }

        // #26/#27: the on-device brain + the two-brain router. The retry
        // wrapper stays on the Hermes side only — retries are a network
        // concern the local brain doesn't have. ChatStore talks to the router
        // as its one `any HermesClientProtocol`.
        let localChatBackend = LocalChatBackend(
            persistence: persistence,
            intelligence: localIntelligence,
            sessionStore: localSessionStore,
            isLocalThread: isLocalThread
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

        // Lane M PR 2: per-profile relay access for the non-active backends.
        let profileRelaySessions = ProfileRelaySessionFactory(
            persistence: persistence,
            secureStore: secureStore,
            profileResolver: { profilesStore.profile(id: $0) },
            activeProfileIDProvider: { profilesStore.activeProfileID }
        )
        profileRelaySessions.onTokensRefreshed = { profilesStore.stampTokenRefresh(profileID: $0) }

        let liveLocationService = LiveLocationService()
        let liveHealthService = LiveHealthService()
        let liveMotionService = LiveMotionService()
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
        // #383: held so the plugin transport can be wired after `container`
        // exists — the link is minted further down and voice is built before
        // it. Same post-construction shape as the router's predicates.
        var liveRealtimeVoice: LiveVoiceSessionService?
        // #302/#323: minted before the stores, because voice and chat both
        // read it at construction. `AppLockController` (AppEntry) is its only
        // writer; everything below is a reader.
        let appLockGate = AppLockGate()

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
                // #383: voice bootstraps over the talaria plugin now. The
                // relay and the connector behind it are retired, and with
                // them the second credential family voice used to carry —
                // this reads the same device token the link already holds.
                realtime: {
                    let realtime = LiveVoiceSessionService()
                    liveRealtimeVoice = realtime
                    return realtime
                }(),
                native: nativeVoice,
                // #383: RELAY pairing used to gate this, which is why realtime
                // voice fell back to the local pipeline the moment the relay
                // was retired — a gate that could never open again. The voice
                // host is the talaria plugin link now, and it pairs itself.
                isVoiceHostPaired: { activeTalariaLink != nil },
                // #221: voice honours the SAME brain selection chat does. Read
                // live from the router that owns it — never cached, because the
                // user can change brain mid-session and the old code's whole
                // defect was a routing decision nobody re-evaluated.
                activeBrain: { chatBackendRouter.resolvedBrainForNextTurn() }
            )
        }

        let container = AppContainer(
            sessionStore: sessionStore,
            pairingStore: runtimePairingStore,
            hostStore: hostStore,
            chatStore: ChatStore(
                hermesClient: chatBackendRouter,
                persistence: persistence,
                journal: journalStore,
                appLockGate: appLockGate
            ),
            inboxStore: InboxStore(
                inboxService: inboxService,
                persistence: persistence,
                sessionStore: sessionStore,
                relayAvailabilityProvider: relayAvailabilityProvider
            ),
            permissionsStore: PermissionsStore(
                locationService: liveLocationService,
                healthService: liveHealthService,
                mediaService: processEnvironment["UITEST_PAIRING_MODE"] != nil ? MockMediaService() : LiveMediaService(),
                motionService: liveMotionService
            ),
            settingsStore: settingsStore,
            talkStore: TalkStore(voiceService: voiceService, appLockGate: appLockGate),
            appLockGate: appLockGate,
            apiClient: apiClient,
            probeAPIClient: bootstrapProbeClient,
            secureStore: secureStore,
            localIntelligence: localIntelligence,
            chatBackendRouter: chatBackendRouter
        )

        container.chatAPIKeyBox = hermesAPIKeyBox

        // #304: the host-approval card's plumbing. The store's answer rides
        // the router's routing-lock forward (the same seam shape as
        // hardStopActiveRun), and the address rides the REQUEST VALUE — run
        // id + frozen endpoint — never the client's single-slot
        // activeRunContext (#285's trap).
        container.hostApprovalStore.sendAnswer = { request, choice in
            await chatBackendRouter.answerApproval(
                runID: request.runID,
                choice: choice,
                endpoint: request.endpoint
            )
        }
        container.chatStore.hostApprovals = container.hostApprovalStore
        // #304 review-2 ruling: the voice pipeline deliberately does NOT get
        // this store. Its own consumer swallows a voice turn's approval
        // frame, and the only route from Talk to chat (ending the session)
        // tears the turn — and would tear a raised card — down before the
        // chat is reachable, so a cross-store raise made a promise the
        // teardown broke. Voice states the honest refusal instead (O5's
        // shape); a voice-surface ANSWER path is #305's scope.

        // #97: pin/archive overlay for server-session rows — same persistence
        // seam as every other store, read by the drawer + search surfaces.
        #if DEBUG
        // #137: the Developer screen's migration-stamp reset needs the REAL
        // store — the stamp is Keychain-mirrored, so a reconstructed one
        // without the same mirror would clear only half of it and read as
        // still-migrated.
        container.debugPersistence = persistence
        #endif

        container.conversationListState = ConversationListStateStore(persistence: persistence)

        // Lane M (#114): backend profiles + session→profile index.
        container.profilesStore = profilesStore
        container.sessionProfileIndex = sessionProfileIndex
        container.profileRelaySessions = profileRelaySessions
        container.gatewayKeyCache = gatewayKeyCache
        container.sessionsChatClient = sessionsClient
        // #223 Lane 5: arm the per-turn model lock from the active profile's
        // persisted pick, from the first turn of the launch.
        sessionsClient.modelSelection = container.activeModelSelection
        // #283 (Phase 3 slice 3A): arm the runs-transport switch from the
        // #382: the transport provider seam is gone — `/v1/runs` is the only
        // turn transport and `SessionsHermesClient` dispatches to it
        // unconditionally.
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
        // #156d: Insights — the usage/cost panel reads the same sessions
        // list endpoint the drawer already talks to, on the same gateway +
        // key (#161: zero new infrastructure). Active profile only.
        container.insightsStore = InsightsStore(
            service: InsightsService(
                baseURLProvider: {
                    let raw = (profilesStore.activeProfile?.gatewayBaseURL ?? "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    return raw.isEmpty ? nil : raw
                },
                apiKeyProvider: { hermesAPIKeyBox.value }
            )
        )
        // M-6: activating a profile re-homes the relay-plane surfaces and
        // credential boxes onto the new backend.
        profilesStore.onActiveProfileChanged = { [weak container] profile in
            await container?.handleActiveProfileChanged(to: profile)
        }
        // #127: the Connected-tier entitlement source. Started even while
        // the gate is dormant — the Transaction.updates listener is StoreKit
        // hygiene (unfinished transactions re-deliver until observed), and a
        // launch-time scan keeps the last-known cache warm for flip day.
        let entitlementService = EntitlementService()
        container.entitlementService = entitlementService
        entitlementService.start()

        // M-9: a successful pair mints fresh relay tokens — stamp freshness.
        // (#375/#309 path 5: the post-pair provisioning fetch that used to
        // hang off this hook is deleted with the relay it spoke to.)
        runtimePairingStore.onProfileTokensMinted = { profileID in
            profilesStore.stampTokenRefresh(profileID: profileID)
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
                // #251-2A: the talaria device credential is TWO slots — a
                // surviving half re-pairs to a host this profile no longer
                // exists on, and `ensurePaired` treats a half-written pair as
                // unpaired anyway. Both halves die with the profile.
                await secureStore.delete(key: BackendProfileScopedKeys.talariaDeviceToken(scope))
                await secureStore.delete(key: BackendProfileScopedKeys.talariaDeviceID(scope))
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
        // #251-2A: ONE location provider for this process. The belt's
        // location/weather/places tools and the phone-query reader both read
        // through it, so a remote query and a local turn share a single
        // CLLocationManager — one authorization state, one in-flight fix.
        let sharedLocationProvider = DeviceLocationProvider()
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
            },
            location: sharedLocationProvider
        )
        // #224 Phase 0: arm the confirm gate's GLOBAL approval mode from
        // UserSettings — a CLOSURE, not a captured value, so a later settings
        // write is seen without re-wiring (the provider-closure pattern
        // #283's transport seam established, since retired by #382).
        // `.manual` is the only value the settings layer can
        // produce in this build, so this changes no behaviour; it is what
        // makes the key real rather than vestigial, and it is the one
        // production line Phase 1 edits.
        container.toolConfirmationCenter.modeProvider = { settingsStore.settings.approvalMode }
        // #323-D: the lock OUTRANKS the mode. Wired as a closure beside
        // `modeProvider` for the same reason — a captured Bool would freeze
        // the answer at wiring time, and the whole point is that it changes.
        container.toolConfirmationCenter.lockStateProvider = { appLockGate.isLocked }
        deviceTools += DeviceToolBelt.makeActionTools(
            relay: toolRelay,
            confirmations: container.toolConfirmationCenter,
            alarmService: container.alarmService
        )
        localChatBackend.installTools(deviceTools, relay: toolRelay)
        // #31: the chat screen reads the standalone availability state off
        // the backend directly.
        container.localChatBackend = localChatBackend

        // #251-2A: the talaria platform transport. Every endpoint-shaped
        // input is a CLOSURE, not a captured value — the active profile can
        // change under this object (M-6) and the link must re-resolve the
        // gateway, key and credential scope on the turn AFTER the switch, not
        // keep talking to the host it was built on.
        //
        // Nil under the #144 mock-pairing gate for the same reason sensor
        // upload is: a UI-test run must never enrol this device with a live
        // host.
        let talariaPlatformLink: TalariaPlatformLink? = usesMockPairingService ? nil : TalariaPlatformLink(
            gatewayBaseURL: {
                let raw = (profilesStore.activeProfile?.gatewayBaseURL ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return raw.isEmpty ? nil : raw
            },
            // #285: no api-key closure — the link reads the Keychain itself
            // under its turn's frozen scope (the in-memory box lags a cold
            // launch and a profile switch, and a live closure here was one of
            // the re-resolution seams the atomicity fix removed).
            installID: { sessionStore.state.installationID.uuidString },
            deviceName: { UIDevice.current.name },
            credentialScopeID: { profilesStore.activeProfile?.credentialScopeID },
            secureStore: secureStore,
            responder: PhoneQueryResponder(
                settings: { settingsStore.settings },
                reader: LivePhoneQueryReader(location: sharedLocationProvider)
            ),
            // Through the STORE, never a merge written straight to
            // persistence: InboxStore is the single writer of that blob, and
            // its next local write (a markRead, a #113 alert) would erase a
            // merge that went around it — losing items the plugin has already
            // marked delivered and will never send again.
            onItemsReceived: { [weak container] items in
                guard let container else { return }
                // #362 3D-C: artifact-kind items fork to the mirror
                // correlator and never reach the inbox — an artifact rendered
                // as an inbox row is a file's contents pasted into a
                // notification. The drain's ack upstream is unconditional, so
                // items the correlator ends up dropping are still acked (the
                // no-redelivery half of bar 3D-A).
                let split = ArtifactMirrorRouting.split(items)
                for artifact in split.artifacts {
                    container.chatStore.artifactMirror.receive(artifact)
                }
                guard !split.passthrough.isEmpty else { return }
                container.inboxStore.receivePlatformItems(split.passthrough)
                // …then nudge a repaint. `receivePlatformItems` lands the
                // CACHE only; without this the drain stays invisible until
                // the user next opens the Inbox — including the chat
                // toolbar's unread pip, which reads `inboxStore.items`.
                //
                // Best-effort, and honestly so: `loadInbox` early-returns
                // while one is already in flight, so a concurrent load wins
                // instead — which is fine, because that load reads the same
                // persisted cache this merge just wrote. The reload is
                // entirely local (the platform inbox service makes no network
                // call and `currentAccessToken` is a Keychain read), so it
                // costs a persistence decode, not a round trip.
                Task { await container.inboxStore.loadInbox(force: true) }
            }
        )
        activeTalariaLink = talariaPlatformLink
        container.talariaPlatformLink = talariaPlatformLink
        // #383: voice's transport. Weak on the container so the service does
        // not keep it alive, and resolved per call so a re-bound link (profile
        // switch) is picked up without re-wiring.
        liveRealtimeVoice?.voiceTransportProvider = { [weak container] in container?.talariaPlatformLink }

        // Foreground-only by design (spec §2.1): the plugin's durable outbox
        // is what makes closed-app time safe, so there is nothing to hold a
        // long-poll open for once the user leaves.
        //
        // Scene notifications deliberately, never anything gated on
        // `pairingStore.isPaired`: that is the RELAY pairing — a plane this
        // transport does not use (#223 is retiring it, and #352 deleted the
        // sensor pipeline that lived behind it). Gating the link on it would
        // leave the whole feature dark on a gateway-only host, which is
        // precisely the configuration the lane exists for. `start()`/`stop()`
        // are both idempotent, so overlapping triggers are free.
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil, queue: .main
        ) { [weak container] _ in
            Task { @MainActor [weak container] in
                container?.talariaPlatformLink?.start()
            }
        }
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil, queue: .main
        ) { [weak container] _ in
            Task { @MainActor [weak container] in
                container?.talariaPlatformLink?.stop()
            }
        }

        // #30: PCC tier gates — the picker entry appears only when the
        // entitlement + availability check actually passes, the router
        // consults quota per new message, and locally-routed turns carry
        // their tier to the backend.
        // #395: the user's hard opt-out gates BOTH predicates, not just
        // selectability. Gating only the picker would leave every automatic
        // route to the tier intact — the toggle has to mean "this app does
        // not use PCC", not "the picker hides it".
        chatBackendRouter.isPrivateCloudSelectable = { [weak localChatBackend, weak settingsStore] in
            guard settingsStore?.settings.privateCloudEnabled ?? true else { return false }
            return localChatBackend?.isPrivateCloudAvailable ?? false
        }
        chatBackendRouter.isPrivateCloudUsable = { [weak localChatBackend, weak settingsStore] in
            guard settingsStore?.settings.privateCloudEnabled ?? true else { return false }
            return localChatBackend?.isPrivateCloudUsable ?? false
        }
        chatBackendRouter.isPrivateCloudDisabledByUser = { [weak settingsStore] in
            !(settingsStore?.settings.privateCloudEnabled ?? true)
        }
        chatBackendRouter.applyLocalTier = { [weak localChatBackend] brain in
            localChatBackend?.setPreferredTier(privateCloud: brain == .privateCloud)
        }

        // #190: unified-drawer seams. Membership routes a stored (or live)
        // local session id to the local backend even while Hermes is the
        // active brain; the record/stub pair keeps the last live Hermes list
        // visible — dimmed — after the host stops being configured. (The
        // router already holds the backend strongly as `local`; these
        // closures add no new ownership.)
        chatBackendRouter.isLocalSessionID = { [weak localChatBackend] id in
            guard let uuid = UUID(uuidString: id) else { return false }
            return localSessionStore?.hasSession(withID: uuid) == true
                || localChatBackend?.currentConversation?.id == uuid
        }
        chatBackendRouter.recordRemoteSessions = { localSessionStore?.recordRemoteSessionStubs($0) }
        chatBackendRouter.remoteSessionStubs = { localSessionStore?.remoteSessionStubs() ?? [] }

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


        // Pre-unlock staleness recovery: a post-reboot background launch
        // (location relaunch) runs BEFORE first unlock, when Keychain and
        // protected UserDefaults read as empty. Everything cached at
        // construction — the pairing config, these key boxes — then reads as
        // absent for the process's whole lifetime, and foregrounding that
        // same process shows "not paired / no key" even though nothing was
        // lost. Re-read whenever protected data becomes available (and on
        // activation, covering the zombie-foreground case). Idempotent: only
        // acts on values that are currently empty.
        let refreshCredentialState: @MainActor () -> Void = { [weak container, hermesAPIKeyBox] in
            guard UIApplication.shared.isProtectedDataAvailable else { return }
            container?.pairingStore.reloadPersistedConfigurationIfNeeded()
            // #137: a migration deferred by a pre-unlock launch lands here,
            // after the pairing re-read it depends on.
            container?.migrateSensorStreamingOptInIfNeeded()
            // #369: the same pre-unlock case for the ACCESS token. A launch
            // that held (pairing intact, credential unreadable) resumes its
            // deferred relay half here — this hook and the activation one
            // below both fire on a single unlock, and the retry is idempotent.
            Task { @MainActor in await container?.retryCredentialHoldIfNeeded() }
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
        //
        // #254: THIS OBSERVER IS THE ONLY BACKSTOP, and that is measured, not
        // assumed. Bar 254-F (2026-08-09, two trials + a positive control):
        // `VoiceOverlayScreen.onDisappear` does NOT fire when the app
        // backgrounds a presented `fullScreenCover`, so #139's unguarded
        // `abandonSession()` never runs on this path. Two changes follow:
        //
        //   1. The rule takes `isStartingSession` as well. Gating on
        //      `isSessionActive` alone made a start-in-flight invisible, and a
        //      connect that landed AFTER backgrounding came up live, speaking,
        //      on a forced loudspeaker with no UI and no owner.
        //   2. The revoke is `abandonSession()`, not `endSession()` -- the
        //      generation bump is what stops a connect already in flight from
        //      being adopted when it returns (#139). `abandonSession` calls
        //      `endSession` internally, so nothing the user-end path did is
        //      lost.
        //
        // What is deliberately NOT done: dropping `isSessionActive` from the
        // rule. Revoking on EVERY backgrounding would reach
        // `setActive(false, .notifyOthersOnDeactivation)` with nothing live --
        // the #84 stray-deactivation shape that once killed the live mic. The
        // rule gains a third input; it does not lose its first. Bar 254-C pins
        // that negative case.
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil, queue: .main
        ) { [weak container] _ in
            Task { @MainActor [weak container] in
                guard let container else { return }
                let isActive = container.talkStore.isSessionActive
                let isStarting = container.talkStore.isStartingSession
                guard TalkBackgroundRule.shouldEndSession(
                    isSessionActive: isActive,
                    isStartingSession: isStarting,
                    routeHasCarAudio: TalkAudioRoute.currentRouteHasCarAudio()
                ) else { return }
                // #254: name WHICH arm fired. A verdict that cannot say whether
                // it revoked a live session or an in-flight start is the #220
                // disease one layer up.
                let arm = isActive ? "LIVE" : "STARTING"
                containerLog.notice("#118/#254: app backgrounded with a voice session (\(arm, privacy: .public)) — revoking it")
                await container.talkStore.abandonSession()
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
            // #310: one spelling of the gate. This site already tested
            // "non-nil and non-empty" by hand — `hasRelay` IS that test, now
            // that the type can say it.
            guard container?.profilesStore?.activeProfile?.hasRelay == true else { return }
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
                // #310: an empty result stores nil — see ProfileEditorDraft.
                let mirrored = configuration.activeBaseURLString ?? configuration.customRelayBaseURL
                profile.relayBaseURL = mirrored.isEmpty ? nil : mirrored
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

        // #190: the walk-away persist inside abandonPendingRun writes the
        // departing local thread through these — same store and same
        // discriminator as the backend's legacy adoption.
        container.chatStore.localSessions = localSessionStore
        container.chatStore.isLocalSessionThread = isLocalThread

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
            // #190: unresumable stubs stay out of Spotlight — a result that
            // can't open is the search-pane version of the lie the drawer's
            // dimmed row exists to avoid.
            container?.spotlightIndexing.donateSessions(sessions.filter(\.isResumable))
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
        // #369: an unreadable credential slot is a HOLD, never an unpairing.
        // This guard used to answer nil with `clearLocalPairing()` — the only
        // destructive launch-path reset in the app, and the one its own three
        // siblings (foreground activation, system launch, background refresh)
        // never had: they log BLOCKED and return.
        //
        // The reading cannot license destruction, by construction:
        // `KeychainSecureStore.retrieveSync` collapses EVERY non-success
        // OSStatus into nil, so errSecItemNotFound, errSecInteractionNotAllowed
        // (a pre-first-unlock background launch — location relaunch, BGTask,
        // APNs) and errSecMissingEntitlement arrive here identical. #46/#15 are
        // the same lesson already paid for once: a self-heal firing on an
        // unreadable credential set orphans a healthy pairing.
        //
        // The local critical path below still runs — it is credential-free by
        // design (#136: degraded is the DEFAULT launch posture), and holding it
        // back is what would strand `shouldShowLaunchSplash`
        // (`isPaired && !isInitialized`) for the whole process lifetime, since
        // `initialize()` has exactly one caller. Only the relay-backed half is
        // deferred, to `retryCredentialHoldIfNeeded()`.
        let credentialReadable = await sessionStore.currentAccessToken() != nil
        credentialsUnreadableHold = !credentialReadable
        if !credentialReadable {
            containerLog.warning("initialize: HOLD — access token unreadable; pairing PRESERVED, relay half deferred (#369)")
        }

        // #136: the critical path is LOCAL-ONLY (see LaunchInitStep) — the
        // splash drops on local-state-ready, never on relay convergence. A
        // black-holed host (firewall DROP, no TCP refusal — every request
        // hangs the full URLSession timeout, error -1001) must not strand
        // the launch splash; a cold launch with ZERO hosts reachable lands
        // on a fully functional app in splash-minimum time.
        await permissionsStore.reloadCapabilities()
        await chatStore.loadConversationIfNeeded()
        reconcileLiveActivities()
        SharedWidgetDataStore.clearRetiredHealthMetrics()  // #352 (no-op once clean)
        updateWidgetData()
        // #123: cold-launch safety net for a share queued while the app was
        // dead — idempotent with the scene-activate drain (the inbox empties
        // on first pass, so a double invocation is a no-op). Free-tier
        // surface: stays on the critical path, before any relay-gated work.
        drainShareInbox()
        isInitialized = true
        // Degraded is the DEFAULT launch posture — the relay-backed half
        // runs behind the live UI and upgrades state as each step lands.
        // #369: unless the credential could not be read at all, in which case
        // it waits for a reading rather than running against a nil token.
        if credentialReadable {
            startBackgroundBootstrap()
        }
    }

    /// #369: the retry half of the credential hold. A hold that is never
    /// retried is only a quieter stall, so the post-unlock hooks
    /// (`protectedDataDidBecomeAvailable` / `didBecomeActive`, wired in
    /// `makeDefault`) call this. Idempotent and cheap: a no-op unless a launch
    /// actually held, so both hooks firing on one unlock cannot double-run the
    /// relay half.
    func retryCredentialHoldIfNeeded() async {
        guard credentialsUnreadableHold else { return }
        // An install that was unpaired while held has nothing to resume; the
        // pairing lifecycle owns its own reset.
        guard pairingStore.isPaired else {
            credentialsUnreadableHold = false
            return
        }
        guard await sessionStore.currentAccessToken() != nil else { return }
        credentialsUnreadableHold = false
        containerLog.notice("credential hold: token readable — running the deferred relay half (#369)")
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
            // locked at launch. Relay-backed features (sensor upload, inbox) stay
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
            await seedActiveModelFromGateway()
            guard isCurrent() else { return }
        }
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

    // MARK: - #145 Part D — activations supersede, they do not stack

    /// The chain currently in flight, if any. Cancellation is the mechanism the
    /// chain previously had none of.
    private var foregroundActivationTask: Task<Void, Never>?
    // harness-visible: #145 Part D's pin is peak CONCURRENCY. A call count
    // cannot distinguish "superseded" from "stacked" — both activations
    // legitimately touch the host, so the count rises either way.
    private(set) var liveForegroundActivations = 0
    // harness-visible
    private(set) var peakConcurrentForegroundActivations = 0

    /// #145 Part E(a) — ONE shared deadline around the whole foreground chain.
    ///
    /// **Part A bounded each CALL; it did not bound the SUM.** Ten guarded
    /// network awaits plus `refreshDormantProfileTokensIfNeeded`'s serial
    /// per-profile loop means a degraded-but-answering host can still hold an
    /// activation for minutes while every individual call behaves correctly.
    /// This caps the total.
    ///
    /// **45s is chosen to be generous, not tight, and that is deliberate.** A
    /// deadline that fires on healthy-but-slow refreshes would silently
    /// truncate real work — a worse bug than the slow chain it replaced, and
    /// an invisible one. A normal activation is seconds; this only bites the
    /// pathological case Part A cannot reach.
    ///
    /// **Cancellation, not a race.** The deadline cancels Part D's existing
    /// activation `Task`, and Part D already placed `if Task.isCancelled`
    /// between every network step — so the chain stops at the next boundary
    /// using machinery that is already proven. Racing `task.value` in a
    /// `TaskGroup` was rejected: `Task<Void, Never>.value` cannot be
    /// timeout-raced without stranding the loser's waiter.
    ///
    /// harness-visible: tests shrink this so the suite pays milliseconds.
    var foregroundActivationBudget: Duration = .seconds(45)

    /// How many activations the deadline cut short. **A silent cut is
    /// indistinguishable from a fast success**, and this is the number that
    /// tells the two apart — if it is ever non-zero in the field, the chain
    /// is hitting the pathological case and §F5's device check has something
    /// real to look at. harness-visible.
    private(set) var foregroundActivationsCutShort = 0

    /// #145 Part D — every scene activation used to queue another full
    /// twelve-await chain, with nothing coalescing or superseding.
    ///
    /// Under an outage that multiplies the wedge by however many times the user
    /// tried to wake the app — **which is exactly what a person does when an app
    /// looks frozen.** The bug got worse the more the user fought it, which is
    /// the property that turns a slow refresh into "I restarted my phone."
    ///
    /// **Supersede, not coalesce:** a chain parked on a dead host has nothing
    /// useful left to deliver, and the newest activation carries the freshest
    /// intent. Two things already make discarding it safe — Part B's UI writes
    /// run FIRST, so a superseded chain has already painted last-known-good
    /// state; and the steps are independent refreshes, so the replacing chain
    /// simply redoes them.
    ///
    /// **The cancel is awaited, following `cancelBackgroundBootstrap`'s
    /// precedent of waiting out the unwinding task rather than racing it.**
    /// Without that wait the old chain's teardown overlaps the new chain's
    /// start and both are briefly live — which is the very thing this fixes, and
    /// it would still read as "stacked" to the pin. The wait is bounded because
    /// `URLSession`'s async API is cancellation-aware and Part A capped an
    /// interactive call at 20s.
    func handleAppDidBecomeActive() async {
        if let inFlight = foregroundActivationTask {
            containerLog.notice("handleAppDidBecomeActive: superseding an in-flight activation (#145 Part D)")
            inFlight.cancel()
            await inFlight.value
        }
        // `guard let`, not `self?.` — optional chaining would make this a
        // `Task<()?, Never>` and it must match `foregroundActivationTask`.
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.runForegroundActivation()
        }
        foregroundActivationTask = task

        // #145 Part E(a): the shared deadline. Cancels the chain rather than
        // racing it — Part D's per-step `Task.isCancelled` guards are what
        // make the cancel actually stop work, so this rides machinery that is
        // already built and tested. The watchdog is itself cancelled on the
        // normal path, so a healthy activation costs one suspended task and
        // nothing else.
        let budget = foregroundActivationBudget
        let watchdog = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: budget)
            } catch {
                return // cancelled: the chain finished first, which is the norm
            }
            // Whole body on the MainActor deliberately. A first draft slept
            // off-actor and hopped in via `MainActor.run` — but `return`
            // inside that closure exits only the CLOSURE, so the cancel below
            // still ran on the superseded path. Harmless (cancelling a
            // finished task is a no-op) and wrong to read, which is how a
            // later edit turns it into a real bug.
            guard let self, self.foregroundActivationTask == task else { return }
            self.foregroundActivationsCutShort += 1
            containerLog.notice(
                "handleAppDidBecomeActive: chain exceeded its foreground budget — cutting it short (#145 Part E(a))"
            )
            task.cancel()
        }

        await task.value
        watchdog.cancel()
        if foregroundActivationTask == task {
            foregroundActivationTask = nil
        }
    }

    private func runForegroundActivation() async {
        liveForegroundActivations += 1
        peakConcurrentForegroundActivations = max(peakConcurrentForegroundActivations, liveForegroundActivations)
        defer { liveForegroundActivations -= 1 }

        guard pairingStore.isPaired else {
            containerLog.warning("handleAppDidBecomeActive: BLOCKED — not paired")
            return
        }
        guard await sessionStore.currentAccessToken() != nil else {
            containerLog.warning("handleAppDidBecomeActive: BLOCKED — no access token")
            return
        }
        containerLog.verbose("handleAppDidBecomeActive: paired + token OK, proceeding")

        // #145 Part B — REFRESH THE VISIBLE STATE BEFORE TOUCHING THE NETWORK.
        //
        // These two used to sit at the END of this function, behind ~8 network
        // awaits. So the app could not update what the user sees until the whole
        // chain drained — and under an outage (#136: packets DROPPED, so every
        // request eats the full 60s timeout) that is MINUTES, continuing well
        // after the host is healthy again. **That is the difference between "the
        // app is slow right now" and "the app is broken and I restarted my
        // phone."** It is the property that made #145 outlive its own outage.
        //
        // Safe to run first, and this was checked rather than assumed: both are
        // synchronous, purely local, and idempotent — they read store state into
        // `SharedWidgetDataStore` / `LiveActivityService` and make no network
        // call of any kind. Running them twice costs one dictionary write.
        //
        // They are ALSO still called at the end, deliberately: this pass paints
        // the last-known-good state immediately, the trailing pass lands whatever
        // the refreshes actually fetched. Removing either one is a regression —
        // the early call is the anti-freeze, the late call is the freshness.
        reconcileLiveActivities()
        updateWidgetData()

        // #145 Part D: a superseded chain must actually STOP. Swift cancellation
        // is cooperative — cancelling a Task does not unwind code that never
        // checks, so without these guards a "cancelled" activation would keep
        // walking its remaining awaits and the supersede would be cosmetic.
        // Each network step gets one, so the chain gives up at the first
        // opportunity after a newer activation arrives.
        // #235 F2: a pending run is the user's stranded ANSWER — reconcile
        // FIRST, before the cancellable network ladder. At the old position
        // (end of chain) rapid app-switching superseded the chain before it
        // ever got here — Owen's device, 2026-08-03: answers sat in the store
        // while the chain restarted five fetches ahead of them. Instant no-op
        // when nothing is pending.
        await chatStore.reconcilePendingRuns()
        if Task.isCancelled { return }
        await permissionsStore.reloadCapabilities()
        if Task.isCancelled { return }
        await hostStore.refresh()
        if Task.isCancelled { return }
        lastKnownHostOnline = hostStore.isHostOnline
        await refreshCommandCatalog(force: true)
        if Task.isCancelled { return }
        // Seed the model chip from the shim if the catalog didn't provide one
        // (e.g. relay offline). This path runs even when initialize() aborts.
        if chatStore.activeModelName == nil {
            await seedActiveModelFromGateway()
            if Task.isCancelled { return }
        }
        talkStore.handleAppDidBecomeActive()
        await talkStore.refreshReadiness()
        if Task.isCancelled { return }
        // #4.15: a turn that finished while backgrounded skipped reasoning
        // condensation (foreground-only work) — catch it up now.
        await chatStore.condensePendingReasoning()
        if Task.isCancelled { return }
        // M-9: keep dormant profiles' relay tokens alive.
        await refreshDormantProfileTokensIfNeeded()
        // The trailing UI writes are NOT guarded: they are local, synchronous
        // and idempotent, and a superseded chain that has already reached here
        // may as well publish what it learned. Guarding them would throw away
        // fetched state for no benefit (#145 Part B).
        reconcileLiveActivities()
        await reportAppStateIfNeeded("foreground")
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
    /// relay APNs (which stays the real-time path). Runs one reconcile fetch
    /// (the existing local "run finished" notification fires on found
    /// completions) and rewrites widget data.
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
        // #369: a hold belongs to the launch it was taken on; the fresh
        // initialize() below decides the new pairing's state for itself.
        credentialsUnreadableHold = false
        // #136: supersede any in-flight background bootstrap — the fresh
        // initialize() below must run its own, on the new pairing's state.
        cancelBackgroundBootstrap()
        chatStore.reset()
        inboxStore.reset()
        await initialize()

        // #251-2A: a fresh pairing usually arrives with a provisioned gateway
        // key (#116), so the link has something to pair with now — don't make
        // the user bounce the app to pick it up. Idempotent when the scene
        // observer already started it.
        talariaPlatformLink?.start()
        await talkStore.refreshReadiness()
    }

    // MARK: - In-app permission revocation (#6 / OPEN_ITEMS #23)
    //
    // The app can't rescind an iOS grant, so in-app revoke means durably
    // stopping Talaria's USE of it. Since #352 the persisted UserSettings
    // flag IS the whole mechanism: it gates PhoneQueryResponder.deniedGate,
    // and nothing captures outside a query, so a revoke survives relaunch by
    // construction. Camera/Photos stay deep-link-only.

    /// #137/#352: the master sensor-sharing opt-in — the switch
    /// PhoneQueryResponder.deniedGate consults before any per-sensor flag.
    func setSensorStreamingEnabled(_ enabled: Bool) async {
        settingsStore.settings.sensorStreamingEnabled = enabled
        await permissionsStore.reloadCapabilities()
    }

    /// Revoke (`false`) or restore (`true`) the app's HealthKit use.
    /// Enabling requests the OS grant contextually first (#137 / the #69
    /// pattern) — a no-op after the install's first decision.
    func setHealthCollectionEnabled(_ enabled: Bool) async {
        settingsStore.settings.healthCollectionEnabled = enabled
        if enabled { await permissionsStore.requestPermission(for: .health) }
        await permissionsStore.reloadCapabilities()
    }

    /// Revoke (`false`) or restore (`true`) the app's location use.
    func setLocationCollectionEnabled(_ enabled: Bool) async {
        settingsStore.settings.locationCollectionEnabled = enabled
        if enabled { await permissionsStore.requestPermission(for: .location) }
        await permissionsStore.reloadCapabilities()
    }

    /// Revoke (`false`) or restore (`true`) the app's motion use (#137 —
    /// motion joins the #6 per-sensor gates). Enabling requests the OS grant
    /// contextually first (the #69 pattern; no-op when already determined).
    func setMotionCollectionEnabled(_ enabled: Bool) async {
        settingsStore.settings.motionCollectionEnabled = enabled
        if enabled { await permissionsStore.requestPermission(for: .motion) }
        await permissionsStore.reloadCapabilities()
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
            hadPersistedSettings: settingsStore.hadPersistedSettings,
            persistence: settingsStore.persistence
        ) {
            settingsStore.settings = settings
            containerLog.notice("sensor opt-in migration: grandfathered streaming ON (active pairing)")
        }
    }

    /// Fetches the dynamic slash command catalog from the connected Hermes host.
    /// Merges built-in commands, gateway commands, skills, and personality options.
    func refreshCommandCatalog(force: Bool = false) async {
        if !force,
           let lastCommandCatalogRefreshAt,
           Date().timeIntervalSince(lastCommandCatalogRefreshAt) < Self.commandCatalogRefreshInterval {
            return
        }
        // #227: join an in-flight fetch instead of racing it. The throttle
        // stamp above is success-only and therefore NOT a concurrency guard
        // (every concurrent caller reads it unstamped) — this is.
        if let running = commandCatalogRefreshTask {
            await running.value
            return
        }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performCommandCatalogRefresh()
        }
        commandCatalogRefreshTask = task
        await task.value
        if commandCatalogRefreshTask == task { commandCatalogRefreshTask = nil }
    }

    private func performCommandCatalogRefresh() async {

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
                    // #245: pick-wins. This call site used to write the HOST's
                    // default over a persisted pick's label on every launch
                    // and foreground refresh — while the per-turn lock kept
                    // riding — so the header claimed a model the turns were
                    // not using. CTX denominator deliberately stays
                    // host-reported (#191's standing choice).
                    activeModel: ModelSelection.headerName(
                        pick: activeModelSelection,
                        hostDefault: response.activeModel?.name
                    ),
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
    private func seedActiveModelFromGateway() async {
        // #223 Lane 5: a persisted pick wins outright — no fetch needed.
        if let pick = activeModelSelection {
            chatStore.replaceCommandCatalog(chatStore.commandCatalog, activeModel: pick.displayName)
            return
        }
        do {
            guard let client = sessionsChatClient else { return }
            let catalog = try await client.fetchModelCatalog()
            // #46: harvest the pricing this payload carries.
            ModelPricingCatalog.shared.ingest(catalog)
            if let currentModel = catalog.model, !currentModel.isEmpty {
                chatStore.replaceCommandCatalog(
                    chatStore.commandCatalog,
                    activeModel: currentModel
                )
                containerLog.verbose("seedActiveModelFromGateway: seeded '\(currentModel)'")
            }
        } catch {
            // Gateway unreachable — chip will show fallback ("HERMES")
            containerLog.notice("seedActiveModelFromGateway: catalog unavailable — \(error.localizedDescription, privacy: .public)")
        }
    }

    func reportAppStateIfNeeded(_ state: String) async {
        // #310: #309 path 10 — a relay beacon, so it needs the relay gate
        // like everything else on that plane. `isPaired` cannot stand in for
        // it: the pairing RECORD outlives the profile's relay URL (it
        // persists its own `baseURLString`), so a profile the retirement
        // cleared still reads as paired and this would keep POSTing at the
        // retired host on every foreground/background transition. It is
        // fire-and-forget, so nobody would ever have seen it fail.
        guard profilesStore?.activeProfile?.hasRelay == true else { return }
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
        // #126: latest briefing for the widget. ORDER-INDEPENDENT BY
        // CONSTRUCTION — `stampBriefing` keeps existing values when no
        // briefing is visible in `items`, so an un-refreshed inbox goes
        // STALE here, never blank. (#298: until #238 this line read "the
        // push-wake path already orders loadInbox(force:) before this call."
        // That path — `handleRemoteNotificationWake` — was deleted whole by
        // #238 T4. It was never the only orderer and never a funnel-wide
        // contract: of nine call sites only `runBackgroundBootstrap` and
        // `handleActiveProfileChanged` order a load first, and both survive.)
        data.stampBriefing(from: inboxStore.items)
        SharedWidgetDataStore.write(data)
    }

    /// Pairing-lifecycle reset seam (internal so the #136 reset-race tests
    /// can drive it): wired to `PairingStore.onPairingChanged` in
    /// `makeDefault`.
    func handlePairingRemoved() async {
        isInitialized = false
        // #369: nothing to resume once the pairing is gone (see
        // `retryCredentialHoldIfNeeded`, which makes the same call).
        credentialsUnreadableHold = false
        // #136: a half-flight background bootstrap must not land relay
        // state into the freshly reset stores below.
        cancelBackgroundBootstrap()
        await talkStore.endSessionIfNeeded()
        talkStore.reset()
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

    // MARK: - #247 B2: the profile-switch verdict

    /// What a 5s gateway probe concluded. Mirrors the #151 Test Connection
    /// classification: 2xx online, 401/403 answering-but-unkeyed, anything
    /// else (including timeout — Owen's outage shape) unreachable.
    enum GatewayProbeVerdict: Sendable { case online, unkeyed, unreachable }

    /// The switch verdict banner, rendered in ChatScreen's notice cascade.
    /// Set by `handleActiveProfileChanged`'s probe; an online confirmation
    /// auto-clears, a failure stays until the next switch resolves it.
    private(set) var profileSwitchNotice: String?
    private var lastActivatedProfile: BackendProfile?
    private var switchNoticeTask: Task<Void, Never>?

    /// Pure and pinned (bars 247-B): the exact sentences. The all-hosts row
    /// is the diagnosis Owen had to derive by RDP elimination during the
    /// 2026-08-04 outage — when BOTH gateways are dark, the phone's own
    /// network is the likely culprit and the app says so.
    nonisolated static func profileSwitchNotice(
        newProfileName: String,
        verdict: GatewayProbeVerdict,
        previousProfileName: String?,
        previousVerdict: GatewayProbeVerdict?
    ) -> String? {
        switch verdict {
        case .online:
            return "\(newProfileName): gateway online."
        case .unkeyed:
            return "\(newProfileName): gateway answering, but its API key was rejected."
        case .unreachable:
            if let previousProfileName, previousVerdict == .unreachable {
                return "\(newProfileName) is unreachable — and so is \(previousProfileName). Every host is failing; check this phone's network or Tailscale."
            }
            return "\(newProfileName): gateway unreachable."
        }
    }

    /// One bounded probe (5s), nil when the profile has no gateway URL to
    /// probe. Unauthenticated probes still classify reachability: a live
    /// gateway answers 401/403 (`.unkeyed`), which is all the all-hosts-dead
    /// diagnosis needs from the PREVIOUS host.
    nonisolated static func probeGatewayVerdict(baseURL: String, key: String?) async -> GatewayProbeVerdict? {
        var trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        guard !trimmed.isEmpty, let url = URL(string: trimmed + "/v1/models") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        if let key, !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let status = (response as? HTTPURLResponse)?.statusCode else { return .unreachable }
            if (200 ..< 300).contains(status) { return .online }
            if status == 401 || status == 403 { return .unkeyed }
            return .unreachable
        } catch {
            return .unreachable
        }
    }

    /// Re-homes the app onto a newly activated profile. NON-DESTRUCTIVE by
    /// construction: nothing is cleared — the previous profile's pairing,
    /// tokens, and sessions stay in their slots, and the current conversation
    /// keeps working via its birth-profile affinity (M-5). Only the
    /// relay-plane interactive surfaces (inbox, host status) and the
    /// shim/model surfaces re-resolve.
    ///
    /// #298: "push watch arming" was in that list until #238 deleted the
    /// notification plane out from under it (same dead surface as #226,
    /// retired MOOT for the same reason). Struck 2026-08-09 rather than
    /// silently dropped.
    ///
    /// #285: this handler runs inside `BackendProfilesStore`'s serialized
    /// activation chain. A newer switch CANCELS this task and waits for it to
    /// exit, so `Task.isCancelled` is the supersession signal — every
    /// checkpoint below stops a superseded activation from writing shared
    /// state (key boxes, store resets, the link restart) that belongs to the
    /// winner.
    func handleActiveProfileChanged(to profile: BackendProfile) async {
        containerLog.notice("profile switch: activating '\(profile.name, privacy: .public)'")
        // #136: the launch background bootstrap may still be in flight
        // against the OLD profile's stores — supersede it before rebinding
        // scope, or its late completions would land cross-profile.
        cancelBackgroundBootstrap()
        // #251-2A/#285: supersede the platform link's in-flight turn. The
        // scope has ALREADY moved (`setActiveProfile` assigns state
        // synchronously, before this handler ever gets a turn — pinned by
        // ProfileSwitchAtomicityTests' provenance test), so stop() is not and
        // cannot be a barrier ahead of the switch. It does not need to be:
        // stop() bumps the link's turn epoch, and a superseded turn abandons
        // at its next side-effect checkpoint instead of completing
        // cross-profile. Restarted at the end iff this activation is still
        // the current one.
        talariaPlatformLink?.stop()
        // Rebind the credential-scoped stores FIRST — their persistence
        // writes resolve the live scope.
        sessionStore.rebindToCurrentScope()
        pairingStore.rebindToActiveProfile()

        // Swap the in-memory credential boxes to the new profile's slots.
        let scope = profile.credentialScopeID
        if let secureStore {
            let gatewayKey = await secureStore.retrieve(key: BackendProfileScopedKeys.gatewayAPIKey(scope)) ?? ""
            // #285 checkpoint: past the first await — a superseded
            // activation must not swap the shared credential boxes.
            guard !Task.isCancelled else { return }
            gatewayKeyCache?.set(gatewayKey, forScope: scope)
            hermesAPIKey = gatewayKey
            chatAPIKeyBox?.value = gatewayKey
        }
        chatBackendRouter?.refreshActiveBrain()

        // #247 B2: verdict the switch — probe the NEW and PREVIOUS gateways
        // concurrently and say what happened, instead of the silent
        // everything-times-out Owen debugged by RDP elimination. Detached
        // from the switch itself; verdicts land within ~5s.
        let previous = lastActivatedProfile
        lastActivatedProfile = profile
        switchNoticeTask?.cancel()
        profileSwitchNotice = nil
        let newKey = hermesAPIKey
        switchNoticeTask = Task { [weak self] in
            async let newVerdict = Self.probeGatewayVerdict(baseURL: profile.gatewayBaseURL, key: newKey)
            async let previousVerdict: GatewayProbeVerdict? = {
                guard let previous else { return nil }
                return await Self.probeGatewayVerdict(baseURL: previous.gatewayBaseURL, key: nil)
            }()
            guard let verdict = await newVerdict, !Task.isCancelled else { return }
            let notice = Self.profileSwitchNotice(
                newProfileName: profile.name,
                verdict: verdict,
                previousProfileName: previous?.name,
                previousVerdict: await previousVerdict
            )
            guard let self, !Task.isCancelled else { return }
            self.profileSwitchNotice = notice
            containerLog.notice("profile switch verdict: \(notice ?? "none", privacy: .public) (#247)")
            if verdict == .online {
                // A confirmation is news for a moment, noise after.
                try? await Task.sleep(for: .seconds(5))
                if !Task.isCancelled, self.profileSwitchNotice == notice {
                    self.profileSwitchNotice = nil
                }
            }
        }

        // #223 Lane 5: the new profile's own pick (or none) drives the
        // per-turn lock from the next turn on.
        sessionsChatClient?.modelSelection = activeModelSelection

        // Relay-plane + model surfaces re-home (M-6/M-10). The conversation
        // and journal are deliberately untouched.
        inboxStore.reset()
        hostStore.reset()
        // #180: the host-fed gateway stores are profile-scoped — their
        // cached rows are the OLD host's and must not survive into the new
        // one (the cron editor's skills picker would otherwise offer Host
        // A's skills for a job created on Host B). Each reset() also bumps
        // a generation so an in-flight fetch against the old host cannot
        // land after this line.
        skillsStore?.reset()
        cronJobsStore?.reset()
        insightsStore?.reset()
        lastKnownHostOnline = false
        lastCommandCatalogRefreshAt = nil
        chatStore.resetCommandCatalog()

        // #310: THE RELAY-PLANE GATE. A gateway-only profile has no relay to
        // answer any of this, so the whole block is skipped rather than run
        // and allowed to fail — which is the difference between a switch that
        // lands immediately and #365's ~10 s full-screen stall. The block
        // HOLDS THE SPLASH while it runs (`shouldShowLaunchSplash` is
        // `sessionStore.isBootstrapping && backgroundBootstrapTask == nil`,
        // and a profile-switch bootstrap has no background task), so "it
        // would just fail fast anyway" was never true: bootstrap's own #15
        // recovery ladder adds two more doomed round trips behind it.
        if profile.hasRelay, pairingStore.isPaired, await sessionStore.currentAccessToken() != nil {
            await sessionStore.bootstrap()
            // #285 checkpoint: the bootstrap can be seconds against a dead
            // host — a superseded activation stops writing here.
            guard !Task.isCancelled else { return }
            pairingStore.validateRestoredIdentity()
            await hostStore.refresh()
            guard !Task.isCancelled else { return }
            lastKnownHostOnline = hostStore.isHostOnline
            await inboxStore.loadInbox(force: true)
        }
        // #310: `refreshCommandCatalog` is relay-plane too and sits OUTSIDE
        // the block above — which is why the gate is repeated rather than the
        // block simply widened. It is #309 path 16 (`GET commands`).
        if profile.hasRelay {
            await refreshCommandCatalog(force: true)
        } else {
            chatStore.resetCommandCatalog()
        }
        if chatStore.activeModelName == nil {
            await seedActiveModelFromGateway()
        }
        // #383-G: readiness is NOT gated any more, and the gate that stood
        // here was this item's finding #1 at a second site.
        //
        // Voice used to be #309 paths 11–12 on the relay, so #310 gated this
        // on `profile.hasRelay` and declared realtime unavailable otherwise.
        // #383 moved the bootstrap onto the talaria plugin — and then #310's
        // own migration CLEARED `relayBaseURL` on every profile, so the
        // else-branch became the ONLY branch: every profile switch declared
        // realtime voice dead and said it "needs a relay", a component
        // retired on both hosts.
        //
        // 310-E's REQUIREMENT survives untouched — a switch must never leave
        // the previous profile's verdict on screen — but it is now met by
        // ASKING rather than by assuming. The service degrades honestly on
        // its own: no talaria link resolves to `UnavailableVoiceTransport`
        // (blocked, no network), and a host whose plugin predates #383
        // answers `unsupported` and says so.
        await talkStore.refreshReadiness()
        await chatStore.refreshDirectHealth()
        // #285 checkpoint: a superseded activation must never restart the
        // link — the winning activation's own handler does that, against ITS
        // profile. Without this guard a cancelled B-handler could arm the
        // loop mid-way through C's rebind.
        guard !Task.isCancelled else { return }
        // #251-2A: back on the loop, now resolving the NEW profile's gateway,
        // key and credential scope — unless the app went to the background
        // while this chain ran. `didEnterBackground` already fired its stop()
        // by then, and restarting here would arm a foreground-only loop with
        // nobody watching, with no further foreground event to correct it
        // (the next `didBecomeActive` start() is a no-op on a running loop).
        if UIApplication.shared.applicationState != .background {
            talariaPlatformLink?.start()
        }
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

    /// #251-2A: a profile's minted talaria device token, read the same way —
    /// Keychain direct, no cache to go stale. The Server screen's PLUGIN LINK
    /// row is the only reader: a token in the slot is the one honest local
    /// signal that this phone has paired with the host's talaria plugin.
    func talariaDeviceToken(for profile: BackendProfile) async -> String? {
        guard let secureStore else { return nil }
        return await secureStore.retrieve(key: BackendProfileScopedKeys.talariaDeviceToken(profile.credentialScopeID))
    }

    /// #116: a profile's stored models-shim token — the Server screen's
    /// honest shim probe follows /healthz with an authenticated call.
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

#if DEBUG
// MARK: - #333 instrument trigger (DEBUG builds only; supersedes #196's pair)

extension AppContainer {
    /// Autonomous runs: `TALARIA_RUN_INSTRUMENT=<name>` (+ `TALARIA_TRIALS`,
    /// `TALARIA_CELLS`) runs any registry instrument on launch; the #196 pair
    /// (`TALARIA_AUTO_BATTERY`, `TALARIA_AUTO_ROUTER_PROBE`) still works,
    /// mapped onto the same registry — one mechanism, no drift. Armed only by
    /// launch environment (devicectl passes `DEVICECTL_CHILD_`-prefixed vars;
    /// simctl passes `SIMCTL_CHILD_`-prefixed), inert in every normal run.
    /// Every run is `unattended: true` by definition here — the conductor
    /// refuses alarm-flagged instruments and never arms `alarmWritesAttended`.
    @MainActor
    func runAutoInstrumentsIfArmed() async {
        let env = ProcessInfo.processInfo.environment
        let intents = InstrumentLaunchIntent.parse(env)
        guard !intents.isEmpty, let backend = localChatBackend else { return }
        let conductor = InstrumentConductor(confirmationCenter: toolConfirmationCenter, backend: backend)
        for intent in intents {
            guard let spec = InstrumentRegistry.spec(named: intent.name) else {
                LocalChatBackend.batteryEmit("instrument: UNKNOWN \(intent.name) (#333)")
                continue
            }
            await conductor.run(spec: spec, trials: intent.trials, cells: intent.cells, unattended: true)
        }
        LocalChatBackend.batteryEmit("instrument: AUTO COMPLETE (#333)")
    }
}
#endif
