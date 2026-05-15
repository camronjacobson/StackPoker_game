import SwiftUI

// ─── Store Peek Tab ───────────────────────────────────────────────────────────
//
// Pure visual subview rendered as the bottom child of StorePanelDrawer's
// composite VStack. The tab does NOT own any state or gestures of its own
// — it's a dumb view that takes a progress value and a red-dot flag, and
// the parent drawer attaches the gesture/tap externally. This split was
// a deliberate refactor: previously the tab handled gestures itself and
// lived as a separate top-bar child while the drawer floated above it,
// which made the tab look disconnected when the drawer pulled down.
// Embedding the tab as the last child of the same composite that holds
// the drawer body means a single `.offset(y:)` moves them together as
// one unit, with the tab acting as the dismiss handle when the drawer
// is open.
//
// Visual:
//   • 64×26pt dark near-black pill (15% lighter than pure black so it
//     reads as a distinct UI chrome layer, not a hole in the screen).
//   • Square top corners, rounded 14pt bottom — silhouette of a drawer
//     pull handle peeking out from above when closed; when open it sits
//     flush against the drawer body's bottom edge.
//   • Centered shopping-cart glyph (cart.fill, 17pt). Morphs to chevron-
//     down past 50% progress so the toggle state is unambiguous mid-drag.
//   • Tiny popRed dot in the top-right when `hasUnviewedDrop`.
//
// Hit area: visible pill is small (88×46 tap region via .padding +
// .contentShape) so it meets WCAG hit-target rules without crowding the
// safe-area inset on Pro devices where the Dynamic Island can expand.
// Accessibility label/hint document both gestures the parent attaches.

struct StorePeekTab: View {

    /// Drives the icon morph (cart → chevron) at the 50% threshold and
    /// the 180° rotation that bridges the two states with a continuous-
    /// feeling animation. 0 = closed, 1 = open. Beyond [0,1] (rubber-
    /// band overshoot) the rotation continues monotonically.
    let progress: CGFloat

    /// Whether to show the unviewed-drop red dot. Cleared by the parent
    /// (drawer) on first open via vm.markStoreTabViewed().
    let hasUnviewedDrop: Bool

    // ── Visual constants ─────────────────────────────────────────────────────
    private let pillWidth:  CGFloat = 64
    private let pillHeight: CGFloat = 26
    private let cornerR:    CGFloat = 14
    private let iconSize:   CGFloat = 17

    var body: some View {
        pill
            .overlay(alignment: .topTrailing) {
                if hasUnviewedDrop {
                    // 8pt red dot with ink hairline border. Positioned
                    // just inside the pill's top-right corner so the
                    // square top edge isn't compromised.
                    Circle()
                        .fill(SPRetro.popRed)
                        .frame(width: 8, height: 8)
                        .overlay(Circle().strokeBorder(SPRetro.ink, lineWidth: 0.75))
                        .offset(x: -6, y: 4)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            // Pad the hit area out to ≥44pt vertically + horizontally so
            // the small visible pill still meets WCAG hit-target rules.
            // .contentShape forces the tap/drag region to follow this
            // padded rectangle rather than the pill's actual path.
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            // Accessibility: the parent drawer attaches both a tap and
            // a drag gesture. We surface the dual nature in the hint
            // string so VoiceOver users know swipe-up also works.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(progress > 0.5
                                     ? "Close cosmetics store"
                                     : "Open cosmetics store"))
            .accessibilityHint(Text("Drag down to open the store panel. Tap or drag up while open to close it."))
            .accessibilityAddTraits(.isButton)
            .animation(.easeInOut(duration: 0.18), value: hasUnviewedDrop)
    }

    // ── Pill body ────────────────────────────────────────────────────────────

    private var pill: some View {
        ZStack {
            // Background — dark near-black at 85% opacity so the felt's
            // gradient still shows through faintly behind it. Square
            // top + rounded bottom gives the "drawer handle" silhouette
            // when closed; when the composite is open, this same shape
            // also reads as a tab dangling from the drawer body — the
            // square-top edge buts cleanly against the drawer's
            // bottom edge.
            UnevenRoundedRectangle(
                cornerRadii: .init(
                    topLeading:     0,
                    bottomLeading:  cornerR,
                    bottomTrailing: cornerR,
                    topTrailing:    0
                ),
                style: .continuous
            )
            .fill(Color(white: 0.06).opacity(0.85))
            // Hairline ink stroke to keep the pill legible against the
            // table felt's mid-tones. Same stroke language as the rest
            // of the in-game UI chrome.
            .overlay(
                UnevenRoundedRectangle(
                    cornerRadii: .init(
                        topLeading:     0,
                        bottomLeading:  cornerR,
                        bottomTrailing: cornerR,
                        topTrailing:    0
                    ),
                    style: .continuous
                )
                .strokeBorder(SPRetro.ink.opacity(0.55), lineWidth: 1)
            )
            // Subtle 2pt downward shadow — gives the pill a sense of
            // hovering above the felt without the heavier hard-ink
            // offset used by retro paper components.
            .shadow(color: Color.black.opacity(0.45), radius: 2, x: 0, y: 1.5)

            // Icon — morphs to chevron.down once progress crosses 0.5,
            // so the toggle state is signaled even mid-drag. The 180°
            // rotationEffect on the same Image creates a continuous
            // visual transition through the symbol swap.
            Image(systemName: iconName)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(Color.white)
                .rotationEffect(.degrees(Double(progress) * 180))
        }
        .frame(width: pillWidth, height: pillHeight)
    }

    /// Icon-name swap is discrete at the 0.5 threshold; the parent
    /// rotationEffect bridges the two states with continuous motion.
    private var iconName: String {
        progress > 0.5 ? "chevron.down" : "cart.fill"
    }
}
