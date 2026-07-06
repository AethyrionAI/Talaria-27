import AlarmKit
import Foundation
import SwiftUI
import os

private let alarmLog = Logger(subsystem: "org.aethyrion.talaria", category: "AlarmService")

/// #16 Phase 1 — the `/alarm` slash-command executor. Turns "wake me at 6:30"
/// prose into an actual AlarmKit alarm that breaks through Silent mode and
/// Focus, with Lock Screen / Dynamic Island presence.
///
/// Never schedules silently: callers parse into an `AlarmRequest`, present the
/// in-app confirm gate, and only call `schedule(_:)` after the user confirms —
/// the decided policy for every alarm write, agent-initiated ones included
/// (the fast-follow relay-sidecar `phone_alarm` tool reuses this same service
/// behind the same gate).
@MainActor
@Observable
final class AlarmService {

    enum AlarmSchedulingError: LocalizedError {
        case notAuthorized
        case invalidTime

        var errorDescription: String? {
            switch self {
            case .notAuthorized:
                return "Alarms aren't authorized for Talaria — enable them in Settings."
            case .invalidTime:
                return "That time couldn't be turned into a schedule."
            }
        }
    }

    /// A parsed, staged-but-not-yet-scheduled alarm. Everything the confirm
    /// dialog needs to describe exactly what will be scheduled.
    struct AlarmRequest: Identifiable, Hashable {
        enum Kind: Hashable {
            /// Next occurrence of a wall-clock time (today or tomorrow).
            case fixedTime(hour: Int, minute: Int)
            /// Countdown timer, in seconds.
            case countdown(TimeInterval)
        }

        let id = UUID()
        let kind: Kind
        let label: String?

        var kindNoun: String {
            switch kind {
            case .fixedTime: return "alarm"
            case .countdown: return "timer"
            }
        }

        /// Human summary for the confirm gate and the transcript receipt,
        /// e.g. `alarm "wake up" at 6:30 AM` / `timer for 25m`.
        var summary: String {
            let subject: String
            switch kind {
            case .fixedTime(let hour, let minute):
                var components = DateComponents()
                components.hour = hour
                components.minute = minute
                let time = Calendar.current.date(from: components)
                    .map { $0.formatted(date: .omitted, time: .shortened) }
                    ?? String(format: "%d:%02d", hour, minute)
                subject = "at \(time)"
            case .countdown(let seconds):
                let formatter = DateComponentsFormatter()
                formatter.allowedUnits = [.hour, .minute, .second]
                formatter.unitsStyle = .abbreviated
                let duration = formatter.string(from: seconds) ?? "\(Int(seconds))s"
                subject = "for \(duration)"
            }
            if let label, !label.isEmpty {
                return "\(kindNoun) “\(label)” \(subject)"
            }
            return "\(kindNoun) \(subject)"
        }
    }

    // MARK: - Parsing

    /// Parses a `/alarm` argument into a request, or nil when no time is
    /// recognizable. Grammar: first token is the time — a duration
    /// (`25m`, `1h30m`, `90s`) or a wall-clock time (`6:30`, `6:30pm`,
    /// `18:45`, `7pm`; a standalone `am`/`pm` second token folds in) — and
    /// everything after it is the label. A bare number (`/alarm 7`) is
    /// deliberately rejected as ambiguous.
    nonisolated static func parse(_ argument: String) -> AlarmRequest? {
        let trimmed = argument.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var tokens = trimmed.split(separator: " ").map(String.init)
        guard !tokens.isEmpty else { return nil }
        var timeToken = tokens.removeFirst().lowercased()
        if let meridiem = tokens.first?.lowercased(), meridiem == "am" || meridiem == "pm" {
            timeToken += meridiem
            tokens.removeFirst()
        }
        let label = tokens.isEmpty ? nil : tokens.joined(separator: " ")

        if let duration = parseDuration(timeToken) {
            return AlarmRequest(kind: .countdown(duration), label: label)
        }
        if let (hour, minute) = parseClockTime(timeToken) {
            return AlarmRequest(kind: .fixedTime(hour: hour, minute: minute), label: label)
        }
        return nil
    }

    private nonisolated static func parseDuration(_ token: String) -> TimeInterval? {
        let pattern = /^(?:(\d{1,3})h)?(?:(\d{1,3})m(?:in)?)?(?:(\d{1,4})s)?$/
        guard let match = token.wholeMatch(of: pattern) else { return nil }
        let hours = match.1.flatMap { Int($0) } ?? 0
        let minutes = match.2.flatMap { Int($0) } ?? 0
        let seconds = match.3.flatMap { Int($0) } ?? 0
        let total = TimeInterval(hours * 3_600 + minutes * 60 + seconds)
        return total > 0 ? total : nil
    }

