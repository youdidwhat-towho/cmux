import AppKit
import Bonsplit
import Combine
import SwiftUI

// MARK: - Right Panel Container

/// Right-side panel that wraps the file explorer with a vertical divider and resize handle.
struct FileExplorerRightPanel: View {
    @ObservedObject var store: FileExplorerStore
    @ObservedObject var state: FileExplorerState

    @State private var isResizerHovered = false
    @State private var isResizerDragging = false
    @State private var dragStartWidth: CGFloat = 0

    private let minWidth: CGFloat = 150
    private let maxWidth: CGFloat = 500
    private let resizerWidth: CGFloat = 6

    var body: some View {
        HStack(spacing: 0) {
            // Vertical divider + resize handle
            Rectangle()
                .fill(isResizerDragging || isResizerHovered
                    ? Color.accentColor.opacity(0.5)
                    : Color(nsColor: .separatorColor))
                .frame(width: isResizerDragging || isResizerHovered ? 2 : 1)
                .padding(.horizontal, (resizerWidth - 1) / 2)
                .contentShape(Rectangle())
                .onHover { hovering in
                    isResizerHovered = hovering
                    if hovering {
                        NSCursor.resizeLeftRight.push()
                    } else if !isResizerDragging {
                        NSCursor.pop()
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { value in
                            if !isResizerDragging {
                                dragStartWidth = state.width
                                isResizerDragging = true
                            }
                            // Dragging left = wider panel, dragging right = narrower
                            let newWidth = dragStartWidth - value.translation.width
                            state.width = min(maxWidth, max(minWidth, newWidth))
                        }
                        .onEnded { _ in
                            isResizerDragging = false
                            if !isResizerHovered {
                                NSCursor.pop()
                            }
                        }
                )
                .accessibilityIdentifier("FileExplorerResizer")

            FileExplorerView(store: store, state: state)
                .frame(width: state.width)
        }
    }
}

// MARK: - Container View

struct FileExplorerView: View {
    @ObservedObject var store: FileExplorerStore
    @ObservedObject var state: FileExplorerState

