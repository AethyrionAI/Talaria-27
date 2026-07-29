import Foundation
import FoundationModels
import Testing
@testable import Talaria

/// #28 — the deterministic layer of the device tool belt: shared formatting,
/// snippet extraction, and the conversation-search report assembly. The
/// framework-facing tool calls (HealthKit, EventKit, WeatherKit, Vision, …)
/// need entitlements + permissions and are device-verified, not unit-tested.
struct DeviceToolBeltTests {

    // MARK: Formatting

    @Test func hoursMinutesFormatsFractionalHours() {
        #expect(DeviceToolFormat.hoursMinutes(fromHours: 7.4) == "7h 24m")
        #expect(DeviceToolFormat.hoursMinutes(fromHours: 8.0) == "8h")
        #expect(DeviceToolFormat.hoursMinutes(fromHours: 0.5) == "30m")
    }

    @Test func storageLineHandlesMissingValues() {
        #expect(DeviceToolFormat.storageLine(availableBytes: nil, totalBytes: nil) == "Storage: unknown free")
        let line = DeviceToolFormat.storageLine(availableBytes: 1_000_000, totalBytes: nil)
        #expect(line.hasPrefix("Storage: "))
        #expect(line.hasSuffix(" free"))
        let full = DeviceToolFormat.storageLine(availableBytes: 1_000_000, totalBytes: 128_000_000_000)
        #expect(full.contains(" free of "))
    }

    // MARK: Snippets

    @Test func snippetFindsCaseInsensitiveMatchWithEllipses() {
        let text = String(repeating: "x", count: 200) + " the TAILSCALE setup steps " + String(repeating: "y", count: 200)
        let snippet = DeviceToolFormat.snippet(around: "tailscale", in: text)
        #expect(snippet != nil)
        #expect(snippet!.localizedCaseInsensitiveContains("tailscale"))
        #expect(snippet!.hasPrefix("…"))
        #expect(snippet!.hasSuffix("…"))
    }

    @Test func snippetReturnsNilWhenTermAbsent() {
        #expect(DeviceToolFormat.snippet(around: "missing", in: "nothing to see here") == nil)
    }

    @Test func snippetFlattensNewlines() {
        let snippet = DeviceToolFormat.snippet(around: "middle", in: "line one\nthe middle line\nline three")
        #expect(snippet?.contains("\n") == false)
    }

    // MARK: Conversation search report

    private func conversation(withMessages contents: [(MessageSender, String)]) -> Conversation {
        Conversation(
            title: "Test",
            messages: contents.map { Message(sender: $0.0, content: $0.1, status: .delivered) }
        )
    }

    @Test func reportFindsHitsInCurrentConversation() {
        let convo = conversation(withMessages: [
            (.user, "How do I configure Tailscale on the Mac Mini?"),
            (.hermes, "Install Tailscale from the App Store, then sign in."),
            (.system, "Tailscale system banner — must not surface"),
        ])
        let report = ConversationSearchTool.report(
            term: "tailscale", conversation: convo, sessions: [], spotlightEnabled: true
        )
        #expect(report.contains("current conversation"))
        #expect(report.contains("You:"))
        #expect(report.contains("Hermes:"))
        #expect(!report.contains("system banner"))
    }

    @Test func reportSearchesSessionCacheTitlesAndPreviews() {
        let sessions = [
            ConversationSearchTool.CachedSession(id: "a", title: "Reverse proxy setup", preview: "Caddy on the home lab"),
            ConversationSearchTool.CachedSession(id: "b", title: "Trip planning", preview: nil),
        ]
        let report = ConversationSearchTool.report(
            term: "caddy", conversation: nil, sessions: sessions, spotlightEnabled: true
        )
        #expect(report.contains("Reverse proxy setup"))
        #expect(!report.contains("Trip planning"))
    }

    @Test func reportIsHonestWhenNothingMatches() {
        let report = ConversationSearchTool.report(
            term: "nonexistent", conversation: nil, sessions: [], spotlightEnabled: true
        )
        #expect(report.contains("No matches"))
    }

    @Test func reportSaysWhenIndexingIsOff() {
        // With indexing off, past sessions genuinely weren't searchable —
        // the report must say so instead of implying full coverage.
        let convo = conversation(withMessages: [(.user, "find the caddy notes")])
        let withHit = ConversationSearchTool.report(
            term: "caddy", conversation: convo, sessions: [], spotlightEnabled: false
        )
        #expect(withHit.contains("indexing is off"))
        let noHit = ConversationSearchTool.report(
            term: "zzz", conversation: nil, sessions: [], spotlightEnabled: false
        )
        #expect(noHit.contains("indexing is off"))
    }

    // MARK: Tool-aware instructions (#26 → #28)

    @Test func instructionsMentionToolsOnlyWhenInstalled() {
        let bare = LocalChatBackend.instructionsText(deviceContext: "Device: test.", hasTools: false)
        #expect(bare.contains("no external tools"))
        // 176C Part 2: the armed branch no longer enumerates the belt in
        // prose — tool-awareness shows as the scoped use-tools sentence.
        let armed = LocalChatBackend.instructionsText(deviceContext: "Device: test.", hasTools: true)
        #expect(armed.contains("Use the tools for the user's own data"))
        #expect(armed.contains("never invent a value"))
    }

    @Test func instructionsCarryNoToolRosterRegardlessOfVision() {
        // 176C Part 2 (#194): the prose belt roster was the convicted
        // creative suppressor — the tools' native `Tool.description` metadata
        // is now the ONLY enumeration, so the instructions can never claim a
        // tool this session wasn't given. The #176/#148 vision gate lives
        // structurally in `DeviceToolBelt.offeredTools` (tested below), not
        // in prose.
        let seeing = LocalChatBackend.instructionsText(
            deviceContext: "Device: test.", hasTools: true, hasImageTools: true
        )
        let blind = LocalChatBackend.instructionsText(
            deviceContext: "Device: test.", hasTools: true, hasImageTools: false
        )
        for text in [seeing, blind] {
            #expect(!text.contains("image text/barcode reading"))
            #expect(!text.contains("You also have device tools"))
            // The kept sentences still stand.
            #expect(text.contains("the user's own data"))
            #expect(text.contains("never invent a value"))
        }
    }

    // MARK: Belt-truth instructions (#176B / #194)

    @Test func armedInstructionsLicenseAnsweringAndCreatingWithoutATool() {
        // The tool-LESS branch always authorized "say so plainly instead of
        // guessing"; the armed branch had no answering clause at all, and the
        // device read the belt as a job description — "write a poem" deflected
        // to reminders/weather (#194). The license must come with the belt.
        let armed = LocalChatBackend.instructionsText(deviceContext: "Device: test.", hasTools: true)
        #expect(armed.contains("need no tool"))
        #expect(armed.contains("facts you know are not guesses"))
        // Generation, not only recall (#194): creative work is first-class.
        #expect(armed.contains("writing and composing"))
        #expect(armed.contains("summarizing"))
        // "Use tools instead of guessing" is scoped to device data, not the world.
        #expect(armed.contains("the user's own data"))
        #expect(armed.contains("general knowledge is not device data"))
    }

    @Test func armedInstructionsCarryTheRecoveryClause() {
        // The absorbing state (#176B): one permission denial became every
        // later turn's answer. A failed tool is information about the tool.
        let armed = LocalChatBackend.instructionsText(deviceContext: "Device: test.", hasTools: true)
        #expect(armed.contains("never the answer"))
        #expect(armed.contains("repeat a denial"))
        // The honesty half stays: recovery must not license invention.
        #expect(armed.contains("never invent a value"))
    }

    // MARK: Session-shape instrument (#196, reworked from #194/176C)

    /// A fixed date so the two texts under comparison can never straddle a
    /// day boundary mid-test.
    private static let shapeDate = Date(timeIntervalSince1970: 1_753_600_000)

    @Test func complicVariantAddsOnlyTheCompositionSentence() {
        let armed = LocalChatBackend.instructionsText(
            deviceContext: "Device: test.", date: Self.shapeDate, hasTools: true
        )
        let complic = LocalChatBackend.instructionsText(
            for: .armedComplic, deviceContext: "Device: test.",
            date: Self.shapeDate, hasTools: true
        )
        // The composition-licensing sentence is whole and in the cell only —
        // production armed is the control and must not carry it. (A battery
        // verdict for the complic/fix cells flips exactly this pin.)
        #expect(!armed.contains("is not retrieval"))
        #expect(complic.contains("You know a great deal about the world — places, people, history, ideas — and writing about it needs no internet, database, or lookup: composing from your own knowledge is not retrieval."))
        // Placed inside the licensing clause: the insertion took exactly one
        // sentence and neither neighbor moved.
        #expect(complic.contains("general knowledge is not device data. You know a great deal"))
        #expect(complic.contains("is not retrieval. Use the tools for the user's own data"))
        // Every production sentence survives (#176/#194 hard constraints):
        #expect(complic.contains("need no tool"))                 // licensing
        #expect(complic.contains("writing and composing"))        // licensing (#194)
        #expect(complic.contains("confirmation card first"))      // action confirmation
        #expect(complic.contains("never invent a value"))         // honesty
        #expect(complic.contains("never the answer"))             // recovery
        #expect(complic.contains("repeat a denial"))              // recovery
    }

    @Test func toollessLicVariantIsTheLicensedBareBranchWithTheCaveatKept() {
        // #196 second battery, cell (c): the bare branch never received
        // #176B's licensing clause and measured 0/10 on composition with
        // the purest denials. The licensed form must license composition
        // AND keep the no-internet honesty caveat — without it the branch
        // would again be free to guess at current events and user data.
        let bare = LocalChatBackend.instructionsText(
            deviceContext: "Device: test.", date: Self.shapeDate, hasTools: false
        )
        let lic = LocalChatBackend.instructionsText(
            for: .toollessLic, deviceContext: "Device: test.",
            date: Self.shapeDate, hasTools: true
        )
        // Licensed composition, absent from the shipping bare branch:
        #expect(!bare.contains("needs no internet or lookup"))
        #expect(lic.contains("writing and composing"))
        #expect(lic.contains("facts you know are not guesses"))
        #expect(lic.contains("writing about the world from your own knowledge needs no internet or lookup"))
        // The honesty caveat survives, both halves:
        #expect(lic.contains("You have no internet access and no external tools in this mode"))
        #expect(lic.contains("say so plainly instead of guessing"))
        // Still the BARE branch — the hasTools:true input above must not
        // leak the armed clauses in:
        #expect(!lic.contains("Use the tools"))
        #expect(!lic.contains("confirmation card"))
    }

