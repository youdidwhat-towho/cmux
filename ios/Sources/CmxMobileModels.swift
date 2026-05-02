import Foundation

struct CmxHiveNode: Identifiable, Equatable {
    let id: UInt64
    var name: String
    var subtitle: String
    var symbolName: String
    var isOnline: Bool
}

struct CmxWorkspace: Identifiable, Equatable {
    let id: UInt64
    var nodeID: UInt64
    var title: String
    var preview: String
    var lastActivity: Date
    var unread: Bool
    var pinned: Bool
    var spaces: [CmxSpace]
}

struct CmxSpace: Identifiable, Equatable {
    let id: UInt64
    var title: String
    var terminals: [CmxTerminal]
}

struct CmxTerminal: Identifiable, Equatable {
    let id: UInt64
    var title: String
    var size: CmxTerminalSize
    var rows: [String]
}

struct CmxTerminalSize: Equatable, Sendable {
    var cols: Int
    var rows: Int

    static let phoneDefault = CmxTerminalSize(cols: 80, rows: 24)
}

struct CmxTerminalOutputChunk: Identifiable, Equatable {
    let id: Int
    let data: Data
}

enum CmxDemoState {
    private static let referenceDate = Date(timeIntervalSince1970: 1_777_680_000)

    static let nodes: [CmxHiveNode] = [
        CmxHiveNode(
            id: 1,
            name: String(localized: "demo.node.macbook", defaultValue: "MacBook Pro"),
            subtitle: String(localized: "demo.node.macbook.subtitle", defaultValue: "local dev node"),
            symbolName: "laptopcomputer",
            isOnline: true
        ),
        CmxHiveNode(
            id: 2,
            name: String(localized: "demo.node.mac_mini", defaultValue: "Mac mini"),
            subtitle: String(localized: "demo.node.mac_mini.subtitle", defaultValue: "hive standby"),
            symbolName: "macmini",
            isOnline: true
        ),
    ]

    static let workspaces: [CmxWorkspace] = [
        CmxWorkspace(
            id: 1,
            nodeID: 1,
            title: String(localized: "demo.workspace.main", defaultValue: "main"),
            preview: String(localized: "demo.workspace.main.preview", defaultValue: "cmx tui attached over Ghostty"),
            lastActivity: referenceDate.addingTimeInterval(-120),
            unread: true,
            pinned: true,
            spaces: [
                CmxSpace(
                    id: 10,
                    title: String(localized: "demo.space.space1", defaultValue: "space-1"),
                    terminals: [
                        CmxTerminal(
                            id: 100,
                            title: String(localized: "demo.terminal.cmx", defaultValue: "cmx"),
                            size: .phoneDefault,
                            rows: [
                                String(localized: "demo.row.cwd", defaultValue: "lawrence in ~/fun/cmux-cli"),
                                String(localized: "demo.row.list_workspaces", defaultValue: "$ cmx list-workspaces"),
                                String(localized: "demo.row.workspace_output", defaultValue: "0  main   spaces 2   terminals 3"),
                                String(localized: "demo.row.bridge_command", defaultValue: "$ cmux-iroh-bridge --socket $CMX_SOCKET_PATH"),
                                String(localized: "demo.row.bridge_ticket", defaultValue: "{\"version\":1,\"alpn\":\"/cmux/cmx/3\",...}"),
                            ]
                        ),
                    ]
                ),
                CmxSpace(
                    id: 11,
                    title: String(localized: "demo.space.logs", defaultValue: "logs"),
                    terminals: [
                        CmxTerminal(
                            id: 101,
                            title: String(localized: "demo.terminal.bridge", defaultValue: "bridge"),
                            size: .phoneDefault,
                            rows: [
                                String(localized: "demo.row.iroh_ready", defaultValue: "iroh endpoint ready"),
                                String(localized: "demo.row.snapshot_attached", defaultValue: "native snapshot stream attached"),
                                String(localized: "demo.row.grid_flowing", defaultValue: "terminal grid snapshots flowing over QUIC"),
                            ]
                        ),
                    ]
                ),
            ]
        ),
        CmxWorkspace(
            id: 2,
            nodeID: 2,
            title: String(localized: "demo.workspace.agent_runs", defaultValue: "agent runs"),
            preview: String(localized: "demo.workspace.agent_runs.preview", defaultValue: "review pane waiting on sync"),
            lastActivity: referenceDate.addingTimeInterval(-3_600),
            unread: false,
            pinned: false,
            spaces: [
                CmxSpace(
                    id: 20,
                    title: String(localized: "demo.space.review", defaultValue: "review"),
                    terminals: [
                        CmxTerminal(
                            id: 200,
                            title: String(localized: "demo.terminal.status", defaultValue: "status"),
                            size: .phoneDefault,
                            rows: [
                                String(localized: "demo.row.spaces_map", defaultValue: "spaces map to cmx spaces"),
                                String(localized: "demo.row.panes_map", defaultValue: "terminal panes map to cmx panels"),
                                String(localized: "demo.row.state_native", defaultValue: "first sync path renders the Rust TUI frame"),
                            ]
                        ),
                    ]
                ),
            ]
        ),
    ]
}
