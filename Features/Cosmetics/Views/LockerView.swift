import SwiftUI
import Combine

// ─── Locker ──────────────────────────────────────────────────────────────────
//
// "Try on" surface for owned cosmetics. The Store sells items; the Locker
// previews them in-context (avatar with frame, large card back) and equips
// on selection-settle. Hero preview + coverflow picker per supported
// category (avatar frames + card backs in v1).
//
// Architecture is intentionally extensible:
//   - Add a new previewable category by:
//       1. Append the case to `supportedCategories` below.
//       2. Build the procedural renderer for that category.
//       3. Add hero + carousel-cell branches in LockerSection.heroPreview
//          and CarouselCell.body.
//   No state-machine, debounce, or token plumbing changes — those are
//   per-section already.
//
// Two pieces of state, deliberately distinct:
//   - `centeredId` (local @State): driven by every swipe frame, updates the
//     hero immediately for the "trying on" feel. Carries the LockerItem.ID
//     so the "None" sentinel is representable.
//   - `vm.equippedByCategory[category]` (server-authoritative): updated
//     only after EquipService confirms. Drives the "Equipped ✓" badge and
//     the post-failure revert target.
//
// Equip-on-settle flow:
//   swipe → centeredId mutates → hero animates (immediate)
//   debounce 300ms → handleStableSelection() with current centeredId
//   → equipService.equip / unequip (current equipGeneration captured)
//   → on response: if generation matches, surface badge or revert.
//                  if generation has advanced (user swiped again), drop
//                  the stale response silently — `equipGeneration` token
//                  guards against out-of-order RPC completions.
//
// External equip mutations (e.g. admin grant landing while Locker is
// open) re-sync `centeredId` from `equippedByCategory` ONLY when no
// equip is in flight and the user isn't actively swiping. Today nothing
// mutates equippedByCategory from outside Locker while it's open, but
// the guard makes the intent obvious for future contributors.

struct LockerView: View {
    @ObservedObject var vm: StoreViewModel
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var cosmetics: CosmeticsContainer
    @Environment(\.dismiss) private var dismiss

    /// Categories the Locker previews today. Append a case to add a new
    /// previewable surface — every section below dispatches on the
    /// category for its hero render and renderable-id filter.
    private static let supportedCategories: [CosmeticCategory] =
        [.avatarFrame, .cardBack]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    ForEach(Self.supportedCategories, id: \.self) { cat in
                        LockerSection(
                            vm: vm,
                            cosmetics: cosmetics,
                            category: cat,
                            avatarId: authVM.currentUser?.avatarId ?? "avatar_1",
                            onVisitStoreDismiss: { dismiss() }
                        )
                    }
                }
                .padding(.vertical, 24)
            }
            .background(SPColors.background.ignoresSafeArea())
            .navigationTitle(NSLocalizedString("My Locker",
                                               comment: "Locker screen title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(SPColors.textPrimary)
                    }
                }
            }
            .toolbarBackground(SPColors.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }
}

// ─── Locker Section ──────────────────────────────────────────────────────────
//
// One category. Owns the carousel state, debounce pipeline, generation
// token, and the badge / toast UI for *this* category alone — each
// section is self-contained so multi-category equips don't race each
// other (avatar-frame equip in flight while user starts swiping card
// backs is fine).

private struct LockerSection: View {
    @ObservedObject var vm: StoreViewModel
    let cosmetics: CosmeticsContainer
    let category: CosmeticCategory
    let avatarId: String
    let onVisitStoreDismiss: () -> Void

    // ── Local state ──
    @State private var centeredId: LockerItem.ID? = nil
    @State private var isUserSwipingCarousel: Bool = false
    @State private var equipGeneration: UUID? = nil
    @State private var showEquippedBadge: Bool = false
    @State private var errorToast: String? = nil

    // Combine pipeline subject for the debounce. PassthroughSubject (vs.
    // @Published on centeredId directly) lets us send-on-onChange so the
    // hero binding stays simple while the equip path gets its own
    // debounced stream.
    private let centeredSubject = PassthroughSubject<LockerItem.ID?, Never>()

    // Equip-on-settle debounce. 300ms picked as a reasonable default —
    // short enough that the equip feels responsive, long enough that
    // rapid back-and-forth swipes don't fire per-step RPCs. TUNABLE in
    // 200-500ms range based on physical-device feel. Don't pre-tune in
    // simulator (touch latency profile differs); validate on real
    // hardware first.
    private static let equipDebounceMs: Int = 300

