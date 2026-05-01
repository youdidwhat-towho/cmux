import Foundation

@MainActor
final class CmxConnectionStore: ObservableObject {
    @Published var ticketText = ""
    @Published private(set) var ticket: CmxBridgeTicket?
    @Published private(set) var errorText: String?
    @Published private(set) var isConnected = false
    @Published var workspaces = CmxDemoState.workspaces
    @Published var selectedWorkspaceID: UInt64 = CmxDemoState.workspaces[0].id
    @Published var selectedSpaceID: UInt64 = CmxDemoState.workspaces[0].spaces[0].id

    var selectedWorkspace: CmxWorkspace {
        workspaces.first(where: { $0.id == selectedWorkspaceID }) ?? workspaces[0]
    }

    var selectedSpace: CmxSpace {
        selectedWorkspace.spaces.first(where: { $0.id == selectedSpaceID }) ?? selectedWorkspace.spaces[0]
    }

    var selectedTerminal: CmxTerminal {
        selectedSpace.terminals[0]
    }

    var statusText: String {
        if isConnected {
            return String(localized: "status.connected", defaultValue: "Connected")
        }
        if errorText != nil {
            return String(localized: "status.needs_ticket", defaultValue: "Ticket needed")
        }
        return String(localized: "status.ready", defaultValue: "Ready")
    }

    func connect() {
        do {
            let parsed = try CmxBridgeTicketParser.parse(ticketText)
            ticket = parsed
            errorText = nil
            isConnected = true
        } catch {
            ticket = nil
            errorText = error.localizedDescription
            isConnected = false
        }
    }

    func disconnect() {
        isConnected = false
    }

    func select(workspace: CmxWorkspace) {
        selectedWorkspaceID = workspace.id
        selectedSpaceID = workspace.spaces[0].id
    }

    func select(space: CmxSpace) {
        selectedSpaceID = space.id
    }
}
