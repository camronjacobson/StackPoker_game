import Foundation

// MAP: GameModels — Codable types decoded from server snapshots (445 lines)
// - PokerCard .............................. L5
// - PlayerStatus (active/folded/allIn …) ... L47
// - RevealedCard (voluntary fold-show) ..... L60
// - GameSeat ............................... L66
// - PotSlice (main + side pots) ............ L99
// - PokerAction ............................ L108
// - LastAction ............................. L145
// - WinnerPayout ........................... L168
// - GamePhase .............................. L179
// - Street ................................. L188
// - ClientGameState (root snapshot) ........ L200
// - HandStrength (label, made vs draw) ..... L275

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

// One voluntarily-shown card from a folded or live player. The server emits
// these so every viewer sees the same exposed card; `index` is the card's
// original slot in the hand (0 or 1 for Holdem) so the UI can place it back
// over the right face-down placeholder rather than reflowing.
struct RevealedCard: Decodable, Identifiable, Equatable, Hashable {
    let index: Int
    let card:  PokerCard
    var id: String { "\(index)-\(card.id)" }
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
    // Cards this seat has voluntarily exposed (fold-show tap or all-in
    // showdown auto-reveal). Optional because older server builds don't
    // emit it — decode falls back to []. Visible to every viewer regardless
    // of seat ownership; the iOS layer renders these face-up over the
    // matching face-down slot.
    let revealedCards:   [RevealedCard]?
    let betThisStreet:   Int
    let totalContributed: Int
    let isDealer:        Bool
    let isSmallBlind:    Bool
    let isBigBlind:      Bool
    let timeBank:        Int
    let isConnected:     Bool
    // Server-side flag: the player tapped "leave" mid-hand and is waiting
    // for the hand to finish before being booted. Optional because older
    // server builds don't emit it — falls back to false. iOS greys out the
    // avatar + shows a "Left" badge while this is true, then the seat just
    // disappears from the next ClientGameState once the engine evicts it.
    let pendingLeave:    Bool?
    // Mid-hand top-up amount this seat has paid for but not yet received.
    // Server omits the field when 0, so this is optional/nil on the
    // common path; the UI renders a small "+N" pending badge near the
    // stack pill when > 0. Drained into `stack` server-side at end of
    // hand (see PokerGameEngine.applyPendingTopUps).
    let pendingTopUp:    Int?

