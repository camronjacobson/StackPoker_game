import SwiftUI

// ─── Poker Table View ─────────────────────────────────────────────────────────
// Pure Poker-style layout: tall pill-shaped blue felt table, flat (no 3D tilt),
// seats positioned around the rim, chip stacks between seats and pot.

// ─── Table Layout ─────────────────────────────────────────────────────────────

struct TableLayout {
    let size: CGSize
    let isLandscape: Bool

    // Felt dimensions — tall vertical pill (taller than wide) in portrait,
    // classic landscape oval when the device is rotated.
    var tableWidth: CGFloat {
        if isLandscape { return min(size.width - 48, size.height * 1.6) }
        // Portrait: pill is narrow relative to screen width so it reads as
        // tall, not wide.
        return min(size.width * 0.72, size.height * 0.42)
    }
    var tableHeight: CGFloat {
        if isLandscape { return tableWidth / 1.6 }
        // Vertically stretched — ~1.65 × width, capped to ~72% of screen height.
        return min(size.height * 0.72, tableWidth * 1.65)
    }
    // Pill shape — radius = half of the shorter side (width in portrait).
    var tableCornerRadius: CGFloat {
        min(tableWidth, tableHeight) / 2
    }
    var tableCenter: CGPoint {
        CGPoint(x: size.width / 2, y: size.height * 0.46)
    }
    var tableRect: CGRect {
        CGRect(
            x: tableCenter.x - tableWidth / 2,
            y: tableCenter.y - tableHeight / 2,
            width: tableWidth,
            height: tableHeight
        )
    }

    // Community cards
    var cardWidth: CGFloat { tableWidth * 0.10 }
    var cardSpacing: CGFloat { tableWidth * 0.016 }

    // Center layout positions (all relative to tableCenter).
    // Tuned for the tall pill felt: community cards high, pot stack sits
    // directly below the cards, then NLH/Blinds/Hosted by stack toward the
    // bottom. Watermark is tucked at the very bottom so it doesn't compete.
    var boardCenter: CGPoint {
        CGPoint(x: tableCenter.x, y: tableCenter.y - tableHeight * 0.12)
    }
    var potCenter: CGPoint {
        CGPoint(x: tableCenter.x, y: tableCenter.y + tableHeight * 0.04)
    }
    var gamePillCenter: CGPoint {
        CGPoint(x: tableCenter.x, y: tableCenter.y + tableHeight * 0.19)
    }
    var blindsCenter: CGPoint {
        CGPoint(x: tableCenter.x, y: tableCenter.y + tableHeight * 0.26)
    }
    var hostedByCenter: CGPoint {
        CGPoint(x: tableCenter.x, y: tableCenter.y + tableHeight * 0.34)
    }
    var brandCenter: CGPoint {
        CGPoint(x: tableCenter.x, y: tableCenter.y + tableHeight * 0.40)
    }

    // Seats
    var seatAvatarSize: CGFloat { isLandscape ? 52 : 56 }

    func seatPositions(count: Int) -> [CGPoint] {
        let cx = tableCenter.x
        let cy = tableCenter.y
        let rx = tableWidth / 2 + 8
        let ry = tableHeight / 2 + 20

        // Fixed angle slots — local player at bottom (270 degrees = bottom in standard math)
        // But we use 90 = bottom visually
        let angles: [Double] = {
            switch count {
            case 2: return [90, 270]
            case 3: return [90, 210, 330]
            case 4: return [90, 180, 270, 0]
            case 5: return [90, 162, 234, 306, 18]
            case 6: return [90, 150, 210, 270, 330, 30]
            case 7: return [90, 141, 193, 244, 296, 347, 38]
            case 8: return [90, 129, 168, 207, 270, 333, 12, 51]
            case 9: return [90, 130, 170, 210, 250, 290, 330, 10, 50]
            default: return [90, 270]
            }
        }()
        return angles.map { deg in
            let rad = deg * .pi / 180
            return CGPoint(x: cx + rx * cos(rad), y: cy + ry * sin(rad))
        }
    }
}

