import SwiftUI
import Combine

// ─── Game View ────────────────────────────────────────────────────────────────
// Full-screen poker table. Replaces the placeholder from Phase 2.

// MAP: GameView — top-level in-game scene, owns layouts + overlays (1283 lines)
// - GameView (root) ........................ L6
// - portraitLayout ......................... L131
// - landscapeLayout ........................ L150
// - Top bar (back/menu/info) ............... L185
// - localPlayerOverlay (my cards + tap-show) L259
// - tableArea (felt + seats) ............... L393
// - ChatOverlay ............................ L501
// - WinnerCelebrationOverlay ............... L575
// - FoldTossModifier (fold animation) ...... L747
// - TableSideMenu .......................... L764
// - TopUpSheet ............................. L1099

struct GameView: View {
    @StateObject var vm: GameViewModel
    @Environment(\.dismiss) var dismiss

    // LobbyViewModel propagates from MainTabView via environmentObject; the
    // fullScreenCover that presents GameView carries it through. Needed for
    // the waiting-overlay invite button (lastTable, canSendInvites,
    // resetInviteSheet) and the invite POST inside InviteFriendsSheet.
    @EnvironmentObject private var lobbyVM: LobbyViewModel

    // Inherited from RootView via the fullScreenCover boundary. Needed
    // for the table-side store panel: AuthViewModel exposes the balance
    // publisher StoreViewModel listens to, CosmeticsContainer is the DI
    // container the store reads its catalog + inventory from. Both are
    // injected at app root in StackPokerApp.
    @EnvironmentObject private var authViewModel: AuthViewModel
    @EnvironmentObject private var cosmetics: CosmeticsContainer

    // Local FriendsViewModel for the invite sheet — same pattern PokerTableView
    // uses. The sheet's own .task triggers loadFriends() so we don't preload.
    @StateObject private var friendsVM = FriendsViewModel()

    // Drives the invite sheet on the waiting overlay. Separate from the
    // PokerTableView seat-tap sheet binding so the two can't fight over
    // presentation state.
    @State private var showWaitingInviteSheet = false

    // Themed room background — follows the user's chosen table color so the
    // surrounding gradient complements the felt.
    @AppStorage("tableThemeId") private var tableThemeId: String = "classic_blue"
    private var theme: TableTheme { TableTheme.find(tableThemeId) }

    // Table capacity as configured at creation time. Server's ClientGameState
    // does not include maxPlayers (its `seats` array is only the occupied
    // seats), so we plumb it in from the lobby. Falls back to 6 when the
    // caller didn't supply it (e.g. legacy deep link).
    private let maxSeats: Int

    init(tableId: String, tableName: String, maxSeats: Int = 6) {
        self.maxSeats = max(2, min(9, maxSeats))
        _vm = StateObject(wrappedValue: GameViewModel(tableId: tableId, tableName: tableName))
    }

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            ZStack {
                // ── Room background — follows the selected table theme
                ZStack {
                    LinearGradient(
                        colors: [Color(hex: theme.roomTop), Color(hex: theme.roomBottom)],
                        startPoint: .top, endPoint: .bottom
                    ).ignoresSafeArea()

                    // Radial glow tinted with the theme's primary color
                    RadialGradient(
                        colors: [
                            theme.primaryColor.opacity(0.22),
                            theme.edgeColor.opacity(0.10),
                            Color.clear,
                        ],
                        center: .center,
                        startRadius: 40,
                        endRadius: max(geo.size.width, geo.size.height) * 0.65
                    )
                    .ignoresSafeArea()
                    .blendMode(.plusLighter)
                    .allowsHitTesting(false)
                }

                if landscape {
                    landscapeLayout(geo: geo)
                } else {
                    portraitLayout(geo: geo)
                }

                // ── Overlays (z-ordered) ──────────────────────────────────────

                // (Winner reveal happens at the table — see PokerTableView's
                //  showdown logic. No full-screen modal.)

                // Chat panel
                if vm.showChat {
                    ChatOverlay(vm: vm)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                        .zIndex(50)
                }

                // Side menu — sliding drawer from the left
                if vm.showSideMenu {
                    TableSideMenu(vm: vm)
                        .transition(.move(edge: .leading))
                        .zIndex(55)
                }

                // Top-up sheet (presented from the side menu)
                if vm.showTopUpSheet {
                    TopUpSheet(vm: vm)
                        .transition(.opacity)
                        .zIndex(70)
                }

                // ── Cosmetics store: scrim ──────────────────────────
                // Dim black overlay behind the panel when open. Provides
                // the third dismiss path (tap-outside-the-panel to
                // close) and visually anchors the panel as a modal
                // layer.
                //
                // .allowsHitTesting(vm.isStorePanelOpen) so the table
                // (poker actions, seat taps) remains interactive when
                // the panel is closed — without this gate, the scrim's
                // full-screen frame would silently eat all taps even
                // at opacity 0.
                //
                // 0.4 black matches the iOS native sheet scrim density.
                // Animation duration intentionally shorter than the
                // panel spring (0.2s vs 0.32s) so the scrim feels
                // tightly coupled to the panel's snap.
                Color.black
                    .opacity(vm.isStorePanelOpen ? 0.4 : 0)
                    .ignoresSafeArea()
                    .allowsHitTesting(vm.isStorePanelOpen)
                    .onTapGesture {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
                            vm.isStorePanelOpen = false
                        }
                    }
                    .animation(.easeInOut(duration: 0.2), value: vm.isStorePanelOpen)
                    .zIndex(64)

                // ── Cosmetics store slide-down panel ──────────────────
                // Panel-only overlay. Tab + scrim are siblings mounted
                // separately so the z-order can be: scrim(64) < panel(65)
                // < tab(66). This z-stack is the entire reason the tab
                // is a separate overlay rather than living in `topBar`
                // (which sits at default zIndex(0) and would be covered
                // by the panel when open, blocking tap-to-close).
                //
                // safeTop / screenHeight come from THIS GeometryReader
                // (the outer one — has correct safe-area reporting
                // since it doesn't ignore the safe area).
                StorePanelDrawer(
                    vm: vm,
                    makeStoreVM: makeStoreViewModel,
                    safeTop: geo.safeAreaInsets.top,
                    screenHeight: geo.size.height
                )
                .zIndex(65)

