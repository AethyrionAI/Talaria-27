import XCTest

/// #135: the template connect-flow tests, refreshed for the #31
/// no-pairing-wall world. First launch lands in a working on-device chat;
/// connecting a host is a Settings-level upgrade. #137: a successful connect
/// pops straight back to chat — no permissions interstitial exists anymore
/// (sensor sharing is a separate Settings-level opt-in).
///
/// **REWRITTEN, NOT DELETED, by #309 Lane B (bar 309-B10, 2026-08-25.)** The
/// journeys below drove `ConnectHermesScreen`: an 8-character relay code, a
/// Relay URL field, and a redeem against a service retired on both hosts.
/// Every one of those is gone. What the journeys were actually FOR is not —
/// "a user can reach the connect flow from Settings, complete it, and land
/// back in chat", and "a disconnect returns cleanly to standalone" are the
/// same two claims about the same product — so each was re-pointed at
/// Connect Host rather than tombstoned. Only the code-field mechanics died,
/// because only they were about the relay.
///
/// The mock scaffolding survives from the template: `UITEST_PAIRING_MODE=mock`
/// (or any detected test run, per #144's `TestRunGuard`) routes the app at its
/// doubles, where the Connect Host PROBE answers connected for any well-formed
/// pair of values — the direct heir of `MockPairingService`, and for the same
/// reason: a UITest has no host to reach, and the journey under test is the
/// flow. The wire itself is `ConnectHostProbeTests`' subject, on stubs that
/// can fail four different ways.
final class TalariaUITests: XCTestCase {
    private struct UITestLaunchContext {
        private struct ExternalConfiguration: Decodable {
            let gatewayURL: String?
            let apiKey: String?
            let pairingMode: String?
        }

        private static let configurationPath = "/tmp/talariamobile-uitest-config.json"

        let defaultsSuite = "uitest.defaults.\(UUID().uuidString)"
        let keychainService = "uitest.keychain.\(UUID().uuidString)"
        /// #309 Lane B: the two values Connect Host acquires, replacing the
        /// 8-character relay `setupCode`. The external-config injection point
        /// survives so an end-to-end run against a REAL host is still possible
        /// — it just names the gateway now, which is what a real run needs.
        let gatewayURL: String
        let apiKey: String
        let pairingMode: String

        init(
            gatewayOverride: String? = ProcessInfo.processInfo.environment["UITEST_GATEWAY_URL"],
            keyOverride: String? = ProcessInfo.processInfo.environment["UITEST_API_KEY"],
            pairingMode: String = ProcessInfo.processInfo.environment["UITEST_PAIRING_MODE"] ?? "mock"
        ) {
            let externalConfiguration = Self.loadExternalConfiguration()
            self.pairingMode = externalConfiguration?.pairingMode ?? pairingMode

            let resolvedGateway = gatewayOverride ?? externalConfiguration?.gatewayURL
            self.gatewayURL = (resolvedGateway?.isEmpty == false)
                ? resolvedGateway! : "http://127.0.0.1:8642"
            let resolvedKey = keyOverride ?? externalConfiguration?.apiKey
            self.apiKey = (resolvedKey?.isEmpty == false) ? resolvedKey! : "uitest-api-server-key"
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
        // #309 Lane B: the negative used to name the pairing screen's manual
        // arm. Both wizard steps are named instead — the wizard is ENTERED,
        // never imposed (bar 309-B1), so neither step 0's choice nor step 1's
        // disclosure may exist at launch.
        XCTAssertFalse(app.buttons["connectHostWizard.connectMyHost"].exists,
                       "the Connect Host wizard must not be the landing state (#31)")
        XCTAssertFalse(app.buttons["connectHostWizard.enterManually"].exists,
                       "no part of the connect flow may be imposed at launch (#31)")
    }

