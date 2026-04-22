import AppKit
import SwiftUI
import WebKit

/// Built-in right-sidebar panels. Config-defined panels share the same registry
/// but keep their own stable string identifiers.
enum RightSidebarMode: String, CaseIterable, Equatable {
    case files
    case sessions

    init?(panelId: String) {
        switch panelId {
        case Self.files.panelId, Self.files.rawValue:
            self = .files
        case Self.sessions.panelId, Self.sessions.rawValue:
            self = .sessions
        default:
            return nil
        }
    }

    var panelId: String {
        switch self {
        case .files: return "builtin.files"
        case .sessions: return "builtin.sessions"
        }
    }

    var label: String {
        switch self {
        case .files: return String(localized: "rightSidebar.mode.files", defaultValue: "Files")
        case .sessions: return String(localized: "rightSidebar.mode.sessions", defaultValue: "Sessions")
        }
    }

    var symbolName: String {
        switch self {
        case .files: return "folder"
        case .sessions: return "bubble.left.and.text.bubble.right"
        }
    }
}

enum RightSidebarCommandRefresh: String, Equatable {
    case manual
    case onAppear
}

enum RightSidebarConfiguredPanelSource: Equatable {
    case builtIn(RightSidebarMode)
    case markdown(path: String)
    case web(url: String)
    case command(command: String, cwd: String?, refresh: RightSidebarCommandRefresh)
}

struct RightSidebarConfiguredPanel: Equatable {
    var id: String
    var title: String?
    var symbolName: String?
    var isEnabled: Bool
    var source: RightSidebarConfiguredPanelSource
}

struct RightSidebarSettings: Equatable {
    static let defaultValue = RightSidebarSettings()

    var selectedPanelId: String?
    var panels: [RightSidebarConfiguredPanel]?
}

private enum RightSidebarPanelSource: Equatable {
    case builtIn(RightSidebarMode)
    case markdown(path: String)
    case web(url: String)
    case command(command: String, cwd: String?, refresh: RightSidebarCommandRefresh)
}

private struct RightSidebarPanelDescriptor: Identifiable, Equatable {
    var id: String
    var title: String
    var symbolName: String
    var source: RightSidebarPanelSource
}

private enum RightSidebarPanelRegistry {
    static func descriptors(from settings: RightSidebarSettings) -> [RightSidebarPanelDescriptor] {
        guard let configuredPanels = settings.panels else {
            return builtInDescriptors()
        }

        var descriptors: [RightSidebarPanelDescriptor] = []
        var seenIds: Set<String> = []
        for panel in configuredPanels where panel.isEnabled {
            guard seenIds.insert(panel.id).inserted else { continue }
            descriptors.append(descriptor(for: panel))
        }

        return descriptors.isEmpty ? builtInDescriptors() : descriptors
    }

    static func isValidPanelId(_ id: String, in descriptors: [RightSidebarPanelDescriptor]) -> Bool {
        descriptors.contains { $0.id == id }
    }

    private static func builtInDescriptors() -> [RightSidebarPanelDescriptor] {
        RightSidebarMode.allCases.map { mode in
            RightSidebarPanelDescriptor(
                id: mode.panelId,
                title: mode.label,
                symbolName: mode.symbolName,
                source: .builtIn(mode)
            )
        }
    }

    private static func descriptor(for panel: RightSidebarConfiguredPanel) -> RightSidebarPanelDescriptor {
        switch panel.source {
        case .builtIn(let mode):
            return RightSidebarPanelDescriptor(
                id: panel.id,
                title: panel.title?.trimmedNonEmpty ?? mode.label,
                symbolName: panel.symbolName?.trimmedNonEmpty ?? mode.symbolName,
                source: .builtIn(mode)
            )
        case .markdown(let path):
            return RightSidebarPanelDescriptor(
                id: panel.id,
                title: panel.title?.trimmedNonEmpty ?? panel.id,
                symbolName: panel.symbolName?.trimmedNonEmpty ?? "doc.richtext",
                source: .markdown(path: path)
            )
        case .web(let url):
            return RightSidebarPanelDescriptor(
                id: panel.id,
                title: panel.title?.trimmedNonEmpty ?? panel.id,
                symbolName: panel.symbolName?.trimmedNonEmpty ?? "globe",
                source: .web(url: url)
            )
        case .command(let command, let cwd, let refresh):
            return RightSidebarPanelDescriptor(
                id: panel.id,
                title: panel.title?.trimmedNonEmpty ?? panel.id,
                symbolName: panel.symbolName?.trimmedNonEmpty ?? "terminal",
                source: .command(command: command, cwd: cwd, refresh: refresh)
            )
        }
    }
}