                // ── Cosmetics store: peek tab (overlay) ────────────
                // Tap-to-toggle + drag-up-to-close handle. Mounted at
                // zIndex(66) above the panel so it remains tappable
                // when the panel is open — primary dismiss path.
                //
                // Positioning: outer VStack pins the HStack to the top
                // of the safe-area-respecting region (no .ignoresSafeArea
                // here, so the natural top of the VStack is at safe
                // area inset). The .padding(.top, 4) + .padding(.horizontal, 14)
                // match topBar's exact padding so the tab sits visually
                // identical to a topBar-HStack member.
                //
                // The tab is wrapped in a Color.clear frame with
                // .allowsHitTesting(false) so only the tab's visible
                // pill (its own .contentShape) intercepts touches —
                // the empty area around it lets taps pass through to
                // the scrim/panel below.
                if vm.showsStoreTab || vm.isStorePanelOpen {
                    VStack(spacing: 0) {
                        HStack {
                            Spacer()
                            StorePeekTab(
                                progress: vm.isStorePanelOpen ? 1 : 0,
                                hasUnviewedDrop: vm.hasUnviewedDrop
                            )
                            .onTapGesture {
                                withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
                                    vm.isStorePanelOpen.toggle()
                                }
                            }
                            .gesture(
                                // Drag-up to close — only fires while
                                // open, so it doesn't compete with the
                                // tap-to-open path when closed.
                                DragGesture(minimumDistance: 8)
                                    .onEnded { value in
                                        guard vm.isStorePanelOpen else { return }
                                        let panelH = geo.size.height * 0.6
                                        let dragFrac      = value.translation.height           / max(panelH, 1)
                                        let predictedFrac = value.predictedEndTranslation.height / max(panelH, 1)
                                        if dragFrac < -0.30 || predictedFrac < -0.40 {
                                            withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
                                                vm.isStorePanelOpen = false
                                            }
                                        }
                                    }
                            )
                            Spacer()
                        }
                        .padding(.top, 4)
                        .padding(.horizontal, 14)
                        Spacer()
                    }
                    .zIndex(66)
                }

                // Transient toast. Used for both errors (server rejections,
                // join failures) and successes (e.g. "Join code copied").
                // Auto-dismisses after 2.5s — the previous implementation
                // had no timer so a one-shot success message ("Join code
                // copied") would stick around for the rest of the session
                // until the next error overrode it. `.task(id: error)`
                // restarts the timer whenever the message changes so
                // back-to-back messages each get their own 2.5s window.
                // Transient chat banner — fades in at the top-right when a
                // new message arrives while the chat panel is closed. Single
                // truncated row so it never overtakes the play area. Tapping
                // the banner opens the full chat panel (faster than reaching
                // for the bubble button in the top bar). Auto-dismisses on a
                // `.task(id:)` timer keyed off the message id so each new
                // incoming message resets the visibility window.
                if let toast = vm.chatToast, !vm.showChat {
                    VStack {
                        HStack {
                            Spacer()
                            ChatToastBanner(msg: toast) {
                                withAnimation { vm.showChat = true }
                            }
                            .padding(.trailing, 14)
                            .padding(.top, 56) // clear the top-bar
                        }
                        Spacer()
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(58)
                    .task(id: toast.id) {
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        if vm.chatToast?.id == toast.id {
                            withAnimation(.easeOut(duration: 0.35)) {
                                vm.chatToast = nil
                            }
                        }
                    }
                }

                if let error = vm.errorMessage {
                    // Retro error toast — maroon pill with ink border and
                    // paper text. Reads as a printed "ERROR" stamp.
                    VStack {
                        Spacer()
                        Text(error)
                            .font(.custom("AmericanTypewriter-Bold", size: 13))
                            .foregroundStyle(SPRetro.paper)
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .background(SPRetro.maroon)
                            .clipShape(Capsule())
                            .overlay(Capsule().strokeBorder(SPRetro.ink, lineWidth: 1.5))
                            .shadow(color: SPRetro.ink.opacity(0.65), radius: 0, x: 1.5, y: 2.5)
                            .padding(.bottom, landscape ? 60 : 90)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(60)
                    .task(id: error) {
                        try? await Task.sleep(nanoseconds: 2_500_000_000)
                        // Guard against a newer message — only clear if the
                        // currently-visible toast is still the one we
                        // scheduled the dismiss for.
                        if vm.errorMessage == error {
                            vm.errorMessage = nil
                        }
                    }
                }
            }
            .animation(.spring(response: 0.35), value: vm.showChat)
            .animation(.spring(response: 0.4, dampingFraction: 0.75), value: vm.showWinners)
            .animation(.easeInOut(duration: 0.2), value: vm.errorMessage != nil)
            .animation(.easeInOut(duration: 0.3), value: landscape)
        }
        // NOTE: do NOT apply .ignoresSafeArea() here — it was pushing the
        // top bar (and its back button) up underneath the Dynamic Island.
        // The background Color already extends edge-to-edge on its own.
        .navigationBarHidden(true)
        .onAppear  { vm.onAppear() }
        .onDisappear { vm.onDisappear() }
        .alert("Removed from table", isPresented: $vm.wasKicked) {
            Button("Leave", role: .destructive) { dismiss() }
        } message: {
            Text("You were removed from this table by the host.")
        }
        .confirmationDialog("Close Table", isPresented: $vm.showCloseConfirm, titleVisibility: .visible) {
            Button("Close Table", role: .destructive) { vm.closeTable() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will end the table for everyone. You cannot undo this.")
        }
        .onChange(of: vm.shouldExit) { _, exit in
            if exit { dismiss() }
        }
        // NOTE: cosmetics-store open/close + "viewed" side-effect are
        // owned by StorePanelDrawer (mounted in the overlay ZStack above).
        // It mirrors local open state back to vm.isStorePanelOpen via
        // .onChange so the rest of the app can still observe the flag.
    }

    // ─── Portrait layout ──────────────────────────────────────────────────────
    // Stacked vertically: top bar → table → action bar

    private func portraitLayout(geo: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            topBar
            ZStack(alignment: .bottom) {
                tableArea(isLandscape: false)
                localPlayerOverlay
                    .padding(.bottom, 4)
                    // When it's my turn, drop the hole-card layer behind the
                    // table so the seat avatar + timer ring draw on top.
                    .zIndex(vm.isMyTurn ? -1 : 1)
            }
            ActionBar(vm: vm)
        }
    }

    // ─── Landscape layout ─────────────────────────────────────────────────────
    // Table fills the full screen. Top bar and action bar overlay with
    // translucent backgrounds so the felt is visible behind them.

    private func landscapeLayout(geo: GeometryProxy) -> some View {
        ZStack(alignment: .bottom) {
            // Table fills entire area
            tableArea(isLandscape: true)
                .ignoresSafeArea()

            // Local player hole cards — floating above the action bar
            VStack(spacing: 0) {
                Spacer()
                localPlayerOverlay
                    .padding(.bottom, 80)
            }

            // Action bar pinned to bottom — compact with gradient backdrop
            VStack(spacing: 0) {
                Spacer()
                ActionBar(vm: vm)
                    .background(
                        LinearGradient(
                            colors: [Color.black.opacity(0), Color.black.opacity(0.80)],
                            startPoint: .top, endPoint: .bottom
                        )
                        .ignoresSafeArea()
                    )
            }

            // Top bar pinned to top
            VStack(spacing: 0) {
                topBar
                    .background(Color.black.opacity(0.55).ignoresSafeArea(edges: .top))
                Spacer()
            }
        }
    }

    // ─── Top bar ──────────────────────────────────────────────────────────────
    // Three circular dark-gray buttons: back chevron (left), "+" (center,
    // no-op placeholder), chat bubble (right). No street/hand-info strip —
    // that information is shown inside the felt via the Blinds label.

    private var topBar: some View {
        HStack(spacing: 12) {
            // Retro hamburger — paper disc with ink border + hard offset
            // shadow, same language as the home-screen header buttons.
            Button {
                vm.loadTableDetailIfNeeded()
                withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                    vm.showSideMenu = true
                }
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(SPRetro.ink)
                    .frame(width: 40, height: 40)
                    .background(SPRetro.paper)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(SPRetro.ink, lineWidth: 1.5))
                    .shadow(color: SPRetro.ink.opacity(0.7), radius: 0, x: 1.5, y: 2)
            }

            Spacer()

            // Center slot intentionally empty. The cosmetics-store
            // peek tab lives in the outer ZStack as a zIndex(66)
            // overlay (see `storeTabOverlay` mounted near the end of
            // body) so it sits ABOVE the panel and remains tappable
            // when the panel is open — that's the primary
            // tap-to-dismiss path. The Spacer-Spacer pair here
            // matches the overlay's own HStack centering so the
            // visual position is identical to the pre-overlay layout.

            Spacer()

            // Retro chat toggle — paper disc + ink border. Active state
            // tints the bubble glyph maroon so it reads as "channel open"
            // without flipping the whole panel color.
            Button { withAnimation { vm.showChat.toggle() } } label: {
                Image(systemName: "bubble.right.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(vm.showChat ? SPRetro.maroon : SPRetro.ink)
                    .frame(width: 40, height: 40)
                    .background(SPRetro.paper)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(SPRetro.ink, lineWidth: 1.5))
                    .shadow(color: SPRetro.ink.opacity(0.7), radius: 0, x: 1.5, y: 2)
                    .overlay(alignment: .topTrailing) {
                        if vm.unreadChatCount > 0 {
                            // Pop-red unread dot with ink border — matches
                            // the alert-badge language in the tab bar.
                            Circle()
                                .fill(SPRetro.popRed)
                                .frame(width: 9, height: 9)
                                .overlay(
                                    Circle()
                                        .strokeBorder(SPRetro.ink, lineWidth: 1)
                                )
                                .offset(x: 2, y: -2)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .animation(.spring(response: 0.3), value: vm.unreadChatCount)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 4)
        .padding(.bottom, 6)
    }

    // ─── Local player overlay ─────────────────────────────────────────────────
    // Face-up hole cards + (optionally) a countdown when it's my turn.
    // Pinned just above the action bar so the user can always see their hand.

    @ViewBuilder
    private var localPlayerOverlay: some View {
        // PLO (4 hole cards) — sort high→low so the user can read their
        // hand at a glance. Deal order is meaningless in PLO (any 2 of 4
        // hole cards play), so ordering by rank makes pairs and connected
        // ranges immediately visible. NLH (2 cards) is left in deal order —
        // muscle memory expects the first dealt card on the left, and
        // reordering at the 2-card level produces no readability win.
        // Scope: this sort applies ONLY to the local player's render path
        // here. Opponents go through HoleCardsView / OpponentHoleCardsView
        // and must NOT be reordered (server preserves deal order across
        // clients; reordering opponent reveals would make them disagree
        // with the local player's memory of the dealing animation).
        let rawCards = vm.myCards
        let cards: [PokerCard] = rawCards.count == 4
            ? rawCards.sorted { rankSortValue($0.rank) > rankSortValue($1.rank) }
            : rawCards
        // Mounted whenever the local player has cards in this hand. We used
        // to gate on `status != .folded`, but with tap-to-show the player
        // needs to keep seeing their own cards after folding so they can
        // optionally expose them to the table. The `mucked` field on the
        // server preserves the values; `myCards` resolves through it for
        // the seat owner. Sitting-out and waiting phases still hide.
        let showing = !cards.isEmpty &&
                      vm.gameState?.phase != .waiting &&
                      vm.mySeat?.status != .sittingOut
        let isFolded = vm.mySeat?.status == .folded
        // Once the player can voluntarily show — i.e. they've folded, or
        // the hand has produced winners — make each card tappable. Before
        // that, taps would do nothing on the server (handNumber gate plus
        // the index isn't actually exposed yet anyway), so we only enable
        // the tap target when it has a real effect, to keep accidental
        // taps mid-hand from broadcasting cards.
        // Tap-to-show is the *opt-in* path for revealing your hole cards.
        // Suppress it entirely on the checked-down auto-reveal path: when
        // the hand had no bets and reaches showdown, GameViewModel fires
        // showCard for every still-hidden index automatically, so an
        // explicit "TAP A CARD TO SHOW" prompt would be misleading. We
        // keep the path open for folded hero (they can still flex) — the
        // VM's auto-reveal also skips folded seats so there's no race.
        // Was: `vm.noBetsThisHand && vm.anyWinnersDeclared && !isFolded`,
        // which false-positived on uncontested preflop fold-wins (no bets +
        // winners + not folded), suppressing the tap path even though the
        // server-side auto-reveal doesn't fire for fold-wins. The VM-side
        // mirror correctly factors in `winners.contains { $0.showCards }`,
        // which the server only sets for contested showdowns.
        let autoRevealing = vm.isAutoRevealingMyCards
        let canShow = (isFolded || vm.anyWinnersDeclared) && !autoRevealing
        let shownIdx = Set((vm.mySeat?.revealed ?? []).map(\.index))
        if showing {
            VStack(spacing: 4) {
                // Fanned hole cards. When it's my turn the cards tighten into
                // a slightly overlapping fan (left card behind right) so the
                // pair reads as one compact hand pushed off to the side of the
                // avatar + timer ring. Otherwise they sit side-by-side.
                //
                // PERF NOTE: spacing is held constant at 6 — the on-turn
                // overlap is achieved with `.offset` per card below. Animating
                // an HStack's `spacing` is a layout-driven animation that re-
                // runs the layout pass every frame of the spring (~30 frames),
                // which caused a visible stutter when checking. `.offset`
                // animates as a GPU transform instead — no layout work.
                HStack(spacing: 6) {
                    ForEach(Array(cards.enumerated()), id: \.element.id) { idx, card in
                        // Gate the gold highlight on `vm.isMeWinner`. card.id is
                        // unique (rank+suit), so a loser's hole card can't match
                        // a winner's bestCards entry today — but at a PLO river
                        // all-in showdown a user reported losing cards looking
                        // highlighted. The math forbids it, but anchoring on the
                        // seat-winner flag closes the door on any stale-state or
                        // future regression path. Same defence in OpponentHole-
                        // CardsView.cardSlot.
                        let isWinningCard = vm.isMeWinner
                            && vm.winningCardIds.contains(card.id)
                        let isShown = shownIdx.contains(idx)
                        // Voluntarily-shown cards override the loser-dim treatment —
                        // when the player taps to expose a card after winning an
                        // uncontested pot, `bestCards` is empty so both cards would
                        // otherwise stay dimmed at 0.55 opacity, making the reveal
                        // invisible to the user (the white border + scale pop got
                        // lost behind the dim). Treating shown cards as un-dim
                        // makes the act of showing unmistakable in any state.
                        let dim = vm.anyWinnersDeclared && !isWinningCard && !isShown
                        // 4-color front (red / blue / green / black) so the
                        // hero's hand reads with the same suit-tinted plates
                        // as the community board.
                        // Retro overlays — winning cards get a mustard ink
                        // border; voluntarily-shown cards get an ink border
                        // so the act of showing reads as a stamped highlight
                        // rather than a glow.
                        PlayingCardView(card: card, size: .large,
                                        coloredBackground: true)
                            .overlay(
                                RoundedRectangle(cornerRadius: PlayingCardView.CardSize.large.cornerRadius)
                                    .strokeBorder(
                                        isWinningCard ? SPRetro.mustard
                                            : (isShown ? SPRetro.ink : Color.clear),
                                        lineWidth: isShown ? 2.0 : 2.5
                                    )
                            )
                            .saturation(dim ? 0.5 : 1.0)
                            .opacity(dim ? 0.55 : (isFolded && !isShown ? 0.7 : 1.0))
                            .shadow(
                                color: isWinningCard ? SPRetro.ink.opacity(0.65)
                                     : (isShown ? SPRetro.ink.opacity(0.5) : .clear),
                                radius: 0,
                                x: isShown || isWinningCard ? 1.5 : 0,
                                y: isShown || isWinningCard ? 2 : 0
                            )
                            // Soft scale pulse on reveal so the act of showing
                            // is unmistakable. Re-keys on `isShown` so it
                            // animates only when the server confirms the new
                            // revealedCards entry.
                            .scaleEffect(isShown ? 1.06 : 1.0)
                            .animation(.spring(response: 0.32, dampingFraction: 0.6),
                                       value: isShown)
                            // Per-card rotation + inward-offset for the fan.
                            // NLH (2 cards) keeps its exact original behaviour
                            // — the count == 2 branch reproduces the prior
                            // hardcoded values byte-for-byte. The count == 4
                            // branch is a PLO-only addition: with twice the
                            // cards we want a wider symmetric fan and a
                            // proportionally larger inward converge on-turn so
                            // the 4-card cluster reads as a tight hand rather
                            // than smushing the inner pair under the outer
                            // pair. Any other count (defensive — shouldn't
                            // happen in practice) falls back to no rotation /
                            // offset so we never mis-render unknown hand sizes.
                            .rotationEffect(.degrees(plowFanDegrees(idx: idx,
                                                                   count: cards.count,
                                                                   onTurn: vm.isMyTurn)))
                            .offset(x: plowFanOffset(idx: idx,
                                                     count: cards.count,
                                                     onTurn: vm.isMyTurn))
                            .zIndex(Double(idx))   // right card (idx=1) on top
                            // Tap-to-show. Disabled until canShow so we don't
                            // emit show_cards mid-hand (server would no-op,
                            // but we save the round-trip). Already-shown
                            // cards stop accepting taps too.
                            .contentShape(Rectangle())
                            .onTapGesture {
                                guard canShow, !isShown else { return }
                                vm.showCard(at: idx)
                            }
                    }
                }
                .shadow(color: .black.opacity(0.6), radius: 8, y: 4)

                // Subtle hand-strength label — hidden once folded; replaced
                // by the tap-to-show prompt the moment the player can act
                // on it. Winners-declared also swaps to the prompt so the
                // pre-fold winner can optionally expose their cards in a
                // fold-win.
                // Retro labels — ink/maroon AmericanTypewriter on the paper
                // felt below. No more washed-out white-on-dark.
                if canShow && shownIdx.count < cards.count {
                    Text("TAP A CARD TO SHOW")
                        .font(.custom("AmericanTypewriter-Bold", size: 10))
                        .tracking(1.8)
                        .foregroundStyle(SPRetro.maroon)
                        .padding(.top, 2)
                } else if let label = HandStrength.label(
                    hole: cards,
                    board: vm.gameState?.communityCards ?? []
                ) {
                    Text(label)
                        .font(.custom("ChalkboardSE-Bold", size: 12))
                        .foregroundStyle(SPRetro.ink)
                        .padding(.top, 2)
                }
            }
            // Two display modes:
            //   • In-hand (not my turn): cards sit centered above the action
            //     bar at a slightly reduced scale so they don't dominate the
            //     screen — the table stays the focus.
            //   • On-turn / "off-hand" (my turn): cards shrink and tuck off
            //     to the side so the avatar + timer ring read cleanly. We
            //     keep them readable by sizing up a touch from the original
            //     0.65, and pull them leftward of where they used to sit
            //     so they don't overlap the +15s extension button on the
            //     action bar (the old x:120 dropped them right on top of it).
            // Off-turn scale dropped 0.90 → 0.78 so the resting hand is
            // visibly smaller. Combined with the larger y offset below this
            // pulls the cards' top edge well clear of the local seat's
            // StackPill (chip badge) — previously the cards ate the chip
            // amount the moment the user checked/raised/folded.
            .scaleEffect(vm.isMyTurn ? 0.85 : 0.78, anchor: .bottom)
            // Off-turn `y: 60` (was 22, originally 0) pushes the resting
            // cluster below the StackPill on every device size. 22pt was
            // not enough — the avatar+name+stack tower extends ~50pt above
            // the cards' bottom anchor, so we need at least that much
            // clearance plus a small visual gap. The on-turn offset
            // (x:70, y:32) is unchanged — that already tucks the cards
            // beside the avatar.
            .offset(x: vm.isMyTurn ? 70  : 0,
                    y: vm.isMyTurn ? 32  : 60)
            .transition(.asymmetric(
                insertion: .move(edge: .bottom).combined(with: .opacity),
                // Fold: slide toward the muck (off to the right) while rotating
                // and fading, as if the player tossed their cards away.
                removal: .modifier(
                    active:     FoldTossModifier(progress: 1),
                    identity:   FoldTossModifier(progress: 0)
                ).combined(with: .opacity)
            ))
            // PERF: collapsed three stacked .animation() modifiers into one.
            //   • The previous `value: cards.map(\.id)` allocated a fresh
            //     [String] on every body invalidation just to compare arrays
            //     for change detection. cards.count flips at the only moments
            //     we actually want to retrigger (deal: 0→2, reset/fold: 2→0).
            //   • Three stacked .animation() modifiers each opened their own
            //     animation transaction when state changed, and broadcasts
            //     after a button press fire multiple body re-evals in quick
            //     succession — each transaction fought the next, which read
            //     as the spring "stuttering" back to the off-turn position.
            //   • Single signature → SwiftUI runs one transaction. The
            //     mySeat?.status change still triggers it because folded
            //     cards transition out via the .transition() above.
            .animation(
                // Slowed from response 0.42 → 0.55 with damping 0.80 → 0.78 so
                // the cards have a softer, slightly weighted return to the
                // off-turn position instead of snapping. Lower damping lets
                // the hand do a tiny settle at the end which reads as the
                // pair "coming to rest." Safe to slow now that the parent
                // layout no longer reflows during the spring (ActionBar's
                // minHeight prevents it).
                .spring(response: 0.55, dampingFraction: 0.78),
                value: HoleCardLayoutKey(
                    isMyTurn: vm.isMyTurn,
                    status:   vm.mySeat?.status,
                    cardCount: cards.count
                )
            )
        }
    }

    // ─── Table area ───────────────────────────────────────────────────────────

    private func tableArea(isLandscape: Bool) -> some View {
        GeometryReader { geo in
            ZStack {
                // Main table
                PokerTableView(
                    seats:       sortedSeats,
                    maxSeats:    maxSeats,
                    vm:          vm,
                    isLandscape: isLandscape
                )

                // "Waiting for next hand" pill — shown when a hand is in
                // progress but I'm not part of it (e.g. I just sat down
                // mid-hand, or I'm sitting out). Without this the user sees
                // an empty action bar with no cards and is confused; the
                // real reason is they're benched until the next hand starts.
                if let state = vm.gameState,
                   state.phase != .waiting,
                   let seat = vm.mySeat,
                   (seat.holeCards?.isEmpty ?? true),
                   seat.status != .folded {
                    // Retro mid-hand wait pill — paper face + ink text + ink
                    // border + hard offset shadow.
                    VStack {
                        Spacer()
                        HStack(spacing: 8) {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(SPRetro.ink)
                                .scaleEffect(0.7)
                            Text("Waiting for next hand…")
                                .font(.custom("AmericanTypewriter-Bold", size: 13))
                                .foregroundStyle(SPRetro.ink)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(SPRetro.paper)
                        .clipShape(Capsule())
                        .overlay(Capsule().strokeBorder(SPRetro.ink, lineWidth: 1.5))
                        .shadow(color: SPRetro.ink.opacity(0.6), radius: 0, x: 1.5, y: 2)
                        .padding(.bottom, 110)
                    }
                    .transition(.opacity)
                    .allowsHitTesting(false)
                    .zIndex(35)
                }

                // Waiting overlay — dim the table behind a translucent ink
                // pane so the paper waiting card sits on a darkened page
                // (not full black-out, which would lose the page texture).
                if vm.gameState?.phase == .waiting || vm.gameState == nil {
                    SPRetro.ink.opacity(0.55).ignoresSafeArea()
                    VStack(spacing: 20) {
                        if vm.gameState == nil {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(SPRetro.mustard)
                                .scaleEffect(1.5)
                            Text("Connecting...")
                                .font(.custom("AmericanTypewriter-Bold", size: 16))
                                .foregroundStyle(SPRetro.paper)
                        } else {
                            let seated = vm.gameState!.seats.filter { $0.status != .sittingOut }.count
                            WaitingForPlayersView(seated: seated, required: 2)

                            // Invite Friends — surfaces the same online-only
                            // invite sheet the seat-tap flow uses, but pinned
                            // under the waiting indicator so a user sitting
                            // alone has an obvious next step. Shown whenever
                            // we have a lastTable to invite to (i.e. user
                            // came from the lobby's create/join flow); falls
                            // back silently if `canSendInvites` is false so
                            // we never present a useless empty sheet.
                            if lobbyVM.canSendInvites {
                                // Retro Invite Friends — mustard pill with
                                // ink text/border + hard offset shadow.
                                Button {
                                    lobbyVM.resetInviteSheet()
                                    showWaitingInviteSheet = true
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "person.2.fill")
                                            .font(.system(size: 14))
                                        Text("Invite Friends")
                                            .font(.custom("AmericanTypewriter-Bold", size: 14))
                                    }
                                    .foregroundStyle(SPRetro.ink)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 10)
                                    .background(SPRetro.mustard)
                                    .clipShape(Capsule())
                                    .overlay(Capsule().strokeBorder(SPRetro.ink, lineWidth: 1.5))
                                    .shadow(color: SPRetro.ink.opacity(0.7), radius: 0, x: 2, y: 2.5)
                                }
                                .buttonStyle(ScaleButtonStyle())
                            }

                            // Add bot button — lets you play solo against an AI opponent.
                            // Only shown when the creator opted into bots at table
                            // creation (or for tables where we have no preference,
                            // i.e. ones we joined rather than created).
                            let hasBot = vm.gameState!.seats.contains { $0.username == "StackBot" }
                            let botsAllowed = TablePreferences.botsAllowed(forTableId: vm.tableId)
                            if !hasBot && botsAllowed {
                                // Retro Add-Bot — paper pill with ink text
                                // so it sits subordinate to the mustard
                                // Invite CTA above (secondary action).
                                Button {
                                    vm.addBot()
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "cpu.fill")
                                            .font(.system(size: 14))
                                        Text("Add Bot Player")
                                            .font(.custom("AmericanTypewriter-Bold", size: 14))
                                    }
                                    .foregroundStyle(SPRetro.ink)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 10)
                                    .background(SPRetro.paper)
                                    .clipShape(Capsule())
                                    .overlay(Capsule().strokeBorder(SPRetro.ink, lineWidth: 1.5))
                                    .shadow(color: SPRetro.ink.opacity(0.6), radius: 0, x: 1.5, y: 2)
                                }
                                .buttonStyle(ScaleButtonStyle())
                            }
                        }
                    }
                }

                // Local player hole cards are rendered in `localPlayerOverlay`
                // (anchored to the bottom of the table area, above the action bar).
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Waiting-overlay invite sheet. Used to be `onlineOnly: true` ("no
        // point pinging an offline friend to fill a seat that's open *right
        // now*") but the user reported that recently-added friends weren't
        // appearing in the invite list while they were still offline —
        // a freshly-accepted friend who isn't connected hides entirely,
        // which reads as a bug. We now show every friend; push wakes the
        // offline ones, and the row still works regardless of presence.
        .sheet(isPresented: $showWaitingInviteSheet) {
            InviteFriendsSheet(vm: lobbyVM, fvm: friendsVM)
        }
    }

    // ─── Seat ordering ────────────────────────────────────────────────────────
    // Local player is rotated to index 0 so table geometry places them at bottom.

    // ─── Hero fan geometry (PLO-aware) ───────────────────────────────────────
    // Per-card rotation (degrees) for the hero's fanned hole-card row.
    //
    // NLH (count == 2): preserves the exact prior hardcoded values — on-turn
    //   [-10°, 6°], off-turn [-4°, 4°] — so this branch is byte-identical to
    //   what shipped before and there's no possible visual regression on the
    //   90% path.
    //
    // PLO (count == 4): symmetric 4-card fan. On-turn the spread is wider
    //   ([-12°, -4°, 4°, 12°]) to match the tighter on-turn overlap; off-turn
    //   it flattens to [-6°, -2°, 2°, 6°] so the cards don't dramatically tilt
    //   at rest. Indices outside [0, count-1] (defensive) get 0°.
    private func plowFanDegrees(idx: Int, count: Int, onTurn: Bool) -> Double {
        switch count {
        case 2:
            // Off-turn was [-4°, +4°] — combined with the 6pt HStack gap and
            // no inward offset, the two cards read as a wide pair instead of
            // a tight resting hand. Tightening to [-2°, +2°] plus the new
            // off-turn inward offset in plowFanOffset (~5pt each) brings the
            // cards close to touching at the inner edge while still keeping a
            // visible fan — fixed 2026-05-13.
            return onTurn ? (idx == 0 ? -10 : 6) : (idx == 0 ? -2 : 2)
        case 4:
            let onTurnDegs:  [Double] = [-12, -4, 4, 12]
            let offTurnDegs: [Double] = [ -6, -2, 2,  6]
            let table = onTurn ? onTurnDegs : offTurnDegs
            return (0..<table.count).contains(idx) ? table[idx] : 0
        default:
            return 0
        }
    }

    // Per-card horizontal inward offset (pt). On-turn produces the tight-
    // fan-converge look; off-turn applies a smaller inward nudge so the
    // resting hand reads as a tight pair instead of two separate cards
    // sitting 6pt apart. Done via `.offset` rather than HStack spacing so
    // SwiftUI doesn't re-run layout every frame (animating HStack spacing
    // re-runs layout for the spring's full ~30 frames — the prior reason
    // off-turn inward offset was 0).
    //
    // NLH (count == 2):
    //   - on-turn  → [14, -14]  (preserved — ~28pt converge for the fan)
    //   - off-turn → [5, -5]    (new — ~10pt converge, snug resting pair)
    //
    // PLO (count == 4): outer pair converges further inward, inner pair only
    //   slightly so the cluster reads as a single tight 4-card hand rather
    //   than two separate pairs. Off-turn is half the on-turn converge so
    //   the resting 4-card hand is tighter than before without flattening
    //   into an unreadable stack. Indices outside [0, count-1] get 0.
    private func plowFanOffset(idx: Int, count: Int, onTurn: Bool) -> CGFloat {
        switch count {
        case 2:
            if onTurn { return idx == 0 ? 14 : -14 }
            return idx == 0 ? 5 : -5
        case 4:
            // Outer cards pulled in by 22pt; inner cards by 7pt. Net
            // converge between outer pair ≈ 44pt, plenty of overlap given
            // HStack spacing 6 and large card width.
            let onTurnTable:  [CGFloat] = [22, 7, -7, -22]
            let offTurnTable: [CGFloat] = [11, 3, -3, -11]
            let table = onTurn ? onTurnTable : offTurnTable
            return (0..<table.count).contains(idx) ? table[idx] : 0
        default:
            return 0
        }
    }

    private var sortedSeats: [GameSeat] {
        guard let state = vm.gameState else { return [] }
        // Use the userId snapshot the VM cached at init() rather than calling
        // KeychainManager.shared.userId here. The previous version did a
        // synchronous Keychain syscall (SecItemCopyMatching) every time this
        // computed property ran — and SwiftUI calls computed properties
        // every body evaluation, so each VM @Published broadcast triggered a
        // round-trip through the keychain just to filter a small array.
        // The user ID is immutable for the session, so reading it once and
        // re-using the cached value is both correct and free.
        let myId = vm.localUserId
        let seats = state.seats.sorted { $0.seatIndex < $1.seatIndex }
        guard let myIdx = seats.firstIndex(where: { $0.userId == myId }) else { return seats }
        return Array(seats[myIdx...]) + Array(seats[..<myIdx])
    }

    // Rank → ordinal value for sorting the local PLO hand high→low.
    // Kept local to GameView (rather than touching HandStrength.rankValue,
    // which is private and used only inside the label evaluator) so the
    // sort key lives next to the only caller that needs it.
    private func rankSortValue(_ r: String) -> Int {
        switch r {
        case "A": return 14
        case "K": return 13
        case "Q": return 12
        case "J": return 11
        case "T": return 10
        default:  return Int(r) ?? 0
        }
    }

    // ─── Cosmetics store view-model factory ───────────────────────────────────
    //
    // Same factory pattern used by ChipsView and ProfileView for their
    // store entry points. Builds the balance publisher from the auth
    // VM's currentUser stream so the in-store balance pill stays in
    // sync with daily-bonus claims, transfers, and (recursive case)
    // purchases made while the panel is open at the table.
    //
    // entryPoint is fixed to `.tableStoreTab` — the panel here is only
    // reachable from the in-game peek-tab.

    private func makeStoreViewModel() -> StoreViewModel {
        let balancePublisher = authViewModel.$currentUser
            .map { profile -> ChipAmount in
                ChipAmount(serverString: profile?.chipBalance ?? "0") ?? .zero
            }
            .eraseToAnyPublisher()
        return StoreViewModel(
            container:        cosmetics,
            balancePublisher: balancePublisher,
            entryPoint:       .tableStoreTab
        )
    }
}

