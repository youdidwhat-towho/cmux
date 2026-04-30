import XCTest

final class TerminalReconnectUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testDirectDaemonReconnectRecovers() {
        let app = XCUIApplication()
        app.launchEnvironment["CMUX_UITEST_TERMINAL_DIRECT_FIXTURE"] = "1"
        app.launchEnvironment["CMUX_UITEST_TERMINAL_RECONNECT_DELAY"] = "0.2"
        app.launch()

        let serverButton = app.buttons["terminal.server.cmux-macmini"]
        XCTAssertTrue(serverButton.waitForExistence(timeout: 6))
        serverButton.tap()

        XCTAssertTrue(app.navigationBars["Mac mini"].waitForExistence(timeout: 4))

        let renderedText = app.otherElements.matching(identifier: "terminal.workspace.detail").firstMatch
        XCTAssertTrue(renderedText.waitForExistence(timeout: 4), "Expected terminal workspace detail")
        XCTAssertTrue(
            waitForValue(of: renderedText, containing: "reconnected", timeout: 12),
            "Expected terminal output after daemon reconnect"
        )
    }

    private func waitForValue(
        of element: XCUIElement,
        containing needle: String,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let value = element.value as? String,
               value.contains(needle) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return (element.value as? String)?.contains(needle) == true
    }
}