    private nonisolated static func parseClockTime(_ token: String) -> (hour: Int, minute: Int)? {
        let pattern = /^(\d{1,2})(?::(\d{2}))?(am|pm)?$/
        guard let match = token.wholeMatch(of: pattern) else { return nil }
        guard var hour = Int(match.1) else { return nil }
        let minute = match.2.flatMap { Int($0) } ?? 0
        let meridiem = match.3.map(String.init)

        // A bare hour ("/alarm 7") is ambiguous — require a colon or am/pm.
        guard match.2 != nil || meridiem != nil else { return nil }
        guard (0...59).contains(minute) else { return nil }

        if let meridiem {
            guard (1...12).contains(hour) else { return nil }
            if meridiem == "pm", hour != 12 { hour += 12 }
            if meridiem == "am", hour == 12 { hour = 0 }
        } else {
            guard (0...23).contains(hour) else { return nil }
        }
        return (hour, minute)
    }

    /// Next wall-clock occurrence of hour:minute strictly after `referenceDate`
    /// — today if still ahead, otherwise tomorrow.
    nonisolated static func nextOccurrence(
        hour: Int,
        minute: Int,
        after referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> Date? {
        calendar.nextDate(
            after: referenceDate,
            matching: DateComponents(hour: hour, minute: minute),
            matchingPolicy: .nextTime
        )
    }

    // MARK: - Scheduling

    /// Schedules a confirmed request with AlarmKit. Requests authorization on
    /// first use (`NSAlarmKitUsageDescription` backs the prompt; no App Store
    /// entitlement involved).
    func schedule(_ request: AlarmRequest) async throws {
        try await ensureAuthorized()

        let title = request.label?.isEmpty == false ? request.label! : "Hermes \(request.kindNoun)"
        let titleResource = LocalizedStringResource(String.LocalizationValue(title))
        // Deep Field hero cyan (ThemePaletteCore) — a static value because the
        // attributes are encoded into the system alarm, not theme-resolved live.
        let tint = Color(hex: "54E6F0")
        let stopButton = AlarmButton(text: "Stop", textColor: .white, systemImageName: "stop.circle")
        let alert = AlarmPresentation.Alert(title: titleResource, stopButton: stopButton)
        let metadata = TalariaAlarmMetadata(label: request.label)

        switch request.kind {
        case .fixedTime(let hour, let minute):
            guard let fireDate = Self.nextOccurrence(hour: hour, minute: minute) else {
                throw AlarmSchedulingError.invalidTime
            }
            let attributes = AlarmAttributes(
                presentation: AlarmPresentation(alert: alert),
                metadata: metadata,
                tintColor: tint
            )
            let configuration = AlarmManager.AlarmConfiguration(
                schedule: .fixed(fireDate),
                attributes: attributes
            )
            _ = try await AlarmManager.shared.schedule(id: request.id, configuration: configuration)
            alarmLog.notice("scheduled fixed alarm for \(fireDate, privacy: .public)")

        case .countdown(let seconds):
            // The countdown presentation drives the dedicated Live Activity in
            // the widget bundle (TalariaAlarmLiveActivity) — its own
            // ActivityConfiguration typed on AlarmAttributes, never a new case
            // on the Hermes activity (#16 caveat).
            let countdown = AlarmPresentation.Countdown(title: titleResource)
            let attributes = AlarmAttributes(
                presentation: AlarmPresentation(alert: alert, countdown: countdown),
                metadata: metadata,
                tintColor: tint
            )
            let configuration = AlarmManager.AlarmConfiguration(
                countdownDuration: .init(preAlert: seconds, postAlert: nil),
                attributes: attributes
            )
            _ = try await AlarmManager.shared.schedule(id: request.id, configuration: configuration)
            alarmLog.notice("scheduled countdown timer (\(Int(seconds))s)")
        }
    }

    private func ensureAuthorized() async throws {
        switch AlarmManager.shared.authorizationState {
        case .authorized:
            return
        case .notDetermined:
            let state = try await AlarmManager.shared.requestAuthorization()
            guard state == .authorized else { throw AlarmSchedulingError.notAuthorized }
        case .denied:
            throw AlarmSchedulingError.notAuthorized
        @unknown default:
            throw AlarmSchedulingError.notAuthorized
        }
    }
}