    /// Connecting a host is a Settings-level upgrade: Settings → the upgrade
    /// row → the Connect Host WIZARD → the manual arm → a green check → step 3
    /// → straight back in chat (#137: no post-connect permissions
    /// interstitial).
    ///
    /// **Renamed from `testMockPairingViaSettingsEntryPoint`** with the flow
    /// it drives; the claim is unchanged.
    @MainActor
    func testConnectingAHostViaSettingsEntryPointLandsBackInChat() throws {
        let context = UITestLaunchContext()
        let app = makeApp(context: context)
        app.launch()

        completeConnect(in: app, context: context)

        XCTAssertNotNil(waitForComposer(in: app, timeout: 15),
                        "a successful connect should land back in chat")
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

    /// #257 lever 3a (bar 257-3a-B): the capability surface is reachable in
    /// ≤2 taps from a fresh chat — the empty-state chip is ONE tap — and
    /// typing /capabilities in the composer opens it. The sheet's rows are
    /// registry-derived, so a real per-tool row is asserted, not a title.
    @MainActor
    func testCapabilitiesSurfaceReachableByChipAndSlashCommand() throws {
        let context = UITestLaunchContext()
        let app = makeApp(context: context)
        app.launch()

        guard waitForComposer(in: app, timeout: 15) != nil else {
            XCTFail("chat composer should be the first-launch landing state")
            return
        }

        let chip = app.buttons["chat.capabilitiesChip"]
        XCTAssertTrue(chip.waitForExistence(timeout: 5),
                      "the fresh-chat empty state should carry the capabilities chip (257-3a-B)")
        chip.tap()

        let header = app.staticTexts["CAPABILITIES"]
        XCTAssertTrue(header.waitForExistence(timeout: 5),
                      "one tap on the chip should open the capability sheet (257-3a-B)")
        XCTAssertTrue(app.staticTexts["readHealth"].waitForExistence(timeout: 3),
                      "the sheet should render per-tool registry rows (257-3a-A)")

        let close = app.buttons["capabilities.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 3))
        close.tap()
        if !chip.waitForExistence(timeout: 3), close.exists {
            // Dismiss-tap hedge: a same-tick sheet tap can drop — one re-tap.
            close.tap()
        }
        XCTAssertTrue(chip.waitForExistence(timeout: 5),
                      "closing the sheet should land back on the fresh chat")

        guard let composer = waitForComposer(in: app, timeout: 5) else {
            XCTFail("composer should be reachable after the sheet closes")
            return
        }
        composer.tap()
        composer.typeText("/capabilities")
        let send = app.buttons["Send message"]
        XCTAssertTrue(send.waitForExistence(timeout: 5))
        send.tap()
        XCTAssertTrue(header.waitForExistence(timeout: 5),
                      "typing /capabilities should open the sheet (257-3a-B)")
    }

    /// 238-A (#238): a fresh install must NEVER present the iOS notification
    /// permission dialog — the notification surface is gone, so there is
    /// nothing left to ask for. Walks the exact trigger points the retired
    /// priming rode: first launch, then a dispatched send (#189 primed on
    /// EVERY send), asserting the springboard shows no alert at each settle.
    @MainActor
    func testFreshInstallNeverPresentsNotificationPermissionDialog() throws {
        let context = UITestLaunchContext()
        let app = makeApp(context: context)
        app.launch()

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

        guard let composer = waitForComposer(in: app, timeout: 15) else {
            XCTFail("chat composer should be the first-launch landing state")
            return
        }
        XCTAssertEqual(springboard.alerts.count, 0,
                       "no permission dialog may appear at first launch (238-A)")

        let message = "fresh install permission probe"
        composer.tap()
        composer.typeText(message)
        let send = app.buttons["Send message"]
        XCTAssertTrue(send.waitForExistence(timeout: 5))
        send.tap()

        XCTAssertTrue(app.staticTexts[message].waitForExistence(timeout: 10),
                      "the sent message should render in the transcript")
        // The retired priming fired here, on the dispatched send. A deliberate
        // bounded negative probe: give an alert 3 seconds to surface, then
        // require zero.
        _ = springboard.alerts.firstMatch.waitForExistence(timeout: 3)
        XCTAssertEqual(springboard.alerts.count, 0,
                       "no permission dialog may appear on a dispatched send (238-A)")
    }

    /// The connected skip-path: a relaunch on the same defaults suite +
    /// keychain service restores the host — straight to chat, no repeated
    /// permissions onboarding, and Settings no longer offers the upgrade row.
    ///
    /// **Renamed from `testPairedRelaunchSkipsPairingEntry`.** What it proves
    /// is now stronger than it was: the credentials it checks survived are the
    /// ones chat actually routes on, rather than a relay pairing record.
    @MainActor
    func testConnectedRelaunchSkipsTheConnectEntry() throws {
        let context = UITestLaunchContext()
        let app = makeApp(context: context)
        app.launch()
        completeConnect(in: app, context: context)
        XCTAssertNotNil(waitForComposer(in: app, timeout: 15))

        app.terminate()

        let relaunchedApp = makeApp(context: context)
        relaunchedApp.launch()

        guard let composer = waitForComposer(in: relaunchedApp, timeout: 15) else {
            XCTFail("a connected relaunch should land directly in chat")
            return
        }
        XCTAssertTrue(composer.exists)

        // The host survived the relaunch: the Settings upgrade row only
        // renders with no host configured. #252: the index is the subsystem
        // grid — assert the grid presents, then assert `settings.upgradeBanner`
        // is absent, plus the containment text as a second, independent probe.
        relaunchedApp.buttons["Open settings"].tap()
        XCTAssertTrue(relaunchedApp.otherElements["settings.grid"].waitForExistence(timeout: 5),
                      "the Settings index (subsystem grid) should present")
        XCTAssertFalse(relaunchedApp.buttons["settings.upgradeBanner"].exists,
                       "a connected install must not offer the settings.upgradeBanner row (#252)")
        XCTAssertNil(waitForButton(containing: "Connect Hermes Desktop", in: relaunchedApp, timeout: 2),
                     "a connected install must not offer the upgrade row")
    }

    /// Disconnect returns cleanly to the standalone chat — the wall is gone
    /// (#31), and the Settings upgrade row comes back. Traverses the Connect
    /// Host settings screen on the way.
    ///
    /// **Renamed from `testDisconnectReturnsToStandaloneChat`'s twin and
    /// re-pointed at the new surface.** It also now traverses the CONFIRM
    /// SHEET, which the old one-tap Disconnect had no equivalent of — design
    /// B4's "one button, both halves spelled out".
    @MainActor
    func testDisconnectingAHostReturnsToStandaloneChat() throws {
        let context = UITestLaunchContext()
        let app = makeApp(context: context)
        app.launch()
        completeConnect(in: app, context: context)
        XCTAssertNotNil(waitForComposer(in: app, timeout: 15))

        // Connected management path: Settings → Uplink card → Connect Host
        // (routes to .connectHost, which resolves to the manual screen once
        // credentials exist). #252: the Uplink card opens the deck directly
        // onto UplinkSettingsScreen, so Connect Host is one tap away.
        app.buttons["Open settings"].tap()
        let uplinkCard = app.buttons["settings.card.uplink"]
        XCTAssertTrue(uplinkCard.waitForExistence(timeout: 5),
                      "Settings should offer the settings.card.uplink card")
        uplinkCard.tap()

        guard let connectRow = waitForButton(containing: "Connect Host", in: app, timeout: 5) else {
            XCTFail("the Uplink deck page should offer the Connect Host action")
            return
        }
        connectRow.tap()

        // iOS 27 beta: this tap dismisses the settings sheet AND pushes the
        // screen in one tick — under bundle-warm timing the synthesized tap
        // occasionally lands without invoking the action at all (screen
        // recording shows the sheet untouched 5 s later; the same flow passes
        // in isolation). Re-tap once if nothing moved.
        var disconnect = app.buttons["connectHost.disconnect"]
        if !disconnect.waitForExistence(timeout: 5), connectRow.exists {
            connectRow.tap()
            disconnect = app.buttons["connectHost.disconnect"]
            _ = disconnect.waitForExistence(timeout: 5)
        }
        guard disconnect.exists else {
            XCTFail("the Connect Host screen should offer the disconnect row")
            return
        }
        disconnect.tap()

        // Design B4: one button, both halves spelled out. The confirm sheet is
        // part of the contract — a disconnect that skipped it would pass the
        // old test and fail the design.
        let confirm = app.buttons["connectHost.disconnectConfirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5),
                      "disconnect must confirm before it forgets anything (design B4)")
        confirm.tap()

        // The screen falls back to its EMPTY state in place — and the empty
        // state is not an error: it names the local brain as the current
        // answer (design A1).
        XCTAssertTrue(app.buttons["connectHost.scan"].waitForExistence(timeout: 10),
                      "after a disconnect the screen must return to its empty state")

        // …and it REPORTS the second half rather than assuming it: with no
        // plugin link in the test doubles the host cannot be told, and the
        // screen says so instead of claiming both halves happened (309-B6).
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS[c] %@", "wasn't reachable")
            ).firstMatch.waitForExistence(timeout: 5),
            "a disconnect the host was not told about must say so"
        )

        // #31: back in the standalone chat, no wall.
        app.navigationBars.buttons.firstMatch.tap()
        guard let composer = waitForComposer(in: app, timeout: 15) else {
            XCTFail("disconnect should land back in the standalone chat")
            return
        }
        XCTAssertTrue(composer.exists)

        // Standalone again: the upgrade banner is back. #252: assert both the
        // id and the containment text, same as the entry point.
        app.buttons["Open settings"].tap()
        XCTAssertTrue(app.buttons["settings.upgradeBanner"].waitForExistence(timeout: 10),
                      "a hostless install should offer the settings.upgradeBanner row again (#252)")
        XCTAssertNotNil(waitForButton(containing: "Connect Hermes Desktop", in: app, timeout: 5),
                        "a hostless install should offer the Settings upgrade row again")
    }

