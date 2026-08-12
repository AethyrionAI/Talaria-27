import Foundation
import FoundationModels
import UIKit
import os

// #334: the READ-ONLY FoundationModels measurement instruments — the three
// that measure the MODEL rather than its behaviour on prompts.
//
// They live here rather than in `LocalChatBackend+Battery.swift` because they
// share nothing with the battery's trial loop: no prompt set, no belt, no
// confirmation gate, no reap. What they DO share is the recorder, and that
// sharing is mandatory rather than stylistic — the #333 conductor calls a run
// `completed` only when a NEW `BatteryRunRecord` appears in the store, so an
// instrument that measured beautifully into `batteryEmit` and never opened a
// recorder run is, to the unattended runner, a FAILED run. Every method below
// opens a run, records every row through it (error rows included), and closes
// it on every path.
//
// **`tokenCount()` concurrent with a live streaming turn KILLS the turn**
// (ModelManagerError 1001, measured — #228 Lane 0.2 revised its own budget
// instrument for exactly this). Nothing here starts a streaming turn; the one
// band that generates at all (`fm-asymmetries` band 3) does so with no
// tokenCount in flight, and all three run at launch under the #333 conductor,
// where no live turn exists.
#if DEBUG
extension LocalChatBackend {

    // MARK: - #334 shared measurement plumbing

    /// One measurement taken `repeats` times, with the FAILURE PATH COUNTED
    /// rather than swallowed.
    ///
    /// `21F0C10D`'s rule, restated for a token-count instrument: a band with
    /// no error counter reports fail-safe noise as data. A tokenCount that
    /// throws contributes to no value here and is counted in `errors`; a row
    /// whose `scored` is 0 and whose `errors` is `repeats` is a row that
    /// measured NOTHING, and it says so instead of reporting an empty min/max
    /// as a clean result.
    ///
    /// Repeats also carry the determinism claim. Token counts SHOULD be
    /// deterministic — if `distinct > 1` the tokenizer is not a fixed
    /// function of its input, which is a finding in itself and is why the row
    /// records min/max/distinct rather than one number.
    struct RepeatedMeasurement {
        var repeats: Int
        var values: [Int] = []
        var errors = 0
        var firstError: String?
        var lowest: Int? { values.min() }
        var highest: Int? { values.max() }
        var distinct: Int { Set(values).count }
    }

    /// Runs `body` `repeats` times, collecting values and counting throws.
    func measureRepeatedly(_ repeats: Int,
                           _ body: () async throws -> Int) async -> RepeatedMeasurement {
        var measurement = RepeatedMeasurement(repeats: repeats)
        for _ in 0 ..< repeats {
            do {
                measurement.values.append(try await body())
            } catch {
                measurement.errors += 1
                if measurement.firstError == nil {
                    measurement.firstError = String(String(describing: error).prefix(200))
                }
            }
        }
        return measurement
    }

    /// Turns one `RepeatedMeasurement` into ONE probe row in the open run,
    /// and emits the same numbers to the three battery sinks.
    ///
    /// The row's `correct/trials` is defined once, here, so no band invents
    /// its own meaning: **`correct` = repeats that produced a value AND (when
    /// the row has a `cap`) fit under it**; `trials` = repeats attempted. A
    /// capless row therefore reports its scored count, and a capped row
    /// reports its fit count — both against the same denominator, with
    /// `errors` naming the difference.
    func recordMeasurementRow(_ measurement: RepeatedMeasurement,
                              probe: String, band: String, variant: String? = nil,
                              cap: Int? = nil,
                              extraMetrics: [String: Double] = [:],
                              notes: [String: String] = [:]) {
        var metrics = extraMetrics
        if let first = measurement.values.first { metrics["value"] = Double(first) }
        if let lowest = measurement.lowest { metrics["min"] = Double(lowest) }
        if let highest = measurement.highest { metrics["max"] = Double(highest) }
        metrics["distinct"] = Double(measurement.distinct)
        metrics["scored"] = Double(measurement.values.count)
        metrics["errors"] = Double(measurement.errors)
        if let cap {
            metrics["cap"] = Double(cap)
            // Headroom off the WORST observed value, never the first — a
            // headroom quoted from the best repeat is the number that flatters.
            if let highest = measurement.highest { metrics["headroom"] = Double(cap - highest) }
        }
        var notes = notes
        if let firstError = measurement.firstError { notes["firstError"] = firstError }
        let fitting = cap.map { limit in measurement.values.filter { $0 <= limit }.count }
            ?? measurement.values.count
        let headroomText = cap.flatMap { limit in measurement.highest.map { String(limit - $0) } } ?? "—"
        Self.batteryEmit("preflight: [\(band)] \(probe) value=\(measurement.values.first.map(String.init) ?? "—") min=\(measurement.lowest.map(String.init) ?? "—") max=\(measurement.highest.map(String.init) ?? "—") distinct=\(measurement.distinct) fit=\(fitting)/\(measurement.repeats) scored=\(measurement.values.count)/\(measurement.repeats) errors=\(measurement.errors) cap=\(cap.map(String.init) ?? "—") headroom=\(headroomText) extra=\(extraMetrics.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",")) notes=\(notes.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ","))")
        Self.batteryRecorder.recordProbe(
            probe: probe, expected: true, correct: fitting, trials: measurement.repeats,
            variant: variant, band: band, errors: measurement.errors,
            metrics: metrics, notes: notes.isEmpty ? nil : notes)
    }

