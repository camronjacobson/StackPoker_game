import Foundation

// ─── Live inventory network port ──────────────────────────────────────────────
//
// Adapter from `NetworkInventoryPort` (the narrow protocol owned by the
// cosmetics module) to the existing `NetworkService.shared`. Mirrors
// LiveNetworkPurchasePort — the cosmetics feature only sees its own port,
// keeping app-wide NetworkService coupling at a single seam.
//
// Backend lives in StackPoker-backend at src/cosmetics/cosmetics.routes.ts:
//   - POST   /cosmetics/equip
//     Body: { "cosmeticId": "...", "category": "cardBack" }
//     Response: { "category": "...", "cosmeticId": "..." }
//   - DELETE /cosmetics/equip/:category
//     Response: { "category": "...", "cosmeticId": null }     (unused here)
//   - GET    /cosmetics/inventory
//     Response: { "ownedIds": [...], "equipped": { "<cat>": "<id>", ... } }
//
// Server error code -> EquipError mapping:
//   COSMETIC_NOT_FOUND  -> .unknownCosmetic
//   NOT_OWNED           -> .notOwned
//   CATEGORY_MISMATCH   -> .categoryMismatch
//   Anything else / network failure -> .network(<message>)

struct EquipCosmeticRequest: Encodable {
    let cosmeticId: CosmeticID
    let category:   String
}

struct EquipCosmeticResponse: Decodable {
    let category:   String
    let cosmeticId: String
}

struct InventoryResponse: Decodable {
    let ownedIds: [String]
    /// Server sends an empty object `{}` (never absent) when nothing is
    /// equipped — see Phase 4 contract in cosmetics.service.ts. That
    /// guarantee lets us declare this non-optional.
    let equipped: [String: String]
}

final class LiveNetworkInventoryPort: NetworkInventoryPort {
    private let network: NetworkService

    init(network: NetworkService = .shared) {
        self.network = network
    }

    func postEquip(cosmeticId: CosmeticID, category: String) async throws
        -> (category: String, cosmeticId: String)
    {
        let body = EquipCosmeticRequest(cosmeticId: cosmeticId, category: category)
        do {
            let resp: EquipCosmeticResponse = try await network.request(
                .equipCosmetic, method: .POST, body: body
            )
            return (category: resp.category, cosmeticId: resp.cosmeticId)
        } catch let err as NetworkError {
            throw Self.mapServerError(err)
        } catch {
            throw EquipError.network(error.localizedDescription)
        }
    }

    func deleteEquip(category: String) async throws {
        do {
            try await network.requestVoid(
                .unequipCosmetic(category: category), method: .DELETE
            )
        } catch let err as NetworkError {
            throw Self.mapServerError(err)
        } catch {
            throw EquipError.network(error.localizedDescription)
        }
    }

    func getInventory() async throws
        -> (ownedIds: [String], equipped: [String: String])
    {
        do {
            let resp: InventoryResponse = try await network.request(
                .cosmeticsInventory, method: .GET
            )
            return (ownedIds: resp.ownedIds, equipped: resp.equipped)
        } catch let err as NetworkError {
            throw Self.mapServerError(err)
        } catch {
            throw EquipError.network(error.localizedDescription)
        }
    }

    // ── Error mapping ────────────────────────────────────────────────────────
    //
    // Centralised so the three endpoints stay in sync if the server adds
    // a new product-meaningful code. Unrecognised codes fall through as
    // `.network(message)` — the user sees the server's text rather than
    // a crash, which keeps the app forward-compatible with new backend
    // versions during a phased rollout.

    private static func mapServerError(_ err: NetworkError) -> EquipError {
        if case let .serverError(code, message) = err {
            switch code {
            case "COSMETIC_NOT_FOUND": return .unknownCosmetic
            case "NOT_OWNED":          return .notOwned
            case "CATEGORY_MISMATCH":  return .categoryMismatch
            default:                   return .network(message)
            }
        }
        return .network(err.localizedDescription)
    }
}
