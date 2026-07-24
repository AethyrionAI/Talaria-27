import XCTest

/// #135: the template pairing-flow tests, refreshed for the #31
/// no-pairing-wall world. First launch lands in a working on-device chat;
/// pairing is a Settings-level upgrade (Settings → Connect Hermes Desktop →
/// the relocated ConnectHermesScreen). #137: a successful pair pops straight
/// back to chat — no permissions interstitial exists anymore (sensor
/// streaming is a separate Settings-level opt-in).
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
    /// Desktop → manual code entry → mock redeem → straight back in chat
    /// (#137: no post-pair permissions interstitial).
    @MainActor
    func testMockPairingViaSettingsEntryPoint() throws {
        let context = UITestLaunchContext()
        let app = makeApp(context: context)
        app.launch()

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

        // iOS 27 beta: this tap dismisses the settings sheet AND pushes the
        // host screen in one tick — under bundle-warm timing the synthesized
        // tap occasionally lands without invoking the action at all (screen
        // recording shows the sheet untouched 5s later; the same flow passes
        // in isolation). The pre-#137 CONTINUE interstitial masked this by
        // rebuilding the root after pairing. Re-tap once if nothing moved —
        // same spirit as the per-keystroke setup-code hedge above.
        var disconnect = waitForButton(containing: "Disconnect", in: app, timeout: 5)
        if disconnect == nil, pairDevice.exists {
            pairDevice.tap()
            disconnect = waitForButton(containing: "Disconnect", in: app, timeout: 5)
        }
        guard let disconnect else {
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
        // #164: assert the wall is GONE, not that it was never momentarily in
        // the tree. The composer and the dismissing wall coexist for a beat —
        // the reproduction on 2026-07-24 checked the composer at t=41.93s and
        // the wall 50ms later, catching the dismissal mid-flight.
        //
        // This deliberately does NOT paper over #31. A wall that genuinely
        // returned never disappears, so it still fails — it just fails after
        // the timeout instead of during someone else's animation. Do not
        // replace this with a sleep or a plain `.exists` check in either
        // direction: one masks the real defect, the other re-opens the flake.
        XCTAssertTrue(app.buttons["Enter Code Manually"].waitForNonExistence(timeout: 5),
                      "no pairing wall may return after disconnect (#31)")

        // Standalone again: the upgrade row is back.
        app.buttons["Open settings"].tap()
        XCTAssertNotNil(waitForButton(containing: "Connect Hermes Desktop", in: app, timeout: 5),
                        "an unpaired install should offer the Settings upgrade row again")
    }

    // MARK: - Pairing helper

    /// Drives the #31 Settings-level pairing flow end to end: opens Settings,
    /// enters the relocated ConnectHermesScreen through the upgrade row,
    /// types the code, and redeems — landing straight back in chat (#137).
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
        // One keystroke per typeText call: the field's onChange formatter
        // rewrites the binding when the display dash lands (5th character),
        // and a single fast burst loses keystrokes inside that rewrite
        // (observed on-sim: only ABCDEF of ABCDEFGH arrived). Per-call app
        // idling lets each reformat settle. The dash itself is stripped —
        // the formatter reinserts it, and skipping the "-" key avoids a
        // keyboard-plane switch.
        for character in setupCode.replacingOccurrences(of: "-", with: "") {
            setupCodeField.typeText(String(character))
        }

        // The GlowButton is titled "Pair Device" but carries an explicit
        // "Connect Hermes" accessibility label. It stays disabled until the
        // code is complete AND the relay URL validates — wait for enablement
        // so a dropped keystroke fails HERE, not as a downstream timeout.
        let pairButton = app.buttons["Connect Hermes"]
        XCTAssertTrue(pairButton.waitForExistence(timeout: 5))
        let enableDeadline = Date(timeIntervalSinceNow: 5)
        while !pairButton.isEnabled, Date() < enableDeadline {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.5))
        }
        XCTAssertTrue(pairButton.isEnabled,
                      "pair button should enable once the full code is present and the relay URL validates")
        pairButton.tap()

        // #137: a successful pair pops straight back to chat — no
        // permissions interstitial may appear.
        guard waitForComposer(in: app, timeout: 15) != nil else {
            XCTFail("a successful pair should land straight in chat (#137)")
            return
        }
        XCTAssertFalse(app.buttons["CONTINUE"].exists,
                       "the post-pair permissions wall must not return (#137)")
        XCTAssertTrue(app.buttons["Open settings"].waitForExistence(timeout: 10))
    }

    // MARK: - Shared locator helpers

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
