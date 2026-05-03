import SwiftUI

@main
struct StackPokerApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var authViewModel = AuthViewModel()
    // Single source of truth for premium entitlement (trial + subscription).
    // Injected at the root so MainTabView, PaywallView and TrialBanner all
    // observe the same instance.
    @StateObject private var subscriptionManager = SubscriptionManager.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .environmentObject(authViewModel)
                .environmentObject(subscriptionManager)
                .preferredColorScheme(.dark)
        }
    }
}
