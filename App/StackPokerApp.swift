import SwiftUI
import Combine

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
    // Cosmetics DI container. Single instance for the app process; the
    // bound-to-active-user subscription below pumps the auth userId into
    // InventoryRepository so the per-user inventory key swaps cleanly on
    // login/logout. Created via the production factory (real catalog +
    // UserDefaults inventory + remote purchase service).
    @StateObject private var cosmetics = CosmeticsContainer.makeProduction()

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
                .environmentObject(cosmetics)
                // Pinned to light to match the retro newsprint design language —
                // cream paper, ink text, mustard / maroon accents. The aesthetic
                // is built for light surfaces; dark-mode system chrome (sheet
                // dimming, keyboard, status-bar inversion) fights the design,
                // and every SPColors / SPRetro token is a static hex literal
                // (no dynamic light/dark variant) so there is no second palette
                // to tune. One-line lock is the right tactical choice.
                .preferredColorScheme(.light)
                // Bridge the Auth → Cosmetics seam. We forward the current
                // userId publisher into the inventory repo so cosmetics
                // state automatically scopes to whoever is signed in.
                // Subscribing on appear (not init) so authViewModel's
                // `@Published currentUser` is fully wired before we sink.
                .onAppear {
                    cosmetics.bindToActiveUser(
                        authViewModel.$currentUser
                            .map { $0?.id }
                            .eraseToAnyPublisher()
                    )
                    // Bridge purchase-success → AuthViewModel balance refresh.
                    // RemoteStorePurchaseService publishes the server-
                    // confirmed new balance through this closure after each
                    // successful purchase so the HUD, ChipsView, ProfileView,
                    // and Store balance pill update without a follow-up
                    // /auth/me round-trip. Wired here (not in init) because
                    // both objects are @StateObjects and can't reference
                    // each other at init time.
                    cosmetics.setBalanceUpdater { [weak authViewModel] newBalance in
                        authViewModel?.applyServerBalance(newBalance)
                    }
                    // Bridge GameSocketClient.chipsUpdatedSubject → AuthVM.
                    // Single subscription that lives for the app's lifetime;
                    // see backend TECH_DEBT.md "Balance sync via socket".
                    // Catches in-session wallet mutations the HTTP-level
                    // `newBalance` plumbing can't reach: leave_table cash-out,
                    // join_table re-debit, idle-table sweep refunds.
                    authViewModel.bindToSocketChipUpdates(GameSocketClient.shared)
                }
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
