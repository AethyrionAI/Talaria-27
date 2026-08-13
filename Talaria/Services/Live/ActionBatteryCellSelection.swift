#if DEBUG
import Foundation

/// #341: the `TALARIA_CELLS` → `ActionBatteryCell` resolver, and the ONE place
/// a launch-env cell request is turned into cases (or refused).
///
/// **Why this exists.** #333 shipped `TALARIA_CELLS` end to end — the runner
/// exports it, `InstrumentLaunchIntent` parses it, the conductor threads it —
/// but no registry entry consumed it, because `runActionBattery`'s cells are
/// `[ActionBatteryCell]` and the wire carries `[String]`. The #335 review
/// recorded that honestly as "reserved, documented, inert". #337 then needed
/// it: `ToolCallGovernor`'s per-turn refusal budget accumulates across a whole
/// run (no battery calls `beginToolTurn()`), so two cells run SEQUENTIALLY are
/// order-confounded — the later arm is starved. The fix that does not touch
/// the governor is to run each arm as its OWN launch, which requires selecting
/// one cell per launch.
///
/// **The rules, and why each is the way it is.**
/// - Names are trimmed; components that are empty after trimming are dropped.
///   A trailing comma is not a cell.
/// - **No names requested — `nil`, or empty after normalisation — falls back to
///   the instrument's own pinned list.** Empty must mean "not requested"
///   because `scripts/mac/run-instrument.sh` exports
///   `DEVICECTL_CHILD_TALARIA_CELLS="$CELLS"` UNCONDITIONALLY, with `CELLS=""`
///   when `--cells` was not passed. So `[]` is the default wire state of every
///   existing harness invocation; treating it as "run zero cells" would break
///   every run that does not name cells.
/// - **An unknown name refuses the WHOLE request** — it is never dropped and
///   the known names around it are never run. A silently-dropped cell produces
///   a run that looks fine and measures something else, which is the entire
///   class of error this file exists to prevent.
/// - **Cells requested of an instrument with no cell dimension refuses too.**
///   `shape`, `two-turn`, the honesty pair and the probes take other cell types
///   or none; forwarding `[String]` to them would be the same silent drop
///   wearing a different hat.
/// - Order is preserved (the cell order IS the run order, and #201B/#200V care
///   about which arm runs cold), and duplicates are preserved rather than
///   coalesced — a repeated cell runs twice and the run record says so.
enum ActionBatteryCellSelection {

    /// The result of resolving one launch's request.
    enum Outcome: Equatable {
        /// The cells to run. `nil` means "nothing was requested and this
        /// instrument declares no cell dimension" — the registry closure
        /// ignores the argument, exactly as it did before #341.
        case resolved([LocalChatBackend.ActionBatteryCell]?)
        /// The request cannot be honoured. The text is written verbatim into
        /// the artifact's `refusalReason`, so it must read as an explanation
        /// on its own.
        case refused(String)
    }

    /// - Parameters:
    ///   - requested: the raw names from `TALARIA_CELLS`, already split on `,`.
    ///   - instrument: the instrument name, for the refusal text only.
    ///   - fallback: the instrument's own pinned cell list, or nil when it has
    ///     no `ActionBatteryCell` dimension.
    static func resolve(requested: [String]?,
                        instrument: String,
                        default fallback: [LocalChatBackend.ActionBatteryCell]?) -> Outcome {
        // #341 STRUCTURE-ONLY BODY — replaced in the same lane by the real
        // resolution. Kept for one commit-less beat so the RED the tests
        // witness is behavioural (the inert pass-through #335 described)
        // rather than a compile error.
        _ = requested
        _ = instrument
        return .resolved(fallback)
    }

    /// Every raw value a caller may name, sorted — the refusal text's "known:"
    /// half. Derived from `CaseIterable`, never retyped.
    static var knownNames: [String] {
        LocalChatBackend.ActionBatteryCell.allCases.map(\.rawValue).sorted()
    }
}
#endif
