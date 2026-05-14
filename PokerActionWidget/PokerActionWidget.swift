import WidgetKit
import SwiftUI
import ActivityKit
import AppIntents

// ─── Live Activity Widget ────────────────────────────────────────────────────
// The single Live Activity registered by this widget extension. Renders three
// surfaces from the same `ActivityConfiguration`:
//
//   • Lock Screen / Notification banner
//       The big tile that appears when the screen wakes — full layout with
//       table name, countdown, pot/to-call/stack stat blocks, and the Fold
//       button. This is what users see most.
//
//   • Dynamic Island (iPhone 14 Pro+ when expanded)
//       Compact pill in the camera bump. Tapping it expands into leading/
//       trailing/center/bottom regions where we mirror the same data plus
//       the Fold button. The compact (collapsed) form just shows a glyph
//       and the live countdown so other-app focus isn't disrupted.
//
//   • Minimal (multiple Live Activities competing for the island)
//       Falls back to a tiny glyph + seconds. Good enough to remind the
//       user they have an action pending.
//
// Why ActivityConfiguration (not StaticConfiguration / IntentConfiguration):
//   This widget exists *only* to render an in-flight Live Activity. There is
//   no Home Screen / Lock Screen widget tile for poker tables — users don't
//   want a poker tile sitting on their Lock Screen when they aren't in a
//   hand. ActivityConfiguration is the correct WidgetKit shape for that.

@available(iOS 16.2, *)
struct PokerActionWidget: Widget {

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PokerActionAttributes.self) { context in
            // ───────────── Lock Screen / Notification banner ─────────────
            LockScreenView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.85))
                .activitySystemActionForegroundColor(.white)

        } dynamicIsland: { context in
            DynamicIsland {
                // ───────────── Expanded (long-press / first appearance) ──
                // Four regions: leading/trailing flank the camera bump and
                // get short labels; center hosts the table name; bottom is
                // a wide row for the Fold button.
                DynamicIslandExpandedRegion(.leading) {
                    StatBlock(label: "POT",
                              value: formatChipsCompact(context.state.pot))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    // Self-ticking countdown — `Text(timerInterval:)` is
                    // animated by the OS for free, so we don't need to push
                    // a new content state every second.
                    Text(timerInterval: Date()...context.state.deadline,
                         pauseTime: nil,
                         countsDown: true,
                         showsHours: false)
                        .monospacedDigit()
                        .font(.title3.weight(.heavy))
                        .foregroundStyle(timerColor(for: context.state.deadline))
                        .multilineTextAlignment(.trailing)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text(context.attributes.tableName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text("Blinds \(context.attributes.blindsLabel)")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.55))
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 10) {
                        // Fire the App Intent that opens the host app via
                        // a `stackpoker://...` URL — see FoldFromActivityIntent.
                        Button(intent: FoldFromActivityIntent(tableId: context.attributes.tableId)) {
                            Text("Fold")
                                .font(.subheadline.weight(.bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Color.red.opacity(0.85))
                                )
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)

                        // "Open" hint — the rest of the actions (call/check/
                        // raise) require the in-app slider, so we direct the
                        // user there explicitly rather than burying it.
                        Text("Tap tile to act")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.6))
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            } compactLeading: {
                // Suit-style glyph keeps the brand on the leading side without
                // needing to ship an asset into the widget bundle.
                Image(systemName: "suit.spade.fill")
                    .foregroundStyle(.white)
            } compactTrailing: {
                Text(timerInterval: Date()...context.state.deadline,
                     pauseTime: nil,
                     countsDown: true,
                     showsHours: false)
                    .monospacedDigit()
                    .font(.caption.weight(.bold))
                    .foregroundStyle(timerColor(for: context.state.deadline))
                    .frame(maxWidth: 44)
            } minimal: {
                // Worst-case fallback when many activities compete for the
                // island. Just a glyph — the OS shows it as a small pill.
                Image(systemName: "suit.spade.fill")
                    .foregroundStyle(.white)
            }
            .widgetURL(PokerActionDeepLink.foldURL(tableId: context.attributes.tableId))
            .keylineTint(Color.white.opacity(0.4))
        }
    }
}

