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
        dismissKeyboardOnboardingIfNeeded(in: app)
        detail.tap()
        app.typeText(Fixture.typedPreview)

        XCTAssertTrue(
            waitForTerminalText(Fixture.typedPreview, in: detail, timeout: 4),
            "Expected typed text to reach the terminal fixture"
        )
        dismissKeyboardIfNeeded(in: app)
        terminalBackButton(in: app, title: "Input Fixture").tap()

        let preview = app.staticTexts.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label == %@",
            "terminal.workspace.preview.",
            Fixture.typedPreview
        )).firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 4), "Expected workspace preview to reflect typed input")
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

    private func waitForTerminalText(_ text: String, in detail: XCUIElement, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate { element, _ in
            guard let detail = element as? XCUIElement,
                  let value = detail.value as? String else {
                return false
            }
            return value.contains(text)
        }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: detail)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func dismissKeyboardIfNeeded(in app: XCUIApplication) {
        dismissKeyboardOnboardingIfNeeded(in: app)

        let hideAccessory = app.buttons["terminal.inputAccessory.hideKeyboard"]
        if hideAccessory.waitForExistence(timeout: 1), hideAccessory.isHittable {
            hideAccessory.tap()
            return
        }

        let keyboard = app.keyboards.firstMatch
        guard keyboard.exists else { return }

        let hideKeyboard = keyboard.buttons["Hide keyboard"]
        if hideKeyboard.exists {
            hideKeyboard.tap()
            return
        }

        let dismissKeyboard = keyboard.buttons["Dismiss keyboard"]
        if dismissKeyboard.exists {
            dismissKeyboard.tap()
            return
        }

        let returnKey = keyboard.buttons["Return"]
        if returnKey.exists {
            returnKey.tap()
        }
    }

    private func dismissKeyboardOnboardingIfNeeded(in app: XCUIApplication) {
        let continueButton = app.buttons["Continue"]
        if continueButton.waitForExistence(timeout: 1), continueButton.isHittable {
            continueButton.tap()
        }
    }
}
