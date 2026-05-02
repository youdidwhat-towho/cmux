import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: CmxConnectionStore

    var body: some View {
        NavigationSplitView {
            WorkspaceListView()
        } detail: {
            TerminalDetailView()
        }
    }
}

private struct WorkspaceListView: View {
    @EnvironmentObject private var store: CmxConnectionStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var searchText = ""

    private var workspaces: [CmxWorkspace] {
        store.visibleWorkspaces(matching: searchText)
    }

    var body: some View {
        List {
            WorkspaceSearchField(text: $searchText)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 14, trailing: 16))
                .listRowSeparator(.hidden)

            Section {
                NodeStrip()
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .padding(.top, 6)
                    .padding(.bottom, 8)
            } header: {
                Text(String(localized: "home.nodes.header", defaultValue: "Nodes"))
            }
            .textCase(nil)

            Section {
                if workspaces.isEmpty {
                    EmptyWorkspaceSearch()
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 18, leading: 16, bottom: 18, trailing: 16))
                } else {
                    ForEach(workspaces) { workspace in
                        let node = store.node(for: workspace)
                        NavigationLink {
                            TerminalDetailView()
                                .onAppear {
                                    store.select(workspace: workspace)
                                }
                        } label: {
                            WorkspaceConversationRow(
                                workspace: workspace,
                                node: node,
                                isSelected: horizontalSizeClass == .regular && workspace.id == store.selectedWorkspaceID
                            )
                        }
                        .accessibilityIdentifier("workspace.row.\(workspace.id)")
                    }
                }
            } header: {
                Text(String(localized: "home.recent.header", defaultValue: "Recent"))
            }
            .textCase(nil)
        }
        .listStyle(.plain)
        .navigationTitle(String(localized: "nav.workspaces", defaultValue: "Workspaces"))
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                    } label: {
                        Label(String(localized: "home.menu.refresh_nodes", defaultValue: "Refresh Nodes"), systemImage: "arrow.clockwise")
                    }
                    .disabled(true)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .accessibilityLabel(String(localized: "home.menu.more", defaultValue: "More"))
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

private struct WorkspaceSearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField(String(localized: "home.search.prompt", defaultValue: "Search workspaces"), text: $text)
                .textFieldStyle(.plain)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityIdentifier("workspace.search")
    }
}

private struct NodeStrip: View {
    @EnvironmentObject private var store: CmxConnectionStore

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 14) {
                ForEach(store.nodes) { node in
                    NodePin(node: node, workspaceCount: store.workspaceCount(for: node))
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

private struct NodePin: View {
    let node: CmxHiveNode
    let workspaceCount: Int

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                Circle()
                    .fill(nodeGradient)
                    .frame(width: 62, height: 62)
                    .overlay {
                        if !node.isOnline {
                            Circle()
                                .fill(Color.gray.opacity(0.52))
                        }
                    }

                Image(systemName: node.symbolName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)

                if workspaceCount > 0 {
                    Text("\(workspaceCount)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.black.opacity(0.72)))
                        .offset(x: 8, y: -6)
                }
            }

            Text(node.name)
                .font(.caption.weight(.semibold))
                .lineLimit(1)

            Text(node.isOnline ? node.subtitle : String(localized: "home.node.offline", defaultValue: "offline"))
                .font(.caption2)
                .foregroundStyle(node.isOnline ? Color.secondary : Color.orange)
                .lineLimit(1)
        }
        .frame(width: 94)
        .opacity(node.isOnline ? 1.0 : 0.55)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("node.pin.\(node.id)")
    }

    private var nodeGradient: LinearGradient {
        let colors: [Color]
        switch node.id % 3 {
        case 0:
            colors = [Color.blue, Color.cyan]
        case 1:
            colors = [Color.green, Color.teal]
        default:
            colors = [Color.indigo, Color.orange]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

private struct WorkspaceConversationRow: View {
    let workspace: CmxWorkspace
    let node: CmxHiveNode
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                Circle()
                    .fill(avatarGradient)
                    .frame(width: 48, height: 48)

                Image(systemName: node.symbolName)
                    .font(.headline)
                    .foregroundStyle(.white)

                if workspace.unread {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 11, height: 11)
                        .overlay(Circle().stroke(Color.white, lineWidth: 2))
                        .offset(x: 2, y: 2)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if workspace.pinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Text(workspace.title)
                        .font(.headline)
                        .lineLimit(1)

                    Spacer(minLength: 10)

                    Text(relativeTimestamp)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text(workspace.preview)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Circle()
                        .fill(node.isOnline ? Color.green : Color.orange)
                        .frame(width: 7, height: 7)
                    Text(node.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Text(
                        String(
                            format: String(localized: "workspace.row.detail", defaultValue: "%d spaces, %d terminals"),
                            workspace.spaces.count,
                            workspace.spaces.reduce(0) { $0 + $1.terminals.count }
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .padding(.horizontal, isSelected ? 10 : 0)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.accentColor.opacity(0.14))
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var avatarGradient: LinearGradient {
        let colors: [Color]
        switch node.id % 3 {
        case 0:
            colors = [Color.blue, Color.cyan]
        case 1:
            colors = [Color.green, Color.teal]
        default:
            colors = [Color.indigo, Color.orange]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var relativeTimestamp: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(workspace.lastActivity) {
            return workspace.lastActivity.formatted(date: .omitted, time: .shortened)
        }
        if calendar.isDateInYesterday(workspace.lastActivity) {
            return String(localized: "home.timestamp.yesterday", defaultValue: "Yesterday")
        }
        return workspace.lastActivity.formatted(.dateTime.month(.defaultDigits).day(.defaultDigits))
    }
}

private struct EmptyWorkspaceSearch: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(String(localized: "home.search.empty.title", defaultValue: "No Workspaces"))
                .font(.headline)
            Text(String(localized: "home.search.empty.body", defaultValue: "No matching workspace is available on your signed-in nodes."))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
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
                Button(store.isConnected || store.isConnecting ? String(localized: "button.disconnect", defaultValue: "Disconnect") : String(localized: "button.connect", defaultValue: "Connect")) {
                    if store.isConnected || store.isConnecting {
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
    @EnvironmentObject private var store: CmxConnectionStore
    let terminal: CmxTerminal

    var body: some View {
        CmxGhosttyTerminalView(store: store, terminalID: terminal.id)
            .id(terminal.id)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
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
