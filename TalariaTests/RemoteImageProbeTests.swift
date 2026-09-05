import Foundation
import os
import SwiftUI
import Testing
import UIKit

@testable import Talaria

/// # 429-T0 — TEMPORARY PROBE. Delete before the PR (plan Task 4).
///
/// **This file asserts almost nothing on purpose.** It is a MEASUREMENT whose
/// answer picks between two designs for the rest of the #429 lane:
///
///  * **Design A** — keep `AsyncImage` and gate it behind consent. Valid only
///    if a hosted `MarkdownContentView` in the app test host actually issues
///    `AsyncImage`'s request through a `URLProtocol` registered with
///    `URLProtocol.registerClass` (i.e. through `URLSession.shared`), because
///    bar 429-B's instrument is exactly that counter.
///  * **Design B** — `RemoteImageView` owns the load through an injectable
///    `RemoteImageLoading`, and the bar counts calls on the injected loader.
///
/// The premise design A rests on has never been measured in this tree: no
/// existing test hosts a SwiftUI view at all (`grep -rn UIHostingController
/// TalariaTests/` → 0 before this file). So this probe hosts one, registers a
/// counting protocol, pumps the run loop several DIFFERENT ways, and PRINTS
/// what it saw. A zero here would not be a bug — it would be the finding.
///
/// Everything is printed rather than asserted so that a run of this suite is
/// readable evidence. The only `#expect`s are structural (the harness built
/// what it thought it built).
///
/// Serialized because `CountingURLProtocol.hits` is class-global and because
/// `URLProtocol.registerClass` mutates process-wide state.
@Suite(.serialized)
@MainActor
struct RemoteImageProbeTests {

    // MARK: - The counting protocol (verbatim from the task brief)

    final class CountingURLProtocol: URLProtocol, @unchecked Sendable {
        static let hits = OSAllocatedUnfairLock<[URL]>(initialState: [])
        override class func canInit(with request: URLRequest) -> Bool { request.url?.scheme?.hasPrefix("http") == true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            if let url = request.url { Self.hits.withLock { $0.append(url) } }
            let response = HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }

    // MARK: - Harness

    /// A window + hosting controller kept alive for the duration of a pump.
    /// Torn down explicitly so a lingering key window cannot leak into another
    /// suite.
    private final class HostedRender {
        let window: UIWindow
        let host: UIHostingController<MarkdownContentView>

        init(content: String, isStreaming: Bool) {
            host = UIHostingController(rootView: MarkdownContentView(content: content, isStreaming: isStreaming))
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
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            window.layoutIfNeeded()
        }

