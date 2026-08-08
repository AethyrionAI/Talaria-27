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
}
