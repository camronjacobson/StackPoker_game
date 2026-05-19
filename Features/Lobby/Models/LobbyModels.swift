import Foundation

// ─── Table Models ─────────────────────────────────────────────────────────────

struct TableListItem: Decodable, Identifiable {
  let id: String
  let name: String
  let joinCode: String
  let status: TableStatus
  let maxPlayers: Int
  let currentPlayers: Int
  let smallBlind: String
  let bigBlind: String
  let minBuyIn: String
  let maxBuyIn: String
  let isPrivate: Bool
  let ownerUsername: String
  let ownerAvatarId: String
  let clubId: String?
  let clubName: String?
  let createdAt: String
  let gameType: String?

  var blindsLabel: String { "\(formatChips(smallBlind))/\(formatChips(bigBlind))" }
  var seatLabel: String { "\(currentPlayers)/\(maxPlayers)" }
  var isFull: Bool { currentPlayers >= maxPlayers }
  var gameTypeLabel: String { (gameType ?? "TEXAS_HOLDEM") == "PLO" ? "PLO" : "NLH" }
}

struct TableDetail: Decodable, Identifiable {
  let id: String
  let name: String
  let joinCode: String
  let status: TableStatus
  let maxPlayers: Int
  let currentPlayers: Int
  let smallBlind: String
  let bigBlind: String
  let minBuyIn: String
  let maxBuyIn: String
  let isPrivate: Bool
  let clubId: String?
  let clubName: String?
  let owner: TableOwner
  let players: [TablePlayer]
  let createdAt: String
  let gameType: String?
}

struct TableOwner: Decodable {
  let id: String
  let username: String
  let displayName: String
  let avatarId: String
}

struct TablePlayer: Decodable, Identifiable {
  let userId: String
  let username: String
  let displayName: String
  let avatarId: String
  let seatIndex: Int
  let stack: String
  let isActive: Bool
  let joinedAt: String

  var id: String { userId }
}

enum TableStatus: String, Decodable {
  case waiting    = "WAITING"
  case inProgress = "IN_PROGRESS"
  case paused     = "PAUSED"
  case closed     = "CLOSED"

  var label: String {
    switch self {
    case .waiting:    return "Waiting"
    case .inProgress: return "In Progress"
    case .paused:     return "Paused"
    case .closed:     return "Closed"
    }
  }
}

// ─── Table List Response ──────────────────────────────────────────────────────

struct TableListResponse: Decodable {
  let tables: [TableListItem]
  let total: Int
}

// ─── Create Table Request ─────────────────────────────────────────────────────

struct CreateTableRequest: Encodable {
  let name: String
  let maxPlayers: Int
  let smallBlind: Int
  let bigBlind: Int
  let minBuyIn: Int
  let maxBuyIn: Int
  let isPrivate: Bool
  let clubId: String?
  let gameType: String
}

struct JoinTableRequest: Encodable {
  let buyInAmount: Int
  let seatIndex: Int?
}

// ─── Join Table Response ──────────────────────────────────────────────────────
//
// The backend's /tables/join/:code endpoint returns a *flat* JSON shape:
// every TableDetail field plus a top-level `newBalance` (the caller's post-
// buy-in chip balance, BigInt-as-string). The flat shape matches the
// convention used by /cosmetics/purchase and the other chip-mutating
// endpoints — see TECH_DEBT.md.
//
// We model that flat JSON as a wrapper so TableDetail itself doesn't grow
// an optional `newBalance` field (which would be meaningless for the GET
// /tables/:id detail fetch and for the list endpoint). Custom Decodable
// decodes the embedded TableDetail from the same root keyed container,
// then pulls out `newBalance` separately.

struct JoinTableResponse: Decodable {
  let detail:     TableDetail
  let newBalance: String

  private enum CodingKeys: String, CodingKey { case newBalance }

  init(from decoder: Decoder) throws {
    self.detail = try TableDetail(from: decoder)
    let c = try decoder.container(keyedBy: CodingKeys.self)
    self.newBalance = try c.decode(String.self, forKey: .newBalance)
  }
}

// ─── Friend Models ────────────────────────────────────────────────────────────

