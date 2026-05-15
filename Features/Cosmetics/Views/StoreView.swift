import SwiftUI

// ─── Store View ───────────────────────────────────────────────────────────────
//
// The Phase-2 cosmetics store. Three rails, one purchase flow, one
// top-right chip-balance pill. Entry points (chips screen / profile row /
// table self-avatar menu) all instantiate this same view, differing only
// in the `entryPoint` passed to the VM for analytics.
//
// View responsibilities:
//   • Section layout: Featured / Catalog / Aspirational (+ Staff Picks
//     fallback when Featured is empty).
//   • Confirm alert with post-purchase balance copy.
//   • Insufficient-funds → ChipStoreSheet presentation.
//   • Confetti overlay on success.
//
// The VM owns ALL business logic — this view is dumb. If you find
// yourself adding `if ...` to filter or sort items here, it belongs on
// StoreViewModel instead.

struct StoreView: View {

    @StateObject var vm: StoreViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Which top-tab is showing. Local state — survives section rebuilds
    /// without resetting on each VM tick.
    @State private var selectedTab: Tab = .featured

    enum Tab: String, CaseIterable, Identifiable {
        case featured, catalog, aspirational
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .featured:     return NSLocalizedString("Featured",     comment: "Store tab")
            case .catalog:      return NSLocalizedString("Catalog",      comment: "Store tab")
            case .aspirational: return NSLocalizedString("Aspirational", comment: "Store tab")
            }
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                header
                tabBar
                ScrollView {
                    LazyVStack(spacing: 24) {
                        switch selectedTab {
                        case .featured:     featuredSection
                        case .catalog:      catalogSection
                        case .aspirational: aspirationalSection
                        }
                    }
                    .padding(.vertical, 16)
                }
            }

            // ── Confetti overlay ─────────────────────────────────────────────
            // Sits over the chrome but allowsHitTesting(false) so taps fall
            // through to the underlying view. The overlay is gated on the
            // purchaseFlow == .celebrating state so it only renders during
            // the 1.5s success window.
            if case .celebrating(let c) = vm.purchaseFlow {
                PurchaseConfettiView(cosmetic: c, reduceMotion: reduceMotion) {
                    vm.celebrationFinished()
                }
                .allowsHitTesting(false)
                .transition(.opacity)
            }
        }
        .onAppear  { vm.onAppear() }
        .onDisappear { vm.onDisappear() }

        // ── Confirm purchase alert ───────────────────────────────────────────
        .alert(confirmAlertTitle,
               isPresented: Binding(
                get:  { if case .confirming = vm.purchaseFlow { return true }; return false },
                set:  { if !$0 { vm.cancelPurchase() } })
        ) {
            Button(NSLocalizedString("Buy", comment: "Confirm purchase button"),
                   action: vm.confirmPurchase)
            Button(NSLocalizedString("Cancel", comment: ""),
                   role: .cancel, action: vm.cancelPurchase)
        } message: {
            Text(confirmAlertBody)
        }

        // ── Insufficient-funds → chip store sheet ────────────────────────────
        .sheet(isPresented: $vm.showInsufficientFundsSheet,
               onDismiss: { vm.onTopUpTapped(source: .insufficientFundsSheet) }) {
            // The existing ChipStoreSheet is the canonical top-up surface
            // (matches the lobby header pill). Reusing it keeps "where to
            // buy chips" a single place across the app.
            ChipStoreSheet()
        }

        // ── Error toast for non-IF failures ──────────────────────────────────
        .overlay(alignment: .bottom) {
            if let err = vm.lastPurchaseError {
                PurchaseErrorToast(error: err) { vm.lastPurchaseError = nil }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: vm.lastPurchaseError)
    }

    // ── Header ───────────────────────────────────────────────────────────────

    private var header: some View {
        HStack(alignment: .center) {
            Text(NSLocalizedString("Store", comment: "Store screen title"))
                .font(.system(size: 28, weight: .bold, design: .rounded))
            Spacer()
            // Top-right balance pill — same visual language as ChipsView,
            // tappable to send the user to top-up.
            Button {
                vm.showInsufficientFundsSheet = true
                vm.onTopUpTapped(source: .balancePill)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "creditcard.circle.fill")
                        .foregroundStyle(.yellow)
                    Text(vm.balance.shortFormatted)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(.green)
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(SPColors.surfaceElevated, in: Capsule())
                .overlay(Capsule().strokeBorder(SPColors.border, lineWidth: 1.5))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 8)
    }

    // ── Tab bar ──────────────────────────────────────────────────────────────

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { selectedTab = tab }
                } label: {
                    VStack(spacing: 6) {
                        Text(tab.displayName)
                            .font(.system(size: 14, weight: selectedTab == tab ? .semibold : .regular))
                            .foregroundStyle(selectedTab == tab ? Color.primary : Color.secondary)
                        Rectangle()
                            .fill(selectedTab == tab ? Color.accentColor : Color.clear)
                            .frame(height: 2)
                    }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 16)
    }

    // ── Featured section ─────────────────────────────────────────────────────

    @ViewBuilder private var featuredSection: some View {
        if !vm.featuredItems.isEmpty {
            sectionHeader(NSLocalizedString("Limited Time", comment: ""))
            ForEach(vm.featuredItems) { c in
                FeaturedCard(cosmetic: c,
                             currentTime: vm.currentTime,
                             isOwned: vm.ownedIDs.contains(c.id))
                    .onTapGesture { vm.promptPurchase(c) }
                    .padding(.horizontal, 16)
            }
        } else {
            sectionHeader(NSLocalizedString("Staff Picks", comment: ""))
            // No live drops — fall back to a curated row of legendaries /
            // mythics. The hero space stays full and the screen never
            // reads as "broken / empty store".
            ForEach(vm.staffPicks) { c in
                FeaturedCard(cosmetic: c,
                             currentTime: vm.currentTime,
                             isOwned: vm.ownedIDs.contains(c.id))
                    .onTapGesture { vm.promptPurchase(c) }
                    .padding(.horizontal, 16)
            }
        }
    }

    // ── Catalog section ──────────────────────────────────────────────────────

    private let catalogColumns: [GridItem] = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    @ViewBuilder private var catalogSection: some View {
        sectionHeader(NSLocalizedString("All Items", comment: ""))
        LazyVGrid(columns: catalogColumns, spacing: 12) {
            ForEach(vm.catalogItems) { c in
                StoreCosmeticCell(
                    cosmetic: c,
                    isOwned: vm.ownedIDs.contains(c.id),
                    canAfford: vm.balance.canAfford(ChipAmount(c.priceChips))
                )
                .onTapGesture { vm.promptPurchase(c) }
            }
        }
        .padding(.horizontal, 16)
        // Rasterize the grid into a Metal layer during the slide-down
        // animation. Each StoreCosmeticCell renders artwork, rarity
        // badge, price pill, and an overlay — re-laying out a dozen of
        // those on every frame of the drawer's spring is the visible
        // stutter source. .drawingGroup() flattens the grid to a single
        // textured surface that SwiftUI just translates, so the cost
        // collapses to a Metal blit per frame.
        .drawingGroup()
    }

    // ── Aspirational section ─────────────────────────────────────────────────

    @ViewBuilder private var aspirationalSection: some View {
        sectionHeader(NSLocalizedString("Earn-only", comment: ""))
        LazyVGrid(columns: catalogColumns, spacing: 12) {
            ForEach(vm.aspirationalItems) { c in
                AspirationalCell(cosmetic: c, progress: vm.progress(for: c))
            }
        }
        .padding(.horizontal, 16)
        // Same reasoning as catalogSection — flatten the grid during
        // the slide-down so per-frame layout cost is a Metal blit.
        .drawingGroup()
    }

    private func sectionHeader(_ text: String) -> some View {
        HStack {
            Text(text)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
            Spacer()
        }
        .padding(.horizontal, 16)
    }

    // ── Alert copy helpers ───────────────────────────────────────────────────

    private var confirmAlertTitle: String {
        if case .confirming(let c) = vm.purchaseFlow {
            return String(format: NSLocalizedString("Buy %@?", comment: "Purchase confirm title"), c.name)
        }
        return ""
    }

    /// "Buy <Name> for <Price> chips? You'll have <Balance-Price> chips remaining."
    /// Built here (not in the VM) because the VM exposes the structured
    /// values; only the formatting / localization belongs in the view layer.
    private var confirmAlertBody: String {
        guard case .confirming(let c) = vm.purchaseFlow,
              let remaining = vm.postPurchaseBalance else { return "" }
        let priceStr = ChipAmount(c.priceChips).longFormatted
        let remStr   = remaining.longFormatted
        let fmt = NSLocalizedString(
            "Spend %1$@ chips? You'll have %2$@ chips remaining.",
            comment: "Purchase confirm body. %1 = price, %2 = remaining balance.")
        return String(format: fmt, priceStr, remStr)
    }
}