    var body: some View {
        VStack(spacing: 0) {
            if store.rootPath.isEmpty {
                emptyState
            } else {
                fileTree
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "folder")
                .font(.system(size: 28))
                .foregroundColor(.secondary)
            Text(String(localized: "fileExplorer.empty", defaultValue: "No folder open"))
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var fileTree: some View {
        VStack(alignment: .leading, spacing: 0) {
            rootPathHeader
            if store.isRootLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                FileExplorerOutlineView(store: store)
            }
        }
    }

    private var rootPathHeader: some View {
        HStack(spacing: 4) {
            Image(systemName: "folder.fill")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Text(store.displayRootPath)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()

            Button {
                state.showHiddenFiles.toggle()
                store.showHiddenFiles = state.showHiddenFiles
                store.reload()
            } label: {
                Image(systemName: state.showHiddenFiles ? "eye" : "eye.slash")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help(state.showHiddenFiles
                ? String(localized: "fileExplorer.hiddenFiles.hide", defaultValue: "Hide Hidden Files")
                : String(localized: "fileExplorer.hiddenFiles.show", defaultValue: "Show Hidden Files"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

// MARK: - NSOutlineView Wrapper

struct FileExplorerOutlineView: NSViewRepresentable {
    @ObservedObject var store: FileExplorerStore

    func makeCoordinator() -> Coordinator {
        Coordinator(store: store)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let outlineView = NSOutlineView()
        outlineView.headerView = nil
        outlineView.usesAlternatingRowBackgroundColors = false
        outlineView.style = .plain
        outlineView.selectionHighlightStyle = .regular
        outlineView.rowSizeStyle = .default
        outlineView.indentationPerLevel = 16
        outlineView.autoresizesOutlineColumn = true
        outlineView.floatsGroupRows = false
        outlineView.backgroundColor = .clear

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        column.isEditable = false
        column.resizingMask = .autoresizingMask
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column

        outlineView.dataSource = context.coordinator
        outlineView.delegate = context.coordinator

        // Context menu
        let menu = NSMenu()
        menu.delegate = context.coordinator
        outlineView.menu = menu

        scrollView.documentView = outlineView
        context.coordinator.outlineView = outlineView

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.store = store
        context.coordinator.reloadIfNeeded()
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate {
        var store: FileExplorerStore
        weak var outlineView: NSOutlineView?
        private var lastRootNodeCount: Int = -1
        private var observationCancellable: AnyCancellable?

        init(store: FileExplorerStore) {
            self.store = store
            super.init()
            observeStore()
        }

        private func observeStore() {
            observationCancellable = store.objectWillChange
                .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
                .sink { [weak self] _ in
                    self?.reloadIfNeeded()
                }
        }

        func reloadIfNeeded() {
            guard let outlineView else { return }
            let newCount = store.rootNodes.count
            if newCount != lastRootNodeCount {
                lastRootNodeCount = newCount
                let expandedPaths = store.expandedPaths
                outlineView.reloadData()
                restoreExpansionState(expandedPaths, in: outlineView)
            } else {
                refreshLoadedNodes(in: outlineView)
            }
        }

        private func restoreExpansionState(_ expandedPaths: Set<String>, in outlineView: NSOutlineView) {
            for row in 0..<outlineView.numberOfRows {
                guard let node = outlineView.item(atRow: row) as? FileExplorerNode else { continue }
                if expandedPaths.contains(node.path) && outlineView.isExpandable(node) {
                    outlineView.expandItem(node)
                }
            }
        }

        private func refreshLoadedNodes(in outlineView: NSOutlineView) {
            for row in 0..<outlineView.numberOfRows {
                guard let node = outlineView.item(atRow: row) as? FileExplorerNode else { continue }
                if node.isDirectory {
                    let isCurrentlyExpanded = outlineView.isItemExpanded(node)
                    let shouldBeExpanded = store.expandedPaths.contains(node.path)

                    if shouldBeExpanded && !isCurrentlyExpanded && node.children != nil {
                        outlineView.reloadItem(node, reloadChildren: true)
                        outlineView.expandItem(node)
                    } else if !shouldBeExpanded && isCurrentlyExpanded {
                        outlineView.collapseItem(node)
                    } else if node.children != nil {
                        outlineView.reloadItem(node, reloadChildren: true)
                        if shouldBeExpanded {
                            outlineView.expandItem(node)
                        }
                    }
                }
            }
        }

        // MARK: - NSOutlineViewDataSource

        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            if item == nil {
                return store.rootNodes.count
            }
            guard let node = item as? FileExplorerNode else { return 0 }
            return node.sortedChildren?.count ?? 0
        }

        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            if item == nil {
                return store.rootNodes[index]
            }
            guard let node = item as? FileExplorerNode,
                  let children = node.sortedChildren else {
                return FileExplorerNode(name: "", path: "", isDirectory: false)
            }
            return children[index]
        }

        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            guard let node = item as? FileExplorerNode else { return false }
            return node.isExpandable
        }

        // MARK: - NSOutlineViewDelegate

        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            guard let node = item as? FileExplorerNode else { return nil }

            let identifier = NSUserInterfaceItemIdentifier("FileExplorerCell")
            let cellView: FileExplorerCellView
            if let existing = outlineView.makeView(withIdentifier: identifier, owner: nil) as? FileExplorerCellView {
                cellView = existing
            } else {
                cellView = FileExplorerCellView(identifier: identifier)
            }

            let gitStatus = store.gitStatusByPath[node.path]
            cellView.configure(with: node, gitStatus: gitStatus)
            cellView.onHover = { [weak self] isHovering in
                guard let self else { return }
                if isHovering {
                    Task { @MainActor in
                        self.store.prefetchChildren(for: node)
                    }
                } else {
                    Task { @MainActor in
                        self.store.cancelPrefetch(for: node)
                    }
                }
            }

            return cellView
        }

        func outlineView(_ outlineView: NSOutlineView, shouldExpandItem item: Any) -> Bool {
            guard let node = item as? FileExplorerNode, node.isDirectory else { return false }
            Task { @MainActor in
                store.expand(node: node)
            }
            return node.children != nil
        }

        func outlineView(_ outlineView: NSOutlineView, shouldCollapseItem item: Any) -> Bool {
            guard let node = item as? FileExplorerNode else { return false }
            Task { @MainActor in
                store.collapse(node: node)
            }
            return true
        }

        func outlineViewItemDidExpand(_ notification: Notification) {
            guard let node = notification.userInfo?["NSObject"] as? FileExplorerNode else { return }
            Task { @MainActor in
                if !store.isExpanded(node) {
                    store.expand(node: node)
                }
            }
        }

        func outlineViewItemDidCollapse(_ notification: Notification) {
            guard let node = notification.userInfo?["NSObject"] as? FileExplorerNode else { return }
            Task { @MainActor in
                if store.isExpanded(node) {
                    store.collapse(node: node)
                }
            }
        }

        func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
            FileExplorerRowView()
        }

        func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
            22
        }

        // MARK: - Drag-to-Terminal

        func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> (any NSPasteboardWriting)? {
            guard let node = item as? FileExplorerNode, !node.isDirectory else { return nil }
            // Only allow drag for local files
            guard store.provider is LocalFileExplorerProvider else { return nil }
            return NSURL(fileURLWithPath: node.path)
        }

        // MARK: - Context Menu (NSMenuDelegate)

        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            guard let outlineView else { return }
            let clickedRow = outlineView.clickedRow
            guard clickedRow >= 0,
                  let node = outlineView.item(atRow: clickedRow) as? FileExplorerNode else { return }

            let isLocal = store.provider is LocalFileExplorerProvider

            if !node.isDirectory && isLocal {
                let openItem = NSMenuItem(
                    title: String(localized: "fileExplorer.contextMenu.openDefault", defaultValue: "Open in Default Editor"),
                    action: #selector(contextMenuOpenInDefaultEditor(_:)),
                    keyEquivalent: ""
                )
                openItem.target = self
                openItem.representedObject = node
                menu.addItem(openItem)
            }

            if isLocal {
                let revealItem = NSMenuItem(
                    title: String(localized: "fileExplorer.contextMenu.revealInFinder", defaultValue: "Reveal in Finder"),
                    action: #selector(contextMenuRevealInFinder(_:)),
                    keyEquivalent: ""
                )
                revealItem.target = self
                revealItem.representedObject = node
                menu.addItem(revealItem)

                menu.addItem(.separator())
            }

            let copyPathItem = NSMenuItem(
                title: String(localized: "fileExplorer.contextMenu.copyPath", defaultValue: "Copy Path"),
                action: #selector(contextMenuCopyPath(_:)),
                keyEquivalent: ""
            )
            copyPathItem.target = self
            copyPathItem.representedObject = node
            menu.addItem(copyPathItem)

            let copyRelItem = NSMenuItem(
                title: String(localized: "fileExplorer.contextMenu.copyRelativePath", defaultValue: "Copy Relative Path"),
                action: #selector(contextMenuCopyRelativePath(_:)),
                keyEquivalent: ""
            )
            copyRelItem.target = self
            copyRelItem.representedObject = node
            menu.addItem(copyRelItem)
        }

        @objc private func contextMenuOpenInDefaultEditor(_ sender: NSMenuItem) {
            guard let node = sender.representedObject as? FileExplorerNode else { return }
            NSWorkspace.shared.open(URL(fileURLWithPath: node.path))
        }

        @objc private func contextMenuRevealInFinder(_ sender: NSMenuItem) {
            guard let node = sender.representedObject as? FileExplorerNode else { return }
            NSWorkspace.shared.selectFile(node.path, inFileViewerRootedAtPath: "")
        }

        @objc private func contextMenuCopyPath(_ sender: NSMenuItem) {
            guard let node = sender.representedObject as? FileExplorerNode else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(node.path, forType: .string)
        }

        @objc private func contextMenuCopyRelativePath(_ sender: NSMenuItem) {
            guard let node = sender.representedObject as? FileExplorerNode else { return }
            let rootPath = store.rootPath
            var relativePath = node.path
            if relativePath.hasPrefix(rootPath) {
                relativePath = String(relativePath.dropFirst(rootPath.count))
                if relativePath.hasPrefix("/") {
                    relativePath = String(relativePath.dropFirst())
                }
            }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(relativePath, forType: .string)
        }
    }
}

// MARK: - Cell View

final class FileExplorerCellView: NSTableCellView {
    private let iconView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let loadingIndicator = NSProgressIndicator()
    private var trackingArea: NSTrackingArea?
    var onHover: ((Bool) -> Void)?

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyDown

        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.font = .systemFont(ofSize: 13, weight: .medium)
        nameLabel.textColor = .labelColor
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.maximumNumberOfLines = 1

        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        loadingIndicator.style = .spinning
        loadingIndicator.controlSize = .small
        loadingIndicator.isHidden = true

