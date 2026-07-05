import Foundation

// MARK: - App icon catalog (issue #25)
//
// The single, data-driven source of truth for the home-screen icon picker. The
// picker UI renders whatever this catalog lists, so adding icon #20 or #50 later
// is three mechanical steps with NO picker/UI code change:
//   1. Add the art  — Icon-<Name>@2x/@3x.png + IconPreview-<id>.png in
//      Talaria/Resources/AppIcons/ (see tools/appicons/generate_app_icons.py).
//   2. Add a `CFBundleAlternateIcons` key `<Name>` in project.yml (then xcodegen).
//   3. Add one `AppIconOption` entry below.
// This intentionally reads the same shape the theme catalog will (issue #24):
// small immutable value + a plain array, resolvable by a stable id.

/// One selectable home-screen icon.
struct AppIconOption: Identifiable, Hashable, Sendable {
    /// Stable catalog id — used for selection/UI state, not the OS icon name.
    let id: String
    /// Human label shown under the preview.
    let displayName: String
    /// Short flavor line under the name (`nil` hides it).
    let subtitle: String?
    /// The `CFBundleAlternateIcons` key passed to `setAlternateIconName(_:)`.
    /// `nil` == the primary asset-catalog `AppIcon` (the default icon).
    let alternateIconName: String?
    /// Loose-bundle preview image (loaded via `UIImage(named:)`) for the picker
    /// grid. Kept distinct from the OS icon files so the default — whose art
    /// lives in the asset catalog and isn't loadable by name — still has a
    /// thumbnail.
    let previewImageName: String

    /// The default / primary icon exposes no alternate name.
    var isPrimary: Bool { alternateIconName == nil }
}

enum AppIconCatalog {
    /// The default / primary icon (asset-catalog `AppIcon`).
    static let primary = AppIconOption(
        id: "default",
        displayName: "Talaria",
        subtitle: "Default",
        alternateIconName: nil,
        previewImageName: "IconPreview-Default"
    )

    /// Every selectable icon, primary first. Grows over time — the picker reads
    /// this list and never hardcodes individual icons.
    ///
    /// The four themed icons are programmatically-generated placeholders whose
    /// hues match the app themes (Shared/ThemePaletteCore.swift); swap the PNGs
    /// for curated art at the same paths without touching this list.
    static let all: [AppIconOption] = [
        primary,
        AppIconOption(id: "deepField", displayName: "Deep Field", subtitle: "Cyan Arc",
                      alternateIconName: "DeepField", previewImageName: "IconPreview-DeepField"),
        AppIconOption(id: "solarForge", displayName: "Solar Forge", subtitle: "Forge Amber",
                      alternateIconName: "SolarForge", previewImageName: "IconPreview-SolarForge"),
        AppIconOption(id: "terminal", displayName: "Terminal", subtitle: "Phosphor Green",
                      alternateIconName: "Terminal", previewImageName: "IconPreview-Terminal"),
        AppIconOption(id: "paperTape", displayName: "Paper Tape", subtitle: "Tracker Red",
                      alternateIconName: "PaperTape", previewImageName: "IconPreview-PaperTape"),
    ]

    /// Resolve the catalog entry for an OS `alternateIconName` (`nil` == primary).
    /// An unknown name (a removed/renamed icon still pinned at the OS level)
    /// falls back to the primary so the picker always has a valid selection.
    static func option(forAlternateIconName name: String?) -> AppIconOption {
        guard let name else { return primary }
        return all.first { $0.alternateIconName == name } ?? primary
    }

    /// Resolve by catalog id.
    static func option(id: String) -> AppIconOption? {
        all.first { $0.id == id }
    }
}
