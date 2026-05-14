import SwiftUI

// ─── Player Seat View ─────────────────────────────────────────────────────────
// Renders a single player seat on the circular table.

// MAP: PlayerSeatView — single seat avatar/name/turn-ring (164 lines)
// - PlayerSeatView (root) .................. L6
// - BlindBadge (D / SB / BB chip) .......... L152

struct PlayerSeatView: View {
    let seat:          GameSeat
    let isMyTurn:      Bool
    let turnProgress:  Double        // 0..1
    let isMe:          Bool
    var lastAction:    LastAction?

    private var isActive: Bool { seat.status == .active || seat.status == .allIn }

    var body: some View {
        VStack(spacing: 3) {
            // Cards above avatar (for opponents)
            if !isMe && seat.hasCards {
                HoleCardsView(cards: seat.holeCards ?? [], cardCount: seat.cardCount, isHidden: seat.holeCards == nil, size: .small)
                    .offset(y: 4)
            }

            // Avatar with turn ring
            ZStack {
                // Turn progress ring — retro palette: muted teal while
                // safe, pop red when the clock is bleeding out. Pulled from
                // the same color set as the table's turn-timer ring so the
                // seat ring + center timer agree visually.
                if isMyTurn {
                    Circle()
                        .trim(from: 0, to: turnProgress)
                        .stroke(
                            turnProgress > 0.3
                                ? SPRetro.teal
                                : SPRetro.popRed,
                            style: StrokeStyle(lineWidth: 3, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: avatarSize + 10, height: avatarSize + 10)
                        .animation(.linear(duration: 0.2), value: turnProgress)
                }

                // Dealer button — paper disc with an ink border and a hard
                // ink offset shadow. AmericanTypewriter-Bold ink "D" so it
                // reads as a hand-stamped dealer chip.
                if seat.isDealer {
                    ZStack {
                        Circle()
                            .fill(SPRetro.ink)
                            .frame(width: 16, height: 16)
                            .offset(x: 1, y: 1.5)
                        Circle()
                            .fill(SPRetro.paper)
                            .frame(width: 16, height: 16)
                        Circle()
                            .strokeBorder(SPRetro.ink, lineWidth: 1)
                            .frame(width: 16, height: 16)
                        Text("D")
                            .font(.custom("AmericanTypewriter-Bold", size: 10))
                            .foregroundStyle(SPRetro.ink)
                    }
                    .offset(x: avatarSize * 0.38, y: -avatarSize * 0.38)
                    .zIndex(2)
                }

                // Avatar
                ZStack {
                    AvatarView(
                        avatarId: seat.avatarId,
                        size: avatarSize,
                        showBorder: isMyTurn || isMe
                    )
                    .opacity(seat.status == .folded ? 0.4 : seat.isConnected ? 1 : 0.6)

                    // Folded X — maroon ink mark, the danger pop color.
                    if seat.status == .folded {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(SPRetro.maroon)
                    }

                    // All-in pill — mustard stamp with ink border and a
                    // hard ink offset shadow. AmericanTypewriter-Bold ink
                    // text + tracking so the label reads as a punched-in
                    // sticker rather than a thin system pill.
                    if seat.status == .allIn {
                        ZStack {
                            Capsule()
                                .fill(SPRetro.ink)
                                .offset(x: 1, y: 1.2)
                            Capsule()
                                .fill(SPRetro.mustard)
                            Capsule()
                                .strokeBorder(SPRetro.ink, lineWidth: 1)
                            Text("ALL IN")
                                .font(.custom("AmericanTypewriter-Bold", size: 8))
                                .tracking(0.8)
                                .foregroundStyle(SPRetro.ink)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                        }
                        .fixedSize()
                        .offset(y: avatarSize * 0.55)
                    }

                    // Disconnected — ink scrim over the avatar with a paper
                    // wifi-slash glyph; reads as a printed "offline" stamp.
                    if !seat.isConnected {
                        Circle()
                            .fill(SPRetro.ink.opacity(0.55))
                            .frame(width: avatarSize, height: avatarSize)
                        Image(systemName: "wifi.slash")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(SPRetro.paper.opacity(0.85))
                    }

                    // Online dot — muted teal on-turn / ink-soft idle,
                    // with a paper hairline so the dot reads against any
                    // avatar regardless of its underlying tone.
                    if seat.isConnected && seat.status != .sittingOut {
                        Circle()
                            .fill(isMyTurn
                                  ? SPRetro.teal
                                  : SPRetro.inkMuted)
                            .frame(width: 8, height: 8)
                            .overlay(
                                Circle().strokeBorder(SPRetro.paper,
                                                      lineWidth: 1.5)
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    }
                }
            }
            .frame(width: avatarSize + 10, height: avatarSize + 10)

            // Username + stack — retro fonts. AmericanTypewriter-Bold for
            // the username (mustard for "me", ink for others so the local
            // player still pops on the page). ChalkboardSE-Bold for the
            // chip count, matching the table's StackPill.
            VStack(spacing: 1) {
                Text(seat.username)
                    .font(.custom("AmericanTypewriter-Bold", size: 11))
                    .foregroundStyle(isMe
                                     ? SPRetro.mustardDark
                                     : SPRetro.ink)
                    .lineLimit(1)
                    .frame(maxWidth: nameWidth)

                if seat.status != .sittingOut {
                    Text(formatChips(String(seat.stack)))
                        .font(.custom("ChalkboardSE-Bold", size: 11))
                        .foregroundStyle(SPRetro.ink)
                }
            }

            // Bet chip (shown below name)
            if seat.betThisStreet > 0 {
                ChipStackView(amount: seat.betThisStreet, compact: true)
                    .transition(.scale.combined(with: .opacity))
            }

            // Last action badge — retro stamp: solid pop-color capsule with
            // ink border, AmericanTypewriter-Bold paper text. Same vocab as
            // the seat action bubbles in PokerTableView so the under-name
            // badge and the bubble agree visually.
            if let action = lastAction, action.playerId == seat.userId {
                ZStack {
                    Capsule().fill(actionColor(action.action))
                    Capsule().strokeBorder(SPRetro.ink, lineWidth: 1)
                    Text(action.displayText)
                        .font(.custom("AmericanTypewriter-Bold", size: 9))
                        .tracking(0.4)
                        .foregroundStyle(SPRetro.paper)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                }
                .fixedSize()
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3), value: seat.status)
        .animation(.spring(response: 0.3), value: isMyTurn)
    }

    private var avatarSize: CGFloat { isMe ? 46 : 38 }
    private var nameWidth:  CGFloat { isMe ? 70 : 58 }

    /// Retro action-badge palette — solid pop colors from SPRetro so the
    /// stamp under each seat matches the in-table action bubbles.
    private func actionColor(_ action: String) -> Color {
        switch action {
        case "FOLD":   return SPRetro.popRed  // pop red
        case "CHECK":  return SPRetro.inkMuted  // ink-soft (neutral)
        case "CALL":   return SPRetro.teal  // muted teal
        case "RAISE":  return SPRetro.popBlue  // pop blue
        case "ALL_IN": return SPRetro.mustard  // mustard
        default:       return SPRetro.ink.opacity(0.6)
        }
    }
}

// ─── Blind badge ─────────────────────────────────────────────────────────────

struct BlindBadge: View {
    let isSB: Bool

    var body: some View {
        // Retro blind chip: pop-blue (SB) / pop-red (BB) capsule with an
        // ink border + paper AmericanTypewriter-Bold label. Replaces the
        // saturated blue/pink Material capsules.
        ZStack {
            Capsule().fill(isSB ? SPRetro.popBlue : SPRetro.popRed)
            Capsule().strokeBorder(SPRetro.ink, lineWidth: 1)
            Text(isSB ? "SB" : "BB")
                .font(.custom("AmericanTypewriter-Bold", size: 8))
                .tracking(0.4)
                .foregroundStyle(SPRetro.paper)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
        }
        .fixedSize()
    }
}
