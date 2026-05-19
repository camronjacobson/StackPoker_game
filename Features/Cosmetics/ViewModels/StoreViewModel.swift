import Foundation
import Combine
import SwiftUI
import os.log

// ─── StoreViewModel ───────────────────────────────────────────────────────────
//
// View-model for the Phase-2 cosmetics Store. Owns the section data,
// the purchase flow state machine, the live chip-balance binding, and
// the countdown tick cadence for limited-time tiles.
//
// Lives outside the View so:
//   • Tests can drive the purchase flow synchronously by injecting a
//     LocalStubPurchaseService and asserting on @Published transitions.
//   • The "open Store from N entry points" surface (ChipsView, ProfileView,
//     table self-avatar menu) all instantiate the same VM with a different
//     `entryPoint` source string for analytics — no view-side branching.
//
// Bound at construction time:
//   • `container` carries catalog/inventory/purchaseService/achievementProgress.
//   • `balancePublisher` is the live chip balance — typically
//     authViewModel.$currentUser.map { ChipAmount(serverString: $0?.chipBalance ?? "0") ?? .zero }.
//     Passed as a publisher rather than as a binding to the AuthVM so we
//     don't grow a hard import of Auth here.
//
// State machine (purchaseFlow):
//
//     idle ──promptPurchase──▶ confirming(cosmetic)
//                                    │
//                  cancelPurchase ───┴──▶ idle
//                                    │
//                       confirm ────▶ purchasing(cosmetic)
//                                          │
//          purchase service ───────────────┤
//          .success(c) ──▶ celebrating(c) ─┴──▶ idle  (after confetti window)
//          .failure(.insufficientFunds) ──▶ idle, showInsufficientFundsSheet = true
//          .failure(other) ──▶ idle, lastPurchaseError = err  (toast)
//
// Countdown cadence:
//   Featured tiles render "Leaves in 3d 4h 21m" / "Leaves in 4m 32s".
//   The VM publishes `currentTime` from a single Timer. The cadence is
//   1.0s when the soonest visible expiry is < 1h away, otherwise 60.0s.
//   This is restarted whenever the soonest-expiry threshold crosses 1h.

@MainActor
final class StoreViewModel: ObservableObject {

    // ── Sections ─────────────────────────────────────────────────────────────

    // TODO: Parked for future Featured banner (post-2026-05-18 store redesign).
    // Not currently consumed by StoreView — the redesigned store dropped the
    // Featured tab because the shipped catalog has zero limited-time items,
    // so the rail rendered as Staff Picks 100% of the time and the surface
    // pretended at scarcity it didn't actually have. The compute logic stays
    // because limited drops are a real Phase-5 plan; re-bind when a real
    // banner-style Featured surface returns to the store top.
    @Published private(set) var featuredItems: [Cosmetic] = []

    // TODO: Parked alongside featuredItems for the future Featured banner.
    // Was the "no live drops" fallback; deliberate to keep the compute path
    // so re-binding is a one-line view change later.
    @Published private(set) var staffPicks: [Cosmetic] = []

    /// All purchasable items, default sort (rarity desc / price asc).
    @Published private(set) var catalogItems: [Cosmetic] = []

    /// Achievement / leaderboard / season-pass items shown in the
    /// "Earned by Play" section of the Identity meta-tab with optional
    /// progress bars.
    @Published private(set) var aspirationalItems: [Cosmetic] = []

    /// Purchasable items grouped by their `CosmeticCategory`, derived from
    /// `catalogItems`. The redesigned store reads this to render sub-category
    /// sections within each meta-tab (Style / Moves / Identity). Sorting
    /// inside each bucket is preserved from `catalogItems` (rarity desc /
    /// price asc), so the section header is the only thing the view needs
    /// to layer on top.
    var catalogByCategory: [CosmeticCategory: [Cosmetic]] {
        Dictionary(grouping: catalogItems, by: \.category)
    }

    // ── Balance + ownership ──────────────────────────────────────────────────

    @Published private(set) var balance: ChipAmount = .zero
    @Published private(set) var ownedIDs: Set<CosmeticID> = []

