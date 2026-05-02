import SwiftUI

// ─── Game View ────────────────────────────────────────────────────────────────
// Full-screen poker table. Replaces the placeholder from Phase 2.

struct GameView: View {
    @StateObject var vm: GameViewModel
    @Environment(\.dismiss) var dismiss

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

                // Error toast
                if let error = vm.errorMessage {
                    VStack {
                        Spacer()
                        Text(error)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .background(SPColors.danger.opacity(0.9))
                            .clipShape(Capsule())
                            .padding(.bottom, landscape ? 60 : 90)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(60)
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
            // Hamburger — opens the in-game side menu (Add Chips, Table
            // Info, Leave / Close, etc.) instead of leaving the table directly.
            Button {
                vm.loadTableDetailIfNeeded()
                withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                    vm.showSideMenu = true
                }
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Circle())
            }

            Spacer()

            // Table tab indicator (shows game type)
            let gameLabel = (vm.gameState?.gameType ?? "TEXAS_HOLDEM") == "PLO" ? "PLO" : "NLH"
            HStack(spacing: 6) {
                // Mini card backs
                HStack(spacing: -6) {
                    ForEach(0..<2, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(hex: "#2D2D4A"))
                            .frame(width: 16, height: 22)
                            .overlay(
                                RoundedRectangle(cornerRadius: 2)
                                    .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
                            )
                    }
                }
                Text(gameLabel)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            )

            Spacer()

            // Chat toggle
            Button { withAnimation { vm.showChat.toggle() } } label: {
                Image(systemName: "bubble.right.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(vm.showChat ? Color(hex: "#4A90E2") : .white.opacity(0.7))
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Circle())
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
        let cards = vm.myCards
        let showing = !cards.isEmpty &&
                      vm.gameState?.phase != .waiting &&
                      vm.mySeat?.status != .folded &&
                      vm.mySeat?.status != .sittingOut
        if showing {
            VStack(spacing: 4) {
                // Fanned hole cards. When it's my turn the cards tighten into
                // a slightly overlapping fan (left card behind right) so the
                // pair reads as one compact hand pushed off to the side of the
                // avatar + timer ring. Otherwise they sit side-by-side.
                HStack(spacing: vm.isMyTurn ? -22 : 6) {
                    ForEach(Array(cards.enumerated()), id: \.element.id) { idx, card in
                        let isWinningCard = vm.winningCardIds.contains(card.id)
                        let dim = vm.anyWinnersDeclared && !isWinningCard
                        // 4-color front (red / blue / green / black) so the
                        // hero's hand reads with the same suit-tinted plates
                        // as the community board.
                        PlayingCardView(card: card, size: .large,
                                        coloredBackground: true)
                            .overlay(
                                RoundedRectangle(cornerRadius: PlayingCardView.CardSize.large.cornerRadius)
                                    .strokeBorder(
                                        isWinningCard ? Color(hex: "#F5C842") : Color.clear,
                                        lineWidth: 2.5
                                    )
                            )
                            .saturation(dim ? 0.5 : 1.0)
                            .opacity(dim ? 0.55 : 1.0)
                            .shadow(
                                color: isWinningCard ? Color(hex: "#F5C842").opacity(0.7) : .clear,
                                radius: 10
                            )
                            .rotationEffect(.degrees(
                                vm.isMyTurn
                                    ? (idx == 0 ? -10 : 6)
                                    : (idx == 0 ? -4  : 4)
                            ))
                            .zIndex(Double(idx))   // right card (idx=1) on top
                    }
                }
                .shadow(color: .black.opacity(0.6), radius: 8, y: 4)

                // Subtle hand-strength label
                if let label = HandStrength.label(
                    hole: cards,
                    board: vm.gameState?.communityCards ?? []
                ) {
                    Text(label)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.top, 2)
                }
            }
            // Two display modes:
            //   • Off-hand (not my turn): cards sit centered above the action
            //     bar at a slightly reduced scale so they don't dominate the
            //     screen — the table stays the focus.
            //   • On-turn: cards shrink and tuck off to the right of the seat
            //     so the avatar + timer ring read cleanly. The y-offset
            //     drops the on-turn stack just enough to clear the stack
            //     pill below the avatar.
            .scaleEffect(vm.isMyTurn ? 0.65 : 0.90, anchor: .bottom)
            .offset(x: vm.isMyTurn ? 120 : 0,
                    y: vm.isMyTurn ? 32  : 0)
            .transition(.asymmetric(
                insertion: .move(edge: .bottom).combined(with: .opacity),
                // Fold: slide toward the muck (off to the right) while rotating
                // and fading, as if the player tossed their cards away.
                removal: .modifier(
                    active:     FoldTossModifier(progress: 1),
                    identity:   FoldTossModifier(progress: 0)
                ).combined(with: .opacity)
            ))
            .animation(.spring(response: 0.45, dampingFraction: 0.78), value: vm.isMyTurn)
            .animation(.spring(response: 0.4,  dampingFraction: 0.85), value: vm.mySeat?.status)
            .animation(.spring(response: 0.35, dampingFraction: 0.8),  value: cards.map(\.id))
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
                    VStack {
                        Spacer()
                        HStack(spacing: 8) {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)
                                .scaleEffect(0.7)
                            Text("Waiting for next hand…")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Color.black.opacity(0.6))
                        .clipShape(Capsule())
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5))
                        .padding(.bottom, 110)
                    }
                    .transition(.opacity)
                    .allowsHitTesting(false)
                    .zIndex(35)
                }

                // Waiting overlay
                if vm.gameState?.phase == .waiting || vm.gameState == nil {
                    Color.black.opacity(0.55).ignoresSafeArea()
                    VStack(spacing: 20) {
                        if vm.gameState == nil {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(SPColors.accent)
                                .scaleEffect(1.5)
                            Text("Connecting...")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                        } else {
                            let seated = vm.gameState!.seats.filter { $0.status != .sittingOut }.count
                            WaitingForPlayersView(seated: seated, required: 2)

                            // Add bot button — lets you play solo against an AI opponent.
                            // Only shown when the creator opted into bots at table
                            // creation (or for tables where we have no preference,
                            // i.e. ones we joined rather than created).
                            let hasBot = vm.gameState!.seats.contains { $0.username == "StackBot" }
                            let botsAllowed = TablePreferences.botsAllowed(forTableId: vm.tableId)
                            if !hasBot && botsAllowed {
                                Button {
                                    vm.addBot()
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "cpu.fill")
                                            .font(.system(size: 14))
                                        Text("Add Bot Player")
                                            .font(.system(size: 14, weight: .semibold))
                                    }
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 10)
                                    .background(SPColors.accent.opacity(0.85))
                                    .clipShape(Capsule())
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
    }

    // ─── Seat ordering ────────────────────────────────────────────────────────
    // Local player is rotated to index 0 so table geometry places them at bottom.

    private var sortedSeats: [GameSeat] {
        guard let state = vm.gameState else { return [] }
        let myId = KeychainManager.shared.userId ?? ""
        let seats = state.seats.sorted { $0.seatIndex < $1.seatIndex }
        guard let myIdx = seats.firstIndex(where: { $0.userId == myId }) else { return seats }
        return Array(seats[myIdx...]) + Array(seats[..<myIdx])
    }
}

