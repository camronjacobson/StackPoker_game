import SwiftUI
import UIKit
import Combine

// ─── Tab bar visibility coordinator ──────────────────────────────────────────
// Lets pushed views (e.g. HandReplayView) hide the custom bottom bar so their
// own scrolling content isn't covered by it. Singleton because the bar lives
// at the root of MainTabView and the pushed views are deep inside a
// NavigationStack — environment binding through that path is brittle.

@MainActor
final class TabBarVisibility: ObservableObject {
    static let shared = TabBarVisibility()
    @Published var isHidden: Bool = false
    private init() {}
}

struct MainTabView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var subscription: SubscriptionManager
    @EnvironmentObject var cosmetics: CosmeticsContainer
    @StateObject private var lobbyVM = LobbyViewModel()
    @StateObject private var tabBarVis = TabBarVisibility.shared
    @State private var selectedTab: AppTab = .home

    // Replaced the long-dead `.alerts` tab (no notifications backend, no UI
    // beyond a placeholder) with `.store` 2026-05-18. Behaves like Home /
    // Friends — selecting it swaps the content area to StoreView. The other
    // store entry points (ChipsView, ProfileView) remain `.sheet`-based
    // because they're contextual; the tab-bar entry is the dedicated
    // destination, so it gets full-screen navigation and a selected visual
    // state like every other tab.
    enum AppTab: Int, CaseIterable {
        case home, history, create, store, friends

        var icon: String {
            switch self {
            case .home:    return "house.fill"
            case .history: return "clock.arrow.circlepath"
            case .create:  return "plus"
            case .store:   return "cart.fill"
            case .friends: return "person.2.fill"
            }
        }

        var label: String {
            switch self {
            case .home:    return "Home"
            case .history: return "Review"
            case .create:  return ""
            case .store:   return "Store"
            case .friends: return "Friends"
            }
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Paper substrate — same base as LobbyView so the bg under the
            // tab bar reads continuous with the home screen. Each tab's
            // content view still draws its own bg on top, so this only
            // peeks through at the bottom edge behind the bar.
            AgedPaperBackground()

            // Content
            Group {
                switch selectedTab {
                case .home:    LobbyView().environmentObject(lobbyVM)
                // Review-feature overhaul (PR 3): the History tab now lands
                // on a coach-style dashboard instead of the raw list. The
                // dashboard pushes HistoryListView for "See all hands".
                //
                // Premium gate: Review is the headline premium feature, so
                // we render the paywall in this tab slot when the user
                // doesn't have an active trial or subscription. We use a
                // tab-replacement paywall (vs. modal) so dismissing is a
                // simple tap on a different tab, which feels less pushy.
                // While trial is active, a thin gold banner sits above the
                // dashboard counting down the remaining time.
                case .history:
                    if subscription.isPremiumActive {
                        VStack(spacing: 0) {
                            TrialBanner()
                            ReviewDashboardView()
                        }
                    } else {
                        PaywallView()
                    }
                case .create:  LobbyView().environmentObject(lobbyVM) // Create triggers sheet, not a tab
                case .store:   StoreView(vm: makeStoreViewModel(entryPoint: .lobbyTab))
                case .friends: FriendsTabView()
                }
            }

            // Tab bar — hidden when a pushed screen requests it (e.g. replay)
            if !tabBarVis.isHidden {
                PokerTabBar(selectedTab: $selectedTab, onCreateTap: {
                    selectedTab = .home
                    lobbyVM.showCreateSheet = true
                })
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: tabBarVis.isHidden)
        .ignoresSafeArea(.keyboard)
    }

    /// Factory for the store VM mirrored from ChipsView / ProfileView so the
    /// in-store balance pill stays in sync with daily-bonus / transfer /
    /// purchase mutations. ChipAmount tolerates bad payloads — bogus chip
    /// strings render as .zero instead of crashing.
    private func makeStoreViewModel(entryPoint: StoreEntryPoint) -> StoreViewModel {
        let balancePublisher = authVM.$currentUser
            .map { profile -> ChipAmount in
                ChipAmount(serverString: profile?.chipBalance ?? "0") ?? .zero
            }
            .eraseToAnyPublisher()
        return StoreViewModel(
            container:        cosmetics,
            balancePublisher: balancePublisher,
            entryPoint:       entryPoint
        )
    }
}

// ─── Poker Tab Bar ───────────────────────────────────────────────────────────

struct PokerTabBar: View {
    @Binding var selectedTab: MainTabView.AppTab
    let onCreateTap: () -> Void

