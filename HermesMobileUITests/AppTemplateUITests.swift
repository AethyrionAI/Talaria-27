import XCTest

final class HermesMobileUITests: XCTestCase {
    private struct UITestLaunchContext {
        private struct ExternalConfiguration: Decodable {
            let setupCode: String?
            let pairingMode: String?
        }

        private static let configurationPath = "/tmp/hermesmobile-uitest-config.json"

        let defaultsSuite = "uitest.defaults.\(UUID().uuidString)"
        let keychainService = "uitest.keychain.\(UUID().uuidString)"
        let setupCode: String
        let pairingMode: String

        init(
            setupCodeOverride: String? = ProcessInfo.processInfo.environment["UITEST_SETUP_CODE"],
            pairingMode: String = ProcessInfo.processInfo.environment["UITEST_PAIRING_MODE"] ?? "mock"
        ) {
            let externalConfiguration = Self.loadExternalConfiguration()
            self.pairingMode = externalConfiguration?.pairingMode ?? pairingMode

            let resolvedSetupCode = setupCodeOverride ?? externalConfiguration?.setupCode
            if let resolvedSetupCode, !resolvedSetupCode.isEmpty {
                self.setupCode = resolvedSetupCode
                return
            }

            self.setupCode = "ABCD-EFGH"
        }

        private static func loadExternalConfiguration() -> ExternalConfiguration? {
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: configurationPath)) else {
                return nil
            }

            return try? JSONDecoder().decode(ExternalConfiguration.self, from: data)
        }
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testManualPairingFlowShowsMainTabs() throws {
        let context = UITestLaunchContext()
        let app = makeApp(context: context)
        app.launch()

        XCTAssertTrue(app.staticTexts["Connect Your Hermes"].waitForExistence(timeout: 5))
        completePairing(in: app, setupCode: context.setupCode)

        XCTAssertTrue(app.tabBars.buttons["Chat"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Talk"].exists)
        XCTAssertTrue(app.tabBars.buttons["Inbox"].exists)
        XCTAssertTrue(app.tabBars.buttons["Settings"].exists)
    }

    @MainActor
    func testChatSendFlow() throws {
        let context = UITestLaunchContext()
        let app = makeApp(context: context)
        let message = "UI live chat smoke test"
        let chatResponseTimeout: TimeInterval = context.pairingMode == "mock" ? 20 : 60

        app.launch()
        completePairing(in: app, setupCode: context.setupCode)

        let input = app.textFields["Message Hermes."]
        XCTAssertTrue(input.waitForExistence(timeout: 5))

        input.tap()
        input.typeText(message)
        app.buttons["Send message"].tap()

        XCTAssertTrue(app.staticTexts[message].waitForExistence(timeout: chatResponseTimeout))
    }

    @MainActor
    func testPairedLaunchSkipsOnboarding() throws {
        let context = UITestLaunchContext()
        let app = makeApp(context: context)
        app.launch()
        completePairing(in: app, setupCode: context.setupCode)
        XCTAssertTrue(app.tabBars.buttons["Settings"].waitForExistence(timeout: 5))

        app.terminate()

        let relaunchedApp = makeApp(context: context)
        relaunchedApp.launch()

        XCTAssertFalse(relaunchedApp.staticTexts["Connect Your Hermes"].waitForExistence(timeout: 2))
        XCTAssertTrue(relaunchedApp.tabBars.buttons["Chat"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testDisconnectReturnsToOnboarding() throws {
        let context = UITestLaunchContext()
        let app = makeApp(context: context)
        app.launch()
        completePairing(in: app, setupCode: context.setupCode)

        app.tabBars.buttons["Settings"].tap()
        let manageButton = app.buttons["Host Status"]
        XCTAssertTrue(manageButton.waitForExistence(timeout: 5))
        manageButton.tap()

        let disconnectButton = app.buttons["Disconnect Hermes"]
        XCTAssertTrue(disconnectButton.waitForExistence(timeout: 5))
        disconnectButton.tap()

        XCTAssertTrue(app.staticTexts["Connect Your Hermes"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testSettingsCanShowHostStatusScreen() throws {
        let context = UITestLaunchContext()
        let app = makeApp(context: context)
        app.launch()
        completePairing(in: app, setupCode: context.setupCode)

        app.tabBars.buttons["Settings"].tap()
        let manageHostButton = app.buttons["Host Status"]
        XCTAssertTrue(manageHostButton.waitForExistence(timeout: 5))
        manageHostButton.tap()

        XCTAssertTrue(app.navigationBars["Connect Host"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Setup From Your Hermes Machine"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "hermes-mobile pair-phone")).firstMatch.exists)
    }

    @MainActor
    func testLaunchPerformance() throws {
        let context = UITestLaunchContext()
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            let app = makeApp(context: context)
            app.launch()
        }
    }

    @MainActor
    private func makeApp(context: UITestLaunchContext) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["UITEST_DEFAULTS_SUITE"] = context.defaultsSuite
        app.launchEnvironment["UITEST_KEYCHAIN_SERVICE"] = context.keychainService
        app.launchEnvironment["UITEST_PAIRING_MODE"] = context.pairingMode
        return app
    }

    @MainActor
    private func completePairing(in app: XCUIApplication, setupCode: String) {
        app.buttons["Enter Setup Code"].tap()

        let setupCodeField = app.textFields["Setup code"]
        XCTAssertTrue(setupCodeField.waitForExistence(timeout: 5))
        setupCodeField.tap()
        setupCodeField.typeText(setupCode)
        app.buttons["Connect Hermes"].tap()

        XCTAssertTrue(app.tabBars.buttons["Chat"].waitForExistence(timeout: 5))
    }
}
