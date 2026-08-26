import SwiftUI
import Testing
@testable import Talaria

/// **#393 call 1 — the generator behind the curated `accentText` values.**
///
/// Not an assertion. This is the tool that PRODUCED the palette literals, kept
/// in the tree for the same reason `printTheSemanticForegroundCensus` is: a
/// table of hand-picked hexes with no way to re-derive it is a claim, not a
/// measurement. Re-run it after any palette change and it prints the current
/// answer.
///
/// **Method.** For each failing cell it blends the decorative hue toward black
/// (on a light background) or white (on a dark one) by binary search on the
/// blend factor, stopping at the FIRST value that clears 4.5:1. Minimal
/// movement, so the result stays recognisably the theme's accent rather than
/// becoming grey — which is the whole reason for a curated variant instead of
/// a global darkening.
///
/// **Why blend rather than HSB-adjust:** blending toward the background's own
/// extreme is monotonic in luminance, so the binary search is guaranteed to
/// converge. An HSB brightness sweep is not — saturation interacts, and on
/// several of these hues the ratio is not monotonic in B.
struct AccentTextVariantGeneratorTests {

    private static func hex(_ rgb: (r: Double, g: Double, b: Double)) -> String {
        let clamp = { (v: Double) in Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "0x%02X%02X%02X", clamp(rgb.r), clamp(rgb.g), clamp(rgb.b))
    }

    /// Snap to the 8-bit grid a hex literal will actually occupy.
    private static func roundTo8Bit(_ rgb: (r: Double, g: Double, b: Double)) -> (r: Double, g: Double, b: Double) {
        let snap = { (v: Double) in (min(max(v, 0), 1) * 255).rounded() / 255.0 }
        return (snap(rgb.r), snap(rgb.g), snap(rgb.b))
    }

    private static func blend(
        _ color: Color, toward target: Double, factor: Double, over background: Color
    ) -> (r: Double, g: Double, b: Double) {
        let c = ThemeContrastMath.composite(color, over: background)
        return (c.r + (target - c.r) * factor,
                c.g + (target - c.g) * factor,
                c.b + (target - c.b) * factor)
    }

    /// The smallest blend that clears `floor`, or nil if even full blend cannot
    /// (which would mean the background itself is the problem — worth knowing).
    private static func solve(
        _ color: Color, on background: Color, floor: Double
    ) -> (hex: String, ratio: Double)? {
        let bgLuma = ThemeContrastMath.relativeLuminance(
            ThemeContrastMath.composite(background, over: background))
        // Move AWAY from the background: darker on light, lighter on dark.
        let target: Double = bgLuma > 0.5 ? 0.0 : 1.0

        // **Measure the ROUNDED value, not the float.** The search converges on
        // a continuous blend factor, but what ships is an 8-bit hex literal —
        // and rounding can drop a hairline 4.50 back under the floor. Solving
        // on the float and trusting it is exactly the "green that proves
        // nothing" shape: the generator would report 4.50 for a literal that
        // renders 4.49 and the ratchet would catch it later, out of context.
        let ratioAtRounded: (Double) -> Double = { f in
            let blended = blend(color, toward: target, factor: f, over: background)
            let snapped = Self.roundTo8Bit(blended)
            let fg = ThemeContrastMath.relativeLuminance(snapped)
            let (hi, lo) = (max(fg, bgLuma), min(fg, bgLuma))
            return (hi + 0.05) / (lo + 0.05)
        }
        guard ratioAtRounded(1.0) >= floor else { return nil }

        var lo = 0.0, hi = 1.0
        for _ in 0 ..< 40 {
            let mid = (lo + hi) / 2
            if ratioAtRounded(mid) >= floor { hi = mid } else { lo = mid }
        }
        // Step out in whole 8-bit increments until the ROUNDED colour clears —
        // the binary search can land on the boundary from the failing side.
        var factor = hi
        while factor <= 1.0, ratioAtRounded(factor) < floor { factor += 1.0 / 255.0 }
        guard factor <= 1.0 else { return nil }
        let blended = Self.roundTo8Bit(blend(color, toward: target, factor: factor, over: background))
        return (hex(blended), ratioAtRounded(factor))
    }

