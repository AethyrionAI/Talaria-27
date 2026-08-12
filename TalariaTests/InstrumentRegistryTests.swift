#if DEBUG
import Foundation
import Testing
@testable import Talaria

/// #333 bar B's substrate: the registry is the ONE dispatch table both the
/// Developer-screen buttons and the launch-env trigger resolve through.
struct InstrumentRegistryTests {

    @Test func namesAreUniqueAndKebabCase() {
        let names = InstrumentRegistry.all.map(\.name)
        #expect(Set(names).count == names.count)
        for name in names {
            #expect(name == name.lowercased() && !name.contains(" "), "bad name: \(name)")
        }
    }

    @Test func canonicalEntriesResolveWithTheirCapabilityFlags() throws {
        let shape = try #require(InstrumentRegistry.spec(named: "shape"))
        #expect(shape.confirmationMode == .autoDecline)
        #expect(!shape.writesEventKit && !shape.writesAlarms)

        let action = try #require(InstrumentRegistry.spec(named: "action"))
        #expect(action.confirmationMode == .autoAccept)
        #expect(action.writesEventKit && action.writesAlarms)

        let readTool = try #require(InstrumentRegistry.spec(named: "read-tool"))
        #expect(readTool.confirmationMode == .none)
        #expect(!readTool.writesEventKit && !readTool.writesAlarms)

        #expect(InstrumentRegistry.spec(named: "router-probe") != nil)
        #expect(InstrumentRegistry.spec(named: "no-such-instrument") == nil)
    }

    @Test func alarmWritersAreAlwaysEventKitOrAcceptMode() {
        // An instrument that writes alarms but never confirms is a spec bug:
        // alarm writes only happen on the accept path.
        for spec in InstrumentRegistry.all where spec.writesAlarms {
            #expect(spec.confirmationMode == .autoAccept, "\(spec.name) writes alarms without accept mode")
        }
    }
}
#endif
