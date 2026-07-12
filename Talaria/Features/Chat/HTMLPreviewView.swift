import SwiftUI
import WebKit

// MARK: - Sandboxed HTML preview (#99)
//
// Renders a reconstructed single-file HTML artifact in-app. The content is
// model-generated, so it's treated like untrusted web content:
//  • loaded via `loadHTMLString(_:baseURL: nil)` — no file URLs, no read
//    access grants;
//  • no JS-to-app bridge — no `WKScriptMessageHandler` is ever installed;
//  • one-shot navigation policy — the initial `about:blank` load is the only
//    navigation that ever commits; link taps, JS redirects, and frame
//    navigations are all cancelled (external links deliberately open
//    NOWHERE — cancelled, not handed to Safari);
//  • `window.open`/`target="_blank"` get no web view back;
//  • ephemeral website data store, no data detectors, no link previews.
// Inline JS inside the artifact still runs — the sandbox is about egress and
// app-bridge surface, not about disabling the artifact.

/// One-shot navigation policy. `loadHTMLString(_:baseURL: nil)` loads as
/// `about:blank`, and that navigation necessarily reaches the policy first —
/// no script has run and no interaction is possible before it — so the policy
/// approves exactly one `about:blank` (or nil-URL) navigation and cancels
/// everything after, main-frame and subframe alike. A non-initial-looking URL
/// never consumes the approval, so a stray early callback can't wedge the
/// preview shut.
@MainActor
final class HTMLPreviewNavigationPolicy: NSObject {
    enum Decision: Equatable {
        case allow
        case cancel
    }

    private(set) var hasApprovedInitialLoad = false

    /// The decision core, separated from the delegate callback so it is
    /// directly unit-testable (`WKNavigationAction` cannot be constructed in
    /// tests).
    func evaluate(url: URL?) -> Decision {
        guard !hasApprovedInitialLoad, Self.isInitialDocumentURL(url) else {
            TalariaLog.event("FilePreview: cancelled HTML preview navigation to \(url?.absoluteString ?? "unknown URL")")
            return .cancel
        }
        hasApprovedInitialLoad = true
        return .allow
    }

    /// The only document the policy ever approves: the `about:blank` load
    /// that `loadHTMLString(_:baseURL: nil)` produces (nil accepted in case
    /// the request URL is absent on the initial action).
    static func isInitialDocumentURL(_ url: URL?) -> Bool {
        guard let url else { return true }
        return url.absoluteString == "about:blank"
    }
}

extension HTMLPreviewNavigationPolicy: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
        evaluate(url: navigationAction.request.url) == .allow ? .allow : .cancel
    }
}

extension HTMLPreviewNavigationPolicy: WKUIDelegate {
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        // window.open / target="_blank": no popup surface exists here.
        nil
    }
}

/// The preview sheet's HTML surface: a hardened `WKWebView` that loads the
/// reconstructed artifact once and never navigates again.
struct HTMLPreviewView: UIViewRepresentable {
    let html: String

    func makeCoordinator() -> HTMLPreviewNavigationPolicy {
        HTMLPreviewNavigationPolicy()
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // Nothing the artifact stores (cookies, localStorage) outlives the
        // presentation.
        configuration.websiteDataStore = .nonPersistent()
        // No auto-linkified phone numbers/addresses — navigation is dead here
        // anyway, so don't manufacture tappable links.
        configuration.dataDetectorTypes = []

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsLinkPreview = false
        webView.allowsBackForwardNavigationGestures = false
        webView.loadHTMLString(html, baseURL: nil)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // Content is fixed for the life of the presentation; a reload here
        // would be cancelled by the one-shot policy by design.
    }
}
