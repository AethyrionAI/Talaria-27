import Foundation
import SwiftUI
import Testing
import UIKit
@testable import Talaria

// MARK: - Shared measurement, so there is exactly one answer per cell

/// WCAG 2.1 contrast math, shared by every palette-contrast suite in this
/// family (#325's `WarningTokenContrastTests` and #393's sweep below).
///
/// **It is shared rather than copied on purpose.** #325's file already warned
/// that a second implementation "could disagree with it on a boundary case and
/// leave two 'measured' numbers with no way to tell which is right" — and then
/// #393 needed a third. One implementation, two callers.
///
/// **Alpha is composited, which the two earlier copies did not do.** Both
/// existing implementations read `getRed(...)` and discard the alpha channel,
/// so a token defined at `opacity: 0.4` would be measured as though it were
/// opaque — i.e. reported as *more* legible than it renders. No token this
/// suite asserts on is translucent today (the ramps and accent families are
/// all opaque hex), so this changes no existing number; it exists so that the
/// first translucent foreground anyone adds cannot flatter itself.
enum ThemeContrastMath {

    /// sRGB components plus alpha.
    private static func components(_ color: Color) -> (r: Double, g: Double, b: Double, a: Double) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b), Double(a))
    }

    /// `foreground` composited over `background` in sRGB. Identity when the
    /// foreground is opaque.
    static func composite(_ foreground: Color, over background: Color) -> (r: Double, g: Double, b: Double) {
        let f = components(foreground)
        guard f.a < 1.0 else { return (f.r, f.g, f.b) }
        let b = components(background)
        return (f.r * f.a + b.r * (1 - f.a),
                f.g * f.a + b.g * (1 - f.a),
                f.b * f.a + b.b * (1 - f.a))
    }

    /// Alpha fraction of a colour, for census reporting.
    static func alpha(_ color: Color) -> Double { components(color).a }

    private static func channel(_ value: Double) -> Double {
        value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }

    /// Widened from `private` for #393 call 1's generator, which needs the
    /// background's luminance to decide which way to blend. Same file-scoped
    /// spirit; nothing outside the test target can reach it.
    static func relativeLuminance(_ rgb: (r: Double, g: Double, b: Double)) -> Double {
        0.2126 * channel(rgb.r) + 0.7152 * channel(rgb.g) + 0.0722 * channel(rgb.b)
    }

    /// WCAG 2.1 contrast ratio of `foreground` against `background`,
    /// compositing the foreground over the background first if it is
    /// translucent.
    static func ratio(_ foreground: Color, on background: Color) -> Double {
        let f = relativeLuminance(composite(foreground, over: background))
        let b = relativeLuminance(composite(background, over: background))
        return (max(f, b) + 0.05) / (min(f, b) + 0.05)
    }
}

/// Every `(theme, accent)` cell the app can actually enter.
///
/// `lockedAccentSlot` themes pin one slot, so enumerating the full cross
/// product would invent cells the app cannot reach — the #215 armed-cell error
/// in a palette costume.
enum ThemeContrastCells {
    static var reachable: [(theme: ThemeID, accent: AccentSlot)] {
        ThemeID.allCases.flatMap { theme -> [(ThemeID, AccentSlot)] in
            if let locked = theme.lockedAccentSlot { return [(theme, locked)] }
            return AccentSlot.allCases.map { (theme, $0) }
        }
    }
}

// MARK: - #393 bar 393-A: the sweep, widened past the token we already suspected

/// **#393 bar 393-A — the catalog-wide sweep over EVERY semantic foreground.**
///
/// **Why this file exists rather than another assertion in #325's.** #325
/// built a catalog-wide contrast instrument, ran it across all 88 reachable
/// cells, and pointed it at exactly one token — the one already known to be
/// broken. Owen then found `accent`/`accentBright` illegible on light themes
/// by *using the app*. The same run would have found it. **A sweep that only
/// measures what you already suspect is a confirmation, not a survey**, which
/// is #388-C's labelling rule and #215's armed-cell rule wearing a third
/// costume: the instrument has to be able to surprise you.
///
/// So the aperture here is *every* foreground token the palette resolves, and
/// the token list is derived from `ThemePalette`'s own stored properties
/// rather than from the tokens anyone suspects.
///
/// **Deliberately excluded:** `coreHighlight` / `coreShadow` (orb geometry,
/// never text), and the chrome colours `surface` / `chipSurface` / `divider` /
/// `chipBorder` / `hairline` / `strongBorder` / `scrim` — those are
/// backgrounds and separators, measured as *grounds* in the census below
/// rather than as foregrounds.
@MainActor
struct SemanticForegroundContrastTests {

