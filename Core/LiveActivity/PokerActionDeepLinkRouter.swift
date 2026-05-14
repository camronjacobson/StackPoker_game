import Foundation
import Combine

// ─── Deep-link Router ────────────────────────────────────────────────────────
// Tiny pub/sub for routing taps from the Live Activity (Fold button or the
// tile itself) back to the in-app GameViewModel.
//
// Why a singleton + NotificationCenter:
//   The URL arrives at the App level (`.onOpenURL` modifier on RootView), but
//   the only place that can *act* on a fold is the running `GameViewModel`,
//   which is owned by `GameView`. The two are several view layers apart,
//   so passing a closure or `@EnvironmentObject` would mean threading state
//   through every level in between for one rare event. NotificationCenter
//   keeps the wiring local: GameViewModel listens, the app posts.
//
// Why "pending" instead of fire-and-forget:
//   When the app is launched cold from the Live Activity (process killed in
//   the background, then user taps Fold), the GameViewModel doesn't exist
//   yet. The router stores the pending fold so that whatever GameViewModel
//   gets created next can pick it up and act on first state push. If no
//   matching VM ever appears (user navigated away, table closed), the
//   pending fold simply ages out — no harm done.

@MainActor
final class PokerActionDeepLinkRouter: ObservableObject {

    static let shared = PokerActionDeepLinkRouter()

    /// Most recent fold request that hasn't been consumed yet. Holds just a
    /// table id and a wall-clock timestamp; the timestamp lets the consumer
    /// drop the request if it's stale (e.g. the user backgrounded the app
    /// for hours then re-opened it on the *current* turn — we don't want
    /// to retroactively fold them).
    @Published private(set) var pendingFold: PendingFold?

    /// Notification name that GameViewModels listen for. Posted whenever a
    /// new pending fold lands, so an already-running VM at the right table
    /// can react immediately rather than polling the published property.
    static let foldNotification = Notification.Name("StackPoker.LiveActivity.PendingFold")

    struct PendingFold: Equatable {
        let tableId: String
        let receivedAt: Date

        /// Folds requested more than this many seconds ago are considered
        /// stale and ignored. 30s is generous — covers a cold-launch with
        /// network reconnect on a slow connection. Anything older almost
        /// certainly belongs to a turn that's long since passed.
        static let maxAge: TimeInterval = 30

        var isFresh: Bool { Date().timeIntervalSince(receivedAt) <= Self.maxAge }
    }

    private init() {}

    // ─── Inbound (from URL handler) ─────────────────────────────────────────

    /// Called by the app's URL handler. Stores the fold and broadcasts so
    /// any GameViewModel currently observing for this tableId can act on
    /// it without waiting for the @Published property to propagate via
    /// SwiftUI's view-update cycle.
    func receive(_ route: PokerActionDeepLink.Route) {
        switch route {
        case .fold(let tableId):
            let pending = PendingFold(tableId: tableId, receivedAt: Date())
            pendingFold = pending
            NotificationCenter.default.post(
                name: Self.foldNotification,
                object: nil,
                userInfo: ["tableId": tableId]
            )
        }
    }

    // ─── Outbound (consumer-side) ──────────────────────────────────────────

    /// Consumes the pending fold for `tableId` if one exists and is fresh.
    /// Returns true if the caller should proceed with a fold. Idempotent:
    /// repeat calls after consumption return false.
    func consumePendingFold(forTableId tableId: String) -> Bool {
        guard let pending = pendingFold,
              pending.tableId == tableId,
              pending.isFresh
        else { return false }
        pendingFold = nil
        return true
    }
}
