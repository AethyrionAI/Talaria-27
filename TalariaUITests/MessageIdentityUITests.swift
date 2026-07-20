import XCTest

/// #120 end-to-end regression guard: the chat transcript `ForEach(messages)`
/// must never render the same message id twice (SwiftUI declares a duplicate
/// -id `ForEach` undefined; the device symptom was the `occurs multiple
/// times` runtime warning and a glitched row).
///
/// This drives the REAL app through the on-device (standalone) path — the
/// backend that appends its reply to `currentConversation` before yielding
/// `.finished`, which is the #120 trigger — and asserts uniqueness after each
/// exchange via the `chat.dupIDProbe` accessibility seam. The critical case
/// is the WARM LAUNCH: terminate mid-thread and relaunch, where the client's
/// `currentConversation` is nil and the post-finish metadata merge could not
/// mask the duplication.
///
/// Determinism: under `UITEST_DUPID_PROBE=1` the on-device backend runs a
/// model-free synthetic turn that appends the reply and then dwells past one
/// 2s poll interval before `.finished`, so the poll-tick merge is guaranteed
/// to land in the duplicate-seeding window. No live model or host required.
final class MessageIdentityUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Shared defaults + keychain suite so the conversation cache survives the
    /// terminate/relaunch cycle (the warm-launch path). Random per-test so
    /// runs don't collide.
    private struct Context {
        let defaultsSuite = "uitest.identity.defaults.\(UUID().uuidString)"
        let keychainService = "uitest.identity.keychain.\(UUID().uuidString)"
    }

    @MainActor
    func testTranscriptNeverRendersDuplicateMessageIDs() throws {
        let context = Context()

        // Cycle 1 — cold launch, lands directly in on-device chat (no pairing
        // wall, #31). Send and confirm the rendered transcript stays unique
        // across the append→merge→finish window.
        var app = makeApp(context: context)
        app.launch()

        guard let composer = waitForComposer(in: app, timeout: 15) else {
            XCTFail("chat composer should be reachable on first launch (on-device, no pairing)")
            return
        }

        sendMessage("first", in: app, composer: composer)
        assertNoDuplicateIDs(in: app, phase: "cold-launch send")

        // Cycles 2–3 — warm launch. Terminate mid-thread and relaunch from
        // cache (client `currentConversation` nil), then send immediately —
        // the exact path that surfaced the bug only on device.
        for cycle in 2...3 {
            app.terminate()
            app = makeApp(context: context)
            app.launch()

            guard let warmComposer = waitForComposer(in: app, timeout: 15) else {
                XCTFail("chat composer should be reachable on warm launch \(cycle)")
                return
            }
            // Prior replies must have restored from cache — still unique.
            assertNoDuplicateIDs(in: app, phase: "warm-launch \(cycle) restore")

            sendMessage("warm\(cycle)", in: app, composer: warmComposer)
            assertNoDuplicateIDs(in: app, phase: "warm-launch \(cycle) send")
        }
    }

    // MARK: - Helpers

    @MainActor
    private func makeApp(context: Context) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["UITEST_DEFAULTS_SUITE"] = context.defaultsSuite
        app.launchEnvironment["UITEST_KEYCHAIN_SERVICE"] = context.keychainService
        // Service isolation (mock media/host/inbox) so no live permission
        // prompts fire. Does NOT pair or set a Hermes key — routing stays
        // on-device, which is the backend that reproduces #120.
        app.launchEnvironment["UITEST_PAIRING_MODE"] = "mock"
        // Arms the identity probe overlay AND the deterministic on-device
        // synthetic turn.
        app.launchEnvironment["UITEST_DUPID_PROBE"] = "1"
        return app
    }

    @MainActor
    private func sendMessage(_ text: String, in app: XCUIApplication, composer: XCUIElement) {
        composer.tap()
        composer.typeText(text)

        let send = app.buttons["Send message"]
        XCTAssertTrue(send.waitForExistence(timeout: 5),
                      "send button should appear once the composer holds text")
        send.tap()

        // The synthetic reply is "Acknowledged <text>"; wait for it to settle
        // so the assertion spans the full append→finish sequence.
        let reply = app.staticTexts["Acknowledged \(text)"]
        XCTAssertTrue(reply.waitForExistence(timeout: 20),
                      "the on-device reply for '\(text)' should render")
    }

    /// Reads the probe's published max-id-multiplicity and fails if any id was
    /// rendered more than once. Polls briefly so the assertion also catches a
    /// transient duplicate that heals after a later merge.
    @MainActor
    private func assertNoDuplicateIDs(in app: XCUIApplication, phase: String) {
        let probe = app.otherElements["chat.dupIDProbe"]
        XCTAssertTrue(probe.waitForExistence(timeout: 10),
                      "identity probe should be present (\(phase))")

        var worst = 1
        // Sample across ~3s to cover any interim merge window.
        for _ in 0..<6 {
            if let value = Int(probe.value as? String ?? "") {
                worst = max(worst, value)
                XCTAssertLessThanOrEqual(
                    value, 1,
                    "transcript rendered a duplicate message id (multiplicity \(value)) during \(phase) — #120 regression"
                )
            }
            // Runloop-friendly pause — a blocking sleep on the main actor
            // starves XCTest's own machinery.
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.5))
        }
        XCTAssertLessThanOrEqual(worst, 1, "max id multiplicity \(worst) during \(phase)")
    }

    @MainActor
    private func composerInput(in app: XCUIApplication) -> XCUIElement {
        // The composer may surface as a text field or a text view depending
        // on the SwiftUI editor in use — check the identifier and the
        // accessibility label across both.
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
    /// be transitioning off onboarding when the first query runs), so the
    /// wait isn't pinned to a single element type guessed too early.
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
