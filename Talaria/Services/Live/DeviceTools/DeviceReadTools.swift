import Contacts
import CoreLocation
import CoreMotion
import Foundation
import FoundationModels
import MapKit
import UIKit
import WeatherKit

// The sensor/system read tools of the #28 belt. Every tool follows the same
// shape: emit a started event on the relay (so the chip appears), do the
// read, emit completed, and return an honest plain-text result — including
// honest "permission not granted" / "no data" results, never fabrication.

// MARK: - Device status (no permission gate)

struct DeviceStatusTool: Tool {
    let name = "deviceStatus"
    let description = "Read this iPhone's current battery level and charging state, free storage, and thermal state."
    let relay: ToolEventRelay

    @Generable
    struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        if case .refused(let refusal) = try await relay.started(name) { return refusal }
        let result = await MainActor.run { Self.statusReport() }
        await relay.completed(name)
        return result
    }

    /// #251-2A: internal rather than private so `PhoneQueryResponder` can
    /// answer a `deviceStatus` phone query through the SAME report the belt
    /// returns — one status string, one place. Not a harness widening: this
    /// is production code with a second production caller.
    @MainActor
    static func statusReport() -> String {
        var lines: [String] = []

        let device = UIDevice.current
        let wasMonitoring = device.isBatteryMonitoringEnabled
        device.isBatteryMonitoringEnabled = true
        if device.batteryLevel >= 0 {
            let percent = Int((device.batteryLevel * 100).rounded())
            let state: String
            switch device.batteryState {
            case .charging: state = "charging"
            case .full: state = "full"
            case .unplugged: state = "not charging"
            default: state = "unknown"
            }
            lines.append("Battery: \(percent)% (\(state))")
        } else {
            lines.append("Battery: level unavailable")
        }
        device.isBatteryMonitoringEnabled = wasMonitoring

        let home = URL(fileURLWithPath: NSHomeDirectory())
        let values = try? home.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeTotalCapacityKey,
        ])
        lines.append(DeviceToolFormat.storageLine(
            availableBytes: values?.volumeAvailableCapacityForImportantUsage,
            totalBytes: values?.volumeTotalCapacity.map(Int64.init)
        ))

        let thermal: String
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: thermal = "nominal"
        case .fair: thermal = "fair (slightly warm)"
        case .serious: thermal = "serious (hot — performance reduced)"
        case .critical: thermal = "critical (very hot)"
        @unknown default: thermal = "unknown"
        }
        lines.append("Thermal state: \(thermal)")
        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            lines.append("Low Power Mode is on.")
        }
        return lines.joined(separator: "\n")
    }
}

extension DeviceStatusTool: CapabilityDescribing {
    static let capabilityDescriptor = CapabilityDescriptor(
        id: "deviceStatus",
        semanticDescription: "Reads battery level, charging state, storage, and network reachability.",
        source: .device, group: .deviceStatus, riskClass: .read,
        permissions: [], argumentSummary: "none")
}

// MARK: - Location (place names, not raw coordinates)

struct LocationTool: Tool {
    let name = "currentLocation"
    let description = "Find where the user is right now, answered as a place name (neighborhood, city, region) — use for \"where am I\" and to ground other location questions."
    let relay: ToolEventRelay
    let location: DeviceLocationProvider

