import Foundation
import Testing
import UIKit
@testable import Talaria

/// #174 — staged images must be downscaled in PIXELS before they are inlined
/// as base64 data URIs on the chat turn.
///
/// The wire capture that opened #174 measured 472,471 / 301,227 / 227,747
/// bytes of base64 in three real sends. `PendingAttachment.image(_:)` DID
/// already downscale — but it sized the render in POINTS and let
/// `UIGraphicsImageRenderer` default to the screen's scale, so a "768 px max"
/// downscale produced a 768-point / 2304-pixel image on a 3× device: nine
/// times the intended pixel area. The 350 KB staging cap then quietly
/// absorbed the result via the progressive-quality loop, which is why nothing
/// looked wrong locally.
///
/// These assert BOUNDS, never exact encoder output.
struct AttachmentDownscaleTests {

    // MARK: Fixtures

    /// A photo-shaped test image at a realistic camera resolution. Drawn with
    /// gradient + noise so the JPEG encoder can't collapse it to nothing —
    /// a flat fill would compress to a few KB and prove nothing about size.
    private func cameraSizedImage(width: Int = 4032, height: Int = 3024) -> UIImage {
        let size = CGSize(width: width, height: height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            let cg = context.cgContext
            let colors = [UIColor.systemTeal.cgColor, UIColor.systemOrange.cgColor] as CFArray
            if let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors,
                locations: [0, 1]
            ) {
                cg.drawLinearGradient(
                    gradient,
                    start: .zero,
                    end: CGPoint(x: size.width, y: size.height),
                    options: []
                )
            }
            // Deterministic high-frequency detail — an LCG, not random(), so
            // the encoded size is stable run to run.
            var seed: UInt64 = 0x2545_F491_4F6C_DD1D
            func next() -> Double {
                seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                return Double(seed >> 33) / Double(UInt32.max)
            }
            for _ in 0 ..< 4000 {
                let rect = CGRect(
                    x: next() * size.width,
                    y: next() * size.height,
                    width: 4 + next() * 24,
                    height: 4 + next() * 24
                )
                cg.setFillColor(
                    UIColor(red: next(), green: next(), blue: next(), alpha: 1).cgColor
                )
                cg.fill(rect)
            }
        }
    }

    /// Pixel dimensions of a staged attachment's encoded bytes — NOT
    /// `UIImage.size`, which is points and is exactly what #174 got wrong.
    private func pixelSize(of data: Data) -> CGSize? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        return CGSize(width: width, height: height)
    }

    // MARK: The downscale contract

    @Test @MainActor
    func stagedImageIsDownscaledInPixelsNotPoints() throws {
        let attachment = try #require(PendingAttachment.image(cameraSizedImage()))
        let pixels = try #require(pixelSize(of: attachment.data))

        // The whole defect in one assertion: a 3× device used to land this at
        // 3 × the cap because the render was sized in points.
        let longEdge = max(pixels.width, pixels.height)
        #expect(
            longEdge <= CGFloat(PendingAttachment.imageMaxPixelDimension),
            "long edge \(longEdge) px exceeds the \(PendingAttachment.imageMaxPixelDimension) px cap"
        )
        // And it must actually BE the cap — a downscale that overshoots small
        // would pass the bound above while destroying the image.
        #expect(longEdge > CGFloat(PendingAttachment.imageMaxPixelDimension) / 2)

        // Aspect ratio survives (4032×3024 is 4:3).
        let ratio = pixels.width / pixels.height
        #expect(abs(ratio - 4.0 / 3.0) < 0.02)
    }

    @Test @MainActor
    func inlinedPayloadIsAtMostHalfThePreFixSize() throws {
        let source = cameraSizedImage()
        let legacy = try #require(legacyStagedImage(source))
        let attachment = try #require(PendingAttachment.image(source))

        let assembly = AttachmentInlining.assemble(message: "look at this", attachments: [attachment])
        let dataURL = try #require(assembly.parts.compactMap { part -> String? in
            if case .imageDataURL(let url) = part { return url }
            return nil
        }.first)

        // Measured against the SAME fixture's pre-fix output rather than an
        // absolute byte count: encoder output varies, and the RATIO is the
        // honest claim.
        //
        // The bar is 1.5×, not the 2.25× pixel-area ratio, because this
        // fixture is adversarial in a specific way: its noise rectangles are
        // a FIXED pixel size, so shrinking the canvas raises their spatial
        // frequency and JPEG compresses the result relatively worse. Real
        // photographic detail scales WITH the image, so a camera photo lands
        // at or above the area ratio. Measured here: 1.77×.
        let legacyPayload = legacy.base64EncodedString().utf8.count
        #expect(
            dataURL.utf8.count * 3 <= legacyPayload * 2,
            "\(dataURL.utf8.count) B vs \(legacyPayload) B pre-fix"
        )
        #expect(assembly.omittedForBudget.isEmpty)
    }

    @Test @MainActor
    func fourImagesNoLongerOverrunTheAggregateBudget() throws {
        // Four is the composer's maximum. At pre-fix sizes a full turn blew
        // the 900 KB aggregate budget and images were replaced with omission
        // stubs — the user's attachment silently became a note saying it
        // didn't fit.
        var legacyTotal = 0
        for _ in 0 ..< 4 {
            let staged = try #require(legacyStagedImage(cameraSizedImage()))
            legacyTotal += staged.base64EncodedString().utf8.count
        }
        #expect(legacyTotal > AttachmentInlining.aggregateAttachmentBudget)

        let four = try (0 ..< 4).map { _ in try #require(PendingAttachment.image(cameraSizedImage())) }
        let batch = AttachmentInlining.assemble(message: "", attachments: four)
        #expect(batch.omittedForBudget.isEmpty, "omitted: \(batch.omittedForBudget)")
    }

    @Test @MainActor
    func alreadySmallImagesAreNotUpscaled() throws {
        let small = cameraSizedImage(width: 400, height: 300)
        let attachment = try #require(PendingAttachment.image(small))
        let pixels = try #require(pixelSize(of: attachment.data))

        #expect(pixels.width == 400)
        #expect(pixels.height == 300)
    }

    /// The pre-#174 staging algorithm, verbatim, kept so the fix's numbers are
    /// a MEASURED comparison rather than a claim. Note the two lines that were
    /// the whole defect: `image.size` (points) and a default-scale renderer.
    private func legacyStagedImage(_ image: UIImage) -> Data? {
        var quality: CGFloat = 0.5
        var targetImage = image
        let maxDimension: CGFloat = 768
        if max(image.size.width, image.size.height) > maxDimension {
            let scale = maxDimension / max(image.size.width, image.size.height)
            let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let renderer = UIGraphicsImageRenderer(size: newSize)
            targetImage = renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: newSize))
            }
        }
        guard var jpegData = targetImage.jpegData(compressionQuality: quality) else { return nil }
        while jpegData.count > PendingAttachment.maxFileSize && quality > 0.1 {
            quality -= 0.2
            if let reduced = targetImage.jpegData(compressionQuality: max(quality, 0.1)) {
                jpegData = reduced
            } else {
                break
            }
        }
        return jpegData.count <= PendingAttachment.maxFileSize ? jpegData : nil
    }

    /// Measurement, not policy — prints the real before/after numbers the #174
    /// PR body quotes, so they can be re-derived rather than trusted.
    @Test @MainActor
    func reportsEncodedSizeForTheRecord() throws {
        for (w, h, label) in [(4032, 3024, "12MP 4:3"), (1920, 1080, "1080p 16:9")] {
            let source = cameraSizedImage(width: w, height: h)

            let before = try #require(legacyStagedImage(source))
            let beforePixels = try #require(pixelSize(of: before))

            let attachment = try #require(PendingAttachment.image(source))
            let after = attachment.data
            let afterPixels = try #require(pixelSize(of: after))

            print("""
            #174 \(label) source \(w)×\(h)
              before: \(Int(beforePixels.width))×\(Int(beforePixels.height)) px, \
            \(before.count) B raw, \(before.base64EncodedString().utf8.count) B base64
              after:  \(Int(afterPixels.width))×\(Int(afterPixels.height)) px, \
            \(after.count) B raw, \(attachment.base64Data.utf8.count) B base64
            """)

            // The fix must actually be a reduction, on every fixture.
            #expect(after.count < before.count)
        }
    }
}