        addSubview(iconView)
        addSubview(nameLabel)
        addSubview(loadingIndicator)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),

            nameLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 4),
            nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: loadingIndicator.leadingAnchor, constant: -4),

            loadingIndicator.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            loadingIndicator.centerYAnchor.constraint(equalTo: centerYAnchor),
            loadingIndicator.widthAnchor.constraint(equalToConstant: 12),
            loadingIndicator.heightAnchor.constraint(equalToConstant: 12),
        ])
    }

    func configure(with node: FileExplorerNode, gitStatus: GitFileStatus? = nil) {
        nameLabel.stringValue = node.name

        if node.isDirectory {
            let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
            iconView.image = NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(config)
            iconView.contentTintColor = .systemBlue
        } else {
            let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
            iconView.image = NSImage(systemSymbolName: "doc", accessibilityDescription: nil)?
                .withSymbolConfiguration(config)
            iconView.contentTintColor = .secondaryLabelColor
        }

        if node.isLoading {
            loadingIndicator.isHidden = false
            loadingIndicator.startAnimation(nil)
        } else {
            loadingIndicator.isHidden = true
            loadingIndicator.stopAnimation(nil)
        }

        if let error = node.error {
            nameLabel.textColor = .systemRed
            nameLabel.toolTip = error
        } else if let gitStatus {
            nameLabel.textColor = Self.colorForGitStatus(gitStatus)
            nameLabel.toolTip = node.path
        } else {
            nameLabel.textColor = .labelColor
            nameLabel.toolTip = node.path
        }
    }

    private static func colorForGitStatus(_ status: GitFileStatus) -> NSColor {
        switch status {
        case .modified: return NSColor(red: 0.65, green: 0.45, blue: 0.0, alpha: 1.0)
        case .added: return .systemGreen
        case .deleted: return .systemRed
        case .renamed: return .systemCyan
        case .untracked: return NSColor(white: 0.5, alpha: 1.0)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        onHover?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHover?(false)
    }
}

