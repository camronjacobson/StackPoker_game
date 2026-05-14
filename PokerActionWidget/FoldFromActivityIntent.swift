import AppIntents
import Foundation

// ─── Fold App Intent ─────────────────────────────────────────────────────────
// The intent that fires when the user taps the "Fold" button in the Live
// Activity (Lock Screen tile or expanded Dynamic Island).
//
// Why a plain `AppIntent` returning `OpenURLIntent` (not `OpenIntent`):
//   The newer Xcode/iOS SDK changed `OpenIntent` to require its `target`
//   parameter to conform to `AppValue` — which `URL` does *not* satisfy.
//   The supported modern pattern for "App Intent that opens a URL in the
//   host app" is to return `OpenURLIntent` from `perform()`. Same end
//   result (host app launches with our `stackpoker://...` URL routed via
//   .onOpenURL), no protocol-conformance pain.
//
// Why open a URL at all (vs. running the fold inside the intent):
//   The websocket session that actually delivers the action lives in the
//   main app process — the widget extension can't reach it. Bringing the
//   app forward via the URL is the only honest way to fire a fold today.
//   Trade-off: ~1s app-launch latency on Fold-from-island. Acceptable —
//   the user is choosing to come back anyway.
//
// Wiring in the app:
//   The launch URL `stackpoker://table/{id}/action/fold` is intercepted by
//   StackPokerApp.swift's .onOpenURL handler, which routes the fold via
//   PokerActionDeepLinkRouter → GameViewModel as soon as the table view
//   is mounted and confirms it's still our turn (race-safe — if the turn
//   already ended, the fold is silently discarded).

@available(iOS 16.4, *)
struct FoldFromActivityIntent: AppIntent {

    // System-facing metadata. Title shows in the long-press preview;
    // description in the Shortcuts app. Keep both terse — no one reads
    // these except us in the debugger.
    static let title: LocalizedStringResource = "Fold (StackPoker)"
    static let description = IntentDescription(
        "Folds your hand at the active StackPoker table."
    )

    // Tells the system to bring the host app forward when this intent
    // runs. Without this the URL would still open but the user would
    // momentarily see widget-extension chrome.
    static let openAppWhenRun: Bool = true

    // Server-side table id — embedded in the URL the intent opens. We pass
    // it as a Parameter (rather than baking the URL itself) so the widget's
    // `Button(intent: FoldFromActivityIntent(tableId: id))` call site stays
    // self-evident and the URL construction stays in one place
    // (`PokerActionDeepLink.foldURL`).
    @Parameter(title: "Table ID")
    var tableId: String

    init() {
        // Default empty — overridden by the convenience init below before use.
        self.tableId = ""
    }

    init(tableId: String) {
        self.tableId = tableId
    }

    /// Returns an `OpenURLIntent` so the system opens our deep-link URL in
    /// the host app. The `& OpensIntent` opaque-result type is the AppIntents
    /// hand-off contract: "after this intent runs, run that intent next."
    @MainActor
    func perform() async throws -> some IntentResult & OpensIntent {
        let url = PokerActionDeepLink.foldURL(tableId: tableId)
        return .result(opensIntent: OpenURLIntent(url))
    }
}
