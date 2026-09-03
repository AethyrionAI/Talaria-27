import Foundation
import UIKit
import os

private let containerLog = Logger(subsystem: "org.aethyrion.talaria", category: "AppContainer")

@MainActor
@Observable
final class AppContainer {
    private static let sharedDefaultContainer = AppContainer.makeDefault()

    let router = TabRouter()
    // #309 Lane B: `sessionStore` (the relay session) and `pairingStore` are
    // DELETED. The last thing either held that the app still needs — the
    // durable installation id — lives in `InstallationIdentity`, and the last
    // question either answered — "is there a host?" — is
    // `hasGatewayCredentials` below.
    /// #309 Lane B: true when the app is running its UI-test doubles. It was
    /// `usesMockServices`, named for the one service it first selected;
    /// that service is gone and the flag still governs the host, inbox and
    /// voice doubles, so it is named for what it means.
    private(set) var usesMockServices = false
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
    /// #422: the on-device memory index — its OWN SwiftData container, never
    /// the session store's (ruling 3 made structural: no host row can live
    /// here). Held on the container because retrieval, the Memory screen and
    /// Forget-everything all read the same store the settle seam writes. Nil
    /// when the container failed to create, and in bare test containers.
    private(set) var memoryStore: MemoryStore?
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
    // #309 Lane C: `profileRelaySessions` (`ProfileRelaySessionFactory`) is
    // DELETED. Lane A left it with exactly one live method — `isPaired(
    // profileID:)` — after the dormant-refresh chain went; its other four
    // reads were already dead (the sensor pipeline's, #352, and the agent-file
    // download's, #375). That last read is re-homed onto
    // `hasGatewayCredentials(forProfileID:)` below, which answers what its
    // four call sites actually wanted to show.
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
    /// #269-B: the conversational installer's consent + verdict store. A
    /// third sibling of the two gates above and, like them, its own actor —
    /// a plain user consent for a message the app wants to send in the
    /// user's name. Its three seams are wired in makeDefault; every default
    /// is an honest dead end, so a store nobody wired can never fake a send
    /// or manufacture a verdict.
    let pluginSetupStore = PluginSetupStore()
    /// #251-2A: the talaria platform transport — auto-pairs with the ACTIVE
    /// profile's gateway key, drains the plugin's durable outbox into the
    /// Inbox, and answers the gateway's phone queries. Optional: nil in bare
    /// test containers and under the #144 mock-pairing gate. Foreground-only
    /// by design (spec §2.1) — see the scene observers in `makeDefault`.
    private(set) var talariaPlatformLink: TalariaPlatformLink?
    // #309 Lane C: `apiClient` / `probeAPIClient` (`RelayAPIClient`) are
    // DELETED with the client. Their last two readers were the
    // `device/app-state` beacon (row 10, deleted by bar C4) and the command
    // catalog's `GET commands` (row 16, re-homed onto `/v1/skills` by bar C3).
    // The #136 short-timeout budget the probe client carried survives on its
    // own in `BootstrapProbeSession`, where the gateway host probe reads it.
    // #309 Lane B widened this from `private`: Connect Host's environment
    // (`AppContainer+ConnectHost.swift`) forgets a profile's credentials, and
    // Swift's `private` is FILE-scoped. Same "private in spirit" widening the
    // #216 harness split made, and the same rule applies — nothing outside
    // this type's own extensions should touch it.
    let secureStore: (any SecureStoreProtocol)?
    private(set) var hermesAPIKey: String = ""
    private var _chatAPIKeyBox: MutableHermesAPIKeyBox?
    private var isInitialized = false
    /// **#309 Lane B: the splash is a LAUNCH surface, and this is what keeps
    /// it one.** `isInitialized` is re-armed by the host-lifecycle seams
    /// (`handleHostConnected` / `handleHostDisconnected`), which is correct —
    /// the host-backed work genuinely has to run again. It is NOT a reason to
    /// re-raise a full-screen splash over a user who is standing in the
    /// middle of the Connect Host wizard.
    ///
    /// Measured, not theorised: the three connect journeys failed the
    /// full-bundle gate at step 3 and passed in isolation. Committing the
    /// credentials flipped `hasGatewayCredentials` true and
    /// `handleHostConnected` flipped `isInitialized` false in the same beat,
    /// so `shouldShowLaunchSplash` became true and covered the wizard — for
    /// as long as the fresh `initialize()`'s host half took, which against a
    /// black-holed address is the full timeout. In isolation it cleared fast
    /// enough to look fine. That is #365's family: a stall visible only when
    /// the host does not answer.
    private var hasCompletedFirstInitialize = false
    /// #369, re-keyed by #411: a launch ran its local half but the active
    /// profile's gateway credentials were not readable yet (the Keychain
    /// restore is async, and a pre-first-unlock launch cannot read it at all).
    /// Declared here (rather than inferred) so the state has a name to surface
    /// (#180) and a condition to retry on.
    ///
    /// It used to mean "the pairing is intact but the RELAY access token is
    /// unreadable", and its whole purpose was to defer `sessionStore
    /// .bootstrap()`. The mechanism is unchanged — hold, then retry when the
    /// credential lands — only the credential it waits on moved planes.
    private(set) var credentialsUnreadableHold = false
    /// #136: the host-backed half of launch, running behind the live UI.
    /// Exposed read-only so tests can await background completion
    /// deterministically. (It no longer suppresses the splash — #309 Lane A
    /// deleted the clause that read it; see `shouldShowLaunchSplash`.)
    private(set) var backgroundLaunchRefreshTask: Task<Void, Never>?
    /// #422 (bar 422-B): the launch backfill over stored local sessions.
    ///
    /// Held so that ONE container starts at most one walk — this is per
    /// instance, not per process, so a second `AppContainer` (a test container,
    /// or a rebuild of the graph) starts its own. That is tolerable rather than
    /// desirable: the walk is idempotent, so two of them cost duplicate WORK and
    /// no duplicate rows (bar 422-A).
    private(set) var memoryBackfillTask: Task<Void, Never>?
    /// #422 (fix round 1, Important item 2): the runner behind that task.
    ///
    /// Held because Forget everything has to reach it — the erase is only half
    /// the job, and the other half (park the cursor, stop the walk) is the
    /// runner's own `cancelAndParkCursorAtCorpusEnd()`. Cancelling the TASK
    /// alone would not do it: a cancelled Task's `Task.yield()` returns
    /// normally, so the walk would carry on writing rows into the store that
    /// was just emptied.
    private(set) var memoryBackfillRunner: MemoryBackfillRunner?
    /// #422: the local session store, kept for the same reason — a forget on a
    /// launch that never started a backfill (no indexer yet, or no task) still
    /// has to park the cursor past the corpus, or the NEXT launch's runner
    /// reads a stale one and walks the erased history back in.
    private var memoryBackfillSessions: (any LocalSessionStoring)?
    /// #136: bumped by every reset/supersede site — a background launch
    /// refresh only touches container state while its generation is current.
    private var launchRefreshGeneration = 0
    /// #136: a superseded run may still be unwinding its cancelled awaits;
    /// the next run drains it first so a half-dead refresh can't
    /// interleave with the fresh one.
    private var supersededLaunchRefreshDrain: Task<Void, Never>?
    /// **#411 — the ONE capability predicate the lifecycle entry points gate
    /// their host-backed work on**, replacing `pairingStore.isPaired`.
    ///
    /// `isPaired` is the RELAY pairing, and the four entry points (plus
    /// `retryCredentialHoldIfNeeded`) hard-guarded their ENTIRE bodies on it —
    /// so a gateway-only install, or the launch pivot's default hostless one,
    /// ran no lifecycle refresh of any kind. The codebase already knew the
    /// trap in one place (`TalariaPlatformLink`'s scene wiring below refuses
    /// the same gate, and says why); the entry points never got the treatment.
    ///
    /// **Derived, not stored.** It reads the two things the chat plane already
    /// consults — the active profile's gateway URL (the same field
    /// `SessionsHermesClient`'s base-URL provider reads) and this container's
    /// mirror of the gateway key cache (`hermesAPIKey`, which
    /// `ChatBackendRouter.isHermesConfigured` reads through its own box). No
    /// new store, and no second source of truth that can drift from the one
    /// the turns use.
    var hasGatewayCredentials: Bool {
        // harness-visible seam — nil in production, so the derivation below
        // cannot be silently mis-wired by a forgotten assignment.
        if let gatewayCredentialsProbe { return gatewayCredentialsProbe() }
        return Self.hasGatewayCredentials(profile: profilesStore?.activeProfile, apiKey: hermesAPIKey)
    }

