import SwiftUI

// ─── History List View ────────────────────────────────────────────────────────
// The full hand-history list. Used in two places:
//   • As a "See all" destination pushed from ReviewDashboardView (PR 3).
//   • Stand-alone (kept for future deep-links / share targets).
// Tapping a row pushes the full HandReplayView. Empty state explains how
// hands get recorded.
//
// PR 4 — Filters + bookmarks:
//   • A horizontal filter chip row above the list (All / Wins / Losses /
//     Bookmarked). Resets on each entry — short-lived UI state, no need
//     to persist.
//   • Swipe-to-bookmark from the leading edge (`star.fill` / `star.slash`).
//     Tap-on-row is reserved for "open replay", so the bookmark control
//     intentionally lives on the swipe and not on the row content.
//   • Star indicator overlaid on the row's top-right when bookmarked.
//   • Filter-aware empty state copy ("No bookmarked hands" vs "No wins").

// One-line filter taxonomy. Backed by an enum so the chip row can iterate
// `allCases` and we get exhaustive `switch` checks when extending the set.
private enum HandFilter: String, CaseIterable, Identifiable {
    case all        = "All"
    case wins       = "Wins"
    case losses     = "Losses"
    case bookmarked = "Bookmarked"

    var id: String { rawValue }

    /// SF Symbol shown inside the chip. Each filter has a distinct visual
    /// shorthand so the row reads at a glance even before the label.
    var icon: String {
        switch self {
        case .all:        return "rectangle.stack"
        case .wins:       return "checkmark.seal.fill"
        case .losses:     return "xmark.seal.fill"
        case .bookmarked: return "star.fill"
        }
    }

    /// Tint per filter — only used when the chip is selected. Kept aligned
    /// with the per-row signaling colors so the same outcome reads in the
    /// same color across the screen.
    var tint: Color {
        switch self {
        case .all:        return SPColors.accentLight
        case .wins:       return SPColors.success
        case .losses:     return SPColors.danger
        case .bookmarked: return SPColors.chipGold
        }
    }
}

struct HistoryListView: View {
    @ObservedObject private var store = HandHistoryStore.shared
    @State private var selectedHandId: String?
    @State private var loadedHand: RecordedHand?
    @State private var pushReplay = false

    /// Active filter chip. Resets every time the screen mounts (`@State`
    /// belongs to the view's lifecycle, not the store) — feels right for
    /// "where did I leave off?" not being a confusing question.
    @State private var filter: HandFilter = .all

    /// Source list after applying the active filter. Filtering is O(n) per
    /// render but `summaries` is the cheap in-memory index, so even with
    /// hundreds of hands this is essentially free. We deliberately *don't*
    /// debounce or cache — the filter switch should feel instant.
    private var filteredSummaries: [RecordedHandSummary] {
        switch filter {
        case .all:        return store.summaries
        case .wins:       return store.summaries.filter { $0.iWon }
        case .losses:     return store.summaries.filter { !$0.iWon }
        case .bookmarked: return store.summaries.filter { store.isBookmarked($0.id) }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                SPColors.background.ignoresSafeArea()

                // We always render the filter chips when there are *any*
                // hands at all — the chip row gives the user a path out of
                // an empty filtered state ("oh, switch back to All").
                if store.summaries.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 0) {
                        filterChipRow
                            .padding(.horizontal, SPSpacing.md)
                            .padding(.bottom, SPSpacing.sm)

                        if filteredSummaries.isEmpty {
                            filteredEmptyState
                        } else {
                            list
                        }
                    }
                }

