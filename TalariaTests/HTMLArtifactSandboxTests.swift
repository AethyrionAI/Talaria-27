import Foundation
import Network
import Testing
import WebKit
@testable import Talaria

/// #259 — the `.html` artifact preview's egress block: scripts ON, network
/// BLOCKED, verified against REAL WebKit with a live control arm (the #258
/// review's standard, brought inside the suite).
///
/// The mechanism under test is a compiled `WKContentRuleList` attached to the
/// preview configuration — markup-independent, so no injection surgery on an
/// agent-authored document, and inline script never passes through a network
/// blocker so interactivity survives by construction. `HTMLPreviewView`
/// REQUIRES the compiled rules by type; the async seam that supplies them
/// degrades to the code view on failure (259-C), so no path renders an HTML
/// artifact scripts-enabled without the block attached.
@Suite(.serialized)
@MainActor
struct HTMLArtifactSandboxTests {

    // MARK: - Harness: a real in-process TCP listener the beacon can hit

    /// Counts connections off the listener queue; read from the main actor.
    private final class BeaconCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var hits = 0

        func record() {
            lock.lock()
            defer { lock.unlock() }
            hits += 1
        }

        var count: Int {
            lock.lock()
            defer { lock.unlock() }
            return hits
        }
    }

    /// A minimal HTTP responder: every accepted connection counts as egress
    /// (the request left the web view — that IS the leak, regardless of what
    /// the response says).
    private func startListener(_ counter: BeaconCounter) throws -> (listener: NWListener, port: UInt16) {
        let listener = try NWListener(using: .tcp, on: .any)
        listener.newConnectionHandler = { connection in
            counter.record()
            connection.start(queue: .global())
            connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { _, _, _, _ in
                let response = Data("HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8)
                connection.send(content: response, completion: .contentProcessed { _ in
                    connection.cancel()
                })
            }
        }
        listener.start(queue: .global())
        for _ in 0..<200 {
            if let port = listener.port?.rawValue, port > 0 { return (listener, port) }
            usleep(20_000)
        }
        throw HarnessError.listenerNeverReady
    }

    private enum HarnessError: Error {
        case listenerNeverReady
    }

    /// An artifact whose inline script tries BOTH cheap egress vectors — a
    /// fetch and an image load — and stamps a DOM marker so script execution
    /// is observable independently of the network outcome.
    private func beaconArtifact(port: UInt16) -> String {
        """
        <!DOCTYPE html><html><head><meta charset="utf-8"></head><body>
        <script>
        document.body.setAttribute("data-ran", "yes");
        fetch("http://127.0.0.1:\(port)/beacon").catch(function () {});
        new Image().src = "http://127.0.0.1:\(port)/beacon.gif";
        </script>
        </body></html>
        """
    }

    /// Polls the DOM marker the ARTIFACT's own script wrote. Reading it with
    /// `evaluateJavaScript` is not circular — the evaluation only reads; the
    /// attribute exists only if the artifact's inline script executed.
    ///
    /// Two harness hazards this encodes, both of which produced a wrong answer
    /// during this lane before being caught:
    /// 1. JS `null` arrives as `NSNull`, which is NOT Swift `nil` — an
    ///    `!= nil` check succeeds on the first poll and measures nothing.
    /// 2. `webView.title` never propagated for these `about:blank` documents,
    ///    so title was a dead observation channel.
    private func waitForScriptMarker(_ webView: WKWebView) async -> Bool {
        for _ in 0..<50 {
            await wait(seconds: 0.1)
            if let marker = (try? await webView.evaluateJavaScript(
                "document.body.getAttribute('data-ran')")) as? String, marker == "yes" {
                return true
            }
        }
        return false
    }

    /// Builds the production web view AND hands back the policy, because
    /// `WKWebView.navigationDelegate` is WEAK: a caller that lets the policy
    /// die leaves the initial navigation decision unanswered and the document
    /// never commits — a BLANK page. SwiftUI retains the coordinator in
    /// production; a test must retain it deliberately.
    private func makeShippedWebView(rules: WKContentRuleList)
        -> (webView: WKWebView, policy: HTMLPreviewNavigationPolicy) {
        let policy = HTMLPreviewNavigationPolicy()
        return (HTMLPreviewView.makeHardenedWebView(rules: rules, policy: policy), policy)
    }

    /// The control arm's bare web view: same load shape as the preview
    /// (`loadHTMLString(_:baseURL: nil)`, ephemeral store) but NO rules —
    /// deliberately not the production view, which cannot be constructed
    /// without rules.
    private func controlWebView() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        return WKWebView(frame: .zero, configuration: configuration)
    }

    private func wait(seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
    }

    // MARK: - Compilation

    @Test func rulesCompileAndCache() async throws {
        let first = try await HTMLArtifactSandbox.rules()
        let second = try await HTMLArtifactSandbox.rules()
        #expect(first === second)
    }

    // MARK: - 259-A: the leak dies, with a live control arm

    /// The control proves the HARNESS: same WebKit, same load shape, no rules
    /// — the beacon lands. Without this arm, a zero in the blocked test could
    /// mean "blocked" or "the harness never worked" and the suite couldn't
    /// tell (#258's blank-pane lesson).
    @Test func controlArmWithoutRulesLeaksToTheListener() async throws {
        let counter = BeaconCounter()
        let (listener, port) = try startListener(counter)
        defer { listener.cancel() }

        let webView = controlWebView()
        webView.loadHTMLString(beaconArtifact(port: port), baseURL: nil)

        var landed = false
        for _ in 0..<50 {
            if counter.count > 0 { landed = true; break }
            await wait(seconds: 0.1)
        }
        #expect(landed, "control arm produced no network hit — the harness is not live")
    }

    /// 259-A. **A zero here means nothing on its own** — a document that never
    /// loaded also beacons zero times, and that is exactly how this test first
    /// passed for the wrong reason during this lane (a dangling weak
    /// navigation delegate left the page blank; #258's "green suite certified
    /// a blank pane", recurring). So the load is ASSERTED, not assumed: the
    /// artifact's script must have run, and only then does zero egress mean
    /// the block worked.
    @Test func shippedRulesBlockEveryBeaconFromALIVEDocument() async throws {
        let counter = BeaconCounter()
        let (listener, port) = try startListener(counter)
        defer { listener.cancel() }

        let rules = try await HTMLArtifactSandbox.rules()
        let (webView, policy) = makeShippedWebView(rules: rules)
        webView.loadHTMLString(beaconArtifact(port: port), baseURL: nil)

        // The document is alive and the beacon code actually executed…
        #expect(await waitForScriptMarker(webView),
                "the artifact never ran — a blank page cannot prove the block works")
        // …and after a window in which the control arm's hit always lands,
        // nothing reached the listener.
        await wait(seconds: 2.0)
        #expect(counter.count == 0)
        withExtendedLifetime(policy) {}
    }

    // MARK: - 259-B: interactivity survives

    @Test func inlineScriptExecutesUnderShippedRules() async throws {
        let rules = try await HTMLArtifactSandbox.rules()
        let (webView, policy) = makeShippedWebView(rules: rules)
        // Port 1: nothing listens, so this measures script execution only.
        webView.loadHTMLString(beaconArtifact(port: 1), baseURL: nil)
        #expect(await waitForScriptMarker(webView),
                "inline script never executed — scripts-on is a bar, not a hope")
        withExtendedLifetime(policy) {}
    }

    // MARK: - 259-C: fail closed, never blank

    @Test func compileFailureDegradesToTheSourceView() {
        struct Boom: Error {}
        #expect(HTMLArtifactPreview.Destination.resolve(nil) == .loading)
        #expect(HTMLArtifactPreview.Destination.resolve(.failure(Boom())) == .source)
        // Success routes to the web surface; the associated list is the one
        // compiled — identity, since WKContentRuleList is a reference type.
    }

    @Test func compileSuccessRoutesToTheWebSurface() async throws {
        let rules = try await HTMLArtifactSandbox.rules()
        #expect(HTMLArtifactPreview.Destination.resolve(.success(rules)) == .web(rules))
    }
}
