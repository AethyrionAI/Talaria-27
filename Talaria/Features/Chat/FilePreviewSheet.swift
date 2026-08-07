import SwiftUI

// MARK: - In-app preview surface for agent files (#99)
//
// Tier 1 (#21) reconstructs agent-written files from the SSE stream into a
// tappable file chip; this adds the in-app preview on top: tap the chip → a
// full-screen sheet. v1 previews single-file HTML (sandboxed WKWebView —
// HTMLPreviewView.swift) and text/code/markdown (the shipped #92 rendering
// stack); #258 adds SVG, rendered as a graphic through that same sandbox and
// degrading to its own source when the markup won't parse. Everything else
// gets an honest no-preview card with a working ShareLink — never a blank
// sheet.
//
// The sheet chrome deliberately takes "a content view + a title", not a
// payload string, so a future P8 rung can present a rendered GenUI IR surface
// (`GenUISurfaceView`) in the same chrome without rework.

// MARK: - Routing

/// Which preview surface a file gets, decided by extension alone. The staged
/// content is read separately (`AgentFilePreview.content(for:)`) and a failed
/// read falls back to the honest no-preview card.
enum FilePreviewRoute: Equatable {
    case html
    case markdown
    /// #258 bar 258-B: a vector graphic, rendered as a GRAPHIC rather than as
    /// its source. Routing is by extension alone and so cannot know whether
    /// the bytes parse — an `.svg` whose markup is malformed degrades to the
    /// code view at content-resolution time, never to a blank sheet.
    case svg
    /// #92 code panel; `language` is the fence tag handed to the highlighter
    /// (nil for plain text, so prose never gets false keyword coloring).
    case code(language: String?)
    case unsupported

    static func route(forFileName fileName: String) -> FilePreviewRoute {
        let ext = (fileName as NSString).pathExtension.lowercased()
        switch ext {
        case "html", "htm":
            return .html
        case "md", "markdown":
            return .markdown
        case "svg":
            // #258: NOT `svgz` — that is gzip, and the whole preview stack is
            // UTF-8 text end to end (`stagedText` decodes or gives up), so
            // routing it would buy a guaranteed no-preview card with extra
            // steps. It keeps the honest card and its working ShareLink.
            return .svg
        case "txt", "log", "text":
            return .code(language: nil)
        case _ where codeExtensions.contains(ext):
            return .code(language: ext)
        default:
            // Includes RTF (its markup would render as noise as plain text)
            // and every binary type — those keep the ShareLink-only behavior.
            return .unsupported
        }
    }

    /// Extensions previewed in the #92 code panel with the extension passed
    /// through as the language tag — `CodeSyntaxHighlighter` resolves the tags
    /// it knows and falls back to its generic profile for the rest.
    private static let codeExtensions: Set<String> = [
        "json", "csv", "tsv", "yml", "yaml", "toml", "xml", "css",
        "swift", "py", "js", "jsx", "ts", "tsx", "sh", "bash", "zsh",
        "ini", "conf", "env", "c", "cpp", "h", "hpp", "java", "kt",
        "rb", "go", "rs", "sql", "diff", "patch",
    ]
}

// MARK: - Content resolution

/// What the preview sheet actually shows: routing + the staged-file read
/// collapsed into one value, so the sheet body is a pure function of it.
enum AgentFilePreviewContent: Equatable {
    case html(String)
    case markdown(String)
    /// #258: the RAW SVG markup. The sheet wraps it for the hardened web view
    /// at render time (`SVGPreviewDocument.wrap`) — keeping the raw markup in
    /// the value means the wrapping stays one testable function, not a string
    /// smeared through content resolution.
    case svg(String)
    case code(language: String?, text: String)
    /// No preview: unsupported type, missing staged file, or non-UTF-8 bytes.
    case unavailable
}

enum AgentFilePreview {
    /// Resolves the preview content for a reconstructed agent file.
    static func content(for attachment: MessageAttachment) -> AgentFilePreviewContent {
        let route = FilePreviewRoute.route(forFileName: attachment.fileName)
        guard route != .unsupported else { return .unavailable }
        guard let text = stagedText(atPath: attachment.localStoragePath) else {
            TalariaLog.event("FilePreview: staged content unreadable for \(attachment.fileName) — showing no-preview card")
            return .unavailable
        }
        switch route {
        case .html: return .html(text)
        case .markdown: return .markdown(text)
        case .svg:
            // #258 bar 258-B: the malformed check lives HERE, not in routing —
            // routing is a pure function of the file name and has no bytes to
            // judge, while this is where the staged read already happens. An
            // unparseable (or misnamed) `.svg` degrades to its source in the
            // #92 code panel rather than painting an empty web view.
            guard SVGPreviewDocument.isRenderable(text) else {
                TalariaLog.event("FilePreview: \(attachment.fileName) is not renderable SVG — showing the source instead")
                return .code(language: "xml", text: text)
            }
            return .svg(text)
        case .code(let language): return .code(language: language, text: text)
        case .unsupported: return .unavailable
        }
    }