    /// Prints ready-to-paste Swift for every cell where the decorative accent
    /// fails the 4.5:1 TEXT floor. Always passes.
    @Test func printAccentTextVariantSuggestions() {
        var lines: [String] = ["=== #393 call 1 — accentText / accentBrightText suggestions ==="]
        var counts = (base: 0, bright: 0, impossible: 0)

        for (theme, accent) in ThemeContrastCells.reachable {
            let palette = ThemePalette(theme: theme, accent: accent)
            let bg = palette.background

            for (label, color) in [("accentText", palette.base), ("accentBrightText", palette.bright)] {
                let ratio = ThemeContrastMath.ratio(color, on: bg)
                guard ratio < 4.5 else { continue }
                guard let fix = Self.solve(color, on: bg, floor: 4.5) else {
                    lines.append("  ⛔ \(theme.rawValue)|\(accent.rawValue)|\(label): UNREACHABLE even at full blend")
                    counts.impossible += 1
                    continue
                }
                if label == "accentText" { counts.base += 1 } else { counts.bright += 1 }
                lines.append(String(
                    format: "  %-20@ %-7@ %-17@ %@ → %@   (%.2f → %.2f)",
                    theme.rawValue as NSString, accent.rawValue as NSString,
                    label as NSString,
                    Self.hex(ThemeContrastMath.composite(color, over: bg)) as NSString,
                    fix.hex as NSString, ratio, fix.ratio))
            }
        }
        lines.append("--- accentText: \(counts.base) · accentBrightText: \(counts.bright) · unreachable: \(counts.impossible) ---")
        print(lines.joined(separator: "\n"))
    }

    /// **#393 calls 3 and 4 — danger text, and the two marginal ramp steps.**
    ///
    /// Prints one line per FAILING CELL, but note the two families differ in
    /// where the value lives, and that changes how many literals a fix needs:
    ///
    /// - `danger` / `dangerBright` are **theme-level**, so a theme's three
    ///   accent slots fail together and share one fix. 15 failing cells are
    ///   about 5 distinct literals.
    /// - `secondaryForeground` / `coolForeground` come from the **ramp**, which
    ///   is theme-level too unless a variant overrides it.
    ///
    /// **Ramp steps get no text/decorative split**, unlike the accent and
    /// danger families: the census already calls the whole six-step ramp text
    /// by construction, so there is no decorative use to protect. They are
    /// raised in place — which is exactly why call 2 (`dimForeground`) is
    /// risky and stayed unelected, and why the ramp-separation check below
    /// exists for these two.
    @Test func printDangerAndRampSuggestions() {
        var lines: [String] = ["=== #393 calls 3+4 — danger / ramp suggestions ==="]
        let targets: [(String, (ThemePalette) -> Color)] = [
            ("dangerText", { $0.danger }),
            ("dangerBrightText", { $0.dangerBright }),
            ("secondaryForeground", { $0.secondaryForeground }),
            ("coolForeground", { $0.coolForeground }),
        ]
        var seen = Set<String>()
        for (theme, accent) in ThemeContrastCells.reachable {
            let palette = ThemePalette(theme: theme, accent: accent)
            let bg = palette.background
            for (label, read) in targets {
                let color = read(palette)
                let ratio = ThemeContrastMath.ratio(color, on: bg)
                guard ratio < 4.5 else { continue }
                let key = "\(theme.rawValue)|\(accent.rawValue)|\(label)"
                guard seen.insert(key).inserted else { continue }
                guard let fix = Self.solve(color, on: bg, floor: 4.5) else {
                    lines.append("  ⛔ \(key): UNREACHABLE")
                    continue
                }
                lines.append(String(
                    format: "  %-20@ %-7@ %-20@ %@ → %@   (%.2f → %.2f)",
                    theme.rawValue as NSString, accent.rawValue as NSString, label as NSString,
                    Self.hex(ThemeContrastMath.composite(color, over: bg)) as NSString,
                    fix.hex as NSString, ratio, fix.ratio))
            }
        }
        print(lines.joined(separator: "\n"))
    }

