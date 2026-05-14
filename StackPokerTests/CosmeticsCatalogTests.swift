import XCTest
@testable import StackPoker

final class CosmeticsCatalogTests: XCTestCase {

    // ── Test fixtures ────────────────────────────────────────────────────────

    private func makeCatalog(_ items: [Cosmetic]) -> CosmeticsCatalog {
        CosmeticsCatalog(cosmetics: items)
    }

    private let evergreen = Cosmetic(
        id: "evergreen_1", name: "Evergreen", category: .cardBack,
        rarity: .common, priceChips: 1000,
        previewAssetName: "x", unlockCondition: .purchase
    )

    private let liveDrop = Cosmetic(
        id: "live_1", name: "Live", category: .cardBack,
        rarity: .epic, priceChips: 30000,
        isLimitedTime: true,
        availableUntil: Date().addingTimeInterval(3600),
        previewAssetName: "x", unlockCondition: .purchase
    )

    private let expiredDrop = Cosmetic(
        id: "expired_1", name: "Expired", category: .cardBack,
        rarity: .epic, priceChips: 30000,
        isLimitedTime: true,
        availableUntil: Date().addingTimeInterval(-3600),
        previewAssetName: "x", unlockCondition: .purchase
    )

    private let achievementTitle = Cosmetic(
        id: "title_rookie_test", name: "Rookie", category: .playerTitle,
        rarity: .common,
        previewAssetName: "x", unlockCondition: .achievement
    )

    // ── id lookup ────────────────────────────────────────────────────────────

    func test_cosmeticById_returnsItem_whenPresent() {
        let catalog = makeCatalog([evergreen])
        XCTAssertEqual(catalog.cosmetic(id: "evergreen_1")?.name, "Evergreen")
    }

    func test_cosmeticById_returnsNil_whenAbsent() {
        let catalog = makeCatalog([evergreen])
        XCTAssertNil(catalog.cosmetic(id: "nonexistent"))
    }

    func test_duplicateIds_lastWinsAndLogs() {
        // Two items with same id — last one wins. Catalog still loads.
        let dup = Cosmetic(
            id: "evergreen_1", name: "DuplicateLater", category: .cardBack,
            rarity: .rare, priceChips: 5000,
            previewAssetName: "y", unlockCondition: .purchase
        )
        let catalog = makeCatalog([evergreen, dup])
        XCTAssertEqual(catalog.cosmetic(id: "evergreen_1")?.name, "DuplicateLater")
    }

    // ── purchasable() ────────────────────────────────────────────────────────

    func test_purchasable_excludesAchievementUnlocks() {
        let catalog = makeCatalog([evergreen, achievementTitle])
        let ids = catalog.purchasable(now: Date()).map(\.id)
        XCTAssertEqual(ids, ["evergreen_1"])
    }

    func test_purchasable_excludesExpiredItems() {
        let catalog = makeCatalog([evergreen, expiredDrop])
        let ids = catalog.purchasable(now: Date()).map(\.id)
        XCTAssertEqual(ids, ["evergreen_1"])
    }

    func test_purchasable_sortsByRarityDescThenPriceAsc() {
        let cheapLegendary = Cosmetic(
            id: "cheap_leg", name: "CheapLeg", category: .cardBack,
            rarity: .legendary, priceChips: 100_000,
            previewAssetName: "x", unlockCondition: .purchase
        )
        let pricyLegendary = Cosmetic(
            id: "pricy_leg", name: "PricyLeg", category: .cardBack,
            rarity: .legendary, priceChips: 250_000,
            previewAssetName: "x", unlockCondition: .purchase
        )
        let common = Cosmetic(
            id: "cm", name: "Common", category: .cardBack,
            rarity: .common, priceChips: 1000,
            previewAssetName: "x", unlockCondition: .purchase
        )
        let catalog = makeCatalog([common, pricyLegendary, cheapLegendary])
        let ids = catalog.purchasable(now: Date()).map(\.id)
        // Rarity desc: legendary before common; within legendary, cheap before pricy.
        XCTAssertEqual(ids, ["cheap_leg", "pricy_leg", "cm"])
    }

    // ── featured() ───────────────────────────────────────────────────────────

    func test_featured_returnsOnlyLiveLimitedTime_sortedByDeadline() {
        let earlier = Cosmetic(
            id: "earlier", name: "Earlier", category: .cardBack,
            rarity: .rare, priceChips: 5000,
            isLimitedTime: true,
            availableUntil: Date().addingTimeInterval(1800),
            previewAssetName: "x", unlockCondition: .purchase
        )
        let later = Cosmetic(
            id: "later", name: "Later", category: .cardBack,
            rarity: .rare, priceChips: 5000,
            isLimitedTime: true,
            availableUntil: Date().addingTimeInterval(7200),
            previewAssetName: "x", unlockCondition: .purchase
        )
        let catalog = makeCatalog([later, earlier, evergreen, expiredDrop])
        let ids = catalog.featured(now: Date()).map(\.id)
        XCTAssertEqual(ids, ["earlier", "later"])
    }

    func test_featured_emptyWhenNoLiveDrops() {
        let catalog = makeCatalog([evergreen, achievementTitle, expiredDrop])
        XCTAssertTrue(catalog.featured(now: Date()).isEmpty)
    }

    // ── isExpired helpers ────────────────────────────────────────────────────

    func test_isExpired_false_forEvergreen() {
        XCTAssertFalse(evergreen.isExpired(now: Date()))
    }

    func test_isExpired_true_pastDeadline() {
        XCTAssertTrue(expiredDrop.isExpired(now: Date()))
    }

    func test_isExpired_true_whenLimitedButDeadlineMissing() {
        // Defensive case: isLimitedTime=true but availableUntil=nil. We
        // treat that as expired (safer than treating as "available forever").
        let broken = Cosmetic(
            id: "broken", name: "Broken", category: .cardBack,
            rarity: .common, priceChips: 1000,
            isLimitedTime: true, availableUntil: nil,
            previewAssetName: "x", unlockCondition: .purchase
        )
        XCTAssertTrue(broken.isExpired(now: Date()))
    }

    // ── JSON decode contract (golden test against the bundled catalog) ───────

    func test_bundledCatalog_loadsWithoutCrashing() {
        // Verifies the actual shipped JSON parses against the current model.
        // If a future JSON edit breaks the schema, this fails before
        // anyone notices the store is empty.
        let catalog = CosmeticsCatalog()
        XCTAssertFalse(catalog.all.isEmpty)
        // Spot-check known items.
        XCTAssertEqual(catalog.cosmetic(id: "card_back_black_diamond")?.rarity, .legendary)
        XCTAssertEqual(catalog.cosmetic(id: "card_back_holographic")?.rarity, .mythic)
        XCTAssertEqual(
            catalog.cosmetic(id: "card_back_holographic")?.unlockCondition,
            .leaderboard
        )
    }
}
