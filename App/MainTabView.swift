import SwiftUI

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
    @StateObject private var lobbyVM = LobbyViewModel()
    @StateObject private var tabBarVis = TabBarVisibility.shared
    @State private var selectedTab: AppTab = .home

    enum AppTab: Int, CaseIterable {
        case home, history, create, alerts, friends

        var icon: String {
            switch self {
            case .home:    return "house.fill"
            case .history: return "clock.arrow.circlepath"
            case .create:  return "plus"
            case .alerts:  return "bell.fill"
            case .friends: return "person.2.fill"
            }
        }

        var label: String {
            switch self {
            case .home:    return "Home"
            case .history: return "Review"
            case .create:  return ""
            case .alerts:  return "Alerts"
            case .friends: return "Friends"
            }
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            SPColors.background.ignoresSafeArea()

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
                case .alerts:  AlertsPlaceholderView()
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
}

// ─── Poker Tab Bar ───────────────────────────────────────────────────────────

struct PokerTabBar: View {
    @Binding var selectedTab: MainTabView.AppTab
    let onCreateTap: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(MainTabView.AppTab.allCases, id: \.self) { tab in
                if tab == .create {
                    // Center "+" button
                    Button {
                        onCreateTap()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color(hex: "#6C5CE7"), Color(hex: "#4A3AB4")],
                                        startPoint: .topLeading, endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 52, height: 52)
                                .shadow(color: Color(hex: "#6C5CE7").opacity(0.4), radius: 8, y: 2)

                            Image(systemName: "plus")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        .offset(y: -10)
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedTab = tab
                        }
                    } label: {
                        VStack(spacing: 3) {
                            ZStack {
                                Image(systemName: tab.icon)
                                    .font(.system(size: 20, weight: selectedTab == tab ? .semibold : .regular))
                                    .foregroundStyle(selectedTab == tab ? .white : Color.white.opacity(0.35))

                                // Alert badge
                                if tab == .alerts {
                                    Circle()
                                        .fill(Color(hex: "#E05555"))
                                        .frame(width: 8, height: 8)
                                        .offset(x: 10, y: -8)
                                }
                            }

                            Text(tab.label)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(selectedTab == tab ? .white : Color.white.opacity(0.35))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, SPSpacing.xs)
                    }
                }
            }
        }
        .padding(.horizontal, SPSpacing.sm)
        .padding(.top, SPSpacing.sm)
        .padding(.bottom, SPSpacing.md + 10)
        .background(
            ZStack {
                Color(hex: "#0D0D14")
                Rectangle()
                    .fill(Color.white.opacity(0.04))
                    .frame(height: 0.5)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
        )
    }
}

// ─── Placeholder views for new tabs ──────────────────────────────────────────

struct AlertsPlaceholderView: View {
    var body: some View {
        ZStack {
            SPColors.background.ignoresSafeArea()
            VStack(spacing: SPSpacing.md) {
                Image(systemName: "bell.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(SPColors.accent.opacity(0.5))
                Text("No new alerts")
                    .font(SPFonts.headline())
                    .foregroundStyle(SPColors.textSecondary)
            }
        }
    }
}

struct FriendsTabView: View {
    @StateObject private var fvm = FriendsViewModel()

    var body: some View {
        ZStack {
            SPColors.background.ignoresSafeArea()
            VStack(spacing: SPSpacing.md) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(SPColors.accent.opacity(0.5))
                Text("Friends")
                    .font(SPFonts.headline())
                    .foregroundStyle(SPColors.textSecondary)
            }
        }
        .onAppear { Task { await fvm.load() } }
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
