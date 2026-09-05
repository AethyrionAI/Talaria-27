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

    // MARK: - One load per URL per launch (#429 Task 2)

    /// The single-flight registry, and the ONE dedup mechanism in this lane.
    ///
    /// A streaming transcript re-parses on every delta and the parser mints a
    /// fresh segment id each time, so each delta gives the image a new SwiftUI
    /// identity and a new `.task`. Task 0 measured what that costs today:
    /// three growing deltas over one hosting controller issued three separate
    /// requests for one unchanged URL. Duplicates of the same URL in a SINGLE
    /// render are the harder half — they all reach `.task` before any load
    /// finishes, so a per-view "have I got it yet?" check cannot see them.
    /// Keying the in-flight `Task` by URL covers both.
    ///
    /// `@ObservationIgnored` deliberately: nothing reads this from a view
    /// body, and an observed write here would invalidate every remote image on
    /// screen for a bookkeeping change. `loaded` is the observed channel — a
    /// completed load writes there, and that is what redraws the image.
    @ObservationIgnored
    private var inFlight: [String: Task<UIImage?, Never>] = [:]

    /// The load for `url`, started at most once per launch.
    ///
    /// The completed task is KEPT, not cleared: a caller arriving after the
    /// load finished gets the same finished task and its recorded result
    /// (`nil` for a failure) without a second network call. That is what makes
    /// "one load per URL per launch" true of failures as well as successes —
    /// at the cost that a transient failure is not retried within the launch,
    /// which is a deliberate trade and not an oversight.
    func loadTask(for url: URL, using loader: any RemoteImageLoading) -> Task<UIImage?, Never> {
        if let existing = inFlight[url.absoluteString] { return existing }
        observeMemoryWarnings()
        let task = Task { [weak self] in
            let image = try? await loader.load(url)
            if let image { self?.store(image, for: url) }
            return image
        }
        // Registered synchronously, before the task's first suspension point,
        // so a same-frame duplicate always finds it.
        inFlight[url.absoluteString] = task
        return task
    }

    /// Drops every decoded image and every load record; approval survives.
    ///
    /// Owen's ruling constrains what may be FETCHED without a tap, not how
    /// long the bytes are kept, so this bounds `loaded` without touching
    /// `approved`. After a purge an already-approved image re-fetches on its
    /// next render — deliberately, because the alternative is holding
    /// full-size decoded bitmaps for the life of the process. So the
    /// "one load per URL per launch" property is precisely: one load per URL
    /// per launch, absent a memory warning.
    ///
    /// `inFlight` goes with `loaded` because a finished task still holds its
    /// `UIImage` result; keeping the registry while emptying the dictionary
    /// would free nothing.
    func purgeDecodedImages() {
        loaded.removeAll()
        inFlight.removeAll()
    }

    @ObservationIgnored
    private nonisolated(unsafe) var memoryWarningObserver: (any NSObjectProtocol)?

    /// Registered lazily on the first real load, so an instance that only ever
    /// answers `isApproved` (every unit test of this type) registers nothing.
    private func observeMemoryWarnings() {
        guard memoryWarningObserver == nil else { return }
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Hop rather than `assumeIsolated`: a MainActor-formed completion
            // run on a framework's own queue traps on this runtime.
            Task { @MainActor in self?.purgeDecodedImages() }
        }
    }

    deinit {
        if let memoryWarningObserver { NotificationCenter.default.removeObserver(memoryWarningObserver) }
    }
}

extension EnvironmentValues { @Entry var remoteImageConsent: RemoteImageConsent = .shared }

enum RemoteImagePolicy {
    static func host(of url: URL) -> String { url.host ?? url.absoluteString }
    static func placeholderTitle(host: String) -> String { "IMAGE · \(host)" }
    static let placeholderAction = "Tap to load"
    static func placeholderAccessibilityLabel(host: String) -> String { "Image from \(host), not loaded. Tap to load." }
}
