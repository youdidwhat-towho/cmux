import XCTest

final class ComeupSimulatorHarnessUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    @MainActor
    func testWorkspaceHomeOpensTerminalDetail() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.collectionViews["cmux.mobile.home"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.cmuxElement("auth.status.row").waitForExistence(timeout: 4))
        XCTAssertTrue(app.cmuxElement("hive.node.node-macbook").waitForExistence(timeout: 4))

        let workspace = app.cmuxElement("workspace.row.workspace-ios-port")
        XCTAssertTrue(workspace.waitForExistence(timeout: 4))
        workspace.tap()

        XCTAssertTrue(app.cmuxElement("workspace.detail.workspace-ios-port").waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["main / pane 1 / shell"].waitForExistence(timeout: 4))
        let terminalSurface = app.cmuxElement("terminal.surface")
        XCTAssertTrue(terminalSurface.waitForExistence(timeout: 4))
        let renderedText = terminalSurface.value as? String ?? ""
        XCTAssertTrue(renderedText.contains("CMX_SENTINEL_TO_SIM"))
    }
}

private extension XCUIApplication {
    func cmuxElement(_ identifier: String) -> XCUIElement {
        descendants(matching: .any)[identifier]
    }
}
