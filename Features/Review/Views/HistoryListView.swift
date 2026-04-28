import SwiftUI

// ─── History List View ────────────────────────────────────────────────────────
// The "History" tab content. Lists every recorded hand newest-first; tapping
// one pushes the full HandReplayView. Empty state explains how hands get
// recorded.

struct HistoryListView: View {
    @ObservedObject private var store = HandHistoryStore.shared
    @State private var selectedHandId: String?
    @State private var loadedHand: RecordedHand?
    @State private var pushReplay = false

    var body: some View {
        NavigationStack {
            ZStack {
                SPColors.background.ignoresSafeArea()

                if store.summaries.isEmpty {
                    emptyState
                } else {
                    list
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

    // ─── List ────────────────────────────────────────────────────────────────

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: SPSpacing.sm) {
                ForEach(store.summaries) { summary in
                    Button {
                        if let hand = store.loadHand(id: summary.id) {
                            loadedHand = hand
                            selectedHandId = summary.id
                            pushReplay = true
                        }
                    } label: {
                        HandHistoryRow(summary: summary)
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
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

    // ─── Empty state ─────────────────────────────────────────────────────────

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
}

// ─── History Row ──────────────────────────────────────────────────────────────

struct HandHistoryRow: View {
    let summary: RecordedHandSummary

    var body: some View {
        HStack(spacing: SPSpacing.md) {
            // Hole cards
            HStack(spacing: 3) {
                ForEach(summary.myHoleCards, id: \.id) { c in
                    miniCard(c)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(summary.tableName)
                    .font(SPFonts.headline(14))
                    .foregroundStyle(SPColors.textPrimary)
                    .lineLimit(1)
                Text("\(summary.opponentCount + 1) players · \(relativeTime(summary.endedAt))")
                    .font(SPFonts.caption(11))
                    .foregroundStyle(SPColors.textSecondary)
                if let name = summary.winningHandName {
                    Text(summary.iWon ? "Won with \(name)" : "Lost to \(name)")
                        .font(SPFonts.caption(11))
                        .foregroundStyle(summary.iWon ? SPColors.success : SPColors.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 2) {
                Text(summary.iWon
                     ? "+\(formatChips(summary.stackDelta))"
                     : formatChips(summary.stackDelta))
                    .font(SPFonts.chips(15))
                    .foregroundStyle(summary.iWon ? SPColors.success : SPColors.danger)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(SPColors.textTertiary)
            }
        }
        .padding(SPSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: SPRadius.md)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "#1A2744"), Color(hex: "#0D1525")],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: SPRadius.md)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private func miniCard(_ c: PFCard) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4).fill(Color.white)
            VStack(spacing: -1) {
                Text(c.live.displayRank)
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                Text(c.live.suitSymbol)
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(c.live.isRed ? SPColors.cardRed : SPColors.cardBlack)
        }
        .frame(width: 22, height: 30)
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