    @Generable
    struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        try await Self.performLocationRead(relay: relay, location: location, name: name)
    }

    /// #251-2A: `call`'s body, lifted verbatim so a phone query reads through
    /// the SAME machinery (and emits the same relay events) as the belt —
    /// matching the `WeatherTool.performLookup` / `DeviceHealthTool.performRead`
    /// shape that already existed for the same reason.
    static func performLocationRead(
        relay: ToolEventRelay, location: DeviceLocationProvider, name: String
    ) async throws -> String {
        if case .refused(let refusal) = try await relay.started(name) { return refusal }
        defer { Task { await relay.completed(name) } }

        let status = await location.ensureAuthorization()
        guard status == .authorizedWhenInUse || status == .authorizedAlways else {
            return "Location permission is not granted, so the current location can't be read. The user can enable it in Settings → Privacy & Security → Location Services → Talaria."
        }
        guard let fix = await location.currentLocation() else {
            return "Couldn't get a location fix right now (no GPS signal, or location is temporarily unavailable)."
        }
        // Answer with place names, not raw coordinates (#28).
        // #198: `CLGeocoder` is deprecated; `MKReverseGeocodingRequest` is the
        // successor. Its `mapItems` getter is NS_SWIFT_UI_ACTOR, so the
        // MKMapItem is MainActor-bound and NON-Sendable — the same shape that
        // forced the CLLocationManager / CMPedometer / MKLocalSearch rewrites.
        // The whole lookup AND the string extraction therefore happen inside
        // one MainActor hop, and only a [String] crosses back out.
        guard let parts = await Self.reverseGeocodedParts(for: fix) else {
            return "Got a location fix, but reverse geocoding failed (this usually needs a network connection). Accuracy ±\(Int(fix.horizontalAccuracy))m."
        }
        var uniqueParts: [String] = []
        for part in parts where !uniqueParts.contains(part) {
            uniqueParts.append(part)
        }
        return "Current location: \(uniqueParts.joined(separator: ", "))"
    }

    /// #198: the MapKit reverse geocode, kept whole inside one MainActor hop so
    /// the non-Sendable `MKMapItem` never crosses a boundary. Returns only
    /// Sendable strings.
    ///
    /// **Behavioural delta, stated rather than buried:** the deprecated
    /// `CLPlacemark` carried a `country`, and `MKAddressRepresentations` has no
    /// country property (it exposes `cityName`, `cityWithContext`, `regionName`,
    /// `regionCode`). So a fix that used to read
    /// "Name, Locality, State, United States" now reads "Name, Locality, State".
    /// This is a READ tool whose output the model consumes, and #200-era work
    /// showed tool-result phrasing changes behaviour — so this is a real, if
    /// small, delta and NOT a mechanical no-op. `cityWithContext` is
    /// deliberately not used: it reformats the city itself, which would change
    /// more of the string than dropping the country does.
    @MainActor
    private static func reverseGeocodedParts(for fix: CLLocation) async -> [String]? {
        guard let request = MKReverseGeocodingRequest(location: fix),
              let item = try? await request.mapItems.first else { return nil }
        let address = item.addressRepresentations
        return [item.name, address?.cityName, address?.regionName].compactMap { $0 }
    }
}

extension LocationTool: CapabilityDescribing {
    static let capabilityDescriptor = CapabilityDescriptor(
        id: "currentLocation",
        semanticDescription: "Reads the device's current location as a place name and coordinates.",
        source: .device, group: .location, riskClass: .read,
        permissions: ["Location"], argumentSummary: "none")
}

// MARK: - Motion (steps today, current activity)

struct MotionTool: Tool {
    let name = "readMotion"
    /// PROMOTED 2026-07-31 (#211, run `63C0EF12`): the step claim is gone.
    ///
    /// The old text claimed "today's step count", and so does `readHealth` —
    /// two tools advertising one capability. Asked "How many steps have I
    /// taken today?", the model picked this one 20/20, `CMPedometer` had no
    /// samples, and the turn answered "no pedometer data" while HealthKit held
    /// the number. Scoping this description off steps took that from **0/10 to
    /// 10/10** correct answers (Fisher exact two-tailed p = 1.08e-05), while
    /// motion questions still reached this tool 9/9.
    ///
    /// Behaviour is UNCHANGED — `call()` still reports steps when the
    /// pedometer has them. Only the advertisement moved. HealthKit is the
    /// better source regardless: it aggregates phone AND watch, where
    /// `CMPedometer` sees only the phone.
    static let productionDescription = "Read the user's current motion activity (walking, running, driving, stationary) from the phone's motion coprocessor."
    /// The pre-#211 text, kept reachable as the measured CONTROL cell
    /// (`armed-motionrollback`) and as the pinned rollback.
    static let stepClaimingDescription211 = "Read today's step count and the user's current motion activity (walking, running, driving, stationary) from the phone's motion coprocessor."
    /// #211 follow-on treatment: the promoted text PLUS a boundary sentence.
    ///
    /// **Why:** promoting the scoped description fixed the misroute (0/10 →
    /// 10/10) but the promoted arm then chained extra tools on motion
    /// questions — **4 of 9 vs 0 of 10** in control. One trial went
    /// `readMotion → currentLocation → currentWeather → currentWeather` and
    /// dragged #212's weather failure into an answer about standing still;
    /// another volunteered a street address. The reading: removing the step
    /// claim also removed the model's sense of what this tool is FOR, so it
    /// kept reaching. Naming the boundary may restore that.
    ///
    /// **The wording is constrained, not free.** It must NOT contain "step",
    /// or the semantic match that caused the original 0/10 misroute comes
    /// straight back — the exact confound the belt test caught in the first
    /// draft of the scoped text. So it points at `readHealth` by domain
    /// ("health metrics"), never by naming the metric.
    static let redirectDescription211B = "Read the user's current motion activity (walking, running, driving, stationary) from the phone's motion coprocessor. For health metrics, use readHealth."
    var description: String = MotionTool.productionDescription
    let relay: ToolEventRelay

