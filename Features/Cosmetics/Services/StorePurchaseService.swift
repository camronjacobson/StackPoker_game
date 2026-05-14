import Foundation
import Combine
import os.log

// ─── Purchase Result ──────────────────────────────────────────────────────────
//
// The purchase outcome enum. Surfaced both to test code (which asserts on
// the exact case) and to view layer (which formats `.error(...)` cases for
// the user-facing toast). Kept separate from NetworkError because purchase
// failures have product semantics (already owned, expired) that aren't
// network errors.

enum PurchaseError: Error, Equatable {
    /// Item is not in the catalog. Defensive — should only happen if the
    /// view layer renders a stale catalog reference. Logs at error level.
    case unknownCosmetic

    /// Item already in inventory. Idempotent — we return this rather than
    /// silently succeeding so the UI can react ("you already own this!").
    case alreadyOwned

    /// `unlockCondition != .purchase` or `priceChips <= 0`. Achievement-
    /// gated and leaderboard-gated items hit this case.
    case notPurchasable

    /// Limited-time window has elapsed (isLimitedTime && now > availableUntil).
    case limitedTimeExpired

    /// Server-confirmed insufficient chips. The remote impl maps the
    /// backend's "INSUFFICIENT_FUNDS" serverError code to this case.
    case insufficientFunds

    /// Generic network failure — wraps the underlying NetworkError's
    /// localizedDescription. We don't re-export NetworkError directly so
    /// the view layer doesn't grow a transitive import of the network
    /// module just to handle purchase failures.
    case network(String)

    /// Atomicity guard tripped: chip deduction succeeded server-side but
    /// the local grant step failed. The repository state is rolled forward
    /// to "owned" anyway on the next /chips/balance refresh — but we surface
    /// this case so the UI can prompt a manual refresh. Should be very rare.
    case atomicityViolation(String)
}

enum PurchaseResult: Equatable {
    case success(Cosmetic)
    case failure(PurchaseError)
}

// ─── Protocol ─────────────────────────────────────────────────────────────────

protocol StorePurchaseServiceProtocol: AnyObject {
    /// Attempt to purchase a cosmetic. The implementation MUST:
    ///   1. Verify the cosmetic is in the catalog
    ///   2. Verify it's purchasable and not expired
    ///   3. Verify it's not already owned
    ///   4. Atomically deduct chips + grant ownership (server-side)
    ///   5. On any failure between 1-4, leave inventory unchanged
    /// Returns the typed result; callers should not throw.
    func purchase(_ cosmetic: Cosmetic) async -> PurchaseResult

    /// Last-seen error, for the view layer to bind a toast against. Cleared
    /// (set to nil) at the start of every new purchase attempt so a stale
    /// error from a previous attempt doesn't flash on a new failure.
    var lastError: PurchaseError? { get }
    var lastErrorPublisher: AnyPublisher<PurchaseError?, Never> { get }
}

// ─── Remote impl (real, talks to backend) ─────────────────────────────────────
//
// Calls POST /cosmetics/purchase with the cosmetic id. Backend is expected
// to do the atomic chip deduction + ledger entry, returning the new chip
// balance and a "granted" flag. We then mutate the local inventory.
//
// IMPORTANT: This endpoint does NOT yet exist on the backend as of Phase 1
// drafting. The backend changes are listed at the end of Phase 1; once
// merged, this impl becomes the runtime default. Until then, view layer
// can be wired to either this impl (and crash gracefully on 404) or the
// LocalStub impl below.

final class RemoteStorePurchaseService: StorePurchaseServiceProtocol, ObservableObject {

    @Published private(set) var lastError: PurchaseError? = nil

    var lastErrorPublisher: AnyPublisher<PurchaseError?, Never> {
        $lastError.eraseToAnyPublisher()
    }

    private let catalog: CosmeticsCatalogProtocol
    private let inventory: InventoryRepositoryProtocol
    private let network: NetworkPurchasePort
    private let now: () -> Date

    private static let log = OSLog(subsystem: "com.stackpoker.cosmetics",
                                   category: "purchase")

    init(catalog: CosmeticsCatalogProtocol,
         inventory: InventoryRepositoryProtocol,
         network: NetworkPurchasePort,
         now: @escaping () -> Date = { Date() }) {
        self.catalog = catalog
        self.inventory = inventory
        self.network = network
        self.now = now
    }