// ─── PokerTableView ───────────────────────────────────────────────────────────

struct PokerTableView: View {
    let seats:       [GameSeat]
    let maxSeats:    Int
    @ObservedObject var vm: GameViewModel
    var isLandscape: Bool = false

    // Felt theme — read from user settings. Defaults to classic blue. Changes
    // in the settings sheet propagate here live via @AppStorage.
    @AppStorage("tableThemeId") private var tableThemeId: String = "classic_blue"
    private var theme: TableTheme { TableTheme.find(tableThemeId) }

    var body: some View {
        GeometryReader { geo in
            let layout = TableLayout(size: geo.size, isLandscape: isLandscape)

            ZStack {
                // ── Table layer (flat, no 3D tilt)
                feltOval(layout)
                brandMark(layout)
                potCluster(layout)
                communityBoard(layout)
                gamePill(layout)
                blindsLabel(layout)
                hostedByLabel(layout)
                dealerRailButton(layout)
                betChipsLayer(layout)
                potFlowLayer(layout)

                // ── Seat overlay
                seatOverlay(layout)
            }
            .animation(.easeInOut(duration: 0.3), value: vm.gameState?.communityCards.count)
            .animation(.easeInOut(duration: 0.3), value: vm.gameState?.totalPot)
            .animation(.spring(response: 0.5, dampingFraction: 0.82), value: betsSignature)
        }
    }

    private var betsSignature: String {
        seats.map { "\($0.userId):\($0.betThisStreet)" }.joined(separator: "|")
    }

    // ─── Felt + rail ──────────────────────────────────────────────────────────

    private func feltOval(_ l: TableLayout) -> some View {
        let cr = l.tableCornerRadius
        return ZStack {
            // Soft outer glow
            RoundedRectangle(cornerRadius: cr + 6)
                .fill(Color.clear)
                .frame(width: l.tableWidth + 12, height: l.tableHeight + 12)
                .shadow(color: Color(hex: "#1A3A6B").opacity(0.5), radius: 30)

            // Felt base — themed radial gradient
            RoundedRectangle(cornerRadius: cr)
                .fill(
                    RadialGradient(
                        colors: [
                            Color(hex: theme.inner),
                            Color(hex: theme.mid),
                            Color(hex: theme.edge),
                        ],
                        center: UnitPoint(x: 0.5, y: 0.45),
                        startRadius: l.tableWidth * 0.05,
                        endRadius: l.tableWidth * 0.65
                    )
                )
                .frame(width: l.tableWidth, height: l.tableHeight)
                .overlay(
                    ZStack {
                        // Inner rail line
                        RoundedRectangle(cornerRadius: cr - 14)
                            .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
                            .frame(width: l.tableWidth - 28, height: l.tableHeight - 28)

                        // Soft upper sheen
                        RoundedRectangle(cornerRadius: cr)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.06),
                                        Color.white.opacity(0.01),
                                        Color.clear
                                    ],
                                    startPoint: .top,
                                    endPoint: .center
                                )
                            )
                            .frame(width: l.tableWidth, height: l.tableHeight)
                            .blendMode(.plusLighter)