    // MARK: - #334 A: `tokencount-preflight` (#257's mandatory pre-flight)

    /// #257's **MANDATORY PRE-FLIGHT — the `21F0C10D` gate**, finally
    /// instrumented (#334).
    ///
    /// #257 queued this before any capability-detection run and it has been
    /// owed since: *"measure the two-field schema's real cost with
    /// `tokenCount` ON DEVICE, outside a live turn."* The hazard it guards is
    /// the exact failure that made run `21F0C10D` worthless — an 11-field
    /// schema reused the 64-token cap, every generation truncated mid-JSON,
    /// the router's catch arm failed safe to ARMED, and **165/165 pure
    /// instrument errors read as a plausible behavioral verdict.** The
    /// capability probe inherits that shape: its catch arm also fails safe to
    /// armed, so a two-field response that does not fit its cap would report
    /// "detection doesn't work" while measuring nothing at all.
    ///
    /// Only a DEVICE can answer it. The test host reports
    /// `isAvailable == true` and then throws on every generation
    /// (availability ≠ generability), and on beta5 the simulator's
    /// `contextSize` reads 0 — so on a sim this instrument produces error
    /// rows, which is the honest result there and still closes its record.
    ///
    /// **What it measures, all outside any turn:**
    /// - the INPUT halves of the payload the probe submits — production's own
    ///   router instructions, the prompt envelope for the worst (longest) of
    ///   the ten pinned baseline rows, and both generation SCHEMAS — plus
    ///   their sum, against the model's `contextSize`;
    /// - the OUTPUT side, which is what a `maximumResponseTokens` cap
    ///   actually governs: the worst-case serialized JSON each schema can
    ///   produce, against the cap that schema really generates under. Caps
    ///   are READ from the production constants (`twoFieldRouterOptions`,
    ///   `toolIntentRouterOptions`), never retyped here — a hardcoded 128
    ///   would keep reporting comfortable headroom the day someone changed
    ///   the constant.
    ///
    /// `trials` is a REPEAT COUNT, not a trial count: token counts should be
    /// deterministic, and the repeats are what turn "should" into a measured
    /// `distinct` per row.
    func runTokenCountPreflight(trials: Int) async {
        guard await Self.beginBatteryRun() else {
            Self.batteryEmit("battery: REFUSED — another battery is already running (#200B mutex)")
            return
        }
        defer { Self.endBatteryRun() }
        let repeats = max(1, trials)
        let model = self.model
        Self.batteryEmit("preflight: TOKENCOUNT PREFLIGHT START repeats=\(repeats) (#257/#334)")
        Self.batteryRecorder.beginRun(trialsPerCell: repeats,
                                      cells: ["tokencount-preflight"],
                                      kind: "tokencount-preflight")

        // The payload, rebuilt from PRODUCTION's own constants — never a copy
        // of them. `routeTurn` builds exactly this: these instructions, this
        // envelope, this schema, under `twoFieldRouterOptions`.
        let instructionsText = Self.routerInstructions(
            for: Self.productionRouterVariant,
            includeImageGuide: Self.productionIncludesImageGuide)
        // The LONGEST of the ten pinned baseline rows. A headroom measured on
        // "What's 2+2?" would flatter the payload; the worst row is the one a
        // cap has to survive.
        let worstRow = Self.routerBaselineProbes.map(\.text).max { $0.count < $1.count } ?? ""
        let promptText = Self.routerPrompt(context: "", prompt: worstRow,
                                           variant: Self.productionRouterVariant)
        let twoFieldCap = Self.twoFieldRouterOptions.maximumResponseTokens
        let oneFieldCap = Self.toolIntentRouterOptions.maximumResponseTokens
        // The worst case the guided decoder can emit for each schema: every
        // field present with the LONGER boolean literal. Guided generation
        // constrains decode to the schema, so this is the ceiling, not a guess
        // at typical output.
        let twoFieldResponse = #"{"needsDeviceTool":false,"isCapabilityQuestion":false}"#
        let oneFieldResponse = #"{"needsDeviceTool":false}"#

        // Band 1 — the window itself. Not a tokenCount and cannot throw, so
        // it is recorded with errors: 0 by construction; on a sim it reads 0,
        // which is the beta5 finding rather than an error.
        let context = await measureRepeatedly(repeats) { model.contextSize }
        recordMeasurementRow(context, probe: "SystemLanguageModel.contextSize",
                             band: "context")

        // Band 2 — the INPUT halves and their sum.
        let instructionTokens = await measureRepeatedly(repeats) {
            try await model.tokenCount(for: Instructions(instructionsText))
        }
        recordMeasurementRow(instructionTokens, probe: "router instructions (production)",
                             band: "input", variant: Self.productionRouterVariant.rawValue)

        let promptTokens = await measureRepeatedly(repeats) {
            try await model.tokenCount(for: Prompt(promptText))
        }
        recordMeasurementRow(promptTokens, probe: "router prompt envelope (worst baseline row)",
                             band: "input", variant: Self.productionRouterVariant.rawValue,
                             notes: ["row": worstRow])

        let twoFieldSchemaTokens = await measureRepeatedly(repeats) {
            try await model.tokenCount(for: ToolIntentRoute.generationSchema)
        }
        recordMeasurementRow(twoFieldSchemaTokens, probe: "ToolIntentRoute.generationSchema (2-field)",
                             band: "input", variant: "two-field")

        let oneFieldSchemaTokens = await measureRepeatedly(repeats) {
            try await model.tokenCount(for: ToolIntentRouteSingleField.generationSchema)
        }
        recordMeasurementRow(oneFieldSchemaTokens, probe: "ToolIntentRouteSingleField.generationSchema (1-field)",
                             band: "input", variant: "one-field")

        // The sum measured as its own repeat, so a partial failure fails the
        // WHOLE payload row rather than silently summing two of three halves.
        let payloadTokens = await measureRepeatedly(repeats) {
            let instructions = try await model.tokenCount(for: Instructions(instructionsText))
            let prompt = try await model.tokenCount(for: Prompt(promptText))
            let schema = try await model.tokenCount(for: ToolIntentRoute.generationSchema)
            return instructions + prompt + schema
        }
        recordMeasurementRow(payloadTokens,
                             probe: "two-field router payload = instructions + prompt + schema",
                             band: "payload", variant: "two-field",
                             cap: context.values.first.flatMap { $0 > 0 ? $0 : nil })

        // Band 3 — the OUTPUT side, which is what the cap governs and what
        // `21F0C10D` actually overflowed.
        let twoFieldResponseTokens = await measureRepeatedly(repeats) {
            try await model.tokenCount(for: twoFieldResponse)
        }
        recordMeasurementRow(twoFieldResponseTokens,
                             probe: "worst-case 2-field response JSON vs twoFieldRouterOptions",
                             band: "response-cap", variant: "two-field", cap: twoFieldCap,
                             notes: ["json": twoFieldResponse])

        let oneFieldResponseTokens = await measureRepeatedly(repeats) {
            try await model.tokenCount(for: oneFieldResponse)
        }
        recordMeasurementRow(oneFieldResponseTokens,
                             probe: "worst-case 1-field response JSON vs toolIntentRouterOptions",
                             band: "response-cap", variant: "one-field", cap: oneFieldCap,
                             notes: ["json": oneFieldResponse])

        Self.batteryEmit("preflight: TOKENCOUNT PREFLIGHT DONE (#257/#334)")
        Self.batteryRecorder.endRun()
    }
}
#endif