    /// One measurable foreground token, named as the design system names it.
    private struct Token {
        let name: String
        let read: (ThemePalette) -> Color
        /// Whether this token is used as READ TEXT anywhere in the app, which
        /// decides its floor: SC 1.4.3 wants 4.5:1 for text, SC 1.4.11 wants
        /// 3.0:1 for non-text UI.
        let isText: Bool
    }

    private static let tokens: [Token] = [
        // The six-step foreground ramp — all of it is text by construction.
        Token(name: "foreground", read: \.foreground, isText: true),
        Token(name: "foregroundBright", read: \.foregroundBright, isText: true),
        Token(name: "secondaryForeground", read: \.secondaryForeground, isText: true),
        Token(name: "mutedForeground", read: \.mutedForeground, isText: true),
        Token(name: "dimForeground", read: \.dimForeground, isText: true),
        Token(name: "coolForeground", read: \.coolForeground, isText: true),
        // The accent family. **#393 call 1 split it, on #325's `forge`/`forgeText`
        // precedent:** `base` and `bright` are the DECORATIVE hues now (3.0
        // floor — fills, strokes, glows, the orb), and the two text variants
        // below carry the 4.5 floor for anything a user reads.
        //
        // The floors moving is not a weakening. Before the split these two were
        // measured at 4.5 *because they were used as text*, and 23 + 13 cells
        // failed. After it, text resolves a token that clears 4.5 by
        // construction, and these keep only the floor their remaining usage
        // implies.
        Token(name: "accent (base)", read: \.base, isText: false),
        Token(name: "accentBright", read: \.bright, isText: false),
        Token(name: "accentText", read: \.accentText, isText: true),
        Token(name: "accentBrightText", read: \.accentBrightText, isText: true),
        Token(name: "accentDeep", read: \.deep, isText: false),
        // The warning pair, #325's subject — kept in the sweep so the two
        // lanes read off one instrument.
        Token(name: "forge", read: \.forge, isText: false),
        Token(name: "forgeText", read: \.forgeText, isText: true),
        // Danger — **#393 call 3 split it**, same reason as the accent family:
        // `danger` has 10 decorative call sites (fills, strokes, StatusPip,
        // hudGlow) and 8 text ones, so one hue cannot carry both floors. The
        // failures arrived in THREES because `danger` is theme-level, not
        // per-slot: a theme's three accent slots share it.
        Token(name: "danger", read: \.danger, isText: false),
        Token(name: "dangerBright", read: \.dangerBright, isText: false),
        Token(name: "dangerText", read: \.dangerText, isText: true),
        Token(name: "dangerBrightText", read: \.dangerBrightText, isText: true),
    ]

    private static func floor(for token: Token) -> Double { token.isText ? 4.5 : 3.0 }

    // MARK: The census — always passes, always prints

    /// Not an assertion. The regenerable measurement behind #393's tables, so
    /// the numbers quoted in the tracker can be reproduced at any commit
    /// without re-deriving the method. A table in a tracker entry with no way
    /// to reproduce it is a claim, not a measurement.
    ///
    /// Prints a per-token summary first (that is the shape of the problem),
    /// then every failing cell.
    @Test func printTheSemanticForegroundCensus() {
        let cells = ThemeContrastCells.reachable
        var report: [String] = []
        report.append("=== #393 semantic-foreground census — \(cells.count) reachable cells × \(Self.tokens.count) tokens ===")
        report.append(String(format: "%-22@ %-6@ %-9@ %-9@ %@",
                             "token" as NSString, "floor" as NSString,
                             "fail/all" as NSString, "light" as NSString, "worst cell"))

        for token in Self.tokens {
            let limit = Self.floor(for: token)
            var failures = 0, lightFailures = 0
            var worst = (ratio: Double.infinity, label: "—")
            for (theme, accent) in cells {
                let palette = ThemePalette(theme: theme, accent: accent)
                let ratio = ThemeContrastMath.ratio(token.read(palette), on: palette.background)
                if ratio < limit {
                    failures += 1
                    if palette.isLight { lightFailures += 1 }
                }
                if ratio < worst.ratio {
                    worst = (ratio, "\(theme.rawValue) × \(accent.rawValue)")
                }
            }
            report.append(String(format: "%-22@ %-6.1f %-9@ %-9@ %@ %.2f:1",
                                 token.name as NSString, limit,
                                 "\(failures)/\(cells.count)" as NSString,
                                 "\(lightFailures) light" as NSString,
                                 worst.label as NSString, worst.ratio))
        }

        // Grounds, for the record: text does not only sit on `background`.
        report.append("--- grounds (not asserted; recorded so a surface-vs-background gap cannot hide) ---")
        for (theme, accent) in cells where ThemePalette(theme: theme, accent: accent).isLight {
            let palette = ThemePalette(theme: theme, accent: accent)
            let surfaceAlpha = ThemeContrastMath.alpha(palette.surface)
            report.append(String(format: "%-22@ %-8@ surface alpha %.2f",
                                 theme.rawValue as NSString, accent.rawValue as NSString, surfaceAlpha))
        }

        print(report.joined(separator: "\n"))
        #expect(!cells.isEmpty)
    }