                        // Vignette
                        RoundedRectangle(cornerRadius: cr)
                            .fill(
                                RadialGradient(
                                    colors: [Color.clear, Color.black.opacity(0.15)],
                                    center: .center,
                                    startRadius: l.tableWidth * 0.30,
                                    endRadius: l.tableWidth * 0.60
                                )
                            )
                            .frame(width: l.tableWidth, height: l.tableHeight)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: cr))
                    .allowsHitTesting(false)
                )

            // Outer rail stroke
            RoundedRectangle(cornerRadius: cr)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.20), Color.white.opacity(0.08)],
                        startPoint: .top, endPoint: .bottom
                    ),
                    lineWidth: 2.5
                )
                .frame(width: l.tableWidth, height: l.tableHeight)
        }
        .position(x: l.tableCenter.x, y: l.tableCenter.y)
    }

    // ─── StackPoker watermark ────────────────────────────────────────────────

    private func brandMark(_ l: TableLayout) -> some View {
        Text("StackPoker")
            .font(.system(size: min(l.tableWidth * 0.11, 42), weight: .heavy, design: .rounded))
            .foregroundStyle(Color.white.opacity(0.05))
            .kerning(2)
            .position(x: l.brandCenter.x, y: l.brandCenter.y)
    }

    // ─── Pot cluster ─────────────────────────────────────────────────────────

    @ViewBuilder
    private func potCluster(_ l: TableLayout) -> some View {
        if let state = vm.gameState, state.totalPot > 0 {
            PotChipStack(amount: state.totalPot)
                .position(x: l.potCenter.x, y: l.potCenter.y)
                .transition(.scale(scale: 0.7).combined(with: .opacity))
                .id(ChipTier.forAmount(state.totalPot))
        }
    }

    // ─── Community board ──────────────────────────────────────────────────────

    private func communityBoard(_ l: TableLayout) -> some View {
        CommunityCardsView(
            cards:        vm.gameState?.communityCards ?? [],
            winnersCards: winnerCardIds,
            cardWidth:    l.cardWidth,
            cardSpacing:  l.cardSpacing,
            colored:      true
        )
        .position(x: l.boardCenter.x, y: l.boardCenter.y)
    }

    // ─── Game type pill ──────────────────────────────────────────────────────

    private func gamePill(_ l: TableLayout) -> some View {
        let label = (vm.gameState?.gameType ?? "TEXAS_HOLDEM") == "PLO" ? "PLO" : "NLH"
        return Text(label)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white.opacity(0.7))
            .tracking(1.2)
            .padding(.horizontal, 16)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.08))
            .clipShape(Capsule())
            .position(x: l.gamePillCenter.x, y: l.gamePillCenter.y)
    }

    // ─── Blinds label ────────────────────────────────────────────────────────

    @ViewBuilder
    private func blindsLabel(_ l: TableLayout) -> some View {
        if let state = vm.gameState {
            Text("Blinds: \(formatChips(String(state.smallBlind)))/\(formatChips(String(state.bigBlind)))")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.35))
                .position(x: l.blindsCenter.x, y: l.blindsCenter.y)
        }
    }

    // ─── "Hosted by" label ───────────────────────────────────────────────────

    private func hostedByLabel(_ l: TableLayout) -> some View {
        VStack(spacing: 3) {
            Text("Hosted by")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.25))
            HStack(spacing: 5) {
                Circle()
                    .fill(Color.white.opacity(0.15))
                    .frame(width: 14, height: 14)
                Text("StackPoker")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.35))
            }
        }
        .position(x: l.hostedByCenter.x, y: l.hostedByCenter.y)
    }

    // ─── Dealer "D" button ───────────────────────────────────────────────────

    @ViewBuilder
    private func dealerRailButton(_ l: TableLayout) -> some View {
        if let dealerIdx = dealerDisplayIndex {
            let positions = l.seatPositions(count: maxSeats)
            if dealerIdx < positions.count {
                let seatPt = positions[dealerIdx]
                let dx = l.tableCenter.x - seatPt.x
                let dy = l.tableCenter.y - seatPt.y
                let bx = seatPt.x + dx * 0.50
                let by = seatPt.y + dy * 0.50

                Text("D")
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(
                        Circle()
                            .fill(Color(hex: "#4A90E2"))
                    )
                    .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
                    .position(x: bx, y: by)
            }
        }
    }

    private var dealerDisplayIndex: Int? {
        seats.firstIndex(where: { $0.isDealer })
    }

    // ─── Pot flow layer ──────────────────────────────────────────────────────

    @ViewBuilder
    private func potFlowLayer(_ l: TableLayout) -> some View {
        if let winners = vm.gameState?.winners, !winners.isEmpty {
            let positions = l.seatPositions(count: maxSeats)
            ForEach(winners, id: \.playerId) { winner in
                if let idx = seats.firstIndex(where: { $0.userId == winner.playerId }),
                   idx < positions.count {
                    PotFlowChip(
                        from:   l.potCenter,
                        to:     positions[idx],
                        amount: winner.amount
                    )
                }
            }
        }
    }

    // ─── Bet chip layer ──────────────────────────────────────────────────────

    @ViewBuilder
    private func betChipsLayer(_ l: TableLayout) -> some View {
        let positions = l.seatPositions(count: maxSeats)
        ZStack {
            ForEach(Array(seats.enumerated()), id: \.element.userId) { idx, seat in
                if idx < positions.count && seat.betThisStreet > 0 {
                    let seatPt = positions[idx]
                    let bx = seatPt.x + (l.tableCenter.x - seatPt.x) * 0.40
                    let by = seatPt.y + (l.tableCenter.y - seatPt.y) * 0.40
                    let dx = l.potCenter.x - bx
                    let dy = l.potCenter.y - by
                    BetChipBadge(amount: seat.betThisStreet)
                        .position(x: bx, y: by)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.35).combined(with: .opacity),
                            removal: .offset(x: dx, y: dy).combined(with: .opacity)
                        ))
                }
            }
        }
    }

    // ─── Seat overlay (flat) ─────────────────────────────────────────────────

    private func seatOverlay(_ l: TableLayout) -> some View {
        let positions = l.seatPositions(count: maxSeats)
        return ForEach(0..<maxSeats, id: \.self) { idx in
            Group {
                if idx < seats.count {
                    let seat = seats[idx]
                    let isMe = (idx == 0)
                    let isActive = vm.gameState?.activePlayerId == seat.userId
                    let isWinner = winnerIds.contains(seat.userId)
                    TargetSeatView(
                        seat: seat,
                        isMe: isMe,
                        isMyTurn: isActive,
                        isWinner: isWinner,
                        turnProgress: isActive ? vm.turnTimeRemaining : 1.0,
                        turnSecondsLeft: isActive ? vm.turnSecondsLeft : 0,
                        lastAction: vm.gameState?.lastAction,
                        avatarSize: l.seatAvatarSize
                    )
                    .position(x: positions[idx].x, y: positions[idx].y)
                    .zIndex(isWinner ? 20 : (isActive ? 10 : 1))
                } else {
                    TargetEmptySeat(avatarSize: l.seatAvatarSize)
                        .position(x: positions[idx].x, y: positions[idx].y)
                }
            }
        }
    }

    private var winnerCardIds: Set<String> {
        guard let winners = vm.gameState?.winners else { return [] }
        return Set(winners.flatMap { $0.bestCards.map { $0.id } })
    }

    private var winnerIds: Set<String> {
        guard let winners = vm.gameState?.winners else { return [] }
        return Set(winners.map { $0.playerId })
    }
}

