import Foundation
import Testing
import UIKit

@testable import Talaria

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
}
