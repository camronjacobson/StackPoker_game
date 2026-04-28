import SwiftUI

// ─── Replay Table View ────────────────────────────────────────────────────────
// Visual representation of a single ReplayFrame. Mirrors the style of
// PokerTableView (oval felt, walnut rail, seats around the edge, board cards
// in the middle, pot below the cards) but is read-only — no action buttons,
// no timer ring, no kick controls. Driven by the parent ReplayViewModel's
// currentFrame.

struct ReplayTableView: View {
    let frame: ReplayFrame
    let userId: String
    let winnerIds: Set<String>      // highlight on showdown

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // ── Felt + rail ──────────────────────────────────────────────
                feltShape
                    .fill(SPColors.railOuter)
                    .frame(width: geo.size.width, height: geo.size.height)

                feltShape
                    .fill(
                        LinearGradient(colors: [SPColors.railLight, SPColors.railMid, SPColors.railOuter],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    .frame(width: geo.size.width * 0.96, height: geo.size.height * 0.94)

                feltShape
                    .fill(SPColors.feltDark)
                    .frame(width: geo.size.width * 0.88, height: geo.size.height * 0.84)

                feltShape
                    .fill(
                        RadialGradient(colors: [SPColors.felt, SPColors.feltDark],
                                       center: .center, startRadius: 20, endRadius: geo.size.width * 0.5)
                    )
                    .frame(width: geo.size.width * 0.85, height: geo.size.height * 0.80)

                // ── Center content ───────────────────────────────────────────
                VStack(spacing: 8) {
                    // Last action banner — keyed on the action so swapping
                    // frames cross-fades instead of snapping characters.
                    Group {
                        if let action = frame.lastAction {
                            Text("\(action.username) · \(verbForAction(action))")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.9))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(Color.black.opacity(0.45)))
                                .id("banner-\(actionKey(action))")
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        } else {
                            // Reserve vertical space so the cards don't jump
                            // when the banner appears/disappears.
                            Color.clear.frame(height: 24)
                        }
                    }
                    .frame(height: 24)
                    .animation(.easeInOut(duration: 0.25), value: frame.lastAction.map(actionKey))

                    HStack(spacing: 6) {
                        ForEach(frame.communityCards, id: \.id) { card in
                            ReplayCardView(card: card, faceUp: true)
                                .transition(.scale(scale: 0.6).combined(with: .opacity))
                        }
                        ForEach(0..<(5 - frame.communityCards.count), id: \.self) { _ in
                            ReplayCardView(card: nil, faceUp: false)
                                .opacity(0.18)
                        }
                    }
                    .animation(.spring(response: 0.45, dampingFraction: 0.8), value: frame.communityCards.count)

                    // Pot — animates the number transition via contentTransition
                    HStack(spacing: 4) {
                        Image(systemName: "circle.hexagongrid.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(SPColors.chipGold)
                        Text("Pot \(formatChips(frame.pot))")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .contentTransition(.numericText())
                            .animation(.easeOut(duration: 0.3), value: frame.pot)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.black.opacity(0.45)))
                }

                // ── Seats around the edge ────────────────────────────────────
                ForEach(Array(frame.seats.enumerated()), id: \.element.id) { _, seat in
                    let pos = seatPosition(
                        seatIndex: seat.seatIndex,
                        totalSeats: max(frame.seats.count, 2),
                        in: geo.size
                    )
                    ReplaySeatView(
                        seat: seat,
                        isHero: seat.userId == userId,
                        isActive: frame.activePlayerId == seat.userId,
                        isWinner: winnerIds.contains(seat.userId),
                        showCards: shouldShowCards(seat: seat)
                    )
                    .position(pos)
                }
            }
        }
    }

    private var feltShape: some Shape { RoundedRectangle(cornerRadius: 200) }

    /// Compute a seat's (x, y) along the rail. Hero is always pinned to the
    /// bottom; everyone else is distributed clockwise around the table.
    private func seatPosition(seatIndex: Int, totalSeats: Int, in size: CGSize) -> CGPoint {
        // Find the hero's seat index for rotation
        let heroIdx = frame.seats.first(where: { $0.userId == userId })?.seatIndex ?? 0
        let relIndex = ((seatIndex - heroIdx) + totalSeats) % totalSeats

        // Bottom = relIndex 0; angle increases clockwise.
        let angle = (Double(relIndex) / Double(totalSeats)) * 2 * .pi + .pi / 2
        let cx = size.width / 2
        let cy = size.height / 2
        let rx = size.width * 0.42
        let ry = size.height * 0.40
        let x = cx + rx * cos(angle)
        let y = cy + ry * sin(angle)
        return CGPoint(x: x, y: y)
    }

    /// We show cards for the hero always, and for any seat that's a declared
    /// winner on the final frame (showdown reveal).
    private func shouldShowCards(seat: PFSeat) -> Bool {
        if seat.userId == userId { return true }
        if winnerIds.contains(seat.userId), frame.winners?.first(where: { $0.playerId == seat.userId }) != nil {
            return true
        }
        return seat.holeCards != nil   // server-revealed
    }

    /// Stable key for a PFAction so SwiftUI's transition can detect "this is
    /// a different action" and cross-fade. PFAction itself isn't Identifiable.
    private func actionKey(_ a: PFAction) -> String {
        "\(a.playerId)|\(a.action)|\(a.amount ?? -1)"
    }

    private func verbForAction(_ a: PFAction) -> String {
        switch a.action {
        case "FOLD":   return "Folded"
        case "CHECK":  return "Checked"
        case "CALL":   return a.amount.map { "Called \(formatChips($0))" } ?? "Called"
        case "RAISE":  return a.amount.map { "Raised to \(formatChips($0))" } ?? "Raised"
        case "ALL_IN": return "All-In"
        case "SMALL_BLIND": return "Small Blind"
        case "BIG_BLIND":   return "Big Blind"
        default: return a.action.capitalized
        }
    }
}

