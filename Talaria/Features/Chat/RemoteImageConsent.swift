import SwiftUI
import UIKit

/// Per-launch, per-URL consent for loading a remote Markdown image (#429).
///
/// Approval is keyed by the URL's absolute string, never by a
/// `MarkdownSegment.image`'s id — a streaming re-parse mints a new segment id
/// on every delta (`MarkdownParser.swift:8`, `case image(id: UUID = UUID(),
/// url:, altText:)`), so keying on the id would forget an already-approved
/// image the moment the transcript re-renders. Nothing here persists past the
/// process: a fresh launch starts with an empty `approved` set.
///
/// `loaded` rides alongside `approved` (added for Task 2, per Task 0's
/// design-B measurement): a streaming transcript re-parses on every delta, so
/// the image loader fetches an approved URL once and stores the result here
/// rather than re-fetching it on each subsequent render.
@MainActor @Observable
final class RemoteImageConsent {
    // `nonisolated` on `shared` and `init` so `@Entry`'s generated
    // `EnvironmentKey.defaultValue` (itself nonisolated, per SE-0475) can
    // reference `.shared` below without hopping actors — the class's other
    // members stay `@MainActor`-isolated as declared.
    nonisolated static let shared = RemoteImageConsent()
    nonisolated init() {}

    private(set) var approved: Set<String> = []          // absolute URL strings, per launch, never persisted
    func approve(_ url: URL) { approved.insert(url.absoluteString) }
    func isApproved(_ url: URL) -> Bool { approved.contains(url.absoluteString) }

    private(set) var loaded: [String: UIImage] = [:]
    func store(_ image: UIImage, for url: URL) { loaded[url.absoluteString] = image }
    func image(for url: URL) -> UIImage? { loaded[url.absoluteString] }
}

extension EnvironmentValues { @Entry var remoteImageConsent: RemoteImageConsent = .shared }

enum RemoteImagePolicy {
    static func host(of url: URL) -> String { url.host ?? url.absoluteString }
    static func placeholderTitle(host: String) -> String { "IMAGE · \(host)" }
    static let placeholderAction = "Tap to load"
    static func placeholderAccessibilityLabel(host: String) -> String { "Image from \(host), not loaded. Tap to load." }
}
