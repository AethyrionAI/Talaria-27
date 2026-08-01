import CoreLocation
import Foundation
import FoundationModels
import os
import UIKit

/// Device tool belt v1 (#28): Swift `Tool` conformances handed to the local
/// brain's `LanguageModelSession` — the device-side mirror of the Hermes MCP
/// tools. This wave is the READ set (no side effects, no confirmation gate);
/// action tools with the shared confirm gate land in #29.
///
/// Honesty rules (real-data-only): a tool that can't answer says WHY — the
/// permission isn't granted, the sensor has no data, the network is down —
/// as its tool RESULT, so the model reacts conversationally instead of the
/// turn dying. Nothing is ever fabricated on a tool's behalf.
enum DeviceToolBelt {

    /// Assembles the read belt. Providers are closures so the belt can be
    /// built before the stores it reads from (AppContainer wires them after
    /// construction, same pattern as the router's conversation lookup).
    @MainActor
    static func makeReadTools(
        relay: ToolEventRelay,
        conversationProvider: @escaping @MainActor () -> Conversation?,
        sessionCacheProvider: @escaping @MainActor () -> [ConversationSearchTool.CachedSession],
        spotlightEnabledProvider: @escaping @MainActor () -> Bool
    ) -> [any Tool] {
        let location = DeviceLocationProvider()
        return [
            DeviceHealthTool(relay: relay),
            LocationTool(relay: relay, location: location),
            MotionTool(relay: relay),
            CalendarReadTool(relay: relay),
            ReminderReadTool(relay: relay),
            WeatherTool(relay: relay, location: location),
            PlacesTool(relay: relay, location: location),
            ContactsTool(relay: relay),
            DeviceStatusTool(relay: relay),
            ImageTextTool(relay: relay, conversationProvider: conversationProvider),
            BarcodeReaderTool(relay: relay, conversationProvider: conversationProvider),
            ConversationSearchTool(
                relay: relay,
                conversationProvider: conversationProvider,
                sessionCacheProvider: sessionCacheProvider,
                spotlightEnabledProvider: spotlightEnabledProvider
            ),
        ]
    }

    /// Assembles the ACTION belt (#29) — side-effecting tools, every one
    /// behind the shared ToolConfirmationCenter gate. The model can never
    /// silently mutate the phone.
    @MainActor
    static func makeActionTools(
        relay: ToolEventRelay,
        confirmations: ToolConfirmationCenter,
        alarmService: AlarmService
    ) -> [any Tool] {
        [
            ReminderCreateTool(relay: relay, confirmations: confirmations),
            CalendarEventTool(relay: relay, confirmations: confirmations),
            AlarmTool(relay: relay, confirmations: confirmations, alarmService: alarmService),
        ]
    }

    /// #200: the action-tool names as ONE list for the battery capture
    /// surfaces (the export's confirm=none synthesis, the drill-down
    /// display). Pinned against `makeActionTools` by test so it can never
    /// drift from the real belt.
    static let actionToolNames: Set<String> = ["createReminder", "createCalendarEvent", "scheduleAlarm"]

    /// The belt as it should be OFFERED for one turn (#176). Vision tools come
    /// off when the conversation carries no image at all.
    ///
    /// This is availability gating, chosen over prompt-tuning because it is
    /// structural: a tool that isn't in the session's tool list cannot be
    /// selected, however the model feels about it. The reported failure was
    /// `readImageText` firing on "Write a haiku about rain" — the belt handed
    /// the model an OCR tool and there was nothing to read.
    ///
    /// Everything else passes through in place. The four health/motion calls
    /// seen on the same session were APPROPRIATE; this narrows selection, it
    /// does not redesign the belt.
    static func offeredTools(from belt: [any Tool], hasImageInContext: Bool) -> [any Tool] {
        guard !hasImageInContext else { return belt }
        return belt.filter { !($0 is any ImageDependentTool) }
    }
}

// MARK: - Context-conditioned tools

/// A tool that can only do its job when the conversation carries an image
/// (#176). `DeviceToolBelt.offeredTools` withholds these when there is
/// nothing to look at.
protocol ImageDependentTool {}

