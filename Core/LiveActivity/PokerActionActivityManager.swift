import Foundation
import ActivityKit

// ─── Live Activity Manager ───────────────────────────────────────────────────
// Owns the lifecycle of the in-game "your action" Live Activity. The shape
// is intentionally narrow — three operations:
//
//   start(tableId:tableName:blindsLabel:state:)
//     Begin a new activity when it becomes the local player's turn. Idempotent:
//     a second call while one is already running becomes an update() instead.
//
//   update(state:)
//     Push a new ContentState (pot/deadline/etc) into the running activity.
//     The deadline is absolute, so the widget self-ticks the countdown — we
//     only call update() when something *other* than time changes (pot grew
//     because someone called, the user requested +15s, etc).
//
//   end()
//     Tear the activity down once the user's turn ends — they acted, the
//     timer expired, the hand ended, or they walked away from the table.
//
// Why @MainActor: ActivityKit's request/update/end are documented as safe to
// call from any actor, but we always touch them from GameViewModel which is
// @MainActor anyway. Pinning the manager to the main actor avoids one whole
// class of "crossed actor boundaries" warnings without any practical cost.
//
// Availability: Live Activities require iOS 16.1+. We gate the *implementation*
// behind a runtime check so the rest of the codebase compiles cleanly on the
// stated deployment target without #available pollution at every call site.

@MainActor
final class PokerActionActivityManager {

    // Singleton: only one of these activities makes sense per device — you
    // can only be "on the clock" at one table at a time. The manager is the
    // single source of truth for whether an activity exists right now.
    static let shared = PokerActionActivityManager()

    // The currently-running activity, if any. Held as an opaque `Any` here
    // because the typed Activity<PokerActionAttributes> needs an iOS 16.1
    // availability gate; we cast back inside the gated helpers below. This
    // is a deliberate trade so the rest of the file stays availability-clean.
    private var activeActivity: Any?

    private init() {}

    // ─── Authorization ──────────────────────────────────────────────────────

    /// True when the user has Live Activities enabled in Settings AND the
    /// device supports them (iOS 16.1+). We check before each `start` so a
    /// user who has them off doesn't see weird "started/ended in the same
    /// frame" behaviour — we just no-op cleanly.
    var canStartActivities: Bool {
        if #available(iOS 16.1, *) {
            return ActivityAuthorizationInfo().areActivitiesEnabled
        }
        return false
    }

    // ─── Public lifecycle ───────────────────────────────────────────────────

    /// Begin a new activity for the local player's turn. If one is already
    /// running for the same table, this becomes an update() — it's normal
    /// for `updateTurnTimer` to fire repeatedly across server state pushes
    /// even within the same turn, and we don't want each push to spawn a
    /// fresh activity (which would compound on the Lock Screen).
    func start(
        tableId: String,
        tableName: String,
        blindsLabel: String,
        state: PokerActionAttributes.ContentState
    ) {
        guard #available(iOS 16.1, *) else { return }
        guard canStartActivities else { return }

        // If we already have an activity for this exact table, just update
        // its content state. Switching to a *different* table mid-activity
        // is a rare edge case (multi-tabling future work), but we handle it
        // by ending the old one before starting fresh.
        if let existing = activeActivity as? Activity<PokerActionAttributes> {
            if existing.attributes.tableId == tableId {
                Task { await existing.update(using: state) }
                return
            } else {
                Task { await existing.end(dismissalPolicy: .immediate) }
                activeActivity = nil
            }
        }

        let attrs = PokerActionAttributes(
            tableId: tableId,
            tableName: tableName,
            blindsLabel: blindsLabel
        )

        do {
            // `pushType: nil` because we don't use ActivityKit push tokens —
            // updates are local from the running app. The widget self-ticks
            // its countdown via the Date in `state.deadline`, so we only
            // need to push updates when *non-time* state changes.
            let activity = try Activity<PokerActionAttributes>.request(
                attributes: attrs,
                contentState: state,
                pushType: nil
            )
            activeActivity = activity
        } catch {
            // Most common failure modes are: user disabled Live Activities
            // (already short-circuited above), or ran past the 8-hour cap.
            // Either way, swallowing is correct — there's no UI to show an
            // error to here, and the in-app timer continues to work fine.
            #if DEBUG
            print("[LiveActivity] start failed: \(error.localizedDescription)")
            #endif
        }
    }

    /// Push a new content state into the running activity. Used when the
    /// pot grows (someone else called/raised), when the user requested a
    /// +15s extension (deadline shifts), or when their stack changes
    /// because of side-pot maths. No-op if no activity is running.
    func update(state: PokerActionAttributes.ContentState) {
        guard #available(iOS 16.1, *) else { return }
        guard let activity = activeActivity as? Activity<PokerActionAttributes> else { return }
        Task { await activity.update(using: state) }
    }

    /// End the activity. Called when the player's turn ends (they acted, or
    /// the timer expired and the server moved on), when the hand ends, or
    /// when the player leaves the table. `.immediate` dismissal removes the
    /// island chip immediately rather than letting it linger for ~4 hours
    /// (the default `.default` policy) — for a per-turn activity, lingering
    /// would be misleading.
    func end() {
        guard #available(iOS 16.1, *) else { return }
        guard let activity = activeActivity as? Activity<PokerActionAttributes> else { return }
        activeActivity = nil
        Task { await activity.end(dismissalPolicy: .immediate) }
    }
}