    // MARK: - Connect helper

    /// Drives the Connect Host wizard end to end: Settings → the upgrade row →
    /// step 0's CONNECT MY HOST → the manual arm → both values → CHECK →
    /// CONTINUE → START CHATTING.
    ///
    /// **Replaces `completePairing`.** Three of its mechanics went with the
    /// relay and are NOT ported, each for a stated reason:
    /// - the per-character Relay URL typing (#310/#405) — there is no relay
    ///   field, and the gateway field is bound to a local draft the model
    ///   never canonicalizes, which `ConnectHostDraftIntegrityTests` now
    ///   measures directly rather than inferring from a UI trace;
    /// - the setup-code reformatter hedges — the code field's `onChange`
    ///   formatter was the source of the dropped keystrokes those hedges
    ///   repaired, and it is deleted with `PhonePairingCode`;
    /// - the enablement poll before the pair button — kept, because the CHECK
    ///   button is still disabled until both values are present, and a dropped
    ///   keystroke must fail HERE rather than as a downstream timeout.
    @MainActor
    private func completeConnect(in app: XCUIApplication, context: UITestLaunchContext) {
        let settingsButton = app.buttons["Open settings"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 10))
        settingsButton.tap()

        // #252: the settings root is the subsystem grid, and the hostless
        // upgrade row is `settings.upgradeBanner`. Assert BOTH the id and the
        // "Connect Hermes Desktop" containment match resolve to the same row,
        // so a future relabel cannot silently drop one contract.
        let upgradeBanner = app.buttons["settings.upgradeBanner"]
        XCTAssertTrue(upgradeBanner.waitForExistence(timeout: 5),
                      "Settings should offer the settings.upgradeBanner row while hostless (#252)")
        XCTAssertNotNil(waitForButton(containing: "Connect Hermes Desktop", in: app, timeout: 5),
                        "the upgrade banner must still contain 'Connect Hermes Desktop' copy")
        upgradeBanner.tap()

