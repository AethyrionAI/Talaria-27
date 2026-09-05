import Foundation
import os
import SwiftUI
import Testing
import UIKit

@testable import Talaria

/// # 429-B / 429-D — nothing is fetched until the user taps, and then once.
///
/// **Why the instrument is an injected loader and not a `URLProtocol`.**
/// Task 0 measured it: a hosted `MarkdownContentView` DOES put an
/// `AsyncImage` request on the wire at render (~29 ms after
/// `makeKeyAndVisible()`, no tap, no consent), but that request never reaches
/// a protocol registered with `URLProtocol.registerClass` — `AsyncImage`
/// loads through a private `URLSession` built from its own configuration,
/// which consults only `configuration.protocolClasses`. The same counter, in
/// the same process, in the same registration window, DID count a direct
/// `URLSession.shared` request. So a `URLProtocol`-counting bar would have
/// read `0` both before and after consent and would have passed against a
/// completely ungated render: a bar that cannot fail. `RemoteImageView`
/// therefore owns the load through `RemoteImageLoading`, and this suite counts
/// calls on the injected loader.
///
/// **The liveness arm is not decoration.** `harnessIsNotBlind` renders the
/// same content with consent ALREADY granted and requires exactly one call. If
/// that arm ever goes to zero, every zero in this file means "the harness
/// stopped rendering", not "nothing was fetched", and the suite says so rather
/// than reporting a green.
///
/// `.serialized` and `@MainActor`: each test owns a key `UIWindow` for its
/// duration, and two key windows at once is not a state either test intends.
@Suite("429-B/D remote image render", .serialized)
@MainActor
struct RemoteImageRenderTests {

    // MARK: - The counting loader (the instrument)

    /// Records every `load(_:)` and answers with a real decoded image.
    ///
    /// Genuinely `Sendable` rather than `@unchecked`: both stored properties
    /// are (`OSAllocatedUnfairLock`, and `UIImage` is `NS_SWIFT_SENDABLE`).
    final class FakeRemoteImageLoader: RemoteImageLoading {
        private let recorded = OSAllocatedUnfairLock<[URL]>(initialState: [])
        private let payload: UIImage

        init(payload: UIImage) { self.payload = payload }

        var calls: [URL] { recorded.withLock { $0 } }

        func load(_ url: URL) async throws -> UIImage {
            recorded.withLock { $0.append(url) }
            return payload
        }
    }

