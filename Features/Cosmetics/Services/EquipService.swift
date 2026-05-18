import Foundation
import Combine
import os.log

// ─── Equip Result ─────────────────────────────────────────────────────────────
//
// Mirrors the StorePurchaseService pattern (PurchaseError / PurchaseResult)
// so the view layer treats equip + purchase outcomes consistently.

enum EquipError: Error, Equatable {
    /// Cosmetic id is not in the local catalog. Defensive — view layer
    /// shouldn't be able to surface an equip affordance for an unknown id.
    case unknownCosmetic
    /// Server rejected the equip because the user doesn't own this
    /// cosmetic. Catches client/server inventory drift — the local cache
    /// said owned, server says no. iOS should re-sync on this error so
    /// future renders match server truth.
    case notOwned
    /// Server rejected the equip because the cosmetic's category doesn't
    /// match the requested slot. Should never happen in production (iOS
    /// passes `cosmetic.category` from the same catalog the server
    /// validates against); surfaces a client bug if it does.
    case categoryMismatch
    /// Generic network failure — wraps the underlying error's localized
    /// description. Doesn't re-export NetworkError so view code stays
    /// decoupled from the transport layer.
    case network(String)
}

enum EquipResult: Equatable {
    case success(CosmeticID, CosmeticCategory)
    case failure(EquipError)
}

// ─── Protocol ─────────────────────────────────────────────────────────────────

protocol EquipServiceProtocol: AnyObject {
    /// Equip a cosmetic in its own category. Server is authoritative —
    /// the local cache is only updated AFTER the backend confirms. No
    /// optimistic UI; we'd rather show a brief spinner than have to undo
    /// a local equip when the network rejects.
    func equip(_ cosmetic: Cosmetic) async -> EquipResult

    /// Clear whatever is equipped in the given category. Idempotent
    /// server-side, so calling unequip on an already-empty slot succeeds.
    func unequip(_ category: CosmeticCategory) async -> EquipResult

    /// Pull canonical inventory state from the server and overwrite the
    /// local cache wholesale. Called once after sign-in / app foreground
    /// so opponents-of-this-user (and the user themselves on a fresh
    /// device) immediately see the right equips. Throws on network
    /// failure; caller decides whether to retry or surface a toast.
    func syncFromServer() async throws

    /// Last-seen error, for view-layer toast binding. Cleared at the
    /// start of every new equip attempt.
    var lastError: EquipError? { get }
    var lastErrorPublisher: AnyPublisher<EquipError?, Never> { get }
}

// ─── Remote impl ──────────────────────────────────────────────────────────────
//
// Talks to /cosmetics/equip, /cosmetics/equip/:category, and
// /cosmetics/inventory. Mirrors RemoteStorePurchaseService — server call
// first, then local cache write so iOS state never diverges from server
// truth in the direction "iOS thinks equipped but server doesn't".

final class RemoteEquipService: EquipServiceProtocol, ObservableObject {

    @Published private(set) var lastError: EquipError? = nil

    var lastErrorPublisher: AnyPublisher<EquipError?, Never> {
        $lastError.eraseToAnyPublisher()
    }

    private let inventory: InventoryRepositoryProtocol
    private let network: NetworkInventoryPort

    private static let log = OSLog(subsystem: "com.stackpoker.cosmetics",
                                   category: "equip")

    init(inventory: InventoryRepositoryProtocol, network: NetworkInventoryPort) {
        self.inventory = inventory
        self.network = network
    }

    func equip(_ cosmetic: Cosmetic) async -> EquipResult {
        lastError = nil

        os_log("Equip attempt: %{public}@ (%{public}@)",
               log: Self.log, type: .info,
               cosmetic.id, cosmetic.category.rawValue)

        do {
            _ = try await network.postEquip(
                cosmeticId: cosmetic.id,
                category:   cosmetic.category.rawValue,
            )
        } catch let err as EquipError {
            return finalize(.failure(err), cosmeticId: cosmetic.id)
        } catch {
            return finalize(.failure(.network(error.localizedDescription)),
                            cosmeticId: cosmetic.id)
        }

        // Network confirmed → write local cache. inventory.equip enforces
        // its own "must own" guard locally; if that fails the server is
        // ahead of the local cache (probably a drift) — log and surface
        // notOwned so the caller can trigger a re-sync.
        let ok = inventory.equip(cosmetic.id, in: cosmetic.category)
        guard ok else {
            os_log("Local equip rejected after server success — cache drift? %{public}@",
                   log: Self.log, type: .error, cosmetic.id)
            return finalize(.failure(.notOwned), cosmeticId: cosmetic.id)
        }
        return finalize(.success(cosmetic.id, cosmetic.category),
                        cosmeticId: cosmetic.id)
    }

    func unequip(_ category: CosmeticCategory) async -> EquipResult {
        lastError = nil

        os_log("Unequip attempt: %{public}@", log: Self.log, type: .info,
               category.rawValue)

        do {
            try await network.deleteEquip(category: category.rawValue)
        } catch let err as EquipError {
            return finalize(.failure(err), cosmeticId: "—")
        } catch {
            return finalize(.failure(.network(error.localizedDescription)),
                            cosmeticId: "—")
        }

        // Capture what WAS equipped so we can return it in .success(...).
        // Unequip is idempotent server-side; the local slot may already
        // be empty if a previous attempt's network response was dropped.
        let wasEquipped = inventory.equippedItem(for: category) ?? ""
        inventory.unequip(category)
        return finalize(.success(wasEquipped, category), cosmeticId: wasEquipped)
    }

    func syncFromServer() async throws {
        os_log("Inventory sync from server", log: Self.log, type: .info)
        let (ownedIds, equipped) = try await network.getInventory()

        // Translate server's [String: String] equipped map into the typed
        // local form. Unknown category strings (forward-compat: server
        // might send a category iOS doesn't yet model) are dropped
        // silently — we'll pick them up on the next iOS release.
        var typed: [CosmeticCategory: CosmeticID] = [:]
        for (cat, id) in equipped {
            if let category = CosmeticCategory(rawValue: cat) {
                typed[category] = id
            }
        }
        inventory.replaceFromServer(ownedIds: Set(ownedIds), equipped: typed)
    }

    private func finalize(_ result: EquipResult, cosmeticId: CosmeticID) -> EquipResult {
        switch result {
        case .success(let id, let cat):
            os_log("Equip success: %{public}@ in %{public}@",
                   log: Self.log, type: .info, id, cat.rawValue)
        case .failure(let err):
            lastError = err
            os_log("Equip failed: %{public}@ — %{public}@",
                   log: Self.log, type: .error, cosmeticId, String(describing: err))
        }
        return result
    }
}

// ─── Network port ─────────────────────────────────────────────────────────────
//
// Narrow protocol around the three inventory-related backend calls. Lets
// the EquipService be tested with an in-memory fake without dragging in
// the full NetworkService. Production binding lives in
// NetworkInventoryPort+Live.swift.

protocol NetworkInventoryPort {
    /// POST /cosmetics/equip — returns (category, cosmeticId) on success.
    /// Throws an `EquipError` for product-meaningful failures
    /// (notOwned, categoryMismatch). Network/transport failures are
    /// surfaced as `EquipError.network(localizedDescription)`.
    func postEquip(cosmeticId: CosmeticID, category: String) async throws
        -> (category: String, cosmeticId: String)

    /// DELETE /cosmetics/equip/:category — idempotent.
    func deleteEquip(category: String) async throws

    /// GET /cosmetics/inventory — owned + equipped snapshot.
    func getInventory() async throws
        -> (ownedIds: [String], equipped: [String: String])
}