// MARK: - Tool event relay

/// Bridges FoundationModels tool invocations onto the existing
/// `StreamingUpdate.toolActivity` channel, so the #10/#11 tool-chip UI
/// renders local tool calls with zero ChatStore changes. The local backend
/// points `emit` at the live stream's continuation for the duration of a
/// turn; between turns it's nil and events drop harmlessly.
@MainActor
final class ToolEventRelay {
    var emit: ((ToolCallEvent) -> Void)?

    #if DEBUG
    /// #196 battery: when non-nil, EVERY tool start logs a classifiable
    /// notice carrying this trial tag — read tools included, which the
    /// confirmation gate never sees. (The first battery's blind spot: two
    /// trials leaked ConversationSearch output into replies with no log
    /// line anywhere.) Nil in every normal run; the battery sets it per
    /// trial and clears it at the end of the run.
    static var batteryTrialTag: String?
    private static let batteryLogger = Logger(subsystem: "org.aethyrion.talaria", category: "LocalChatBackend")
    #endif

    func started(_ name: String, detail: String? = nil) {
        #if DEBUG
        if let tag = Self.batteryTrialTag {
            // One emit path for every battery line (#196 battery 4):
            // os_log + flushed stdout + the container file sink.
            LocalChatBackend.batteryEmit("battery: tool=\(name) \(tag) detail=\(String((detail ?? "").prefix(80)))")
            // Results-page store gets the UNTRUNCATED detail — the 80-char
            // prefix above is Console-line width, not a capture budget.
            LocalChatBackend.batteryRecorder.recordToolCall(name: name, detail: detail ?? "")
        }
        #endif
        emit?(ToolCallEvent(name: name, phase: .started, detail: detail))
    }

    /// #212: `result` is what the tool RETURNED, recorded into the battery
    /// store only. It never reaches the transcript or the UI — the completed
    /// event is unchanged — so this cannot leak internals into a reply the way
    /// #197's tool dump did.
    func completed(_ name: String, result: String? = nil) {
        #if DEBUG
        if Self.batteryTrialTag != nil, let result {
            LocalChatBackend.batteryRecorder.recordToolResult(name: name, result: result)
        }
        #endif
        emit?(ToolCallEvent(name: name, phase: .completed))
    }
}

// MARK: - Shared one-shot location

/// One CLLocationManager shared by the location-flavored tools (location /
/// weather / places). Requests when-in-use authorization on FIRST USE —
/// that's #31's contextual priming: the permission prompt appears while the
/// user is asking a location question, never in an up-front wall.
@MainActor
final class DeviceLocationProvider: NSObject, CLLocationManagerDelegate {

    /// #203 (2A): the seam. Everything the waiting policies ask of
    /// CoreLocation, as MainActor closures — production wires all four to one
    /// concrete CLLocationManager; tests wire them to a script. The policies
    /// themselves (the fix deadline + generation counting, the
    /// dismissed-dialog foreground trigger, the unbounded human wait) sit
    /// above this line, which is what makes them drivable from a test at
    /// all. Closures rather than a protocol for the same reason the belt's
    /// providers are closures — and so the non-Sendable manager stays
    /// captured inside them, never crossing a concurrency boundary.
    struct Seam {
        var authorizationStatus: @MainActor () -> CLAuthorizationStatus
        var cachedLocation: @MainActor () -> CLLocation?
        var requestWhenInUseAuthorization: @MainActor () -> Void
        var requestLocation: @MainActor () -> Void
    }

    private let seam: Seam
    private let notificationCenter: NotificationCenter
    /// The deadline THIS instance arms. Production always gets
    /// `Self.fixDeadline`; tests shorten it to prove the deadline path fires.
    private let fixDeadline: Duration
    private var authorizationContinuations: [CheckedContinuation<CLAuthorizationStatus, Never>] = []
    private var locationContinuations: [CheckedContinuation<CLLocation?, Never>] = []
    /// #203: bumped every time waiters are resolved, so a fired deadline can
    /// only ever affect the request it was armed for.
    private var locationGeneration = 0
    /// #203 (2A): armed only while an authorization prompt is pending. Read
    /// access is internal so the teardown tests can see it; only this class
    /// writes it.
    private(set) var foregroundObserver: NSObjectProtocol?

