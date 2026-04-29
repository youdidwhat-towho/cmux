import XCTest
import AppKit

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@MainActor
final class GhosttyEnsureFocusWindowActivationTests: XCTestCase {
    func testAllowsActivationForActiveManager() {
        let activeManager = TabManager()
        let otherManager = TabManager()
        let targetWindow = NSWindow()
        let otherWindow = NSWindow()

        XCTAssertTrue(
            shouldAllowEnsureFocusWindowActivation(
                activeTabManager: activeManager,
                targetTabManager: activeManager,
                keyWindow: targetWindow,
                mainWindow: targetWindow,
                targetWindow: targetWindow
            )
        )
        XCTAssertFalse(
            shouldAllowEnsureFocusWindowActivation(
                activeTabManager: activeManager,
                targetTabManager: otherManager,
                keyWindow: otherWindow,
                mainWindow: otherWindow,
                targetWindow: targetWindow
            )
        )
    }

    func testAllowsActivationWhenAppHasNoKeyAndNoMainWindow() {
        let targetManager = TabManager()
        let targetWindow = NSWindow()

        XCTAssertTrue(
            shouldAllowEnsureFocusWindowActivation(
                activeTabManager: nil,
                targetTabManager: targetManager,
                keyWindow: nil,
                mainWindow: nil,
                targetWindow: targetWindow
            )
        )
        XCTAssertFalse(
            shouldAllowEnsureFocusWindowActivation(
                activeTabManager: nil,
                targetTabManager: targetManager,
                keyWindow: NSWindow(),
                mainWindow: nil,
                targetWindow: targetWindow
            )
        )
        XCTAssertFalse(
            shouldAllowEnsureFocusWindowActivation(
                activeTabManager: nil,
                targetTabManager: targetManager,
                keyWindow: nil,
                mainWindow: NSWindow(),
                targetWindow: targetWindow
            )
        )
    }

    func testRightSidebarFocusOwnerBlocksDeferredTerminalFirstResponderRequest() {
#if DEBUG
        guard let appDelegate = AppDelegate.shared else {
            XCTFail("Expected AppDelegate.shared")
            return
        }

        let windowId = appDelegate.createMainWindow()
        defer { closeWindow(withId: windowId) }

        guard let window = window(withId: windowId),
              let tabManager = appDelegate.tabManagerFor(windowId: windowId),
              let workspace = tabManager.selectedWorkspace,
              let terminalPanel = workspace.focusedTerminalPanel else {
            XCTFail("Expected a focused terminal panel")
            return
        }

        let hostedView = terminalPanel.hostedView
        hostedView.setVisibleInUI(true)
        hostedView.setActive(true)
        appDelegate.noteRightSidebarKeyboardFocusIntent(mode: .files, in: window)

        XCTAssertFalse(
            hostedView.debugRequestSurfaceFirstResponderForTesting(in: window, reason: "test.rightSidebar"),
            "Deferred terminal focus retries should not steal first responder while the right sidebar owns keyboard focus"
        )
        XCTAssertFalse(hostedView.isSurfaceViewFirstResponder())
#else
        XCTFail("debugRequestSurfaceFirstResponderForTesting is only available in DEBUG")
#endif
    }

