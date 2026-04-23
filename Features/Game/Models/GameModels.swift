import Foundation

// ─── Card ─────────────────────────────────────────────────────────────────────

struct PokerCard: Decodable, Identifiable, Equatable, Hashable {
    let rank: String   // 2..9, T, J, Q, K, A
    let suit: String   // S, H, D, C

    var id: String { "\(rank)\(suit)" }

    var displayRank: String {
        switch rank {
        case "T": return "10"
        case "J": return "J"
        case "Q": return "Q"
        case "K": return "K"
        case "A": return "A"
        default:  return rank
        }
    }

    var suitSymbol: String {
        switch suit {
        case "S": return "♠"
        case "H": return "♥"
        case "D": return "♦"
        case "C": return "♣"
        default:  return suit
        }
    }

    var isRed: Bool { suit == "H" || suit == "D" }

    var suitName: String {
        switch suit {
        case "S": return "Spades"
        case "H": return "Hearts"
        case "D": return "Diamonds"
        case "C": return "Clubs"
        default:  return suit
        }
    }
}

// ─── Seat ─────────────────────────────────────────────────────────────────────

enum PlayerStatus: String, Decodable {
    case waiting      = "WAITING"
    case active       = "ACTIVE"
    case folded       = "FOLDED"
    case allIn        = "ALL_IN"
    case sittingOut   = "SITTING_OUT"
    case disconnected = "DISCONNECTED"
}

struct GameSeat: Decodable, Identifiable {
    let seatIndex:       Int
    let userId:          String
    let username:        String
    let displayName:     String
    let avatarId:        String
    let stack:           Int
    let status:          PlayerStatus
    let holeCards:       [PokerCard]?     // nil = hidden
    let cardCount:       Int
    let betThisStreet:   Int
    let totalContributed: Int
    let isDealer:        Bool
    let isSmallBlind:    Bool
    let isBigBlind:      Bool
    let timeBank:        Int
    let isConnected:     Bool

    var id: String { userId }
    var isActive: Bool { status == .active }
    var hasCards: Bool { (holeCards?.count ?? cardCount) > 0 }
}

// ─── Pot ─────────────────────────────────────────────────────────────────────

struct PotSlice: Decodable, Identifiable {
    let amount:             Int
    let eligiblePlayerIds:  [String]
    let isMain:             Bool
    var id: String { "\(amount)-\(isMain)" }
}

// ─── Legal Action ─────────────────────────────────────────────────────────────

enum PokerAction: String, Decodable, CaseIterable {
    case fold    = "FOLD"
    case check   = "CHECK"
    case call    = "CALL"
    case raise   = "RAISE"
    case allIn   = "ALL_IN"

    var label: String {
        switch self {
        case .fold:  return "Fold"
        case .check: return "Check"
        case .call:  return "Call"
        case .raise: return "Raise"
        case .allIn: return "All In"
        }
    }

    var color: String {
        switch self {
        case .fold:  return "#E17055"
        case .check: return "#636e72"
        case .call:  return "#00B894"
        case .raise: return "#6C5CE7"
        case .allIn: return "#F9CA24"
        }
    }
}

struct LegalAction: Decodable {
    let action:     PokerAction
    let minAmount:  Int?
    let maxAmount:  Int?
    let callAmount: Int?
}

// ─── Last Action ─────────────────────────────────────────────────────────────

struct LastAction: Decodable {
    let playerId:  String
    let username:  String
    let action:    String
    let amount:    Int?
    let timestamp: Int

    var displayText: String {
        switch action {
        case "FOLD":        return "Folded"
        case "CHECK":       return "Checked"
        case "CALL":        return amount != nil ? "Called \(formatChips(String(amount!)))" : "Called"
        case "RAISE":       return amount != nil ? "Raised to \(formatChips(String(amount!)))" : "Raised"
        case "ALL_IN":      return "All In!"
        case "SMALL_BLIND": return "Small blind"
        case "BIG_BLIND":   return "Big blind"
        default:            return action.capitalized
        }
    }
}

// ─── Winner ───────────────────────────────────────────────────────────────────

struct WinnerPayout: Decodable {
    let playerId:  String
    let username:  String
    let amount:    Int
    let handName:  String
    let bestCards: [PokerCard]
    let showCards: Bool
}

// ─── Game Phase / Street ──────────────────────────────────────────────────────

