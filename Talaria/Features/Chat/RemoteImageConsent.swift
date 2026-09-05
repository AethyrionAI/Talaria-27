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

    // MARK: - A failure the reader can retry (#437-A)

    /// URLs whose load came back empty.
    ///
    /// This used to be `@State` on `RemoteImageView`, and that is what made a
    /// transient failure permanent: the view owned the fact, the store owned
    /// the finished task that caused it, and nothing could clear both. They
    /// have to be forgotten TOGETHER — so the fact lives here, next to the
    /// task.
    ///
    /// Observed (not `@ObservationIgnored`): the view's `body` reads it, and
    /// clearing it is what puts the spinner back.
    private(set) var failedLoads: Set<String> = []
    func hasFailed(_ url: URL) -> Bool { failedLoads.contains(url.absoluteString) }
    func recordFailure(for url: URL) { failedLoads.insert(url.absoluteString) }

    /// How many times this URL's load has been started, counted so a retried
    /// view gets a `.task(id:)` it has not seen before.
    ///
    /// Without it the retry would rest on SwiftUI re-inserting the progress
    /// branch and re-running a `.task` whose id never changed — plausibly true
    /// today, and not a property any bar could hold. Bumping a value the id is
    /// built from makes "the tap starts a new load" mechanical instead.
    private(set) var attempts: [String: Int] = [:]
    func attempt(for url: URL) -> Int { attempts[url.absoluteString] ?? 0 }

    /// The tap on the failure row: forget one failed load so the next render
    /// starts a real one.
    ///
    /// All four writes matter. `approved` is a belt — the failure row is only
    /// reachable past the gate, so this is idempotent, but it means the retry
    /// cannot be the thing that loads bytes for an unapproved URL.
    /// `failedLoads` puts the spinner back. `attempts` gives the view a fresh
    /// `.task` id. And dropping the `inFlight` entry is the one that actually
    /// costs a network call: the registry deliberately KEEPS finished tasks,
    /// failures included, so without this line the retry re-reads the same
    /// recorded `nil` and never reaches the loader at all — the failure row
    /// would be tappable and useless.
    func retry(_ url: URL) {
        let key = url.absoluteString
        approved.insert(key)
        failedLoads.remove(key)
        attempts[key, default: 0] += 1
        inFlight[key] = nil
    }

    /// The decoded bytes for an approved URL, without a second trip to the
    /// host when the image is already on the device (#437-D).
    ///
    /// `ImageViewerScreen`'s Save button used to re-fetch the URL. The reader
    /// had consented to ONE fetch; the second one told that host they were
    /// still looking, from a button labelled "Save", with no consent anywhere
    /// near it. Going through the registry makes the ordinary case free — the
    /// finished task is still there and hands back its result — and keeps the
    /// rare one (a memory warning purged the bytes) inside the same approval
    /// gate as every other load.
    func loadedImage(for url: URL, using loader: any RemoteImageLoading) async -> UIImage? {
        if let image = image(for: url) { return image }
        return await loadTask(for: url, using: loader).value
    }

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
    /// "one load per URL per launch" true of failures as well as successes.
    ///
    /// **#437-A corrects what this comment used to claim.** It said a
    /// transient failure simply is not retried within the launch — "a
    /// deliberate trade and not an oversight". It was an oversight: the
    /// `AsyncImage` this design replaced retried on every re-parse, so a
    /// blip that used to heal itself became permanent. Nothing about the
    /// registry changes; what changed is that `retry(_:)` can now drop one
    /// entry, and the failure row is the control that calls it. Retrying is
    /// still never automatic — an approved URL is still a beacon, and the
    /// reader decides when to ping it again.
    func loadTask(for url: URL, using loader: any RemoteImageLoading) -> Task<UIImage?, Never> {
        // #437-B — defence in depth. The gate lives in `RemoteImageView.body`
        // and both of today's call sites are correct; this is here so that a
        // third one added later cannot fetch by forgetting to ask. The
        // refusal is deliberately NOT registered in `inFlight`: a cached "no"
        // would turn the reader's own tap into a no-op for the rest of the
        // launch, fail-closed and silent.
        guard isApproved(url) else { return Task { nil } }
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
    ///
    /// `failedLoads` and `attempts` deliberately survive: they hold no bytes,
    /// and a URL that failed should keep showing its retry row rather than
    /// silently re-fetching because the system got short of memory.
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

    /// The loaded image's VoiceOver label (#437-C).
    ///
    /// The placeholder has named its host since #429; once the reader tapped,
    /// the label disappeared and the image became the only unlabelled image
    /// surface in the app. The host stays in the label after loading for the
    /// same reason it is in the placeholder: it is the fact the reader
    /// consented to, and a screen-reader user should not lose it by saying
    /// yes. Alt text leads when the author supplied it, because that is what
    /// the picture IS.
    static func loadedAccessibilityLabel(host: String, altText: String) -> String {
        altText.isEmpty ? "Image from \(host)" : "\(altText). Image from \(host)"
    }

    /// The failure row (#437-A). One spelling for both modes — the fullscreen
    /// viewer used to say "Failed to load image" and the inline row "Image
    /// failed to load", a difference nobody chose.
    static let failureTitle = "Image failed to load"
    static let failureAction = "Tap to retry"
    static func failureAccessibilityLabel(host: String) -> String {
        "Image from \(host) failed to load. Tap to retry."
    }
}
