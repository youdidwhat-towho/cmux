import SwiftUI

/// Bonsplit-pane host for the iOS Simulator viewer. Reuses `SimulatorListView`.
struct SimulatorPanelView: View {
    @ObservedObject var panel: SimulatorPanel
    let isFocused: Bool
    let isVisibleInUI: Bool
    let portalPriority: Int
    let onRequestPanelFocus: (UUID) -> Void

    var body: some View {
        SimulatorListView(initialUDID: panel.preferredUDID)
            .background(Color(nsColor: .windowBackgroundColor))
            .onTapGesture {
                onRequestPanelFocus(panel.id)
            }
    }
}
