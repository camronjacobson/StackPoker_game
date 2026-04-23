import SwiftUI

// ─── Turn Timer Arc ───────────────────────────────────────────────────────────
// Displayed on the active player's seat ring.

struct TurnTimerArc: View {
    let progress: Double   // 0..1, where 1 = full time remaining
    var size: CGFloat = 52

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 3)
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
        return idx < current ? SPColors.accent.opacity(0.4) : Color.white.opacity(0.15)
    }
}

// ─── Pot Animation ────────────────────────────────────────────────────────────

struct AnimatedPotView: View {
    let amount: Int
    @State private var displayed: Int = 0

    var body: some View {
        Text(formatChips(String(displayed)))
            .font(.system(size: 15, weight: .bold, design: .rounded))
            .foregroundStyle(SPColors.chipGold)
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
            HStack(spacing: 6) {
                ForEach(0..<required, id: \.self) { i in
                    Circle()
                        .fill(i < seated ? SPColors.success : Color.white.opacity(0.2))
                        .frame(width: 10, height: 10)
                        .scaleEffect(i < seated ? 1.2 : 1)
                        .animation(.spring(response: 0.3).delay(Double(i) * 0.05), value: seated)
                }
            }
            Text("Waiting for players\(dots)")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
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
        VStack(spacing: 8) {
            ForEach(Array(winners.enumerated()), id: \.element.playerId) { idx, winner in
                HStack(spacing: 10) {
                    // Trophy / crown
                    ZStack {
                        Circle()
                            .fill(SPColors.chipGold.opacity(0.2))
                            .frame(width: 36, height: 36)
                        Image(systemName: winners.count > 1 ? "equal.circle.fill" : "crown.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(SPColors.chipGold)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(winner.username)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                        Text(winner.handName)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.6))
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 1) {
                        Text("+\(formatChips(String(winner.amount)))")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
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
                    Divider().background(Color.white.opacity(0.1))
                }
            }
        }
        .background(
            ZStack {
                Color.black.opacity(0.75)
                LinearGradient(
                    colors: [SPColors.chipGold.opacity(0.08), .clear],
                    startPoint: .top, endPoint: .bottom
                )
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(SPColors.chipGold.opacity(0.3), lineWidth: 1)
        )
        .shadow(color: SPColors.chipGold.opacity(0.15), radius: 20)
        .padding(.horizontal, 20)
        .scaleEffect(isVisible ? 1 : 0.8)
        .opacity(isVisible ? 1 : 0)
        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: isVisible)
    }
}
