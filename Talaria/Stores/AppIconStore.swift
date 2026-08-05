import UIKit

// MARK: - App icon store (issue #25)
//
// Owns the live home-screen icon selection. iOS persists the choice itself
// (`UIApplication.alternateIconName` survives relaunch), so this store only
// reflects the OS state and drives `setAlternateIconName(_:)` — nothing is added
// to UserSettings. The system shows its own "You've changed the icon" prompt on
// the first switch; we don't (and can't) suppress it.
@MainActor
@Observable
final class AppIconStore {
    /// The currently-applied icon, resolved from the OS.
    private(set) var selection: AppIconOption
    /// A switch is in flight (the grid disables interaction while true).
    private(set) var isApplying = false
    /// Last failure, surfaced in the picker; cleared on the next attempt.
    var errorMessage: String?

    /// Alternate icons are unavailable in some contexts (older/managed devices).
    var supportsAlternateIcons: Bool { application.supportsAlternateIcons }

    private let application: UIApplication
    /// #250: where the selected icon's preview is published for the widget
    /// extension (the island wears it). Injected for tests; nil (no app
    /// group) publishes nowhere and the widget falls back to bundled art.
    private let iconHandoffURL: URL?

    init(application: UIApplication = .shared,
         iconHandoffURL: URL? = SelectedIconHandoff.containerFileURL()) {
        self.application = application
        self.iconHandoffURL = iconHandoffURL
        self.selection = AppIconCatalog.option(forAlternateIconName: application.alternateIconName)
        publishSelectionForWidgets()   // heal a missing handoff on every launch
    }

    /// Re-read the OS in case the icon changed elsewhere (or a prior set failed).
    func refresh() {
        selection = AppIconCatalog.option(forAlternateIconName: application.alternateIconName)
        publishSelectionForWidgets()
    }

    /// #250: hand the current selection's art across the app-group boundary.
    private func publishSelectionForWidgets() {
        SelectedIconHandoff.publish(
            previewImageName: selection.previewImageName, to: iconHandoffURL
        )
    }

    /// Apply `option`, tolerating the no-op and unsupported cases.
    func select(_ option: AppIconOption) async {
        guard option.id != selection.id else { return }
        guard supportsAlternateIcons else {
            errorMessage = "This device can't change the app icon."
            return
        }
        // Already on this icon at the OS level → adopt without a system prompt.
        guard application.alternateIconName != option.alternateIconName else {
            selection = option
            errorMessage = nil
            return
        }

        isApplying = true
        errorMessage = nil
        defer { isApplying = false }

        do {
            try await application.setAlternateIconName(option.alternateIconName)
            selection = option
            publishSelectionForWidgets()
        } catch {
            // Reconcile to whatever the OS actually kept, then report.
            refresh()
            errorMessage = "Couldn't switch icon: \(error.localizedDescription)"
        }
    }
}
