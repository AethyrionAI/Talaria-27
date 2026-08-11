import SwiftUI
import UIKit

// MARK: - Brand icon for widget + Live Activity slots (#250)
//
// Lives in `Shared/` — compiled into BOTH the app and the widget extension —
// rather than in `TalariaWidgets/HermesLiveActivity.swift` where it was born.
// Moved 2026-08-11 by lane #250F for one reason: bar 250F-A needs a unit test
// over `redrawn(_:at:)`, and `TalariaTests` compiles only its own sources plus
// `@testable import Talaria`. This is the pattern project.yml's #58 note
// prescribes ("the extra source-file entries that used to compile widget
// sources straight into this bundle are gone") — shared code moves to
// `Shared/`, tests reach it through the app module. Pure code motion: the only
// semantic change is `redrawn`'s access level, tagged below.
//
// Nothing in the app target renders this view; it is compiled there so the
// test bundle can see it.
struct HermesBrandIcon: View {
    let size: CGFloat
    var fallbackSymbol: String = "brain.head.profile"
    var fallbackTint: Color = .yellow
    var backgroundTint: Color? = nil
    var cornerRadius: CGFloat? = nil

    var body: some View {
        if let uiImage = Self.loadImage().map({ Self.redrawn($0, at: size) }) {
            Image(uiImage: uiImage)
                .resizable()
                .renderingMode(.original)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius ?? size * 0.22))
                .ifLet(backgroundTint) { view, tint in
                    view.background(tint, in: RoundedRectangle(cornerRadius: cornerRadius ?? size * 0.22))
                }
        } else {
            Image(systemName: fallbackSymbol)
                .font(.system(size: size * 0.7, weight: .medium))
                .foregroundStyle(fallbackTint)
                .frame(width: size, height: size)
                .ifLet(backgroundTint) { view, tint in
                    view.background(tint, in: Circle())
                }
        }
    }

    /// #250 — **the fix for the Dynamic Island's compact leading slot, proven on
    /// device 2026-08-10.** `UIImage(data:)` has no scale to read and returns
    /// scale 1.0, so the handoff PNG arrives as an image whose **point** size
    /// equals its **pixel** count. The lock screen (44 pt) and the expanded
    /// island (28 pt) draw it; the 14 pt compact slot drew nothing at all — a
    /// grey placeholder square, identical for every icon. Redrawing at the
    /// slot's own point size makes the compact slot render the real icon.
    ///
    /// **Size correction, #250F 2026-08-11.** This comment said "a 120 px
    /// handoff PNG … a 120 point image" from `371e462` until now. The
    /// mechanism is right but the number was not: `IconPreview-Default.png`
    /// is a loose **240×240** bundle resource with no `@Nx` suffix, so
    /// `publish` writes 240 px and `load` returns **240 pt at scale 1.0** —
    /// measured, not inferred (`realPublishedHandoffAlsoLoadsAtScaleOne`).
    /// The mismatch against a 14 pt slot is twice what was written down.
    ///
    /// **What is established vs. assumed.** Established: the redraw fixes it,
    /// and the slot is NOT monochrome (a plain SwiftUI symbol renders in full
    /// colour there — probed directly). NOT isolated: this redraw changes point
    /// size, scale AND provenance in one step, so which of the three is
    /// load-bearing is unproven. Do not restate "oversized images fail to
    /// encode" as fact without narrowing it.
    // harness-visible — `private static` until #250F; widened to internal ONLY
    // so `HermesBrandIconRedrawTests` (bars 250F-A/B) can assert the point-size
    // and scale transform directly. Private in spirit, per the #216 convention:
    // nothing outside this file and that suite may call it, and this tag is
    // what a reader greps before assuming it is part of any real interface.
    static func redrawn(_ image: UIImage, at points: CGFloat) -> UIImage {
        let target = CGSize(width: points, height: points)
        return UIGraphicsImageRenderer(size: target).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    private static func loadImage() -> UIImage? {
        // #250: the app publishes the SELECTED icon's art into the app group;
        // wear it when present so the island matches the home screen.
        //
        // 2026-08-10 (bar 250T-C, device): this loader is CORRECT and was
        // wrongly suspected. The compact island's failure lived in how the
        // loaded image was handed to that slot, not in the handoff — see
        // `redrawn(_:at:)` above, which is what fixes it. Two theories were
        // tried on device and BOTH FAILED, recorded so nobody spends the
        // evening again: forcing `.withRenderingMode(.alwaysOriginal)` here
        // changed nothing, and the "system tints an opaque bitmap into a
        // square silhouette" story was falsified outright by a plain SwiftUI
        // symbol rendering in full colour in the same slot.
        if let selected = SelectedIconHandoff.load() {
            return selected
        }
        if let image = UIImage(named: "AppIcon60x60", in: Bundle.main, compatibleWith: nil) {
            return image
        }

        let containerAppURL = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        if let appBundle = Bundle(url: containerAppURL),
           let image = UIImage(named: "AppIcon60x60", in: appBundle, compatibleWith: nil) {
            return image
        }

        return nil
    }
}

extension View {
    @ViewBuilder
    func ifLet<T, Content: View>(_ value: T?, transform: (Self, T) -> Content) -> some View {
        if let value {
            transform(self, value)
        } else {
            self
        }
    }
}