    @Generable
    struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        try await Self.performMotionRead(relay: relay, name: name)
    }

    /// #251-2A: `call`'s body, lifted verbatim. `Arguments` is empty, so the
    /// extraction takes no request parameter — the signature follows the body,
    /// not the sketch.
    static func performMotionRead(relay: ToolEventRelay, name: String) async throws -> String {
        if case .refused(let refusal) = try await relay.started(name) { return refusal }
        defer { Task { await relay.completed(name) } }

        guard CMPedometer.isStepCountingAvailable() else {
            return "This device has no step-counting hardware."
        }
        if CMPedometer.authorizationStatus() == .denied || CMPedometer.authorizationStatus() == .restricted {
            return "Motion & Fitness permission is not granted, so steps and activity can't be read. The user can enable it in Settings → Privacy & Security → Motion & Fitness."
        }

        var lines: [String] = []
        let start = Calendar.current.startOfDay(for: Date())
        // #203 (1C): CoreMotion's completion is not guaranteed to fire, and
        // an unfired continuation parks the turn forever. `run` returns a
        // sentinel on expiry rather than throwing, so the tool still answers
        // with whatever else it gathered.
        //
        // CMPedometer is NOT Sendable, so it is built INSIDE the closure and
        // only the Date crosses — the same constraint that shaped the Places
        // rewrite in #200Y.
        let stepsText = await DeviceToolTimeout.run(label: name) {
            let steps: Int? = await withCheckedContinuation { continuation in
                CMPedometer().queryPedometerData(from: start, to: Date()) { data, _ in
                    continuation.resume(returning: data.map { $0.numberOfSteps.intValue })
                }
            }
            return steps.map(String.init) ?? ""
        }
        let steps = Int(stepsText)
        if let steps {
            lines.append("Steps today (pedometer): \(steps)")
        } else {
            lines.append("No pedometer data recorded today.")
        }

        if CMMotionActivityManager.isActivityAvailable() {
            let manager = CMMotionActivityManager()
            // Classify inside the completion handler — CMMotionActivity is
            // not Sendable and must not cross the continuation boundary.
            let activityKind: String? = await withCheckedContinuation { continuation in
                manager.queryActivityStarting(from: Date().addingTimeInterval(-600), to: Date(), to: .main) { activities, _ in
                    guard let recent = activities?.last else {
                        continuation.resume(returning: nil)
                        return
                    }
                    var kind = "unknown"
                    if recent.walking { kind = "walking" }
                    if recent.running { kind = "running" }
                    if recent.cycling { kind = "cycling" }
                    if recent.automotive { kind = "driving" }
                    if recent.stationary { kind = "stationary" }
                    continuation.resume(returning: kind)
                }
            }
            if let activityKind {
                lines.append("Current activity: \(activityKind)")
            }
        }
        return lines.joined(separator: "\n")
    }
}

extension MotionTool: CapabilityDescribing {
    static let capabilityDescriptor = CapabilityDescriptor(
        id: "readMotion",
        semanticDescription: "Reads current motion activity: walking, running, stationary, step cadence.",
        source: .device, group: .health, riskClass: .read,
        permissions: ["Motion & Fitness"], argumentSummary: "none")
}