/// Right sidebar root view. Hosts a configurable panel switcher plus the active panel.
struct RightSidebarPanelView: View {
    @ObservedObject var fileExplorerStore: FileExplorerStore
    @ObservedObject var fileExplorerState: FileExplorerState
    @ObservedObject var sessionIndexStore: SessionIndexStore
    @ObservedObject private var settingsObserver = KeyboardShortcutSettingsObserver.shared

    let onResumeSession: ((SessionEntry) -> Void)?

    private var rightSidebarSettings: RightSidebarSettings {
        KeyboardShortcutSettings.settingsFileStore.rightSidebarSettings()
    }

    private var panelDescriptors: [RightSidebarPanelDescriptor] {
        RightSidebarPanelRegistry.descriptors(from: rightSidebarSettings)
    }

    private var selectedDescriptor: RightSidebarPanelDescriptor {
        let descriptors = panelDescriptors
        if let selected = descriptors.first(where: { $0.id == fileExplorerState.selectedPanelId }) {
            return selected
        }
        return descriptors[0]
    }

    private var selectedPanelBinding: Binding<String> {
        Binding(
            get: { selectedDescriptor.id },
            set: { panelId in
                guard let descriptor = panelDescriptors.first(where: { $0.id == panelId }) else { return }
                selectPanel(descriptor)
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            modeBar
            Divider()
            content(for: selectedDescriptor)
                .id(selectedDescriptor.id)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            synchronizeSelection(applyConfiguredSelection: true)
        }
        .onChange(of: settingsObserver.revision) { _ in
            synchronizeSelection(applyConfiguredSelection: true)
        }
    }

    private var modeBar: some View {
        HStack(spacing: 0) {
            Picker(
                String(localized: "rightSidebar.panelPicker.accessibilityLabel", defaultValue: "Right sidebar panel"),
                selection: selectedPanelBinding
            ) {
                ForEach(panelDescriptors) { descriptor in
                    Label(descriptor.title, systemImage: descriptor.symbolName)
                        .tag(descriptor.id)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .fixedSize(horizontal: true, vertical: false)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .frame(height: 31)
    }

    @ViewBuilder
    private func content(for descriptor: RightSidebarPanelDescriptor) -> some View {
        switch descriptor.source {
        case .builtIn(.files):
            FileExplorerPanelView(store: fileExplorerStore, state: fileExplorerState)
        case .builtIn(.sessions):
            SessionIndexView(store: sessionIndexStore, onResume: onResumeSession)
                .onAppear {
                    prepareSessionIndex()
                }
        case .markdown(let path):
            RightSidebarMarkdownPanelView(path: path)
        case .web(let url):
            RightSidebarWebPanelView(rawURL: url)
        case .command(let command, let cwd, let refresh):
            RightSidebarCommandPanelView(command: command, cwd: cwd, refresh: refresh)
        }
    }

    private func selectPanel(_ descriptor: RightSidebarPanelDescriptor) {
        guard fileExplorerState.selectedPanelId != descriptor.id else { return }
        fileExplorerState.selectedPanelId = descriptor.id
        if descriptor.source == .builtIn(.sessions) {
            prepareSessionIndex()
        }
    }

    private func synchronizeSelection(applyConfiguredSelection: Bool) {
        let descriptors = panelDescriptors
        if applyConfiguredSelection,
           let configuredPanelId = rightSidebarSettings.selectedPanelId,
           RightSidebarPanelRegistry.isValidPanelId(configuredPanelId, in: descriptors) {
            if fileExplorerState.selectedPanelId != configuredPanelId {
                fileExplorerState.selectedPanelId = configuredPanelId
            }
            return
        }

        if !RightSidebarPanelRegistry.isValidPanelId(fileExplorerState.selectedPanelId, in: descriptors),
           let first = descriptors.first {
            fileExplorerState.selectedPanelId = first.id
        }
    }

    private func prepareSessionIndex() {
        sessionIndexStore.setCurrentDirectoryIfChanged(sessionIndexDirectory)
        if sessionIndexStore.entries.isEmpty {
            sessionIndexStore.reload()
        }
    }

    private var sessionIndexDirectory: String? {
        fileExplorerStore.rootPath.isEmpty ? nil : fileExplorerStore.rootPath
    }
}

private struct RightSidebarMarkdownPanelView: View {
    let path: String

    @State private var contents: String = ""
    @State private var isUnavailable = false

    var body: some View {
        Group {
            if isUnavailable {
                unavailableView
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        pathHeader
                        Divider()
                        markdownBody
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .onAppear(perform: reload)
        .onChange(of: path) { _ in reload() }
    }

    private var pathHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.richtext")
                .foregroundStyle(.secondary)
            Text(displayPath)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            Button(action: reload) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .help(String(localized: "browser.reload", defaultValue: "Reload"))
        }
    }

    private var markdownBody: some View {
        Group {
            if let attributed = try? AttributedString(markdown: contents) {
                Text(attributed)
            } else {
                Text(contents)
            }
        }
        .font(.system(size: 12))
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var unavailableView: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.questionmark")
                .font(.system(size: 30))
                .foregroundStyle(.secondary)
            Text(String(localized: "markdown.fileUnavailable.title", defaultValue: "File unavailable"))
                .font(.headline)
            Text(displayPath)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Button(String(localized: "browser.reload", defaultValue: "Reload"), action: reload)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func reload() {
        let expanded = (path as NSString).expandingTildeInPath
        do {
            contents = try String(contentsOfFile: expanded, encoding: .utf8)
            isUnavailable = false
        } catch {
            contents = ""
            isUnavailable = true
        }
    }

    private var displayPath: String {
        (path as NSString).abbreviatingWithTildeInPath
    }
}

private struct RightSidebarWebPanelView: View {
    let rawURL: String

    var body: some View {
        if let url = URL(string: rawURL), url.scheme != nil {
            RightSidebarWebView(url: url)
        } else {
            VStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
                Text(String(localized: "rightSidebar.web.invalidURL", defaultValue: "Invalid URL"))
                    .font(.headline)
                Text(rawURL)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
            }
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct RightSidebarWebView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.underPageBackgroundColor = .clear
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        guard nsView.url != url else { return }
        nsView.load(URLRequest(url: url))
    }
}

private struct RightSidebarCommandPanelView: View {
    let command: String
    let cwd: String?
    let refresh: RightSidebarCommandRefresh

    @State private var output: String = ""
    @State private var exitCode: Int32?
    @State private var isRunning = false
    @State private var hasAutoRun = false

    var body: some View {
        VStack(spacing: 0) {
            commandToolbar
            Divider()
            ScrollView {
                Text(displayOutput)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
        }
        .onAppear {
            guard refresh == .onAppear, !hasAutoRun else { return }
            hasAutoRun = true
            run()
        }
    }

    private var commandToolbar: some View {
        HStack(spacing: 8) {
            Image(systemName: "terminal")
                .foregroundStyle(.secondary)
            Text(command)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            if isRunning {
                ProgressView()
                    .scaleEffect(0.55)
                    .frame(width: 14, height: 14)
                    .accessibilityLabel(String(localized: "rightSidebar.command.running", defaultValue: "Running"))
            }
            Button(action: run) {
                Image(systemName: "play.fill")
            }
            .buttonStyle(.plain)
            .disabled(isRunning)
            .help(String(localized: "dialog.cmuxConfig.confirmCommand.run", defaultValue: "Run"))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(height: 31)
    }

    private var displayOutput: String {
        if isRunning && output.isEmpty {
            return String(localized: "rightSidebar.command.running", defaultValue: "Running")
        }
        if output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return String(localized: "rightSidebar.command.noOutput", defaultValue: "No output")
        }
        if let exitCode, exitCode != 0 {
            let format = String(localized: "rightSidebar.command.exitCode", defaultValue: "Exit code %d")
            return output + "\n\n" + String(format: format, exitCode)
        }
        return output
    }

    private func run() {
        guard !isRunning else { return }
        isRunning = true
        output = ""
        exitCode = nil

        let command = command
        let cwd = cwd
        Task {
            let result = await RightSidebarCommandRunner.run(command: command, cwd: cwd)
            output = result.output
            exitCode = result.exitCode
            isRunning = false
        }
    }
}

private enum RightSidebarCommandRunner {
    struct Result: Sendable {
        var output: String
        var exitCode: Int32
    }

    static func run(command: String, cwd: String?) async -> Result {
        await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-lc", command]
            if let cwd = cwd?.trimmedNonEmpty {
                process.currentDirectoryURL = URL(fileURLWithPath: (cwd as NSString).expandingTildeInPath)
            }

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            do {
                try process.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                let text = String(data: data, encoding: .utf8) ?? ""
                return Result(output: text, exitCode: process.terminationStatus)
            } catch {
                return Result(output: String(describing: error), exitCode: 1)
            }
        }.value
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