    /// Reads a staged Tier-1 file back as UTF-8 text. Tier 1 only ever stages
    /// text (the `args.content` string from the SSE stream), so bytes that
    /// don't decode are treated as unpreviewable rather than force-decoded.
    static func stagedText(atPath path: String?) -> String? {
        guard let path,
              let data = FileManager.default.contents(atPath: path) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - Sheet chrome

/// Full-screen preview chrome: file-name title bar, Done, and the ShareLink
/// relocated from the bubble into the toolbar (preview AND share, not
/// either/or). The content slot is a generic view — HTML or the #92 stack
/// today, a rendered IR surface on a later P8 rung.
struct FilePreviewSheet<Content: View>: View {
    let title: String
    var shareItem: URL?
    @ViewBuilder var content: () -> Content

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                HUDScreenBackground()
                    .ignoresSafeArea()
                content()
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let shareItem {
                    ToolbarItem(placement: .topBarLeading) {
                        ShareLink(item: shareItem) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: Design.Size.iconSmall))
                                .foregroundStyle(Design.Brand.accent)
                        }
                        .accessibilityLabel("Share file \(title)")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(Design.Typography.mono(13, weight: .medium))
                        .foregroundStyle(Design.Brand.accent)
                }
            }
        }
    }
}

// MARK: - Agent-file preview

/// The sheet the agent-file bubble presents: routes the reconstructed file
/// into the right preview surface inside the shared chrome.
struct AgentFilePreviewSheet: View {
    let attachment: MessageAttachment

    private var shareURL: URL? {
        attachment.localStoragePath.map { URL(fileURLWithPath: $0) }
    }

    var body: some View {
        let resolved = AgentFilePreview.content(for: attachment)
        FilePreviewSheet(title: attachment.fileName, shareItem: shareURL) {
            switch resolved {
            case .html(let html):
                // #259: rides the egress-rules seam — loading spinner, then
                // the hardened web view; a rules failure fails closed to the
                // artifact's own source in the code panel.
                HTMLArtifactPreview(html: html, sourceLanguage: "html", sourceText: html)
            case .svg(let markup):
                // Same vehicle, same seam; the source fallback is the RAW
                // markup, not the wrapper document around it.
                HTMLArtifactPreview(
                    html: SVGPreviewDocument.wrap(markup),
                    sourceLanguage: "xml",
                    sourceText: markup
                )
            case .markdown(let text):
                ScrollView {
                    MarkdownContentView(content: text, isStreaming: false)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Design.Spacing.md)
                }
            case .code(let language, let text):
                ScrollView {
                    CodeBlockView(language: language, code: text)
                        .padding(Design.Spacing.md)
                }
            case .unavailable:
                FilePreviewUnavailableCard(fileName: attachment.fileName, shareURL: shareURL)
            }
        }
    }
}

// MARK: - No-preview card

/// Honest placeholder for files the app can't render in place. Keeps a
/// working ShareLink so the file stays one tap from Files/AirDrop even when
/// it can't be previewed.
struct FilePreviewUnavailableCard: View {
    let fileName: String
    let shareURL: URL?

    var body: some View {
        VStack(spacing: Design.Spacing.md) {
            Image(systemName: "eye.slash")
                .font(.system(size: 28))
                .foregroundStyle(Design.Colors.mutedForeground)

            MonoLabel("NO IN-APP PREVIEW", size: 11, color: Design.Colors.mutedForeground)

            Text("\(fileName) can't be rendered here. Share it to another app instead.")
                .font(Design.Typography.footnote)
                .foregroundStyle(Design.Colors.secondaryForeground)
                .multilineTextAlignment(.center)

            if let shareURL {
                ShareLink(item: shareURL) {
                    HStack(spacing: Design.Spacing.xs) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: Design.Size.iconSmall))
                        Text("SHARE")
                            .font(Design.Typography.mono(12, weight: .medium))
                            .tracking(Design.Tracking.mono)
                    }
                    .foregroundStyle(Design.Brand.accent)
                    .padding(.horizontal, Design.Spacing.lg)
                    .padding(.vertical, Design.Spacing.sm)
                    .hudPanel(
                        cornerRadius: Design.CornerRadius.full,
                        borderColor: Design.Colors.accentTint(0.28),
                        fill: Design.Colors.surface
                    )
                }
                .accessibilityLabel("Share file \(fileName)")
            }
        }
        .padding(Design.Spacing.lg)
    }
}
