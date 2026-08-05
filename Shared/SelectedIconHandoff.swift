import UIKit

// MARK: - Selected-icon handoff (#250)
//
// The Live Activity should wear whatever home-screen icon is selected, but the
// widget extension cannot read the app bundle's loose alternate-icon PNGs by
// OS icon name. Mirror the ControlHandoff pattern: the APP publishes the
// selected icon's preview PNG into the shared app-group container; the widget
// loads that file first and falls back to the bundled primary art when the
// handoff is absent (fresh install, unsigned sim runs where the container is
// unavailable, or a pre-#250 install that never published).
enum SelectedIconHandoff {
    static let filename = "selected-icon.png"

    /// The handoff destination in the shared container; nil when the app
    /// group is unavailable — callers tolerate nil and fall back.
    static func containerFileURL(groupID: String = ControlHandoffStore.appGroupID) -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: groupID)?
            .appendingPathComponent(filename)
    }

    /// Copy the picker preview named `previewImageName` from `bundle` to
    /// `destination`. Returns false (leaving any previous file in place) when
    /// the image or destination is unavailable — the widget's fallback chain
    /// covers both directions of failure.
    @discardableResult
    static func publish(previewImageName: String, from bundle: Bundle = .main, to destination: URL?) -> Bool {
        guard let destination,
              let image = UIImage(named: previewImageName, in: bundle, compatibleWith: nil),
              let data = image.pngData() else { return false }
        do {
            try data.write(to: destination, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// The published icon, or nil when nothing readable was published.
    static func load(from url: URL? = containerFileURL()) -> UIImage? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }
}