struct Friend: Decodable, Identifiable {
  let friendshipId: String
  let userId: String
  let username: String
  let displayName: String
  let avatarId: String
  let isOnline: Bool
  let currentTableId: String?
  let chipBalance: String
  // Wire shape from backend: { "avatarFrame": "avatar_frame_gold", … } —
  // same per-user equipped dict the seat broadcast uses. Optional for
  // back-compat with older server builds that haven't shipped the friends-
  // payload extension yet; `equipped` below coerces to an empty dict so
  // call sites don't deal with the optional.
  let equippedCosmetics: [String: String]?

  var id: String { friendshipId }

  var formattedChips: String { formatChips(chipBalance) }

  // Convenience accessor matching the pattern used by `GameSeat.equipped`
  // (see GameModels.swift). Call sites read e.g. `friend.equipped["avatarFrame"]`
  // to get an optional cosmeticId without dealing with double-optionality.
  var equipped: [String: String] { equippedCosmetics ?? [:] }
}

struct FriendsResponse: Decodable {
  let friends: [Friend]
}

struct FriendRequest: Decodable, Identifiable {
  let id: String
  let status: String
  let createdAt: String
  let sender: FriendRequestUser
}

struct FriendRequestUser: Decodable {
  let id: String
  let username: String
  let displayName: String
  let avatarId: String
}

struct FriendRequestsResponse: Decodable {
  let requests: [FriendRequest]
}

struct SearchedUser: Decodable, Identifiable {
  let id: String
  let username: String
  let displayName: String
  let avatarId: String
  let chipBalance: String
  let friendshipStatus: String?
  let friendshipId: String?

  var formattedChips: String { formatChips(chipBalance) }

  var isFriend: Bool { friendshipStatus == "ACCEPTED" }
  var hasPendingRequest: Bool { friendshipStatus == "PENDING" }
}

struct SearchUsersResponse: Decodable {
  let users: [SearchedUser]
}

// ─── Invite Models ────────────────────────────────────────────────────────────

struct TableInvite: Decodable, Identifiable {
  let id: String
  let status: String
  let expiresAt: String
  let createdAt: String
  let table: InviteTableInfo
  let sender: FriendRequestUser
}

struct InviteTableInfo: Decodable {
  let id: String
  let name: String
  let joinCode: String
  let smallBlind: String
  let bigBlind: String
  let currentPlayers: Int
  let maxPlayers: Int

  var blindsLabel: String { "\(formatChips(smallBlind))/\(formatChips(bigBlind))" }
}

struct InvitesResponse: Decodable {
  let invites: [TableInvite]
}

// ─── Chip formatting helper (shared) ─────────────────────────────────────────

func formatChips(_ raw: String) -> String {
  guard let n = Int64(raw) else { return raw }
  if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
  if n >= 1_000     { return String(format: "%.1fK", Double(n) / 1_000) }
  return "\(n)"
}

// ─── Standard presets for table creation ─────────────────────────────────────

struct BlindPreset: Identifiable {
  let id = UUID()
  let label: String
  let smallBlind: Int
  let bigBlind: Int
  let defaultMinBuyIn: Int
  let defaultMaxBuyIn: Int
}

extension BlindPreset {
  static let presets: [BlindPreset] = [
    BlindPreset(label: "Micro",  smallBlind: 5,    bigBlind: 10,   defaultMinBuyIn: 200,    defaultMaxBuyIn: 1_000),
    BlindPreset(label: "Low",    smallBlind: 25,   bigBlind: 50,   defaultMinBuyIn: 1_000,  defaultMaxBuyIn: 5_000),
    BlindPreset(label: "Mid",    smallBlind: 100,  bigBlind: 200,  defaultMinBuyIn: 4_000,  defaultMaxBuyIn: 20_000),
    BlindPreset(label: "High",   smallBlind: 500,  bigBlind: 1000, defaultMinBuyIn: 20_000, defaultMaxBuyIn: 100_000),
    BlindPreset(label: "Custom", smallBlind: 0,    bigBlind: 0,    defaultMinBuyIn: 0,      defaultMaxBuyIn: 0),
  ]
}