    /// #309 Lane C: the derivation itself, hoisted to a static so the THREE
    /// readers cannot drift apart. Lane A's container property above is one;
    /// the host and inbox stores' capability gates (constructed in
    /// `makeDefault`, before this container exists) are the other two, and a
    /// second hand-inlined copy in each is how "the same predicate" becomes
    /// three predicates that disagree about a whitespace-only key.
    static func hasGatewayCredentials(profile: BackendProfile?, apiKey: String) -> Bool {
        guard let profile else { return false }
        guard !profile.gatewayBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        return !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// #309 Lane C: the PER-PROFILE twin, and the re-home of
    /// `ProfileRelaySessionFactory.isPaired(profileID:)` — the one live method
    /// that factory had left when Lane A finished with it.
    ///
    /// `isPaired` answered "does this profile hold a relay-era pairing
    /// record?", which is dying vocabulary about a retired plane: the record
    /// persists its own `baseURLString`, so a profile the retirement cleared
    /// still reads as paired forever. What its four call sites actually want
    /// to show — a per-profile connected badge, and the #127 gate's
    /// re-pair-vs-new-connect classification — is whether THIS profile can
    /// talk to a Hermes host, which is exactly `hasGatewayCredentials` scoped
    /// to a profile rather than to the active one.
    ///
    /// Synchronous, because every call site is a view body. The key comes from
    /// `ProfileGatewayKeyCache` (loaded for every profile at startup, updated
    /// on save and on switch) — the same cache `SessionsHermesClient`'s
    /// per-profile endpoint resolver reads, so a profile this says yes about
    /// is a profile a turn could actually be routed to. The ACTIVE profile
    /// reads the container's own key mirror instead, which is briefly AHEAD of
    /// the cache after a save.
    func hasGatewayCredentials(forProfileID profileID: UUID) -> Bool {
        guard let profile = profilesStore?.profile(id: profileID) else { return false }
        let key = profile.id == profilesStore?.activeProfileID
            ? hermesAPIKey
            : (gatewayKeyCache?.key(forScope: profile.credentialScopeID) ?? "")
        return Self.hasGatewayCredentials(profile: profile, apiKey: key)
    }
    // harness-visible: bare test containers hold no profiles store, so this is
    // the only way to exercise the credentialed arm of the #411 gates.
    var gatewayCredentialsProbe: (@MainActor () -> Bool)?
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
        hostStore: HermesHostStore,
        chatStore: ChatStore,
        inboxStore: InboxStore,
        permissionsStore: PermissionsStore,
        settingsStore: SettingsStore,
        talkStore: TalkStore,
        appLockGate: AppLockGate = AppLockGate(),
        secureStore: (any SecureStoreProtocol)? = nil,
        localIntelligence: LocalIntelligenceService = LocalIntelligenceService(),
        chatBackendRouter: ChatBackendRouter? = nil
    ) {
        self.hostStore = hostStore
        self.chatStore = chatStore
        self.inboxStore = inboxStore
        self.permissionsStore = permissionsStore
        self.settingsStore = settingsStore
        self.talkStore = talkStore
        self.appLockGate = appLockGate
        self.secureStore = secureStore
        self.localIntelligence = localIntelligence
        self.chatBackendRouter = chatBackendRouter
    }

    static func sharedDefault() -> AppContainer {
        sharedDefaultContainer
    }

    var shouldShowLaunchSplash: Bool {
        // #309 Lane A: the second clause — `sessionStore.isBootstrapping &&
        // backgroundBootstrapTask == nil` — is DELETED with the relay session
        // bootstrap it watched. It existed so a bootstrap fired OUTSIDE the
        // launch background task (the profile-switch re-home, the unpaired
        // forced re-registration) still raised the splash; both of those
        // callers are gone, so the clause could only ever read false now.
        // That is #365's stall dying at the source rather than being gated.
        //
        // #309 Lane B re-keyed the surviving clause off RELAY pairing, as
        // Lane A's note said it would: the splash exists to cover a host-backed
        // launch's first reads, and whether there IS a host is
        // `hasGatewayCredentials`. A hostless install never had anything to
        // wait for and now never waits.
        // The third clause is the one that makes this a LAUNCH splash rather
        // than an any-time one — see `hasCompletedFirstInitialize`.
        return hasGatewayCredentials && !isInitialized && !hasCompletedFirstInitialize
    }

    // MARK: - Launch partition (#136)

    /// The launch-path partition: which init steps may run before the splash
    /// drops. Pure data so tests can assert no network-touching step ever
    /// creeps in front of `isInitialized = true`, and that the networked steps
    /// keep their order. `initialize()` and
    /// `runBackgroundLaunchRefresh(generation:)` mirror these lists step for
    /// step — a new init step belongs in exactly one list.
    ///
    /// **#309 Lane A dropped two cases: `.sessionBootstrap` and
    /// `.validateRestoredIdentity`.** The first was the relay session
    /// bootstrap; the second was #3/#46's identity check, which existed only
    /// to compare the bootstrapped session's user against the pairing's — with
    /// nothing loading a session there is no user to compare, and the
    /// ordering constraint it enforced ("validation strictly AFTER bootstrap")
    /// has no operands left. `PairingStore.validateRestoredIdentity()` itself
    /// survives untouched for Lane B.
    enum LaunchInitStep: CaseIterable, Sendable {
        // Critical path — local-only, in order.
        case reloadCapabilities
        case loadConversationCache
        case reconcileLiveActivities
        case updateWidgetData
        case drainShareInbox
        // Background launch refresh — host-backed, in order.
        case hostRefresh
        case inboxLoad
        case commandCatalogRefresh
        case gatewayModelSeed