// ─── Chip Color Tiers ────────────────────────────────────────────────────────

enum ChipTier {
    case white, red, blue, black, purple, gold

    static func forAmount(_ amount: Int) -> ChipTier {
        switch amount {
        case ..<100:       return .white
        case 100..<500:    return .red
        case 500..<1000:   return .blue
        case 1000..<5000:  return .black
        case 5000..<25000: return .purple
        default:           return .gold
        }
    }

    var colors: (primary: Color, secondary: Color, edge: Color) {
        switch self {
        case .white:  return (Color(hex: "#E8E8E8"), Color(hex: "#C0C0C0"), Color(hex: "#AAAAAA"))
        case .red:    return (Color(hex: "#E05555"), Color(hex: "#B83A3A"), Color(hex: "#8B2020"))
        case .blue:   return (Color(hex: "#4A90E2"), Color(hex: "#2D6CC0"), Color(hex: "#1A4F8F"))
        case .black:  return (Color(hex: "#3A3A3A"), Color(hex: "#222222"), Color(hex: "#111111"))
        case .purple: return (Color(hex: "#8B5CF6"), Color(hex: "#6C3CD8"), Color(hex: "#4A2B9E"))
        case .gold:   return (Color(hex: "#F5C842"), Color(hex: "#D4A520"), Color(hex: "#B8860B"))
        }
    }
}

