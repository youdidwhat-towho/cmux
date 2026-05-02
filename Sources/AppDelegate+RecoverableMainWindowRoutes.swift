import AppKit
import ObjectiveC.runtime

@MainActor
final class RecoverableMainWindowRoute {
    let windowId: UUID
    weak var tabManager: TabManager?
    weak var window: NSWindow?

    init(windowId: UUID, tabManager: TabManager, window: NSWindow?) {
        self.windowId = windowId
        self.tabManager = tabManager
        self.window = window
    }
}

@MainActor
private final class RecoverableMainWindowRouteStore {
    var routesByWindowId: [UUID: RecoverableMainWindowRoute] = [:]
}

private var recoverableMainWindowRouteStoreKey: UInt8 = 0

extension AppDelegate {
    private var recoverableMainWindowRouteStore: RecoverableMainWindowRouteStore {
        if let store = objc_getAssociatedObject(self, &recoverableMainWindowRouteStoreKey) as? RecoverableMainWindowRouteStore {
            return store
        }
        let store = RecoverableMainWindowRouteStore()
        objc_setAssociatedObject(self, &recoverableMainWindowRouteStoreKey, store, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return store
    }

    private func tabManagerHasRegisteredTerminalSurface(_ manager: TabManager) -> Bool {
        for workspace in manager.tabs {
            for panel in workspace.panels.values {
                guard let terminalPanel = panel as? TerminalPanel else { continue }
                if TerminalSurfaceRegistry.shared.surface(id: terminalPanel.id) === terminalPanel.surface {
                    return true
                }
            }
        }
        return false
    }

    private func liveRecoverableMainWindow(windowId: UUID, cachedWindow: NSWindow?) -> NSWindow? {
        cachedWindow ?? windowForMainWindowId(windowId)
    }

    private func pruneRecoverableMainWindowRoutes() {
        recoverableMainWindowRouteStore.routesByWindowId = recoverableMainWindowRouteStore.routesByWindowId.filter { _, route in
            guard let manager = route.tabManager else { return false }
            guard let window = liveRecoverableMainWindow(windowId: route.windowId, cachedWindow: route.window) else { return false }
            route.window = window
            return tabManagerHasRegisteredTerminalSurface(manager)
        }
    }

    func forgetRecoverableMainWindowRoute(windowId: UUID) {
        recoverableMainWindowRouteStore.routesByWindowId.removeValue(forKey: windowId)
    }

    func rememberRecoverableMainWindowRoute(windowId: UUID, tabManager: TabManager, window: NSWindow?) {
        guard let window = liveRecoverableMainWindow(windowId: windowId, cachedWindow: window) else { return }
        guard tabManagerHasRegisteredTerminalSurface(tabManager) else { return }
        recoverableMainWindowRouteStore.routesByWindowId[windowId] = RecoverableMainWindowRoute(
            windowId: windowId,
            tabManager: tabManager,
            window: window
        )
    }

    func recoverableMainWindowRoute(windowId: UUID) -> RecoverableMainWindowRoute? {
        pruneRecoverableMainWindowRoutes()
        return recoverableMainWindowRouteStore.routesByWindowId[windowId]
    }

    func recoverableMainWindowRoutes() -> [RecoverableMainWindowRoute] {
        pruneRecoverableMainWindowRoutes()
        return recoverableMainWindowRouteStore.routesByWindowId.values.sorted {
            $0.windowId.uuidString < $1.windowId.uuidString
        }
    }

    func listMainWindowSummaries() -> [MainWindowSummary] {
        var seen: Set<UUID> = []
        var summaries = mainWindowContexts.values.map { ctx in
            seen.insert(ctx.windowId)
            let window = ctx.window ?? windowForMainWindowId(ctx.windowId)
            return MainWindowSummary(
                windowId: ctx.windowId,
                isKeyWindow: window?.isKeyWindow ?? false,
                isVisible: window?.isVisible ?? false,
                workspaceCount: ctx.tabManager.tabs.count,
                selectedWorkspaceId: ctx.tabManager.selectedTabId
            )
        }
        for route in recoverableMainWindowRoutes() {
            guard seen.insert(route.windowId).inserted,
                  let manager = route.tabManager else { continue }
            let window = route.window ?? windowForMainWindowId(route.windowId)
            summaries.append(
                MainWindowSummary(
                    windowId: route.windowId,
                    isKeyWindow: window?.isKeyWindow ?? false,
                    isVisible: window?.isVisible ?? false,
                    workspaceCount: manager.tabs.count,
                    selectedWorkspaceId: manager.selectedTabId
                )
            )
        }
        return summaries
    }

    func tabManagerFor(windowId: UUID) -> TabManager? {
        if let manager = tabManagerForLiveRegisteredMainWindow(windowId: windowId) {
            return manager
        }
        return recoverableMainWindowRoute(windowId: windowId)?.tabManager
    }

    func windowId(for tabManager: TabManager) -> UUID? {
        if let windowId = mainWindowContexts.values.first(where: { $0.tabManager === tabManager })?.windowId {
            return windowId
        }
        return recoverableMainWindowRoutes().first(where: { $0.tabManager === tabManager })?.windowId
    }

    func mainWindowContainingWorkspace(_ workspaceId: UUID) -> NSWindow? {
        for context in mainWindowContexts.values where context.tabManager.tabs.contains(where: { $0.id == workspaceId }) {
            if let window = context.window ?? windowForMainWindowId(context.windowId) {
                return window
            }
        }
        for route in recoverableMainWindowRoutes() {
            guard let manager = route.tabManager,
                  manager.tabs.contains(where: { $0.id == workspaceId }) else {
                continue
            }
            if let window = route.window ?? windowForMainWindowId(route.windowId) {
                return window
            }
        }
        return nil
    }

    private func scriptableMainWindow(for window: NSWindow) -> ScriptableMainWindowState? {
        if let context = contextForMainTerminalWindow(window, reindex: false) {
            return ScriptableMainWindowState(
                windowId: context.windowId,
                tabManager: context.tabManager,
                window: context.window ?? windowForMainWindowId(context.windowId)
            )
        }

        if let windowId = mainWindowId(from: window),
           let route = recoverableMainWindowRoute(windowId: windowId),
           let manager = route.tabManager {
            return ScriptableMainWindowState(
                windowId: route.windowId,
                tabManager: manager,
                window: route.window ?? windowForMainWindowId(route.windowId)
            )
        }

        let windowNumber = window.windowNumber
        guard windowNumber >= 0 else { return nil }
        for route in recoverableMainWindowRoutes() {
            guard let manager = route.tabManager,
                  let routeWindow = route.window ?? windowForMainWindowId(route.windowId),
                  routeWindow === window || routeWindow.windowNumber == windowNumber else {
                continue
            }
            return ScriptableMainWindowState(
                windowId: route.windowId,
                tabManager: manager,
                window: routeWindow
            )
        }
        return nil
    }

    func currentScriptableMainWindow() -> ScriptableMainWindowState? {
        var seenWindows = Set<ObjectIdentifier>()

        func resolve(_ window: NSWindow?) -> ScriptableMainWindowState? {
            guard let window else { return nil }
            guard seenWindows.insert(ObjectIdentifier(window)).inserted else { return nil }
            return scriptableMainWindow(for: window)
        }

        if let state = resolve(NSApp.keyWindow) {
            return state
        }
        if let state = resolve(NSApp.mainWindow) {
            return state
        }
        for window in NSApp.orderedWindows {
            if let state = resolve(window) {
                return state
            }
        }
        return scriptableMainWindows().first
    }

    func scriptableMainWindows() -> [ScriptableMainWindowState] {
        var results: [ScriptableMainWindowState] = []
        var seen: Set<UUID> = []

        for window in NSApp.orderedWindows {
            guard let state = scriptableMainWindow(for: window) else { continue }
            guard seen.insert(state.windowId).inserted else { continue }
            results.append(state)
        }

        let remaining = mainWindowContexts.values
            .sorted { $0.windowId.uuidString < $1.windowId.uuidString }
            .filter { seen.insert($0.windowId).inserted }

        for context in remaining {
            results.append(
                ScriptableMainWindowState(
                    windowId: context.windowId,
                    tabManager: context.tabManager,
                    window: context.window ?? windowForMainWindowId(context.windowId)
                )
            )
        }

        for route in recoverableMainWindowRoutes() where seen.insert(route.windowId).inserted {
            guard let manager = route.tabManager else { continue }
            results.append(
                ScriptableMainWindowState(
                    windowId: route.windowId,
                    tabManager: manager,
                    window: route.window ?? windowForMainWindowId(route.windowId)
                )
            )
        }

        return results
    }

    func scriptableMainWindow(windowId: UUID) -> ScriptableMainWindowState? {
        if let context = mainWindowContexts.values.first(where: { $0.windowId == windowId }) {
            return ScriptableMainWindowState(
                windowId: context.windowId,
                tabManager: context.tabManager,
                window: context.window ?? windowForMainWindowId(context.windowId)
            )
        }
        guard let route = recoverableMainWindowRoute(windowId: windowId),
              let manager = route.tabManager else { return nil }
        return ScriptableMainWindowState(
            windowId: route.windowId,
            tabManager: manager,
            window: route.window ?? windowForMainWindowId(route.windowId)
        )
    }

    func scriptableMainWindowForTab(_ tabId: UUID) -> ScriptableMainWindowState? {
        if let context = contextContainingTabId(tabId) {
            return ScriptableMainWindowState(
                windowId: context.windowId,
                tabManager: context.tabManager,
                window: context.window ?? windowForMainWindowId(context.windowId)
            )
        }
        for route in recoverableMainWindowRoutes() {
            guard let manager = route.tabManager,
                  manager.tabs.contains(where: { $0.id == tabId }) else {
                continue
            }
            return ScriptableMainWindowState(
                windowId: route.windowId,
                tabManager: manager,
                window: route.window ?? windowForMainWindowId(route.windowId)
            )
        }
        return nil
    }

    func contextContainingTabId(_ tabId: UUID) -> MainWindowContext? {
        for context in mainWindowContexts.values {
            if context.tabManager.tabs.contains(where: { $0.id == tabId }) {
                return context
            }
        }
        return nil
    }

    /// Returns the `TabManager` that owns `tabId`, if any.
    func tabManagerFor(tabId: UUID) -> TabManager? {
        if let manager = contextContainingTabId(tabId)?.tabManager {
            return manager
        }
        return recoverableMainWindowRoutes()
            .compactMap(\.tabManager)
            .first { manager in
                manager.tabs.contains(where: { $0.id == tabId })
            }
    }
}
