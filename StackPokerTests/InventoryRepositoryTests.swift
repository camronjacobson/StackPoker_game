import XCTest
@testable import StackPoker

final class InventoryRepositoryTests: XCTestCase {

    // Isolated UserDefaults suite per test so state can't leak between
    // tests OR back to the app's real UserDefaults.standard.
    private var defaults: UserDefaults!
    private let suiteName = "test.cosmetics.inventory"
    private var repo: UserDefaultsInventoryRepository!

    override func setUp() {
        super.setUp()
        UserDefaults().removePersistentDomain(forName: suiteName)
        defaults = UserDefaults(suiteName: suiteName)!
        repo = UserDefaultsInventoryRepository(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        repo = nil
        super.tearDown()
    }

    // ── Active-user lifecycle ────────────────────────────────────────────────

    func test_noActiveUser_writesAreNoOps() {
        // own() with no active user should not crash and should not persist
        // anything. setActiveUser(nil) means logged-out — writes refuse.
        repo.own("card_back_classic_red")
        XCTAssertFalse(repo.inventory.isOwned("card_back_classic_red"))
        XCTAssertTrue(repo.inventory.ownedIDs.isEmpty)
    }

    func test_setActiveUser_loadsEmptyForFreshUser() {
        repo.setActiveUser("user_alpha")
        XCTAssertEqual(repo.inventory, .empty)
    }

    func test_setActiveUser_loadsPersistedForReturningUser() {
        repo.setActiveUser("user_alpha")
        repo.own("card_back_vegas_neon")
        XCTAssertTrue(repo.inventory.isOwned("card_back_vegas_neon"))

        // Build a fresh repo against the same defaults → should reload from disk.
        let repo2 = UserDefaultsInventoryRepository(defaults: defaults)
        repo2.setActiveUser("user_alpha")
        XCTAssertTrue(repo2.inventory.isOwned("card_back_vegas_neon"))
    }

    func test_setActiveUser_switchingUserSwapsInventory() {
        repo.setActiveUser("user_alpha")
        repo.own("card_back_classic_red")

        repo.setActiveUser("user_beta")
        XCTAssertFalse(repo.inventory.isOwned("card_back_classic_red"),
                       "User B should not see User A's items")
        repo.own("card_back_classic_blue")

        repo.setActiveUser("user_alpha")
        XCTAssertTrue(repo.inventory.isOwned("card_back_classic_red"),
                      "User A's items must be restored on re-login")
        XCTAssertFalse(repo.inventory.isOwned("card_back_classic_blue"),
                       "User A should not see User B's items")
    }

    func test_setActiveUser_sameUserIsIdempotent() {
        // Setting the same user twice should not re-load from disk or
        // re-broadcast — checked indirectly by counting publisher fires.
        var firings = 0
        let cancellable = repo.inventoryPublisher.sink { _ in firings += 1 }

        repo.setActiveUser("user_alpha")
        let baseline = firings
        repo.setActiveUser("user_alpha")    // idempotent
        XCTAssertEqual(firings, baseline,
                       "Re-setting same user must not re-publish inventory")
        cancellable.cancel()
    }

    func test_logout_clearsInMemoryButPreservesDisk() {
        repo.setActiveUser("user_alpha")
        repo.own("card_back_royal_gold")
        repo.setActiveUser(nil)                // logout
        XCTAssertEqual(repo.inventory, .empty)

        // Re-login: items should still be there.
        repo.setActiveUser("user_alpha")
        XCTAssertTrue(repo.inventory.isOwned("card_back_royal_gold"))
    }

    // ── Ownership semantics ──────────────────────────────────────────────────

    func test_own_idempotent() {
        repo.setActiveUser("u")
        repo.own("x")
        repo.own("x")
        XCTAssertEqual(repo.inventory.ownedIDs.count, 1)
    }

    func test_isOwned() {
        repo.setActiveUser("u")
        XCTAssertFalse(repo.isOwned("x"))
        repo.own("x")
        XCTAssertTrue(repo.isOwned("x"))
    }

    // ── Equip semantics ──────────────────────────────────────────────────────

    func test_equip_rejectsUnownedItem() {
        repo.setActiveUser("u")
        let ok = repo.equip("x", in: .cardBack)
        XCTAssertFalse(ok)
        XCTAssertNil(repo.equippedItem(for: .cardBack))
    }

    func test_equip_succeedsForOwnedItem() {
        repo.setActiveUser("u")
        repo.own("x")
        let ok = repo.equip("x", in: .cardBack)
        XCTAssertTrue(ok)
        XCTAssertEqual(repo.equippedItem(for: .cardBack), "x")
    }

    func test_equip_replacesPreviousInSameCategory() {
        repo.setActiveUser("u")
        repo.own("a"); repo.own("b")
        repo.equip("a", in: .cardBack)
        repo.equip("b", in: .cardBack)
        XCTAssertEqual(repo.equippedItem(for: .cardBack), "b")
    }

    func test_equip_independentAcrossCategories() {
        repo.setActiveUser("u")
        repo.own("cb_red"); repo.own("frame_gold")
        repo.equip("cb_red",     in: .cardBack)
        repo.equip("frame_gold", in: .avatarFrame)
        XCTAssertEqual(repo.equippedItem(for: .cardBack),    "cb_red")
        XCTAssertEqual(repo.equippedItem(for: .avatarFrame), "frame_gold")
    }

    func test_unequip_removesItem() {
        repo.setActiveUser("u")
        repo.own("x")
        repo.equip("x", in: .cardBack)
        repo.unequip(.cardBack)
        XCTAssertNil(repo.equippedItem(for: .cardBack))
    }

    func test_unequip_idempotent() {
        repo.setActiveUser("u")
        repo.unequip(.cardBack)    // no-op, must not crash
        XCTAssertNil(repo.equippedItem(for: .cardBack))
    }

    // ── Persistence schema version ───────────────────────────────────────────

    func test_loadFromDisk_returnsEmptyOnSchemaMismatch() {
        // Manually write a blob with a future schema version. The repo
        // should treat it as empty rather than crash or corrupt-load.
        struct Stale: Codable {
            let ownedIDs: [String]
            let equippedByCategory: [String: String]
            let schemaVersion: Int
        }
        let stale = Stale(
            ownedIDs: ["card_back_classic_red"],
            equippedByCategory: [:],
            schemaVersion: 999
        )
        let data = try! JSONEncoder().encode(stale)
        defaults.set(data, forKey: "cosmetics.inventory.v1.user_alpha")

        repo.setActiveUser("user_alpha")
        XCTAssertEqual(repo.inventory, .empty,
                       "Schema-mismatched blob must load as empty")
    }
}
