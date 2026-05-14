import Foundation
import Combine
import SwiftUI

// ─── Cosmetics Container ──────────────────────────────────────────────────────
//
// Single DI container ObservableObject for the cosmetics module. Created
// at the app root and injected via @EnvironmentObject — matches the pattern
// used by AppState / AuthViewModel / SubscriptionManager elsewhere in the
// app, so wiring the cosmetics container into StackPokerApp.swift is a
// one-line addition.
//
// The container holds *concrete* service references typed to their
// protocols, so view code reads through the protocols (testable, swappable)
// while production wires up to the real impls.
//
// IMPORTANT: This container also bridges Auth → cosmetics. It subscribes
// to the active userId from a CurrentValueSubject that the auth layer
// pumps into; that subject is the *only* coupling between Auth and
// Cosmetics. Phase-1 wiring at the app root is a single statement:
//   cosmetics.bindToActiveUser(authViewModel.$userProfile.map { $0?.id })

@MainActor
final class CosmeticsContainer: ObservableObject {

    let catalog: CosmeticsCatalogProtocol
    let inventory: InventoryRepositoryProtocol
    let purchaseService: StorePurchaseServiceProtocol

    private var cancellables: Set<AnyCancellable> = []

    init(catalog: CosmeticsCatalogProtocol,
         inventory: InventoryRepositoryProtocol,
         purchaseService: StorePurchaseServiceProtocol) {
        self.catalog = catalog
        self.inventory = inventory
        self.purchaseService = purchaseService
    }

    /// Convenience factory for the production wire-up. Loads the bundled
    /// catalog, builds a UserDefaults-backed inventory, and uses the
    /// remote purchase service against the live backend port.
    ///
    /// The choice between `RemoteStorePurchaseService` and
    /// `LocalStubPurchaseService` lives here so the rest of the app
    /// doesn't grow a compile-time switch for it.
    static func makeProduction() -> CosmeticsContainer {
        let catalog   = CosmeticsCatalog()
        let inventory = UserDefaultsInventoryRepository()
        let purchase  = RemoteStorePurchaseService(
            catalog:   catalog,
            inventory: inventory,
            network:   LiveNetworkPurchasePort()
        )
        return CosmeticsContainer(
            catalog:         catalog,
            inventory:       inventory,
            purchaseService: purchase
        )
    }

    /// Forwards the active userId from auth to the inventory repository.
    /// Pass a publisher that emits the current userId (or nil when logged
    /// out). Subscribed via Combine — `setActiveUser` is dedupe-guarded
    /// inside the repository so a re-emitted same-userId is a no-op.
    func bindToActiveUser<P: Publisher>(_ publisher: P)
        where P.Output == String?, P.Failure == Never
    {
        publisher
            .removeDuplicates()
            .sink { [weak self] userId in
                self?.inventory.setActiveUser(userId)
            }
            .store(in: &cancellables)
    }
}