    // ── Derived items ──
    private var items: [LockerItem] {
        let renderable = (vm.ownedByCategory[category] ?? [])
            .filter { isRenderable($0) }
        return [.none] + renderable.map { .cosmetic($0) }
    }

    private var isEmpty: Bool {
        items.count == 1 // only the .none sentinel
    }

    private func isRenderable(_ c: Cosmetic) -> Bool {
        switch category {
        case .avatarFrame: return AvatarFrameRenderer.supports(c.id)
        case .cardBack:    return CardBackRenderer.supports(c.id)
        default:           return true
        }
    }

    /// Resolve the `centeredId` sentinel back to a structured `LockerItem`.
    /// Falls back to `.none` if the id no longer exists in the item list
    /// (e.g. catalog shifted under us — extremely rare for v1).
    private func resolve(_ id: LockerItem.ID?) -> LockerItem {
        guard let id else { return .none }
        if id == LockerItem.noneId { return .none }
        if let c = items.compactMap({ $0.cosmetic }).first(where: { $0.id == id }) {
            return .cosmetic(c)
        }
        return .none
    }

    private var previewedCosmetic: Cosmetic? {
        if case .cosmetic(let c) = resolve(centeredId) { return c }
        return nil
    }

    // ── Body ──
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader

            if isEmpty {
                emptyState
            } else {
                heroBlock
                carousel
            }
        }
        .overlay(alignment: .bottom) { errorToastOverlay }
        .onAppear { syncFromServerEquip() }
        .onChange(of: vm.equippedByCategory[category]) { _, _ in
            // External equip flips (admin grant, multi-device,
            // other surfaces) should only sync the Locker UI when
            // no equip is in flight AND the user isn't actively
            // swiping. Otherwise we'd yank the carousel out from
            // under the user's finger or stomp a pending equip
            // that hasn't returned yet. Today this is theoretical
            // for v1, but spelling it out keeps future paths
            // honest.
            guard equipGeneration == nil, !isUserSwipingCarousel else { return }
            syncFromServerEquip()
        }
        .onChange(of: centeredId) { _, newId in
            centeredSubject.send(newId)
        }
        .onReceive(centeredSubject
            .debounce(for: .milliseconds(Self.equipDebounceMs),
                      scheduler: RunLoop.main)
            .removeDuplicates()
        ) { stable in
            handleStableSelection(stable)
        }
    }

    // ── Sub-views ────────────────────────────────────────────────────────────

    private var sectionHeader: some View {
        Text(category.displayName)
            .font(SPFonts.headline(20))
            .foregroundStyle(SPColors.textPrimary)
            .padding(.horizontal, 20)
    }

    @ViewBuilder
    private var heroBlock: some View {
        ZStack {
            heroPreview
                // Cross-fade when selection changes — animated against
                // the LockerItem id so identity-stable hero transitions
                // (e.g. same item re-centered) don't trigger a fade.
                .id(centeredId ?? LockerItem.noneId)
                .transition(.opacity)
                .animation(.smooth(duration: 0.25), value: centeredId)
        }
        .frame(height: 180)
        .frame(maxWidth: .infinity)
        // Badge as overlay (not VStack sibling) so its appearance does
        // NOT push the carousel down — layout stays stable across
        // equip-settle cycles. Anchored 8pt up from the bottom edge of
        // the hero so it floats over the lower portion of the preview
        // without obscuring it.
        .overlay(alignment: .bottom) {
            if showEquippedBadge {
                equippedBadge
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom)
                        .combined(with: .opacity))
            }
        }
        .animation(.smooth(duration: 0.3), value: showEquippedBadge)
    }

    @ViewBuilder
    private var heroPreview: some View {
        switch category {
        case .avatarFrame:
            // 140pt — within the renderer's tested 40-100pt range
            // ceiling (which it explicitly says scales linearly).
            // showBorder false so the cosmetic frame, not the
            // selection ink-border, is the visual headliner.
            AvatarView(
                avatarId:      avatarId,
                size:          140,
                showBorder:    false,
                avatarFrameId: previewedCosmetic?.id
            )
        case .cardBack:
            // 120pt wide; aspect ratio inherits from CardBackRenderer
            // (~0.72). For .none sentinel render a paper outline of
            // the same dimensions so layout stays stable when toggling.
            if let id = previewedCosmetic?.id {
                CardBackRenderer.view(
                    for: id,
                    size: 120,
                    cornerRadius: 12
                )
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(SPColors.surface)
                    .frame(width: 120, height: 120 / 0.72)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(SPColors.borderLight,
                                          style: StrokeStyle(lineWidth: 1.5,
                                                             dash: [4, 4]))
                    )
                    .overlay(
                        Image(systemName: "rectangle.dashed")
                            .font(.system(size: 28))
                            .foregroundStyle(SPColors.textTertiary)
                    )
            }
        default:
            EmptyView()
        }
    }

    private var equippedBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(SPColors.success)
            Text(NSLocalizedString("Equipped",
                                   comment: "Locker equipped confirmation"))
                .font(SPFonts.caption(12))
                .foregroundStyle(SPColors.textPrimary)
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(SPColors.surfaceElevated, in: Capsule())
        .overlay(Capsule().strokeBorder(SPColors.border, lineWidth: 1))
    }

    @ViewBuilder
    private var carousel: some View {
        GeometryReader { geo in
            let cell: CGFloat = 80
            let leadingPad = (geo.size.width - cell) / 2
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(items) { item in
                        CarouselCell(item: item, category: category)
                            .frame(width: cell, height: cell)
                            .scrollTransition(.interactive) { content, phase in
                                content
                                    .scaleEffect(phase.isIdentity ? 1.15 : 0.75)
                                    .opacity(phase.isIdentity ? 1.0 : 0.55)
                            }
                            .onTapGesture {
                                withAnimation(.smooth(duration: 0.25)) {
                                    centeredId = item.id
                                }
                            }
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, leadingPad)
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: Binding(
                get: { centeredId },
                set: { centeredId = $0 }
            ))
            // iOS 17.5 fallback for active-touch detection (no
            // onScrollPhaseChange until iOS 18). A 0-distance drag layered
            // simultaneously over the ScrollView fires onChanged the
            // moment the finger touches and onEnded the moment it lifts.
            // Won't block ScrollView's own pan because it's a
            // simultaneousGesture (recognised in parallel). Used purely
            // for the external-state interlock — see handleStableSelection.
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in isUserSwipingCarousel = true }
                    .onEnded   { _ in isUserSwipingCarousel = false }
            )
        }
        .frame(height: 110)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text(String(format: NSLocalizedString(
                "No %@ owned yet",
                comment: "Locker empty state — %@ is lowercased plural category name."),
                        category.displayName.lowercased()))
                .font(SPFonts.body(14).italic())
                .foregroundStyle(SPRetro.inkSoft)

            Button {
                // v1 = dismiss only. TECH_DEBT entry tracks the future
                // section-scroll deep-link to the relevant Store category.
                onVisitStoreDismiss()
            } label: {
                HStack(spacing: 4) {
                    Text(NSLocalizedString("Visit Store",
                                           comment: "Locker empty-state CTA"))
                    Image(systemName: "arrow.right")
                }
                .font(SPFonts.headline(14))
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(SPColors.accent, in: Capsule())
                .overlay(Capsule().strokeBorder(SPColors.border, lineWidth: 1.5))
                .foregroundStyle(SPColors.textPrimary)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private var errorToastOverlay: some View {
        if let msg = errorToast {
            Text(msg)
                .font(SPFonts.caption(13))
                .foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(SPColors.danger, in: Capsule())
                .padding(.bottom, 24)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task {
                    try? await Task.sleep(for: .seconds(2.5))
                    withAnimation(.smooth(duration: 0.3)) { errorToast = nil }
                }
        }
    }

    // ── Equip flow ───────────────────────────────────────────────────────────

    private func syncFromServerEquip() {
        let serverEquip = vm.equippedByCategory[category]
        let newCenter: LockerItem.ID = serverEquip ?? LockerItem.noneId
        // Avoid redundant writes (which would echo back through
        // centeredSubject and re-trigger debounce → equip RPC).
        if centeredId != newCenter {
            centeredId = newCenter
        }
    }

    private func handleStableSelection(_ stable: LockerItem.ID?) {
        let target = resolve(stable)

        // No-op if the stable selection matches what's already equipped
        // server-side. Prevents re-firing equip on every Locker open
        // (the initial sync sets centeredId = serverEquip, which would
        // otherwise debounce-fire an equip on first appearance).
        let serverEquipId = vm.equippedByCategory[category]
        switch target {
        case .none where serverEquipId == nil:
            return
        case .cosmetic(let c) where c.id == serverEquipId:
            return
        default:
            break
        }

        let myGen = UUID()
        equipGeneration = myGen

        Task { @MainActor in
            let result: EquipResult
            switch target {
            case .none:
                result = await cosmetics.equipService.unequip(category)
            case .cosmetic(let c):
                result = await cosmetics.equipService.equip(c)
            }

            // Stale-response guard: only the latest generation gets to
            // mutate Locker UI. Out-of-order completions from earlier
            // swipes are silently dropped.
            guard equipGeneration == myGen else { return }
            handleEquipResult(result)
        }
    }

    private func handleEquipResult(_ result: EquipResult) {
        equipGeneration = nil
        switch result {
        case .success:
            withAnimation(.smooth(duration: 0.3)) {
                showEquippedBadge = true
            }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.5))
                withAnimation(.smooth(duration: 0.3)) {
                    showEquippedBadge = false
                }
            }
        case .failure(let err):
            withAnimation(.smooth(duration: 0.3)) {
                errorToast = errorMessage(for: err)
            }
            // Revert preview to actual server-confirmed state. Carousel
            // animates back via scrollPosition binding; hero re-renders
            // alongside.
            syncFromServerEquip()
        }
    }

    private func errorMessage(for err: EquipError) -> String {
        switch err {
        case .unknownCosmetic, .categoryMismatch:
            return NSLocalizedString("Couldn't equip — please try again.",
                                     comment: "Locker generic equip error")
        case .notOwned:
            return NSLocalizedString("You don't own that yet.",
                                     comment: "Locker not-owned equip error")
        case .network(let msg):
            return msg
        }
    }
}

