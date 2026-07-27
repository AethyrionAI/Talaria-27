import AppIntents
import Foundation
import Testing
@testable import Talaria

/// #58 — Control Center launch intents, post-`.main` (2026-07-27).
///
/// Honest scope, stated up front: **system dispatch cannot be tested here.**
/// Whether a Control Center tap reaches `perform()` at all is decided by the
/// OS (`chronod`), and the previous suite is the cautionary tale — it pinned
/// `openAppWhenRun == true` while the OS rejected that exact declaration at
/// dispatch (Code 2001, device pass 2026-07-25), staying green on a control
/// with zero live executions. Those pins are gone. The device log is the
/// only dispatch evidence: one `.notice` per tap, category `controls`, whose
/// SUBSYSTEM names the process (`org.aethyrion.talaria` = `.main` held;
/// `…talaria27.widgets` + `.error` = extension fallback).
///
/// What IS asserted here, and would fail if broken:
///  - `perform()` → router behavior. The intents are compiled into the app
///    module now (`.main` execution target), so `perform()` is an ordinary
///    method this host can call — the old "needs the system AppIntents
///    machinery" limitation applied to driving DISPATCH, not the body.
///  - each destination → `DeeplinkRouter` behavior, hermetically, against a
///    fresh router — a control whose destination stops routing fails here.
///  - the declaration set (`supportedModes`/`allowedExecutionTargets`/
///    `isDiscoverable`/kinds) as REGRESSION pins: they catch an edit that
///    reverts the launch shape, and prove nothing about the OS honoring it.
///    Both types are doc-confirmed `Equatable` OptionSets.
struct HermesControlsTests {

    // MARK: - Hermetic routing fixture

    /// Minimal client so a ChatStore can exist; none of the routes driven
    /// here touch it (chat/voice are router-only cases).
    @MainActor
    private final class InertClient: HermesClientProtocol {
        var connectionStatus: ConnectionStatus = .disconnected
        var currentConversation: Conversation?

        func connect() async {}
        func disconnect() async {}

        func send(message: String, attachments: [PendingAttachment], clientMessageID: UUID) async -> Message {
            Message(sender: .hermes, content: "ok", status: .delivered)
        }

        func sendStreaming(
            message: String,
            attachments: [PendingAttachment],
            clientMessageID: UUID
        ) -> AsyncStream<StreamingUpdate> {
            AsyncStream { $0.finish() }
        }

        func loadConversation() async -> Conversation {
            Conversation(title: Conversation.defaultTitle)
        }

        func clearConversation() async throws -> Conversation {
            Conversation(title: Conversation.defaultTitle)
        }
    }

