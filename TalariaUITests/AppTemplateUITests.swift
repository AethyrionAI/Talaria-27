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
                NSPredicate(format: "label CONTAINS[c] %@", "wasn't told")
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

    // MARK: - #219 DET-A: the swallowed-tap fixture

    /// **The failure path, on demand (#219, bar DET-A).**
    ///
    /// `testConnectedRelaunchSkipsTheConnectEntry` flakes ~1 run in 10 on a
    /// START CHATTING tap that XCUITest resolves to `Computed hit point
    /// {-1, -1}` — the button exists at a valid frame and is not hittable. That
    /// shape appeared roughly monthly, never on demand, and the one diagnostic
    /// the suite carried never reached the log because its assertion PASSED.
    ///
    /// `UITEST_OVERLAY_BLOCKS_WIZARD=1` mounts a DEBUG-only clear overlay above
    /// the wizard's done step, which reproduces the shape deterministically:
    /// same frame, same existence, no hit point. What this test PINS is not the
    /// flake — it is the diagnostic. A helper whose timeout path stops naming
    /// what covers the button fails here in seconds instead of costing another
    /// month of gate runs.
    @MainActor
    func testOverlayFixtureMakesStartChattingUnhittable() throws {
        let context = UITestLaunchContext()
        let app = makeApp(context: context)
        app.launchEnvironment["UITEST_OVERLAY_BLOCKS_WIZARD"] = "1"
        app.launch()

        let startChatting = advanceWizardToStartChatting(in: app, context: context)
        XCTAssertTrue(startChatting.exists,
                      "the fixture must leave the button PRESENT — an absent button is a different failure")

        // The tap COUNTER, read before and after: the outcome case, the `via`
        // arm and "the wizard is still up" are all satisfied by a helper that
        // never tapped. This is the only assertion here that a missing tap
        // fails.
        XCTAssertEqual(swallowedOverlayTaps(in: app), 0,
                       "the fixture overlay must publish a tap counter, starting at 0")

        // A SHORT budget on purpose: this test is about the path, not the
        // budget. Production's own call site keeps its existing 10s.
        let outcome = startChatting.tapWhenHittable(
            timeout: 3,
            in: app,
            strategy: .elementTap,
            label: "connectHostWizard.startChatting"
        )

        guard case let .tappedAfterTimeout(diagnostic, via) = outcome else {
            // Read `exists` BEFORE anything else: when this assertion fires the
            // usual reason is that the tap WORKED and the wizard popped, and a
            // property read on the departed button raises "Failed to get
            // matching snapshot" — which replaces the real message with a
            // stack trace. (Measured: that is exactly what the RED run
            // printed.) Same rule the drive helper's own diagnostic follows.
            let stillPresent = startChatting.exists
            let extra = stillPresent
                ? "hittable=\(startChatting.isHittable) frame=\(startChatting.frame)"
                : "the button is gone — the tap went through and the wizard popped"
            XCTFail("""
                the overlay fixture must drive the tap onto the timeout path, \
                got \(outcome) — \(extra)
                """)
            return
        }
        XCTAssertEqual(via, .elementTap, "the default arm must fall back to today's element tap")
        XCTAssertTrue(
            diagnostic.contains("uitest.overlayBlocksWizard"),
            """
            DET-A: the timeout diagnostic must NAME what sits over the button's \
            centre point — got:
            \(diagnostic)
            """
        )

        // The overlay swallows the fallback tap too, so the wizard stays up —
        // which is what makes this a fixture for the flake rather than a
        // roundabout way of completing the connect.
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 1.0))
        XCTAssertTrue(startChatting.exists,
                      "a swallowed tap must leave the wizard where it was")
        XCTAssertEqual(
            swallowedOverlayTaps(in: app), 1,
            """
            DET-A: the element-tap arm must ISSUE its fallback tap — the overlay \
            counts exactly one swallowed tap. A count of 0 means the helper \
            emitted the diagnostic and never tapped, which every other assertion \
            in this test would still pass.
            """
        )
    }

    /// The coordinate arm FIRES after the timeout (bar DET-A's second half).
    ///
    /// It does not fix anything here — the overlay swallows a coordinate tap
    /// exactly as it swallows an element tap, which is the fixture's correct
    /// semantics: the fixture proves the arm RUNS, and the later A/B measures
    /// whether it helps against the real flake.
    @MainActor
    func testOverlayFixtureCoordinateArmStillTapsAfterTimeout() throws {
        let context = UITestLaunchContext()
        let app = makeApp(context: context)
        app.launchEnvironment["UITEST_OVERLAY_BLOCKS_WIZARD"] = "1"
        app.launch()

        let startChatting = advanceWizardToStartChatting(in: app, context: context)
        XCTAssertEqual(swallowedOverlayTaps(in: app), 0,
                       "the fixture overlay must publish a tap counter, starting at 0")

        let outcome = startChatting.tapWhenHittable(
            timeout: 3,
            in: app,
            strategy: .coordinateAfterTimeout,
            label: "connectHostWizard.startChatting"
        )

        guard case let .tappedAfterTimeout(diagnostic, via) = outcome else {
            XCTFail("the coordinate arm must still reach the timeout path, got \(outcome)")
            return
        }
        XCTAssertEqual(via, .coordinateAfterTimeout,
                       "an explicitly-passed strategy must not be overridden by the environment")
        XCTAssertTrue(diagnostic.contains("uitest.overlayBlocksWizard"),
                      "DET-A: the coordinate arm reports the same diagnostic — got:\n\(diagnostic)")

        RunLoop.current.run(until: Date(timeIntervalSinceNow: 1.0))
        XCTAssertTrue(startChatting.exists,
                      "the overlay swallows a coordinate tap too — the wizard must still be up")
        XCTAssertEqual(
            swallowedOverlayTaps(in: app), 1,
            """
            DET-A: the coordinate arm must ISSUE its tap — the overlay counts \
            exactly one swallowed tap. This is what makes "the arm RUNS" a \
            measurement rather than a claim about an unobserved code path.
            """
        )
    }

    /// The DEBUG fixture overlay publishes the number of taps it has SWALLOWED
    /// as its accessibility VALUE (`UITestWizardBlockingOverlay`). `nil` means
    /// the overlay is absent or is not publishing a value at all — reported as
    /// itself rather than folded into 0, so a broken fixture cannot read as a
    /// missing tap.
    @MainActor
    private func swallowedOverlayTaps(in app: XCUIApplication) -> Int? {
        let overlay = app.otherElements["uitest.overlayBlocksWizard"]
        guard overlay.exists, let raw = overlay.value as? String else { return nil }
        return Int(raw)
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
        let startChatting = advanceWizardToStartChatting(in: app, context: context)

        // **The flake site (#219). ONE budget, not two.** The 10s this site
        // used to spend in `waitForExistence` is now spent HERE, polling
        // `exists ∧ hittable` — `advanceWizardToStartChatting` hands the
        // button over on a zero-budget `exists` check (its own 30s condition
        // loop already polled existence), so nothing is stacked and the
        // site's worst case is exactly the pre-change 10s. An earlier draft
        // of this lane kept both and doubled the site to 20s, which is the
        // thing "never widen a wait" forbids.
        //
        // The strategy is left defaulted because this is the one site the A/B
        // varies.
        //
        // `XFLAKE pre` folded into the helper's own `HITTAP pre`; `XFLAKE post`
        // became `HITTAP post` so one grep prefix reads the whole path, and it
        // now carries the OUTCOME — the single line a batch run needs.
        let outcome = startChatting.tapWhenHittable(
            timeout: 10,
            in: app,
            label: "connectHostWizard.startChatting"
        )
        XCTContext.runActivity(named: HittableTap.clamp("""
            \(HittableTap.activityPrefix)post outcome=\(outcome) \
            wizardUp=\(startChatting.exists) \
            composerIn5s=\(waitForComposer(in: app, timeout: 5) != nil) \
            wizardUpAfter=\(startChatting.exists)
            """)) { _ in }

        // #137: landing straight in chat — no permissions interstitial.
        guard waitForComposer(in: app, timeout: 15) != nil else {
            XCTFail("a successful connect should land straight in chat (#137)")
            return
        }
        XCTAssertFalse(app.buttons["CONTINUE"].exists,
                       "the post-connect permissions wall must not return (#137)")
        XCTAssertTrue(app.buttons["Open settings"].waitForExistence(timeout: 10))
    }

    /// #219 DET-A: the wizard drive, split out of `completeConnect` verbatim so
    /// a fixture test can reach step 3 WITHOUT also taking the START CHATTING
    /// tap — that tap is the flake under investigation, and a test about the
    /// tap cannot share a helper that has already taken it. Returns the
    /// START CHATTING button, existence already asserted.
    @discardableResult
    @MainActor
    private func advanceWizardToStartChatting(
        in app: XCUIApplication,
        context: UITestLaunchContext
    ) -> XCUIElement {
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

        // **iOS 27 beta, bundle-warm: a synthesized tap lands without invoking
        // the action.** The same signature #164 and #182 record for this
        // suite, and MEASURED here across four full runs: the three connect
        // journeys passed alone, failed together on one full-bundle gate, then
        // passed 14/14 on the NEXT run of the identical invocation over the
        // identical code. That last run is what makes it a flake rather than a
        // regression — and it is why one re-tap was not enough.
        //
        // The fix is #164's own shape: wait on the CONDITION with a bounded
        // retry instead of on a fixed timeout. Every second, if the wizard is
        // still showing CONTINUE, tap it again. A wizard that genuinely never
        // advances still runs out the deadline and still reds — nothing is
        // masked; a dropped tap is retried instead of being fatal.
        //
        // **And the loop dismisses a SYSTEM ALERT if one is up, because the
        // diagnostic finally named the mechanism.** After thirty re-taps a
        // gate run still reported `continue=true`: the button was on screen
        // and its action never ran, which is not a dropped tap — it is a tap
        // being SWALLOWED by something on top. A springboard alert is exactly
        // that, and it is invisible to `app.buttons`, which is why every
        // earlier diagnostic pointed at the wrong thing. Tapping it through is
        // the same courtesy `testFreshInstallNeverPresentsNotificationPermission
        // Dialog` already extends to the springboard, in the other direction.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let startChatting = app.buttons["connectHostWizard.startChatting"]
        let tapDeadline = Date(timeIntervalSinceNow: 30)
        // **One dump per loop, not one per iteration (#219).** The first
        // un-hittable iteration gets the full DET-A diagnostic; the rest get a
        // single suppressed line. Thirty `debugDescription` snapshots and ~480
        // activity names inside the very flake this loop exists for would eat
        // the 1s cadence — costing the loop retries inside its unchanged 30s
        // deadline — and bury the prefix a batch run greps.
        var hasDumpedContinueDiagnostic = false
        while !startChatting.exists, Date() < tapDeadline {
            if springboard.alerts.count > 0 {
                let alert = springboard.alerts.firstMatch
                let accept = alert.buttons.element(boundBy: alert.buttons.count - 1)
                if accept.exists { accept.tap() }
            }
            if carryOn.exists {
                // **`.exists` is not `.isHittable`.** An element under the
                // keyboard plane or below the fold still exists, and `.tap()`
                // on it lands on whatever is actually at those coordinates —
                // which is a tap that "does nothing" from the test's side and
                // is indistinguishable from a dropped one. Scroll it into
                // reach first, then tap the coordinate space rather than the
                // frame.
                if !carryOn.isHittable {
                    // Swipe the SCROLL VIEW, not the app: `app.swipeUp()`
                    // targets the window and can land on chrome that does not
                    // scroll, which is a gesture that looks like it did
                    // something and did not.
                    let scroller = app.scrollViews.firstMatch
                    if scroller.exists { scroller.swipeUp() } else { app.swipeUp() }
                }
                // Through the shared helper for the diagnostic only — the
                // behaviour is byte-for-byte what stood here: hittable ⇒ tap,
                // otherwise the coordinate tap. Hence `timeout: 0` (this
                // loop's own 30s deadline is the budget; a per-iteration poll
                // would eat the retries) and an EXPLICIT strategy (this site
                // already coordinate-taps, so it must not swing with the A/B's
                // environment variable — only START CHATTING does).
                let carryOnOutcome = carryOn.tapWhenHittable(
                    timeout: 0,
                    in: app,
                    strategy: .coordinateAfterTimeout,
                    diagnose: !hasDumpedContinueDiagnostic,
                    label: "connectHostWizard.continue"
                )
                // Latch on the EXPENSIVE path only: a loop whose first
                // iteration taps cleanly must still dump when a later one
                // does not.
                if case .tappedAfterTimeout = carryOnOutcome {
                    hasDumpedContinueDiagnostic = true
                }
            }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 1.0))
        }
        // The diagnostic is deliberately made of CHEAP, NAMED probes rather
        // than an element dump: `allElementsBoundByIndex` re-snapshots the
        // hierarchy and throws "No matches found for Element at index N" when
        // it changes underneath — which is how the first version of this line
        // replaced a readable failure with an unreadable one. Every property
        // read here goes through `HittableTap.describe`, which gates on
        // existence for the same reason (a `.frame` read on the element that
        // is MISSING is exactly the read this message would make).
        //
        // **`exists`, not `waitForExistence(timeout: 10)` (#219).** The loop
        // above already polled existence for 30s and exits the instant the
        // button appears, so the old 10s here was a second budget stacked on
        // that one — and the caller's `tapWhenHittable(timeout: 10)` is now
        // where this site's single 10s is spent. Nothing was widened, and one
        // hedge was removed.
        XCTAssertTrue(
            startChatting.exists,
            """
            step 3 should offer START CHATTING — buttons=\(app.buttons.count) \
            continue=\(app.buttons["connectHostWizard.continue"].exists) \
            notNow=\(app.buttons["connectHostWizard.notNow"].exists) \
            check=\(app.buttons["connectHostWizard.check"].exists) \
            connectMyHost=\(app.buttons["connectHostWizard.connectMyHost"].exists) \
            tryAgain=\(app.buttons["TRY AGAIN"].exists) \
            settingsScan=\(app.buttons["connectHost.scan"].exists) \
            composer=\(composerInput(in: app).exists) \
            springboardAlerts=\(springboard.alerts.count) \
            keyboards=\(app.keyboards.count) \
            scrollViews=\(app.scrollViews.count) \
            continueState=\(HittableTap.describe(app.buttons["connectHostWizard.continue"])) \
            window=\(HittableTap.describeFrame(of: app.windows.firstMatch))
            """
        )
        return startChatting
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

    /// #224 bar 224-1D(i): the `// Agent Actions` control RENDERS on the
    /// Privacy page, in its ruled position, and a mode switch lands.
    ///
    /// **This is the only 224-1D assertion that puts the section on a screen.**
    /// The others are unit tests over copy strings and colours resolved from
    /// palettes — real checks, but a palette resolving correctly says nothing
    /// about whether the rows were ever added to `body`. It is also the only
    /// place the VoiceOver labels are used the way a screen reader uses them:
    /// as the element's identity. A later lane that shortens one back to a
    /// bare mode name fails here, not just in the copy pin.
    @MainActor
    func testPrivacyAgentActionsControlRendersAndSwitchesMode() throws {
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
        app.buttons["settings.card.privacy"].tap()

        let section = app.descendants(matching: .any)["settings.privacy.agentActions"]
        XCTAssertTrue(section.waitForExistence(timeout: 10),
                      "Privacy must carry the // Agent Actions control (#224 ruling 6)")

        let askEveryTime = app.buttons[
            "Ask every time. Every reminder, event, and alarm waits for your approval."]
        let neverAsk = app.buttons[
            "Never ask. Actions go ahead without asking, and any that trip a caution are refused instead of created."]

        // Bounded scroll — the section is third on the page, under Sensor
        // Sharing, so it can start below the fold. Bounded rather than
        // `while true` because a row that never arrives must FAIL the test,
        // not spin it.
        var swipes = 0
        while !neverAsk.isHittable, swipes < 6 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(neverAsk.isHittable, "the Never ask row never came into view")
        XCTAssertTrue(askEveryTime.exists, "the Ask every time row must render alongside it")
        XCTAssertTrue(askEveryTime.isSelected,
                      "a fresh install must land on Ask every time (#224 bar 224-1A)")
        XCTAssertFalse(neverAsk.isSelected)

        neverAsk.tap()
        XCTAssertTrue(neverAsk.isSelected, "tapping Never ask must select it")
        XCTAssertFalse(askEveryTime.isSelected, "the previous mode must clear")
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

    // `composerInput` / `waitForComposer` live in `Support/HittableTap.swift`
    // (#219): this class and `MessageIdentityUITests` carried byte-identical
    // private copies.
}
