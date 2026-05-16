import SwiftUI

// ─── PokerTableView previews ──────────────────────────────────────────────
//
// Hot-iteration harness for the table layout. Each #Preview decodes a
// `ClientGameState` from a JSON literal, assigns it onto a stock
// `GameViewModel`, and renders `PokerTableView` with the one
// @EnvironmentObject it actually pulls in directly (`LobbyViewModel` —
// used for the in-game invite-friends flow; nothing else from the env
// is touched by PokerTableView itself).
//
// Why JSON-decoding instead of memberwise inits?
//   - `ClientGameState`, `GameSeat`, `PokerCard`, `PotSlice` are all
//     `Decodable` with `let` properties. We'd need to either add
//     memberwise inits for every type (production surface area) or just
//     hand the decoder a literal — the literal is cheaper and stays in
//     this preview-only filxe.
//
// Mocked dependencies (everything else in the env chain is untouched
// because PokerTableView doesn't read it directly):
//   • LobbyViewModel  — injected via .environmentObject. Default init,
//     no network calls fire (its REST loads are explicit method calls).
//   • GameViewModel   — created with dummy tableId/tableName. Its init
//     just calls setupSubscriptions, which sinks on a Combine subject
//     that never publishes in preview (no socket connect). `gameState`
//     is the only @Published field we populate.
//
// If a future change makes PokerTableView reach for AuthViewModel,
// CosmeticsContainer, or SubscriptionManager directly, add the
// corresponding `.environmentObject(...)` call in `previewHost`.

#if DEBUG

// ─── JSON → model helper ──────────────────────────────────────────────────

private enum PreviewMocks {

    static func decode(_ json: String) -> ClientGameState {
        // Force-unwrap is preview-only — a bad literal is a programmer
        // error visible the moment the canvas loads.
        let data = json.data(using: .utf8)!
        return try! JSONDecoder().decode(ClientGameState.self, from: data)
    }

    // Stock seat JSON. The fields are spelled out (rather than templated
    // with String interpolation) so the literal stays valid JSON the
    // Decodable path is happy with — no trailing-comma / quote-escaping
    // surprises mid-edit. `holeCards` is omitted on non-hero seats so
    // the table renders opponents' cards face-down.
    static let heroSeat = """
    {
      "seatIndex": 0,
      "userId": "hero",
      "username": "you",
      "displayName": "You",
      "avatarId": "default",
      "stack": 4820,
      "status": "ACTIVE",
      "holeCards": [{"rank":"A","suit":"S"},{"rank":"K","suit":"S"}],
      "cardCount": 2,
      "betThisStreet": 0,
      "totalContributed": 200,
      "isDealer": true,
      "isSmallBlind": false,
      "isBigBlind": false,
      "timeBank": 0,
      "isConnected": true
    }
    """

    static let villainSeat = """
    {
      "seatIndex": 3,
      "userId": "villain",
      "username": "rival",
      "displayName": "Rival",
      "avatarId": "default",
      "stack": 3180,
      "status": "ACTIVE",
      "cardCount": 2,
      "betThisStreet": 0,
      "totalContributed": 200,
      "isDealer": false,
      "isSmallBlind": false,
      "isBigBlind": true,
      "timeBank": 0,
      "isConnected": true
    }
    """

    // Fills the other four positions on a 6-max table. Each villain has
    // their own userId so PokerTableView's seat lookup works (it keys
    // on userId) and so the avatar grid doesn't share state across
    // adjacent seats. Statuses are varied to exercise rendering for an
    // active row, a folded row, and an all-in row.
    static func villain(seatIndex: Int, userId: String, name: String,
                        stack: Int, status: String,
                        bet: Int = 0,
                        flags: (dealer: Bool, sb: Bool, bb: Bool) = (false, false, false)) -> String {
        """
        {
          "seatIndex": \(seatIndex),
          "userId": "\(userId)",
          "username": "\(userId)",
          "displayName": "\(name)",
          "avatarId": "default",
          "stack": \(stack),
          "status": "\(status)",
          "cardCount": 2,
          "betThisStreet": \(bet),
          "totalContributed": 200,
          "isDealer": \(flags.dealer),
          "isSmallBlind": \(flags.sb),
          "isBigBlind": \(flags.bb),
          "timeBank": 0,
          "isConnected": true
        }
        """
    }

