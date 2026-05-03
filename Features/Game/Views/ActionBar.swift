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
                HStack {
                    Spacer()
                    Button {
                        vm.requestTimeExtension()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 12, weight: .bold))
                            Text("15s")
                                .font(.system(size: 12, weight: .heavy,
                                              design: .rounded))
                        }
                        .foregroundStyle(Color(hex: "#F5C842"))
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .background(
                            Capsule()
                                .fill(Color(hex: "#1A2744"))
                                .overlay(
                                    Capsule().strokeBorder(
                                        Color(hex: "#F5C842").opacity(0.5),
                                        lineWidth: 1
                                    )
                                )
                        )
                        .shadow(color: Color(hex: "#F5C842").opacity(0.25),
                                radius: 6)
                    }
                    .buttonStyle(.plain)
                    .opacity(vm.turnExtensionUsed ? 0 : 1)
                    .allowsHitTesting(!vm.turnExtensionUsed)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 4)
                .animation(.easeOut(duration: 0.2), value: vm.turnExtensionUsed)

                // Action buttons — full-width pill row pinned to bottom of screen
                HStack(spacing: 10) {
                    PokerActionButton(style: .fold) { vm.fold() }

                    if vm.canCheck {
                        PokerActionButton(style: .check) { vm.check() }
                    } else if vm.canCall {
                        PokerActionButton(style: .call(amount: vm.callAmount)) { vm.call() }
                    }

                    if vm.canRaise {
                        PokerActionButton(style: .raise(active: vm.showRaiseSlider)) {
                            withAnimation(.spring(response: 0.35)) {
                                vm.showRaiseSlider.toggle()
                            }
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
        .animation(.spring(response: 0.35), value: vm.showRaiseSlider)
        .animation(.spring(response: 0.4), value: vm.isMyTurn)
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
    }

    let style:  Style
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            action()
        } label: {
            Text(primaryLabel)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(backgroundColor)
                .clipShape(RoundedRectangle(cornerRadius: 28))
                .shadow(color: shadowColor.opacity(0.35), radius: 8, y: 3)
                .scaleEffect(isPressed ? 0.95 : 1.0)
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
        case .fold:              return "Fold"
        case .check:             return "Check"
        case .call(let amount):  return amount > 0 ? "Call \(formatChips(String(amount)))" : "Call"
        case .raise(let active): return active ? "Cancel" : "Bet"
        case .allIn:             return "All In"
        }
    }

    private var backgroundColor: Color {
        switch style {
        case .fold:   return Color(hex: "#C8344A")
        case .check:  return Color(hex: "#2A2A2A")
        case .call:   return Color(hex: "#2A2A2A")
        case .raise:  return Color(hex: "#2D7FF9")
        case .allIn:  return Color(hex: "#F5C842")
        }
    }

    private var shadowColor: Color {
        switch style {
        case .fold:   return Color(hex: "#C8344A")
        case .check:  return .black
        case .call:   return .black
        case .raise:  return Color(hex: "#2D7FF9")
        case .allIn:  return Color(hex: "#F5C842")
        }
    }
}

// ─── Raise Slider Panel ───────────────────────────────────────────────────────

struct RaiseSliderView: View {
    @ObservedObject var vm: GameViewModel

    // Detect "all-in" state: the chosen raise amount equals the maximum legal
    // raise, which by construction is the player's stack + their existing bet
    // for the street. When that's true, the action is functionally an all-in
    // and the confirm label should reflect that — calling it "Raise" hides
    // an important fact from the user (e.g., they could fold and survive,
    // versus this commit-everything choice). Computed at render time so it
    // updates with the slider drag.
    private var isAllIn: Bool { vm.raiseAmount >= vm.maxRaise && vm.maxRaise > 0 }

    var body: some View {
        VStack(spacing: 14) {
            // ─── Amount display ────────────────────────────────────────────
            // Single-line, white. The previous version had a stacked
            // "RAISE TO" all-caps tracked label above a yellow numeric
            // display — two competing visual weights for one piece of info.
            // The label below the number is small and quiet so the number
            // stays the focus.
            VStack(spacing: 2) {
                Text(formatChips(String(vm.raiseAmount)))
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                Text(isAllIn ? "all in" : "raise to")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
            }

            // ─── Quick amounts row ────────────────────────────────────────
            // Trimmed from 6 pills to 4 (Min, ½, Pot, Max). The dropped
            // ⅓ and 2× rarely got tapped and crowded the row on narrow
            // phones (SE, mini). Selected state inverts (white fill, dark
            // text) — single clear visual instead of the previous four
            // overlapping yellow accents.
            HStack(spacing: 8) {
                ForEach(quickAmounts, id: \.label) { qa in
                    let selected = vm.raiseAmount == qa.amount
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                            vm.raiseAmount = qa.amount
                        }
                        UISelectionFeedbackGenerator().selectionChanged()
                    } label: {
                        Text(qa.label)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(selected ? Color(hex: "#0D1B2A") : .white.opacity(0.85))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(selected ? Color.white : Color.white.opacity(0.08))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            // ─── Slider ───────────────────────────────────────────────────
            // SwiftUI's Slider(in:step:) calls Swift.stride internally and
            // crashes with "max stride must be positive" any time the range
            // can't fit even one step. That happens in three legitimate game
            // states: minRaise == maxRaise (short-stack: only an all-in is
            // legal), bigBlind > (max - min) (step bigger than the window),
            // or a transient frame where min/max haven't been computed yet.
            // We derive lo/hi/step from one consistent floor and pad hi up
            // to at least lo + step so the slider always renders.
            //
            // Tint moved from yellow → white. Yellow on a slider track plus
            // a yellow confirm button below was double-accenting; reserving
            // yellow for the action button alone makes it pop more, not less.
            let bounds = sliderBounds
            Slider(
                value: Binding<Double>(
                    get: { Double(min(max(vm.raiseAmount, Int(bounds.lo)), Int(bounds.hi))) },
                    set: { new in
                        vm.raiseAmount = Int(new)
                        UISelectionFeedbackGenerator().selectionChanged()
                    }
                ),
                in: bounds.lo...bounds.hi,
                step: bounds.step
            )
            .tint(.white)
            .padding(.horizontal, 4)
            // Disable when the legal range collapsed to a single value — the
            // user can still confirm via the button below; dragging a
            // one-tick slider would feel broken.
            .disabled(bounds.lo >= bounds.hi - bounds.step / 2)

            // ─── Confirm button ───────────────────────────────────────────
            // Label is dynamic: "All In" when the user has dragged or tapped
            // to max stack, otherwise "Raise to N" so they see what they're
            // about to commit. Removed the yellow drop-shadow glow — that
            // was the single most "video-game-y" element in the old design.
            // Flat fill, slightly tighter corner radius, weight reduced from
            // .heavy to .bold so the button feels confident without shouting.
            Button { vm.raise() } label: {
                Text(isAllIn ? "All In" : "Raise to \(formatChips(String(vm.raiseAmount)))")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color(hex: "#0D1B2A"))
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(Color(hex: "#F5C842"))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        // Background is the same dark navy but the strokeBorder is gone —
        // the panel reads as a clean shape on the action bar without the
        // extra hairline that was making it feel boxed-in.
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(hex: "#0D1B2A").opacity(0.96))
        )
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
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
