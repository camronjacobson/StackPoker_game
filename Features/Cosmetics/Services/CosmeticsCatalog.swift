import Foundation
import os.log

// ─── Cosmetics Catalog ────────────────────────────────────────────────────────
//
// Loads the bundled `cosmetics_catalog.json` and exposes typed query helpers.
// Currently a read-only, single-load-at-init service — the catalog is
// static for the lifetime of the app process, matching the iteration-1
// design where catalog updates ship with the app binary.
//
// When iteration 2 moves to a server-backed catalog, the protocol stays;
// only the impl swaps to one that fetches `/cosmetics/catalog` on launch
// and caches the response. View layer is unchanged.

protocol CosmeticsCatalogProtocol {
    /// All catalog items in their JSON-declared order. Use the typed helpers
    /// below for sorted / filtered views — callers that want raw access can
    /// still iterate this, but they shouldn't be making sort/filter
    /// decisions in view code.
    var all: [Cosmetic] { get }

    /// O(1) lookup by id. Returns nil if the id doesn't exist in the
    /// loaded catalog. The view layer treats nil as "this item was
    /// removed from the catalog since the player acquired it" — see
    /// PlayerInventory's equippedItem(for:) docs for the healing path.
    func cosmetic(id: CosmeticID) -> Cosmetic?

    /// All items in a single category. Returns the JSON order so the
    /// catalog JSON itself dictates the within-category layout for the
    /// inventory screen (where rarity grouping is less important than
    /// "first cosmetic added shows first").
    func items(in category: CosmeticCategory) -> [Cosmetic]

    /// All currently purchasable items (unlockCondition == .purchase AND
    /// price > 0 AND not expired). Sorted by rarity desc, then price asc.
    /// This is the Phase-2 "Catalog tab" default order.
    func purchasable(now: Date) -> [Cosmetic]

    /// All limited-time items not yet expired, sorted by closest deadline
    /// first. Drives the Featured tab. Empty when no limited drops are
    /// active — Featured tab handles that case in the view layer.
    func featured(now: Date) -> [Cosmetic]
}

// ─── Bundled JSON impl ────────────────────────────────────────────────────────

final class CosmeticsCatalog: CosmeticsCatalogProtocol {

    let all: [Cosmetic]
    private let byId: [CosmeticID: Cosmetic]

    // Single os.log subsystem for the whole cosmetics module. The category
    // breakdown makes it filterable in Console.app to "subsystem:
    // com.stackpoker.cosmetics category:catalog" when investigating a
    // load failure.
    private static let log = OSLog(subsystem: "com.stackpoker.cosmetics",
                                   category: "catalog")

    /// Top-level shape of the bundled JSON. `_meta` is optional — useful
    /// for authoring but not load-required, so a future schemaVersion check
    /// can be added without breaking older bundles.
    private struct CatalogFile: Decodable {
        struct Meta: Decodable { let schemaVersion: Int? }
        let _meta: Meta?
        let cosmetics: [Cosmetic]
    }

    /// Bundle-loading initializer. Default fileName matches the file we
    /// ship in Resources/. Throws if the resource is missing or malformed —
    /// this is a programmer error (we shipped a bad bundle), not a runtime
    /// recoverable state, so we let it crash on app launch.
    convenience init(bundle: Bundle = .main, fileName: String = "cosmetics_catalog") {
        guard let url = bundle.url(forResource: fileName, withExtension: "json") else {
            os_log("Catalog JSON not found in bundle (resource: %{public}@.json). " +
                   "Check that the file is added to the StackPoker target's Copy Bundle Resources phase.",
                   log: CosmeticsCatalog.log, type: .fault, fileName)
            fatalError("Missing cosmetics catalog resource: \(fileName).json")
        }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            // ISO8601 matches the format we'll emit from the backend in
            // iteration 2 and is human-authorable for hand-edited limited
            // drops in the JSON.
            decoder.dateDecodingStrategy = .iso8601
            let file = try decoder.decode(CatalogFile.self, from: data)
            self.init(cosmetics: file.cosmetics)
        } catch {
            os_log("Catalog JSON decode failed: %{public}@",
                   log: CosmeticsCatalog.log, type: .fault, String(describing: error))
            fatalError("Cosmetics catalog decode failed: \(error)")
        }
    }

    /// Direct-injection initializer — used by tests to pass a synthetic
    /// catalog without going through the bundle. Keeps the bundle-loading
    /// path the *default*, not the *only* path.
    init(cosmetics: [Cosmetic]) {
        self.all = cosmetics
        // Build the index in O(n). Duplicate IDs are a bundle authoring
        // error — we log them but keep the last-seen entry, which keeps
        // the app booting in the face of a typo'd JSON line.
        var index: [CosmeticID: Cosmetic] = [:]
        index.reserveCapacity(cosmetics.count)
        for c in cosmetics {
            if index[c.id] != nil {
                os_log("Duplicate cosmetic id in catalog: %{public}@. Last-seen entry wins.",
                       log: CosmeticsCatalog.log, type: .error, c.id)
            }
            index[c.id] = c
        }
        self.byId = index
        os_log("Catalog loaded with %d items", log: CosmeticsCatalog.log, type: .info, cosmetics.count)
    }

    // ── Queries ──────────────────────────────────────────────────────────────

    func cosmetic(id: CosmeticID) -> Cosmetic? {
        byId[id]
    }

    func items(in category: CosmeticCategory) -> [Cosmetic] {
        all.filter { $0.category == category }
    }

    func purchasable(now: Date = Date()) -> [Cosmetic] {
        all
            .filter { $0.isPurchasable && !$0.isExpired(now: now) }
            .sorted { a, b in
                // Higher rarity first; ties broken by lower price (cheaper
                // legendaries sit above expensive ones within a tier).
                if a.rarity.sortOrdinal != b.rarity.sortOrdinal {
                    return a.rarity.sortOrdinal > b.rarity.sortOrdinal
                }
                return a.priceChips < b.priceChips
            }
    }

    func featured(now: Date = Date()) -> [Cosmetic] {
        all
            .filter { $0.isLimitedTime && !$0.isExpired(now: now) }
            .sorted { ($0.availableUntil ?? .distantFuture) < ($1.availableUntil ?? .distantFuture) }
    }
}
