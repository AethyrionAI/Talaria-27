import XCTest

final class HermesMobileUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testTabNavigation() throws {
        let app = XCUIApplication()
        app.launch()

        // Verify all tabs are accessible
        // Agents should expand this with app-specific tab names
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