// ─── Chat Overlay ─────────────────────────────────────────────────────────────

struct ChatOverlay: View {
    @ObservedObject var vm: GameViewModel
    @FocusState private var inputFocused: Bool

    var body: some View {
        // Retro chat panel — paper substrate with ink headers, ink text, and
        // a hard ink offset shadow. Replaces the dark-glass/ultraThinMaterial
        // panel so it reads as a printed transcript pasted to the page.
        VStack(spacing: 0) {
            HStack {
                Text("TABLE CHAT")
                    .font(.custom("AmericanTypewriter-Bold", size: 14))
                    .tracking(1.5)
                    .foregroundStyle(SPRetro.ink)
                Spacer()
                Button { withAnimation { vm.showChat = false } } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(SPRetro.ink.opacity(0.7))
                        .font(.system(size: 18))
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(SPRetro.paperShade)

            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(vm.chatMessages) { msg in
                            ChatBubble(msg: msg, isMe: msg.userId == vm.localUserId)
                                .id(msg.id)
                        }
                    }
                    .padding(10)
                }
                .onChange(of: vm.chatMessages.count) { _, _ in
                    if let last = vm.chatMessages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
            .frame(maxHeight: 220)
            .background(SPRetro.paper)

            HStack(spacing: 8) {
                TextField("Message...", text: $vm.chatInput)
                    .font(.custom("AmericanTypewriter", size: 13))
                    .foregroundStyle(SPRetro.ink)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(SPRetro.paper)
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(SPRetro.ink, lineWidth: 1))
                    .focused($inputFocused)
                    .onSubmit { vm.sendChat() }

                Button(action: vm.sendChat) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(vm.chatInput.isEmpty ? SPRetro.ink.opacity(0.3) : SPRetro.maroon)
                }
                .disabled(vm.chatInput.isEmpty)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(SPRetro.paperShade)
        }
        .background(SPRetro.paper)
        .clipShape(RoundedRectangle(cornerRadius: SPRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: SPRadius.lg)
                .strokeBorder(SPRetro.ink, lineWidth: 2)
        )
        .shadow(color: SPRetro.ink.opacity(0.7), radius: 0, x: 2.5, y: 4)
        .padding(.trailing, 10)
        .frame(maxWidth: 290)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .padding(.top, 68)
    }
}

