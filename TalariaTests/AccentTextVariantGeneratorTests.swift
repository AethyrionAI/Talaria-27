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
}
