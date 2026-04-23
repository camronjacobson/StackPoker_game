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

    static let all: [AvatarOption] = [
        AvatarOption(id: "avatar_1",  emoji: "🦁", label: "Lion",     color: "#E67E22"),
        AvatarOption(id: "avatar_2",  emoji: "🐺", label: "Wolf",     color: "#6C5CE7"),
        AvatarOption(id: "avatar_3",  emoji: "🦊", label: "Fox",      color: "#E17055"),
        AvatarOption(id: "avatar_4",  emoji: "🐻", label: "Bear",     color: "#795548"),
        AvatarOption(id: "avatar_5",  emoji: "🦅", label: "Eagle",    color: "#2980B9"),
        AvatarOption(id: "avatar_6",  emoji: "🐯", label: "Tiger",    color: "#F39C12"),
        AvatarOption(id: "avatar_7",  emoji: "🦈", label: "Shark",    color: "#1A6FA8"),
        AvatarOption(id: "avatar_8",  emoji: "🐉", label: "Dragon",   color: "#C0392B"),
        AvatarOption(id: "avatar_9",  emoji: "🦋", label: "Butterfly",color: "#8E44AD"),
        AvatarOption(id: "avatar_10", emoji: "🐸", label: "Frog",     color: "#27AE60"),
        AvatarOption(id: "avatar_11", emoji: "🦌", label: "Deer",     color: "#A0522D"),
        AvatarOption(id: "avatar_12", emoji: "🐼", label: "Panda",    color: "#555555"),
    ]

    static func find(_ id: String) -> AvatarOption {
        all.first { $0.id == id } ?? all[0]
    }
}