    func testRightSidebarFocusOwnerBlocksAlreadyFirstResponderTerminalReassertion() {
#if DEBUG
        guard let appDelegate = AppDelegate.shared else {
            XCTFail("Expected AppDelegate.shared")
            return
        }

        let windowId = appDelegate.createMainWindow()
        defer { closeWindow(withId: windowId) }

        guard let window = window(withId: windowId),
              let tabManager = appDelegate.tabManagerFor(windowId: windowId),
              let workspace = tabManager.selectedWorkspace,
              let terminalPanel = workspace.focusedTerminalPanel else {
            XCTFail("Expected a focused terminal panel")
            return
        }

        let hostedView = terminalPanel.hostedView
        hostedView.setVisibleInUI(true)
        hostedView.setActive(true)
        window.makeKeyAndOrderFront(nil)

        XCTAssertTrue(
            hostedView.debugRequestSurfaceFirstResponderForTesting(in: window, reason: "test.initialTerminal"),
            "Test setup should put the terminal surface in the responder chain"
        )
        XCTAssertTrue(hostedView.isSurfaceViewFirstResponder())
        XCTAssertTrue(terminalPanel.surface.debugDesiredFocusState())

        appDelegate.noteRightSidebarKeyboardFocusIntent(mode: .files, in: window)
        hostedView.yieldTerminalSurfaceFocusForForeignResponder(reason: "test.rightSidebar")
        XCTAssertFalse(terminalPanel.surface.debugDesiredFocusState())

        hostedView.debugApplyFirstResponderIfNeededForTesting()

        XCTAssertFalse(
            terminalPanel.surface.debugDesiredFocusState(),
            "Deferred terminal focus applies must not restart Ghostty cursor blinking while the right sidebar owns keyboard focus"
        )
#else
        XCTFail("debugApplyFirstResponderIfNeededForTesting is only available in DEBUG")
#endif
    }

    func testRightSidebarResponderBlocksDeferredTerminalApplyAfterIntentDrift() {
#if DEBUG
        guard let appDelegate = AppDelegate.shared else {
            XCTFail("Expected AppDelegate.shared")
            return
        }

        let windowId = appDelegate.createMainWindow()
        defer { closeWindow(withId: windowId) }

        guard let window = window(withId: windowId),
              let tabManager = appDelegate.tabManagerFor(windowId: windowId),
              let workspace = tabManager.selectedWorkspace,
              let terminalPanel = workspace.focusedTerminalPanel else {
            XCTFail("Expected a focused terminal panel")
            return
        }

        let hostedView = terminalPanel.hostedView
        hostedView.setVisibleInUI(true)
        hostedView.setActive(true)
        window.makeKeyAndOrderFront(nil)
        window.displayIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))

        XCTAssertTrue(
            appDelegate.focusRightSidebarInActiveMainWindow(preferredWindow: window),
            "Test setup should move AppKit focus into the right sidebar"
        )
        guard let rightSidebarResponder = window.firstResponder else {
            XCTFail("Expected a right sidebar first responder")
            return
        }
        XCTAssertTrue(
            appDelegate.isRightSidebarFocusResponder(rightSidebarResponder, in: window),
            "Test setup should produce a right-sidebar-owned first responder"
        )

        appDelegate.noteMainPanelKeyboardFocusIntent(workspaceId: workspace.id, panelId: terminalPanel.id, in: window)

        hostedView.debugApplyFirstResponderIfNeededForTesting()

        XCTAssertTrue(
            window.firstResponder === rightSidebarResponder,
            "Deferred terminal focus must not steal AppKit focus from a right-sidebar responder even if model intent drifted"
        )
        XCTAssertFalse(
            terminalPanel.surface.debugDesiredFocusState(),
            "Deferred terminal focus must not restart Ghostty cursor blinking while right-sidebar AppKit focus is active"
        )
#else
        XCTFail("debugApplyFirstResponderIfNeededForTesting is only available in DEBUG")
