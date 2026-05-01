import AppKit
import Foundation

@MainActor
final class MainWindowVisibilityController {
    enum Reason: String {
        case createMainWindow
        case ensureInitialWindow
        case feedback
        case fileSearchFocus
        case findShortcut
        case focusMainWindow
        case globalHotkey
        case menuBar
        case notification
        case rightSidebarFocus
        case rightSidebarToggle
        case socketActivate
        case workspaceCreation
    }

    enum Activation {
        case none
        case appIgnoringOtherApps(Bool)
        case runningApplication(NSApplication.ActivationOptions)
    }

    enum ActivationTiming {
        case beforeWindowOrdering
        case afterWindowOrdering
    }

    @MainActor
    struct WindowOperations {
        var isVisible: @MainActor (NSWindow) -> Bool
        var isMiniaturized: @MainActor (NSWindow) -> Bool
        var isKeyWindow: @MainActor (NSWindow) -> Bool
        var canBecomeMain: @MainActor (NSWindow) -> Bool
        var canBecomeKey: @MainActor (NSWindow) -> Bool
        var deminiaturize: @MainActor (NSWindow) -> Void
        var makeKeyAndOrderFront: @MainActor (NSWindow) -> Void
        var orderFront: @MainActor (NSWindow) -> Void
        var orderFrontRegardless: @MainActor (NSWindow) -> Void

        static let live = WindowOperations(
            isVisible: { $0.isVisible },
            isMiniaturized: { $0.isMiniaturized },
            isKeyWindow: { $0.isKeyWindow },
            canBecomeMain: { $0.canBecomeMain },
            canBecomeKey: { $0.canBecomeKey },
            deminiaturize: { $0.deminiaturize(nil) },
            makeKeyAndOrderFront: { $0.makeKeyAndOrderFront(nil) },
            orderFront: { $0.orderFront(nil) },
            orderFrontRegardless: { $0.orderFrontRegardless() }
        )
    }

    @MainActor
    struct Dependencies {
        var isActivationSuppressed: @MainActor () -> Bool
        var setActiveMainWindow: @MainActor (NSWindow) -> Void
        var isApplicationActive: @MainActor () -> Bool
        var isApplicationHidden: @MainActor () -> Bool
        var keyWindow: @MainActor () -> NSWindow?
        var mainWindow: @MainActor () -> NSWindow?
        var hideApplication: @MainActor () -> Void
        var unhideApplication: @MainActor () -> Void
        var activateApplicationIgnoringOtherApps: @MainActor (Bool) -> Void
        var activateRunningApplication: @MainActor (NSApplication.ActivationOptions) -> Void
        var windowOperations: WindowOperations

        init(
            isActivationSuppressed: @escaping @MainActor () -> Bool,
            setActiveMainWindow: @escaping @MainActor (NSWindow) -> Void,
            isApplicationActive: @escaping @MainActor () -> Bool = { NSApp.isActive },
            isApplicationHidden: @escaping @MainActor () -> Bool = { NSApp.isHidden },
            keyWindow: @escaping @MainActor () -> NSWindow? = { NSApp.keyWindow },
            mainWindow: @escaping @MainActor () -> NSWindow? = { NSApp.mainWindow },
            hideApplication: @escaping @MainActor () -> Void = { NSApp.hide(nil) },
            unhideApplication: @escaping @MainActor () -> Void = { NSApp.unhide(nil) },
            activateApplicationIgnoringOtherApps: @escaping @MainActor (Bool) -> Void = {
                NSApp.activate(ignoringOtherApps: $0)
            },
            activateRunningApplication: @escaping @MainActor (NSApplication.ActivationOptions) -> Void = {
                NSRunningApplication.current.activate(options: $0)
            },
            windowOperations: WindowOperations? = nil
        ) {
            self.isActivationSuppressed = isActivationSuppressed
            self.setActiveMainWindow = setActiveMainWindow
            self.isApplicationActive = isApplicationActive
            self.isApplicationHidden = isApplicationHidden
            self.keyWindow = keyWindow
            self.mainWindow = mainWindow
            self.hideApplication = hideApplication
            self.unhideApplication = unhideApplication
            self.activateApplicationIgnoringOtherApps = activateApplicationIgnoringOtherApps
            self.activateRunningApplication = activateRunningApplication
            self.windowOperations = windowOperations ?? WindowOperations.live
        }
    }

