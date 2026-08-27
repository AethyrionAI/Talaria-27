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
        #expect(OpenHermesChatIntent.destination == URL(string: "talaria://chat"))
        #expect(OpenHermesVoiceIntent.destination == URL(string: "talaria://voice"))
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
    ///
    /// **415-N-3.** This test predates the #415 rename and is deliberately
    /// UNCHANGED by it: the visible titles moved to Talaria, the identities
    /// did not. A rename that also moved a kind would satisfy every other
    /// bar in that lane and still orphan Owen's placed controls.
    @Test func controlKindsAreStable() {
        #expect(HermesControlKind.askHermes == "org.aethyrion.talaria27.control.askHermes")
        #expect(HermesControlKind.talkToHermes == "org.aethyrion.talaria27.control.talkToHermes")
    }

    // MARK: - #415 naming (fact 2) — the controls say Talaria

    /// **415-N-1.** Owen, on the 3108 runbook pass: *"The talk and chat ones
    /// should be changed from hermes to talaria."* These are the COMPILED
    /// values the system reads for the two Control Center controls'
    /// intents, so this fails on a real regression rather than on a stale
    /// comment — `LocalizedStringResource` is `Equatable`, and a literal
    /// that got commented out instead of changed would not satisfy it.
    ///
    /// Note the name HEAD actually carried: the chat control was titled
    /// **"Ask Hermes"**, not "Chat with Hermes" — so the swap is
    /// Ask/Talk, not Chat/Talk.
    @Test func launchIntentTitlesNameTalaria() {
        #expect(OpenHermesChatIntent.title == "Ask Talaria")
        #expect(OpenHermesVoiceIntent.title == "Talk to Talaria")
    }

    /// **415-N-2, the widget half.** `AskHermesControl` /
    /// `TalkToHermesControl` are widget-target-only — this host cannot
    /// compile them, so their `Label` / `.displayName` / `.description`
    /// literals are pinned by reading the source (the #399 pattern, same
    /// shape as `RunsTransportSwitchTests`). Both directions are asserted:
    /// the new spellings present AND the old ones gone, because "contains
    /// the new string" alone passes on a half-done rename that left one of
    /// the three sites behind. Fails loudly if the file cannot be read — a
    /// check that cannot run must say so rather than pass.
    ///
    /// The absence half matches the QUOTED spelling, so it covers comments
    /// too: that file may discuss the old names in prose (and does), but not
    /// with the double quotes that make a string literal.
    @Test func theWidgetControlsSpellTalaria() throws {
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // TalariaTests/
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("TalariaWidgets/Controls/HermesControls.swift")
        let source = try #require(
            try? String(contentsOf: file, encoding: .utf8),
            "cannot read TalariaWidgets/Controls/HermesControls.swift — this check did not run"
        )

        // All six user-facing sites — Label / displayName / description for
        // each control — matched WITH their surrounding call, so a rename
        // that fixed the Label and forgot the displayName goes red, and no
        // amount of comment prose can satisfy them.
        for site in [
            "Label(\"Ask Talaria\", systemImage: \"text.bubble\")",
            ".displayName(\"Ask Talaria\")",
            ".description(\"Open the Talaria chat and ask a question.\")",
            "Label(\"Talk to Talaria\", systemImage: \"waveform\")",
            ".displayName(\"Talk to Talaria\")",
            ".description(\"Open Talaria and start a hands-free voice session.\")",
        ] {
            #expect(source.contains(site), "control site missing or renamed: \(site)")
        }

        // Old spellings gone as STRING LITERALS. Prose in the file's
        // comments may legitimately still discuss the history.
        #expect(!source.contains("\"Ask Hermes\""),
                "the chat control still spells a literal \"Ask Hermes\"")
        #expect(!source.contains("\"Talk to Hermes\""),
                "the voice control still spells a literal \"Talk to Hermes\"")
    }

    /// **415-N-4.** The failure mode a rename lane actually has is a global
    /// search-and-replace, and no amount of asserting the two NEW titles can
    /// see it. Talaria is a client for a **Hermes** host, so every string
    /// that means the host stays correct and must survive. Four sampled
    /// from three different screens; if a sweep took the word out of the
    /// app, at least one of these goes red.
    @Test func hostMeaningHermesStringsSurviveTheRename() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // TalariaTests/
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("Talaria")
        let files = try #require(
            FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
                .compactMap { $0 as? URL }
                .filter { $0.pathExtension == "swift" },
            "cannot enumerate Talaria/ — this check did not run"
        )
        #expect(!files.isEmpty, "cannot enumerate Talaria/ — this check did not run")

        let sources = files.compactMap { try? String(contentsOf: $0, encoding: .utf8) }
        #expect(!sources.isEmpty, "cannot read any Talaria/ source — this check did not run")

        // The host, named as the host: composer placeholder, two lines of
        // Connect Host copy, one chat-status line.
        for expected in [
            "\"Message Hermes\u{2026}\"",
            "\"A Hermes gateway\"",
            "\"Something's there, but it isn't Hermes\"",
            "\"Hermes host online\"",
        ] {
            #expect(sources.contains { $0.contains(expected) },
                    "a host-meaning string vanished from Talaria/: \(expected)")
        }
    }
}
