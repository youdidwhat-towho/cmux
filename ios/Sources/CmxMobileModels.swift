import Foundation

struct CmxWorkspace: Identifiable, Equatable {
    let id: UInt64
    var title: String
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
    var rows: [String]
}

enum CmxDemoState {
    static let workspaces: [CmxWorkspace] = [
        CmxWorkspace(
            id: 1,
            title: String(localized: "demo.workspace.main", defaultValue: "main"),
            spaces: [
                CmxSpace(
                    id: 10,
                    title: String(localized: "demo.space.space1", defaultValue: "space-1"),
                    terminals: [
                        CmxTerminal(
                            id: 100,
                            title: String(localized: "demo.terminal.cmx", defaultValue: "cmx"),
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
            title: String(localized: "demo.workspace.agent_runs", defaultValue: "agent runs"),
            spaces: [
                CmxSpace(
                    id: 20,
                    title: String(localized: "demo.space.review", defaultValue: "review"),
                    terminals: [
                        CmxTerminal(
                            id: 200,
                            title: String(localized: "demo.terminal.status", defaultValue: "status"),
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