    // MARK: 393-A — the RED demonstration, kept as a ratchet

    /// **The measured failure set as of 2026-08-21, before any fix.**
    ///
    /// **Tightened 2026-08-23 (call 2 + the danger slice, RED-first):** 58
    /// `dimForeground` cells and the 3 `danger|autumnHarvest` cells were
    /// removed BEFORE the palette moved, so the retune had a red bar to turn
    /// green. What remains of `dimForeground` is the ruled residue:
    /// `deepField` ×3 (ramp byte-pinned as pre-theming legacy identity —
    /// breaking that pin is Owen's call, not a lane's) and `pulpNoir` ×3 /
    /// `stickerBombToybox` ×3 (capped just under their own `mutedForeground`
    /// — 3.75 and 4.09 after the raise — because those themes' muted steps
    /// sit below 4.5 and a dim at 4.5 would invert the ramp).
    ///
    /// 170 `token|theme|accent` cells. This is the artifact 393-A required
    /// recorded, in the one place that cannot go stale: a test reads it.
    ///
    /// **Why a baseline rather than a disabled test.** The wide assertion is
    /// RED today and #393's route is Owen's call, so the honest options were a
    /// disabled test or a ratchet. A disabled test rots silently — it would
    /// still be disabled after the fix, and nothing would notice. This one
    /// stays GREEN at today's numbers, goes RED the moment a new failing cell
    /// appears (a new theme, a retuned hue, a widened aperture), and prints
    /// every cell that has since been FIXED so the baseline gets tightened
    /// rather than carried forever.
    ///
    /// **It asserts containment, not equality.** Improvements must never fail
    /// the suite — that is how a ratchet stops being a ratchet and starts
    /// being a reason not to fix things.
    private static let knownFailingCells: Set<String> = [
        "mutedForeground|deepField|cyan",  // 4.12:1
        "mutedForeground|deepField|amber",  // 4.12:1
        "mutedForeground|deepField|violet",  // 4.12:1
        "mutedForeground|pulpNoir|cyan",  // 3.84:1
        "mutedForeground|pulpNoir|amber",  // 3.84:1
        "mutedForeground|pulpNoir|violet",  // 3.84:1
        "mutedForeground|stickerBombToybox|cyan",  // 4.20:1
        "mutedForeground|stickerBombToybox|amber",  // 4.20:1
        "mutedForeground|stickerBombToybox|violet",  // 4.20:1
        "dimForeground|deepField|cyan",  // 3.16:1
        "dimForeground|deepField|amber",  // 3.16:1
        "dimForeground|deepField|violet",  // 3.16:1
        "dimForeground|pulpNoir|cyan",  // 2.36:1
        "dimForeground|pulpNoir|amber",  // 2.36:1
        "dimForeground|pulpNoir|violet",  // 2.36:1
        "dimForeground|stickerBombToybox|cyan",  // 2.46:1
        "dimForeground|stickerBombToybox|amber",  // 2.46:1
        "dimForeground|stickerBombToybox|violet",  // 2.46:1
        "accent (base)|winterFrost|cyan",  // 2.23:1
        "accent (base)|winterFrost|amber",  // 1.54:1
        "accent (base)|springSprout|cyan",  // 2.60:1
        "accent (base)|springSprout|amber",  // 1.80:1
        "accent (base)|springSprout|violet",  // 1.40:1
        "accent (base)|retroSciFi|violet",  // 1.24:1
        "accent (base)|pulpNoir|amber",  // 2.18:1
        "accent (base)|stickerBombToybox|cyan",  // 2.12:1
        "accent (base)|stickerBombToybox|amber",  // 2.09:1
        "accent (base)|comicFunnies|cyan",  // 2.53:1
        "accent (base)|comicFunnies|amber",  // 1.35:1
        "accentBright|winterFrost|cyan",  // 1.80:1
        "accentBright|winterFrost|amber",  // 1.35:1
        "accentBright|winterFrost|violet",  // 2.79:1
        "accentBright|springSprout|cyan",  // 2.05:1
        "accentBright|springSprout|amber",  // 1.54:1
        "accentBright|springSprout|violet",  // 1.28:1
        "accentBright|retroSciFi|cyan",  // 2.59:1
        "accentBright|retroSciFi|amber",  // 2.50:1
        "accentBright|retroSciFi|violet",  // 1.16:1
        "accentBright|comicFunnies|amber",  // 2.76:1
        "accentDeep|deepField|cyan",  // 2.90:1
        "accentDeep|deepField|amber",  // 2.61:1
        "accentDeep|deepField|violet",  // 1.70:1
        "accentDeep|solarForge|cyan",  // 2.64:1
        "accentDeep|solarForge|amber",  // 2.93:1
        "accentDeep|solarForge|violet",  // 1.72:1
        "accentDeep|paperTape|cyan",  // 2.00:1
        "accentDeep|paperTape|amber",  // 1.49:1
        "accentDeep|paperTape|violet",  // 1.74:1
        "accentDeep|springSprout|violet",  // 2.85:1
        "accentDeep|autumnHarvest|amber",  // 2.40:1
        "accentDeep|retroSciFi|violet",  // 2.57:1
        "accentDeep|eventHorizon|cyan",  // 2.77:1
        "accentDeep|witchsBrew|amber",  // 2.74:1
        "accentDeep|graffitiGalaxy|cyan",  // 2.81:1
        "accentDeep|graffitiGalaxy|amber",  // 2.13:1
        "accentDeep|karaokeSupernova|cyan",  // 2.98:1
        "accentDeep|luchaLibre|cyan",  // 2.44:1
        "accentDeep|pulpNoir|cyan",  // 1.88:1
        "accentDeep|pulpNoir|amber",  // 1.35:1
        "accentDeep|pulpNoir|violet",  // 2.02:1
        "accentDeep|casinoLucky7s|cyan",  // 2.39:1
        "accentDeep|casinoLucky7s|violet",  // 2.03:1
        "accentDeep|cosmicBowling|violet",  // 2.30:1
        "accentDeep|stickerBombToybox|cyan",  // 1.45:1
        "accentDeep|stickerBombToybox|amber",  // 1.43:1
        "accentDeep|stickerBombToybox|violet",  // 1.94:1
        "accentDeep|comicVillain|amber",  // 2.83:1
        "accentDeep|comicFunnies|cyan",  // 1.66:1
        "accentDeep|comicFunnies|amber",  // 1.15:1
        "accentDeep|comicFunnies|violet",  // 1.94:1
    ]

