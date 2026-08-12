#if DEBUG
import Foundation

/// #333: one reachable instrument. `run` binds the EXACT call the
/// Developer-screen button makes — the button and the trigger share this
/// closure, which is the whole of bar 333-B. Capability flags feed the
/// conductor's refusal rules (alarms never unattended — Owen 2026-08-11;
/// EventKit never on an iPad — Shelley's-device rule made structural).
///
/// Backend is optional so conductor tests can exercise flag discipline with
/// no LocalChatBackend; every registry entry guard-lets it first thing.
struct InstrumentSpec {
    enum ConfirmationMode { case autoAccept, autoDecline, none }
    let name: String
    let confirmationMode: ConfirmationMode
    let writesEventKit: Bool
    let writesAlarms: Bool
    let run: @MainActor (LocalChatBackend?, _ trials: Int, _ cells: [String]?) async -> Void
}

enum InstrumentRegistry {
    static let all: [InstrumentSpec] = [
        // #196: composition/decline battery. Headless sessions can never answer
        // a confirmation card, so grabs auto-decline — which also measures
        // post-denial recovery. Button: DeveloperSettingsScreen.swift:644,
        // `await backend.runShapeBattery(trials: trials)` — trials only.
        InstrumentSpec(name: "shape", confirmationMode: .autoDecline,
                       writesEventKit: false, writesAlarms: false,
                       run: { backend, trials, _ in
                           guard let backend else { return }
                           await backend.runShapeBattery(trials: trials)
                       }),
        // #200: the action-SUCCESS path — real EventKit/AlarmKit writes,
        // marker-tagged, reaped (#331 container). Button:
        // DeveloperSettingsScreen.swift:681, `await backend.runActionBattery(trials:
        // trials)` — trials only, `cells` untouched at its `[.armed]` default.
        // `runActionBattery`'s real `cells:` parameter is `[ActionBatteryCell]`,
        // not `[String]` — the button never supplies one, so this entry does not
        // either; inventing a conversion here would be an argument the button
        // doesn't pass.
        InstrumentSpec(name: "action", confirmationMode: .autoAccept,
                       writesEventKit: true, writesAlarms: true,
                       run: { backend, trials, _ in
                           guard let backend else { return }
                           await backend.runActionBattery(trials: trials)
                       }),
        // Read-only tools; nothing to accept or decline. Button:
        // DeveloperSettingsScreen.swift:895, trials only.
        InstrumentSpec(name: "read-tool", confirmationMode: .none,
                       writesEventKit: false, writesAlarms: false,
                       run: { backend, trials, _ in
                           guard let backend else { return }
                           await backend.runReadToolBattery(trials: trials)
                       }),
        // #196: router classification probe — FM-only, no tool execution.
        // Button: DeveloperSettingsScreen.swift:1741, trials only.
        InstrumentSpec(name: "router-probe", confirmationMode: .none,
                       writesEventKit: false, writesAlarms: false,
                       run: { backend, trials, _ in
                           guard let backend else { return }
                           await backend.runRouterProbe(trials: trials)
                       }),
    ]

    static func spec(named name: String) -> InstrumentSpec? {
        all.first { $0.name == name }
    }
}
#endif
