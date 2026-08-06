import Foundation
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

// MARK: - SVG artifacts (#258 bar 258-B)

/// Turns an agent-written `.svg` into something the hardened preview above can
/// show as a GRAPHIC, and decides when it can't be shown at all.
///
/// The vehicle is deliberately the sandbox above, UNMODIFIED: the wrapped
/// document still rides `loadHTMLString(_:baseURL: nil)`, the ephemeral data
/// store, the one-shot navigation policy, the dead `window.open`, and the
/// absent JS bridge. Every guarantee in the block at the top of this file
/// holds for an SVG exactly as it holds for an HTML artifact.
///
/// The wrapper adds one thing on top — a deny-by-default
/// Content-Security-Policy — because SVG is the artifact type that can legally
/// carry `<script>` and a remote `<image href>`, and a subresource load is NOT
/// a navigation, so the one-shot policy never sees it. The CSP is a belt, not
/// the braces: if a WebKit build ignored the meta tag, an SVG would land
/// exactly where HTML artifacts already are today — never further.
enum SVGPreviewDocument {

    /// Whether the markup is worth handing to the web view at all: well-formed
    /// XML whose root element is `svg`. Anything else — a truncated
    /// generation, an unescaped `&`, a file merely NAMED `.svg` — would paint
    /// an empty page, so the caller degrades it to the code view instead
    /// (bar 258-B: never blank, never a crash).
    static func isRenderable(_ markup: String) -> Bool {
        guard let data = markup.data(using: .utf8), !data.isEmpty else { return false }
        let parser = XMLParser(data: data)
        // Agent-authored markup never gets to make the app fetch a DTD or
        // expand an external entity on its say-so.
        parser.shouldResolveExternalEntities = false
        let probe = RootElementProbe()
        parser.delegate = probe
        guard parser.parse(), let root = probe.rootElement else { return false }
        // Namespace processing is off, so a prefixed document reports its root
        // qualified (`svg:svg`); the local name is what identifies it.
        return root.split(separator: ":").last?.lowercased() == "svg"
    }

    /// The minimal host document: charset, viewport, the deny-by-default CSP,
    /// and just enough CSS to centre the graphic and fit it to the sheet.
    ///
    /// The markup is embedded verbatim rather than re-serialized — callers
    /// have already run it through `isRenderable`, which proves it is a single
    /// balanced `<svg>` tree, so it cannot close the wrapper early. The canvas
    /// is white on purpose: an `.svg` almost always assumes a light page and
    /// `currentColor` resolves to black, so painting one straight onto the
    /// dark HUD would produce the invisible-graphic case this route exists to
    /// avoid.
    static func wrap(_ markup: String) -> String {
        """
        <!DOCTYPE html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta http-equiv="Content-Security-Policy" \
        content="default-src 'none'; style-src 'unsafe-inline'; img-src data:">
        <style>
        html, body { margin: 0; height: 100%; background: #ffffff; }
        body { display: flex; align-items: center; justify-content: center;
               padding: 16px; box-sizing: border-box; }
        body > svg { max-width: 100%; max-height: 100%; width: auto; height: auto; }
        </style>
        </head><body>
        \(markup)
        </body></html>
        """
    }

    /// Captures the first element the parser opens — the document root.
    private final class RootElementProbe: NSObject, XMLParserDelegate {
        private(set) var rootElement: String?

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName: String?,
            attributes attributeDict: [String: String]
        ) {
            if rootElement == nil { rootElement = elementName }
        }
    }
}
