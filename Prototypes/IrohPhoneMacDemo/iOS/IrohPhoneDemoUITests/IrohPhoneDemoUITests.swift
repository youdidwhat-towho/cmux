import XCTest

final class IrohPhoneDemoUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchShowsTicketField() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.navigationBars["Iroh Link"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Paste Ticket"].exists)
    }
}
