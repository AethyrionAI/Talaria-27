import SwiftUI
import UIKit

/// How a remote Markdown image's bytes are fetched (#429).
///
/// **This seam exists because of a measurement, not a preference.** Task 0
/// hosted a `MarkdownContentView` in a key window with a `URLProtocol`
/// registered process-wide and watched `AsyncImage` put a request on the wire
/// ~29 ms after `makeKeyAndVisible()` — with no tap and no consent — that the
/// registered protocol never saw. `AsyncImage` loads through a private
/// `URLSession` built from its own `URLSessionConfiguration`, and a
/// configuration-backed session consults only `configuration.protocolClasses`,
/// never the globally registered list. It exposes no session, no configuration
/// and no delegate.
///
/// So `AsyncImage` is ungateable (nothing can stop it fetching at render) AND
/// unobservable (no in-process counter can prove it did not). This protocol
/// replaces both properties at once: production loads through
/// `URLSessionRemoteImageLoader`, and a test injects a counter and reads a
/// number that means something.
protocol RemoteImageLoading: Sendable {
    func load(_ url: URL) async throws -> UIImage
}

enum RemoteImageLoadError: Error {
    /// Bytes arrived, but `UIImage` cannot decode them. Distinguished from a
    /// transport error so the failure row is not blamed on the network.
    case undecodable
}

/// The shipping loader: one `URLSession.shared` fetch, decoded once.
struct URLSessionRemoteImageLoader: RemoteImageLoading {
    func load(_ url: URL) async throws -> UIImage {
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let image = UIImage(data: data) else { throw RemoteImageLoadError.undecodable }
        return image
    }
}

extension EnvironmentValues {
    @Entry var remoteImageLoader: any RemoteImageLoading = URLSessionRemoteImageLoader()
}
