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
}
