import Foundation
import Combine

// ─── API Configuration ────────────────────────────────────────────────────────

enum APIConfig {
    // Toggle between local and production:
    //   Local (simulator): "http://localhost:3000"
    //   Local (real device on Wi-Fi): "http://192.168.0.55:3000"
    //   Production: "https://your-app.up.railway.app"
    private static let host = "http://192.168.0.55:3000"

    static let baseURL = host + "/api"
    static let wsURL   = host.replacingOccurrences(of: "http", with: "ws")

    static let timeout: TimeInterval = 15
}

// ─── HTTP Method ──────────────────────────────────────────────────────────────

enum HTTPMethod: String {
    case GET, POST, PUT, PATCH, DELETE
}

// ─── API Endpoint ─────────────────────────────────────────────────────────────

enum APIEndpoint {
    // Auth
    case register
    case login
    case appleAuth
    case refresh
    case logout
    case checkUsername(String)
    case me

    // Users
    case userProfile(id: String)
    case updateProfile

    // Lobby
    case tables
    case createTable
    case joinTable(code: String)
    case tableDetail(id: String)
    case leaveTable(id: String)
    case closeTable(id: String)
    case topUpChips(tableId: String)

    // Friends
    case friends
    case sendFriendRequest(userId: String)
    case respondFriendRequest(id: String)
    case searchUsers(query: String)

    // Clubs
    case clubs
    case createClub
    case joinClub(code: String)
    case clubDetail(id: String)
    case clubLeaderboard(id: String)
    case clubMessages(id: String)

    // Chips
    case chipBalance
    case chipHistory
    case dailyBonus
    case transferChips

    // Invites
    case tableInvites
    case respondInvite(id: String)
    case sendInvite(tableId: String)

    // Bot
    case addBot(tableId: String)

    // Admin
    case adminKick(tableId: String, userId: String)
    case adminBan(userId: String)
    case adminReset(tableId: String)
    case adminGrantChips(userId: String)

    var path: String {
        switch self {
        case .register:              return "/auth/register"
        case .login:                 return "/auth/login"
        case .appleAuth:             return "/auth/apple"
        case .refresh:               return "/auth/refresh"
        case .logout:                return "/auth/logout"
        case .checkUsername(let u):  return "/auth/username/check?username=\(u)"
        case .me:                    return "/auth/me"
        case .userProfile(let id):   return "/users/\(id)"
        case .updateProfile:         return "/auth/me"
        case .tables:                return "/tables"
        case .createTable:           return "/tables"
        case .joinTable(let code):   return "/tables/join/\(code)"
        case .tableDetail(let id):   return "/tables/\(id)"
        case .leaveTable(let id):    return "/tables/\(id)/leave"
        case .closeTable(let id):    return "/tables/\(id)/close"
        case .topUpChips(let id):    return "/tables/\(id)/topup"
        case .friends:               return "/friends"
        case .sendFriendRequest(let id): return "/friends/request/\(id)"
        case .respondFriendRequest(let id): return "/friends/\(id)/respond"
        case .searchUsers(let q):    return "/users/search?q=\(q)"
        case .clubs:                 return "/clubs"
        case .createClub:            return "/clubs"
        case .joinClub(let code):    return "/clubs/join/\(code)"
        case .clubDetail(let id):    return "/clubs/\(id)"
        case .clubLeaderboard(let id): return "/clubs/\(id)/leaderboard"
        case .clubMessages(let id):  return "/clubs/\(id)/messages"
        case .chipBalance:           return "/chips/balance"
        case .chipHistory:           return "/chips/history"
        case .dailyBonus:            return "/chips/daily"
        case .transferChips:         return "/chips/transfer"
        case .tableInvites:                return "/tables/invites/pending"
        case .respondInvite(let id):       return "/tables/invites/\(id)/respond"
        case .sendInvite(let tid):         return "/tables/\(tid)/invite"
        case .addBot(let tid):             return "/tables/\(tid)/add-bot"
        case .adminKick(let tid, _): return "/admin/tables/\(tid)/kick"
        case .adminBan(let uid):           return "/admin/users/\(uid)/ban"
        case .adminReset(let tid):         return "/admin/tables/\(tid)/reset"
        case .adminGrantChips(let uid):    return "/admin/users/\(uid)/grant-chips"
        }
    }
}

// ─── Network Error ────────────────────────────────────────────────────────────

enum NetworkError: LocalizedError {
    case noInternet
    case timeout
    case serverError(code: String, message: String)
    case unauthorized
    case notFound
    case decodingError
    case unknown(Int)