    /// **#393 call 2 + the elected danger slice — the generator behind the
    /// dimForeground raise (ruled 2026-08-23).**
    ///
    /// Per theme (the ramp is theme-level; the baseline shows dim identical
    /// across accent slots everywhere), the target is min(4.6, a step below
    /// the theme's own mutedForeground ratio) — the ramp cap bars
    /// 393-C2-A..C pre-register: a dim raised past muted has inverted the
    /// de-emphasis order, which is worse than the contrast it fixed.
    ///
    /// **`deepField` is SKIPPED on purpose:** its ramp is byte-pinned as
    /// pre-theming legacy identity (`DesignThemeTests`, "Do not retune"),
    /// and breaking that standing pin is Owen's call at the device-eyeball
    /// round, not a lane's judgment.
    @Test func printDimForegroundAndDangerSuggestions() {
        var lines: [String] = ["=== #393 call 2 — dimForeground suggestions (+ danger|autumnHarvest) ==="]
        for theme in ThemeID.allCases {
            guard theme != .deepField else { continue }
            let accent = theme.lockedAccentSlot ?? .cyan
            let p = ThemePalette(theme: theme, accent: accent)
            let bg = p.background
            let dimRatio = ThemeContrastMath.ratio(p.dimForeground, on: bg)
            guard dimRatio < 4.5 else { continue }
            let mutedRatio = ThemeContrastMath.ratio(p.mutedForeground, on: bg)
            let target = min(4.6, mutedRatio - 0.12)
            guard let fix = Self.solve(p.dimForeground, on: bg, floor: target) else {
                lines.append("  ⛔ \(theme.rawValue): UNREACHABLE even at full blend (muted \(mutedRatio))")
                continue
            }
            lines.append(String(
                format: "  %-22@ dim %.2f → %@ %.2f   (muted %.2f, target %.2f)",
                theme.rawValue as NSString, dimRatio,
                fix.hex as NSString, fix.ratio, mutedRatio, target))
        }
        // The danger slice is theme-level too: one literal covers the three
        // accent cells of danger|autumnHarvest (2.60 against the 3.0
        // decorative floor — an error pip nearly invisible).
        let autumn = ThemePalette(theme: .autumnHarvest, accent: .cyan)
        let dangerRatio = ThemeContrastMath.ratio(autumn.danger, on: autumn.background)
        if dangerRatio < 3.0 {
            if let fix = Self.solve(autumn.danger, on: autumn.background, floor: 3.2) {
                lines.append(String(format: "  autumnHarvest danger  %.2f → %@ %.2f",
                                    dangerRatio, fix.hex as NSString, fix.ratio))
            } else {
                lines.append("  ⛔ autumnHarvest danger: UNREACHABLE")
            }
        }
        print(lines.joined(separator: "\n"))
    }

