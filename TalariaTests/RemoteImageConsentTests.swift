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

/// A loader that PARKS a load until it is cancelled, and counts both.
///
/// The instrument for "a retry that arrives mid-flight cancels the load it
/// drops": every other fake in this lane answers immediately, and a load that
/// is already finished can never be caught in flight — which is exactly the
/// blindness that let `retry(_:)` drop a live task uncancelled for a whole
/// lane without any bar noticing.
///
/// The park is BOUNDED (two seconds) on purpose: the mutation this pin exists
/// to red — drop the entry without cancelling it — must fail in two seconds
/// rather than hang the suite, which is the failure mode a `while true` park
/// would have.
private final class ParkingRemoteImageLoader: RemoteImageLoading {
    private let starts = OSAllocatedUnfairLock<Int>(initialState: 0)
    private let cancels = OSAllocatedUnfairLock<Int>(initialState: 0)
    var startCount: Int { starts.withLock { $0 } }
    var cancelCount: Int { cancels.withLock { $0 } }

    func load(_ url: URL) async throws -> UIImage {
        starts.withLock { $0 += 1 }
        do {
            try await Task.sleep(for: .seconds(2))
        } catch {
            cancels.withLock { $0 += 1 }
            throw error
        }
        return UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { context in
            UIColor.green.setFill()
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
    /// **The failure row's copy, as VALUES (2026-09-05).**
    ///
    /// #437-A introduced `failureTitle`, `failureAction` and the row's
    /// VoiceOver label with no value pin at all — the only user-visible copy
    /// in this feature that nothing held. The alt-text arm is the one with a
    /// claim behind it: the label leads with the alt text for the same reason
    /// `loadedAccessibilityLabel` does, and dropping it is the mutation this
    /// pin exists to red (the site half, that both modes actually pass it in,
    /// is `RemoteImageSitePinsTests.theFailureRowLabelCarriesTheAltText`).
    @Test func theFailureCopyIsPinned() {
        let host = RemoteImagePolicy.host(of: URL(string: "https://images.example/pixel.png")!)
        #expect(RemoteImagePolicy.failureTitle == "Image failed to load")
        #expect(RemoteImagePolicy.failureAction == "Tap to retry")
        #expect(RemoteImagePolicy.failureAccessibilityLabel(host: host, altText: "")
                == "Image from images.example failed to load. Tap to retry.")
        #expect(RemoteImagePolicy.failureAccessibilityLabel(host: host, altText: "chart")
                == "chart. Image from images.example failed to load. Tap to retry.",
                "the failure label must lead with the alt text, as the loaded label does")
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

    // MARK: - M1 (fix round 1, 2026-09-05) — a retry cannot leave a load running

    /// **`retry(_:)` cancels the in-flight task it drops.**
    ///
    /// `retry(_:)` has to drop the `inFlight` entry or the retry re-reads the
    /// same recorded `nil` and never reaches the loader (#437-A). Dropping it
    /// without cancelling is a different thing: the dropped `Task` keeps
    /// running, so one URL has two live fetches and the loser is still talking
    /// to a host the reader consented to ping ONCE — and its late `store(_:for:)`
    /// can land on top of whatever the retry produced.
    ///
    /// **Unreachable from today's UI, and that is the point.** The failure row
    /// only exists after the task finished, so `RemoteImageView` can never
    /// call this mid-flight. That is a property of the VIEW; this suite is
    /// about the STORE, whose API lets any caller retry at any moment. Making
    /// it structural here means the next call site cannot get it wrong.
    ///
    /// Mutation: change `inFlight.removeValue(forKey: key)?.cancel()` back to
    /// `inFlight[key] = nil` and all three expectations below red.
    @Test func retryCancelsALoadThatIsStillInFlight() async throws {
        let consent = RemoteImageConsent()
        let loader = ParkingRemoteImageLoader()
        let url = URL(string: "https://images.example/parked.png")!
        consent.approve(url)

        let first = consent.loadTask(for: url, using: loader)

        // Wait for the load to genuinely START. Without this the cancel could
        // land before the loader ever ran, and the arm would pass for the
        // wrong reason — nothing was in flight to cancel.
        var waited = 0
        while loader.startCount == 0 && waited < 200 {
            try await Task.sleep(for: .milliseconds(5))
            waited += 1
        }
        #expect(loader.startCount == 1,
                "the premise failed — no load was ever in flight, so this arm measures nothing")

        consent.retry(url)
        _ = await first.value

        #expect(first.isCancelled,
                "retry dropped a LIVE load without cancelling it — two fetches now race for one URL")
        #expect(loader.cancelCount == 1,
                "the dropped load ran to completion: starts \(loader.startCount), cancels \(loader.cancelCount)")
        #expect(consent.image(for: url) == nil,
                "the dropped load still stored its bytes, so it can overwrite the retry's own result")
    }
}
