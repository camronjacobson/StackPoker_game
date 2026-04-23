import SwiftUI

// ─── Player Seat View ─────────────────────────────────────────────────────────
// Renders a single player seat on the circular table.

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
                // Turn progress ring
                if isMyTurn {
                    Circle()
                        .trim(from: 0, to: turnProgress)
                        .stroke(
                            turnProgress > 0.3 ? SPColors.success : SPColors.warning,
                            style: StrokeStyle(lineWidth: 3, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: avatarSize + 10, height: avatarSize + 10)
                        .animation(.linear(duration: 0.2), value: turnProgress)
                }

                // Dealer / blind badges
                if seat.isDealer {
                    Circle()
                        .fill(SPColors.chipGold)
                        .frame(width: 16, height: 16)
                        .overlay(Text("D").font(.system(size: 9, weight: .black)).foregroundStyle(SPColors.chipGoldDark))
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

                    // Folded X
                    if seat.status == .folded {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(SPColors.danger)
                    }

                    // All-in crown
                    if seat.status == .allIn {
                        Text("ALL IN")
                            .font(.system(size: 7, weight: .black))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(SPColors.warning)
                            .clipShape(Capsule())
                            .offset(y: avatarSize * 0.55)
                    }

                    // Disconnected indicator
                    if !seat.isConnected {
                        Circle()
                            .fill(Color.black.opacity(0.5))
                            .frame(width: avatarSize, height: avatarSize)
                        Image(systemName: "wifi.slash")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.7))
                    }

                    // Online dot
                    if seat.isConnected && seat.status != .sittingOut {
                        Circle()
                            .fill(isMyTurn ? SPColors.success : SPColors.textTertiary)
                            .frame(width: 8, height: 8)
                            .overlay(Circle().strokeBorder(SPColors.felt, lineWidth: 1.5))
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    }
                }
            }
            .frame(width: avatarSize + 10, height: avatarSize + 10)

            // Username + stack
            VStack(spacing: 1) {
                Text(seat.username)
                    .font(.system(size: 10, weight: isMe ? .bold : .medium))
                    .foregroundStyle(isMe ? SPColors.accentLight : .white)
                    .lineLimit(1)
                    .frame(maxWidth: nameWidth)

                if seat.status != .sittingOut {
                    Text(formatChips(String(seat.stack)))
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(SPColors.chipGold)
                }
            }

            // Bet chip (shown below name)
            if seat.betThisStreet > 0 {
                ChipStackView(amount: seat.betThisStreet, compact: true)
                    .transition(.scale.combined(with: .opacity))
            }

            // Last action badge
            if let action = lastAction, action.playerId == seat.userId {
                Text(action.displayText)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(actionColor(action.action))
                    .clipShape(Capsule())
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3), value: seat.status)
        .animation(.spring(response: 0.3), value: isMyTurn)
    }

    private var avatarSize: CGFloat { isMe ? 46 : 38 }
    private var nameWidth:  CGFloat { isMe ? 70 : 58 }

    private func actionColor(_ action: String) -> Color {
        switch action {
        case "FOLD":  return SPColors.danger.opacity(0.8)
        case "CHECK": return SPColors.textTertiary.opacity(0.8)
        case "CALL":  return SPColors.success.opacity(0.8)
        case "RAISE": return SPColors.accent.opacity(0.9)
        case "ALL_IN": return SPColors.warning.opacity(0.9)
        default:      return Color.black.opacity(0.6)
        }
    }
}

// ─── Blind badge ─────────────────────────────────────────────────────────────

struct BlindBadge: View {
    let isSB: Bool

    var body: some View {
        Text(isSB ? "SB" : "BB")
            .font(.system(size: 8, weight: .black))
            .foregroundStyle(.white)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(isSB ? Color(hex: "#0984E3") : Color(hex: "#E84393"))
            .clipShape(Capsule())
    }
}
