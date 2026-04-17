import XCTest
import CoreGraphics

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

final class WorkspaceContentViewVisibilityTests: XCTestCase {
    func testPanelVisibleInUIReturnsFalseWhenWorkspaceHidden() {
        XCTAssertFalse(
            WorkspaceContentView.panelVisibleInUI(
                isWorkspaceVisible: false,
                isSelectedInPane: true,
                isFocused: true
            )
        )
    }

    func testPanelVisibleInUIReturnsTrueForSelectedPanel() {
        XCTAssertTrue(
            WorkspaceContentView.panelVisibleInUI(
                isWorkspaceVisible: true,
                isSelectedInPane: true,
                isFocused: false
            )
        )
    }

    func testPanelVisibleInUIReturnsFalseForFocusedPanelDuringTransientSelectionGap() {
        XCTAssertFalse(
            WorkspaceContentView.panelVisibleInUI(
                isWorkspaceVisible: true,
                isSelectedInPane: false,
                isFocused: true
            )
        )
    }

    func testPanelVisibleInUIReturnsFalseWhenNeitherSelectedNorFocused() {
        XCTAssertFalse(
            WorkspaceContentView.panelVisibleInUI(
                isWorkspaceVisible: true,
                isSelectedInPane: false,
                isFocused: false
            )
        )
    }

    func testPanelPresentationFactsDeriveVisibilityAndResponderIntent() {
        let paneId = PaneID(id: UUID())
        let panelId = UUID()

        let visibleFocused = WorkspacePanelPresentationFacts(
            paneId: paneId,
            panelId: panelId,
            isWorkspaceVisible: true,
            isWorkspaceInputActive: true,
            isSelectedInPane: true,
            isFocused: true
        )
        XCTAssertTrue(visibleFocused.isVisibleInUI)
        XCTAssertTrue(visibleFocused.wantsFirstResponder)

        let hidden = WorkspacePanelPresentationFacts(
            paneId: paneId,
            panelId: panelId,
            isWorkspaceVisible: false,
            isWorkspaceInputActive: true,
            isSelectedInPane: true,
            isFocused: true
        )
        XCTAssertFalse(hidden.isVisibleInUI)
        XCTAssertFalse(hidden.wantsFirstResponder)
    }

    func testTerminalPresentationTransitionResolverEmitsOnlyEdgeOperations() {
        let hidden = WorkspaceTerminalPresentationState(isVisibleInUI: false, isActive: false)
        let visibleFocused = WorkspaceTerminalPresentationState(isVisibleInUI: true, isActive: true)

        XCTAssertEqual(
            WorkspaceTerminalPresentationTransitionResolver.operations(
                previous: hidden,
                next: visibleFocused
            ),
            [.setVisibleInUI(true), .setActive(true), .requestFirstResponderReconcile]
        )

        XCTAssertEqual(
            WorkspaceTerminalPresentationTransitionResolver.operations(
                previous: visibleFocused,
                next: visibleFocused
            ),
            []
        )

        XCTAssertEqual(
            WorkspaceTerminalPresentationTransitionResolver.operations(
                previous: visibleFocused,
                next: hidden
            ),
            [.setVisibleInUI(false), .setActive(false)]
        )
    }

    func testTmuxWorkspacePaneOverlayRectReturnsMatchingPaneFrame() {
        let paneID = PaneID(id: UUID())
        let snapshot = LayoutSnapshot(
            containerFrame: PixelRect(x: 200, y: 32, width: 1200, height: 800),
            panes: [
                PaneGeometry(
                    paneId: paneID.id.uuidString,
                    frame: PixelRect(x: 877.5, y: 32, width: 500, height: 320),
                    selectedTabId: nil,
                    tabIds: []
                )
            ],
            focusedPaneId: paneID.id.uuidString,
            timestamp: 0
        )

        XCTAssertEqual(
            WorkspaceContentView.tmuxWorkspacePaneOverlayRect(
                layoutSnapshot: snapshot,
                paneId: paneID
            ),
            CGRect(x: 677.5, y: 30, width: 500, height: 290)
        )
    }

    @MainActor
    func testTmuxWorkspacePaneUnreadRectsIncludeFocusedReadIndicator() {
        let appDelegate = AppDelegate.shared ?? AppDelegate()
        let manager = TabManager()
        let store = TerminalNotificationStore.shared

        let originalTabManager = appDelegate.tabManager
        let originalNotificationStore = appDelegate.notificationStore

        store.replaceNotificationsForTesting([])
        store.configureNotificationDeliveryHandlerForTesting { _, _ in }
        appDelegate.tabManager = manager
        appDelegate.notificationStore = store

        defer {
            store.replaceNotificationsForTesting([])
            store.resetNotificationDeliveryHandlerForTesting()
            appDelegate.tabManager = originalTabManager
            appDelegate.notificationStore = originalNotificationStore
        }

        guard let workspace = manager.selectedWorkspace,
              let panelId = workspace.focusedPanelId,
              let surfaceId = workspace.surfaceIdFromPanelId(panelId),
              let paneId = workspace.paneId(forPanelId: panelId) else {
            XCTFail("Expected selected workspace geometry")
            return
        }

        store.setFocusedReadIndicator(forTabId: workspace.id, surfaceId: panelId)

        let snapshot = LayoutSnapshot(
            containerFrame: PixelRect(x: 200, y: 32, width: 1200, height: 800),
            panes: [
                PaneGeometry(
                    paneId: paneId.id.uuidString,
                    frame: PixelRect(x: 877.5, y: 32, width: 500, height: 320),
                    selectedTabId: surfaceId.uuid.uuidString,
                    tabIds: [surfaceId.uuid.uuidString]
                )
            ],
            focusedPaneId: paneId.id.uuidString,
            timestamp: 0
        )

        XCTAssertEqual(
            WorkspaceContentView.tmuxWorkspacePaneUnreadRects(
                workspace: workspace,
                notificationStore: store,
                layoutSnapshot: snapshot
            ),
            [CGRect(x: 677.5, y: 30, width: 500, height: 290)]
        )
    }
}