    @Test func armedAndRemfixInstructionsAreProductionVerbatimAndToollessIsTheBareBranch() {
        for hasImageTools in [false, true] {
            let production = LocalChatBackend.instructionsText(
                deviceContext: "Device: test.", date: Self.shapeDate,
                hasTools: true, hasImageTools: hasImageTools
            )
            let control = LocalChatBackend.instructionsText(
                for: .armed, deviceContext: "Device: test.",
                date: Self.shapeDate, hasTools: true, hasImageTools: hasImageTools
            )
            #expect(control == production)
            // armed-remfix is a BELT treatment: its instructions must be
            // the production text verbatim or the cell measures two things.
            let remfix = LocalChatBackend.instructionsText(
                for: .armedRemfix, deviceContext: "Device: test.",
                date: Self.shapeDate, hasTools: true, hasImageTools: hasImageTools
            )
            #expect(remfix == production)
        }
        // armed-fix's INSTRUCTION half is exactly armed-complic's text —
        // the combined cell adds the belt treatment on top, nothing else.
        let complic = LocalChatBackend.instructionsText(
            for: .armedComplic, deviceContext: "Device: test.",
            date: Self.shapeDate, hasTools: true
        )
        let fix = LocalChatBackend.instructionsText(
            for: .armedFix, deviceContext: "Device: test.",
            date: Self.shapeDate, hasTools: true
        )
        #expect(fix == complic)
        let bare = LocalChatBackend.instructionsText(
            deviceContext: "Device: test.", date: Self.shapeDate, hasTools: false
        )
        let farControl = LocalChatBackend.instructionsText(
            for: .toolless, deviceContext: "Device: test.",
            date: Self.shapeDate, hasTools: true
        )
        #expect(farControl == bare)
    }

    @Test func sessionShapeCellsParseFromLaunchEnvValuesAndGateTools() {
        // The six spellings, exactly as the desk A/B checklist uses them.
        #expect(LocalChatBackend.SessionShape(rawValue: "armed") == .armed)
        #expect(LocalChatBackend.SessionShape(rawValue: "armed-remfix") == .armedRemfix)
        #expect(LocalChatBackend.SessionShape(rawValue: "armed-complic") == .armedComplic)
        #expect(LocalChatBackend.SessionShape(rawValue: "armed-fix") == .armedFix)
        #expect(LocalChatBackend.SessionShape(rawValue: "toolless") == .toolless)
        #expect(LocalChatBackend.SessionShape(rawValue: "toolless-lic") == .toollessLic)
        // Unknown values must fall back to production, never crash or
        // guess — including EVERY retired cell name a phone may still carry
        // in the persisted Diagnostics override from an earlier A/B (the
        // 176C names and the first battery's).
        #expect(LocalChatBackend.SessionShape(rawValue: "bogus") == nil)
        #expect(LocalChatBackend.SessionShape(rawValue: "armed-noprose") == nil)
        #expect(LocalChatBackend.SessionShape(rawValue: "prose-notools") == nil)
        #expect(LocalChatBackend.SessionShape(rawValue: "armed-direct") == nil)
        #expect(LocalChatBackend.SessionShape(rawValue: "armed-noneg") == nil)
        // Which cells hand the session a belt at all.
        #expect(LocalChatBackend.SessionShape.armed.registersTools)
        #expect(LocalChatBackend.SessionShape.armedRemfix.registersTools)
        #expect(LocalChatBackend.SessionShape.armedComplic.registersTools)
        #expect(LocalChatBackend.SessionShape.armedFix.registersTools)
        #expect(!LocalChatBackend.SessionShape.toolless.registersTools)
        #expect(!LocalChatBackend.SessionShape.toollessLic.registersTools)
        // Which cells carry the scoped createReminder description.
        #expect(!LocalChatBackend.SessionShape.armed.usesScopedReminderDescription)
        #expect(LocalChatBackend.SessionShape.armedRemfix.usesScopedReminderDescription)
        #expect(!LocalChatBackend.SessionShape.armedComplic.usesScopedReminderDescription)
        #expect(LocalChatBackend.SessionShape.armedFix.usesScopedReminderDescription)
        #expect(!LocalChatBackend.SessionShape.toolless.usesScopedReminderDescription)
        #expect(!LocalChatBackend.SessionShape.toollessLic.usesScopedReminderDescription)

        // Third battery (#196 decomposition): the five structural cells.
        #expect(LocalChatBackend.SessionShape(rawValue: "armed-noinstr") == .armedNoinstr)
        #expect(LocalChatBackend.SessionShape(rawValue: "toolless-noinstr") == .toollessNoinstr)
        #expect(LocalChatBackend.SessionShape(rawValue: "armed-readonly") == .armedReadonly)
        #expect(LocalChatBackend.SessionShape(rawValue: "armed-nocall") == .armedNocall)
        #expect(LocalChatBackend.SessionShape(rawValue: "armed-noschema") == .armedNoschema)
        // The cut cell never became a spelling (Owen veto at dispatch v2 —
        // prose is not the road): it must not parse.
        #expect(LocalChatBackend.SessionShape(rawValue: "armed-example") == nil)
        #expect(LocalChatBackend.SessionShape.armedNoinstr.registersTools)
        #expect(!LocalChatBackend.SessionShape.toollessNoinstr.registersTools)
        #expect(LocalChatBackend.SessionShape.armedReadonly.registersTools)
        #expect(LocalChatBackend.SessionShape.armedNocall.registersTools)
        #expect(LocalChatBackend.SessionShape.armedNoschema.registersTools)
        // None of the decomposition cells touches the remfix description
        // treatment — single-variable discipline.
        for shape in [LocalChatBackend.SessionShape.armedNoinstr, .toollessNoinstr, .armedReadonly, .armedNocall, .armedNoschema] {
            #expect(!shape.usesScopedReminderDescription)
        }

        // Fourth battery (#196 cure lane): the payload and the candidate.
        #expect(LocalChatBackend.SessionShape(rawValue: "toolless-lic2") == .toollessLic2)
        #expect(LocalChatBackend.SessionShape(rawValue: "armed-routed") == .armedRouted)
        #expect(!LocalChatBackend.SessionShape.toollessLic2.registersTools)
        // armed-routed CAN register — the per-turn router decides whether a
        // given turn actually does.
        #expect(LocalChatBackend.SessionShape.armedRouted.registersTools)
        #expect(!LocalChatBackend.SessionShape.toollessLic2.usesScopedReminderDescription)
        #expect(!LocalChatBackend.SessionShape.armedRouted.usesScopedReminderDescription)
    }

    @Test @MainActor func shapedBeltSwapsOnlyTheReminderDescriptionInRemfixCells() {
        // #196 cell (a): fix the tool, not the prompt. The shaped belt must
        // be the identity everywhere except createReminder's description in
        // the remfix treatments — same tools, same order, same gate.
        let relay = ToolEventRelay()
        let confirmations = ToolConfirmationCenter()
        let belt: [any Tool] = [
            ReminderCreateTool(relay: relay, confirmations: confirmations),
            CalendarEventTool(relay: relay, confirmations: confirmations),
        ]
        // The default description IS production — the seam is inert at
        // every production call site.
        #expect((belt[0] as? ReminderCreateTool)?.description == ReminderCreateTool.productionDescription)

        let untouched = LocalChatBackend.shapedBelt(from: belt, shape: .armed)
        #expect(untouched.map { $0.name } == ["createReminder", "createCalendarEvent"])
        #expect((untouched[0] as? ReminderCreateTool)?.description == ReminderCreateTool.productionDescription)

        for shape in [LocalChatBackend.SessionShape.armedRemfix, .armedFix] {
            let shaped = LocalChatBackend.shapedBelt(from: belt, shape: shape)
            #expect(shaped.map { $0.name } == ["createReminder", "createCalendarEvent"])
            #expect((shaped[0] as? ReminderCreateTool)?.description == ReminderCreateTool.scopedDescription196)
            #expect((shaped[1] as? CalendarEventTool)?.description == belt[1].description)
        }
        // The scoped text names the boundary in both directions.
        #expect(ReminderCreateTool.scopedDescription196.contains("only when the user asks to be reminded"))
        #expect(ReminderCreateTool.scopedDescription196.contains("never for requests to write, compose, or answer"))
    }

    // MARK: Decomposition cells (#196 third battery)

    /// A four-tool belt with one read tool and all three action tools, in
    /// belt order — the smallest surface the readonly/noschema treatments
    /// can be verified against without framework entitlements (every store
    /// is constructed inside `call()`, so assembly is inert).
    @MainActor
    private func decompositionBelt() -> [any Tool] {
        let relay = ToolEventRelay()
        let confirmations = ToolConfirmationCenter()
        return [
            DeviceStatusTool(relay: relay),
            ReminderCreateTool(relay: relay, confirmations: confirmations),
            CalendarEventTool(relay: relay, confirmations: confirmations),
            AlarmTool(relay: relay, confirmations: confirmations, alarmService: AlarmService()),
        ]
    }

