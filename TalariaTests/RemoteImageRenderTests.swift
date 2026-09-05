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
        /// Widened from `FakeRemoteImageLoader` by #437-E, which drives the
        /// SHIPPING `URLSessionRemoteImageLoader` through this same harness.
        let loader: any RemoteImageLoading

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
        private let loader: any RemoteImageLoading

        init(content: String, isStreaming: Bool, consent: RemoteImageConsent, loader: any RemoteImageLoading) {
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

    /// Every non-empty `accessibilityLabel` in a view hierarchy.
    ///
    /// **Not the walk #429 tried and abandoned.** That one read
    /// `accessibilityElements` / `accessibilityElementCount()`, which SwiftUI
    /// builds lazily and never built in a test host, so it collected zero
    /// labels and made "the placeholder is gone" true for the wrong reason.
    /// This reads the `accessibilityLabel` PROPERTY off each backing `UIView`,
    /// which SwiftUI sets eagerly — and every arm that uses it asserts the
    /// placeholder's own label first, so a blind walk reds instead of passing.
    private func accessibilityLabels(in view: UIView) -> [String] {
        var out: [String] = []
        if let label = view.accessibilityLabel, !label.isEmpty { out.append(label) }
        for subview in view.subviews { out.append(contentsOf: accessibilityLabels(in: subview)) }
        return out
    }

    private static let pixelURL = URL(string: "https://images.example/pixel.png")!

    /// A fresh URL per test, so nothing can be served from `URLSession.shared`'s
    /// cache and no two arms share a consent key by accident.
    private static func uniqueURL(_ tag: String) -> URL {
        URL(string: "https://images.example/\(tag)-\(UUID().uuidString).png")!
    }

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

    // MARK: - 437-A

    /// A loader that records every call and always fails.
    ///
    /// `RemoteImageLoadError.undecodable` rather than a transport error
    /// because the distinction does not reach the row — what the reader sees
    /// either way is "failed", and what 437-A is about is what happens next.
    final class FailingRemoteImageLoader: RemoteImageLoading {
        private let recorded = OSAllocatedUnfairLock<[URL]>(initialState: [])
        var calls: [URL] { recorded.withLock { $0 } }

        func load(_ url: URL) async throws -> UIImage {
            recorded.withLock { $0.append(url) }
            throw RemoteImageLoadError.undecodable
        }
    }

    /// **437-A — a failed load leaves a row whose tap fetches exactly once
    /// more.**
    ///
    /// The registry keeps finished tasks on purpose, so "one load per URL per
    /// launch" was true of failures too: a transient network blip left a dead
    /// image for the rest of the launch with no way back. The pre-#429
    /// `AsyncImage` self-healed on the next re-parse, so this was a real
    /// regression, and the fix is a tap — not an automatic retry, which would
    /// re-fetch a beacon URL the reader approved once.
    ///
    /// The first `#expect` is the arm's own liveness control: if the initial
    /// load never happened, "exactly one MORE call" would be measuring
    /// nothing.
    ///
    /// The tap itself is driven as `consent.retry(url)` — the Button's own
    /// action, which `RemoteImageSitePinsTests.theFailureRowIsAButtonThatRetries`
    /// pins positionally, the same split #429's I-3 fix established for the
    /// placeholder.
    @Test("437-A — a failed load leaves a retryable row; one tap costs exactly one new load")
    func theFailureRowRetriesExactlyOnce() async throws {
        let url = Self.uniqueURL("retry")
        let consent = RemoteImageConsent()
        consent.approve(url)
        let failing = FailingRemoteImageLoader()

        let render = HostedRender(content: "![chart](\(url.absoluteString))",
                                  isStreaming: false, consent: consent, loader: failing)
        defer { render.teardown() }

        try await Task.sleep(for: .seconds(1))
        #expect(failing.calls == [url],
                "the first load never happened — the retry count below would be vacuous")
        #expect(consent.hasFailed(url),
                "the failure was not recorded, so no failure row is on screen to tap")
        #expect(consent.image(for: url) == nil)

        // The tap.
        consent.retry(url)
        #expect(!consent.hasFailed(url), "the tap must clear the failure so the spinner comes back")
        render.layout()
        try await Task.sleep(for: .seconds(1))

        #expect(failing.calls == [url, url],
                "one tap must produce exactly one new load — the loader saw \(failing.calls.count)")
        #expect(consent.hasFailed(url),
                "the retry failed too, so the row must be back rather than a permanent spinner")
    }

    // MARK: - 437-D (counting half)

    /// **437-D — saving an already-loaded image costs no new load.**
    ///
    /// The source half (`RemoteImageSitePinsTests.savingToPhotosDoesNotRefetch`)
    /// pins that `downloadToPhotos` asks the consent store; this counts what
    /// that ask costs. `downloadToPhotos` itself cannot be called from a test
    /// — it is `private` on a `View` and its first act is a Photos
    /// authorization prompt — so this drives the exact call it makes.
    @Test("437-D — saving an already-loaded image makes no new loader call")
    func savingAnAlreadyLoadedImageMakesNoNewLoad() async throws {
        let url = Self.uniqueURL("save")
        let consent = RemoteImageConsent()
        consent.approve(url)
        let fake = FakeRemoteImageLoader(payload: Self.pixel())

        let render = HostedRender(content: "![chart](\(url.absoluteString))",
                                  isStreaming: false, consent: consent, loader: fake)
        defer { render.teardown() }

        try await Task.sleep(for: .seconds(1))
        #expect(fake.calls == [url], "the image never loaded — the count below would be vacuous")

        // What the Save button asks for.
        let saved = await consent.loadedImage(for: url, using: fake)
        #expect(saved != nil, "save could not find bytes the reader is looking at")
        #expect(fake.calls == [url],
                "saving went back to the host: \(fake.calls.map(\.absoluteString))")
    }

    // MARK: - 437-C (rendered half)

    /// **437-C (rendered) — the loaded image's label, if this host can see a
    /// label at all.**
    ///
    /// **Measured, and it is the third blind route.** #429 tried
    /// `accessibilityElements` and the dynamic
    /// `accessibilityElementCount()`/`accessibilityElement(at:)` pair and got
    /// nothing from a hosted `MarkdownContentView`, and replaced its rendered
    /// arm with a pixel probe on that account. This lane added a third route —
    /// reading the `accessibilityLabel` PROPERTY off every backing `UIView` —
    /// and measured it empty as well: on the unmodified tree the walk returned
    /// `[]` even for the PLACEHOLDER's label, which has been in the source
    /// since #429. SwiftUI builds its accessibility tree lazily and nothing in
    /// a test host asks for it.
    ///
    /// So this arm asserts the label **whenever any route can see one** and
    /// falls back to the claim this harness provably can make when none can,
    /// printing which happened. It is written to upgrade itself: the day a
    /// runtime starts exposing labels here, the first branch begins asserting
    /// the real thing without anyone editing this file. What it must never do
    /// is assert "no placeholder label is present" — on a blind walk that is
    /// true for the wrong reason, which is exactly the vacuous green #429
    /// caught with its own positive control.
    @Test("437-C — the loaded image is labelled for VoiceOver where a label is observable")
    func theLoadedImageIsLabelledForVoiceOver() async throws {
        let url = Self.uniqueURL("a11y")
        let consent = RemoteImageConsent()
        let fake = FakeRemoteImageLoader(payload: Self.pixel())

        let render = HostedRender(content: "![chart](\(url.absoluteString))",
                                  isStreaming: false, consent: consent, loader: fake)
        defer { render.teardown() }

        try await Task.sleep(for: .seconds(1))
        let placeholderLabel = RemoteImagePolicy.placeholderAccessibilityLabel(host: "images.example")
        let before = accessibilityLabels(in: render.window)
        print("437-C [labels before tap] \(before)")

        consent.approve(url)
        render.layout()
        try await Task.sleep(for: .seconds(1))

        let after = accessibilityLabels(in: render.window)
        print("437-C [labels after tap] \(after)")

        let expected = RemoteImagePolicy.loadedAccessibilityLabel(host: "images.example", altText: "chart")
        if before.contains(placeholderLabel) {
            // The walk is live: assert the real claim.
            #expect(after.contains(expected),
                    "the loaded image is unlabelled for VoiceOver — labels were \(after)")
        } else {
            // MEASURED BLIND. Assert what this harness can still see, and say so.
            print("437-C [a11y walk is blind in this host — falling back to the paint probe]")
            #expect(before.isEmpty && after.isEmpty,
                    "the walk found SOME labels but not the placeholder's — the fallback is not justified: \(before) / \(after)")
            let painted = paintedPixels(in: render.window)
            #expect(painted.drawn > 0, "the snapshot is blank — the next check would pass vacuously")
            #expect(painted.red > 0, "the approved image never replaced the placeholder")
        }
    }

    // MARK: - 437-E — the first wire count against the SHIPPING loader

    /// A PNG deliberately larger than 512 bytes.
    ///
    /// A stub body under 512 bytes can sit in `URLProtocol`'s buffer and never
    /// flush (measured on this project's SSE fixtures), so the size is an
    /// asserted premise of the bar rather than an accident of the fixture. A
    /// solid-colour PNG compresses to a few hundred bytes; per-pixel variation
    /// is what makes this one big enough.
    private static func paddedPNG() -> Data {
        let side = 48
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { context in
            for x in 0..<side {
                for y in 0..<side {
                    UIColor(red: CGFloat(x) / CGFloat(side),
                            green: CGFloat(y) / CGFloat(side),
                            blue: CGFloat((x * 7 + y * 13) % side) / CGFloat(side),
                            alpha: 1).setFill()
                    context.fill(CGRect(x: x, y: y, width: 1, height: 1))
                }
            }
        }
        return image.pngData() ?? Data()
    }

    /// **437-E — the SHIPPING loader puts nothing on the wire before the tap,
    /// and exactly one request after it.**
    ///
    /// Every other bar in this file counts calls on an INJECTED loader, so
    /// what they prove is that `RemoteImageView` asks nobody for bytes — true
    /// and load-bearing, but silent about whether production's own loader
    /// would have gone to the network anyway. This arm hosts the real view
    /// with the real `URLSessionRemoteImageLoader` and counts requests where
    /// they actually leave: a registered `URLProtocol`.
    ///
    /// The LIVE CONTROL is a direct `URLSession.shared` fetch through the same
    /// stub in the same registration window. Without it, "zero before the tap"
    /// is indistinguishable from a counter that was never wired up — which is
    /// exactly the trap #429's Task 0 fell into and named.
    @Test("437-E — the shipping loader makes zero requests before the tap and one after")
    func theShippingLoaderMakesNoRequestUntilTheTap() async throws {
        let png = Self.paddedPNG()
        #expect(png.count > 512,
                "a stub body under 512 bytes can fail to flush — the fixture is \(png.count) bytes")

        CountingURLProtocol.reset(body: png)
        URLProtocol.registerClass(CountingURLProtocol.self)
        defer { URLProtocol.unregisterClass(CountingURLProtocol.self) }

        // The live control, first: prove the counter can count.
        let controlURL = Self.uniqueURL("wire-control")
        let (controlData, _) = try await URLSession.shared.data(from: controlURL)
        #expect(controlData.count == png.count, "the stub served \(controlData.count) of \(png.count) bytes")
        #expect(CountingURLProtocol.count == 1,
                "the wire counter is blind — every zero below would be uninterpretable")

        let url = Self.uniqueURL("wire")
        let consent = RemoteImageConsent()
        let render = HostedRender(content: "![chart](\(url.absoluteString))",
                                  isStreaming: false, consent: consent, loader: URLSessionRemoteImageLoader())
        defer { render.teardown() }

        try await Task.sleep(for: .seconds(1))
        #expect(CountingURLProtocol.count == 1,
                "the shipping loader reached the wire with no consent: \(CountingURLProtocol.urls.map(\.absoluteString))")

        // The tap.
        consent.approve(url)
        render.layout()
        try await Task.sleep(for: .seconds(2))

        #expect(CountingURLProtocol.count == 2,
                "expected exactly one request after the tap, saw \(CountingURLProtocol.count - 1)")
        #expect(CountingURLProtocol.urls.last == url,
                "the request that went out was not the URL the reader tapped")
        #expect(consent.image(for: url) != nil,
                "the stubbed PNG never decoded — this bar measured a failed load, not a gated one")
    }
}

