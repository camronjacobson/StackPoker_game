import Foundation
import Security

// ─── Keychain Manager ─────────────────────────────────────────────────────────

final class KeychainManager {
    static let shared = KeychainManager()

    private let service = "com.stackpoker.app"

    private init() {}

    enum Key: String {
        case accessToken   = "access_token"
        case refreshToken  = "refresh_token"
        case userId        = "user_id"
        case username      = "username"
    }

    // ─── Save ──────────────────────────────────────────────────────────────────

    @discardableResult
    func save(_ value: String, for key: Key) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key.rawValue,
            kSecValueData:   data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        // Delete existing entry first
        SecItemDelete(query as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    // ─── Load ──────────────────────────────────────────────────────────────────

    func load(_ key: Key) -> String? {
        let query: [CFString: Any] = [
            kSecClass:            kSecClassGenericPassword,
            kSecAttrService:      service,
            kSecAttrAccount:      key.rawValue,
            kSecReturnData:       true,
            kSecMatchLimit:       kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }

        return string
    }

    // ─── Delete ────────────────────────────────────────────────────────────────

    @discardableResult
    func delete(_ key: Key) -> Bool {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key.rawValue,
        ]
        return SecItemDelete(query as CFDictionary) == errSecSuccess
    }

    // ─── Clear All ─────────────────────────────────────────────────────────────

    func clearAll() {
        Key.allCases.forEach { delete($0) }
    }

    // ─── Auth Token Helpers ────────────────────────────────────────────────────

    func saveTokens(access: String, refresh: String) {
        save(access, for: .accessToken)
        save(refresh, for: .refreshToken)
    }

    var accessToken: String?  { load(.accessToken) }
    var refreshToken: String? { load(.refreshToken) }
    var userId: String?       { load(.userId) }
    var username: String?     { load(.username) }

    var hasValidSession: Bool { accessToken != nil && refreshToken != nil }
}

extension KeychainManager.Key: CaseIterable {}
