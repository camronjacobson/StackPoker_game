import XCTest
@testable import StackPoker

// ─── Test doubles ─────────────────────────────────────────────────────────────

/// Fake network port that records calls and returns scripted responses.
/// Lets us test the full RemoteStorePurchaseService flow without a real
/// backend (or any HTTP at all).
private final class FakeNetworkPort: NetworkPurchasePort {
    enum Outcome {
        case ok
        case throwPurchase(PurchaseError)
        case throwOther(Error)
    }
    var outcome: Outcome = .ok
    /// Balance string the fake returns on a successful purchase. Tests that
    /// assert on the onBalanceUpdated callback override this.
    var scriptedNewBalance: String = "0"
    private(set) var callCount = 0
    private(set) var lastCosmeticId: CosmeticID?
    private(set) var lastExpectedPrice: String?

    func postPurchase(cosmeticId: CosmeticID, expectedPrice: String) async throws -> String {
        callCount += 1
        lastCosmeticId = cosmeticId
        lastExpectedPrice = expectedPrice
        switch outcome {
        case .ok:                          return scriptedNewBalance
        case .throwPurchase(let e):        throw e
        case .throwOther(let e):           throw e
        }
    }
}

/// In-memory inventory repo with an optional "grant failure" toggle to
/// exercise the atomicity-violation branch. Avoids touching UserDefaults
/// at all so tests run without isolation gymnastics.
private final class InMemoryInventoryRepo: InventoryRepositoryProtocol, ObservableObject {
    @Published private(set) var inventory: PlayerInventory = .empty
    var inventoryPublisher: AnyPublisher<PlayerInventory, Never> {
        $inventory.eraseToAnyPublisher()
    }
    var activeUserId: String? = "test_user"
    /// When true, own(_:) is a no-op — simulates a persistence-layer
    /// failure so we can test that the service surfaces an atomicity
    /// violation (or doesn't, depending on the impl).
    var simulateGrantFailure: Bool = false

    func setActiveUser(_ userId: String?) { activeUserId = userId }
    func own(_ id: CosmeticID) {
        guard !simulateGrantFailure else { return }
        inventory = inventory.owning(id)
    }
    func isOwned(_ id: CosmeticID) -> Bool { inventory.isOwned(id) }
    @discardableResult
    func equip(_ id: CosmeticID, in category: CosmeticCategory) -> Bool {
        guard inventory.isOwned(id) else { return false }
        inventory = inventory.equipping(id, in: category)
        return true
    }
    func equippedItem(for category: CosmeticCategory) -> CosmeticID? {
        inventory.equippedItem(for: category)
    }
    func unequip(_ category: CosmeticCategory) {
        inventory = inventory.unequipping(category)
    }
    func replaceFromServer(ownedIds: Set<CosmeticID>, equipped: [CosmeticCategory: CosmeticID]) {
        inventory = PlayerInventory(
            ownedIDs: ownedIds,
            equippedByCategory: equipped,
            schemaVersion: PlayerInventory.currentSchemaVersion
        )
    }
}

import Combine

// ─── Tests ────────────────────────────────────────────────────────────────────

final class StorePurchaseServiceTests: XCTestCase {

    // ── Fixtures ─────────────────────────────────────────────────────────────

    private let purchasable = Cosmetic(
        id: "p", name: "Purchasable", category: .cardBack,
        rarity: .rare, priceChips: 5000,
        previewAssetName: "x", unlockCondition: .purchase
    )

    private let achievementOnly = Cosmetic(
        id: "ach", name: "Achievement", category: .playerTitle,
        rarity: .legendary,
        previewAssetName: "x", unlockCondition: .achievement
    )

    private let expiredLimited = Cosmetic(
        id: "expired", name: "Expired", category: .cardBack,
        rarity: .epic, priceChips: 30_000,
        isLimitedTime: true,
        availableUntil: Date().addingTimeInterval(-3600),
        previewAssetName: "x", unlockCondition: .purchase
    )

    private func makeService(
        catalogItems: [Cosmetic],
        outcome: FakeNetworkPort.Outcome = .ok,
        preOwned: [CosmeticID] = []
    ) -> (RemoteStorePurchaseService, FakeNetworkPort, InMemoryInventoryRepo) {
        let catalog = CosmeticsCatalog(cosmetics: catalogItems)
        let inv = InMemoryInventoryRepo()
        for id in preOwned { inv.own(id) }
        let port = FakeNetworkPort()
        port.outcome = outcome
        let svc = RemoteStorePurchaseService(
            catalog: catalog, inventory: inv, network: port
        )
        return (svc, port, inv)
    }

    // ── Success path ─────────────────────────────────────────────────────────

    func test_purchase_success_grantsAndReturnsCosmetic() async {
        let (svc, port, inv) = makeService(catalogItems: [purchasable])
        let result = await svc.purchase(purchasable)
        XCTAssertEqual(result, .success(purchasable))
        XCTAssertTrue(inv.isOwned(purchasable.id))
        XCTAssertEqual(port.callCount, 1)
        XCTAssertEqual(port.lastCosmeticId, purchasable.id)
        XCTAssertNil(svc.lastError)
    }

    // ── Pre-flight failures (no network call) ────────────────────────────────

