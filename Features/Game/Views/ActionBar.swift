import SwiftUI

// ─── Action Bar ───────────────────────────────────────────────────────────────
// PurePoker-style action bar: only visible when it's my turn, dark pill
// buttons with colored text, optional raise slider panel.

// MAP: ActionBar — fold/check/call/raise buttons + +15s + slider (342 lines)
// - ActionBar (root) ....................... L7
// - PokerActionButton (single pill) ........ L100
// - RaiseSliderView (raise amount picker) .. L176

struct ActionBar: View {
    @ObservedObject var vm: GameViewModel

    // Minimum frame height for the bar — kept constant whether or not the
    // local player is on-turn. The on-turn-no-slider content naturally takes
    // ~104pt (30pt +15s row + paddings, 56pt button row + paddings). Pinning
    // the OUTER frame to this minimum prevents the parent VStack in
    // GameView.portraitLayout from reflowing when `isMyTurn` flips false:
    // before this, ActionBar collapsed from ~104pt → 0 over the spring's
    // duration, which dragged the table-area ZStack downward and shifted
    // the hole-card layer's bounds *during* the cards-return spring — that
    // layout-driven movement was the residual "drift" the user saw after the
    // big withAnimation removal in GameViewModel. Trade-off: an empty ~110pt
    // strip sits below the table when off-turn, which is fine because cards
    // are now anchored to a stable position instead of jumping with each turn.
    //
    // The slider growing the inner content above this minHeight is allowed
    // (frame becomes ~224pt while open) — that reflow only happens during
    // the user's own slider interaction, where a small settle is expected.
    private static let baseHeight: CGFloat = 110

    var body: some View {
        VStack(spacing: 0) {
            if vm.isMyTurn {
                if vm.showRaiseSlider {
                    RaiseSliderView(vm: vm)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // ── +15s extension button ────────────────────────────────
                // Floats above the action row, right-aligned. Replaces the
                // longer base decision time we used to give every player —
                // now you get a shorter clock by default plus one optional
                // +15s on demand.
                //
                // Visibility note: we keep the button MOUNTED at all times
                // and just fade it out once used, rather than removing it
                // from the view tree. Removing it shifts the action row /
                // hole cards upward by ~34pt as SwiftUI reflows the parent
                // VStack — the user found that movement disorienting.
                // `.allowsHitTesting(false)` prevents a phantom re-tap on
                // the now-invisible target.
                // Left-aligned so the +15s pill never overlaps the vertical
                // raise slider that lives on the right side of the screen
                // when a bet/raise is in progress.
                HStack {
                    Button {
                        vm.requestTimeExtension()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 12, weight: .bold))
                            Text("15s")
                                .font(.custom("ChalkboardSE-Bold", size: 12))
                        }
                        .foregroundStyle(SPRetro.ink)
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .background(
                            ZStack {
                                // Hard ink offset shadow — comic-panel idiom,
                                // no blur. Sits below the mustard capsule so
                                // the button reads as a sticker pressed onto
                                // the page rather than a glowing system pill.
                                Capsule()
                                    .fill(SPRetro.ink)
                                    .offset(x: 1.5, y: 2)
                                Capsule()
                                    .fill(SPRetro.mustard)
                                Capsule()
                                    .strokeBorder(SPRetro.ink,
                                                  lineWidth: 1.5)
                            }
                        )
                    }
                    .buttonStyle(.plain)
                    .opacity(vm.turnExtensionUsed ? 0 : 1)
                    .allowsHitTesting(!vm.turnExtensionUsed)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 4)
                .animation(.easeOut(duration: 0.2), value: vm.turnExtensionUsed)

                // Action buttons — full-width pill row pinned to bottom of
                // screen. Two layouts depending on slider state:
                //   - Closed: Fold | Check-or-Call | Bet
                //   - Open:   Fold | Cancel       | Bet N  (yellow commit)
                // Opening the picker replaces the Check/Call slot with a
                // Cancel pill (closes slider without betting) and turns the
                // third pill into the live commit button that shows the
                // amount the user has dialed in.
                HStack(spacing: 10) {
                    PokerActionButton(style: .fold) { vm.fold() }

                    if vm.showRaiseSlider {
                        // Cancel takes the Check/Call slot while the slider
                        // is open — once the user has decided to raise, the
                        // most useful secondary action is "back out", not
                        // a passive check.
                        PokerActionButton(style: .cancel) {
                            vm.showRaiseSlider = false
                        }
                    } else if vm.canCheck {
                        PokerActionButton(style: .check) { vm.check() }
                    } else if vm.canCall {
                        PokerActionButton(style: .call(amount: vm.callAmount)) { vm.call() }
                    }

                    if vm.showRaiseSlider {
                        // Commit button — yellow, shows the live amount the
                        // slider/pills have set. Tapping fires the raise.
                        // This is the only way to actually bet now; the
                        // slider release no longer auto-commits.
                        PokerActionButton(style: .betCommit(amount: vm.raiseAmount)) {
                            vm.raise()
                        }
                    } else if vm.canRaise {
                        PokerActionButton(style: .raise(active: false)) {
                            // The toggle alone is enough — the parent VStack
                            // already has `.animation(.spring(...), value:
                            // vm.showRaiseSlider)` below, which animates the
                            // panel's insert/remove transition. Wrapping the
                            // toggle in an explicit `withAnimation` *also*
                            // ran a second concurrent transaction over the
                            // same change, and the two springs visibly beat
                            // against each other on first present (the
                            // stutter the user saw). One animation source is
                            // enough — let the modifier own it.
                            vm.showRaiseSlider.toggle()
                        }
                    } else if let seat = vm.mySeat, seat.stack > 0 {
                        PokerActionButton(style: .allIn) { vm.allIn() }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 6)
                .padding(.bottom, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        // Outer frame stays at `baseHeight` minimum so the parent layout
        // never reflows when `isMyTurn` collapses the inner content. See the
        // baseHeight comment above for the full rationale.
        .frame(maxWidth: .infinity, minHeight: Self.baseHeight, alignment: .bottom)
        .animation(.spring(response: 0.35), value: vm.showRaiseSlider)
        // Slowed from 0.4 → 0.5 (with explicit damping 0.85) so the slide-off
        // reads as smooth motion instead of a snap. Now that the layout is
        // stable across `isMyTurn` flips, the longer animation no longer
        // exposes any reflow drift.
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: vm.isMyTurn)
    }
}

// ─── Poker Action Button ──────────────────────────────────────────────────────

struct PokerActionButton: View {
    enum Style {
        case fold
        case check
        case call(amount: Int)
        case raise(active: Bool)
        case allIn
        /// Shown in the third slot when the bet picker is open. Yellow,
        /// dark text, label includes the live amount so the user reads
        /// exactly what they're committing before tapping.
        case betCommit(amount: Int)
        /// Replaces Check/Call in the second slot when the bet picker is
        /// open. Closes the slider without betting.
        case cancel
    }