// ─── Winner Celebration Overlay ───────────────────────────────────────────────

struct WinnerCelebrationOverlay: View {
    let winners: [WinnerPayout]

    @State private var appear = false
    @State private var confettiTrigger = false

    var body: some View {
        // Retro winner celebration — mustard panel with ink crown and ink
        // text on a darkened page. The crown sits at the top with no glow;
        // depth comes from the hard ink offset shadow under the panel.
        ZStack {
            SPRetro.ink.opacity(0.5).ignoresSafeArea()

            ConfettiView(trigger: confettiTrigger)
                .allowsHitTesting(false)

            VStack(spacing: 14) {
                ForEach(Array(winners.enumerated()), id: \.element.playerId) { _, w in
                    VStack(spacing: 10) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(SPRetro.ink)
                            .scaleEffect(appear ? 1 : 0.2)
                            .animation(.spring(response: 0.55, dampingFraction: 0.6), value: appear)

                        Text(w.username)
                            .font(.custom("ChalkboardSE-Bold", size: 20))
                            .foregroundStyle(SPRetro.ink)

                        Text(w.handName)
                            .font(.custom("AmericanTypewriter-Bold", size: 13))
                            .foregroundStyle(SPRetro.inkSoft)

                        if w.showCards && !w.bestCards.isEmpty {
                            HStack(spacing: 4) {
                                ForEach(w.bestCards.prefix(5)) { card in
                                    PlayingCardView(card: card, size: .medium)
                                }
                            }
                            .padding(.vertical, 4)
                        }

                        Text("+\(formatChips(String(w.amount)))")
                            .font(.custom("ChalkboardSE-Bold", size: 30))
                            .foregroundStyle(SPRetro.maroon)
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 20)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(SPRetro.mustard)
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .strokeBorder(SPRetro.ink, lineWidth: 2.5)
                            )
                            .shadow(color: SPRetro.ink.opacity(0.75), radius: 0, x: 3, y: 5)
                    )
                }
            }
            .scaleEffect(appear ? 1 : 0.7)
            .opacity(appear ? 1 : 0)
            .animation(.spring(response: 0.5, dampingFraction: 0.75), value: appear)
        }
        .onAppear {
            appear = true
            confettiTrigger.toggle()
        }
    }
}

