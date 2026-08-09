import FoundationModels
import Testing
@testable import Talaria

struct CapabilityRegistryTests {

    // Doubles: two minimal descriptor-carrying types, no FoundationModels needed.
    private struct StubDescribedA: CapabilityDescribing {
        static let capabilityDescriptor = CapabilityDescriptor(
            id: "stubA", semanticDescription: "stub A", source: .device,
            group: .calendar, riskClass: .read, permissions: ["Calendars"],
            argumentSummary: "none")
    }
    private struct StubDescribedB: CapabilityDescribing {
        static let capabilityDescriptor = CapabilityDescriptor(
            id: "stubB", semanticDescription: "stub B", source: .device,
            group: .health, riskClass: .write, permissions: [],
            argumentSummary: "none")
    }

    @Test func groupToolNameMappingFiltersTheCatalog() {
        let catalog = [StubDescribedA.capabilityDescriptor, StubDescribedB.capabilityDescriptor]
        #expect(CapabilityRegistry.toolNames(for: [.calendar], in: catalog) == ["stubA"])
        #expect(CapabilityRegistry.toolNames(for: [.calendar, .health], in: catalog) == ["stubA", "stubB"])
        #expect(CapabilityRegistry.toolNames(for: [], in: catalog).isEmpty)
    }

    @Test func enumerationIsDeterministicAndOxfordJoined() {
        // Order follows the CaseIterable declaration order, not the input order.
        let sentence = CapabilityRegistry.armedCapabilityEnumeration(
            families: [.reminders, .health, .calendar])
        #expect(sentence == "their health and activity, calendar, and reminders")
        #expect(CapabilityRegistry.armedCapabilityEnumeration(families: [.weather]) == "the weather")
    }

    @Test func everyGroupHasADisplayPhrase() {
        for group in CapabilityGroup.allCases {
            #expect(!group.displayPhrase.isEmpty)
        }
    }

    // MARK: - Armed instructions enumeration (#284 Task 3, #257 fix)

    @Test func armedEnumerationCoversEveryNonVisionFamilyByDefault() {
        let armed = LocalChatBackend.instructionsText(
            deviceContext: "Device: iPhone.", hasTools: true)
        // The #257 fix: families the hand-written sentence missed.
        #expect(armed.contains("device status"))
        #expect(armed.contains("their health and activity"))
        // The frame sentence survives verbatim around the generated list.
        #expect(armed.contains("Use the tools for the user's own data"))
        #expect(armed.contains("instead of guessing at it"))
        // No image in context → no vision phrase (#176 invariant).
        #expect(!armed.contains("attached image"))
    }

    @Test func armedEnumerationAddsVisionOnlyWithImageTools() {
        let armed = LocalChatBackend.instructionsText(
            deviceContext: "Device: iPhone.", hasTools: true, hasImageTools: true)
        #expect(armed.contains("text and barcodes in the attached image"))
    }

    @Test func armedEnumerationHonorsANarrowedFamilyList() {
        let armed = LocalChatBackend.instructionsText(
            deviceContext: "Device: iPhone.", hasTools: true,
            armedCapabilityFamilies: [.reminders])
        #expect(armed.contains("reminders"))
        #expect(!armed.contains("their health and activity"))  // never advertise an absent tool
    }

    @Test func visionInTheFamiliesListNeverLeaksWithoutImageTools() {
        // `armedEnumeration`'s families.filter { $0 != .vision } line is the
        // mechanism behind the global rule "vision only via hasImageTools,
        // never via the families list" — even if a caller (a future Stage 3
        // regression) hands .vision in the families list, hasImageTools:
        // false must still suppress the vision phrase.
        let armed = LocalChatBackend.instructionsText(
            deviceContext: "Device: iPhone.", hasTools: true, hasImageTools: false,
            armedCapabilityFamilies: CapabilityGroup.allCases)
        #expect(!armed.contains("attached image"))
    }

    // MARK: - #257 lever 1: the deterministic capability answer block

