import SwiftUI

// ─── Replay Table View ────────────────────────────────────────────────────────
// Visual representation of a single ReplayFrame. Mirrors the style of
// PokerTableView (oval felt, walnut rail, seats around the edge, board cards
// in the middle, pot below the cards) but is read-only — no action buttons,
// no timer ring, no kick controls.
//
// PR 2 (visual unification):
//   The seat component is now `TargetSeatView` (the same component the live
//   game uses) instead of a bespoke `ReplaySeatView`. This is the whole point
//   of this PR: live + replay share one seat treatment so any future polish
//   to the live seat (folded label, all-in pulse, winner glow, opponent
//   card flip-up) shows up in the replay for free.
//
//   Because TargetSeatView is built around the live `GameSeat` / `LastAction`
//   types and we persist `PFSeat` / `PFAction` on disk, the file-private
//   adapters in the `// Adapters` section below bridge the two without
//   modifying the persisted Codable shapes.
//
//   The replay frame is much smaller than the live table (height 280 vs full
//   screen), so we shrink `avatarSize` and pull the seat ring inward
//   (`rx`/`ry`) to make sure adjacent seats — and their offset opponent-card
//   stacks — don't collide.

struct ReplayTableView: View {
    let frame: ReplayFrame
    let userId: String
    let winnerIds: Set<String>      // highlight on showdown