private func pokerChipIcon(diameter: CGFloat, amount: Int = 0) -> some View {
    let tier = ChipTier.forAmount(amount)
    let c = tier.colors
    return ZStack {
        Circle()
            .fill(
                LinearGradient(
                    colors: [c.primary, c.secondary],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            )
        Circle()
            .strokeBorder(Color.white.opacity(0.5), lineWidth: 1)
        Circle()
            .strokeBorder(c.edge, style: StrokeStyle(lineWidth: 1.5, dash: [2, 2]))
            .padding(diameter * 0.18)
    }
    .frame(width: diameter, height: diameter)
    .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
}

// ─── Pot Flow Chip ───────────────────────────────────────────────────────────

private struct PotFlowChip: View {
    let from:   CGPoint
    let to:     CGPoint
    let amount: Int

    @State private var progress: CGFloat = 0
    @State private var opacity:  Double = 0

    private var currentPos: CGPoint {
        CGPoint(
            x: from.x + (to.x - from.x) * progress,
            y: from.y + (to.y - from.y) * progress
        )
    }

    var body: some View {
        HStack(spacing: 4) {
            pokerChipIcon(diameter: 14, amount: amount)
            Text("+\(formatChips(String(amount)))")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Color(hex: "#F5C842"))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.black.opacity(0.6))
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(Color(hex: "#F5C842").opacity(0.6), lineWidth: 1))
        .shadow(color: Color(hex: "#F5C842").opacity(0.5), radius: 6)
        .position(currentPos)
        .opacity(opacity)
        .onAppear {
            withAnimation(.easeOut(duration: 0.15)) { opacity = 1 }
            withAnimation(.easeInOut(duration: 0.75).delay(0.1)) { progress = 1 }
            withAnimation(.easeIn(duration: 0.25).delay(0.65)) { opacity = 0 }
        }
    }
}

// ─── Bet chip badge ──────────────────────────────────────────────────────────
// Mini chip stack shown in front of each seat between the seat and the pot,
// scaled by amount so raises look physically heavier than calls. The stack
// renders 1..6 chips of the amount's tier color with overlapping circles to
// read as a short stack of ceramic chips on the felt.

private struct BetChipBadge: View {
    let amount: Int

    private var chipCount: Int {
        // Visual chip count grows with amount but caps to keep the stack
        // compact. Tuned so min-raises look like a short stack and all-ins
        // look like a tall one.
        switch amount {
        case ..<50:         return 1
        case 50..<200:      return 2
        case 200..<1_000:   return 3
        case 1_000..<5_000: return 4
        case 5_000..<25_000: return 5
        default:            return 6
        }
    }

    private let chipDiameter: CGFloat = 14
    private let stackStep:    CGFloat = 3   // y-offset between stacked chips

    var body: some View {
        VStack(spacing: 3) {
            ZStack(alignment: .bottom) {
                // Base shadow under the stack to anchor it to the felt.
                Ellipse()
                    .fill(Color.black.opacity(0.35))
                    .frame(width: chipDiameter * 1.1, height: 3)
                    .offset(y: 1)

                ForEach(0..<chipCount, id: \.self) { i in
                    pokerChipIcon(diameter: chipDiameter, amount: amount)
                        // Stack up from the bottom; topmost chip is the
                        // "face" of the bet.
                        .offset(y: -CGFloat(i) * stackStep)
                }
            }
            // Height accounts for stacked chips so text sits below the stack
            .frame(height: chipDiameter + CGFloat(chipCount - 1) * stackStep)

            Text(formatChips(String(amount)))
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Color.black.opacity(0.55))
                .clipShape(Capsule())
                .contentTransition(.numericText())
        }
    }
}

// ─── Pot chip stack ──────────────────────────────────────────────────────────
// Main pot visualization — taller stack of chips sitting below the community
// cards, colored by the pot-size tier (white → red → blue → black → purple →
// gold). Amount pill sits beneath the stack.

private struct PotChipStack: View {
    let amount: Int

