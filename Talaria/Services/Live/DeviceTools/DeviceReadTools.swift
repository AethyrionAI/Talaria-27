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
        await relay.started(name)
        let result = await MainActor.run { Self.statusReport() }
        await relay.completed(name)
        return result
    }

    @MainActor
    private static func statusReport() -> String {
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

// MARK: - Location (place names, not raw coordinates)

struct LocationTool: Tool {
    let name = "currentLocation"
    let description = "Find where the user is right now, answered as a place name (neighborhood, city, region) — use for \"where am I\" and to ground other location questions."
    let relay: ToolEventRelay
    let location: DeviceLocationProvider

    @Generable
    struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        await relay.started(name)
        defer { Task { await relay.completed(name) } }

        let status = await location.ensureAuthorization()
        guard status == .authorizedWhenInUse || status == .authorizedAlways else {
            return "Location permission is not granted, so the current location can't be read. The user can enable it in Settings → Privacy & Security → Location Services → Talaria."
        }
        guard let fix = await location.currentLocation() else {
            return "Couldn't get a location fix right now (no GPS signal, or location is temporarily unavailable)."
        }
        // Answer with place names, not raw coordinates (#28).
        let geocoder = CLGeocoder()
        guard let placemark = try? await geocoder.reverseGeocodeLocation(fix).first else {
            return "Got a location fix, but reverse geocoding failed (this usually needs a network connection). Accuracy ±\(Int(fix.horizontalAccuracy))m."
        }
        let parts = [
            placemark.name,
            placemark.locality,
            placemark.administrativeArea,
            placemark.country,
        ].compactMap { $0 }
        var uniqueParts: [String] = []
        for part in parts where !uniqueParts.contains(part) {
            uniqueParts.append(part)
        }
        return "Current location: \(uniqueParts.joined(separator: ", "))"
    }
}

// MARK: - Motion (steps today, current activity)

struct MotionTool: Tool {
    let name = "readMotion"
    let description = "Read today's step count and the user's current motion activity (walking, running, driving, stationary) from the phone's motion coprocessor."
    let relay: ToolEventRelay

    @Generable
    struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        await relay.started(name)
        defer { Task { await relay.completed(name) } }

        guard CMPedometer.isStepCountingAvailable() else {
            return "This device has no step-counting hardware."
        }
        if CMPedometer.authorizationStatus() == .denied || CMPedometer.authorizationStatus() == .restricted {
            return "Motion & Fitness permission is not granted, so steps and activity can't be read. The user can enable it in Settings → Privacy & Security → Motion & Fitness."
        }

        var lines: [String] = []
        let pedometer = CMPedometer()
        let start = Calendar.current.startOfDay(for: Date())
        let steps: Int? = await withCheckedContinuation { continuation in
            pedometer.queryPedometerData(from: start, to: Date()) { data, _ in
                continuation.resume(returning: data.map { $0.numberOfSteps.intValue })
            }
        }
        if let steps {
            lines.append("Steps today (pedometer): \(steps)")
        } else {
            lines.append("No pedometer data recorded today.")
        }