// ─── Locker Item ─────────────────────────────────────────────────────────────
//
// Sum type for carousel positions. `.none` is the always-first position
// representing "no frame / no card back" — settling on it triggers
// `unequip(category)`. `.cosmetic(c)` carries the full model for
// rendering and the equip call. Identifiable via a stable string id so
// ScrollView.scrollPosition can bind to it.

private enum LockerItem: Hashable, Identifiable {
    case none
    case cosmetic(Cosmetic)

    static let noneId: String = "__locker_none__"

    var id: String {
        switch self {
        case .none: return Self.noneId
        case .cosmetic(let c): return c.id
        }
    }

    var cosmetic: Cosmetic? {
        if case .cosmetic(let c) = self { return c }
        return nil
    }
}

// ─── Carousel Cell ───────────────────────────────────────────────────────────

private struct CarouselCell: View {
    let item: LockerItem
    let category: CosmeticCategory

    var body: some View {
        ZStack {
            switch (item, category) {
            case (.none, .avatarFrame):
                Circle()
                    .fill(SPColors.surface)
                    .frame(width: 60, height: 60)
                Circle()
                    .strokeBorder(SPColors.borderLight,
                                  style: StrokeStyle(lineWidth: 1.5,
                                                     dash: [4, 4]))
                    .frame(width: 60, height: 60)
                Image(systemName: "person.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(SPColors.textTertiary)

            case (.none, .cardBack):
                RoundedRectangle(cornerRadius: 8)
                    .fill(SPColors.surface)
                    .frame(width: 50, height: 70)
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(SPColors.borderLight,
                                  style: StrokeStyle(lineWidth: 1.5,
                                                     dash: [4, 4]))
                    .frame(width: 50, height: 70)
                Image(systemName: "rectangle.dashed")
                    .font(.system(size: 18))
                    .foregroundStyle(SPColors.textTertiary)

            case (.cosmetic(let c), .avatarFrame):
                let d: CGFloat = 60
                Circle()
                    .fill(SPColors.surface)
                    .frame(width: d, height: d)
                Circle()
                    .strokeBorder(SPColors.border, lineWidth: 1)
                    .frame(width: d, height: d)
                AvatarFrameRenderer.view(for: c.id, diameter: d)

            case (.cosmetic(let c), .cardBack):
                CardBackRenderer.view(for: c.id, size: 56, cornerRadius: 6)

            default:
                // Unreachable for v1's two supported categories. Future
                // categories that get added to supportedCategories
                // without a cell branch will surface as a debug
                // placeholder rather than silently render nothing.
                Image(systemName: "questionmark.square.dashed")
                    .font(.system(size: 24))
                    .foregroundStyle(SPColors.textTertiary)
            }
        }
        .frame(width: 80, height: 80)
    }
}