// MARK: - The wire counter (437-E)

/// Counts every request that reaches the wire for `images.example`, and answers
/// with a real PNG.
///
/// Registered globally, which is why this can see the shipping loader at all:
/// `URLSessionRemoteImageLoader` fetches through `URLSession.shared`, and the
/// shared session consults the global protocol registry. (`AsyncImage` did not,
/// which is the whole reason #429 could only count on an injected seam — 437-E
/// is the bar that finally measures production's own bytes rather than a
/// stand-in for them.)
///
/// File scope, not nested in the `@MainActor` suite: `startLoading()` is called
/// on the URL loading system's own thread, and the counter has to be reachable
/// from there.
///
/// **`@unchecked Sendable` is load-bearing and was learned the hard way.**
/// Every one of the fourteen other `URLProtocol` stubs in this target declares
/// it; the first draft of this one did not, and the module stopped compiling —
/// `RunsApprovalTests.swift:189` failed with "capture of 'self' with
/// non-Sendable type 'ApprovalStubURLProtocol'", in a file this lane never
/// touched. Measured, not guessed: a clean `build-for-testing` of the tree
/// with this lane's changes stashed succeeded with zero errors and zero
/// `#UnavailableSendableConformance` warnings, and the same build with them
/// restored produced seven. A subclass that leaves its own Sendability to be
/// inferred makes the compiler resolve `URLProtocol`'s own — which Foundation
/// marks unavailable — and every sibling's `@unchecked Sendable` is then
/// reported as inheriting that unavailable conformance and stops counting.
/// The annotation short-circuits the lookup. Nothing here is actually shared
/// unsafely: all mutable state is behind the lock below.
final class CountingURLProtocol: URLProtocol, @unchecked Sendable {
    private struct State {
        var count = 0
        var urls: [URL] = []
        var body = Data()
    }

    private static let state = OSAllocatedUnfairLock<State>(initialState: State())

    static func reset(body: Data) { state.withLock { $0 = State(count: 0, urls: [], body: body) } }
    static var count: Int { state.withLock { $0.count } }
    static var urls: [URL] { state.withLock { $0.urls } }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "images.example"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        let body = Self.state.withLock { state -> Data in
            state.count += 1
            state.urls.append(url)
            return state.body
        }
        if let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "image/png", "Content-Length": "\(body.count)"]
        ) {
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        }
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
