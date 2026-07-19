import Foundation
import Testing

/// #123 — pins the TalariaShare share-extension configuration by reading the
/// BUILT appex's Info.plist out of the host app's PlugIns dir (same
/// built-artifact-over-source-yaml pattern as the #108 built-plist guards).
/// An xcodegen regen or project.yml edit that drops an activation type, or
/// swaps the dictionary rule for a TRUEPREDICATE (App Review rejection),
/// fails here instead of on a device.
struct ShareExtensionConfigTests {

    private static func builtSharePlist() throws -> [String: Any] {
        let plugIns = try #require(Bundle.main.builtInPlugInsURL,
                                   "test host app bundle has no PlugIns dir")
        let url = plugIns.appendingPathComponent("TalariaShare.appex/Info.plist")
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        return try #require(plist as? [String: Any])
    }

    @Test func shareExtensionIsEmbeddedWithExpectedIdentity() throws {
        let plist = try Self.builtSharePlist()
        #expect(plist["CFBundleIdentifier"] as? String == "org.aethyrion.talaria27.share")
        let ext = try #require(plist["NSExtension"] as? [String: Any])
        #expect(ext["NSExtensionPointIdentifier"] as? String == "com.apple.share-services")
        #expect(ext["NSExtensionPrincipalClass"] as? String == "ShareViewController")
    }

    @Test func activationRuleIsTheExactPinnedDictionary() throws {
        let plist = try Self.builtSharePlist()
        let ext = try #require(plist["NSExtension"] as? [String: Any])
        let attributes = try #require(ext["NSExtensionAttributes"] as? [String: Any])

        // A TRUEPREDICATE rule arrives as a String — the dictionary cast is
        // itself the guard against that regression.
        let rule = try #require(attributes["NSExtensionActivationRule"] as? [String: Any],
                                "activation rule must be a dictionary, never a predicate string")

        #expect(rule["NSExtensionActivationSupportsWebURLWithMaxCount"] as? Int == 1)
        #expect(rule["NSExtensionActivationSupportsImageWithMaxCount"] as? Int == 4)
        #expect(rule["NSExtensionActivationSupportsFileWithMaxCount"] as? Int == 1)
        #expect(rule["NSExtensionActivationSupportsText"] as? Bool == true)
        // Exactly these four keys — a supported type can't be silently
        // dropped, and nothing broadens activation without a test edit.
        #expect(rule.count == 4)
    }
}
