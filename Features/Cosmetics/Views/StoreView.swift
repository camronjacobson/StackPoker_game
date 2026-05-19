import SwiftUI

// ─── Store View ───────────────────────────────────────────────────────────────
//
// The Phase-2 cosmetics store, redesigned 2026-05-18 around three meta-tabs
// instead of the original Featured / Catalog / Aspirational rails:
//
//     Style    — cardBack, cardFace, avatarFrame, tableFelt, chipSet
//     Moves    — dealAnimation, winAnimation, emote
//     Identity — playerTitle + aspirational unlocks
//
// Within each meta-tab the body is a single ScrollView of sub-category
// sections (one section header + one 2-column grid per CosmeticCategory).
// Sub-category headers act as the visual anchors that the old top-tab row
// used to provide. The Featured tab was dropped: the shipped catalog has
// zero limited-time items, so the rail effectively rendered Staff Picks
// every time — pretending at scarcity the store didn't have. A real
// Featured banner can return later (see TODO on StoreViewModel.featuredItems).
//
// View responsibilities:
//   • Meta-tab selection (local @State) and the sub-category section layout.
//   • Procedural preview dispatch — StoreCosmeticPreview routes cardBack
//     and avatarFrame ids through CardBackRenderer / AvatarFrameRenderer
//     when supported, falls back to CosmeticImageView otherwise.
//   • Confirm alert with post-purchase balance copy.
//   • Insufficient-funds → ChipStoreSheet presentation.
//   • Confetti overlay on success.
//
// The VM owns ALL business logic — this view is dumb. If you find yourself
// adding `if ...` to filter or sort items here, it belongs on the VM.

struct StoreView: View {

    @StateObject var vm: StoreViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Which meta-tab is showing. Local state — survives section rebuilds
    /// without resetting on each VM tick.
    @State private var selectedTab: MetaTab = .style

