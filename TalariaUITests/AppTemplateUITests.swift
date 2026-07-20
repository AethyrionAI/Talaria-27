import XCTest

/// #135: the template pairing-flow tests, refreshed for the #31
/// no-pairing-wall world. First launch lands in a working on-device chat;
/// pairing is a Settings-level upgrade (Settings → Connect Hermes Desktop →
/// the relocated ConnectHermesScreen). A successful pair swaps the root to
/// the permissions onboarding once; Continue (no grants) returns to chat.
///
/// The mock scaffolding survives from the template: `UITEST_PAIRING_MODE=mock`
/// routes `PairingStore` at `MockPairingService` (any well-formed code
/// redeems), and `/tmp/hermesmobile-uitest-config.json` can inject a live
/// setup code + pairing mode for an end-to-end run against a real relay.
final class TalariaUITests: XCTestCase {
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

            // Any 8 characters from PhonePairingCode's alphabet (no I/O/0/1).
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

    // MARK: - Flows

    /// #31: no pairing wall — the working on-device chat IS the landing state.
    @MainActor
    func testStandaloneFirstLaunchLandsInChat() throws {
        let context = UITestLaunchContext()
        let app = makeApp(context: context)
        app.launch()
        dismissPermissionsOnboardingIfNeeded(in: app)

        guard let composer = waitForComposer(in: app, timeout: 15) else {
            XCTFail("chat composer should be the first-launch landing state (no pairing wall, #31)")
            return
        }
        XCTAssertTrue(composer.exists)
        XCTAssertTrue(app.buttons["Start voice mode"].exists)
        XCTAssertTrue(app.buttons["Open settings"].exists)
        XCTAssertFalse(app.buttons["Enter Code Manually"].exists,
                       "the pairing screen must not be the landing state (#31)")
    }

    /// Pairing is a Settings-level upgrade now: Settings → Connect Hermes
    /// Desktop → manual code entry → mock redeem → the one-time post-pair
    /// permissions onboarding → back in chat.
    @MainActor
    func testMockPairingViaSettingsEntryPoint() throws {
        let context = UITestLaunchContext()
        let app = makeApp(context: context)
        app.launch()
        dismissPermissionsOnboardingIfNeeded(in: app)

        completePairing(in: app, setupCode: context.setupCode)

        XCTAssertNotNil(waitForComposer(in: app, timeout: 15),
                        "a successful pair should land back in chat")
    }

    /// Chat send against the deterministic on-device synthetic turn (the #120
    /// seam): no live model or host required. Routing note: with no Hermes API
    /// key configured the backend router picks the local brain unconditionally
    /// — this is the standalone send path, mock-paired or not.
    @MainActor
    func testChatSendFlow() throws {
        let context = UITestLaunchContext()
        let app = makeApp(context: context)
        app.launchEnvironment["UITEST_DUPID_PROBE"] = "1"
        app.launch()
        dismissPermissionsOnboardingIfNeeded(in: app)

        guard let composer = waitForComposer(in: app, timeout: 15) else {
            XCTFail("chat composer should be reachable for the send flow")
            return
        }

        let message = "UI chat send smoke test"
        composer.tap()
        composer.typeText(message)

        let send = app.buttons["Send message"]
        XCTAssertTrue(send.waitForExistence(timeout: 5),
                      "send button should appear once the composer holds text")
        send.tap()

        XCTAssertTrue(app.staticTexts[message].waitForExistence(timeout: 10),
                      "the sent message should render in the transcript")
        XCTAssertTrue(app.staticTexts["Acknowledged \(message)"].waitForExistence(timeout: 20),
                      "the synthetic on-device reply should render")
    }

