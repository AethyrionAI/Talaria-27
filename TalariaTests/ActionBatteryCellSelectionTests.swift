#if DEBUG
import Foundation
import Testing
@testable import Talaria

/// #341: the `TALARIA_CELLS` resolver, and the registry columns it reads.
///
/// The bar these pin is not "the strings parse" — #333 already parsed them.
/// It is that a request the app cannot honour NEVER becomes a run. #337's
/// pending A/B has to be two separate launches (the governor's per-turn
/// refusal budget accumulates across a run, so sequential cells are
/// order-confounded), which means one cell per launch, which means a mistyped
/// cell name would otherwise produce a full-default run that LOOKS like the
/// requested one.
struct ActionBatteryCellSelectionTests {

    private typealias Cell = LocalChatBackend.ActionBatteryCell
    private let fallback: [Cell] = LocalChatBackend.calendarBatteryCells

    private func resolve(_ requested: [String]?,
                         fallback: [Cell]? = LocalChatBackend.calendarBatteryCells)
        -> ActionBatteryCellSelection.Outcome {
        ActionBatteryCellSelection.resolve(requested: requested,
                                           instrument: "calendar", default: fallback)
    }

    // MARK: - round trip

    /// Every case is reachable by its own raw value. A case the wire cannot
    /// name is a cell no launch can select, which is the silent half of the
    /// same disease.
    @Test func everyKnownCellRoundTripsThroughItsRawValue() {
        for cell in Cell.allCases {
            #expect(resolve([cell.rawValue]) == .resolved([cell]),
                    "\(cell.rawValue) did not round-trip")
        }
    }

    @Test func orderIsPreservedBecauseCellOrderIsRunOrder() {
        #expect(resolve(["armed-cardrollback", "armed"])
                == .resolved([.armedCardrollback, .armed]))
        #expect(resolve(["armed", "armed-cardrollback"])
                == .resolved([.armed, .armedCardrollback]))
    }

    /// A repeated cell runs twice and the record says so — coalescing would
    /// silently halve a requested denominator.
    @Test func duplicatesArePreservedRatherThanCoalesced() {
        #expect(resolve(["armed", "armed"]) == .resolved([.armed, .armed]))
    }

    @Test func surroundingWhitespaceIsTrimmed() {
        #expect(resolve([" armed ", "\tarmed-cardrollback"])
                == .resolved([.armed, .armedCardrollback]))
    }

    // MARK: - the default path

    /// The bar: with nothing requested the instrument runs its OWN constant,
    /// unchanged. `calendarBatteryCells` is the list #200L pinned.
    @Test func noRequestFallsBackToTheInstrumentsOwnPinnedCells() {
        #expect(resolve(nil) == .resolved(fallback))
        #expect(fallback == [.armed, .armedCardrollback, .armedSpiralfix])
    }

    /// `scripts/mac/run-instrument.sh` exports
    /// `DEVICECTL_CHILD_TALARIA_CELLS="$CELLS"` unconditionally, empty when
    /// `--cells` was not passed — so an empty request is the DEFAULT wire
    /// state of every existing harness invocation and must mean "not
    /// requested", never "run zero cells".
    @Test func anEmptyRequestIsTheUnsetWireStateAndFallsBack() {
        #expect(resolve([]) == .resolved(fallback))
        #expect(resolve([""]) == .resolved(fallback))
        #expect(resolve(["   ", "\t"]) == .resolved(fallback))
    }

    /// An instrument with no cell dimension and no request keeps working
    /// exactly as before — nil in, nil out, closure ignores it.
    @Test func noRequestAndNoCellDimensionResolvesToNil() {
        #expect(resolve(nil, fallback: nil) == .resolved(nil))
        #expect(resolve([], fallback: nil) == .resolved(nil))
    }

    // MARK: - refusals

    @Test func anUnknownNameIsRefusedAndTheRefusalNamesIt() throws {
        let outcome = resolve(["armed-nosuchcell"])
        guard case .refused(let reason) = outcome else {
            Issue.record("expected a refusal, got \(outcome)"); return
        }
        #expect(reason.contains("armed-nosuchcell"))
        #expect(reason.contains("unknown"))
    }

    /// The whole request dies, not just the bad name — a partially-applied
    /// request is the exact failure this file exists to prevent.
    @Test func oneUnknownNameRefusesTheEntireRequest() {
        let outcome = resolve(["armed", "armed-nosuchcell", "armed-cardrollback"])
        if case .resolved(let cells) = outcome {
            Issue.record("a bad name was dropped and \(cells as Any) would have run")
        }
    }

    @Test func everyUnknownNameIsReportedNotJustTheFirst() throws {
        let outcome = resolve(["nope-one", "armed", "nope-two"])
        guard case .refused(let reason) = outcome else {
            Issue.record("expected a refusal, got \(outcome)"); return
        }
        #expect(reason.contains("nope-one") && reason.contains("nope-two"))
    }

    /// Case matters: the raw values are lowercase-kebab and a near-miss must
    /// not be silently coerced into a real cell.
    @Test func aNameThatDiffersOnlyByCaseIsStillUnknown() {
        if case .resolved = resolve(["ARMED"]) {
            Issue.record("\"ARMED\" resolved; raw values are exact")
        }
    }

    /// Requesting cells of an instrument that has no `ActionBatteryCell`
    /// dimension is refused rather than ignored — forwarding to `shape` or
    /// `two-turn` would be the same silent drop wearing a different hat.
    @Test func cellsRequestedOfAnInstrumentWithNoCellDimensionAreRefused() throws {
        let outcome = ActionBatteryCellSelection.resolve(
            requested: ["armed"], instrument: "shape", default: nil)
        guard case .refused(let reason) = outcome else {
            Issue.record("expected a refusal, got \(outcome)"); return
        }
        #expect(reason.contains("shape"))
    }

    /// The refusal text is the artifact's `refusalReason` — a human reading
    /// `latest.json` gets the valid names without going to the source.
    @Test func theRefusalTextCarriesTheKnownNames() throws {
        guard case .refused(let reason) = resolve(["armed-nosuchcell"]) else {
            Issue.record("expected a refusal"); return
        }
        #expect(reason.contains("armed-cardrollback"))
        #expect(ActionBatteryCellSelection.knownNames.count == Cell.allCases.count)
    }

    // MARK: - the registry columns the resolver reads

    /// `defaultCells` is load-bearing (the conductor substitutes it), so a
    /// wrong value is a wrong run. These pin the two the #337 A/B uses.
    @Test func theCalendarInstrumentDeclaresItsPinnedCells() throws {
        let calendar = try #require(InstrumentRegistry.spec(named: "calendar"))
        #expect(calendar.defaultCells == LocalChatBackend.calendarBatteryCells)
        #expect(calendar.defaultCells == [.armed, .armedCardrollback, .armedSpiralfix])
    }

    @Test func actionFamilyEntriesDeclareCellsAndTheOthersDeclareNone() throws {
        for name in ["action", "calendar", "spiral", "routed", "decline",
                     "read-tool", "motion-scope", "deadend-reconsider"] {
            let spec = try #require(InstrumentRegistry.spec(named: name))
            #expect(spec.defaultCells?.isEmpty == false,
                    "\(name) is an action-family instrument with no declared cells")
        }
        // Other cell types (or none at all) — a `TALARIA_CELLS` request for
        // these must refuse, which only works while they declare nil.
        for name in ["shape", "two-turn", "honesty", "honesty-v2",
                     "router-probe", "tokencount-preflight"] {
            let spec = try #require(InstrumentRegistry.spec(named: name))
            #expect(spec.defaultCells == nil,
                    "\(name) declares ActionBatteryCells it cannot run")
        }
    }

    /// A declared default that is empty would run nothing and report a clean
    /// zero-cell run — never legitimate.
    @Test func noInstrumentDeclaresAnEmptyDefaultCellList() {
        for spec in InstrumentRegistry.all {
            if let cells = spec.defaultCells {
                #expect(!cells.isEmpty, "\(spec.name) declares an empty cell list")
            }
        }
    }
}
#endif
