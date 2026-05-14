import SwiftUI

// ─── Top-Up Sheet ────────────────────────────────────────────────────────────
// Sheet that surfaces the chip-purchase tiers when the user taps the chip
// balance pill in the lobby header. Six tiers from $1.99 → $99.99 with a
// "Most Popular" badge on the mid-tier and a "Best Value" badge (computed
// from chips-per-dollar) on the highest tier.
//
// IMPORTANT — purchase wiring:
//   The actual StoreKit transaction is *not* implemented here. The "Buy"
//   action is a clearly-marked stub (see `purchase(_:)`). Wiring real IAPs
//   requires:
//     1. Configuring matching product IDs in App Store Connect.
//     2. Implementing a StoreKit 2 client (`Product.products(for:)`,
//        `product.purchase()`, transaction listener) that calls a backend
//        endpoint to credit chips on verified receipts.
//   The tier list below uses placeholder product IDs (`com.stackpoker.chips.*`)
//   so the eventual StoreKit fetch lines up 1:1 with this UI without any
//   restructuring.
//
// Apple-store compliance:
//   Per App Store guidelines, virtual currency in a poker app must be
//   visibly labeled as play-only chips with no cash-out path. We surface
//   that disclosure in the footer copy.

// ─── Tier model ──────────────────────────────────────────────────────────────

struct ChipPackageTier: Identifiable, Hashable {
    let id: String              // matches the StoreKit product ID
    let chips: Int              // amount credited on successful purchase
    let priceDisplay: String    // pre-localized fallback; replaced by StoreKit's localizedPrice when wired
    let bonusPercent: Int       // 0 = baseline rate; >0 = "+X% bonus"
    let badge: TierBadge?       // nil = no badge

    enum TierBadge: String {
        case popular   = "Most Popular"
        case bestValue = "Best Value"
    }

    // Single source of truth for the lineup. Chips-per-dollar climbs as
    // tiers go up so the higher rows feel like the "deal" — standard f2p
    // ladder. Numbers chosen so the bonus % reads as a clean integer.
    static let lineup: [ChipPackageTier] = [
        .init(id: "com.stackpoker.chips.tier1", chips:   2_000, priceDisplay: "$1.99",  bonusPercent: 0,  badge: nil),
        .init(id: "com.stackpoker.chips.tier2", chips:   5_500, priceDisplay: "$4.99",  bonusPercent: 10, badge: nil),
        .init(id: "com.stackpoker.chips.tier3", chips:  12_000, priceDisplay: "$9.99",  bonusPercent: 20, badge: .popular),
        .init(id: "com.stackpoker.chips.tier4", chips:  30_000, priceDisplay: "$19.99", bonusPercent: 50, badge: nil),
        .init(id: "com.stackpoker.chips.tier5", chips:  80_000, priceDisplay: "$49.99", bonusPercent: 60, badge: nil),
        .init(id: "com.stackpoker.chips.tier6", chips: 200_000, priceDisplay: "$99.99", bonusPercent: 100, badge: .bestValue)
    ]
}

// ─── Sheet ───────────────────────────────────────────────────────────────────

// Note: this `ChipStoreSheet` is distinct from the in-game `TopUpSheet`
// in `Features/Game/Views/GameView.swift`, which handles mid-table rebuys
// against a seated stack. This one sells real-money chip *packages* from
// the lobby — different flow, different gating, different copy.
struct ChipStoreSheet: View {
    @EnvironmentObject var authVM: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    // While a "purchase" is in flight (the stub is instant; this leaves room
    // for the eventual StoreKit call which is async). Indexed by tier id so
    // only the tapped row spins.
    @State private var inFlight: String?
    @State private var errorText: String?
    @State private var successText: String?

    var body: some View {
        NavigationStack {
            ZStack {
                // Aged-paper substrate so the chip store reads as part of
                // the same printed lobby booklet, not a dark IAP screen.
                AgedPaperBackground().ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: SPSpacing.lg) {
                        balanceHeader
                        tierList
                        footerDisclaimer
                        Color.clear.frame(height: 20)
                    }
                    .padding(.top, SPSpacing.md)
                }

                // Transient toast — surfaces success/error without yanking the
                // sheet open and shut. Lives at the bottom edge so it doesn't
                // overlap the balance header.
                if let msg = successText ?? errorText {
                    VStack {
                        Spacer()
                        toast(msg, isError: errorText != nil)
                            .padding(.bottom, SPSpacing.lg)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.4), value: successText)
            .animation(.spring(response: 0.4), value: errorText)
            .navigationTitle("Get Chips")
            .navigationBarTitleDisplayMode(.inline)
            .spNavigationStyle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(SPColors.textSecondary)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(SPColors.background)
    }

    // ─── Header — current balance ────────────────────────────────────────────