    /// **BAR 257-1-C**, scored by the SHIPPED scorer — the real
    /// `toollessIndexFamiliesNamed(in:)` that produced zero false positives
    /// across 120 device replies in #297, called here rather than
    /// reimplemented. The thing run `A04154D7` spent a device run failing
    /// (10 of 10 non-vision families named) is true BY CONSTRUCTION for a
    /// rendered block, and this is the proof.
    ///
    /// A miss here is NOT a licence to widen the keyword table (#297's named
    /// trap) — it means the registry and the table disagree, which is a
    /// finding to report, not a test to tune.
    #if DEBUG
    @Test func capabilityAnswerBlockNamesEveryNonVisionFamilyUnderTheShippedScorer() {
        let block = CapabilityRegistry.capabilityAnswerBlock()
        // The dispatch's §7 cheap experiment: the rendered string IS the
        // product, so the suite prints it — Owen judges the copy without a
        // device run, a build, or an OTA.
        print("#257 CAPABILITY BLOCK ↓↓↓\n\(block)\n#257 CAPABILITY BLOCK ↑↑↑")

        let named = LocalChatBackend.toollessIndexFamiliesNamed(in: block)
        let expected = Set(CapabilityGroup.allCases.filter { $0 != .vision })
        #expect(named == expected,
                "missed: \(expected.subtracting(named).map(\.rawValue).sorted())")
        #expect(named.count == expected.count)   // 10 of 10, derived not literal
    }

    /// The block must not itself trip #297's honesty union — it rides a real
    /// reply in the 1b APPEND shape, so 297-C scores it too. Halves counted
    /// SEPARATELY (#202C: folding them destroys the migration signal).
    @Test func capabilityAnswerBlockCarriesNoActionClaimAndNoToolSyntax() {
        let block = CapabilityRegistry.capabilityAnswerBlock()
        #expect(!LocalChatBackend.toollessIndexClaimHit(block))
        #expect(!LocalChatBackend.toollessIndexSyntaxHit(block))
    }
    #endif

    /// Registry-DERIVED arity: the expected line count comes from
    /// `allCases`, never from a literal list, so adding a `CapabilityGroup`
    /// fails the suite loudly. (The two exhaustive switches behind the line
    /// already fail the COMPILE — this pins the block's shape on top.)
    @Test func capabilityAnswerBlockRendersOneDerivedBulletPerNonVisionFamily() {
        let expected = CapabilityGroup.allCases.filter { $0 != .vision }
        let lines = CapabilityRegistry.capabilityAnswerBlock().components(separatedBy: "\n")
        #expect(lines.count == expected.count + 2)   // opener + N bullets + closer
        #expect(lines.first == CapabilityRegistry.capabilityAnswerOpener)
        #expect(lines.last == CapabilityRegistry.capabilityAnswerCloser)
        for (line, group) in zip(lines.dropFirst().dropLast(), expected) {
            #expect(line == "• \(group.capabilityAnswerTitle) — \(group.capabilityAnswerDetail)")
        }
    }

    /// Determinism: two renders are byte-identical. Zero generation is the
    /// whole mechanism — if this ever wobbles, something stochastic got in.
    @Test func capabilityAnswerBlockIsByteIdenticalAcrossRenders() {
        let first = CapabilityRegistry.capabilityAnswerBlock()
        let second = CapabilityRegistry.capabilityAnswerBlock()
        #expect(first == second)
        #expect(Array(first.utf8) == Array(second.utf8))
        // Caller ordering must not leak into the output either.
        #expect(CapabilityRegistry.capabilityAnswerBlock(
            families: CapabilityGroup.allCases.reversed()) == first)
    }

    /// #176 rule V at this seam: `.vision` never appears, even when a caller
    /// hands it in explicitly — the mirror of
    /// `visionInTheFamiliesListNeverLeaksWithoutImageTools`.
    @Test func capabilityAnswerBlockNeverAdvertisesTheImageTools() {
        let block = CapabilityRegistry.capabilityAnswerBlock(families: CapabilityGroup.allCases)
        #expect(!block.contains(CapabilityGroup.vision.capabilityAnswerTitle))
        #expect(!block.contains("barcode"))
        #expect(!block.contains("photo"))
    }

    /// Narrowing works and stays ordered — the surface #257's lever 3a would
    /// reuse can render a subset without a second builder (#202D).
    @Test func capabilityAnswerBlockHonorsANarrowedFamilyList() {
        let block = CapabilityRegistry.capabilityAnswerBlock(families: [.reminders, .calendar])
        let lines = block.components(separatedBy: "\n")
        #expect(lines.count == 4)
        #expect(lines[1].hasPrefix("• Calendar —"))     // declaration order, not caller order
        #expect(lines[2].hasPrefix("• Reminders —"))
        #expect(!block.contains("Health and activity"))
        #expect(CapabilityRegistry.capabilityAnswerBlock(families: []).isEmpty)
        #expect(CapabilityRegistry.capabilityAnswerBlock(families: [.vision]).isEmpty)
    }

    @Test func everyGroupHasAnAnswerTitleAndDetail() {
        for group in CapabilityGroup.allCases {
            #expect(!group.capabilityAnswerTitle.isEmpty)
            #expect(!group.capabilityAnswerDetail.isEmpty)
        }
    }

    // MARK: - Belt pins (#200 actionToolNames pattern, bidirectional)

    @MainActor private static func fullBelt() -> [any Tool] {
        let relay = ToolEventRelay()
        var belt = DeviceToolBelt.makeReadTools(
            relay: relay,
            conversationProvider: { nil },
            sessionCacheProvider: { [] },
            spotlightEnabledProvider: { false })
        belt += DeviceToolBelt.makeActionTools(
            relay: relay,
            confirmations: ToolConfirmationCenter(),
            alarmService: AlarmService())
        return belt
    }

    @Test @MainActor func everyBeltToolHasADescriptorWhoseIdIsItsName() {
        let belt = Self.fullBelt()
        let registry = CapabilityRegistry(belt: belt)
        #expect(registry.descriptors.count == belt.count)  // no undescribed tool
        for tool in belt {
            let descriptor = registry.descriptors.first { $0.id == tool.name }
            #expect(descriptor != nil, "no descriptor for \(tool.name)")
        }
    }

    @Test @MainActor func everyGroupMapsToAtLeastOneToolAndEveryToolToExactlyOneGroup() {
        let registry = CapabilityRegistry(belt: Self.fullBelt())
        let groups = Set(registry.descriptors.map(\.group))
        #expect(groups == Set(CapabilityGroup.allCases))   // no orphan group
        // "exactly one group" is structural (group is a single field), but
        // duplicate descriptors would double-count — pin id uniqueness.
        #expect(Set(registry.descriptors.map(\.id)).count == registry.descriptors.count)
    }

    @Test @MainActor func actionToolsAreWriteClassAndReadToolsAreReadClass() {
        let registry = CapabilityRegistry(belt: Self.fullBelt())
        for d in registry.descriptors {
            let isAction = DeviceToolBelt.actionToolNames.contains(d.id)
            #expect((d.riskClass == .write) == isAction, "\(d.id) risk class wrong")
        }
    }

    @Test @MainActor func visionGroupIsExactlyTheImageDependentTools() {
        let belt = Self.fullBelt()
        let registry = CapabilityRegistry(belt: belt)
        let visionIds = Set(registry.descriptors.filter { $0.group == .vision }.map(\.id))
        let imageDependent = Set(belt.filter { $0 is any ImageDependentTool }.map(\.name))
        #expect(visionIds == imageDependent)  // rule V's precondition (spec §6)
    }

    // MARK: - ToolIntentRouteVector mapping (#284 Task 5)

    #if DEBUG
    @Test func vectorMapsTrueFieldsToGroups() {
        let vector = ToolIntentRouteVector(
            needsDeviceTool: true,
            wantsCalendar: true, wantsReminders: false, wantsAlarms: false,
            wantsHealth: true, wantsWeather: false, wantsPlaces: false,
            wantsContacts: false, wantsConversations: false,
            wantsDeviceStatus: false, wantsLocation: false)
        #expect(vector.armedGroups == [.calendar, .health])
        let none = ToolIntentRouteVector(
            needsDeviceTool: true,
            wantsCalendar: false, wantsReminders: false, wantsAlarms: false,
            wantsHealth: false, wantsWeather: false, wantsPlaces: false,
            wantsContacts: false, wantsConversations: false,
            wantsDeviceStatus: false, wantsLocation: false)
        #expect(none.armedGroups.isEmpty)   // all-false = abstention = full belt (O1)
    }
    #endif

    // MARK: - Vector probe grid consistency (#284 Task 6)

    #if DEBUG
    @Test @MainActor func vectorGridExpectationsAreInternallyConsistent() {
        let catalog = CapabilityRegistry(belt: Self.fullBelt()).descriptors
        for row in LocalChatBackend.vectorProbeGrid {
            // A toolless row expects no groups and no tools.
            if !row.expectedArmed {
                #expect(row.expectedGroups.isEmpty && row.expectedTools.isEmpty)
                continue
            }
            // Every expected tool is reachable from the expected groups —
            // otherwise the danger bar is unsatisfiable by construction.
            let reachable = CapabilityRegistry.toolNames(for: row.expectedGroups, in: catalog)
            #expect(row.expectedTools.isSubset(of: reachable),
                    "row '\(row.text)': expected tools unreachable from expected groups")
        }
    }

    @Test func vectorGridKeepsTheTrapRows() {
        let texts = LocalChatBackend.vectorProbeGrid.map(\.text)
        // #217B's falsifiability traps survive verbatim (spec §5.2).
        #expect(texts.contains("Play some music"))
        #expect(texts.contains("How long will it take me to drive to the airport?"))
        #expect(texts.contains("Read the label on this bottle for me"))
    }
    #endif

    // MARK: - Danger scorer (#284 Task 7)

    #if DEBUG
    @Test @MainActor func dangerScoringMatchesTheSpecDefinition() {
        let catalog = CapabilityRegistry(belt: Self.fullBelt()).descriptors
        // Narrowed to reminders when the prompt needed the calendar read → dangerous.
        #expect(LocalChatBackend.vectorTrialIsDangerous(
            armed: true, groups: [.reminders], expectedArmed: true,
            expectedTools: ["readCalendar"], catalog: catalog))
        // All-false → full belt → never dangerous (O1).
        #expect(!LocalChatBackend.vectorTrialIsDangerous(
            armed: true, groups: [], expectedArmed: true,
            expectedTools: ["readCalendar"], catalog: catalog))
        // Right group → covered → safe.
        #expect(!LocalChatBackend.vectorTrialIsDangerous(
            armed: true, groups: [.calendar], expectedArmed: true,
            expectedTools: ["readCalendar"], catalog: catalog))
        // Spurious arming on a trap row (no expected tools) → dangerous:
        // the belt narrowed for no reason on a prompt no belt tool serves.
        #expect(LocalChatBackend.vectorTrialIsDangerous(
            armed: true, groups: [.reminders], expectedArmed: true,
            expectedTools: [], catalog: catalog))
    }
    #endif

    // MARK: - Router generation options (#284 fix, device run 21F0C10D)

    #if DEBUG
    @Test func productionRouterOptionsStayAtTheMeasuredSixtyFourTokenCap() {
        // Unchanged measured artifact (#196/#217) — pinned so the vector's
        // wider cap can never silently drift onto this one.
        #expect(LocalChatBackend.toolIntentRouterOptions
            == GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 64))
    }

    @Test func vectorRouterOptionsCarryTheirOwnWiderTokenCap() {
        // 165/165 device errors (run 21F0C10D) traced to routeVector
        // reusing the 64-token production cap for an 11-field response that
        // needs ~90-110 tokens — every generation was truncated mid-JSON.
        #expect(LocalChatBackend.vectorRouterOptions
            == GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 256))
    }
    #endif
}
