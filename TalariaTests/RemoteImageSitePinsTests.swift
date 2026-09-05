import Foundation
import Testing

@testable import Talaria

/// # 429-C / 429-E — every remote-image render site, structurally.
///
/// Bar 429-B counts loads through the injected seam, which can only see the
/// sites that actually go through `RemoteImageView`. A second `AsyncImage`
/// added anywhere in the app tomorrow would fetch on render, obey no consent,
/// and pass every runtime bar in this lane — so the ban has to be structural.
///
/// Task 0 measured why the ban is total rather than "exactly one site":
/// `AsyncImage` issues its request through a private `URLSession` built from
/// its own configuration, which consults only `configuration.protocolClasses`
/// and never the globally registered list. It exposes no session, no
/// configuration and no delegate — there is no seam to gate it on and no
/// counter that can watch it. `AsyncImage` is therefore unusable in this app,
/// not merely undesirable, and this file is where that is enforced.
///
/// Every check that reads a file fails LOUDLY when it cannot read it — a check
/// that did not run must say so rather than pass (`NamingSweepTests`' rule).
@Suite("429-C/E remote image site pins")
struct RemoteImageSitePinsTests {

    // MARK: - Helpers

    /// Every `.swift` source in the shipping targets, as text.
    ///
    /// A copy of `NamingSweepTests.shippingSources()` (`:46-62`) because that
    /// one is `private static` and this suite is not in that type. Same four
    /// roots, same loud-failure discipline; if a future task hoists one of
    /// them, hoist both.
    private static func shippingSources() throws -> [(path: String, text: String)] {
        var out: [(String, String)] = []
        for dir in ["Talaria", "Shared", "TalariaWidgets", "TalariaShare"] {
            let root = RepoSourceWitness.repoRoot.appendingPathComponent(dir)
            let walker = try #require(
                FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil),
                "cannot enumerate \(dir)/ — this check did not run"
            )
            for case let url as URL in walker where url.pathExtension == "swift" {
                if let text = try? String(contentsOf: url, encoding: .utf8) {
                    out.append((url.path, text))
                }
            }
        }
        #expect(!out.isEmpty, "cannot read any shipping source — this check did not run")
        return out
    }

    private static func occurrences(of needle: String, in haystack: String) -> Int {
        haystack.components(separatedBy: needle).count - 1
    }

    private static let markdownContentViewPath = "Talaria/Features/Chat/MarkdownContentView.swift"
    private static let remoteImageViewPath = "Talaria/Features/Chat/RemoteImageView.swift"
    private static let remoteImageLoadingPath = "Talaria/Features/Chat/RemoteImageLoading.swift"

    // MARK: - 429-C

    /// **429-C-1 — `AsyncImage(` occurs in ZERO shipping sources.**
    ///
    /// The design-B branch of the plan's 429-C. Not "exactly one site": there
    /// is no gateable `AsyncImage` at all.
    @Test(.enabled(if: RepoSourceWitness.repoSourcesAreReadable,
                   "reads the repo — simulator only"))
    func asyncImageAppearsInNoShippingSource() throws {
        let sources = try Self.shippingSources()
        let offenders = sources
            .filter { $0.text.contains("AsyncImage(") }
            .map { $0.path }
        #expect(offenders.isEmpty,
                "AsyncImage fetches on render and cannot be gated on consent (Task 0) — found in: \(offenders)")
    }

    /// **429-C-2 — `MarkdownContentView` renders both image sites through
    /// `RemoteImageView` and contains no `AsyncImage(`.**
    @Test(.enabled(if: RepoSourceWitness.repoSourcesAreReadable,
                   "reads the repo — simulator only"))
    func markdownContentViewGoesThroughRemoteImageViewTwice() throws {
        let source = try RepoSourceWitness.source(Self.markdownContentViewPath)
        #expect(Self.occurrences(of: "RemoteImageView(", in: source) >= 2,
                "the inline site and the fullscreen viewer must both render through RemoteImageView")
        #expect(Self.occurrences(of: "AsyncImage(", in: source) == 0)
    }

    /// **429-C-3 — the three other `MarkdownContentView` callers stay
    /// indirect.**
    ///
    /// They render remote images only by going through `MarkdownContentView`.
    /// Pinned by name so a future direct `AsyncImage` in a message bubble, a
    /// file preview or a briefing reds here rather than shipping an ungated
    /// fetch.
    @Test(.enabled(if: RepoSourceWitness.repoSourcesAreReadable,
                   "reads the repo — simulator only"))
    func theOtherRenderSurfacesHoldNoAsyncImage() throws {
        for path in [
            "Talaria/Features/Chat/MessageBubble.swift",
            "Talaria/Features/Chat/FilePreviewSheet.swift",
            "Talaria/Features/Inbox/BriefingDetailScreen.swift"
        ] {
            let source = try RepoSourceWitness.source(path)
            #expect(source.contains("MarkdownContentView("),
                    "\(path) no longer renders through MarkdownContentView — re-point this pin")
            #expect(Self.occurrences(of: "AsyncImage(", in: source) == 0, "\(path)")
        }
    }

    // MARK: - 429-E

    /// **429-E-1 — the placeholder is built from the policy, and it is
    /// labelled for VoiceOver.**
    ///
    /// A source read rather than a render read: the visible strings are pinned
    /// as VALUES by 429-A (`thePolicyCopyIsPinned`), and what this bar adds is
    /// that `RemoteImageView` uses those values rather than re-spelling them,
    /// and that the placeholder carries an `accessibilityLabel` at all. A
    /// button whose whole label is a host name and the words "Tap to load" is
    /// useless to VoiceOver without it.
    @Test(.enabled(if: RepoSourceWitness.repoSourcesAreReadable,
                   "reads the repo — simulator only"))
    func thePlaceholderIsBuiltFromThePolicyAndCarriesAnAccessibilityLabel() throws {
        let source = try RepoSourceWitness.source(Self.remoteImageViewPath)
        #expect(source.contains(".accessibilityLabel("))
        #expect(source.contains("RemoteImagePolicy.placeholderAccessibilityLabel("))
        #expect(source.contains("RemoteImagePolicy.placeholderTitle("))
        #expect(source.contains("RemoteImagePolicy.placeholderAction"))
    }

    /// **429-E-2 — no `Hermes` token in either new file.**
    ///
    /// Owen's standing naming ruling (#415): the app's outward identity is
    /// TALARIA; "Hermes" survives only where it means the HOST. A remote image
    /// from `images.example` has nothing to do with the host, so neither new
    /// file may name it.
    @Test(.enabled(if: RepoSourceWitness.repoSourcesAreReadable,
                   "reads the repo — simulator only"))
    func theNewFilesNameNoHost() throws {
        for path in [Self.remoteImageViewPath, Self.remoteImageLoadingPath] {
            let source = try RepoSourceWitness.source(path)
            #expect(!source.lowercased().contains("hermes"), "\(path)")
        }
    }
}