    /// Production wiring: one concrete CLLocationManager behind the seam,
    /// this object as its delegate. This initializer is the one line of the
    /// class no unit test can reach — everything behind it is driven through
    /// the same entry points CoreLocation uses.
    override convenience init() {
        let manager = CLLocationManager()
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        self.init(seam: Seam(
            authorizationStatus: { manager.authorizationStatus },
            cachedLocation: { manager.location },
            requestWhenInUseAuthorization: { manager.requestWhenInUseAuthorization() },
            requestLocation: { manager.requestLocation() }
        ))
        manager.delegate = self
    }

    init(
        seam: Seam,
        notificationCenter: NotificationCenter = .default,
        fixDeadline: Duration = DeviceLocationProvider.fixDeadline
    ) {
        self.seam = seam
        self.notificationCenter = notificationCenter
        self.fixDeadline = fixDeadline
        super.init()
    }

    /// Settled authorization status, prompting if not yet determined.
    ///
    /// #203 (2A, Owen's call 2026-07-31): still UNBOUNDED by any clock — a
    /// machine deadline on a human reading a system dialog is unfair, and
    /// that reasoning stands. What is NOT fair is parking forever when the
    /// human has visibly walked away: `locationManagerDidChangeAuthorization`
    /// returns early while the status is `.notDetermined`, so a dialog
    /// dismissed WITHOUT an answer left the waiter pending with no
    /// resolution path and the turn spun.
    ///
    /// The trigger is the FOREGROUND TRANSITION, not a timer: if the app
    /// comes back with the status still undetermined, the user dismissed the
    /// dialog. The waiter resolves `.notDetermined`, every caller already
    /// renders that honestly as location-unavailable, and the turn finishes
    /// with a sentence instead of a hang — the shape #202D promoted.
    func ensureAuthorization() async -> CLAuthorizationStatus {
        let status = seam.authorizationStatus()
        guard status == .notDetermined else { return status }
        return await withCheckedContinuation { continuation in
            authorizationContinuations.append(continuation)
            observeForegroundForDismissedDialog()
            seam.requestWhenInUseAuthorization()
        }
    }