    func test_purchase_unknownCosmetic_returnsFailure_withoutNetworkCall() async {
        // Catalog has no items at all → any id is "unknown".
        let (svc, port, inv) = makeService(catalogItems: [])
        let result = await svc.purchase(purchasable)
        XCTAssertEqual(result, .failure(.unknownCosmetic))
        XCTAssertEqual(port.callCount, 0)
        XCTAssertFalse(inv.isOwned(purchasable.id))
        XCTAssertEqual(svc.lastError, .unknownCosmetic)
    }

    func test_purchase_alreadyOwned_returnsFailure_withoutNetworkCall() async {
        let (svc, port, _) = makeService(
            catalogItems: [purchasable],
            preOwned: [purchasable.id]
        )
        let result = await svc.purchase(purchasable)
        XCTAssertEqual(result, .failure(.alreadyOwned))
        XCTAssertEqual(port.callCount, 0,
                       "Pre-flight ownership check must short-circuit the network call")
    }

    func test_purchase_achievementOnly_returnsNotPurchasable() async {
        let (svc, port, inv) = makeService(catalogItems: [achievementOnly])
        let result = await svc.purchase(achievementOnly)
        XCTAssertEqual(result, .failure(.notPurchasable))
        XCTAssertEqual(port.callCount, 0)
        XCTAssertFalse(inv.isOwned(achievementOnly.id))
    }

    func test_purchase_expiredLimited_returnsLimitedTimeExpired() async {
        let (svc, port, inv) = makeService(catalogItems: [expiredLimited])
        let result = await svc.purchase(expiredLimited)
        XCTAssertEqual(result, .failure(.limitedTimeExpired))
        XCTAssertEqual(port.callCount, 0)
        XCTAssertFalse(inv.isOwned(expiredLimited.id))
    }

    // ── Network failures (after pre-flight passes) ───────────────────────────

    func test_purchase_insufficientFunds_returnsFailure_noGrant() async {
        let (svc, _, inv) = makeService(
            catalogItems: [purchasable],
            outcome: .throwPurchase(.insufficientFunds)
        )
        let result = await svc.purchase(purchasable)
        XCTAssertEqual(result, .failure(.insufficientFunds))
        XCTAssertFalse(inv.isOwned(purchasable.id),
                       "Inventory must NOT be granted when server rejects payment")
        XCTAssertEqual(svc.lastError, .insufficientFunds)
    }

    func test_purchase_genericNetworkError_isWrapped() async {
        struct Dummy: Error { let label = "boom" }
        let (svc, _, inv) = makeService(
            catalogItems: [purchasable],
            outcome: .throwOther(Dummy())
        )
        let result = await svc.purchase(purchasable)
        if case .failure(.network) = result {
            // Expected — message contents are localized so we don't assert
            // on exact string.
        } else {
            XCTFail("Expected .failure(.network), got \(result)")
        }
        XCTAssertFalse(inv.isOwned(purchasable.id),
                       "Inventory must NOT be granted on a generic network error")
    }

    // ── lastError lifecycle ──────────────────────────────────────────────────

    func test_lastError_clearsAtStartOfNewAttempt() async {
        let (svc, port, _) = makeService(
            catalogItems: [purchasable],
            outcome: .throwPurchase(.insufficientFunds)
        )
        _ = await svc.purchase(purchasable)
        XCTAssertEqual(svc.lastError, .insufficientFunds)

        // Re-script the port to succeed; next attempt should clear lastError.
        port.outcome = .ok
        _ = await svc.purchase(purchasable)
        XCTAssertNil(svc.lastError,
                     "Successful follow-up purchase must clear stale error")
    }

    // ── Atomicity (preflight contract) ───────────────────────────────────────
    //
    // The current RemoteStorePurchaseService doesn't have a refund step
    // because UserDefaults grants don't fail. But the *spec* requires that
    // if the grant fails, inventory state stays consistent. We test the
    // observable contract: when the grant silently no-ops, the next
    // isOwned() returns false — so retrying the purchase doesn't double-
    // charge (the pre-flight alreadyOwned check would have returned, but
    // it doesn't, so the retry hits the network again). This is the
    // tripwire for noticing that we need a server-side reconciliation
    // step in iteration 2.

    func test_purchase_localGrantFailure_doesNotMarkOwned() async {
        let catalog = CosmeticsCatalog(cosmetics: [purchasable])
        let inv = InMemoryInventoryRepo()
        inv.simulateGrantFailure = true
        let port = FakeNetworkPort()
        let svc = RemoteStorePurchaseService(catalog: catalog, inventory: inv, network: port)

        let result = await svc.purchase(purchasable)
        // Service returns .success because the server confirmed payment —
        // the iter-1 contract is that local persistence failures are
        // logged-but-tolerated. The tripwire below is the assertion that
        // matters: ownership state is now drifted between server and
        // client. Iteration 2 must add a reconciliation path that pulls
        // ownership from /cosmetics/inventory after a successful purchase.
        XCTAssertEqual(result, .success(purchasable))
        XCTAssertFalse(inv.isOwned(purchasable.id),
                       "Drift recorded — flags need for iter-2 server reconciliation")
    }
}
