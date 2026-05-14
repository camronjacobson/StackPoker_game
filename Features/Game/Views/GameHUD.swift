import SwiftUI

// ─── Turn Timer Arc ───────────────────────────────────────────────────────────
// Displayed on the active player's seat ring.

struct TurnTimerArc: View {
    let progress: Double   // 0..1, where 1 = full time remaining
    var size: CGFloat = 52

    var body: some View {
        ZStack {
            // Track ring — ink at low opacity so it reads as a soft printed
            // outline on the cream avatar disc, not a glowing system ring.
            Circle()
                .strokeBorder(SPRetro.ink.opacity(0.18), lineWidth: 3)
                .frame(width: size, height: size)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    timerColor,
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: size, height: size)
                .animation(.linear(duration: 0.2), value: progress)
        }
    }

    private var timerColor: Color {
        if progress > 0.5 { return SPColors.success }
        if progress > 0.25 { return SPColors.warning }
        return SPColors.danger
    }
}

// ─── Street Progress Indicator ────────────────────────────────────────────────

struct StreetIndicator: View {
    let street: Street

    private let streets: [Street] = [.preflop, .flop, .turn, .river]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(streets, id: \.self) { s in
                Capsule()
                    .fill(color(for: s))
                    .frame(width: s == street ? 20 : 8, height: 4)
                    .animation(.spring(response: 0.4), value: street)
            }
        }
    }

    private func color(for s: Street) -> Color {
        if s == street { return SPColors.accent }
        let order: [Street: Int] = [.preflop:0, .flop:1, .turn:2, .river:3]
        let current = order[street] ?? 0
        let idx     = order[s]     ?? 0
        // Future streets fade to ink-soft at low opacity so the pill row
        // reads as page-printed dashes on cream, not a translucent system
        // overlay. Past streets retain the mustard accent at half intensity.
        return idx < current
            ? SPColors.accent.opacity(0.4)
            : SPRetro.ink.opacity(0.15)
    }
}

// ─── Pot Animation ────────────────────────────────────────────────────────────

struct AnimatedPotView: View {
    let amount: Int
    @State private var displayed: Int = 0

    var body: some View {
        // ChalkboardSE-Bold ink — same chip-amount idiom used on the table's
        // StackPill so animated pot numbers look like printed chip counts
        // rather than a system-rounded label.
        Text(formatChips(String(displayed)))
            .font(.custom("ChalkboardSE-Bold", size: 15))
            .foregroundStyle(SPRetro.ink)
            .contentTransition(.numericText())
            .onAppear {
                withAnimation(.easeOut(duration: 0.6)) { displayed = amount }
            }
            .onChange(of: amount) { _, newVal in
                withAnimation(.easeOut(duration: 0.4)) { displayed = newVal }
            }
    }
}

// ─── Waiting for Players View ─────────────────────────────────────────────────

struct WaitingForPlayersView: View {
    let seated:   Int
    let required: Int
    @State private var dots = ""
    @State private var timer: Timer?

    var body: some View {
        VStack(spacing: 12) {
            // Seat-fill dots — filled seats use muted teal (the retro
            // success color); empty seats are ink dots at low opacity so
            // the row reads as printed bullet points on the page.
            HStack(spacing: 6) {
                ForEach(0..<required, id: \.self) { i in
                    Circle()
                        .fill(i < seated
                              ? SPColors.success
                              : SPRetro.ink.opacity(0.2))
                        .frame(width: 10, height: 10)
                        .overlay(
                            Circle().strokeBorder(
                                SPRetro.ink.opacity(0.6),
                                lineWidth: 1
                            )
                        )
                        .scaleEffect(i < seated ? 1.2 : 1)
                        .animation(.spring(response: 0.3).delay(Double(i) * 0.05), value: seated)
                }
            }
            Text("Waiting for players\(dots)")
                .font(.custom("AmericanTypewriter-Bold", size: 14))
                .tracking(0.6)
                .foregroundStyle(SPRetro.ink.opacity(0.7))
        }
        .onAppear {
            timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
                dots = dots.count >= 3 ? "" : dots + "."
            }
        }
        .onDisappear { timer?.invalidate() }
    }
}

// ─── Hand Result Banner ───────────────────────────────────────────────────────

struct HandResultBanner: View {
    let winners: [WinnerPayout]
    let isVisible: Bool

    var body: some View {
        // Retro comic banner: paper substrate, ink panel border, hard ink
        // offset shadow (no blur), retro fonts. Winner row uses a mustard
        // crown disc with ink border so the prize reads as a stamped seal
        // on a printed result card.
        VStack(spacing: 8) {
            ForEach(Array(winners.enumerated()), id: \.element.playerId) { idx, winner in
                HStack(spacing: 10) {
                    // Trophy / crown — solid mustard disc with ink border
                    // and a tiny hard offset shadow. Same vocabulary as the
                    // lobby's burst CTAs and the +15s button.
                    ZStack {
                        Circle()
                            .fill(SPRetro.ink)
                            .frame(width: 36, height: 36)
                            .offset(x: 1.2, y: 1.5)
                        Circle()
                            .fill(SPRetro.mustard)
                            .frame(width: 36, height: 36)
                        Circle()
                            .strokeBorder(SPRetro.ink, lineWidth: 1.5)
                            .frame(width: 36, height: 36)
                        Image(systemName: winners.count > 1 ? "equal.circle.fill" : "crown.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(SPRetro.ink)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(winner.username)
                            .font(.custom("AmericanTypewriter-Bold", size: 14))
                            .foregroundStyle(SPRetro.ink)
                        Text(winner.handName)
                            .font(.custom("AmericanTypewriter", size: 11))
                            .foregroundStyle(SPRetro.inkMuted)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 1) {
                        // Prize amount — ChalkboardSE-Bold in muted teal
                        // (success); the "+" prefix kept as a typographic
                        // shorthand for the chip pickup.
                        Text("+\(formatChips(String(winner.amount)))")
                            .font(.custom("ChalkboardSE-Bold", size: 16))
                            .foregroundStyle(SPColors.success)

                        // Best hand cards (mini)
                        if winner.showCards && !winner.bestCards.isEmpty {
                            HStack(spacing: 2) {
                                ForEach(winner.bestCards.prefix(5)) { card in
                                    PlayingCardView(card: card, size: .small)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

                if idx < winners.count - 1 {
                    // Ink hairline between stacked winners — slightly heavier
                    // than the SwiftUI default Divider so it carries the same
                    // comic-panel weight as the rest of the page.
                    Rectangle()
                        .fill(SPRetro.ink.opacity(0.5))
                        .frame(height: 1)
                        .padding(.horizontal, 10)
                }
            }
        }
        .background(
            // Paper panel beneath the rows. The ink shadow below sits in
            // an outer ZStack via .background so the shadow rectangle isn't
            // clipped by the rounded paper card.
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(SPRetro.ink)
                    .offset(x: 2.5, y: 4)
                RoundedRectangle(cornerRadius: 16)
                    .fill(SPRetro.paper)
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(SPRetro.ink, lineWidth: 2)
            }
        )
        .padding(.horizontal, 20)
        .scaleEffect(isVisible ? 1 : 0.8)
        .opacity(isVisible ? 1 : 0)
        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: isVisible)
    }
}
