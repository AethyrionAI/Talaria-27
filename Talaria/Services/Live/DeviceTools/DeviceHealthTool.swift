import Foundation
import FoundationModels
import HealthKit

/// HealthKit read tool (#28) — rides the same `HealthQueryCore` primitives as
/// the sensor snapshot and the #15 widget tiles, so query windows and
/// rounding agree everywhere a number is shown.
struct DeviceHealthTool: Tool {
    let name = "readHealth"
    let description = "Read the user's health data from Apple Health: steps today, active calories today, latest heart rate, and last night's sleep."
    let relay: ToolEventRelay

    @Generable
    struct Arguments {
        @Guide(description: "Which metric to read: \"steps\", \"calories\", \"heartRate\", \"sleep\", or \"summary\" for all of them.")
        var metric: String
    }

    /// Read-only authorization set. Share types deliberately empty — this
    /// belt never writes health data.
    private static var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = []
        if let steps = HKObjectType.quantityType(forIdentifier: .stepCount) { types.insert(steps) }
        if let energy = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) { types.insert(energy) }
        if let heart = HKObjectType.quantityType(forIdentifier: .heartRate) { types.insert(heart) }
        types.insert(HKCategoryType(.sleepAnalysis))
        return types
    }

    func call(arguments: Arguments) async throws -> String {
        let metric = arguments.metric.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        await relay.started(name, detail: metric)
        defer { Task { await relay.completed(name) } }

        guard HKHealthStore.isHealthDataAvailable() else {
            return "Health data isn't available on this device."
        }
        let store = HKHealthStore()
        // Contextual priming (#31): the Health sheet appears on the first
        // health question. Settings grants alone don't suffice — an explicit
        // in-app request is required every process (hard-won HealthKit rule).
        do {
            try await store.requestAuthorization(toShare: [], read: Self.readTypes)
        } catch {
            return "Couldn't request Health access: \(error.localizedDescription)"
        }

        let now = Date()
        let dayStart = HealthQueryCore.startOfToday(for: now)
        var lines: [String] = []

        func wantsMetric(_ key: String) -> Bool {
            metric.isEmpty || metric.contains("summary") || metric.contains("all") || metric.contains(key)
        }

        if wantsMetric("step") {
            if let steps = await HealthQueryCore.cumulativeSum(
                .stepCount, unit: .count(), from: dayStart, to: now, store: store
            ) {
                lines.append("Steps today: \(Int(steps.rounded()))")
            } else {
                lines.append("Steps today: no data recorded.")
            }
        }
        if wantsMetric("calorie") || wantsMetric("energy") {
            if let calories = await HealthQueryCore.cumulativeSum(
                .activeEnergyBurned, unit: .kilocalorie(), from: dayStart, to: now, store: store
            ) {
                lines.append("Active calories today: \(Int(calories.rounded())) kcal")
            } else {
                lines.append("Active calories today: no data recorded.")
            }
        }
        if wantsMetric("heart") {
            if let (bpm, at) = await HealthQueryCore.latestSample(
                .heartRate,
                unit: .count().unitDivided(by: .minute()),
                from: now.addingTimeInterval(-HealthQueryCore.heartRateLookback),
                store: store
            ) {
                let formatter = RelativeDateTimeFormatter()
                lines.append("Latest heart rate: \(Int(bpm.rounded())) bpm (\(formatter.localizedString(for: at, relativeTo: now)))")
            } else {
                lines.append("Heart rate: no sample in the last 24 hours.")
            }
        }
        if wantsMetric("sleep") {
            if let hours = await HealthQueryCore.sleepDuration(
                attributedTo: HealthQueryCore.sleepBucketDay(for: now), store: store
            ) {
                lines.append("Sleep last night: \(DeviceToolFormat.hoursMinutes(fromHours: hours))")
            } else {
                lines.append("Sleep last night: no data recorded.")
            }
        }

        guard !lines.isEmpty else {
            return "Unknown health metric \"\(metric)\" — supported: steps, calories, heartRate, sleep, summary."
        }
        // HealthKit hides read-denial by design: denied reads look identical
        // to empty data. Say so whenever everything came back empty, so the
        // model never presents a permission problem as a zero.
        if lines.allSatisfy({ $0.contains("no data") || $0.contains("no sample") }) {
            lines.append("(If Health access wasn't granted, denied data is indistinguishable from empty — the user can check Settings → Health → Data Access & Devices → Talaria.)")
        }
        return lines.joined(separator: "\n")
    }
}
