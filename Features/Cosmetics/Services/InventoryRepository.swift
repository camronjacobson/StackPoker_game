import Foundation
import Combine
import os.log

// ─── Inventory Repository ─────────────────────────────────────────────────────
//
// Owns the per-user PlayerInventory and persists it. The view layer reads
// the @Published `inventory` snapshot; mutating methods produce a new
// snapshot, write to disk synchronously, then publish.
//
// Cardinal design rule (pinned during Phase 1 planning):
//   - This is the ONLY home for equipped state.
//   - It is NOT inside UserProfile.
//   - /auth/me refreshes do not touch this object.
// See Phase 1 design notes for the full rationale.

protocol InventoryRepositoryProtocol: AnyObject {
    /// Current snapshot for the active user. Defaults to .empty when no
    /// user is active (logged-out state).
    var inventory: PlayerInventory { get }

    /// Publisher counterpart to `inventory`, for SwiftUI / Combine sinks
    /// that want to react to changes.
    var inventoryPublisher: AnyPublisher<PlayerInventory, Never> { get }

    /// Tell the repository which user is now active. Triggers a flush of
    /// the in-memory inventory and a re-hydrate from the new key. Pass
    /// nil on logout. Idempotent — passing the same userId again is a
    /// no-op (the published value won't re-fire).
    func setActiveUser(_ userId: String?)

    /// Grant ownership of a cosmetic. Called by StorePurchaseService on
    /// successful purchase, and by future achievement / season-pass
    /// services. Idempotent; granting an already-owned item is a no-op.
    func own(_ id: CosmeticID)

    func isOwned(_ id: CosmeticID) -> Bool

    /// Equip an item. Returns true if the equip succeeded, false if the
    /// player doesn't own the item (defensive — the UI shouldn't surface
    /// the Equip button for un-owned items, but tests catch the case).
    @discardableResult
    func equip(_ id: CosmeticID, in category: CosmeticCategory) -> Bool

    func equippedItem(for category: CosmeticCategory) -> CosmeticID?

    func unequip(_ category: CosmeticCategory)
}

// ─── UserDefaults impl ────────────────────────────────────────────────────────

final class UserDefaultsInventoryRepository: InventoryRepositoryProtocol, ObservableObject {

    @Published private(set) var inventory: PlayerInventory = .empty

    var inventoryPublisher: AnyPublisher<PlayerInventory, Never> {
        $inventory.eraseToAnyPublisher()
    }

    private let defaults: UserDefaults
    private var activeUserId: String?

    private static let log = OSLog(subsystem: "com.stackpoker.cosmetics",
                                   category: "inventory")

    /// Key prefix for persisted inventory. The `v1` segment is the schema
    /// version — a future migration would write to a `v2` key and leave
    /// the v1 blob in place until we're confident the migration succeeded.
    private static let keyPrefix = "cosmetics.inventory.v1."

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // ── Active user lifecycle ────────────────────────────────────────────────

    func setActiveUser(_ userId: String?) {
        // Dedupe: same userId, nothing to do. Without this, every /auth/me
        // refresh that re-published the same UserProfile would cause a no-op
        // disk read + a synthetic @Published broadcast that re-renders every
        // view binding against `inventory`.
        if userId == activeUserId { return }

        os_log("Active user changed: %{public}@ -> %{public}@",
               log: Self.log, type: .info,
               activeUserId ?? "<nil>", userId ?? "<nil>")

        activeUserId = userId
        if let userId = userId {
            inventory = loadFromDisk(userId: userId)
        } else {
            // Logged out — reset the in-memory copy. Disk data for the
            // previous user is intentionally left intact so the next
            // sign-in for the same userId restores their items.
            inventory = .empty
        }
    }

    // ── Mutators ─────────────────────────────────────────────────────────────

    func own(_ id: CosmeticID) {
        guard let userId = activeUserId else {
            os_log("own(_:) called with no active user — refusing write",
                   log: Self.log, type: .error)
            return
        }
        guard !inventory.isOwned(id) else { return }    // idempotent
        let next = inventory.owning(id)
        persist(next, userId: userId)
        inventory = next
        os_log("Owned: %{public}@", log: Self.log, type: .info, id)
    }

    func isOwned(_ id: CosmeticID) -> Bool {
        inventory.isOwned(id)
    }

    @discardableResult
    func equip(_ id: CosmeticID, in category: CosmeticCategory) -> Bool {
        guard let userId = activeUserId else {
            os_log("equip(_:in:) called with no active user — refusing write",
                   log: Self.log, type: .error)
            return false
        }
        // Defensive — caller should have gated on isOwned, but we re-check
        // here so an integration mistake can't put non-owned ids into the
        // equipped dict (which would render an item the player can't
        // legitimately use).
        guard inventory.isOwned(id) else {
            os_log("equip rejected — %{public}@ not owned", log: Self.log, type: .error, id)
            return false
        }
        let next = inventory.equipping(id, in: category)
        persist(next, userId: userId)
        inventory = next
        os_log("Equipped %{public}@ in %{public}@",
               log: Self.log, type: .info, id, category.rawValue)
        return true
    }

    func equippedItem(for category: CosmeticCategory) -> CosmeticID? {
        inventory.equippedItem(for: category)
    }

    func unequip(_ category: CosmeticCategory) {
        guard let userId = activeUserId else {
            os_log("unequip(_:) called with no active user — refusing write",
                   log: Self.log, type: .error)
            return
        }
        guard inventory.equippedByCategory[category] != nil else { return }    // idempotent
        let next = inventory.unequipping(category)
        persist(next, userId: userId)
        inventory = next
        os_log("Unequipped %{public}@", log: Self.log, type: .info, category.rawValue)
    }

    // ── Persistence ──────────────────────────────────────────────────────────

    private func key(for userId: String) -> String {
        Self.keyPrefix + userId
    }

    private func loadFromDisk(userId: String) -> PlayerInventory {
        guard let data = defaults.data(forKey: key(for: userId)) else {
            os_log("No persisted inventory for user %{public}@ — using empty",
                   log: Self.log, type: .info, userId)
            return .empty
        }
        do {
            let decoded = try JSONDecoder().decode(PlayerInventory.self, from: data)
            // Version check. Older blobs are treated as empty rather than
            // crash-on-decode — this is the read side of the migration
            // policy described in PlayerInventory.swift.
            guard decoded.schemaVersion == PlayerInventory.currentSchemaVersion else {
                os_log("Inventory schema mismatch for user %{public}@ (disk=%d, expected=%d) — using empty",
                       log: Self.log, type: .error, userId,
                       decoded.schemaVersion, PlayerInventory.currentSchemaVersion)
                return .empty
            }
            return decoded
        } catch {
            os_log("Inventory decode failed for user %{public}@: %{public}@ — using empty",
                   log: Self.log, type: .error, userId, String(describing: error))
            return .empty
        }
    }

    private func persist(_ inv: PlayerInventory, userId: String) {
        do {
            let data = try JSONEncoder().encode(inv)
            defaults.set(data, forKey: key(for: userId))
        } catch {
            // Encoding can only fail if PlayerInventory's Codable conformance
            // breaks — which is a build-time concern, not a runtime one.
            // Logging keeps the failure visible if it ever does.
            os_log("Inventory encode failed: %{public}@",
                   log: Self.log, type: .fault, String(describing: error))
        }
    }
}