// MARK: - Row View (Finder-like rounded inset)

final class FileExplorerRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        guard isSelected else { return }
        let insetRect = bounds.insetBy(dx: 4, dy: 1)
        let path = NSBezierPath(roundedRect: insetRect, xRadius: 4, yRadius: 4)
        NSColor.controlAccentColor.withAlphaComponent(0.2).setFill()
        path.fill()
    }

    override var interiorBackgroundStyle: NSView.BackgroundStyle {
        isSelected ? .emphasized : .normal
    }
}

// MARK: - Right Titlebar Toggle Button

struct FileExplorerTitlebarButton: View {
    let onToggle: () -> Void
    let config: TitlebarControlsStyleConfig
    @State private var isHovering = false

    var body: some View {
        TitlebarControlButton(config: config, action: {
            #if DEBUG
            dlog("titlebar.toggleFileExplorer")
            #endif
            onToggle()
        }) {
            Image(systemName: "sidebar.right")
                .font(.system(size: config.iconSize))
                .frame(width: config.buttonSize, height: config.buttonSize)
        }
        .accessibilityIdentifier("titlebarControl.toggleFileExplorer")
        .accessibilityLabel(String(localized: "titlebar.fileExplorer.accessibilityLabel", defaultValue: "Toggle File Explorer"))
        .safeHelp(KeyboardShortcutSettings.Action.toggleFileExplorer.tooltip(
            String(localized: "titlebar.fileExplorer.tooltip", defaultValue: "Show or hide the file explorer")
        ))
    }
}

