import Foundation
import SwiftUI
import Testing
@testable import Talaria

// Lane J PR 2 — native split view. Four UI-independent suites: the root
// layout decision (the extended compact-parity guard), sidebar-visibility
// persistence, the store-level conversation selection (J-8), and the ⌘K
// sidebar-focus request seam (J-9).

// MARK: - J-8: root layout decision / compact parity

struct RootLayoutPlanTests {

    /// The extended compact-parity guard: every non-regular size class —
    /// including nil (unresolved environment) — renders today's iPhone
    /// stack. Only an actual regular width gets the split view; the plan
    /// never consults device idiom.
    @Test func everyNonRegularInputIsTheCompactStack() {
        #expect(RootLayoutPlan.plan(for: nil) == .compactStack)
        #expect(RootLayoutPlan.plan(for: .compact) == .compactStack)
    }

    @Test func regularWidthGetsTheSplitView() {
        #expect(RootLayoutPlan.plan(for: .regular) == .regularSplit)
    }
}

// MARK: - J-9: sidebar visibility persistence

struct SidebarVisibilityPersistenceTests {

    @Test func mappingRoundTripsBothStates() {
        #expect(SidebarVisibilityPersistence.visibility(fromPersisted: true) == .all)
        #expect(SidebarVisibilityPersistence.visibility(fromPersisted: false) == .detailOnly)
        #expect(SidebarVisibilityPersistence.persisted(from: .all) == true)
        #expect(SidebarVisibilityPersistence.persisted(from: .detailOnly) == false)
    }

    /// SDK reality canary: on the iOS 27 SDK, `.automatic` compares EQUAL
    /// to `.detailOnly` (the struct aliases its unresolved default — macOS
    /// aliases it to `.doubleColumn` instead), so "automatic counts as
    /// visible" is unimplementable via equality. The app never lets
    /// `.automatic` reach persistence in steady state: `onAppear` imposes
    /// the persisted value immediately. If the first expectation ever
    /// fails, the alias changed on a new SDK — revisit `persisted(from:)`
    /// and the original automatic-as-visible intent.
    @Test func automaticAliasesDetailOnlyOnThisSDK() {
        #expect(NavigationSplitViewVisibility.automatic == .detailOnly)
        #expect(SidebarVisibilityPersistence.persisted(from: .automatic) == false)
    }

    @Test func persistedStatesSurviveTheRoundTrip() {
        for visible in [true, false] {
            let visibility = SidebarVisibilityPersistence.visibility(fromPersisted: visible)
            #expect(SidebarVisibilityPersistence.persisted(from: visibility) == visible)
        }
    }
}

// MARK: - J-8: store-level conversation selection

@MainActor
struct StoreSelectionTests {

    private static func makePersistence() -> UserDefaultsAppPersistenceStore {
        let suiteName = "split-view-selection-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return UserDefaultsAppPersistenceStore(defaults: defaults)
    }

    /// Inert client — selection derivation is pure store bookkeeping and
    /// must not need a network seam.
    private final class InertClient: HermesClientProtocol {
        var connectionStatus: ConnectionStatus = .disconnected
        var currentConversation: Conversation?
        func connect() async {}
        func disconnect() async {}
        func send(message: String, attachments: [PendingAttachment], clientMessageID: UUID) async -> Message {
            Message(sender: .hermes, content: "", status: .delivered)
        }
        func sendStreaming(message: String, attachments: [PendingAttachment], clientMessageID: UUID) -> AsyncStream<StreamingUpdate> {
            AsyncStream { $0.finish() }
        }
        func loadConversation() async -> Conversation { Conversation(title: Conversation.defaultTitle) }
        func clearConversation() async throws -> Conversation { Conversation(title: Conversation.defaultTitle) }
    }

    /// The selection the sidebar and detail share is the journal's active
    /// hop handle — no journal (or no hop yet) reads as an honest nil.
    @Test func activeSessionIDTracksTheJournalHop() {
        let persistence = Self.makePersistence()
        let journal = ConversationJournalStore(persistence: persistence)
        let store = ChatStore(hermesClient: InertClient(), persistence: persistence, journal: journal)

        #expect(store.activeSessionID == nil)

        journal.beginHop(apiSessionId: "api_sidebar_42", primingUsage: nil)
        #expect(store.activeSessionID == "api_sidebar_42")
    }

    @Test func noJournalMeansNoSelection() {
        let persistence = Self.makePersistence()
        let store = ChatStore(hermesClient: InertClient(), persistence: persistence)
        #expect(store.activeSessionID == nil)
    }
}

// MARK: - J-9: ⌘K sidebar focus request seam

@MainActor
struct SearchFieldFocusRequestTests {

    /// Request/consume semantics: a request is honored exactly once (the
    /// pane may consume it on mount, arbitrarily later), and consuming
    /// without a request is a no-op — a stale flag can never steal focus.
    @Test func requestIsConsumedExactlyOnce() {
        let model = SessionsDrawerModel()
        #expect(model.consumeSearchFieldFocusRequest() == false)

        model.requestSearchFieldFocus()
        #expect(model.searchFieldFocusRequested == true)
        #expect(model.consumeSearchFieldFocusRequest() == true)
        #expect(model.searchFieldFocusRequested == false)
        #expect(model.consumeSearchFieldFocusRequest() == false)
    }

    @Test func repeatRequestsRefire() {
        let model = SessionsDrawerModel()
        model.requestSearchFieldFocus()
        _ = model.consumeSearchFieldFocusRequest()
        model.requestSearchFieldFocus()
        #expect(model.consumeSearchFieldFocusRequest() == true)
    }
}