enum GamePhase: String, Decodable {
    case waiting  = "WAITING"
    case starting = "STARTING"
    case dealing  = "DEALING"
    case betting  = "BETTING"
    case showdown = "SHOWDOWN"
    case ended    = "ENDED"
}

enum Street: String, Decodable {
    case preflop  = "PREFLOP"
    case flop     = "FLOP"
    case turn     = "TURN"
    case river    = "RIVER"
    case showdown = "SHOWDOWN"

    var label: String { rawValue.capitalized }
}

// ─── Full Client Game State ───────────────────────────────────────────────────

struct ClientGameState: Decodable {
    let tableId:         String
    let handNumber:      Int
    let phase:           GamePhase
    let street:          Street
    let seats:           [GameSeat]
    let communityCards:  [PokerCard]
    let pots:            [PotSlice]
    let totalPot:        Int
    let currentBet:      Int
    let minRaise:        Int
    let activePlayerId:  String?
    let dealerSeatIndex: Int
    let smallBlind:      Int
    let bigBlind:        Int
    let actionDeadline:  Double   // unix ms
    let turnDuration:    Double?  // ms — authoritative span of current turn (base + time bank); nil on older servers
    let lastAction:      LastAction?
    let winners:         [WinnerPayout]?
    let legalActions:    [LegalAction]
    let gameType:        String?  // "TEXAS_HOLDEM" or "PLO"

    // Convenience
    var mySeat: GameSeat? { nil }   // filled in by ViewModel from userId

    var activeSeat: GameSeat? {
        guard let id = activePlayerId else { return nil }
        return seats.first { $0.userId == id }
    }

    var dealerSeat: GameSeat? {
        seats.first { $0.seatIndex == dealerSeatIndex }
    }
}

// ─── WS Envelope ─────────────────────────────────────────────────────────────

struct WsEnvelope<T: Decodable>: Decodable {
    let event: String
    let data:  T
    let ts:    Double
}

struct WsErrorData: Decodable {
    let code:    String
    let message: String
}

struct ChatMessage: Decodable, Identifiable {
    let userId:   String
    let username: String
    let message:  String
    let ts:       Double
    var id: String { "\(userId)-\(ts)" }
}

struct PlayerActionEvent: Decodable {
    let userId:   String
    let username: String
    let action:   String
    let amount:   Int?
    let ts:       Double
}

// ─── HandStrength ─────────────────────────────────────────────────────────────
// Lightweight display-only evaluator. Given the user's 2 hole cards and the
// (0–5) community cards, returns a short human-readable description such as
// "High Card", "One Pair", "Flush Draw", "Straight", "Full House", etc.
//
// This is NOT the authoritative showdown evaluator — the server owns that.
// It renders the small subtitle beneath the player's fanned hole cards.
//
// Preflop (board empty) it shows a simple hole-card descriptor
// ("Pocket Aces", "Suited Connectors", "Ace High", …).

enum HandStrength {
    static func label(hole: [PokerCard], board: [PokerCard]) -> String? {
        guard hole.count == 2 || hole.count == 4 else { return nil }
        if board.isEmpty {
            if hole.count == 4 { return ploPreflopLabel(hole) }
            return preflopLabel(hole)
        }
        let all = hole + board
        return madeHandLabel(all) ?? drawLabel(hole: hole, board: board) ?? "High Card"
    }

    // PLO preflop labels
    private static func ploPreflopLabel(_ hole: [PokerCard]) -> String {
        let ranks = hole.map { rankValue($0.rank) }.sorted(by: >)
        let suits = hole.map { $0.suit }
        let uniqueSuits = Set(suits)

        let hasPair = Set(ranks).count < ranks.count
        let hasAce = ranks.contains(14)
        let isDoubleSuited = suits.count - uniqueSuits.count >= 2

        if ranks[0] == ranks[1] && ranks[1] == ranks[2] { return "Trips" }
        if hasPair && hasAce && isDoubleSuited { return "Premium" }
        if hasAce && isDoubleSuited { return "Ace Double Suited" }
        if hasPair && hasAce { return "Ace + Pair" }
        if isDoubleSuited { return "Double Suited" }
        if hasAce { return "Ace High" }
        if hasPair { return "Paired" }

        let connected = ranks[0] - ranks[3] <= 4
        if connected { return "Connected" }
        return "Mixed"
    }