    func purchase(_ cosmetic: Cosmetic) async -> PurchaseResult {
        // Clear stale error at the start so the view layer doesn't latch
        // on an old failure.
        lastError = nil

        os_log("Purchase attempt: %{public}@ (%{public}@, %d chips)",
               log: Self.log, type: .info,
               cosmetic.id, cosmetic.rarity.rawValue, cosmetic.priceChips)

        // ── Pre-flight validation (1-3) ──────────────────────────────────────
        // We re-resolve from the catalog (rather than trusting the passed-in
        // value) so a stale view-layer Cosmetic instance can't bypass
        // limited-time / purchasability checks that the catalog might have
        // updated since the view captured it. In practice the catalog is
        // immutable in iter 1, but this defends iter 2.
        guard let resolved = catalog.cosmetic(id: cosmetic.id) else {
            return finalize(.failure(.unknownCosmetic), cosmetic: cosmetic)
        }
        guard !inventory.isOwned(resolved.id) else {
            return finalize(.failure(.alreadyOwned), cosmetic: resolved)
        }
        guard resolved.isPurchasable else {
            return finalize(.failure(.notPurchasable), cosmetic: resolved)
        }
        if resolved.isExpired(now: now()) {
            return finalize(.failure(.limitedTimeExpired), cosmetic: resolved)
        }

        // ── Atomic server-side purchase (4) ──────────────────────────────────
        do {
            try await network.postPurchase(cosmeticId: resolved.id)
        } catch let err as PurchaseError {
            return finalize(.failure(err), cosmetic: resolved)
        } catch {
            return finalize(.failure(.network(error.localizedDescription)),
                            cosmetic: resolved)
        }

        // ── Local inventory grant ────────────────────────────────────────────
        // The server already debited chips and recorded the ledger entry;
        // adding to local inventory cannot fail under iter 1 storage (a
        // UserDefaults write that fails just logs and continues). We mark
        // the success unconditionally.
        inventory.own(resolved.id)
        return finalize(.success(resolved), cosmetic: resolved)
    }

    /// Centralised result-emission point. Writes `lastError` and logs the
    /// outcome with consistent fields. Keeps the purchase() flow above
    /// readable — every return goes through one place.
    private func finalize(_ result: PurchaseResult, cosmetic: Cosmetic) -> PurchaseResult {
        switch result {
        case .success(let c):
            os_log("Purchase success: %{public}@", log: Self.log, type: .info, c.id)
        case .failure(let err):
            lastError = err
            os_log("Purchase failed: %{public}@ — %{public}@",
                   log: Self.log, type: .error, cosmetic.id, String(describing: err))
        }
        return result
    }
}

// ─── Network port ─────────────────────────────────────────────────────────────
//
// Narrow protocol around the single network call this service makes. Lets
// tests inject a fake without mocking the entire NetworkService surface.
// The production binding lives in NetworkPurchasePort+Live.swift below.

protocol NetworkPurchasePort {
    /// POSTs to /cosmetics/purchase with `{ "cosmeticId": id }`. Throws a
    /// `PurchaseError` for product-meaningful failures (insufficientFunds,
    /// alreadyOwned, etc.) or rethrows the underlying NetworkError for
    /// transport failures. Returns Void on success — the new balance will
    /// be read from /auth/me on the next refresh.
    func postPurchase(cosmeticId: CosmeticID) async throws
}

// ─── Local stub (works offline, for dev + Phase-1 demo) ───────────────────────
//
// In-memory chip wallet for development before the backend endpoint exists.
// NOT a production code path — its only job is to let the store screen do
// "Purchase" gestures end-to-end during Phase 2 without depending on the
// backend changes landing first.

final class LocalStubPurchaseService: StorePurchaseServiceProtocol, ObservableObject {

    @Published private(set) var lastError: PurchaseError? = nil
    @Published private(set) var simulatedBalance: Int

    var lastErrorPublisher: AnyPublisher<PurchaseError?, Never> {
        $lastError.eraseToAnyPublisher()
    }

    private let catalog: CosmeticsCatalogProtocol
    private let inventory: InventoryRepositoryProtocol
    private let now: () -> Date

    private static let log = OSLog(subsystem: "com.stackpoker.cosmetics",
                                   category: "purchase.stub")

    init(catalog: CosmeticsCatalogProtocol,
         inventory: InventoryRepositoryProtocol,
         startingBalance: Int = 100_000,
         now: @escaping () -> Date = { Date() }) {
        self.catalog = catalog
        self.inventory = inventory
        self.simulatedBalance = startingBalance
        self.now = now
    }

    func purchase(_ cosmetic: Cosmetic) async -> PurchaseResult {
        lastError = nil

        guard let resolved = catalog.cosmetic(id: cosmetic.id) else {
            lastError = .unknownCosmetic
            return .failure(.unknownCosmetic)
        }
        guard !inventory.isOwned(resolved.id) else {
            lastError = .alreadyOwned
            return .failure(.alreadyOwned)
        }
        guard resolved.isPurchasable else {
            lastError = .notPurchasable
            return .failure(.notPurchasable)
        }
        if resolved.isExpired(now: now()) {
            lastError = .limitedTimeExpired
            return .failure(.limitedTimeExpired)
        }
        guard simulatedBalance >= resolved.priceChips else {
            lastError = .insufficientFunds
            return .failure(.insufficientFunds)
        }

        // Atomic local "deduct + grant". UserDefaults write inside
        // `inventory.own` is logged-on-failure but doesn't throw, so the
        // refund branch below is unreachable under the current persistence
        // backend — kept anyway as a tripwire if persistence later starts
        // throwing.
        simulatedBalance -= resolved.priceChips
        inventory.own(resolved.id)
        if !inventory.isOwned(resolved.id) {
            simulatedBalance += resolved.priceChips
            lastError = .atomicityViolation("Local grant failed; chips refunded")
            os_log("Local stub atomicity refund triggered for %{public}@",
                   log: Self.log, type: .error, resolved.id)
            return .failure(.atomicityViolation("Local grant failed; chips refunded"))
        }
        os_log("Stub purchase success: %{public}@ (-%d chips, %d remaining)",
               log: Self.log, type: .info,
               resolved.id, resolved.priceChips, simulatedBalance)
        return .success(resolved)
    }
}