#endif
    }

    func testRightSidebarIntentBlocksDirectTerminalFirstResponderSteal() {
#if DEBUG
        AppDelegate.installWindowResponderSwizzlesForTesting()
        guard let appDelegate = AppDelegate.shared else {
            XCTFail("Expected AppDelegate.shared")
            return
        }

        let windowId = appDelegate.createMainWindow()
        defer { closeWindow(withId: windowId) }

        guard let window = window(withId: windowId),
              let tabManager = appDelegate.tabManagerFor(windowId: windowId),
              let workspace = tabManager.selectedWorkspace,
              let terminalPanel = workspace.focusedTerminalPanel,
              let terminalSurfaceView = surfaceView(in: terminalPanel.hostedView) else {
            XCTFail("Expected a focused terminal surface")
            return
        }

        terminalPanel.hostedView.setVisibleInUI(true)
        terminalPanel.hostedView.setActive(true)
        window.makeKeyAndOrderFront(nil)
        window.displayIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))

        XCTAssertTrue(
            appDelegate.focusRightSidebarInActiveMainWindow(preferredWindow: window),
            "Test setup should move AppKit focus into the right sidebar"
        )
        guard let rightSidebarResponder = window.firstResponder else {
            XCTFail("Expected a right sidebar first responder")
            return
        }
        XCTAssertTrue(appDelegate.isRightSidebarFocusResponder(rightSidebarResponder, in: window))

        XCTAssertFalse(
            window.makeFirstResponder(terminalSurfaceView),
            "Programmatic AppKit first responder changes must not steal focus back from the right sidebar"
        )
        XCTAssertTrue(
            window.firstResponder === rightSidebarResponder,
            "The right sidebar first responder should remain active after a blocked terminal focus request"
        )
        XCTAssertFalse(
            terminalPanel.surface.debugDesiredFocusState(),
            "Blocked AppKit focus requests must not restart Ghostty cursor blinking"
        )
#else
        XCTFail("Debug-only regression test")
#endif
    }

    func testPointerTerminalFocusEscapesRightSidebarIntent() {
#if DEBUG
        AppDelegate.installWindowResponderSwizzlesForTesting()
        guard let appDelegate = AppDelegate.shared else {
            XCTFail("Expected AppDelegate.shared")
            return
        }

        let windowId = appDelegate.createMainWindow()
        defer { closeWindow(withId: windowId) }

        guard let window = window(withId: windowId),
              let tabManager = appDelegate.tabManagerFor(windowId: windowId),
              let workspace = tabManager.selectedWorkspace,
              let terminalPanel = workspace.focusedTerminalPanel,
              let terminalSurfaceView = surfaceView(in: terminalPanel.hostedView) else {
            XCTFail("Expected a focused terminal surface")
            return
        }

        terminalPanel.hostedView.setVisibleInUI(true)
        terminalPanel.hostedView.setActive(true)
        window.makeKeyAndOrderFront(nil)
        window.displayIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))

        XCTAssertTrue(
            appDelegate.focusRightSidebarInActiveMainWindow(preferredWindow: window),
            "Test setup should move AppKit focus into the right sidebar"
        )
        guard let event = makeMouseDownEvent(in: window) else {
            XCTFail("Failed to build mouse event")
            return
        }
        AppDelegate.setWindowFirstResponderGuardTesting(currentEvent: event, hitView: terminalSurfaceView)
        defer { AppDelegate.clearWindowFirstResponderGuardTesting() }

        XCTAssertTrue(
            window.makeFirstResponder(terminalSurfaceView),
            "A real pointer click on the terminal should be allowed to move focus back from the right sidebar"
        )
        XCTAssertTrue(terminalPanel.hostedView.isSurfaceViewFirstResponder())
        XCTAssertTrue(
            terminalPanel.surface.debugDesiredFocusState(),
            "Pointer-initiated terminal focus should restart Ghostty cursor focus"
        )
#else
        XCTFail("Debug-only regression test")
#endif
    }

    private func window(withId windowId: UUID) -> NSWindow? {
        let identifier = "cmux.main.\(windowId.uuidString)"
        return NSApp.windows.first(where: { $0.identifier?.rawValue == identifier })
    }

    private func closeWindow(withId windowId: UUID) {
        guard let window = window(withId: windowId) else { return }
        window.performClose(nil)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
    }

    private func surfaceView(in hostedView: GhosttySurfaceScrollView) -> GhosttyNSView? {
        var stack: [NSView] = [hostedView]
        while let current = stack.popLast() {
            if let surfaceView = current as? GhosttyNSView {
                return surfaceView
            }
            stack.append(contentsOf: current.subviews)
        }
        return nil
    }

    private func makeMouseDownEvent(in window: NSWindow) -> NSEvent? {
        NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1.0
        )
    }
}
