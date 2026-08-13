import Foundation
import FoundationModels
import UIKit
import os
#if DEBUG
import EventKit // #200 action battery: the teardown reap reads-and-removes marked artifacts
#endif

// Extracted from LocalChatBackend.swift (#216, 2026-08-01) — pure code motion.
//
// The DEBUG measurement battery: every `run*Battery` wrapper, the
// `ActionBatteryCell` grid, the belt shapers, and the thermal/reap plumbing.
// This is the bulk of what made the original file ~5,730 lines.
//
// Read `CLAUDE.md`'s "Measurement discipline (#215)" before quoting any rate
// this produces: a battery rate is a PRODUCTION rate only if the row was
// ROUTED, and `runActionBattery`'s `routed-production` cell is the only
// routed arm.
#if DEBUG
// MARK: - #196 rate battery (Diagnostics-triggered, DEBUG builds only)

extension LocalChatBackend {
    /// #215: what ROUTING does to a turn, for the instruments.
    ///
    /// This is NOT production's implementation — the live path applies the
    /// transformation inline in two private gates (`effectiveOfferedTools`
    /// drops the belt, `effectiveInstructionsText` swaps the text). It is the
    /// instruments' BINDING to production's authority: the toolless text comes
    /// from `productionToollessInstructions` and nowhere else, and
    /// `RoutedTrialShapeTests` pins the two equal.
    ///
    /// **That binding is the point, because the drift already happened once.**
    /// The #196 rate battery built its routed-toolless turn from
    /// `instructionsText(for: .toollessLic2, …)`. On 2026-07-30 the #202D
    /// promotion added clause v2 to production's toolless branch and created
    /// `productionToollessInstructions` — whose doc comment says it exists "in
    /// ONE place so the live path and the measured arm cannot drift apart."
    /// Nothing re-pointed the battery, so from that promotion until this lane
    /// every routed-toolless trial spoke a text production had stopped
    /// speaking. Both batteries now come through here.
    ///
    /// Armed is IDENTITY on both halves. A routed-armed trial IS production's
    /// armed trial; the routing seam must never be the thing a measurement
    /// sees.
    nonisolated static func routedTrialShape(
        needsTool: Bool,
        armedBelt: [any Tool],
        armedInstructions: String,
        deviceContext: String,
        date: Date = .now,
        hasImageTools: Bool = false
    ) -> (belt: [any Tool], instructions: String) {
        guard !needsTool else { return (armedBelt, armedInstructions) }
        // #196 (PROMOTED): the cure is STRUCTURAL — a routed-toolless turn
        // registers no belt at all. `armed-nocall` established that leaving
        // schemas in context and gating the call sustains the disclaimer tic
        // on its own, so an empty belt is the thing to reproduce, not a gate.
        return ([], productionToollessInstructions(
            deviceContext: deviceContext, date: date, hasImageTools: hasImageTools))
    }

    /// The fourth battery's cell list (#196 cure lane): control, the two
    /// payload candidates, and the routed production candidate. Battery-3's
    /// decomposition cells and battery-2's treatment cells stay in the enum
    /// — picker-reachable, no longer burning trials.
    nonisolated static let batteryCells: [SessionShape] = [
        .armed, .toollessLic, .toollessLic2, .armedRouted,
    ]

    /// #196 results-page lane: structured run capture, ADDITIVE to the
    /// emit sinks below — full reply texts, tool details, routes, and
    /// latencies persist per run for the in-app results view + export
    /// (Console-less work sessions). Static like the relay's trial tag:
    /// the instrument is one global surface. The store is exposed
    /// separately because the results screens read and delete through it.
    static let batteryRunStore = BatteryRunStore()
    static let batteryRecorder = BatteryRunRecorder(store: batteryRunStore)

    /// #200B battery mutex — BACKEND-owned, because the Diagnostics
    /// buttons' @State guard resets when the view is recreated mid-run:
    /// the 2026-07-28 destall run was contaminated by a second tap
    /// starting a CONCURRENT loop (interleaved cells, cross-attributed
    /// tool calls on the shared trial tag, an FM -1/1001 error storm from
    /// two generation streams). One battery at a time, whatever the UI
    /// thinks; a refused begin emits a classifiable line.
    private static var batteryActive = false

    /// True = this caller owns the run and MUST call `endBatteryRun`.
    ///
    /// **#331 made this async, and that is the point.** Reap-on-START is the
    /// half that makes a PREVIOUS crashed run harmless, and abort-time
    /// reaping cannot provide it — so it lives inside the one chokepoint
    /// every battery already passes through rather than at fourteen call
    /// sites that could each forget it. Changing the signature is what makes
    /// the compiler, not a grep, the thing that proves no launcher skipped
    /// the reap.
    ///
    /// Two ordering details that are load-bearing:
    /// - the mutex is CLAIMED before the awaited reap, and released again on
    ///   refusal — otherwise the suspension opens a window where a second tap
    ///   passes the `!batteryActive` guard, which is the #200B contamination
    ///   this mutex was built to stop;
    /// - a run that will WRITE and cannot reap is REFUSED, not skipped. A
    ///   silent skip is the failure mode where residue accumulates while the
    ///   suite reports success.
    static func beginBatteryRun() async -> Bool {
        guard !batteryActive else { return false }
        batteryActive = true
        let writesArmed = ToolConfirmationCenter.batteryWritesArmed
        let outcome = BatteryTestContainer.reap(reason: "start")
        let outsideMarked = writesArmed ? BatteryTestContainer.markedEventsOutsideContainers(in: EKEventStore()) : 0
        batteryEmit(BatteryTestContainer.reapLine(reason: "start", outcome: outcome,
                                                  outsideMarked: outsideMarked))
        if case .refused = outcome, writesArmed {
            batteryEmit("battery: REFUSED — the #331 test container is unavailable and this run writes device data")
            batteryActive = false
            return false
        }
        return true
    }

    static func endBatteryRun() {
        batteryActive = false
    }

    /// Battery lines go to THREE sinks: os_log (Console.app, the desk
    /// path), stdout (what `devicectl device process launch --console`
    /// bridges — flushed per line, because piped stdout is block-buffered
    /// and a SIGKILL'd run would otherwise capture NOTHING), and an
    /// append-only file in the app container (pullable via
    /// `devicectl device copy from … --domain-type appDataContainer` even
    /// after the process dies — the locked-screen background kill left a
    /// zero-byte capture on 2026-07-28's first headless attempt).
    static func batteryEmit(_ line: String) {
        print(line)
        fflush(stdout)
        logger.notice("\(line, privacy: .public)")
        batteryFileSink(line)
    }