    // A full 6-max ring. seats[0] = hero (anchored to the bottom by
    // PokerTableView's seat overlay), the rest read clockwise from
    // there. Stacks/statuses are tuned to exercise the most common
    // render cases: small blind, big blind, an all-in, a fold, plus
    // two live players.
    static func sixHandedSeats(hero: String) -> String {
        [
            hero,
            villain(seatIndex: 1, userId: "v1", name: "Sam",   stack: 2150, status: "ACTIVE", flags: (false, true, false)),
            villain(seatIndex: 2, userId: "v2", name: "Mia",   stack: 0,    status: "ALL_IN"),
            villain(seatIndex: 3, userId: "v3", name: "Rival", stack: 3180, status: "ACTIVE", bet: 80, flags: (false, false, true)),
            villain(seatIndex: 4, userId: "v4", name: "Leo",   stack: 5400, status: "FOLDED"),
            villain(seatIndex: 5, userId: "v5", name: "Kim",   stack: 1820, status: "ACTIVE"),
        ].joined(separator: ",")
    }

    static let emptyState = """
    {
      "tableId": "preview-empty",
      "handNumber": 0,
      "phase": "WAITING",
      "street": "PREFLOP",
      "seats": [],
      "communityCards": [],
      "pots": [],
      "totalPot": 0,
      "currentBet": 0,
      "minRaise": 20,
      "activePlayerId": null,
      "dealerSeatIndex": 0,
      "smallBlind": 10,
      "bigBlind": 20,
      "actionDeadline": 0,
      "legalActions": []
    }
    """

    static func midGameState(communityCards: String, street: String) -> String {
        """
        {
          "tableId": "preview-game",
          "handNumber": 42,
          "phase": "BETTING",
          "street": "\(street)",
          "seats": [\(heroSeat),\(villainSeat)],
          "communityCards": \(communityCards),
          "pots": [{"amount":1200,"eligiblePlayerIds":["hero","villain"],"isMain":true}],
          "totalPot": 1200,
          "currentBet": 0,
          "minRaise": 40,
          "activePlayerId": "hero",
          "dealerSeatIndex": 0,
          "smallBlind": 10,
          "bigBlind": 20,
          "actionDeadline": 1900000000000,
          "legalActions": []
        }
        """
    }

    static let turnCards = """
    [{"rank":"A","suit":"D"},{"rank":"K","suit":"H"},{"rank":"7","suit":"C"},{"rank":"2","suit":"S"}]
    """

    static let riverCards = """
    [{"rank":"A","suit":"D"},{"rank":"K","suit":"H"},{"rank":"7","suit":"C"},{"rank":"2","suit":"S"},{"rank":"9","suit":"D"}]
    """

    // ActionBar-visible state.
    //
    // ActionBar gates its body on `vm.isMyTurn`, which is
    // `gameState.activePlayerId == vm.userId`. In preview the VM's userId
    // resolves through KeychainManager to an empty string, so we mirror
    // that here: hero's seat userId = "", activePlayerId = "". Same
    // empty-string match makes isMyTurn true AND `mySeat` resolve, so
    // RaiseSliderView's min/max math (which reads `mySeat?.stack`) works.
    static let heroSeatActionable = """
    {
      "seatIndex": 0,
      "userId": "",
      "username": "you",
      "displayName": "You",
      "avatarId": "default",
      "stack": 4820,
      "status": "ACTIVE",
      "holeCards": [{"rank":"A","suit":"S"},{"rank":"K","suit":"S"}],
      "cardCount": 2,
      "betThisStreet": 0,
      "totalContributed": 200,
      "isDealer": true,
      "isSmallBlind": false,
      "isBigBlind": false,
      "timeBank": 0,
      "isConnected": true
    }
    """