// ─── Lock-Screen Tile ────────────────────────────────────────────────────────
// Pulled out into its own view so the body of `PokerActionWidget` stays
// readable. Uses the same data the Dynamic Island expanded view reads.

@available(iOS 16.2, *)
private struct LockScreenView: View {
    let context: ActivityViewContext<PokerActionAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header: table name + blinds on the left, countdown on the right.
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.tableName)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text("Blinds \(context.attributes.blindsLabel) · Your action")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }
                Spacer()
                Text(timerInterval: Date()...context.state.deadline,
                     pauseTime: nil,
                     countsDown: true,
                     showsHours: false)
                    .monospacedDigit()
                    .font(.title2.weight(.heavy))
                    .foregroundStyle(timerColor(for: context.state.deadline))
            }

            // Stat blocks: POT / TO CALL / STACK in equal columns. Gives the
            // user the minimum information they need to commit to a fold
            // without opening the app.
            HStack(spacing: 0) {
                StatBlock(label: "POT",
                          value: formatChipsCompact(context.state.pot))
                    .frame(maxWidth: .infinity)
                Divider().background(.white.opacity(0.15))
                StatBlock(label: "TO CALL",
                          value: context.state.toCall == 0
                                  ? "—"
                                  : formatChipsCompact(context.state.toCall))
                    .frame(maxWidth: .infinity)
                Divider().background(.white.opacity(0.15))
                StatBlock(label: "STACK",
                          value: formatChipsCompact(context.state.myStack))
                    .frame(maxWidth: .infinity)
            }
            .frame(height: 38)

            // Action row: Fold button on the left, Open hint on the right.
            HStack(spacing: 10) {
                Button(intent: FoldFromActivityIntent(tableId: context.attributes.tableId)) {
                    Text("Fold")
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.red.opacity(0.85))
                        )
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                // Tapping any other part of the tile opens the app via the
                // widgetURL set on the dynamicIsland configuration above.
                Text("Tap to open")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(.white.opacity(0.18), lineWidth: 1)
                    )
            }
        }
        .padding(14)
    }
}

// ─── Reusable stat cell ──────────────────────────────────────────────────────
// Tiny label-on-top, value-below stack used by both the Lock Screen tile and
// the Dynamic Island expanded leading region.

@available(iOS 16.2, *)
private struct StatBlock: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2.weight(.heavy))
                .foregroundStyle(.white.opacity(0.55))
            Text(value)
                .font(.callout.weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

// ─── Helpers ─────────────────────────────────────────────────────────────────
// Duplicated locally rather than imported — the widget extension is its own
// build module and can't reach into the main app's chip-formatting helpers
// without making them part of a shared framework. Keeping a tiny copy here
// is cheaper than introducing a shared module just for two helpers.

/// Compact chip formatter: 1234 → "1.2K", 1_500_000 → "1.5M".
/// Single decimal place for K/M, none for plain integers under 1_000.
@available(iOS 16.2, *)
private func formatChipsCompact(_ amount: Int) -> String {
    if amount >= 1_000_000 {
        let m = Double(amount) / 1_000_000
        return String(format: "%.1fM", m)
    }
    if amount >= 1_000 {
        let k = Double(amount) / 1_000
        // Drop the .0 for whole-K values so "5K" doesn't render as "5.0K".
        return k.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(k))K"
            : String(format: "%.1fK", k)
    }
    return "\(amount)"
}

/// Color the countdown by urgency: gold by default, amber under 10s, red
/// under 5s. Mirrors the in-app action-bar timer so the visual language
/// is consistent whether the user is looking at the table or the island.
@available(iOS 16.2, *)
private func timerColor(for deadline: Date) -> Color {
    let remaining = deadline.timeIntervalSinceNow
    if remaining <= 5  { return .red }
    if remaining <= 10 { return .orange }
    return Color(red: 0.95, green: 0.78, blue: 0.30) // gold
}