    private var balanceHeader: some View {
        // Retro balance panel: paperShade card with ink panel border and
        // hard ink offset shadow. Reuses the mustard dealer-chip + ink
        // typography vocab from the lobby header so the sheet reads as
        // the same printed page.
        VStack(spacing: SPSpacing.sm) {
            Text("CURRENT BALANCE")
                .font(.custom("AmericanTypewriter-Bold", size: 11))
                .tracking(1.4)
                .foregroundStyle(SPRetro.inkMuted)

            HStack(spacing: 10) {
                PokerChip(
                    text: "$",
                    tint: SPRetro.mustard,
                    textColor: SPRetro.ink,
                    size: 36
                )
                Text(authVM.currentUser?.formattedChips ?? "0")
                    .font(.custom("ChalkboardSE-Bold", size: 32))
                    .foregroundStyle(SPRetro.ink)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, SPSpacing.lg)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(SPRetro.ink)
                    .offset(x: 2, y: 3)
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(SPRetro.paperShade)
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(SPRetro.ink, lineWidth: 2)
            }
        )
        .padding(.horizontal, SPSpacing.md)
    }

    // ─── Tier list ───────────────────────────────────────────────────────────

    private var tierList: some View {
        VStack(spacing: SPSpacing.sm) {
            ForEach(ChipPackageTier.lineup) { tier in
                TierRow(
                    tier: tier,
                    isLoading: inFlight == tier.id,
                    isDisabled: inFlight != nil && inFlight != tier.id,
                    onBuy: { Task { await purchase(tier) } }
                )
            }
        }
        .padding(.horizontal, SPSpacing.md)
    }

    // ─── Footer disclaimer ───────────────────────────────────────────────────

    private var footerDisclaimer: some View {
        VStack(spacing: 6) {
            Text("Virtual chips only — no real-money gambling")
                .font(SPFonts.caption(11))
                .foregroundStyle(SPColors.textTertiary)
            Text("Chips are non-refundable and cannot be exchanged for cash.")
                .font(SPFonts.caption(10))
                .foregroundStyle(SPColors.textTertiary.opacity(0.75))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, SPSpacing.md)
    }

    // ─── Toast ───────────────────────────────────────────────────────────────

    private func toast(_ message: String, isError: Bool) -> some View {
        // Retro inline toast — paper pill, ink border + hard offset
        // shadow, ink AmericanTypewriter-Bold body. Pop red icon on
        // errors, muted teal on success. Same vocab as the global
        // ToastView so the IAP sheet feels printed instead of glassy.
        HStack(spacing: 8) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(isError ? SPRetro.popRed : SPRetro.teal)
            Text(message)
                .font(.custom("AmericanTypewriter-Bold", size: 13))
                .foregroundStyle(SPRetro.ink)
                .lineLimit(2)
        }
        .padding(.horizontal, SPSpacing.md)
        .padding(.vertical, SPSpacing.sm)
        .background(
            ZStack {
                Capsule().fill(SPRetro.ink)
                    .offset(x: 1.5, y: 2.5)
                Capsule().fill(SPRetro.paper)
                Capsule().strokeBorder(SPRetro.ink, lineWidth: 1.5)
            }
        )
        .padding(.horizontal, SPSpacing.md)
    }

    // ─── Purchase stub ───────────────────────────────────────────────────────

    // Placeholder for the eventual StoreKit 2 purchase flow. Today this just
    // simulates a brief network hop and shows a "coming soon" toast, so the
    // UI feels real without falsely claiming chips were granted. Replace
    // with `Product.purchase()` + server-side receipt verification once the
    // App Store Connect products are created.
    private func purchase(_ tier: ChipPackageTier) async {
        guard inFlight == nil else { return }
        inFlight = tier.id
        successText = nil
        errorText = nil
        // Simulated latency so the row's spinner is visible — keeps the UI
        // honest about the eventual async StoreKit call.
        try? await Task.sleep(nanoseconds: 600_000_000)
        inFlight = nil

        // Until StoreKit is wired, surface a transparent "not yet available"
        // message rather than silently no-op'ing or pretending it worked.
        errorText = "In-app purchases aren't enabled yet. Coming soon."

        // Auto-clear the toast so it doesn't stick around.
        try? await Task.sleep(nanoseconds: 2_400_000_000)
        if errorText != nil { errorText = nil }
    }
}

// ─── Tier Row ────────────────────────────────────────────────────────────────

// One purchase row. Layout: chip-stack icon (left) + chip amount + bonus
// label, with a gold price button on the right. Optional badge ribbon
// floats above the row's top edge so it doesn't compete with the row's
// own contents for vertical space.
private struct TierRow: View {
    let tier: ChipPackageTier
    let isLoading: Bool
    let isDisabled: Bool
    let onBuy: () -> Void