    var errorDescription: String? {
        switch self {
        case .noInternet:             return "No internet connection"
        case .timeout:                return "Request timed out"
        case .serverError(_, let m):  return m
        case .unauthorized:           return "Session expired. Please log in again."
        case .notFound:               return "Not found"
        case .decodingError:          return "Failed to parse server response"
        case .unknown(let code):      return "Server error (\(code))"
        }
    }
}

// ─── API Response Wrapper ─────────────────────────────────────────────────────

struct APIResponse<T: Decodable>: Decodable {
    let success: Bool
    let data: T?
    let error: APIErrorBody?
}

struct APIResponseEmpty: Decodable {
    let success: Bool
    let error: APIErrorBody?
}

struct APIErrorBody: Decodable {
    let code: String
    let message: String
    let field: String?
}

// ─── Network Service ──────────────────────────────────────────────────────────

@MainActor
final class NetworkService: ObservableObject {
    static let shared = NetworkService()

    private let session: URLSession
    private let decoder: JSONDecoder

    // Auth token injected by TokenManager
    var accessToken: String?

    // Refresh callback — set by AuthViewModel
    var onTokenExpired: (() async -> Bool)?

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = APIConfig.timeout
        config.timeoutIntervalForResource = APIConfig.timeout * 2
        config.httpAdditionalHeaders = [
            "Content-Type": "application/json",
            "Accept": "application/json",
            "X-App-Version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
        ]
        self.session = URLSession(configuration: config)

        self.decoder = JSONDecoder()
        self.decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder.dateDecodingStrategy = .iso8601
    }

    // ─── Core Request ──────────────────────────────────────────────────────────

    func request<T: Decodable>(
        _ endpoint: APIEndpoint,
        method: HTTPMethod = .GET,
        body: Encodable? = nil,
        requiresAuth: Bool = true,
        retryOnExpiry: Bool = true
    ) async throws -> T {
        let urlString = APIConfig.baseURL + endpoint.path
        guard let url = URL(string: urlString) else {
            throw NetworkError.unknown(0)
        }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue

        // Attach body
        if let body {
            request.httpBody = try JSONEncoder().encode(body)
        }

        // Attach auth header
        if requiresAuth, let token = accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        // Device headers
        request.setValue(UIDevice.current.identifierForVendor?.uuidString, forHTTPHeaderField: "X-Device-ID")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw NetworkError.unknown(0)
            }

            if http.statusCode == 404 { throw NetworkError.notFound }

            // Parse response (needed before deciding how to handle 401)
            let apiResponse = try decoder.decode(APIResponse<T>.self, from: data)

            // Handle 401: if the server returned a structured error body (e.g. INVALID_CREDENTIALS),
            // surface that message directly. Only treat as "session expired" for bare 401s from the
            // auth middleware (no meaningful error body, or explicit SESSION_EXPIRED/UNAUTHORIZED codes).
            if http.statusCode == 401 {
                if let err = apiResponse.error,
                   err.code != "SESSION_EXPIRED" && err.code != "UNAUTHORIZED" && err.code != "INVALID_TOKEN" {
                    // Structured error — show the real message (e.g. "Invalid email or password")
                    throw NetworkError.serverError(code: err.code, message: err.message)
                }
                // Bare 401 or token-expiry — attempt silent refresh then retry
                if retryOnExpiry {
                    if let refresh = onTokenExpired, await refresh() {
                        return try await self.request(endpoint, method: method, body: body, requiresAuth: requiresAuth, retryOnExpiry: false)
                    }
                }
                throw NetworkError.unauthorized
            }

            if apiResponse.success, let data = apiResponse.data {
                return data
            }

            if let err = apiResponse.error {
                throw NetworkError.serverError(code: err.code, message: err.message)
            }

            throw NetworkError.unknown(http.statusCode)

        } catch let err as NetworkError {
            throw err
        } catch let err as URLError {
            switch err.code {
            case .notConnectedToInternet, .networkConnectionLost:
                throw NetworkError.noInternet
            case .timedOut:
                throw NetworkError.timeout
            default:
                throw NetworkError.unknown(err.errorCode)
            }
        } catch is DecodingError {
            throw NetworkError.decodingError
        }
    }

    // Void response variant
    func requestVoid(
        _ endpoint: APIEndpoint,
        method: HTTPMethod = .POST,
        body: Encodable? = nil,
        requiresAuth: Bool = true
    ) async throws {
        let _: EmptyResponse = try await request(endpoint, method: method, body: body, requiresAuth: requiresAuth)
    }
}

private struct EmptyResponse: Decodable {}

// ─── UIDevice import shim for non-UIKit contexts ──────────────────────────────
#if canImport(UIKit)
import UIKit
#endif