    /// The paired skip-path: a relaunch on the same defaults suite + keychain
    /// service restores the pairing — straight to chat, no repeated
    /// permissions onboarding, and Settings no longer offers the unpaired
    /// upgrade row.
    @MainActor
    func testPairedRelaunchSkipsPairingEntry() throws {
        let context = UITestLaunchContext()
        let app = makeApp(context: context)
        app.launch()
        dismissPermissionsOnboardingIfNeeded(in: app)
        completePairing(in: app, setupCode: context.setupCode)
        XCTAssertNotNil(waitForComposer(in: app, timeout: 15))

        app.terminate()

        let relaunchedApp = makeApp(context: context)
        relaunchedApp.launch()

        guard let composer = waitForComposer(in: relaunchedApp, timeout: 15) else {
            XCTFail("paired relaunch should land directly in chat")
            return
        }
        XCTAssertTrue(composer.exists)
        XCTAssertFalse(relaunchedApp.buttons["Enter Code Manually"].exists)

        // Paired state survived the relaunch: the Settings upgrade row only
        // renders while unpaired.
        relaunchedApp.buttons["Open settings"].tap()
        XCTAssertNotNil(waitForButton(containing: "Hermes Host", in: relaunchedApp, timeout: 5),
                        "the Settings index should present")
        XCTAssertNil(waitForButton(containing: "Connect Hermes Desktop", in: relaunchedApp, timeout: 2),
                     "a paired install must not offer the unpaired upgrade row")
    }

    /// Disconnect returns cleanly to the standalone chat — the wall is gone
    /// (#31), and the Settings upgrade row comes back. Traverses the paired
    /// host-management screen on the way (the old host-status assertions live
    /// here now).
    @MainActor
    func testDisconnectReturnsToStandaloneChat() throws {
        let context = UITestLaunchContext()
        let app = makeApp(context: context)
        app.launch()
        dismissPermissionsOnboardingIfNeeded(in: app)
        completePairing(in: app, setupCode: context.setupCode)
        XCTAssertNotNil(waitForComposer(in: app, timeout: 15))

        // Paired management path: Settings → Hermes Host → Pair Device
        // (routes to .connectHost, which resolves to the host status screen
        // while paired).
        app.buttons["Open settings"].tap()
        guard let hostRow = waitForButton(containing: "Hermes Host", in: app, timeout: 5) else {
            XCTFail("Settings should offer the Hermes Host row")
            return
        }
        hostRow.tap()

        guard let pairDevice = waitForButton(containing: "Pair Device", in: app, timeout: 5) else {
            XCTFail("the Hermes Host screen should offer the Pair Device action")
            return
        }
        pairDevice.tap()

        guard let disconnect = waitForButton(containing: "Disconnect", in: app, timeout: 5) else {
            XCTFail("the paired host screen should offer Disconnect")
            return
        }
        disconnect.tap()

        // #31: back in the standalone chat, no wall.
        guard let composer = waitForComposer(in: app, timeout: 15) else {
            XCTFail("disconnect should land back in the standalone chat")
            return
        }
        XCTAssertTrue(composer.exists)
        XCTAssertFalse(app.buttons["Enter Code Manually"].exists,
                       "no pairing wall may return after disconnect (#31)")

        // Standalone again: the upgrade row is back.
        app.buttons["Open settings"].tap()
        XCTAssertNotNil(waitForButton(containing: "Connect Hermes Desktop", in: app, timeout: 5),
                        "an unpaired install should offer the Settings upgrade row again")
    }

    // MARK: - Pairing helper

    /// Drives the #31 Settings-level pairing flow end to end: opens Settings,
    /// enters the relocated ConnectHermesScreen through the upgrade row,
    /// types the code, redeems, and completes the one-time post-pair
    /// permissions onboarding.
    @MainActor
    private func completePairing(in app: XCUIApplication, setupCode: String) {
        let settingsButton = app.buttons["Open settings"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 10))
        settingsButton.tap()

        // The upgrade row is a plain SwiftUI Button whose accessibility label
        // concatenates title + subtitle + UPGRADE — match by containment.
        guard let connectRow = waitForButton(containing: "Connect Hermes Desktop", in: app, timeout: 5) else {
            XCTFail("Settings should offer the Connect Hermes Desktop upgrade row while unpaired")
            return
        }
        connectRow.tap()

        // ConnectHermesScreen (the sheet dismissed; pushed on the main stack).
        let manualEntry = app.buttons["Enter Code Manually"]
        XCTAssertTrue(manualEntry.waitForExistence(timeout: 5))
        manualEntry.tap()