// ─── Simple Confetti ──────────────────────────────────────────────────────────

struct ConfettiView: View {
    let trigger: Bool

    private let particles: [ConfettiParticle] = (0..<24).map { _ in ConfettiParticle.random() }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(particles) { p in
                    ConfettiParticleView(particle: p, center: CGPoint(x: geo.size.width / 2, y: geo.size.height / 2))
                }
            }
        }
    }
}

struct ConfettiParticle: Identifiable {
    let id = UUID()
    let color: Color
    let size: CGFloat
    let angle: Double
    let distance: CGFloat
    let duration: Double

    static func random() -> ConfettiParticle {
        // Retro confetti — mustard / paper / pop-red / pop-blue. Replaces
        // the all-gold/white palette so the confetti reads as the same
        // pop-color family as the rest of the comic system.
        let palette: [Color] = [
            SPRetro.mustard,
            SPRetro.paper,
            SPRetro.popRed,
            SPRetro.popBlue
        ]
        return ConfettiParticle(
            color: palette.randomElement()!,
            size: CGFloat.random(in: 8...12),
            angle: Double.random(in: 0...(2 * .pi)),
            distance: CGFloat.random(in: 140...280),
            duration: Double.random(in: 1.1...1.6)
        )
    }
}

struct ConfettiParticleView: View {
    let particle: ConfettiParticle
    let center: CGPoint

