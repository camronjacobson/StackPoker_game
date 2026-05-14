import Foundation
import ActivityKit

// ─── Live Activity Attributes ────────────────────────────────────────────────
// Shared model that describes the data we hand to a poker-turn Live Activity.
// "Attributes" in ActivityKit's vocabulary == both the immutable per-activity
// metadata (table id, blinds, your starting stack) AND the dynamic content
// state that we push updates into (action deadline, pot, current bet).
//
// IMPORTANT — multi-target file:
//   This file MUST be included in BOTH the main StackPoker app target AND the
//   PokerActionWidget extension target. The two targets exchange instances of
//   this struct via ActivityKit's IPC, so the type identity must match. In
//   Xcode's File Inspector, set Target Membership for this file to BOTH
//   targets. (The .pbxproj has the main-target entry; you add the widget
//   membership when you create the extension target.)
//
// Why a single shared struct rather than two parallel ones:
//   Live Activities serialize the attributes via Codable and reconstruct them
//   on the widget side using the *same* type. If the widget defined its own
//   "compatible" struct, encoding would still work but the activity wouldn't
//   match by type and UI updates from the app would be silently dropped.

// `ActivityAttributes` itself is iOS 16.1+ / iPadOS 16.1+. The @available
// on the type lets the project compile against macCatalyst-style toolchains
// without complaining; production code paths are gated at the call sites.
@available(iOS 16.1, *)
public struct PokerActionAttributes: ActivityAttributes {

    // ─── Static metadata (set once at activity start, never updated) ────────

    /// Server-side table identifier. Doubles as the routing key the Fold
    /// App Intent embeds in its open-URL — `stackpoker://table/{id}/fold`.
    public let tableId: String

    /// Human-readable table name. Shown on the Lock Screen tile and the
    /// expanded Dynamic Island so the user can tell *which* table is asking
    /// for action when they have multiple sessions or recently played at
    /// several tables.
    public let tableName: String

    /// Pretty-printed blinds, e.g. "5/10". We render the formatted string
    /// rather than two integers so the widget doesn't need to know about
    /// our chip-formatting helpers.
    public let blindsLabel: String

    // ─── Dynamic content state (updated each tick / push) ───────────────────

    public struct ContentState: Codable, Hashable {

        /// Wall-clock instant when the user's decision window expires. We
        /// pass an absolute Date (not a remaining-seconds count) because:
        ///   1. The widget can render `Text(timerInterval:)` which the OS
        ///      auto-ticks for free — no per-second push needed.
        ///   2. If the activity update arrives slightly late (push latency,
        ///      app suspension), the rendered countdown stays correct
        ///      without us doing any arithmetic to "rebase" elapsed time.
        public var deadline: Date

        /// Total pot at the moment the activity was last updated. Shown as
        /// secondary copy on the expanded view so the player has just
        /// enough context to decide whether to act vs. fold from the
        /// lock screen.
        public var pot: Int

        /// The amount required to call right now (0 if it's a check).
        /// Drives the verb under the timer: "Call 40" vs. "Check".
        public var toCall: Int

        /// The active player's current chip stack — "you have X behind".
        /// Lets the user weigh the call against their stack at a glance.
        public var myStack: Int

        public init(deadline: Date, pot: Int, toCall: Int, myStack: Int) {
            self.deadline = deadline
            self.pot      = pot
            self.toCall   = toCall
            self.myStack  = myStack
        }
    }

    public init(tableId: String, tableName: String, blindsLabel: String) {
        self.tableId     = tableId
        self.tableName   = tableName
        self.blindsLabel = blindsLabel
    }
}

// ─── Deep-link helpers ───────────────────────────────────────────────────────
// Centralized in this shared file so both the App Intent (widget target) and
// the URL handler (main target) agree on the URL shape. If you change the
// scheme, change it here in one place.

public enum PokerActionDeepLink {

    /// Custom URL scheme registered in the main app's Info.plist. Both the
    /// scheme string and the URL types entry must match exactly or the OS
    /// won't route taps from the Live Activity back to the app.
    public static let scheme = "stackpoker"

    /// Builds the URL the Fold App Intent opens. Using a structured path
    /// (`/table/{id}/action/fold`) rather than query strings keeps the
    /// router parsing trivial and lets us add other actions later
    /// (`/check`, `/call`) without inventing new query keys.
    public static func foldURL(tableId: String) -> URL {
        // URL components are safer than string-concat: tableId is a server-
        // assigned id (UUID-shaped) so percent-encoding is rarely needed,
        // but if a future id format ever contains reserved characters this
        // path still produces a valid URL.
        var comps = URLComponents()
        comps.scheme = scheme
        comps.host   = "table"
        comps.path   = "/\(tableId)/action/fold"
        return comps.url ?? URL(string: "\(scheme)://table/\(tableId)/action/fold")!
    }

    /// Decodes an incoming URL into a routable action. Returns nil for any
    /// URL that doesn't match our scheme/shape so the caller can ignore
    /// malformed/legacy links without throwing.
    public static func parse(_ url: URL) -> Route? {
        guard url.scheme == scheme, url.host == "table" else { return nil }
        // URL.pathComponents includes a leading "/" — drop it so the
        // remaining components line up with the structured path above.
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count >= 3,
              parts[1] == "action" else { return nil }
        let tableId = parts[0]
        switch parts[2] {
        case "fold": return .fold(tableId: tableId)
        default:     return nil
        }
    }

    public enum Route: Equatable {
        case fold(tableId: String)
    }
}