    @Test func batteryRunsTheFourCureCells() {
        // The fourth battery's cell list — control, both payload candidates,
        // and the routed production candidate. Battery-2/-3 cells stay in
        // the enum (picker-reachable) but no longer burn trials.
        #expect(LocalChatBackend.batteryCells == [
            .armed, .toollessLic, .toollessLic2, .armedRouted,
        ])
    }

    // MARK: Cure cells (#196 battery 4)

    @Test func lic2InstructionsCarryTheTwoCanaryFixesOnTheLicensedBareBranch() {
        let lic = LocalChatBackend.instructionsText(
            for: .toollessLic, deviceContext: "Device: test.",
            date: Self.shapeDate, hasTools: true
        )
        let lic2 = LocalChatBackend.instructionsText(
            for: .toollessLic2, deviceContext: "Device: test.",
            date: Self.shapeDate, hasTools: true
        )
        // The two device-observed canary fixes, present only in lic2:
        // the math/facts license (third battery: the bare branch denies
        // arithmetic; licensing covered writing, not calculation)…
        #expect(!lic.contains("Simple math"))
        #expect(lic2.contains("Simple math and everyday factual questions you answer directly yourself."))
        // …and the output-format mandate (the degenerate response_format
        // JSON wrapper artifact, Apple template convention).
        #expect(lic2.contains("Reply in plain conversational prose — never JSON, XML, code blocks, or tool syntax unless the user asks for them."))
        // Still the licensed BARE branch: the licensing sentence and the
        // honesty caveat survive, and no armed clause leaks in.
        #expect(lic2.contains("needs no internet or lookup"))
        #expect(lic2.contains("You have no internet access and no external tools in this mode"))
        #expect(lic2.contains("say so plainly instead of guessing"))
        #expect(!lic2.contains("Use the tools"))
        #expect(!lic2.contains("confirmation card"))
    }

    @Test func routedShapeSpeaksProductionArmedOnItsArmedHalf() {
        // armed-routed's instructionsText(for:) is the ARMED half — the
        // toolless half is resolved by the live routing gates and the
        // battery's per-trial route, both of which return the
        // toolless-lic2 text instead. The armed half must be production
        // verbatim (the router adds no prose to armed turns).
        let production = LocalChatBackend.instructionsText(
            deviceContext: "Device: test.", date: Self.shapeDate, hasTools: true
        )
        let routed = LocalChatBackend.instructionsText(
            for: .armedRouted, deviceContext: "Device: test.",
            date: Self.shapeDate, hasTools: true
        )
        #expect(routed == production)
    }

    @Test @MainActor func promotionResolvesTheDefaultShapeToArmedRouted() {
        // #196 promotion (2026-07-28): the launch-scoped resolution — env,
        // then persisted picker, then DEFAULT — must land on armed-routed
        // when nothing overrides. Recomputed from the same inputs the
        // static reads, so the pin holds on any machine regardless of
        // ambient sim state.
        let expected: LocalChatBackend.SessionShape = {
            if let raw = ProcessInfo.processInfo.environment["TALARIA_SESSION_SHAPE"],
               let shape = LocalChatBackend.SessionShape(rawValue: raw) {
                return shape
            }
            if let raw = UserDefaults.standard.string(forKey: "debug.sessionShape"),
               let shape = LocalChatBackend.SessionShape(rawValue: raw) {
                return shape
            }
            return .armedRouted
        }()
        #expect(LocalChatBackend.activeSessionShape == expected)
        // DEBUG semantics of the production gate: routing is enabled
        // exactly when the launch shape IS the routed shape, so legacy
        // cells (armed control included) never route.
        #expect(LocalChatBackend.turnRoutingEnabled
            == (LocalChatBackend.activeSessionShape == .armedRouted))
    }

    @Test func promotedRoutedToollessTurnSpeaksExactlyTheMeasuredLic2Text() {
        // The promoted production branch calls the lic2 flag directly
        // (no SessionShape in Release) — it must produce byte-identical
        // text to the toolless-lic2 cell the battery measured at 60/60.
        let direct = LocalChatBackend.instructionsText(
            deviceContext: "Device: test.", date: Self.shapeDate,
            hasTools: false, hasImageTools: false,
            includeToollessLic2Clause: true
        )
        let cell = LocalChatBackend.instructionsText(
            for: .toollessLic2, deviceContext: "Device: test.", date: Self.shapeDate
        )
        #expect(direct == cell)
    }

    @Test func routerConstantsPinTheMeasuredWinningShape() {
        // The few-shot framing is the ONLY one that cleared the Mac-host
        // probe grid (200/200 at n=20): both polarities exampled, the
        // creative-verb confusion countered explicitly.
        let instructions = LocalChatBackend.toolIntentRouterInstructions
        #expect(instructions.contains("\"Write a haiku about rain\" -> needsDeviceTool: false"))
        #expect(instructions.contains("\"Remind me to call Shelley tomorrow\" -> needsDeviceTool: true"))
        #expect(instructions.contains("answerable with words alone"))
        // Deterministic and tiny: greedy decode, hard token cap.
        let options = LocalChatBackend.toolIntentRouterOptions
        #expect(options.samplingMode == .greedy)
        #expect(options.maximumResponseTokens == 64)
    }

    @Test @MainActor func readonlyBeltRemovesExactlyTheThreeActionTools() {
        let belt = decompositionBelt()
        // armed-readonly: grabs must die structurally — there is no action
        // tool to grab. The read tool survives in place.
        let shaped = LocalChatBackend.shapedBelt(from: belt, shape: .armedReadonly)
        #expect(shaped.map { $0.name } == ["deviceStatus"])
        // The control keeps the full belt untouched, in order.
        let control = LocalChatBackend.shapedBelt(from: belt, shape: .armed)
        #expect(control.map { $0.name } == ["deviceStatus", "createReminder", "createCalendarEvent", "scheduleAlarm"])
    }

    @Test @MainActor func shapedBeltIsTheIdentityForEveryUntreatedShape() {
        // Derived from allCases, not an enumerated list, so a future cell
        // can never dodge this pin: every shape without a declared belt
        // treatment must pass the belt through untouched — same names,
        // same order, production descriptions, schema gates open.
        let belt = decompositionBelt()
        let treated: Set<LocalChatBackend.SessionShape> = [.armedRemfix, .armedFix, .armedReadonly, .armedNoschema]
        for shape in LocalChatBackend.SessionShape.allCases where !treated.contains(shape) {
            let identity = LocalChatBackend.shapedBelt(from: belt, shape: shape)
            #expect(identity.map { $0.name } == belt.map { $0.name })
            #expect(identity.allSatisfy { $0.includesSchemaInInstructions })
            #expect((identity[1] as? ReminderCreateTool)?.description == ReminderCreateTool.productionDescription)
        }
    }

    @Test @MainActor func noschemaBeltHidesOnlyTheActionToolSchemas() {
        let belt = decompositionBelt()
        // Production pin: every tool ships with the schema gate OPEN — the
        // action tools' stored-var seam defaults to the framework default,
        // so the shipping belt is byte-identical with the seam in place.
        for tool in belt {
            #expect(tool.includesSchemaInInstructions)
        }
        let shaped = LocalChatBackend.shapedBelt(from: belt, shape: .armedNoschema)
        // Same tools, same order — still registered, still callable.
        #expect(shaped.map { $0.name } == belt.map { $0.name })
        // The three action tools hide their schemas from the instructions…
        #expect((shaped[1] as? ReminderCreateTool)?.includesSchemaInInstructions == false)
        #expect((shaped[2] as? CalendarEventTool)?.includesSchemaInInstructions == false)
        #expect((shaped[3] as? AlarmTool)?.includesSchemaInInstructions == false)
        // …with every other surface untouched (single-variable discipline).
        #expect(shaped[1].description == ReminderCreateTool.productionDescription)
        #expect(shaped[0].includesSchemaInInstructions)
        // And the held remfix treatment stays single-variable too: its belt
        // never flips the schema gate.
        let remfix = LocalChatBackend.shapedBelt(from: belt, shape: .armedRemfix)
        #expect(remfix.allSatisfy { $0.includesSchemaInInstructions })
    }

    @Test func frameworkDefaultInjectsSchemasIntoInstructions() {
        // A bare `Tool` conformance that does NOT declare
        // `includesSchemaInInstructions` reads the FRAMEWORK's default. The
        // action tools' stored-var seam defaults `true` on the claim that
        // this matches the SDK — if an SDK rev ever flips it, this test
        // screams instead of the shipping belt silently changing shape.
        #expect(SchemaGateProbeTool().includesSchemaInInstructions)
    }

    @Test func nocallOptionsDisallowToolCallsAndChangeNothingElse() {
        let base = LocalChatBackend.chatGenerationOptions(for: .onDevice)
        let shaped = LocalChatBackend.shapedGenerationOptions(base, shape: .armedNocall)
        // armed-nocall: schemas stay in context, calling is impossible —
        // the per-turn-routing ship path's proof cell.
        #expect(shaped.toolCallingMode == .disallowed)
        #expect(shaped.temperature == base.temperature)
        #expect(shaped.samplingMode == base.samplingMode)
        #expect(shaped.maximumResponseTokens == base.maximumResponseTokens)
        // Identity for every other shape — armed stays byte-identical
        // production, and no other cell touches decode-time availability.
        // allCases-derived, so a future cell can't slip past the pin.
        for shape in LocalChatBackend.SessionShape.allCases where shape != .armedNocall {
            #expect(LocalChatBackend.shapedGenerationOptions(base, shape: shape) == base)
        }
    }

    @Test func decompositionCellInstructionsAreProductionVerbatimOrAbsent() {
        let production = LocalChatBackend.instructionsText(
            deviceContext: "Device: test.", date: Self.shapeDate, hasTools: true
        )
        // Belt/options treatments carry the production instructions
        // VERBATIM — the treatment is structural, never prose.
        for shape in [LocalChatBackend.SessionShape.armedReadonly, .armedNocall, .armedNoschema] {
            let text = LocalChatBackend.instructionsText(
                for: shape, deviceContext: "Device: test.",
                date: Self.shapeDate, hasTools: true
            )
            #expect(text == production)
        }
        // The -noinstr cells pass NO instructions at all: empty text backs
        // `passesInstructions == false`, and the session is built without
        // the instructions parameter (battery) / without an instructions
        // transcript entry (live path).
        for shape in [LocalChatBackend.SessionShape.armedNoinstr, .toollessNoinstr] {
            #expect(!shape.passesInstructions)
            let text = LocalChatBackend.instructionsText(
                for: shape, deviceContext: "Device: test.",
                date: Self.shapeDate, hasTools: true
            )
            #expect(text.isEmpty)
        }
        // Every other cell still hands the session instructions
        // (allCases-derived, airtight against future cells).
        for shape in LocalChatBackend.SessionShape.allCases
        where shape != .armedNoinstr && shape != .toollessNoinstr {
            #expect(shape.passesInstructions)
            let text = LocalChatBackend.instructionsText(
                for: shape, deviceContext: "Device: test.",
                date: Self.shapeDate, hasTools: true
            )
            #expect(!text.isEmpty)
        }
    }

    // MARK: Vision-tool availability gating (#176)

    /// The SHIPPING read belt, filtered the way `LocalChatBackend` filters it.
    /// Deliberately the real `makeReadTools` output rather than a stand-in —
    /// the gate is only worth anything if it acts on what actually ships.
    /// Every tool's framework store (HealthKit, EventKit, Contacts) is
    /// constructed inside `call()`, so assembling the belt is inert here.
    @MainActor
    private func offeredNames(hasImageInContext: Bool) -> [String] {
        let belt = DeviceToolBelt.makeReadTools(
            relay: ToolEventRelay(),
            conversationProvider: { nil },
            sessionCacheProvider: { [] },
            spotlightEnabledProvider: { false }
        )
        return DeviceToolBelt.offeredTools(from: belt, hasImageInContext: hasImageInContext).map(\.name)
    }

    @Test @MainActor func visionToolsAreWithheldWhenNoImageIsInContext() {
        // The structural half of #176: the model cannot pick what it is not
        // given. A haiku prompt is never offered an OCR tool.
        let offered = offeredNames(hasImageInContext: false)
        #expect(!offered.contains("readImageText"))
        #expect(!offered.contains("readBarcode"))
    }

    @Test @MainActor func visionToolsAreOfferedWhenAnImageIsInContext() {
        let offered = offeredNames(hasImageInContext: true)
        #expect(offered.contains("readImageText"))
        #expect(offered.contains("readBarcode"))
    }

    @Test @MainActor func gatingRemovesOnlyTheVisionToolsAndPreservesBeltOrder() {
        // #176 narrows selection; it does not redesign the belt. The 4-call
        // health/motion turn that prompted the item was APPROPRIATE — every
        // non-vision tool must survive the gate untouched, in place.
        let armed = offeredNames(hasImageInContext: true)
        let gated = offeredNames(hasImageInContext: false)
        #expect(gated == armed.filter { $0 != "readImageText" && $0 != "readBarcode" })
        #expect(gated.count == armed.count - 2)
        for survivor in ["readHealth", "readMotion", "currentLocation", "searchConversations"] {
            #expect(gated.contains(survivor))
        }
    }

    @Test @MainActor func everyOfferedToolKeepsItsNameAndDescription() {
        // Description tightening must not cost a tool its schema surface —
        // the belt still serializes with or without the gate.
        for hasImage in [true, false] {
            let belt = DeviceToolBelt.makeReadTools(
                relay: ToolEventRelay(),
                conversationProvider: { nil },
                sessionCacheProvider: { [] },
                spotlightEnabledProvider: { false }
            )
            for tool in DeviceToolBelt.offeredTools(from: belt, hasImageInContext: hasImage) {
                #expect(!tool.name.isEmpty)
                #expect(!tool.description.isEmpty)
            }
        }
    }

    // MARK: Image presence (#176)

    private func imageAttachment(
        thumbnailBase64: String? = nil,
        localStoragePath: String? = nil
    ) -> MessageAttachment {
        MessageAttachment(
            kind: "image",
            fileName: "shot.png",
            mimeType: "image/png",
            thumbnailBase64: thumbnailBase64,
            localStoragePath: localStoragePath
        )
    }

    @Test @MainActor func hasImageIsFalseForATextOnlyConversation() {
        let convo = conversation(withMessages: [(.user, "Write a haiku about rain.")])
        #expect(!ConversationImageSource.hasImage(in: convo))
    }

    @Test @MainActor func hasImageIsFalseForNilConversation() {
        #expect(!ConversationImageSource.hasImage(in: nil))
    }

    @Test @MainActor func hasImageSeesAThumbnailBackedAttachment() {
        var convo = conversation(withMessages: [(.user, "what does this say?")])
        convo.messages[0].attachments = [imageAttachment(thumbnailBase64: "Zm9v")]
        #expect(ConversationImageSource.hasImage(in: convo))
    }

    @Test @MainActor func hasImageSeesAnAttachmentWhoseBytesAreStillOnDisk() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("t27-176-\(UUID().uuidString).png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        var convo = conversation(withMessages: [(.user, "read this")])
        convo.messages[0].attachments = [imageAttachment(localStoragePath: url.path)]
        #expect(ConversationImageSource.hasImage(in: convo))
    }

    @Test @MainActor func hasImageIsFalseWhenTheImageBytesAreGone() {
        // A staged image whose file was reaped leaves a record but nothing to
        // read — offering OCR for it buys the model a dead end.
        var convo = conversation(withMessages: [(.user, "read this")])
        convo.messages[0].attachments = [
            imageAttachment(localStoragePath: "/var/tmp/t27-176-definitely-not-here.png")
        ]
        #expect(!ConversationImageSource.hasImage(in: convo))
    }

    @Test @MainActor func hasImageIgnoresNonImageAttachments() {
        var convo = conversation(withMessages: [(.user, "here are my notes")])
        convo.messages[0].attachments = [
            MessageAttachment(
                kind: "file",
                fileName: "notes.txt",
                mimeType: "text/plain",
                thumbnailBase64: "Zm9v",
                localStoragePath: nil
            )
        ]
        #expect(!ConversationImageSource.hasImage(in: convo))
    }

    @Test @MainActor func hasImageSeesTheIncomingTurnBeforeItLandsInHistory() {
        // The ordering trap this gate has to clear: every send path prepares
        // the session BEFORE appending the user turn, so a gate reading only
        // stored history would withhold OCR on the exact turn that attaches
        // the image — the tool's primary use case.
        let pending = PendingAttachment(
            kind: .image,
            fileName: "receipt.jpg",
            mimeType: "image/jpeg",
            data: Data([0xFF, 0xD8]),
            localStoragePath: nil,
            thumbnailData: nil
        )
        #expect(ConversationImageSource.hasImage(in: nil, incoming: [pending]))
        #expect(!ConversationImageSource.hasImage(in: nil, incoming: []))
    }

    @Test @MainActor func hasImageIgnoresIncomingNonImageAttachments() {
        let pending = PendingAttachment(
            kind: .file,
            fileName: "notes.txt",
            mimeType: "text/plain",
            data: Data("hello".utf8),
            localStoragePath: nil,
            thumbnailData: nil
        )
        #expect(!ConversationImageSource.hasImage(in: nil, incoming: [pending]))
    }

    // MARK: Vision-tool descriptions (#176)

    @Test @MainActor func visionToolDescriptionsStateWhenTheyApply() {
        // Gating covers "no image anywhere". This covers the other half: an
        // image from twenty turns ago keeps the tools offered, so each one
        // has to say what it is FOR, not just what it does.
        let ocr = ImageTextTool(relay: ToolEventRelay(), conversationProvider: { nil })
        #expect(ocr.description.localizedCaseInsensitiveContains("only"))
        let barcode = BarcodeReaderTool(relay: ToolEventRelay(), conversationProvider: { nil })
        #expect(barcode.description.localizedCaseInsensitiveContains("only"))
    }

    @Test @MainActor func conversationSearchDescriptionStatesWhenItApplies() {
        // #176B Part B: the selector searched the literal string "2+2"
        // because the old description read like a general memory tool. The
        // corrected text follows the #148 pattern — when it applies (finding
        // a specific past mention), and that the recent thread needs no tool.
        let search = ConversationSearchTool(
            relay: ToolEventRelay(),
            conversationProvider: { nil },
            sessionCacheProvider: { [] },
            spotlightEnabledProvider: { false }
        )
        #expect(search.description.localizedCaseInsensitiveContains("only"))
        #expect(search.description.localizedCaseInsensitiveContains("past"))
        #expect(search.description.contains("without any tool"))
    }

    // MARK: Battery mutex (#200B)

    /// The 2026-07-28 destall run was contaminated by TWO concurrent
    /// battery loops: the guard lived in the Diagnostics view's @State,
    /// which resets when the view is recreated mid-run — so a second tap
    /// started a parallel loop sharing the static trial tag and recorder
    /// (interleaved cells, cross-attributed tool calls, an FM -1/1001
    /// error storm from model contention). The mutex is backend-owned:
    /// one battery at a time, whatever the UI thinks.
    @Test @MainActor func batteryMutexAdmitsOneRunAtATime() {
        // Isolate from any state another test left behind.
        LocalChatBackend.endBatteryRun()

        #expect(LocalChatBackend.beginBatteryRun())
        // A second begin while active must be refused.
        #expect(!LocalChatBackend.beginBatteryRun())
        LocalChatBackend.endBatteryRun()
        // Released — the next run may begin.
        #expect(LocalChatBackend.beginBatteryRun())
        LocalChatBackend.endBatteryRun()
    }

    // MARK: Destall treatment cells (#200B)

    /// The de-stalled description is a measured artifact: production text
    /// plus the create-immediately clause. Pinned so the battery measures
    /// what the dispatch names.
    @Test func destalledDescriptionExtendsProductionWithTheNoAskClause() {
        let destalled = ReminderCreateTool.destalledDescription200
        #expect(destalled.hasPrefix(ReminderCreateTool.productionDescription))
        #expect(destalled.contains("never ask"))
        #expect(destalled != ReminderCreateTool.productionDescription)
    }

    /// The guidefix copy must be indistinguishable from production except
    /// for text: same tool name, production description by default (the
    /// @Guide delta is the cell's ONLY change; bothfix passes the
    /// destalled description explicitly).
    @Test @MainActor func guidefixCopySharesNameAndProductionDescription() {
        let copy = ReminderCreateToolGuidefix(
            relay: ToolEventRelay(),
            confirmations: ToolConfirmationCenter()
        )
        #expect(copy.name == "createReminder")
        #expect(copy.description == ReminderCreateTool.productionDescription)
    }

    /// The battery's belt swap per treatment cell: identity for the
    /// control; guidefix swaps in the copy struct (production description);
    /// toolfix keeps the production struct with the destalled description;
    /// bothfix is the copy struct WITH the destalled description. Belt
    /// size and every other tool's identity never change.
    @Test @MainActor func destallBeltSwapsOnlyTheReminderTool() {
        let relay = ToolEventRelay()
        let confirmations = ToolConfirmationCenter()
        let belt = DeviceToolBelt.makeActionTools(
            relay: relay, confirmations: confirmations, alarmService: AlarmService()
        )

        let control = LocalChatBackend.destallBelt(from: belt, cell: .armed)
        #expect(control.map(\.name) == belt.map(\.name))
        #expect(control.first { $0.name == "createReminder" }?.description == ReminderCreateTool.productionDescription)
        #expect(control.contains { $0 is ReminderCreateTool })

        let guidefix = LocalChatBackend.destallBelt(from: belt, cell: .armedGuidefix)
        #expect(guidefix.map(\.name) == belt.map(\.name))
        #expect(guidefix.contains { $0 is ReminderCreateToolGuidefix })
        #expect(guidefix.first { $0.name == "createReminder" }?.description == ReminderCreateTool.productionDescription)

        let toolfix = LocalChatBackend.destallBelt(from: belt, cell: .armedToolfix)
        #expect(toolfix.map(\.name) == belt.map(\.name))
        #expect(toolfix.contains { $0 is ReminderCreateTool })
        #expect(toolfix.first { $0.name == "createReminder" }?.description == ReminderCreateTool.destalledDescription200)

        let bothfix = LocalChatBackend.destallBelt(from: belt, cell: .armedBothfix)
        #expect(bothfix.map(\.name) == belt.map(\.name))
        #expect(bothfix.contains { $0 is ReminderCreateToolGuidefix })
        #expect(bothfix.first { $0.name == "createReminder" }?.description == ReminderCreateTool.destalledDescription200)
    }

    /// Cell raw values are the record/export labels — the classification
    /// grammar's vocabulary. Pinned.
    @Test func destallCellLabelsMatchTheDispatch() {
        #expect(LocalChatBackend.ActionBatteryCell.armed.rawValue == "armed")
        #expect(LocalChatBackend.ActionBatteryCell.armedGuidefix.rawValue == "armed-guidefix")
        #expect(LocalChatBackend.ActionBatteryCell.armedToolfix.rawValue == "armed-toolfix")
        #expect(LocalChatBackend.ActionBatteryCell.armedBothfix.rawValue == "armed-bothfix")
        #expect(LocalChatBackend.ActionBatteryCell.armedInstrfix.rawValue == "armed-instrfix")
        #expect(LocalChatBackend.ActionBatteryCell.armedToolmode.rawValue == "armed-toolmode")
        #expect(LocalChatBackend.ActionBatteryCell.armedScoped.rawValue == "armed-scoped")
        #expect(LocalChatBackend.ActionBatteryCell.armedCreateonly.rawValue == "armed-createonly")
        #expect(LocalChatBackend.ActionBatteryCell.armedFindfix.rawValue == "armed-findfix")
        #expect(LocalChatBackend.ActionBatteryCell.armedSpiralfix.rawValue == "armed-spiralfix")
        #expect(LocalChatBackend.ActionBatteryCell.armedStrikefix.rawValue == "armed-strikefix")
        #expect(LocalChatBackend.ActionBatteryCell.armedCardfix.rawValue == "armed-cardfix")
        #expect(LocalChatBackend.ActionBatteryCell.armedDatefix.rawValue == "armed-datefix")
        #expect(LocalChatBackend.ActionBatteryCell.armedCardrollback.rawValue == "armed-cardrollback")
        #expect(LocalChatBackend.ActionBatteryCell.armedDeadendfix.rawValue == "armed-deadendfix")
        #expect(LocalChatBackend.ActionBatteryCell.armedGrabfix.rawValue == "armed-grabfix")
        #expect(LocalChatBackend.ActionBatteryCell.armedStallfix.rawValue == "armed-stallfix")
        #expect(LocalChatBackend.ActionBatteryCell.armedSchemafix.rawValue == "armed-schemafix")
        #expect(LocalChatBackend.ActionBatteryCell.armedSchemarollback.rawValue == "armed-schemarollback")
        #expect(LocalChatBackend.ActionBatteryCell.allCases.count == 19)
    }

    // MARK: Structural de-stall via tool-calling mode (#200E)

    /// The toolmode cell is an OPTIONS treatment only — belt AND
    /// instructions are production; the sole seam is the per-request
    /// tool-calling mode. Belt identity pinned here (instructions identity
    /// is structural: the cell takes runActionBattery's non-instrfix
    /// branch, the production text).
    @Test @MainActor func toolmodeBeltIsProductionIdentity() {
        let belt = DeviceToolBelt.makeActionTools(
            relay: ToolEventRelay(), confirmations: ToolConfirmationCenter(),
            alarmService: AlarmService()
        )
        let toolmode = LocalChatBackend.destallBelt(from: belt, cell: .armedToolmode)
        #expect(toolmode.map(\.name) == belt.map(\.name))
        #expect(toolmode.contains { $0 is ReminderCreateTool })
        #expect(toolmode.first { $0.name == "createReminder" }?.description == ReminderCreateTool.productionDescription)
    }

    /// The demote exit is MANDATORY: `.required` loops "until a Tool
    /// throws an error or this value is changed dynamically" (beta-4 doc
    /// comment; WWDC26/242 exit pattern). The cell's mode function is
    /// Apple's own: required until the first tool call, allowed after.
    /// A regression here re-arms the infinite-loop hazard.
    @Test func toolmodeDemoteExitMatchesApplesPattern() {
        #expect(LocalChatBackend.toolmodeMode(after: 0) == .required)
        #expect(LocalChatBackend.toolmodeMode(after: 1) == .allowed)
        #expect(LocalChatBackend.toolmodeMode(after: 7) == .allowed)
    }

    // MARK: Community-destall cells (#200F)

    /// The community battery's cell list — promoted-production control
    /// plus the three survey-derived treatments, in dispatch order.
    @Test func communityBatteryRunsTheFourSurveyCells() {
        #expect(LocalChatBackend.communityBatteryCells == [
            .armed, .armedScoped, .armedCreateonly, .armedFindfix,
        ])
    }

    /// The SHIPPING armed belt as the battery assembles it: the read
    /// belt (vision-gated off — no image in context) then the action
    /// belt, matching AppContainer's construction order.
    @MainActor
    private func fullArmedBelt() -> [any Tool] {
        let relay = ToolEventRelay()
        var belt = DeviceToolBelt.makeReadTools(
            relay: relay,
            conversationProvider: { nil },
            sessionCacheProvider: { [] },
            spotlightEnabledProvider: { false }
        )
        belt += DeviceToolBelt.makeActionTools(
            relay: relay, confirmations: ToolConfirmationCenter(), alarmService: AlarmService()
        )
        return DeviceToolBelt.offeredTools(from: belt, hasImageInContext: false)
    }

    /// Apple's guidance is 3–5 active tools per request (the armed belt
    /// is 13). The scoped cell keeps each intent's create tool plus its
    /// same-domain reads; createonly removes the same-domain read — no
    /// readReminders to flee into (#200E: the forced first call was
    /// readReminders 10/10; find-first is model-baked). Alarm has no
    /// same-domain read, so its two cells coincide. Haiku rides the
    /// REMIND scope — the worst-case misroute canary. Belt order is
    /// preserved (filter, never reorder).
    @Test @MainActor func scopedBeltMatchesTheDispatchPerIntent() {
        let belt = fullArmedBelt()
        #expect(belt.map(\.name) == [
            "readHealth", "currentLocation", "readMotion", "readCalendar",
            "readReminders", "currentWeather", "searchPlaces", "lookupContact",
            "deviceStatus", "searchConversations",
            "createReminder", "createCalendarEvent", "scheduleAlarm",
        ])

        func names(_ cell: LocalChatBackend.ActionBatteryCell, _ tag: String) -> [String] {
            LocalChatBackend.scopedBelt(from: belt, cell: cell, promptTag: tag).map(\.name)
        }
        // scoped: same-domain reads IN.
        #expect(names(.armedScoped, "remind") == ["readCalendar", "readReminders", "createReminder"])
        #expect(names(.armedScoped, "alarm") == ["readCalendar", "scheduleAlarm"])
        #expect(names(.armedScoped, "calendar") == ["currentLocation", "readCalendar", "createCalendarEvent"])
        #expect(names(.armedScoped, "haiku") == names(.armedScoped, "remind"))
        // createonly: the same-domain read is GONE.
        #expect(names(.armedCreateonly, "remind") == ["readCalendar", "createReminder"])
        #expect(names(.armedCreateonly, "alarm") == ["readCalendar", "scheduleAlarm"])
        #expect(names(.armedCreateonly, "calendar") == ["currentLocation", "createCalendarEvent"])
        #expect(names(.armedCreateonly, "haiku") == names(.armedCreateonly, "remind"))
    }

    /// Scoping is those two cells' ONLY seam: every other cell passes
    /// through identity whatever the prompt — findfix keeps the full
    /// production belt (its treatment is instructions).
    @Test @MainActor func scopedBeltIsIdentityForEveryOtherCell() {
        let belt = fullArmedBelt()
        for cell in LocalChatBackend.ActionBatteryCell.allCases
        where cell != .armedScoped && cell != .armedCreateonly {
            for tag in ["remind", "alarm", "calendar", "haiku"] {
                #expect(LocalChatBackend.scopedBelt(from: belt, cell: cell, promptTag: tag).map(\.name) == belt.map(\.name))
            }
        }
    }

    /// #200G (PROMOTED 2026-07-29, #200F verdict, corded run @ a656004):
    /// the find-first carve-out is production — remind 9/10 vs 1/10
    /// control (lifetime control 1/60), find-first killed outright (ZERO
    /// readReminders calls in the cell's remind trials). The flag stays
    /// as the rollback/re-measure seam: explicit `false` reproduces the
    /// pre-promotion text. (A rollback flips exactly this pin back.)
    @Test func findFirstCarveoutIsProductionDefaultAndRemovable() {
        let production = LocalChatBackend.instructionsText(
            deviceContext: "Device: test.", hasTools: true
        )
        // The promoted carve-out, verbatim, at its measured seam: after
        // the de-stall clause, before honesty-and-recovery.
        // #200K: the card clause now follows the carve-out in production,
        // so this seam ends at it rather than at honesty-and-recovery.
        #expect(production.contains("leave optional fields empty and the defaults apply. 'Remind me' means create the reminder — do not search existing reminders first. Reminders and calendar events are different tools — prefer a reminder when the user asks to be reminded. The confirmation card is shown automatically"))
        // Explicit true is identity with the default — the #200F treated
        // cell now measures production.
        let explicitOn = LocalChatBackend.instructionsText(
            deviceContext: "Device: test.", hasTools: true,
            includeFindFirstCarveout: true
        )
        #expect(explicitOn == production)
        // The rollback seam: explicit false removes exactly the two
        // sentences and nothing else — the neighboring de-stall clause
        // and honesty-and-recovery close back up.
        let rollback = LocalChatBackend.instructionsText(
            deviceContext: "Device: test.", hasTools: true,
            includeFindFirstCarveout: false
        )
        #expect(rollback != production)
        #expect(!rollback.contains("'Remind me'"))
        #expect(rollback.contains("leave optional fields empty and the defaults apply. The confirmation card is shown automatically"))
        // The carve-out never reaches the toolless branch.
        let bare = LocalChatBackend.instructionsText(
            deviceContext: "Device: test.", hasTools: false
        )
        #expect(!bare.contains("'Remind me'"))
    }

    // MARK: Calendar-spiral cells (#200H, reworded #200I)

    /// The spiral battery's cell list — promoted-production control plus
    /// the two treatment seams, in dispatch order.
    @Test func spiralBatteryRunsTheThreeCells() {
        #expect(LocalChatBackend.spiralBatteryCells == [
            .armed, .armedSpiralfix, .armedStrikefix,
        ])
    }

    /// #200I: the spiralfix re-measure drops strikefix — that cell is
    /// parked until its tally instrument is proven (#200H emits were
    /// anomalous and no third strike ever came due), and re-running it
    /// would spend a third of the trials on a treatment that cannot
    /// engage. Control plus the reworded carve-out, nothing else.
    @Test func spiralfixBatteryRunsTheControlAndTheCarveoutOnly() {
        #expect(LocalChatBackend.spiralfixBatteryCells == [
            .armed, .armedSpiralfix,
        ])
    }

    /// #200H spiralfix: the lookup-spiral carve-out — the identity-hunt
    /// sentence and the location-misbinding sentence — rides a flag that
    /// is OFF by default; flag-off is production byte-identical. Flag-on
    /// adds exactly the two sentences at the measured seam: after the
    /// find-first carve-out, before honesty-and-recovery.
    ///
    /// #200I rewords sentence 1 EVENT-SCOPED. The v1 phrasing ("an event
    /// or reminder") tamed the calendar spiral (9/10, best ever) but bled
    /// across intents — grabs doubled and remind sagged, because a
    /// sentence naming reminders reads as guidance about reminders. The
    /// treatment now names only the event path it was measured on, and
    /// "before creating the event" states the create as the destination
    /// rather than merely forbidding the search.
    @Test func lookupSpiralCarveoutIsOffByDefaultAndSitsAfterTheFindFirstCarveout() {
        let production = LocalChatBackend.instructionsText(
            deviceContext: "Device: test.", hasTools: true
        )
        #expect(!production.contains("identify them before creating the event"))
        let explicitOff = LocalChatBackend.instructionsText(
            deviceContext: "Device: test.", hasTools: true,
            includeLookupSpiralCarveout: false
        )
        #expect(explicitOff == production)
        let treated = LocalChatBackend.instructionsText(
            deviceContext: "Device: test.", hasTools: true,
            includeLookupSpiralCarveout: true
        )
        #expect(treated.contains("prefer a reminder when the user asks to be reminded. A person's name in an event title is just part of the title — never search contacts, conversations, or places to identify them before creating the event. Only include an event location the user themselves gave; a place search result is never the location. The confirmation card is shown automatically"))
        // The v1 cross-intent phrasing is GONE, not merely reordered —
        // that word is the whole #200I hypothesis.
        #expect(!treated.contains("event or reminder"))
        // The carve-out rides the armed capabilities paragraph only.
        let bare = LocalChatBackend.instructionsText(
            deviceContext: "Device: test.", hasTools: false,
            includeLookupSpiralCarveout: true
        )
        #expect(!bare.contains("identify them before creating the event"))
    }

    // MARK: The narrated confirmation card (#200J)

    /// #200J: control vs the card-narration clause, nothing else. The
    /// treatment's whole claim is about the remind path, but all four
    /// prompts run because the clause names every action tool.
    @Test func cardfixBatteryRunsTheControlAndTheClauseOnly() {
        #expect(LocalChatBackend.cardfixBatteryCells == [
            .armed, .armedCardfix,
        ])
    }

    /// #200K PROMOTION. The #200J battery killed the specimen outright —
    /// card narration occurred 3× in control (remind t2/t4/t10, all
    /// zero-tool) and ZERO times anywhere in the treatment cell's 40
    /// trials — and remind went 5/10 → 8/10, the largest single-seam gain
    /// since #200D. Default is now TRUE; explicit `false` is the pinned
    /// byte-identical rollback (a rollback flips exactly this pin back).
    @Test func cardNarrationClauseIsProductionDefaultAndRemovable() {
        let production = LocalChatBackend.instructionsText(
            deviceContext: "Device: test.", hasTools: true
        )
        // The promoted clause, verbatim, at its measured seam: after the
        // find-first carve-out, before honesty-and-recovery.
        #expect(production.contains("prefer a reminder when the user asks to be reminded. The confirmation card is shown automatically when you call an action tool — never write the card out, list the details back for approval, or ask whether to proceed; make the call and let the card do the asking. If you can't identify a person"))
        // Explicit true is identity with the default — the #200J treated
        // cell now measures production (the findfix precedent), which is
        // what makes the re-verify battery pool.
        let explicitOn = LocalChatBackend.instructionsText(
            deviceContext: "Device: test.", hasTools: true,
            includeCardNarrationClause: true
        )
        #expect(explicitOn == production)
        // The rollback seam: explicit false removes exactly this sentence
        // and nothing else — the carve-out and honesty close back up.
        let rollback = LocalChatBackend.instructionsText(
            deviceContext: "Device: test.", hasTools: true,
            includeCardNarrationClause: false
        )
        #expect(rollback != production)
        #expect(!rollback.contains("never write the card out"))
        #expect(rollback.contains("prefer a reminder when the user asks to be reminded. If you can't identify a person"))
        // The clause never reaches the toolless branch.
        let bare = LocalChatBackend.instructionsText(
            deviceContext: "Device: test.", hasTools: false
        )
        #expect(!bare.contains("never write the card out"))
    }

    /// #200K datefix: #200J's residual remind misses were BOTH zero-tool
    /// date interrogations ("Could you clarify the due date?", "a specific
    /// date or keep it open for today?") — a different disease from the
    /// card narration the promoted clause killed, and one the #200D
    /// de-stall clause does not reach: it licenses empty OPTIONAL fields,
    /// while a bare clock time reads as an AMBIGUOUS required one. The
    /// clause names the resolution instead. Off by default, flag-off
    /// byte-identical, seated after the promoted card clause.
    @Test func dayDefaultClauseIsOffByDefaultAndSitsAfterTheCardClause() {
        let production = LocalChatBackend.instructionsText(
            deviceContext: "Device: test.", hasTools: true
        )
        #expect(!production.contains("never ask which day"))
        let explicitOff = LocalChatBackend.instructionsText(
            deviceContext: "Device: test.", hasTools: true,
            includeDayDefaultClause: false
        )
        #expect(explicitOff == production)
        let treated = LocalChatBackend.instructionsText(
            deviceContext: "Device: test.", hasTools: true,
            includeDayDefaultClause: true
        )
        #expect(treated.contains("make the call and let the card do the asking. A time with no day means the next time that clock time comes around — never ask which day. If you can't identify a person"))
        let bare = LocalChatBackend.instructionsText(
            deviceContext: "Device: test.", hasTools: false,
            includeDayDefaultClause: true
        )
        #expect(!bare.contains("never ask which day"))
    }

    // MARK: The optional-field schema, PROMOTED (#200S)

    /// #200S PROMOTION. Two runs, same direction both times: remind
    /// **20/20 pooled with ZERO zero-tool stalls** vs control 17/20 with
    /// three, alarm untouched, calendar within K=3. The mechanism is the
    /// one the hypothesis named — `due` and `list` were REQUIRED by the
    /// schema while the promoted #200D clause told the model to leave them
    /// empty, and asking the user is a rational way to satisfy a required
    /// field.
    ///
    /// This pin is the promotion's proof: production `Arguments` accepts
    /// `nil` for both fields, which compiles ONLY if they are optional.
    /// #200Q's grab collapse is NOT pinned — it failed to replicate in
    /// #200R (7/10 vs 8/10) and the claim was withdrawn.
    @Test func productionReminderArgumentsAcceptOmittedDueAndList() {
        let omitted = ReminderCreateTool.Arguments(title: "Test Talaria", due: nil, list: nil)
        #expect(omitted.due == nil)
        #expect(omitted.list == nil)
        // Title stays REQUIRED: the schema should demand what the tool
        // genuinely cannot default.
        #expect(omitted.title == "Test Talaria")
    }

    /// #200S: the pinned rollback. A type change cannot ride a Bool flag,
    /// so the rollback seam is a struct — `ReminderCreateToolRequiredFields`
    /// is the pre-promotion tool verbatim (non-optional `due`/`list`),
    /// reachable as a measured cell exactly like #200L's cardrollback.
    @Test @MainActor func schemarollbackCellRestoresTheRequiredFieldTool() {
        let belt = DeviceToolBelt.makeActionTools(
            relay: ToolEventRelay(), confirmations: ToolConfirmationCenter(),
            alarmService: AlarmService()
        )
        let rolled = LocalChatBackend.destallBelt(from: belt, cell: .armedSchemarollback)
        #expect(rolled.map(\.name) == belt.map(\.name))
        #expect(rolled.contains { $0 is ReminderCreateToolRequiredFields })
        #expect(!rolled.contains { $0 is ReminderCreateTool })
        // Everything else about the tool is production, so the cell
        // measures the field types and nothing else.
        let reminder = rolled.first { $0.name == "createReminder" }
        #expect(reminder?.description == ReminderCreateTool.productionDescription)
        #expect(reminder?.includesSchemaInInstructions == true)
    }

    /// #200S: post-promotion the #200Q/#200R treated cell is production
    /// identity (the findfix/cardfix precedent), which is what lets it pool
    /// with the control as a re-verify.
    @Test @MainActor func schemafixCellIsProductionIdentityAfterThePromotion() {
        let belt = DeviceToolBelt.makeActionTools(
            relay: ToolEventRelay(), confirmations: ToolConfirmationCenter(),
            alarmService: AlarmService()
        )
        let treated = LocalChatBackend.destallBelt(from: belt, cell: .armedSchemafix)
        #expect(treated.map(\.name) == belt.map(\.name))
        #expect(treated.contains { $0 is ReminderCreateTool })
        #expect(treated.first { $0.name == "createReminder" }?.description == ReminderCreateTool.productionDescription)
    }

    /// #200S battery: the promoted control and the (now identity) treated
    /// cell pool as the production re-verify at n=20/prompt, while the
    /// rollback arm measures — within the same run — whether the promotion
    /// actually earns its place. Same shape as #200K and #200O.
    @Test func schemaReverifyBatteryPoolsTheReverifyAndTheRollback() {
        #expect(LocalChatBackend.schemaReverifyBatteryCells == [
            .armed, .armedSchemafix, .armedSchemarollback,
        ])
    }

    // MARK: The stall's structural seam (#200Q)

    /// #200Q battery: was production vs the schema swap; since the #200S
    /// promotion both arms are production, so it survives only as a
    /// pooled-production sanity battery. The rollback comparison lives in
    /// `schemaReverifyBatteryCells`.
    @Test func schemafixBatteryIsProductionVersusTheSchemaSwap() {
        #expect(LocalChatBackend.schemafixBatteryCells == [
            .armed, .armedSchemafix,
        ])
    }

    // MARK: The conserved stall (#200P)

    /// #200P: the last disease standing on the remind path. Zero-tool
    /// interrogation took 12 of 30 remind trials in #200O and it is
    /// CONSERVED — #200K's datefix closed the date question and the model
    /// started asking about the list instead, same count, different field.
    /// So this treats the CLASS, not another field.
    ///
    /// It also cannot just repeat the promoted #200D clause, which already
    /// says "never ask which list… leave optional fields empty and the
    /// defaults apply" and is demonstrably ignored ~40% of the time in a
    /// bad run. What worked in #200J was naming the CARD as the thing the
    /// model was standing in for; this names the card as the place a
    /// missing detail gets fixed, so the model has somewhere to put the
    /// question instead of asking it.
    @Test func cardCorrectionClauseIsOffByDefaultAndSitsAfterTheCarveout() {
        let production = LocalChatBackend.instructionsText(
            deviceContext: "Device: test.", hasTools: true
        )
        #expect(!production.contains("never a reason to ask first"))
        let explicitOff = LocalChatBackend.instructionsText(
            deviceContext: "Device: test.", hasTools: true,
            includeCardCorrectionClause: false
        )
        #expect(explicitOff == production)
        let treated = LocalChatBackend.instructionsText(
            deviceContext: "Device: test.", hasTools: true,
            includeCardCorrectionClause: true
        )
        #expect(treated.contains("create the event with the name exactly as the user gave it. A missing detail is never a reason to ask first — create it with the default and let the confirmation card be where the user changes it. When a tool reports"))
        let bare = LocalChatBackend.instructionsText(
            deviceContext: "Device: test.", hasTools: false,
            includeCardCorrectionClause: true
        )
        #expect(!bare.contains("never a reason to ask first"))
    }

    /// #200P battery: production vs the stall clause, two arms in one run.
    /// #200O proved cross-run comparison is worthless here — all three of
    /// its cells landed on exactly 6/10 remind on three different texts —
    /// so the control must ride in the same run, and every bar is a
    /// within-run delta.
    @Test func stallfixBatteryIsProductionVersusTheStallClause() {
        #expect(LocalChatBackend.stallfixBatteryCells == [
            .armed, .armedStallfix,
        ])
    }

    // MARK: The grab disease (#200O)

    /// #200O: grabs are now the program's largest untreated disease and
    /// the only one that has gotten WORSE as the others improved — 4/8,
    /// 4/10, 7/10, 15/20, 9/10, 9/10 across the lanes. That trend is not a
    /// coincidence: six lanes have spent their words raising
    /// create-pressure ("create it right away", "make the call", "create
    /// the event with the name as given"), and the haiku prompt is swept
    /// up in it. The specimen is the META-GRAB — a reminder whose title is
    /// the request itself ("Write a haiku about sledding"), and in #200N
    /// one trial produced both a reminder AND a calendar event for a poem.
    ///
    /// The armed paragraph already says composing "needs no tool". That is
    /// permission, and permission has never been enough in this program —
    /// #200J proved the same thing about the confirmation card. So this
    /// names the artifact instead: the writing IS the deliverable, so
    /// there is nothing left to schedule.
    @Test func compositionAnswerClauseIsOffByDefaultAndSitsAfterTheCarveout() {
        let production = LocalChatBackend.instructionsText(
            deviceContext: "Device: test.", hasTools: true
        )
        #expect(!production.contains("the writing itself is the answer"))
        let explicitOff = LocalChatBackend.instructionsText(
            deviceContext: "Device: test.", hasTools: true,
            includeCompositionAnswerClause: false
        )
        #expect(explicitOff == production)
        let treated = LocalChatBackend.instructionsText(
            deviceContext: "Device: test.", hasTools: true,
            includeCompositionAnswerClause: true
        )
        #expect(treated.contains("create the event with the name exactly as the user gave it. When the user asks you to write something, the writing itself is the answer — never also create a reminder, event, or alarm about writing it. When a tool reports"))
        let bare = LocalChatBackend.instructionsText(
            deviceContext: "Device: test.", hasTools: false,
            includeCompositionAnswerClause: true
        )
        #expect(!bare.contains("the writing itself is the answer"))
    }

    /// #200O battery: the promoted control and the (now identity)
    /// deadendfix cell pool as the production re-verify at n=20/prompt —
    /// which is what confirms the calendar promotion at a real sample
    /// size — while grabfix measures the new treatment against that pooled
    /// control in the same run. Same shape as #200K.
    @Test func grabfixBatteryPoolsTheReverifyAndTheNewTreatment() {
        #expect(LocalChatBackend.grabfixBatteryCells == [
            .armed, .armedDeadendfix, .armedGrabfix,
        ])
    }

    // MARK: The dead-end carve-out, v3 (#200M)

    /// #200M: #200L showed WHY the v2 carve-out works, and it is narrower
    /// than the sentence claims. Identity-hunt calls only fell 23 → 16
    /// (−30%) in the treated cell — the hunting continues, and one trial
    /// ran away to 20 calls (17 consecutive searchConversations) and timed
    /// out. What went to ZERO was the DEAD END: 5 "couldn't find Sam, so
    /// I'm asking instead of creating" misses in production, none in the
    /// treated cell. The carve-out converts hunt→ask into hunt→create.
    ///
    /// So v3 says only that, and pays for nothing else. v2's search
    /// prohibition is what plausibly moved the reminder path (pooled over
    /// two runs it cost remind −20 points and grabs −15), and v2's second
    /// sentence about locations is unearned: across #200J/#200K/#200L
    /// every accepted event was a bare title with NO location bound, so
    /// there was no misbinding left for it to prevent.
    /// #200O PROMOTION. Two independent runs: calendar **17/20 (85%) vs
    /// 10/19 (53%)** for production, +32 points, same direction and size
    /// both times, with Sam dead-end misses 5→~0 and 4→1 while hunt calls
    /// barely moved (23→16, 16→15) — the win is licensing the create, not
    /// forbidding the search. Remind is level pooled (18/20 vs 19/20), so
    /// #200M's one-trial miss was noise and #200N's 10/10 settled it.
    /// Default is now TRUE; explicit `false` is the pinned byte-identical
    /// rollback.
    @Test func deadEndCarveoutIsProductionDefaultAndRemovable() {
        let production = LocalChatBackend.instructionsText(
            deviceContext: "Device: test.", hasTools: true
        )
        // The promoted carve-out, verbatim, at its measured seam: after
        // the card clause, before honesty-and-recovery.
        #expect(production.contains("make the call and let the card do the asking. If you can't identify a person named in an event, that's fine — create the event with the name exactly as the user gave it. When a tool reports"))
        // Explicit true is identity with the default — the #200M/#200N
        // treated cell now measures production, which is what lets it
        // pool as a re-verify.
        let explicitOn = LocalChatBackend.instructionsText(
            deviceContext: "Device: test.", hasTools: true,
            includeDeadEndCarveout: true
        )
        #expect(explicitOn == production)
        // The rollback seam: explicit false removes exactly this sentence
        // and nothing else.
        let rollback = LocalChatBackend.instructionsText(
            deviceContext: "Device: test.", hasTools: true,
            includeDeadEndCarveout: false
        )
        #expect(rollback != production)
        #expect(!rollback.contains("create the event with the name"))
        #expect(rollback.contains("make the call and let the card do the asking. When a tool reports"))
        // The single-variable claim survives promotion: the promoted text
        // carries NO search prohibition and NO location sentence — those
        // are v2's, and v2 was retired for resurrecting find-first.
        #expect(!production.contains("never search"))
        #expect(!production.contains("place search result"))
        let bare = LocalChatBackend.instructionsText(
            deviceContext: "Device: test.", hasTools: false
        )
        #expect(!bare.contains("create the event with the name"))
    }

    /// #200N: the confirmation A/B. v3 passed 5 of 6 bars in #200M and
    /// missed remind by ONE trial (8/10 vs production's 10/10), with both
    /// misses being the known conserved stall rather than anything the
    /// carve-out introduced. That is exactly the situation the protocol
    /// exists for: the number is inside production's own historical range,
    /// so the temptation is to call it noise by eyeball — instead it gets
    /// a second independent run against a baseline that has finally held
    /// still (production calendar 5/10 twice consecutively). v2 is NOT in
    /// this battery: #200M showed it resurrects find-first, so it is
    /// retired rather than re-measured.
    @Test func deadendVerifyBatteryIsProductionVersusV3Only() {
        #expect(LocalChatBackend.deadendVerifyBatteryCells == [
            .armed, .armedDeadendfix,
        ])
    }

    /// #200M battery: production, v3, and v2 in ONE run, so v3 is measured
    /// against the version it is trying to replace rather than against a
    /// remembered number from a different run — the #200I lesson about
    /// between-run control drift, applied to treatments.
    @Test func deadendBatteryRunsProductionAndBothCarveoutVersions() {
        #expect(LocalChatBackend.deadendBatteryCells == [
            .armed, .armedDeadendfix, .armedSpiralfix,
        ])
    }

    // MARK: The calendar lane (#200L)

    /// #200L: the first cell in this program that measures a promoted
    /// clause by REMOVING it. #200K's re-verify put pooled calendar at
    /// 8/18 (44%) and post-promotion calendar at 22/37 (59%) against
    /// 21/30 (70%) for pre-promotion controls — not significant (p≈0.4)
    /// and swamped by a control that has read 7/10, 4/10, 10/10, but the
    /// direction is unfavorable and #200J's A/B pointed the same way. A
    /// suspicion this cheap to test should not be carried on trend lines.
    /// The cell IS the pinned rollback: production with the card clause
    /// explicitly off, byte-identical to the pre-#200K text.
    @Test func cardrollbackCellIsExactlyThePinnedRollbackText() {
        let rollback = LocalChatBackend.instructionsText(
            deviceContext: "Device: test.", hasTools: true,
            includeCardNarrationClause: false
        )
        let production = LocalChatBackend.instructionsText(
            deviceContext: "Device: test.", hasTools: true
        )
        #expect(rollback != production)
        #expect(!rollback.contains("never write the card out"))
        // Everything else survives the removal — the promoted #200D and
        // #200G clauses are still there, and the seam closes back up.
        #expect(rollback.contains("leave optional fields empty and the defaults apply. 'Remind me' means"))
        #expect(rollback.contains("prefer a reminder when the user asks to be reminded. If you can't identify a person"))
    }

    /// #200L battery: promoted control, the same text with the card clause
    /// removed, and the #200I spiral carve-out — one run answers "does the
    /// promoted clause cost calendar" and "does the carve-out fix the Sam
    /// dead-end" against the same baseline. All 14 classified calendar
    /// misses in #200K were that dead-end, so both questions are about the
    /// same 18 trials.
    @Test func calendarBatteryRunsTheRollbackAndTheCarveout() {
        #expect(LocalChatBackend.calendarBatteryCells == [
            .armed, .armedCardrollback, .armedSpiralfix,
        ])
    }

    /// #200K battery: the promoted control and the (now identity) cardfix
    /// cell pool as the production re-verify at n=20/prompt — which is
    /// what settles #200J's calendar guard, whose control read 7/4/10
    /// across three runs — while datefix measures the new treatment
    /// against that pooled control in the same run.
    @Test func datefixBatteryPoolsTheReverifyAndTheNewTreatment() {
        #expect(LocalChatBackend.datefixBatteryCells == [
            .armed, .armedCardfix, .armedDatefix,
        ])
    }

    /// #200J stacks below #200H's carve-out: with both flags on the spiral
    /// text comes first and the card clause follows, so neither pin's seam
    /// can drift when the other promotes.
    @Test func cardNarrationClauseFollowsTheSpiralCarveoutWhenBothAreOn() {
        let both = LocalChatBackend.instructionsText(
            deviceContext: "Device: test.", hasTools: true,
            includeLookupSpiralCarveout: true,
            includeCardNarrationClause: true
        )
        #expect(both.contains("a place search result is never the location. The confirmation card is shown automatically"))
    }

    /// #200J treats INSTRUCTIONS only — belt is production identity, the
    /// reminder tool included (its description is the seam #200B
    /// falsified, and it must stay production here).
    @Test @MainActor func cardfixBeltIsProductionIdentity() {
        let belt = DeviceToolBelt.makeActionTools(
            relay: ToolEventRelay(), confirmations: ToolConfirmationCenter(),
            alarmService: AlarmService()
        )
        let treated = LocalChatBackend.destallBelt(from: belt, cell: .armedCardfix)
        #expect(treated.map(\.name) == belt.map(\.name))
        #expect(treated.first { $0.name == "createReminder" }?.description == ReminderCreateTool.productionDescription)
    }

    /// #200H strikefix: the third-strike demote is data-derived — across
    /// #200F/#200G every healthy create used at most 2 calls of any one
    /// tool, every spiral casualty had a tool at 3+. `.allowed` until any
    /// single tool's tally reaches 3, `.disallowed` after (the model must
    /// answer with what it has). A regression here either re-opens the
    /// spiral or strangles healthy flows.
    @Test func spiralBudgetModeStrikesOnAnyToolsThirdCall() {
        #expect(LocalChatBackend.spiralBudgetMode(tally: [:]) == .allowed)
        #expect(LocalChatBackend.spiralBudgetMode(tally: ["searchConversations": 2, "readCalendar": 2]) == .allowed)
        #expect(LocalChatBackend.spiralBudgetMode(tally: ["searchConversations": 3]) == .disallowed)
        #expect(LocalChatBackend.spiralBudgetMode(tally: ["readCalendar": 1, "searchConversations": 5]) == .disallowed)
    }

    /// Both #200H cells treat OFF-belt seams — spiralfix the
    /// instructions, strikefix the tool-calling mode — so their belts are
    /// production identity (scopedBelt identity is covered for every
    /// non-scoping cell by `scopedBeltIsIdentityForEveryOtherCell`).
    @Test @MainActor func spiralCellBeltsAreProductionIdentity() {
        let belt = DeviceToolBelt.makeActionTools(
            relay: ToolEventRelay(), confirmations: ToolConfirmationCenter(),
            alarmService: AlarmService()
        )
        for cell in [LocalChatBackend.ActionBatteryCell.armedSpiralfix, .armedStrikefix] {
            let treated = LocalChatBackend.destallBelt(from: belt, cell: cell)
            #expect(treated.map(\.name) == belt.map(\.name))
            #expect(treated.contains { $0 is ReminderCreateTool })
            #expect(treated.first { $0.name == "createReminder" }?.description == ReminderCreateTool.productionDescription)
        }
    }

    // MARK: Per-trial reap (#200F Part 0)

    /// #200E lost 4 of 10 treatment remind trials to already-exists
    /// reads of REAL artifacts the control cell had created minutes
    /// earlier — the sweep now runs after EVERY trial. The REAP-TRIAL
    /// line is classification vocabulary; pinned byte-for-byte.
    ///
    /// #200S adds `alarms=`: the per-trial reap now cancels alarms too,
    /// because alarms used to wait for end-of-run and every crashed run
    /// stranded every alarm it had scheduled — 2026-07-29's four jetsam
    /// kills stranded ~47, and Owen had to sweep by hand to keep working.
    @Test func reapTrialLineGrammarIsStable() {
        #expect(LocalChatBackend.reapTrialLine(
            reminders: 1, events: 0, alarms: 1, failures: 0, tag: "shape=armed p=remind t=3"
        ) == "battery: REAP-TRIAL reminders=1 events=0 alarms=1 failures=0 shape=armed p=remind t=3 (#200F)")
    }

    /// The final REAP line keeps its #200 grammar; its counts now FOLD
    /// IN the per-trial sums, so reap arithmetic stays exact — total
    /// removed this run = per-trial sums + end-of-run backstop. The
    /// no-access skip form is unchanged.
    @Test func reapCountSegmentFoldsPerTrialSumsAndKeepsTheSkipForm() {
        #expect(LocalChatBackend.reapCountSegment("reminders", backstop: 2, perTrial: 13, hadAccess: true) == "reminders=15")
        #expect(LocalChatBackend.reapCountSegment("events", backstop: 0, perTrial: 0, hadAccess: true) == "events=0")
        #expect(LocalChatBackend.reapCountSegment("reminders", backstop: 0, perTrial: 4, hadAccess: false) == "reminders=skipped(no-access)")
    }

    // MARK: Instructions-level de-stall (#200C)

    /// #200D (PROMOTED 2026-07-28, #200C verdict on run FFC92E35): the
    /// de-stall clause is production — calendar 0/9 → 8/10, alarm 8/10 →
    /// 10/10, remind off zero (2/10 vs 0/40 lifetime control), grabs DOWN
    /// 9/10 → 3/9. The flag stays as the rollback/re-measure seam:
    /// explicit `false` reproduces the pre-promotion text. (A rollback
    /// flips exactly this pin back.)
    @Test func actionDestallClauseIsProductionDefaultAndRemovable() {
        let production = LocalChatBackend.instructionsText(
            deviceContext: "Device: test.", hasTools: true
        )
        // The promoted clause, verbatim, at its measured seam: after the
        // confirmation-card sentence. Since #200G the find-first carve-out
        // follows it, before honesty-and-recovery.
        #expect(production.contains("accept it gracefully. When the user asks for a reminder, alarm, or calendar event and says what and when, create it right away — never ask which list, which calendar, or for other optional details first; leave optional fields empty and the defaults apply. 'Remind me' means"))
        // Explicit true is identity with the default — the #200C treated
        // cell now measures production.
        let explicitOn = LocalChatBackend.instructionsText(
            deviceContext: "Device: test.", hasTools: true,
            includeActionDestallClause: true
        )
        #expect(explicitOn == production)
        // The rollback seam: explicit false removes the clause and nothing
        // else — every neighboring production sentence survives, including
        // the #200G carve-out, which has its OWN flag and rollback.
        let rollback = LocalChatBackend.instructionsText(
            deviceContext: "Device: test.", hasTools: true,
            includeActionDestallClause: false
        )
        #expect(rollback != production)
        #expect(!rollback.contains("never ask which list"))
        #expect(rollback.contains("confirmation card first; if they decline, accept it gracefully. 'Remind me' means"))
        #expect(rollback.contains("never invent a value"))
        // The clause never reaches the toolless branch (it rides inside
        // the hasTools capabilities paragraph).
        let bare = LocalChatBackend.instructionsText(
            deviceContext: "Device: test.", hasTools: false
        )
        #expect(!bare.contains("create it right away"))
    }

    /// The instrfix cell is an INSTRUCTIONS treatment only — its belt is
    /// production, byte-identical, including the reminder tool.
    @Test @MainActor func instrfixBeltIsProductionIdentity() {
        let belt = DeviceToolBelt.makeActionTools(
            relay: ToolEventRelay(), confirmations: ToolConfirmationCenter(),
            alarmService: AlarmService()
        )
        let instrfix = LocalChatBackend.destallBelt(from: belt, cell: .armedInstrfix)
        #expect(instrfix.map(\.name) == belt.map(\.name))
        #expect(instrfix.contains { $0 is ReminderCreateTool })
        #expect(instrfix.first { $0.name == "createReminder" }?.description == ReminderCreateTool.productionDescription)
    }

    // MARK: Action-tool names (#200)

    /// The #200 capture surfaces (confirm=none synthesis in the export, the
    /// drill-down display) identify action tools by name from ONE list.
    /// Pinned against the real action belt so the list can never drift.
    @Test @MainActor func actionToolNamesMatchTheActionBelt() {
        let names = DeviceToolBelt.makeActionTools(
            relay: ToolEventRelay(),
            confirmations: ToolConfirmationCenter(),
            alarmService: AlarmService()
        ).map(\.name)
        #expect(Set(names) == DeviceToolBelt.actionToolNames)
        #expect(names.count == DeviceToolBelt.actionToolNames.count)
    }
}

// MARK: - (#196) framework-default probe tool

/// Deliberately does NOT declare `includesSchemaInInstructions` — the whole
/// point is reading the protocol extension's default (file scope: the
/// `@Generable` macro expansion can't see into a `private` nested type).
/// Never called.
fileprivate struct SchemaGateProbeTool: Tool {
    let name = "schemaGateProbe"
    let description = "Probes the framework default for includesSchemaInInstructions."

    @Generable
    struct Arguments {
        @Guide(description: "Unused.")
        var probe: String
    }

    func call(arguments: Arguments) async throws -> String { "unused" }
}