// ─── Store Cosmetic Cell (grid) ───────────────────────────────────────────────
//
// One tile in the 2-col Catalog grid. Shows artwork, name, rarity badge,
// and a price chip. Owned items show a "Owned" check overlay instead of
// the price chip and are NOT tappable for repurchase — the VM also re-
// validates ownership on tap, so this is purely a visual affordance.

struct StoreCosmeticCell: View {
    let cosmetic: Cosmetic
    let isOwned: Bool
    let canAfford: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CosmeticImageView(cosmetic: cosmetic, size: 140)
                .overlay(alignment: .topTrailing) {
                    if isOwned {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(.green)
                            .padding(6)
                    }
                }
            Text(cosmetic.name)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
            HStack(spacing: 6) {
                Text(cosmetic.rarity.displayName)
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(cosmetic.rarity.solidColor.opacity(0.2), in: Capsule())
                    .foregroundStyle(cosmetic.rarity.solidColor)
                Spacer()
                if isOwned {
                    Text(NSLocalizedString("Owned", comment: ""))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 3) {
                        Image(systemName: "creditcard.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.yellow)
                        Text(ChipAmount(cosmetic.priceChips).shortFormatted)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(canAfford ? Color.primary : Color.secondary)
                    }
                }
            }
        }
        .padding(10)
        .background(SPColors.surfaceElevated, in: RoundedRectangle(cornerRadius: 12))
        .opacity(isOwned ? 0.65 : 1.0)
    }
}