    private var chipCount: Int {
        // Pot stack is more generous than per-seat bet stacks. Caps at 10 so
        // it never overflows the felt.
        switch amount {
        case ..<200:          return 3
        case 200..<1_000:     return 4
        case 1_000..<5_000:   return 6
        case 5_000..<25_000:  return 8
        case 25_000..<100_000: return 9
        default:              return 10
        }
    }

    private let chipDiameter: CGFloat = 22
    private let stackStep:    CGFloat = 4

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .bottom) {
                // Cast shadow under the stack.
                Ellipse()
                    .fill(Color.black.opacity(0.45))
                    .frame(width: chipDiameter * 1.2, height: 5)
                    .offset(y: 2)
                    .blur(radius: 1)

                ForEach(0..<chipCount, id: \.self) { i in
                    pokerChipIcon(diameter: chipDiameter, amount: amount)
                        .offset(y: -CGFloat(i) * stackStep)
                        // Top chip catches a slight highlight to sell the
                        // 3D illusion without doing actual 3D.
                        .overlay(
                            i == chipCount - 1
                                ? Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.white.opacity(0.15), .clear],
                                            startPoint: .top, endPoint: .center
                                        )
                                    )
                                    .frame(width: chipDiameter, height: chipDiameter)
                                    .offset(y: -CGFloat(i) * stackStep)
                                    .allowsHitTesting(false)
                                : nil
                        )
                }
            }
            .frame(height: chipDiameter + CGFloat(chipCount - 1) * stackStep + 4)

            VStack(spacing: 1) {
                Text("Pot")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .tracking(0.8)
                Text(formatChips(String(amount)))
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(ChipTier.forAmount(amount).colors.primary)
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 3)
            .background(Color.black.opacity(0.45))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        ChipTier.forAmount(amount).colors.primary.opacity(0.35),
                        lineWidth: 0.5
                    )
            )
        }
    }
}

// ─── Target-style seat ───────────────────────────────────────────────────────

struct TargetSeatView: View {
    let seat:         GameSeat
    let isMe:         Bool
    let isMyTurn:     Bool
    var isWinner:     Bool = false
    let turnProgress: Double
    var turnSecondsLeft: Int = 0
    var lastAction:   LastAction?
    let avatarSize:   CGFloat

    @State private var allInPulse = false
    @State private var winnerPulse = false

    private var plateWidth: CGFloat { avatarSize * 1.55 }