    let style:  Style
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            action()
        } label: {
            // Comic-panel button: hard ink offset shadow behind the color
            // capsule (no blur — pages don't blur), ink stroke for the
            // panel border, AmericanTypewriter-Bold label in the retro
            // palette's contrast color. Press state collapses the offset
            // so the button reads as "punched in" rather than just shrunk.
            ZStack {
                RoundedRectangle(cornerRadius: 28)
                    .fill(SPRetro.ink)
                    .offset(x: isPressed ? 0 : 2,
                            y: isPressed ? 0 : 3)
                RoundedRectangle(cornerRadius: 28)
                    .fill(backgroundColor)
                RoundedRectangle(cornerRadius: 28)
                    .strokeBorder(SPRetro.ink, lineWidth: 2)
                Text(primaryLabel)
                    .font(.custom("AmericanTypewriter-Bold", size: 18))
                    .foregroundStyle(foregroundColor)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .scaleEffect(isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.12), value: isPressed)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressed {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                    isPressed = true
                }
                .onEnded   { _ in isPressed = false }
        )
    }

    private var primaryLabel: String {
        switch style {
        case .fold:                  return "Fold"
        case .check:                 return "Check"
        case .call(let amount):      return amount > 0 ? "Call \(formatChips(String(amount)))" : "Call"
        case .raise(let active):     return active ? "Cancel" : "Bet"
        case .allIn:                 return "All In"
        case .betCommit(let amount): return "Bet \(formatChips(String(amount)))"
        case .cancel:                return "Cancel"
        }
    }

    /// Retro palette mapping — each style fills with a distinct pop color
    /// from the comic theme so the action row reads as a row of stamped
    /// stickers on the table page. Specifically:
    ///   - fold:      maroon  (#8B2C2C) — the danger color in the system
    ///   - check/call: ink    (#1A1410) — neutral, low-temperature action
    ///   - raise:     pop blue (#2A6DB5) — primary aggressive action
    ///   - allIn/betCommit: mustard (#E8B923) — headline commit color, same
    ///                family as the lobby's JOIN! CTA and the +15s burst
    ///   - cancel:    paperShade (#E8D49A) — neutral page tone, "back out"
    private var backgroundColor: Color {
        switch style {
        case .fold:       return SPRetro.maroon
        case .check:      return SPRetro.ink
        case .call:       return SPRetro.ink
        case .raise:      return SPRetro.popBlue
        case .allIn:      return SPRetro.mustard
        case .betCommit:  return SPRetro.mustard
        case .cancel:     return SPRetro.paperShade
        }
    }

    /// Kept for API compatibility — the ZStack render uses the fixed ink
    /// hard-offset shadow, so this is unused at the call site. Left here
    /// in case future tweaks want a per-style accent shadow.
    private var shadowColor: Color {
        SPRetro.ink
    }

    /// Foreground color for the label. Mustard/paperShade pills get ink
    /// text for contrast on the cream tones; the dark fold/check/call/raise
    /// pills get paper (#F4E4BC) text so the type stays on-palette instead
    /// of using a stark white that reads as foreign Material Design.
    private var foregroundColor: Color {
        switch style {
        case .allIn, .betCommit, .cancel: return SPRetro.ink
        default:                          return SPRetro.paper
        }
    }
}