                // Hidden NavigationLink driven by `pushReplay`. We do this so
                // we can lazily load the full hand from disk only when the
                // user taps in.
                NavigationLink(
                    destination: Group {
                        if let loadedHand {
                            HandReplayView(hand: loadedHand)
                        }
                    },
                    isActive: $pushReplay,
                    label: { EmptyView() }
                )
                .opacity(0)
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if !store.summaries.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button(role: .destructive) {
                                store.deleteAll()
                            } label: {
                                Label("Clear all", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .foregroundStyle(SPColors.textPrimary)
                        }
                    }
                }
            }
        }
    }

    // ─── Filter chips ────────────────────────────────────────────────────────

    /// Horizontal chip row. We use ScrollView even though four chips fit on
    /// every iPhone width today — keeps us safe if the filter set grows
    /// (e.g. "Showdowns" / "Big pots" / per-table filters in a future PR).
    private var filterChipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: SPSpacing.sm) {
                ForEach(HandFilter.allCases) { f in
                    filterChip(f)
                }
            }
        }
    }

    private func filterChip(_ f: HandFilter) -> some View {
        let isOn = filter == f
        // For the Bookmarked chip we surface the count so the user sees the
        // size of their starred set at a glance. Other chips don't — those
        // counts are obvious from scrolling the list.
        let count: Int? = (f == .bookmarked) ? store.bookmarkedIds.count : nil

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) { filter = f }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: f.icon)
                    .font(.system(size: 11, weight: .bold))
                Text(f.rawValue)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                if let count, count > 0 {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            Capsule().fill(
                                (isOn ? Color.black : f.tint).opacity(isOn ? 0.18 : 0.20)
                            )
                        )
                }
            }
            .foregroundStyle(isOn ? Color.black : SPColors.textPrimary)
            .padding(.horizontal, SPSpacing.sm + 2)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(
                    isOn ? f.tint : SPColors.surfaceElevated
                )
            )
            .overlay(
                Capsule().strokeBorder(
                    isOn ? f.tint.opacity(0.0) : Color.white.opacity(0.06),
                    lineWidth: 0.5
                )
            )
        }
        .buttonStyle(.plain)
    }

    // ─── List ────────────────────────────────────────────────────────────────

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: SPSpacing.sm) {
                ForEach(filteredSummaries) { summary in
                    Button {
                        if let hand = store.loadHand(id: summary.id) {
                            loadedHand = hand
                            selectedHandId = summary.id
                            pushReplay = true
                        }
                    } label: {
                        HandHistoryRow(
                            summary:      summary,
                            isBookmarked: store.isBookmarked(summary.id)
                        )
                    }
                    .buttonStyle(.plain)
                    // Leading-edge swipe = bookmark toggle. We use a non-
                    // destructive role so iOS doesn't auto-dismiss the row;
                    // the user can keep starring/unstarring without the row
                    // sliding off the screen.
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                store.toggleBookmark(id: summary.id)
                            }
                        } label: {
                            if store.isBookmarked(summary.id) {
                                Label("Unstar", systemImage: "star.slash.fill")
                            } else {
                                Label("Star", systemImage: "star.fill")
                            }
                        }
                        .tint(SPColors.chipGold)
                    }
                    // Trailing-edge swipe stays as the destructive delete.
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            store.delete(id: summary.id)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(.horizontal, SPSpacing.md)
            .padding(.bottom, 100) // breathing room above the tab bar
        }
    }

    // ─── Empty states ────────────────────────────────────────────────────────

    /// True empty state — no hands recorded at all.
    private var emptyState: some View {
        VStack(spacing: SPSpacing.md) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 48))
                .foregroundStyle(SPColors.accent.opacity(0.5))
            Text("No hands yet")
                .font(SPFonts.headline())
                .foregroundStyle(SPColors.textPrimary)
            Text("Play a hand and it'll show up here for replay and review.")
                .font(SPFonts.body(13))
                .foregroundStyle(SPColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, SPSpacing.xl)
        }
    }

    /// Filter-specific empty state. Hands exist, just none match the chip
    /// the user picked. We show a "Show all" shortcut so the user doesn't
    /// have to find the chip row again to escape the dead end.
    private var filteredEmptyState: some View {
        VStack(spacing: SPSpacing.md) {
            Image(systemName: filter.icon)
                .font(.system(size: 40))
                .foregroundStyle(filter.tint.opacity(0.5))
            Text(filteredEmptyTitle)
                .font(SPFonts.headline(15))
                .foregroundStyle(SPColors.textPrimary)
            Text(filteredEmptySubtitle)
                .font(SPFonts.body(12))
                .foregroundStyle(SPColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, SPSpacing.xl)

            if filter != .all {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { filter = .all }
                } label: {
                    Text("Show all hands")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.black)
                        .padding(.horizontal, SPSpacing.md)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(SPColors.accentLight))
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var filteredEmptyTitle: String {
        switch filter {
        case .all:        return "No hands yet"
        case .wins:       return "No wins yet"
        case .losses:     return "No losses recorded"
        case .bookmarked: return "No bookmarked hands"
        }
    }

    private var filteredEmptySubtitle: String {
        switch filter {
        case .all:
            return "Play a hand and it'll show up here."
        case .wins:
            return "Hands you win will land here. Keep at it."
        case .losses:
            return "No losing hands in your history — nice run."
        case .bookmarked:
            return "Swipe right on any hand to star it for later."
        }
    }
}

// ─── History Row ──────────────────────────────────────────────────────────────

struct HandHistoryRow: View {
    let summary: RecordedHandSummary
    /// Whether the row should display a star indicator. Defaults to false
    /// so callers that don't care (e.g. dashboard carousel reusing the row)
    /// keep their old behavior.
    var isBookmarked: Bool = false

