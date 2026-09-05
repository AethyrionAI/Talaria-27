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

    /// The shipping-source enumerator now lives in `RepoSourceWitness`
    /// (#437 item 5) — this suite's private copy and `NamingSweepTests`' were
    /// byte-identical, and the copy that used to sit here said so.
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
        let sources = try RepoSourceWitness.shippingSources()
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

    /// **I-3 (final review, 2026-09-04) — the placeholder's tap grants
    /// consent.**
    ///
    /// Every render test in this lane approves programmatically
    /// (`consent.approve(url)` called directly, `RemoteImageRenderTests.swift`),
    /// so no automated arm anywhere in the suite ever drives the placeholder
    /// `Button`'s own action. A refactor that dropped `consent.approve(url)`
    /// from that action — or wired it behind a `Mode`-conditional branch —
    /// would leave all 23 of this lane's other tests green, and the app would
    /// ship a placeholder that can never load an image. Fails closed, so it
    /// is a feature-dead hole rather than a privacy hole, but it is a hole
    /// with full green cover today.
    ///
    /// **Positional, not a whole-file `contains`.** `Button` occurs twice in
    /// this file — the placeholder (owning `placeholderTitle`/
    /// `placeholderAction`) and the loaded-image tap-to-open (`onOpen?()`).
    /// A bare `source.contains("consent.approve(url)")` cannot tell which
    /// `Button` it lives in, so this locates the nearest `Button` that
    /// PRECEDES the placeholder's own labels and requires the call inside
    /// that window — the span between the `Button`'s opening and its label
    /// closure, which is exactly where the placeholder's action lives. Both
    /// anchors are `try #require`d, so a rename of either symbol fails loud
    /// rather than the pin silently matching nothing.
    @Test(.enabled(if: RepoSourceWitness.repoSourcesAreReadable,
                   "reads the repo — simulator only"))
    func thePlaceholderButtonActionApprovesConsent() throws {
        let source = try RepoSourceWitness.source(Self.remoteImageViewPath)

        let labelAnchor = try #require(
            source.range(of: "RemoteImagePolicy.placeholderTitle("),
            "cannot find the placeholder's title label — this pin no longer matches the source"
        )

        let precedingSource = source[source.startIndex..<labelAnchor.lowerBound]
        let buttonAnchor = try #require(
            precedingSource.range(of: "Button", options: .backwards),
            "cannot find a Button preceding the placeholder's labels — this pin no longer matches the source"
        )

        let window = source[buttonAnchor.lowerBound..<labelAnchor.lowerBound]
        #expect(window.contains("consent.approve(url)"),
                "the placeholder Button's action must call consent.approve(url) directly — window was: \(window)")
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

    // MARK: - 437-A (source half)

    /// **437-A — the failure row is a `Button` whose action retries.**
    ///
    /// The behavioural half lives in `RemoteImageRenderTests` and counts a
    /// second loader call after `consent.retry(url)`. This half pins the wire
    /// between the two: that the row the reader actually sees is a control
    /// they can press, and that pressing it calls the same method the render
    /// arm drives. Without it a refactor could keep `retry(_:)` working
    /// perfectly and still ship a dead `HStack` — the shape of I-3's hole,
    /// one level down.
    ///
    /// Bounded on `failureRow` rather than a whole-file `contains`, because
    /// `Button` occurs three times in this file (placeholder, loaded-image
    /// tap-to-open, failure row) and only one of them is this claim.
    @Test(.enabled(if: RepoSourceWitness.repoSourcesAreReadable,
                   "reads the repo — simulator only"))
    func theFailureRowIsAButtonThatRetries() throws {
        let body = try RepoSourceWitness.functionBody(
            from: "private var failureRow",
            in: Self.remoteImageViewPath,
            boundary: "\n    private "
        )
        #expect(body.contains("Button"),
                "the failure row must be tappable — a failed load is otherwise dead for the launch")
        #expect(body.contains("consent.retry(url)"),
                "the failure row's action must call consent.retry(url) — body was: \(body)")
    }

    // MARK: - 437-C (source half)

    /// **437-C — the LOADED image carries an accessibility label naming the
    /// host.**
    ///
    /// The placeholder has had one since #429 (`429-E-1`, above); after the
    /// tap the label disappeared, leaving the only unlabelled image surface in
    /// the app on the branch a reader reaches by consenting. Bounded on
    /// `loadedImage(` so the placeholder's own label cannot satisfy it.
    @Test(.enabled(if: RepoSourceWitness.repoSourcesAreReadable,
                   "reads the repo — simulator only"))
    func theLoadedImageIsLabelledFromThePolicy() throws {
        let body = try RepoSourceWitness.functionBody(
            from: "private func loadedImage(",
            in: Self.remoteImageViewPath,
            boundary: "\n    private "
        )
        #expect(body.contains(".accessibilityLabel("),
                "the loaded image is unlabelled for VoiceOver — body was: \(body)")
        #expect(body.contains("RemoteImagePolicy.loadedAccessibilityLabel("),
                "the label must come from the policy, not be re-spelled at the call site")
    }

    // MARK: - 437-D (source half)

    /// **437-D — saving to Photos uses the bytes already on the device.**
    ///
    /// The reader consented to ONE fetch of this URL. Saving it re-fetched,
    /// so the host learned a second time — a beacon fired by a button whose
    /// label says "Save", with no second consent anywhere near it. The
    /// counting half is in `RemoteImageRenderTests`; this half is what the
    /// "restore the re-fetch" mutation reds, because a private method on a
    /// `View` cannot be called from a test.
    @Test(.enabled(if: RepoSourceWitness.repoSourcesAreReadable,
                   "reads the repo — simulator only"))
    func savingToPhotosDoesNotRefetch() throws {
        let body = try RepoSourceWitness.functionBody(
            from: "private func downloadToPhotos()",
            in: Self.markdownContentViewPath,
            boundary: "\n// MARK:"
        )
        #expect(body.contains("consent.loadedImage("),
                "save must reuse the loaded bytes — body was: \(body)")
        #expect(!body.contains("URLSession"),
                "save re-fetches over the network after the reader already consented once")
    }

    // MARK: - 437-F

    /// The needles a hand-rolled remote image fetch has to write.
    ///
    /// `.data(from:` carries the leading dot on purpose: bare `data(from:`
    /// also matches `mergeConversationMetadata(from:` (three sites in
    /// `ChatStore.swift`), and a ban that reds on an unrelated method name is
    /// a ban the next lane deletes. `.data(for:` is deliberately absent —
    /// `ServerSettingsScreen` posts a `URLRequest` that way and it is not an
    /// image fetch; this ban is about fetching bytes BY URL and turning them
    /// into a picture.
    private static let remoteFetchNeedles = [
        ".data(from:",
        "dataTask(with:",
        "UIImage(contentsOf",
        "Image(url:"
    ]

    /// **437-F — only `RemoteImageLoading.swift` may fetch image bytes.**
    ///
    /// #429's ban was the literal string `AsyncImage(`, which is exactly one
    /// spelling of the hazard. A future view that hand-rolled
    /// `URLSession.shared.data(from: url)` + `UIImage(data:)` would fetch at
    /// render, obey no consent, and pass every bar in this file — the ban has
    /// to name the OPERATION, not the API that happened to be used in
    /// September.
    ///
    /// The exemption is one file, and the last check is what keeps it from
    /// being vacuous: if the loader ever stops fetching, the exemption is
    /// protecting nothing and this says so rather than quietly widening.
    @Test(.enabled(if: RepoSourceWitness.repoSourcesAreReadable,
                   "reads the repo — simulator only"))
    func onlyTheLoaderFetchesRemoteImageBytes() throws {
        let sources = try RepoSourceWitness.shippingSources()
        var offenders: [String] = []
        for source in sources where !source.path.hasSuffix("/RemoteImageLoading.swift") {
            for needle in Self.remoteFetchNeedles where source.text.contains(needle) {
                offenders.append("\(needle) in \(source.path)")
            }
        }
        #expect(offenders.isEmpty,
                "remote bytes must be fetched only by RemoteImageLoading, which the consent gate owns — found: \(offenders)")

        let loader = try RepoSourceWitness.source(Self.remoteImageLoadingPath)
        #expect(loader.contains(".data(from:"),
                "the exempt file no longer fetches — this ban is exempting nothing, re-point it")
    }

    // MARK: - 429-P

    /// **429-P — the privacy page names image hosts and the tap-to-load rule.**
    ///
    /// `docs/` is the live GitHub Pages root — merging this PR publishes it —
    /// so the sentence itself is held for Owen's read, but the pin that it
    /// landed is a normal RED-first test like any other bar in this lane.
    @Test(.enabled(if: RepoSourceWitness.repoSourcesAreReadable,
                   "reads the repo — simulator only"))
    func privacyPageNamesTheTapToLoadRule() throws {
        let source = try RepoSourceWitness.source("docs/privacy.html")
        #expect(source.contains("only when you tap that image to load it"))
    }
}