    /// A real 2×2 image, so a successful load produces something SwiftUI can
    /// actually lay out (a bare `UIImage()` has zero size and renders to
    /// nothing, which would make "the image replaced the placeholder"
    /// unfalsifiable).
    private static func pixel() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
    }

    // MARK: - Harness

    /// The root the hosting controller renders: `MarkdownContentView` with the
    /// two seams overridden. A named type rather than an `AnyView` so
    /// `host.rootView = …` (the streaming-delta shape) stays type-checked.
    private struct HarnessRoot: View {
        var content: String
        var isStreaming: Bool
        let consent: RemoteImageConsent
        let loader: FakeRemoteImageLoader

        var body: some View {
            MarkdownContentView(content: content, isStreaming: isStreaming)
                .environment(\.remoteImageConsent, consent)
                .environment(\.remoteImageLoader, loader)
        }
    }

    /// A window + hosting controller kept alive for the duration of a pump.
    /// Copied from Task 0 §4 — that setup is what made the render actually
    /// happen; a hosting controller not in a key window never lays out.
    private final class HostedRender {
        let window: UIWindow
        let host: UIHostingController<HarnessRoot>
        private let consent: RemoteImageConsent
        private let loader: FakeRemoteImageLoader

        init(content: String, isStreaming: Bool, consent: RemoteImageConsent, loader: FakeRemoteImageLoader) {
            self.consent = consent
            self.loader = loader
            host = UIHostingController(
                rootView: HarnessRoot(content: content, isStreaming: isStreaming, consent: consent, loader: loader)
            )
            let frame = CGRect(x: 0, y: 0, width: 390, height: 844)
            if let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState != .unattached }) {
                window = UIWindow(windowScene: scene)
                window.frame = frame
            } else {
                window = UIWindow(frame: frame)
            }
            window.rootViewController = host
            window.makeKeyAndVisible()
            host.view.frame = frame
            layout()
        }

        /// Force a fresh body evaluation (the streaming-delta shape).
        func update(content: String, isStreaming: Bool) {
            host.rootView = HarnessRoot(content: content, isStreaming: isStreaming, consent: consent, loader: loader)
            layout()
        }

        func layout() {
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            window.layoutIfNeeded()
        }

        func teardown() {
            window.rootViewController = nil
            window.isHidden = true
            window.resignKey()
        }
    }

    /// What is actually painted: how many of `view`'s pixels are the fake
    /// loader's red, and how many were drawn at all.
    ///
    /// **This replaced an accessibility-tree walk that could not work.** Two
    /// measured runs of this suite collected ZERO labels from a hosted
    /// `MarkdownContentView` — `accessibilityElements` is `nil` on every node
    /// and the dynamic `accessibilityElementCount()`/`accessibilityElement(at:)`
    /// route returns nothing either, because SwiftUI builds its accessibility
    /// tree lazily and nothing in a test host asks for it. An empty tree makes
    /// "the placeholder is not on screen" true for the wrong reason, so the
    /// instrument had to become one that cannot be vacuous.
    ///
    /// The fake loader answers with a solid red image and nothing else in the
    /// placeholder is red, so `red > 0` means the loaded image is on screen and
    /// `red == 0` means it is not. `drawn` is the snapshot's own positive
    /// control: if `drawHierarchy` ever comes back blank, `drawn == 0` says so
    /// instead of letting `red == 0` read as a verdict.
    private func paintedPixels(in view: UIView) -> (red: Int, drawn: Int) {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let snapshot = UIGraphicsImageRenderer(bounds: view.bounds, format: format).image { _ in
            view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
        }
        guard let cgImage = snapshot.cgImage else { return (0, 0) }

        let width = cgImage.width
        let height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return (0, 0) }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var red = 0
        var drawn = 0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            if pixels[index + 3] > 0 { drawn += 1 }
            if pixels[index] > 180 && pixels[index + 1] < 80 && pixels[index + 2] < 80 { red += 1 }
        }
        return (red, drawn)
    }

    private static let pixelURL = URL(string: "https://images.example/pixel.png")!

    // MARK: - 429-B

    /// **The liveness control.** Consent granted BEFORE the first render ⇒ the
    /// loader is called exactly once. This arm is what makes every zero in the
    /// rest of the file mean something.
    @Test("429-B liveness — with consent already granted, the harness DOES reach the loader")
    func harnessIsNotBlind() async throws {
        let url = Self.pixelURL
        let consent = RemoteImageConsent()
        consent.approve(url)
        let fake = FakeRemoteImageLoader(payload: Self.pixel())

        let render = HostedRender(content: "![chart](\(url.absoluteString))",
                                  isStreaming: false, consent: consent, loader: fake)
        defer { render.teardown() }

        try await Task.sleep(for: .seconds(1))

        #expect(fake.calls == [url],
                "the harness is blind — every zero elsewhere in this suite is uninterpretable")
        #expect(consent.image(for: url) != nil, "a successful load stores the image for the re-parse")
    }

    /// **429-B — zero requests before the tap; exactly the approved URL after
    /// it.**
    @Test("429-B — nothing is fetched before the tap, and exactly the tapped URL after")
    func zeroRequestsBeforeConsentThenExactlyOne() async throws {
        let url = Self.pixelURL
        let consent = RemoteImageConsent()
        let fake = FakeRemoteImageLoader(payload: Self.pixel())

        let render = HostedRender(content: "![chart](\(url.absoluteString))",
                                  isStreaming: false, consent: consent, loader: fake)
        defer { render.teardown() }

        try await Task.sleep(for: .seconds(1))
        #expect(fake.calls.isEmpty,
                "a remote image was fetched with no consent — found \(fake.calls.map(\.absoluteString))")
        #expect(consent.image(for: url) == nil)

        // The tap.
        consent.approve(url)
        render.layout()
        try await Task.sleep(for: .seconds(1))

        #expect(fake.calls == [url], "exactly the approved URL, exactly once")
    }

    /// **429-B (painted) — no remote pixel reaches the screen before the tap.**
    ///
    /// The call-counting arms prove no REQUEST is made. This proves no remote
    /// image is DISPLAYED, which is the thing the reader actually experiences,
    /// and it would still red if some future path handed `RemoteImageView`
    /// bytes it never fetched (the `loaded ⊆ approved` seam `body` is written
    /// to close). Self-controlling in both directions: `drawn > 0` says the
    /// snapshot happened, and `red > 0` after the tap says red is findable
    /// when it is there.
    @Test("429-B — no remote pixel is painted before the tap, and the image is painted after")
    func nothingRemoteIsPaintedUntilTheTap() async throws {
        let url = Self.pixelURL
        let consent = RemoteImageConsent()
        let fake = FakeRemoteImageLoader(payload: Self.pixel())

        let render = HostedRender(content: "![chart](\(url.absoluteString))",
                                  isStreaming: false, consent: consent, loader: fake)
        defer { render.teardown() }

        try await Task.sleep(for: .seconds(1))
        let before = paintedPixels(in: render.window)
        print("429-B [painted before] red=\(before.red) drawn=\(before.drawn)")
        #expect(before.drawn > 0, "the snapshot is blank — the next check would pass vacuously")
        #expect(before.red == 0, "a remote image was painted with no consent (\(before.red) px)")

        consent.approve(url)
        render.layout()
        try await Task.sleep(for: .seconds(1))

        let after = paintedPixels(in: render.window)
        print("429-B [painted after] red=\(after.red) drawn=\(after.drawn)")
        #expect(after.red > 0, "the approved image never replaced the placeholder")
    }

    // MARK: - 429-D

    /// **429-D — the streaming transcript.**
    ///
    /// Task 0 measured today's behaviour on exactly this shape: three growing
    /// deltas over ONE hosting controller produced a fresh request on every
    /// delta that contained the image, because the per-delta re-parse mints a
    /// new segment id (`MarkdownParser.swift:8`) and therefore a new SwiftUI
    /// identity. So this test holds two lines at once — nothing before the
    /// tap, and ONE load after it no matter how many more deltas arrive.
    @Test("429-D — three streaming deltas fetch nothing; after the tap the URL loads exactly once")
    func streamingDeltasLoadOnceAfterTheTap() async throws {
        let url = Self.pixelURL
        let image = "![chart](\(url.absoluteString))"
        let deltas = [
            "Here is a chart\n\n\(image)",
            "Here is a chart\n\n\(image)\n\nIt shows the trend.",
            "Here is a chart\n\n\(image)\n\nIt shows the trend, and it is rising."
        ]
        let consent = RemoteImageConsent()
        let fake = FakeRemoteImageLoader(payload: Self.pixel())

        let render = HostedRender(content: deltas[0], isStreaming: true, consent: consent, loader: fake)
        defer { render.teardown() }
        try await Task.sleep(for: .milliseconds(500))
        #expect(fake.calls.isEmpty, "delta 1 fetched \(fake.calls.map(\.absoluteString))")

        render.update(content: deltas[1], isStreaming: true)
        try await Task.sleep(for: .milliseconds(500))
        #expect(fake.calls.isEmpty, "delta 2 fetched \(fake.calls.map(\.absoluteString))")

        render.update(content: deltas[2], isStreaming: true)
        try await Task.sleep(for: .milliseconds(500))
        #expect(fake.calls.isEmpty, "delta 3 fetched \(fake.calls.map(\.absoluteString))")

        // The tap.
        consent.approve(url)
        render.layout()
        try await Task.sleep(for: .seconds(1))
        #expect(fake.calls == [url])

        // Two more deltas, each a fresh re-parse and a fresh segment identity.
        render.update(content: deltas[2] + "\n\nAnd a closing line.", isStreaming: true)
        try await Task.sleep(for: .milliseconds(600))
        render.update(content: deltas[2] + "\n\nAnd a closing line. Done.", isStreaming: false)
        try await Task.sleep(for: .milliseconds(600))

        #expect(fake.calls == [url],
                "one load per URL per launch — the re-parse refetched: \(fake.calls.map(\.absoluteString))")
        #expect(consent.isApproved(url), "the approval survived the re-parse")
        #expect(consent.image(for: url) != nil, "the decoded image survived the re-parse")

        let painted = paintedPixels(in: render.window)
        print("429-D [painted after deltas] red=\(painted.red) drawn=\(painted.drawn)")
        #expect(painted.drawn > 0, "the snapshot is blank — the next check would pass vacuously")
        #expect(painted.red > 0, "the placeholder came back on a later delta — the image is not painted")
    }

    /// **429-D (concurrency) — duplicates that render in the SAME frame still
    /// load once.**
    ///
    /// The sequential deltas above are deduped by the stored image; this arm
    /// is the one only an in-flight registry can pass. Three copies of the
    /// same URL in one pre-approved document all reach `.task` before any load
    /// finishes, so a per-view "have I got it yet?" check would fire three
    /// times.
    @Test("429-D — three copies of one URL in a single render load it once, not three times")
    func concurrentDuplicatesLoadOnce() async throws {
        let url = Self.pixelURL
        let image = "![chart](\(url.absoluteString))"
        let consent = RemoteImageConsent()
        consent.approve(url)
        let fake = FakeRemoteImageLoader(payload: Self.pixel())

        let render = HostedRender(content: "\(image)\n\nprose\n\n\(image)\n\nmore\n\n\(image)",
                                  isStreaming: false, consent: consent, loader: fake)
        defer { render.teardown() }

        try await Task.sleep(for: .seconds(1))

        #expect(fake.calls == [url],
                "concurrent duplicates were not deduped: \(fake.calls.map(\.absoluteString))")
    }
}