    // Postflop bet-entry mock — hero on the turn with the betting row
    // available. Used to verify the postflop preset labels (33% / 66% /
    // 100%) and that the pot-percentage math reads from
    // `totalPot + callAmount` correctly.
    static let actionBarState = """
    {
      "tableId": "preview-actionbar",
      "handNumber": 42,
      "phase": "BETTING",
      "street": "TURN",
      "seats": [\(heroSeatActionable),\(villainSeat)],
      "communityCards": \(turnCards),
      "pots": [{"amount":1200,"eligiblePlayerIds":["","villain"],"isMain":true}],
      "totalPot": 1200,
      "currentBet": 0,
      "minRaise": 40,
      "activePlayerId": "",
      "dealerSeatIndex": 0,
      "smallBlind": 10,
      "bigBlind": 20,
      "actionDeadline": 1900000000000,
      "legalActions": [
        {"action":"FOLD"},
        {"action":"CHECK"},
        {"action":"RAISE","minAmount":40,"maxAmount":4820}
      ]
    }
    """

    // Preflop bet-entry mock — empty board, hero in big blind facing a
    // potential open. Used to verify the preflop preset labels (2BB /
    // 3BB / 4BB) and that the row swaps cleanly from percentages to BB
    // multiples when `vm.isPostflop` flips false.
    //
    // Currents: bigBlind = 20, so minRaise = 40 (2BB), 3BB = 60, 4BB = 80.
    // currentBet matches the BB so RAISE math reads as a standard preflop
    // open. We keep activePlayerId = "" / hero userId = "" so isMyTurn
    // resolves true the same way the postflop preview does.
    static let actionBarPreflopState = """
    {
      "tableId": "preview-actionbar-pf",
      "handNumber": 42,
      "phase": "BETTING",
      "street": "PREFLOP",
      "seats": [\(heroSeatActionable),\(villainSeat)],
      "communityCards": [],
      "pots": [{"amount":30,"eligiblePlayerIds":["","villain"],"isMain":true}],
      "totalPot": 30,
      "currentBet": 20,
      "minRaise": 40,
      "activePlayerId": "",
      "dealerSeatIndex": 0,
      "smallBlind": 10,
      "bigBlind": 20,
      "actionDeadline": 1900000000000,
      "legalActions": [
        {"action":"FOLD"},
        {"action":"CALL","callAmount":20},
        {"action":"RAISE","minAmount":40,"maxAmount":4820}
      ]
    }
    """

    // Facing-a-bet variant. CHECK swapped for CALL so the bottom row
    // renders Fold | Call $80 | Bet. Villain has already pushed 80 in
    // and the hero's `betThisStreet` is left at 0 so `currentBet`
    // reflects the call delta.
    static let foldCallBetState = """
    {
      "tableId": "preview-foldcallbet",
      "handNumber": 42,
      "phase": "BETTING",
      "street": "TURN",
      "seats": [\(sixHandedSeats(hero: heroSeatActionable))],
      "communityCards": \(turnCards),
      "pots": [{"amount":1200,"eligiblePlayerIds":["","v1","v2","v3","v5"],"isMain":true}],
      "totalPot": 1200,
      "currentBet": 80,
      "minRaise": 160,
      "activePlayerId": "",
      "dealerSeatIndex": 0,
      "smallBlind": 10,
      "bigBlind": 20,
      "actionDeadline": 1900000000000,
      "legalActions": [
        {"action":"FOLD"},
        {"action":"CALL","callAmount":80},
        {"action":"RAISE","minAmount":160,"maxAmount":4820}
      ]
    }
    """

    @MainActor
    static func makeVM(with state: ClientGameState?) -> GameViewModel {
        let vm = GameViewModel(tableId: "preview-table", tableName: "Preview")
        vm.gameState = state
        return vm
    }
}

// ─── Preview host ─────────────────────────────────────────────────────────
//
// Centralizes env-object wiring and the page background so each #Preview
// stays a one-liner. If env requirements grow, this is the only place
// that needs to learn about them.

private struct PokerTablePreviewHost: View {
    let seats: [GameSeat]
    let maxSeats: Int
    let vm: GameViewModel
    // When true, stacks ActionBar (and any open raise slider) beneath the
    // felt so the full bottom-of-screen play surface is rendered together.
    var showActionBar: Bool = false