        let setupCodeField = app.textFields["Setup code"]
        XCTAssertTrue(setupCodeField.waitForExistence(timeout: 5))
        setupCodeField.tap()
        // Strip the display dash — the field's formatter reinserts it, and
        // skipping the "-" key avoids a keyboard-plane flake.
        setupCodeField.typeText(setupCode.replacingOccurrences(of: "-", with: ""))

        // The GlowButton is titled "Pair Device" but carries an explicit
        // "Connect Hermes" accessibility label.
        let pairButton = app.buttons["Connect Hermes"]
        XCTAssertTrue(pairButton.waitForExistence(timeout: 5))
        pairButton.tap()

        // A successful pair swaps the root to the permissions onboarding.
        guard let continueButton = waitForButton(containing: "Continue", in: app, timeout: 10) else {
            XCTFail("a successful pair should present the permissions onboarding")
            return
        }
        continueButton.tap()

        XCTAssertTrue(app.buttons["Open settings"].waitForExistence(timeout: 10))
    }

    // MARK: - Shared locator helpers

    /// A stale `hermes.needsPermissionsOnboarding` flag in STANDARD defaults
    /// (it deliberately lives outside the per-test suite) can leak the
    /// onboarding onto a fresh launch — tolerate it, same as
    /// MessageIdentityUITests. GlowButton uppercases its title into the
    /// accessibility label ('CONTINUE', not 'Continue' — hierarchy dump
    /// 2026-07-18); both are checked.
    @MainActor
    private func dismissPermissionsOnboardingIfNeeded(in app: XCUIApplication) {
        let uppercased = app.buttons["CONTINUE"]
        let titleCased = app.buttons["Continue"]
        let deadline = Date(timeIntervalSinceNow: 5)
        repeat {
            if uppercased.exists {
                uppercased.tap()
                return
            }
            if titleCased.exists {
                titleCased.tap()
                return
            }
            // Already in chat — nothing leaked.
            if composerInput(in: app).exists {
                return
            }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.5))
        } while Date() < deadline
    }

    /// Case-insensitive containment match, polling until the deadline. One
    /// helper covers both locator traps at once: GlowButton's uppercased
    /// titles (PAIR DEVICE, CONTINUE) and SwiftUI row buttons whose labels
    /// concatenate every child text.
    @MainActor
    private func waitForButton(
        containing text: String,
        in app: XCUIApplication,
        timeout: TimeInterval
    ) -> XCUIElement? {
        let candidate = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", text)
        ).firstMatch
        let deadline = Date(timeIntervalSinceNow: timeout)
        repeat {
            if candidate.exists { return candidate }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.5))
        } while Date() < deadline
        return nil
    }

    @MainActor
    private func makeApp(context: UITestLaunchContext) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["UITEST_DEFAULTS_SUITE"] = context.defaultsSuite
        app.launchEnvironment["UITEST_KEYCHAIN_SERVICE"] = context.keychainService
        app.launchEnvironment["UITEST_PAIRING_MODE"] = context.pairingMode
        return app
    }

    /// The composer may surface as a text field or a text view depending on
    /// the SwiftUI editor in use — check the identifier and the accessibility
    /// label across both.
    @MainActor
    private func composerInput(in app: XCUIApplication) -> XCUIElement {
        for candidate in [
            app.textFields["chat.composer"],
            app.textViews["chat.composer"],
            app.textFields["Reply to Hermes"],
            app.textViews["Reply to Hermes"],
        ] where candidate.exists {
            return candidate
        }
        return app.textViews["chat.composer"]
    }

    /// Polls the composer candidates until one exists (the screen may still
    /// be transitioning off onboarding when the first query runs).
    @MainActor
    private func waitForComposer(in app: XCUIApplication, timeout: TimeInterval) -> XCUIElement? {
        let deadline = Date(timeIntervalSinceNow: timeout)
        repeat {
            let candidate = composerInput(in: app)
            if candidate.exists { return candidate }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.5))
        } while Date() < deadline
        return nil
    }
}
