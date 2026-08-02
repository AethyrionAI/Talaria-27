import XCTest

final class TalariaUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        // #144: belt-and-braces, and NOT the proven polluter.
        //
        // Every other launch in this target goes through a `makeApp(context:)`
        // helper that sets `UITEST_*`; this auto-generated template test is the
        // one bare `XCUIApplication()` in the suite, so it was the obvious
        // suspect for the 99 junk device rows on the Mac relay.
        //
        // **It was measured and it is NOT the cause.** A full run carrying
        // `TestRunGuard` but NOT this line added ZERO rows — if this launch were
        // enrolling, that run would have added one. The likelier culprit is the
        // unit-test HOST process, which does carry `XCTestConfigurationFilePath`
        // and is caught by the guard's other branch.
        //
        // Kept anyway: a bare launch with no marker is a standing hazard whether
        // or not it fired this time, and it costs one line.
        //
        // `UITEST_RUN` rather than `UITEST_PAIRING_MODE = "mock"` deliberately:
        // it states what is true — this is a test run — and it exercises
        // `TestRunGuard`'s detection rather than bypassing it, so the gate
        // covers the guard itself.
        app.launchEnvironment["UITEST_RUN"] = "1"
        app.launch()

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