// ─── Seat (compact) ──────────────────────────────────────────────────────────

private struct ReplaySeatView: View {
    let seat: PFSeat
    let isHero: Bool
    let isActive: Bool
    let isWinner: Bool
    let showCards: Bool

    var body: some View {
        VStack(spacing: 4) {
            // Cards (or backs)
            HStack(spacing: 2) {
                if showCards, let cards = seat.holeCards, cards.count >= 1 {
                    ForEach(cards, id: \.id) { c in ReplayCardView(card: c, faceUp: true) }
                } else if seat.cardCount > 0 {
                    ForEach(0..<seat.cardCount, id: \.self) { _ in
                        ReplayCardView(card: nil, faceUp: false)
                    }
                }
            }
            .frame(height: 30)
            .opacity(seat.status == "FOLDED" ? 0.25 : 1)

            // Avatar puck
            ZStack {
                Circle()
                    .fill(isHero ? SPColors.accent.opacity(0.9) : SPColors.surfaceElevated)
                    .frame(width: 38, height: 38)
                Text(String(seat.username.prefix(1)).uppercased())
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                if seat.isDealer {
                    Circle()
                        .fill(.white)
                        .frame(width: 14, height: 14)
                        .overlay(Text("D").font(.system(size: 9, weight: .heavy)).foregroundStyle(.black))
                        .offset(x: 18, y: -14)
                }
            }
            .overlay(
                Circle()
                    .stroke(borderColor, lineWidth: 2)
            )

            // Name + stack
            VStack(spacing: 1) {
                Text(seat.username)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(formatChips(seat.stack))
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(SPColors.chipGold)
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.3), value: seat.stack)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.black.opacity(0.55)))

            // Bet
            ZStack {
                if seat.betThisStreet > 0 {
                    Text(formatChips(seat.betThisStreet))
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(SPColors.chipGold))
                        .contentTransition(.numericText())
                        .transition(.scale(scale: 0.7).combined(with: .opacity))
                }
            }
            .frame(height: 14)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: seat.betThisStreet)
        }
        .animation(.easeInOut(duration: 0.25), value: seat.status)
    }

    private var borderColor: Color {
        if isWinner { return SPColors.chipGold }
        if isActive { return SPColors.accent }
        return Color.white.opacity(0.18)
    }
}

// ─── Card (compact) ──────────────────────────────────────────────────────────

private struct ReplayCardView: View {
    let card: PFCard?
    let faceUp: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(faceUp && card != nil ? Color.white : SPColors.cardBack)
            if faceUp, let card = card {
                VStack(spacing: 0) {
                    Text(card.live.displayRank)
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                    Text(card.live.suitSymbol)
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundStyle(card.live.isRed ? SPColors.cardRed : SPColors.cardBlack)
            } else {
                RoundedRectangle(cornerRadius: 3)
                    .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                    .padding(2)
            }
        }
        .frame(width: 22, height: 30)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.black.opacity(0.30), lineWidth: 0.5)
        )
    }
}
