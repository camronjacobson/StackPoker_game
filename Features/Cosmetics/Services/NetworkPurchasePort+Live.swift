import Foundation

// ─── Live network port ────────────────────────────────────────────────────────
//
// Adapter from `NetworkPurchasePort` (the narrow protocol owned by the
// cosmetics module) to the existing `NetworkService.shared` (the broad
// app-wide client). Keeps cosmetics code from depending on the entire
// NetworkService surface, which is the whole point of the port-and-adapter
// split.
//
// The /cosmetics/purchase endpoint is added in the same Phase 1 backend
// patch — see the "Backend changes" section of the Phase 1 summary for the
// route + handler + Prisma migration. This adapter assumes:
//   - POST /cosmetics/purchase
//   - Body: { "cosmeticId": "card_back_black_diamond" }
//   - Response: { "newBalance": "12345", "granted": true }
//   - Errors mapped via NetworkError.serverError(code, message):
//       INSUFFICIENT_FUNDS  -> .insufficientFunds
//       ALREADY_OWNED       -> .alreadyOwned
//       NOT_PURCHASABLE     -> .notPurchasable
//       LIMITED_EXPIRED     -> .limitedTimeExpired
//       UNKNOWN_COSMETIC    -> .unknownCosmetic
//     Any other server code or network failure -> .network(<message>)

struct PurchaseCosmeticRequest: Encodable {
    let cosmeticId: CosmeticID
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

    func postPurchase(cosmeticId: CosmeticID) async throws {
        let body = PurchaseCosmeticRequest(cosmeticId: cosmeticId)
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
        } catch let err as PurchaseError {
            throw err
        } catch let err as NetworkError {
            // Map server error codes to product-meaningful PurchaseError
            // cases. Anything we don't recognise falls through to .network.
            if case let .serverError(code, message) = err {
                switch code {
                case "INSUFFICIENT_FUNDS": throw PurchaseError.insufficientFunds
                case "ALREADY_OWNED":      throw PurchaseError.alreadyOwned
                case "NOT_PURCHASABLE":    throw PurchaseError.notPurchasable
                case "LIMITED_EXPIRED":    throw PurchaseError.limitedTimeExpired
                case "UNKNOWN_COSMETIC":   throw PurchaseError.unknownCosmetic
                default:                   throw PurchaseError.network(message)
                }
            }
            throw PurchaseError.network(err.localizedDescription)
        }
    }
}
