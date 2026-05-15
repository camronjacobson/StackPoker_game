import SwiftUI

// ─── StorePanelDrawer ─────────────────────────────────────────────────────────
//
// Slide-from-top overlay that hosts the cosmetics StoreView. *Panel only*
// — the toggle handle (StorePeekTab) lives in GameView.topBar as a
// sibling of the menu and chat buttons; this drawer is a pure overlay
// that listens to `vm.isStorePanelOpen` and slides the panel down/up.
//
// ── Why the tab was moved out (Option A refactor) ──
// Earlier versions composited the tab + panel inside this view to get
// a "tab rides the panel bottom edge" effect during slide. That broke
// for two reasons:
//
//   1. `.ignoresSafeArea(.top)` on the composite caused
//      `GeometryReader { geo in ... geo.safeAreaInsets.top }` inside
//      the closure to report 0 instead of the actual island/notch
//      inset, so the tab's resting position landed BEHIND the
//      Dynamic Island.
//   2. The composite was wrapped by GameView's outer ZStack which
//      has 4 stacked `.animation(_, value:)` modifiers including
//      `value: landscape`. During the parent `.fullScreenCover`
//      entrance, `landscape` (derived from geo.size.width >
//      geo.size.height) can flip transiently, triggering an
//      implicit transition that animated the tab's opacity and
//      offset — causing the reported "tab flashes then disappears"
//      symptom.
//
// Moving the tab into the HUD row makes its position determined by
// the HStack layout (same as menu + chat buttons) and entirely
// independent of overlay geometry. The cost: tab no longer slides
// with the panel — it stays put and the panel slides down past it.
// Robustness >> visual flourish here.
//
// ── Parent-provided safe area ──
// safeTop and screenHeight are passed in from GameView's outer
// GeometryReader (which has correct safe-area reporting because it
// doesn't ignore the safe area). The drawer itself applies
// `.ignoresSafeArea(.top)` so the closed panel can sit fully
// off-screen above the bezel, but it does NOT read safeAreaInsets
// from inside its own ignoredSafeArea zone (which would resolve to 0).

private extension Animation {
    /// Snap animation for open/close transitions. Tuned to read like
    /// a UISheet dismiss — quick + slightly damped, no overshoot.
    static var storeDrawerSnap: Animation {
        .spring(response: 0.32, dampingFraction: 0.9)
    }
}

struct StorePanelDrawer: View {

    @ObservedObject var vm: GameViewModel

    /// Factory closure so the StoreViewModel is constructed lazily on first
    /// open. Capturing the factory (not the result) avoids spinning up the
    /// catalog subscription before the user ever opens the panel.
    let makeStoreVM: () -> StoreViewModel

    /// Top safe-area inset, passed in from the parent GeometryReader so
    /// we read the *real* value instead of the 0 that `.ignoresSafeArea`
    /// would report inside our own GeometryReader closure.
    let safeTop: CGFloat

    /// Screen height, passed in from the parent. Used to compute the
    /// panel's 60%-of-screen open detent.
    let screenHeight: CGFloat

    /// Close-drag delta in points (negative = dragging upward to close).
    /// @GestureState auto-resets when the gesture ends, so we never
    /// have to remember to zero it out.
    @GestureState private var closeDragOffset: CGFloat = 0

    // ── Visual constants ─────────────────────────────────────────────────────

    /// Panel height as a fraction of screen height. 0.6 matches the
    /// previous system-sheet attempt's `.fraction(0.6)` detent.
    private let panelFraction: CGFloat = 0.6

    /// Clearance below the safe-area inset for the open-panel top edge.
    private let topClearance: CGFloat = 8

    /// Extra cushion added to the closed-state offset so even a heavy
    /// shadow on the panel can't peek below the bezel.
    private let closedOvershoot: CGFloat = 40

