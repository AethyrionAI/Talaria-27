#if DEBUG
import Foundation
import Testing
@testable import Talaria

/// #333: pure parse of the launch environment. Legacy #196 vars map onto
/// registry names so the old contract keeps working with no second mechanism.
struct InstrumentLaunchIntentTests {

    @Test func newVarsParseNameTrialsAndCells() {
        let intents = InstrumentLaunchIntent.parse([
            "TALARIA_RUN_INSTRUMENT": "action",
            "TALARIA_TRIALS": "5",
            "TALARIA_CELLS": "armed,armed-routed",
        ])
        #expect(intents == [InstrumentLaunchIntent(name: "action", trials: 5, cells: ["armed", "armed-routed"])])
    }

    @Test func trialsDefaultsToTenAndCellsToNil() {
        let intents = InstrumentLaunchIntent.parse(["TALARIA_RUN_INSTRUMENT": "shape"])
        #expect(intents == [InstrumentLaunchIntent(name: "shape", trials: 10, cells: nil)])
    }

    @Test func legacyVarsMapToRegistryNamesInLegacyOrder() {
        // #196's contract: battery first, then probe, both runnable in one launch.
        let intents = InstrumentLaunchIntent.parse([
            "TALARIA_AUTO_BATTERY": "3",
            "TALARIA_AUTO_ROUTER_PROBE": "4",
        ])
        #expect(intents == [
            InstrumentLaunchIntent(name: "shape", trials: 3, cells: nil),
            InstrumentLaunchIntent(name: "router-probe", trials: 4, cells: nil),
        ])
    }

    @Test func emptyOrGarbageEnvironmentParsesToNothing() {
        #expect(InstrumentLaunchIntent.parse([:]).isEmpty)
        #expect(InstrumentLaunchIntent.parse(["TALARIA_TRIALS": "5"]).isEmpty)
        #expect(InstrumentLaunchIntent.parse(["TALARIA_AUTO_BATTERY": "many"]).isEmpty)
    }
}
#endif