// MARK: - Right Titlebar Accessory ViewController

final class FileExplorerTitlebarAccessoryViewController: NSTitlebarAccessoryViewController {
    private let hostingView: NonDraggableHostingView<FileExplorerTitlebarButton>

    init(onToggle: @escaping () -> Void) {
        let style = TitlebarControlsStyle(rawValue: UserDefaults.standard.integer(forKey: "titlebarControlsStyle")) ?? .classic
        let config = style.config
        hostingView = NonDraggableHostingView(
            rootView: FileExplorerTitlebarButton(
                onToggle: onToggle,
                config: config
            )
        )

        super.init(nibName: nil, bundle: nil)

        // Use fixed dimensions matching the button config to avoid layout feedback loops.
        let buttonSize = config.buttonSize
        let width = buttonSize + 12
        let height = buttonSize

        hostingView.translatesAutoresizingMaskIntoConstraints = false
        let wrapper = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        wrapper.translatesAutoresizingMaskIntoConstraints = true
        wrapper.wantsLayer = true
        wrapper.layer?.masksToBounds = false
        wrapper.addSubview(hostingView)

        NSLayoutConstraint.activate([
            hostingView.centerXAnchor.constraint(equalTo: wrapper.centerXAnchor),
            hostingView.centerYAnchor.constraint(equalTo: wrapper.centerYAnchor),
        ])

        view = wrapper
        preferredContentSize = NSSize(width: width, height: height)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - Sidebar Explorer Divider

/// Draggable horizontal divider between the tab list and file explorer in the sidebar.
struct SidebarExplorerDivider: View {
    @Binding var position: CGFloat
    let totalHeight: CGFloat
    var minFraction: CGFloat = 0.1
    var maxFraction: CGFloat = 0.8

    @State private var isDragging = false
    @State private var isHovered = false
    @State private var dragStartPosition: CGFloat = 0

    private let handleHeight: CGFloat = 6

    var body: some View {
        Rectangle()
            .fill(isDragging || isHovered
                ? Color.accentColor.opacity(0.5)
                : Color(nsColor: .separatorColor))
            .frame(height: isDragging || isHovered ? 2 : 1)
            .frame(maxWidth: .infinity)
            .padding(.vertical, (handleHeight - 1) / 2)
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovered = hovering
                if hovering {
                    NSCursor.resizeUpDown.push()
                } else if !isDragging {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if !isDragging {
                            dragStartPosition = position
                            isDragging = true
                        }
                        let newPosition = dragStartPosition + (value.translation.height / totalHeight)
                        position = min(maxFraction, max(minFraction, newPosition))
                    }
                    .onEnded { _ in
                        isDragging = false
                        if !isHovered {
                            NSCursor.pop()
                        }
                    }
            )
            .accessibilityIdentifier("SidebarExplorerDivider")
    }
}