        // **The wizard — reached by a TAP, never imposed (bar 309-B1).** That
        // it is here at all is the point: an install with no host gets the
        // wizard, and it got here because the user asked for it.
        let connectMyHost = app.buttons["connectHostWizard.connectMyHost"]
        XCTAssertTrue(connectMyHost.waitForExistence(timeout: 8),
                      "the Connect Host wizard should present from the Settings upgrade row")
        // …and the local path is offered alongside it, on the same step.
        XCTAssertTrue(app.buttons["connectHostWizard.startLocally"].exists,
                      "step 0 must offer START LOCALLY beside CONNECT MY HOST")
        XCTAssertTrue(app.buttons["connectHostWizard.notNow"].exists,
                      "Not now must be on every step (bar 309-B1)")
        connectMyHost.tap()

        // Step 1 is scan-first; the manual arm is a disclosure.
        let enterManually = app.buttons["connectHostWizard.enterManually"]
        XCTAssertTrue(enterManually.waitForExistence(timeout: 5),
                      "step 1 should offer the manual arm alongside the scanner")
        enterManually.tap()

        let gatewayField = app.textFields["Gateway URL"]
        XCTAssertTrue(gatewayField.waitForExistence(timeout: 5),
                      "the manual arm must offer a Gateway URL field")
        gatewayField.tap()
        gatewayField.typeText(context.gatewayURL)

