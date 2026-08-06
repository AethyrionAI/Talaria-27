import Foundation

/// #251-2A: the read seam the phone-query catalog dispatches through.
///
/// It exists so the gate logic is testable without HealthKit, EventKit,
/// WeatherKit or a location fix — everything below this line is the belt's
/// own machinery and stays device-verified. `@MainActor` because the belt's
/// relay and location provider both are; the reads themselves are `async` and
/// hop off on their own, exactly as a belt tool call does.
@MainActor
protocol PhoneQueryReader {
    func location(relay: ToolEventRelay) async throws -> String
    func health(metric: String?, relay: ToolEventRelay) async throws -> String
    func motion(relay: ToolEventRelay) async throws -> String
    func weather(relay: ToolEventRelay) async throws -> String
    func calendar(daysAhead: Int, relay: ToolEventRelay) async throws -> String
    func reminders(relay: ToolEventRelay) async throws -> String
    func deviceStatus() async -> String
}

/// The production reader: every method is a straight call into the SAME
/// static the #28 belt tool calls, so a phone query and a local turn cannot
/// answer the same question two different ways — including the honest
/// "permission not granted" / "no data" strings, which are the answer here
/// too rather than an error.
@MainActor
final class LivePhoneQueryReader: PhoneQueryReader {
    /// One provider for both location-flavored reads, matching the belt's
    /// single shared `DeviceLocationProvider` (#31 contextual priming: the
    /// prompt appears on first use, never up front).
    private let location: DeviceLocationProvider

    /// Injected so the app hands over the SAME provider the #28 belt already
    /// holds (Task 11 ruling): two `DeviceLocationProvider`s mean two
    /// `CLLocationManager`s with two independent delegates, authorization
    /// states and in-flight fixes — one device answering itself twice. The
    /// default keeps standalone construction (tests, previews) valid.
    init(location: DeviceLocationProvider = DeviceLocationProvider()) {
        self.location = location
    }

    func location(relay: ToolEventRelay) async throws -> String {
        try await LocationTool.performLocationRead(relay: relay, location: location, name: "currentLocation")
    }

    func health(metric: String?, relay: ToolEventRelay) async throws -> String {
        try await DeviceHealthTool.performRead(rawMetric: metric, relay: relay, name: "readHealth")
    }

    func motion(relay: ToolEventRelay) async throws -> String {
        try await MotionTool.performMotionRead(relay: relay, name: "readMotion")
    }

    /// Deliberately weather HERE — no place is threaded through from a query.
    /// That keeps this a location-derived read, which is what lets it sit
    /// honestly behind the location toggle.
    func weather(relay: ToolEventRelay) async throws -> String {
        try await WeatherTool.performLookup(rawPlace: nil, relay: relay, location: location, name: "currentWeather")
    }

    func calendar(daysAhead: Int, relay: ToolEventRelay) async throws -> String {
        try await CalendarReadTool.performRead(rawDaysAhead: daysAhead, relay: relay, name: "readCalendar")
    }

    func reminders(relay: ToolEventRelay) async throws -> String {
        try await ReminderReadTool.performRead(relay: relay, name: "readReminders")
    }

    func deviceStatus() async -> String {
        DeviceStatusTool.statusReport()
    }
}

/// #251-2A: answers the gateway's structured phone queries using the SAME
/// read machinery the on-device belt uses, behind the SAME privacy gates
/// (spec §2.2).
///
/// Two rules shape the whole type:
///
/// 1. **The gate is checked BEFORE the read, never after.** A denied kind
///    must not touch HealthKit or start a location fix on its way to saying
///    no — a denial that already read the data is not a denial.
/// 2. **Prose out.** The consumer is an LLM and the belt's strings are
///    already the honest surface, so a "permission not granted" or "no data
///    recorded" sentence is a `.success` — the read ran and this is what it
///    truthfully returned. `.unavailable` is reserved for the two cases where
///    there is no answer at all: a kind this phone does not serve, and a read
///    that threw.
@MainActor
final class PhoneQueryResponder: PhoneQueryResponding {

    /// Today only. The belt's `readCalendar` takes an explicit window from
    /// the model; a query that names none gets the narrowest useful read
    /// rather than a fortnight of someone's calendar.
    static let defaultCalendarDaysAhead = 1

    private let settings: @MainActor () -> UserSettings
    private let relayFactory: @MainActor () -> ToolEventRelay
    private let reader: any PhoneQueryReader

    /// `settings` is a closure, not a value, so the gate is re-read on every
    /// answer — a toggle flipped mid-session takes effect on the next query
    /// rather than on the next app launch.
    init(
        settings: @escaping @MainActor () -> UserSettings,
        relayFactory: @escaping @MainActor () -> ToolEventRelay = { ToolEventRelay() },
        reader: any PhoneQueryReader = LivePhoneQueryReader()
    ) {
        self.settings = settings
        self.relayFactory = relayFactory
        self.reader = reader
    }

    func answer(kind: String, params: [String: String]) async -> PhoneQueryAnswer {
        let current = settings()
        let master = current.sensorStreamingEnabled
        switch kind {
        case "health":
            guard master, current.healthCollectionEnabled else { return .denied }
        case "location":
            guard master, current.locationCollectionEnabled else { return .denied }
        case "motion":
            guard master, current.motionCollectionEnabled else { return .denied }
        case "weather":
            // Weather here is weather AT THE USER'S LOCATION, so it is a
            // location read wearing another name and rides that toggle.
            guard master, current.locationCollectionEnabled else { return .denied }
        case "calendar", "reminders", "deviceStatus":
            // iOS's own permission prompts gate these, exactly as on the belt
            // (spec §2.2) — there is no sensor-collection setting for them to
            // answer to, and inventing one would gate them twice.
            break
        default:
            return .unavailable(reason: "unknown_kind")
        }

        // A fresh relay per query: `emit` is nil so no tool chip appears in a
        // conversation the user is not having, and `governor` is nil so the
        // per-turn call budget of a local turn does not apply to a remote one.
        let relay = relayFactory()
        do {
            let text: String
            switch kind {
            case "location":
                text = try await reader.location(relay: relay)
            case "health":
                text = try await reader.health(metric: params["metric"], relay: relay)
            case "motion":
                text = try await reader.motion(relay: relay)
            case "weather":
                text = try await reader.weather(relay: relay)
            case "calendar":
                text = try await reader.calendar(daysAhead: Self.daysAhead(from: params["window_days"]), relay: relay)
            case "reminders":
                text = try await reader.reminders(relay: relay)
            case "deviceStatus":
                text = await reader.deviceStatus()
            default:
                // The gate switch above and this one are two hand-synced
                // lists. A kind added to the gate's permission-only arm but
                // forgotten here must fail LOUDLY — falling through to the
                // device-status report would answer a privacy-adjacent query
                // with confidently wrong data, which is the one failure mode
                // this whole type exists to prevent.
                return .unavailable(reason: "unknown_kind")
            }
            return .success(text: text)
        } catch {
            return .unavailable(reason: "read_failed")
        }
    }

    /// Missing or unparsable window → the default. The belt's own clamp
    /// (1…14) still applies underneath, so a hostile number cannot widen the
    /// read past what the tool allows.
    static func daysAhead(from raw: String?) -> Int {
        guard let raw, let days = Int(raw.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return defaultCalendarDaysAhead
        }
        return days
    }
}
