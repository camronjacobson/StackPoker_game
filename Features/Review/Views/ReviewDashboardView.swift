import SwiftUI

// ─── Review Dashboard View ────────────────────────────────────────────────────
// PR 3 of the Review-feature overhaul.
//
// What this is:
//   The new entry point for the "Review" tab (replaces the bare
//   `HistoryListView` that used to sit at MainTabView -> .history). Acts as a
//   coach-style landing page that surfaces *signal* about how the user is
//   playing, not just a chronological log.
//
// Information architecture, top → bottom:
//   1. `statsHeroCard`       — net chips delta + trend indicator. The single
//                              most important number, sized accordingly.
//   2. `streakBadge`         — only shown when the user has a ≥2-hand same-
//                              outcome streak. Small psychological cue: hot or
//                              cold? It's optional and collapses cleanly when
//                              there's nothing interesting to say.
//   3. `miniStatsRow`        — three quick-glance tiles (Hands, Win %,
//                              Biggest Win). Designed to fit in one row on
//                              every iPhone width.
//   4. `recentHandsCarousel` — horizontally-scrolling "play card" tiles for
//                              the latest 6 hands. Different visual treatment
//                              from the list rows below so the carousel
//                              doesn't read as duplicate content.
//   5. `recentHandsList`     — the same `HandHistoryRow` rows used by
//                              `HistoryListView`, capped at 5 with a
//                              "See all" button that pushes the full list.
//
// All stats are derived from `HandHistoryStore.shared.summaries` — the cheap
// in-memory index. We never load full RecordedHand JSON on this screen
// (that's reserved for the replay push).

struct ReviewDashboardView: View {
    @ObservedObject private var store = HandHistoryStore.shared

    // Lazy-loaded full hand for the replay push. We load on tap (same pattern
    // as HistoryListView) so the dashboard stays cheap to render even with
    // hundreds of hands on disk.
    @State private var loadedHand: RecordedHand?
    @State private var pushReplay = false

    // Drives the "See all hands" → HistoryListView push.
    @State private var pushAllHands = false

    // How many tiles / rows to show on the dashboard before we hand off to the
    // full HistoryListView. Tuned to ~one screen on a regular iPhone.
    private let carouselLimit = 6
    private let listLimit     = 5

