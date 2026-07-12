import SwiftUI

// MARK: - Hardware keyboard shortcuts (Lane J, J-4)
//
// The app's ⌘-shortcut surface, as data. Registration happens through
// ChatScreen's hidden shortcut bridge (the actions need its presentation
// state) and `.keyboardShortcut(.cancelAction)` on sheet/overlay close
// buttons — but the key assignments live HERE as a table, because SwiftUI
// offers no runtime introspection of registered shortcuts and the
// registration set should be assertable in tests (collision-free, stable).
//
// Shortcuts are registered unconditionally: they only ever fire from a
// hardware keyboard (iPad primary), and are inert-but-harmless on iPhone.

enum ChatKeyboardShortcuts {
    /// One ⌘-key assignment. `name` is a stable identifier for tests and
    /// the iPadOS ⌘-hold discoverability HUD (via the bridge button labels).
    struct Spec: Equatable {
        let key: KeyEquivalent
        let modifiers: EventModifiers
        let name: String
    }

    /// ⌘N — new conversation. Routes through the same clear-confirmation
    /// dialog as the drawer's New Chat button; never clears silently.
    static let newConversation = Spec(key: "n", modifiers: .command, name: "newConversation")

    /// ⌘K — full-corpus conversation search (Lane F's surface).
    static let conversationSearch = Spec(key: "k", modifiers: .command, name: "conversationSearch")

    /// ⌘, — the Settings sheet.
    static let openSettings = Spec(key: ",", modifiers: .command, name: "openSettings")

    /// ⌘1…⌘9 — jump to the nth conversation in drawer order.
    static let sessionJumpCount = 9

    static func sessionJump(_ ordinal: Int) -> Spec {
        precondition((1...sessionJumpCount).contains(ordinal), "session jump is ⌘1…⌘9")
        return Spec(
            key: KeyEquivalent(Character("\(ordinal)")),
            modifiers: .command,
            name: "sessionJump\(ordinal)"
        )
    }

    /// Every registered ⌘-shortcut — the test surface for collision checks.
    static var registrationTable: [Spec] {
        [newConversation, conversationSearch, openSettings]
            + (1...sessionJumpCount).map(sessionJump)
    }

    /// ⌘1…⌘9 target order = exactly the drawer's visible order — Lane F's
    /// `SessionsDrawerModel.grouped` (reused, not forked) with no query and
    /// the archived filter off, flattened: pinned rows first, then
    /// today/yesterday/earlier in fetch (recency) order. Archived rows are
    /// not reachable by shortcut. (@MainActor because the drawer model —
    /// and therefore its static grouping rule — is main-actor isolated.)
    @MainActor
    static func sessionJumpTargets(
        sessions: [SessionsDrawerModel.SessionSummary],
        pinnedIDs: Set<String>,
        archivedIDs: Set<String>
    ) -> [SessionsDrawerModel.SessionSummary] {
        SessionsDrawerModel.grouped(
            sessions: sessions,
            query: "",
            pinnedIDs: pinnedIDs,
            archivedIDs: archivedIDs,
            showingArchived: false
        )
        .flatMap(\.items)
    }
}

extension View {
    /// Registers Esc (the cancel action) to run `action` while this view is
    /// on screen — for sheets/overlays whose chrome has no close button to
    /// hang `.keyboardShortcut(.cancelAction)` on (J-4). The bridge button
    /// is zero-size, invisible, and untouchable; hardware Esc is its only
    /// entry point.
    func onEscapeDismiss(_ action: @escaping () -> Void) -> some View {
        background {
            Button("Close", action: action)
                .keyboardShortcut(.cancelAction)
                .frame(width: 0, height: 0)
                .opacity(0)
                .accessibilityHidden(true)
                .allowsHitTesting(false)
        }
    }
}
