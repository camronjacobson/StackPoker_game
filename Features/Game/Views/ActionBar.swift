import SwiftUI

// ─── Action Bar ───────────────────────────────────────────────────────────────
// PurePoker-style action bar: only visible when it's my turn, dark pill
// buttons with colored text, optional raise slider panel.

struct ActionBar: View {
    @ObservedObject var vm: GameViewModel

    var body: some View {
        VStack(spacing: 0) {
            if vm.isMyTurn {
                if vm.showRaiseSlider {
                    RaiseSliderView(vm: vm)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

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

    var body: some View {
        VStack(spacing: 12) {
            // Current raise amount (large centered display)
            VStack(spacing: 1) {
                Text("RAISE TO")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                    .tracking(1.8)
                Text(formatChips(String(vm.raiseAmount)))
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundStyle(Color(hex: "#F5C842"))
                    .contentTransition(.numericText())
            }

            // Quick amounts row
            HStack(spacing: 6) {
                ForEach(quickAmounts, id: \.label) { qa in
                    Button {
                        withAnimation(.spring(response: 0.2)) {
                            vm.raiseAmount = qa.amount
                        }
                        UISelectionFeedbackGenerator().selectionChanged()
                    } label: {
                        Text(qa.label)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(
                                vm.raiseAmount == qa.amount
                                    ? Color(hex: "#F5C842")
                                    : .white.opacity(0.7)
                            )
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                vm.raiseAmount == qa.amount
                                    ? Color(hex: "#2A3D6A")
                                    : Color(hex: "#1A2744")
                            )
                            .clipShape(Capsule())
                            .overlay(
                                Capsule().strokeBorder(
                                    vm.raiseAmount == qa.amount
                                        ? Color(hex: "#F5C842").opacity(0.4)
                                        : Color(hex: "#2A3D6A").opacity(0.4),
                                    lineWidth: 1
                                )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            // Slider
            Slider(
                value: Binding<Double>(
                    get: { Double(vm.raiseAmount) },
                    set: { new in
                        vm.raiseAmount = Int(new)
                        UISelectionFeedbackGenerator().selectionChanged()
                    }
                ),
                in: Double(max(1, vm.minRaise))...Double(max(vm.minRaise + 1, vm.maxRaise)),
                step: Double(max(1, vm.gameState?.bigBlind ?? 10))
            )
            .tint(Color(hex: "#F5C842"))
            .padding(.horizontal, 6)

            // Confirm Raise
            Button { vm.raise() } label: {
                Text("Confirm Raise")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(Color(hex: "#0D1B2A"))
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color(hex: "#F5C842"))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: Color(hex: "#F5C842").opacity(0.35), radius: 8, y: 3)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(hex: "#0D1B2A").opacity(0.95))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(Color(hex: "#2A3D6A"), lineWidth: 1)
                )
        )
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
    }

    private struct QuickAmount { let label: String; let amount: Int }

    private var quickAmounts: [QuickAmount] {
        let lo  = max(1, vm.minRaise)
        let hi  = vm.maxRaise
        let pot = vm.gameState?.totalPot ?? 0
        let cb  = vm.gameState?.currentBet ?? 0
        let two = min(hi, max(lo, cb * 2))

        let items: [(String, Int)] = [
            ("Min",  lo),
            ("⅓",    min(hi, max(lo, pot / 3 + cb))),
            ("½",    min(hi, max(lo, pot / 2 + cb))),
            ("Pot",  min(hi, max(lo, pot + cb))),
            ("2x",   two),
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