// ─── Chat Overlay ─────────────────────────────────────────────────────────────

struct ChatOverlay: View {
    @ObservedObject var vm: GameViewModel
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Table Chat")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Button { withAnimation { vm.showChat = false } } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white.opacity(0.5))
                        .font(.system(size: 18))
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Color.black.opacity(0.6))

            // Messages list
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(vm.chatMessages) { msg in
                            ChatBubble(msg: msg, isMe: msg.userId == KeychainManager.shared.userId)
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
            .background(Color.black.opacity(0.45))

            // Input row
            HStack(spacing: 8) {
                TextField("Message...", text: $vm.chatInput)
                    .font(.system(size: 13))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Capsule())
                    .focused($inputFocused)
                    .onSubmit { vm.sendChat() }

                Button(action: vm.sendChat) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(vm.chatInput.isEmpty ? .white.opacity(0.25) : SPColors.accent)
                }
                .disabled(vm.chatInput.isEmpty)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(Color.black.opacity(0.6))
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: SPRadius.lg))
        .shadow(color: .black.opacity(0.5), radius: 20)
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
        ZStack {
            // Dim full screen
            Color.black.opacity(0.5).ignoresSafeArea()

            // Confetti
            ConfettiView(trigger: confettiTrigger)
                .allowsHitTesting(false)

            // Centered winner card(s)
            VStack(spacing: 14) {
                ForEach(Array(winners.enumerated()), id: \.element.playerId) { _, w in
                    VStack(spacing: 10) {
                        // Crown
                        Image(systemName: "crown.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(Color(hex: "#F5C842"))
                            .shadow(color: Color(hex: "#F5C842").opacity(0.6), radius: 12)
                            .scaleEffect(appear ? 1 : 0.2)
                            .animation(.spring(response: 0.55, dampingFraction: 0.6), value: appear)

                        // Name
                        Text(w.username)
                            .font(.system(size: 20, weight: .heavy))
                            .foregroundStyle(.white)

                        // Hand name
                        Text(w.handName)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.7))

                        // Best 5 cards
                        if w.showCards && !w.bestCards.isEmpty {
                            HStack(spacing: 4) {
                                ForEach(w.bestCards.prefix(5)) { card in
                                    PlayingCardView(card: card, size: .medium)
                                }
                            }
                            .padding(.vertical, 4)
                        }

                        // Amount won
                        Text("+\(formatChips(String(w.amount)))")
                            .font(.system(size: 30, weight: .black, design: .rounded))
                            .foregroundStyle(Color(hex: "#F5C842"))
                            .shadow(color: Color(hex: "#F5C842").opacity(0.4), radius: 8)
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 20)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color(hex: "#0D1B2A").opacity(0.92))
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .strokeBorder(Color(hex: "#F5C842").opacity(0.5), lineWidth: 1.5)
                            )
                            .shadow(color: Color(hex: "#F5C842").opacity(0.3), radius: 20)
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
        let palette: [Color] = [
            Color(hex: "#F5C842"),
            Color.white,
            Color(hex: "#F9CA24"),
            Color(hex: "#FFF3B0")
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

struct ChatBubble: View {
    let msg:  ChatMessage
    let isMe: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 5) {
            if !isMe {
                Text(msg.username)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(SPColors.accentLight)
                    .frame(width: 44, alignment: .trailing)
            }
            Text(msg.message)
                .font(.system(size: 12))
                .foregroundStyle(.white)
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(isMe ? SPColors.accent.opacity(0.75) : Color.white.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10))
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

            ZStack(alignment: .leading) {
                // Scrim — tap to dismiss
                Color.black.opacity(0.55)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { close() }

                // Drawer
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
                    LinearGradient(
                        colors: [Color(hex: "#0F1422"), Color(hex: "#0A0E1A")],
                        startPoint: .top, endPoint: .bottom
                    )
                    .ignoresSafeArea()
                )
                .overlay(
                    Rectangle()
                        .fill(Color.white.opacity(0.06))
                        .frame(width: 1)
                        .frame(maxHeight: .infinity),
                    alignment: .trailing
                )
                .shadow(color: .black.opacity(0.55), radius: 20, x: 6)
            }
        }
    }

    // ─── Header ──────────────────────────────────────────────────────────────

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Table")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
                    .tracking(1.2)
                Text(vm.tableDetail?.name ?? vm.tableName)
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            Spacer()
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white.opacity(0.65))
                    .frame(width: 32, height: 32)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background(Color.white.opacity(0.02))
        .overlay(
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 0.5),
            alignment: .bottom
        )
    }

    // ─── Stack card — your chips at a glance ─────────────────────────────────

    private var stackCard: some View {
        let stack = vm.mySeat?.stack ?? 0
        return VStack(alignment: .leading, spacing: 8) {
            Text("Your Stack")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.45))
                .tracking(1.2)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(formatChips(String(stack)))
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundStyle(ChipTier.forAmount(stack).colors.primary)
                    .contentTransition(.numericText())
                if let bbs = stackBBs {
                    Text("\(bbs) BB")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            if let info = vm.tableDetail {
                Text("Buy-in range: \(formatChips(String(info.minBuyIn))) – \(formatChips(String(info.maxBuyIn)))")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.6)
        )
    }

    // ─── Table info card ──────────────────────────────────────────────────────

    @ViewBuilder
    private var tableInfoCard: some View {
        if let info = vm.tableDetail {
            VStack(spacing: 0) {
                infoRow(label: "Blinds", value: "\(formatChips(String(info.smallBlind)))/\(formatChips(String(info.bigBlind)))")
                Divider().background(Color.white.opacity(0.06))
                infoRow(label: "Game", value: (vm.gameState?.gameType ?? "TEXAS_HOLDEM") == "PLO" ? "Pot-Limit Omaha" : "No-Limit Hold'em")
                Divider().background(Color.white.opacity(0.06))
                infoRow(label: "Hand #", value: "\(vm.gameState?.handNumber ?? 0)")
                Divider().background(Color.white.opacity(0.06))
                infoRow(label: "Hosted by", value: info.ownerName)
            }
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.6)
            )
        }
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    // ─── Actions ─────────────────────────────────────────────────────────────

    private var actionsList: some View {
        VStack(spacing: 8) {
            // Add chips — primary action. Disabled mid-hand with a subtitle
            // explaining why; the server enforces the same rule.
            menuRow(
                icon: "plus.circle.fill",
                iconColor: midHand ? Color.white.opacity(0.35) : Color(hex: "#2ECC71"),
                title: "Add Chips",
                subtitle: midHand
                    ? "Available between hands"
                    : (vm.tableDetail.map { "Top up to \(formatChips(String($0.maxBuyIn))) max" } ?? "Top up your stack"),
                disabled: midHand
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
                    iconColor: Color(hex: "#4A90E2"),
                    title: "Copy Join Code",
                    subtitle: info.joinCode,
                    trailing: AnyView(
                        Text(info.joinCode)
                            .font(.system(size: 11, weight: .heavy, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.6))
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
                iconColor: Color(hex: "#4A90E2"),
                title: "Open Chat",
                subtitle: "Send a message to the table"
            ) {
                close()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                    vm.showChat = true
                }
            }

            Divider()
                .background(Color.white.opacity(0.06))
                .padding(.vertical, 6)

            // Leave / Close — destructive at the bottom. Owners alone at
            // the table get the close option; everyone else gets leave.
            if vm.isAloneAtTable && (vm.tableDetail?.isMine ?? true) {
                menuRow(
                    icon: "xmark.circle.fill",
                    iconColor: Color(hex: "#E05555"),
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
                    iconColor: Color(hex: "#E05555"),
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
        Button(action: { if !disabled { action() } }) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(iconColor.opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(iconColor)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(disabled ? Color.white.opacity(0.4) : .white)
                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if let trailing { trailing }
                else if !disabled {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.25))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(disabled ? 0.02 : 0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.white.opacity(0.05), lineWidth: 0.6)
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
    @State private var amount: Double = 0

    private var currentStack: Int { vm.mySeat?.stack ?? 0 }
    private var maxBuyIn: Int { vm.tableDetail?.maxBuyIn ?? max(currentStack * 2, 1000) }
    private var headroom: Int { max(maxBuyIn - currentStack, 0) }

    private func close() {
        withAnimation(.easeInOut(duration: 0.2)) { vm.showTopUpSheet = false }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.65)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { close() }

            VStack(spacing: 16) {
                // Header
                HStack {
                    Text("Add Chips")
                        .font(.system(size: 18, weight: .heavy))
                        .foregroundStyle(.white)
                    Spacer()
                    Button(action: close) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white.opacity(0.6))
                            .frame(width: 30, height: 30)
                            .background(Color.white.opacity(0.06))
                            .clipShape(Circle())
                    }
                }

                // Stack preview: current → after
                HStack(spacing: 12) {
                    stackBox(label: "Current", amount: currentStack, accent: Color.white.opacity(0.5))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white.opacity(0.4))
                    stackBox(label: "After", amount: currentStack + Int(amount), accent: Color(hex: "#2ECC71"))
                }

                // Slider
                VStack(spacing: 6) {
                    HStack {
                        Text("Amount")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.5))
                        Spacer()
                        Text(formatChips(String(Int(amount))))
                            .font(.system(size: 14, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .contentTransition(.numericText())
                    }
                    Slider(value: $amount, in: 0...Double(max(headroom, 1)), step: 1)
                        .tint(Color(hex: "#2ECC71"))
                        .disabled(headroom == 0)
                }

                // Preset chips — quick fills for common rebuys.
                HStack(spacing: 8) {
                    ForEach(presets, id: \.label) { preset in
                        presetChip(label: preset.label, value: preset.value)
                    }
                }

                Text("Max top-up: \(formatChips(String(headroom))) chips (caps at table max buy-in)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
                    .multilineTextAlignment(.center)

                // Confirm
                Button {
                    vm.topUpChips(amount: Int(amount))
                } label: {
                    HStack(spacing: 8) {
                        if vm.topUpInProgress {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 15))
                        }
                        Text(vm.topUpInProgress ? "Adding…" : "Confirm Top-Up")
                            .font(.system(size: 15, weight: .heavy))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(amount > 0 ? Color(hex: "#2ECC71") : Color.white.opacity(0.1))
                    )
                }
                .buttonStyle(ScaleButtonStyle())
                .disabled(amount <= 0 || vm.topUpInProgress)
            }
            .padding(20)
            .frame(maxWidth: 360)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color(hex: "#0F1422"))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.8)
            )
            .shadow(color: .black.opacity(0.6), radius: 30, y: 12)
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
        Button {
            withAnimation(.spring(response: 0.25)) { amount = Double(value) }
        } label: {
            VStack(spacing: 1) {
                Text(label)
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(.white)
                Text(formatChips(String(value)))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Int(amount) == value ? Color(hex: "#2ECC71").opacity(0.25) : Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        Int(amount) == value ? Color(hex: "#2ECC71").opacity(0.6) : Color.white.opacity(0.08),
                        lineWidth: 0.6
                    )
            )
        }
        .buttonStyle(ScaleButtonStyle())
        .disabled(value <= 0)
    }

    private func stackBox(label: String, amount: Int, accent: Color) -> some View {
        VStack(spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.45))
                .tracking(1.0)
            Text(formatChips(String(amount)))
                .font(.system(size: 17, weight: .black, design: .rounded))
                .foregroundStyle(accent)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
        )
    }
}