    var body: some View {
        VStack(spacing: 0) {
            // Folded label above avatar
            if seat.status == .folded {
                Text("Folded")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color(hex: "#E8A838"))
                    .padding(.bottom, 3)
            } else if let action = lastAction,
                      action.playerId == seat.userId,
                      let kind = actionBubbleKind(for: action.action) {
                Text(kind.label)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(kind.color)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                    .padding(.bottom, 3)
                    .transition(.scale.combined(with: .opacity))
            }

            ZStack {
                // Winner glow
                if isWinner {
                    Circle()
                        .strokeBorder(
                            Color(hex: "#F5C842"),
                            lineWidth: winnerPulse ? 4 : 2
                        )
                        .frame(
                            width:  avatarSize + (winnerPulse ? 16 : 8),
                            height: avatarSize + (winnerPulse ? 16 : 8)
                        )
                        .shadow(
                            color: Color(hex: "#F5C842").opacity(winnerPulse ? 0.8 : 0.3),
                            radius: winnerPulse ? 16 : 4
                        )
                }

                // Turn timer ring
                if isMyTurn {
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.06), lineWidth: 3)
                            .frame(width: avatarSize + 8, height: avatarSize + 8)

                        Circle()
                            .trim(from: 0, to: turnProgress)
                            .stroke(
                                AngularGradient(
                                    gradient: Gradient(colors: [
                                        timerColor.opacity(0.0),
                                        timerColor.opacity(0.4),
                                        timerColor,
                                        Color.white
                                    ]),
                                    center: .center,
                                    startAngle: .degrees(0),
                                    endAngle:   .degrees(360 * turnProgress)
                                ),
                                style: StrokeStyle(lineWidth: 3, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                            .frame(width: avatarSize + 8, height: avatarSize + 8)
                            .shadow(color: timerColor.opacity(0.4), radius: 4)
                            .animation(.linear(duration: 0.1), value: turnProgress)
                    }
                }

                // Avatar circle
                Circle()
                    .fill(Color(hex: "#1A2744"))
                    .overlay(
                        Circle().strokeBorder(
                            isMyTurn ? Color.white.opacity(0.6) : Color(hex: "#2A3D6A"),
                            lineWidth: isMyTurn ? 2 : 1
                        )
                    )
                    .frame(width: avatarSize, height: avatarSize)
                    .overlay(
                        Text(AvatarOption.find(seat.avatarId).emoji)
                            .font(.system(size: avatarSize * 0.58))
                    )
                    .opacity(seat.status == .folded ? 0.5 : 1.0)
                    .shadow(
                        color: seat.status == .allIn
                            ? Color(hex: "#F5C842").opacity(allInPulse ? 0.7 : 0.15)
                            : Color.black.opacity(0.4),
                        radius: seat.status == .allIn ? (allInPulse ? 10 : 3) : 5,
                        y: 2
                    )

                // Last-5-seconds countdown — sits in front of the avatar at
                // half opacity so it reads as a subtle urgency cue without
                // competing with the timer ring.
                if isMyTurn, turnSecondsLeft > 0, turnSecondsLeft <= 5 {
                    Text("\(turnSecondsLeft)")
                        .font(.system(size: avatarSize * 0.7, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                        .shadow(color: .black.opacity(0.6), radius: 2, y: 1)
                        .frame(width: avatarSize, height: avatarSize)
                        .transition(.scale.combined(with: .opacity))
                        .id(turnSecondsLeft) // retrigger transition each tick
                        .zIndex(5)
                }

                // Face-down card backs beside avatar (for players with cards)
                if seat.hasCards && seat.status != .folded && !isMe {
                    HStack(spacing: -8) {
                        ForEach(0..<min(seat.cardCount, 4), id: \.self) { i in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(
                                    LinearGradient(
                                        colors: [Color(hex: "#2D2D4A"), Color(hex: "#1A1A30")],
                                        startPoint: .topLeading, endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 18, height: 24)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 3)
                                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
                                )
                                .rotationEffect(.degrees(Double(i) * 5 - 5))
                                .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                        }
                    }
                    .offset(x: -avatarSize * 0.52, y: -avatarSize * 0.15)
                }

                // SB / BB badges
                if seat.isSmallBlind {
                    blindBadge("SB", color: Color(hex: "#4A90E2"))
                        .offset(x: -avatarSize * 0.42, y: -avatarSize * 0.40)
                } else if seat.isBigBlind {
                    blindBadge("BB", color: Color(hex: "#4A90E2"))
                        .offset(x: -avatarSize * 0.42, y: -avatarSize * 0.40)
                }

                // Disconnect indicator
                if !seat.isConnected {
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(3)
                        .background(Color.red.opacity(0.85))
                        .clipShape(Circle())
                        .offset(x: avatarSize * 0.38, y: -avatarSize * 0.38)
                }
            }
            .frame(width: avatarSize + 10, height: avatarSize + 10)

            // Name plate
            VStack(spacing: 1) {
                Text(truncatedName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(formatChips(String(seat.stack)))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(stackColor)
                    .lineLimit(1)
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(width: plateWidth)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(hex: "#1C2030").opacity(0.9))
                    .shadow(color: .black.opacity(0.5), radius: 3, y: 2)
            )
            .offset(y: -4)
        }
        .onAppear {
            if seat.status == .allIn { startAllInPulse() }
            if isWinner              { startWinnerPulse() }
        }
        .onChange(of: seat.status) { _, new in
            if new == .allIn { startAllInPulse() } else { allInPulse = false }
        }
        .onChange(of: isWinner) { _, new in
            if new { startWinnerPulse() } else { winnerPulse = false }
        }
        .animation(.spring(response: 0.3), value: seat.status)
        .animation(.spring(response: 0.3), value: isMyTurn)
    }

    private func startWinnerPulse() {
        withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
            winnerPulse = true
        }
    }

    private var truncatedName: String {
        let n = seat.username
        return n.count > 9 ? String(n.prefix(8)) + "..." : n
    }

    private var stackColor: Color {
        switch seat.status {
        case .active:  return Color(hex: "#2ECC71")
        case .folded:  return Color(hex: "#F5C842")
        case .allIn:   return Color(hex: "#F5C842")
        default:       return Color(hex: "#F5C842")
        }
    }

    private var timerColor: Color {
        if turnProgress > 0.5  { return Color(hex: "#2ECC71") }
        if turnProgress > 0.25 { return Color(hex: "#F5C842") }
        return Color(hex: "#E05555")
    }

    private func startAllInPulse() {
        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
            allInPulse = true
        }
    }

    private func blindBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .black))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(Color.white.opacity(0.4), lineWidth: 0.5))
    }

    private struct ActionKind { let label: String; let color: Color }
    private func actionBubbleKind(for raw: String) -> ActionKind? {
        switch raw {
        case "CHECK":  return ActionKind(label: "Check", color: Color(hex: "#2D8B3E"))
        case "CALL":   return ActionKind(label: "Call",  color: Color(hex: "#2D8B3E"))
        case "RAISE":  return ActionKind(label: "Raise", color: Color(hex: "#4A90E2"))
        case "ALL_IN": return ActionKind(label: "All In", color: Color(hex: "#F5C842"))
        default:       return nil
        }
    }
}