        /// Force a fresh body evaluation (the streaming-delta shape).
        func update(content: String, isStreaming: Bool) {
            host.rootView = MarkdownContentView(content: content, isStreaming: isStreaming)
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

    /// Reset every piece of shared state a previous arm could have left behind.
    private func resetHarness() {
        URLCache.shared.removeAllCachedResponses()
        CountingURLProtocol.hits.withLock { $0.removeAll() }
    }

    private var hits: [URL] { CountingURLProtocol.hits.withLock { $0 } }

    private func report(_ label: String, _ observed: [URL]) {
        print("429-T0 [\(label)] hits=\(observed.count)")
        for (i, url) in observed.enumerated() {
            print("429-T0 [\(label)]   #\(i + 1) \(url.absoluteString)")
        }
    }

    // MARK: - Arm 1 — the brief's prescribed form: RunLoop.main.run(until:)

    @Test("429-T0 arm 1 — hosted render, RunLoop.main.run(until: .now + 1.0)")
    func armOne_runLoopPump() {
        let urlString = "https://images.example/pixel.png"
        resetHarness()
        #expect(URLProtocol.registerClass(CountingURLProtocol.self))
        defer { URLProtocol.unregisterClass(CountingURLProtocol.self) }

        // Structural: the parser really does mint an .image segment for this
        // content, so a zero below is about the RENDER, not about parsing.
        let segments = parseMarkdownSegments("![chart](\(urlString))", isStreaming: false)
        let imageURLs: [URL] = segments.compactMap {
            if case .image(_, let url, _) = $0 { return url }
            return nil
        }
        print("429-T0 [arm1] parsed segments=\(segments.count) imageSegments=\(imageURLs.count) urls=\(imageURLs.map(\.absoluteString))")
        #expect(imageURLs.map(\.absoluteString) == [urlString])

        let render = HostedRender(content: "![chart](\(urlString))", isStreaming: false)
        defer { render.teardown() }

        let started = Date()
        RunLoop.main.run(until: .now + 1.0)
        let elapsed = Date().timeIntervalSince(started)

        let observed = hits
        print("429-T0 [arm1] pump=RunLoop.main.run(until: .now + 1.0) elapsed=\(String(format: "%.3f", elapsed))s")
        report("arm1", observed)
        print("429-T0 [arm1] VERDICT INPUT: count=\(observed.count) exactURLMatches=\(observed.filter { $0.absoluteString == urlString }.count)")
    }

    // MARK: - Arm 2 — Task.sleep + Task.yield on the main actor

    @Test("429-T0 arm 2 — hosted render, Task.sleep + Task.yield on the main actor")
    func armTwo_taskSleepYield() async throws {
        let urlString = "https://images.example/arm2.png"
        resetHarness()
        #expect(URLProtocol.registerClass(CountingURLProtocol.self))
        defer { URLProtocol.unregisterClass(CountingURLProtocol.self) }

        let render = HostedRender(content: "![chart](\(urlString))", isStreaming: false)
        defer { render.teardown() }

        let started = Date()
        await Task.yield()
        try await Task.sleep(for: .seconds(1))
        await Task.yield()
        let elapsed = Date().timeIntervalSince(started)

        let observed = hits
        print("429-T0 [arm2] pump=Task.yield+Task.sleep(1s)+Task.yield elapsed=\(String(format: "%.3f", elapsed))s")
        report("arm2", observed)
        print("429-T0 [arm2] VERDICT INPUT: count=\(observed.count) exactURLMatches=\(observed.filter { $0.absoluteString == urlString }.count)")
    }

    // MARK: - Arm 3 — the brief's step-3 retry (setNeedsLayout + 2 s pump)

    @Test("429-T0 arm 3 — setNeedsLayout + 2 s RunLoop pump, cache cleared first")
    func armThree_retryLongerPump() {
        let urlString = "https://images.example/arm3.png"
        resetHarness()
        #expect(URLProtocol.registerClass(CountingURLProtocol.self))
        defer { URLProtocol.unregisterClass(CountingURLProtocol.self) }

        let render = HostedRender(content: "![chart](\(urlString))", isStreaming: false)
        defer { render.teardown() }

        render.window.rootViewController?.view.setNeedsLayout()
        render.window.rootViewController?.view.layoutIfNeeded()

        let started = Date()
        RunLoop.main.run(until: .now + 2.0)
        let elapsed = Date().timeIntervalSince(started)

        let observed = hits
        print("429-T0 [arm3] pump=setNeedsLayout + RunLoop 2.0s elapsed=\(String(format: "%.3f", elapsed))s")
        report("arm3", observed)
        print("429-T0 [arm3] VERDICT INPUT: count=\(observed.count) exactURLMatches=\(observed.filter { $0.absoluteString == urlString }.count)")
    }

    // MARK: - Arm 4 — detached task pump (the third form the lane asked about)

    @Test("429-T0 arm 4 — await Task.detached { }.value while the main run loop is pumped")
    func armFour_detachedTask() async {
        let urlString = "https://images.example/arm4.png"
        resetHarness()
        #expect(URLProtocol.registerClass(CountingURLProtocol.self))
        defer { URLProtocol.unregisterClass(CountingURLProtocol.self) }

        let render = HostedRender(content: "![chart](\(urlString))", isStreaming: false)
        defer { render.teardown() }

        let started = Date()
        await Task.detached { try? await Task.sleep(for: .seconds(1)) }.value
        let elapsed = Date().timeIntervalSince(started)

        let observed = hits
        print("429-T0 [arm4] pump=await Task.detached{sleep 1s}.value elapsed=\(String(format: "%.3f", elapsed))s")
        report("arm4", observed)
        print("429-T0 [arm4] VERDICT INPUT: count=\(observed.count) exactURLMatches=\(observed.filter { $0.absoluteString == urlString }.count)")
    }

    // MARK: - Arm 5 — timing: stepped pump, elapsed at first hit

    @Test("429-T0 arm 5 — stepped RunLoop pump, time to first request")
    func armFive_timeToFirstRequest() {
        let urlString = "https://images.example/arm5.png"
        resetHarness()
        #expect(URLProtocol.registerClass(CountingURLProtocol.self))
        defer { URLProtocol.unregisterClass(CountingURLProtocol.self) }

        let render = HostedRender(content: "![chart](\(urlString))", isStreaming: false)
        defer { render.teardown() }

        let started = Date()
        var firstHitAfter: TimeInterval?
        var slices = 0
        while Date().timeIntervalSince(started) < 3.0 {
            RunLoop.main.run(until: .now + 0.05)
            slices += 1
            if firstHitAfter == nil, !hits.isEmpty {
                firstHitAfter = Date().timeIntervalSince(started)
                break
            }
        }
        let observed = hits
        let timing = firstHitAfter.map { String(format: "%.3f", $0) } ?? "NEVER (3.0s budget)"
        print("429-T0 [arm5] slices=\(slices) timeToFirstRequest=\(timing)s")
        report("arm5", observed)
    }

    // MARK: - Arm 6 — the CONTROL design A's bar needs: no image ⇒ no hits

    @Test("429-T0 arm 6 — control: content with NO image issues no counted request")
    func armSix_noImageControl() {
        resetHarness()
        #expect(URLProtocol.registerClass(CountingURLProtocol.self))
        defer { URLProtocol.unregisterClass(CountingURLProtocol.self) }

        let content = """
        # Heading

        Some **prose** with a [link](https://images.example/not-an-image) and a table.

        | a | b |
        |---|---|
        | 1 | 2 |

        ```swift
        let x = 1
        ```
        """
        let render = HostedRender(content: content, isStreaming: false)
        defer { render.teardown() }

        RunLoop.main.run(until: .now + 1.0)

        let observed = hits
        print("429-T0 [arm6-control] no-image content rendered for 1.0s")
        report("arm6-control", observed)
        print("429-T0 [arm6-control] VERDICT INPUT: count=\(observed.count) (app chatter would appear here)")
    }

    // MARK: - Arm 7 — a second render of the SAME URL (429-D's cache question)

    @Test("429-T0 arm 7 — same URL rendered twice: does the second render issue a second request?")
    func armSeven_sameURLTwice() {
        let urlString = "https://images.example/arm7.png"
        resetHarness()
        #expect(URLProtocol.registerClass(CountingURLProtocol.self))
        defer { URLProtocol.unregisterClass(CountingURLProtocol.self) }

        let first = HostedRender(content: "![chart](\(urlString))", isStreaming: false)
        RunLoop.main.run(until: .now + 1.0)
        let afterFirst = hits
        report("arm7-first", afterFirst)
        first.teardown()

        // Same process, same URL, a brand-new hosting controller and window —
        // the shape a scroll-off/scroll-on or a fullscreen open produces.
        let second = HostedRender(content: "![chart](\(urlString))", isStreaming: false)
        defer { second.teardown() }
        RunLoop.main.run(until: .now + 1.0)
        let afterSecond = hits
        report("arm7-second", afterSecond)
        print("429-T0 [arm7] first=\(afterFirst.count) total=\(afterSecond.count) delta=\(afterSecond.count - afterFirst.count)")

        // And the streaming-delta shape 429-D cares about: three growing
        // contents through ONE hosting controller.
        resetHarness()
        let deltas = [
            "Here is a chart",
            "Here is a chart\n\n![chart](\(urlString))",
            "Here is a chart\n\n![chart](\(urlString))\n\nand some trailing prose."
        ]
        let streamer = HostedRender(content: deltas[0], isStreaming: true)
        defer { streamer.teardown() }
        RunLoop.main.run(until: .now + 0.3)
        print("429-T0 [arm7-delta] after delta 1 hits=\(hits.count)")
        streamer.update(content: deltas[1], isStreaming: true)
        RunLoop.main.run(until: .now + 0.5)
        print("429-T0 [arm7-delta] after delta 2 hits=\(hits.count)")
        streamer.update(content: deltas[2], isStreaming: true)
        RunLoop.main.run(until: .now + 0.5)
        print("429-T0 [arm7-delta] after delta 3 hits=\(hits.count)")
        report("arm7-delta", hits)
    }

    // MARK: - Arm 8 — the harness's own liveness (is the counter blind?)

    /// A zero above proves nothing unless the counter is shown to SEE a
    /// request when one is definitely made. This is the "live control arm or
    /// it is not a bar" rule applied to the probe itself.
    @Test("429-T0 arm 8 — liveness: a direct URLSession.shared request IS counted")
    func armEight_counterLiveness() async {
        let urlString = "https://images.example/liveness.png"
        resetHarness()
        #expect(URLProtocol.registerClass(CountingURLProtocol.self))
        defer { URLProtocol.unregisterClass(CountingURLProtocol.self) }

        _ = try? await URLSession.shared.data(from: URL(string: urlString)!)
        let observed = hits
        report("arm8-liveness", observed)
        print("429-T0 [arm8-liveness] VERDICT INPUT: count=\(observed.count) — if this is 0 the harness is blind and every other arm is uninterpretable")
        #expect(observed.map(\.absoluteString) == [urlString])
    }
}
