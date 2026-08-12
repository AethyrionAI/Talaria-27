#if DEBUG
import Foundation

/// #333: one requested instrument run, parsed from launch environment.
/// Pure function of the env dictionary — trivially testable, no ProcessInfo.
struct InstrumentLaunchIntent: Equatable {
    var name: String
    var trials: Int
    var cells: [String]?

    static func parse(_ env: [String: String]) -> [InstrumentLaunchIntent] {
        var intents: [InstrumentLaunchIntent] = []
        // #196 legacy vars first, in their original order (battery, then probe).
        if let trials = env["TALARIA_AUTO_BATTERY"].flatMap(Int.init) {
            intents.append(.init(name: "shape", trials: trials, cells: nil))
        }
        if let trials = env["TALARIA_AUTO_ROUTER_PROBE"].flatMap(Int.init) {
            intents.append(.init(name: "router-probe", trials: trials, cells: nil))
        }
        if let name = env["TALARIA_RUN_INSTRUMENT"], !name.isEmpty {
            let trials = env["TALARIA_TRIALS"].flatMap(Int.init) ?? 10
            let cells = env["TALARIA_CELLS"].map { $0.split(separator: ",").map(String.init) }
            intents.append(.init(name: name, trials: trials, cells: cells))
        }
        return intents
    }
}
#endif
