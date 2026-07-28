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