    var body: some View {
        NavigationStack {
            ZStack {
                SPColors.background.ignoresSafeArea()

                if store.summaries.isEmpty {
                    emptyState
                } else {
                    dashboard
                }

                // Hidden NavigationLinks. Same lazy-push pattern HistoryListView
                // uses — keeps the destination View construction out of the hot
                // render path until the user actually triggers it.
                NavigationLink(
                    destination: Group {
                        if let loadedHand { HandReplayView(hand: loadedHand) }
                    },
                    isActive: $pushReplay,
                    label: { EmptyView() }
                )
                .opacity(0)

                NavigationLink(
                    destination: HistoryListView(),
                    isActive: $pushAllHands,
                    label: { EmptyView() }
                )
                .opacity(0)
            }
            .navigationTitle("Review")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    // ─── Stats ───────────────────────────────────────────────────────────────

    /// Single computed view of all dashboard numbers. Derived once per render
    /// from `store.summaries`. Cheap (O(n) over the index) and pure — no I/O.
    private var stats: DashboardStats {
        DashboardStats.compute(from: store.summaries)
    }

    // ─── Sections ────────────────────────────────────────────────────────────

    private var dashboard: some View {
        ScrollView {
            LazyVStack(spacing: SPSpacing.md) {
                statsHeroCard
                streakBadge   // collapses to EmptyView when no streak ≥2
                miniStatsRow
                recentHandsCarousel
                recentHandsList
            }
            .padding(.horizontal, SPSpacing.md)
            .padding(.top, SPSpacing.sm)
            .padding(.bottom, 100) // breathing room above the tab bar
        }
    }

    // ── Hero card: net chips delta ─────────────────────────────────────────
    // Big number, trend-tinted color, arrow icon. Designed to be the first
    // thing the eye lands on when the tab opens.
    private var statsHeroCard: some View {
        let s     = stats
        let isUp  = s.netChips >= 0
        let tint  = isUp ? SPColors.success : SPColors.danger
        let arrow = isUp ? "arrow.up.right" : "arrow.down.right"

        // Retro hero card: paperShade card with ink panel border + hard
        // offset shadow (same vocab as the lobby cards). Tint comes from
        // SPColors.success/danger (already retroed to muted teal/maroon).
        return VStack(alignment: .leading, spacing: SPSpacing.sm) {
            HStack(spacing: 6) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(SPRetro.inkMuted)
                Text("ALL TIME")
                    .font(.custom("AmericanTypewriter-Bold", size: 11))
                    .foregroundStyle(SPRetro.inkMuted)
                    .tracking(1.5)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                // Sign + number. Use contentTransition so deltas animate as
                // new hands roll in via @ObservedObject. ChalkboardSE-Bold
                // matches the chip-count typography used throughout the app.
                Text("\(isUp ? "+" : "")\(formatChips(s.netChips))")
                    .font(.custom("ChalkboardSE-Bold", size: 36))
                    .foregroundStyle(tint)
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.35), value: s.netChips)

                // Ink-bordered tinted sticker disc instead of a soft tint
                // wash — matches the retro sticker vocabulary used by every
                // CTA/badge across the app.
                ZStack {
                    Circle()
                        .fill(SPRetro.ink)
                        .frame(width: 30, height: 30)
                        .offset(x: 1.5, y: 2)
                    Circle()
                        .fill(tint)
                        .frame(width: 30, height: 30)
                    Circle()
                        .strokeBorder(SPRetro.ink, lineWidth: 1.5)
                        .frame(width: 30, height: 30)
                    Image(systemName: arrow)
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(SPRetro.ink)
                }
            }

            Text(isUp ? "Net winnings across \(s.handsPlayed) hand\(s.handsPlayed == 1 ? "" : "s")"
                      : "Net losses across \(s.handsPlayed) hand\(s.handsPlayed == 1 ? "" : "s")")
                .font(.custom("AmericanTypewriter", size: 13))
                .foregroundStyle(SPRetro.inkSoft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(SPSpacing.md)
        .background(elevatedCardBackground(tint: tint))
    }

    // ── Streak badge (optional) ─────────────────────────────────────────────
    // Only renders when there's an interesting streak (≥2 same-outcome hands
    // in a row). Falls back to EmptyView so the parent VStack collapses
    // entirely on the boring case (no extra spacing, no empty pill).
    @ViewBuilder
    private var streakBadge: some View {
        let s = stats
        if s.streakCount >= 2 {
            let tint = s.streakWon ? SPColors.success : SPColors.danger
            // Retro streak pill: paperShade card with ink border + tint icon
            // + ink body copy. No translucent tint wash — flat ink/paper.
            HStack(spacing: 8) {
                Image(systemName: s.streakWon ? "flame.fill" : "snowflake")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(tint)
                Text("\(s.streakCount) \(s.streakWon ? "wins" : "losses") in a row")
                    .font(.custom("AmericanTypewriter-Bold", size: 13))
                    .foregroundStyle(SPRetro.ink)
                Spacer()
                Text(s.streakWon ? "You're hot." : "Cool off — review the leaks.")
                    .font(.custom("AmericanTypewriter", size: 11))
                    .foregroundStyle(SPRetro.inkMuted)
                    .lineLimit(1)
            }
            .padding(.horizontal, SPSpacing.md)
            .padding(.vertical, SPSpacing.sm + 2)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: SPRadius.md)
                        .fill(SPRetro.paperShade)
                    RoundedRectangle(cornerRadius: SPRadius.md)
                        .strokeBorder(SPRetro.ink, lineWidth: 1.2)
                }
            )
        } else {
            // No interesting streak — render nothing. SwiftUI's VStack
            // collapses around EmptyView siblings without leaving extra
            // spacing, so the surrounding cards close up cleanly.
            EmptyView()
        }
    }

    // ── Mini stats row ──────────────────────────────────────────────────────
    private var miniStatsRow: some View {
        let s = stats
        // We pick three numbers that are quick to grok and don't repeat the
        // headline (`netChips`). Win % is the most-asked stat in coaching
        // tools; biggest win is a small dopamine hit; hands count is context.
        return HStack(spacing: SPSpacing.sm) {
            MiniStat(
                label: "Hands",
                value: "\(s.handsPlayed)",
                icon:  "rectangle.stack.fill",
                tint:  SPColors.info
            )
            MiniStat(
                label: "Win %",
                value: "\(Int(s.winRate * 100))%",
                icon:  "trophy.fill",
                tint:  s.winRate >= 0.5 ? SPColors.success : SPColors.warning
            )
            MiniStat(
                label: "Biggest Win",
                value: s.biggestWin > 0 ? "+\(formatChips(s.biggestWin))" : "—",
                icon:  "star.fill",
                tint:  SPColors.chipGold
            )
        }
    }

    // ── Recent hands carousel ───────────────────────────────────────────────
    // Horizontal strip of "play card" tiles. Visually distinct from the list
    // rows so the section reads as "recent highlights" rather than duplicate
    // content. Tap pushes the replay just like the list rows do.
    private var recentHandsCarousel: some View {
        VStack(alignment: .leading, spacing: SPSpacing.sm) {
            sectionHeader(title: "Recent hands", showSeeAll: false)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: SPSpacing.sm) {
                    ForEach(store.summaries.prefix(carouselLimit)) { summary in
                        Button {
                            openReplay(for: summary)
                        } label: {
                            RecentHandCard(summary: summary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                // Bleed the cards out to the screen edges by negating the
                // parent horizontal padding, then re-add internal padding.
                // Looks like a magazine carousel rather than a clipped list.
                .padding(.horizontal, SPSpacing.md)
            }
            .padding(.horizontal, -SPSpacing.md)
        }
    }

    // ── Recent hands list (compact, capped, "See all" → HistoryListView) ────
    private var recentHandsList: some View {
        VStack(alignment: .leading, spacing: SPSpacing.sm) {
            sectionHeader(
                title: "All hands",
                showSeeAll: store.summaries.count > listLimit,
                onSeeAll: { pushAllHands = true }
            )

            VStack(spacing: SPSpacing.sm) {
                ForEach(store.summaries.prefix(listLimit)) { summary in
                    Button {
                        openReplay(for: summary)
                    } label: {
                        // Reuse the existing row component from
                        // HistoryListView so styling stays in lockstep.
                        HandHistoryRow(summary: summary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // ─── Helpers ─────────────────────────────────────────────────────────────

    /// Common section header with a title on the left and an optional "See
    /// all" button on the right. Centralized so spacing/typography stays
    /// consistent across sections.
    private func sectionHeader(
        title: String,
        showSeeAll: Bool,
        onSeeAll: (() -> Void)? = nil
    ) -> some View {
        HStack {
            Text(title)
                .font(.custom("AmericanTypewriter-Bold", size: 15))
                .foregroundStyle(SPRetro.ink)
            Spacer()
            if showSeeAll, let onSeeAll {
                Button(action: onSeeAll) {
                    HStack(spacing: 3) {
                        Text("See all")
                            .font(.custom("AmericanTypewriter-Bold", size: 12))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(SPRetro.mustardDark)
                }
            }
        }
    }

    /// Lazily load the full RecordedHand and trigger the replay push. Pulled
    /// out so the carousel and list call sites stay one-liners.
    private func openReplay(for summary: RecordedHandSummary) {
        guard let hand = store.loadHand(id: summary.id) else { return }
        loadedHand = hand
        pushReplay = true
    }

    /// Retro hero-card background: paperShade card with a hard ink panel
    /// border and a 2.5pt ink offset shadow — the same vocabulary used by
    /// every elevated card and primary CTA across the app, so the dashboard
    /// reads as one printed-magazine system instead of a different screen.
    /// `tint` is intentionally unused at the background level now; the
    /// verdict color lives on the headline number and the arrow disc.
    private func elevatedCardBackground(tint: Color) -> some View {
        _ = tint
        return ZStack {
            RoundedRectangle(cornerRadius: SPRadius.md)
                .fill(SPRetro.ink)
                .offset(x: 2, y: 3)
            RoundedRectangle(cornerRadius: SPRadius.md)
                .fill(SPRetro.paperShade)
            RoundedRectangle(cornerRadius: SPRadius.md)
                .strokeBorder(SPRetro.ink, lineWidth: 2)
        }
    }

    // ─── Empty state ─────────────────────────────────────────────────────────

    private var emptyState: some View {
        // Retro empty state: mustard sparkles + ink title + ink-soft body.
        // Sits directly on the paper substrate (no card) so it reads as a
        // friendly hand-written note rather than another panel.
        VStack(spacing: SPSpacing.md) {
            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundStyle(SPRetro.mustardDark)
            Text("Your coach is waiting")
                .font(.custom("AmericanTypewriter-Bold", size: 18))
                .foregroundStyle(SPRetro.ink)
            Text("Play a hand and we'll start tracking your stats, streaks, and biggest pots.")
                .font(.custom("AmericanTypewriter", size: 13))
                .foregroundStyle(SPRetro.inkMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, SPSpacing.xl)
        }
    }
}

// ─── Stats model ─────────────────────────────────────────────────────────────
// Pure data + pure computation. Lives next to ReviewDashboardView because no
// other screen needs these aggregates yet. If/when PR 4 (filters) lands and
// PR 6 (leaks tab) needs the same numbers, promote this to its own file.

private struct DashboardStats {
    let netChips:    Int
    let handsPlayed: Int
    let winRate:     Double  // 0...1
    let biggestWin:  Int     // best single-hand stackDelta, ≥0 (0 if no wins)
    let streakCount: Int     // length of the current same-outcome run
    let streakWon:   Bool    // direction of that run (matches summaries[0].iWon)

    /// Compute every dashboard number in a single pass. Keeps the body of
    /// `ReviewDashboardView.stats` cheap and unit-testable in isolation.
    static func compute(from summaries: [RecordedHandSummary]) -> DashboardStats {
        guard let head = summaries.first else {
            return DashboardStats(netChips: 0, handsPlayed: 0, winRate: 0,
                                  biggestWin: 0, streakCount: 0, streakWon: false)
        }

        var net = 0
        var wins = 0
        var biggest = 0
        for s in summaries {
            net += s.stackDelta
            if s.iWon { wins += 1 }
            // We deliberately track the biggest *won* delta, not the biggest
            // absolute swing — losing a stack isn't a "biggest win".
            if s.iWon, s.stackDelta > biggest { biggest = s.stackDelta }
        }

        // Current streak: walk newest → older while iWon matches the head.
        // summaries are pre-sorted newest-first by HandHistoryStore.
        let direction = head.iWon
        var streak = 0
        for s in summaries {
            if s.iWon == direction { streak += 1 } else { break }
        }

        let rate = summaries.isEmpty ? 0 : Double(wins) / Double(summaries.count)
        return DashboardStats(
            netChips:    net,
            handsPlayed: summaries.count,
            winRate:     rate,
            biggestWin:  biggest,
            streakCount: streak,
            streakWon:   direction
        )
    }
}

// ─── Mini-stat tile ──────────────────────────────────────────────────────────
// Reusable square-ish tile for the three quick-glance metrics. Equal-width
// because the parent HStack uses `frame(maxWidth: .infinity)` on each tile.

private struct MiniStat: View {
    let label: String
    let value: String
    let icon:  String
    let tint:  Color

    var body: some View {
        // Retro mini-stat tile: paperShade card with ink panel border and
        // small ink offset shadow — same sticker vocabulary as the lobby
        // mini cards. AmericanTypewriter-Bold label + ChalkboardSE-Bold
        // value so the number reads like a chip count.
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(tint)
                Text(label.uppercased())
                    .font(.custom("AmericanTypewriter-Bold", size: 10))
                    .foregroundStyle(SPRetro.inkMuted)
                    .tracking(1.0)
            }
            Text(value)
                .font(.custom("ChalkboardSE-Bold", size: 18))
                .foregroundStyle(SPRetro.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, SPSpacing.sm + 2)
        .padding(.vertical, SPSpacing.sm + 2)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: SPRadius.md)
                    .fill(SPRetro.ink)
                    .offset(x: 1.5, y: 2)
                RoundedRectangle(cornerRadius: SPRadius.md)
                    .fill(SPRetro.paperShade)
                RoundedRectangle(cornerRadius: SPRadius.md)
                    .strokeBorder(SPRetro.ink, lineWidth: 1.2)
            }
        )
    }
}

// ─── Recent hand card (carousel tile) ────────────────────────────────────────
// Vertical card composition for the horizontal carousel. Different shape and
// emphasis than HandHistoryRow on purpose — the carousel is for skim/scrub,
// the list is for scan/select. Width is fixed so multiple tiles peek into
// view and signal "scroll for more" without an explicit chevron.

private struct RecentHandCard: View {
    let summary: RecordedHandSummary

    var body: some View {
        VStack(alignment: .leading, spacing: SPSpacing.sm) {
            // Top row: hole cards (fanned) + W/L badge in the corner.
            ZStack(alignment: .topTrailing) {
                HStack(spacing: -10) {
                    if summary.myHoleCards.indices.contains(0) {
                        bigCard(summary.myHoleCards[0])
                            .rotationEffect(.degrees(-6))
                    }
                    if summary.myHoleCards.indices.contains(1) {
                        bigCard(summary.myHoleCards[1])
                            .rotationEffect(.degrees(6))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 6)

                Image(systemName: summary.iWon
                      ? "checkmark.seal.fill"
                      : "xmark.seal.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(summary.iWon ? SPColors.success : SPColors.danger)
            }
            .frame(height: 58)

            // Bottom: hand name (if any) + delta. Delta is the focal point.
            VStack(alignment: .leading, spacing: 2) {
                Text(summary.winningHandName ?? "Hand #\(summary.handNumber)")
                    .font(.custom("AmericanTypewriter-Bold", size: 11))
                    .foregroundStyle(SPRetro.inkMuted)
                    .lineLimit(1)

                Text(summary.iWon
                     ? "+\(formatChips(summary.stackDelta))"
                     : formatChips(summary.stackDelta))
                    .font(.custom("ChalkboardSE-Bold", size: 16))
                    .foregroundStyle(summary.iWon ? SPColors.success : SPColors.danger)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .padding(SPSpacing.sm + 2)
        .frame(width: 140, height: 130, alignment: .topLeading)
        .background(
            // Retro recent-hand tile: paperShade card with ink border +
            // hard ink offset shadow — matches the magazine/print look of
            // every other elevated tile in the app.
            ZStack {
                RoundedRectangle(cornerRadius: SPRadius.md)
                    .fill(SPRetro.ink)
                    .offset(x: 1.5, y: 2.5)
                RoundedRectangle(cornerRadius: SPRadius.md)
                    .fill(SPRetro.paperShade)
                RoundedRectangle(cornerRadius: SPRadius.md)
                    .strokeBorder(SPRetro.ink, lineWidth: 1.5)
            }
        )
    }

    /// Carousel-card-sized hole-card glyph. Larger than the list row's mini
    /// cards because the carousel is the "highlight" surface and the cards
    /// are its center of gravity. Retro: paper face + ink hairline border,
    /// no soft shadow — flat printed-card look.
    private func bigCard(_ c: PFCard) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(SPRetro.paper)
            VStack(spacing: -2) {
                Text(c.live.displayRank)
                    .font(.custom("ChalkboardSE-Bold", size: 20))
                Text(c.live.suitSymbol)
                    .font(.system(size: 16, weight: .bold))
            }
            .foregroundStyle(c.live.isRed ? SPColors.cardRed : SPColors.cardBlack)
        }
        .frame(width: 38, height: 52)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(SPRetro.ink, lineWidth: 1)
        )
    }
}
