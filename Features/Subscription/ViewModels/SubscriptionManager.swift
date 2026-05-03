import SwiftUI
import Combine

// ─── Subscription Manager ────────────────────────────────────────────────────
// Single source of truth for whether the user has access to premium features
// (currently: the Review/Replay system). Three concepts share one gate:
//
//   1. trial      — 2-day free trial. One per device install.
//   2. subscription — paid recurring entitlement (StoreKit 2, TODO).
//   3. isPremiumActive = (trial active) OR (subscription active).
//
// State is local-only (`@AppStorage`) for now. The UX is what matters
// pre-launch; we don't yet need server enforcement because there is no
// real-money flow that abuse could siphon. When App Store Connect products
// are configured and we want trial-per-account (not trial-per-install), the
// `trialStartedAtMs` / `subscriptionActive` reads will move to the backend
// (extending UserProfile) and the rest of this class stays the same.

@MainActor
final class SubscriptionManager: ObservableObject {

    // ─── Singleton ───────────────────────────────────────────────────────────
    // Single instance across the app so MainTabView and PaywallView see the
    // same state without prop-drilling. Injected as @EnvironmentObject from
    // StackPokerApp so SwiftUI re-renders on @Published changes.
    static let shared = SubscriptionManager()

    // Trial duration — 2 full days from the moment "Start Trial" is tapped.
    // Kept as a constant so future A/B tests (3-day vs. 2-day) only touch
    // one line. Computed in seconds for Date arithmetic.
    static let trialDurationSeconds: TimeInterval = 2 * 24 * 3600

    // ─── Persisted State ─────────────────────────────────────────────────────
    // `@AppStorage` survives app relaunches via UserDefaults. Stored as
    // ms-since-epoch (Double) so the value is portable when we move it to the
    // backend (matches `lastDailyBonusClaimMs` already in use elsewhere).

    // Timestamp the user tapped "Start Free Trial". 0 = trial never used.
    @AppStorage("trialStartedAtMs")    private var trialStartedAtMs: Double = 0
    // Manual flip for now; will be replaced by StoreKit Transaction listener.
    @AppStorage("subscriptionActive")  private var subscriptionActiveStored: Bool = false

    // ─── Published Mirrors ───────────────────────────────────────────────────
    // SwiftUI binds to these. We re-publish whenever the underlying
    // @AppStorage values change so views see updates immediately even though
    // AppStorage doesn't itself drive ObservableObject updates outside the
    // owning view.
    @Published private(set) var trialEndsAt: Date?
    @Published private(set) var trialUsed: Bool = false
    @Published private(set) var subscriptionActive: Bool = false

    private init() {
        recompute()
    }

    // ─── Derived State ───────────────────────────────────────────────────────

    // The single check the rest of the app should use. Prefer this over
    // poking at `trialEndsAt` / `subscriptionActive` separately so the
    // entitlement rule lives in one place.
    var isPremiumActive: Bool {
        if subscriptionActive { return true }
        if let end = trialEndsAt, end > Date() { return true }
        return false
    }

    // True only while the trial window hasn't elapsed. Distinct from
    // `isPremiumActive` because we want to render the trial banner only when
    // access is granted *because of* the trial (not because of a real sub).
    var trialActive: Bool {
        guard let end = trialEndsAt else { return false }
        return end > Date()
    }

    // Seconds remaining in the trial. Clamped at 0 once expired so callers
    // can format without bounds-checking.
    var trialSecondsRemaining: Int {
        guard let end = trialEndsAt else { return 0 }
        return max(0, Int(end.timeIntervalSinceNow))
    }

    // ─── Actions ─────────────────────────────────────────────────────────────

    // Start the 2-day free trial. No-op if already used — the button that
    // calls this should be hidden in that state, but we guard anyway so a
    // race (e.g. double-tap) doesn't extend the window.
    func startTrial() {
        guard !trialUsed else { return }
        trialStartedAtMs = Date().timeIntervalSince1970 * 1000
        recompute()
    }

    // Stub for the real StoreKit purchase flow. When App Store Connect has a
    // monthly product configured, this is where we'll:
    //   1. Look up Product.products(for: ["com.stackpoker.premium.monthly"])
    //   2. Call product.purchase(), await Transaction verification
    //   3. On success: subscriptionActiveStored = true; recompute()
    //   4. Subscribe to Transaction.updates for renewal/cancellation
    // For now we surface an "unavailable" result so the UI can show a
    // "Coming soon" message rather than silently doing nothing.
    enum PurchaseResult {
        case success
        case cancelled
        case unavailable     // returned by the stub until StoreKit is wired up
        case failure(String)
    }

    func purchaseMonthly() async -> PurchaseResult {
        // TODO: replace with StoreKit 2 Product.purchase() when product is set
        // up in App Store Connect. Until then this never completes a real
        // purchase — the paywall surfaces a "Coming soon" alert.
        return .unavailable
    }

    // Dev-only helper for testing the entitlement state without going through
    // the App Store. Keep this around — it's also useful as the manual lever
    // for granting comp subs to specific users until backend tracking lands.
    func _debugSetSubscription(active: Bool) {
        subscriptionActiveStored = active
        recompute()
    }

    // ─── Internal ────────────────────────────────────────────────────────────

    // Re-derives every Published mirror from the underlying @AppStorage
    // values. Called from init and after any mutation. Safe to call multiple
    // times — values that haven't changed simply re-publish the same value.
    private func recompute() {
        if trialStartedAtMs > 0 {
            let start = Date(timeIntervalSince1970: trialStartedAtMs / 1000)
            trialEndsAt = start.addingTimeInterval(Self.trialDurationSeconds)
            trialUsed = true
        } else {
            trialEndsAt = nil
            trialUsed = false
        }
        subscriptionActive = subscriptionActiveStored
    }
}
