import Foundation

/// #284: capability metadata for every tool the local brain can be armed
/// with. ONE registry — native device tools now; `.hermes`/`.mcp`/`.skill`
/// are cases only, the shape #150/#163 land into later. Descriptors are
/// declared BY the tool types (`CapabilityDescribing`) and the registry is
/// built FROM live belt instances, so it structurally cannot describe a
/// tool the belt doesn't carry. Bidirectional drift pins live in
/// `CapabilityRegistryTests` (the #200 `actionToolNames` pattern).
enum CapabilityGroup: String, CaseIterable, Sendable {
    case health          // readHealth, readMotion
    case location        // currentLocation
    case weather         // currentWeather
    case places          // searchPlaces
    case calendar        // readCalendar, createCalendarEvent
    case reminders       // readReminders, createReminder
    case alarms          // scheduleAlarm
    case contacts        // lookupContact
    case conversations   // searchConversations
    case deviceStatus    // deviceStatus
    /// Image tools. NEVER in the router vector — armed by the #176 image
    /// gate, union'd over any narrowing (spec §6 rule V).
    case vision          // readImageText, readBarcode

    /// The phrase the armed instructions enumeration uses for this family.
    var displayPhrase: String {
        switch self {
        case .health: return "their health and activity"
        case .location: return "their location"
        case .weather: return "the weather"
        case .places: return "nearby places"
        case .calendar: return "calendar"
        case .reminders: return "reminders"
        case .alarms: return "alarms"
        case .contacts: return "contacts"
        case .conversations: return "past conversations"
        case .deviceStatus: return "device status"
        case .vision: return "text and barcodes in the attached image"
        }
    }
}

enum CapabilitySource: String, Sendable {
    case device
    // Unpopulated this lane — the #150/#163 landing shape (spec §3.2).
    case hermes, mcp, skill
}

enum CapabilityRiskClass: String, Sendable {
    case read
    /// Write == confirmation-gated: every action tool shows the card first.
    case write
}

struct CapabilityDescriptor: Sendable {
    let id: String                    // == Tool.name
    let semanticDescription: String
    let source: CapabilitySource
    let group: CapabilityGroup
    let riskClass: CapabilityRiskClass
    let permissions: [String]         // user-facing framework names; [] = none
    let argumentSummary: String
}

/// A tool type that carries its own capability descriptor. Static, so the
/// nonisolated instructions builder can read catalog data without touching
/// MainActor tool instances.
protocol CapabilityDescribing {
    static var capabilityDescriptor: CapabilityDescriptor { get }
}

struct CapabilityRegistry {
    let descriptors: [CapabilityDescriptor]

    /// Built from live belt instances — a tool whose type does not conform
    /// is simply absent, and the pin test fails on the count mismatch.
    init(belt: [Any]) {
        descriptors = belt.compactMap {
            (type(of: $0) as? any CapabilityDescribing.Type)?.capabilityDescriptor
        }
    }

    nonisolated static func toolNames(
        for groups: Set<CapabilityGroup>, in catalog: [CapabilityDescriptor]
    ) -> Set<String> {
        Set(catalog.filter { groups.contains($0.group) }.map(\.id))
    }

    /// The armed blurb's enumeration, generated so it can never go stale
    /// (#257's root cause was a hand-written copy of this list). Order is
    /// the `CapabilityGroup` declaration order — deterministic, pinned.
    nonisolated static func armedCapabilityEnumeration(families: [CapabilityGroup]) -> String {
        let ordered = CapabilityGroup.allCases.filter { families.contains($0) }
        let phrases = ordered.map(\.displayPhrase)
        switch phrases.count {
        case 0: return ""
        case 1: return phrases[0]
        case 2: return "\(phrases[0]) and \(phrases[1])"
        default:
            return phrases.dropLast().joined(separator: ", ") + ", and " + phrases.last!
        }
    }
}