// ─── Raise Slider Panel ───────────────────────────────────────────────────────

struct RaiseSliderView: View {
    @ObservedObject var vm: GameViewModel

    // Local draft of the slider value so per-tick drags don't write to the
    // @Published `vm.raiseAmount` (which would invalidate every view observing
    // the VM — ActionBar, PokerTableView, GameView — at slider's gesture rate
    // and produce the drag stutter the user reported). The drag updates this
    // local @State only; we commit to the VM exactly twice: on drag release
    // and on confirm tap. The "RAISE TO N" label and quick-pill highlights
    // read from `draft` too so the UI stays in sync without a VM round-trip.
    @State private var draft: Int = 0

    // Detect "all-in" state: the chosen raise amount equals the maximum legal
    // raise, which by construction is the player's stack + their existing bet
    // for the street. When that's true, the action is functionally an all-in
    // and the confirm label should reflect that — calling it "Raise" hides
    // an important fact from the user (e.g., they could fold and survive,
    // versus this commit-everything choice). Computed at render time so it
    // updates with the slider drag.
    private var isAllIn: Bool { draft >= vm.maxRaise && vm.maxRaise > 0 }

    var body: some View {
        // Minimal layout: a larger vertical slider on the right plus a single
        // row of quick-amount pills sitting along the bottom (where the old
        // yellow "Raise to N" CTA used to live). No separate confirm button:
        //
        //   - Tap a pill   → commits a raise to that preset amount
        //   - Drag slider, release → commits a raise at the slider amount
        //   - Tap Cancel (bottom action row) → closes without committing
        //
        // Removing the standalone Raise pill frees a row of vertical space
        // that we give back to the slider, making the drag rail noticeably
        // taller and easier to land on with a thumb.
        let bounds = sliderBounds
        let collapsed = bounds.lo >= bounds.hi - bounds.step / 2
        let panelHeight: CGFloat = 120   // taller slider column; was 110 with
                                         // half the height eaten by the CTA.

        HStack(alignment: .bottom, spacing: 12) {
            // ─── Quick amounts row ───────────────────────────────────────
            // Lowered to the bottom of the picker (sitting on the same
            // baseline the old yellow CTA used to occupy). Pills are
            // *set-only*: tapping snaps the slider's draft and writes the
            // amount to vm.raiseAmount, but does NOT commit the bet — the
            // user explicitly asked for tap-to-commit to be removed. To
            // actually bet, they tap the yellow "Bet N" button in the
            // bottom action row.
            //
            // Visual: each pill is a translucent dark capsule with a thin
            // gold ring. The currently-selected preset inverts to a solid
            // gold fill with dark text so the user can see which preset
            // matches their current amount at a glance.
            HStack(spacing: 6) {
                ForEach(quickAmounts, id: \.label) { qa in
                    let selected = draft == qa.amount
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                            draft = qa.amount
                            vm.raiseAmount = qa.amount
                        }
                        UISelectionFeedbackGenerator().selectionChanged()
                    } label: {
                        // Retro pill: paperShade (unselected) or mustard
                        // (selected) capsule, both wrapped in an ink stroke
                        // and a hard ink offset shadow that collapses on
                        // selection. Text in AmericanTypewriter-Bold ink so
                        // labels read as page-printed stamps rather than
                        // glowing system controls.
                        ZStack {
                            Capsule()
                                .fill(SPRetro.ink)
                                .offset(x: selected ? 0 : 1.5,
                                        y: selected ? 0 : 2)
                            Capsule()
                                .fill(selected
                                      ? SPRetro.mustard
                                      : SPRetro.paperShade)
                            Capsule()
                                .strokeBorder(SPRetro.ink,
                                              lineWidth: selected ? 2 : 1.5)
                            Text(qa.label)
                                .font(.custom("AmericanTypewriter-Bold",
                                              size: 14))
                                .foregroundStyle(SPRetro.ink)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity)

            // ─── Vertical Slider ──────────────────────────────────────────
            // The single drag surface for choosing the bet amount. Release
            // is no longer a commit — `onCommit` only syncs the draft to
            // the VM so the bottom "Bet N" button shows the right number.
            // The user committing happens exclusively via that bottom pill.
            //
            // The slider is now the visual centerpiece of the picker, so
            // we've also bumped up the track thickness, thumb size, and
            // gradient styling (see VerticalRaiseSlider below).
            VerticalRaiseSlider(
                value: $draft,
                lo: bounds.lo,
                hi: bounds.hi,
                step: bounds.step,
                disabled: collapsed,
                onCommit: { vm.raiseAmount = draft }
            )
            .frame(width: 72, height: panelHeight)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        // No background — the picker floats directly over the table area.
        // The pills and Raise CTA each carry their own contrast so they
        // remain legible without a containing panel.
        // Seed the local draft from the VM when the panel mounts, and re-sync
        // whenever the VM's raiseAmount changes externally — that happens when
        // a quick-pill commits, when the server pushes a clamped legal range,
        // or when the panel is dismissed/re-opened on a new turn. Without the
        // re-sync the slider would freeze on a stale value across hands.
        .onAppear { draft = vm.raiseAmount }
        .onChange(of: vm.raiseAmount) { _, new in
            if new != draft { draft = new }
        }
        // Push the local draft up to the VM on every change so the bottom
        // "Bet N" commit button reads the live slider amount. Changes are
        // already step-quantized (the slider snaps before writing draft), so
        // this fires ~10-50 times per full-range drag — not per gesture-tick.
        // The original drag stutter came from per-pixel writes to vm.raiseAmount;
        // per-step writes don't reproduce it.
        .onChange(of: draft) { _, new in
            if vm.raiseAmount != new { vm.raiseAmount = new }
        }
    }

    /// Consistent (lo, hi, step) tuple for the raise Slider. Computed once
    /// per render so the bounds and step are coherent — derived from a
    /// single floor (`lo`) and padded so `hi >= lo + step` always holds.
    /// This is what fixes the "max stride must be positive" crash that
    /// SwiftUI's Slider throws when the range can't fit one step.
    private var sliderBounds: (lo: Double, hi: Double, step: Double) {
        let step = max(1, vm.gameState?.bigBlind ?? 10)
        let lo   = max(1, vm.minRaise)
        // Pad hi up to at least lo + step so Slider always has a stride.
        // Using max(vm.maxRaise, lo + step) means a fully collapsed range
        // (short-stacks where only an all-in is legal) still renders.
        let hi   = max(vm.maxRaise, lo + step)
        return (Double(lo), Double(hi), Double(step))
    }

    private struct QuickAmount { let label: String; let amount: Int }

    // Quick-amount presets. Trimmed from six (Min, ⅓, ½, Pot, 2×, Max) to four
    // because: (a) on a 4-pill row each pill gets ~22% of the bet panel width,
    // which reads cleanly without truncation even on iPhone SE; (b) the dropped
    // ⅓-pot and 2×-current-bet were rarely tapped in practice — Min, ½-pot,
    // Pot, and Max cover the strategic spread of common bet sizes; (c) fewer
    // pills means each one is more deliberate, less "every option crammed in".
    // Each candidate is clamped to the legal [lo, hi] range so we never offer
    // a value the server would reject. Duplicates are de-duped via `seen` —
    // e.g., when minRaise == pot/2 + cb, the Min and ½-pot pills would render
    // the same amount, so we keep only the first.
    private var quickAmounts: [QuickAmount] {
        let lo  = max(1, vm.minRaise)
        let hi  = vm.maxRaise
        let pot = vm.gameState?.totalPot ?? 0
        let cb  = vm.gameState?.currentBet ?? 0

        let items: [(String, Int)] = [
            ("Min",  lo),
            ("½",    min(hi, max(lo, pot / 2 + cb))),
            ("Pot",  min(hi, max(lo, pot + cb))),
            ("Max",  hi),
        ]
        var seen = Set<Int>()
        var out: [QuickAmount] = []
        for (label, amt) in items where amt >= lo && amt <= hi && seen.insert(amt).inserted {
            out.append(QuickAmount(label: label, amount: amt))
        }
        return out
    }
}

// ─── Vertical Raise Slider ────────────────────────────────────────────────────
// Compact custom slider designed for right-thumb access on portrait phones.
// The thumb sits along the right edge of the bet panel, drag UP increases the
// raise amount and drag DOWN decreases it. Each step boundary crossed fires a
// `UISelectionFeedbackGenerator` selection-change so the user can feel chip
// increments without watching the number tick. The track auto-sizes to its
// parent's height (`GeometryReader`) so it scales cleanly across phone widths
// and orientations — narrow phones still get a usable drag rail, big phones
// get a longer rail that's easier to make small adjustments on.
//
// Why not a rotated SwiftUI `Slider`:
//   - `.rotationEffect` on Slider preserves its original hit-test rect, so
//     drag responsiveness becomes weird on the rotated frame.
//   - System Slider exposes no hook for per-step haptic; we want a tick on
//     each `step` boundary, not just on release.
//   - We need explicit Int snapping (chip amounts) and a graceful no-op when
//     the legal range collapses (short-stack forced-allin).

private struct VerticalRaiseSlider: View {
    @Binding var value: Int
    let lo:   Double        // legal minimum chip amount (inclusive)
    let hi:   Double        // legal maximum chip amount (inclusive)
    let step: Double        // increment unit (typically big blind)
    var disabled: Bool = false
    /// Fires once when the drag gesture ends. Mirrors the horizontal Slider's
    /// `onEditingChanged: false` callback — the parent commits the local
    /// draft to the @Published VM here.
    var onCommit: () -> Void = {}

    /// Last `value` we fired a haptic for. We only fire on transitions so
    /// holding the thumb stationary doesn't repeat-fire. Initialized to a
    /// sentinel that can never match a real chip value.
    @State private var lastHapticValue: Int = .min
    /// True while the user is actively dragging. We use this to differentiate
    /// "drag-released-after-modifying" (commit) from "stray tap on track"
    /// (no-op) — the parent view treats `onCommit` as "user picked this
    /// amount and wants to bet", so we must only fire it on a real drag.
    @State private var didDrag: Bool = false
    /// Snapshot of `value` at drag start. Drag commits only if value moved.
    @State private var dragStartValue: Int = 0
    /// Pre-warmed generator. Prepare() reduces first-tap latency from ~120ms
    /// down to ~10ms (Apple's recommended pattern for picker-like UIs).
    private let haptic = UISelectionFeedbackGenerator()

    var body: some View {
        GeometryReader { geo in
            let h    = max(1, geo.size.height)
            let span = max(1, hi - lo)
            // Progress 0...1 from bottom (lo) to top (hi).
            let progress = CGFloat((Double(value) - lo) / span)
                .clamped(to: 0...1)
            let fillH = h * progress
            let thumbR: CGFloat = 18  // diameter 36 — was 28, bumped for
                                      // easier thumb landing now that the
                                      // slider is the primary picker.

            ZStack(alignment: .bottom) {
                // Track — paper-shade pill with an ink hairline border. Flat
                // fill (no gradient) so it reads as a printed channel on the
                // page rather than a glossy system slider. The ink stroke
                // is the same panel-border line used everywhere else in the
                // retro theme.
                Capsule()
                    .fill(SPRetro.paperShade)
                    .frame(width: 14)
                    .overlay(
                        Capsule().strokeBorder(
                            SPRetro.ink,
                            lineWidth: 1.2
                        )
                    )

                // Active fill — flat mustard climbing from the bottom of the
                // track. No gradient, no glow: comic-style fills are solid.
                // When disabled (collapsed range / forced all-in) the fill
                // drops to paperShade so the rail still reads but doesn't
                // imply an interactable amount.
                Capsule()
                    .fill(disabled
                          ? Color(hex: "#DCC58A")
                          : SPRetro.mustard)
                    .frame(width: 14, height: fillH)
                    .overlay(
                        Capsule().strokeBorder(
                            SPRetro.ink,
                            lineWidth: 1.2
                        )
                    )

                // Thumb — retro stamp: ink hard-offset shadow disc behind
                // a mustard ring with a paper inner cap. No blur, no glow,
                // no gradient — comic-style flat fills with ink borders
                // pulled from the same vocabulary as the +15s button.
                ZStack {
                    // Hard ink offset shadow (no blur).
                    Circle()
                        .fill(SPRetro.ink)
                        .frame(width: thumbR * 2, height: thumbR * 2)
                        .offset(x: 1.5, y: 2.5)

                    // Mustard ring (or paperShade when disabled).
                    Circle()
                        .fill(disabled
                              ? Color(hex: "#DCC58A")
                              : SPRetro.mustard)
                        .frame(width: thumbR * 2, height: thumbR * 2)

                    // Ink border around the ring.
                    Circle()
                        .strokeBorder(SPRetro.ink, lineWidth: 2)
                        .frame(width: thumbR * 2, height: thumbR * 2)

                    // Paper inner cap.
                    Circle()
                        .fill(SPRetro.paper)
                        .frame(width: thumbR * 2 - 14, height: thumbR * 2 - 14)
                        .overlay(
                            Circle().strokeBorder(SPRetro.ink,
                                                  lineWidth: 1)
                        )

                    // Live amount badge — mustard capsule with ink border
                    // and a hard ink offset shadow. ChalkboardSE-Bold ink
                    // text reads as a hand-drawn "now showing" sticker.
                    ZStack {
                        Capsule()
                            .fill(SPRetro.ink)
                            .offset(x: 1.5, y: 2)
                        Capsule()
                            .fill(SPRetro.mustard)
                        Capsule()
                            .strokeBorder(SPRetro.ink, lineWidth: 1.5)
                        Text(formatChips(String(value)))
                            .font(.custom("ChalkboardSE-Bold", size: 13))
                            .foregroundStyle(SPRetro.ink)
                            .contentTransition(.numericText())
                            .padding(.horizontal, 10)
                    }
                    .frame(height: 28)
                    .fixedSize()
                    // Offset left of thumb so the tooltip travels with the
                    // drag and the eye doesn't have to jump between the
                    // slider and a static number.
                    .offset(x: -40, y: 0)
                }
                // Position so the circle's center sits at the fill's top.
                // SwiftUI's coordinate origin is top-left, so the offset
                // for "fillH from bottom" is `-fillH` from bottom anchor.
                .offset(y: -fillH + thumbR)
            }
            // Wider tap surface than the visible 6pt track — the gesture
            // recognizer sits on the whole 40pt column so the thumb is
            // forgiving on fast drags.
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            // Require a small minimum drag distance so an accidental
            // stationary tap on the track doesn't immediately commit a raise.
            // A finger that travels ≥4pt has clearly intended to drag.
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { g in
                        guard !disabled else { return }
                        if !didDrag {
                            didDrag = true
                            dragStartValue = value
                        }
                        // SwiftUI gives `g.location.y` in the GeometryReader's
                        // coordinate space (0 at top). Convert to "height
                        // above bottom" so dragging UP increases value.
                        let yFromBottom = max(0, min(h, h - g.location.y))
                        let p           = Double(yFromBottom / h)
                        let raw         = lo + span * p
                        // Snap to nearest step multiple. Computing in float
                        // space and rounding before cast avoids drift on
                        // small step sizes.
                        let steps   = (raw / step).rounded()
                        let snapped = Int(steps * step)
                        let clamped = min(Int(hi), max(Int(lo), snapped))
                        if clamped != value {
                            value = clamped
                            // Only fire haptic on actual step crossings,
                            // not every drag tick at the same value.
                            if clamped != lastHapticValue {
                                haptic.selectionChanged()
                                haptic.prepare()
                                lastHapticValue = clamped
                            }
                        }
                    }
                    .onEnded { _ in
                        defer { didDrag = false }
                        guard !disabled, didDrag, value != dragStartValue
                        else { return }
                        // `onCommit` is no longer "fire the bet" — it just
                        // syncs the local draft to the VM so the bottom
                        // "Bet N" commit button reads the right amount.
                        // The actual raise happens when the user taps that
                        // button.
                        onCommit()
                    }
            )
            .onAppear { haptic.prepare() }
        }
        // No fixed height — the parent HStack lets the GeometryReader fill
        // the column height set by the sibling content. This is what makes
        // the slider scale naturally with table/device size.
    }
}

// Tiny helper so the progress math stays readable. Equivalent to clamping
// against a closed range without pulling in numeric protocols.
private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