    /// A fresh, unobserved router + store pair. Unobserved is the point:
    /// nothing presents UI off these flags, so the voice route can be driven
    /// without `VoiceOverlayScreen` auto-starting a real session in the test
    /// host (which is why the voice intent's `perform()` — hardwired to the
    /// shared container — is NOT driven directly; its destination is).
    @MainActor
    private func makeRoutingFixture() -> (router: TabRouter, chatStore: ChatStore) {
        let suiteName = "HermesControlsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let chatStore = ChatStore(
            hermesClient: InertClient(),
            persistence: UserDefaultsAppPersistenceStore(defaults: defaults)
        )
        return (TabRouter(), chatStore)
    }

    /// Dirty state a correct route must clean up — a sheet and a pushed
    /// screen. Routing over a pristine router would vacuously pass.
    @MainActor
    private func dirty(_ router: TabRouter) {
        router.presentSheet(.settings)
        router.navigate(to: .skills)
    }

    // MARK: - perform() → routing (the app-process branch, driven for real)

    /// Drives the REAL `perform()` of the chat intent — the exact code a
    /// Control Center tap executes in the app process under `.main` — against
    /// the shared container, then reads the outcome off its router. Fails if
    /// the perform body stops routing, routes the wrong destination, or the
    /// chat case stops landing on a clean Chat tab. Uses the shared container
    /// (perform is hardwired to it), so this is the one test in the suite
    /// that touches live host state; chat-landing is benign there — no
    /// overlay, no session start.
    @Test @MainActor
    func chatControlPerformRoutesTheSharedRouterToChat() async throws {
        let container = AppContainer.sharedDefault()
        dirty(container.router)

        _ = try await OpenHermesChatIntent().perform()

        #expect(container.router.selectedTab == .chat)
        #expect(container.router.activeSheet == nil)
        #expect(container.router.path().isEmpty)
    }

    // MARK: - destination → routing (hermetic, both controls)

    /// The voice intent's own destination must present the voice overlay —
    /// the same flag `StartVoiceSessionIntent` sets — and clear any sheet.
    /// Driven through `DeeplinkRouter` on a fresh router (see the fixture
    /// note for why not through `perform()`); a destination swap to
    /// anything that doesn't reach the `voice` case fails here.
    @Test @MainActor
    func voiceControlDestinationPresentsTheVoiceOverlay() {
        let fixture = makeRoutingFixture()
        dirty(fixture.router)

        DeeplinkRouter.route(
            OpenHermesVoiceIntent.destination,
            router: fixture.router,
            chatStore: fixture.chatStore
        )

        #expect(fixture.router.isVoiceOverlayPresented)
        #expect(fixture.router.activeSheet == nil)
    }

    /// Chat, hermetically — the twin of the shared-container perform test,
    /// kept so the chat route stays covered even if that test ever has to go.
    @Test @MainActor
    func chatControlDestinationLandsOnACleanChatTab() {
        let fixture = makeRoutingFixture()
        dirty(fixture.router)

        DeeplinkRouter.route(
            OpenHermesChatIntent.destination,
            router: fixture.router,
            chatStore: fixture.chatStore
        )

        #expect(fixture.router.selectedTab == .chat)
        #expect(fixture.router.activeSheet == nil)
        #expect(fixture.router.path().isEmpty)
        #expect(!fixture.router.isVoiceOverlayPresented)
    }

    /// The router owns scheme policy: a foreign URL must change nothing —
    /// not fall through to some default route.
    @Test @MainActor
    func foreignSchemeRoutesNowhere() {
        let fixture = makeRoutingFixture()
        dirty(fixture.router)

        DeeplinkRouter.route(
            URL(string: "https://example.com/chat")!,
            router: fixture.router,
            chatStore: fixture.chatStore
        )

        #expect(fixture.router.activeSheet == .some(.settings))
        #expect(fixture.router.path() == [.skills])
    }

    // MARK: - Declaration pins (regression guards, not liveness proofs)

    /// The launch shape: foreground the app, perform in the app process.
    /// Reverting either — most plausibly someone re-adding `openAppWhenRun`
    /// in place of `supportedModes` — flips these red. What these canNOT do
    /// is fail when the OS rejects the declaration at dispatch; that
    /// evidence is device-only (see the suite header).
    @Test func controlsDeclareForegroundMainAppExecution() {
        #expect(OpenHermesChatIntent.supportedModes == .foreground)
        #expect(OpenHermesVoiceIntent.supportedModes == .foreground)
        #expect(OpenHermesChatIntent.allowedExecutionTargets == .main)
        #expect(OpenHermesVoiceIntent.allowedExecutionTargets == .main)
    }

    /// Each control must hand the router ITS OWN destination — the two
    /// intents are near-identical twins, which is exactly the shape a
    /// copy-paste swap survives unnoticed.
    @Test func controlDestinationsMatchTheirRoutes() {
        #expect(OpenHermesChatIntent.destination == URL(string: "hermes://chat"))
        #expect(OpenHermesVoiceIntent.destination == URL(string: "hermes://voice"))
    }

    /// Control-only plumbing must never shadow the app target's discoverable
    /// `AskHermesIntent` / `StartVoiceSessionIntent` in Shortcuts/Spotlight.
    @Test func launchIntentsStayUndiscoverable() {
        #expect(OpenHermesChatIntent.isDiscoverable == false)
        #expect(OpenHermesVoiceIntent.isDiscoverable == false)
    }

    /// The system keys placed controls by `kind` — a rename orphans every
    /// control Owen has already placed. The ControlWidget structs are
    /// widget-target-only and can't be compiled here; they reference these
    /// constants (enforced by the widget compile), so pinning the values
    /// pins the kinds — unless someone swaps a struct back to a literal,
    /// which is what the "keep this a reference" comments there guard.
    @Test func controlKindsAreStable() {
        #expect(HermesControlKind.askHermes == "org.aethyrion.talaria27.control.askHermes")
        #expect(HermesControlKind.talkToHermes == "org.aethyrion.talaria27.control.talkToHermes")
    }
}
