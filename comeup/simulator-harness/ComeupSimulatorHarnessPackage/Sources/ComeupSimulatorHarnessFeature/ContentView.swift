import SwiftUI

public struct ContentView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedWorkspaceID: String?
    @State private var selectedTerminalID: String?

    private let snapshot: CmuxMobileHomeSnapshot

    public init(snapshot: CmuxMobileHomeSnapshot = .fixture) {
        self.snapshot = snapshot
        _selectedWorkspaceID = State(initialValue: snapshot.workspaces.first?.id)
        _selectedTerminalID = State(initialValue: snapshot.workspaces.first?.terminalTree.first?.terminal.id)
    }

    public var body: some View {
        if horizontalSizeClass == .regular {
            NavigationSplitView {
                WorkspaceHomeView(
                    snapshot: snapshot,
                    selectedWorkspaceID: $selectedWorkspaceID,
                    selectedTerminalID: $selectedTerminalID,
                    compactNavigation: false
                )
            } detail: {
                WorkspaceDetailView(
                    snapshot: snapshot,
                    workspaceID: selectedWorkspaceID,
                    selectedTerminalID: $selectedTerminalID
                )
            }
        } else {
            NavigationStack {
                WorkspaceHomeView(
                    snapshot: snapshot,
                    selectedWorkspaceID: $selectedWorkspaceID,
                    selectedTerminalID: $selectedTerminalID,
                    compactNavigation: true
                )
            }
        }
    }
}

private struct WorkspaceHomeView: View {
    let snapshot: CmuxMobileHomeSnapshot
    @Binding var selectedWorkspaceID: String?
    @Binding var selectedTerminalID: String?
    let compactNavigation: Bool

    var body: some View {
        List {
            Section {
                AuthStatusRow(auth: snapshot.auth)
                    .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
            }

            Section {
                NodeDiscoveryStrip(nodes: snapshot.nodes)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
            }

            Section {
                ForEach(snapshot.workspaces) { workspace in
                    if compactNavigation {
                        NavigationLink {
                            WorkspaceDetailView(
                                snapshot: snapshot,
                                workspaceID: workspace.id,
                                selectedTerminalID: $selectedTerminalID
                            )
                            .onAppear {
                                selectedWorkspaceID = workspace.id
                                selectedTerminalID = workspace.terminalTree.first?.terminal.id
                            }
                        } label: {
                            WorkspaceConversationRow(
                                workspace: workspace,
                                node: snapshot.node(id: workspace.nodeID)
                            )
                        }
                        .accessibilityIdentifier("workspace.row.\(workspace.id)")
                    } else {
                        WorkspaceConversationRow(
                            workspace: workspace,
                            node: snapshot.node(id: workspace.nodeID)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedWorkspaceID = workspace.id
                            selectedTerminalID = workspace.terminalTree.first?.terminal.id
                        }
                        .accessibilityIdentifier("workspace.row.\(workspace.id)")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(String(localized: "ios.home.title", defaultValue: "Workspaces"))
        .accessibilityIdentifier("cmux.mobile.home")
    }
}

private struct AuthStatusRow: View {
    let auth: CmuxAuthSnapshot

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: authSymbol)
                .font(.title2)
                .foregroundStyle(authColor)
                .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(auth.displayName)
                    .font(.headline)
                    .lineLimit(1)
                Text(auth.primaryEmail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(authLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(authColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(authColor.opacity(0.12), in: Capsule())
        }
        .accessibilityIdentifier("auth.status.row")
    }

    private var authLabel: String {
        switch auth.state {
        case .signedOut:
            String(localized: "ios.auth.signedOut", defaultValue: "Signed out")
        case .restoring:
            String(localized: "ios.auth.restoring", defaultValue: "Restoring")
        case .signedIn:
            String(localized: "ios.auth.signedIn", defaultValue: "Signed in")
        }
    }

    private var authSymbol: String {
        switch auth.state {
        case .signedOut:
            "person.crop.circle.badge.xmark"
        case .restoring:
            "arrow.triangle.2.circlepath.circle"
        case .signedIn:
            "person.crop.circle.fill.badge.checkmark"
        }
    }

    private var authColor: Color {
        switch auth.state {
        case .signedOut:
            .orange
        case .restoring:
            .blue
        case .signedIn:
            .green
        }
    }
}

private struct NodeDiscoveryStrip: View {
    let nodes: [CmuxHiveNode]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(nodes) { node in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(color(for: node.status))
                            .frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(node.name)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                            Text(node.route)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityIdentifier("hive.node.\(node.id)")
                }
            }
            .padding(.horizontal, 16)
        }
        .accessibilityIdentifier("hive.node.strip")
    }

    private func color(for status: CmuxHiveNode.Status) -> Color {
        switch status {
        case .online:
            .green
        case .connecting:
            .blue
        case .offline:
            .gray
        }
    }
}

private struct WorkspaceConversationRow: View {
    let workspace: CmuxMobileWorkspace
    let node: CmuxHiveNode?

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.16))
                Text(initials)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(workspace.title)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                    Text(node?.name ?? String(localized: "ios.node.unknown", defaultValue: "Unknown"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text(workspace.lastMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if workspace.unreadCount > 0 {
                Text("\(workspace.unreadCount)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(minWidth: 22, minHeight: 22)
                    .background(Color.accentColor, in: Circle())
            }
        }
        .padding(.vertical, 6)
    }

    private var initials: String {
        workspace.title
            .split(separator: " ")
            .prefix(2)
            .compactMap(\.first)
            .map(String.init)
            .joined()
            .uppercased()
    }
}

private struct WorkspaceDetailView: View {
    let snapshot: CmuxMobileHomeSnapshot
    let workspaceID: String?
    @Binding var selectedTerminalID: String?

    private var workspace: CmuxMobileWorkspace {
        snapshot.workspace(id: workspaceID)
    }

    private var selectedTerminal: CmuxMobileTerminal {
        workspace.terminal(id: selectedTerminalID)
    }

    var body: some View {
        VStack(spacing: 0) {
            TerminalPicker(
                workspace: workspace,
                selectedTerminalID: $selectedTerminalID
            )
            TerminalScreen(terminal: selectedTerminal)
        }
        .navigationTitle(workspace.title)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("workspace.detail.\(workspace.id)")
    }
}

private struct TerminalPicker: View {
    let workspace: CmuxMobileWorkspace
    @Binding var selectedTerminalID: String?

    var body: some View {
        Menu {
            ForEach(workspace.terminalTree) { row in
                Button {
                    selectedTerminalID = row.terminal.id
                } label: {
                    Label(
                        "\(row.space.title) / \(row.pane.title) / \(row.terminal.title)",
                        systemImage: row.terminal.id == selectedTerminalID ? "checkmark.circle.fill" : "terminal"
                    )
                }
                .accessibilityIdentifier("terminal.option.\(row.terminal.id)")
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "terminal")
                Text(selectedTreeLabel)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
        }
        .buttonStyle(.plain)
        .background(.bar)
        .accessibilityIdentifier("terminal.tree.menu")
    }

    private var selectedTreeLabel: String {
        guard let row = workspace.terminalTree.first(where: { $0.terminal.id == selectedTerminalID }) else {
            return workspace.terminalTree[0].terminal.title
        }
        return "\(row.space.title) / \(row.pane.title) / \(row.terminal.title)"
    }
}

private struct TerminalScreen: View {
    let terminal: CmuxMobileTerminal

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(terminal.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(terminal.size.cols)x\(terminal.size.rows)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
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
        .accessibilityIdentifier("terminal.screen.\(terminal.id)")
    }
}

#Preview {
    ContentView()
}
