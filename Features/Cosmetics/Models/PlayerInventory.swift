import Foundation

// ─── Player Inventory ─────────────────────────────────────────────────────────
//
// The local-side ownership + equipped-slot record. This is the value type
// that the InventoryRepository owns and persists; the view layer reads from
// the repository's @Published copy of it.
//
// Critical design point pinned down in the Phase 1 plan: this struct
// intentionally does NOT live inside `UserProfile`. `/auth/me` refreshes
// only replace `UserProfile`, so they cannot touch the inventory. The two
// objects are decoupled at every layer.
//
// `schemaVersion` lets us bump persistence format later without orphaning
// stored data — a future v2 migration step checks `schemaVersion == 1` and
// re-keys / re-shapes the persisted blob. The key on disk also encodes v1
// (see UserDefaultsInventoryRepository) so a v2 rollout is a deliberate
// key migration, not an in-place overwrite.

struct PlayerInventory: Codable, Equatable {
    /// Set of cosmetic IDs the player owns. We use Set rather than [String]
    /// because every operation that matters (isOwned, contains-checks while
    /// rendering the store grid, "Owned" badge resolution) is a membership
    /// query — O(1) vs O(n) for an array, and the store grid renders all 60+
    /// items at once.
    var ownedIDs: Set<CosmeticID>

    /// Currently equipped item per category. Categories with no equipped
    /// item (i.e. player is using the default) are simply absent from the
    /// dictionary — we do NOT store `nil` values. This keeps the persisted
    /// JSON minimal and means "no equipped frame" is the natural empty
    /// state, requiring no special-case initialization.
    var equippedByCategory: [CosmeticCategory: CosmeticID]

    /// Persistence format version. Bump when the on-disk shape changes.
    /// Always 1 in this iteration. Reading code tolerates older versions
    /// by treating them as empty inventories (intentional — we'd rather
    /// re-grant items from the server in iter 2 than corrupt-load).
    let schemaVersion: Int

    static let currentSchemaVersion = 1

    /// Convenience empty inventory — used when no persisted blob exists
    /// for the active user (first install, fresh account, or no active
    /// user). Distinct from the "logged-out" sentinel that the repository
    /// uses internally; this is just the data shape.
    static let empty = PlayerInventory(
        ownedIDs: [],
        equippedByCategory: [:],
        schemaVersion: currentSchemaVersion
    )

    init(ownedIDs: Set<CosmeticID> = [],
         equippedByCategory: [CosmeticCategory: CosmeticID] = [:],
         schemaVersion: Int = PlayerInventory.currentSchemaVersion) {
        self.ownedIDs = ownedIDs
        self.equippedByCategory = equippedByCategory
        self.schemaVersion = schemaVersion
    }

    // ── Queries ──────────────────────────────────────────────────────────────

    func isOwned(_ id: CosmeticID) -> Bool {
        ownedIDs.contains(id)
    }

    func equippedItem(for category: CosmeticCategory) -> CosmeticID? {
        equippedByCategory[category]
    }

    func isEquipped(_ id: CosmeticID, in category: CosmeticCategory) -> Bool {
        equippedByCategory[category] == id
    }

    // ── Mutators ─────────────────────────────────────────────────────────────
    //
    // These return a *new* PlayerInventory rather than mutating self,
    // because the repository pattern hands the inventory back as an
    // immutable snapshot to view consumers. The repository internally
    // owns the mutable storage and broadcasts the new snapshot via
    // @Published, which only fires when the value type's identity changes —
    // value-semantics guarantees a clean diff.

    func owning(_ id: CosmeticID) -> PlayerInventory {
        var copy = self
        copy.ownedIDs.insert(id)
        return copy
    }

    func equipping(_ id: CosmeticID, in category: CosmeticCategory) -> PlayerInventory {
        var copy = self
        copy.equippedByCategory[category] = id
        return copy
    }

    func unequipping(_ category: CosmeticCategory) -> PlayerInventory {
        var copy = self
        copy.equippedByCategory.removeValue(forKey: category)
        return copy
    }
}