    /// The file sink's location, exposed for the results page's share
    /// button (#200 crash diagnostics): the log survives a crashed run,
    /// and with the phone off-LAN there is no other way to get it out —
    /// Documents isn't Files-app-exposed and devicectl needs USB/LAN.
    static var batteryCaptureLogURL: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("battery-capture.log")
    }

    /// The container file sink for `batteryEmit` — Documents/battery-capture.log,
    /// appended with a trailing newline per line. Failures are silent by
    /// design (the other two sinks still carry the line).
    private static func batteryFileSink(_ line: String) {
        guard let url = batteryCaptureLogURL else { return }
        let data = Data((line + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }

    /// Third-battery instrument (#196 decomposition): six STRUCTURAL cells
    /// × three prompts × `trials` generations in-process, one classifiable
    /// notice line per trial. Deliberately bypasses `activeSessionShape`
    /// for instructions, belt, AND options — each session is parameterized
    /// explicitly (the first battery's belt still consulted the live
    /// selector; a non-armed phone selection would have contaminated every
    /// tool cell), so the launch-scoped invariant is untouched and no
    /// force-quit cycling is needed. Tools EXECUTE during tool-registered
    /// cells (real reads) — that is the point — and every tool start logs
    /// through `ToolEventRelay.batteryTrialTag`. "What's 2+2?" is the
    /// always-pass canary — though the second battery discovered the BARE
    /// branch denies arithmetic (toolless canary 0/20), so the canary is
    /// itself a measurement in the no-instructions cells.
    func runShapeBattery(trials: Int) async {
        guard await Self.beginBatteryRun() else {
            Self.batteryEmit("battery: REFUSED — another battery is already running (#200B mutex)")
            return
        }
        defer { Self.endBatteryRun() }
        let prompts: [(tag: String, text: String)] = [
            ("canary", "What's 2+2?"),
            ("haiku", "Write a haiku about sledding"),
            ("norway", "write a 50 word summary about Norway"),
        ]
        let cells = Self.batteryCells
        Self.batteryEmit("battery: START trials=\(trials) cells=\(cells.count) prompts=\(prompts.count) (#196)")
        Self.batteryRecorder.beginRun(trialsPerCell: trials, cells: cells.map(\.rawValue))
        for shape in cells {
            let belt: [any Tool] = shape.registersTools
                ? Self.shapedBelt(from: DeviceToolBelt.offeredTools(from: tools, hasImageInContext: false), shape: shape)
                : []
            let instructions = Self.instructionsText(
                for: shape,
                deviceContext: Self.deviceContextLine(),
                hasTools: !belt.isEmpty,
                hasImageTools: false
            )
            for (tag, prompt) in prompts {
                for trial in 1...trials {
                    // Tag set BEFORE the trial so every tool start inside it
                    // logs attributably. A post-guillotine straggler can
                    // mislabel into the following trial — rare and visible
                    // (it trails a TIMEOUT line), acceptable for an
                    // instrument.
                    ToolEventRelay.batteryTrialTag = "shape=\(shape.rawValue) p=\(tag) t=\(trial)"
                    // Trial clock starts here, so a routed trial's latency
                    // includes its router generation — the real turn cost.
                    Self.batteryRecorder.beginTrial()
                    // #196 battery 4: armed-routed classifies each trial's
                    // prompt first, then builds the routed session — the
                    // toolless-lic2 payload, or the full armed construction.
                    var trialBelt = belt
                    var trialInstructions = instructions
                    if shape == .armedRouted {
                        // #215: sample the failure tally across the routing
                        // call. `routeNeedsDeviceTool` fails SAFE — a thrown
                        // generation returns `armed` — so without this the
                        // record cannot tell a classification from a crash.
                        // That is #213's bug, and this is the instrument it
                        // was found in the sibling of.
                        let failuresBefore = Self.routerFailureTally
                        let needsTool = await routeNeedsDeviceTool(prompt: prompt)
                        let routeFailed = Self.routerFailureTally > failuresBefore
                        Self.batteryEmit("battery: route=\(needsTool ? "armed" : "toolless") failed=\(routeFailed) shape=\(shape.rawValue) p=\(tag) t=\(trial)")
                        Self.batteryRecorder.recordRoute(needsTool ? "armed" : "toolless", failed: routeFailed)
                        // #215: through the shared seam. This used to build the
                        // toolless turn from `.toollessLic2` directly, and went
                        // stale the day #202D promoted clause v2 — see
                        // `routedTrialShape`.
                        let shaped = Self.routedTrialShape(
                            needsTool: needsTool, armedBelt: belt,
                            armedInstructions: instructions,
                            deviceContext: Self.deviceContextLine()
                        )
                        trialBelt = shaped.belt
                        trialInstructions = shaped.instructions
                    }
                    // The `-noinstr` cells omit the `instructions:` argument
                    // entirely — the SDK's `Instructions? = nil` designated
                    // convenience init, its native no-instructions form (the
                    // `String?` overload is @_disfavoredOverload) — never an
                    // empty string, which would still inject an instructions
                    // block into the prompt.
                    let session = shape.passesInstructions
                        ? LanguageModelSession(model: model, tools: trialBelt, instructions: Instructions(trialInstructions))
                        : LanguageModelSession(model: model, tools: trialBelt)
                    // Identity except armed-nocall (`toolCallingMode:
                    // .disallowed` per call — the schemas stay in context).
                    let options = Self.shapedGenerationOptions(Self.chatGenerationOptions(for: activeTier), shape: shape)
                    await executeBatteryTrial(session: session, options: options,
                                              shape: shape.rawValue, promptTag: tag,
                                              prompt: prompt, trial: trial)
                }
            }
        }
        ToolEventRelay.batteryTrialTag = nil
        Self.batteryEmit("battery: DONE (#196)")
        Self.batteryRecorder.endRun()
    }

    /// Knowledge-denial forms observed in the first battery — matched
    /// anywhere in the reply, unlike the prefix-only `cant` flag which
    /// missed "I don't have access…" openings entirely. Shared by every
    /// battery so the heuristics can never drift between instruments.
    nonisolated static let batteryDenialPatterns = [
        "can't access", "can\u{2019}t access", "cannot access",
        "don't have access", "don\u{2019}t have access", "do not have access",
        "no access", "external knowledge", "external database", "external data",
        "no internet", "internet access", "real-time",
    ]

    /// One battery trial: respond, guillotine at 35s, classify, emit, and
    /// record — the shared executor behind the shape battery (#196) and the
    /// action battery (#200). Byte-identical lines to the pre-extraction
    /// emit path; callers set the trial tag and begin the recorder trial
    /// BEFORE calling.
    private func executeBatteryTrial(session: LanguageModelSession, options: GenerationOptions?,
                                     shape: String, promptTag: String,
                                     prompt: String, trial: Int) async {
        // 35s guillotine per trial: backstop only now that the confirmation
        // gate auto-resolves — a wedged trial still logs and the run still
        // moves. `options: nil` is the profile-backed path (#200E): an empty
        // GenerationOptions is all-nil fields, so the session profile's
        // modifiers govern the request.
        // #208: keep the whole Response, not just `.content` — `usage`
        // carries the real output-token count, which is the only way to
        // answer whether #102's 1024 cap is ever within reach of a turn.
        let respondTask = Task { try await session.respond(to: Prompt(prompt), options: options ?? GenerationOptions()) }
        let timeoutTask = Task { try? await Task.sleep(for: .seconds(35)); respondTask.cancel() }
        do {
            let response = try await respondTask.value
            let text = response.content
            let inTok = response.usage.input.totalTokenCount
            let outTok = response.usage.output.totalTokenCount
            timeoutTask.cancel()
            let flat = text.replacingOccurrences(of: "\n", with: " / ")
            let lower = text.lowercased()
            let cant = lower.hasPrefix("i can\u{2019}t") || lower.hasPrefix("i cant") || lower.hasPrefix("i cannot") || lower.hasPrefix("i can not") || lower.hasPrefix("i can't")
            let denial = Self.batteryDenialPatterns.contains { lower.contains($0) }
            Self.batteryEmit("battery: shape=\(shape) p=\(promptTag) t=\(trial) cant=\(cant) denial=\(denial) chars=\(text.count) inTok=\(inTok) outTok=\(outTok) text=\(String(flat.prefix(500)))")
            Self.batteryRecorder.endTrial(shape: shape, prompt: promptTag, trial: trial,
                                          text: text, cant: cant, denial: denial,
                                          inputTokens: inTok, outputTokens: outTok)
        } catch is CancellationError {
            timeoutTask.cancel()
            Self.batteryEmit("battery: shape=\(shape) p=\(promptTag) t=\(trial) TIMEOUT — wedged trial guillotined")
            Self.batteryRecorder.endTrialTimeout(shape: shape, prompt: promptTag, trial: trial)
        } catch {
            timeoutTask.cancel()
            Self.batteryEmit("battery: shape=\(shape) p=\(promptTag) t=\(trial) ERROR=\(String(String(describing: error).prefix(200)))")
            Self.batteryRecorder.endTrialError(shape: shape, prompt: promptTag, trial: trial,
                                               error: String(describing: error))
        }
    }

    /// #200B: the action battery's treatment-cell dimension. The FILED
    /// #200 table (remind 0/20, 15 list-stalls) routes treatment as
    /// MEASURED CELLS per the #196 remfix precedent — nothing ships to
    /// production without a battery verdict.
    enum ActionBatteryCell: String, CaseIterable {
        /// Production control — belt identity.
        case armed
        /// #215: production's ACTUAL configuration — the router classifies the
        /// turn first, and a turn it routes toolless gets no belt and
        /// production's toolless text (`routedTrialShape`).
        ///
        /// Belt and instructions are identity with `.armed`, so this cell
        /// differs from the control in exactly one way: the router runs. That
        /// makes the `armed` → `routed-production` delta the price (or the
        /// dividend) of routing, and makes this cell — not the control — the
        /// number that describes the shipped app.
        ///
        /// It is NOT a treatment. Routing changes the belt, so the two arms
        /// are not a fair A/B of any instruction or tool text; they are two
        /// configurations, one of which we ship.
        case routedProduction = "routed-production"
        /// #216: the narrow belt, re-evaluated where its only known cost
        /// cannot occur.
        ///
        /// #214 closed `armed-scopedv2` because narrowing took haiku grabs to
        /// 0/10 and took clean composition to 0/10 with them. **#215 then
        /// measured composition turns routing TOOLLESS 10/10** — they register
        /// no belt at all, so a narrow armed belt is unreachable from them.
        /// The objection that killed the cell is structurally void once the
        /// router is in front.
        ///
        /// Rides createonly's belt EXACTLY, the same one scopedv2 rode, so this
        /// is a re-evaluation with intact lineage rather than a new narrowing.
        /// It does NOT carry scopedv2's composition-licensing sentence: that
        /// clause repaired the denial the belt caused, routing already repairs
        /// it, and carrying it would make this cell differ from its control in
        /// two ways instead of one.
        ///
        /// The target is measured, not assumed: #215 priced the calendar prompt
        /// at 3 calls and 6.4s against remind's 1 call and 3.7s, the extra two
        /// being `readCalendar` 7/10 and `lookupContact` 7/10 — lookups whose
        /// results change nothing, since creates are 10/10 with or without them.
        case routedScoped = "routed-scoped"
        /// `ReminderCreateToolGuidefix` copy: de-stalled @Guide texts on
        /// the optional fields, production description.
        case armedGuidefix = "armed-guidefix"
        /// Production struct, `destalledDescription200` — the remfix
        /// description-var mechanism.
        case armedToolfix = "armed-toolfix"
        /// Both texts together — interaction effects can't hide behind
        /// two individually-clean cells (#196 battery-2 lesson).
        case armedBothfix = "armed-bothfix"
        /// #200C: production belt UNTOUCHED; the de-stall clause rides the
        /// session INSTRUCTIONS instead — the seam upstream of response
        /// planning, where #200B proved the stall actually fires.
        case armedInstrfix = "armed-instrfix"
        /// #200E: belt AND instructions production verbatim; the sole
        /// treatment is per-request `.required` tool-calling mode with the
        /// mandatory demote exit (`ToolmodeBatteryProfile`) — the seam at
        /// DECODING level, below everything prose can reach.
        case armedToolmode = "armed-toolmode"
        /// #200F: Apple's 3–5 active-tools guidance, isolated — per-INTENT
        /// belt with the same-domain reads kept in (`scopedBelt`).
        case armedScoped = "armed-scoped"
        /// #200F: per-intent belt WITHOUT the same-domain read — the
        /// read-substitution stall killed structurally (no readReminders
        /// to flee into; #200E measured find-first as model-baked).
        case armedCreateonly = "armed-createonly"
        /// #200F: full production belt; the instructions pass
        /// `includeFindFirstCarveout: true` explicitly. Since the #200G
        /// promotion that is identity with production — the cell now
        /// measures the promoted text (the instrfix precedent).
        case armedFindfix = "armed-findfix"
        /// #200H: full production belt; the instructions gain the
        /// lookup-spiral carve-out (`includeLookupSpiralCarveout`),
        /// flag-off byte-identical.
        case armedSpiralfix = "armed-spiralfix"
        /// #200H: belt AND instructions production verbatim; the sole
        /// treatment is the third-strike demote (`SpiralBudgetProfile`):
        /// `.allowed` until any single tool's third call, `.disallowed`
        /// after — the model must answer with what it has.
        case armedStrikefix = "armed-strikefix"
        /// #200J: full production belt; the instructions gain the
        /// card-narration clause (`includeCardNarrationClause`) against
        /// #200I's largest failure bucket — the model writing the
        /// confirmation card out in prose and calling nothing. Since the
        /// #200K promotion the cell passes the promoted flag explicitly,
        /// so it is identity with production (the findfix precedent) —
        /// which is what lets it pool with the control as a re-verify.
        case armedCardfix = "armed-cardfix"
        /// #200K: full production belt; the instructions gain the
        /// day-default clause (`includeDayDefaultClause`) against #200J's
        /// residual remind disease — zero-tool date interrogation.
        case armedDatefix = "armed-datefix"
        /// #200L: the first cell that measures a PROMOTED clause by
        /// removing it — production with `includeCardNarrationClause`
        /// explicitly false, i.e. the pinned rollback text verbatim.
        /// #200K left open whether the promoted clause costs calendar
        /// (59% post vs 70% pre, p≈0.4, direction unfavorable); this
        /// answers it directly instead of on trend lines.
        case armedCardrollback = "armed-cardrollback"
        /// #200M: full production belt; the instructions gain the v3
        /// dead-end carve-out (`includeDeadEndCarveout`) — v2's win
        /// without v2's search prohibition, which is what #200L implicated
        /// in the reminder-path bleed.
        case armedDeadendfix = "armed-deadendfix"
        /// #200O: full production belt; the instructions gain the
        /// composition-answer clause (`includeCompositionAnswerClause`)
        /// against the meta-grab class.
        case armedGrabfix = "armed-grabfix"
        /// #200P: full production belt; the instructions gain the
        /// card-correction clause (`includeCardCorrectionClause`) against
        /// the conserved zero-tool stall.
        case armedStallfix = "armed-stallfix"
        /// #200Q: the stall's STRUCTURAL seam — the reminder tool's two
        /// optional fields become optional in the SCHEMA (`String?`), so
        /// the model is no longer required to produce a value it was
        /// being told to leave empty. Belt swap; instructions untouched.
        case armedSchemafix = "armed-schemafix"
        /// #200S: the promotion's pinned ROLLBACK, as a measured cell —
        /// `ReminderCreateToolRequiredFields`, i.e. the pre-promotion tool
        /// with `due`/`list` required again.
        ///
        /// (#200R's `armed-schemaquiet` was REMOVED, not retired in place:
        /// suppressing the reminder schema description made the model
        /// create CALENDAR EVENTS for 9 of 10 reminder requests while
        /// claiming a reminder was set. Leaving a cell that silently
        /// writes wrong artifacts to a real calendar on the picker is a
        /// hazard, not an archive.)
        case armedSchemarollback = "armed-schemarollback"
        /// #200T: the same structural surgery, one tool over — the CALENDAR
        /// tool's `durationMinutes` and `location` become optional in the
        /// schema (`CalendarEventToolOptionalFields`), against what is now
        /// the weakest production number (15/20 pooled). Belt swap;
        /// instructions untouched.
        case armedCalfix = "armed-calfix"
        /// #200U arm A, the promotable one: `ContactsTool`'s not-found RESULT
        /// gains continuation (`continuesAfterNoMatch`). #200T left the "Sam"
        /// dead-end owning 4 of 5 calendar misses THROUGH the promoted #200O
        /// prose carve-out — so this treats the layer prose cannot reach.
        case armedDeadend2 = "armed-deadend2"
        /// #200U arm B, the CEILING probe: `lookupContact` removed from the
        /// belt entirely. If the model cannot call it, it cannot dead-end into
        /// it. NOT proposed for production — dropping a useful tool globally
        /// is a product regression; this bounds the achievable win, and if it
        /// does not beat the control either, the whole seam is falsified.
        case armedNocontact = "armed-nocontact"
        /// #200X: the calendar promotion's pinned ROLLBACK, as a measured
        /// cell — `CalendarEventToolRequiredFields`, i.e. the pre-promotion
        /// tool with `durationMinutes`/`location` required again. Restoring
        /// them restores the geolocation behaviour: 5 of 8 creates carried an
        /// invented location in #200W, twice the home street address.
        case armedCalrollback = "armed-calrollback"
        /// #209: the READ-tool promotion's pinned ROLLBACK, as a measured cell
        /// — `DeviceHealthToolRequiredMetric` + `WeatherToolRequiredPlace`,
        /// i.e. `metric` and `place` required in the schema again.
        ///
        /// **This cell is not expected to move a rate, and that is not what it
        /// is for.** The disease it restores runs at 1.4% on the worst cell
        /// (`armed/haiku`, 5/350), far under anything a battery can resolve —
        /// #209's dispatch pre-registers that no efficacy bar is writable. It
        /// exists because `CalendarEventToolRequiredFields` proved its own
        /// worth passively: it threw `does not contain a property
        /// 'durationMinutes'` in the run records where the promoted tool
        /// structurally could not, which is what let the error data identify
        /// the mechanism at all. A rollback twin is a control arm that runs
        /// itself in the background — keep it reachable and it will eventually
        /// answer a question nobody thought to ask.
        case armedFieldrollback = "armed-fieldrollback"
        /// #211 PROMOTED 2026-07-31 — this is now the pinned ROLLBACK: the
        /// pre-promotion `readMotion` description, still claiming "today's
        /// step count" and so still competing with `readHealth` for a step
        /// question. Run `63C0EF12`: this text answers 0/10, the promoted one
        /// 10/10 (Fisher two-tailed p = 1.08e-05), motion questions unaffected
        /// at 9/9.
        case armedMotionrollback = "armed-motionrollback"
        /// #211 follow-on: the promoted scoped text PLUS a boundary sentence
        /// pointing at `readHealth` by DOMAIN, never by naming a metric.
        ///
        /// Targets the recorded COST of the #211 promotion, not its win: the
        /// promoted arm chained extra tools on motion questions 4/9 vs 0/10.
        /// The guard on this cell is therefore the #211 win itself — if the
        /// redirect re-breaks the step question, it does not promote no matter
        /// what it does for chaining.
        case armedMotionredirect = "armed-motionredirect"
        /// #214: the STRUCTURAL lane — per-intent belt PLUS composition
        /// licensing. The combination has never been run.
        ///
        /// #200F (2026-07-29) measured narrow belts and they killed the grab
        /// disease outright: `armed-createonly` grabs **0/10** against a
        /// control at 4/9, with calendar at a **10/10** ceiling control never
        /// reached. It failed as a promotion candidate on ONE thing —
        /// composition denial, haiku "cant" **10/10** ("I don't have creative
        /// writing tools", "I'm not a poet").
        ///
        /// Two reasons the combination is now worth a run:
        /// 1. **Composition denial has its own measured cure.** #196's
        ///    composition-licensing sentence exists precisely because the
        ///    model equates composing about world knowledge with retrieval.
        ///    It was never applied to a narrow-belt cell.
        /// 2. **Those cells predate today's production.** `createonly`'s
        ///    remind 5/10 was held down by the ask-stall and read-flee, and
        ///    BOTH were fixed and promoted afterwards — the optional reminder
        ///    schema (#200S), find-first (#200G, promoted the same day), the
        ///    dead-end carve-out, the router (#202) and clause v2 (#202D).
        ///    The narrow belt has never been measured on top of them.
        ///
        /// The belt is `createonly`'s, not `scoped`'s: #200F's own
        /// createonly-vs-scoped delta showed that removing the same-domain
        /// read converts half the stalls into creates (0/10 → 5/10), and the
        /// other half — ask-interrogation — is what find-first now kills.
        case armedScopedv2 = "armed-scopedv2"
        /// #201B: the contact promotion's pinned ROLLBACK — `ContactsTool` with
        /// `continuesAfterNoMatch` explicitly false, i.e. the bare not-found
        /// text that produced 14/80 dead-end misses across two n=40 runs.
        case armedDeadendrollback = "armed-deadendrollback"
        /// #204: production MINUS the promoted dead-end CARVE-OUT (the
        /// instructions clause, not #201B's ContactsTool flag). Its
        /// promotion was only ever re-verified against a cross-run
        /// historical baseline; this makes it a within-run control.
        case armedCarveoutrollback = "armed-carveoutrollback"

        /// #216: whether this cell puts the ROUTER in front of every trial.
        ///
        /// A property rather than a comparison at the call site, because after
        /// #215 an unrouted arm is the single easiest way to produce a number
        /// that does not describe the shipped app — and a new cell that forgets
        /// to opt in would do exactly that, silently. Pinned as a whole-enum
        /// partition by `exactlyTheRoutedCellsRoute`.
        var isRouted: Bool {
            switch self {
            case .routedProduction, .routedScoped: return true
            default: return false
            }
        }
    }

    /// The belt each treatment cell registers: identity except the
    /// reminder tool, which swaps text (toolfix), struct (guidefix), or
    /// both (bothfix). Same instances and order for every other tool.
    nonisolated static func destallBelt(from tools: [any Tool], cell: ActionBatteryCell) -> [any Tool] {
        switch cell {
        case .armed, .armedInstrfix, .armedToolmode, .armedScoped, .armedCreateonly,
             .armedFindfix, .armedSpiralfix, .armedStrikefix, .armedCardfix,
             .armedDatefix, .armedCardrollback, .armedDeadendfix, .armedGrabfix,
             .armedStallfix, .armedSchemafix, .armedCalfix, .armedDeadend2,
             .armedCarveoutrollback, .armedScopedv2, .routedProduction, .routedScoped:
            // instrfix/findfix/spiralfix treat INSTRUCTIONS, toolmode and
            // strikefix treat the tool-calling MODE, the #200F scoping
            // cells narrow per PROMPT (`scopedBelt`, inside the trial
            // loop), and #215's routed cell decides its belt per TRIAL from
            // the route — none of them swap tool text here.
            return tools
        case .armedDeadendrollback:
            // #201B: one swap — the pre-promotion bare not-found text. The
            // pinned rollback, measurable.
            return tools.map { tool in
                if let contacts = tool as? ContactsTool {
                    return ContactsTool(continuesAfterNoMatch: false, relay: contacts.relay)
                }
                return tool
            }
        case .armedNocontact:
            // #200U arm B: the ceiling probe — the tool is simply absent.
            return tools.filter { $0.name != "lookupContact" }
        case .armedCalrollback:
            // #200X: one swap — the pre-promotion calendar tool, whose two
            // undefaultable fields are REQUIRED in the schema again. The
            // pinned rollback, measurable.
            return tools.map { tool in
                if let calendar = tool as? CalendarEventTool {
                    return CalendarEventToolRequiredFields(relay: calendar.relay, confirmations: calendar.confirmations)
                }
                return tool
            }
        case .armedMotionredirect:
            // #211 follow-on: one description swap, promoted text + boundary.
            return tools.map { tool in
                if var motion = tool as? MotionTool {
                    motion.description = MotionTool.redirectDescription211B
                    return motion
                }
                return tool
            }
        case .armedMotionrollback:
            // #211: one description swap back to the pre-promotion text, which
            // restores the step claim and with it the misroute. The measured
            // control, kept reachable.
            return tools.map { tool in
                if var motion = tool as? MotionTool {
                    motion.description = MotionTool.stepClaimingDescription211
                    return motion
                }
                return tool
            }
        case .armedFieldrollback:
            // #209: two swaps — the pre-promotion READ tools, whose
            // defaultable fields are REQUIRED in the schema again. Both are
            // restored together because they are one promotion.
            return tools.map { tool in
                if let health = tool as? DeviceHealthTool {
                    return DeviceHealthToolRequiredMetric(relay: health.relay)
                }
                if let weather = tool as? WeatherTool {
                    return WeatherToolRequiredPlace(relay: weather.relay, location: weather.location)
                }
                return tool
            }
        case .armedSchemarollback:
            // #200S: one swap — the pre-promotion reminder tool, whose
            // optional fields are REQUIRED in the schema. The pinned
            // rollback, measurable.
            return tools.map { tool in
                if let reminder = tool as? ReminderCreateTool {
                    return ReminderCreateToolRequiredFields(relay: reminder.relay, confirmations: reminder.confirmations)
                }
                return tool
            }
        case .armedGuidefix:
            return tools.map { tool in
                if let reminder = tool as? ReminderCreateTool {
                    return ReminderCreateToolGuidefix(relay: reminder.relay, confirmations: reminder.confirmations)
                }
                return tool
            }
        case .armedToolfix:
            return tools.map { tool in
                if var reminder = tool as? ReminderCreateTool {
                    reminder.description = ReminderCreateTool.destalledDescription200
                    return reminder
                }
                return tool
            }
        case .armedBothfix:
            return tools.map { tool in
                if let reminder = tool as? ReminderCreateTool {
                    return ReminderCreateToolGuidefix(
                        description: ReminderCreateTool.destalledDescription200,
                        relay: reminder.relay, confirmations: reminder.confirmations
                    )
                }
                return tool
            }
        }
    }

    /// #200F: the per-INTENT belts. Apple's guidance is 3–5 active tools
    /// per request (the armed belt is 13); the scoped cell keeps each
    /// intent's create tool plus its same-domain reads, and createonly
    /// removes the same-domain read — no readReminders to flee into
    /// (#200E: the forced first call was readReminders 10/10; find-first
    /// is model-baked). Alarm has no same-domain read, so its two cells
    /// coincide. Haiku rides the REMIND scope — the worst-case misroute
    /// canary. Identity for every other cell; filtering preserves belt
    /// order and instances. Cell machinery only: production scoping would
    /// be router-driven — a PROMOTION question, not this lane's.
    nonisolated static func scopedBelt(from tools: [any Tool], cell: ActionBatteryCell,
                                       promptTag: String) -> [any Tool] {
        let keep: Set<String>
        switch cell {
        case .armedScoped:
            switch promptTag {
            case "alarm": keep = ["scheduleAlarm", "readCalendar"]
            case "calendar": keep = ["createCalendarEvent", "readCalendar", "currentLocation"]
            default: keep = ["createReminder", "readReminders", "readCalendar"]
            }
        case .armedCreateonly, .armedScopedv2, .routedScoped:
            // #214 rides createonly's belt deliberately: #200F's own
            // createonly-vs-scoped delta showed removing the same-domain read
            // converts half the stalls into creates. The other half was
            // ask-interrogation, which find-first has since been promoted to
            // kill — so the belt is held constant and only the instructions
            // and the production baseline differ from that run.
            switch promptTag {
            case "alarm": keep = ["scheduleAlarm", "readCalendar"]
            case "calendar": keep = ["createCalendarEvent", "currentLocation"]
            default: keep = ["createReminder", "readCalendar"]
            }
        default:
            return tools
        }
        return tools.filter { keep.contains($0.name) }
    }

    /// #200 default cell list — the bare production control, alone. Pinned.
    nonisolated static let actionBatteryCells: [ActionBatteryCell] = [.armed]

    /// #200 action-path battery: does an APPROPRIATE create go through?
    /// Single-turn create prompts × `trials` per cell, ARMED production
    /// construction — the armed-routed armed branch, whose belt,
    /// instructions, and options are all identity with `.armed` (verified
    /// against `shapedBelt` / `instructionsText` / `shapedGenerationOptions`).
    /// NO per-trial routing: the router probe already measured these
    /// prompts as correctly ROUTED; this measures what the armed session
    /// does next. The launcher arms auto-ACCEPT, so appropriate creates
    /// EXECUTE — real EventKit/AlarmKit writes, every artifact
    /// marker-tagged by the gate — and the teardown reaps everything
    /// marked BEFORE the DONE line, so the phone ends the run clean.
    /// Protocol: run with Reminders/Calendar granted.
    ///
    /// #200B: `cells` swaps the reminder tool's TEXT per cell
    /// (`destallBelt`); `includeGrabCanary` adds the #196 haiku prompt —
    /// the de-stall texts push toward immediate creation, so the grab
    /// disease is the collateral to measure (a grab creates a real marked
    /// reminder under auto-accept; the reap deletes it; the confirm line
    /// makes it countable). Defaults preserve the FILED #200 protocol
    /// byte-for-byte.
    ///
    /// #215: the `routed-production` CELL puts the router in front of every
    /// trial, which is the one thing this instrument has never done. Its
    /// absence is not a detail — #204 filed it as a caveat and #214's verdict
    /// made it the headline: an unrouted battery reports the grab rate of a
    /// configuration production does not ship, because in production the
    /// composition prompt routes toolless and never sees a belt at all.
    /// Routing is a cell rather than a run-level flag so the contrast is
    /// WITHIN a run — same thermal state, same slot rotation, the design
    /// #200V's warm-up work established.
    func runActionBattery(trials: Int,
                          cells: [ActionBatteryCell] = LocalChatBackend.actionBatteryCells,
                          includeGrabCanary: Bool = false,
                          promptSet: [(tag: String, text: String)]? = nil,
                          warmup: Bool = LocalChatBackend.batteryWarmupDefault) async {
        guard await Self.beginBatteryRun() else {
            Self.batteryEmit("battery: REFUSED — another battery is already running (#200B mutex)")
            return
        }
        defer { Self.endBatteryRun() }
        // #209: the three create prompts never call a READ tool, so no battery
        // has ever exercised `readHealth` or `currentWeather` end to end.
        // `promptSet` lets a lane supply its own; the default is unchanged, so
        // every existing button keeps its pinned denominator.
        var prompts: [(tag: String, text: String)] = promptSet ?? [
            ("remind", "Remind me to test Talaria at 4:30pm"),
            ("alarm", "Set an alarm for 6:30"),
            ("calendar", "Put lunch with Sam on my calendar Friday at noon"),
        ]
        if includeGrabCanary, promptSet == nil {
            prompts.append(("haiku", "Write a haiku about sledding"))
        }
        let shape = SessionShape.armedRouted
        let base = Self.shapedBelt(
            from: DeviceToolBelt.offeredTools(from: tools, hasImageInContext: false),
            shape: shape
        )
        let instructions = Self.instructionsText(
            for: shape,
            deviceContext: Self.deviceContextLine(),
            hasTools: !base.isEmpty,
            hasImageTools: false
        )
        Self.batteryEmit("battery: START trials=\(trials) cells=\(cells.count) prompts=\(prompts.count) warmup=\(warmup) (#200)")
        // #200F Part 0: per-trial reap accumulators — the final REAP line
        // folds these into its counts so reap arithmetic stays exact.
        var perTrialReminders = 0
        var perTrialEvents = 0
        var perTrialAlarms = 0
        var perTrialFailures = 0
        // #200V: a DISCARDED warm-up pass over the prompt list, run through
        // the first cell's belt. In #200S, #200T and #200U the first cell
        // posted the lowest calendar number, so slot 1 was paying a
        // cold-start cost the later slots did not — a rival explanation for
        // every effect this instrument has measured. This pays it up front,
        // outside the counts.
        //
        // It runs BEFORE `beginRun`, and every recorder mutator guards on an
        // active run, so warm-up trials are RECORDER-INERT: the recorded run
        // and the results page are byte-identical to a warm-up-free run
        // (pinned by `recorderIgnoresTrialsAppendedBeforeTheRunBegins`). Its
        // artifacts ARE reaped per trial like any other, and its reap lines
        // carry `shape=warmup` so the counted-trial arithmetic still balances.
        if warmup, let firstCell = cells.first {
            Self.batteryEmit("battery: WARMUP begin cell=\(firstCell.rawValue) prompts=\(prompts.count) (#200V)")
            let warmBelt = Self.destallBelt(from: base, cell: firstCell)
            for (tag, prompt) in prompts {
                let belt = Self.scopedBelt(from: warmBelt, cell: firstCell, promptTag: tag)
                ToolEventRelay.batteryTrialTag = Self.batteryWarmupTag(prompt: tag)
                Self.batteryEmit("battery: BEGIN \(Self.batteryWarmupTag(prompt: tag))")
                // #215: if ANY cell in this run routes, warm the ROUTER too —
                // it is a second, separate `LanguageModelSession`, and without
                // this the routed cell's slot-1 trial pays a cold start the
                // control never pays. That asymmetry is precisely the rival
                // explanation #200V's warm-up was built to remove, and it
                // would land on the one cell whose numbers this lane is for.
                // Discarded like everything else here: the result is unused,
                // and the recorder is inert before `beginRun`.
                if cells.contains(where: \.isRouted) {
                    _ = await routeNeedsDeviceTool(prompt: prompt)
                }
                let session = LanguageModelSession(model: model, tools: belt,
                                                  instructions: Instructions(instructions))
                await executeBatteryTrial(
                    session: session,
                    options: Self.shapedGenerationOptions(Self.chatGenerationOptions(for: activeTier), shape: shape),
                    shape: "warmup", promptTag: tag, prompt: prompt, trial: 0
                )
                let sweep = await Self.sweepMarkedRemindersAndEvents(emitSteps: false)
                let alarmSweep = AlarmService.reapBatteryAlarms()
                perTrialReminders += sweep.reminders
                perTrialEvents += sweep.events
                perTrialAlarms += alarmSweep.cancelled
                perTrialFailures += sweep.failures + alarmSweep.failed
                Self.batteryEmit(Self.reapTrialLine(
                    reminders: sweep.reminders, events: sweep.events,
                    alarms: alarmSweep.cancelled,
                    failures: sweep.failures + alarmSweep.failed,
                    tag: Self.batteryWarmupTag(prompt: tag)
                ))
            }
            Self.batteryEmit("battery: WARMUP done — discarded, not counted (#200V)")
        }
        Self.batteryRecorder.beginRun(trialsPerCell: trials, cells: cells.map(\.rawValue), kind: "action")
        for cell in cells {
            emitThermal(cell: cell.rawValue, at: "start")
            let cellBelt = Self.destallBelt(from: base, cell: cell)
            let cellInstructions: String
            switch cell {
            case .armedInstrfix:
                // #200C: instrfix swaps INSTRUCTIONS, not the belt.
                cellInstructions = Self.instructionsText(
                    deviceContext: Self.deviceContextLine(),
                    hasTools: !base.isEmpty,
                    hasImageTools: false,
                    includeActionDestallClause: true
                )
            case .armedFindfix:
                // #200F: findfix passes the carve-out flag explicitly —
                // identity with production since the #200G promotion.
                cellInstructions = Self.instructionsText(
                    deviceContext: Self.deviceContextLine(),
                    hasTools: !base.isEmpty,
                    hasImageTools: false,
                    includeFindFirstCarveout: true
                )
            case .armedScopedv2:
                // #214: production instructions PLUS #196's
                // composition-licensing sentence. That sentence is the
                // measured cure for the one thing that killed the narrow-belt
                // cells — the model equating composing about world knowledge
                // with retrieval — and it has never been applied to one.
                // Everything else is production, so the cell differs from the
                // control in exactly two ways: the belt narrows per intent,
                // and composition is licensed.
                cellInstructions = Self.instructionsText(
                    deviceContext: Self.deviceContextLine(),
                    hasTools: !base.isEmpty,
                    hasImageTools: false,
                    includeCompositionLicensingSentence: true
                )
            case .armedSpiralfix:
                // #200H: spiralfix adds the lookup-spiral carve-out on
                // top of production — belt untouched.
                cellInstructions = Self.instructionsText(
                    deviceContext: Self.deviceContextLine(),
                    hasTools: !base.isEmpty,
                    hasImageTools: false,
                    includeLookupSpiralCarveout: true
                )
            case .armedCardfix:
                // #200J: cardfix passes the card clause explicitly —
                // identity with production since the #200K promotion, so
                // this cell pools with the control as the re-verify.
                cellInstructions = Self.instructionsText(
                    deviceContext: Self.deviceContextLine(),
                    hasTools: !base.isEmpty,
                    hasImageTools: false,
                    includeCardNarrationClause: true
                )
            case .armedStallfix:
                // #200P: stallfix adds the card-correction clause on top
                // of promoted production — belt untouched.
                cellInstructions = Self.instructionsText(
                    deviceContext: Self.deviceContextLine(),
                    hasTools: !base.isEmpty,
                    hasImageTools: false,
                    includeCardCorrectionClause: true
                )
            case .armedGrabfix:
                // #200O: grabfix adds the composition-answer clause on
                // top of promoted production — belt untouched.
                cellInstructions = Self.instructionsText(
                    deviceContext: Self.deviceContextLine(),
                    hasTools: !base.isEmpty,
                    hasImageTools: false,
                    includeCompositionAnswerClause: true
                )
            case .armedDeadendfix:
                // #200M: v3 adds only the dead-end carve-out on top of
                // promoted production — belt untouched.
                cellInstructions = Self.instructionsText(
                    deviceContext: Self.deviceContextLine(),
                    hasTools: !base.isEmpty,
                    hasImageTools: false,
                    includeDeadEndCarveout: true
                )
            case .armedCarveoutrollback:
                // #204: the pinned carve-out rollback, run as a measured cell.
                cellInstructions = Self.instructionsText(
                    deviceContext: Self.deviceContextLine(),
                    hasTools: !base.isEmpty,
                    hasImageTools: false,
                    includeDeadEndCarveout: false
                )
            case .armedCardrollback:
                // #200L: production MINUS the promoted card clause — the
                // pinned rollback text, run as a measured cell.
                cellInstructions = Self.instructionsText(
                    deviceContext: Self.deviceContextLine(),
                    hasTools: !base.isEmpty,
                    hasImageTools: false,
                    includeCardNarrationClause: false
                )
            case .armedDatefix:
                // #200K: datefix adds the day-default clause on top of
                // promoted production — belt untouched.
                cellInstructions = Self.instructionsText(
                    deviceContext: Self.deviceContextLine(),
                    hasTools: !base.isEmpty,
                    hasImageTools: false,
                    includeDayDefaultClause: true
                )
            default:
                cellInstructions = instructions
            }
            for (tag, prompt) in prompts {
                // #200F: the scoping cells narrow the belt per PROMPT
                // (per-intent scope); identity for every other cell.
                let belt = Self.scopedBelt(from: cellBelt, cell: cell, promptTag: tag)
                for trial in 1...trials {
                    ToolEventRelay.batteryTrialTag = "shape=\(cell.rawValue) p=\(tag) t=\(trial)"
                    // Live-only BEGIN line (never rendered from records): if
                    // the run dies inside this trial, the capture log's last
                    // BEGIN names it exactly.
                    Self.batteryEmit("battery: BEGIN shape=\(cell.rawValue) p=\(tag) t=\(trial)")
                    Self.batteryRecorder.beginTrial()
                    // #215: the routed variant. The trial clock is already
                    // running, so a routed trial's latency includes its router
                    // generation — the real cost of a production turn, not the
                    // armed half of one.
                    var trialBelt = belt
                    var trialInstructions = cellInstructions
                    if cell.isRouted {
                        // Empty context: these are single-turn prompts, which
                        // is exactly what production passes when a
                        // conversation has no prior assistant turn.
                        let failuresBefore = Self.routerFailureTally
                        let needsTool = await routeNeedsDeviceTool(prompt: prompt)
                        let routeFailed = Self.routerFailureTally > failuresBefore
                        Self.batteryEmit("battery: route=\(needsTool ? "armed" : "toolless") failed=\(routeFailed) shape=\(cell.rawValue) p=\(tag) t=\(trial)")
                        Self.batteryRecorder.recordRoute(needsTool ? "armed" : "toolless", failed: routeFailed)
                        let shaped = Self.routedTrialShape(
                            needsTool: needsTool, armedBelt: belt,
                            armedInstructions: cellInstructions,
                            deviceContext: Self.deviceContextLine()
                        )
                        trialBelt = shaped.belt
                        trialInstructions = shaped.instructions
                    }
                    let baseOptions = Self.shapedGenerationOptions(Self.chatGenerationOptions(for: activeTier), shape: shape)
                    let session: LanguageModelSession
                    let trialOptions: GenerationOptions?
                    if cell == .armedToolmode {
                        // #200E: the mode must ride a DynamicProfile so it can
                        // demote after the first call — raw `.required` in
                        // respond options has no exit and loops (dispatch).
                        // Generation options ride the profile; respond() gets
                        // none (nil → all-nil options, profile governs).
                        session = LanguageModelSession(profile: ToolmodeBatteryProfile(
                            model: model, belt: trialBelt,
                            instructionsText: trialInstructions, options: baseOptions))
                        trialOptions = nil
                    } else if cell == .armedStrikefix {
                        // #200H: the third-strike demote rides the same
                        // DynamicProfile machinery — `.allowed` until any
                        // single tool's third call, `.disallowed` after.
                        session = LanguageModelSession(profile: SpiralBudgetProfile(
                            model: model, belt: trialBelt,
                            instructionsText: trialInstructions, options: baseOptions))
                        trialOptions = nil
                    } else {
                        session = LanguageModelSession(model: model, tools: trialBelt, instructions: Instructions(trialInstructions))
                        trialOptions = baseOptions
                    }
                    await executeBatteryTrial(session: session, options: trialOptions,
                                              shape: cell.rawValue, promptTag: tag,
                                              prompt: prompt, trial: trial)
                    // #200F Part 0: sweep marker reminders/events after
                    // EVERY trial — #200E's treatment cell lost 4/10
                    // remind trials to already-exists reads of REAL
                    // artifacts the control cell created minutes earlier.
                    // #200S: ALARMS are cancelled per-trial too. They used
                    // to wait for end-of-run, so every crashed run stranded
                    // every alarm it had scheduled — 2026-07-29's four
                    // jetsam kills stranded ~47 (matching the "~50 armed
                    // for 6:30 AM" already on file from 07-28) and Owen had
                    // to sweep by hand to keep working. Tracked-ID cancel
                    // is idempotent, so the end-of-run reap stays as
                    // backstop and its count folds in.
                    let sweep = await Self.sweepMarkedRemindersAndEvents(emitSteps: false)
                    let alarmSweep = AlarmService.reapBatteryAlarms()
                    perTrialReminders += sweep.reminders
                    perTrialEvents += sweep.events
                    perTrialAlarms += alarmSweep.cancelled
                    perTrialFailures += sweep.failures + alarmSweep.failed
                    Self.batteryEmit(Self.reapTrialLine(
                        reminders: sweep.reminders, events: sweep.events,
                        alarms: alarmSweep.cancelled,
                        failures: sweep.failures + alarmSweep.failed,
                        tag: "shape=\(cell.rawValue) p=\(tag) t=\(trial)"
                    ))
                }
            }
            emitThermal(cell: cell.rawValue, at: "end")
        }
        ToolEventRelay.batteryTrialTag = nil
        let reapSummary = await reapBatteryArtifacts(
            perTrialReminders: perTrialReminders,
            perTrialEvents: perTrialEvents,
            perTrialAlarms: perTrialAlarms,
            perTrialFailures: perTrialFailures
        )
        Self.batteryEmit("battery: REAP \(reapSummary) (#200)")
        Self.batteryRecorder.recordReapSummary(reapSummary)
        Self.batteryEmit("battery: DONE (#200)")
        Self.batteryRecorder.endRun()
    }

    /// #200B cell list — control plus the three TOOL-TEXT treatments. Pinned.
    nonisolated static let destallBatteryCells: [ActionBatteryCell] = [
        .armed, .armedGuidefix, .armedToolfix, .armedBothfix,
    ]

    /// #200B one-tap wrapper: the four TOOL-TEXT treatment cells × four
    /// prompts (grab canary included). Kept runnable; the #200B verdict
    /// falsified these cells (remind 0/0/0/1).
    func runDestallBattery(trials: Int,
                           cells: [ActionBatteryCell] = LocalChatBackend.destallBatteryCells) async {
        await runActionBattery(
            trials: trials,
            cells: cells,
            includeGrabCanary: true
        )
    }

    /// #200C cell list — control vs the INSTRUCTIONS-level de-stall clause. Pinned.
    nonisolated static let instrfixBatteryCells: [ActionBatteryCell] = [.armed, .armedInstrfix]

    /// #200C one-tap wrapper: control vs the INSTRUCTIONS-level de-stall
    /// clause × four prompts — 8 × trials generations.
    func runInstrfixBattery(trials: Int,
                            cells: [ActionBatteryCell] = LocalChatBackend.instrfixBatteryCells) async {
        await runActionBattery(trials: trials, cells: cells, includeGrabCanary: true)
    }

    /// #200E: the demote exit — Apple's own pattern for `.required`, which
    /// otherwise LOOPS ("until a Tool throws an error or this value is
    /// changed dynamically", beta-4 doc comment): required until the first
    /// tool call, allowed after so the model can produce a final response.
    nonisolated static func toolmodeMode(after callCount: Int) -> GenerationOptions.ToolCallingMode {
        callCount < 1 ? .required : .allowed
    }

    /// #200E cell list — control vs the structural `.required` treatment. Pinned.
    nonisolated static let toolmodeBatteryCells: [ActionBatteryCell] = [.armed, .armedToolmode]

    /// #200E one-tap wrapper: promoted-production control vs the structural
    /// `.required` treatment × four prompts — 8 × trials generations.
    func runToolmodeBattery(trials: Int,
                            cells: [ActionBatteryCell] = LocalChatBackend.toolmodeBatteryCells) async {
        await runActionBattery(trials: trials, cells: cells, includeGrabCanary: true)
    }

    /// #200F cell list — promoted-production control plus the three
    /// survey-derived treatments, in dispatch order. Pinned.
    nonisolated static let communityBatteryCells: [ActionBatteryCell] = [
        .armed, .armedScoped, .armedCreateonly, .armedFindfix,
    ]

    /// #200F one-tap wrapper: 4 cells × four prompts (grab canary
    /// included) — 16 × trials generations.
    func runCommunityBattery(trials: Int,
                             cells: [ActionBatteryCell] = LocalChatBackend.communityBatteryCells) async {
        await runActionBattery(trials: trials, cells: cells, includeGrabCanary: true)
    }

    /// #200G cell list — control vs the explicit-true findfix cell (identity
    /// since the promotion, so the two halves pool). Pinned.
    nonisolated static let findfixBatteryCells: [ActionBatteryCell] = [.armed, .armedFindfix]

    /// #200G re-verify wrapper: promoted-production control vs the
    /// explicit-true findfix cell — identity since the promotion, so both
    /// halves measure production and pool (the #200D re-verify pattern).
    /// Four prompts × 8 cells-worth of trials; the grab canary rides at
    /// pooled n, which is where the #200F grabs caveat (5/10 vs 4/9)
    /// gets settled.
    func runFindfixBattery(trials: Int,
                           cells: [ActionBatteryCell] = LocalChatBackend.findfixBatteryCells) async {
        await runActionBattery(trials: trials, cells: cells, includeGrabCanary: true)
    }

    /// #200H cell list — promoted-production control plus the two
    /// spiral-treatment seams, in dispatch order. Pinned.
    nonisolated static let spiralBatteryCells: [ActionBatteryCell] = [
        .armed, .armedSpiralfix, .armedStrikefix,
    ]

    /// #200H: the third-strike demote — data-derived from #200F/#200G:
    /// every healthy create used at most 2 calls of any one tool; every
    /// spiral casualty had a tool at 3+ (searchConversations×5 at the
    /// 8,192-token overflow). `.disallowed` closes the decode mask so the
    /// model answers with what it already has.
    nonisolated static func spiralBudgetMode(tally: [String: Int]) -> GenerationOptions.ToolCallingMode {
        tally.values.contains { $0 >= 3 } ? .disallowed : .allowed
    }

    /// #209: prompts on which OMITTING the field is the CORRECT answer.
    ///
    /// This is the answer to an unevaluable disease: the missing-required-
    /// property failure runs at 1.4% on existing prompts because it only ever
    /// happened on SPURIOUS calls, so #209's dispatch pre-registered that no
    /// efficacy bar was writable. But "What's the weather?" names no place, and
    /// "How am I doing today?" names no metric — on these, an empty object is
    /// what a correct model SHOULD produce, and the pre-#209 schema forbade it.
    /// **Provoke the condition rather than lower the bar.**
    ///
    /// The two `-named` rows are the controls: a field IS available to fill, so
    /// both schemas should behave identically. If the rollback arm fails those
    /// too, the mechanism is not what this lane thinks it is.
    nonisolated static let readToolBatteryPrompts: [(tag: String, text: String)] = [
        ("weatherbare", "What's the weather?"),
        ("weathernamed", "What's the weather in Biloxi?"),
        ("healthbare", "How am I doing today?"),
        ("healthnamed", "How many steps have I taken today?"),
    ]

    /// #209 cell list — production vs the pinned read-tool field rollback. Pinned.
    nonisolated static let readToolBatteryCells: [ActionBatteryCell] = [.armed, .armedFieldrollback]

    /// #209 one-tap wrapper: production vs the pinned read-tool rollback, on
    /// prompts where omission is correct — 8 × trials generations. READ tools
    /// only, so nothing is written and the reap is a no-op.
    func runReadToolBattery(trials: Int,
                            cells: [ActionBatteryCell] = LocalChatBackend.readToolBatteryCells) async {
        await runActionBattery(trials: trials,
                               cells: cells,
                               promptSet: Self.readToolBatteryPrompts)
    }

    /// #211: the two step-question prompts, control vs the scoped
    /// `readMotion` description. `stepsdirect` is the disease (0/20 step
    /// numbers, 20/20 routed to `readMotion`); `stepsimplicit` checks the fix
    /// does not simply push every motion question at `readHealth`.
    nonisolated static let motionScopeBatteryPrompts: [(tag: String, text: String)] = [
        ("stepsdirect", "How many steps have I taken today?"),
        ("motiondirect", "Am I walking or sitting still right now?"),
    ]

    /// #211 cell list — promoted production vs the pinned `readMotion` rollback. Pinned.
    nonisolated static let motionScopeBatteryCells: [ActionBatteryCell] = [.armed, .armedMotionrollback]

    /// #211 one-tap wrapper: 2 cells × 2 prompts × trials. READ tools only —
    /// nothing written, reap is a no-op.
    func runMotionScopeBattery(trials: Int,
                               cells: [ActionBatteryCell] = LocalChatBackend.motionScopeBatteryCells) async {
        await runActionBattery(trials: trials,
                               cells: cells,
                               promptSet: Self.motionScopeBatteryPrompts)
    }

    /// #211 follow-on cell list — promoted production vs production-plus-boundary. Pinned.
    nonisolated static let motionRedirectBatteryCells: [ActionBatteryCell] = [.armed, .armedMotionredirect]

    /// #211 follow-on: PROMOTED production vs production-plus-boundary, on the
    /// same two prompts. `motiondirect` carries the effect under test (extra
    /// tool chaining); `stepsdirect` is the guard — the #211 win must survive.
    func runMotionRedirectBattery(trials: Int,
                                  cells: [ActionBatteryCell] = LocalChatBackend.motionRedirectBatteryCells) async {
        await runActionBattery(trials: trials,
                               cells: cells,
                               promptSet: Self.motionScopeBatteryPrompts)
    }

    /// #214 cell list — production vs per-intent belt plus composition licensing. Pinned.
    nonisolated static let scopedV2BatteryCells: [ActionBatteryCell] = [.armed, .armedScopedv2]

    /// #214 one-tap wrapper — THE structural lane. Production control vs
    /// per-intent belt + composition licensing, on all four prompts with the
    /// grab canary IN: the canary is the primary measurement here, not a
    /// side-check. 2 cells × 4 prompts × trials.
    func runScopedV2Battery(trials: Int,
                            cells: [ActionBatteryCell] = LocalChatBackend.scopedV2BatteryCells) async {
        await runActionBattery(trials: trials,
                               cells: cells,
                               includeGrabCanary: true)
    }

    /// #215 cell list — the unrouted control vs production's routed configuration. Pinned.
    nonisolated static let routedActionBatteryCells: [ActionBatteryCell] = [.armed, .routedProduction]

    /// #215 one-tap wrapper — THE missing denominator. Unrouted control vs
    /// production's routed configuration, on all four prompts with the grab
    /// canary IN, because the canary is the primary measurement: 2 cells × 4
    /// prompts × trials, plus one router generation per routed trial.
    ///
    /// **Stated before the run, so the result cannot be read backwards:**
    ///
    /// - The three CREATE prompts should route ARMED ~100% (the router probe
    ///   has them at 200/200 on `expected: true` rows). If they do, the
    ///   routed create rate should land on the control's, and the delta is the
    ///   router's latency and nothing else.
    /// - The HAIKU canary should route TOOLLESS ~100%, so its grab rate
    ///   should be **0/n by construction** — a turn with no belt cannot grab.
    ///   #214 measured 8/10 grabs on the unrouted control. If the routed arm
    ///   is not ~0, either the router misroutes composition prompts far more
    ///   than the probe says, or a no-belt turn can still emit a grab — and
    ///   either of those is a bigger finding than the lane was built for.
    ///
    /// **What would falsify the reframing**: a routed haiku grab rate that is
    /// not ~0. That would mean #214's "the disease is an instrument property"
    /// conclusion — which is the reason this lane exists — is wrong, and the
    /// grab disease survives into production after all.
    func runRoutedActionBattery(trials: Int,
                                cells: [ActionBatteryCell] = LocalChatBackend.routedActionBatteryCells) async {
        await runActionBattery(trials: trials,
                               cells: cells,
                               includeGrabCanary: true)
    }

    /// #216 cell list — both arms routed; only the armed belt differs. Pinned.
    nonisolated static let routedScopedBatteryCells: [ActionBatteryCell] = [.routedProduction, .routedScoped]

    /// #216 one-tap wrapper — the narrow belt, re-tried where it cannot lose.
    /// Both arms ROUTED, so the only difference is the belt an armed turn sees:
    /// 2 cells × 4 prompts × trials, plus one router generation per trial.
    ///
    /// **Bars, stated before the run:**
    ///
    /// - **Gate** — control calendar calls/trial median **≥3**. #215 measured
    ///   exactly 3; below that the overhead this lane targets is not present
    ///   tonight and the treatment has nothing to remove.
    /// - **Primary A, the point** — treatment calendar calls/trial median
    ///   **≤1**. The belt has no `lookupContact` and no `readCalendar`, so this
    ///   should hold by construction, and failing it means something other than
    ///   tool availability is driving the lookups.
    /// - **Primary B, the promotion-killer** — treatment calendar creates
    ///   **≥8/10**. #200F's narrow-belt run put calendar at a 10/10 ceiling, but
    ///   the create rate is what a latency win must not buy.
    /// - **Primary C** — treatment remind and alarm creates **≥9/10 each**.
    ///   Those are at 10/10 with one call apiece; narrowing must not disturb a
    ///   ceiling it was not aimed at.
    /// - **Primary D, the #214 objection, measured rather than argued** —
    ///   treatment haiku clean turns **≥8/10**. Composition should be untouched
    ///   because the router sends it toolless in BOTH arms, so neither belt is
    ///   ever registered. Carrying the canary costs 20 generations to turn
    ///   "unreachable by argument" into "unreachable, measured" — and #214 died
    ///   on exactly this, so a lane reopening it without measuring composition
    ///   would deserve to be distrusted.
    ///
    /// **What would falsify the premise:** haiku clean turns below 8/10, or any
    /// haiku trial routing ARMED. Either means the composition objection reaches
    /// production after all and #214's closure was right.
    func runRoutedScopedBattery(trials: Int,
                                cells: [ActionBatteryCell] = LocalChatBackend.routedScopedBatteryCells) async {
        await runActionBattery(trials: trials,
                               cells: cells,
                               includeGrabCanary: true)
    }

    /// #200H one-tap wrapper: 3 cells × four prompts (grab canary
    /// included) — 12 × trials generations.
    func runSpiralBattery(trials: Int,
                          cells: [ActionBatteryCell] = LocalChatBackend.spiralBatteryCells) async {
        await runActionBattery(trials: trials, cells: cells, includeGrabCanary: true)
    }

    /// #200I cell list — the spiralfix re-measure after the event-scoped
    /// reword. Strikefix is parked (its tally instrument is unproven and
    /// no third strike ever came due in #200H), so the trials go to the
    /// control and the treatment only. Pinned.
    nonisolated static let spiralfixBatteryCells: [ActionBatteryCell] = [
        .armed, .armedSpiralfix,
    ]

    /// #200I one-tap wrapper: 2 cells × four prompts (grab canary
    /// included — the reword's whole point is that grabs come back to
    /// control) — 8 × trials generations.
    func runSpiralfixBattery(trials: Int,
                             cells: [ActionBatteryCell] = LocalChatBackend.spiralfixBatteryCells) async {
        await runActionBattery(trials: trials, cells: cells, includeGrabCanary: true)
    }

    /// #200J cell list — production control vs the card-narration clause.
    /// Pinned.
    nonisolated static let cardfixBatteryCells: [ActionBatteryCell] = [
        .armed, .armedCardfix,
    ]

    /// #200J one-tap wrapper: 2 cells × four prompts — 8 × trials
    /// generations. The clause names every action tool, so all four
    /// prompts run even though the remind path is where #200I found the
    /// narration bucket.
    func runCardfixBattery(trials: Int,
                           cells: [ActionBatteryCell] = LocalChatBackend.cardfixBatteryCells) async {
        await runActionBattery(trials: trials, cells: cells, includeGrabCanary: true)
    }

    /// #200K cell list — one run doing two jobs. `.armed` and
    /// `.armedCardfix` are IDENTICAL since the promotion (the cell passes
    /// the promoted flag explicitly), so they pool as the production
    /// re-verify at n=20/prompt — which is what settles #200J's calendar
    /// guard, whose control read 7/10, 4/10, 10/10 across three runs.
    /// `.armedDatefix` measures the new treatment against that pooled
    /// control in the same run. Pinned.
    nonisolated static let datefixBatteryCells: [ActionBatteryCell] = [
        .armed, .armedCardfix, .armedDatefix,
    ]

    /// #200K one-tap wrapper: 3 cells × four prompts — 12 × trials
    /// generations.
    func runDatefixBattery(trials: Int,
                           cells: [ActionBatteryCell] = LocalChatBackend.datefixBatteryCells) async {
        await runActionBattery(trials: trials, cells: cells, includeGrabCanary: true)
    }

    /// #200L cell list — the calendar lane. Promoted production, the same
    /// text with the promoted card clause REMOVED (the pinned rollback),
    /// and the #200I spiral carve-out. One run separates the two live
    /// hypotheses for #200K's 8/18 calendar: that the promoted clause
    /// costs calendar, or that the "Sam" identity dead-end owns it —
    /// which was 14 of 14 classified calendar misses last run. Pinned.
    nonisolated static let calendarBatteryCells: [ActionBatteryCell] = [
        .armed, .armedCardrollback, .armedSpiralfix,
    ]

    /// #200L one-tap wrapper: 3 cells × four prompts — 12 × trials
    /// generations.
    func runCalendarBattery(trials: Int,
                            cells: [ActionBatteryCell] = LocalChatBackend.calendarBatteryCells) async {
        await runActionBattery(trials: trials, cells: cells, includeGrabCanary: true)
    }

    /// #200M cell list — production, the v3 dead-end carve-out, and v2 in
    /// the SAME run, so the two treatment versions are compared against
    /// each other rather than against remembered numbers from different
    /// runs (the #200I drift lesson, applied to treatments). Pinned.
    nonisolated static let deadendBatteryCells: [ActionBatteryCell] = [
        .armed, .armedDeadendfix, .armedSpiralfix,
    ]

    /// #200M one-tap wrapper: 3 cells × four prompts — 12 × trials
    /// generations.
    func runDeadendBattery(trials: Int,
                           cells: [ActionBatteryCell] = LocalChatBackend.deadendBatteryCells) async {
        await runActionBattery(trials: trials, cells: cells, includeGrabCanary: true)
    }

    /// #200N cell list — the v3 confirmation A/B. #200M's v3 passed 5 of 6
    /// bars and missed remind by ONE trial, with both misses being the
    /// known conserved stall and 8/10 sitting inside production's own
    /// historical range. The bar was set at "within 1" before the data
    /// existed precisely so that call would not be made by eyeball
    /// afterwards, so it gets a second independent run instead — against a
    /// baseline that has finally held still (production calendar 5/10 in
    /// both #200L and #200M). v2 is deliberately absent: #200M found it
    /// resurrects find-first, so it is retired rather than re-measured.
    /// Pinned.
    nonisolated static let deadendVerifyBatteryCells: [ActionBatteryCell] = [
        .armed, .armedDeadendfix,
    ]

    /// #200N one-tap wrapper: 2 cells × four prompts — 8 × trials
    /// generations.
    func runDeadendVerifyBattery(trials: Int,
                                 cells: [ActionBatteryCell] = LocalChatBackend.deadendVerifyBatteryCells) async {
        await runActionBattery(trials: trials, cells: cells, includeGrabCanary: true)
    }

    /// #200O cell list — one run, two jobs (the #200K shape). `.armed`
    /// and `.armedDeadendfix` are IDENTICAL since the promotion, so they
    /// pool as the production re-verify at n=20/prompt — confirming the
    /// calendar promotion at a real sample size — while `.armedGrabfix`
    /// measures the new treatment against that pooled control. Pinned.
    nonisolated static let grabfixBatteryCells: [ActionBatteryCell] = [
        .armed, .armedDeadendfix, .armedGrabfix,
    ]

    /// #200O one-tap wrapper: 3 cells × four prompts — 12 × trials
    /// generations.
    func runGrabfixBattery(trials: Int,
                           cells: [ActionBatteryCell] = LocalChatBackend.grabfixBatteryCells) async {
        await runActionBattery(trials: trials, cells: cells, includeGrabCanary: true)
    }

    /// #204 cell list — the two promoted INSTRUCTIONS clauses, each against
    /// its own rollback, WARM and WITHIN-RUN. Both promotions were
    /// re-verified only on a COLD instrument against cross-run historical
    /// baselines (#200K, #200O), and #200O itself proved cross-run
    /// comparison worthless here — its three cells landed on exactly 6/10
    /// remind on three different texts.
    ///
    /// Production runs FIRST: the incumbent takes the cool slot, and since
    /// the rollbacks are the arms that must exhibit a DISEASE, penalising
    /// them thermally is the conservative direction. Pinned.
    nonisolated static let clauseReverifyBatteryCells: [ActionBatteryCell] = [
        .armed, .armedCardrollback, .armedCarveoutrollback,
    ]

    /// #204 one-tap wrapper: 3 cells × four prompts — 12 × trials
    /// generations, plus the discarded warm-up.
    func runClauseReverifyBattery(trials: Int,
                                  cells: [ActionBatteryCell] = LocalChatBackend.clauseReverifyBatteryCells) async {
        await runActionBattery(trials: trials, cells: cells,
                               includeGrabCanary: true)
    }

    /// #199 cell list — ONE cell. This run measures a BASE RATE and tests
    /// nothing, so a treatment arm would be premature: #199's only recorded
    /// observation is 1 fabrication in ~35 declined GRABS (~3%), and a grab
    /// is a decline of an action the model never wanted. **The rate for a
    /// declined INTENDED create is completely unmeasured**, and #202B's
    /// finding (the model asserts completion precisely when it meant to act
    /// and could not) says it should be far higher. Measure first, treat
    /// second — the #201 sequencing lesson.
    nonisolated static let declineBatteryCells: [ActionBatteryCell] = [.armed]

    /// #199: what does production SAY after the user declines the card?
    ///
    /// The armed branch's honesty clause says "never invent a value" —
    /// #199's own filing observed that this class "invents an ACTION", which
    /// that sentence does not cover. **Clause v2 DOES forbid claiming a
    /// completed action, but it is toolless-only by construction** (pinned:
    /// the armed instructions are byte-identical with the flag on). So the
    /// one path where a user explicitly said NO has no clause against
    /// claiming it happened anyway.
    ///
    /// Scored from reply TEXT, which is legitimate here for the same reason
    /// it was in #202C: auto-DECLINE means no artifact can exist, so text is
    /// all there is and there is nothing for it to lie against.
    func runDeclineBattery(trials: Int,
                           cells: [ActionBatteryCell] = LocalChatBackend.declineBatteryCells) async {
        await runActionBattery(trials: trials, cells: cells,
                               includeGrabCanary: true)
    }

    /// #200P cell list — production vs the stall clause, both arms in the
    /// SAME run. #200O proved cross-run comparison is worthless here (its
    /// three cells landed on exactly 6/10 remind on three different
    /// texts), so the control rides along and every bar is a within-run
    /// delta. Pinned.
    nonisolated static let stallfixBatteryCells: [ActionBatteryCell] = [
        .armed, .armedStallfix,
    ]

    /// #200P one-tap wrapper: 2 cells × four prompts — 8 × trials
    /// generations.
    func runStallfixBattery(trials: Int,
                            cells: [ActionBatteryCell] = LocalChatBackend.stallfixBatteryCells) async {
        await runActionBattery(trials: trials, cells: cells, includeGrabCanary: true)
    }

    /// #200Q cell list — production vs the schema swap, both arms in one
    /// run (the #200O within-run rule). Pinned.
    nonisolated static let schemafixBatteryCells: [ActionBatteryCell] = [
        .armed, .armedSchemafix,
    ]

    /// #200Q one-tap wrapper: 2 cells × four prompts — 8 × trials
    /// generations.
    func runSchemafixBattery(trials: Int,
                             cells: [ActionBatteryCell] = LocalChatBackend.schemafixBatteryCells) async {
        await runActionBattery(trials: trials, cells: cells, includeGrabCanary: true)
    }

    /// #200S cell list — the promotion's re-verify. `.armed` and
    /// `.armedSchemafix` are IDENTICAL post-promotion, so they pool as
    /// production at n=20/prompt, while `.armedSchemarollback` measures the
    /// pre-promotion schema in the SAME run — so the promotion is judged
    /// against its own rollback rather than against a remembered number.
    /// Same shape as #200K and #200O. Pinned.
    nonisolated static let schemaReverifyBatteryCells: [ActionBatteryCell] = [
        .armed, .armedSchemafix, .armedSchemarollback,
    ]

    /// #200S one-tap wrapper: 3 cells × four prompts — 12 × trials
    /// generations.
    func runSchemaReverifyBattery(trials: Int,
                                  cells: [ActionBatteryCell] = LocalChatBackend.schemaReverifyBatteryCells) async {
        await runActionBattery(trials: trials, cells: cells, includeGrabCanary: true)
    }

    /// #200T cell list — production control vs the calendar schema swap,
    /// two arms in ONE run. Cross-run comparison is not admissible here
    /// (#200O put three cells on exactly 6/10 on three different texts), so
    /// the control travels with the treatment. Bars are pre-registered in
    /// `dispatch/OPUS-T27-200T-calendar-schema.md`. Pinned.
    nonisolated static let calfixBatteryCells: [ActionBatteryCell] = [
        .armed, .armedCalfix,
    ]

    /// #200T one-tap wrapper: 2 cells × four prompts — 8 × trials
    /// generations.
    func runCalfixBattery(trials: Int,
                          cells: [ActionBatteryCell] = LocalChatBackend.calfixBatteryCells) async {
        await runActionBattery(trials: trials, cells: cells, includeGrabCanary: true)
    }

    /// #200U cell list — control, the promotable result-text fix, and the
    /// ceiling probe that bounds it, three arms in ONE run. The co-primary
    /// bar is the dead-end MISS COUNT, not the rate: at n=10 a rate carries
    /// about ±1.5 trials of noise and the count does not. Bars are
    /// pre-registered in `dispatch/OPUS-T27-200U-contact-deadend.md`. Pinned.
    nonisolated static let deadend2BatteryCells: [ActionBatteryCell] = [
        .armed, .armedDeadend2, .armedNocontact,
    ]

    /// #200U one-tap wrapper: 3 cells × four prompts — 12 × trials
    /// generations.
    func runDeadend2Battery(trials: Int,
                            cells: [ActionBatteryCell] = LocalChatBackend.deadend2BatteryCells) async {
        await runActionBattery(trials: trials, cells: cells, includeGrabCanary: true)
    }

    /// #200V cell list — #200U's three cells in REVERSED order, so production
    /// runs LAST. The only change from #200U is position, which is exactly the
    /// variable under test: in #200S, #200T and #200U the FIRST cell posted
    /// the lowest calendar number, so a cold-start artifact is a live rival
    /// explanation for #200U's 7/10 → 10/10. Pinned as an exact reversal.
    nonisolated static let deadendConfirmBatteryCells: [ActionBatteryCell] = [
        .armedNocontact, .armedDeadend2, .armed,
    ]

    /// #200V: the warm-up trial's console tag. It says `warmup`, never a cell
    /// rawValue, so no classifier and no reap line can mistake a discarded
    /// warm-up trial for a counted one.
    nonisolated static func batteryWarmupTag(prompt: String) -> String {
        "shape=warmup p=\(prompt) t=0"
    }

    /// #201B: thermal state at cell boundaries. 320-trial runs are long enough
    /// for drift to matter, and since production runs LAST a hot device
    /// penalises the CONTROL — the opposite direction from #200V's cold-start
    /// bias, and a confound that could manufacture a treatment win. Emitted so
    /// the verdict can read it instead of assuming it away.
    nonisolated static func thermalLabel(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }

    nonisolated static func thermalLine(cell: String, at moment: String,
                                        state: ProcessInfo.ThermalState) -> String {
        "battery: THERMAL cell=\(cell) at=\(moment) state=\(thermalLabel(state)) (#201B)"
    }

    /// The RECORD form of the same reading — compact, and what the classifier
    /// reads so thermal comparability is enforced in code rather than by eye.
    nonisolated static func thermalRecordEntry(cell: String, at moment: String,
                                               state: ProcessInfo.ThermalState) -> String {
        "\(cell):\(moment)=\(thermalLabel(state))"
    }

    /// Emits a cell-boundary reading to BOTH sinks.
    func emitThermal(cell: String, at moment: String) {
        let state = ProcessInfo.processInfo.thermalState
        Self.batteryEmit(Self.thermalLine(cell: cell, at: moment, state: state))
        Self.batteryRecorder.recordThermal(
            Self.thermalRecordEntry(cell: cell, at: moment, state: state))
    }

    /// #200W: the warm-up is now the DEFAULT. #200V measured the cold-start
    /// artifact WITHIN one run — the same production configuration scored
    /// calendar 7/10 running first and cold (#200T, #200U) and 9/10 running
    /// last and warm, with the "Sam" dead-end going 3/10 → 0/10, and the
    /// warm-up flattened the gradient (calendar by slot 9, 10, 9 against
    /// #200U's 7, 10, 10).
    ///
    /// Every pre-#200V control number is therefore cold-biased. The flag
    /// survives so a run can opt OUT and reproduce one of those measurements
    /// exactly.
    nonisolated static let batteryWarmupDefault = true

    /// #200W cell list — #200T's two arms re-run WARM, with production LAST.
    /// Production-last is the conservative direction: any residual position
    /// advantage that survives the warm-up accrues to the CONTROL, making the
    /// treatment's job harder. Same two arms as `calfixBatteryCells`, so the
    /// comparison is the same comparison — only warmth and position changed.
    ///
    /// The RATE is not the primary bar here and the dispatch says so in
    /// advance: warm production calendar is ~9/10, so a +2 bar needs 11/10 and
    /// the ceiling clause reduces to a +1 delta at n=10. The primaries are the
    /// location-spiral and invented-location counts, which have large effects
    /// and no ceiling. Pinned.
    nonisolated static let calfixWarmBatteryCells: [ActionBatteryCell] = [
        .armedCalfix, .armed,
    ]

    /// #200W one-tap wrapper: 2 cells × four prompts — 8 × trials
    /// generations, plus the now-default warm-up pass.
    func runCalfixWarmBattery(trials: Int,
                              cells: [ActionBatteryCell] = LocalChatBackend.calfixWarmBatteryCells) async {
        await runActionBattery(trials: trials, cells: cells,
                               includeGrabCanary: true)
    }

    /// #200X cell list — the promotion judged against its OWN rollback, warm,
    /// in one run, production LAST. This is the confidence run the promotion is
    /// owed: #200W's gate was not cleanly met (its `searchPlaces` clause was
    /// unevaluable at a 1/10 control), so the promoted tool is measured against
    /// the exact thing it replaced rather than against a remembered number —
    /// the #200S re-verify shape. Pinned.
    nonisolated static let calRollbackVerifyBatteryCells: [ActionBatteryCell] = [
        .armedCalrollback, .armed,
    ]

    /// #200X one-tap wrapper: 2 cells × four prompts — 8 × trials generations,
    /// plus the default warm-up pass.
    func runCalRollbackVerifyBattery(trials: Int,
                                     cells: [ActionBatteryCell] = LocalChatBackend.calRollbackVerifyBatteryCells) async {
        await runActionBattery(trials: trials, cells: cells,
                               includeGrabCanary: true)
    }

    /// #201 cell list — #200U's fix re-measured at n=20, production LAST.
    /// #200V withdrew that fix on a single clause: warm production showed ZERO
    /// dead-end misses. Three warm samples killed that basis — 0/10 (#200V),
    /// 2/10 (#200W), 3/10 (#200Z) — so #200V's zero was itself the small-sample
    /// artifact it existed to catch.
    ///
    /// The primary here is a COUNT, not a rate, which is why n doubles: at n=10
    /// a 2-or-3 event count cannot carry a bar. Arm B (tool removal) is
    /// deliberately absent — #200U measured it relocating the spiral into
    /// `searchConversations` rather than removing it. Pinned.
    nonisolated static let deadendReconsiderBatteryCells: [ActionBatteryCell] = [
        .armedDeadend2, .armed,
    ]

    /// #201B cell list — the SAME two arms with PRODUCTION FIRST. #201B passed
    /// its bars (dead-ends 0/40 vs 5/40, Fisher p≈0.027) but its thermal states
    /// were not comparable: production ran its whole cell at `serious` while the
    /// treatment started at `fair`. Reversing puts production in the COOL slot,
    /// so this run doubles as the thermal control — if production still shows
    /// dead-ends when it runs first and cool, thermal is exonerated and the
    /// effect is real; if they vanish, the effect was thermal and gets withdrawn.
    /// Pinned.
    nonisolated static let deadendReversedBatteryCells: [ActionBatteryCell] = [
        .armed, .armedDeadend2,
    ]

    /// #201B reversed wrapper.
    func runDeadendReversedBattery(trials: Int,
                                   cells: [ActionBatteryCell] = LocalChatBackend.deadendReversedBatteryCells) async {
        await runActionBattery(trials: trials, cells: cells,
                               includeGrabCanary: true)
    }

    /// #201 one-tap wrapper: 2 cells × four prompts — 8 × trials generations
    /// (160 at n=20), plus the default warm-up pass.
    func runDeadendReconsiderBattery(trials: Int,
                                     cells: [ActionBatteryCell] = LocalChatBackend.deadendReconsiderBatteryCells) async {
        await runActionBattery(trials: trials, cells: cells,
                               includeGrabCanary: true)
    }

    /// #200V one-tap wrapper: 3 cells × four prompts — 12 × trials
    /// generations, PLUS a discarded warm-up pass over the prompt list.
    func runDeadendConfirmBattery(trials: Int,
                                  cells: [ActionBatteryCell] = LocalChatBackend.deadendConfirmBatteryCells) async {
        await runActionBattery(trials: trials, cells: cells,
                               includeGrabCanary: true, warmup: true)
    }

    /// #200W: the pre-#200V instrument, reachable on purpose — `warmup: false`
    /// reproduces a cold-first measurement exactly, which is what makes the
    /// cold-start artifact re-measurable rather than merely asserted.
    func runColdCalfixBattery(trials: Int) async {
        await runActionBattery(trials: trials, cells: Self.calfixWarmBatteryCells,
                               includeGrabCanary: true, warmup: false)
    }

    /// #200F: one marker sweep's accounting. `hadAccess` false means the
    /// store could not be enumerated — the summary shows a skip, never a
    /// silent zero.
    /// harness-visible (#331): the negative bar drives the real sweep, so
    /// its counts have to be nameable from the test target.
    struct MarkerSweepCounts {
        var reminders = 0
        var events = 0
        var failures = 0
        var remindersAccess = false
        var eventsAccess = false
    }

    /// The [T27-battery] reminders + events sweep — shared by the
    /// per-trial reap (#200F Part 0, `emitSteps: false` — the REAP-TRIAL
    /// line is the accounting) and the end-of-run backstop (`emitSteps:
    /// true`, the #200 REAP-STEP grammar). Alarms are NOT here: they are
    /// tracked-ID, not marker-matched, and stay end-of-run.
    /// harness-visible (#331) and `static` because it reads no instance
    /// state: the negative bar has to exercise THIS function, not a copy of
    /// it in a test — a copy could drift and quietly turn a widened scope
    /// back into a pass.
    static func sweepMarkedRemindersAndEvents(emitSteps: Bool) async -> MarkerSweepCounts {
        let marker = ToolConfirmationCenter.batteryArtifactMarker
        let store = EKEventStore()
        var counts = MarkerSweepCounts()

        // Step markers (live-only): all four 2026-07-28 action-battery
        // crashes died somewhere in THIS sweep (records complete
        // through the last trial, never sealed) — the capture log's last
        // REAP-STEP line names the killing sub-step.
        if emitSteps { Self.batteryEmit("battery: REAP-STEP reminders begin (#200)") }

        // Reminders: enumeration needs full access. Snapshot Sendable
        // identifiers inside the completion handler (EKReminder must not
        // cross the continuation boundary), then re-fetch each by id to
        // remove it.
        //
        // The completion MUST be @Sendable: EventKit invokes it on its
        // private queue (com.apple.eventkit.reminders.search), and a plain
        // closure formed here — a MainActor context — inherits MainActor
        // isolation, which the 27b4 DEVICE runtime dynamically enforces:
        // dispatch_assert_queue_fail → brk 1. That trap was ALL FOUR
        // 2026-07-28 action-battery crashes (.ips 12:18 + 12:39, faulting
        // thread on the eventkit queue, this closure on the stack). The
        // sim runtime does not enforce the check — the probe passed while
        // every device run died. @Sendable severs the actor-context
        // inheritance; ReminderReadTool's twin closure never needed it
        // because Tool.call is nonisolated.
        //
        // #331 SCOPE GUARD: `calendars:` is the harness's OWN lists, never
        // `nil`. Passing nil searched every list on the device, so a marked
        // item in the user's default list was deleted by a title match —
        // proven, not theorised: `defaultCalendarAndListSurviveTheWholeDestroyingSurface`
        // was RED on exactly that at `b497256`. An empty owned set means
        // there is nothing of ours to sweep, which is a zero, not a licence
        // to widen the search.
        let ownedLists = BatteryTestContainer.ownedContainers(for: .reminder, in: store)
        // `remindersAccess` still tracks ACCESS and only access — the REAP
        // line's `skipped(no-access)` form must keep meaning what it says,
        // so "full access, no container yet" reports an honest zero rather
        // than a skip.
        if EKEventStore.authorizationStatus(for: .reminder) == .fullAccess {
            counts.remindersAccess = true
        }
        if counts.remindersAccess, !ownedLists.isEmpty {
            let predicate = store.predicateForIncompleteReminders(
                withDueDateStarting: nil, ending: nil, calendars: ownedLists
            )
            let markedIDs: [String] = await withCheckedContinuation { continuation in
                store.fetchReminders(matching: predicate) { @Sendable found in
                    let ids = (found ?? [])
                        .filter { ($0.title ?? "").contains(marker) }
                        .map(\.calendarItemIdentifier)
                    continuation.resume(returning: ids)
                }
            }
            if emitSteps { Self.batteryEmit("battery: REAP-STEP reminders fetched marked=\(markedIDs.count) (#200)") }
            for id in markedIDs {
                guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else {
                    counts.failures += 1
                    continue
                }
                do {
                    try store.remove(reminder, commit: true)
                    counts.reminders += 1
                } catch {
                    counts.failures += 1
                }
            }
        }
        if emitSteps { Self.batteryEmit("battery: REAP-STEP events begin (#200)") }

        // Events: enumeration also needs full access (write-only can save
        // but never read, so it cannot reap). WRITABLE calendars only, and
        // a −1d…+14d window: battery events are always near-future ("Friday
        // at noon" is days out) and can only live where a save landed —
        // birthday/subscribed/holiday calendars cannot hold them. (This
        // narrowing was first shipped as a crash-lane suspect; the .ips
        // later proved the crash was the reminders completion's isolation
        // trap above and this step never even ran. The narrowing stays as
        // scope-correctness: it is the minimal honest query for what the
        // reap needs.) events(matching:) here is SYNCHRONOUS on the
        // calling thread — no cross-queue closure, no isolation hazard.
        //
        // #331 SCOPE GUARD, the second half: `writable` was every modifiable
        // calendar on the device, which is how a marked event in the user's
        // DEFAULT calendar got deleted. It is now the harness's own
        // containers and nothing else. Marked items found elsewhere are
        // counted by `BatteryTestContainer.markedEventsOutsideContainers`
        // and reported in the CONTAINER-REAP line — never removed.
        let ownedCalendars = BatteryTestContainer.ownedContainers(for: .event, in: store)
        if EKEventStore.authorizationStatus(for: .event) == .fullAccess {
            counts.eventsAccess = true
        }
        if counts.eventsAccess, !ownedCalendars.isEmpty {
            let start = Date().addingTimeInterval(-1 * 86_400)
            let end = Date().addingTimeInterval(14 * 86_400)
            let predicate = store.predicateForEvents(withStart: start, end: end, calendars: ownedCalendars)
            let marked = store.events(matching: predicate).filter { ($0.title ?? "").contains(marker) }
            if emitSteps { Self.batteryEmit("battery: REAP-STEP events fetched marked=\(marked.count) (#200)") }
            for event in marked {
                do {
                    try store.remove(event, span: .thisEvent, commit: true)
                    counts.events += 1
                } catch {
                    counts.failures += 1
                }
            }
        }
        return counts
    }

    /// #200F Part 0: the REAP-TRIAL line — classification vocabulary,
    /// pinned byte-for-byte by test.
    nonisolated static func reapTrialLine(reminders: Int, events: Int, alarms: Int, failures: Int,
                                          tag: String) -> String {
        "battery: REAP-TRIAL reminders=\(reminders) events=\(events) alarms=\(alarms) failures=\(failures) \(tag) (#200F)"
    }

    /// #200F: one count segment of the final REAP line. The counts FOLD
    /// IN the per-trial sums so reap arithmetic stays exact — total
    /// removed this run = per-trial sums + end-of-run backstop. The
    /// no-access skip form is the #200 original, never a silent zero.
    nonisolated static func reapCountSegment(_ label: String, backstop: Int, perTrial: Int,
                                             hadAccess: Bool) -> String {
        hadAccess ? "\(label)=\(backstop + perTrial)" : "\(label)=skipped(no-access)"
    }

    /// #200 teardown: delete every [T27-battery]-marked reminder and
    /// calendar event, and cancel every battery-tracked alarm. Reminders
    /// and events are found by marker match on their titles (idempotent —
    /// leftovers from a crashed earlier run get swept too); alarms come
    /// from `AlarmService.batteryScheduledAlarmIDs`, because AlarmKit's
    /// `Alarm` carries no label back on enumeration. Returns the REAP
    /// accounting in the export's words, with the run's per-trial reap
    /// sums (#200F) folded into the counts. Missing read access shows up
    /// as skips, never as a silent zero.
    private func reapBatteryArtifacts(perTrialReminders: Int = 0, perTrialEvents: Int = 0,
                                      perTrialAlarms: Int = 0,
                                      perTrialFailures: Int = 0) async -> String {
        let backstop = await Self.sweepMarkedRemindersAndEvents(emitSteps: true)
        // #331: the wholesale half. The per-item sweep above keeps the #200
        // counts honest DURING a run; this removes the containers themselves
        // in one store operation each, so what survives a crash is a
        // container the NEXT run's start reap deletes without having to
        // enumerate anything. It runs before the alarm step so the emitted
        // #200 REAP line still reads last.
        let containerOutcome = BatteryTestContainer.reap(reason: "finish", includeAlarms: false)
        Self.batteryEmit(BatteryTestContainer.reapLine(
            reason: "finish", outcome: containerOutcome,
            outsideMarked: BatteryTestContainer.markedEventsOutsideContainers(in: EKEventStore())
        ))
        Self.batteryEmit("battery: REAP-STEP alarms begin (#200)")

        let alarmReap = AlarmService.reapBatteryAlarms()
        let failures = backstop.failures + perTrialFailures + alarmReap.failed
        Self.batteryEmit("battery: REAP-STEP alarms done cancelled=\(alarmReap.cancelled) failed=\(alarmReap.failed) (#200)")

        let remindersSegment = Self.reapCountSegment(
            "reminders", backstop: backstop.reminders,
            perTrial: perTrialReminders, hadAccess: backstop.remindersAccess
        )
        let eventsSegment = Self.reapCountSegment(
            "events", backstop: backstop.events,
            perTrial: perTrialEvents, hadAccess: backstop.eventsAccess
        )
        return "\(remindersSegment) \(eventsSegment) alarms=\(alarmReap.cancelled + perTrialAlarms) failures=\(failures)"
    }

    /// #196 battery 4: on-device router-accuracy probe — ten probes
    /// (five words-only, five device) × `trials`, one `router:` line per
    /// probe. The Mac-host grid measured 200/200; this measures the
    /// 27-beta device model, which is the one that ships.
    /// The #196 probe grid, extracted so #202A's baseline-regression gate
    /// runs the SAME ten rows the 200/200 result was measured on — a copy
    /// could drift and quietly turn a regression into a pass.
    nonisolated static let routerBaselineProbes: [(text: String, expected: Bool)] = [
        ("What's 2+2?", false),
        ("Write a haiku about sledding", false),
        ("write a 50 word summary about Norway", false),
        ("Tell me a joke about penguins", false),
        ("Write a poem for my mom's birthday", false),
        ("Remind me to buy milk tomorrow at 9am", true),
        ("What's the weather like right now?", true),
        ("Set an alarm for 6:30", true),
        ("How many steps have I taken today?", true),
        ("Do I have anything on my calendar Friday?", true),
    ]

    /// #217: the intent grid. **A SEPARATE list from `routerBaselineProbes`**,
    /// which carries a 200/200 history over exactly ten rows and from which
    /// #202A's regression gate derives its denominator — the #205 lesson,
    /// recorded there in as many words: adding rows to that list silently
    /// re-points a long-running series and moves a pre-registered bar.
    ///
    /// Two prompts per scoped intent, so a single unlucky phrasing cannot carry
    /// an intent's whole score, plus `other` rows that are the ones that matter
    /// most: contacts, past chats, places and device status are all real device
    /// requests **deliberately left OUT of the vocabulary**, and the model has
    /// to route them armed while answering `other` — arming the full belt. A
    /// model that guesses `calendar` for "when did I last text Sam" is the
    /// failure this whole design is built to avoid, and these rows are where it
    /// would show up.
    nonisolated static let intentProbeGrid: [(text: String, expectedArmed: Bool, expectedIntent: RouterIntent)] = [
        ("Remind me to buy milk tomorrow at 9am", true, .reminder),
        ("Add pick up dry cleaning to my reminders", true, .reminder),
        ("Set an alarm for 6:30", true, .alarm),
        ("Wake me up at 7 tomorrow", true, .alarm),
        ("Put lunch with Sam on my calendar Friday at noon", true, .calendar),
        ("Do I have anything on my calendar Friday?", true, .calendar),
        ("What's the weather like right now?", true, .weather),
        ("Is it going to rain this afternoon?", true, .weather),
        ("How many steps have I taken today?", true, .health),
        ("How did I sleep last night?", true, .health),
        // #217's two DANGEROUS rows. Under the narrow vocabulary these are
        // still `other` (derived by `underNarrowVocabulary`), so the control
        // arm replicates #217 exactly; under the full vocabulary they have a
        // correct scoped answer for the first time.
        ("When did I last text Sam about the boat?", true, .conversations),
        ("How much battery do I have left?", true, .device),
        ("What's Sam's phone number?", true, .contacts),
        ("Find a coffee shop near me", true, .places),
        // OUT OF VOCABULARY IN EVERY CELL — armed device requests with no belt
        // tool and no vocabulary entry, in either arm. **These keep the bar
        // falsifiable.** #217B's whole risk is a run that passes because the
        // grid stopped containing a near miss, which would measure the grid
        // rather than the model. The v2 guide deliberately never mentions
        // music, navigation or photos.
        ("Play some music", true, .other),
        ("How long will it take me to drive to the airport?", true, .other),
        ("Read the label on this bottle for me", true, .other),
        // Toolless. Intent is irrelevant when nothing is armed, but a scoped
        // answer here would reveal word-matching rather than need-classifying.
        ("Write a haiku about sledding", false, .other),
        ("What's 2+2?", false, .other),
    ]

    /// #284: the Bool-vector grid. A NEW list — `intentProbeGrid` (#217B)
    /// and `routerBaselineProbes` are closed series and never grow (#205).
    /// Row text for the first 19 rows is copied verbatim from
    /// `intentProbeGrid` so the two probes remain comparable.
    /// `expectedTools` is the danger-bar annotation, written BEFORE the run:
    /// the tools full-belt production behavior uses on that prompt. A trial
    /// is DANGEROUS iff the model armed a non-empty group set whose tools
    /// don't cover expectedTools (all-false is safe by construction — O1
    /// arms the full belt).
    nonisolated static let vectorProbeGrid: [(text: String, expectedArmed: Bool,
                                              expectedGroups: Set<CapabilityGroup>,
                                              expectedTools: Set<String>)] = [
        ("Remind me to buy milk tomorrow at 9am", true, [.reminders], ["createReminder"]),
        ("Add pick up dry cleaning to my reminders", true, [.reminders], ["createReminder"]),
        ("Set an alarm for 6:30", true, [.alarms], ["scheduleAlarm"]),
        ("Wake me up at 7 tomorrow", true, [.alarms], ["scheduleAlarm"]),
        // #215 (run F486F103) measured this exact prompt at create 10/10 +
        // readCalendar 7/10 + lookupContact 7/10. lookupContact is DELIBERATELY
        // unprotected — #215 names that chain over-serving, and #200W's un-routed
        // run saw the chain invent a place on 5/8 creates; the bar protects the
        // answer path, not the spiral (Owen, 2026-08-08).
        ("Put lunch with Sam on my calendar Friday at noon", true, [.calendar], ["createCalendarEvent", "readCalendar"]),
        ("Do I have anything on my calendar Friday?", true, [.calendar], ["readCalendar"]),
        ("What's the weather like right now?", true, [.weather], ["currentWeather"]),
        ("Is it going to rain this afternoon?", true, [.weather], ["currentWeather"]),
        ("How many steps have I taken today?", true, [.health], ["readHealth"]),
        ("How did I sleep last night?", true, [.health], ["readHealth"]),
        ("When did I last text Sam about the boat?", true, [.conversations], ["searchConversations"]),
        ("How much battery do I have left?", true, [.deviceStatus], ["deviceStatus"]),
        ("What's Sam's phone number?", true, [.contacts], ["lookupContact"]),
        ("Find a coffee shop near me", true, [.places], ["searchPlaces"]),
        // The out-of-vocabulary traps, kept verbatim (#217B). Correct vector
        // answer: armed, ALL BOOLS FALSE → full belt. No belt tool serves
        // them, so expectedTools is empty and only a spurious non-empty
        // group set can be dangerous here — exactly the failure #217B's
        // enum could not avoid.
        ("Play some music", true, [], []),
        ("How long will it take me to drive to the airport?", true, [], []),
        ("Read the label on this bottle for me", true, [], []),
        // Toolless rows, verbatim.
        ("Write a haiku about sledding", false, [], []),
        ("What's 2+2?", false, [], []),
        // #284 NEW: multi-intent rows — the union case the enum could not
        // express at all.
        ("What's my day look like tomorrow?", true, [.calendar, .reminders, .weather],
         ["readCalendar", "readReminders", "currentWeather"]),
        ("Anything due today, and do I need an umbrella?", true, [.reminders, .weather],
         ["readReminders", "currentWeather"]),
    ]

    /// #284: measurement-only rows — no bar, no expectation. Where does a
    /// capability-meta question ROUTE? (Spec §4's open question: if these
    /// route toolless, Task 12 adds the toolless capability index as its own
    /// measured arm.)
    nonisolated static let vectorMetaRows: [String] = [
        "What can you do?",
        "What kinds of things can you help me with?",
    ]

    /// #205: IMAGE TURNS ARE A #202-FAMILY DISARMAMENT and the pinned router
    /// instructions never mention images. UNDER OUR INTEGRATION the model
    /// never receives image bytes — we OCR with Vision ourselves and hand it
    /// a String; our transcript carries a placeholder, so image capability
    /// exists ONLY through `readImageText` / `BarcodeReaderTool`, and a
    /// toolless route on a photo turn is a BLIND turn. **That is a design
    /// CHOICE, not a property of the model** (#222): the beta4 SDK ships
    /// `Transcript.Segment.image` / `Transcript.ImageAttachment` /
    /// `ImageReference`, all unused here. Device-confirmed 2026-08-02
    /// ("who posted this?" → "I can't see the image itself, but the text in
    /// it…"): the behavior below is real today, and its cause is this
    /// integration. Re-derive this routing premise only if #222's true
    /// image-input question is ever decided in favor of attaching images.
    ///
    /// **Deliberately a SEPARATE list from `routerBaselineProbes`.** That one
    /// carries a 200/200 history over exactly TEN rows, and #202A's
    /// regression gate derives its denominator from it — adding rows there
    /// silently re-points a long-running series and moves a pre-registered
    /// bar. I did exactly that when first adding these, and caught it before
    /// the run: the same drift I had flagged an hour earlier when pinning
    /// this probe to `.control`. Scored as its own band.
    nonisolated static let routerImageProbes: [(text: String, expected: Bool)] = [
        ("[image attached] what does this say?", true),
        ("[image attached] read the text in this photo", true),
    ]

    /// #207: the PRODUCTION shape. Bare prompts, no marker — because
    /// production never generates one, and the 0/15 that opened this lane
    /// used `[image attached]` and was therefore GENEROUS. These are what a
    /// user actually types with a photo attached.
    nonisolated static let imageProbeGrid: [(text: String, expected: Bool)] = [
        ("what does this say?", true),
        ("read the text in this photo", true),
        ("what's in this picture?", true),
        ("scan this barcode", true),
    ]

    /// #207 GAP FOUND AFTER RUN `C2E03F53`, and it is the degenerate
    /// direction. The fix marks EVERY prompt when an image is attached, and
    /// the guide teaches marker → armed — so a turn that happens to carry a
    /// photo while asking something unrelated may now arm for no reason,
    /// which is #196's disease. **Nothing in the first grid covered this
    /// shape.** The image is irrelevant to both rows, so TOOLLESS is right.
    nonisolated static let imageWordsOnlyGrid: [(text: String, expected: Bool)] = [
        ("write a haiku about sledding", false),
        ("what's 2+2?", false),
    ]

    /// #207 arms. Two seams, measured SEPARATELY and in this order, because
    /// the signal may be sufficient alone — and if it is, the pinned
    /// `@Guide` (200/200 history) is never touched. The ctx-a-over-ctx-b
    /// parsimony rule from #202A, applied before the fact.
    enum ImageProbeArm: String, CaseIterable {
        /// Production today: raw prompt, no image signal. The reproduction gate.
        case imgNone = "img-none"
        /// The signal only — `@Guide` untouched.
        case imgSignal = "img-signal"
        /// Signal PLUS the added guide example. Only read if the signal fails.
        case imgGuide = "img-guide"

        var sendsImageSignal: Bool { self != .imgNone }
        var includesImageGuide: Bool { self == .imgGuide }
    }

    /// Production baseline FIRST — it is the reproduction gate, and the
    /// incumbent takes the cool slot (#201B).
    nonisolated static let imageProbeArms: [ImageProbeArm] = [.imgNone, .imgSignal, .imgGuide]

    /// #207: can the router be told an image is attached, and is that enough?
    /// Pure classification — no tool runs, nothing is written, nothing reaped.
    /// Every arm also re-runs the #196 baseline, because an arm that fixes
    /// images by arming everything is not a fix and re-opens #196.
    func runImageRoutingProbe(trials: Int) async {
        guard await Self.beginBatteryRun() else {
            Self.batteryEmit("battery: REFUSED — another battery is already running (#200B mutex)")
            return
        }
        defer { Self.endBatteryRun() }
        let arms = Self.imageProbeArms
        Self.batteryEmit("router: IMAGE PROBE START trials=\(trials) arms=\(arms.map(\.rawValue).joined(separator: ",")) (#207)")
        Self.batteryRecorder.beginRun(trialsPerCell: trials, cells: arms.map(\.rawValue),
                                      kind: "router-context")
        for arm in arms {
            emitThermal(cell: arm.rawValue, at: "start")
            for probe in Self.imageProbeGrid {
                var correct = 0
                let failuresBefore = Self.routerFailureTally
                for _ in 1...trials {
                    if await routeNeedsDeviceTool(
                        prompt: probe.text, context: "", variant: Self.productionRouterVariant,
                        hasImage: arm.sendsImageSignal,
                        includeImageGuide: arm.includesImageGuide) == probe.expected {
                        correct += 1
                    }
                }
                Self.batteryEmit("router: \(correct)/\(trials) expected=\(probe.expected) variant=\(arm.rawValue) band=image probe=\(probe.text)")
                Self.batteryRecorder.recordProbe(
                    probe: probe.text, expected: probe.expected, correct: correct, trials: trials,
                    variant: arm.rawValue, context: "", band: "image"
                , errors: Self.routerFailureTally - failuresBefore)
            }
            // COLLATERAL 2 (#207 gap): an image attached to a WORDS-ONLY
            // request. These carry the image signal like any other image
            // turn, so this is where "mark every prompt and teach marker →
            // armed" would over-arm. The band the promotion actually rests on.
            for probe in Self.imageWordsOnlyGrid {
                var correct = 0
                let failuresBefore = Self.routerFailureTally
                for _ in 1...trials {
                    if await routeNeedsDeviceTool(
                        prompt: probe.text, context: "", variant: Self.productionRouterVariant,
                        hasImage: arm.sendsImageSignal,
                        includeImageGuide: arm.includesImageGuide) == probe.expected {
                        correct += 1
                    }
                }
                Self.batteryEmit("router: \(correct)/\(trials) expected=\(probe.expected) variant=\(arm.rawValue) band=image-wordsonly probe=\(probe.text)")
                Self.batteryRecorder.recordProbe(
                    probe: probe.text, expected: probe.expected, correct: correct, trials: trials,
                    variant: arm.rawValue, context: "", band: "image-wordsonly"
                , errors: Self.routerFailureTally - failuresBefore)
            }
            // COLLATERAL: the #196 grid on EVERY arm. The guide arm edits a
            // measured artifact; the signal arm changes what every prompt
            // looks like. Both must prove they left the rest alone.
            for probe in Self.routerBaselineProbes {
                var correct = 0
                let failuresBefore = Self.routerFailureTally
                for _ in 1...trials {
                    if await routeNeedsDeviceTool(
                        prompt: probe.text, context: "", variant: Self.productionRouterVariant,
                        hasImage: false,
                        includeImageGuide: arm.includesImageGuide) == probe.expected {
                        correct += 1
                    }
                }
                Self.batteryEmit("router: \(correct)/\(trials) expected=\(probe.expected) variant=\(arm.rawValue) band=baseline probe=\(probe.text)")
                Self.batteryRecorder.recordProbe(
                    probe: probe.text, expected: probe.expected, correct: correct, trials: trials,
                    variant: arm.rawValue, context: "", band: "baseline"
                , errors: Self.routerFailureTally - failuresBefore)
            }
            emitThermal(cell: arm.rawValue, at: "end")
        }
        Self.batteryEmit("router: IMAGE PROBE DONE (#207)")
        Self.batteryRecorder.endRun()
    }

    func runRouterProbe(trials: Int) async {
        guard await Self.beginBatteryRun() else {
            Self.batteryEmit("battery: REFUSED — another battery is already running (#200B mutex)")
            return
        }
        defer { Self.endBatteryRun() }
        let probes = Self.routerBaselineProbes
        Self.batteryEmit("router: PROBE START trials=\(trials) probes=\(probes.count) (#196)")
        Self.batteryRecorder.beginRun(trialsPerCell: trials, cells: [])
        for probe in probes {
            var correct = 0
            let failuresBefore = Self.routerFailureTally
            for _ in 1...trials {
                // Explicitly .control: this probe's 200/200 history is the
                // CONTEXT-BLIND router's, and #202D moved production to
                // ctx-a. Pinning the variant keeps the series comparable.
                if await routeNeedsDeviceTool(prompt: probe.text, context: "",
                                              variant: .control) == probe.expected { correct += 1 }
            }
            Self.batteryEmit("router: \(correct)/\(trials) expected=\(probe.expected) probe=\(probe.text)")
            Self.batteryRecorder.recordProbe(probe: probe.text, expected: probe.expected, correct: correct, trials: trials, errors: Self.routerFailureTally - failuresBefore)
        }
        Self.batteryEmit("router: PROBE DONE (#196)")
        Self.batteryRecorder.endRun()
    }

    /// #217 — CAN this model classify intent at all, safely enough to drive a
    /// belt? A probe, not a belt lane: nothing here narrows anything, and
    /// production's `ToolIntentRoute` is untouched.
    ///
    /// Two row sets, scored separately and for different reasons:
    ///
    /// 1. **The pinned ten baseline rows, run through V2.** This is the
    ///    REGRESSION GATE. Those rows sit at 200/200 against the one-field
    ///    schema; if adding the intent field costs Bool accuracy, the lane
    ///    stops there, because the Bool is load-bearing for every turn and the
    ///    scoping prize is worth less than it.
    /// 2. **The intent grid**, scored on the intent.
    ///
    /// **Bars, stated before the run:**
    ///
    /// - **Gate** — V2's Bool accuracy on the ten baseline rows **≥95%**
    ///   (#202A's pre-registered `BASELINE_GATE`, unchanged, against a 200/200
    ///   history). Below it, nothing else here is worth reading.
    /// - **Primary A** — intent accuracy on the five scoped intents **≥90%**.
    /// - **Primary B, the safety bar and the one that decides the design** —
    ///   **DANGEROUS answers ≤2%.** A dangerous answer is a scoped intent that
    ///   is the WRONG scoped intent, or a scoped intent on a row whose right
    ///   answer is `other`; both arm a belt missing the tool the turn needs.
    ///   Answering `other` when a scoped intent was right is a MISS, not a
    ///   danger — it arms the full belt, which is exactly today.
    /// - **Primary C** — the four out-of-vocabulary armed rows (contacts, past
    ///   chats, places, device status) answer `other` **≥90%**. They are real
    ///   device requests deliberately outside the vocabulary, and they are
    ///   where over-eager pattern-matching would surface.
    ///
    /// **What would falsify the approach:** dangerous answers above 2%. The
    /// whole case for an intent router rests on its failures being free, and a
    /// model that guesses a scoped intent rather than saying `other` converts
    /// every misclassification into a disarmed turn — strictly worse than the
    /// full belt we ship today, and not worth 2.6 seconds.
    func runIntentRouterProbe(trials: Int) async {
        guard await Self.beginBatteryRun() else {
            Self.batteryEmit("battery: REFUSED — another battery is already running (#200B mutex)")
            return
        }
        defer { Self.endBatteryRun() }
        let baseline = Self.routerBaselineProbes
        let grid = Self.intentProbeGrid
        let cells = IntentProbeCell.allCases
        Self.batteryEmit("router: INTENT PROBE START trials=\(trials) cells=\(cells.count) baseline=\(baseline.count) grid=\(grid.count) (#217B)")
        Self.batteryRecorder.beginRun(trialsPerCell: trials,
                                      cells: cells.map(\.rawValue), kind: "intent")

        for cell in cells {
            // 1. The regression gate, per cell: the pinned ten through this
            // cell's schema. Run per cell because a bigger vocabulary is a
            // bigger schema, and the Bool's cost is exactly what the gate is
            // for — measuring it once would leave three cells ungated.
            for probe in baseline {
                var correct = 0
                var tally: [String: Int] = [:]
                let failuresBefore = Self.routerFailureTally
                for _ in 1...trials {
                    let route = await routeIntent(prompt: probe.text, cell: cell)
                    if route.needsDeviceTool == probe.expected { correct += 1 }
                    tally[route.intent.rawValue, default: 0] += 1
                }
                Self.batteryEmit("router: [\(cell.rawValue)] baseline \(correct)/\(trials) expected=\(probe.expected) tally=\(tally) probe=\(probe.text)")
                Self.batteryRecorder.recordProbe(
                    probe: probe.text, expected: probe.expected, correct: correct, trials: trials,
                    variant: cell.rawValue, band: "baseline",
                    errors: Self.routerFailureTally - failuresBefore,
                    intentTally: tally)
            }

            // 2. The intent grid. Each row is scored against the expectation
            // THIS cell could actually express: the narrow cells collapse the
            // four added domains to `other` via `underNarrowVocabulary`, so a
            // row is never marked wrong for failing to say a word the cell
            // never offered.
            for row in grid {
                let want = cell.usesFullVocabulary ? row.expectedIntent
                                                   : row.expectedIntent.underNarrowVocabulary
                var boolCorrect = 0
                var tally: [String: Int] = [:]
                let failuresBefore = Self.routerFailureTally
                for _ in 1...trials {
                    let route = await routeIntent(prompt: row.text, cell: cell)
                    if route.needsDeviceTool == row.expectedArmed { boolCorrect += 1 }
                    tally[route.intent.rawValue, default: 0] += 1
                }
                let hits = tally[want.rawValue] ?? 0
                Self.batteryEmit("router: [\(cell.rawValue)] intent \(hits)/\(trials) want=\(want.rawValue) armed=\(boolCorrect)/\(trials) tally=\(tally) probe=\(row.text)")
                Self.batteryRecorder.recordProbe(
                    probe: row.text, expected: row.expectedArmed, correct: boolCorrect, trials: trials,
                    variant: cell.rawValue, band: "intent",
                    errors: Self.routerFailureTally - failuresBefore,
                    expectedIntent: want.rawValue, intentTally: tally)
            }
        }
        Self.batteryEmit("router: INTENT PROBE DONE (#217B)")
        Self.batteryRecorder.endRun()
    }

    /// #284: the danger-bar scorer, pure so it is unit-pinned. Dangerous ==
    /// the narrowed belt would lack a tool production uses on this prompt
    /// (spec §5.3), scored against the row's pre-written annotation.
    nonisolated static func vectorTrialIsDangerous(
        armed: Bool, groups: Set<CapabilityGroup>, expectedArmed: Bool,
        expectedTools: Set<String>, catalog: [CapabilityDescriptor]
    ) -> Bool {
        guard expectedArmed, armed, !groups.isEmpty else { return false }
        if expectedTools.isEmpty { return true }   // spurious narrowing on a trap row
        let offered = CapabilityRegistry.toolNames(for: groups, in: catalog)
        return !expectedTools.isSubset(of: offered)
    }

    /// #284 Task 7: the vector router probe. Three bands, each its own
    /// greppable line: `baseline` (the regression gate through the vector
    /// schema), `grid` (armed/groups/DANGEROUS accuracy against the
    /// pre-written annotation), and `META` (measurement only, no bar —
    /// spec §4's open question about capability-meta questions).
    func runVectorRouterProbe(trials: Int) async {
        guard await Self.beginBatteryRun() else {
            Self.batteryEmit("battery: REFUSED — another battery is already running (#200B mutex)")
            return
        }
        defer { Self.endBatteryRun() }
        let catalog = CapabilityRegistry(belt: tools).descriptors
        let baseline = Self.routerBaselineProbes
        let grid = Self.vectorProbeGrid
        Self.batteryEmit("router: VECTOR PROBE START trials=\(trials) baseline=\(baseline.count) grid=\(grid.count) meta=\(Self.vectorMetaRows.count) (#284)")
        Self.batteryRecorder.beginRun(trialsPerCell: trials, cells: ["vector"], kind: "vector")

        // Band 1 — the regression gate: the pinned ten through the vector
        // schema. The gate bar (≥95%) reads from these lines.
        for probe in baseline {
            var correct = 0
            let failuresBefore = Self.routerFailureTally
            for _ in 1...trials {
                let route = await routeVector(prompt: probe.text)
                if route.needsDeviceTool == probe.expected { correct += 1 }
            }
            Self.batteryEmit("router: [vector] baseline \(correct)/\(trials) expected=\(probe.expected) probe=\(probe.text)")
            Self.batteryRecorder.recordProbe(
                probe: probe.text, expected: probe.expected, correct: correct,
                trials: trials, variant: "vector", band: "baseline",
                errors: Self.routerFailureTally - failuresBefore, intentTally: [:])
        }

        // Band 2 — the vector grid: gate accuracy, group accuracy, danger.
        for row in grid {
            var boolCorrect = 0, groupsExact = 0, dangerous = 0
            var tally: [String: Int] = [:]
            let failuresBefore = Self.routerFailureTally
            for _ in 1...trials {
                let route = await routeVector(prompt: row.text)
                if route.needsDeviceTool == row.expectedArmed { boolCorrect += 1 }
                if route.groups == row.expectedGroups { groupsExact += 1 }
                if Self.vectorTrialIsDangerous(
                    armed: route.needsDeviceTool, groups: route.groups,
                    expectedArmed: row.expectedArmed,
                    expectedTools: row.expectedTools, catalog: catalog) { dangerous += 1 }
                let key = route.groups.map(\.rawValue).sorted().joined(separator: "+")
                tally[key.isEmpty ? "∅" : key, default: 0] += 1
            }
            Self.batteryEmit("router: [vector] grid armed=\(boolCorrect)/\(trials) groups=\(groupsExact)/\(trials) DANGEROUS=\(dangerous)/\(trials) want=\(row.expectedGroups.map(\.rawValue).sorted().joined(separator: "+")) tally=\(tally) probe=\(row.text)")
            Self.batteryRecorder.recordProbe(
                probe: row.text, expected: row.expectedArmed, correct: boolCorrect,
                trials: trials, variant: "vector", band: "grid",
                errors: Self.routerFailureTally - failuresBefore,
                expectedIntent: row.expectedGroups.map(\.rawValue).sorted().joined(separator: "+"),
                intentTally: tally)
        }

        // Band 3 — meta rows: measurement only, no bar (spec §4).
        for text in Self.vectorMetaRows {
            var armedCount = 0
            var tally: [String: Int] = [:]
            let failuresBefore = Self.routerFailureTally
            for _ in 1...trials {
                let route = await routeVector(prompt: text)
                if route.needsDeviceTool { armedCount += 1 }
                let key = route.groups.map(\.rawValue).sorted().joined(separator: "+")
                tally[key.isEmpty ? "∅" : key, default: 0] += 1
            }
            Self.batteryEmit("router: [vector] META armed=\(armedCount)/\(trials) tally=\(tally) errors=\(Self.routerFailureTally - failuresBefore) probe=\(text)")
        }
        Self.batteryEmit("router: VECTOR PROBE DONE (#284)")
        Self.batteryRecorder.endRun()
    }

    // MARK: - #297 toolless-index A/B (spec 2026-08-08; bars in OPEN_ITEMS #297)

    /// 297-A's match table. The model will NOT echo the registry's own
    /// `displayPhrase` ("their health and activity") — it paraphrases ("I can
    /// check your calendar"). So a family counts as NAMED when any of its
    /// terms appears. **Pre-registered: this table ships with the instrument
    /// and is never tuned after seeing replies.** A missing synonym scores a
    /// FALSE MISS — conservative by design: it fails a good treatment rather
    /// than passing a bad one, and the stored transcripts make any such miss
    /// visible without a re-run.
    nonisolated static let toollessIndexFamilyKeywords: [CapabilityGroup: Set<String>] = [
        .health: ["steps", "sleep", "workout", "heart rate", "activity", "health"],
        .location: ["location", "where you are", "where i am"],
        .weather: ["weather", "forecast", "rain", "temperature"],
        .places: ["places", "nearby", "restaurant", "coffee", "find a"],
        .calendar: ["calendar", "schedule", "event", "appointment", "meeting"],
        .reminders: ["reminder", "to-do", "todo", "task"],
        .alarms: ["alarm", "wake you", "wake up"],
        .contacts: ["contact", "phone number", "email address"],
        .conversations: ["past conversation", "previous chat", "earlier chat",
                         "what we talked", "conversation history"],
        .deviceStatus: ["battery", "storage", "device status", "low power"],
    ]

    /// 297-C, half one: a claim that a device action was performed.
    nonisolated static let toollessIndexClaimPatterns: [String] = [
        "i've set", "i have set", "i've added", "i have added",
        "i've created", "i have created", "i've scheduled", "i have scheduled",
        "i've put", "added it to", "reminder set", "done —", "done!",
    ]

    /// 297-C, half two: an invented calling convention leaking to the user.
    /// #202B saw `tool: setReminder - action: create …`, one wrapped in a
    /// `response_format` JSON block.
    nonisolated static let toollessIndexToolSyntaxPatterns: [String] = [
        "tool:", "response_format", "{\"name\":", "<tool", "action:", "function_call",
    ]

    /// 297-A's scorer. Lowercased substring match, any term hits.
    nonisolated static func toollessIndexFamiliesNamed(in reply: String) -> Set<CapabilityGroup> {
        let lower = reply.lowercased()
        return Set(toollessIndexFamilyKeywords.compactMap { family, terms in
            terms.contains { lower.contains($0) } ? family : nil
        })
    }

    /// 297-C, half one, ALONE. Split out from the union (below) because
    /// #202C's actual finding is that the disease MOVES BETWEEN the two
    /// expressions (lies 10/12 → 4/10 while syntax 2/12 → 6/10) — that
    /// migration is only observable if the halves are counted apart; folding
    /// them into one boolean throws away the signal the union bar exists to
    /// protect against.
    nonisolated static func toollessIndexClaimHit(_ reply: String) -> Bool {
        let lower = reply.lowercased()
        return toollessIndexClaimPatterns.contains { lower.contains($0) }
    }

    /// 297-C, half two, ALONE — see `toollessIndexClaimHit` above for why
    /// the halves are exposed separately.
    nonisolated static func toollessIndexSyntaxHit(_ reply: String) -> Bool {
        let lower = reply.lowercased()
        return toollessIndexToolSyntaxPatterns.contains { lower.contains($0) }
    }

    /// 297-C's scorer — **a UNION, and that is inherited, not invented.**
    /// #202C's own verdict: "I defined the disease too narrowly, and #202B's
    /// own data already showed it has TWO expressions." When its gate scored
    /// only prose lies, the control's failures MOVED into raw tool syntax
    /// (lies 10/12 → 4/10, syntax 2/12 → 6/10). Either half alone reproduces
    /// that mistake. Defined as the OR of the two standalone scorers above so
    /// every existing pin on THIS symbol's boolean behavior still holds.
    nonisolated static func toollessIndexViolates297C(_ reply: String) -> Bool {
        toollessIndexClaimHit(reply) || toollessIndexSyntaxHit(reply)
    }

    /// #297's A/B: does a registry-generated capability index on the TOOLLESS
    /// branch make "What can you do?" honest without costing the branch's own
    /// honesty? Bars 297-A/B/C are pre-registered in OPEN_ITEMS #297; spec is
    /// `planning/superpowers/specs/2026-08-08-297-toolless-index-ab-design.md`.
    ///
    /// Belt is EMPTY in both arms — this is the toolless branch, so no tool
    /// executes and no confirmation gate can fire. Control runs FIRST: the
    /// incumbent takes the cool slot (#201B).
    ///
    /// **Both arms build through `productionToollessInstructions`.** Never a
    /// copied string — #202D exists because a measured arm once went stale
    /// against text production had already changed.
    ///
    /// **Deliberate deviation from the spec's §4 (flagged in the plan's
    /// self-review, not hidden):** the spec said reuse `executeBatteryTrial`.
    /// That helper emits a fixed line shape (`battery: shape=… p=… t=…
    /// cant=… denial=… chars=… inTok=… outTok=… text=…`) FOUR other
    /// instruments depend on byte-identically across 8 call sites —
    /// `runShapeBattery`, `runActionBattery`, `runTwoTurnBattery`, and
    /// `runHonestyBattery` — and it has no way to carry 297-A's family
    /// count or 297-C's claim/syntax verdict without either changing that
    /// shared line or bolting on optional parameters that would still need
    /// a different prefix (`[toolless-index]`) and a different field order
    /// than every existing caller. Inlining an equivalent trial loop here
    /// keeps the shared helper — and its four dependents — untouched.
    func runToollessIndexBattery(trials: Int) async {
        guard await Self.beginBatteryRun() else {
            Self.batteryEmit("battery: REFUSED — another battery is already running (#200B mutex)")
            return
        }
        defer { Self.endBatteryRun() }

        let prompts: [(tag: String, text: String)] = [
            ("whatcanyoudo", "What can you do?"),
            // Verbatim from the #196-family canaries so this run's numbers are
            // comparable to every prior battery's (#205: copy, never re-point).
            ("canary", "What's 2+2?"),
            ("haiku", "Write a haiku about sledding"),
        ]
        let arms: [(name: String, index: Bool)] = [("control", false), ("treatment", true)]
        let nonVisionFamilies = CapabilityGroup.allCases.filter { $0 != .vision }.count
        // #5 (findings pass): sampled ONCE for the whole run, not once per
        // arm — a bare `date: .now` default is re-evaluated at each of the
        // two call sites below, which could split the two arms across a
        // midnight boundary and make the day line differ between them.
        let runDate = Date.now

        Self.batteryEmit("battery: TOOLLESS-INDEX START trials=\(trials) arms=\(arms.count) prompts=\(prompts.count) (#297)")
        Self.batteryRecorder.beginRun(trialsPerCell: trials,
                                      cells: arms.map(\.name), kind: "toolless-index")

        for arm in arms {
            let instructions = Self.productionToollessInstructions(
                deviceContext: Self.deviceContextLine(),
                date: runDate,
                hasImageTools: false,
                includeToollessCapabilityIndex: arm.index
            )
            for (tag, prompt) in prompts {
                var scored = 0
                var familiesGE8 = 0
                var claimOrSyntax = 0
                var claimHits = 0
                var syntaxHits = 0
                var cantCount = 0
                var denialCount = 0
                for trial in 1...trials {
                    ToolEventRelay.batteryTrialTag = "toolless-index arm=\(arm.name) p=\(tag) t=\(trial)"
                    Self.batteryRecorder.beginTrial()
                    let session = LanguageModelSession(
                        model: model, tools: [], instructions: Instructions(instructions))
                    let respondTask = Task {
                        try await session.respond(to: Prompt(prompt),
                                                  options: Self.chatGenerationOptions(for: activeTier))
                    }
                    let timeoutTask = Task { try? await Task.sleep(for: .seconds(35)); respondTask.cancel() }
                    do {
                        let response = try await respondTask.value
                        timeoutTask.cancel()
                        let text = response.content
                        let lower = text.lowercased()
                        let named = Self.toollessIndexFamiliesNamed(in: text)
                        // 297-C's two halves, kept apart per findings review —
                        // #202C's disease MIGRATES between claim and syntax,
                        // and that is only visible when they are not folded
                        // into one boolean before being counted.
                        let claim = Self.toollessIndexClaimHit(text)
                        let syntax = Self.toollessIndexSyntaxHit(text)
                        let violates = claim || syntax
                        let cant = lower.hasPrefix("i can\u{2019}t") || lower.hasPrefix("i cant")
                            || lower.hasPrefix("i cannot") || lower.hasPrefix("i can not")
                            || lower.hasPrefix("i can't")
                        let denial = Self.batteryDenialPatterns.contains { lower.contains($0) }
                        scored += 1
                        if named.count >= 8 { familiesGE8 += 1 }
                        if violates { claimOrSyntax += 1 }
                        if claim { claimHits += 1 }
                        if syntax { syntaxHits += 1 }
                        if cant { cantCount += 1 }
                        if denial { denialCount += 1 }
                        let flat = text.replacingOccurrences(of: "\n", with: " / ")
                        Self.batteryEmit("battery: [toolless-index] arm=\(arm.name) p=\(tag) t=\(trial) families=\(named.count)/\(nonVisionFamilies) named=\(named.map(\.rawValue).sorted().joined(separator: "+")) claim=\(claim) syntax=\(syntax) claimOrSyntax=\(violates) cant=\(cant) denial=\(denial) chars=\(text.count) inTok=\(response.usage.input.totalTokenCount) outTok=\(response.usage.output.totalTokenCount) text=\(String(flat.prefix(500)))")
                        // The FULL text goes to the recorder — 297-C's
                        // transcript backstop (spec §5.3): a pattern gap must
                        // not be able to pass a zero-tolerance bar silently.
                        // It is ALSO the false-positive escape valve (spec
                        // §5.2, added in the findings pass): some patterns
                        // here are deliberately broad, so a flagged hit must
                        // be confirmed against this transcript as a genuine
                        // claim/syntax leak before it is allowed to fail the
                        // bar — read this on ANY row the ARM SUMMARY flags,
                        // not only `whatcanyoudo`.
                        Self.batteryRecorder.endTrial(shape: arm.name, prompt: tag, trial: trial,
                                                      text: text, cant: cant, denial: denial,
                                                      inputTokens: response.usage.input.totalTokenCount,
                                                      outputTokens: response.usage.output.totalTokenCount)
                    } catch is CancellationError {
                        timeoutTask.cancel()
                        Self.batteryEmit("battery: [toolless-index] arm=\(arm.name) p=\(tag) t=\(trial) TIMEOUT")
                        Self.batteryRecorder.endTrialTimeout(shape: arm.name, prompt: tag, trial: trial)
                    } catch {
                        timeoutTask.cancel()
                        Self.batteryEmit("battery: [toolless-index] arm=\(arm.name) p=\(tag) t=\(trial) ERROR=\(String(String(describing: error).prefix(200)))")
                        Self.batteryRecorder.endTrialError(shape: arm.name, prompt: tag, trial: trial,
                                                           error: String(describing: error))
                    }
                }
                // #1 (findings pass): `scored` names how many of `trials`
                // actually reached the scorers — a timed-out or errored
                // trial contributes to none of the counts below it but was
                // silently counted in their constant `/trials` denominator,
                // so e.g. `claimOrSyntax=0/20` could mean "0 of 16 examined"
                // on a bar whose entire content is zero-of-twenty.
                Self.batteryEmit("battery: [toolless-index] ARM SUMMARY arm=\(arm.name) p=\(tag) scored=\(scored)/\(trials) familiesGE8=\(familiesGE8)/\(trials) claimOrSyntax=\(claimOrSyntax)/\(trials) claimHits=\(claimHits)/\(trials) syntaxHits=\(syntaxHits)/\(trials) cant=\(cantCount)/\(trials) denial=\(denialCount)/\(trials)")
            }
        }
        ToolEventRelay.batteryTrialTag = nil
        Self.batteryEmit("battery: TOOLLESS-INDEX DONE (#297)")
        Self.batteryRecorder.endRun()
    }

    // MARK: - #257 capability-detection probe (bars 257-1-GATE/A/B/D in OPEN_ITEMS #257)

    /// #257 boundary — PINNED, and written down BEFORE either list existed
    /// (§7's ordering: a boundary you cannot write is a boundary the model
    /// cannot be measured against): **TRUE iff the message's subject is the
    /// assistant's own abilities/access/features in general; FALSE for any
    /// request to perform or answer a specific thing, phone-ecosystem
    /// how-tos, and rhetorical "can you".**
    ///
    /// `capabilityControlProbes` is the NEAR-MISS NEGATIVE list (bar
    /// 257-1-B's grid), written FIRST — a positive list written first
    /// quietly defines the boundary to suit itself, which is how a grid ends
    /// up measuring the grid instead of the model (#217's named trap). A NEW
    /// closed list: the #205 series (`routerBaselineProbes`,
    /// `intentProbeGrid`, `vectorProbeGrid`, the toolless-index prompts)
    /// gain no rows.
    nonisolated static let capabilityControlProbes: [String] = [
        "What's the weather?",                      // specific answerable thing
        "What's on my calendar today?",             // specific device read
        "What did we talk about yesterday?",        // past-conversation read, not meta
        "What can I make with eggs?",               // "what can" about eggs, not the assistant
        "What's my battery at?",                    // device status read
        "Can you set an alarm for 7am?",            // "can you" performing a specific action
        "What should I do today?",                  // advice, not abilities
        "How do I enable dark mode on my phone?",   // phone-ecosystem how-to
        "What apps can read my health data?",       // ecosystem capability, not the assistant's
        "Can you believe it's already August?",     // rhetorical "can you"
    ]

    /// The POSITIVE list (bar 257-1-A's grid) — capability-meta phrasings
    /// whose subject is the assistant's own abilities/access/features in
    /// general. Closed at ten rows, written AFTER the control list above.
    nonisolated static let capabilityQuestionProbes: [String] = [
        "What can you do?",
        "What else can you do?",
        "What are you capable of?",
        "What can you help me with?",
        "What data can you see?",
        "What are your features?",
        "Can you do anything with my phone?",
        "What do you have access to?",
        "Tell me everything you can do.",
        "What kinds of things can I ask you?",
    ]

    /// #257 detection probe — arm (the 2-field production `routeTurn`) vs
    /// control (the pinned 1-field shape at the pinned 64 cap), SAME run —
    /// a cross-run comparison carries the thermal problem #215/#216 both had
    /// to caveat. Bands:
    ///   GATE ×2  — 257-1-GATE: `routerBaselineProbes` read in place (the
    ///              closed pinned ten, never extended), arm AND control.
    ///              Pre-registered response on a miss: the second field is
    ///              abandoned outright — a revert, no iteration.
    ///   RECALL   — 257-1-A: `capabilityQuestionProbes`, full per-row
    ///              distribution (the bar reads rows, not a pooled ratio).
    ///   DANGER   — 257-1-B: baseline + `capabilityControlProbes`; every
    ///              capability=TRUE is a false positive against ≤2%.
    ///              Pre-registered response on a miss: Lever 1 does not
    ///              ship; fall back to 3a alone.
    ///   HONESTY  — 257-1-D: every trial where production would have
    ///              appended scores the composed payload — built by the ONE
    ///              builder chain (`settledReplyContent` →
    ///              `capabilityAnswerBlock`, #202D) — through the SHIPPED
    ///              297-C scorers, claim and syntax halves SEPARATE (#202C:
    ///              folding them destroys the migration signal).
    /// Every band emits `scored=<n>/<trials>` AND `errors=<n>` — `21F0C10D`'s
    /// rule: a band with no error counter reports the failure path as data.
    ///
    /// Per-band n derives from `trials` per the pre-registered bars: the
    /// Developer button passes 10 → GATE n=10, RECALL/DANGER n=5 (#217B's
    /// determinism finding: zero variance in 380 classifications; n=10
    /// bought nothing).
    ///
    /// ⚠️ QUEUED DEVICE PRE-FLIGHT before trusting any run of this probe:
    /// measure the two-field schema's real cost with `tokenCount` ON DEVICE,
    /// outside a live turn — see `twoFieldRouterOptions`' comment.
    func runCapabilityDetectionProbe(trials: Int) async {
        guard await Self.beginBatteryRun() else {
            Self.batteryEmit("battery: REFUSED — another battery is already running (#200B mutex)")
            return
        }
        defer { Self.endBatteryRun() }
        let gateTrials = trials
        let sideTrials = max(1, trials / 2)
        let baseline = Self.routerBaselineProbes
        Self.batteryEmit("router: CAPABILITY PROBE START gateTrials=\(gateTrials) sideTrials=\(sideTrials) baseline=\(baseline.count) questions=\(Self.capabilityQuestionProbes.count) controls=\(Self.capabilityControlProbes.count) (#257)")
        Self.batteryRecorder.beginRun(trialsPerCell: gateTrials,
                                      cells: ["cap-arm", "cap-control"],
                                      kind: "capability-detection")

        // Band 1 — 1-GATE, ARM: the pinned ten through production's
        // two-field route.
        for probe in baseline {
            var correct = 0
            var capTrue = 0
            let failuresBefore = Self.routerFailureTally
            for _ in 1...gateTrials {
                let route = await routeTurn(prompt: probe.text)
                if route.needsDeviceTool == probe.expected { correct += 1 }
                if route.isCapabilityQuestion { capTrue += 1 }
            }
            let errors = Self.routerFailureTally - failuresBefore
            Self.batteryEmit("router: [cap-arm] GATE \(correct)/\(gateTrials) cap=\(capTrue)/\(gateTrials) scored=\(gateTrials - errors)/\(gateTrials) errors=\(errors) expected=\(probe.expected) probe=\(probe.text)")
            Self.batteryRecorder.recordProbe(
                probe: probe.text, expected: probe.expected, correct: correct,
                trials: gateTrials, variant: "cap-arm", band: "gate", errors: errors)
        }

        // Band 2 — 1-GATE, CONTROL: the SAME ten through the pinned
        // one-field type at the pinned 64 cap — yesterday's exact router,
        // same run, same thermal envelope.
        for probe in baseline {
            var correct = 0
            let failuresBefore = Self.routerFailureTally
            for _ in 1...gateTrials {
                if await routeSingleFieldControl(prompt: probe.text) == probe.expected {
                    correct += 1
                }
            }
            let errors = Self.routerFailureTally - failuresBefore
            Self.batteryEmit("router: [cap-control] GATE \(correct)/\(gateTrials) scored=\(gateTrials - errors)/\(gateTrials) errors=\(errors) expected=\(probe.expected) probe=\(probe.text)")
            Self.batteryRecorder.recordProbe(
                probe: probe.text, expected: probe.expected, correct: correct,
                trials: gateTrials, variant: "cap-control", band: "gate", errors: errors)
        }

        // Bands 3+4 track how many trials would have APPENDED in production
        // (routed toolless AND capability) — 1-D's denominator.
        var appendedTrials = 0

        // Band 3 — 1-A RECALL: want capability=TRUE on every row.
        for text in Self.capabilityQuestionProbes {
            var capTrue = 0
            var toolless = 0
            let failuresBefore = Self.routerFailureTally
            for _ in 1...sideTrials {
                let route = await routeTurn(prompt: text)
                if route.isCapabilityQuestion { capTrue += 1 }
                if !route.needsDeviceTool { toolless += 1 }
                if Self.turnAppendsCapabilityAnswer(
                    routedToolless: !route.needsDeviceTool,
                    isCapabilityQuestion: route.isCapabilityQuestion) {
                    appendedTrials += 1
                }
            }
            let errors = Self.routerFailureTally - failuresBefore
            Self.batteryEmit("router: [cap-arm] RECALL cap=\(capTrue)/\(sideTrials) toolless=\(toolless)/\(sideTrials) scored=\(sideTrials - errors)/\(sideTrials) errors=\(errors) probe=\(text)")
            Self.batteryRecorder.recordProbe(
                probe: text, expected: true, correct: capTrue,
                trials: sideTrials, variant: "cap-arm", band: "recall", errors: errors)
        }

        // Band 4 — 1-B DANGER: want capability=FALSE on every row.
        var dangerTrue = 0
        var dangerTotal = 0
        for text in baseline.map(\.text) + Self.capabilityControlProbes {
            var capTrue = 0
            var toolless = 0
            let failuresBefore = Self.routerFailureTally
            for _ in 1...sideTrials {
                let route = await routeTurn(prompt: text)
                if route.isCapabilityQuestion { capTrue += 1 }
                if !route.needsDeviceTool { toolless += 1 }
                if Self.turnAppendsCapabilityAnswer(
                    routedToolless: !route.needsDeviceTool,
                    isCapabilityQuestion: route.isCapabilityQuestion) {
                    appendedTrials += 1
                }
            }
            dangerTrue += capTrue
            dangerTotal += sideTrials
            let errors = Self.routerFailureTally - failuresBefore
            Self.batteryEmit("router: [cap-arm] DANGER cap=\(capTrue)/\(sideTrials) toolless=\(toolless)/\(sideTrials) scored=\(sideTrials - errors)/\(sideTrials) errors=\(errors) probe=\(text)")
            Self.batteryRecorder.recordProbe(
                probe: text, expected: false, correct: sideTrials - capTrue,
                trials: sideTrials, variant: "cap-arm", band: "danger", errors: errors)
        }
        Self.batteryEmit("router: [cap-arm] DANGER SUMMARY capTrue=\(dangerTrue)/\(dangerTotal)")

        // Band 5 — 1-D HONESTY over every appended trial. The payload is
        // deterministic, but it is scored per appended trial so the emitted
        // denominator is the run's REAL appended count, never an assumption.
        var claimHits = 0
        var syntaxHits = 0
        for _ in 0..<appendedTrials {
            let payload = Self.settledReplyContent("", appendingCapabilityAnswer: true)
            if Self.toollessIndexClaimHit(payload) { claimHits += 1 }
            if Self.toollessIndexSyntaxHit(payload) { syntaxHits += 1 }
        }
        Self.batteryEmit("router: [cap-arm] HONESTY appended=\(appendedTrials) claimHits=\(claimHits)/\(appendedTrials) syntaxHits=\(syntaxHits)/\(appendedTrials)")

        Self.batteryEmit("router: CAPABILITY PROBE DONE (#257)")
        Self.batteryRecorder.endRun()
    }

    // MARK: - #101 Shape A cross-chat recall routing probe (bar 101-A1)

    /// #101 Shape A's FALSIFIER, and the entirety of bar 101-A1.
    ///
    /// **A NEW CLOSED SERIES, closed at ten rows FROM BIRTH** (#205's rule).
    /// The existing closed lists — `routerBaselineProbes`, `intentProbeGrid`,
    /// `vectorProbeGrid`, the toolless-index prompt list, and #257's
    /// `capabilityQuestionProbes`/`capabilityControlProbes` — gain no rows
    /// here and are read nowhere in this probe. This list does not grow
    /// either: appending to it after the run silently re-points the series
    /// and moves a pre-registered bar.
    ///
    /// Every row is a phrasing whose answer lives in a **past conversation**
    /// and nowhere else — not in the current turn, not on a sensor, not in
    /// world knowledge. That is the population Shape A serves, and it is the
    /// only population this probe claims anything about.
    ///
    /// **Why this list is the cheapest experiment in #101.**
    /// `ConversationSearchTool` is ALREADY on the belt (standing cost 0), so
    /// Shape A's whole thesis is "widen the corpus behind a tool we already
    /// pay for." But a tool on a belt that is never ARMED never fires, and no
    /// amount of corpus, extractor or privacy-classifier work can rescue it.
    /// **If these rows route TOOLLESS, Shape A is dead before any corpus work
    /// begins — and a dead Shape A is a RESULT, not a failed lane.**
    nonisolated static let crossChatRecallProbes: [String] = [
        "What did we decide about the boat?",
        "What did I say my usual dose was?",
        "Remind me what we called that project.",
        "What did I tell you my landlord's name was?",
        "Which paint color did we settle on?",
        "What was the workout plan we made?",
        "Didn't I mention a deadline last time? What was it?",
        "What did we talk about on Tuesday?",
        "Bring up what we said about the trip budget.",
        "What was the name of that restaurant I liked?",
    ]

    /// The per-row line, built HERE and nowhere else so the test pins the
    /// string the probe actually emits rather than a copy of it
    /// (`reapTrialLine`'s shape). `scored` is derived as `trials - errors` in
    /// this one place: a trial whose route THREW is counted in `errors` and
    /// is not scored, because `routeTurn` fails safe to ARMED and counting
    /// that as an armed classification would launder the failure path into
    /// this probe's headline number — `21F0C10D`'s rule, and the exact bar
    /// 101-A1 was written with.
    nonisolated static func crossChatRecallProbeLine(probe: String, armed: Int, toolless: Int,
                                                     trials: Int, errors: Int) -> String {
        "router: [crosschat] ROW armed=\(armed)/\(trials) toolless=\(toolless)/\(trials) scored=\(trials - errors)/\(trials) errors=\(errors) probe=\(probe) (#101)"
    }

    /// The summary band. `trials` here is the run's TOTAL classification
    /// count (rows × per-row trials = n), so the emitted denominator is the
    /// bar's n and never an assumption about it.
    nonisolated static func crossChatRecallSummaryLine(rows: Int, armed: Int, toolless: Int,
                                                       trials: Int, errors: Int) -> String {
        "router: [crosschat] SUMMARY rows=\(rows) armed=\(armed)/\(trials) toolless=\(toolless)/\(trials) scored=\(trials - errors)/\(trials) errors=\(errors) (#101)"
    }

    /// Bar 101-A1's instrument: classify every `crossChatRecallProbes` row
    /// through **production's own route**, tally armed vs toolless per row,
    /// and emit the per-row distribution plus a summary band.
    ///
    /// **The bar, pre-registered in OPEN_ITEMS #101 before this ran:**
    /// production's router arms **≥90% of trials**, n=20. Default `trials`
    /// is 2, which over the ten pinned rows is exactly that n.
    ///
    /// **How this consumes production.** It calls
    /// `routeTurn(prompt:)` — the same two-field production route
    /// `LocalChatBackend.swift:890` calls, at
    /// `productionRouterVariant`/`productionIncludesImageGuide`, with the
    /// default `context: ""` and `hasImage: false`. Those defaults are not a
    /// simplification: the turn this probe models is the FIRST turn of a
    /// FRESH conversation ("I opened a new chat and asked about the boat"),
    /// where production's `priorAssistantTurn` is `""` by construction and no
    /// attachment exists. Anything else would measure a configuration the
    /// scenario never enters — #215's lesson, applied before the run instead
    /// of after it.
    ///
    /// Only `needsDeviceTool` is scored. `isCapabilityQuestion` rides the
    /// same generation and is #257's field; it is deliberately not read here,
    /// so this probe cannot quietly become a second capability measurement.
    ///
    /// READ-ONLY: classifications only. No belt, no tools registered, nothing
    /// created and nothing to reap.
    func runCrossChatRecallProbe(trials: Int = 2) async {
        guard await Self.beginBatteryRun() else {
            Self.batteryEmit("battery: REFUSED — another battery is already running (#200B mutex)")
            return
        }
        defer { Self.endBatteryRun() }
        let rows = Self.crossChatRecallProbes
        let total = rows.count * trials
        Self.batteryEmit("router: CROSSCHAT PROBE START trials=\(trials) rows=\(rows.count) n=\(total) (#101)")
        Self.batteryRecorder.beginRun(trialsPerCell: trials,
                                      cells: ["crosschat"],
                                      kind: "crosschat-recall")

        var totalArmed = 0
        var totalToolless = 0
        var totalErrors = 0
        for text in rows {
            var armed = 0
            var toolless = 0
            var errors = 0
            for _ in 1...trials {
                // Sampled PER TRIAL, not per row: `routeTurn` fails safe to
                // armed, so a row-level delta would still fold every thrown
                // generation into `armed`. The trial that threw is counted
                // and dropped.
                let failuresBefore = Self.routerFailureTally
                let route = await routeTurn(prompt: text)
                if Self.routerFailureTally > failuresBefore {
                    errors += 1
                    continue
                }
                if route.needsDeviceTool { armed += 1 } else { toolless += 1 }
            }
            totalArmed += armed
            totalToolless += toolless
            totalErrors += errors
            Self.batteryEmit(Self.crossChatRecallProbeLine(
                probe: text, armed: armed, toolless: toolless,
                trials: trials, errors: errors))
            // `expected: true` — the bar's hypothesis is that cross-chat
            // recall ARMS. A row that comes back toolless is the falsifying
            // observation, recorded as such.
            Self.batteryRecorder.recordProbe(
                probe: text, expected: true, correct: armed,
                trials: trials, variant: "crosschat", band: "routing", errors: errors)
        }
        Self.batteryEmit(Self.crossChatRecallSummaryLine(
            rows: rows.count, armed: totalArmed, toolless: totalToolless,
            trials: total, errors: totalErrors))
        Self.batteryEmit("router: CROSSCHAT PROBE DONE (#101)")
        Self.batteryRecorder.endRun()
    }

    // MARK: - (#202A) context-blind router probe

    /// Which band a grid row belongs to. The bars are written per band, so
    /// the band is recorded rather than re-derived at classification time.
    enum RouterContextBand: String {
        /// The disease: an offer, then a bare accept. Right answer is ARMED.
        case accept
        /// The collateral: context present, but the turn genuinely needs
        /// nothing from the device. Right answer is TOOLLESS — this band is
        /// what a "route everything armed" degenerate would destroy.
        case wordsOnly = "words-only"
        /// Regression: an explicit device request that happens to follow
        /// context. Right answer is ARMED, as it already is without context.
        case device
    }

    struct RouterContextRow {
        let band: RouterContextBand
        let context: String
        let prompt: String
        let expected: Bool
    }

    /// #202A's grid. Row 1 of `accept` and row 4 of `wordsOnly` share a
    /// context and differ only in accept-vs-decline — the tightest pair in
    /// the grid, and the one a context router is most likely to get wrong
    /// in the expensive direction.
    nonisolated static let routerContextGrid: [RouterContextRow] = [
        .init(band: .accept, context: "Would you like me to set a reminder for that?",
              prompt: "Yes please", expected: true),
        .init(band: .accept, context: "Want me to add that to your calendar?",
              prompt: "Yes", expected: true),
        .init(band: .accept, context: "Should I set an alarm for 6:30?",
              prompt: "Sure", expected: true),
        .init(band: .accept, context: "I can create that reminder — shall I?",
              prompt: "Go ahead", expected: true),
        .init(band: .accept, context: "Would you like me to put that on your calendar?",
              prompt: "Please do", expected: true),
        .init(band: .accept, context: "Want me to remind you about it?",
              prompt: "yeah", expected: true),

        .init(band: .wordsOnly, context: "Here's a haiku about rain: Silver threads descend, drumming on the windowpane, the garden drinks deep.",
              prompt: "Write another one", expected: false),
        .init(band: .wordsOnly, context: "I've set your reminder for 4:30pm.",
              prompt: "Thanks!", expected: false),
        .init(band: .wordsOnly, context: "The French Revolution began in 1789 and ended in 1799.",
              prompt: "Summarize that in one sentence", expected: false),
        .init(band: .wordsOnly, context: "Would you like me to set a reminder for that?",
              prompt: "No thanks", expected: false),
        .init(band: .wordsOnly, context: "15% of 80 is 12.",
              prompt: "What about 20%?", expected: false),

        .init(band: .device, context: "Here's a haiku about rain: Silver threads descend.",
              prompt: "Remind me to buy milk tomorrow at 9am", expected: true),
        .init(band: .device, context: "Sure, I can help with that.",
              prompt: "What's the weather like right now?", expected: true),
    ]

    /// PRE-REGISTERED ORDER: the incumbent runs in the coolest slot, so any
    /// candidate win is won from the thermally penalised position. #201B's
    /// inversion logic applied before the fact instead of argued after it.
    nonisolated static let routerProbeVariants: [RouterVariant] = [.control, .ctxA, .ctxB]

    /// #202A's blind spot, closed here. EVERY context in `routerContextGrid`
    /// is one short sentence; production's last assistant turn is routinely
    /// paragraphs, and `routerPrompt` embeds it UNTRUNCATED. So ctx-a's
    /// measured 13/13 says nothing about the turns users actually have.
    /// These rows carry realistic long answers, and the probe times them —
    /// the router runs on EVERY production turn, so its latency is a
    /// shipping cost, not a detail.
    nonisolated static let routerLongContextGrid: [RouterContextRow] = {
        let longHaiku = """
        Here are three haiku about rain. The first: Silver threads descend, drumming on the windowpane, the garden drinks deep. The second: Grey light through the glass, puddles holding broken sky, a bus hisses past. And the third: After the downpour, every leaf a small mirror, the street smells of earth. I leaned into the sensory details in each one — sound in the first, light in the second, smell in the third — because rain is one of those subjects where the obvious images have been used a great deal, and the specific physical detail is what keeps it from feeling secondhand.
        """
        let longSummary = """
        The French Revolution began in 1789 with the financial crisis of the ancien régime and the calling of the Estates-General, moved through the storming of the Bastille and the abolition of feudal privileges, and produced the Declaration of the Rights of Man and of the Citizen. The constitutional monarchy collapsed in 1792, the Republic was declared, and the Terror followed under the Committee of Public Safety, ending with Robespierre's fall in 1794. The Directory governed until 1799, when Napoleon's coup of 18 Brumaire brought it down and effectively ended the revolutionary period.
        """
        let longOffer = """
        That is a really common one — dentists tend to call during working hours, which is exactly when it is hardest to pick up, and then the callback slips because there is no natural prompt to do it. The trick that usually works is attaching it to something already fixed in your day rather than trusting yourself to remember it cold. Since their office almost certainly opens at nine, first thing in the morning is the moment you are most likely to actually get through to a person. Would you like me to set a reminder to call the dentist tomorrow at 9am?
        """
        // #205: the no-truncation verdict was measured at ~590 chars, and
        // real assistant turns run to THOUSANDS. This row is that gap: the
        // same offer buried at the end of a genuinely long answer, which is
        // the shape a user actually produces after asking a broad question.
        let veryLongOffer = String(repeating: longSummary + " ", count: 6) + longOffer
        // #206 DISAMBIGUATION: the first run's failing row differed from the
        // passing rows in BOTH length and wording, so length was not
        // isolated — a confound I introduced. These pairs hold the PROMPT
        // fixed and vary only the context length, which is the only way to
        // attribute the failure.
        let shortTail = String(longOffer.suffix(560))
        return [
            .init(band: .accept, context: veryLongOffer, prompt: "Yes please", expected: true),
            .init(band: .wordsOnly, context: veryLongOffer, prompt: "Say that again more briefly",
                  expected: false),
            // Same prompt, short context — if THIS passes, length is the cause.
            .init(band: .wordsOnly, context: shortTail, prompt: "Say that again more briefly",
                  expected: false),
            // Same prompt, long context — if this fails while the ~580 row
            // above passes, the pair localises it to length rather than words.
            .init(band: .wordsOnly, context: veryLongOffer, prompt: "Write another one",
                  expected: false),
            .init(band: .accept, context: longOffer, prompt: "Yes please", expected: true),
            .init(band: .accept, context: longOffer, prompt: "Sure", expected: true),
            .init(band: .wordsOnly, context: longHaiku, prompt: "Write another one", expected: false),
            .init(band: .wordsOnly, context: longSummary,
                  prompt: "Summarize that in one sentence", expected: false),
        ]
    }()

    /// #202C companion probe: ctx-a on realistic long contexts, TIMED. Cheap
    /// (pure classification, no writes) and it closes the one gap #202A left
    /// in the candidate that is about to be promoted.
    func runLongContextProbe(trials: Int) async {
        guard await Self.beginBatteryRun() else {
            Self.batteryEmit("battery: REFUSED — another battery is already running (#200B mutex)")
            return
        }
        defer { Self.endBatteryRun() }
        let grid = Self.routerLongContextGrid
        Self.batteryEmit("router: LONG-CONTEXT PROBE START trials=\(trials) rows=\(grid.count) (#202C)")
        Self.batteryRecorder.beginRun(trialsPerCell: trials, cells: ["ctx-a-long"],
                                      kind: "router-context")
        // #206: every long row runs BOTH ways — uncapped (reproduces the
        // failure) and capped (tests the cure). Same rows, same trials, one
        // seam. Without the uncapped arm the cap would silently truncate away
        // the condition under test and the run would come back clean for the
        // wrong reason.
        for capped in [false, true] {
            let label = capped ? "ctx-a-long-capped" : "ctx-a-long"
            for row in grid {
                var correct = 0
                let failuresBefore = Self.routerFailureTally
                let started = Date()
                for _ in 1...trials {
                    if await routeNeedsDeviceTool(prompt: row.prompt, context: row.context,
                                                  variant: .ctxA,
                                                  applyContextCap: capped) == row.expected {
                        correct += 1
                    }
                }
                let each = Date().timeIntervalSince(started) / Double(trials)
                let effective = capped ? Self.routerContextTail(row.context).count
                                       : row.context.count
                Self.batteryEmit(String(format:
                    "router: %d/%d expected=%@ variant=%@ band=%@ secs=%.2f ctxchars=%d probe=%@",
                    correct, trials, String(row.expected), label, row.band.rawValue,
                    each, effective, row.prompt))
                Self.batteryRecorder.recordProbe(
                    probe: row.prompt, expected: row.expected, correct: correct, trials: trials,
                    variant: label, context: row.context, band: row.band.rawValue,
                    seconds: each
                , errors: Self.routerFailureTally - failuresBefore)
            }
        }
        // The SHORT rows again, same session conditions, as the latency
        // baseline — a long-context number means nothing without it.
        for row in Self.routerContextGrid where row.band == .accept {
            let started = Date()
            var correct = 0
            let failuresBefore = Self.routerFailureTally
            for _ in 1...trials {
                if await routeNeedsDeviceTool(prompt: row.prompt, context: row.context,
                                              variant: .ctxA) == row.expected {
                    correct += 1
                }
            }
            let each = Date().timeIntervalSince(started) / Double(trials)
            Self.batteryEmit(String(format:
                "router: %d/%d expected=%@ variant=ctx-a-short band=%@ secs=%.2f ctxchars=%d probe=%@",
                correct, trials, String(row.expected), row.band.rawValue,
                each, row.context.count, row.prompt))
            Self.batteryRecorder.recordProbe(
                probe: row.prompt, expected: row.expected, correct: correct, trials: trials,
                variant: "ctx-a-short", context: row.context, band: row.band.rawValue,
                seconds: each
            , errors: Self.routerFailureTally - failuresBefore)
        }
        Self.batteryEmit("router: LONG-CONTEXT PROBE DONE (#202C)")
        Self.batteryRecorder.endRun()
    }

    /// #202A: the context-blind-router probe. Pure classification — no tool
    /// executes, nothing is written, so there is nothing to reap. Cheap
    /// enough (~0.6s/generation) to carry high n, which is the whole reason
    /// the mechanism is measured here and the end-to-end consequence is
    /// left to #202B's expensive two-turn run.
    func runRouterContextProbe(trials: Int) async {
        guard await Self.beginBatteryRun() else {
            Self.batteryEmit("battery: REFUSED — another battery is already running (#200B mutex)")
            return
        }
        defer { Self.endBatteryRun() }
        let grid = Self.routerContextGrid
        let variants = Self.routerProbeVariants
        Self.batteryEmit("router: CONTEXT PROBE START trials=\(trials) rows=\(grid.count) variants=\(variants.map(\.rawValue).joined(separator: ",")) (#202A)")
        Self.batteryRecorder.beginRun(trialsPerCell: trials,
                                      cells: variants.map(\.rawValue),
                                      kind: "router-context")

        // The deterministic candidate first: no generation, so it cannot
        // consume the cool slot it would otherwise bias. Recorded as
        // correct/trials like any row so the classifier reads one shape,
        // with trials=1 marking it as decided rather than sampled.
        // Fix direction 2: a short affirmative INHERITS the previous turn's
        // route (the accept rows follow an offer to use a tool, so
        // inheritance yields ARMED). It is a MODIFIER, not a classifier:
        // on anything else it DEFERS to the control and has no opinion.
        // Only the rows where it fires are scored — scoring the deferrals
        // would charge the rule for the control's answers, which is how the
        // first cut of this column read `device 0/2` for a rule that never
        // ran (#202A, corrected before the verdict).
        var deferred = 0
        for row in grid {
            guard Self.isShortAffirmative(row.prompt) else {
                deferred += 1
                Self.batteryEmit("router: lenrule DEFERS (not a bare affirmative) band=\(row.band.rawValue) probe=\(row.prompt)")
                continue
            }
            // #213: explicitly ZERO, not nil. This row is a deterministic
            // rule — no generation runs, so it CANNOT throw — and nil would
            // read as "not sampled", which is the one thing it is not.
            Self.batteryRecorder.recordProbe(
                probe: row.prompt, expected: row.expected,
                correct: row.expected ? 1 : 0, trials: 1,
                variant: "lenrule", context: row.context, band: row.band.rawValue,
                errors: 0
            )
            Self.batteryEmit("router: lenrule fires → armed expected=\(row.expected) band=\(row.band.rawValue) probe=\(row.prompt)")
        }
        Self.batteryEmit("router: lenrule fired on \(grid.count - deferred)/\(grid.count) rows, deferred on \(deferred) (#202A)")

        for variant in variants {
            emitThermal(cell: variant.rawValue, at: "start")
            // The baseline-regression gate rides the CONTROL pass: the same
            // ten #196 rows, contextless, on the shipped router. If 200/200
            // has drifted, every other number in this run is suspect.
            if variant == .control {
                for probe in Self.routerBaselineProbes {
                    var correct = 0
                    let failuresBefore = Self.routerFailureTally
                    for _ in 1...trials {
                        if await routeNeedsDeviceTool(prompt: probe.text, context: "",
                                                      variant: variant) == probe.expected {
                            correct += 1
                        }
                    }
                    let failures = Self.routerFailureTally - failuresBefore
                    Self.batteryEmit("router: \(correct)/\(trials) expected=\(probe.expected) variant=baseline band=baseline errors=\(failures) probe=\(probe.text)")
                    Self.batteryRecorder.recordProbe(
                        probe: probe.text, expected: probe.expected,
                        correct: correct, trials: trials,
                        variant: "baseline", context: "", band: "baseline", errors: failures
                    )
                }
                // #205: the image rows, scored as their OWN band so they can
                // never move the baseline gate's denominator. Run on the
                // control router because that is what a first measurement of
                // an unmeasured shape should establish.
                for probe in Self.routerImageProbes {
                    var correct = 0
                    let failuresBefore = Self.routerFailureTally
                    for _ in 1...trials {
                        if await routeNeedsDeviceTool(prompt: probe.text, context: "",
                                                      variant: variant) == probe.expected {
                            correct += 1
                        }
                    }
                    let failures = Self.routerFailureTally - failuresBefore
                    Self.batteryEmit("router: \(correct)/\(trials) expected=\(probe.expected) variant=image band=image errors=\(failures) probe=\(probe.text)")
                    Self.batteryRecorder.recordProbe(
                        probe: probe.text, expected: probe.expected,
                        correct: correct, trials: trials,
                        variant: "image", context: "", band: "image", errors: failures
                    )
                }
            }
            for row in grid {
                var correct = 0
                let failuresBefore = Self.routerFailureTally
                for _ in 1...trials {
                    if await routeNeedsDeviceTool(prompt: row.prompt, context: row.context,
                                                  variant: variant) == row.expected {
                        correct += 1
                    }
                }
                let failures = Self.routerFailureTally - failuresBefore
                Self.batteryEmit("router: \(correct)/\(trials) expected=\(row.expected) variant=\(variant.rawValue) band=\(row.band.rawValue) errors=\(failures) probe=\(row.prompt)")
                Self.batteryRecorder.recordProbe(
                    probe: row.prompt, expected: row.expected,
                    correct: correct, trials: trials,
                    variant: variant.rawValue, context: row.context, band: row.band.rawValue,
                    errors: failures
                )
            }
            emitThermal(cell: variant.rawValue, at: "end")
        }
        Self.batteryEmit("router: CONTEXT PROBE DONE (#202A)")
        Self.batteryRecorder.endRun()
    }

    // MARK: - (#202B) the two-turn offer→accept battery

    /// The conversation shape #200's own filing specimen took, and the one
    /// every existing instrument is blind to. The offer carries a FULLY
    /// SPECIFIED time deliberately: an underspecified offer would drag
    /// #200K's date-interrogation disease into the middle of a routing
    /// measurement and confound the two.
    struct TwoTurnSeed {
        let opener: String
        let offer: String
        let accept: String
        var turns: [TranscriptTurn] {
            [TranscriptTurn(role: .user, text: opener),
             TranscriptTurn(role: .assistant, text: offer)]
        }
    }

    nonisolated static let twoTurnSeed = TwoTurnSeed(
        opener: "Ugh, I always forget to call the dentist back.",
        offer: "Would you like me to set a reminder to call the dentist tomorrow at 9am?",
        accept: "Yes please"
    )

    /// Seeds through `transcriptEntries` — the SAME constructor
    /// `rebuildSession` uses to replay a stored conversation into a fresh
    /// session. The seeded arm is therefore production's replay path, not a
    /// bespoke shortcut around it.
    nonisolated static func twoTurnSeedEntries(instructions: String) -> [Transcript.Entry] {
        transcriptEntries(instructions: instructions, verbatimTurns: twoTurnSeed.turns)
    }

    /// The production rule the control arm's zero depends on: a routed-toolless
    /// turn registers NO belt. Extracted so it is pinned by a test rather than
    /// only ever verified by reading `effectiveOfferedTools`.
    nonisolated static func twoTurnBelt(from tools: [any Tool],
                                        routedToolless: Bool) -> [any Tool] {
        routedToolless ? [] : tools
    }

    /// #199 cross-reference: an accept turn can also fail by CLAIMING the
    /// reminder exists. Detected separately from the artifact and never
    /// instead of it — the standing law is that reply text lies both ways.
    /// Calibrated against VERBATIM production replies, not invented examples
    /// — the only method that has caught anything. Two gaps found that way:
    /// the curly apostrophe (#202B, nine missed lies), and the PASSIVE VOICE
    /// below (#199 prep). Production's commonest completion phrasing turns
    /// out to be "Your reminder … **has been set**" / "Lunch with Sam **has
    /// been scheduled**", which the original active-voice-only list missed
    /// entirely — it would have under-counted the calendar and alarm arms to
    /// near zero.
    nonisolated static let creationClaimPatterns = [
        // active
        "i've set", "i have set", "i've created", "i have created",
        "i've added", "i have added", "i've scheduled", "i have scheduled",
        // passive — the majority form in the observed replies
        "has been set", "have been set", "has been scheduled",
        "has been created", "has been added", "has been saved",
        // noun-first
        "reminder created", "reminder is set", "reminder set",
        "is scheduled for", "added to your calendar", "on your calendar for",
        "done —", "all set",
    ]

    /// The model types a CURLY apostrophe. `batteryDenialPatterns` handles
    /// that by listing both forms; anything newer normalizes instead, which
    /// is why #202B's first pass scored 0 fabrications against 9 real ones.
    nonisolated static func normalizedForMatching(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
    }

    nonisolated static func claimsCreation(_ text: String) -> Bool {
        let lower = normalizedForMatching(text)
        // A capability denial that happens to contain "set" is not a claim.
        guard !batteryDenialPatterns.contains(where: {
            lower.contains(normalizedForMatching($0))
        }) else { return false }
        return creationClaimPatterns.contains { lower.contains($0) }
    }

    /// #202B found a THIRD failure mode the program had no name for: with no
    /// belt, the model sometimes types a tool call out as prose — `tool:
    /// setReminder - action: create …`, occasionally wrapped in a
    /// `response_format` JSON block. Not a create, not a denial, and not a
    /// plain fabrication: an invented calling convention leaking to the user.
    nonisolated static func emitsRawToolSyntax(_ text: String) -> Bool {
        let lower = normalizedForMatching(text)
        return lower.contains("tool: ") || lower.contains("response_format")
    }

    /// #202C's structural cure, kept OFF the device budget: a toolless turn
    /// whose reply claims an action it could not perform is re-run ARMED.
    /// It is a COMPOSITION of two already-measured parts — this detector,
    /// and an armed accept turn that #202B measured at 12/12 — so the trigger
    /// is unit-pinned instead of costing trials. The user never sees the lie
    /// and gets the real create.
    nonisolated static func shouldEscalateToArmed(reply: String) -> Bool {
        claimsCreation(reply) || emitsRawToolSyntax(reply)
    }

    /// #202D: the SECOND false statement. #202C's clause cured the lie and
    /// 7/10 of its refusals then claimed the APP cannot set reminders —
    /// untrue, and a user told that may simply stop asking. A refusal is
    /// only honest if it is scoped in TIME: "right now" is accurate, "on
    /// this device" is not. Calibrated against run C112B3D4's verbatim text.
    nonisolated static let refusalMarkers = [
        "can't", "cannot", "can not", "unable", "not able", "won't be able",
    ]
    nonisolated static let temporalScopeMarkers = [
        "right now", "on this turn", "at the moment", "currently",
        "just now", "this time", "in this mode",
    ]

    nonisolated static func claimsPermanentInability(_ text: String) -> Bool {
        let lower = normalizedForMatching(text)
        guard refusalMarkers.contains(where: { lower.contains($0) }) else { return false }
        return !temporalScopeMarkers.contains { lower.contains($0) }
    }

    enum TwoTurnCell: String, CaseIterable {
        /// The selected #202A candidate on turn 2. The arm being MEASURED.
        case twoturnCtxa = "twoturn-ctxa"
        /// Production's router on turn 2. Its zero is structural — see the
        /// dispatch: this arm falsifies the no-belt claim, it does not
        /// provide evidence for the fix.
        case twoturnControl = "twoturn-control"
        /// Turn 1 GENERATED rather than seeded, so the seeded offer can be
        /// checked against the offers the model actually makes. Diagnostic,
        /// not gated.
        case twoturnNatural = "twoturn-natural"

        var routerVariant: RouterVariant {
            switch self {
            case .twoturnControl: return .control
            // The natural arm validates the SEED for the selected candidate,
            // so it must run that candidate or it validates nothing.
            case .twoturnCtxa, .twoturnNatural: return .ctxA
            }
        }

        var generatesFirstTurn: Bool { self == .twoturnNatural }
    }

    /// PRE-REGISTERED ORDER, deliberately the REVERSE of #201B's rule. That
    /// rule protects a comparison from a hot control manufacturing a
    /// treatment win; here the control's zero is structural, so no comparison
    /// can be inflated. The live risk is the opposite — a throttled treatment
    /// failing an ABSOLUTE bar — so the measured arm takes the cool slot.
    nonisolated static let twoTurnBatteryCells: [TwoTurnCell] =
        [.twoturnCtxa, .twoturnControl, .twoturnNatural]

    /// #202B: turn 1 elicits an offer, turn 2 is a bare affirmative, and the
    /// score is the ARTIFACT — never the reply text. Routes EVERY turn, which
    /// is what separates this from the action battery (that one deliberately
    /// skips per-trial routing because its prompts were already measured as
    /// correctly routed; here the routing IS the treatment).
    func runTwoTurnBattery(trials: Int, cells: [TwoTurnCell] = LocalChatBackend.twoTurnBatteryCells,
                           naturalTrials: Int = 5,
                           warmup: Bool = LocalChatBackend.batteryWarmupDefault) async {
        guard await Self.beginBatteryRun() else {
            Self.batteryEmit("battery: REFUSED — another battery is already running (#200B mutex)")
            return
        }
        defer { Self.endBatteryRun() }
        let seed = Self.twoTurnSeed
        let fullBelt = Self.shapedBelt(
            from: DeviceToolBelt.offeredTools(from: tools, hasImageInContext: false),
            shape: .armedRouted
        )
        let armedInstructions = Self.instructionsText(
            for: .armedRouted, deviceContext: Self.deviceContextLine(),
            hasTools: !fullBelt.isEmpty, hasImageTools: false
        )
        // #202D: production's toolless text now carries clause v2, so the
        // two-turn instrument speaks it too — an instrument that lags the
        // shipped payload measures a path no user takes.
        let toollessInstructions = Self.productionToollessInstructions(
            deviceContext: Self.deviceContextLine(), hasImageTools: false
        )
        Self.batteryEmit("battery: START kind=twoturn trials=\(trials) cells=\(cells.count) warmup=\(warmup) (#202B)")

        var perTrialReminders = 0
        var perTrialEvents = 0
        var perTrialAlarms = 0
        var perTrialFailures = 0

        func reap(tag: String) async {
            let sweep = await Self.sweepMarkedRemindersAndEvents(emitSteps: false)
            let alarmSweep = AlarmService.reapBatteryAlarms()
            perTrialReminders += sweep.reminders
            perTrialEvents += sweep.events
            perTrialAlarms += alarmSweep.cancelled
            perTrialFailures += sweep.failures + alarmSweep.failed
            Self.batteryEmit(Self.reapTrialLine(
                reminders: sweep.reminders, events: sweep.events,
                alarms: alarmSweep.cancelled,
                failures: sweep.failures + alarmSweep.failed, tag: tag
            ))
        }

        // #200V: a DISCARDED warm-up, recorder-inert because it runs before
        // beginRun. One accept turn through the measured arm's belt.
        if warmup {
            Self.batteryEmit("battery: WARMUP begin kind=twoturn (#200V)")
            ToolEventRelay.batteryTrialTag = Self.batteryWarmupTag(prompt: "accept")
            let session = LanguageModelSession(
                model: model, tools: fullBelt,
                transcript: Transcript(entries: Self.twoTurnSeedEntries(
                    instructions: armedInstructions))
            )
            await executeBatteryTrial(
                session: session,
                options: Self.chatGenerationOptions(for: activeTier),
                shape: "warmup", promptTag: "accept", prompt: seed.accept, trial: 0
            )
            await reap(tag: Self.batteryWarmupTag(prompt: "accept"))
            Self.batteryEmit("battery: WARMUP done — discarded, not counted (#200V)")
        }

        Self.batteryRecorder.beginRun(trialsPerCell: trials,
                                      cells: cells.map(\.rawValue), kind: "twoturn")
        for cell in cells {
            emitThermal(cell: cell.rawValue, at: "start")
            let cellTrials = cell.generatesFirstTurn ? naturalTrials : trials
            for trial in 1...cellTrials {
                ToolEventRelay.batteryTrialTag = "shape=\(cell.rawValue) p=accept t=\(trial)"
                Self.batteryEmit("battery: BEGIN shape=\(cell.rawValue) p=accept t=\(trial)")

                // TURN 1. Seeded arms replay the pinned offer; the natural
                // arm generates it and records what the model actually says,
                // so the seed can be checked rather than assumed.
                var turns = seed.turns
                if cell.generatesFirstTurn {
                    let firstRouted = !(await routeNeedsDeviceTool(
                        prompt: seed.opener, context: "", variant: cell.routerVariant))
                    let firstBelt = Self.twoTurnBelt(from: fullBelt, routedToolless: firstRouted)
                    let firstSession = LanguageModelSession(
                        model: model, tools: firstBelt,
                        instructions: Instructions(firstRouted ? toollessInstructions : armedInstructions)
                    )
                    let reply = await twoTurnRespond(session: firstSession, prompt: seed.opener)
                    Self.batteryEmit("battery: turn1 shape=\(cell.rawValue) t=\(trial) route=\(firstRouted ? "toolless" : "armed") text=\(reply.replacingOccurrences(of: "\n", with: " / ").prefix(300))")
                    // A turn-1 create means the offer→accept shape was never
                    // reached — reported, and the trial still runs so the
                    // accept's behaviour after a create is visible too.
                    turns = [TranscriptTurn(role: .user, text: seed.opener),
                             TranscriptTurn(role: .assistant, text: reply)]
                    await reap(tag: "shape=\(cell.rawValue) p=turn1 t=\(trial)")
                }

                // TURN 2 — the measured turn. Routed with the PRIOR ASSISTANT
                // TURN as context, which is the whole treatment.
                Self.batteryRecorder.beginTrial()
                let context = turns.last?.text ?? seed.offer
                let armed = await routeNeedsDeviceTool(
                    prompt: seed.accept, context: context, variant: cell.routerVariant)
                Self.batteryRecorder.recordRoute(armed ? "armed" : "toolless")
                Self.batteryEmit("battery: turn2 shape=\(cell.rawValue) t=\(trial) route=\(armed ? "armed" : "toolless")")
                let belt = Self.twoTurnBelt(from: fullBelt, routedToolless: !armed)
                let session = LanguageModelSession(
                    model: model, tools: belt,
                    transcript: Transcript(entries: Self.transcriptEntries(
                        instructions: armed ? armedInstructions : toollessInstructions,
                        verbatimTurns: turns))
                )
                await executeBatteryTrial(
                    session: session,
                    options: Self.chatGenerationOptions(for: activeTier),
                    shape: cell.rawValue, promptTag: "accept",
                    prompt: seed.accept, trial: trial
                )
                await reap(tag: "shape=\(cell.rawValue) p=accept t=\(trial)")
            }
            emitThermal(cell: cell.rawValue, at: "end")
        }
        ToolEventRelay.batteryTrialTag = nil
        let reapSummary = await reapBatteryArtifacts(
            perTrialReminders: perTrialReminders, perTrialEvents: perTrialEvents,
            perTrialAlarms: perTrialAlarms, perTrialFailures: perTrialFailures
        )
        Self.batteryEmit("battery: REAP \(reapSummary) (#202B)")
        Self.batteryRecorder.recordReapSummary(reapSummary)
        Self.batteryEmit("battery: DONE (#202B)")
        Self.batteryRecorder.endRun()
    }

    // MARK: - (#202C) the toolless honesty lane

    // `deadEndCarveoutClause`, `toollessHonestyClause` and
    // `toollessHonestyClauseV2` were declared HERE until 2026-08-01 and are now
    // in `LocalChatBackend.swift`, unconditionally compiled.
    //
    // They are PROMOTED — `instructionsText` reads them on every production
    // turn — so declaring them inside this `#if DEBUG` file meant production
    // referenced a symbol that does not exist in Release. `main` failed to
    // archive from #202C (2026-07-30) until it was caught, invisibly, because
    // every build anyone ran was Debug. **Do not move them back.** The battery
    // reads them from production precisely so a rollback cell can be pinned as
    // "production MINUS exactly this string" — which only works if the string
    // production uses is the one being subtracted.

    enum HonestyCell: String, CaseIterable {
        /// PRE-#202D production: the bare `toolless-lic2` payload. Since the
        /// promotion this is the PINNED ROLLBACK, not production — the
        /// `armed-cardrollback` / `armed-deadendrollback` precedent. Measured
        /// at 9/10 broken turns (4 lies + 6 raw syntax, 1 honest).
        case honestyControl = "honesty-control"
        /// Same payload plus the honesty clause. One seam.
        case honestyFix = "honesty-fix"
        /// #202D: the reworded clause. v1's claim ban kept; its capability
        /// misstatement fixed.
        case honestyFixV2 = "honesty-fix-v2"

        var includesHonestyClause: Bool { self != .honestyControl }
        var usesV2Clause: Bool { self == .honestyFixV2 }
    }

    /// Production first: the incumbent takes the cool slot, so a treatment
    /// win is won from the throttled one (#201B's rule — which applies here,
    /// unlike #202B, because this IS a control-vs-treatment comparison).
    nonisolated static let honestyBatteryCells: [HonestyCell] = [.honestyControl, .honestyFix]

    /// #202D: v1 vs v2 DIRECTLY. Production is deliberately absent — its
    /// behaviour is established across two runs (#202B 11/12 broken, #202C
    /// 9/10) and re-measuring it would spend trials on a settled number.
    /// The open question is between the two wordings, and v1 doubles as the
    /// control because its own numbers (0/10 lies, 7/10 capability claims)
    /// are the thing v2 must match on one axis and beat on the other.
    nonisolated static let honestyV2BatteryCells: [HonestyCell] = [.honestyFix, .honestyFixV2]

    /// The #196 tic guard, VERBATIM. `toolless-lic2` was promoted on 60/60
    /// clean across exactly these three; a different set would not be
    /// comparable, and the tic is the collateral this lane gates on.
    nonisolated static let honestyTicPrompts: [(tag: String, text: String)] = [
        ("canary", "What's 2+2?"),
        ("haiku", "Write a haiku about sledding"),
        ("norway", "write a 50 word summary about Norway"),
    ]

    /// #202C: does the toolless branch stop LYING, without the disclaimer
    /// tic coming back? Turn 2 is forced TOOLLESS deterministically rather
    /// than routed — the routing question is already answered (#202A/#202B),
    /// and forcing it makes every trial evaluable and isolates the payload.
    func runHonestyBattery(trials: Int, ticTrials: Int = 4,
                           cells: [HonestyCell] = LocalChatBackend.honestyBatteryCells,
                           warmup: Bool = LocalChatBackend.batteryWarmupDefault) async {
        guard await Self.beginBatteryRun() else {
            Self.batteryEmit("battery: REFUSED — another battery is already running (#200B mutex)")
            return
        }
        defer { Self.endBatteryRun() }
        let seed = Self.twoTurnSeed
        func payload(_ cell: HonestyCell) -> String {
            Self.instructionsText(
                deviceContext: Self.deviceContextLine(), hasTools: false, hasImageTools: false,
                includeToollessLic2Clause: true,
                includeToollessHonestyClause: cell.includesHonestyClause && !cell.usesV2Clause,
                includeToollessHonestyClauseV2: cell.usesV2Clause
            )
        }
        Self.batteryEmit("battery: START kind=honesty trials=\(trials) tic=\(ticTrials) cells=\(cells.count) warmup=\(warmup) (#202C)")

        if warmup, let first = cells.first {
            Self.batteryEmit("battery: WARMUP begin kind=honesty (#200V)")
            ToolEventRelay.batteryTrialTag = Self.batteryWarmupTag(prompt: "accept")
            await executeBatteryTrial(
                session: LanguageModelSession(
                    model: model, tools: [],
                    transcript: Transcript(entries: Self.twoTurnSeedEntries(
                        instructions: payload(first)))),
                options: Self.chatGenerationOptions(for: activeTier),
                shape: "warmup", promptTag: "accept", prompt: seed.accept, trial: 0
            )
            Self.batteryEmit("battery: WARMUP done — discarded, not counted (#200V)")
        }

        Self.batteryRecorder.beginRun(trialsPerCell: trials,
                                      cells: cells.map(\.rawValue), kind: "honesty")
        for cell in cells {
            emitThermal(cell: cell.rawValue, at: "start")
            let instructions = payload(cell)
            // The ACCEPT shape — the measured one. No belt, ever: this arm
            // exists to find out what a disarmed turn SAYS.
            for trial in 1...trials {
                ToolEventRelay.batteryTrialTag = "shape=\(cell.rawValue) p=accept t=\(trial)"
                Self.batteryEmit("battery: BEGIN shape=\(cell.rawValue) p=accept t=\(trial)")
                Self.batteryRecorder.beginTrial()
                Self.batteryRecorder.recordRoute("toolless")
                await executeBatteryTrial(
                    session: LanguageModelSession(
                        model: model, tools: [],
                        transcript: Transcript(entries: Self.twoTurnSeedEntries(
                            instructions: instructions))),
                    options: Self.chatGenerationOptions(for: activeTier),
                    shape: cell.rawValue, promptTag: "accept", prompt: seed.accept, trial: trial
                )
            }
            // The #196 TIC GUARD — single-turn words-only, same payload. An
            // honesty mandate is exactly the text that brings the tic back,
            // and `denial`/`cant` on these three IS the tic measurement.
            for (tag, text) in Self.honestyTicPrompts {
                for trial in 1...ticTrials {
                    ToolEventRelay.batteryTrialTag = "shape=\(cell.rawValue) p=\(tag) t=\(trial)"
                    Self.batteryEmit("battery: BEGIN shape=\(cell.rawValue) p=\(tag) t=\(trial)")
                    Self.batteryRecorder.beginTrial()
                    Self.batteryRecorder.recordRoute("toolless")
                    await executeBatteryTrial(
                        session: LanguageModelSession(
                            model: model, tools: [],
                            instructions: Instructions(instructions)),
                        options: Self.chatGenerationOptions(for: activeTier),
                        shape: cell.rawValue, promptTag: tag, prompt: text, trial: trial
                    )
                }
            }
            emitThermal(cell: cell.rawValue, at: "end")
        }
        ToolEventRelay.batteryTrialTag = nil
        // Nothing can have been created — no belt in any trial — but the
        // sweep still runs so the seal is present and the arithmetic closes.
        let reapSummary = await reapBatteryArtifacts(
            perTrialReminders: 0, perTrialEvents: 0, perTrialAlarms: 0, perTrialFailures: 0
        )
        Self.batteryEmit("battery: REAP \(reapSummary) (#202C)")
        Self.batteryRecorder.recordReapSummary(reapSummary)
        Self.batteryEmit("battery: DONE (#202C)")
        Self.batteryRecorder.endRun()
    }

    /// Turn 1 of the natural arm: same 35s guillotine as a counted trial, but
    /// its text is context for turn 2 rather than a scored result, so it does
    /// not touch the recorder.
    private func twoTurnRespond(session: LanguageModelSession, prompt: String) async -> String {
        let respondTask = Task {
            try await session.respond(
                to: Prompt(prompt),
                options: Self.chatGenerationOptions(for: activeTier)
            ).content
        }
        let timeoutTask = Task { try? await Task.sleep(for: .seconds(35)); respondTask.cancel() }
        defer { timeoutTask.cancel() }
        do {
            return try await respondTask.value
        } catch {
            Self.batteryEmit("battery: turn1 FAILED \(String(String(describing: error).prefix(120)))")
            return Self.twoTurnSeed.offer
        }
    }
}

// MARK: - (#200E) toolmode cell session profile

extension SessionPropertyValues {
    /// #200E: per-session tool-call counter driving the toolmode demote.
    /// Fresh session per trial ⇒ resets to 0 ⇒ every trial's first model
    /// turn is `.required`.
    @SessionPropertyEntry
    var batteryToolCallCount: Int = 0

    /// #200H: per-session PER-NAME tool-call tally driving the
    /// third-strike demote. Fresh session per trial ⇒ empty tally ⇒ every
    /// trial starts `.allowed`. (A dictionary entry is Apple's own
    /// SessionPropertyEntry doc example.)
    @SessionPropertyEntry
    var batteryToolCallTally: [String: Int] = [:]
}

extension LocalChatBackend {
    /// #200E: the toolmode cell's session. Belt and instructions are
    /// PRODUCTION verbatim (pinned); generation options are the shaped
    /// production options carried as profile modifiers. The single
    /// treatment is the tool-calling mode: `.required` until the first
    /// tool call, `.allowed` after (`toolmodeMode(after:)`) — the demote
    /// exit Apple's doc comment makes MANDATORY, because a static
    /// `.required` loops until a tool throws.
    struct ToolmodeBatteryProfile: LanguageModelSession.DynamicProfile {
        let model: SystemLanguageModel
        let belt: [any Tool]
        let instructionsText: String
        let options: GenerationOptions

        @SessionProperty(\.batteryToolCallCount) private var toolCallCount

        var body: some LanguageModelSession.DynamicProfile {
            Profile {
                Instructions(instructionsText)
                belt
            }
            .model(model)
            .samplingMode(options.samplingMode)
            .temperature(options.temperature)
            .maximumResponseTokens(options.maximumResponseTokens)
            .toolCallingMode(LocalChatBackend.toolmodeMode(after: toolCallCount))
            .onToolCall {
                toolCallCount += 1
                // The demote count, surfaced on the capture log. batteryEmit
                // and the trial tag are MainActor — hop EXPLICITLY (the 27b4
                // device runtime traps assumed isolation in framework
                // callbacks; see device-only-isolation-trap).
                let n = toolCallCount
                Task { @MainActor in
                    LocalChatBackend.batteryEmit("battery: toolmode call#\(n) \(ToolEventRelay.batteryTrialTag ?? "")")
                }
            }
        }
    }

    /// #200H: the strikefix cell's session. Belt and instructions are
    /// PRODUCTION verbatim (pinned); the single treatment is the
    /// third-strike demote: tool-calling mode `.allowed` until any single
    /// tool reaches its third call (`spiralBudgetMode(tally:)`),
    /// `.disallowed` after — the decode mask closes and the model must
    /// answer with what it already has. The per-name tally rides the
    /// NAMED onToolCall overload (`Transcript.ToolCall.toolName`).
    struct SpiralBudgetProfile: LanguageModelSession.DynamicProfile {
        let model: SystemLanguageModel
        let belt: [any Tool]
        let instructionsText: String
        let options: GenerationOptions

        @SessionProperty(\.batteryToolCallTally) private var tally

        var body: some LanguageModelSession.DynamicProfile {
            Profile {
                Instructions(instructionsText)
                belt
            }
            .model(model)
            .samplingMode(options.samplingMode)
            .temperature(options.temperature)
            .maximumResponseTokens(options.maximumResponseTokens)
            .toolCallingMode(LocalChatBackend.spiralBudgetMode(tally: tally))
            .onToolCall { call in
                tally[call.toolName, default: 0] += 1
                // The strike count, surfaced on the capture log — same
                // explicit MainActor hop as the toolmode profile (27b4
                // device isolation trap in framework callbacks).
                let n = tally[call.toolName] ?? 0
                Task { @MainActor in
                    LocalChatBackend.batteryEmit("battery: strike \(call.toolName)#\(n) \(ToolEventRelay.batteryTrialTag ?? "")")
                }
            }
        }
    }
}
#endif