    /// Equipped item per category. View reads this to render the
    /// "Equipped" badge and to drive the equip-vs-unequip branch on tap.
    /// Sourced from `container.inventory.inventoryPublisher` so updates
    /// from any path (this VM, syncFromServer, other VMs) propagate.
    @Published private(set) var equippedByCategory: [CosmeticCategory: CosmeticID] = [:]

    // ── Purchase flow ────────────────────────────────────────────────────────

    enum PurchaseFlow: Equatable {
        case idle
        case confirming(Cosmetic)
        case purchasing(Cosmetic)
        case celebrating(Cosmetic)
    }

    @Published private(set) var purchaseFlow: PurchaseFlow = .idle

    // ── Equip flow ───────────────────────────────────────────────────────────
    //
    // Mirror of PurchaseFlow for the equip path. Owned items show an
    // "Equip" CTA on the cell; tapping an already-equipped item shows
    // "Unequip" instead. Both go through `EquipService` (server-
    // authoritative), so the network call drives the cache write — see
    // RemoteEquipService.
    //
    //     idle ──promptEquip(c)──▶ confirmingEquip(c)
    //                                   │
    //              cancelEquip ────────┴──▶ idle
    //                                   │
    //                   confirm ──────▶ equipping(c)
    //                                          │
    //          EquipService ───────────────────┤
    //          .success ──▶ idle  (cell badge flips via inventoryPublisher)
    //          .failure(err) ──▶ idle, lastEquipError = err  (toast)

    enum EquipFlow: Equatable {
        case idle
        case confirmingEquip(Cosmetic)
        case confirmingUnequip(Cosmetic)
        case equipping(Cosmetic)
        case unequipping(Cosmetic)
    }

    @Published private(set) var equipFlow: EquipFlow = .idle

    /// Surfaces error toasts for equip/unequip failures (notOwned,
    /// categoryMismatch, network). Cleared by the view when dismissed.
    @Published var lastEquipError: EquipError?

    /// Surfaces error toasts for non-insufficient-funds failures. Cleared
    /// to nil when the view dismisses the toast.
    @Published var lastPurchaseError: PurchaseError?

    /// Drives the TopUpSheet sheet presentation when a purchase failed
    /// for insufficient funds. View binds with `.sheet(isPresented:)`.
    @Published var showInsufficientFundsSheet: Bool = false

    /// Cosmetic that caused the insufficient-funds prompt — carried so
    /// the sheet can offer "Add Chips" copy referencing the gap.
    @Published private(set) var insufficientFundsTarget: Cosmetic?

    // ── Countdown ticker ─────────────────────────────────────────────────────

    /// Re-emits on the Timer cadence below. The view binds to this to
    /// re-compute "Leaves in X" labels — no per-cell timer.
    @Published private(set) var currentTime: Date = Date()

    /// Threshold for switching to per-second cadence. Tuned at 1h: well
    /// under any user's "set a calendar reminder" granularity and well
    /// over the typical store browse session.
    private static let secondCadenceThreshold: TimeInterval = 3600

    // ── Dependencies ─────────────────────────────────────────────────────────

    private let container: CosmeticsContainer
    private let entryPoint: StoreEntryPoint
    private let now: () -> Date

    private var cancellables: Set<AnyCancellable> = []
    private var tickTimer: Timer?
    private var lastCadenceWasFast: Bool = false

    private static let log = OSLog(subsystem: "com.stackpoker.cosmetics",
                                   category: "store")

    // ── Init ─────────────────────────────────────────────────────────────────

