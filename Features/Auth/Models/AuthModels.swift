import Foundation

// ─── Auth Request Models ──────────────────────────────────────────────────────

struct RegisterRequest: Encodable {
    let email: String
    let password: String
    let username: String
    let displayName: String
    let avatarId: String
}

struct LoginRequest: Encodable {
    let email: String
    let password: String
}

struct AppleAuthRequest: Encodable {
    let identityToken: String
    let authorizationCode: String
    let fullName: AppleFullName?
    let username: String?
    let avatarId: String?

    struct AppleFullName: Encodable {
        let givenName: String?
        let familyName: String?
    }
}

struct RefreshRequest: Encodable {
    let refreshToken: String
}

struct LogoutRequest: Encodable {
    let refreshToken: String
}

// Partial profile update — send only the fields the user changed. Omitted
// fields stay as-is on the server. Decoded by the backend's PATCH /auth/me.
struct UpdateProfileRequest: Encodable {
    let avatarId: String?
    let displayName: String?
}

// ─── Auth Response Models ─────────────────────────────────────────────────────

struct AuthResponse: Decodable {
    let tokens: AuthTokens
    let user: UserProfile
    let isNewUser: Bool?
}

struct AuthTokens: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
}

struct TokensResponse: Decodable {
    let tokens: AuthTokens
}

struct UsernameCheckResponse: Decodable {
    let available: Bool
    let valid: Bool
}

// Note: DailyBonusResponse is declared in Features/Profile/ViewModels/ChipsViewModel.swift
// (used by both ChipsViewModel.claimDailyBonus and AuthViewModel.claimDailyBonus).

// ─── User Profile Model ───────────────────────────────────────────────────────

struct UserProfile: Decodable, Identifiable, Equatable {
    let id: String
    let username: String
    let displayName: String
    let avatarId: String
    let avatarUrl: String?
    let chipBalance: String      // BigInt serialized as string
    let totalWon: String?
    let totalLost: String?
    let handsPlayed: Int?
    let gamesPlayed: Int?
    let email: String?
    let isAdmin: Bool?
    let createdAt: String?
    let lastSeenAt: String?

    var chipBalanceInt: Int64 {
        Int64(chipBalance) ?? 0
    }

    var formattedChips: String {
        let n = chipBalanceInt
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000     { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }

    static func == (lhs: UserProfile, rhs: UserProfile) -> Bool {
        lhs.id == rhs.id
    }
}

// ─── Avatar Definitions ───────────────────────────────────────────────────────

struct AvatarOption: Identifiable {
    let id: String
    let emoji: String
    let label: String
    let color: String   // hex background

    // Retro-themed avatar roster — poker suits, casino classics, and
    // 60s-pulp motifs. Background colors all sit inside the retro palette
    // (maroon / popRed / popBlue / mutedTeal / mustard / ink etc.) so the
    // avatar discs read as printed stamps on the comic page rather than
    // generic emoji circles. Existing user `selectedAvatarId` values
    // (avatar_1 … avatar_12) still resolve, so this is a pure cosmetic
    // swap with no data migration required.
    static let all: [AvatarOption] = [
        AvatarOption(id: "avatar_1",  emoji: "🃏",  label: "Joker",    color: "#8B2C2C"),
        AvatarOption(id: "avatar_2",  emoji: "🎩",  label: "Top Hat",  color: "#1A1410"),
        AvatarOption(id: "avatar_3",  emoji: "🎲",  label: "Dice",     color: "#D33232"),
        AvatarOption(id: "avatar_4",  emoji: "♠️", label: "Spade",    color: "#2E7C8B"),
        AvatarOption(id: "avatar_5",  emoji: "♥️", label: "Heart",    color: "#B68A14"),
        AvatarOption(id: "avatar_6",  emoji: "♦️", label: "Diamond",  color: "#2A6DB5"),
        AvatarOption(id: "avatar_7",  emoji: "♣️", label: "Club",     color: "#5C4838"),
        AvatarOption(id: "avatar_8",  emoji: "🍀",  label: "Clover",   color: "#3F6B3A"),
        AvatarOption(id: "avatar_9",  emoji: "💎",  label: "Gem",      color: "#3F87C9"),
        AvatarOption(id: "avatar_10", emoji: "👑",  label: "Crown",    color: "#E8B923"),
        AvatarOption(id: "avatar_11", emoji: "🎯",  label: "Bullseye", color: "#A53939"),
        AvatarOption(id: "avatar_12", emoji: "🚀",  label: "Rocket",   color: "#8A6038"),
    ]

    static func find(_ id: String) -> AvatarOption {
        all.first { $0.id == id } ?? all[0]
    }
}
