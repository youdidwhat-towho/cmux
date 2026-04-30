import XCTest

final class TerminalInputUITests: XCTestCase {
    private enum Fixture {
        static let typedPreview = "z"
    }

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testInputFixtureTypingUpdatesWorkspacePreview() {
        let app = XCUIApplication()
        app.launchEnvironment["CMUX_UITEST_TERMINAL_INPUT_FIXTURE"] = "1"
        app.launch()

        let serverButton = app.buttons["terminal.server.cmux-input"]
        XCTAssertTrue(serverButton.waitForExistence(timeout: 6), "Expected input fixture server pin")
        serverButton.tap()

        let detail = terminalDetail(in: app)
        XCTAssertTrue(detail.waitForExistence(timeout: 4), "Expected terminal workspace detail")
        detail.tap()
        app.typeText(Fixture.typedPreview)

        terminalBackButton(in: app, title: "Input Fixture").tap()

        let preview = app.staticTexts[Fixture.typedPreview]
        XCTAssertTrue(preview.waitForExistence(timeout: 4), "Expected workspace preview to reflect typed input")
    }

    func testInputFixtureAccessoryEscapeUpdatesWorkspacePreview() {
        let app = XCUIApplication()
        app.launchEnvironment["CMUX_UITEST_TERMINAL_INPUT_FIXTURE"] = "1"
        app.launch()

        let serverButton = app.buttons["terminal.server.cmux-input"]
        XCTAssertTrue(serverButton.waitForExistence(timeout: 6), "Expected input fixture server pin")
        serverButton.tap()

        let detail = terminalDetail(in: app)
        XCTAssertTrue(detail.waitForExistence(timeout: 4), "Expected terminal workspace detail")
        detail.tap()

        let escapeButton = app.buttons["terminal.inputAccessory.escape"]
        XCTAssertTrue(escapeButton.waitForExistence(timeout: 4), "Expected escape accessory button")
        tapEvenIfKeyboardAccessoryReportsCovered(escapeButton)

        terminalBackButton(in: app, title: "Input Fixture").tap()

        let preview = app.staticTexts["[ESC]"]
        XCTAssertTrue(preview.waitForExistence(timeout: 4), "Expected workspace preview to reflect accessory escape")
    }

    private func terminalBackButton(in app: XCUIApplication, title: String) -> XCUIElement {
        let navigationBar = app.navigationBars[title]
        let backButton = navigationBar.buttons.matching(NSPredicate(format: "identifier != %@", "Reconnect")).firstMatch
        XCTAssertTrue(backButton.waitForExistence(timeout: 4), "Expected terminal back button")
        return backButton
    }

    private func terminalDetail(in app: XCUIApplication) -> XCUIElement {
        app.otherElements.matching(identifier: "terminal.workspace.detail").firstMatch
    }

    private func tapEvenIfKeyboardAccessoryReportsCovered(_ element: XCUIElement) {
        if element.isHittable {
            element.tap()
            return
        }
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }
}
