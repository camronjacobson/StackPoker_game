import WidgetKit
import SwiftUI

// ─── Widget Bundle ───────────────────────────────────────────────────────────
// Entry point for the widget extension. WidgetKit looks up the @main
// `WidgetBundle` to discover every widget the extension provides.
//
// Right now we only ship one Live Activity widget — the per-turn poker
// activity. We deliberately do NOT register a Home Screen / Lock Screen
// widget tile; users don't want a static poker glyph living on their
// Lock Screen between hands. If a Home Screen widget is added later,
// list it here alongside `PokerActionWidget()`.
//
// The @available gate matches the only widget we ship: ActivityKit Live
// Activities require iOS 16.2 for `Button(intent:)` inside an activity.

@main
@available(iOS 16.2, *)
struct PokerActionWidgetBundle: WidgetBundle {
    var body: some Widget {
        PokerActionWidget()
    }
}
