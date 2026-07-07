import CoreLocation
import Foundation
import FoundationModels
import os

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
}

// MARK: - Tool event relay

/// Bridges FoundationModels tool invocations onto the existing
/// `StreamingUpdate.toolActivity` channel, so the #10/#11 tool-chip UI
/// renders local tool calls with zero ChatStore changes. The local backend
/// points `emit` at the live stream's continuation for the duration of a
/// turn; between turns it's nil and events drop harmlessly.
@MainActor
final class ToolEventRelay {
    var emit: ((ToolCallEvent) -> Void)?

    func started(_ name: String, detail: String? = nil) {
        emit?(ToolCallEvent(name: name, phase: .started, detail: detail))
    }

    func completed(_ name: String) {
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
    private let manager = CLLocationManager()
    private var authorizationContinuations: [CheckedContinuation<CLAuthorizationStatus, Never>] = []
    private var locationContinuations: [CheckedContinuation<CLLocation?, Never>] = []

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    /// Settled authorization status, prompting if not yet determined.
    func ensureAuthorization() async -> CLAuthorizationStatus {
        let status = manager.authorizationStatus
        guard status == .notDetermined else { return status }
        return await withCheckedContinuation { continuation in
            authorizationContinuations.append(continuation)
            manager.requestWhenInUseAuthorization()
        }
    }

    /// One-shot fix. A fix from the last two minutes is fresh enough for
    /// weather/places and skips the radio spin-up.
    func currentLocation() async -> CLLocation? {
        if let cached = manager.location, cached.timestamp.timeIntervalSinceNow > -120 {
            return cached
        }
        return await withCheckedContinuation { continuation in
            locationContinuations.append(continuation)
            manager.requestLocation()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            let status = self.manager.authorizationStatus
            guard status != .notDetermined else { return }
            let waiting = authorizationContinuations
            authorizationContinuations = []
            waiting.forEach { $0.resume(returning: status) }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let newest = locations.last
        Task { @MainActor in
            let waiting = locationContinuations
            locationContinuations = []
            waiting.forEach { $0.resume(returning: newest) }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            let waiting = locationContinuations
            locationContinuations = []
            waiting.forEach { $0.resume(returning: nil) }
        }
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