    private var formattedChips: String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: tier.chips)) ?? "\(tier.chips)"
    }

    // Higher tiers stack more chips visually — three discs for the top,
    // one disc for the entry tier. Cheap visual progression cue.
    private var stackHeight: Int {
        switch tier.bonusPercent {
        case 0:        return 1
        case 1...20:   return 2
        default:       return 3
        }
    }

    var body: some View {
        // Retro tier row: paperShade card on the cream page, ink panel
        // border (mustard ink-bordered when badged so the highlighted
        // tiers visibly pop), hard offset shadow only on badged rows so
        // unbadged tiers don't make the column feel heavy.
        ZStack(alignment: .topTrailing) {
            HStack(spacing: SPSpacing.md) {
                chipStack
                    .frame(width: 56)

                VStack(alignment: .leading, spacing: 4) {
                    Text(formattedChips)
                        .font(.custom("ChalkboardSE-Bold", size: 20))
                        .foregroundStyle(SPRetro.ink)
                    Text(bonusLabel)
                        .font(.custom("AmericanTypewriter-Bold", size: 11))
                        .tracking(0.4)
                        .foregroundStyle(
                            tier.bonusPercent > 0
                                ? SPRetro.mustardDark
                                : SPRetro.inkMuted
                        )
                }

                Spacer(minLength: 0)

                buyButton
            }
            .padding(SPSpacing.md)
            .background(
                ZStack {
                    if tier.badge != nil {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(SPRetro.ink)
                            .offset(x: 2, y: 3)
                    }
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(SPRetro.paperShade)
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(SPRetro.ink,
                                      lineWidth: tier.badge != nil ? 2 : 1.2)
                }
            )

            if let badge = tier.badge {
                badgeRibbon(badge)
                    .offset(x: -SPSpacing.md, y: -10)
            }
        }
        .opacity(isDisabled ? 0.5 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isDisabled)
    }

    private var bonusLabel: String {
        if tier.bonusPercent == 0 {
            return "Starter pack"
        }
        return "+\(tier.bonusPercent)% bonus chips"
    }

    @ViewBuilder
    private var chipStack: some View {
        // Decorative — three layered chips for high tiers, fewer for low.
        // Slight horizontal stagger so the row reads as a stack of physical
        // chips instead of a flat icon.
        ZStack {
            ForEach(0..<stackHeight, id: \.self) { i in
                PokerChip(
                    text: tier.bonusPercent >= 50 ? "$" : "",
                    tint: stackTint(for: i),
                    textColor: Color(hex: "#0D1B2A"),
                    size: 38
                )
                .offset(y: CGFloat(stackHeight - 1 - i) * -3)
                .offset(x: CGFloat(i) * 1.5)
            }
        }
    }

    // Retro stack tints — mustard / pop red / pop blue, all from the
    // retro palette so the chip stack reads as the same chips used at
    // the table rather than f2p-store gold/red/blue gradients.
    private func stackTint(for index: Int) -> Color {
        switch index {
        case 0:  return SPRetro.popRed   // pop red — bottom
        case 1:  return SPRetro.popBlue   // pop blue — middle
        default: return SPRetro.mustard   // mustard — top
        }
    }

    @ViewBuilder
    private var buyButton: some View {
        // Retro price button: mustard capsule with ink border and hard
        // offset shadow, ChalkboardSE-Bold ink price. Same vocab as the
        // SPButton primary so every CTA on the screen reads as the same
        // stamped sticker.
        Button(action: onBuy) {
            ZStack {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(SPRetro.ink)
                } else {
                    Text(tier.priceDisplay)
                        .font(.custom("ChalkboardSE-Bold", size: 15))
                        .foregroundStyle(SPRetro.ink)
                }
            }
            .frame(minWidth: 78)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                ZStack {
                    Capsule().fill(SPRetro.ink)
                        .offset(x: 1.5, y: 2.5)
                    Capsule().fill(SPRetro.mustard)
                    Capsule().strokeBorder(SPRetro.ink, lineWidth: 1.5)
                }
            )
        }
        .buttonStyle(.plain)
        .disabled(isLoading || isDisabled)
    }

    @ViewBuilder
    private func badgeRibbon(_ badge: ChipPackageTier.TierBadge) -> some View {
        // Retro ribbon sticker: mustard capsule, ink border, hard offset
        // shadow, AmericanTypewriter-Bold ink text — reads as a stamped
        // sale sticker pinned over the row's top-left corner.
        Text(badge.rawValue.uppercased())
            .font(.custom("AmericanTypewriter-Bold", size: 9))
            .tracking(1.2)
            .foregroundStyle(SPRetro.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                ZStack {
                    Capsule().fill(SPRetro.ink)
                        .offset(x: 1, y: 2)
                    Capsule().fill(SPRetro.mustard)
                    Capsule().strokeBorder(SPRetro.ink, lineWidth: 1.2)
                }
            )
    }
}