    @State private var moved = false

    var body: some View {
        Circle()
            .fill(particle.color)
            .frame(width: particle.size, height: particle.size)
            .position(center)
            .offset(
                x: moved ? particle.distance * cos(particle.angle) : 0,
                y: moved ? particle.distance * sin(particle.angle) + (moved ? 80 : 0) : 0
            )
            .opacity(moved ? 0 : 1)
            .onAppear {
                withAnimation(.easeOut(duration: particle.duration)) {
                    moved = true
                }
            }
    }
}

// ─── Chat Toast Banner ───────────────────────────────────────────────────────
// Single-row pill that fades in at the top-right when a chat message arrives
// while the panel is closed. Sender name in accent color, message truncated
// to one line with "..." so it can never grow taller than the chat-toggle
// button next to it. The whole pill is a button — tapping it opens the
// full chat panel for context.

private struct ChatToastBanner: View {
    let msg: ChatMessage
    let onTap: () -> Void

    var body: some View {
        // Retro chat-toast banner — paper pill, pop-blue bubble icon,
        // maroon sender name, ink message body.
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: "bubble.right.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(SPRetro.popBlue)
                Text(msg.username)
                    .font(.custom("AmericanTypewriter-Bold", size: 11))
                    .foregroundStyle(SPRetro.maroon)
                Text(msg.message)
                    .font(.custom("AmericanTypewriter", size: 11))
                    .foregroundStyle(SPRetro.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: 220, alignment: .leading)
            // Shape-only offset plate (not `.shadow()`) so the truncated
            // chat message text doesn't get rasterized into a doubled
            // glyph along with the rest of the pill. Same fix pattern as
            // the winning-hand banner, name plate, and stack pill.
            .background(
                ZStack {
                    Capsule()
                        .fill(SPRetro.ink.opacity(0.65))
                        .offset(x: 1.5, y: 2)
                    Capsule()
                        .fill(SPRetro.paper)
                        .overlay(
                            Capsule()
                                .strokeBorder(SPRetro.ink, lineWidth: 1.5)
                        )
                }
            )
        }
        .buttonStyle(.plain)
    }
}

struct ChatBubble: View {
    let msg:  ChatMessage
    let isMe: Bool

    var body: some View {
        // Retro chat bubble — mustard for self, paper for others, both with
        // ink borders and ink text. Reads as cut-out printed transcript
        // lines on the paper substrate.
        HStack(alignment: .bottom, spacing: 5) {
            if !isMe {
                Text(msg.username)
                    .font(.custom("AmericanTypewriter-Bold", size: 9))
                    .foregroundStyle(SPRetro.maroon)
                    .frame(width: 44, alignment: .trailing)
            }
            Text(msg.message)
                .font(.custom("AmericanTypewriter", size: 12))
                .foregroundStyle(SPRetro.ink)
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(isMe ? SPRetro.mustard : SPRetro.paper)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(SPRetro.ink, lineWidth: 1)
                )
        }
        .frame(maxWidth: .infinity, alignment: isMe ? .trailing : .leading)
    }
}

// ─── Fold Toss Modifier ───────────────────────────────────────────────────────
// Drives the removal transition on the local player's hole cards when they
// fold — slides the cards toward the right edge while rotating, as if tossing
// them into the muck.

private struct FoldTossModifier: ViewModifier {
    var progress: CGFloat   // 0 = identity, 1 = tossed

    func body(content: Content) -> some View {
        content
            .offset(x: 260 * progress, y: -40 * progress)
            .rotationEffect(.degrees(Double(progress) * 35))
            .scaleEffect(1 - 0.15 * progress)
    }
}

// ─── Table Side Menu ──────────────────────────────────────────────────────────
// Sliding drawer from the leading edge with in-game options. Replaces the
// old "tap top-left to leave" behavior — leaving is now one option among
// several. Width is bounded so the felt remains partially visible behind
// the dimmed scrim, signaling it's a transient panel rather than a route.

struct TableSideMenu: View {
    @ObservedObject var vm: GameViewModel
    @Environment(\.dismiss) private var dismiss

    private var midHand: Bool {
        // True when a hand is in progress and the user can't rebuy. Matches
        // the server's gate so the UI never shows "Add Chips enabled" while
        // the API would reject it.
        guard let phase = vm.gameState?.phase else { return false }
        return phase != .waiting && phase != .ended
    }

    private var stackBBs: Int? {
        guard let bb = vm.gameState?.bigBlind, bb > 0,
              let stack = vm.mySeat?.stack else { return nil }
        return stack / bb
    }

