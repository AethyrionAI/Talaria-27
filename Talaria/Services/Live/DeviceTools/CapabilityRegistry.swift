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

    /// #257 lever 1: the user-facing heading for this family's line in the
    /// deterministic capability answer. Separate from `displayPhrase`, which
    /// is third-person copy written for the ARMED instructions ("their health
    /// and activity") and reads wrong when spoken to the user.
    ///
    /// An exhaustive switch by design — a new `CapabilityGroup` case cannot
    /// compile until it has an answer line, which is the structural guard
    /// #257's root cause (a hand-written list that drifted) actually needs.
    var capabilityAnswerTitle: String {
        switch self {
        case .health: return "Health and activity"
        case .location: return "Location"
        case .weather: return "Weather"
        case .places: return "Nearby places"
        case .calendar: return "Calendar"
        case .reminders: return "Reminders"
        case .alarms: return "Alarms"
        case .contacts: return "Contacts"
        case .conversations: return "Past conversations"
        case .deviceStatus: return "Device status"
        case .vision: return "Images you attach"
        }
    }

    /// #257 lever 1: the short concrete detail after the heading. Every clause
    /// is grounded in a shipped tool's `semanticDescription` — nothing here
    /// promises a capability the belt does not carry, because 297-C's honesty
    /// bar scores this text when it rides a reply.
    var capabilityAnswerDetail: String {
        switch self {
        case .health: return "steps, sleep, workouts, heart rate, and whether you're moving right now"
        case .location: return "where you are, as a place name"
        case .weather: return "current conditions and the forecast where you are"
        case .places: return "restaurants, shops, and other spots around you"
        case .calendar: return "read your schedule, and create events"
        case .reminders: return "read what's on your lists, and add new ones"
        case .alarms: return "set an alarm for a time you name"
        case .contacts: return "look up someone's phone number or email address"
        case .conversations: return "search what we've talked about before"
        case .deviceStatus: return "battery, charging, storage, and Low Power Mode"
        case .vision: return "read the text and barcodes in a photo you send"
        }
    }

    /// #257-V: the availability caveat a family carries when its tools are
    /// not on every turn's belt. **ONE source** — the deterministic
    /// capability block and the `/capabilities` sheet both render THIS
    /// string (the sheet's `MonoLabel` uppercases it), so the two surfaces
    /// cannot drift apart (#202D, the rule this file's copy exists for).
    /// `nil` = the family is unconditional and its line carries no caveat.
    ///
    /// Vision is the only conditional family today: the image tools arm
    /// solely through the #176 image gate. **Naming it, caveated, is Owen's
    /// 2026-08-10 ruling** — the block is deterministic app text rather than
    /// model output, so the caveat carries no overpromise risk, and without
    /// the line the feature is undiscoverable. It does NOT arm anything: the
    /// instructions the model reads still gate vision on `hasImageTools`.
    ///
    /// Exhaustive by design, like the two switches above — a new
    /// `CapabilityGroup` cannot compile until someone decides whether it is
    /// always available.
    var availabilityCaveat: String? {
        switch self {
        case .health, .location, .weather, .places, .calendar, .reminders,
             .alarms, .contacts, .conversations, .deviceStatus:
            return nil
        case .vision:
            return "available when you attach a photo"
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

    // MARK: - #257 lever 1: the deterministic capability answer

    /// The block's first line. A `let`, not an inline literal, so the probe
    /// and any future caller can pin the exact string they measure (#202D:
    /// one builder, one source of the text).
    nonisolated static let capabilityAnswerOpener =
        "Here is everything I can reach on this iPhone:"

    /// The block's last line.
    nonisolated static let capabilityAnswerCloser = "Just ask for any of these."

    /// #257 LEVER 1 — the capability answer the APP renders, with **zero
    /// generation**. The model never recites this list.
    ///
    /// Why it is built rather than prompted: run `A04154D7` (#297) measured
    /// what happens when the ten-family list is put in the toolless
    /// instructions and the model is asked to say it — it COMPRESSES to a
    /// natural-sounding four-family sample, 7/20 against a ≥18/20 bar. That
    /// is normal behaviour for a response planner and it is not fixable by
    /// rewording. **The arity of a `for` loop cannot compress**, so the
    /// enumeration moves out of the model and into the registry. Bar 257-1-C
    /// scores this string with the shipped `toollessIndexFamiliesNamed(in:)`.
    ///
    /// **`.vision` IS rendered, carrying its `availabilityCaveat` (#257-V,
    /// Owen's ruling 2026-08-10).** This paragraph said the opposite until
    /// then — that the family was excluded "by design" because advertising
    /// image tools on an attachment-less turn would promise a tool the belt
    /// is not carrying. The ruling flips it, and the reasoning that looked
    /// sound was scoped wrong:
    ///
    /// - The rule it borrowed from — `armedEnumeration`'s `hasImageTools`
    ///   gate — governs the INSTRUCTIONS THE MODEL READS, where naming a
    ///   tool that is not on the belt really does invite a phantom call.
    ///   **That gate is untouched.** This block is deterministic app text
    ///   spoken to the USER; it offers the model nothing, so a caveated line
    ///   cannot promise a tool to anyone who could try to call it.
    /// - The caveat is what makes it honest, and it is the registry's one
    ///   copy (`availabilityCaveat`) — the `/capabilities` sheet's label
    ///   renders the same string, so the two surfaces cannot drift (#202D).
    /// - Excluding it cost DISCOVERABILITY, which is the defect this whole
    ///   item exists to fix: `readImageText`/`readBarcode` are two of the
    ///   fifteen tools the original "I thought it could do more than that"
    ///   complaint counted as missing.
    ///
    /// Order is `CapabilityGroup` declaration order, so the render is
    /// byte-identical every call regardless of the caller's ordering.
    nonisolated static func capabilityAnswerBlock(
        families: [CapabilityGroup] = CapabilityGroup.allCases
    ) -> String {
        let ordered = CapabilityGroup.allCases.filter { families.contains($0) }
        guard !ordered.isEmpty else { return "" }
        var lines = [capabilityAnswerOpener]
        lines += ordered.map { group in
            let body = "• \(group.capabilityAnswerTitle) — \(group.capabilityAnswerDetail)"
            guard let caveat = group.availabilityCaveat else { return body }
            return "\(body) (\(caveat))"
        }
        lines.append(capabilityAnswerCloser)
        return lines.joined(separator: "\n")
    }
}