    /// **#393 the mutedForeground lane (ruled 2026-08-25) — the generator
    /// behind the muted raise, and the instrument that found its cap.**
    ///
    /// Same method as its call-2 sibling one step down the ramp: per theme
    /// (the ramp is theme-level), blend `mutedForeground` toward the
    /// background's opposite extreme, 8-bit-snapped, stopping at the first
    /// value that clears the target — minimal movement, so the muted step
    /// stays its theme's hue.
    ///
    /// **The cap comes from ABOVE this time, and that is the whole finding.**
    /// Call 2's dim was capped by `mutedForeground` below it; muted is capped
    /// by `secondaryForeground` above it. On the two light themes that fail,
    /// `secondaryForeground` itself sits at 4.51–4.52 — because #393 call 4
    /// solved *the same minimal-blend problem from the same starting literal*
    /// when it raised secondary. So running the generator on the PRE-RAISE
    /// muted reproduced secondary's exact hex: **on `pulpNoir` and
    /// `stickerBombToybox`, a muted at 4.5:1 IS `secondaryForeground`**, and
    /// the ladder has no 8-bit step in between (pulpNoir jumped 4.4771 →
    /// 4.5246, toybox 4.4636 → 4.5100).
    ///
    /// **Run from the SHIPPED values it now states the same cap the other way
    /// round** — the first AA rung *overshoots* secondary (pulpNoir 4.5410 vs
    /// 4.5246) because blending from the raised literal walks a different
    /// rounding path and skips the rung that sat exactly on secondary. Either
    /// spelling says the one thing that matters: on these two themes there is
    /// no AA landing at or below `secondaryForeground` except that literal
    /// itself.
    ///
    /// Both landings are printed for every failing theme — the capped one this
    /// lane ships, and the collapse one that would clear AA by making the two
    /// steps identical — because that trade is a design call, not a
    /// measurement, and the entry hands design calls to Owen.
    ///
    /// **`deepField` is SKIPPED for the same reason call 2 skipped it:** its
    /// ramp is byte-pinned as pre-theming legacy identity (`DesignThemeTests`,
    /// `mutedForeground == 0x5D7488`), and Owen RULED on 2026-08-23 —
    /// "accept deepField at 3.16, keep the pin". It has headroom (secondary
    /// 6.28) and would reach 4.50 at `0x647A8E`; it is not moved.
    @Test func printMutedForegroundSuggestions() {
        var lines: [String] = ["=== #393 muted lane — mutedForeground suggestions ==="]
        for theme in ThemeID.allCases {
            let accent = theme.lockedAccentSlot ?? .cyan
            let p = ThemePalette(theme: theme, accent: accent)
            let bg = p.background
            let mutedRatio = ThemeContrastMath.ratio(p.mutedForeground, on: bg)
            guard mutedRatio < 4.5 else { continue }
            let secondaryRatio = ThemeContrastMath.ratio(p.secondaryForeground, on: bg)
            let dimRatio = ThemeContrastMath.ratio(p.dimForeground, on: bg)

            guard theme != .deepField else {
                lines.append(String(
                    format: "  %-22@ muted %.4f — SKIPPED (byte-pinned legacy ramp; ruled 2026-08-23)",
                    theme.rawValue as NSString, mutedRatio))
                continue
            }

            // Call 2's rule verbatim, one step up the ramp: keep a real gap
            // below the neighbour instead of landing on top of it.
            let target = min(4.6, secondaryRatio - 0.12)
            if let fix = Self.solve(p.mutedForeground, on: bg, floor: target) {
                lines.append(String(
                    format: "  %-22@ muted %.4f → %@ %.4f   (secondary %.4f, dim %.4f, target %.4f)%@",
                    theme.rawValue as NSString, mutedRatio,
                    fix.hex as NSString, fix.ratio, secondaryRatio, dimRatio, target,
                    (fix.ratio >= 4.5 ? "" : "  ← RAMP-CAPPED, stays baseline-listed") as NSString))
            } else {
                lines.append("  ⛔ \(theme.rawValue): UNREACHABLE even at full blend")
            }

            // The alternative landing, printed so the trade is legible: the
            // smallest value that clears the 4.5 TEXT floor outright.
            //
            // **The collapse is detected by HEX IDENTITY, not by comparing
            // ratios.** The two numbers are computed by different routes
            // (`solve`'s snapped luminance vs `ThemeContrastMath.ratio`) and
            // differ in the last float bit, so a `>=` on them printed nothing
            // for two cells that are literally the same colour — a check that
            // cannot see the thing it is checking for.
            let secondaryHex = Self.hex(ThemeContrastMath.composite(p.secondaryForeground, over: bg))
            if let aa = Self.solve(p.mutedForeground, on: bg, floor: 4.5) {
                // **And the verdict must be re-derivable AFTER the raise, not
                // only from the pre-raise literal.** Solving from the shipped
                // (already-raised) muted walks a slightly different rounding
                // path and skips the rung that sat exactly on secondary, so a
                // bare hex-equality check prints nothing today and the finding
                // would read as unreproducible. Both outcomes are named.
                let verdict: String
                if aa.hex == secondaryHex {
                    verdict = "  ← that IS secondaryForeground (\(secondaryHex)): AA COLLAPSES the muted step"
                } else if aa.ratio > secondaryRatio {
                    verdict = String(format: "  ← OVERSHOOTS secondaryForeground (%.4f): AA INVERTS the ramp here",
                                     secondaryRatio)
                } else {
                    verdict = ""
                }
                lines.append(String(
                    format: "  %-22@   AA landing would be %@ %.4f%@",
                    "" as NSString, aa.hex as NSString, aa.ratio, verdict as NSString))
            }
        }
        print(lines.joined(separator: "\n"))
    }

    /// **The check that makes call 4 safe, and the one call 2 would fail.**
    ///
    /// Raising a ramp step narrows its gap to the neighbours. A ramp whose
    /// steps become indistinguishable has been collapsed — six tokens
    /// rendering as four is a worse outcome than the marginal contrast it was
    /// raised to fix. Prints the ramp's step-to-step luminance gaps so the
    /// effect is visible rather than assumed.
    @Test func printRampSeparation() {
        var lines: [String] = ["=== ramp separation (luminance per step) ==="]
        for (theme, accent) in ThemeContrastCells.reachable where accent == .cyan {
            let p = ThemePalette(theme: theme, accent: accent)
            let steps: [(String, Color)] = [
                ("fgBright", p.foregroundBright), ("fg", p.foreground),
                ("secondary", p.secondaryForeground), ("cool", p.coolForeground),
                ("muted", p.mutedForeground), ("dim", p.dimForeground),
            ]
            let lums = steps.map { ThemeContrastMath.relativeLuminance(
                ThemeContrastMath.composite($0.1, over: p.background)) }
            let gaps = zip(lums, lums.dropFirst()).map { abs($0 - $1) }
            let minGap = gaps.min() ?? 0
            lines.append(String(format: "  %-22@ minGap %.4f  [%@]",
                                theme.rawValue as NSString, minGap,
                                gaps.map { String(format: "%.3f", $0) }.joined(separator: " ") as NSString))
        }
        print(lines.joined(separator: "\n"))
    }
}