    private func close() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            vm.showSideMenu = false
        }
    }

    var body: some View {
        GeometryReader { geo in
            let panelWidth = min(geo.size.width * 0.82, 340)

            // Retro side menu — paper drawer with a hard ink trailing edge
            // (panel border) and ink offset shadow. Scrim is ink at 55%.
            ZStack(alignment: .leading) {
                SPRetro.ink.opacity(0.55)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { close() }

                // Shadow plate — a separate ink rectangle behind the panel,
                // shifted right by 4pt. We can't use `.shadow()` on the
                // panel itself: SwiftUI rasterizes the whole subtree (text
                // included) when applying a shadow modifier, which renders
                // a ghost copy of every text label and reads as "doubled
                // text". Putting the shadow on its own layer keeps the
                // hard-ink offset effect without bleeding into text.
                Rectangle()
                    .fill(SPRetro.ink.opacity(0.75))
                    .frame(width: panelWidth)
                    .frame(maxHeight: .infinity)
                    .offset(x: 4)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                VStack(alignment: .leading, spacing: 0) {
                    header

                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 14) {
                            stackCard
                            tableInfoCard
                            actionsList
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 24)
                    }
                }
                .frame(width: panelWidth)
                .frame(maxHeight: .infinity)
                .background(
                    SPRetro.paper.ignoresSafeArea()
                )
                .overlay(
                    Rectangle()
                        .fill(SPRetro.ink)
                        .frame(width: 2.5)
                        .frame(maxHeight: .infinity),
                    alignment: .trailing
                )
            }
        }
    }

    // ─── Header ──────────────────────────────────────────────────────────────

    private var header: some View {
        // Retro side-menu header — ink label + ink title on the paper drawer.
        // The bottom edge is a 2pt ink hairline separating header from body.
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("TABLE")
                    .font(.custom("AmericanTypewriter-Bold", size: 11))
                    .foregroundStyle(SPRetro.inkMuted)
                    .tracking(1.8)
                Text(vm.tableDetail?.name ?? vm.tableName)
                    .font(.custom("ChalkboardSE-Bold", size: 17))
                    .foregroundStyle(SPRetro.ink)
                    .lineLimit(1)
            }
            Spacer()
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(SPRetro.ink)
                    .frame(width: 32, height: 32)
                    .background(SPRetro.paperShade)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(SPRetro.ink, lineWidth: 1.5))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background(SPRetro.paperShade)
        .overlay(
            Rectangle()
                .fill(SPRetro.ink)
                .frame(height: 2),
            alignment: .bottom
        )
    }

    // ─── Stack card — your chips at a glance ─────────────────────────────────

    private var stackCard: some View {
        // Retro stack card — paperShade panel with ink border and hard ink
        // offset shadow. Stack value renders in ChalkboardSE-Bold so it
        // reads as a stamped numeral.
        let stack = vm.mySeat?.stack ?? 0
        return VStack(alignment: .leading, spacing: 8) {
            Text("YOUR STACK")
                .font(.custom("AmericanTypewriter-Bold", size: 11))
                .foregroundStyle(SPRetro.inkMuted)
                .tracking(1.8)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(formatChips(String(stack)))
                    .font(.custom("ChalkboardSE-Bold", size: 28))
                    .foregroundStyle(SPRetro.ink)
                    .contentTransition(.numericText())
                if let bbs = stackBBs {
                    Text("\(bbs) BB")
                        .font(.custom("AmericanTypewriter-Bold", size: 12))
                        .foregroundStyle(SPRetro.inkMuted)
                }
            }
            if let info = vm.tableDetail {
                Text("Buy-in range: \(formatChips(String(info.minBuyIn))) – \(formatChips(String(info.maxBuyIn)))")
                    .font(.custom("AmericanTypewriter", size: 11))
                    .foregroundStyle(SPRetro.inkMuted)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Shape-only offset plate (not `.shadow()`) so the text labels
        // inside this card don't render as doubled glyphs.
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(SPRetro.ink.opacity(0.6))
                    .offset(x: 1.5, y: 2)
                RoundedRectangle(cornerRadius: 12)
                    .fill(SPRetro.paperShade)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(SPRetro.ink, lineWidth: 1.5)
                    )
            }
        )
    }

    // ─── Table info card ──────────────────────────────────────────────────────

    @ViewBuilder
    private var tableInfoCard: some View {
        // Retro table-info card — paperShade panel + ink dividers between
        // rows. The whole card sits inside a single ink border with a hard
        // offset shadow, matching the stackCard above.
        if let info = vm.tableDetail {
            VStack(spacing: 0) {
                infoRow(label: "Blinds", value: "\(formatChips(String(info.smallBlind)))/\(formatChips(String(info.bigBlind)))")
                Divider().background(SPRetro.ink.opacity(0.25))
                infoRow(label: "Game", value: (vm.gameState?.gameType ?? "TEXAS_HOLDEM") == "PLO" ? "Pot-Limit Omaha" : "No-Limit Hold'em")
                Divider().background(SPRetro.ink.opacity(0.25))
                infoRow(label: "Hand #", value: "\(vm.gameState?.handNumber ?? 0)")
                Divider().background(SPRetro.ink.opacity(0.25))
                infoRow(label: "Hosted by", value: info.ownerName)
            }
            .padding(.vertical, 4)
            // Shape-only offset plate (not `.shadow()`) so the row labels
            // inside don't render as doubled text.
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(SPRetro.ink.opacity(0.6))
                        .offset(x: 1.5, y: 2)
                    RoundedRectangle(cornerRadius: 12)
                        .fill(SPRetro.paperShade)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(SPRetro.ink, lineWidth: 1.5)
                        )
                }
            )
        }
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.custom("AmericanTypewriter", size: 12))
                .foregroundStyle(SPRetro.inkMuted)
            Spacer()
            Text(value)
                .font(.custom("AmericanTypewriter-Bold", size: 13))
                .foregroundStyle(SPRetro.ink)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    // ─── Actions ─────────────────────────────────────────────────────────────

    private var actionsList: some View {
        VStack(spacing: 8) {
            // Add chips — primary action. Always enabled: mid-hand requests
            // are queued server-side (see lobby.routes.ts topup branch) and
            // applied to the seat's stack the moment the hand ends. The
            // subtitle nudges the user about the deferred apply so they
            // aren't surprised by a "+N pending" badge that doesn't credit
            // until showdown is over.
            menuRow(
                icon: "plus.circle.fill",
                iconColor: SPRetro.teal,
                title: "Add Chips",
                subtitle: midHand
                    ? "Queued — applies after this hand"
                    : (vm.tableDetail.map { "Top up to \(formatChips(String($0.maxBuyIn))) max" } ?? "Top up your stack"),
                disabled: false
            ) {
                close()
                // Tiny delay so the drawer slide-out doesn't fight the
                // sheet's fade-in — feels less janky.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                    vm.showTopUpSheet = true
                }
            }

            // Copy join code — handy for inviting friends from the table.
            if let info = vm.tableDetail {
                menuRow(
                    icon: "doc.on.doc.fill",
                    iconColor: SPRetro.popBlue,
                    title: "Copy Join Code",
                    // Subtitle is a generic explainer — the actual code lives
                    // in the trailing chip so we don't render it twice.
                    subtitle: "Tap to copy and share",
                    trailing: AnyView(
                        Text(info.joinCode)
                            .font(.custom("ChalkboardSE-Bold", size: 11))
                            .foregroundStyle(SPRetro.ink)
                            .tracking(1.2)
                    )
                ) {
                    UIPasteboard.general.string = info.joinCode
                    vm.errorMessage = "Join code copied"
                }
            }

            // Chat shortcut — same as the existing top-right bubble, but
            // discoverable from the menu.
            menuRow(
                icon: "bubble.right.fill",
                iconColor: SPRetro.popBlue,
                title: "Open Chat",
                subtitle: "Send a message to the table"
            ) {
                close()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                    vm.showChat = true
                }
            }

            Divider()
                .background(SPRetro.ink.opacity(0.25))
                .padding(.vertical, 6)

            // Leave / Close — destructive at the bottom. Owners alone at
            // the table get the close option; everyone else gets leave.
            if vm.isAloneAtTable && (vm.tableDetail?.isMine ?? true) {
                menuRow(
                    icon: "xmark.circle.fill",
                    iconColor: SPRetro.popRed,
                    title: "Close Table",
                    subtitle: "Ends the table for everyone"
                ) {
                    close()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                        vm.showCloseConfirm = true
                    }
                }
            } else {
                menuRow(
                    icon: "rectangle.portrait.and.arrow.right",
                    iconColor: SPRetro.popRed,
                    title: "Leave Table",
                    subtitle: midHand ? "You'll be marked sitting-out for this hand" : "Cash out and return to lobby"
                ) {
                    close()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                        dismiss()
                    }
                }
            }
        }
    }

    // ─── Menu row ────────────────────────────────────────────────────────────

    private func menuRow(
        icon: String,
        iconColor: Color,
        title: String,
        subtitle: String,
        disabled: Bool = false,
        trailing: AnyView? = nil,
        action: @escaping () -> Void
    ) -> some View {
        // Retro menu row — each row is its own ink-bordered paperShade card
        // with a hard offset shadow. The icon disc carries the pop color
        // (mustard/maroon/teal/pop-blue) while the surrounding panel stays
        // neutral paper.
        Button(action: { if !disabled { action() } }) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(iconColor)
                        .frame(width: 36, height: 36)
                        .overlay(Circle().strokeBorder(SPRetro.ink, lineWidth: 1.5))
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(SPRetro.paper)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.custom("AmericanTypewriter-Bold", size: 14))
                        .foregroundStyle(disabled ? SPRetro.inkMuted.opacity(0.55) : SPRetro.ink)
                    Text(subtitle)
                        .font(.custom("AmericanTypewriter", size: 11))
                        .foregroundStyle(SPRetro.inkMuted)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if let trailing { trailing }
                else if !disabled {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(SPRetro.ink.opacity(0.45))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            // Shape-only offset plate (not `.shadow()`) so the menu row's
            // title and subtitle don't render as doubled glyphs.
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(SPRetro.ink.opacity(0.55))
                        .offset(x: 1.5, y: 2)
                    RoundedRectangle(cornerRadius: 10)
                        .fill(SPRetro.paperShade)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(SPRetro.ink, lineWidth: 1.5)
                        )
                }
            )
        }
        .buttonStyle(ScaleButtonStyle())
        .disabled(disabled)
    }
}

// ─── Top-up Sheet ─────────────────────────────────────────────────────────────
// Modal for adding chips mid-table. Presets honor the table's buy-in range
// (so the user can't accidentally request a top-up that exceeds maxBuyIn —
// the slider/presets are derived from `headroom = maxBuyIn - currentStack`).

struct TopUpSheet: View {
    @ObservedObject var vm: GameViewModel
    // Injected so we can hand it through to vm.topUpChips — the VM needs to
    // call applyServerBalance on it after the server returns newBalance.
    @EnvironmentObject var authVM: AuthViewModel
    @State private var amount: Double = 0