    /// Top-level grouping. The associated `categories` array dictates the
    /// section order within a tab — front-loaded toward the cosmetics the
    /// player will reach for first (Card Backs in Style, Deal Animations
    /// in Moves, Titles in Identity).
    enum MetaTab: String, CaseIterable, Identifiable {
        case style, moves, identity
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .style:    return NSLocalizedString("Style",    comment: "Store meta-tab")
            case .moves:    return NSLocalizedString("Moves",    comment: "Store meta-tab")
            case .identity: return NSLocalizedString("Identity", comment: "Store meta-tab")
            }
        }
        /// Sub-categories rendered inside this tab, in display order.
        var categories: [CosmeticCategory] {
            switch self {
            case .style:
                return [.cardBack, .cardFace, .avatarFrame, .tableFelt, .chipSet]
            case .moves:
                return [.dealAnimation, .winAnimation, .emote]
            case .identity:
                return [.playerTitle]
            }
        }
        /// Identity also surfaces the unlock-by-play items under a single
        /// "Earned by Play" section at the bottom — same conceptual family
        /// as Titles (status indicators), but rendered with AspirationalCell
        /// instead of StoreCosmeticCell because they show progress, not price.
        var includesAspirational: Bool {
            self == .identity
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                header
                tabBar
                ScrollView {
                    LazyVStack(spacing: 20) {
                        sectionsForCurrentTab
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

        // ── Confirm equip alert ──────────────────────────────────────────────
        .alert(equipAlertTitle,
               isPresented: Binding(
                get:  { if case .confirmingEquip = vm.equipFlow { return true }; return false },
                set:  { if !$0 { vm.cancelEquip() } })
        ) {
            Button(NSLocalizedString("Equip", comment: "Confirm equip"),
                   action: vm.confirmEquip)
            Button(NSLocalizedString("Cancel", comment: ""),
                   role: .cancel, action: vm.cancelEquip)
        } message: {
            Text(equipAlertBody)
        }

        // ── Confirm unequip alert ────────────────────────────────────────────
        // Separate alert (not branched copy on a shared one) because the
        // primary button role differs — Unequip is destructive-ish so the
        // user gets clearer messaging.
        .alert(unequipAlertTitle,
               isPresented: Binding(
                get:  { if case .confirmingUnequip = vm.equipFlow { return true }; return false },
                set:  { if !$0 { vm.cancelEquip() } })
        ) {
            Button(NSLocalizedString("Unequip", comment: "Confirm unequip"),
                   role: .destructive, action: vm.confirmUnequip)
            Button(NSLocalizedString("Cancel", comment: ""),
                   role: .cancel, action: vm.cancelEquip)
        }

        // ── Equip error toast ────────────────────────────────────────────────
        .overlay(alignment: .bottom) {
            if let err = vm.lastEquipError {
                EquipErrorToast(error: err) { vm.lastEquipError = nil }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: vm.lastEquipError)

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
    //
    // Three meta-tabs, retro-typographed. Active tab is full-ink with a
    // mustard accent underline; inactive uses textTertiary so the unselected
    // labels read as printed-page tertiary rather than washed-out semantic
    // secondary (the system Color.secondary was an opacity hack on the cream
    // background).

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(MetaTab.allCases) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { selectedTab = tab }
                } label: {
                    VStack(spacing: 6) {
                        Text(tab.displayName)
                            .font(SPFonts.headline(15))
                            .foregroundStyle(selectedTab == tab
                                             ? SPColors.textPrimary
                                             : SPColors.textTertiary)
                        Rectangle()
                            .fill(selectedTab == tab ? SPColors.accent : Color.clear)
                            .frame(height: 2)
                    }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 16)
    }

    // ── Sections per meta-tab ────────────────────────────────────────────────
    //
    // Each sub-category renders as a section header + a 2-col grid of cells.
    // Identity adds an "Earned by Play" section at the bottom that uses
    // AspirationalCell instead of StoreCosmeticCell, since those items
    // surface progress / unlock condition rather than price.

    @ViewBuilder private var sectionsForCurrentTab: some View {
        ForEach(selectedTab.categories, id: \.self) { category in
            if let items = vm.catalogByCategory[category], !items.isEmpty {
                categorySection(category: category, items: items)
            }
        }
        if selectedTab.includesAspirational, !vm.aspirationalItems.isEmpty {
            aspirationalSection
        }
    }

    private let storeColumns: [GridItem] = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
    ]

    @ViewBuilder
    private func categorySection(category: CosmeticCategory, items: [Cosmetic]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(category.displayName)
            LazyVGrid(columns: storeColumns, spacing: 16) {
                ForEach(items) { c in
                    StoreCosmeticCell(
                        cosmetic: c,
                        isOwned: vm.ownedIDs.contains(c.id),
                        isEquipped: vm.equippedByCategory[c.category] == c.id,
                        canAfford: vm.balance.canAfford(ChipAmount(c.priceChips))
                    )
                    .onTapGesture { handleTap(c) }
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
    }

    @ViewBuilder private var aspirationalSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(NSLocalizedString("Earned by Play", comment: "Aspirational section header"))
            LazyVGrid(columns: storeColumns, spacing: 16) {
                ForEach(vm.aspirationalItems) { c in
                    AspirationalCell(cosmetic: c, progress: vm.progress(for: c))
                }
            }
            .padding(.horizontal, 16)
            .drawingGroup()
        }
    }

    /// Owned items route to the equip alert; un-owned items route to
    /// purchase confirm. Branch lives here (not in the VM) so the VM's
    /// `promptPurchase` and `promptEquip` retain narrow contracts —
    /// each one assumes the caller has already gated on ownership. The
    /// view, which holds the rendered `isOwned` state, is the right
    /// place to do the gating.
    private func handleTap(_ c: Cosmetic) {
        if vm.ownedIDs.contains(c.id) {
            vm.promptEquip(c)
        } else {
            vm.promptPurchase(c)
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        HStack {
            Text(text)
                .font(SPFonts.title(20))
                .foregroundStyle(SPColors.textPrimary)
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

    // ── Equip alert copy ─────────────────────────────────────────────────────

    private var equipAlertTitle: String {
        if case .confirmingEquip(let c) = vm.equipFlow {
            return String(format: NSLocalizedString("Equip %@?", comment: "Equip confirm title"), c.name)
        }
        return ""
    }

    private var unequipAlertTitle: String {
        if case .confirmingUnequip(let c) = vm.equipFlow {
            return String(format: NSLocalizedString("Unequip %@?", comment: "Unequip confirm title"), c.name)
        }
        return ""
    }

    /// "Replace your current <category>?" if the slot is occupied by a
    /// different item, otherwise empty — the alert title carries enough
    /// info on its own.
    private var equipAlertBody: String {
        guard case .confirmingEquip(let c) = vm.equipFlow,
              let currentEquippedId = vm.equippedByCategory[c.category],
              currentEquippedId != c.id else { return "" }
        return NSLocalizedString(
            "This will replace your current item in this slot.",
            comment: "Equip body — slot is already occupied")
    }
}

// ─── Store Cosmetic Preview (dispatch) ────────────────────────────────────────
//
// Routes a grid cell's preview area to a procedural renderer when one
// exists for the item's category + id, falling back to CosmeticImageView
// (the rarity-tinted placeholder path) otherwise.
//
// Today's coverage:
//   • cardBack    — CardBackRenderer covers 2 of 8 catalog ids (red, blue);
//                   the remaining 6 fall through to CosmeticImageView. See
//                   TECH_DEBT.md for the cleanup note.
//   • avatarFrame — AvatarFrameRenderer covers all 8 catalog ids. The frame
//                   is an OVERLAY ring per the renderer's contract, so we
//                   render a placeholder avatar disc inside the cell and
//                   stamp the frame around it.
//   • everything else — CosmeticImageView (existing placeholder).

private struct StoreCosmeticPreview: View {
    let cosmetic: Cosmetic
    /// Square slot dimension. Both procedural and placeholder branches
    /// render at this exact footprint so cell layout is identical
    /// regardless of which branch fires.
    let size: CGFloat

    var body: some View {
        switch cosmetic.category {
        case .cardBack where CardBackRenderer.supports(cosmetic.id):
            // Card aspect ratio ~0.72 — render the card centred in the
            // square slot so adjacent cells line up.
            CardBackRenderer.view(
                for: cosmetic.id,
                size: size * 0.72,
                cornerRadius: size * 0.08
            )
            .frame(width: size, height: size)
        case .avatarFrame where AvatarFrameRenderer.supports(cosmetic.id):
            // Placeholder avatar disc + the procedural frame as an overlay
            // ring (matches AvatarFrameRenderer's "outside the disc"
            // contract). Disc is ~72% of the slot; the ring's thickness
            // pushes the frame's outer edge to ~84% — still well inside
            // the cell so the section grid stays even.
            let discDiameter = size * 0.66
            Circle()
                .fill(SPColors.surface)
                .frame(width: discDiameter, height: discDiameter)
                .overlay(
                    Image(systemName: "person.fill")
                        .font(.system(size: discDiameter * 0.45))
                        .foregroundStyle(SPColors.textTertiary)
                )
                .overlay(Circle().strokeBorder(SPColors.border, lineWidth: 1))
                .overlay {
                    AvatarFrameRenderer.view(for: cosmetic.id, diameter: discDiameter)
                }
                .frame(width: size, height: size)
        default:
            CosmeticImageView(cosmetic: cosmetic, size: size)
        }
    }
}

// ─── Store Cosmetic Cell (grid) ───────────────────────────────────────────────
//
// One tile in a sub-category grid. Shows preview, name, rarity badge, and
// a price (or owned/equipped indicator). Owned items render with a slightly
// flatter cream background — communicated by tone, not opacity, so the text
// stays fully legible.

struct StoreCosmeticCell: View {
    let cosmetic: Cosmetic
    let isOwned: Bool
    /// Equipped in its slot — overrides the "Owned" badge with the
    /// brighter "Equipped" label so the player can spot active items at
    /// a glance. Independent of `isOwned` so a future server-granted
    /// equip without a local ownership record renders sensibly (treats
    /// the equipped flag as the visual source of truth).
    let isEquipped: Bool
    let canAfford: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            StoreCosmeticPreview(cosmetic: cosmetic, size: 144)
                .overlay(alignment: .topTrailing) {
                    if isEquipped {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(SPColors.info)
                            .padding(6)
                    } else if isOwned {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(SPColors.success)
                            .padding(6)
                    }
                }
            Text(cosmetic.name)
                .font(SPFonts.headline(14))
                .foregroundStyle(SPColors.textPrimary)
                .lineLimit(1)
            HStack(spacing: 6) {
                Text(cosmetic.rarity.displayName)
                    .font(SPFonts.caption(11))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(cosmetic.rarity.solidColor.opacity(0.25), in: Capsule())
                    .foregroundStyle(cosmetic.rarity.solidColor)
                Spacer()
                if isEquipped {
                    Text(NSLocalizedString("Equipped", comment: ""))
                        .font(SPFonts.caption(11))
                        .foregroundStyle(SPColors.info)
                } else if isOwned {
                    Text(NSLocalizedString("Owned", comment: ""))
                        .font(SPFonts.caption(11))
                        .foregroundStyle(SPColors.textSecondary)
                } else {
                    HStack(spacing: 3) {
                        Image(systemName: "creditcard.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.yellow)
                        // Full-ink price regardless of affordability — the
                        // insufficient-funds tap path already routes to the
                        // top-up sheet, so dimming the number was doing no
                        // real work and hurt readability on cream.
                        Text(ChipAmount(cosmetic.priceChips).shortFormatted)
                            .font(SPFonts.chips(13))
                            .foregroundStyle(SPColors.textPrimary)
                    }
                }
            }
        }
        .padding(14)
        // Owned vs unowned communicated by background tone, not opacity, so
        // text stays full-ink legible. surface (#E8D49A) is one shade
        // lighter than surfaceElevated (#DCC58A) — verify in canvas; if
        // the two tones read identical, swap for a corner ribbon.
        .background(
            isOwned ? SPColors.surface : SPColors.surfaceElevated,
            in: RoundedRectangle(cornerRadius: 12)
        )
        .overlay(
            // Bold ink-stroke matching the lobby button language. 1.5pt is
            // the same stroke used on the balance pill in the header above.
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(SPColors.border, lineWidth: 1.5)
        )
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
        VStack(alignment: .leading, spacing: 10) {
            StoreCosmeticPreview(cosmetic: cosmetic, size: 144)
            Text(cosmetic.name)
                .font(SPFonts.headline(14))
                .foregroundStyle(SPColors.textPrimary)
                .lineLimit(1)
            HStack(spacing: 6) {
                Text(cosmetic.rarity.displayName)
                    .font(SPFonts.caption(11))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(cosmetic.rarity.solidColor.opacity(0.25), in: Capsule())
                    .foregroundStyle(cosmetic.rarity.solidColor)
                Spacer()
                Text(unlockLabel)
                    .font(SPFonts.caption(11))
                    .foregroundStyle(SPColors.textSecondary)
            }
            if let p = progress {
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(p.label)
                            .font(SPFonts.caption(10))
                            .foregroundStyle(SPColors.textSecondary)
                            .lineLimit(1)
                        Spacer()
                        Text("\(p.current)/\(p.target)")
                            .font(SPFonts.caption(10))
                            .foregroundStyle(SPColors.textSecondary)
                    }
                    ProgressView(value: p.fraction)
                        .tint(cosmetic.rarity.solidColor)
                }
            }
        }
        .padding(14)
        .background(SPColors.surfaceElevated, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(SPColors.border, lineWidth: 1.5)
        )
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
        case .priceMismatch:       return NSLocalizedString("Item price has changed. Please refresh and try again.", comment: "")
        case .rateLimited:         return NSLocalizedString("Too many requests. Slow down and try again in a moment.", comment: "")
        case .validationError:     return NSLocalizedString("Something went wrong. Please try again.", comment: "")
        case .network(let s):      return String(format: NSLocalizedString("Network error: %@", comment: ""), s)
        case .atomicityViolation:  return NSLocalizedString("Purchase partially failed — refresh your balance.", comment: "")
        }
    }
}

// ─── Equip Error Toast ────────────────────────────────────────────────────────
//
// Sibling of PurchaseErrorToast. Same look + dismiss behaviour, different
// underlying error type. Kept as a separate struct rather than a generic
// because the per-case message dispatch is tighter when the error is
// concrete — and there are only two of these in the app.

struct EquipErrorToast: View {
    let error: EquipError
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
        case .unknownCosmetic:    return NSLocalizedString("Item not found. Please try again.",                     comment: "")
        case .notOwned:           return NSLocalizedString("You don't own this item yet.",                          comment: "")
        case .categoryMismatch:   return NSLocalizedString("This item can't be equipped here.",                     comment: "")
        case .network(let s):     return String(format: NSLocalizedString("Network error: %@", comment: ""), s)
        }
    }
}