        /// Whether the step can touch the network. `loadConversationCache` is
        /// the persisted-cache restore (its no-cache fallback fetch rides the
        /// chat path, whose timeouts #136 deliberately leaves alone). (#352
        /// deleted the two sensor steps — `startSensorService` /
        /// `sensorForegroundRefresh` — with the upload pipeline.)
        var touchesNetwork: Bool {
            switch self {
            case .reloadCapabilities, .loadConversationCache,
                 .reconcileLiveActivities, .updateWidgetData, .drainShareInbox:
                false
            case .hostRefresh, .inboxLoad, .commandCatalogRefresh,
                 .gatewayModelSeed:
                true
            }
        }

        /// The steps allowed to run before `isInitialized = true` drops the
        /// splash (#136 non-negotiable 1). Local-only, by construction.
        ///
        /// **#411: these now run for EVERY install, not only relay-paired
        /// ones.** They are credential-free by design, which is precisely why
        /// gating them on `pairingStore.isPaired` was the defect.
        static let criticalPath: [LaunchInitStep] = [
            .reloadCapabilities, .loadConversationCache,
            .reconcileLiveActivities, .updateWidgetData, .drainShareInbox,
        ]

        /// The host-backed steps the background task runs, in order
        /// (#136 non-negotiable 2). Degraded is the DEFAULT launch posture —
        /// these upgrade it as each lands, and #411 gates them on the active
        /// profile actually holding gateway credentials.
        static let backgroundLaunchRefresh: [LaunchInitStep] = [
            .hostRefresh, .inboxLoad, .commandCatalogRefresh, .gatewayModelSeed,
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
        let allowMockFallbacks = AppEnvironmentPolicy.currentBuild.allowsEnvironmentOverrides
        // #144: a test run must never enrol as a LIVE device. This used to read
        // `UITEST_PAIRING_MODE == "mock"` alone, which relied on every test
        // author remembering to set it — five of nine UI-test launches did not,
        // and the Mac relay accumulated 97 junk device rows with live push
        // registrations. The guard now DETECTS the test run instead, so the safe
        // path is the default and the live path has to be earned.
        let usesMockServices = TestRunGuard.mustUseMockPairing(
            environment: processEnvironment,
            explicitMockRequested: processEnvironment["UITEST_PAIRING_MODE"] == "mock",
            allowsEnvironmentOverrides: allowMockFallbacks
        )
        // #383: the voice host, captured by reference and assigned where the
        // link is minted further down — voice is constructed before it exists.
        var activeTalariaLink: TalariaPlatformLink?

        // #309 Lane C: the relay base-URL provider and the two `RelayAPIClient`
        // instances built on it are DELETED — nothing calls the relay any more.
        // #309 Lane B finished the job: `BackendProfile.relayBaseURL`, the
        // relay session store and the pairing store are gone too, so there is
        // no relay vocabulary left in this construction at all.
        //
        // The durable installation id (#133/#143) used to be resolved as a
        // side effect of building `AppSessionStore`. It is read directly now,
        // ONCE, from the owner that survived the deletion.
        let installationID = InstallationIdentity.resolve(persistence: persistence)

        // The active profile's gateway key, in memory. Hoisted above the
        // host-fed stores by #309 Lane C — both the gateway host probe and the
        // capability predicate below read it, and both are constructed here.
        let hermesAPIKeyBox = MutableHermesAPIKeyBox()

        // #309 Lane C (row 7): HOST PRESENCE READS THE GATEWAY.
        //
        // `LiveHermesHostService` asked the relay `GET hosts/current` — a
        // record the relay's connector kept about an ENROLLED machine, i.e. a
        // third party's opinion of a second machine's liveness. Both relays
        // are retired (#346/#375), so that question has had no answerer since
        // the retirement: every refresh burned the full probe timeout and the
        // UI reported "unreachable" for a service nobody runs.
        //
        // The gateway IS the host under #251/#269 — no enrollment, no
        // connector, no third party — so the question reduces to "does :8642
        // answer", which is one `GET /health` on the plane chat already uses.
        // #309 Lane A's note here (the deleted #15 401-recovery ladder, and
        // the `accessTokenRefresher` parameter it left behind) goes with the
        // service: the gateway probe carries no relay token at all.
        let hostService: any HermesHostServiceProtocol
        if usesMockServices {
            hostService = MockHermesHostService()
        } else {
            hostService = GatewayHermesHostService(
                baseURLProvider: {
                    let raw = (profilesStore.activeProfile?.gatewayBaseURL ?? "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    return raw.isEmpty ? nil : raw
                },
                apiKeyProvider: { hermesAPIKeyBox.value },
                displayNameProvider: { profilesStore.activeProfile?.name },
                identityProvider: { profilesStore.activeProfileID }
            )
        }

        // #45: the Inbox is a live surface — no demo fallback; MockInboxService
        // survives only for the UITest harness (and unit tests), never a
        // production path.
        // #251-2A: the feed is the talaria drain's local cache, not the relay
        // — `LiveInboxService` and its 401-recovery ladder went with the relay
        // inbox route. Nothing here fetches, so there is no longer a fetch that
        // can fail. (#309 Lane C bar C6 finished the job the parenthesis here
        // used to defer: `InboxScreen.unreachableState`'s copy no longer names
        // the relay, and the store's gate is the gateway-credential one below.)
        let inboxService: any InboxServiceProtocol = usesMockServices
            ? MockInboxService()
            : TalariaPlatformInboxService(persistence: persistence)

        // **#309 Lane C: the ONE capability predicate the host-fed stores
        // share — and it is now the GATEWAY's, not the relay's.**
        //
        // #310 put a shared predicate here and that shape survives untouched:
        // it resolves per call rather than being captured, so a profile switch
        // or a Server-settings edit changes the answer with no rewiring. What
        // changed is what it asks. `profile.hasRelay` gated stores whose
        // fetches now go to the gateway and to a local cache, so on every
        // profile — #310's own migration cleared `relayBaseURL` everywhere —
        // it answered NO and starved two working surfaces. That is #411's
        // wrong-plane class, and #412 is Owen seeing it on the Inbox.
        //
        // Same derivation as `AppContainer.hasGatewayCredentials`, through the
        // shared static so the two cannot drift.
        let hasGatewayCredentials: @MainActor () -> Bool = {
            AppContainer.hasGatewayCredentials(
                profile: profilesStore.activeProfile,
                apiKey: hermesAPIKeyBox.value
            )
        }

        let hostStore = HermesHostStore(
            hostService: hostService,
            hasGatewayCredentials: hasGatewayCredentials
        )

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
            // #309 Lane B: the first clause asked the RELAY pairing store
            // whether a host existed; it asks the gateway credentials now — the
            // same question, on the plane the fallback is actually about.
            allowsFallback: { allowMockFallbacks && (!hasGatewayCredentials() || usesMockServices) }
        )

        // #190: keyed local-session storage. A nil store (container-creation
        // failure) degrades sessions to the pre-#190 single slot — logged in
        // the store, never a boot crash.
        let localSessionStore = SwiftDataLocalSessionStore.make()
        // #422: the local memory index, built exactly like the session store
        // above and for the same reason — a nil store (container-creation
        // failure) is logged in the store and degrades to "no memory", never a
        // boot crash. Separate container by ruling 3.
        let memoryStore = MemoryStore.make()
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
            isLocalThread: isLocalThread,
            // #422 Task 11 fix round 1 (CRITICAL): the backend needs its own
            // reference — `savedNoteThisTurn` answers "did this turn really
            // write a memory" from the store, and cannot borrow ChatStore's
            // copy across the `HermesClientProtocol` boundary. Same store,
            // same toggle closure as ChatStore's own wiring above.
            memoryStore: memoryStore,
            isMemoryEnabled: { settingsStore.settings.memoryEnabled }
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
            // #309 Lane B: the relay-pairing clause is gone. A key in the
            // box IS "a Hermes host has been set up" — the disjunction only
            // ever added the relay's opinion of the same question.
            hasHermesHost: { [hermesAPIKeyBox] in !hermesAPIKeyBox.value.isEmpty }
        )

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

