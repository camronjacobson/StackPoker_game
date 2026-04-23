import SwiftUI

@main
struct StackPokerApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var authViewModel = AuthViewModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .environmentObject(authViewModel)
                .preferredColorScheme(.dark)
        }
    }
}
