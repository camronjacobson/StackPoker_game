import SwiftUI

@main
struct StackPokerApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var authViewModel = AuthViewModel()
    // Single source of truth for premium entitlement (trial + subscription).
    // Injected at the root so MainTabView, PaywallView and TrialBanner all
    // observe the same instance.
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    // Drives the full-screen daily-bonus reveal. Lives at app root so the
    // overlay can sit above MainTabView (covers the tab bar) and outside
    // the lobby's ScrollView clip.
    @StateObject private var dailyBonusPresenter = DailyBonusRevealPresenter()

    // PERF: warm up SoundManager off the main thread at app launch so the
    // first in-game sound effect (check / fold / call / etc.) doesn't pay
    // the AVAudioEngine start + buffer load cost on the main thread mid-
    // game — that decode work was contributing to the visible stutter on
    // the first action after entering a hand. SoundManager's init is
    // thread-safe (AVAudioSession + AVAudioEngine + AVAudioConverter all
    // tolerate non-main usage), so a detached background Task is fine.
    init() {
        Task.detached(priority: .utility) {
            _ = SoundManager.shared
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .environmentObject(authViewModel)
                .environmentObject(subscriptionManager)
                .environmentObject(dailyBonusPresenter)
                .preferredColorScheme(.dark)
                // ─── Live Activity → app deep-link bridge ──────────────────
                // The Fold button in the Live Activity fires
                // FoldFromActivityIntent (an `OpenIntent`), which asks iOS to
                // open this URL in our app:
                //
                //     stackpoker://table/<tableId>/action/fold
                //
                // We parse it into a `PokerActionDeepLink.Route` and hand it
                // to the router, which:
                //   • broadcasts a NotificationCenter event for any already-
                //     running GameViewModel to react to immediately, AND
                //   • holds a "pendingFold" flag for the cold-launch case
                //     (process killed, app being launched fresh — the VM
                //     doesn't exist yet, so it consumes the pending fold on
                //     its first state push).
                //
                // Anything we can't parse (malformed scheme, unknown action,
                // etc.) is silently dropped — there's nothing the user can do
                // about a malformed URL and we don't want to spam alerts.
                .onOpenURL { url in
                    guard let route = PokerActionDeepLink.parse(url) else { return }
                    PokerActionDeepLinkRouter.shared.receive(route)
                }
        }
    }
}
