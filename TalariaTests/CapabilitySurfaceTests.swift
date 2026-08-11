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
        // Declaration order. `.vision` rides along with no tools of its own
        // (257-V-C) — it declares an availability caveat, so it is stated
        // rather than dropped; every other tool-less group is still absent.
        #expect(sections.map(\.group) == [.health, .calendar, .vision])
        #expect(sections.first { $0.group == .calendar }?.tools.map(\.id) == ["aTool", "zTool"])
        #expect(sections.last?.tools.isEmpty == true)
        #expect(CapabilitiesSheet.sections(from: []).isEmpty)
    }

    /// **BAR 257-V-C** — the sheet states the image family even when the
    /// belt it was handed carries no image tools. Before Owen's 2026-08-10
    /// ruling, `sections(from:)` dropped any tool-less group, so the Images
    /// section could vanish entirely; naming it (caveated) is the whole
    /// point of the ruling, since the feature was otherwise undiscoverable.
    ///
    /// Derived from the caveat DECLARATION, not from a `.vision` literal: a
    /// future conditional family gets the same treatment for free.
    @Test func sectionsStateCaveatedFamiliesEvenWithNoLiveTools() {
        let noImageTools = [
            CapabilityDescriptor(id: "readHealth", semanticDescription: "h", source: .device,
                                 group: .health, riskClass: .read, permissions: ["Health"],
                                 argumentSummary: "none"),
        ]
        let sections = CapabilitiesSheet.sections(from: noImageTools)
        let vision = sections.first { $0.group == .vision }
        #expect(vision != nil, "a caveated family must render with no live tools (257-V-C)")
        #expect(vision?.tools.isEmpty == true, "real data only — no invented tool rows")
        #expect(CapabilityGroup.vision.availabilityCaveat != nil,
                "the section's caveat label reads this one source (257-V-B)")

        // Every family WITHOUT a caveat still drops when its tools are absent.
        let rendered = Set(sections.map(\.group))
        for group in CapabilityGroup.allCases where group.availabilityCaveat == nil {
            #expect(rendered.contains(group) == (group == .health),
                    "\(group.rawValue) should render only when it has live tools")
        }
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
