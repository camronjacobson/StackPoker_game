import SwiftUI

// ─── Action Bar ───────────────────────────────────────────────────────────────
// PurePoker-style action bar: only visible when it's my turn, dark pill
// buttons with colored text, optional raise slider panel.

// MAP: ActionBar — fold/check/call/raise + +15s + in-place bet entry
// - ActionBar (root) ........................ L13
// - PokerActionButton (single pill) ......... L170
//
// Fine-tune slider lives in VerticalChipSlider.swift (right-edge column,
// mounted by GameView.portraitLayout's overlay, NOT inside ActionBar).

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
    // Bet entry now transforms the action row IN PLACE instead of
    // mounting any overlay/sheet — the row morphs from
    // [Fold / Check-or-Call / Raise] into
    // [preset₁ / preset₂ / preset₃ / Confirm] with a slim slider just
    // above it. The bar's frame still stays at baseHeight when not in
    // bet mode; in bet mode it grows by the slider strip (~32pt) which
    // is small enough that the table doesn't visibly reflow.
    private static let baseHeight: CGFloat = 110

    /// Spring matching the cosmetics-store drawer — used for the
    /// in-place morph between default and betting rows, and for the
    /// slider snap when a preset is tapped.
    private static let morph: Animation =
        .spring(response: 0.32, dampingFraction: 0.9)

    var body: some View {
        VStack(spacing: 0) {
            if vm.isMyTurn {
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

                // The fine-tune slider used to live inline above this
                // row; it's now a dedicated right-side column rendered
                // by VerticalChipSlider in GameView.portraitLayout's
                // overlay. Keeping the bar lean here means opening the
                // bet picker doesn't grow the bottom strip — the chip
                // column claims its own region of the screen.

                // ── Action row ───────────────────────────────────────────
                // Two-mode morph driven by vm.showRaiseSlider:
                //   - default: [Fold] [Check or Call] [Raise]
                //   - betting: [preset₁] [preset₂] [preset₃] [Confirm]
                // Preset labels come from vm.isPostflop:
                //   preflop  → [2BB] [3BB] [4BB]
                //   postflop → [33%] [66%] [100%]
                // Each preset is always tappable; the resulting amount
                // is clamped to [minRaise, maxRaise] silently inside
                // betPresets(). Confirm fires vm.raise() and resets the
                // flag — that closes the morph and reverts the row to
                // default state for the next decision.
                HStack(spacing: 10) {
                    if vm.showRaiseSlider {
                        ForEach(betPresets, id: \.label) { preset in
                            PokerActionButton(style: .preset(label: preset.label)) {
                                UISelectionFeedbackGenerator().selectionChanged()
                                withAnimation(Self.morph) {
                                    vm.raiseAmount = preset.amount
                                }
                            }
                        }
                        PokerActionButton(style: .confirm) {
                            vm.raise()
                            vm.showRaiseSlider = false
                        }
                    } else {
                        PokerActionButton(style: .fold) { vm.fold() }

                        if vm.canCheck {
                            PokerActionButton(style: .check) { vm.check() }
                        } else if vm.canCall {
                            PokerActionButton(style: .call(amount: vm.callAmount)) { vm.call() }
                        }

                        if vm.canRaise {
                            PokerActionButton(style: .raise(active: false)) {
                                // Seed the slider at min legal raise so each
                                // open is a fresh deliberate entry — no
                                // stale value from a prior aborted bet.
                                vm.raiseAmount = vm.minRaise
                                vm.showRaiseSlider = true
                            }
                        } else if let seat = vm.mySeat, seat.stack > 0 {
                            PokerActionButton(style: .allIn) { vm.allIn() }
                        }
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
        // Drive the in-place morph between default row and betting row from
        // a single animation modifier. We use the same drawer-style spring
        // (`morph`) for both the slim slider's appear/disappear and the
        // HStack content swap so the two read as one motion. Without this,
        // the slider would fade with whatever ambient animation context
        // the parent injects (often `.default`), creating a small lag
        // between the buttons morphing and the slider sliding in.
        .animation(Self.morph, value: vm.showRaiseSlider)
        // Slowed from 0.4 → 0.5 (with explicit damping 0.85) so the slide-off
        // reads as smooth motion instead of a snap. Now that the layout is
        // stable across `isMyTurn` flips, the longer animation no longer
        // exposes any reflow drift.
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: vm.isMyTurn)
    }

    // ─── Bet-row preset model ────────────────────────────────────────────
    /// Single preset chip on the betting row. The label is what's drawn on
    /// the pill (e.g. "2BB" or "66%"); `amount` is the clamped chip count
    /// that gets written into `vm.raiseAmount` when tapped.
    private struct BetPreset { let label: String; let amount: Int }

    /// Three presets for the betting-row HStack, computed live so a hand
    /// transitioning from preflop → flop swaps labels without remounting
    /// the bar. Always returns exactly three entries; if any preset's raw
    /// amount falls outside `[minRaise, maxRaise]` the value is clamped
    /// silently rather than dropping the pill — keeping the slot count
    /// constant prevents the row width from jittering as the legal range
    /// changes (a short stack can otherwise see the row reflow each
    /// street). Preflop uses BB multiples (industry-standard preflop
    /// shorthand); postflop uses pot-percentage opens calculated against
    /// pot + call so "100%" reads as a true pot-sized raise after calling.
    private var betPresets: [BetPreset] {
        let lo  = max(1, vm.minRaise)
        let hi  = max(lo, vm.maxRaise)
        let clamp: (Int) -> Int = { min(hi, max(lo, $0)) }

        if vm.isPostflop {
            let pot  = vm.gameState?.totalPot ?? 0
            let cb   = vm.gameState?.currentBet ?? 0
            let myBet = vm.mySeat?.betThisStreet ?? 0
            // Amount we'd have to call before our raise lands. Including it
            // in the pot baseline makes "100% pot" mean a true pot-sized
            // raise (commit call + bet the new pot), matching how solvers
            // and live-poker shorthand describe pot-sized bets.
            let callAmt = max(0, cb - myBet)
            let basePot = pot + callAmt
            // raise-to amount = current bet + percentage of the post-call pot.
            // We send "raise to" not "raise by" because vm.raiseAmount and
            // the server's BetAction both use absolute target amounts.
            let pct: (Double) -> Int = { p in
                clamp(cb + Int((Double(basePot) * p).rounded()))
            }
            return [
                BetPreset(label: "33%",  amount: pct(0.33)),
                BetPreset(label: "66%",  amount: pct(0.66)),
                BetPreset(label: "100%", amount: pct(1.00)),
            ]
        } else {
            let bb = max(1, vm.gameState?.bigBlind ?? 10)
            return [
                BetPreset(label: "2BB", amount: clamp(2 * bb)),
                BetPreset(label: "3BB", amount: clamp(3 * bb)),
                BetPreset(label: "4BB", amount: clamp(4 * bb)),
            ]
        }
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
        /// One of the three quick-amount chips on the betting row
        /// ("2BB", "3BB", "4BB" preflop; "33%", "66%", "100%" postflop).
        /// Label is supplied by ActionBar.betPresets — the button itself
        /// doesn't know about chip math, it just snaps the slider when
        /// tapped (the action closure handles that). Visual: paperShade
        /// fill so the chips read as recessed page-tone pills against
        /// the bolder fold/raise pills, keeping the eye on Confirm.
        case preset(label: String)
        /// Final commit pill in the fourth slot of the betting row. Label
        /// is just "Confirm" — the live amount lives on the slim slider's
        /// thumb badge directly above, so duplicating it here would
        /// create two competing numbers on the same row. Mustard fill
        /// + ink text marks it as the headline commit action.
        case confirm
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
        case .fold:                 return "Fold"
        case .check:                return "Check"
        case .call(let amount):     return amount > 0 ? "Call \(formatChips(String(amount)))" : "Call"
        case .raise(let active):    return active ? "Cancel" : "Bet"
        case .allIn:                return "All In"
        case .preset(let label):    return label
        case .confirm:              return "Confirm"
        }
    }

    /// Retro palette mapping — each style fills with a distinct pop color
    /// from the comic theme so the action row reads as a row of stamped
    /// stickers on the table page. Specifically:
    ///   - fold:      maroon  (#8B2C2C) — the danger color in the system
    ///   - check/call: ink    (#1A1410) — neutral, low-temperature action
    ///   - raise:     pop blue (#2A6DB5) — primary aggressive action
    ///   - allIn/confirm: mustard (#E8B923) — headline commit color, same
    ///                family as the lobby's JOIN! CTA and the +15s burst
    ///   - preset:    paperShade (#E8D49A) — neutral page tone for the
    ///                amount chips; keeps the eye on the bolder Confirm
    private var backgroundColor: Color {
        switch style {
        case .fold:    return SPRetro.maroon
        case .check:   return SPRetro.ink
        case .call:    return SPRetro.ink
        case .raise:   return SPRetro.popBlue
        case .allIn:   return SPRetro.mustard
        case .preset:  return SPRetro.paperShade
        case .confirm: return SPRetro.mustard
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
        case .allIn, .preset, .confirm: return SPRetro.ink
        default:                        return SPRetro.paper
        }
    }
}