    init(container: CosmeticsContainer,
         balancePublisher: AnyPublisher<ChipAmount, Never>,
         entryPoint: StoreEntryPoint,
         now: @escaping () -> Date = { Date() }) {
        self.container = container
        self.entryPoint = entryPoint
        self.now = now

        // Snapshot initial state synchronously so the first render has
        // real data (no empty-flash while Combine spins up).
        self.currentTime = now()
        rebuildSections()
        self.ownedIDs = container.inventory.inventory.ownedIDs

        // Balance binding. removeDuplicates so a /auth/me poll that
        // re-emits the same balance doesn't churn the alert copy.
        balancePublisher
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] amount in self?.balance = amount }
            .store(in: &cancellables)

        // Inventory binding — owned set may change while the Store is open
        // (the player just bought something else, or a season pass granted
        // an item in another flow). Equipped map mirrored for the same
        // reason — sync-from-server, other VMs, or an in-table equip can
        // all mutate it while the store is open.
        self.equippedByCategory = container.inventory.inventory.equippedByCategory
        container.inventory.inventoryPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] inv in
                self?.ownedIDs = inv.ownedIDs
                self?.equippedByCategory = inv.equippedByCategory
            }
            .store(in: &cancellables)

        // Equip-error toast binding. EquipService publishes its lastError
        // through Combine so the VM doesn't need to thread the error
        // through every async call site.
        container.equipService.lastErrorPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] err in
                if let err { self?.lastEquipError = err }
            }
            .store(in: &cancellables)
    }

    deinit {
        tickTimer?.invalidate()
    }

    // ── Lifecycle (View → VM) ────────────────────────────────────────────────

    /// Called by the View's .onAppear. Logs analytics + starts the
    /// countdown timer at the appropriate cadence.
    func onAppear() {
        os_log("storeOpened source=%{public}@",
               log: Self.log, type: .info, entryPoint.rawValue)
        startTickTimer()
    }

    /// Called by the View's .onDisappear. Stops the ticker so a backgrounded
    /// store screen doesn't keep a Timer alive draining the run loop.
    func onDisappear() {
        tickTimer?.invalidate()
        tickTimer = nil
    }

    /// View-bound: top-right balance pill tap → top-up funnel. Same
    /// analytics surface as the insufficient-funds CTA so the funnel
    /// can read both as "user expressed top-up intent in store context".
    func onTopUpTapped(source: TopUpSource) {
        switch source {
        case .insufficientFundsSheet:
            os_log("insufficientFundsTopUpTapped storeEntry=%{public}@",
                   log: Self.log, type: .info, entryPoint.rawValue)
        case .balancePill:
            os_log("storeBalancePillTopUpTapped storeEntry=%{public}@",
                   log: Self.log, type: .info, entryPoint.rawValue)
        }
    }

    // ── Section rebuild ──────────────────────────────────────────────────────
    //
    // Rebuilds the three rails from the catalog using `now()`. Called on
    // init and after each timer tick — limited-time items naturally fall
    // off Featured when they expire, so a once-per-minute rebuild is the
    // simplest way to keep the rails honest without a separate per-item
    // expiry watcher.

    private func rebuildSections() {
        let n = now()
        let featured = container.catalog.featured(now: n)
        self.featuredItems = featured
        self.catalogItems  = container.catalog.purchasable(now: n)

        // Aspirational = anything not purchasable, in JSON order. Filters
        // out items that are themselves expired (limited-time achievements
        // we ran past their window).
        self.aspirationalItems = container.catalog.all.filter {
            !$0.isPurchasable && !$0.isExpired(now: n)
        }

        // Staff Picks fallback — only computed when Featured is empty, to
        // avoid burning cycles on the hot path. Top three legendaries /
        // mythics by rarity desc / price asc.
        if featured.isEmpty {
            self.staffPicks = container.catalog.purchasable(now: n)
                .filter { $0.rarity.sortOrdinal >= CosmeticRarity.legendary.sortOrdinal }
                .prefix(3)
                .map { $0 }
        } else {
            self.staffPicks = []
        }
    }

    // ── Progress passthrough ─────────────────────────────────────────────────

    /// Achievement progress for an aspirational tile. Returns nil for
    /// items the source can't quantify (Phase-2 stub returns nil for
    /// everything; Phase-5 fills this in). View renders the progress bar
    /// only when non-nil.
    func progress(for cosmetic: Cosmetic) -> AchievementProgress? {
        container.achievementProgress.progress(for: cosmetic)
    }

    // ── Purchase flow ────────────────────────────────────────────────────────

    /// Step 1 — user tapped a cosmetic cell. The view will render the
    /// confirm alert with the price + post-purchase balance. We do the
    /// balance math here (not in the view) so insufficient-funds is
    /// detected up front and we never show the alert with a negative
    /// "you'll have …" number.
    func promptPurchase(_ cosmetic: Cosmetic) {
        // Re-validate from catalog — a stale cell reference could carry
        // an outdated price. Belt + suspenders; matches the same
        // re-resolution done inside StorePurchaseService.
        guard let resolved = container.catalog.cosmetic(id: cosmetic.id) else {
            lastPurchaseError = .unknownCosmetic
            return
        }
        guard resolved.isPurchasable, !resolved.isExpired(now: now()) else {
            lastPurchaseError = resolved.isExpired(now: now())
                ? .limitedTimeExpired
                : .notPurchasable
            return
        }
        let price = ChipAmount(resolved.priceChips)
        if !balance.canAfford(price) {
            // Skip the confirm dialog entirely — go straight to the
            // top-up sheet. Showing "you'll have -500 chips" would be
            // a worse UX than just routing to the chip purchase flow.
            insufficientFundsTarget = resolved
            showInsufficientFundsSheet = true
            let shortBy: Int64 = {
                if case .failure(.insufficientFunds(let s)) = balance.subtracting(price) {
                    return s.rawValue
                }
                return 0
            }()
            os_log("insufficientFundsShown cosmetic=%{public}@ short=%lld",
                   log: Self.log, type: .info, resolved.id, shortBy)
            return
        }
        purchaseFlow = .confirming(resolved)
    }

    /// Step 2a — user cancelled at the confirm alert.
    func cancelPurchase() {
        purchaseFlow = .idle
    }

    /// Step 2b — user confirmed at the alert. Kicks the async purchase
    /// against the service; result is handled in `handlePurchaseResult`.
    func confirmPurchase() {
        guard case .confirming(let cosmetic) = purchaseFlow else { return }
        purchaseFlow = .purchasing(cosmetic)
        Task { [weak self] in
            guard let self = self else { return }
            let result = await self.container.purchaseService.purchase(cosmetic)
            await MainActor.run {
                self.handlePurchaseResult(result, for: cosmetic)
            }
        }
    }

    /// Post-purchase landing. Routes success → confetti, insufficient
    /// funds → top-up sheet, anything else → error toast.
    private func handlePurchaseResult(_ result: PurchaseResult, for cosmetic: Cosmetic) {
        switch result {
        case .success(let c):
            purchaseFlow = .celebrating(c)
            // Section rebuild — the just-bought item should leave the
            // Catalog rail (it's now owned) and may appear in inventory
            // surfaces that render off the catalog list.
            rebuildSections()
        case .failure(let err):
            purchaseFlow = .idle
            if err == .insufficientFunds {
                insufficientFundsTarget = cosmetic
                showInsufficientFundsSheet = true
                os_log("insufficientFundsShown cosmetic=%{public}@ (server-confirmed)",
                       log: Self.log, type: .info, cosmetic.id)
            } else {
                lastPurchaseError = err
            }
        }
    }

    /// Confetti window completed — return to idle. View calls this from
    /// the confetti view's onComplete or a 1.5s timer fallback.
    func celebrationFinished() {
        if case .celebrating = purchaseFlow { purchaseFlow = .idle }
    }

    // ── Equip flow (owned items) ─────────────────────────────────────────────
    //
    // Single entrypoint for owned-item taps: routes to confirmingUnequip
    // if the item is already equipped in its slot, otherwise to
    // confirmingEquip. Purchase-vs-equip branching lives in the View
    // (the cell knows whether it's drawing an Owned badge or not), and
    // an item that isn't owned never reaches here.

    /// View → VM: user tapped an owned cell.
    func promptEquip(_ cosmetic: Cosmetic) {
        if equippedByCategory[cosmetic.category] == cosmetic.id {
            equipFlow = .confirmingUnequip(cosmetic)
        } else {
            equipFlow = .confirmingEquip(cosmetic)
        }
    }

    func cancelEquip() {
        equipFlow = .idle
    }

    /// View → VM: user tapped Confirm on the Equip alert.
    func confirmEquip() {
        guard case .confirmingEquip(let cosmetic) = equipFlow else { return }
        equipFlow = .equipping(cosmetic)
        Task { [weak self] in
            guard let self = self else { return }
            let result = await self.container.equipService.equip(cosmetic)
            await MainActor.run {
                self.handleEquipResult(result)
            }
        }
    }

    /// View → VM: user tapped Confirm on the Unequip alert.
    func confirmUnequip() {
        guard case .confirmingUnequip(let cosmetic) = equipFlow else { return }
        equipFlow = .unequipping(cosmetic)
        Task { [weak self] in
            guard let self = self else { return }
            let result = await self.container.equipService.unequip(cosmetic.category)
            await MainActor.run {
                self.handleEquipResult(result)
            }
        }
    }

    /// Both equip and unequip land here. Success is silent — the
    /// inventoryPublisher binding will flip the cell's badge — failure
    /// surfaces through `lastEquipError`, which the EquipService also
    /// publishes (so we don't need to inspect `result.failure` again).
    private func handleEquipResult(_ result: EquipResult) {
        equipFlow = .idle
        // On notOwned: local cache claimed ownership but server disagreed.
        // Re-sync so subsequent renders match server truth.
        if case .failure(.notOwned) = result {
            Task { [weak container] in
                await container?.syncInventoryFromServer()
            }
        }
    }

    // ── Computed: balance preview for confirm copy ───────────────────────────

    /// Post-purchase balance for the alert body. Returns nil if the
    /// confirm flow isn't active (caller shouldn't be asking) or if
    /// somehow the math wouldn't succeed (shouldn't happen — we gate
    /// promptPurchase on canAfford).
    var postPurchaseBalance: ChipAmount? {
        guard case .confirming(let c) = purchaseFlow else { return nil }
        return try? balance.subtracting(ChipAmount(c.priceChips)).get()
    }

    // ── Countdown ticker plumbing ────────────────────────────────────────────

    private func startTickTimer() {
        tickTimer?.invalidate()
        let cadence = idealCadence()
        lastCadenceWasFast = cadence < Self.secondCadenceThreshold
        tickTimer = Timer.scheduledTimer(withTimeInterval: cadence, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
    }

    /// One tick: update currentTime, rebuild sections if a limited-time
    /// item has just expired, and restart the timer if the cadence
    /// threshold was crossed.
    private func tick() {
        currentTime = now()
        rebuildSections()
        let nowFast = soonestExpiry().map { $0 < Self.secondCadenceThreshold } ?? false
        if nowFast != lastCadenceWasFast {
            startTickTimer()
        }
    }

    /// Soonest time-until-expiry across visible Featured items, or nil
    /// if Featured is empty (use slow cadence).
    private func soonestExpiry() -> TimeInterval? {
        let n = now()
        return featuredItems
            .compactMap { $0.timeUntilExpiry(now: n) }
            .min()
    }

    /// Per-second when < 1h to soonest expiry, else per-minute. Default
    /// per-minute when there are no Featured items at all.
    private func idealCadence() -> TimeInterval {
        if let soonest = soonestExpiry(), soonest < Self.secondCadenceThreshold {
            return 1.0
        }
        return 60.0
    }
}

// ─── Entry points ─────────────────────────────────────────────────────────────
//
// Source attribution for the storeOpened analytics event. Adding a case
// here forces the call site to pass it — there's no `.unknown` fallback
// because every entry point is intentional product surface.

enum StoreEntryPoint: String {
    case chipsView                // tapped Store button on chips screen
    case profileRow               // tapped Store row in Profile
    // Renamed from the original speculative `tableSelfAvatarMenu`. After
    // inspecting the existing self-avatar tap (which already opens
    // OpponentPopupView as a read-only stat card) we decided not to
    // overload that gesture. The table entry point is now a persistent
    // peek-tab anchored to the top safe-area inset — see StorePeekTab.
    case tableStoreTab            // tapped/dragged the table peek-tab
    // Added 2026-05-18 when the long-dead Alerts tab in the lobby bottom
    // bar was replaced with a real Store tab. Unlike the other two store
    // entries (which present StoreView as a `.sheet`), this one is full
    // navigation — selecting it swaps MainTabView's content area, same
    // model as Home / Friends.
    case lobbyTab                 // selected the Store tab in lobby bottom bar
}

enum TopUpSource {
    case insufficientFundsSheet
    case balancePill
}

