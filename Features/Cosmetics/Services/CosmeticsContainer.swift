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
    /// Server-authoritative equip/unequip + inventory sync. View layer
    /// always routes through this — direct `inventory.equip(...)` calls
    /// from the UI are forbidden (the local cache is downstream of server
    /// truth now). The InventoryRepository protocol still exposes `equip`
    /// because EquipService itself needs to update the cache after a
    /// successful network round-trip.
    let equipService: EquipServiceProtocol
    /// Optional progress feed for achievement-gated cosmetics. Phase 2
    /// ships a stub that always returns nil; Phase 5 supplies a real
    /// implementation backed by the achievements store.
    let achievementProgress: AchievementProgressSource

    private var cancellables: Set<AnyCancellable> = []

    init(catalog: CosmeticsCatalogProtocol,
         inventory: InventoryRepositoryProtocol,
         purchaseService: StorePurchaseServiceProtocol,
         equipService: EquipServiceProtocol,
         achievementProgress: AchievementProgressSource = StubAchievementProgressSource()) {
        self.catalog = catalog
        self.inventory = inventory
        self.purchaseService = purchaseService
        self.equipService = equipService
        self.achievementProgress = achievementProgress
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
        let equip = RemoteEquipService(
            inventory: inventory,
            network:   LiveNetworkInventoryPort()
        )
        return CosmeticsContainer(
            catalog:         catalog,
            inventory:       inventory,
            purchaseService: purchase,
            equipService:    equip
        )
    }

    /// Pull canonical inventory state from the server. Called from the
    /// composition root after auth resolves and on app foreground —
    /// failures are swallowed (logged inside EquipService) because the
    /// local cache from disk is a tolerable fallback. Subsequent equip
    /// attempts will surface fresh server errors on their own.
    func syncInventoryFromServer() async {
        do { try await equipService.syncFromServer() }
        catch { /* logged inside EquipService */ }
    }

    /// Forwards the active userId from auth to the inventory repository,
    /// and triggers a one-shot server sync whenever a non-nil userId
    /// arrives (login, app cold-start with stored session, account switch).
    /// `removeDuplicates` ensures re-emissions of the same userId don't
    /// re-fire the sync — `setActiveUser` is also dedupe-guarded inside
    /// the repository, so both writes are safe to re-emit.
    /// App-foreground re-sync is deliberately NOT handled here — see
    /// TECH_DEBT.md "Phase 5: app-foreground inventory refresh".
    func bindToActiveUser<P: Publisher>(_ publisher: P)
        where P.Output == String?, P.Failure == Never
    {
        publisher
            .removeDuplicates()
            .sink { [weak self] userId in
                guard let self else { return }
                self.inventory.setActiveUser(userId)
                if userId != nil {
                    Task { [weak self] in
                        await self?.syncInventoryFromServer()
                    }
                }
            }
            .store(in: &cancellables)
    }

    /// Installs a callback that the remote purchase service invokes with
    /// the server-confirmed new chip balance after every successful
    /// purchase. Wired from the composition root because `AuthViewModel`
    /// and `CosmeticsContainer` are sibling @StateObjects and can't
    /// reference each other at init time — the bridge has to be deferred
    /// to `.onAppear`. The cast no-ops cleanly for the local-stub purchase
    /// service (which manages its own simulated balance and doesn't need
    /// to talk back to AuthViewModel).
    func setBalanceUpdater(_ updater: @escaping @MainActor (String) -> Void) {
        (purchaseService as? RemoteStorePurchaseService)?.onBalanceUpdated = updater
    }
}