        if CMMotionActivityManager.isActivityAvailable() {
            let manager = CMMotionActivityManager()
            let recent: CMMotionActivity? = await withCheckedContinuation { continuation in
                manager.queryActivityStarting(from: Date().addingTimeInterval(-600), to: Date(), to: .main) { activities, _ in
                    continuation.resume(returning: activities?.last)
                }
            }
            if let recent {
                var kind = "unknown"
                if recent.walking { kind = "walking" }
                if recent.running { kind = "running" }
                if recent.cycling { kind = "cycling" }
                if recent.automotive { kind = "driving" }
                if recent.stationary { kind = "stationary" }
                lines.append("Current activity: \(kind)")
            }
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Weather (WeatherKit)

struct WeatherTool: Tool {
    let name = "currentWeather"
    let description = "Get live weather conditions and today's forecast from Apple Weather — at the user's current location, or at a named place if one is given."
    let relay: ToolEventRelay
    let location: DeviceLocationProvider

    @Generable
    struct Arguments {
        @Guide(description: "Optional place name to get weather for (city or address). Leave empty for the user's current location.")
        var place: String
    }

    func call(arguments: Arguments) async throws -> String {
        let place = arguments.place.trimmingCharacters(in: .whitespacesAndNewlines)
        await relay.started(name, detail: place.isEmpty ? nil : place)
        defer { Task { await relay.completed(name) } }

        let target: CLLocation
        let label: String
        if place.isEmpty {
            let status = await location.ensureAuthorization()
            guard status == .authorizedWhenInUse || status == .authorizedAlways else {
                return "Location permission is not granted, so weather for the current location can't be looked up. Ask for a specific place instead, or enable Location in Settings → Privacy & Security → Location Services → Talaria."
            }
            guard let fix = await location.currentLocation() else {
                return "Couldn't get a location fix for the weather lookup."
            }
            target = fix
            label = "current location"
        } else {
            guard let match = try? await CLGeocoder().geocodeAddressString(place).first,
                  let found = match.location else {
                return "Couldn't find a place called \"\(place)\" to look up weather for."
            }
            target = found
            label = match.name ?? place
        }

        do {
            let weather = try await WeatherService.shared.weather(for: target)
            let formatter = MeasurementFormatter()
            formatter.unitOptions = .naturalScale
            formatter.numberFormatter.maximumFractionDigits = 0

            let current = weather.currentWeather
            var lines = [
                "Weather at \(label): \(current.condition.description), \(formatter.string(from: current.temperature)) (feels like \(formatter.string(from: current.apparentTemperature)))",
                "Humidity \(Int(current.humidity * 100))%, wind \(formatter.string(from: current.wind.speed))",
            ]
            if let today = weather.dailyForecast.first {
                let precip = Int(today.precipitationChance * 100)
                lines.append("Today: high \(formatter.string(from: today.highTemperature)), low \(formatter.string(from: today.lowTemperature)), \(precip)% chance of precipitation")
            }
            return lines.joined(separator: "\n")
        } catch {
            // Missing entitlement, no network, or a WeatherKit outage — all
            // land here; say so instead of inventing a forecast.
            return "Weather lookup failed: \(error.localizedDescription). (WeatherKit needs a network connection and the app's WeatherKit capability.)"
        }
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
        await relay.started(name, detail: query)
        defer { Task { await relay.completed(name) } }
        guard !query.isEmpty else { return "No search query was given." }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query

        // "Near me" needs a center; without permission the search still runs,
        // just un-anchored (results may be far away — honest, not fabricated).
        var origin: CLLocation?
        let status = await location.ensureAuthorization()
        if status == .authorizedWhenInUse || status == .authorizedAlways,
           let fix = await location.currentLocation() {
            origin = fix
            request.region = MKCoordinateRegion(
                center: fix.coordinate,
                latitudinalMeters: 10_000,
                longitudinalMeters: 10_000
            )
        }

        do {
            let response = try await MKLocalSearch(request: request).start()
            guard !response.mapItems.isEmpty else {
                return "No places found for \"\(query)\"."
            }
            let lines = response.mapItems.prefix(5).map { item -> String in
                var line = item.name ?? "Unnamed place"
                if let address = item.placemark.title, !address.isEmpty {
                    line += " — \(address)"
                }
                if let origin, let itemLocation = item.placemark.location {
                    let meters = origin.distance(from: itemLocation)
                    let formatter = MKDistanceFormatter()
                    line += " (\(formatter.string(fromDistance: meters)) away)"
                }
                return line
            }
            var result = lines.joined(separator: "\n")
            if origin == nil {
                result += "\n(Location permission not granted — results are not anchored to the user's position.)"
            }
            return result
        } catch {
            return "Place search failed: \(error.localizedDescription). (Maps search needs a network connection.)"
        }
    }
}

// MARK: - Contacts (name → number/email lookup)

struct ContactsTool: Tool {
    let name = "lookupContact"
    let description = "Look up a person in the user's contacts by name and return their phone numbers and email addresses."
    let relay: ToolEventRelay

    @Generable
    struct Arguments {
        @Guide(description: "The contact's name (or part of it), e.g. \"Shelley\".")
        var contactName: String
    }

    func call(arguments: Arguments) async throws -> String {
        let query = arguments.contactName.trimmingCharacters(in: .whitespacesAndNewlines)
        await relay.started(name, detail: query)
        defer { Task { await relay.completed(name) } }
        guard !query.isEmpty else { return "No name was given to look up." }

        let status = CNContactStore.authorizationStatus(for: .contacts)
        if status == .notDetermined {
            // Contextual priming (#31): the prompt appears on the first lookup.
            let granted = (try? await CNContactStore().requestAccess(for: .contacts)) ?? false
            guard granted else {
                return "Contacts permission was not granted, so the lookup can't run."
            }
        } else if status != .authorized {
            return "Contacts permission is not granted, so the lookup can't run. The user can enable it in Settings → Privacy & Security → Contacts."
        }

        // CNContactStore fetches are blocking — keep them off the main actor.
        let report: String = await Task.detached(priority: .userInitiated) {
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
                return "No contact matching \"\(query)\" was found."
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
        }.value
        return report
    }
}