    /// **393-C2-A — the de-emphasis order is load-bearing.** `dimForeground`
    /// marks text MORE de-emphasized than `mutedForeground`, so per cell the
    /// muted step must read strictly stronger. This is the pin that makes
    /// call 2's raise safe: without it, "raise dim toward 4.5" on a theme
    /// whose muted sits below 4.62 silently inverts the ramp — six steps
    /// rendering as five with two of them swapped. Proven by mutation
    /// (one theme's two steps swapped → RED naming the theme).
    @Test func theRampsDeEmphasisOrderHolds() {
        for (theme, accent) in ThemeContrastCells.reachable {
            let p = ThemePalette(theme: theme, accent: accent)
            let muted = ThemeContrastMath.ratio(p.mutedForeground, on: p.background)
            let dim = ThemeContrastMath.ratio(p.dimForeground, on: p.background)
            #expect(muted > dim, """
                \(theme.rawValue)|\(accent.rawValue): mutedForeground \
                (\(String(format: "%.2f", muted))) must read stronger than \
                dimForeground (\(String(format: "%.2f", dim))) — the ramp's \
                de-emphasis order inverted
                """)
        }
    }

    /// **393-M-A — the WHOLE ramp order, not just its last step.**
    ///
    /// Call 2 pinned one relation (`muted > dim`, above) because that was the
    /// step it moved. This lane moves `mutedForeground`, which has a neighbour
    /// on each side, so the pin is extended to the relation the palette
    /// actually promises — **measured across all 88 reachable cells at HEAD,
    /// not asserted from the token names**:
    ///
    /// ```
    /// foregroundBright ≥ foreground > secondaryForeground ≥ mutedForeground > dimForeground
    ///                                                       coolForeground ≥ mutedForeground
    /// ```
    ///
    /// **The mixed strictness is a measurement, not a preference.** 24 of the
    /// 30 themes set `secondaryForeground`, `coolForeground` and
    /// `mutedForeground` to ONE literal — #393 call 4 recorded it in so many
    /// words ("the ramp was already collapsed there, by design") — so a strict
    /// `>` on those pairs would be RED on arrival and would forbid a shipped
    /// design decision. `foreground > secondary` and `muted > dim` are strict
    /// because every cell in the catalogue separates those two pairs.
    ///
    /// **`coolForeground` is deliberately pinned only against `muted`.** It is
    /// not a monotone step: on `deepField`, `paperTape`, `solarForge` and
    /// `terminal` the cool-tinted step reads far STRONGER than
    /// `secondaryForeground` (deepField 14.90 vs 6.28). Pinning it into the
    /// linear chain would encode an order the palette has never had — the
    /// aperture error #393 exists to name, pointed at a ramp instead of a
    /// token.
    ///
    /// Mutation-proven: swapping one theme's `secondary`/`muted` literals turns
    /// this RED naming that theme and its three cells.
    @Test func theRampOrderHoldsAcrossEveryStep() {
        /// Pairs of (stronger, weaker) with the strictness each one actually
        /// has in the catalogue.
        let relations: [(name: String,
                         stronger: (ThemePalette) -> Color, strongerName: String,
                         weaker: (ThemePalette) -> Color, weakerName: String,
                         strict: Bool)] = [
            ("bright ≥ foreground", \.foregroundBright, "foregroundBright",
             \.foreground, "foreground", false),
            ("foreground > secondary", \.foreground, "foreground",
             \.secondaryForeground, "secondaryForeground", true),
            ("secondary ≥ muted", \.secondaryForeground, "secondaryForeground",
             \.mutedForeground, "mutedForeground", false),
            ("cool ≥ muted", \.coolForeground, "coolForeground",
             \.mutedForeground, "mutedForeground", false),
            ("muted > dim", \.mutedForeground, "mutedForeground",
             \.dimForeground, "dimForeground", true),
        ]

        for (theme, accent) in ThemeContrastCells.reachable {
            let p = ThemePalette(theme: theme, accent: accent)
            for relation in relations {
                let strong = ThemeContrastMath.ratio(relation.stronger(p), on: p.background)
                let weak = ThemeContrastMath.ratio(relation.weaker(p), on: p.background)
                let holds = relation.strict ? (strong > weak) : (strong >= weak)
                #expect(holds, """
                    \(theme.rawValue)|\(accent.rawValue): the ramp order broke at \
                    \(relation.name) — \(relation.strongerName) \
                    (\(String(format: "%.2f", strong))) must read \
                    \(relation.strict ? "strictly stronger than" : "at least as strong as") \
                    \(relation.weakerName) (\(String(format: "%.2f", weak)))
                    """)
            }
        }
    }

    /// **393-A. The survey, fenced at its measured size.**
    ///
    /// Every semantic foreground against its own cell's background, at the
    /// floor its usage implies. Demonstrated RED across all 13 tokens before
    /// any palette or call-site change — nine tokens, 170 cells, recorded in
    /// OPEN_ITEMS #393 and pinned in `knownFailingCells` above.
    ///
    /// It reports every failing cell rather than the first, because "N cells
    /// under the floor" is the shape of the problem and a test that stops at
    /// one would make a catalogue-wide defect look like a one-line fix.
    @Test func noSemanticForegroundFallsBelowItsFloorBeyondTheRecordedBaseline() {
        var current: Set<String> = []
        var detail: [String: String] = [:]
        for token in Self.tokens {
            let limit = Self.floor(for: token)
            for (theme, accent) in ThemeContrastCells.reachable {
                let palette = ThemePalette(theme: theme, accent: accent)
                let ratio = ThemeContrastMath.ratio(token.read(palette), on: palette.background)
                guard ratio < limit else { continue }
                let key = "\(token.name)|\(theme.rawValue)|\(accent.rawValue)"
                current.insert(key)
                detail[key] = String(format: "%.2f:1 (floor %.1f)", ratio, limit)
            }
        }

        // Improvements are reported, never failed — see the doc comment.
        let fixed = Self.knownFailingCells.subtracting(current)
        if !fixed.isEmpty {
            print("""
                ✅ #393: \(fixed.count) cell(s) in the baseline now PASS. Tighten \
                `knownFailingCells` by removing them:
                \(fixed.sorted().map { "  " + $0 }.joined(separator: "\n"))
                """)
        }

        let regressions = current.subtracting(Self.knownFailingCells)
        #expect(regressions.isEmpty, """
            \(regressions.count) semantic-foreground cell(s) fall below their contrast \
            floor and are NOT in #393's recorded baseline — this is new:
            \(regressions.sorted().map { "  \($0) — \(detail[$0] ?? "?")" }.joined(separator: "\n"))
            """)
    }
}