    // Compact seat avatar size. Live table uses ~50–60pt; here we want the
    // whole seat (cards + avatar + name pill + stack pill) to fit inside a
    // 280pt-tall table with breathing room above and below.
    private let avatarSize: CGFloat = 36

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
                // We render every PFSeat through TargetSeatView. Two important
                // adapter calls per seat:
                //   • `seat.asGameSeat()` — bridges the persisted PFSeat shape
                //     into the live GameSeat type that TargetSeatView expects.
                //     Status string → PlayerStatus enum, [PFCard] → [PokerCard].
                //   • `lastActionForSeat(...)` — TargetSeatView shows the per-
                //     seat action bubble (Folded / Called / Raised) only when
                //     `lastAction.playerId == seat.userId`. Passing the raw
                //     frame.lastAction would still work (it does its own match
                //     check) but doing it here is explicit and cheap.
                //
                // We pass `isMe: false` for every seat (including the hero) on
                // purpose: the live game hides opponent face-up cards from the
                // hero's own seat and renders the hero's hand at the bottom of
                // the screen instead. In the replay we *want* the hero's cards
                // visible at their seat for context, so we treat everyone like
                // an opponent here.
                ForEach(Array(frame.seats.enumerated()), id: \.element.id) { _, seat in
                    let pos = seatPosition(
                        seatIndex: seat.seatIndex,
                        totalSeats: max(frame.seats.count, 2),
                        in: geo.size
                    )
                    TargetSeatView(
                        seat:               seat.asGameSeat(),
                        isMe:               false,
                        isMyTurn:           false,                 // no live timer in replay
                        isWinner:           winnerIds.contains(seat.userId),
                        turnProgress:       0,
                        turnSecondsLeft:    0,
                        lastAction:         lastActionForSeat(seat),
                        avatarSize:         avatarSize,
                        winningCardIds:     winningCardIds(for: seat),
                        anyWinnersDeclared: !winnerIds.isEmpty
                    )
                    .position(pos)
                }
            }
        }
    }

    private var feltShape: some Shape { RoundedRectangle(cornerRadius: 200) }

    /// Compute a seat's (x, y) along the rail. Hero is always pinned to the
    /// bottom; everyone else is distributed clockwise around the table.
    ///
    /// Radii were tightened from 0.42/0.40 → 0.38/0.36 in PR 2. TargetSeatView
    /// is wider than the old ReplaySeatView (it has a name pill at
    /// `plateWidth = avatarSize * 1.55` plus an opponent-card stack offset
    /// `-avatarSize * 0.52` to the left), so the previous radii pushed seat
    /// elements outside the felt and into each other on tables with 8–9 seats.
    private func seatPosition(seatIndex: Int, totalSeats: Int, in size: CGSize) -> CGPoint {
        // Find the hero's seat index for rotation
        let heroIdx = frame.seats.first(where: { $0.userId == userId })?.seatIndex ?? 0
        let relIndex = ((seatIndex - heroIdx) + totalSeats) % totalSeats

        // Bottom = relIndex 0; angle increases clockwise.
        let angle = (Double(relIndex) / Double(totalSeats)) * 2 * .pi + .pi / 2
        let cx = size.width / 2
        let cy = size.height / 2
        let rx = size.width  * 0.38
        let ry = size.height * 0.36
        let x = cx + rx * cos(angle)
        let y = cy + ry * sin(angle)
        return CGPoint(x: x, y: y)
    }

    /// TargetSeatView only renders an action bubble when the action matches
    /// this seat. Pre-filtering here also keeps the spring transition tied to
    /// just this seat's identity (no flicker on neighbors when a different
    /// seat acts).
    private func lastActionForSeat(_ seat: PFSeat) -> LastAction? {
        guard let a = frame.lastAction, a.playerId == seat.userId else { return nil }
        return a.asLastAction()
    }

    /// At showdown, the persisted PFWinner records the exact 5 cards that made
    /// the winning hand. TargetSeatView uses this set to highlight winning
    /// cards in gold while dimming the rest of the opponent's hole cards.
    /// Returns an empty set if this seat isn't a winner (TargetSeatView treats
    /// empty == "don't highlight anything special").
    private func winningCardIds(for seat: PFSeat) -> Set<String> {
        guard winnerIds.contains(seat.userId),
              let winner = frame.winners?.first(where: { $0.playerId == seat.userId })
        else { return [] }
        // PFCard.id is "rank+suit" e.g. "AH". PokerCard's id is the same shape,
        // so the IDs are interchangeable across the bridge.
        return Set(winner.bestCards.map(\.id))
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

// ─── Adapters: PFSeat / PFAction → live game types ───────────────────────────
// These convert the Codable persisted shapes back into the live types the
// shared TargetSeatView expects. They're file-private because they only exist
// to support replay rendering — nothing outside this file should be reaching
// for a "GameSeat" view of a "PFSeat" (that would mean we lost track of which
// world we're in).

private extension PFSeat {
    /// Build a live `GameSeat` from this persisted seat. The conversion is
    /// total: every PFSeat field has a 1:1 GameSeat counterpart.
    ///
    /// Two fields don't exist on the persisted shape and are filled with
    /// sensible replay defaults:
    ///   • `timeBank`    — 0. We don't show a turn ring in replay, so this is
    ///                     never read by TargetSeatView.
    ///   • `isConnected` — true. Replay frames are post-hoc; "disconnected"
    ///                     would surface a wifi-slash icon that has no meaning
    ///                     when reviewing a finished hand.
    ///
    /// Status is stored as the raw string ("ACTIVE" / "FOLDED" / "ALL_IN" / …)
    /// so we round-trip through `PlayerStatus(rawValue:)`. If a future server
    /// version introduces an unknown status we fall back to `.active` rather
    /// than crashing the replay.
    func asGameSeat() -> GameSeat {
        GameSeat(
            seatIndex:        seatIndex,
            userId:           userId,
            username:         username,
            displayName:      displayName,
            avatarId:         avatarId,
            stack:            stack,
            status:           PlayerStatus(rawValue: status) ?? .active,
            holeCards:        holeCards?.map(\.live),
            cardCount:        cardCount,
            // Replay frames don't track voluntary fold-show events — the
            // recorded hand only captures the authoritative state at each
            // street boundary. Always nil here so TargetSeatView falls back
            // to its existing "no partial reveals" behavior.
            revealedCards:    nil,
            betThisStreet:    betThisStreet,
            totalContributed: totalContributed,
            isDealer:         isDealer,
            isSmallBlind:     isSmallBlind,
            isBigBlind:       isBigBlind,
            timeBank:         0,
            isConnected:      true
        )
    }
}

private extension PFAction {
    /// Bridge a persisted `PFAction` back to a live `LastAction` so it can be
    /// fed to TargetSeatView's per-seat action bubble.
    func asLastAction() -> LastAction {
        LastAction(
            playerId:  playerId,
            username:  username,
            action:    action,
            amount:    amount,
            timestamp: timestamp
        )
    }
}

// ─── Card (compact) ──────────────────────────────────────────────────────────
// Still used by the center community-card row. The seat itself no longer
// renders cards directly — TargetSeatView's OpponentHoleCardsView handles
// face-down/face-up flipping at the seat positions.

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