    var id: String { userId }
    var isActive: Bool { status == .active }
    var isLeaving: Bool { pendingLeave == true }
    var pendingTopUpAmount: Int { pendingTopUp ?? 0 }
    var hasCards: Bool { (holeCards?.count ?? cardCount) > 0 }
    // Convenience for the UI: empty array if server didn't emit the field.
    var revealed: [RevealedCard] { revealedCards ?? [] }
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
    // Cards that *would have been* dealt to fill the rest of the board if the
    // hand had run out instead of ending early on a fold. Server populates
    // this only when phase==ENDED *and* the board never reached the river;
    // empty array (or nil from older servers) otherwise. iOS turns these into
    // face-down tappable placeholders that flip on tap so the player can see
    // what they would have hit. Optional so old server builds still decode.
    let revealableBoard: [PokerCard]?

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

// ─── your_chips_updated payload ──────────────────────────────────────────────
// Server-pushed wallet update for the current user. `newBalance` is the
// authoritative post-mutation chipBalance (BigInt-as-string, matching the
// REST `newBalance` field convention). `reason` is a short tag for
// debugging/telemetry — iOS does NOT branch on it; every value flows through
// applyServerBalance the same way.
//
// See TECH_DEBT.md ("Balance sync via socket"). The canonical channel for
// server-side wallet mutations that aren't tied to an HTTP response.
struct ChipsUpdatedEvent: Decodable {
    let newBalance: String
    let reason:     String?
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
            // PLO preflop: intentionally no label. The descriptive
            // strings produced by `ploPreflopLabel` ("Ace Double Suited",
            // "Premium", "Connected", etc.) aren't real poker hand
            // strengths and confused testers into thinking the game was
            // misreading their hand. NLH preflop keeps its "Pocket Aces /
            // Suited Connectors / Ace High" labels because those are
            // standard hole-card descriptors.
            if hole.count == 4 { return nil }
            return preflopLabel(hole)
        }
        // PLO postflop: must use exactly 2 hole + 3 board. The NLH "all 7
        // cards into madeHandLabel" path is wrong here because it would let
        // (say) trips on the board + a hole-card pair form a full house even
        // though PLO rules forbid using more than 2 hole cards. Branch into
        // the enumeration-based PLO evaluator that walks every C(4,2)×C(B,3)
        // combination and picks the strongest made hand.
        if hole.count == 4 {
            // PLO postflop is restricted to the canonical made-hand
            // whitelist (no draws, no descriptive preflop strings). The
            // enumerator returns one of madeHandLabel's exact strings or
            // nil; nil → "High Card". The only rename is "Four of a Kind"
            // → "Quads" because that's the term requested for the PLO UI
            // (NLH still says "Four of a Kind" via its own path).
            let raw = bestPLOMadeHandLabel(hole: hole, board: board) ?? "High Card"
            return raw == "Four of a Kind" ? "Quads" : raw
        }
        let all = hole + board
        // On the river (5 community cards) the hand is final — there are no
        // more cards to come, so showing "Flush Draw" / "Straight Draw" is
        // misleading. Past 4 board cards we degrade gracefully to the actual
        // made hand or "High Card". Draws are still surfaced on the flop
        // (3) and turn (4), where outs remain and the label is useful.
        if board.count >= 5 {
            return madeHandLabel(all) ?? "High Card"
        }
        return madeHandLabel(all) ?? drawLabel(hole: hole, board: board) ?? "High Card"
    }

    // Strength ordering for the human-readable made-hand strings produced by
    // `madeHandLabel`. Used by the PLO enumerator to rank the 6×C(B,3) combos
    // and pick the strongest. Kept tightly coupled to madeHandLabel's exact
    // output strings on purpose — if you add a new tier there, add it here.
    private static let madeHandRank: [String: Int] = [
        "High Card":        1,
        "One Pair":         2,
        "Two Pair":         3,
        "Three of a Kind":  4,
        "Straight":         5,
        "Flush":            6,
        "Full House":       7,
        "Four of a Kind":   8,
        "Straight Flush":   9,
        "Royal Flush":     10,
    ]

    // PLO label evaluator. Enumerates every valid (2 hole) × (3 board)
    // combination, evaluates each as a 5-card NLH hand via the existing
    // `madeHandLabel`, and returns the strongest by `madeHandRank`. Limited
    // to 6×C(B,3) combos: 6 on the flop, 24 on the turn, 60 on the river —
    // trivially cheap for a display-only label that re-evaluates only when
    // the board or hole cards change.
    //
    // Returns nil only if every combination is High Card (caller treats
    // that as "High Card" rather than hiding the label).
    //
    // Draws (flush draw / straight draw) are intentionally NOT surfaced
    // here — the NLH `drawLabel` heuristic uses all hole+board cards and
    // would over-report draws in PLO (e.g. 4 hole hearts + 1 board heart
    // is NOT a flush draw under 2+3). Conservative: show made hand only.
    private static func bestPLOMadeHandLabel(hole: [PokerCard], board: [PokerCard]) -> String? {
        guard hole.count == 4, board.count >= 3 else { return nil }
        let holePairs  = combinations(hole,  k: 2)
        let boardTrios = combinations(board, k: 3)

        var bestLabel: String? = nil
        var bestRank:  Int     = 0
        for h in holePairs {
            for b in boardTrios {
                guard let lbl = madeHandLabel(h + b) else { continue }
                let r = madeHandRank[lbl] ?? 0
                if r > bestRank {
                    bestRank  = r
                    bestLabel = lbl
                }
            }
        }
        return bestLabel
    }

    // k-combinations helper. Returns every length-k subset of `arr` (input
    // order preserved within each subset). Tiny recursive enumeration —
    // max depth 3 here (board trios), max breadth 10 (C(5,3) on the river)
    // so the recursion overhead is negligible vs allocating a fancier
    // iterator.
    private static func combinations<T>(_ arr: [T], k: Int) -> [[T]] {
        var out: [[T]] = []
        var chosen: [T] = []
        func recurse(_ start: Int) {
            if chosen.count == k { out.append(chosen); return }
            for i in start..<arr.count {
                chosen.append(arr[i])
                recurse(i + 1)
                chosen.removeLast()
            }
        }
        recurse(0)
        return out
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