    // Bundled Kenney UI click + light impact haptic, fired together on
    // every tab icon tap (Home / Review / + / Alerts / Friends). Kept as
    // a private helper so all five buttons share the exact same cue —
    // tapping different tabs shouldn't feel or sound subtly different.
    // .light matches Apple's own tab-bar selection feel; .medium felt
    // too heavy for a navigation action.
    private func tabTapFeedback() {
        SoundManager.shared.play(.menuTap)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(MainTabView.AppTab.allCases, id: \.self) { tab in
                if tab == .create {
                    // Center "+" — mustard burst-circle with ink border and a
                    // hard ink offset shadow. Same comic-panel language as the
                    // lobby's JOIN! CTA so this button reads as the same
                    // family of "punch this" actions.
                    Button {
                        tabTapFeedback()
                        onCreateTap()
                    } label: {
                        ZStack {
                            // Hard ink offset shadow (no blur — comic pages
                            // don't blur).
                            Circle()
                                .fill(SPRetro.ink)
                                .frame(width: 54, height: 54)
                                .offset(x: 2, y: 3)
                            Circle()
                                .fill(SPRetro.mustard)
                                .frame(width: 54, height: 54)
                            Circle()
                                .strokeBorder(SPRetro.ink, lineWidth: 2.5)
                                .frame(width: 54, height: 54)

                            Image(systemName: "plus")
                                .font(.system(size: 24, weight: .black))
                                .foregroundStyle(SPRetro.ink)
                        }
                        .offset(y: -10)
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    Button {
                        tabTapFeedback()
                        // Was `withAnimation(.spring(...)) { selectedTab = tab }`.
                        // The spring made the switch-Group in MainTabView.body
                        // cross-fade between tabs, and since each tab paints its
                        // own paper background on top of MainTabView's
                        // AgedPaperBackground, the two semi-transparent paper
                        // layers combined at intermediate opacities during the
                        // ~300ms transition produced a brief darker/yellower
                        // flash. Native iOS tab switching is instant; matching
                        // that removes the flash entirely — fixed 2026-05-13.
                        selectedTab = tab
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 20, weight: selectedTab == tab ? .black : .bold))
                                .foregroundStyle(selectedTab == tab ? SPRetro.ink : SPRetro.inkSoft.opacity(0.55))

                            Text(tab.label)
                                .font(SPRetroFonts.callout(10))
                                .foregroundStyle(selectedTab == tab ? SPRetro.ink : SPRetro.inkSoft.opacity(0.55))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, SPSpacing.xs)
                    }
                }
            }
        }
        .padding(.horizontal, SPSpacing.sm)
        .padding(.top, SPSpacing.sm)
        // Was `SPSpacing.md + 10` (~26pt) which pushed the icons far above
        // the home indicator and left a visible gap. The bottom safe-area
        // on home-indicator devices is already ~34pt, so a minimal extra
        // pad of `xs` is enough — icons now sit close to the bottom edge
        // without overlapping the swipe-up indicator.
        .padding(.bottom, SPSpacing.xs)
        .background(
            ZStack {
                SPRetro.paperShade
                // Ink hairline along the top — reads as the page fold
                // separating the tab bar from the content above. Slightly
                // thicker than a normal 0.5 divider so it carries the
                // comic-panel weight of the rest of the page.
                Rectangle()
                    .fill(SPRetro.ink)
                    .frame(height: 2.5)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            // Extend the background fill through the bottom safe-area
            // (home indicator region). Without this, the paper substrate
            // shows through below the bar and reads as a "weird gap"
            // between the tab bar and the bottom of the screen. Icons
            // themselves stay above the indicator via the bottom padding
            // above — only the paperShade fill stretches down.
            .ignoresSafeArea(edges: .bottom)
        )
    }
}

// ─── Placeholder views for new tabs ──────────────────────────────────────────

// FriendsTabView used to be a placeholder showing only an icon and the word
// "Friends", which is why mutual friends never appeared in the bottom-bar tab
// even though they showed up in LobbyView's friends section. Now it renders
// the same Friends / Requests / Find sub-views the FriendsSheet uses, but
// embedded as a tab (no dismiss button, no presentationDetents). Reusing the
// existing FriendsTabBar / FriendsListTab / FriendRequestsTab / FriendSearchTab
// keeps the UX identical between the modal sheet and the dedicated tab.
struct FriendsTabView: View {
    @StateObject private var fvm = FriendsViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                SPColors.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    FriendsTabBar(vm: fvm)
                        .padding(.horizontal, SPSpacing.md)
                        .padding(.top, SPSpacing.sm)
                        .padding(.bottom, SPSpacing.md)

                    SPDivider()

                    Group {
                        switch fvm.activeTab {
                        case .friends:  FriendsListTab(vm: fvm)
                        case .requests: FriendRequestsTab(vm: fvm)
                        case .search:   FriendSearchTab(vm: fvm)
                        }
                    }
                    .transition(.opacity.animation(.easeInOut(duration: 0.18)))
                    .animation(.easeInOut(duration: 0.18), value: fvm.activeTab)
                }
                // Reserve space for the custom tab bar that sits above this
                // view in MainTabView. Without this, the bottom of the
                // friends list slips behind the tab bar's pill background.
                .padding(.bottom, 60)
            }
            .navigationTitle("Friends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(SPColors.surface, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        withAnimation { fvm.activeTab = .search }
                    } label: {
                        Image(systemName: "person.badge.plus")
                            .foregroundStyle(SPColors.accent)
                    }
                }
            }
        }
        .task { await fvm.load() }
    }
}

struct ClubsPlaceholderView: View {
    var body: some View {
        ZStack {
            SPColors.background.ignoresSafeArea()
            VStack(spacing: SPSpacing.md) {
                Image(systemName: "person.3.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(SPColors.accent.opacity(0.5))
                Text("Groups")
                    .font(SPFonts.headline())
                    .foregroundStyle(SPColors.textSecondary)
            }
        }
    }
}