// ─── Featured Card (hero / limited-time) ──────────────────────────────────────
//
// Wide hero card used by Featured and Staff Picks. Shows the artwork on
// the left, a countdown band on the right when limited, and a price /
// owned label. Tap → confirm purchase.

struct FeaturedCard: View {
    let cosmetic: Cosmetic
    let currentTime: Date
    let isOwned: Bool

    var body: some View {
        HStack(spacing: 14) {
            CosmeticImageView(cosmetic: cosmetic, size: 110)
            VStack(alignment: .leading, spacing: 6) {
                Text(cosmetic.name)
                    .font(.system(size: 17, weight: .semibold))
                Text(cosmetic.rarity.displayName)
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(cosmetic.rarity.solidColor.opacity(0.2), in: Capsule())
                    .foregroundStyle(cosmetic.rarity.solidColor)
                if let remaining = cosmetic.timeUntilExpiry(now: currentTime) {
                    HStack(spacing: 4) {
                        Image(systemName: "timer")
                            .font(.system(size: 11))
                        Text(Self.format(remaining: remaining))
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(.orange)
                }
                Spacer(minLength: 0)
                HStack {
                    if isOwned {
                        Label(NSLocalizedString("Owned", comment: ""),
                              systemImage: "checkmark.seal.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.green)
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "creditcard.circle.fill")
                                .foregroundStyle(.yellow)
                            Text(ChipAmount(cosmetic.priceChips).shortFormatted)
                                .font(.system(size: 14, weight: .semibold))
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(SPColors.surfaceElevated, in: RoundedRectangle(cornerRadius: 14))
        .opacity(isOwned ? 0.65 : 1.0)
    }

    /// "3d 4h", "4h 21m", "12m 03s" depending on order of magnitude. The
    /// per-second / per-minute switch is driven by the VM's tick cadence;
    /// this just renders what the parent passes in.
    static func format(remaining: TimeInterval) -> String {
        let total = Int(remaining)
        let days  = total / 86_400
        let hours = (total % 86_400) / 3600
        let mins  = (total % 3600) / 60
        let secs  =  total % 60
        if days > 0   { return String(format: "%dd %dh", days, hours) }
        if hours > 0  { return String(format: "%dh %dm", hours, mins) }
        if mins > 0   { return String(format: "%dm %02ds", mins, secs) }
        return String(format: "%ds", secs)
    }
}

// ─── Aspirational Cell ────────────────────────────────────────────────────────
//
// Same footprint as StoreCosmeticCell but renders an unlock-condition
// label instead of a price, plus an optional progress bar when the
// AchievementProgressSource can quantify the player's progress.

struct AspirationalCell: View {
    let cosmetic: Cosmetic
    let progress: AchievementProgress?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CosmeticImageView(cosmetic: cosmetic, size: 140)
            Text(cosmetic.name)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
            HStack(spacing: 6) {
                Text(cosmetic.rarity.displayName)
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(cosmetic.rarity.solidColor.opacity(0.2), in: Capsule())
                    .foregroundStyle(cosmetic.rarity.solidColor)
                Spacer()
                Text(unlockLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            if let p = progress {
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(p.label)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        Text("\(p.current)/\(p.target)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: p.fraction)
                        .tint(cosmetic.rarity.solidColor)
                }
            }
        }
        .padding(10)
        .background(SPColors.surfaceElevated, in: RoundedRectangle(cornerRadius: 12))
    }

    private var unlockLabel: String {
        switch cosmetic.unlockCondition {
        case .purchase:     return ""
        case .achievement:  return NSLocalizedString("Achievement",  comment: "")
        case .seasonPass:   return NSLocalizedString("Season Pass",  comment: "")
        case .leaderboard:  return NSLocalizedString("Leaderboard",  comment: "")
        case .eventReward:  return NSLocalizedString("Event",        comment: "")
        }
    }
}

// ─── Purchase Error Toast ─────────────────────────────────────────────────────
//
// Small bottom-sheet-style toast for non-insufficient-funds failures.
// Tapping anywhere dismisses. Auto-dismisses after 3s so a backgrounded
// store doesn't keep a stale error pinned indefinitely.

struct PurchaseErrorToast: View {
    let error: PurchaseError
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 14, weight: .medium))
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(SPColors.surfaceHighlight, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.orange.opacity(0.6), lineWidth: 1)
        )
        .onTapGesture { onDismiss() }
        .task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            onDismiss()
        }
    }

    private var message: String {
        switch error {
        case .alreadyOwned:        return NSLocalizedString("You already own this item.",            comment: "")
        case .notPurchasable:      return NSLocalizedString("This item isn't available in the store.", comment: "")
        case .limitedTimeExpired:  return NSLocalizedString("This limited-time item just expired.",  comment: "")
        case .unknownCosmetic:     return NSLocalizedString("Item not found. Please try again.",     comment: "")
        case .insufficientFunds:   return NSLocalizedString("Not enough chips.",                     comment: "")
        case .network(let s):      return String(format: NSLocalizedString("Network error: %@", comment: ""), s)
        case .atomicityViolation:  return NSLocalizedString("Purchase partially failed — refresh your balance.", comment: "")
        }
    }
}
