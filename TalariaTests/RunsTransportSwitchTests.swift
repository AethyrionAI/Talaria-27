import Foundation
import Testing
@testable import Talaria

struct RunsTransportSwitchTests {
    @Test func defaultsToOffAndSurvivesRoundTrip() throws {
        var settings = UserSettings()
        #expect(settings.useRunsTransport == false)
        settings.useRunsTransport = true
        let decoded = try JSONDecoder().decode(UserSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded.useRunsTransport == true)
    }

    @Test func legacyPayloadWithoutKeyDecodesOff() throws {
        let legacy = try JSONEncoder().encode(UserSettings())
        var obj = try #require(JSONSerialization.jsonObject(with: legacy) as? [String: Any])
        obj.removeValue(forKey: "useRunsTransport")
        let stripped = try JSONSerialization.data(withJSONObject: obj)
        let decoded = try JSONDecoder().decode(UserSettings.self, from: stripped)
        #expect(decoded.useRunsTransport == false)
    }
}