        let keyField = app.secureTextFields["API key"]
        XCTAssertTrue(keyField.waitForExistence(timeout: 5),
                      "the manual arm must offer an API key field")
        keyField.tap()
        keyField.typeText(context.apiKey)

        // The check button stays disabled until BOTH values are present — so
        // a dropped keystroke fails here, with the field values in the
        // message, rather than as a downstream timeout.
        let checkButton = app.buttons["connectHostWizard.check"]
        XCTAssertTrue(checkButton.waitForExistence(timeout: 5))
        let enableDeadline = Date(timeIntervalSinceNow: 10)
        while !checkButton.isEnabled, Date() < enableDeadline {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.5))
        }
        XCTAssertTrue(checkButton.isEnabled,
                      """
                      CHECK & CONNECT should enable once both values are present \
                      (gateway field: '\(gatewayField.value as? String ?? "?")')
                      """)
        checkButton.tap()

        // Step 2 → the green card, then step 3.
        let carryOn = app.buttons["connectHostWizard.continue"]
        XCTAssertTrue(carryOn.waitForExistence(timeout: 15),
                      "a green check should reach the connected card")
        carryOn.tap()

        // iOS 27 beta, bundle-warm: a synthesized tap occasionally lands
        // without invoking the action — the same signature this file already
        // hedges for on the settings-sheet transition, and MEASURED here: all
        // three connect journeys passed in isolation and failed together on
        // the full-bundle gate run at exactly this step. One verified re-tap,
        // never a sleep: if the wizard genuinely never advances, the second
        // wait still fails and the test still reds.
        let startChatting = app.buttons["connectHostWizard.startChatting"]
        if !startChatting.waitForExistence(timeout: 10), carryOn.exists {
            carryOn.tap()
        }
        XCTAssertTrue(startChatting.waitForExistence(timeout: 10),
                      "step 3 should offer START CHATTING")
        startChatting.tap()

        // #137: landing straight in chat — no permissions interstitial.
        guard waitForComposer(in: app, timeout: 15) != nil else {
            XCTFail("a successful connect should land straight in chat (#137)")
            return
        }
        XCTAssertFalse(app.buttons["CONTINUE"].exists,
                       "the post-connect permissions wall must not return (#137)")
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

    /// T9: the deck counter updates asynchronously after tap/swipe/dot-tap,
    /// so asserting `counter.label` the instant the gesture returns is a
    /// proven flake source. Same poll idiom as `waitForButton` above —
    /// re-check on a short interval until the deadline instead of a single
    /// immediate read. The caller still asserts for real afterward, so a
    /// label that never catches up fails the test rather than being masked.
    @MainActor
    private func waitForCounter(
        _ element: XCUIElement,
        toEqual expected: String,
        timeout: TimeInterval
    ) {
        let deadline = Date(timeIntervalSinceNow: timeout)
        repeat {
            if element.label == expected { return }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.2))
        } while Date() < deadline
    }

    /// #244 (replaces the #239 sub-screen test IN PLACE): the Appearance tab
    /// is a full-bleed channel browser — one theme per channel, applies as
    /// you land. Steps to Solar Forge with the deterministic › button (the
    /// browser opens on Deep Field's channel in a fresh UITest context, and
    /// Solar Forge is the next Flagship channel), then verifies the pick
    /// PERSISTED by relaunch-free re-entry: leave Appearance, reopen, and
    /// the browser must open on Solar Forge's channel.
    @MainActor
    func testAppearanceChannelBrowserAppliesThemeOnLand() throws {
        let context = UITestLaunchContext()
        let app = makeApp(context: context)
        app.launch()

        guard waitForComposer(in: app, timeout: 15) != nil else {
            XCTFail("chat composer should be the first-launch landing state")
            return
        }

        // #252: Settings → Appearance card opens the deck on the Appearance
        // page (a hero + read-only tuning values); the channel browser
        // itself is a separate push behind the openBrowser handoff button.
        app.buttons["Open settings"].tap()
        let appearanceCard = app.buttons["settings.card.appearance"]
        XCTAssertTrue(appearanceCard.waitForExistence(timeout: 10))
        appearanceCard.tap()

        let openBrowser = app.buttons["settings.appearance.openBrowser"]
        XCTAssertTrue(openBrowser.waitForExistence(timeout: 10),
                      "the Appearance deck page should offer the channel browser handoff (#252)")
        openBrowser.tap()

        // The browser is present: counter + the fresh-context start channel.
        let counter = app.staticTexts["appearance.channelCounter"]
        XCTAssertTrue(counter.waitForExistence(timeout: 10),
                      "Appearance must present the channel browser (#244)")
        let deepFieldName = app.staticTexts["DEEP FIELD"]
        XCTAssertTrue(deepFieldName.waitForExistence(timeout: 5),
                      "a fresh context opens on Deep Field's channel")

        // One deterministic step forward: Flagship order puts Solar Forge next.
        app.buttons["Next theme"].tap()
        let solarForgeName = app.staticTexts["SOLAR FORGE"]
        XCTAssertTrue(solarForgeName.waitForExistence(timeout: 5),
                      "the next channel must be Solar Forge (catalog order)")

        // Apply-on-land persisted: leave and re-enter — the browser must
        // reopen on Solar Forge's channel, not Deep Field's. "Back" pops
        // the NavigationLink push back onto the Appearance deck page (the
        // deck's own TabView selection is untouched), so the handoff
        // button is a direct re-tap — no card re-navigation needed.
        app.buttons["Back"].firstMatch.tap()
        let openBrowserAgain = app.buttons["settings.appearance.openBrowser"]
        XCTAssertTrue(openBrowserAgain.waitForExistence(timeout: 10))
        openBrowserAgain.tap()
        let reopened = app.staticTexts["SOLAR FORGE"]
        XCTAssertTrue(reopened.waitForExistence(timeout: 10),
                      "re-entry must open on the applied channel (244-C)")
    }

    // MARK: - #252 Channels IA navigation (252-A/B/E)

    /// 252-A: the settings root opens directly on the nine-subsystem grid —
    /// every card + the developer row present by id, and none of the old
    /// hardcoded root header values (e.g. "REACTOR") survive the rewrite.
    @MainActor
    func testSettingsGridPresentsNineSubsystems() throws {
        let context = UITestLaunchContext()
        let app = makeApp(context: context)
        app.launch()

        guard waitForComposer(in: app, timeout: 15) != nil else {
            XCTFail("chat composer should be the first-launch landing state")
            return
        }

        app.buttons["Open settings"].tap()
        XCTAssertTrue(app.otherElements["settings.grid"].waitForExistence(timeout: 10),
                      "Settings must open on the subsystem grid (#252)")
        // #256: the at-a-glance status strip sits above the cards in grid view.
        XCTAssertTrue(app.descendants(matching: .any)["settings.statusStrip"].exists,
                      "the status strip must render above the grid (#256)")
        for id in ["settings.card.uplink", "settings.card.server", "settings.card.models",
                   "settings.card.voice", "settings.card.appearance", "settings.card.privacy",
                   "settings.card.sessions", "settings.card.about", "settings.row.developer"] {
            XCTAssertTrue(app.buttons[id].exists, "\(id) card must be present")
        }
        XCTAssertFalse(app.staticTexts["REACTOR"].exists, "hardcoded root values must be gone (#252)")

        // #251-2A: the Server page carries the plugin-link status row. Query
        // by `.any` — the combined accessibility element's type depends on
        // what the panel collapses to.
        app.buttons["settings.card.server"].tap()
        let talariaLink = app.descendants(matching: .any)["settings.server.talariaLink"]
        XCTAssertTrue(talariaLink.waitForExistence(timeout: 10),
                      "the Server page must show the talaria PLUGIN LINK row (#251-2A)")
    }

    /// 252-B: swipe and grid-toggle navigation through the deck, plus the
    /// deferred coverage owed from Tasks 3–8 — page-dot tap navigation
    /// (each dot's accessibilityLabel is "Open <TITLE>") and, where
    /// feasible on iOS XCUITest, Esc-key sheet dismissal (`dismissKeyCatcher`
    /// wires `.keyboardShortcut(.cancelAction)` on a control that stays in
    /// the tree across both grid and deck mode).
    @MainActor
    func testSettingsDeckNavigation() throws {
        let context = UITestLaunchContext()
        let app = makeApp(context: context)
        app.launch()

        guard waitForComposer(in: app, timeout: 15) != nil else {
            XCTFail("chat composer should be the first-launch landing state")
            return
        }

        app.buttons["Open settings"].tap()
        app.buttons["settings.card.uplink"].tap()
        let counter = app.staticTexts["settings.deck.counter"]
        XCTAssertTrue(counter.waitForExistence(timeout: 10), "deck counter must appear")
        // #403: the deck is 10 pages on a DEBUG simulator — the Private
        // Cloud tile exists here now (metadata carve-out), matching what a
        // device shows. Positional numbering per #395-D2: 08 PRIVATE CLOUD /
        // 09 ABOUT / 10 DEVELOPER.
        waitForCounter(counter, toEqual: "01 / 10", timeout: 5)
        XCTAssertEqual(counter.label, "01 / 10")
        // The deck page's accessibilityIdentifier lands on whatever root
        // view each embedded screen collapses to — UplinkSettingsScreen's
        // is a ScrollView, not a generic "Other" container, and other
        // subsystems may differ again. Query by `.any` so the swipe target
        // resolves regardless of the underlying element type.
        let uplinkPage = app.descendants(matching: .any)["settings.deck.page.uplink"]
        XCTAssertTrue(uplinkPage.waitForExistence(timeout: 5), "the uplink deck page must be reachable")
        // #256: the strip is grid-only — the deck stays full-bleed.
        XCTAssertFalse(app.descendants(matching: .any)["settings.statusStrip"].exists,
                       "the status strip must not render in deck mode (#256)")
        uplinkPage.swipeLeft()
        waitForCounter(counter, toEqual: "02 / 10", timeout: 5)
        XCTAssertEqual(counter.label, "02 / 10", "swipe must advance the deck")

        // Page-dot tap navigation (owed from Tasks 3–8): each dot's
        // accessibilityLabel is "Open <TITLE>", independent of swiping.
        let aboutDot = app.buttons["Open ABOUT"]
        XCTAssertTrue(aboutDot.waitForExistence(timeout: 5), "the About page dot must be reachable")
        aboutDot.tap()
        waitForCounter(counter, toEqual: "09 / 10", timeout: 5)
        XCTAssertEqual(counter.label, "09 / 10", "a dot tap must jump straight to its page")

        app.buttons["Toggle overview"].tap()
        XCTAssertTrue(app.otherElements["settings.grid"].waitForExistence(timeout: 5),
                      "grid toggle must return to the overview")

        // Esc-key dismissal (owed from Tasks 3–8): re-enter the deck, then
        // synthesize a hardware Escape key press. `typeKey` is available
        // for iOS in XCUIElement.h (gated `TARGET_OS_OSX ||
        // TARGET_OS_MACCATALYST || TARGET_OS_IOS`, not macOS-only), so
        // this is a real probe of on-simulator behavior, not a compile-time
        // assumption.
        app.buttons["settings.card.uplink"].tap()
        XCTAssertTrue(counter.waitForExistence(timeout: 5))
        app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
        XCTAssertNotNil(waitForComposer(in: app, timeout: 5),
                        "Esc should dismiss the settings sheet back to chat (#252)")
    }

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
