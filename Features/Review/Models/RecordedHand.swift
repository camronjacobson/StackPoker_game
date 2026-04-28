import Foundation

// ─── Recorded Hand ────────────────────────────────────────────────────────────
// Codable mirror of the live game models, persisted to disk after every hand
// the local user takes part in. We can't reuse the live `ClientGameState`
// directly because those are Decodable-only (they decode the server payload).
// The "PF" prefix = "Persisted Frame" — these are the on-disk representations.

struct PFCard: Codable, Hashable, Identifiable {
    let rank: String   // 2..9, T, J, Q, K, A
    let suit: String   // S, H, D, C
    var id: String { "\(rank)\(suit)" }

    init(rank: String, suit: String) { self.rank = rank; self.suit = suit }
    init(_ card: PokerCard) { self.rank = card.rank; self.suit = card.suit }

    /// Bridge back to the live model so existing card views can render us.
    var live: PokerCard { PokerCard(rank: rank, suit: suit) }
}

struct PFSeat: Codable, Identifiable {
    let seatIndex: Int
    let userId: String
    let username: String
    let displayName: String
    let avatarId: String
    let stack: Int
    let status: String           // PlayerStatus rawValue
    let holeCards: [PFCard]?     // nil for hidden, empty array for "shown but no cards"
    let cardCount: Int
    let betThisStreet: Int
    let totalContributed: Int
    let isDealer: Bool
    let isSmallBlind: Bool
    let isBigBlind: Bool

    var id: String { userId }

    init(_ seat: GameSeat) {
        self.seatIndex        = seat.seatIndex
        self.userId           = seat.userId
        self.username         = seat.username
        self.displayName      = seat.displayName
        self.avatarId         = seat.avatarId
        self.stack            = seat.stack
        self.status           = seat.status.rawValue
        self.holeCards        = seat.holeCards?.map(PFCard.init)
        self.cardCount        = seat.cardCount
        self.betThisStreet    = seat.betThisStreet
        self.totalContributed = seat.totalContributed
        self.isDealer         = seat.isDealer
        self.isSmallBlind     = seat.isSmallBlind
        self.isBigBlind       = seat.isBigBlind
    }
}

struct PFAction: Codable {
    let playerId: String
    let username: String
    let action: String           // FOLD/CHECK/CALL/RAISE/ALL_IN/SMALL_BLIND/BIG_BLIND
    let amount: Int?
    let timestamp: Int

    init(_ a: LastAction) {
        self.playerId  = a.playerId
        self.username  = a.username
        self.action    = a.action
        self.amount    = a.amount
        self.timestamp = a.timestamp
    }
}

struct PFWinner: Codable {
    let playerId: String
    let username: String
    let amount: Int
    let handName: String
    let bestCards: [PFCard]

    init(_ w: WinnerPayout) {
        self.playerId  = w.playerId
        self.username  = w.username
        self.amount    = w.amount
        self.handName  = w.handName
        self.bestCards = w.bestCards.map(PFCard.init)
    }
}

// ─── Frame ─────────────────────────────────────────────────────────────────────
// One snapshot of the table at a meaningful moment (action change, street
// change, board update). Not every server tick is captured — see HandRecorder.

struct ReplayFrame: Codable, Identifiable {
    let id: String                  // UUID
    let capturedAt: Date
    let phase: String               // GamePhase rawValue
    let street: String              // Street rawValue
    let communityCards: [PFCard]
    let pot: Int
    let currentBet: Int
    let smallBlind: Int
    let bigBlind: Int
    let seats: [PFSeat]
    let activePlayerId: String?
    let dealerSeatIndex: Int
    let lastAction: PFAction?
    let winners: [PFWinner]?

    static func from(state: ClientGameState, capturedAt: Date = Date()) -> ReplayFrame {
        ReplayFrame(
            id: UUID().uuidString,
            capturedAt: capturedAt,
            phase: state.phase.rawValue,
            street: state.street.rawValue,
            communityCards: state.communityCards.map(PFCard.init),
            pot: state.totalPot,
            currentBet: state.currentBet,
            smallBlind: state.smallBlind,
            bigBlind: state.bigBlind,
            seats: state.seats.map(PFSeat.init),
            activePlayerId: state.activePlayerId,
            dealerSeatIndex: state.dealerSeatIndex,
            lastAction: state.lastAction.map(PFAction.init),
            winners: state.winners?.map(PFWinner.init)
        )
    }

    var streetEnum: Street { Street(rawValue: street) ?? .preflop }
}

// ─── Recorded Hand ─────────────────────────────────────────────────────────────

struct RecordedHand: Codable, Identifiable {
    let id: String
    let tableId: String
    let tableName: String
    let handNumber: Int
    let userId: String              // owner of the recording = local user
    let myUsername: String
    let smallBlind: Int
    let bigBlind: Int
    let myStartingStack: Int
    let myEndingStack: Int
    let myHoleCards: [PFCard]
    let opponents: [String]         // usernames seated when hand started
    let pot: Int                    // final total pot
    let winners: [PFWinner]
    let startedAt: Date
    let endedAt: Date
    let frames: [ReplayFrame]

    var iWon: Bool { winners.contains { $0.playerId == userId } }
    var stackDelta: Int { myEndingStack - myStartingStack }
    var winningHandName: String? { winners.first?.handName }

    var summary: RecordedHandSummary {
        RecordedHandSummary(
            id: id,
            tableName: tableName,
            handNumber: handNumber,
            myHoleCards: myHoleCards,
            stackDelta: stackDelta,
            iWon: iWon,
            winningHandName: winningHandName,
            opponentCount: opponents.count,
            endedAt: endedAt
        )
    }
}

/// Lightweight row used in the history list — avoids loading the full frames
/// array for every hand on the screen.
struct RecordedHandSummary: Codable, Identifiable, Hashable {
    let id: String
    let tableName: String
    let handNumber: Int
    let myHoleCards: [PFCard]
    let stackDelta: Int
    let iWon: Bool
    let winningHandName: String?
    let opponentCount: Int
    let endedAt: Date
}

// ─── formatChips Int overload ────────────────────────────────────────────────
// The shared helper in LobbyModels takes a String (because it parses server
// payloads). Inside the Review feature we already have Int chip values, so add
// an overload to avoid `formatChips("\(n)")` callsites everywhere.
func formatChips(_ n: Int) -> String { formatChips(String(n)) }
