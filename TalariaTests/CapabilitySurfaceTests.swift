import FoundationModels
import Testing
@testable import Talaria

/// #257 lever 3a — bar 257-3a-A: the `/capabilities` surface enumerates the
/// REGISTRY, derived. Adding a `CapabilityGroup` case or a belt tool moves
/// these derived counts, so a hand-written list smuggled into the view
/// (#257's root cause, re-entering through the UI door) fails loudly here.
struct CapabilitySurfaceTests {

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

    /// 257-3a-A, against the REAL belt: every tool renders exactly once, in
    /// a section for its own group, section order is the `CapabilityGroup`
    /// declaration order — all derived from the registry, never a literal.
    @Test @MainActor func sheetSectionsEnumerateTheRegistryExactly() {
        let belt = Self.fullBelt()
        let descriptors = CapabilityRegistry(belt: belt).descriptors
        let sections = CapabilitiesSheet.sections(from: descriptors)

        // Every belt tool present exactly once, none invented.
        let renderedIds = sections.flatMap { $0.tools.map(\.id) }
        #expect(renderedIds.count == belt.count)
        #expect(Set(renderedIds) == Set(belt.map(\.name)))
        #expect(Set(renderedIds).count == renderedIds.count)

        // Every group with a live tool renders, in declaration order.
        let expectedGroups = CapabilityGroup.allCases.filter { group in
            descriptors.contains { $0.group == group }
        }
        #expect(sections.map(\.group) == expectedGroups)

        // Each section carries only its own group's tools.
        for section in sections {
            #expect(section.tools.allSatisfy { $0.group == section.group })
        }
    }

    /// Derivation mechanics on fixtures: declaration-ordered sections,
    /// id-sorted rows, empty registry → empty render (the honest state,
    /// never a mock).
    @Test func sectionsDeriveOrderFromDeclarationAndSortToolsById() {
        let stubs = [
            CapabilityDescriptor(id: "zTool", semanticDescription: "z", source: .device,
                                 group: .calendar, riskClass: .read, permissions: [],
                                 argumentSummary: "none"),
            CapabilityDescriptor(id: "aTool", semanticDescription: "a", source: .device,
                                 group: .calendar, riskClass: .write, permissions: ["Calendars"],
                                 argumentSummary: "none"),
            CapabilityDescriptor(id: "hTool", semanticDescription: "h", source: .device,
                                 group: .health, riskClass: .read, permissions: [],
                                 argumentSummary: "none"),
        ]
        let sections = CapabilitiesSheet.sections(from: stubs)
        #expect(sections.map(\.group) == [.health, .calendar])   // declaration order
        #expect(sections.last?.tools.map(\.id) == ["aTool", "zTool"])  // id-sorted
        #expect(CapabilitiesSheet.sections(from: []).isEmpty)
    }

    /// 257-3a-B's typed route exists: `/capabilities` ships as a LOCAL
    /// slash command (app-handled, no argument, non-destructive).
    @Test func capabilitiesSlashCommandIsLocalAndArgumentFree() {
        let command = SlashCommand.localCommands.first { $0.name == "capabilities" }
        #expect(command != nil)
        #expect(command?.isLocal == true)
        #expect(command?.acceptsArgument == false)
        #expect(command?.isDestructive == false)
    }
}
