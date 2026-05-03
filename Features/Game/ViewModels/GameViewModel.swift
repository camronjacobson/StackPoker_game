import SwiftUI
import Combine

// MAP: GameViewModel — central in-game state + action dispatcher (572 lines)
// - Published state ........................ L21
// - init() ................................. L97
// - Lifecycle (start/stop) ................. L106
// - Subscriptions (socket → state) ......... L122
// - Game state handler (apply server view) . L198
// - Turn timer ............................. L306
// - Player actions (sendAction et al) ...... L362
//     fold L379, check L384, call L389, raise L395, allIn L400
// - requestTimeExtension ................... L416
// - sendChat ............................... L423
// - showCard (voluntary fold-show) ......... L436
// - Convenience vars (mySeat, isMyTurn …) .. L543

// Cached subset of TableDetail used by the in-game side menu. The websocket
// game state doesn't include join code, owner, or buy-in limits — those come
// from the lobby's REST detail endpoint and are loaded lazily.
struct TableInfoSnapshot: Equatable {
    let name:       String
    let joinCode:   String
    let smallBlind: Int
    let bigBlind:   Int
    let minBuyIn:   Int
    let maxBuyIn:   Int
    let ownerName:  String
    let isMine:     Bool
}

@MainActor
final class GameViewModel: ObservableObject {

    // ─── Published state ──────────────────────────────────────────────────────

    @Published var gameState:     ClientGameState?
    @Published var chatMessages:  [ChatMessage] = []
    @Published var chatInput      = ""
    @Published var showChat       = false
    @Published var showWinners    = false
    @Published var winnerPayouts: [WinnerPayout] = []

    // Action UI
    @Published var showRaiseSlider = false
    @Published var raiseAmount     = 0
    @Published var isSendingAction = false
    @Published var errorMessage:   String?
    @Published var lastActionLabel: String?

    // Timer
    @Published var turnTimeRemaining: Double = 1.0  // 0..1 progress
    @Published var turnSecondsLeft:   Int    = 20

    /// True after the local player has used their per-turn +15s extension.
    /// Reset when the active player changes (i.e. each new turn). Drives
    /// the +15s button visibility in ActionBar so a player can't spam.
    @Published private(set) var turnExtensionUsed: Bool = false

    /// Tracks the previous active player id so we can detect turn-change
    /// transitions inside `updateTurnTimer` and reset `turnExtensionUsed`.
    /// Decoupled from `gameState?.activePlayerId` because that gets
    /// reassigned inside `withAnimation` before the timer runs.
    private var lastActivePlayerId: String?

    // Haptics
    private let heavyImpact  = UIImpactFeedbackGenerator(style: .heavy)
    private let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private let lightImpact  = UIImpactFeedbackGenerator(style: .light)
    private let rigidImpact  = UIImpactFeedbackGenerator(style: .rigid)
    private let selectionFeedback = UISelectionFeedbackGenerator()
    private let notificationFeedback = UINotificationFeedbackGenerator()

    private func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
    private func notificationHaptic(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        notificationFeedback.notificationOccurred(type)
    }

    private var lastWarningSecond: Int = -1
    // Timestamp of the last `LastAction` we've already produced sound for.
    // Used to detect *new* opponent actions in handleGameState so we can
    // play a matching chip/fold sound when another player acts.
    private var lastSeenActionTimestamp: Int = 0

    // Kick/exit
    @Published var wasKicked = false
    @Published var shouldExit = false
    @Published var showCloseConfirm = false

    // In-game side menu (sliding drawer from the left). Holds Add Chips,
    // Table Info, Copy Join Code, Leave / Close Table.
    @Published var showSideMenu = false
    @Published var showTopUpSheet = false
    @Published var topUpInProgress = false
    // Cached table detail for the side menu (joinCode, blinds, max buy-in,
    // owner name). Loaded lazily the first time the menu is opened.
    @Published var tableDetail: TableInfoSnapshot?

    // ─── Dependencies ─────────────────────────────────────────────────────────

    let tableId:  String
    let tableName: String
    private let userId:   String
    private let socket   = GameSocketClient.shared
    private let keychain = KeychainManager.shared
    private var cancellables = Set<AnyCancellable>()
    private var turnTimerTask: Task<Void, Never>?

    // ─── Init ─────────────────────────────────────────────────────────────────