    var body: some View {
        HStack(spacing: SPSpacing.md) {
            // Hole cards — sized large enough to read rank + suit at a glance
            // while scrolling. Tilted into a tight fan so they read as a hand
            // rather than two flat tiles.
            ZStack {
                if summary.myHoleCards.indices.contains(0) {
                    miniCard(summary.myHoleCards[0])
                        .rotationEffect(.degrees(-7))
                        .offset(x: -8)
                }
                if summary.myHoleCards.indices.contains(1) {
                    miniCard(summary.myHoleCards[1])
                        .rotationEffect(.degrees(7))
                        .offset(x: 8)
                }
            }
            .frame(width: 56, height: 46)

            VStack(alignment: .leading, spacing: 5) {
                Text(summary.tableName)
                    .font(SPFonts.headline(14))
                    .foregroundStyle(SPColors.textPrimary)
                    .lineLimit(1)

                // Tag-pill row: hand name + opponent count. Cleaner than free
                // text and gives the row visual structure to scan against.
                HStack(spacing: 5) {
                    if let name = summary.winningHandName {
                        rowTag(
                            text:  name,
                            color: summary.iWon ? SPColors.success : SPColors.textSecondary
                        )
                    }
                    rowTag(
                        text:  "\(summary.opponentCount + 1)P",
                        color: SPColors.textSecondary
                    )
                    Text(relativeTime(summary.endedAt))
                        .font(SPFonts.caption(11))
                        .foregroundStyle(SPColors.textTertiary)
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 4) {
                // Win/loss icon — the most important signal in the row,
                // promoted from a chevron to a tinted badge.
                Image(systemName: summary.iWon
                      ? "checkmark.seal.fill"
                      : "xmark.seal.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(summary.iWon ? SPColors.success : SPColors.danger)

                Text(summary.iWon
                     ? "+\(formatChips(summary.stackDelta))"
                     : formatChips(summary.stackDelta))
                    .font(SPFonts.chips(15))
                    .foregroundStyle(summary.iWon ? SPColors.success : SPColors.danger)
            }
        }
        .padding(.horizontal, SPSpacing.md)
        .padding(.vertical, SPSpacing.sm + 2)
        .background(
            RoundedRectangle(cornerRadius: SPRadius.md)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "#1F2C4A"), Color(hex: "#0D1525")],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    // Thin top-edge highlight reads as a subtle bevel — sells
                    // the card as elevated rather than painted onto the bg.
                    RoundedRectangle(cornerRadius: SPRadius.md)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.18),
                                    Color.white.opacity(0.04)
                                ],
                                startPoint: .top, endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                )
        )
        // Bookmark indicator. A tiny gold star floated into the top-right
        // corner so the bookmark state reads at a glance without taking up
        // structural space in the row layout. Only renders when starred so
        // unstarred rows stay visually quiet.
        .overlay(alignment: .topTrailing) {
            if isBookmarked {
                Image(systemName: "star.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(SPColors.chipGold)
                    .padding(5)
                    .background(
                        Circle()
                            .fill(Color.black.opacity(0.45))
                            .overlay(
                                Circle()
                                    .strokeBorder(SPColors.chipGold.opacity(0.6), lineWidth: 0.5)
                            )
                    )
                    .offset(x: -8, y: 8)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .shadow(color: Color.black.opacity(0.45), radius: 6, x: 0, y: 3)
    }

    private func miniCard(_ c: PFCard) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.white)
            VStack(spacing: -1) {
                Text(c.live.displayRank)
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                Text(c.live.suitSymbol)
                    .font(.system(size: 13, weight: .bold))
            }
            .foregroundStyle(c.live.isRed ? SPColors.cardRed : SPColors.cardBlack)
        }
        .frame(width: 30, height: 42)
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .stroke(Color.black.opacity(0.25), lineWidth: 0.6)
        )
        .shadow(color: .black.opacity(0.45), radius: 1.5, x: 0, y: 1)
    }

    private func rowTag(text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(color.opacity(0.15))
            )
            .overlay(
                Capsule().strokeBorder(color.opacity(0.30), lineWidth: 0.5)
            )
            .lineLimit(1)
    }

    /// Compact relative time: "now", "5m", "3h", "2d", or short date.
    private func relativeTime(_ date: Date) -> String {
        let s = -date.timeIntervalSinceNow
        if s < 60 { return "now" }
        if s < 3600 { return "\(Int(s / 60))m" }
        if s < 86400 { return "\(Int(s / 3600))h" }
        if s < 604800 { return "\(Int(s / 86400))d" }
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: date)
    }
}