// ─── Empty Seat ──────────────────────────────────────────────────────────────

struct TargetEmptySeat: View {
    let avatarSize: CGFloat
    var body: some View {
        VStack(spacing: 4) {
            Circle()
                .strokeBorder(
                    Color.white.opacity(0.08),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                )
                .frame(width: avatarSize, height: avatarSize)
                .overlay(
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.15))
                )
            Text("Open")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.15))
        }
    }
}

// ─── Table Theme ──────────────────────────────────────────────────────────────
// Felt color presets chosen in Settings. Persisted via @AppStorage
// ("tableThemeId"). Read here by PokerTableView and GameView for live updates.

struct TableTheme: Identifiable, Equatable {
    let id: String
    let label: String
    // Three-stop radial gradient for the felt.
    let inner: String
    let mid:   String
    let edge:  String
    // Room background (gradient behind the felt).
    let roomTop:    String
    let roomBottom: String

    static let all: [TableTheme] = [
        TableTheme(id: "classic_blue", label: "Classic Blue",
                   inner: "#1E5BA8", mid: "#143E7A", edge: "#0C2850",
                   roomTop: "#05070D", roomBottom: "#0A1F44"),
        TableTheme(id: "emerald", label: "Emerald",
                   inner: "#1E8A5F", mid: "#0F5E3E", edge: "#08351F",
                   roomTop: "#060B08", roomBottom: "#0B2A1C"),
        TableTheme(id: "crimson", label: "Crimson",
                   inner: "#B0394A", mid: "#7A1F2B", edge: "#3F0A12",
                   roomTop: "#0D0406", roomBottom: "#2A0B11"),
        TableTheme(id: "royal_purple", label: "Royal Purple",
                   inner: "#6B4CC5", mid: "#44288F", edge: "#1F1252",
                   roomTop: "#07060D", roomBottom: "#1E1640"),
        TableTheme(id: "midnight", label: "Midnight",
                   inner: "#2D3847", mid: "#1A222E", edge: "#0A0F17",
                   roomTop: "#030506", roomBottom: "#0B1219"),
        TableTheme(id: "bourbon", label: "Bourbon",
                   inner: "#C68E3C", mid: "#8A5A1E", edge: "#3F2807",
                   roomTop: "#0C0805", roomBottom: "#2A1B08"),
    ]

    static func find(_ id: String) -> TableTheme {
        all.first { $0.id == id } ?? all[0]
    }

    var primaryColor: Color { Color(hex: inner) }
    var edgeColor:    Color { Color(hex: edge) }
}
