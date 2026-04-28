import Foundation
import SwiftUI

enum WorkspaceLayoutTabKind: String, Codable, Sendable {
    case terminal
    case browser
    case markdown
}

struct WorkspaceLayoutConfiguration: Sendable {
    var allowSplits: Bool
    var allowCloseTabs: Bool
    var allowCloseLastPane: Bool
    var allowTabReordering: Bool
    var allowCrossPaneTabMove: Bool
    var autoCloseEmptyPanes: Bool
    var newTabPosition: NewTabPosition
    var appearance: Appearance

    static let `default` = WorkspaceLayoutConfiguration()

    init(
        allowSplits: Bool = true,
        allowCloseTabs: Bool = true,
        allowCloseLastPane: Bool = false,
        allowTabReordering: Bool = true,
        allowCrossPaneTabMove: Bool = true,
        autoCloseEmptyPanes: Bool = true,
        newTabPosition: NewTabPosition = .current,
        appearance: Appearance = .default
    ) {
        self.allowSplits = allowSplits
        self.allowCloseTabs = allowCloseTabs
        self.allowCloseLastPane = allowCloseLastPane
        self.allowTabReordering = allowTabReordering
        self.allowCrossPaneTabMove = allowCrossPaneTabMove
        self.autoCloseEmptyPanes = autoCloseEmptyPanes
        self.newTabPosition = newTabPosition
        self.appearance = appearance
    }

    struct SplitButtonTooltips: Sendable, Equatable {
        var newTerminal: String
        var newBrowser: String
        var splitRight: String
        var splitDown: String

        static let `default` = SplitButtonTooltips()

        init(
            newTerminal: String = String(localized: "workspace.tooltip.newTerminal", defaultValue: "New Terminal"),
            newBrowser: String = String(localized: "workspace.tooltip.newBrowser", defaultValue: "New Browser"),
            splitRight: String = String(localized: "workspace.tooltip.splitRight", defaultValue: "Split Right"),
            splitDown: String = String(localized: "workspace.tooltip.splitDown", defaultValue: "Split Down")
        ) {
            self.newTerminal = newTerminal
            self.newBrowser = newBrowser
            self.splitRight = splitRight
            self.splitDown = splitDown
        }
    }

    struct Appearance: Sendable {
        struct ChromeColors: Sendable {
            var backgroundHex: String?
            var borderHex: String?

            init(backgroundHex: String? = nil, borderHex: String? = nil) {
                self.backgroundHex = backgroundHex
                self.borderHex = borderHex
            }
        }

        var tabBarHeight: CGFloat
        var tabMinWidth: CGFloat
        var tabMaxWidth: CGFloat
        var tabTitleFontSize: CGFloat
        var tabSpacing: CGFloat
        var minimumPaneWidth: CGFloat
        var minimumPaneHeight: CGFloat
        var showSplitButtons: Bool
        var splitButtonsOnHover: Bool
        var tabBarLeadingInset: CGFloat
        var splitButtonTooltips: SplitButtonTooltips
        var animationDuration: Double
        var enableAnimations: Bool
        var chromeColors: ChromeColors

        static let `default` = Appearance()

        init(
            tabBarHeight: CGFloat = 30,
            tabMinWidth: CGFloat = 48,
            tabMaxWidth: CGFloat = 220,
            tabTitleFontSize: CGFloat = 11,
            tabSpacing: CGFloat = 0,
            minimumPaneWidth: CGFloat = 100,
            minimumPaneHeight: CGFloat = 100,
            showSplitButtons: Bool = true,
            splitButtonsOnHover: Bool = false,
            tabBarLeadingInset: CGFloat = 0,
            splitButtonTooltips: SplitButtonTooltips = .default,
            animationDuration: Double = 0.15,
            enableAnimations: Bool = false,
            chromeColors: ChromeColors = .init()
        ) {
            self.tabBarHeight = tabBarHeight
            self.tabMinWidth = tabMinWidth
            self.tabMaxWidth = tabMaxWidth
            self.tabTitleFontSize = tabTitleFontSize
            self.tabSpacing = tabSpacing
            self.minimumPaneWidth = minimumPaneWidth
            self.minimumPaneHeight = minimumPaneHeight
            self.showSplitButtons = showSplitButtons
            self.splitButtonsOnHover = splitButtonsOnHover
            self.tabBarLeadingInset = tabBarLeadingInset
            self.splitButtonTooltips = splitButtonTooltips
            self.animationDuration = animationDuration
            self.enableAnimations = enableAnimations
            self.chromeColors = chromeColors
        }
    }
}

enum WorkspaceLayout {
    struct Tab: Identifiable, Hashable, Codable, Sendable {
        var id: TabID
        var title: String
        var hasCustomTitle: Bool
        var icon: String?
        var iconImageData: Data?
        var kind: WorkspaceLayoutTabKind?
        var isDirty: Bool
        var showsNotificationBadge: Bool
        var isLoading: Bool
        var isPinned: Bool

        init(
            id: TabID = TabID(),
            title: String,
            hasCustomTitle: Bool = false,
            icon: String? = nil,
            iconImageData: Data? = nil,
            kind: WorkspaceLayoutTabKind? = nil,
            isDirty: Bool = false,
            showsNotificationBadge: Bool = false,
            isLoading: Bool = false,
            isPinned: Bool = false
        ) {
            self.id = id
            self.title = title
            self.hasCustomTitle = hasCustomTitle
            self.icon = icon
            self.iconImageData = iconImageData
            self.kind = kind
            self.isDirty = isDirty
            self.showsNotificationBadge = showsNotificationBadge
            self.isLoading = isLoading
            self.isPinned = isPinned
        }

        static func rendered(
            id: TabID = TabID(),
            title: String,
            hasCustomTitle: Bool = false,
            icon: String? = nil,
            iconImageData: Data? = nil,
            kind: WorkspaceLayoutTabKind? = nil,
            isDirty: Bool = false,
            showsNotificationBadge: Bool = false,
            isLoading: Bool = false,
            isPinned: Bool = false
        ) -> Self {
            var tab = Self(id: id, title: title, isPinned: isPinned)
            tab.hasCustomTitle = hasCustomTitle
            tab.icon = icon
            tab.iconImageData = iconImageData
            tab.kind = kind
            tab.isDirty = isDirty
            tab.showsNotificationBadge = showsNotificationBadge
            tab.isLoading = isLoading
            return tab
        }
    }
}