    private var dependencies: Dependencies
    private var hiddenWindowRestoreTargets: [NSWindow] = []

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    @discardableResult
    func focus(
        _ window: NSWindow,
        reason: Reason,
        activation: Activation = .runningApplication([.activateAllWindows, .activateIgnoringOtherApps]),
        activationTiming: ActivationTiming = .afterWindowOrdering,
        makeKey: Bool = true,
        deminiaturize: Bool = true,
        unhide: Bool = true,
        respectActivationSuppression: Bool = true
    ) -> Bool {
        if respectActivationSuppression, dependencies.isActivationSuppressed() {
            dependencies.setActiveMainWindow(window)
            log("focus.suppressed", reason: reason, windows: [window])
            return true
        }

        dependencies.setActiveMainWindow(window)
        if unhide, dependencies.isApplicationHidden() {
            dependencies.unhideApplication()
        }
        if activationTiming == .beforeWindowOrdering {
            activate(activation)
        }
        if deminiaturize, dependencies.windowOperations.isMiniaturized(window) {
            dependencies.windowOperations.deminiaturize(window)
        }
        if makeKey {
            dependencies.windowOperations.makeKeyAndOrderFront(window)
        } else {
            dependencies.windowOperations.orderFront(window)
        }
        if activationTiming == .afterWindowOrdering {
            activate(activation)
        }
        log("focus", reason: reason, windows: [window])
        return true
    }

    func focusForInWindowCommand(_ window: NSWindow, reason: Reason) {
        dependencies.setActiveMainWindow(window)
        guard !dependencies.windowOperations.isKeyWindow(window) else {
            log("focus.inWindow.key", reason: reason, windows: [window])
            return
        }
        if dependencies.isApplicationHidden() {
            dependencies.unhideApplication()
        }
        if !dependencies.isApplicationActive() {
            activate(.runningApplication([.activateAllWindows]))
        }
        if dependencies.windowOperations.isMiniaturized(window) {
            dependencies.windowOperations.deminiaturize(window)
        }
        dependencies.windowOperations.makeKeyAndOrderFront(window)
        log("focus.inWindow", reason: reason, windows: [window])
    }

    func captureHiddenWindowRestoreTargets(windows: [NSWindow]) {
        hiddenWindowRestoreTargets = uniqueWindows(windows).filter { window in
            dependencies.windowOperations.isVisible(window) || dependencies.windowOperations.isMiniaturized(window)
        }
        log("hide.capture", reason: .globalHotkey, windows: hiddenWindowRestoreTargets)
    }

    func toggleApplicationVisibility(windows: [NSWindow], reason: Reason = .globalHotkey) {
        let windows = uniqueWindows(windows)
        let isFrontmost = dependencies.isApplicationActive() && !dependencies.isApplicationHidden()
        let hasVisibleWindow = windows.contains { window in
            dependencies.windowOperations.isVisible(window) && !dependencies.windowOperations.isMiniaturized(window)
        }

        if isFrontmost && hasVisibleWindow {
            captureHiddenWindowRestoreTargets(windows: windows)
            dependencies.hideApplication()
            log("toggle.hide", reason: reason, windows: windows)
            return
        }

        _ = showApplicationWindows(windows: windows, reason: reason)
    }