@MainActor
final class TerminalViewportLifecycleControllerTests: XCTestCase {
    private func facts(
        visible: Bool,
        windowed: Bool,
        geometry: Bool,
        runtime: Bool,
        presentedFrame: Bool,
        active: Bool
    ) -> TerminalViewportLifecycleFacts {
        TerminalViewportLifecycleFacts(
            isVisibleInUI: visible,
            isWindowed: windowed,
            hasUsableGeometry: geometry,
            hasRuntime: runtime,
            hasPresentedFrame: presentedFrame,
            isActive: active
        )
    }

    func testVisibleLifecycleWaitsForWindowAndGeometryBeforeRuntimeCreation() {
        let controller = TerminalViewportLifecycleController()

        XCTAssertEqual(
            controller.reconcile(
                facts: facts(
                    visible: true,
                    windowed: false,
                    geometry: false,
                    runtime: false,
                    presentedFrame: false,
                    active: false
                ),
                force: false
            ),
            TerminalViewportLifecycleUpdate(
                phase: .mountedAwaitingWindow,
                demand: .visible,
                commands: []
            )
        )

        XCTAssertEqual(
            controller.reconcile(
                facts: facts(
                    visible: true,
                    windowed: true,
                    geometry: false,
                    runtime: false,
                    presentedFrame: false,
                    active: false
                ),
                force: false
            ),
            TerminalViewportLifecycleUpdate(
                phase: .mountedAwaitingGeometry,
                demand: .visible,
                commands: []
            )
        )

        XCTAssertEqual(
            controller.reconcile(
                facts: facts(
                    visible: true,
                    windowed: true,
                    geometry: true,
                    runtime: false,
                    presentedFrame: false,
                    active: false
                ),
                force: false
            ),
            TerminalViewportLifecycleUpdate(
                phase: .runtimeRealized,
                demand: .visible,
                commands: [.realizeRuntime, .synchronizeVisibleGeometry]
            )
        )
    }

    func testAwaitingFirstFrameRequestsRedrawOnlyOnEntry() {
        let controller = TerminalViewportLifecycleController()
        let awaitingFirstFrameFacts = facts(
            visible: true,
            windowed: true,
            geometry: true,
            runtime: true,
            presentedFrame: false,
            active: false
        )

        XCTAssertEqual(
            controller.reconcile(facts: awaitingFirstFrameFacts, force: false),
            TerminalViewportLifecycleUpdate(
                phase: .awaitingFirstFrame,
                demand: .visible,
                commands: [.synchronizeVisibleGeometry, .requestFirstFrame]
            )
        )

        XCTAssertEqual(
            controller.reconcile(facts: awaitingFirstFrameFacts, force: false),
            TerminalViewportLifecycleUpdate(
                phase: .awaitingFirstFrame,
                demand: .visible,
                commands: [.synchronizeVisibleGeometry]
            )
        )
    }

    func testVisibleFocusedPhaseResumesFocusOnlyAfterFramePresentation() {
        let controller = TerminalViewportLifecycleController()

        XCTAssertEqual(
            controller.reconcile(
                facts: facts(
                    visible: true,
                    windowed: true,
                    geometry: true,
                    runtime: true,
                    presentedFrame: true,
                    active: false
                ),
                force: false
            ),
            TerminalViewportLifecycleUpdate(
                phase: .visible,
                demand: .visible,
                commands: [.synchronizeVisibleGeometry]
            )
        )

        XCTAssertEqual(
            controller.reconcile(
                facts: facts(
                    visible: true,
                    windowed: true,
                    geometry: true,
                    runtime: true,
                    presentedFrame: true,
                    active: true
                ),
                force: false
            ),
            TerminalViewportLifecycleUpdate(
                phase: .visibleFocused,
                demand: .visible,
                commands: [.synchronizeVisibleGeometry, .resumeFocus]
            )
        )
    }

    func testBackgroundDemandPersistsUntilRuntimeCreationBecomesPossible() {
        let controller = TerminalViewportLifecycleController()
        controller.requestBackgroundRuntime()

        XCTAssertEqual(
            controller.reconcile(
                facts: facts(
                    visible: false,
                    windowed: false,
                    geometry: false,
                    runtime: false,
                    presentedFrame: false,
                    active: false
                ),
                force: false
            ),
            TerminalViewportLifecycleUpdate(
                phase: .mountedAwaitingWindow,
                demand: .background,
                commands: []
            )
        )

        XCTAssertEqual(
            controller.reconcile(
                facts: facts(
                    visible: false,
                    windowed: true,
                    geometry: false,
                    runtime: false,
                    presentedFrame: false,
                    active: false
                ),
                force: false
            ),
            TerminalViewportLifecycleUpdate(
                phase: .mountedHidden,
                demand: .background,
                commands: []
            )
        )

        XCTAssertEqual(
            controller.reconcile(
                facts: facts(
                    visible: false,
                    windowed: true,
                    geometry: true,
                    runtime: false,
                    presentedFrame: false,
                    active: false
                ),
                force: false
            ),
            TerminalViewportLifecycleUpdate(
                phase: .runtimeRealized,
                demand: .background,
                commands: [.realizeRuntime]
            )
        )
    }
}
