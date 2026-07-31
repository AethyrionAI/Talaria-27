import Foundation
import FoundationModels
import HealthKit

/// HealthKit read tool (#28) — rides the same `HealthQueryCore` primitives as
/// the sensor snapshot and the #15 widget tiles, so query windows and
/// rounding agree everywhere a number is shown.
struct DeviceHealthTool: Tool {
    let name = "readHealth"
    /// Static so the pinned rollback twin ships the SAME description — the
    /// two cells must differ in exactly one thing, the schema.
    static let productionDescription = "Read the user's health data from Apple Health: steps today, active calories today, latest heart rate, and last night's sleep."
    let description = DeviceHealthTool.productionDescription
    let relay: ToolEventRelay

    // #209: `metric` is OPTIONAL because the tool can default it, and because
    // a required one was killing whole turns. Dug out of the run records once
    // the classifier stopped hiding the cause behind the tool dump: FIVE
    // trials died on `GeneratedContent does not contain a property 'metric'.
    // Content: {}` — the model emitting an empty object rather than picking a
    // metric. `wantsMetric` ALREADY reads empty as "all of them", so nil lands
    // on exactly the summary path an explicit "summary" takes and no
    // well-formed call changes behaviour at all. Same shape as #200S/#200X,
    // and the same rule they set: the schema should demand only what the tool
    // cannot default. `DeviceHealthToolRequiredMetric` is the pinned rollback.
    @Generable
    struct Arguments {
        @Guide(description: "Which metric to read: \"steps\", \"calories\", \"heartRate\", \"sleep\", or \"summary\" for all of them. Leave empty for all of them.")
        var metric: String?
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
        await Self.performRead(rawMetric: arguments.metric, relay: relay, name: name)
    }

    /// nil and "" are the SAME request — everything. Shared with the pinned
    /// rollback so the two cells differ only in their schema, never in engine.
    static func normalizedMetric(_ raw: String?) -> String {
        (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func performRead(rawMetric: String?, relay: ToolEventRelay, name: String) async -> String {
        // An omitted metric lands on exactly the path an empty string took.
        let metric = normalizedMetric(rawMetric)
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

/// #209 PINNED ROLLBACK for the optional-`metric` schema. Identical to
/// `DeviceHealthTool` in name, description and engine — the ONLY delta is that
/// `metric` is REQUIRED, which is what production shipped until #209.
///
/// It exists for the same reason `CalendarEventToolRequiredFields` did, and
/// that reason paid off: the required-fields calendar twin is what let the
/// error records PROVE the mechanism, by throwing
/// `does not contain a property 'durationMinutes'` where the promoted tool
/// structurally could not. A rollback twin is not just a revert — it is the
/// control arm of a natural experiment that runs itself.
struct DeviceHealthToolRequiredMetric: Tool {
    let name = "readHealth"
    var description: String = DeviceHealthTool.productionDescription
    let relay: ToolEventRelay

    @Generable
    struct Arguments {
        @Guide(description: "Which metric to read: \"steps\", \"calories\", \"heartRate\", \"sleep\", or \"summary\" for all of them.")
        var metric: String
    }

    func call(arguments: Arguments) async throws -> String {
        await DeviceHealthTool.performRead(rawMetric: arguments.metric, relay: relay, name: name)
    }
}
