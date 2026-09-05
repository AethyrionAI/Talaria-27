import Foundation
import os
import Testing
import UIKit

@testable import Talaria

/// Records every `load(_:)` and answers with a decodable image.
///
/// File-scope rather than nested, because `RemoteImageRenderTests` is
/// `@MainActor` and its fakes inherit that isolation; this suite needs a
/// loader it can hand to `loadTask` from a non-isolated context. Genuinely
/// `Sendable`: `OSAllocatedUnfairLock` is, and `UIImage` is `NS_SWIFT_SENDABLE`.
private final class RecordingRemoteImageLoader: RemoteImageLoading {
    private let recorded = OSAllocatedUnfairLock<[URL]>(initialState: [])
    var calls: [URL] { recorded.withLock { $0 } }

    func load(_ url: URL) async throws -> UIImage {
        recorded.withLock { $0.append(url) }
        return UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
    }
}

@Suite("429-A remote image consent")
@MainActor
struct RemoteImageConsentTests {
    @Test func approvalIsKeyedByURLNotBySegmentIdentity() throws {
        let markdown = "![chart](https://images.example/pixel.png)"
        let first = try #require(parseMarkdownSegments(markdown).first { if case .image = $0 { return true }; return false })
        let second = try #require(parseMarkdownSegments(markdown).first { if case .image = $0 { return true }; return false })
        #expect(first.id != second.id, "the premise: a re-parse mints a new segment id")
        guard case .image(_, let url, _) = first else { return }
        let consent = RemoteImageConsent()
        #expect(!consent.isApproved(url))
        consent.approve(url)
        #expect(consent.isApproved(url))
        guard case .image(_, let url2, _) = second else { return }
        #expect(consent.isApproved(url2), "same URL from a later parse must still be approved")
        #expect(!consent.isApproved(URL(string: "https://images.example/other.png")!))
    }
    @Test func thePolicyCopyIsPinned() {
        let host = RemoteImagePolicy.host(of: URL(string: "https://images.example/pixel.png?x=1")!)
        #expect(host == "images.example")
        #expect(RemoteImagePolicy.placeholderTitle(host: host) == "IMAGE · images.example")
        #expect(RemoteImagePolicy.placeholderAction == "Tap to load")
        #expect(RemoteImagePolicy.placeholderAccessibilityLabel(host: host) == "Image from images.example, not loaded. Tap to load.")
    }
    @Test func loadedImageRidesWithApprovalKeyedByURL() {
        let consent = RemoteImageConsent()
        let url = URL(string: "https://images.example/pixel.png")!
        let other = URL(string: "https://images.example/other.png")!
        #expect(consent.image(for: url) == nil)
        let image = UIImage()
        consent.store(image, for: url)
        #expect(consent.image(for: url) === image)
        #expect(consent.image(for: other) == nil)

        // approve(_:) alone must not populate `loaded`.
        let approvedOnly = RemoteImageConsent()
        approvedOnly.approve(other)
        #expect(approvedOnly.image(for: other) == nil)
    }

    // MARK: - 437-B — defence in depth on the loader

    /// **437-B — `loadTask` refuses a URL the reader has not approved.**
    ///
    /// #429 put the whole gate in `RemoteImageView.body`, and both call sites
    /// are correct today — which is exactly the state in which a third call
    /// site gets added without one. The store owns the approval set, so the
    /// store is where the refusal belongs; a view is then one of two places
    /// that has to be right rather than the only one.
    ///
    /// The second half is the part that is easy to get wrong: the refusal
    /// must NOT be registered in the single-flight registry. A cached "no"
    /// would make the reader's own tap a no-op for the rest of the launch —
    /// a fail-closed bug with no error message anywhere.
    @Test func loadTaskRefusesAnUnapprovedURL() async {
        let consent = RemoteImageConsent()
        let loader = RecordingRemoteImageLoader()
        let url = URL(string: "https://images.example/pixel.png")!

        let refused = await consent.loadTask(for: url, using: loader).value
        #expect(refused == nil, "an unapproved URL resolved to bytes")
        #expect(loader.calls.isEmpty,
                "the loader was called for a URL nobody approved: \(loader.calls.map(\.absoluteString))")
        #expect(consent.image(for: url) == nil)

        consent.approve(url)
        let loaded = await consent.loadTask(for: url, using: loader).value
        #expect(loaded != nil,
                "the refusal was cached — the reader's tap can no longer load this URL for the launch")
        #expect(loader.calls == [url], "expected exactly one real load after approval")
    }
}
