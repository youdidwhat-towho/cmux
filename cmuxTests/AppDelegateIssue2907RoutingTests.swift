import XCTest
import AppKit

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@MainActor
final class AppDelegateIssue2907RoutingTests: XCTestCase {
    private func makeMainWindow(id: UUID) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.identifier = NSUserInterfaceItemIdentifier("cmux.main.\(id.uuidString)")
        return window
    }

    private func decodeV2Response(_ response: String, file: StaticString = #filePath, line: UInt = #line) throws -> [String: Any] {
        let data = try XCTUnwrap(response.data(using: .utf8), file: file, line: line)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any], file: file, line: line)
    }

    private func v2Envelope(
        method: String,
        params: [String: Any] = [:],
        id: String? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> (raw: String, envelope: [String: Any]) {
        var request: [String: Any] = [
            "id": id ?? method,
            "method": method,
            "params": params
        ]
        if params.isEmpty {
            request["params"] = [:]
        }
        let requestData = try JSONSerialization.data(withJSONObject: request)
        let requestLine = try XCTUnwrap(String(data: requestData, encoding: .utf8), file: file, line: line)
        let raw = TerminalController.shared.handleSocketLine(requestLine)
        return (raw, try decodeV2Response(raw, file: file, line: line))
    }

    private func v2Result(
        method: String,
        params: [String: Any] = [:],
        id: String? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> [String: Any] {
        let (raw, envelope) = try v2Envelope(method: method, params: params, id: id, file: file, line: line)
        XCTAssertEqual(envelope["ok"] as? Bool, true, raw, file: file, line: line)
        return try XCTUnwrap(envelope["result"] as? [String: Any], raw, file: file, line: line)
    }

    private func v2ResultIfAvailable(
        method: String,
        params: [String: Any] = [:],
        id: String? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> [String: Any]? {
        let (raw, envelope) = try v2Envelope(method: method, params: params, id: id, file: file, line: line)
        XCTAssertEqual(envelope["ok"] as? Bool, true, raw, file: file, line: line)
        return envelope["result"] as? [String: Any]
    }

    private func workspaceListPayload(surfaceId: UUID, file: StaticString = #filePath, line: UInt = #line) throws -> [String: Any] {
        try v2Result(
            method: "workspace.list",
            params: ["surface_id": surfaceId.uuidString],
            id: "workspace-list",
            file: file,
            line: line
        )
    }

    private func assertWorkspaceListContains(
        _ payload: [String: Any],
        workspaceId: UUID,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let workspaces = try XCTUnwrap(payload["workspaces"] as? [[String: Any]], file: file, line: line)
        XCTAssertTrue(
            workspaces.contains { ($0["id"] as? String) == workspaceId.uuidString },
            "workspace.list should include \(workspaceId.uuidString)",
            file: file,
            line: line
        )
    }

    func testWorkspaceListResolvesLiveSurfaceAfterMainWindowContextAssociationIsLost() throws {
        _ = NSApplication.shared
        let app = AppDelegate()

        let windowId = UUID()
        let window = makeMainWindow(id: windowId)
        defer {
            TerminalController.shared.setActiveTabManager(nil)
            window.orderOut(nil)
        }

        let manager = TabManager()
        app.registerMainWindow(
            window,
            windowId: windowId,
            tabManager: manager,
            sidebarState: SidebarState(),
            sidebarSelectionState: SidebarSelectionState(),
            fileExplorerState: FileExplorerState()
        )
        TerminalController.shared.setActiveTabManager(manager)

        let workspace = try XCTUnwrap(manager.selectedWorkspace)
        let terminalPanel = try XCTUnwrap(workspace.focusedTerminalPanel)
        let surfaceId = terminalPanel.id
        XCTAssertTrue(TerminalSurfaceRegistry.shared.surface(id: surfaceId) === terminalPanel.surface)
        XCTAssertEqual(terminalPanel.surface.debugLastKnownWorkspaceId(), workspace.id)

        try assertWorkspaceListContains(try workspaceListPayload(surfaceId: surfaceId), workspaceId: workspace.id)

        app.unregisterMainWindowContextForTesting(windowId: windowId)
        TerminalController.shared.setActiveTabManager(nil)

        try assertWorkspaceListContains(try workspaceListPayload(surfaceId: surfaceId), workspaceId: workspace.id)
    }

    func testIssue2907TabManagerDependentSocketCommandsRecoverLiveSurfaceContext() throws {
        _ = NSApplication.shared
        let app = AppDelegate()

        let windowId = UUID()
        let window = makeMainWindow(id: windowId)
        defer {
            TerminalController.shared.setActiveTabManager(nil)
            app.unregisterMainWindowContextForTesting(windowId: windowId)
            window.orderOut(nil)
        }

        let manager = TabManager()
        app.registerMainWindow(
            window,
            windowId: windowId,
            tabManager: manager,
            sidebarState: SidebarState(),
            sidebarSelectionState: SidebarSelectionState(),
            fileExplorerState: FileExplorerState()
        )
        TerminalController.shared.setActiveTabManager(manager)

        let workspace = try XCTUnwrap(manager.selectedWorkspace)
        let terminalPanel = try XCTUnwrap(workspace.focusedTerminalPanel)
        let surfaceId = terminalPanel.id
        XCTAssertTrue(TerminalSurfaceRegistry.shared.surface(id: surfaceId) === terminalPanel.surface)
        XCTAssertEqual(terminalPanel.surface.debugLastKnownWorkspaceId(), workspace.id)

        try assertWorkspaceListContains(try v2Result(method: "workspace.list"), workspaceId: workspace.id)
        let baselineTree = try v2Result(method: "system.tree")
        let baselineWindows = try XCTUnwrap(baselineTree["windows"] as? [[String: Any]])
        XCTAssertTrue(baselineWindows.contains { ($0["id"] as? String) == windowId.uuidString })

        app.unregisterMainWindowContextForTesting(windowId: windowId)
        TerminalController.shared.setActiveTabManager(nil)

        let ping = try v2Result(method: "system.ping")
        XCTAssertEqual(ping["pong"] as? Bool, true)
        _ = try v2Result(method: "system.capabilities")

        let tree = try v2Result(method: "system.tree")
        let debugTerminals = try v2Result(method: "debug.terminals")
        let terminals = try XCTUnwrap(debugTerminals["terminals"] as? [[String: Any]])
        let originalTerminal = try XCTUnwrap(
            terminals.first { ($0["surface_id"] as? String) == surfaceId.uuidString }
        )
        XCTAssertEqual(originalTerminal["mapped"] as? Bool, true)
        XCTAssertEqual(originalTerminal["workspace_id"] as? String, workspace.id.uuidString)
        XCTAssertEqual(originalTerminal["last_known_workspace_id"] as? String, workspace.id.uuidString)

        let recoveredTreeWindows = try XCTUnwrap(tree["windows"] as? [[String: Any]])
        XCTAssertTrue(
            recoveredTreeWindows.contains { ($0["id"] as? String) == windowId.uuidString },
            "system.tree should not report an empty world while a live terminal surface is still associated with its workspace"
        )

        if let currentWindow = try v2ResultIfAvailable(method: "window.current") {
            XCTAssertEqual(currentWindow["window_id"] as? String, windowId.uuidString)
        }
        if let currentWorkspace = try v2ResultIfAvailable(method: "workspace.current") {
            XCTAssertEqual(currentWorkspace["workspace_id"] as? String, workspace.id.uuidString)
        }
        if let workspaceList = try v2ResultIfAvailable(method: "workspace.list") {
            try assertWorkspaceListContains(workspaceList, workspaceId: workspace.id)
        }
        if let workspaceListBySurface = try v2ResultIfAvailable(method: "workspace.list", params: ["surface_id": surfaceId.uuidString]) {
            try assertWorkspaceListContains(workspaceListBySurface, workspaceId: workspace.id)
        }
        if let surfaces = try v2ResultIfAvailable(method: "surface.list", params: ["surface_id": surfaceId.uuidString]) {
            XCTAssertEqual(surfaces["workspace_id"] as? String, workspace.id.uuidString)
        }
        if let currentSurface = try v2ResultIfAvailable(method: "surface.current", params: ["surface_id": surfaceId.uuidString]) {
            XCTAssertEqual(currentSurface["workspace_id"] as? String, workspace.id.uuidString)
        }
        if let panes = try v2ResultIfAvailable(method: "pane.list", params: ["surface_id": surfaceId.uuidString]) {
            XCTAssertEqual(panes["workspace_id"] as? String, workspace.id.uuidString)
        }
        if let health = try v2ResultIfAvailable(method: "surface.health", params: ["surface_id": surfaceId.uuidString]) {
            XCTAssertEqual(health["workspace_id"] as? String, workspace.id.uuidString)
        }
        if let split = try v2ResultIfAvailable(
            method: "surface.split",
            params: [
                "surface_id": surfaceId.uuidString,
                "direction": "right",
                "focus": false
            ]
        ) {
            XCTAssertNotNil(split["surface_id"] as? String)
        }
    }

    func testIssue2907NoTargetCommandsPreferKeyRecoveredWindowOverRegisteredWindow() throws {
        _ = NSApplication.shared
        let app = AppDelegate()

        let registeredWindowId = UUID()
        let recoveredWindowId = UUID()
        let registeredWindow = makeMainWindow(id: registeredWindowId)
        let recoveredWindow = makeMainWindow(id: recoveredWindowId)
        defer {
            TerminalController.shared.setActiveTabManager(nil)
            app.unregisterMainWindowContextForTesting(windowId: registeredWindowId)
            app.unregisterMainWindowContextForTesting(windowId: recoveredWindowId)
            registeredWindow.orderOut(nil)
            recoveredWindow.orderOut(nil)
        }

        let registeredManager = TabManager()
        let recoveredManager = TabManager()
        app.registerMainWindow(
            registeredWindow,
            windowId: registeredWindowId,
            tabManager: registeredManager,
            sidebarState: SidebarState(),
            sidebarSelectionState: SidebarSelectionState(),
            fileExplorerState: FileExplorerState()
        )
        app.registerMainWindow(
            recoveredWindow,
            windowId: recoveredWindowId,
            tabManager: recoveredManager,
            sidebarState: SidebarState(),
            sidebarSelectionState: SidebarSelectionState(),
            fileExplorerState: FileExplorerState()
        )

        registeredWindow.makeKeyAndOrderFront(nil)
        recoveredWindow.makeKeyAndOrderFront(nil)
        TerminalController.shared.setActiveTabManager(recoveredManager)

        let recoveredWorkspace = try XCTUnwrap(recoveredManager.selectedWorkspace)
        let recoveredTerminal = try XCTUnwrap(recoveredWorkspace.focusedTerminalPanel)
        XCTAssertTrue(TerminalSurfaceRegistry.shared.surface(id: recoveredTerminal.id) === recoveredTerminal.surface)

        app.unregisterMainWindowContextForTesting(windowId: recoveredWindowId)
        TerminalController.shared.setActiveTabManager(nil)

        let currentWindow = try v2Result(method: "window.current")
        XCTAssertEqual(currentWindow["window_id"] as? String, recoveredWindowId.uuidString)

        let currentWorkspace = try v2Result(method: "workspace.current")
        XCTAssertEqual(currentWorkspace["workspace_id"] as? String, recoveredWorkspace.id.uuidString)
    }
}
