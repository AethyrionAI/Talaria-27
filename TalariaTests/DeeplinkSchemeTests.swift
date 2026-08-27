import Foundation
import Testing
@testable import Talaria

/// #77 — the URL-scheme surface, after the 2026-08-26 election that made
/// `talaria://` the primary documented scheme and kept `hermes://` registered
/// and working (the ruling is quoted once, at the registration site in
/// `project.yml`'s `CFBundleURLTypes` — read it there, don't re-derive it).
///
/// Two things are pinned, and they fail for different reasons:
///
///  - **Registration** (bar 77-A) is read off the **BUILT** app plist, never
///    the source YAML — #108's built-plist pattern. A `project.yml` edit that
///    is correct but never regenerated leaves the source right and the build
///    wrong, which is exactly the state a source-reading test calls green.
///  - **Routing** (bar 77-B) is driven through `DeeplinkRouter` on a fresh,
///    unobserved router for BOTH schemes and the outcomes compared. Parity
///    alone would be satisfied by a router that ignored both, so every pair
///    also asserts the concrete outcome it must produce.
struct DeeplinkSchemeTests {

    // MARK: - Registration (bar 77-A)

    /// Both schemes must be in the built app's `CFBundleURLTypes`, with
    /// `talaria` FIRST — order is the machine-readable half of "primary".
    /// The `hermes` entry is deliberate and load-bearing: see the ruling
    /// quoted at the registration site in `project.yml`.
    @Test func builtAppRegistersTalariaFirstAndHermesSecond() throws {
        let types = try #require(Bundle.main.infoDictionary?["CFBundleURLTypes"] as? [[String: Any]],
                                 "test host app bundle declares no CFBundleURLTypes")
        let schemes = types.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        #expect(schemes == ["talaria", "hermes"])
    }

    /// Each declared type keeps its own reverse-DNS name — two entries sharing
    /// one name is the copy-paste regression this shape invites.
    @Test func eachRegisteredSchemeHasItsOwnURLName() throws {
        let types = try #require(Bundle.main.infoDictionary?["CFBundleURLTypes"] as? [[String: Any]])
        let names = types.compactMap { $0["CFBundleURLName"] as? String }
        #expect(names == ["org.aethyrion.talaria27.talaria", "org.aethyrion.talaria27.hermes"])
    }

    // MARK: - Routing parity (bar 77-B)

    /// Everything a route can move. Comparing whole snapshots rather than
    /// field-by-field is the point: a scheme that reached a DIFFERENT route
    /// would still satisfy any single-field check that happened to match.
    private struct RouteOutcome: Equatable {
        var tab: AppTab
        var sheet: String?
        var path: [Route]
        var voiceOverlay: Bool
        var composerSeed: String?
    }

    /// Minimal client so a ChatStore can exist. `session` routing reaches
    /// `ChatStore.openSession`, whose protocol default is `loadConversation()`
    /// — inert here, no network.
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

    /// Routes `scheme://suffix` against a fresh router that has been DIRTIED
    /// first (a presented sheet + a pushed screen), so a route that cleans up
    /// is distinguishable from one that does nothing.
    @MainActor
    private func outcome(scheme: String, suffix: String) async -> RouteOutcome {
        let suiteName = "DeeplinkSchemeTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let chatStore = ChatStore(
            hermesClient: InertClient(),
            persistence: UserDefaultsAppPersistenceStore(defaults: defaults)
        )
        let router = TabRouter()
        router.presentSheet(.settings)
        router.navigate(to: .skills)

        DeeplinkRouter.route(URL(string: "\(scheme)://\(suffix)")!, router: router, chatStore: chatStore)

        let snapshot = RouteOutcome(
            tab: router.selectedTab,
            sheet: router.activeSheet?.id,
            path: router.path(),
            voiceOverlay: router.isVoiceOverlayPresented,
            composerSeed: chatStore.pendingComposerSeed
        )
        // Let the `session` case's detached open settle inside this test
        // rather than leaking into the next one.
        await Task.yield()
        defaults.removePersistentDomain(forName: suiteName)
        return snapshot
    }

    /// The whole of bar 77-B in one table: every route the switch answers,
    /// driven under both schemes, compared, AND checked against the outcome
    /// it must actually produce.
    @Test @MainActor
    func everyRouteBehavesIdenticallyUnderBothSchemes() async {
        let cases: [(suffix: String, expected: RouteOutcome)] = [
            ("chat", RouteOutcome(tab: .chat, sheet: nil, path: [], voiceOverlay: false, composerSeed: nil)),
            ("session/sess-42", RouteOutcome(tab: .chat, sheet: nil, path: [], voiceOverlay: false, composerSeed: nil)),
            ("health", RouteOutcome(tab: .chat, sheet: nil, path: [.permissions], voiceOverlay: false, composerSeed: nil)),
            ("briefing", RouteOutcome(tab: .chat, sheet: nil, path: [.briefing(nil)], voiceOverlay: false, composerSeed: nil)),
            // `voice` clears the sheet but deliberately does not pop — the
            // pushed screen survives, and that asymmetry is part of parity.
            ("voice", RouteOutcome(tab: .chat, sheet: nil, path: [.skills], voiceOverlay: true, composerSeed: nil)),
            ("ask?q=hello", RouteOutcome(tab: .chat, sheet: nil, path: [], voiceOverlay: false, composerSeed: "hello"))
        ]

        for (suffix, expected) in cases {
            let talaria = await outcome(scheme: "talaria", suffix: suffix)
            let hermes = await outcome(scheme: "hermes", suffix: suffix)
            #expect(talaria == expected, "talaria://\(suffix) did not produce its documented outcome")
            #expect(hermes == talaria, "hermes://\(suffix) diverged from talaria://\(suffix)")
        }
    }

    /// The #48 security posture on the primary scheme, stated on its own so it
    /// cannot be lost in a table refactor: `ask` SEEDS and never sends. Any
    /// app or web page can fire a custom-scheme URL; auto-sending would let
    /// external content inject agent turns.
    @Test @MainActor
    func talariaAskSeedsTheComposerAndNeverSends() async {
        let result = await outcome(scheme: "talaria", suffix: "ask?q=summarize%20my%20day")
        #expect(result.composerSeed == "summarize my day")
        #expect(result.tab == .chat)
    }

    /// "Scheme-agnostic" must mean "these two", not "anything". A foreign
    /// scheme and a plausible-but-unregistered near-miss both route nowhere —
    /// the dirtied state survives untouched.
    @Test @MainActor
    func unregisteredSchemesRouteNowhere() async {
        for scheme in ["https", "talaria27", "talariax"] {
            let result = await outcome(scheme: scheme, suffix: "chat")
            #expect(result.sheet == SheetDestination.settings.id, "\(scheme):// must not route")
            #expect(result.path == [.skills], "\(scheme):// must not route")
            #expect(result.composerSeed == nil)
        }
    }
}
