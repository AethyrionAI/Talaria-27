import Foundation
import Testing
@testable import Talaria

/// Lane I (#99): file-type routing for the preview sheet, preview-content
/// plumbing from reconstructed Tier-1 fixtures, and the one-shot HTML
/// navigation policy (initial load allowed, everything after cancelled).
struct FilePreviewTests {

    // MARK: - File-type routing

    @Test func routesHTMLExtensions() {
        #expect(FilePreviewRoute.route(forFileName: "dashboard.html") == .html)
        #expect(FilePreviewRoute.route(forFileName: "page.htm") == .html)
        // Extension matching is case-insensitive.
        #expect(FilePreviewRoute.route(forFileName: "REPORT.HTML") == .html)
    }

    @Test func routesMarkdown() {
        #expect(FilePreviewRoute.route(forFileName: "notes.md") == .markdown)
        #expect(FilePreviewRoute.route(forFileName: "README.markdown") == .markdown)
    }

    @Test func routesPlainTextWithoutALanguageTag() {
        // nil language → the highlighter's generic profile, so prose never
        // gets false keyword coloring.
        #expect(FilePreviewRoute.route(forFileName: "output.txt") == .code(language: nil))
        #expect(FilePreviewRoute.route(forFileName: "server.log") == .code(language: nil))
    }

    @Test func routesCodeWithTheExtensionAsLanguageTag() {
        #expect(FilePreviewRoute.route(forFileName: "Main.swift") == .code(language: "swift"))
        #expect(FilePreviewRoute.route(forFileName: "script.py") == .code(language: "py"))
        #expect(FilePreviewRoute.route(forFileName: "data.json") == .code(language: "json"))
        #expect(FilePreviewRoute.route(forFileName: "deploy.YAML") == .code(language: "yaml"))
    }

    @Test func routesEverythingElseToUnsupported() {
        #expect(FilePreviewRoute.route(forFileName: "photo.png") == .unsupported)
        #expect(FilePreviewRoute.route(forFileName: "archive.zip") == .unsupported)
        #expect(FilePreviewRoute.route(forFileName: "report.pdf") == .unsupported)
        // RTF is text-ish on disk but its markup would render as noise.
        #expect(FilePreviewRoute.route(forFileName: "styled.rtf") == .unsupported)
        #expect(FilePreviewRoute.route(forFileName: "no-extension") == .unsupported)
        #expect(FilePreviewRoute.route(forFileName: "") == .unsupported)
    }

    // MARK: - Content plumbing (reconstructed Tier-1 fixture → preview)

    private func removeStagedFile(_ attachment: MessageAttachment) {
        if let path = attachment.localStoragePath {
            try? FileManager.default.removeItem(atPath: path)
        }
    }

    @Test func htmlFixturePlumbsThroughVerbatim() throws {
        let html = "<html><body><script>document.title = 'artifact';</script><h1>Hi</h1></body></html>"
        let attachment = try #require(
            MessageAttachment.agentFile(remotePath: "/hermes/out/artifact.html", content: html)
        )
        defer { removeStagedFile(attachment) }
        #expect(AgentFilePreview.content(for: attachment) == .html(html))
    }

    @Test func markdownFixtureRoutesToTheMarkdownStack() throws {
        let markdown = "# Report\n\nSome **bold** findings.\n\n```swift\nlet x = 1\n```\n"
        let attachment = try #require(
            MessageAttachment.agentFile(remotePath: "/hermes/out/report.md", content: markdown)
        )
        defer { removeStagedFile(attachment) }
        #expect(AgentFilePreview.content(for: attachment) == .markdown(markdown))
    }

    @Test func codeFixtureCarriesLanguageAndText() throws {
        let json = "{\n  \"ok\": true\n}\n"
        let attachment = try #require(
            MessageAttachment.agentFile(remotePath: "/hermes/out/data.json", content: json)
        )
        defer { removeStagedFile(attachment) }
        #expect(AgentFilePreview.content(for: attachment) == .code(language: "json", text: json))
    }

    @Test func unsupportedTypeIsUnavailableEvenWithReadableContent() throws {
        let attachment = try #require(
            MessageAttachment.agentFile(remotePath: "/hermes/out/photo.png", content: "not really an image")
        )
        defer { removeStagedFile(attachment) }
        #expect(AgentFilePreview.content(for: attachment) == .unavailable)
    }

    @Test func missingStagedPathIsUnavailable() {
        let attachment = MessageAttachment(
            kind: "file", fileName: "ghost.html", mimeType: "text/html", localStoragePath: nil
        )
        #expect(AgentFilePreview.content(for: attachment) == .unavailable)
    }

    @Test func unreadableStagedPathIsUnavailable() {
        let attachment = MessageAttachment(
            kind: "file", fileName: "gone.md", mimeType: "text/markdown",
            localStoragePath: "/nonexistent/\(UUID().uuidString)/gone.md"
        )
        #expect(AgentFilePreview.content(for: attachment) == .unavailable)
    }

    @Test func nonUTF8StagedBytesAreUnavailable() throws {
        // 0xFF can never start a UTF-8 scalar, so this cannot decode.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString)-junk.txt")
        try Data([0xFF, 0xFE, 0xFA, 0x00, 0xD8]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let attachment = MessageAttachment(
            kind: "file", fileName: "junk.txt", mimeType: "text/plain", localStoragePath: url.path
        )
        #expect(AgentFilePreview.content(for: attachment) == .unavailable)
    }

    // MARK: - One-shot HTML navigation policy

    @Test @MainActor func initialAboutBlankLoadIsAllowedOnce() {
        let policy = HTMLPreviewNavigationPolicy()
        #expect(policy.evaluate(url: URL(string: "about:blank")) == .allow)
        #expect(policy.hasApprovedInitialLoad)
    }

    @Test @MainActor func nilRequestURLCountsAsTheInitialLoad() {
        let policy = HTMLPreviewNavigationPolicy()
        #expect(policy.evaluate(url: nil) == .allow)
        #expect(policy.hasApprovedInitialLoad)
    }

    @Test @MainActor func everyNavigationAfterTheInitialLoadIsCancelled() {
        let policy = HTMLPreviewNavigationPolicy()
        #expect(policy.evaluate(url: URL(string: "about:blank")) == .allow)
        // Link tap out of the artifact.
        #expect(policy.evaluate(url: URL(string: "https://example.com")) == .cancel)
        // JS redirect back to about:blank after load.
        #expect(policy.evaluate(url: URL(string: "about:blank")) == .cancel)
        // The policy stays closed.
        #expect(policy.evaluate(url: nil) == .cancel)
    }

    @Test @MainActor func externalURLNeverConsumesTheInitialApproval() {
        let policy = HTMLPreviewNavigationPolicy()
        // A non-initial-looking URL is cancelled without wedging the preview
        // shut: the real about:blank load afterwards still commits.
        #expect(policy.evaluate(url: URL(string: "https://example.com")) == .cancel)
        #expect(!policy.hasApprovedInitialLoad)
        #expect(policy.evaluate(url: URL(string: "about:blank")) == .allow)
    }

    @Test @MainActor func anchorFragmentNavigationIsCancelled() {
        // In-page anchors arrive as about:blank#fragment — a distinct URL, so
        // they are cancelled like everything else post-load (v1 posture).
        let policy = HTMLPreviewNavigationPolicy()
        #expect(policy.evaluate(url: URL(string: "about:blank")) == .allow)
        #expect(policy.evaluate(url: URL(string: "about:blank#section-2")) == .cancel)
    }
}
