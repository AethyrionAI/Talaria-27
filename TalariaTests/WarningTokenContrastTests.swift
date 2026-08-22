import Foundation
import SwiftUI
import Testing
import UIKit
@testable import Talaria

/// **#325 bar 325-D — the catalog-wide contrast sweep.**
///
/// Route (c) was ruled on 2026-08-18: add a `forgeText` token resolved per
/// theme, leaving `forge` as the decorative hue. This file is the bar that
/// governs it, and per 325-D it is **written and demonstrated RED before any
/// palette value changes** — a contrast test authored after the fix would only
/// ever pin the fix's own arithmetic.
///
/// **The measurement method is borrowed, not reinvented.** #320's lane already
/// computes WCAG 2.1 relative luminance over palette colours
/// (`RealtimeVoiceIndicatorTests`), and a second implementation here could
/// disagree with it on a boundary case and leave two "measured" numbers with
/// no way to tell which is right. Same linearisation, same ratio formula.
///
/// **Thresholds, and why there are two.** SC 1.4.3 (AA, normal text) wants
/// **4.5:1**; SC 1.4.11 (non-text UI) and large text want **3.0:1**. `forge`
/// is used both ways in this app — as warning TEXT the user is meant to read,
/// and as pips, borders and fills — which is exactly why route (c) splits the
/// token rather than retuning one hue to satisfy both.
@MainActor
struct WarningTokenContrastTests {

    // MARK: - Measurement

    /// **Shared with #393's sweep** (`ThemeContrastMath` /
    /// `ThemeContrastCells` in `SemanticForegroundContrastTests.swift`).
    ///
    /// This file originally carried its own private copy of the WCAG 2.1
    /// math, with a docstring warning that a second implementation "could
    /// disagree with it on a boundary case and leave two 'measured' numbers
    /// with no way to tell which is right". #393 then needed a third, so the
    /// math moved to one place and this suite calls it. The numbers are
    /// unchanged — every token measured here is opaque, so the shared
    /// implementation's alpha compositing is the identity for them.
    private static func contrastRatio(_ foreground: Color, _ background: Color) -> Double {
        ThemeContrastMath.ratio(foreground, on: background)
    }

    private static var reachableCells: [(theme: ThemeID, accent: AccentSlot)] {
        ThemeContrastCells.reachable
    }

    // MARK: - 325-D: the sweep

    /// **325-A's text clause.** Measured on `forgeText`, which is the token
    /// warning TEXT now resolves.
    ///
    /// **This test was demonstrated RED before `forgeText` existed** — 21 of
    /// 88 cells, failure text recorded in OPEN_ITEMS #325 — which is 325-D's
    /// requirement and the reason it is trustworthy now that it is green. A
    /// contrast test authored after the fix only ever pins the fix's own
    /// arithmetic.
    ///
    /// It reports EVERY failing cell rather than the first, because "21 cells
    /// under 4.5:1" is the shape of the problem and a test that stops at one
    /// would make a seven-theme redesign look like a one-line fix.
    @Test func warningTextClearsAATextContrastInEveryReachableCell() {
        var failures: [String] = []
        for (theme, accent) in Self.reachableCells {
            let palette = ThemePalette(theme: theme, accent: accent)
            let ratio = Self.contrastRatio(palette.forgeText, palette.background)
            if ratio < 4.5 {
                failures.append(String(format: "%@ × %@ — %.2f:1",
                                       theme.rawValue, accent.rawValue, ratio))
            }
        }
        #expect(failures.isEmpty, """
            \(failures.count) of \(Self.reachableCells.count) reachable cells render warning TEXT \
            below WCAG AA's 4.5:1 floor:
            \(failures.joined(separator: "\n"))
            """)
    }

    /// **325-A's decoration clause**, on `forge` — the hue pips, borders and
    /// fills legitimately keep.
    ///
    /// This is the clause route (c) alone could NOT satisfy: `forgeText` fixes
    /// text and does nothing for decoration, and four light themes shipped a
    /// `forge` below even 3.0:1. Owen ruled on 2026-08-21 to nudge those four
    /// rather than document an exception, which is why this is a bar and not
    /// a known-failing note.
    @Test func warningDecorationClearsNonTextContrastInEveryReachableCell() {
        var failures: [String] = []
        for (theme, accent) in Self.reachableCells {
            let palette = ThemePalette(theme: theme, accent: accent)
            let ratio = Self.contrastRatio(palette.forge, palette.background)
            if ratio < 3.0 {
                failures.append(String(format: "%@ × %@ — %.2f:1",
                                       theme.rawValue, accent.rawValue, ratio))
            }
        }
        #expect(failures.isEmpty, """
            \(failures.count) of \(Self.reachableCells.count) reachable cells render warning \
            DECORATION below WCAG's 3.0:1 non-text floor:
            \(failures.joined(separator: "\n"))
            """)
    }

    // MARK: - The measurement itself, always printed

    /// Not an assertion — a census. It always passes and always prints, so the
    /// numbers in OPEN_ITEMS #325 can be regenerated by anyone at any commit
    /// without re-deriving the method. A table quoted in a tracker entry with
    /// no way to reproduce it is a claim, not a measurement.
    @Test func printTheContrastCensus() {
        var rows: [String] = []
        for (theme, accent) in Self.reachableCells {
            let palette = ThemePalette(theme: theme, accent: accent)
            let decor = Self.contrastRatio(palette.forge, palette.background)
            let text = Self.contrastRatio(palette.forgeText, palette.background)
            rows.append(String(format: "%-22@ %-8@ decor %5.2f:1  text %5.2f:1  %@%@",
                               theme.rawValue as NSString, accent.rawValue as NSString,
                               decor, text, palette.isLight ? "light" : "dark ",
                               palette.forge == palette.forgeText ? "  (single hue)" : ""))
        }
        print("=== #325 forge:background census — \(rows.count) reachable cells ===")
        for row in rows.sorted() { print(row) }
        #expect(!rows.isEmpty)
    }
}
