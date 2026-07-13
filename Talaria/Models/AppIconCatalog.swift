import Foundation

// MARK: - App icon catalog (issue #25)
//
// The single, data-driven source of truth for the home-screen icon picker. The
// picker UI renders whatever this catalog lists, so adding icon #20 or #50 later
// is three mechanical steps with NO picker/UI code change:
//   1. Add the art  — Icon-<Name>@2x/@3x.png + IconPreview-<Name>.png in
//      Talaria/Resources/AppIcons/ (see tools/appicons/render_gallery_icons.py
//      for gallery SVGs, generate_app_icons.py for the flagship placeholders).
//   2. Add a `CFBundleAlternateIcons` key `<Name>` in project.yml AND the
//      hand-mirrored committed Talaria/Resources/Info.plist (then xcodegen).
//   3. Add one `AppIconOption` entry to a section below.
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

/// One titled group of the icon picker — the theme gallery taxonomy's sections
/// (mirrors `ThemeSection`). Icon groups and theme groups share names, but the
/// selections stay fully independent: picking a theme never changes the icon
/// and vice versa.
struct AppIconSection: Identifiable, Sendable {
    let title: String
    let options: [AppIconOption]
    var id: String { title }
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

    /// Default + the four flagship theme icons. The themed four are
    /// programmatically-generated placeholders whose hues match the app themes
    /// (Shared/ThemePaletteCore.swift); swap the PNGs for curated art at the
    /// same paths without touching this list.
    static let flagship: [AppIconOption] = [
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

    /// Neon Arcade Collection — curated gallery art (design/themes/
    /// app-icons.html, rendered by tools/appicons/render_gallery_icons.py).
    /// Neon Arcade itself is the collection namesake: NA#01 is the gallery's
    /// own chrome and never ported as a theme, but its icon ships. Deep Sea
    /// Diner is deliberately absent — the theme was cut, so the icon was too.
    static let neonArcadeCollection: [AppIconOption] = [
        AppIconOption(id: "neonArcade", displayName: "Neon Arcade", subtitle: "Coin-Op",
                      alternateIconName: "NeonArcade", previewImageName: "IconPreview-NeonArcade"),
        AppIconOption(id: "glitchGarden", displayName: "Glitch Garden", subtitle: "Vine Green",
                      alternateIconName: "GlitchGarden", previewImageName: "IconPreview-GlitchGarden"),
        AppIconOption(id: "witchsBrew", displayName: "Witch's Brew", subtitle: "Poison Green",
                      alternateIconName: "WitchsBrew", previewImageName: "IconPreview-WitchsBrew"),
        AppIconOption(id: "holoSushi", displayName: "Holo Sushi", subtitle: "Roe Pink",
                      alternateIconName: "HoloSushi", previewImageName: "IconPreview-HoloSushi"),
        AppIconOption(id: "lunarDiner", displayName: "Lunar Diner", subtitle: "Soda Pink",
                      alternateIconName: "LunarDiner", previewImageName: "IconPreview-LunarDiner"),
        AppIconOption(id: "cyberCactus", displayName: "Cyber Cactus", subtitle: "Sunset",
                      alternateIconName: "CyberCactus", previewImageName: "IconPreview-CyberCactus"),
        AppIconOption(id: "discoInferno", displayName: "Disco Inferno", subtitle: "Disco Gold",
                      alternateIconName: "DiscoInferno", previewImageName: "IconPreview-DiscoInferno"),
        AppIconOption(id: "cerealBox", displayName: "Cereal Box", subtitle: "Breakfast",
                      alternateIconName: "CerealBox", previewImageName: "IconPreview-CerealBox"),
        AppIconOption(id: "bubblegumMecha", displayName: "Bubblegum Mecha", subtitle: "Sugar",
                      alternateIconName: "BubblegumMecha", previewImageName: "IconPreview-BubblegumMecha"),
        AppIconOption(id: "retroSciFi", displayName: "Retro Sci-Fi", subtitle: "Retro",
                      alternateIconName: "RetroSciFi", previewImageName: "IconPreview-RetroSciFi"),
    ]

    /// Special Edition — the five SE theme icons (Lane L; SVGs in
    /// app-icons.html's Special Edition section, same render pipeline).
    static let specialEdition: [AppIconOption] = [
        AppIconOption(id: "eventHorizon", displayName: "Event Horizon", subtitle: "Singularity",
                      alternateIconName: "EventHorizon", previewImageName: "IconPreview-EventHorizon"),
        AppIconOption(id: "graffitiGalaxy", displayName: "Graffiti Galaxy", subtitle: "Spray Cap",
                      alternateIconName: "GraffitiGalaxy", previewImageName: "IconPreview-GraffitiGalaxy"),
        AppIconOption(id: "karaokeSupernova", displayName: "Karaoke Supernova", subtitle: "Mirror Ball",
                      alternateIconName: "KaraokeSupernova", previewImageName: "IconPreview-KaraokeSupernova"),
        AppIconOption(id: "midnightAquarium", displayName: "Midnight Aquarium", subtitle: "Moon Jelly",
                      alternateIconName: "MidnightAquarium", previewImageName: "IconPreview-MidnightAquarium"),
        AppIconOption(id: "moltenForge", displayName: "Molten Forge", subtitle: "Crucible",
                      alternateIconName: "MoltenForge", previewImageName: "IconPreview-MoltenForge"),
    ]

    /// Midnight Marquee — the Lane L collection. Comic Book ships BOTH
    /// variants (POW + ZAP) as separately selectable icons: icon choice is
    /// fully independent of theme choice (the Lane K coupling rule), so the
    /// adaptive theme's two halves are just two icons here.
    static let midnightMarquee: [AppIconOption] = [
        AppIconOption(id: "luchaLibre", displayName: "Lucha Libre", subtitle: "Rudo Nocturno",
                      alternateIconName: "LuchaLibre", previewImageName: "IconPreview-LuchaLibre"),
        AppIconOption(id: "kaijuAttack", displayName: "Kaiju Attack", subtitle: "Code Red Tokyo",
                      alternateIconName: "KaijuAttack", previewImageName: "IconPreview-KaijuAttack"),
        AppIconOption(id: "pulpNoir", displayName: "Pulp Noir", subtitle: "Dime Novel",
                      alternateIconName: "PulpNoir", previewImageName: "IconPreview-PulpNoir"),
        AppIconOption(id: "casinoLucky7s", displayName: "Casino Lucky 7s", subtitle: "House Felt",
                      alternateIconName: "CasinoLucky7s", previewImageName: "IconPreview-CasinoLucky7s"),
        AppIconOption(id: "cosmicBowling", displayName: "Cosmic Bowling", subtitle: "Carpet Classic",
                      alternateIconName: "CosmicBowling", previewImageName: "IconPreview-CosmicBowling"),
        AppIconOption(id: "stickerBombToybox", displayName: "Sticker-Bomb Toybox", subtitle: "Kidcore Shelf",
                      alternateIconName: "StickerBombToybox", previewImageName: "IconPreview-StickerBombToybox"),
        AppIconOption(id: "comicVillain", displayName: "Comic Book", subtitle: "Villain Variant",
                      alternateIconName: "ComicVillain", previewImageName: "IconPreview-ComicVillain"),
        AppIconOption(id: "comicFunnies", displayName: "Comic Book", subtitle: "Sunday Funnies",
                      alternateIconName: "ComicFunnies", previewImageName: "IconPreview-ComicFunnies"),
    ]

    /// Seasonal — same gallery pipeline as the Neon Arcade Collection. Unlike
    /// seasonal THEMES, seasonal icons are always selectable (no date window):
    /// the OS keeps whatever icon is set, so gating them would strand a choice.
    static let seasonal: [AppIconOption] = [
        AppIconOption(id: "autumnHarvest", displayName: "Autumn Harvest", subtitle: "Pumpkin",
                      alternateIconName: "AutumnHarvest", previewImageName: "IconPreview-AutumnHarvest"),
        AppIconOption(id: "springSprout", displayName: "Spring Sprout", subtitle: "Blossom",
                      alternateIconName: "SpringSprout", previewImageName: "IconPreview-SpringSprout"),
        AppIconOption(id: "summerSolar", displayName: "Summer Solar", subtitle: "Mango",
                      alternateIconName: "SummerSolar", previewImageName: "IconPreview-SummerSolar"),
        AppIconOption(id: "winterFrost", displayName: "Winter Frost", subtitle: "Ice",
                      alternateIconName: "WinterFrost", previewImageName: "IconPreview-WinterFrost"),
    ]

    /// The picker's titled sections, in display order — mirrors the theme
    /// gallery taxonomy (`ThemeCatalog.sections`).
    static let sections: [AppIconSection] = [
        AppIconSection(title: "Flagship", options: flagship),
        AppIconSection(title: "Neon Arcade Collection", options: neonArcadeCollection),
        AppIconSection(title: "Special Edition", options: specialEdition),
        AppIconSection(title: "Midnight Marquee", options: midnightMarquee),
        AppIconSection(title: "Seasonal", options: seasonal),
    ]

    /// Every selectable icon, primary first — the sections flattened in display
    /// order. Grows over time; the picker and resolution helpers read this (or
    /// `sections`) and never hardcode individual icons.
    static let all: [AppIconOption] = sections.flatMap(\.options)

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