    init(tableId: String, tableName: String) {
        self.tableId   = tableId
        self.tableName = tableName
        self.userId    = KeychainManager.shared.userId ?? ""
        setupSubscriptions()
    }

    // ─── Lifecycle ─────────────────────────────────────────────────────────────

    func onAppear() {
        guard let token = keychain.accessToken else { return }
        socket.connect(token: token)
        socket.joinTable(tableId)
    }

    func onDisappear() {
        socket.leaveTable(tableId)
        turnTimerTask?.cancel()
        // Cut any in-flight sfx (e.g. a timer tick scheduled right before
        // exit) so audio doesn't continue over the rejoin banner.
        SoundManager.shared.stopAll()
    }

    // ─── Subscriptions ────────────────────────────────────────────────────────

    private func setupSubscriptions() {
        socket.gameStateSubject
            .receive(on: RunLoop.main)
            .sink { [weak self] state in self?.handleGameState(state) }
            .store(in: &cancellables)

        socket.chatSubject
            .receive(on: RunLoop.main)
            .sink { [weak self] msg in
                self?.chatMessages.append(msg)
                if self?.chatMessages.count ?? 0 > 100 { self?.chatMessages.removeFirst() }
            }
            .store(in: &cancellables)

        socket.handEndedSubject
            .receive(on: RunLoop.main)
            .sink { [weak self] payouts in
                guard let self else { return }
                self.winnerPayouts = payouts
                withAnimation(.spring(response: 0.5)) { self.showWinners = true }
                // Only play/haptic on wins — losing a hand should be silent.
                if payouts.contains(where: { $0.playerId == self.userId }) {
                    SoundManager.shared.play(.win)
                    self.notificationHaptic(.success)
                }
                // Persist to local hand history for the Review feature.
                HandRecorder.shared.finalize(winners: payouts)
                Task {
                    // Hide the winner-celebration UI 2s sooner than before
                    // (was 4s) so the next deal feels snappy. Note: the
                    // *server* still controls when the next hand actually
                    // starts dealing — if next-hand pacing still feels slow,
                    // shorten the matching delay in the backend hand loop.
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    withAnimation { self.showWinners = false }
                }
            }
            .store(in: &cancellables)

        socket.errorSubject
            .receive(on: RunLoop.main)
            .sink { [weak self] err in
                guard let self else { return }
                self.errorMessage = err.message

                // CRITICAL: reset the in-flight action debounce. `isSendingAction` is
                // normally cleared in `handleGameState` when the server broadcasts a
                // new state — but a *rejected* action sends an `error` event with no
                // accompanying state broadcast. Without this reset, `isSendingAction`
                // stays `true` forever and the `guard !isSendingAction else { return }`
                // in `sendAction` silently no-ops every subsequent button press,
                // making the table appear frozen until the user reconnects. Discovered
                // 2026-05-02 after server-side raise validation started rejecting
                // stale `raiseAmount` values (see fix in `handleGameState`).
                self.isSendingAction = false

                // Close the raise sheet so the user can retry from a clean state. If
                // the rejection was due to a stale raiseAmount, the next time they
                // open the slider it will re-clamp to the current legal range.
                self.showRaiseSlider = false

                Task {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    self.errorMessage = nil
                }
            }
            .store(in: &cancellables)

        socket.kickedSubject
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.wasKicked = true }
            .store(in: &cancellables)
    }

    // ─── Game State Handler ───────────────────────────────────────────────────

    private func handleGameState(_ state: ClientGameState) {
        let wasMyTurn = gameState?.activePlayerId == userId
        let prevCardCount = gameState?.seats.first(where: { $0.userId == userId })?.holeCards?.count ?? 0
        let prevCommunityCount = gameState?.communityCards.count ?? 0

        withAnimation(.easeInOut(duration: 0.25)) {
            gameState = state
        }
        updateTurnTimer(state)

        // Capture for hand-history / review feature. Cheap, runs on main.
        let myUsername = state.seats.first(where: { $0.userId == userId })?.username ?? ""
        HandRecorder.shared.observe(
            state: state,
            tableName: tableName,
            userId: userId,
            myUsername: myUsername
        )

        // Community card deal sound — stagger one play per new card so the
        // audio tracks each card landing on the felt (flop = 3 staggered plays).
        let newCommunityCards = state.communityCards.count - prevCommunityCount
        if newCommunityCards > 0 {
            playDealStaggered(count: newCommunityCards)
            haptic(.light)
        }

        // Sync raiseAmount with the current legal range. Two scenarios:
        //
        //   A) First time the raise panel is relevant this session — raiseAmount
        //      starts at 0, so we default it to the advertised minimum.
        //
        //   B) raiseAmount holds a value from a *previous* turn or hand and the
        //      legal range has shifted (e.g. someone re-raised, so minRaise is
        //      now higher than what the user previously selected). The slider's
        //      getter visually clamps to the new range, but the underlying
        //      @Published `raiseAmount` still holds the stale low value. Tapping
        //      Confirm would then send a number below the server's accepted
        //      minimum, the server rejects, and combined with the previous bug
        //      where `isSendingAction` wasn't reset on error, the UI froze.
        //
        //   Always clamping on every state arrival keeps `raiseAmount` honest
        //   with whatever the server is currently willing to accept.
        if let legal = state.legalActions.first(where: { $0.action == .raise }),
           let lo = legal.minAmount,
           let hi = legal.maxAmount {
            if raiseAmount == 0 {
                raiseAmount = lo
            } else {
                raiseAmount = min(max(raiseAmount, lo), hi)
            }
        }

        isSendingAction = false

        // Haptics — single buzz when it becomes the local player's turn. The
        // ticking sound is intentionally not played here; it only fires in the
        // final 5 seconds from the timer loop below.
        let isNowMyTurn = state.activePlayerId == userId
        if isNowMyTurn && !wasMyTurn {
            haptic(.heavy)
        }

        let newCardCount = state.seats.first(where: { $0.userId == userId })?.holeCards?.count ?? 0
        if newCardCount > prevCardCount {
            haptic(.light) // hole cards dealt
            playDealStaggered(count: newCardCount - prevCardCount)
        }

        // Opponent action sounds — when another player acts, play the sound
        // matching their action. Local player sounds are already fired
        // optimistically from fold/check/call/raise/allIn below, so we skip
        // actions authored by the local user to avoid doubling up.
        if let last = state.lastAction,
           last.timestamp > lastSeenActionTimestamp {
            lastSeenActionTimestamp = last.timestamp
            if last.playerId != userId {
                switch last.action {
                case "FOLD":        SoundManager.shared.play(.fold)
                case "CHECK":       SoundManager.shared.play(.check)
                case "CALL",
                     "SMALL_BLIND",
                     "BIG_BLIND":   SoundManager.shared.play(.call)
                case "RAISE":       SoundManager.shared.play(.raise)
                case "ALL_IN":      SoundManager.shared.play(.allIn)
                default: break
                }
            }
        }
    }

    /// Plays `.cardDeal` `count` times with ~120ms between plays so overlapping
    /// AVAudioPlayerNodes in the sound pool produce a sequence that matches
    /// each card landing on the felt.
    private func playDealStaggered(count: Int) {
        guard count > 0 else { return }
        SoundManager.shared.play(.cardDeal)
        guard count > 1 else { return }
        Task {
            for _ in 1..<count {
                try? await Task.sleep(nanoseconds: 120_000_000)
                SoundManager.shared.play(.cardDeal)
            }
        }
    }

    // ─── Turn Timer ───────────────────────────────────────────────────────────

    private func updateTurnTimer(_ state: ClientGameState) {
        turnTimerTask?.cancel()

        // Reset the per-turn +15s allowance whenever the active player
        // changes. We do this before the early-return so even hands that end
        // (activePlayerId becomes nil) clear the flag for the next turn.
        if state.activePlayerId != lastActivePlayerId {
            lastActivePlayerId = state.activePlayerId
            turnExtensionUsed  = false
        }

        guard state.activePlayerId != nil,
              state.actionDeadline > 0 else {
            turnTimeRemaining = 1.0
            // Fallback only — real value is server-authoritative via
            // state.turnDuration. The matching shorter base TURN_DURATION
            // belongs in the backend; this just keeps offline/test UIs sane.
            turnSecondsLeft   = 20
            return
        }

        let deadline = Date(timeIntervalSince1970: state.actionDeadline / 1000)
        // Authoritative turn span from the server (base duration + time bank).
        // Fallback: if an older server omits turnDuration, measure the span
        // ourselves from the first deadline we see so the ring still animates
        // proportionally instead of pinning at 1.0 for the first N seconds.
        let total: Double = {
            if let ms = state.turnDuration, ms > 0 { return ms / 1000 }
            let measured = deadline.timeIntervalSinceNow
            return measured > 0 ? measured : 20
        }()

        lastWarningSecond = -1
        let isMe = state.activePlayerId == userId
        turnTimerTask = Task { [weak self] in
            while !Task.isCancelled {
                let remaining = deadline.timeIntervalSinceNow
                let progress  = max(0, min(1, remaining / total))
                let secs      = max(0, Int(ceil(remaining)))
                self?.turnTimeRemaining = progress
                self?.turnSecondsLeft   = secs
                // Timer warning: tick haptic + sound only in the final 5 seconds
                // for the local player, matching the visible countdown overlay.
                if isMe, secs <= 5, secs > 0, secs != self?.lastWarningSecond {
                    self?.lastWarningSecond = secs
                    self?.haptic(.light)
                    SoundManager.shared.play(.timerWarning)
                }
                if remaining <= 0 { break }
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
    }

    // ─── Player Actions ───────────────────────────────────────────────────────

    func sendAction(_ action: PokerAction, amount: Int? = nil) {
        guard !isSendingAction else { return }
        isSendingAction = true
        showRaiseSlider = false

        socket.sendAction(tableId: tableId, action: action, amount: amount)

        // Optimistic label
        lastActionLabel = action.label
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            lastActionLabel = nil
        }
    }

    func fold()  {
        haptic(.medium)
        SoundManager.shared.play(.fold)
        sendAction(.fold)
    }
    func check() {
        haptic(.light)
        SoundManager.shared.play(.check)
        sendAction(.check)
    }
    func call()  {
        haptic(.medium)
        SoundManager.shared.play(.call)
        let callAmt = gameState?.legalActions.first(where: { $0.action == .call })?.callAmount
        sendAction(.call, amount: callAmt)
    }
    func raise() {
        haptic(.rigid)
        SoundManager.shared.play(.raise)
        sendAction(.raise, amount: raiseAmount)
    }
    func allIn() {
        haptic(.heavy)
        SoundManager.shared.play(.allIn)
        Task {
            try? await Task.sleep(nanoseconds: 100_000_000)
            self.haptic(.heavy)
        }
        sendAction(.allIn)
    }

    /// Asks the server to add 15s to the current decision window. Limited
    /// to once per turn — `turnExtensionUsed` flips immediately so the +15s
    /// button can disable on tap. The visible countdown updates when the
    /// server echoes the new `actionDeadline` (typically <200ms RTT). We
    /// intentionally don't bump `turnSecondsLeft` locally to avoid drift
    /// between the optimistic value and the next authoritative tick.
    func requestTimeExtension() {
        guard isMyTurn, !turnExtensionUsed else { return }
        turnExtensionUsed = true
        haptic(.medium)
        socket.requestTimeExtension(tableId: tableId)
    }

    func sendChat() {
        let msg = chatInput.trimmingCharacters(in: .whitespaces)
        guard !msg.isEmpty else { return }
        socket.sendChat(tableId: tableId, message: msg)
        chatInput = ""
    }

    /// User tapped one of their own hole cards to expose it to everyone.
    /// We don't gate locally on phase / status — the server is the source
    /// of truth and will silently no-op if the index is invalid (no hand
    /// yet, out of range, already shown). The server's broadcast carries
    /// the new revealedCards back to every client, including this one,
    /// which drives the flip animation in HoleCardsView.
    func showCard(at index: Int) {
        haptic(.light)
        socket.showCard(tableId: tableId, cardIndex: index)
    }

    // True when local player is the only active seat (or table is empty of others)
    var isAloneAtTable: Bool {
        guard let state = gameState else { return false }
        let others = state.seats.filter { $0.userId != userId && $0.status != .sittingOut }
        return others.isEmpty
    }

    func closeTable() {
        Task {
            do {
                struct Empty: Decodable {}
                let _: Empty = try await NetworkService.shared.request(
                    .closeTable(id: tableId), method: .POST
                )
                shouldExit = true
            } catch let err as NetworkError {
                errorMessage = err.localizedDescription
            } catch {}
        }
    }

    // ─── Top-up chips ────────────────────────────────────────────────────────
    // Adds chips to the local player's stack between hands. Server enforces
    // the mid-hand block, max-buy-in cap, and chip balance check; we just
    // surface any error message.
    func topUpChips(amount: Int) {
        guard amount > 0 else { return }
        topUpInProgress = true
        Task {
            defer { topUpInProgress = false }
            do {
                struct Body: Encodable { let amount: Int }
                struct TopUpResponse: Decodable { let newStack: String; let addedAmount: String }
                let _: TopUpResponse = try await NetworkService.shared.request(
                    .topUpChips(tableId: tableId),
                    method: .POST,
                    body: Body(amount: amount)
                )
                showTopUpSheet = false
            } catch let err as NetworkError {
                errorMessage = err.localizedDescription
            } catch {
                errorMessage = "Failed to add chips"
            }
        }
    }

    // ─── Load table detail for the side menu ─────────────────────────────────
    // The websocket gameState doesn't include join code, owner, or buy-in
    // limits — those live on the lobby's TableDetail. Fetched lazily so it
    // doesn't run for users who never open the menu.
    func loadTableDetailIfNeeded() {
        guard tableDetail == nil else { return }
        Task {
            do {
                struct Player: Decodable { let userId: String; let stack: String }
                struct Owner:  Decodable { let id: String; let username: String; let displayName: String? }
                struct Detail: Decodable {
                    let id: String
                    let name: String
                    let joinCode: String
                    let smallBlind: String
                    let bigBlind: String
                    let minBuyIn: String
                    let maxBuyIn: String
                    let owner: Owner
                    let players: [Player]?
                }
                let d: Detail = try await NetworkService.shared.request(
                    .tableDetail(id: tableId), method: .GET
                )
                tableDetail = TableInfoSnapshot(
                    name:       d.name,
                    joinCode:   d.joinCode,
                    smallBlind: Int(d.smallBlind) ?? 0,
                    bigBlind:   Int(d.bigBlind)   ?? 0,
                    minBuyIn:   Int(d.minBuyIn)   ?? 0,
                    maxBuyIn:   Int(d.maxBuyIn)   ?? 0,
                    ownerName:  d.owner.displayName ?? d.owner.username,
                    isMine:     d.owner.id == userId
                )
            } catch {
                // Non-fatal — menu will show without the extra info.
            }
        }
    }

    func addBot() {
        Task {
            do {
                struct BotResponse: Decodable { let message: String }
                let _: BotResponse = try await NetworkService.shared.request(
                    .addBot(tableId: tableId), method: .POST
                )
            } catch let err as NetworkError {
                errorMessage = err.localizedDescription
            } catch {
                errorMessage = "Failed to add bot"
            }
        }
    }

    // ─── Convenience ─────────────────────────────────────────────────────────

    var mySeat: GameSeat? { gameState?.seats.first { $0.userId == userId } }
    var isMyTurn: Bool    { gameState?.activePlayerId == userId }
    var myCards:  [PokerCard] { mySeat?.holeCards ?? [] }

    /// Card IDs (e.g. "AH", "KD") that appear in any winner's best 5. Used by
    /// the table + local-player overlay to highlight the cards that made the
    /// winning hand at showdown.
    var winningCardIds: Set<String> {
        guard let winners = gameState?.winners else { return [] }
        return Set(winners.flatMap { $0.bestCards.map(\.id) })
    }

    /// True once the server has declared winners for the current hand —
    /// flips on at showdown, flips off when the next hand begins. Drives the
    /// dim-the-losers / highlight-the-winners visual state.
    var anyWinnersDeclared: Bool {
        !(gameState?.winners?.isEmpty ?? true)
    }

    var legalActions: [LegalAction] { gameState?.legalActions ?? [] }

    var canCheck: Bool { legalActions.contains { $0.action == .check } }
    var canCall:  Bool { legalActions.contains { $0.action == .call } }
    var canRaise: Bool { legalActions.contains { $0.action == .raise } }
    var callAmount: Int { legalActions.first { $0.action == .call }?.callAmount ?? 0 }
    var minRaise: Int   { legalActions.first { $0.action == .raise }?.minAmount ?? 0 }
    var maxRaise: Int   { legalActions.first { $0.action == .raise }?.maxAmount ?? mySeat?.stack ?? 0 }
}
