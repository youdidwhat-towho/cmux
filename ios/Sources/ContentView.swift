import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: CmxConnectionStore

    var body: some View {
        NavigationSplitView {
            WorkspaceListView()
                .navigationTitle(String(localized: "nav.workspaces", defaultValue: "Workspaces"))
        } detail: {
            TerminalDetailView()
        }
    }
}

private struct WorkspaceListView: View {
    @EnvironmentObject private var store: CmxConnectionStore

    var body: some View {
        List {
            Section {
                ForEach(store.workspaces) { workspace in
                    NavigationLink {
                        TerminalDetailView()
                            .onAppear {
                                store.select(workspace: workspace)
                            }
                    } label: {
                        WorkspaceRow(workspace: workspace)
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            TicketPanel()
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(.bar)
        }
    }
}

private struct WorkspaceRow: View {
    let workspace: CmxWorkspace

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(workspace.title)
                .font(.headline)
            Text(
                String(
                    format: String(localized: "workspace.row.detail", defaultValue: "%d spaces, %d terminals"),
                    workspace.spaces.count,
                    workspace.spaces.reduce(0) { $0 + $1.terminals.count }
                )
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct TicketPanel: View {
    @EnvironmentObject private var store: CmxConnectionStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(store.statusText, systemImage: store.isConnected ? "checkmark.circle.fill" : "bolt.horizontal.circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(store.isConnected ? .green : .secondary)
                Spacer()
                Button(store.isConnected ? String(localized: "button.disconnect", defaultValue: "Disconnect") : String(localized: "button.connect", defaultValue: "Connect")) {
                    if store.isConnected {
                        store.disconnect()
                    } else {
                        store.connect()
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            TextField(
                String(localized: "ticket.placeholder", defaultValue: "Paste iroh bridge ticket"),
                text: $store.ticketText,
                axis: .vertical
            )
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .font(.system(.caption, design: .monospaced))
            .lineLimit(2...4)

            if let errorText = store.errorText {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }
}

private struct TerminalDetailView: View {
    @EnvironmentObject private var store: CmxConnectionStore

    var body: some View {
        VStack(spacing: 0) {
            SpaceStrip()
            TerminalPane(terminal: store.selectedTerminal)
            BridgeSummary(ticket: store.ticket)
        }
        .navigationTitle(store.selectedWorkspace.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SpaceStrip: View {
    @EnvironmentObject private var store: CmxConnectionStore

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(store.selectedWorkspace.spaces) { space in
                    Button {
                        store.select(space: space)
                    } label: {
                        Text(space.title)
                            .font(.callout.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(space.id == store.selectedSpaceID ? Color.accentColor.opacity(0.14) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(.bar)
    }
}

private struct TerminalPane: View {
    let terminal: CmxTerminal

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                Text(terminal.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 8)
                ForEach(Array(terminal.rows.enumerated()), id: \.offset) { _, row in
                    Text(row)
                        .font(.system(size: 13, weight: .regular, design: .monospaced))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(14)
        }
        .background(Color(.systemBackground))
    }
}

private struct BridgeSummary: View {
    let ticket: CmxBridgeTicket?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "bridge.summary.title", defaultValue: "Iroh bridge"))
                .font(.caption.weight(.semibold))
            if let ticket {
                Text(ticket.endpoint.id)
                    .font(.system(.caption2, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let auth = ticket.auth {
                    Text(auth.label)
                        .font(.system(.caption2, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                ForEach(ticket.endpoint.addrs) { route in
                    Text(route.label)
                        .font(.system(.caption2, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            } else {
                Text(String(localized: "bridge.summary.empty", defaultValue: "Paste a bridge ticket to attach this device."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.bar)
    }
}