    var body: some View {
        ZStack {
            // Match the cream page background GameView uses around the felt
            // so the preview reads close to the in-app composition.
            Color(red: 0.95, green: 0.93, blue: 0.86)
                .ignoresSafeArea()
            VStack(spacing: 0) {
                ZStack(alignment: .bottomTrailing) {
                    PokerTableView(
                        seats:       seats,
                        maxSeats:    maxSeats,
                        vm:          vm,
                        isLandscape: false
                    )
                    // Mirror GameView.localPlayerOverlay (cards pinned above
                    // the action bar). PokerTableView itself doesn't render
                    // the hero's hole cards — that lives in GameView — so
                    // we drop a minimal replica here so the preview shows
                    // the hand in front of the felt.
                    if !vm.myCards.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(vm.myCards, id: \.id) { card in
                                PlayingCardView(card: card, size: .large)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.bottom, 4)
                    }
                    // Mirror GameView.portraitLayout's right-side chip
                    // slider mount so the preview canvas shows the live
                    // bet-entry composition. We skip the tap-dismiss
                    // Color.clear overlay (no point in preview) but
                    // otherwise match the production placement.
                    if vm.showRaiseSlider {
                        VerticalChipSlider(vm: vm)
                            .padding(.trailing, 8)
                    }
                }
                if showActionBar {
                    ActionBar(vm: vm)
                }
            }
        }
        .environmentObject(LobbyViewModel())
    }
}

// ─── #Preview entries ─────────────────────────────────────────────────────

#Preview("Empty") {
    let vm = PreviewMocks.makeVM(with: PreviewMocks.decode(PreviewMocks.emptyState))
    return PokerTablePreviewHost(seats: [], maxSeats: 6, vm: vm)
}

// Hero facing a bet on the turn — slider closed, just the
// Fold | Call $80 | Bet row, hero avatar + hole cards, table. Same
// userId="" trick as `heroSeatActionable` so `vm.isMyTurn` resolves
// to true and the ActionBar materializes its buttons in preview.
#Preview("Fold · Call · Bet") {
    let state = PreviewMocks.decode(PreviewMocks.foldCallBetState)
    let vm = PreviewMocks.makeVM(with: state)
    vm.showRaiseSlider = false
    return PokerTablePreviewHost(
        seats:         state.seats,
        maxSeats:      6,
        vm:            vm,
        showActionBar: true
    )
}

#Preview("River — 5 cards") {
    let state = PreviewMocks.decode(
        PreviewMocks.midGameState(communityCards: PreviewMocks.riverCards, street: "RIVER")
    )
    let vm = PreviewMocks.makeVM(with: state)
    return PokerTablePreviewHost(seats: state.seats, maxSeats: 6, vm: vm)
}

// Hero preflop with the in-place betting row pre-opened. Verifies that
// `vm.isPostflop == false` picks the BB-multiple preset labels (2BB /
// 3BB / 4BB) and that the slim slider's min/max math reads the legal
// raise bounds correctly. Pre-seeded `raiseAmount = minRaise` mirrors
// what the Raise button does in production on first tap. See
// `heroSeatActionable` for the userId="" trick that makes `isMyTurn`
// resolve to true in preview.
#Preview("Bet Entry — preflop") {
    let state = PreviewMocks.decode(PreviewMocks.actionBarPreflopState)
    let vm = PreviewMocks.makeVM(with: state)
    vm.showRaiseSlider = true
    vm.raiseAmount = state.minRaise
    return PokerTablePreviewHost(
        seats:         state.seats,
        maxSeats:      6,
        vm:            vm,
        showActionBar: true
    )
}

// Hero postflop (turn) with the in-place betting row pre-opened.
// Verifies the percentage preset labels (33% / 66% / 100%) and that
// the pot-sized "100%" preset reads `totalPot + callAmount` so it lands
// on the canonical pot-sized raise after calling. callAmount is 0 here
// since `betThisStreet` and `currentBet` are both 0, so the 100% chip
// should equal `currentBet + totalPot` = 0 + 1200 = 1200 chips.
#Preview("Bet Entry — postflop") {
    let state = PreviewMocks.decode(PreviewMocks.actionBarState)
    let vm = PreviewMocks.makeVM(with: state)
    vm.showRaiseSlider = true
    vm.raiseAmount = state.minRaise
    return PokerTablePreviewHost(
        seats:         state.seats,
        maxSeats:      6,
        vm:            vm,
        showActionBar: true
    )
}

#endif
