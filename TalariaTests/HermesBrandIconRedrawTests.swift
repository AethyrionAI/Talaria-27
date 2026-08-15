import Foundation
import Testing
import UIKit
@testable import Talaria

/// The three point sizes the icon is actually asked for in production:
/// 14 pt is the Dynamic Island compact leading slot (and the status widget's
/// small row) — the slot that failed; 28 pt is the expanded island's leading
/// region; 44 pt is the lock-screen layout. 28 and 44 are the CONTROL — they
/// rendered correctly before the fix, which is what made the diagnosis
/// possible, so the fix is not scored on 14 alone (bar 250F-B).
///
/// File scope, not a static member of the suite below: the suite is
/// `@MainActor`, and a `@Test(arguments:)` attribute is evaluated outside
/// that actor ("Main actor-isolated static property … cannot be accessed
/// from outside of the actor" — a compile error, not a test failure).
private let productionSlotSizes: [CGFloat] = [14, 28, 44]

/// #250F — the COMPACT-SLOT FIX. Bars 250F-A (RED witnessed, then GREEN) and
/// 250F-B (the sizes that already worked still work).
///
/// **The defect this pins.** `SelectedIconHandoff.load` ends in
/// `UIImage(data:)`, which has no scale information to read and so returns a
/// **scale-1.0** image: the handoff PNG arrives with its **point** size equal
/// to its **pixel** count. The lock screen (44 pt) and the expanded island
/// (28 pt) drew it anyway; the Dynamic Island's 14 pt compact leading slot
/// drew a grey placeholder square instead — device-observed 2026-08-10, bar
/// 250T-C. `HermesBrandIcon.redrawn(_:at:)` re-renders at the slot's own
/// point size, and the compact slot then shows the real icon.
///
/// **What these tests do NOT establish.** The redraw changes point size,
/// scale AND provenance in one step. These assertions prove the transform
/// happens; they do not isolate which of the three the compact slot was
/// actually rejecting. Do not read a green here as "oversized images fail to
/// encode" — that is still unproven (honesty clause, carried from the fix
/// commit and from the bars).
///
/// **How the RED was witnessed** — recorded because a test written after a
/// fix and never seen red is worth very little, and this project has been
/// burned by exactly that. `redrawn` was temporarily stubbed to
/// `return image` (the pre-fix behaviour: the raw handoff image went to the
/// slot untouched) and this suite was run on 2026-08-11. Result:
/// **"Test run with 4 tests in 1 suite failed after 0.330 seconds with 15
/// issues"** — `redrawnAdoptsTheSlotPointSizeAndTheScreenScale` failed at
/// ALL THREE sizes (14, 28, 44), five assertions each. The two load-shape
/// tests passed, which is the point: they describe the input, and the input
/// was never what broke. The stub was then reverted and the suite re-run
/// green. Full evidence in OPEN_ITEMS #250 under bar 250F-A.
@MainActor
struct HermesBrandIconRedrawTests {

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("icon-redraw-\(UUID().uuidString).png")
    }

    /// Writes a `pixels`×`pixels` PNG to disk — the shape a published handoff
    /// file has on disk, independent of how it is later read.
    @discardableResult
    private func writePNG(pixels: CGFloat, to url: URL) throws -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: CGSize(width: pixels, height: pixels), format: format)
            .image { context in
                UIColor.systemTeal.setFill()
                context.fill(CGRect(x: 0, y: 0, width: pixels, height: pixels))
                UIColor.systemPink.setFill()
                context.fill(CGRect(x: 0, y: 0, width: pixels / 2, height: pixels / 2))
            }
        try #require(image.pngData()).write(to: url, options: .atomic)
        return image
    }

    // MARK: - 250F-A

    /// **The RED baseline, asserted rather than remembered.** A 120 px PNG
    /// loaded exactly the way the handoff file is loaded arrives as a
    /// 120-POINT, scale-1.0 image. This is the input the 14 pt compact slot
    /// was handed on device, and it is what the fix exists to transform. If
    /// this test ever goes red, the premise of the whole item changed.
    @Test func handoffLoadYieldsA120PointScaleOneImage() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try writePNG(pixels: 120, to: url)

        let loaded = try #require(SelectedIconHandoff.load(from: url))

        #expect(loaded.scale == 1.0)
        #expect(loaded.size == CGSize(width: 120, height: 120))
        // Point size and PIXEL count are the same number — that is the whole
        // defect, stated as an equality rather than as a story.
        #expect(loaded.size.width * loaded.scale == 120)
    }

    /// The same shape, but read off the REAL published artifact instead of a
    /// synthetic one, so the claim is not hypothetical.
    ///
    /// **This is also where #250F corrected the record.** Every prior write-up
    /// of this defect — the fix commit's comment, the tracker header, the
    /// device-pass row — called it "the 120 px handoff PNG". Measured here, it
    /// is **240**: `IconPreview-Default.png` is a loose 240×240 bundle
    /// resource with no `@Nx` suffix, so `UIImage(named:)` reads it at scale
    /// 1.0, `pngData()` writes 240 px, and `UIImage(data:)` hands back 240 pt.
    /// The MECHANISM was always right; the number was off by 2×, which makes
    /// the mismatch against a 14 pt slot worse than anyone wrote down. Pinned
    /// exactly so a future art change surfaces here instead of silently
    /// rotting the prose.
    @Test func realPublishedHandoffAlsoLoadsAtScaleOne() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(SelectedIconHandoff.publish(previewImageName: "IconPreview-Default", to: url))

        let loaded = try #require(SelectedIconHandoff.load(from: url))

        #expect(loaded.scale == 1.0)
        // The defect shape, stated as an exact invariant rather than a number:
        // one point per pixel, because there is no scale to read off a bare
        // PNG. This holds whatever the art's dimensions become.
        let pixelWidth = CGFloat(try #require(loaded.cgImage).width)
        #expect(loaded.size.width == pixelWidth)
        // And the number as it stands today.
        #expect(loaded.size.width == 240)
        #expect(loaded.size.width > 44, "a handoff smaller than the lock-screen slot would make #250's premise moot")
    }

    // MARK: - 250F-A + 250F-B

    /// **GREEN.** After `redrawn(_:at:)` the image's point size is the SLOT's
    /// and its scale is the SCREEN's — the two facts the compact slot needed.
    /// Runs over all three production sizes, so 28 and 44 (bar 250F-B's
    /// control) are scored alongside the 14 that failed.
    @Test(arguments: productionSlotSizes)
    func redrawnAdoptsTheSlotPointSizeAndTheScreenScale(points: CGFloat) throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try writePNG(pixels: 120, to: url)
        let loaded = try #require(SelectedIconHandoff.load(from: url))

        let out = HermesBrandIcon.redrawn(loaded, at: points)

        // Point size is the slot's, not the file's.
        #expect(out.size == CGSize(width: points, height: points))
        // Scale is the screen's, not 1.0. `preferred()` is what an unconfigured
        // UIGraphicsImageRenderer resolves against the current trait
        // collection, so this asserts the renderer took the display's scale
        // rather than inheriting the source image's.
        #expect(out.scale == UIGraphicsImageRendererFormat.preferred().scale)
        #expect(out.scale == UITraitCollection.current.displayScale)
        // Backstop with teeth even if the two expressions above ever agree on
        // a degenerate value: the source was scale 1.0 and the output is not.
        #expect(out.scale > loaded.scale)
        // The output's PIXEL footprint is the slot's own — points × screen
        // scale — and is therefore decoupled from the source's pixel count.
        //
        // ⚠️ This assertion started life as `out.pixels < loaded.pixels`
        // ("the source is resampled DOWN") and the gate caught it red at
        // 44 pt on 2026-08-11: 44 × 3 = 132 px against a 120 px synthetic
        // source, so the redraw made the bitmap BIGGER. Kept as a correction
        // rather than quietly deleted, because the false version smuggled in
        // exactly the story the honesty clause forbids — the fix is not
        // "shrink an oversized image", it is "re-render at the slot's own
        // geometry", and at the lock-screen size that means MORE pixels than
        // a 120 px source carries.
        #expect(out.size.width * out.scale == points * out.scale)
        #expect(out.size.height * out.scale == points * out.scale)
    }

    /// The transform is idempotent at a given size — redrawing an
    /// already-correct image does not drift its geometry. Guards against a
    /// future caller redrawing twice.
    @Test func redrawnIsIdempotentAtTheSameSize() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try writePNG(pixels: 120, to: url)
        let loaded = try #require(SelectedIconHandoff.load(from: url))

        let once = HermesBrandIcon.redrawn(loaded, at: 14)
        let twice = HermesBrandIcon.redrawn(once, at: 14)

        #expect(once.size == twice.size)
        #expect(once.scale == twice.scale)
    }
}
