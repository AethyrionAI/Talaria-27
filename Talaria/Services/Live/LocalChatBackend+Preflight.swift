import Foundation
import FoundationModels
import UIKit
import os

// #335: the READ-ONLY FoundationModels measurement instruments — the three
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

    // MARK: - #335 shared measurement plumbing

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

    // MARK: - #335 A: `tokencount-preflight` (#257's mandatory pre-flight)

    /// #257's **MANDATORY PRE-FLIGHT — the `21F0C10D` gate**, finally
    /// instrumented (#335).
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
        Self.batteryEmit("preflight: TOKENCOUNT PREFLIGHT START repeats=\(repeats) (#257/#335)")
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

        Self.batteryEmit("preflight: TOKENCOUNT PREFLIGHT DONE (#257/#335)")
        Self.batteryRecorder.endRun()
    }

    // MARK: - #335 B: `fm-asymmetries` (#324-W3)

    /// The filler sentence the boundary band is built from. Pinned and
    /// deterministic — a random or lorem payload would make two runs of the
    /// same instrument incomparable, and the whole question is whether the
    /// SAME text counts differently at two sizes.
    nonisolated static let asymmetryFillerSentence =
        "The quick brown fox jumps over the lazy dog beside the river at dawn. "

    /// Roughly `approximateTokens` tokens of that filler.
    ///
    /// ~4 characters per token is a working ratio for this tokenizer family,
    /// and the instrument does not depend on it being right: every row records
    /// the TARGET, the character count and the MEASURED count, so a wrong
    /// ratio shows up as a number rather than silently moving the boundary
    /// the band exists to straddle.
    nonisolated static func asymmetryFiller(approximateTokens: Int,
                                            charsPerToken: Int = 4) -> String {
        let target = max(1, approximateTokens * charsPerToken)
        var text = ""
        text.reserveCapacity(target + asymmetryFillerSentence.count)
        while text.count < target { text += asymmetryFillerSentence }
        return text
    }

    /// The plain-generation probe for the cap band. Instructions and prompt
    /// are pinned so the only variable is the cap.
    nonisolated static let responseCapProbeInstructions =
        "You are a helpful assistant. Answer in prose."
    nonisolated static let responseCapProbePrompt =
        "Write a paragraph about the sea."
    /// Deliberately far below anything a paragraph could fit in — #208
    /// measured real turns at 25–49 output tokens, so 8 is guaranteed to
    /// BIND, which is the precondition Apple's own "a strict cap can lead to
    /// malformed results" warning needs before it means anything.
    nonisolated static let responseCapProbeCap = 8

    /// #335 B / #324-W3 — the three FoundationModels behaviours the beta5 SDK
    /// audit could not settle off-device, each its own labeled band.
    ///
    /// The audit's own words on why this needs hardware: on the simulator
    /// `tokenCount` **throws** (`ModelManagerError 1026`) and `contextSize`
    /// reads **0**, so the boundary question is *"device asymmetry
    /// unmeasurable off-device"* in as many words. Everything here therefore
    /// produces error rows on a sim and real numbers on a device — and the
    /// rows say which, rather than reporting an absent measurement as a
    /// finding.
    ///
    /// 1. **`boundary`** — the same pinned filler text sized for ~4096 and
    ///    ~8192 tokens. The asymmetry question is whether counting behaves
    ///    differently across that boundary; the row records both counts, the
    ///    character counts, and BOTH ratios, because a tokenizer that clamps
    ///    at the window shows up as `tokenRatio < charRatio` and a tokenizer
    ///    that refuses shows up as an error tally.
    /// 2. **`variant`** — `SystemLanguageModel.variant.displayName`, new in
    ///    beta5. The row's numeric value is the string's LENGTH; the
    ///    measurement itself is the string, in `notes`.
    ///    **⚠️ This symbol is why the whole app must run on a beta5 runtime:**
    ///    a beta5-built binary referencing a new-in-beta5 symbol dies at dyld
    ///    launch on a beta4 27.0 runtime (#324, proven), and `@available`
    ///    cannot weak-link between betas of one version.
    /// 3. **`response-cap-behavior`** — one plain generation under a cap far
    ///    below the answer it asks for. GUIDED generation is known to THROW
    ///    when the schema cannot fit its cap; plain generation is unmeasured,
    ///    and "throws" vs "truncates" changes what a caller must handle. The
    ///    band classifies what THIS build does and records the evidence —
    ///    the error for a throw, the output length for a truncation.
    ///
    /// **Ordering is load-bearing:** the generating band runs LAST, after
    /// every tokenizer round trip has returned. `tokenCount()` concurrent
    /// with a live turn kills the turn (ModelManagerError 1001, measured), so
    /// the two are never in flight together here.
    func runFMAsymmetriesProbe(trials: Int) async {
        guard await Self.beginBatteryRun() else {
            Self.batteryEmit("battery: REFUSED — another battery is already running (#200B mutex)")
            return
        }
        defer { Self.endBatteryRun() }
        let repeats = max(1, trials)
        let model = self.model
        Self.batteryEmit("preflight: FM ASYMMETRIES START repeats=\(repeats) (#324-W3/#335)")
        Self.batteryRecorder.beginRun(
            trialsPerCell: repeats,
            cells: ["boundary", "variant", "response-cap-behavior"],
            kind: "fm-asymmetries")

        // Band 1 — the 4096 / 8192 boundary.
        let near4096 = Self.asymmetryFiller(approximateTokens: 4096)
        let near8192 = Self.asymmetryFiller(approximateTokens: 8192)
        let lower = await measureRepeatedly(repeats) {
            try await model.tokenCount(for: Prompt(near4096))
        }
        var lowerMetrics: [String: Double] = ["targetTokens": 4096, "chars": Double(near4096.count)]
        if let value = lower.values.first, value > 0 {
            lowerMetrics["measuredCharsPerToken"] = Double(near4096.count) / Double(value)
        }
        recordMeasurementRow(lower, probe: "synthetic payload sized for ~4096 tokens",
                             band: "boundary", variant: "4096", extraMetrics: lowerMetrics)

        let upper = await measureRepeatedly(repeats) {
            try await model.tokenCount(for: Prompt(near8192))
        }
        var upperMetrics: [String: Double] = ["targetTokens": 8192, "chars": Double(near8192.count),
                                              "charRatioVs4096": Double(near8192.count) / Double(near4096.count)]
        if let value = upper.values.first, value > 0 {
            upperMetrics["measuredCharsPerToken"] = Double(near8192.count) / Double(value)
        }
        if let low = lower.values.first, let high = upper.values.first, low > 0 {
            // The comparison the band exists for: a tokenizer that simply
            // counts returns this ~equal to `charRatioVs4096`; one that clamps
            // at the window returns it LOWER. Recorded, never interpreted here.
            upperMetrics["tokenRatioVs4096"] = Double(high) / Double(low)
        }
        recordMeasurementRow(upper, probe: "synthetic payload sized for ~8192 tokens",
                             band: "boundary", variant: "8192", extraMetrics: upperMetrics)

        // Band 2 — the new beta5 variant surface. Reading it cannot throw, so
        // this row's errors are 0 by construction; what makes it worth
        // recording is the STRING, which no sim can produce meaningfully.
        let variantName = model.variant.displayName
        let variantRead = await measureRepeatedly(repeats) { model.variant.displayName.count }
        recordMeasurementRow(variantRead,
                             probe: "SystemLanguageModel.variant.displayName (length; the string is in notes)",
                             band: "variant",
                             extraMetrics: ["contextSize": Double(model.contextSize)],
                             notes: ["displayName": variantName,
                                     "isCore3": String(model.variant == .core3),
                                     "isCoreAdvanced3": String(model.variant == .coreAdvanced3),
                                     "availability": String(describing: model.availability)])

        // Band 3 — throw vs truncate, and it GENERATES, so it goes last.
        var truncatedCount = 0
        var threwCount = 0
        var timedOutCount = 0
        var outputTokens: [Int] = []
        var outputChars: [Int] = []
        var firstError: String?
        for trial in 1...repeats {
            let session = LanguageModelSession(
                model: model,
                instructions: Instructions(Self.responseCapProbeInstructions))
            let respondTask = Task {
                try await session.respond(
                    to: Prompt(Self.responseCapProbePrompt),
                    options: GenerationOptions(maximumResponseTokens: Self.responseCapProbeCap))
            }
            let timeoutTask = Task { try? await Task.sleep(for: .seconds(35)); respondTask.cancel() }
            do {
                let response = try await respondTask.value
                timeoutTask.cancel()
                truncatedCount += 1
                outputTokens.append(response.usage.output.totalTokenCount)
                outputChars.append(response.content.count)
                Self.batteryEmit("preflight: [response-cap-behavior] t=\(trial) TRUNCATED outTok=\(response.usage.output.totalTokenCount) chars=\(response.content.count) text=\(response.content.replacingOccurrences(of: "\n", with: " / ").prefix(200))")
            } catch is CancellationError {
                timeoutTask.cancel()
                timedOutCount += 1
                Self.batteryEmit("preflight: [response-cap-behavior] t=\(trial) TIMEOUT — guillotined at 35s")
            } catch {
                timeoutTask.cancel()
                threwCount += 1
                if firstError == nil { firstError = String(String(describing: error).prefix(200)) }
                Self.batteryEmit("preflight: [response-cap-behavior] t=\(trial) THREW error=\(String(String(describing: error).prefix(200)))")
            }
        }
        // "none" is a real, reportable outcome: a band where every trial timed
        // out has measured NOTHING, and must not be read as "it truncated".
        let behavior: String
        switch (threwCount > 0, truncatedCount > 0) {
        case (true, true): behavior = "mixed"
        case (true, false): behavior = "threw"
        case (false, true): behavior = "truncated"
        case (false, false): behavior = "none"
        }
        var capMetrics: [String: Double] = [
            "cap": Double(Self.responseCapProbeCap),
            "truncated": Double(truncatedCount),
            "threw": Double(threwCount),
            "timedOut": Double(timedOutCount),
            "scored": Double(truncatedCount + threwCount),
            "errors": Double(threwCount + timedOutCount),
        ]
        if let low = outputTokens.min() { capMetrics["outputTokensMin"] = Double(low) }
        if let high = outputTokens.max() { capMetrics["outputTokensMax"] = Double(high) }
        if let high = outputChars.max() { capMetrics["outputCharsMax"] = Double(high) }
        var capNotes = ["behavior": behavior]
        if let firstError { capNotes["firstError"] = firstError }
        Self.batteryEmit("preflight: [response-cap-behavior] SUMMARY behavior=\(behavior) truncated=\(truncatedCount)/\(repeats) threw=\(threwCount)/\(repeats) timedOut=\(timedOutCount)/\(repeats) cap=\(Self.responseCapProbeCap) outTok=\(outputTokens.map(String.init).joined(separator: ","))")
        Self.batteryRecorder.recordProbe(
            probe: "plain generation under maximumResponseTokens=\(Self.responseCapProbeCap)",
            expected: true, correct: truncatedCount, trials: repeats,
            variant: "plain", band: "response-cap-behavior",
            errors: threwCount + timedOutCount,
            metrics: capMetrics, notes: capNotes)

        Self.batteryEmit("preflight: FM ASYMMETRIES DONE (#324-W3/#335)")
        Self.batteryRecorder.endRun()
    }

    // MARK: - #335 C: `condensation-fit` (#210's residual)

    /// #210's recorded ceiling — the device said *"Provided 8,583 tokens, but
    /// the maximum allowed is 8,192"*. Pinned as the verdict line so the
    /// instrument answers the question that was actually asked; the RUNTIME
    /// budget is recorded beside every row, so a reader can re-score against
    /// the real window without re-running anything.
    nonisolated static let condensationFitCeiling = 8192

    /// A synthetic transcript engineered to overflow that ceiling.
    ///
    /// Synthetic BY DESIGN. Reading the user's real `ChatStore` would measure
    /// whatever happened to be in the app that day, could not be re-run, and
    /// would answer a question about one conversation rather than about the
    /// mechanism — and #210's residual is about the mechanism. 12 turns at
    /// ~900 tokens is ~10,800 tokens, comfortably over 8,192, and each turn is
    /// numbered so the condensed memory block is readable rather than a wall
    /// of identical filler.
    nonisolated static func condensationOverflowTranscript(
        turnCount: Int = 12, approximateTokensPerTurn: Int = 900
    ) -> [TranscriptTurn] {
        (0 ..< turnCount).map { index in
            TranscriptTurn(
                role: index.isMultiple(of: 2) ? .user : .assistant,
                text: "Turn \(index + 1). " + asymmetryFiller(approximateTokens: approximateTokensPerTurn))
        }
    }

    /// #335 C / #210 — **does one forced condensation actually get an
    /// over-budget conversation back under the window?**
    ///
    /// #210's own *Still owed*, verbatim: *"the condensation budget itself is
    /// untouched and unmeasured. The guard now FIRES; whether one forced
    /// condensation actually gets a real long-conversation turn under 8,192 is
    /// a separate question and needs a measured run, not an assumption."*
    /// This is that run's instrument.
    ///
    /// **It calls production's condenser, it does not model one.**
    /// `sessionBlueprint(for:hasImageInContext:forceCondense:)` is the same
    /// function `rebuildSession` calls on the #26/#229 retry path; the only
    /// difference is where the turns come from. A reimplementation would be a
    /// measurement of a lookalike, which measures nothing.
    ///
    /// Per trial the record carries: the pre-condensation count (the ARMING
    /// evidence — a trial only counts if it is over the ceiling, MEASURED, per
    /// #215's rule that an unarmed cell measures a configuration the app never
    /// enters), the post-condensation count, how the split fell
    /// (condensed/verbatim turn counts), the runtime window and budget, the
    /// fits verdict, and the throw tally. Character counts ride along because
    /// they are knowable WITHOUT a model — on a sim, where every tokenCount
    /// throws, the record still shows the payload shrank rather than showing
    /// nothing at all.
    ///
    /// **Known limit, stated here rather than discovered later.** This is the
    /// PRE-TURN condensation shape: the instructions are whatever
    /// `effectiveInstructionsText` gives this backend right now, i.e. the
    /// belt-bearing text. #229's mid-turn overflow RETRY additionally disarms
    /// the belt, so its payload is strictly SMALLER than what this measures —
    /// the verdict here is therefore conservative, and the toolless
    /// instructions' own cost is recorded as a `reference` row so the
    /// difference is computable rather than guessed at.
    func runCondensationFitProbe(trials: Int) async {
        guard await Self.beginBatteryRun() else {
            Self.batteryEmit("battery: REFUSED — another battery is already running (#200B mutex)")
            return
        }
        defer { Self.endBatteryRun() }
        let repeats = max(1, trials)
        let model = self.model
        let ceiling = Self.condensationFitCeiling
        let turns = Self.condensationOverflowTranscript()
        let contextSize = model.contextSize
        let budget = max(1024, contextSize - Self.responseHeadroomTokens(for: activeTier))
        Self.batteryEmit("preflight: CONDENSATION FIT START repeats=\(repeats) turns=\(turns.count) ceiling=\(ceiling) contextSize=\(contextSize) budget=\(budget) tier=\(activeTier.rawValue) (#210/#335)")
        Self.batteryRecorder.beginRun(trialsPerCell: repeats,
                                      cells: ["condensation-fit"],
                                      kind: "condensation-fit")

        // Reference rows — the window, and the two instruction shapes, so the
        // conservative-direction caveat above is a NUMBER rather than a claim.
        let armedInstructions = effectiveInstructionsText(hasImageInContext: false)
        let toollessInstructions = Self.productionToollessInstructions(
            deviceContext: Self.deviceContextLine(), hasImageTools: false)
        let armedInstructionTokens = await measureRepeatedly(1) {
            try await model.tokenCount(for: Instructions(armedInstructions))
        }
        recordMeasurementRow(armedInstructionTokens,
                             probe: "instructions this backend would send (belt-bearing)",
                             band: "reference", variant: "armed",
                             extraMetrics: ["chars": Double(armedInstructions.count),
                                            "contextSize": Double(contextSize),
                                            "budget": Double(budget),
                                            "ceiling": Double(ceiling)])
        let toollessInstructionTokens = await measureRepeatedly(1) {
            try await model.tokenCount(for: Instructions(toollessInstructions))
        }
        recordMeasurementRow(toollessInstructionTokens,
                             probe: "production toolless instructions (#229's retry shape)",
                             band: "reference", variant: "toolless",
                             extraMetrics: ["chars": Double(toollessInstructions.count)])

        var armedTrials = 0
        var fittingTrials = 0
        var unknownTrials = 0
        for trial in 1 ... repeats {
            var errors = 0
            var firstError: String?
            func count(_ entries: [Transcript.Entry]) async -> Int? {
                do { return try await model.tokenCount(for: entries) } catch {
                    errors += 1
                    if firstError == nil { firstError = String(String(describing: error).prefix(200)) }
                    return nil
                }
            }

            let preInstructions = effectiveInstructionsText(hasImageInContext: false)
            let preEntries = Self.transcriptEntries(instructions: preInstructions, verbatimTurns: turns)
            let preChars = preInstructions.count + turns.reduce(0) { $0 + $1.text.count }
            let pre = await count(preEntries)

            // PRODUCTION's condenser. The offer flag is sampled and restored
            // around it: arming #30's one-per-conversation escalation offer is
            // the one side effect this call has, and a measurement should not
            // leave the user an offer they never earned.
            let offerBefore = shouldOfferPrivateCloudEscalation
            let blueprint = await sessionBlueprint(for: turns, hasImageInContext: false,
                                                   forceCondense: true)
            let offerFired = shouldOfferPrivateCloudEscalation && !offerBefore
            restorePrivateCloudEscalationOffer(offerBefore)

            let postEntries = Self.transcriptEntries(instructions: blueprint.instructions,
                                                     verbatimTurns: blueprint.verbatimTurns)
            let postChars = blueprint.instructions.count
                + blueprint.verbatimTurns.reduce(0) { $0 + $1.text.count }
            let post = await count(postEntries)

            let armed = pre.map { $0 > ceiling }
            let fits = post.map { $0 <= ceiling }
            // FIVE outcomes, not three. "Armed but the post count threw" is
            // NOT the same claim as "armed and over" — collapsing them would
            // put an unmeasured trial on record as a failure, which is the
            // same laundering of unknown into finding that #213's error tally
            // exists to prevent. Only ARMED+FITS scores.
            let verdict: String
            switch (armed, fits) {
            case (.some(true), .some(true)):
                verdict = "ARMED+FITS"; armedTrials += 1; fittingTrials += 1
            case (.some(true), .some(false)):
                verdict = "ARMED+OVER"; armedTrials += 1
            case (.some(true), .none):
                verdict = "ARMED+FIT-UNKNOWN"; unknownTrials += 1
            case (.some(false), _):
                verdict = "UNARMED"; unknownTrials += 1
            case (.none, _):
                verdict = "ARMING-UNKNOWN"; unknownTrials += 1
            }

            var metrics: [String: Double] = [
                "preChars": Double(preChars), "postChars": Double(postChars),
                "condensedTurns": Double(turns.count - blueprint.verbatimTurns.count),
                "verbatimTurns": Double(blueprint.verbatimTurns.count),
                "totalTurns": Double(turns.count),
                "contextSize": Double(contextSize), "budget": Double(budget),
                "ceiling": Double(ceiling),
                "scored": Double(2 - errors), "errors": Double(errors),
                "memoryChars": Double(blueprint.condensedMemory?.count ?? 0),
            ]
            if let pre { metrics["preTokens"] = Double(pre) }
            if let post { metrics["postTokens"] = Double(post) }
            if let armed { metrics["armed"] = armed ? 1 : 0 }
            if let fits { metrics["fits"] = fits ? 1 : 0 }
            var notes: [String: String] = [
                "verdict": verdict,
                "escalationOfferFired": String(offerFired),
                "hasCondensedMemory": String(blueprint.condensedMemory != nil),
            ]
            if let firstError { notes["firstError"] = firstError }
            Self.batteryEmit("preflight: [condensation-fit] t=\(trial) verdict=\(verdict) pre=\(pre.map(String.init) ?? "—") post=\(post.map(String.init) ?? "—") ceiling=\(ceiling) armed=\(armed.map(String.init) ?? "—") fits=\(fits.map(String.init) ?? "—") preChars=\(preChars) postChars=\(postChars) condensed=\(turns.count - blueprint.verbatimTurns.count)/\(turns.count) memoryChars=\(blueprint.condensedMemory?.count ?? 0) errors=\(errors) offerFired=\(offerFired)")
            Self.batteryRecorder.recordProbe(
                probe: "forced condensation of a \(turns.count)-turn overflow transcript, trial \(trial)",
                expected: true, correct: (armed == true && fits == true) ? 1 : 0, trials: 1,
                variant: "forced", band: "condensation-fit", errors: errors,
                metrics: metrics, notes: notes)
        }

        // The summary row. `correct` counts trials that were ARMED AND FIT —
        // #215's rule in arithmetic: an unarmed trial is not a pass, it is not
        // a measurement, and it is counted separately so a run of them cannot
        // pool into a verdict.
        Self.batteryEmit("preflight: [condensation-fit] SUMMARY armed=\(armedTrials)/\(repeats) fits=\(fittingTrials)/\(armedTrials) unarmedOrUnknown=\(unknownTrials)/\(repeats) ceiling=\(ceiling)")
        Self.batteryRecorder.recordProbe(
            probe: "condensation fit summary (armed trials only)",
            expected: true, correct: fittingTrials, trials: repeats,
            variant: "forced", band: "summary", errors: unknownTrials,
            metrics: ["armedTrials": Double(armedTrials),
                      "fittingTrials": Double(fittingTrials),
                      "unarmedOrUnknownTrials": Double(unknownTrials),
                      "ceiling": Double(ceiling),
                      "contextSize": Double(contextSize),
                      "budget": Double(budget)],
            notes: ["verdict": armedTrials == 0
                    ? "NO TRIAL ARMED — #210's residual stays open; this run scores nothing"
                    : (fittingTrials == armedTrials ? "every armed trial fit" : "at least one armed trial did NOT fit")])

        Self.batteryEmit("preflight: CONDENSATION FIT DONE (#210/#335)")
        Self.batteryRecorder.endRun()
    }
}
#endif