    @discardableResult
    func showApplicationWindows(windows allWindows: [NSWindow], reason: Reason = .globalHotkey) -> NSWindow? {
        let allWindows = uniqueWindows(allWindows)
        let revealTargets: [NSWindow]

        if dependencies.isApplicationHidden() {
            dependencies.unhideApplication()
            let capturedTargets = hiddenWindowRestoreTargets.filter { capturedWindow in
                allWindows.contains { $0 === capturedWindow }
            }
            hiddenWindowRestoreTargets.removeAll()
            revealTargets = capturedTargets.isEmpty
                ? allWindows.filter { dependencies.windowOperations.isMiniaturized($0) }
                : capturedTargets
        } else {
            revealTargets = allWindows.filter { window in
                dependencies.windowOperations.isVisible(window) || dependencies.windowOperations.isMiniaturized(window)
            }
        }

        return reveal(
            revealTargets,
            preferredWindow: nil,
            reason: reason,
            activation: .runningApplication([.activateAllWindows, .activateIgnoringOtherApps])
        )
    }

    @discardableResult
    func reveal(
        _ windows: [NSWindow],
        preferredWindow: NSWindow?,
        reason: Reason,
        activation: Activation = .runningApplication([.activateAllWindows, .activateIgnoringOtherApps])
    ) -> NSWindow? {
        let windows = uniqueWindows(windows)
        guard !windows.isEmpty else {
            log("reveal.empty", reason: reason, windows: [])
            return nil
        }

        for window in windows where dependencies.windowOperations.isMiniaturized(window) {
            dependencies.windowOperations.deminiaturize(window)
        }
        activate(activation)

        let focusWindow = resolvedPreferredFocusWindow(preferredWindow: preferredWindow, in: windows)
        if let focusWindow {
            dependencies.setActiveMainWindow(focusWindow)
            dependencies.windowOperations.makeKeyAndOrderFront(focusWindow)
        }

        for window in windows where window !== focusWindow {
            dependencies.windowOperations.orderFrontRegardless(window)
        }

        log("reveal", reason: reason, windows: windows)
        return focusWindow
    }

    private func resolvedPreferredFocusWindow(preferredWindow: NSWindow?, in windows: [NSWindow]) -> NSWindow? {
        if let preferredWindow, windows.contains(where: { $0 === preferredWindow }) {
            return preferredWindow
        }
        if let keyWindow = dependencies.keyWindow(), windows.contains(where: { $0 === keyWindow }) {
            return keyWindow
        }
        if let mainWindow = dependencies.mainWindow(), windows.contains(where: { $0 === mainWindow }) {
            return mainWindow
        }
        return windows.first(where: dependencies.windowOperations.canBecomeMain)
            ?? windows.first(where: dependencies.windowOperations.canBecomeKey)
            ?? windows.first
    }

    private func activate(_ activation: Activation) {
        switch activation {
        case .none:
            break
        case .appIgnoringOtherApps(let ignoringOtherApps):
            dependencies.activateApplicationIgnoringOtherApps(ignoringOtherApps)
        case .runningApplication(let options):
            dependencies.activateRunningApplication(options)
        }
    }

    private func uniqueWindows(_ windows: [NSWindow]) -> [NSWindow] {
        var result: [NSWindow] = []
        for window in windows where !result.contains(where: { $0 === window }) {
            result.append(window)
        }
        return result
    }

    private func log(_ event: String, reason: Reason, windows: [NSWindow]) {
#if DEBUG
        let windowTokens = windows.map { window -> String in
            let id = window.identifier?.rawValue ?? "<nil>"
            return "\(id):visible=\(dependencies.windowOperations.isVisible(window) ? 1 : 0):mini=\(dependencies.windowOperations.isMiniaturized(window) ? 1 : 0):key=\(dependencies.windowOperations.isKeyWindow(window) ? 1 : 0)"
        }
        cmuxDebugLog("mainWindow.visibility.\(event) reason=\(reason.rawValue) windows=[\(windowTokens.joined(separator: ","))]")
#endif
    }
}