    /// One observer per pending prompt. Resolving is idempotent — the
    /// delegate may also fire, and whichever lands first empties the queue.
    private func observeForegroundForDismissedDialog() {
        guard foregroundObserver == nil else { return }
        foregroundObserver = notificationCenter.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.resolveAuthorizationIfDialogWasDismissed() }
        }
    }

    func resolveAuthorizationIfDialogWasDismissed() {
        if let foregroundObserver {
            notificationCenter.removeObserver(foregroundObserver)
            self.foregroundObserver = nil
        }
        // Only a still-undetermined status means the dialog was dismissed
        // without an answer. A real decision resolves through the delegate.
        guard seam.authorizationStatus() == .notDetermined else { return }
        let waiting = authorizationContinuations
        authorizationContinuations = []
        waiting.forEach { $0.resume(returning: .notDetermined) }
    }

    /// How long a one-shot fix may take before the tools give up. Apple's
    /// `requestLocation()` normally delivers a fix or an error well inside
    /// this; the deadline exists for when it delivers NEITHER.
    static let fixDeadline: Duration = .seconds(10)

    /// One-shot fix. A fix from the last two minutes is fresh enough for
    /// weather/places and skips the radio spin-up.
    ///
    /// #203 (SHIP BLOCKER, Hermes audit): this used to park a continuation with
    /// NO deadline. If CoreLocation delivered neither `didUpdateLocations` nor
    /// `didFailWithError` — plausible under beta thermal pressure — the waiter
    /// never resumed, and because a hung TOOL is not cancellable (#200Y) and the
    /// PRODUCTION stream loop has no guillotine (that is battery-only), the
    /// user's chat turn spun forever with no recovery. Now bounded: on deadline
    /// the waiters resume `nil`, which every caller already renders honestly as
    /// "couldn't get a location fix right now".
    ///
    /// `ensureAuthorization()` is deliberately left UNBOUNDED: it waits on a
    /// human reading a system dialog, and no machine deadline is fair to that.
    func currentLocation() async -> CLLocation? {
        if let cached = seam.cachedLocation(), cached.timestamp.timeIntervalSinceNow > -120 {
            return cached
        }
        let generation = locationGeneration
        let deadline = fixDeadline
        // #198: no `await` on the resolve call. This class is @MainActor, so
        // the unstructured Task inherits that isolation and the hop the `await`
        // implied never happens — the compiler flags it, and leaving it in
        // misdescribes the concurrency model to the next reader.
        Task { [weak self] in
            try? await Task.sleep(for: deadline)
            self?.failLocationWaitersIfStillPending(generation: generation)
        }
        return await withCheckedContinuation { continuation in
            locationContinuations.append(continuation)
            seam.requestLocation()
        }
    }

    /// Resumes any waiter still parked from `generation` with nil. Generation
    /// counting is what keeps a late deadline from cancelling a LATER request's
    /// waiters — the bug a naive timeout would introduce. Internal (not
    /// private) so tests can fire a STALE deadline deterministically instead
    /// of racing real timers.
    func failLocationWaitersIfStillPending(generation: Int) {
        guard generation == locationGeneration, !locationContinuations.isEmpty else { return }
        let waiting = locationContinuations
        locationContinuations = []
        locationGeneration += 1
        waiting.forEach { $0.resume(returning: nil) }
    }

    /// The MainActor half of `locationManagerDidChangeAuthorization`, split
    /// out so tests drive a real decision through the same code CoreLocation
    /// does. A decided status resolves every waiter and tears down the
    /// dismissed-dialog observer; `.notDetermined` is not a decision.
    func handleAuthorizationChange() {
        let status = seam.authorizationStatus()
        guard status != .notDetermined else { return }
        if let observer = foregroundObserver {
            notificationCenter.removeObserver(observer)
            foregroundObserver = nil
        }
        let waiting = authorizationContinuations
        authorizationContinuations = []
        waiting.forEach { $0.resume(returning: status) }
    }

    /// The MainActor half of both fix-delivery callbacks: an answer — a fix,
    /// or nil for a definitive failure — resolves every parked waiter and
    /// bumps the generation so any still-armed deadline goes stale.
    func resolveLocationWaiters(with location: CLLocation?) {
        let waiting = locationContinuations
        locationContinuations = []
        locationGeneration += 1
        waiting.forEach { $0.resume(returning: location) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in self.handleAuthorizationChange() }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let newest = locations.last
        Task { @MainActor in self.resolveLocationWaiters(with: newest) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.resolveLocationWaiters(with: nil) }
    }
}

// MARK: - Shared formatting

/// Pure formatting helpers shared across the belt — kept static + Foundation
/// only so they're unit-testable without any framework entitlements.
enum DeviceToolFormat {

    /// "7h 24m" from fractional hours.
    static func hoursMinutes(fromHours hours: Double) -> String {
        let totalMinutes = Int((hours * 60).rounded())
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        if h == 0 { return "\(m)m" }
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    /// "512 MB free of 128 GB" — nil-safe on either side.
    static func storageLine(availableBytes: Int64?, totalBytes: Int64?) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        let free = availableBytes.map { formatter.string(fromByteCount: $0) } ?? "unknown"
        guard let totalBytes else { return "Storage: \(free) free" }
        return "Storage: \(free) free of \(formatter.string(fromByteCount: totalBytes))"
    }

    /// Compact one-line snippet around the first case-insensitive match of
    /// `term` in `text` — the conversation-search result surface. Nil when
    /// the term doesn't occur.
    static func snippet(around term: String, in text: String, radius: Int = 60) -> String? {
        guard let range = text.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) else {
            return nil
        }
        let start = text.index(range.lowerBound, offsetBy: -radius, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(range.upperBound, offsetBy: radius, limitedBy: text.endIndex) ?? text.endIndex
        var line = String(text[start ..< end])
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
        if start > text.startIndex { line = "…" + line }
        if end < text.endIndex { line += "…" }
        return line
    }
}
