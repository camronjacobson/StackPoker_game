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

                // Winner celebration overlay
                if vm.showWinners {
                    WinnerCelebrationOverlay(winners: vm.winnerPayouts)
                        .transition(.opacity)
                        .zIndex(40)
                }

                // Chat panel
                if vm.showChat {
                    ChatOverlay(vm: vm)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                        .zIndex(50)
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
            // Hamburger / back menu
            Button {
                if vm.isAloneAtTable { vm.showCloseConfirm = true } else { dismiss() }
            } label: {
                Image(systemName: vm.isAloneAtTable ? "xmark" : "line.3.horizontal")
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
                        PlayingCardView(card: card, size: .large)
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
            // When it's my turn: shrink the fanned hole cards, nudge them
            // slightly right, and push the whole overlay behind the seat (via
            // zIndex on the containing ZStack) so the turn-timer ring around
            // my avatar draws cleanly in front of the cards.
            .scaleEffect(vm.isMyTurn ? 0.55 : 1.0, anchor: .bottom)
            .offset(x: vm.isMyTurn ? 120 : 0)
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

                            // Add bot button — lets you play solo against an AI opponent
                            let hasBot = vm.gameState!.seats.contains { $0.username == "StackBot" }
                            if !hasBot {
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