        if usesMockServices {
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
                hasGatewayCredentials: hasGatewayCredentials
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
            secureStore: secureStore,
            localIntelligence: localIntelligence,
            chatBackendRouter: chatBackendRouter
        )

        container.usesMockServices = usesMockServices
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
        // #269-B: the conversational installer's three seams.
        //
        // The prompt rides the app's ORDINARY send path — it is a normal chat
        // turn on the runs plane, not a private channel, which is what makes
        // the whole flow visible in the transcript the user is reading.
        // `sendMessage` returns only once the turn has settled (it awaits its
        // own streaming task), so the probe below runs AFTER the agent is
        // done rather than racing it.
        container.pluginSetupStore.sendPrompt = { [weak container] prompt in
            guard let container else { return false }
            return await container.chatStore.sendMessage(prompt)
        }
        // Shown beside the verdict, never consulted for it (269-B-G).
        container.pluginSetupStore.lastAgentReply = { [weak container] in
            container?.chatStore.conversation?.messages.last(where: { $0.sender == .hermes })?.content ?? ""
        }
        // #269-A's probe, composed with the active profile's held token —
        // the SAME two facts the Server screen's PLUGIN LINK row composes, so
        // the two surfaces cannot disagree about what was seen.
        container.pluginSetupStore.probe = { [weak container] in
            guard let container else { return (nil, nil) }
            let observation = await container.talariaPlatformLink?.probeLinkState()
            guard let profile = container.profilesStore?.activeProfile else { return (observation, nil) }
            return (observation, await container.talariaDeviceToken(for: profile))
        }
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