    // Preflop
    private static func preflopLabel(_ hole: [PokerCard]) -> String {
        let a = hole[0], b = hole[1]
        if a.rank == b.rank { return "Pocket \(pluralName(a.rank))" }
        let suited = (a.suit == b.suit)
        let va = rankValue(a.rank), vb = rankValue(b.rank)
        let hi = max(va, vb), lo = min(va, vb)
        let connector = (hi - lo == 1)
        let highName  = rankName(hi)
        if connector && suited { return "Suited Connectors" }
        if connector           { return "Connectors" }
        if suited              { return "\(highName) Suited" }
        return "\(highName) High"
    }

    // Made hand
    private static func madeHandLabel(_ cards: [PokerCard]) -> String? {
        guard cards.count >= 3 else { return nil }
        let ranks = cards.map { rankValue($0.rank) }
        let suits = cards.map { $0.suit }

        var rankCount: [Int: Int] = [:]
        for r in ranks { rankCount[r, default: 0] += 1 }
        let counts = rankCount.values.sorted(by: >)

        var suitCount: [String: Int] = [:]
        for s in suits { suitCount[s, default: 0] += 1 }
        let flushSuit = suitCount.first(where: { $0.value >= 5 })?.key

        let straightHigh = bestStraightHigh(in: ranks)

        if let fs = flushSuit {
            let flushRanks = cards.filter { $0.suit == fs }.map { rankValue($0.rank) }
            if let sfHi = bestStraightHigh(in: flushRanks) {
                if sfHi == 14 { return "Royal Flush" }
                return "Straight Flush"
            }
        }

        if counts.first == 4 { return "Four of a Kind" }
        if counts.first == 3 && (counts.dropFirst().first ?? 0) >= 2 { return "Full House" }
        if flushSuit != nil    { return "Flush" }
        if straightHigh != nil { return "Straight" }
        if counts.first == 3   { return "Three of a Kind" }
        if counts.filter({ $0 == 2 }).count >= 2 { return "Two Pair" }
        if counts.first == 2   { return "One Pair" }
        return nil
    }

    // Draws — simple heuristic (4-to-flush or 4-in-a-row straight draw)
    private static func drawLabel(hole: [PokerCard], board: [PokerCard]) -> String? {
        let all = hole + board
        var suitCount: [String: Int] = [:]
        for c in all { suitCount[c.suit, default: 0] += 1 }
        if suitCount.values.contains(4) { return "Flush Draw" }

        var expanded = Set(all.map { rankValue($0.rank) })
        if expanded.contains(14) { expanded.insert(1) }  // wheel
        let sorted = expanded.sorted()
        var run = 1
        for i in 1..<sorted.count {
            if sorted[i] == sorted[i-1] + 1 {
                run += 1
                if run >= 4 { return "Straight Draw" }
            } else if sorted[i] != sorted[i-1] {
                run = 1
            }
        }
        return nil
    }

    private static func bestStraightHigh(in rawRanks: [Int]) -> Int? {
        var set = Set(rawRanks)
        if set.contains(14) { set.insert(1) }
        let sorted = set.sorted()
        var best: Int? = nil
        var run = 1
        for i in 1..<sorted.count {
            if sorted[i] == sorted[i-1] + 1 {
                run += 1
                if run >= 5 { best = sorted[i] }
            } else {
                run = 1
            }
        }
        return best
    }

    private static func rankValue(_ r: String) -> Int {
        switch r {
        case "A": return 14
        case "K": return 13
        case "Q": return 12
        case "J": return 11
        case "T": return 10
        default:  return Int(r) ?? 0
        }
    }

    private static func rankName(_ v: Int) -> String {
        switch v {
        case 14: return "Ace"
        case 13: return "King"
        case 12: return "Queen"
        case 11: return "Jack"
        case 10: return "Ten"
        default: return "\(v)"
        }
    }

    private static func pluralName(_ r: String) -> String {
        switch r {
        case "A": return "Aces"
        case "K": return "Kings"
        case "Q": return "Queens"
        case "J": return "Jacks"
        case "T": return "Tens"
        case "2": return "Deuces"
        case "3": return "Threes"
        case "4": return "Fours"
        case "5": return "Fives"
        case "6": return "Sixes"
        case "7": return "Sevens"
        case "8": return "Eights"
        case "9": return "Nines"
        default:  return "\(r)s"
        }
    }
}