// MARK: - Weather (WeatherKit)

struct WeatherTool: Tool {
    let name = "currentWeather"
    /// Static so the pinned rollback twin ships the SAME description — the two
    /// cells must differ in exactly one thing, the schema.
    static let productionDescription = "Get live weather conditions plus today's and tomorrow's forecast from Apple Weather — at the user's current location, or at a named place if one is given."
    let description = WeatherTool.productionDescription
    let relay: ToolEventRelay
    let location: DeviceLocationProvider

    // #209: the @Guide has said "Optional… Leave empty" since this tool
    // shipped, while the TYPE said required — so the model did as it was told,
    // emitted `{}`, and the turn died on `GeneratedContent does not contain a
    // property 'place'`. Two trials in the records. This is the week plan's
    // finding 3 in its purest form: when behaviour resists an instruction,
    // look for a structural constraint saying the opposite. `call()` already
    // treats empty as "here", so nil changes nothing for a well-formed call.
    // `WeatherToolRequiredPlace` is the pinned rollback.
    @Generable
    struct Arguments {
        @Guide(description: "Optional place name to get weather for (city or address). Leave empty for the user's current location.")
        var place: String?
        // #230: "tomorrow" was unmeetable by the whole belt, and the unmet
        // demand displaced into searchConversations (#216) and became #225's
        // spiral and #232's grind. One extra guided value ends that question
        // at call 2.
        // #234: the guide names the beyond-tomorrow boundary and the
        // pass-through rule — with no advertised third state, the model
        // snapped "day after tomorrow" to 'tomorrow' and the honest
        // unsupported path never fired (argument-time nearest-fit).
        @Guide(description: WeatherTool.dayGuideText)
        var day: String?
    }

    /// #234-A: pinned by WeatherTomorrowTests — a guide edit is a deliberate act.
    nonisolated static let dayGuideText = "Optional: 'tomorrow' for tomorrow's forecast. Leave empty for current conditions and today. Weather beyond tomorrow is not available: if the user asks about a later day (like 'day after tomorrow' or a weekday), pass their exact words through unchanged — never substitute 'tomorrow'."

    func call(arguments: Arguments) async throws -> String {
        try await Self.performLookup(rawPlace: arguments.place, rawDay: arguments.day,
                                 relay: relay, location: location, name: name)
    }

    // MARK: #230 — the day the caller asked for (pure, pinned)

    enum RequestedDay: Equatable { case today, tomorrow, unsupported }

    nonisolated static func requestedDay(from raw: String?) -> RequestedDay {
        let day = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if day.isEmpty || day == "today" || day == "now" { return .today }
        if day == "tomorrow" { return .tomorrow }
        return .unsupported
    }

    /// #234-B: the line names its own calendar date ("Tomorrow (Aug 5) at…"),
    /// so a relay that mislabels the day contradicts itself on its face.
    /// Fixed-locale month-day — tool output is English throughout.
    nonisolated static func tomorrowForecastLine(
        label: String, condition: String, high: String, low: String, precipPercent: Int,
        date: Date? = nil
    ) -> String {
        let datePart: String
        if let date {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "MMM d"
            datePart = " (\(formatter.string(from: date)))"
        } else {
            datePart = ""
        }
        return "Tomorrow\(datePart) at \(label): \(condition), high \(high), low \(low), \(precipPercent)% chance of precipitation"
    }

    /// Real-data-only: a horizon this tool cannot serve is named back, never
    /// silently answered with today's numbers — the date-relabel is the
    /// #199-suspect shape from the 2026-08-02 control.
    nonisolated static func unsupportedDayAnswer(requested: String) -> String {
        "Weather is available for today and tomorrow only — \"\(requested)\" is beyond this tool's forecast horizon. Ask about today or tomorrow."
    }

    /// #198: forward geocode inside one MainActor hop — `MKMapItem` is
    /// non-Sendable, so only a `CLLocation` and a `String` cross back.
    @MainActor
    private static func geocodedTarget(for place: String) async -> (location: CLLocation, name: String?)? {
        guard let request = MKGeocodingRequest(addressString: place),
              let item = try? await request.mapItems.first else { return nil }
        return (item.location, item.name)
    }