        // #309 Lane B: `onProfileTokensMinted` is DELETED. It stamped M-9
        // token freshness for the dormant-refresh pass, and Lane A deleted the
        // pass; the tokens it dated are gone with `AppSessionStore`.
        // Keychain hygiene: a deleted profile's credential slot dies with it.
        // The migrated (legacy-keyed) profile is undeletable in practice —
        // it's active/sensor-destination until another profile takes over —
        // but scoped deletion is correct for it too.
        profilesStore.onProfileDeleted = { profile in
            let scope = profile.credentialScopeID
            persistence.purgeRelayCredentialResidue(profileScope: scope)
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
        let talariaPlatformLink: TalariaPlatformLink? = usesMockServices ? nil : TalariaPlatformLink(
            gatewayBaseURL: {
                let raw = (profilesStore.activeProfile?.gatewayBaseURL ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return raw.isEmpty ? nil : raw
            },
            // #285: no api-key closure — the link reads the Keychain itself
            // under its turn's frozen scope (the in-memory box lags a cold
            // launch and a profile switch, and a live closure here was one of
            // the re-resolution seams the atomicity fix removed).
            installID: { installationID.uuidString },
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
        // #396: the sensitivity pick, read live at mint time (a closure, not
        // a captured value — the provider-closure house pattern).
        liveRealtimeVoice?.voiceTuningProvider = { [weak settingsStore] in
            (settingsStore?.settings.voiceSensitivity ?? .normal).rawValue
        }

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
        //
        // **This wiring was RIGHT and ALONE — until #309 Lane A / #411.** For
        // months it was the only place in the file that refused the relay gate
        // and said why, while `initialize()`, `runForegroundActivation()`,
        // `handleSystemLaunch()`, `handleBackgroundRefresh()` and
        // `retryCredentialHoldIfNeeded()` all hard-guarded their whole bodies
        // on `isPaired`. Those five are re-keyed now: local work runs
        // unconditionally, host work asks `hasGatewayCredentials`. **The link
        // stays UNGATED even by that** — it resolves its own credentials per
        // start and degrades honestly with none, so a capability gate here
        // would only add a second, staler opinion.
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
            // #137: a migration deferred by a pre-unlock launch lands here.
            container?.migrateSensorStreamingOptInIfNeeded()
            // #369: the same pre-unlock case for the GATEWAY key. A launch
            // that held (a host configured, its credential unreadable) resumes
            // here — this hook and the activation one below both fire on a
            // single unlock, and the retry is idempotent.
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

        // **#309 Lane B: three relay hooks DELETED here.**
        //
        // `refreshUnpairedRelayContext` cleared the relay session when the
        // environment or the relay URL changed; `onEnvironmentChanged` and
        // `onRelayConfigurationChanged` were its two callers, and the latter
        // also mirrored `UserSettings.relayConfiguration` onto
        // `BackendProfile.relayBaseURL` — a property this lane deleted, fed by
        // a settings surface that retired with M-13. `onPairingChanged` fanned
        // `PairingStore`'s notify into `handlePairingActivated` /
        // `handlePairingRemoved`; the Connect Host screen's commit and
        // disconnect are the only pairing transitions left, and each does its
        // own work directly instead of through a store callback nothing else
        // could observe.

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

        // #422 (bar 422-B): the memory index rides the SAME settle seam as the
        // store-membership upsert just above — that seam is where a turn has
        // already been judged local-origin, which is the only kind of turn
        // ruling 3 lets into this store. No store, no indexer: the seam then
        // behaves exactly as it did before this lane.
        container.memoryStore = memoryStore
        // The master switch is a CLOSURE, not a captured Bool: the indexer is
        // built once here and lives for the process, so reading the setting at
        // construction would leave a mid-session flip inert until the next cold
        // start (Owen's 09-02 ruling covers indexing as well as retrieval).
        container.chatStore.memoryIndexer = memoryStore.map {
            MemoryIndexer(store: $0, isEnabled: { settingsStore.settings.memoryEnabled })
        }
        // #422 Task 11: the explicit "Remember that…" capture, wired the
        // same way — ChatStore writes through this directly (a note is
        // captured before ANY backend runs, never only on a settled local
        // turn), so it needs its own reference rather than reaching through
        // `memoryIndexer`.
        container.chatStore.memoryStore = memoryStore
        container.chatStore.isMemoryEnabled = { settingsStore.settings.memoryEnabled }
        container.startMemoryBackfill(settingsStore: settingsStore, localSessions: localSessionStore)

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
        guard !isInitialized else {
            containerLog.verbose("initialize: SKIP — already initialized")
            return
        }

        // #136: the critical path is LOCAL-ONLY (see LaunchInitStep) — the
        // splash drops on local-state-ready, never on host convergence. A
        // black-holed host (firewall DROP, no TCP refusal — every request
        // hangs the full URLSession timeout, error -1001) must not strand
        // the launch splash; a cold launch with ZERO hosts reachable lands
        // on a fully functional app in splash-minimum time.
        //
        // **#411: THIS BLOCK IS NOW UNCONDITIONAL.** It used to sit behind
        // `guard pairingStore.isPaired` — the RELAY pairing — so a
        // gateway-only install, and the launch pivot's DEFAULT hostless one,
        // ran none of it on any launch. Every step here is credential-free by
        // construction, which is what made the gate wrong rather than merely
        // conservative: it withheld local work to protect a network plane the
        // work never touched.
        await permissionsStore.reloadCapabilities()
        await chatStore.loadConversationIfNeeded()
        reconcileLiveActivities()
        SharedWidgetDataStore.clearRetiredHealthMetrics()  // #352 (no-op once clean)
        updateWidgetData()
        // #123: cold-launch safety net for a share queued while the app was
        // dead — idempotent with the scene-activate drain (the inbox empties
        // on first pass, so a double invocation is a no-op). Free-tier
        // surface: stays on the critical path, before any host-gated work.
        // **LAUNCH ONLY — and this is the defect the connect journeys found.**
        //
        // `drainShareInbox()` ends with `router.popToRoot()`, which is right at
        // launch: a staged share belongs in the composer and the composer is at
        // the root. `initialize()` is not only a launch path any more, though —
        // `handleHostConnected()` runs it when a host is acquired, and that
        // happens while the user is standing INSIDE the Connect Host wizard.
        // With anything queued in the app group, committing the credentials
        // popped them straight out of step 2 into chat.
        //
        // **Why only the bundle run saw it:** the share inbox lives in the
        // shared APP GROUP, which — unlike the per-test defaults suite and
        // Keychain service — is not isolated between UI tests. Alone, the group
        // was empty and `drain()` returned nil, so the pop never fired.
        //
        // Nothing is lost by gating it: `AppEntry` drains on every
        // scenePhase → active, so a share arriving later still lands. Same
        // latch as the splash above, for the same reason — this is a step that
        // belongs to the first launch, not to every reset of it.
        if Self.launchStepsShouldDrainShareInbox(hasCompletedFirstInitialize: hasCompletedFirstInitialize) {
            drainShareInbox()
        }
        isInitialized = true
        hasCompletedFirstInitialize = true

        // Degraded is the DEFAULT launch posture — the host-backed half runs
        // behind the live UI and upgrades state as each step lands.
        //
        // #369, re-keyed by #411: the credentials this half needs are the
        // GATEWAY's, and they may not be readable yet — the Keychain restore
        // in `makeDefault` is async, and a pre-first-unlock launch (location
        // relaunch, BGTask, APNs) cannot read the Keychain at all. Hold
        // rather than run against nothing; `retryCredentialHoldIfNeeded()`
        // resumes when they land. A hostless install simply holds forever,
        // which costs one boolean and no requests.
        //
        // The reading still cannot license destruction (#369's founding
        // point): `KeychainSecureStore.retrieveSync` collapses EVERY
        // non-success OSStatus into nil, so "absent" and "locked" arrive
        // here identical, and nothing below acts on the difference.
        let credentialsReadable = hasGatewayCredentials
        credentialsUnreadableHold = !credentialsReadable
        if credentialsReadable {
            startBackgroundLaunchRefresh()
        } else {
            containerLog.notice("initialize: HOLD — no readable gateway credentials on the active profile; local launch COMPLETE, host half deferred (#369/#411)")
        }
    }

    /// #369: the retry half of the credential hold. A hold that is never
    /// retried is only a quieter stall, so the post-unlock hooks
    /// (`protectedDataDidBecomeAvailable` / `didBecomeActive`, wired in
    /// `makeDefault`) call this. Idempotent and cheap: a no-op unless a launch
    /// actually held, so both hooks firing on one unlock cannot double-run the
    /// host half.
    ///
    /// **#411: the `guard pairingStore.isPaired` that stood here is gone.** It
    /// cleared the hold for an unpaired install, which on a gateway-only
    /// profile meant discarding a hold that was about to become satisfiable.
    func retryCredentialHoldIfNeeded() async {
        guard credentialsUnreadableHold else { return }
        guard hasGatewayCredentials else { return }
        credentialsUnreadableHold = false
        containerLog.notice("credential hold: gateway credentials readable — running the deferred host half (#369/#411)")
        startBackgroundLaunchRefresh()
    }

    // MARK: - Background launch refresh (#136)

    /// Launches the host-backed half of launch behind the live UI.
    /// Single-flight: a second `initialize()` (or any re-entry) while one is
    /// in flight must not double-run it.
    private func startBackgroundLaunchRefresh() {
        guard backgroundLaunchRefreshTask == nil else { return }
        launchRefreshGeneration += 1
        let generation = launchRefreshGeneration
        let predecessor = supersededLaunchRefreshDrain
        supersededLaunchRefreshDrain = nil
        backgroundLaunchRefreshTask = Task { [weak self] in
            // A superseded run may still be unwinding its cancelled awaits —
            // drain it first so its in-flight fetches can't interleave with
            // this run's fresh ones.
            await predecessor?.value
            await self?.runBackgroundLaunchRefresh(generation: generation)
            guard let self, self.launchRefreshGeneration == generation else { return }
            self.backgroundLaunchRefreshTask = nil
        }
    }

    /// Cancels + supersedes any in-flight background launch refresh. Every
    /// `isInitialized = false` reset site calls this (#136 non-negotiable
    /// 5), as does a profile switch — a half-dead run must neither land
    /// stale state past the reset nor block the next run's single-flight
    /// gate.
    private func cancelBackgroundLaunchRefresh() {
        // #309 Lane C: the switch's detached host-plane half is superseded by
        // the same three sites, and for the same reason — it writes host,
        // inbox and catalog state that must not land past a reset or into the
        // next profile.
        profileSwitchRefreshTask?.cancel()
        profileSwitchRefreshTask = nil
        launchRefreshGeneration += 1
        guard let task = backgroundLaunchRefreshTask else { return }
        task.cancel()
        backgroundLaunchRefreshTask = nil
        // Keep a handle so the NEXT run can wait out the unwinding corpse —
        // chained, in case resets stack up before another run starts.
        if let existingDrain = supersededLaunchRefreshDrain {
            supersededLaunchRefreshDrain = Task {
                await existingDrain.value
                await task.value
            }
        } else {
            supersededLaunchRefreshDrain = task
        }
    }

    /// The host-backed launch steps, in
    /// `LaunchInitStep.backgroundLaunchRefresh` order. Every state write is
    /// generation-guarded: a reset that superseded this run wins, and nothing
    /// stale lands after it.
    ///
    /// **#309 Lane A removed the first two steps.** `sessionStore.bootstrap()`
    /// (`device/register` → `session` → the #15 refresh/re-register ladder)
    /// and the `pairingStore.validateRestoredIdentity()` that had to follow it
    /// were the cold-launch half of the doomed relay chain — three network
    /// round trips at a retired service before the first useful one.
    private func runBackgroundLaunchRefresh(generation: Int) async {
        func isCurrent() -> Bool {
            launchRefreshGeneration == generation && !Task.isCancelled
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

    /// Whether `initialize()`'s own share drain should run. Extracted as a
    /// named predicate rather than an inline `if` so the rule has somewhere to
    /// be read and pinned: the drain NAVIGATES, and a navigating step must not
    /// fire on a mid-session re-initialize.
    // harness-visible
    static func launchStepsShouldDrainShareInbox(hasCompletedFirstInitialize: Bool) -> Bool {
        !hasCompletedFirstInitialize
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
    /// **Part A bounded each CALL; it did not bound the SUM.** A chain of
    /// guarded network awaits means a degraded-but-answering host can still
    /// hold an activation for minutes while every individual call behaves
    /// correctly. This caps the total. (#309 Lane A removed the worst
    /// contributor — `refreshDormantProfileTokensIfNeeded`'s serial
    /// per-profile `auth/refresh` loop — but the cap stays: the budget exists
    /// for the chain's shape, not for one step.)
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
    /// **The cancel is awaited, following `cancelBackgroundLaunchRefresh`'s
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

        // **#411: the two guards that stood here are gone.**
        // `guard pairingStore.isPaired` + `guard currentAccessToken() != nil`
        // were the RELAY plane's, and they blocked the ENTIRE body — including
        // the live-activity reconcile and the widget write that #145 Part B
        // deliberately hoisted to the front for exactly the case where the
        // network is unusable. The capability gate now sits mid-chain, where
        // the network work actually starts.
        //
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
        // #4.15: a turn that finished while backgrounded skipped reasoning
        // condensation (foreground-only work) — catch it up now. On-device
        // work, so it moved UP here with #411's re-key: it has no more
        // business behind a host gate than the widget write does.
        await chatStore.condensePendingReasoning()
        if Task.isCancelled { return }
        // Local Talk bookkeeping (session/audio state) — not a host call.
        talkStore.handleAppDidBecomeActive()

        // ── #411: everything BELOW needs a host to ask. ──────────────────
        // Gated on the active profile holding gateway credentials, not on the
        // relay pairing. A hostless install falls through to the trailing UI
        // writes, which is the whole point: local state stays fresh on every
        // foreground for the DEFAULT user (#31's no-pairing-wall stance).
        guard hasGatewayCredentials else {
            containerLog.verbose("handleAppDidBecomeActive: local half only — no gateway credentials on the active profile (#411)")
            reconcileLiveActivities()
            updateWidgetData()
            return
        }
        await hostStore.refresh()
        if Task.isCancelled { return }
        lastKnownHostOnline = hostStore.isHostOnline
        await refreshCommandCatalog(force: true)
        if Task.isCancelled { return }
        // Seed the model chip if the catalog didn't provide one. This path
        // runs even when initialize() held.
        if chatStore.activeModelName == nil {
            await seedActiveModelFromGateway()
            if Task.isCancelled { return }
        }
        await talkStore.refreshReadiness()
        if Task.isCancelled { return }
        // #309 Lane A: `refreshDormantProfileTokensIfNeeded()` stood here —
        // M-9's serial per-profile `auth/refresh` sweep, deleted with the
        // bootstrap chain along with `DormantTokenRefreshPolicy`. It was the
        // single worst offender for #145 Part E's budget: one round trip per
        // dormant relay-bearing profile, all of them retired.
        //
        // The trailing UI writes are NOT guarded: they are local, synchronous
        // and idempotent, and a superseded chain that has already reached here
        // may as well publish what it learned. Guarding them would throw away
        // fetched state for no benefit (#145 Part B).
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
        // #411: the live-activity reconcile is LOCAL and now runs for every
        // install — a system launch (location relaunch, a Live Activity the
        // user tapped) that leaves stale activities on screen is a defect
        // whether or not a relay was ever paired.
        reconcileLiveActivities()
        guard hasGatewayCredentials else {
            containerLog.verbose("handleSystemLaunch: local half only — no gateway credentials on the active profile (#411)")
            return
        }
        await talkStore.refreshReadiness()
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
        // **#411: ungated.** Both steps below are local — the reconcile asks
        // the chat client this device is already configured for (an instant
        // no-op with nothing pending), and the widget write is a dictionary
        // write into the App Group. Gating them on the RELAY pairing meant a
        // gateway-only or hostless install had NO widget refresh on any
        // background wake at all, which is the starved path #411 named that
        // has no per-screen fallback: no screen is on screen.
        // In-memory pendingRun survives warm relaunches only — on a cold
        // background launch there is nothing pending by design (the sessions
        // drawer stays the authoritative recovery surface).
        await chatStore.reconcilePendingRuns()
        updateWidgetData()
    }

    /// Host-lifecycle reset seam (internal so the #136 reset-race tests can
    /// drive it).
    ///
    /// **#309 Lane B renamed it from `handlePairingActivated` and re-homed its
    /// caller.** It was wired to `PairingStore.onPairingChanged` — a store
    /// callback fired by a relay redeem. The transition it models is real and
    /// survives: acquiring a host means the launch's host-backed work has to
    /// happen again. Connect Host's commit is the one caller now.
    func handleHostConnected() async {
        isInitialized = false
        // #369: a hold belongs to the launch it was taken on; the fresh
        // initialize() below decides the new host's state for itself.
        credentialsUnreadableHold = false
        // #136: supersede any in-flight background bootstrap — the fresh
        // initialize() below must run its own, on the new pairing's state.
        cancelBackgroundLaunchRefresh()
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

    /// #422 (bar 422-B): kick off the launch backfill over stored local sessions
    /// — everything the user said before memory existed.
    ///
    /// Deliberately thin. The cursor arithmetic lives in `MemoryBackfillRunner`,
    /// where it is tested; this is construction and a task, and nothing else.
    /// An earlier version kept the walk inline here and had three defects nobody
    /// could see from outside — that is what the extraction is for.
    func startMemoryBackfill(settingsStore: SettingsStore, localSessions: (any LocalSessionStoring)?) {
        // Recorded BEFORE the guard, and that ordering is the whole point
        // (#422 final review, I5): `forgetLocalMemory`'s no-runner fallback
        // reads exactly these two, and assigning them alongside the runner —
        // i.e. only on the path that also produces a runner — made the
        // fallback unreachable dead code. A launch that never starts a walk
        // (no indexer yet, no local store wired) is precisely the launch whose
        // stale cursor the fallback exists to park.
        memoryBackfillSessions = localSessions
        memoryBackfillCursorWriter = { settingsStore.settings.memoryBackfillCursor = $0 }
        guard memoryBackfillTask == nil,
              let localSessions,
              let indexer = chatStore.memoryIndexer else { return }
        let runner = MemoryBackfillRunner(
            sessions: localSessions,
            indexer: indexer,
            isEnabled: { settingsStore.settings.memoryEnabled },
            readCursor: { settingsStore.settings.memoryBackfillCursor },
            writeCursor: { settingsStore.settings.memoryBackfillCursor = $0 })
        memoryBackfillRunner = runner
        // No `self` capture: the task is HELD by the container but does not hold
        // it, so a container that goes away is not kept alive walking history
        // nobody is looking at.
        memoryBackfillTask = Task(priority: .utility) { @MainActor in await runner.run() }
    }

    /// #422: how to persist the backfill cursor, captured from the same
    /// `SettingsStore` the runner writes through. Set alongside the runner so
    /// the no-runner forget path below has a route to the same key.
    private var memoryBackfillCursorWriter: ((Int) -> Void)?

    /// **#422 Forget everything, whole (fix round 1, Important item 2).**
    ///
    /// The screen calls THIS, not `MemoryStore.forgetEverything()` directly,
    /// because erasing the rows is only part of forgetting. Owen ruled that
    /// Forget everything is the only eraser and that retention is never — so
    /// history the user erased must not come back, and there are two ways it
    /// could:
    ///
    ///  1. **A stale cursor.** The launch backfill may not have finished (or
    ///     may never have started). Its cursor points into the middle of the
    ///     user's history, and the next `run()` walks the rest of it back in.
    ///  2. **A walk in flight.** The runner is between conversations on this
    ///     same actor; left alone it resumes and writes rows into the store
    ///     that was just emptied.
    ///
    /// Order matters and is asserted by the runner's own tests: park + refuse
    /// FIRST, erase second.
    ///
    /// The task is cancelled too, and it is worth being exact about what that
    /// does. `Task.yield()` is the walk's ONLY suspension point, and it returns
    /// normally on a cancelled task — the runner checks no cancellation flag of
    /// the Task's own — so `Task.cancel()` alone stops nothing here. The
    /// runner's `isCancelled` is what ends the walk; cancelling the task is
    /// defence in depth against a future suspension point that does honour it.
    func forgetLocalMemory() {
        if let memoryBackfillRunner {
            memoryBackfillRunner.cancelAndParkCursorAtCorpusEnd()
        } else if let memoryBackfillCursorWriter, let memoryBackfillSessions {
            // No runner this launch — but a future one would read the same
            // stale cursor, so park it anyway. Same number, same ordering
            // (a count does not depend on the sort), read from the same store.
            memoryBackfillCursorWriter(memoryBackfillSessions.sessionSummaries().count)
        }
        memoryBackfillTask?.cancel()
        memoryBackfillTask = nil
        memoryStore?.forgetEverything()
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
        var settings = settingsStore.settings
        if SensorStreamingGrandfathering.migrateIfNeeded(
            settings: &settings,
            hasHost: hasGatewayCredentials,
            hadPersistedSettings: settingsStore.hadPersistedSettings,
            persistence: settingsStore.persistence
        ) {
            settingsStore.settings = settings
            containerLog.notice("sensor opt-in migration: grandfathered streaming ON (active pairing)")
        }
    }

    /// Fetches the dynamic slash command catalog from the connected Hermes
    /// host: built-in commands merged with the host's installed SKILLS
    /// (`GET /v1/skills`). Personalities and quick commands were relay-only
    /// and are a ruled loss — see `performCommandCatalogRefresh`.
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

    /// **#309 row 16's ADAPT, executed by Lane C (bar 309-C3): the composer's
    /// catalog reads the GATEWAY's `/v1/skills`.**
    ///
    /// What it replaces: `GET commands` on the relay, which returned four
    /// lists in one payload — remote built-in commands, skills, personalities
    /// and quick commands — plus the host's active model and its context
    /// window. The relay is retired on both hosts (#346/#375), so that fetch
    /// has failed on every launch since the retirement and the composer has
    /// been running on `SlashCommand.allBuiltIn` the whole time.
    ///
    /// **What comes back and what does not, per Owen's 2026-08-19 ruling:**
    /// skills are re-homed; **personalities and quick commands are an ACCEPTED
    /// LOSS** — `/v1/skills` is the only skill-or-command route on `:8642`
    /// (route table, re-verified 2026-08-09), and neither has a gateway
    /// equivalent to move to. Degrading honestly per #180 means exactly that:
    /// nothing is fabricated and no empty section is rendered — the composer
    /// simply offers built-ins plus real skills. `SlashCommand.fromPersonality`
    /// and `.fromQuickCommand` are left in place unused; they belong to the
    /// model, and deleting a constructor is not how a ruled loss is recorded.
    ///
    /// **The other thing the relay payload carried, stated because it is a
    /// real degradation and not an oversight:** `activeModel.contextWindow`
    /// was #191's host-reported CTX denominator, and `/v1/skills` has no such
    /// field (nor does `/api/model/options` — checked). The meter falls back
    /// to `ChatStore.inferredContextWindow`, which is what #4's own comment
    /// anticipated, and to the `/model` chat response's "Context: N tokens"
    /// when the user switches models. This did not regress here; it has been
    /// the live behaviour since the retirement, and this lane is where it
    /// stops being an accident.
    private func performCommandCatalogRefresh() async {
        // The catalog is a gateway read now, so it asks the gateway's own
        // capability question — the same predicate every other host-plane
        // step uses since #411/Lane A. Without credentials there is nothing
        // to ask and nothing to say: keep whatever is on screen rather than
        // resetting it, exactly as a failed refresh does below.
        guard hasGatewayCredentials, let skillsStore else { return }

        // #161's standing rule — zero new infrastructure. `SkillsStore` already
        // owns a `SkillsService` pointed at this profile's gateway and key, it
        // already resets per profile switch (#180), and its own contract is the
        // one this path needs: **errors never replace content that already
        // exists.** Sharing it also means the Skills browser and the composer
        // cannot disagree about what the host has installed — the old code's
        // two planes could, and its comment said so.
        await skillsStore.refresh()
        let skills = skillsStore.skills

        // A refresh that FAILED leaves `skills` holding the last good rows (or
        // empty if none ever landed). Treat it as the old code's catch arm:
        // built-ins on screen, active model and CTX denominator preserved, no
        // success stamp — so the next caller retries instead of being
        // throttled out by a failure.
        if skillsStore.lastErrorMessage != nil {
            if skills.isEmpty { chatStore.restoreBuiltInCatalog() }
            return
        }

        if skills.isEmpty {
            // A host with no skills installed is a real answer, not a failure
            // — and `resetCommandCatalog()` is what the old code did with the
            // all-empty payload.
            chatStore.resetCommandCatalog()
            lastCommandCatalogRefreshAt = .now
            return
        }

        var catalog = SlashCommand.localCommands
        var catalogIDs = Set(catalog.map(\.id))
        for skill in skills {
            let command = SlashCommand.fromSkill(
                name: skill.name,
                description: skill.description ?? ""
            )
            if catalogIDs.insert(command.id).inserted {
                catalog.append(command)
            }
        }
        // #245's pick-wins rule is preserved by omission: with no host default
        // to merge, a persisted pick is never overwritten and the header keeps
        // whatever `seedActiveModelFromGateway` resolved.
        chatStore.replaceCommandCatalog(catalog)
        lastCommandCatalogRefreshAt = .now
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

    // **#309 Lane C bar C4: `reportAppStateIfNeeded` is DELETED (row 10).**
    //
    // It POSTed `device/app-state` to the relay on every foreground and system
    // launch — a fire-and-forget beacon nothing app-side ever read back, whose
    // only consumer was the relay's own device table. The relay is retired on
    // both hosts, so the beacon has been shouting into a closed socket since
    // the retirement; being fire-and-forget is exactly why nobody ever saw it
    // fail. #310 gave it a relay gate rather than deleting it, which was the
    // right call for that lane and is what kept it silent until this one.
    //
    // Nothing replaces it. The gateway plane has no app-state verb, the plugin
    // link's own POST cadence is the liveness signal the host actually uses
    // (#347), and re-homing a beacon nobody reads would be building a second
    // one.
    //
    // Row 5 (`POST device/provisioning`, `ProvisioningService`) was checked in
    // the same pass and is ALREADY ABSENT from the tree — #375 deleted it, as
    // that row's disposition predicted. `git grep -n 'device/provisioning\|
    // ProvisioningService' -- '*.swift'` returns nothing.

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
        // contract: of nine call sites only `runBackgroundLaunchRefresh` and
        // `handleActiveProfileChanged` order a load first, and both survive.)
        data.stampBriefing(from: inboxStore.items)
        SharedWidgetDataStore.write(data)
    }

    /// The other half of the seam — see `handleHostConnected`. Connect Host's
    /// Disconnect is its one caller.
    func handleHostDisconnected() async {
        isInitialized = false
        // #369: nothing to resume once the host is gone (see
        // `retryCredentialHoldIfNeeded`, which makes the same call).
        credentialsUnreadableHold = false
        // #136: a half-flight background bootstrap must not land host state
        // into the freshly reset stores below.
        cancelBackgroundLaunchRefresh()
        await talkStore.endSessionIfNeeded()
        talkStore.reset()
        router.selectedTab = .chat
        router.activeSheet = nil
        // **#309 Lane B removed `router.resetAll()` here.** It popped the
        // whole navigation stack, which under the relay flow meant leaving a
        // host-management screen that had just become meaningless. Connect
        // Host's empty state is NOT meaningless — it names the local brain as
        // the current answer (design A1) — and it is where the disconnect
        // REPORTS whether the host was actually told. Popping it would delete
        // the one surface that answers "did both halves happen?", which is
        // exactly the honesty bar 309-B6 exists for. The user leaves by the
        // back button, having read the outcome.
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
    /// #309 Lane C: the switch's host-plane half, run BEHIND the switch.
    /// Superseded by the next switch and by an unpair — a late landing from
    /// the outgoing profile is the same cross-profile leak `#285`/#136 guard
    /// against everywhere else on this path.
    // harness-visible
    private(set) var profileSwitchRefreshTask: Task<Void, Never>?

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
        cancelBackgroundLaunchRefresh()
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
        // #309 Lane B: the two credential-scoped stores that had to be
        // rebound here are deleted. Everything scope-sensitive that survives
        // resolves the scope per call from `profilesStore.activeProfile`, so
        // there is nothing left to re-point at a switch.

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

        // ── #309 Lane A: THE RELAY-PLANE BLOCK IS DELETED, NOT GATED. ─────
        //
        // What stood here: `if profile.hasRelay, pairingStore.isPaired,
        // accessToken != nil { bootstrap(); validateRestoredIdentity();
        // hostStore.refresh(); inboxStore.loadInbox(force:) }`, followed by a
        // second `if profile.hasRelay { refreshCommandCatalog(force:) }`.
        //
        // #310 gated it so a GATEWAY-ONLY profile switched instantly, and that
        // half of #365 has been fixed since. **The residual — the half #310
        // could not reach — was that every RELAY-BEARING profile, which is
        // every profile paired before the retirement, still ran the whole
        // doomed chain on every switch.** Nothing answers at the other end on
        // either host, so each step is a full URLSession timeout and the
        // bootstrap's own #15 ladder stacks two more behind it, all while the
        // switch holds the UI. Deleting it makes the switch relay-silent for
        // EVERY profile, which is what 309-A4 pins.
        //
        // ── #309 Lane C: THE THREE RE-HOMED STEPS ARE BACK — AND OFF THE
        //    SWITCH'S CRITICAL PATH, WHICH IS THE WHOLE POINT. ─────────────
        //
        // Lane A's note above ended "Lane C's to re-home onto gateway
        // `/health` and `/v1/skills`; until they land, the switch leaves both
        // honestly empty." They have landed (rows 7 and 16), and the inbox
        // reload comes back with them now that its gate asks the right
        // capability (bar C6).
        //
        // **They do NOT go back where they were.** #365's lesson is
        // structural, not about which host answers: a switch that AWAITS a
        // network probe stalls the UI for as long as the probe hangs, and a
        // black-holed GATEWAY hangs exactly like a black-holed relay did
        // (firewall DROP, no TCP refusal, the full timeout). Owen's phone is
        // off-tailnet routinely — that is the case #412 was filed from. So the
        // refresh lands BEHIND the switch, superseded by the next one, in the
        // same shape #136 gives the launch path and #247 B2 gives the switch
        // verdict beside it. `aProfileSwitchCompletesWithEveryHostSurfaceBlack-
        // Holed` is what holds this line: awaiting any of these reds it.
        if chatStore.activeModelName == nil {
            await seedActiveModelFromGateway()
        }
        startProfileSwitchRefresh()
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

    /// #309 Lane C: the profile switch's host-plane half — host presence (row
    /// 7), the plugin inbox, and the command catalog (row 16), all on the
    /// gateway now.
    ///
    /// Detached deliberately. Every step here is a network read against a host
    /// that may be black-holed, and the switch handler must return whether or
    /// not any of them answers; the alternative is #365, which is what these
    /// three calls caused in their previous form. Cancellation is checked
    /// between steps rather than only at entry, so a switch that lands
    /// mid-flight cannot write the outgoing profile's host state over the
    /// incoming one's.
    private func startProfileSwitchRefresh() {
        profileSwitchRefreshTask?.cancel()
        profileSwitchRefreshTask = Task { @MainActor [weak self] in
            guard let self, self.hasGatewayCredentials else { return }
            await self.hostStore.refresh()
            if Task.isCancelled { return }
            self.lastKnownHostOnline = self.hostStore.isHostOnline
            await self.inboxStore.loadInbox(force: true)
            if Task.isCancelled { return }
            await self.refreshCommandCatalog(force: true)
            if Task.isCancelled { return }
            self.updateWidgetData()
        }
    }

    // #309 Lane A: `refreshDormantProfileTokensIfNeeded()` lived here — M-9's
    // opportunistic `auth/refresh` sweep over dormant relay-bearing profiles,
    // one serial round trip each on every foreground. It is DELETED with the
    // bootstrap chain it called through (`ProfileRelaySessionFactory
    // .refreshAccessToken` was that chain's fourth construction site), along
    // with `DormantTokenRefreshPolicy` and the `dormantRefreshAttempts`
    // no-thrash ledger. There is no 30-day refresh TTL left to strand.

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
