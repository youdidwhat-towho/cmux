import SwiftUI

@main
struct CMuxMobileApp: App {
    @StateObject private var connectionStore = CmxConnectionStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(connectionStore)
        }
    }
}