    static func performLookup(rawPlace: String?, rawDay: String? = nil, relay: ToolEventRelay,
                              location: DeviceLocationProvider, name: String) async throws -> String {
        // nil and "" are the same request: weather here.
        let place = (rawPlace ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let day = requestedDay(from: rawDay)
        let detailBase = place.isEmpty ? "" : place
        let detail = day == .tomorrow ? (detailBase.isEmpty ? "tomorrow" : "\(detailBase) · tomorrow") : detailBase
        if case .refused(let refusal) = try await relay.started(name, detail: detail.isEmpty ? nil : detail) { return refusal }
        if day == .unsupported {
            let answer = unsupportedDayAnswer(requested: (rawDay ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
            await relay.completed(name, result: answer)
            return answer
        }
        // #212: record what this tool actually RETURNED, not merely that it
        // finished. 40 of 40 weather trials failed with WeatherKit's real
        // error in hand and the record kept only the model's paraphrase.
        // Wrapping the body means every exit is captured without threading a
        // variable through five returns.
        // #212: the RECORD gets the diagnostic, the USER gets the reply.
        //
        // These diverged and it cost a run. The honest-failure rewrite made
        // `currentWeather` return "the weather service rejected this app's
        // credentials" — good for a reader, and it replaced the captured
        // result, so the raw `WDSJWTAuthenticatorServiceListener` text went
        // from 40 occurrences in the previous run's JSON to ZERO in the next.
        // **A fix for the user blinded the instrument that had just diagnosed
        // the thing being fixed.** `relay.completed(result:)` is battery-store
        // only and never reaches a transcript (#197), so the raw text belongs
        // there and the sanitised sentence belongs in the reply.
        let (answer, diagnostic) = await lookup(place: place, day: day, location: location)
        await relay.completed(name, result: diagnostic ?? answer)
        return answer
    }

    private static func lookup(place: String, day: RequestedDay, location: DeviceLocationProvider) async -> (answer: String, diagnostic: String?) {
        let target: CLLocation
        let label: String
        if place.isEmpty {
            let status = await location.ensureAuthorization()
            guard status == .authorizedWhenInUse || status == .authorizedAlways else {
                return ("Location permission is not granted, so weather for the current location can't be looked up. Ask for a specific place instead, or enable Location in Settings → Privacy & Security → Location Services → Talaria.", nil)
            }
            guard let fix = await location.currentLocation() else {
                return ("Couldn't get a location fix for the weather lookup.", nil)
            }
            target = fix
            label = "current location"
        } else {
            // #198: `MKGeocodingRequest` replaces the deprecated
            // `geocodeAddressString`. This site maps near-identically — it only
            // ever used `location` and `name`, and `MKMapItem` has both — so
            // unlike the reverse-geocode site there is no output delta. Same
            // MainActor/non-Sendable constraint, same containment.
            guard let found = await Self.geocodedTarget(for: place) else {
                return ("Couldn't find a place called \"\(place)\" to look up weather for.", nil)
            }
            target = found.location
            label = found.name ?? place
        }

        do {
            let weather = try await WeatherService.shared.weather(for: target)
            let formatter = MeasurementFormatter()
            formatter.unitOptions = .naturalScale
            formatter.numberFormatter.maximumFractionDigits = 0

            // #230: the tomorrow path answers from the DAILY forecast — the
            // exact data the "Gulfport tomorrow" turn needed at call 2 and
            // could not get. Calendar-matched, never index-assumed.
            if day == .tomorrow {
                guard let tomorrow = weather.dailyForecast.first(where: { Calendar.current.isDateInTomorrow($0.date) }) else {
                    return ("Apple Weather returned no forecast for tomorrow at \(label).", "NO-TOMORROW-ENTRY")
                }
                let line = Self.tomorrowForecastLine(
                    label: label,
                    condition: tomorrow.condition.description,
                    high: formatter.string(from: tomorrow.highTemperature),
                    low: formatter.string(from: tomorrow.lowTemperature),
                    precipPercent: Int(tomorrow.precipitationChance * 100),
                    date: tomorrow.date
                )
                return (line, nil)
            }

            let current = weather.currentWeather
            var lines = [
                "Weather at \(label): \(current.condition.description), \(formatter.string(from: current.temperature)) (feels like \(formatter.string(from: current.apparentTemperature)))",
                "Humidity \(Int(current.humidity * 100))%, wind \(formatter.string(from: current.wind.speed))",
            ]
            if let today = weather.dailyForecast.first {
                let precip = Int(today.precipitationChance * 100)
                lines.append("Today: high \(formatter.string(from: today.highTemperature)), low \(formatter.string(from: today.lowTemperature)), \(precip)% chance of precipitation")
            }
            return (lines.joined(separator: "\n"), nil)
        } catch {
            // #212: the old text blamed "a network connection and the app's
            // WeatherKit capability". Both were verifiably FINE — entitlement
            // present in the signed binary AND the provisioning profile — and
            // the real failure was
            // `WDSJWTAuthenticatorServiceListener.Errors error 2`, 40/40: the
            // weather service REJECTING the app's token. A message that names
            // the wrong causes sends the reader to check two things that are
            // not broken, which is worse than saying less. Auth failures are
            // now named as such; everything else stays generic rather than
            // guessing.
            let described = error.localizedDescription
            // The diagnostic ALWAYS carries the raw text, even when the reply
            // does not. That divergence is the whole point (#212): the battery
            // record is not a transcript, and sanitising both is what erased
            // `WDSJWTAuthenticatorServiceListener` from a run that existed to
            // capture it.
            if described.contains("JWTAuthenticator") || described.contains("Authenticator") {
                return ("Weather is unavailable: the weather service rejected this app's credentials. That is an account/service setup issue, not something retrying will fix.",
                        "AUTH-REJECTED raw=\(described)")
            }
            return ("Weather lookup failed: \(described)", "FAILED raw=\(described)")
        }
    }
}

extension WeatherTool: CapabilityDescribing {
    static let capabilityDescriptor = CapabilityDescriptor(
        id: "currentWeather",
        semanticDescription: "Reads current conditions and forecast for the user's location.",
        source: .device, group: .weather, riskClass: .read,
        permissions: ["Location"], argumentSummary: "optional day offset")
}

/// #209 PINNED ROLLBACK for the optional-`place` schema: identical to
/// `WeatherTool` in name, description, @Guide text and engine — the ONLY delta
/// is that `place` is REQUIRED, which is what production shipped until #209
/// while its own @Guide told the model the field was optional.
struct WeatherToolRequiredPlace: Tool {
    let name = "currentWeather"
    var description: String = WeatherTool.productionDescription
    let relay: ToolEventRelay
    let location: DeviceLocationProvider

    @Generable
    struct Arguments {
        @Guide(description: "Optional place name to get weather for (city or address). Leave empty for the user's current location.")
        var place: String
    }

    func call(arguments: Arguments) async throws -> String {
        try await WeatherTool.performLookup(rawPlace: arguments.place, relay: relay,
                                        location: location, name: name)
    }
}

// MARK: - Places (MapKit local search)

struct PlacesTool: Tool {
    let name = "searchPlaces"
    let description = "Search for places, businesses, and points of interest near the user (or anywhere by name) using Apple Maps."
    let relay: ToolEventRelay
    let location: DeviceLocationProvider

    @Generable
    struct Arguments {
        @Guide(description: "What to search for, e.g. \"coffee\", \"pharmacy\", \"Golden Gate Bridge\".")
        var query: String
    }

    func call(arguments: Arguments) async throws -> String {
        let query = arguments.query.trimmingCharacters(in: .whitespacesAndNewlines)
        if case .refused(let refusal) = try await relay.started(name, detail: query) { return refusal }
        defer { Task { await relay.completed(name) } }
        guard !query.isEmpty else { return "No search query was given." }

        // "Near me" needs a center; without permission the search still runs,
        // just un-anchored (results may be far away — honest, not fabricated).
        // Immutable: these are captured by a @Sendable closure below, so a
        // `var` would not compile (and would be a data race if it did).
        let status = await location.ensureAuthorization()
        let fix = (status == .authorizedWhenInUse || status == .authorizedAlways)
            ? await location.currentLocation()
            : nil
        let anchorLat: Double? = fix?.coordinate.latitude
        let anchorLon: Double? = fix?.coordinate.longitude
        let anchored = fix != nil

        // #200Y/F6 (Hermes audit): MKLocalSearch is a network round-trip with no
        // deadline of its own — bounded so a stalled search cannot outlive the
        // turn. Only SENDABLE values cross the boundary: `MKLocalSearch.Request`,
        // `.Response` and `CLLocation` are all non-Sendable classes, so the
        // request is BUILT and consumed inside the closure from plain doubles and
        // only the formatted lines come back out.
        do {
            let lines: [String] = try await DeviceToolTimeout.runThrowing(label: name) {
                let request = MKLocalSearch.Request()
                request.naturalLanguageQuery = query
                if let anchorLat, let anchorLon {
                    request.region = MKCoordinateRegion(
                        center: CLLocationCoordinate2D(latitude: anchorLat, longitude: anchorLon),
                        latitudinalMeters: 10_000,
                        longitudinalMeters: 10_000
                    )
                }
                let response = try await MKLocalSearch(request: request).start()
                let origin = (anchorLat != nil && anchorLon != nil)
                    ? CLLocation(latitude: anchorLat!, longitude: anchorLon!)
                    : nil
                // #198: `MKMapItem.placemark` is deprecated in favour of
                // `location` / `address` / `addressRepresentations`. The address
                // line moves from `placemark.title` to `address?.fullAddress` —
                // both are a single formatted address string, so the shape of
                // the reply is unchanged even though the exact formatting is
                // Apple's to decide. `location` is now non-optional, which
                // removes a branch rather than adding one.
                return response.mapItems.prefix(5).map { item -> String in
                    var line = item.name ?? "Unnamed place"
                    if let address = item.address?.fullAddress, !address.isEmpty {
                        line += " — \(address)"
                    }
                    if let origin {
                        let itemLocation = item.location
                        let meters = origin.distance(from: itemLocation)
                        let formatter = MKDistanceFormatter()
                        line += " (\(formatter.string(fromDistance: meters)) away)"
                    }
                    return line
                }
            }
            guard !lines.isEmpty else {
                return "No places found for \"\(query)\"."
            }
            var result = lines.joined(separator: "\n")
            if !anchored {
                result += "\n(Location permission not granted — results are not anchored to the user's position.)"
            }
            return result
        } catch {
            return "Place search failed: \(error.localizedDescription). (Maps search needs a network connection.)"
        }
    }
}

extension PlacesTool: CapabilityDescribing {
    static let capabilityDescriptor = CapabilityDescriptor(
        id: "searchPlaces",
        semanticDescription: "Searches for nearby places and points of interest around the user.",
        source: .device, group: .places, riskClass: .read,
        permissions: ["Location"], argumentSummary: "search term")
}

// MARK: - Contacts (name → number/email lookup)

struct ContactsTool: Tool {
    let name = "lookupContact"
    let description = "Look up a person in the user's contacts by name and return their phone numbers and email addresses."
    /// #201B PROMOTION: production's not-found result CARRIES CONTINUATION.
    ///
    /// The bare negative was read by the model as a blocker: it called the tool,
    /// the lookup missed, and it stopped to ask the user instead of creating with
    /// the name it was given — THROUGH the promoted #200O prose carve-out that
    /// already says to carry on. Prose could not reach it because a tool RESULT is
    /// not instructions the model weighs; it is fact the model consumes.
    ///
    /// Measured twice at n=40, in BOTH slot orders, with the confound inverted:
    /// dead-end misses **0/80 treatment vs 14/80 control** pooled (control 17.5%,
    /// matching the 16.7% base rate the power calculation assumed), Fisher
    /// p≈0.0012 on the confirmation run alone. In that run the treatment ran
    /// SECOND and THERMALLY THROTTLED and still went 40/40 while cool, rested
    /// production went 31/40 — so heat and slot position are both exonerated, and
    /// the surviving confound ran AGAINST the winner.
    ///
    /// `ContactsToolBareNotFound` — reachable as the `armed-deadendrollback`
    /// cell, which passes `false` explicitly — is the pinned rollback.
    var continuesAfterNoMatch: Bool = true
    let relay: ToolEventRelay

    @Generable
    struct Arguments {
        @Guide(description: "The contact's name (or part of it), e.g. \"Shelley\".")
        var contactName: String
    }

    /// The not-found result in one place so both texts are pinnable. The
    /// continuing form is a strict superset — same bare sentence, plus the
    /// continuation — so the delta the model sees is exactly the added clause.
    nonisolated static func noMatchText(query: String, continuing: Bool) -> String {
        let bare = "No contact matching \"\(query)\" was found."
        guard continuing else { return bare }
        return bare + " This does not block anything — if the name came from a request to create something, continue with the name exactly as the user gave it."
    }

    func call(arguments: Arguments) async throws -> String {
        let query = arguments.contactName.trimmingCharacters(in: .whitespacesAndNewlines)
        if case .refused(let refusal) = try await relay.started(name, detail: query) { return refusal }
        defer { Task { await relay.completed(name) } }
        guard !query.isEmpty else { return "No name was given to look up." }

        let status = CNContactStore.authorizationStatus(for: .contacts)
        if status == .notDetermined {
            // Contextual priming (#31): the prompt appears on the first lookup.
            let granted = (try? await CNContactStore().requestAccess(for: .contacts)) ?? false
            guard granted else {
                return "Contacts permission was not granted, so the lookup can't run."
            }
        } else if status != .authorized && status != .limited {
            // .limited (the Contact Access Picker) still returns hits from
            // the approved subset — a narrower grant is not a denial (#186).
            return "Contacts permission is not granted, so the lookup can't run. The user can enable it in Settings → Privacy & Security → Contacts."
        }

        // CNContactStore fetches are blocking — keep them off the main actor.
        // #200Y/F6: bounded, because a blocking framework fetch is exactly the
        // hop cancellation cannot interrupt. The PERMISSION REQUEST above is
        // deliberately NOT wrapped — that one waits on a human, and 12s is not
        // a fair deadline for a person reading a system dialog.
        let continuing = continuesAfterNoMatch
        let report: String = await DeviceToolTimeout.run(label: name) { await Task.detached(priority: .userInitiated) {
            let store = CNContactStore()
            let keys: [CNKeyDescriptor] = [
                CNContactGivenNameKey as CNKeyDescriptor,
                CNContactFamilyNameKey as CNKeyDescriptor,
                CNContactOrganizationNameKey as CNKeyDescriptor,
                CNContactPhoneNumbersKey as CNKeyDescriptor,
                CNContactEmailAddressesKey as CNKeyDescriptor,
            ]
            let predicate = CNContact.predicateForContacts(matchingName: query)
            guard let contacts = try? store.unifiedContacts(matching: predicate, keysToFetch: keys),
                  !contacts.isEmpty else {
                return Self.noMatchText(query: query, continuing: continuing)
            }
            return contacts.prefix(5).map { contact in
                var lines = ["\(contact.givenName) \(contact.familyName)".trimmingCharacters(in: .whitespaces)]
                if !contact.organizationName.isEmpty {
                    lines[0] += " (\(contact.organizationName))"
                }
                for phone in contact.phoneNumbers {
                    let label = phone.label.map { CNLabeledValue<NSString>.localizedString(forLabel: $0) } ?? "phone"
                    lines.append("  \(label): \(phone.value.stringValue)")
                }
                for email in contact.emailAddresses {
                    let label = email.label.map { CNLabeledValue<NSString>.localizedString(forLabel: $0) } ?? "email"
                    lines.append("  \(label): \(email.value as String)")
                }
                if contact.phoneNumbers.isEmpty && contact.emailAddresses.isEmpty {
                    lines.append("  (no phone or email on file)")
                }
                return lines.joined(separator: "\n")
            }.joined(separator: "\n\n")
        }.value }
        return report
    }
}

extension ContactsTool: CapabilityDescribing {
    static let capabilityDescriptor = CapabilityDescriptor(
        id: "lookupContact",
        semanticDescription: "Looks up a person in the user's contacts: phone, email, address.",
        source: .device, group: .contacts, riskClass: .read,
        permissions: ["Contacts"], argumentSummary: "name")
}
