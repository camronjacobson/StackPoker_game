import Foundation

// ─── Live network port ────────────────────────────────────────────────────────
//
// Adapter from `NetworkPurchasePort` (the narrow protocol owned by the
// cosmetics module) to the existing `NetworkService.shared` (the broad
// app-wide client). Keeps cosmetics code from depending on the entire
// NetworkService surface, which is the whole point of the port-and-adapter
// split.
//
// The /cosmetics/purchase endpoint lives in StackPoker-backend at
// src/cosmetics/cosmetics.routes.ts. This adapter assumes:
//   - POST /cosmetics/purchase
//   - Body: { "cosmeticId": "card_back_black_diamond",
//             "expectedPrice": "1000" }
//     expectedPrice is a BigInt-as-decimal-string; server enforces equality
//     with the canonical `priceChips` value and rejects with PRICE_MISMATCH
//     on drift. Critical safety check against client/catalog skew.
//   - Response: { "newBalance": "12345",
//                 "ownedCosmeticId": "card_back_black_diamond",
//                 "granted": true }
//     `ownedCosmeticId` is returned by the server but unused here — the
//     Decodable below ignores it.
//   - Errors mapped via NetworkError.serverError(code, message):
//       INSUFFICIENT_CHIPS        -> .insufficientFunds
//       ALREADY_OWNED             -> .alreadyOwned
//       COSMETIC_NOT_PURCHASABLE  -> .notPurchasable
//       COSMETIC_NOT_AVAILABLE    -> .limitedTimeExpired
//       COSMETIC_NOT_FOUND        -> .unknownCosmetic
//       PRICE_MISMATCH            -> .priceMismatch
//       RATE_LIMITED              -> .rateLimited
//       VALIDATION_ERROR          -> .validationError
//     Any other server code or network failure -> .network(<message>)

struct PurchaseCosmeticRequest: Encodable {
    let cosmeticId:    CosmeticID
    /// BigInt-as-decimal-string. Matches the server's canonical price
    /// representation so drift can be detected before chips move.
    let expectedPrice: String
}

struct PurchaseCosmeticResponse: Decodable {
    let newBalance: String     // BigInt-as-string, matches /chips/balance
    let granted:    Bool
}

final class LiveNetworkPurchasePort: NetworkPurchasePort {
    private let network: NetworkService

    init(network: NetworkService = .shared) {
        self.network = network
    }

    func postPurchase(cosmeticId: CosmeticID, expectedPrice: String) async throws -> String {
        let body = PurchaseCosmeticRequest(
            cosmeticId:    cosmeticId,
            expectedPrice: expectedPrice
        )
        do {
            let resp: PurchaseCosmeticResponse = try await network.request(
                .purchaseCosmetic, method: .POST, body: body
            )
            // Server may legitimately return granted: false in an "already
            // owned" race that we didn't catch client-side (rare; mostly if
            // two devices try to buy the same item simultaneously). Treat
            // that as alreadyOwned so the user gets a sensible message.
            if !resp.granted {
                throw PurchaseError.alreadyOwned
            }
            // Return the server-confirmed post-purchase balance so the
            // calling service can propagate it to AuthViewModel without a
            // second /auth/me round-trip.
            return resp.newBalance
        } catch let err as PurchaseError {
            throw err
        } catch let err as NetworkError {
            // Map server error codes to product-meaningful PurchaseError
            // cases. Anything we don't recognise falls through to .network
            // with the server's message — so future codes display "Purchase
            // failed: <server msg>" rather than crashing the client.
            if case let .serverError(code, message) = err {
                switch code {
                case "INSUFFICIENT_CHIPS":       throw PurchaseError.insufficientFunds
                case "ALREADY_OWNED":            throw PurchaseError.alreadyOwned
                case "COSMETIC_NOT_PURCHASABLE": throw PurchaseError.notPurchasable
                case "COSMETIC_NOT_AVAILABLE":   throw PurchaseError.limitedTimeExpired
                case "COSMETIC_NOT_FOUND":       throw PurchaseError.unknownCosmetic
                case "PRICE_MISMATCH":           throw PurchaseError.priceMismatch
                case "RATE_LIMITED":             throw PurchaseError.rateLimited
                case "VALIDATION_ERROR":         throw PurchaseError.validationError
                default:                         throw PurchaseError.network(message)
                }
            }
            throw PurchaseError.network(err.localizedDescription)
        }
    }
}
