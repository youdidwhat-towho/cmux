import SwiftUI
import AppKit

/// Shared appearance settings for pane-hosted content.
struct PanelAppearance {
    let dividerColor: Color
    let unfocusedOverlayNSColor: NSColor
    let unfocusedOverlayOpacity: Double

    static func fromConfig(_ config: GhosttyConfig) -> PanelAppearance {
        PanelAppearance(
            dividerColor: Color(nsColor: config.resolvedSplitDividerColor),
            unfocusedOverlayNSColor: config.unfocusedSplitOverlayFill,
            unfocusedOverlayOpacity: config.unfocusedSplitOverlayOpacity
        )
    }
}

extension GhosttySurfaceScrollView {
#if DEBUG
    func debugRequestSurfaceFirstResponderForTesting(in window: NSWindow, reason: String) -> Bool {
        requestSurfaceFirstResponder(in: window, reason: reason)
    }
#endif

    func foreignTerminalFocusBlockReason(in window: NSWindow) -> String? {
        guard let firstResponder = window.firstResponder else { return nil }
        if let view = firstResponder as? NSView,
           view === surfaceView || view.isDescendant(of: surfaceView) {
            return nil
        }
        if firstResponder is NSText {
            return "textEditorFocused"
        }
        if AppDelegate.shared?.isRightSidebarFocusResponder(firstResponder, in: window) == true {
            return "rightSidebarFocused"
        }
        return nil
    }

    func canRequestSurfaceFirstResponder(
        in window: NSWindow,
        reason: String,
        respectForeignFirstResponder: Bool = false
    ) -> Bool {
        guard let terminalSurface = surfaceView.terminalSurface else {
            return true
        }

        let allowed = AppDelegate.shared?.allowsTerminalKeyboardFocus(
            workspaceId: terminalSurface.tabId,
            panelId: terminalSurface.id,
            in: window
        ) ?? true

#if DEBUG
        if !allowed {
            dlog(
                "focus.apply.skip surface=\(terminalSurface.id.uuidString.prefix(5)) " +
                "reason=\(reason).coordinatorRightSidebar"
            )
        }
#endif

        return allowed
    }

    @discardableResult
    func requestSurfaceFirstResponder(
        in window: NSWindow,
        reason: String,
        respectForeignFirstResponder: Bool = false
    ) -> Bool {
        guard canRequestSurfaceFirstResponder(
            in: window,
            reason: reason,
            respectForeignFirstResponder: respectForeignFirstResponder
        ) else {
            return false
        }
        if respectForeignFirstResponder,
           let blockReason = foreignTerminalFocusBlockReason(in: window) {
#if DEBUG
            dlog(
                "focus.apply.skip surface=\(surfaceView.terminalSurface?.id.uuidString.prefix(5) ?? "nil") " +
                "reason=\(reason).\(blockReason)"
            )
#endif
            return false
        }
        return window.makeFirstResponder(surfaceView)
    }
}