    var body: some View {
        let panelH    = max(0, screenHeight * panelFraction)
        let openTop   = safeTop + topClearance
        let closedTop = -(panelH + safeTop + closedOvershoot)
        let baseTop   = vm.isStorePanelOpen ? openTop : closedTop

        // closeDragOffset is added directly (negative when dragging
        // upward, clamped to 0 so a downward drag on an open panel
        // doesn't rubber-band past its open resting position).
        let panelY = baseTop + min(0, closeDragOffset)

        StablePanelHost(panelHeight: panelH) {
            storePanelBody()
        }
        .equatable()
        .frame(maxWidth: .infinity)
        .frame(height: panelH)
        .offset(y: panelY)
        // Drag-to-close attaches only while the panel is open, so it
        // never competes with table-area gestures and the @GestureState
        // invalidation cost is only paid during a close interaction.
        .gesture(vm.isStorePanelOpen ? closeDragGesture(panelHeight: panelH) : nil)
        // Pin the panel to the top of the overlay frame; without this
        // the .offset positions read against an auto-sized container
        // and end up in the wrong vertical band.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Extend into the top safe area so the closed panel can fully
        // hide above the bezel.
        .ignoresSafeArea(.all, edges: .top)
        // Empty regions of the overlay don't intercept touches —
        // taps on the table felt / action bar pass through.
        .allowsHitTesting(vm.isStorePanelOpen)
        // Fire the "viewed" side-effect once per open transition.
        .onChange(of: vm.isStorePanelOpen) { _, opened in
            if opened { vm.markStoreTabViewed() }
        }
    }

    // ── Subviews ─────────────────────────────────────────────────────────────

    @ViewBuilder
    private func storePanelBody() -> some View {
        // Rasterized panel content — Metal-flattened so the slide
        // animation moves a single GPU layer instead of recomposing
        // shadows/strokes/grid layout mid-flight.
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(SPColors.background)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(SPRetro.ink.opacity(0.55), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.35), radius: 8, x: 0, y: 4)

            StoreView(vm: makeStoreVM())
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .padding(.horizontal, 8)
        .compositingGroup()
    }

    // ── Gestures ─────────────────────────────────────────────────────────────

    /// Drag-up to close. Attaches only while the panel is open so it
    /// never competes with table-area gestures.
    private func closeDragGesture(panelHeight: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .updating($closeDragOffset) { value, state, _ in
                // Only track upward motion. Downward drag is clamped
                // to 0 in the panelY math so the open panel doesn't
                // rubber-band downward.
                state = min(0, value.translation.height)
            }
            .onEnded { value in
                // Snap closed if dragged past ~30% of panel height OR
                // flicked upward with enough velocity that the predicted
                // end translation exceeds 40% of panel height.
                let dragFrac      = value.translation.height           / max(panelHeight, 1)
                let predictedFrac = value.predictedEndTranslation.height / max(panelHeight, 1)

                if dragFrac < -0.30 || predictedFrac < -0.40 {
                    withAnimation(.storeDrawerSnap) { vm.isStorePanelOpen = false }
                }
                // Otherwise @GestureState resets to 0 and the panel
                // springs back to its open resting position via the
                // implicit transition on panelY.
            }
    }
}

// ─── StablePanelHost ──────────────────────────────────────────────────────────
//
// Equatable wrapper around the panel body. SwiftUI's view diff treats
// `EquatableView` (applied via `.equatable()`) as "skip re-evaluation if
// `==` returns true", so as long as our equality predicate only depends
// on layout-affecting inputs (currently just panelHeight), the entire
// panel subtree is memoized across body invalidations that don't change
// the layout.
//
// Main job: absorb @Published changes on the view-model (chat toasts,
// timer ticks, etc.) that fire during the slide animation. Without it,
// those publishers can invalidate the drawer body mid-animation and
// force the heavy StoreView grid to re-evaluate against an interpolating
// offset, causing visible hitches.

private struct StablePanelHost<Content: View>: View, Equatable {
    let panelHeight: CGFloat
    @ViewBuilder var content: () -> Content

    static func == (lhs: StablePanelHost, rhs: StablePanelHost) -> Bool {
        abs(lhs.panelHeight - rhs.panelHeight) < 0.5
    }

    var body: some View {
        content()
    }
}