    // True when there's an active hand running. The backend accepts the
    // top-up either way but parks the chips in `pendingTopUp` until the
    // hand ends — we surface that explicitly in the sheet copy below so
    // the user understands their stack won't change immediately.
    private var midHand: Bool {
        guard let phase = vm.gameState?.phase else { return false }
        return phase != .waiting && phase != .ended
    }
    private var currentStack: Int { vm.mySeat?.stack ?? 0 }
    private var maxBuyIn: Int { vm.tableDetail?.maxBuyIn ?? max(currentStack * 2, 1000) }
    // Already-queued chips count against headroom so the user can't slide
    // past maxBuyIn over multiple mid-hand top-ups.
    private var alreadyPending: Int { vm.mySeat?.pendingTopUpAmount ?? 0 }
    private var headroom: Int { max(maxBuyIn - currentStack - alreadyPending, 0) }

    private func close() {
        withAnimation(.easeInOut(duration: 0.2)) { vm.showTopUpSheet = false }
    }

    var body: some View {
        // Retro top-up sheet — paper modal with ink border, ink offset
        // shadow, and mustard primary CTA. Slider keeps a green tint for
        // "going right adds chips" affordance but the rest of the panel
        // sits in the retro palette.
        ZStack {
            SPRetro.ink.opacity(0.65)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { close() }

            VStack(spacing: 16) {
                HStack {
                    Text("Add Chips")
                        .font(.custom("ChalkboardSE-Bold", size: 18))
                        .foregroundStyle(SPRetro.ink)
                    Spacer()
                    Button(action: close) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(SPRetro.ink)
                            .frame(width: 30, height: 30)
                            .background(SPRetro.paperShade)
                            .clipShape(Circle())
                            .overlay(Circle().strokeBorder(SPRetro.ink, lineWidth: 1.5))
                    }
                }

                HStack(spacing: 12) {
                    stackBox(label: "Current", amount: currentStack, accent: SPRetro.inkMuted)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(SPRetro.ink)
                    stackBox(
                        label: midHand ? "After hand" : "After",
                        amount: currentStack + alreadyPending + Int(amount),
                        accent: SPRetro.maroon
                    )
                }

                if midHand {
                    // Retro mid-hand notice — mustard pill with ink border
                    // and hard offset shadow, reads as a stamped warning.
                    HStack(spacing: 6) {
                        Image(systemName: "hourglass")
                            .font(.system(size: 10, weight: .bold))
                        Text("Applies when this hand ends")
                            .font(.custom("AmericanTypewriter-Bold", size: 11))
                    }
                    .foregroundStyle(SPRetro.ink)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    // Shape-only offset plate (not `.shadow()`) so the
                    // "Applies when this hand ends" label stays crisp.
                    .background(
                        ZStack {
                            Capsule()
                                .fill(SPRetro.ink.opacity(0.55))
                                .offset(x: 1, y: 1.5)
                            Capsule()
                                .fill(SPRetro.mustard)
                                .overlay(
                                    Capsule()
                                        .strokeBorder(SPRetro.ink, lineWidth: 1.5)
                                )
                        }
                    )
                }

                VStack(spacing: 6) {
                    HStack {
                        Text("AMOUNT")
                            .font(.custom("AmericanTypewriter-Bold", size: 11))
                            .tracking(1.5)
                            .foregroundStyle(SPRetro.inkMuted)
                        Spacer()
                        Text(formatChips(String(Int(amount))))
                            .font(.custom("ChalkboardSE-Bold", size: 14))
                            .foregroundStyle(SPRetro.ink)
                            .contentTransition(.numericText())
                    }
                    Slider(value: $amount, in: 0...Double(max(headroom, 1)), step: 1)
                        .tint(SPRetro.maroon)
                        .disabled(headroom == 0)
                }

                HStack(spacing: 8) {
                    ForEach(presets, id: \.label) { preset in
                        presetChip(label: preset.label, value: preset.value)
                    }
                }

                Text("Max top-up: \(formatChips(String(headroom))) chips (caps at table max buy-in)")
                    .font(.custom("AmericanTypewriter", size: 11))
                    .foregroundStyle(SPRetro.inkMuted)
                    .multilineTextAlignment(.center)

                // Retro confirm — mustard burst CTA with ink text/border
                // and a hard ink offset shadow. Disabled state goes to a
                // muted paperShade so the affordance is unmistakable.
                Button {
                    vm.topUpChips(amount: Int(amount), authVM: authVM)
                } label: {
                    HStack(spacing: 8) {
                        if vm.topUpInProgress {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(SPRetro.ink)
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 15))
                        }
                        Text(vm.topUpInProgress ? "Adding…" : "Confirm Top-Up")
                            .font(.custom("ChalkboardSE-Bold", size: 15))
                    }
                    .foregroundStyle(SPRetro.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    // Shape-only offset plate (not `.shadow()`) so the
                    // "Confirm Top-Up" CTA label doesn't double.
                    .background(
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(SPRetro.ink.opacity(0.7))
                                .offset(x: 2, y: 3)
                            RoundedRectangle(cornerRadius: 10)
                                .fill(amount > 0 ? SPRetro.mustard : Color(hex: "#DCC58A"))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .strokeBorder(SPRetro.ink, lineWidth: 2)
                                )
                        }
                    )
                }
                .buttonStyle(ScaleButtonStyle())
                .disabled(amount <= 0 || vm.topUpInProgress)
            }
            .padding(20)
            .frame(maxWidth: 360)
            // Shape-only offset plate (not `.shadow()`) so EVERY label
            // inside the Add Chips sheet — title, stack boxes, AMOUNT,
            // preset chips, helper text, CTA — renders crisp instead of
            // each one getting rasterized through the sheet-wide shadow.
            // This is the biggest fix: a `.shadow()` on the outermost
            // panel cascades the doubling to all inner text at once.
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(SPRetro.ink.opacity(0.7))
                        .offset(x: 3, y: 5)
                    RoundedRectangle(cornerRadius: 18)
                        .fill(SPRetro.paper)
                        .overlay(
                            RoundedRectangle(cornerRadius: 18)
                                .strokeBorder(SPRetro.ink, lineWidth: 2.5)
                        )
                }
            )
            .padding(.horizontal, 24)
        }
        .onAppear {
            // Default to a half-fill so the sheet starts useful.
            amount = Double(headroom / 2)
        }
    }

    private struct Preset { let label: String; let value: Int }
    private var presets: [Preset] {
        [
            Preset(label: "25%",  value: headroom / 4),
            Preset(label: "50%",  value: headroom / 2),
            Preset(label: "Max",  value: headroom),
        ]
    }

    private func presetChip(label: String, value: Int) -> some View {
        // Retro preset chip — selected state fills with mustard, unselected
        // is plain paperShade. Each chip is its own ink-bordered card.
        let selected = Int(amount) == value
        return Button {
            withAnimation(.spring(response: 0.25)) { amount = Double(value) }
        } label: {
            VStack(spacing: 1) {
                Text(label)
                    .font(.custom("AmericanTypewriter-Bold", size: 11))
                    .foregroundStyle(SPRetro.ink)
                Text(formatChips(String(value)))
                    .font(.custom("AmericanTypewriter", size: 10))
                    .foregroundStyle(SPRetro.inkMuted)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(selected ? SPRetro.mustard : SPRetro.paperShade)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(SPRetro.ink, lineWidth: selected ? 2 : 1.2)
            )
        }
        .buttonStyle(ScaleButtonStyle())
        .disabled(value <= 0)
    }

    private func stackBox(label: String, amount: Int, accent: Color) -> some View {
        // Retro stack-preview box — paperShade card + ink border + ink hard
        // offset shadow. `accent` controls the amount color so callers can
        // mark before/after with different tones.
        VStack(spacing: 3) {
            Text(label)
                .font(.custom("AmericanTypewriter-Bold", size: 10))
                .foregroundStyle(SPRetro.inkMuted)
                .tracking(1.4)
            Text(formatChips(String(amount)))
                .font(.custom("ChalkboardSE-Bold", size: 17))
                .foregroundStyle(accent)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        // Shape-only offset plate (not `.shadow()`) so the Current/After
        // labels and chip amounts inside stay crisp.
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(SPRetro.ink.opacity(0.55))
                    .offset(x: 1, y: 1.5)
                RoundedRectangle(cornerRadius: 10)
                    .fill(SPRetro.paperShade)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(SPRetro.ink, lineWidth: 1.5)
                    )
            }
        )
    }
}

// ─── Hole-card layout signature ──────────────────────────────────────────────
// Single Equatable key that captures every input the hole-card layout cares
// about (turn state, status, card count). Used as the `value:` for one
// .animation() modifier on `localPlayerOverlay` so SwiftUI runs ONE animation
// transaction when any of them flips, instead of three stacked transactions
// fighting each other when a server broadcast fires multiple body re-evals
// in quick succession after an action button press.
private struct HoleCardLayoutKey: Equatable {
    let isMyTurn: Bool
    let status: PlayerStatus?
    let cardCount: Int
}
