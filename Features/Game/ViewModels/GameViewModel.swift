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

// ─── Turn Clock ──────────────────────────────────────────────────────────────
// Standalone ObservableObject for the per-turn timer values. See the
// `turnClock` property on GameViewModel for the rationale (5Hz tick was
// invalidating the whole VM observer tree). Only views that actually need
// the live progress (the seat's countdown ring + last-5s digit) hold an
// @ObservedObject reference to this; the rest of the table observes the
// VM directly and is unaffected by tick churn.
@MainActor
final class TurnClock: ObservableObject {
    @Published var progress:    Double = 1.0  // 0…1, retained for any non-ring consumer
    @Published var secondsLeft: Int    = 20   // whole-second display digit
    // Absolute end time of the current turn — set once at turn start, then
    // left alone. The ring view consumes this directly via TimelineView so
    // the trim animates at the display refresh rate (~60Hz) instead of
    // being driven by 5Hz `progress` writes from the Task loop (which
    // looked choppy because SwiftUI was interpolating between five
    // discrete points per second). nil ⇒ no active turn, hide the ring.
    @Published var deadline:    Date?  = nil
    // Total span of the current turn (base + time bank, in seconds). Used
    // alongside `deadline` by the ring view to compute the trim ratio.
    @Published var duration:    Double = 0
}

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
    @Published var showChat       = false {
        // Opening the chat clears any unread state and dismisses the transient
        // top-right toast — the user is already looking at the panel, so the
        // out-of-band cues are redundant.
        didSet {
            if showChat {
                unreadChatCount = 0
                chatToast = nil
            }
        }
    }
    /// Number of incoming messages received while the chat panel was closed.
    /// Drives the red dot on the chat-toggle bubble button. Resets to 0 the
    /// moment the user opens the panel (see `showChat.didSet`) or sends a
    /// message themselves (sending implies "I'm aware of the conversation").
    @Published private(set) var unreadChatCount: Int = 0
    /// Transient surface for the last incoming message. Drives the small
    /// truncated banner that fades in at the top-right of the table when
    /// chat is closed. Auto-cleared by a `.task(id:)` timer in the view, so
    /// the VM only needs to publish — it does not own the dismiss schedule.
    @Published var chatToast: ChatMessage?
    @Published var showWinners    = false
    @Published var winnerPayouts: [WinnerPayout] = []

    // Action UI
    @Published var showRaiseSlider = false
    @Published var raiseAmount     = 0
    @Published var isSendingAction = false
    @Published var errorMessage:   String?
    @Published var lastActionLabel: String?

    // Timer — moved off the GameViewModel @Published cascade and onto a
    // dedicated TurnClock object. Background: the timer task ticks at 5Hz,
    // and when those two values were @Published on this VM, every tick fired
    // objectWillChange, which re-evaluated the entire body of every view
    // observing the VM (GameView, PokerTableView, ActionBar, GameHUD, …)
    // five times per second. That was the source of the per-second stutter
    // the user felt during normal play. Isolating the clock means only the
    // small wrapper view that explicitly subscribes to it (the seat ring +
    // last-5s countdown digit in PokerTableView) re-renders on tick. Static
    // chrome — the felt, pot, board, action bar — stays stable between server
    // game-state pushes.
    let turnClock = TurnClock()

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

    // ─── Checked-down auto-reveal ──────────────────────────────────────────
    // Stays true for hands where no aggression beyond the blinds happens —
    // i.e. nobody RAISEs and nobody goes ALL_IN. When a hand like that
    // reaches showdown, the local player's hole cards are auto-broadcast
    // to the rest of the table the moment winners are declared, so the
    // user doesn't have to tap "show". A bet anywhere in the hand flips
    // this off and we revert to the normal opt-in tap-to-show flow.
    @Published private(set) var noBetsThisHand: Bool = true
    /// Hand number we last saw — drives the per-hand reset of
    /// `noBetsThisHand` and `hasAutoShownThisHand`.
    private var lastSeenHandNumber: Int = 0
    /// Guards against re-firing the auto-show on every state push for the
    /// rest of the hand. The first push that meets the conditions fires
    /// the broadcasts; subsequent pushes are ignored.
    private var hasAutoShownThisHand: Bool = false

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

    // ── Store peek-tab + slide-down panel ────────────────────────────────────
    //
    // The cosmetics store at the table is surfaced via a small persistent
    // tab anchored to the top safe-area inset (StorePeekTab). Tapping
    // the tab — or dragging it downward — slides StorePanelDrawer down
    // from the top of the screen. The drawer is a custom SwiftUI overlay
    // (not a system .sheet) because iOS sheets only slide from the bottom.
    //
    // Visibility model — a *single* gate `showsStoreTab` whose default is
    // `true` while the user is on the table view. It is flipped to false
    // by anything that needs the top region clear (showdown reveal, all-
    // in dramatics, panel fully open). New hides can be added by toggling
    // this bool from the relevant code path — no enum needed.
    //
    // Why not derive it from `showWinners || isAllInRunout || …`?
    //   - Those flags are owned by different subsystems and their lifecycle
    //     boundaries don't line up perfectly with "hide the store tab".
    //     A dedicated bool gives the table view a single, explicit knob.
    //   - Keeps the rule discoverable from one place.

    /// Master visibility gate for the peek-tab. True by default; flip to
    /// false during showdown / all-in dramatics. Sheet presentation is
    /// gated separately by `isStorePanelOpen`.
    @Published var showsStoreTab: Bool = true

    /// Open/closed state for the cosmetics-store drawer. The drawer
    /// itself owns the drag and snap logic via local @State, mirroring
    /// final state back into this flag so the rest of the app can
    /// observe it (showdown gating, deep links, etc.). Setting this
    /// from outside the drawer also works — the drawer watches for
    /// external changes and animates accordingly.
    @Published var isStorePanelOpen: Bool = false

    /// Red-dot indicator on the peek-tab — true when there's a limited-time
    /// drop the user hasn't seen yet. Cleared on first panel open.
    /// TODO(post-phase-5): wire to `CosmeticsCatalog.hasUnviewedLimitedDrop`
    /// keyed on UserDefaults("lastStoreOpenAt" per-user). Stubbed at false
    /// for now so the dot doesn't flash on launch before the catalog has
    /// resolved.
    @Published var hasUnviewedDrop: Bool = false

    /// Called the first time the panel opens after a new drop. The view-
    /// level call site is the peek-tab's `onPanelOpen` hook.
    func markStoreTabViewed() {
        if hasUnviewedDrop { hasUnviewedDrop = false }
    }

    // ─── Dependencies ─────────────────────────────────────────────────────────

    let tableId:  String
    let tableName: String
    private let userId:   String
    /// Public accessor for the cached local user ID. Views (e.g. GameView's
    /// `sortedSeats`, ChatOverlay) call this on every body evaluation, so we
    /// expose the cached value rather than have each call site reach into
    /// KeychainManager.shared.userId — which would trigger a synchronous
    /// Keychain syscall (SecItemCopyMatching) per render. Set once at init.
    var localUserId: String { userId }
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
        // End any running Live Activity. This covers the "user dismissed
        // the table view but left the app open" path; the in-app teardown
        // happens here, while the timer-based teardown lives inside
        // updateTurnTimer for normal turn-end transitions.
        PokerActionActivityManager.shared.end()
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
                guard let self else { return }
                self.chatMessages.append(msg)
                if self.chatMessages.count > 100 { self.chatMessages.removeFirst() }
                // Out-of-band notifications when the chat panel is closed and
                // the message is from someone else. Echoes of the local user's
                // own sends skip both surfaces — bumping the unread badge for
                // your own message would be misleading. Toast updates fire
                // unconditionally (each new incoming message replaces any
                // currently-visible toast so the latest is what the user sees).
                let isFromMe = msg.userId == self.userId
                if !isFromMe && !self.showChat {
                    self.unreadChatCount += 1
                    self.chatToast = msg
                }
            }
            .store(in: &cancellables)

        socket.handEndedSubject
            .receive(on: RunLoop.main)
            .sink { [weak self] payouts in
                guard let self else { return }
                self.winnerPayouts = payouts
                withAnimation(.spring(response: 0.5)) { self.showWinners = true }
                // Showdown hide rule for the cosmetics peek-tab: clear the
                // top region while winner cards/badges animate in. Restored
                // below when showWinners flips back to false.
                // TODO: also hide on all-in dramatics once that animation
                //       state exists in code (see GameViewModel visibility
                //       comment block ~L177).
                self.showsStoreTab = false
                // Only play/haptic on wins — losing a hand should be silent.
                if payouts.contains(where: { $0.playerId == self.userId }) {
                    SoundManager.shared.play(.win)
                    self.notificationHaptic(.success)
                }
                // Persist to local hand history for the Review feature.
                HandRecorder.shared.finalize(winners: payouts)
                Task { [weak self] in
                    // Hide the winner-celebration UI 2s sooner than before
                    // (was 4s) so the next deal feels snappy. Note: the
                    // *server* still controls when the next hand actually
                    // starts dealing — if next-hand pacing still feels slow,
                    // shorten the matching delay in the backend hand loop.
                    //
                    // [weak self]: the outer Combine sink already uses [weak
                    // self], but this inner Task was capturing self strongly,
                    // keeping the VM alive past scene-disconnect and crashing
                    // with EXC_BAD_ACCESS when the sleep resolves on a half-
                    // torn-down view tree. Drop the work if VM is gone.
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    guard let self else { return }
                    withAnimation { self.showWinners = false }
                    // Restore peek-tab once the showdown reveal clears.
                    self.showsStoreTab = true
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

                Task { [weak self] in
                    // See comment on the showWinners Task above — same
                    // pattern, same EXC_BAD_ACCESS risk if the VM is torn
                    // down during the 3s sleep (e.g., user swipes the game
                    // scene off while a server error toast is in-flight).
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    self?.errorMessage = nil
                }
            }
            .store(in: &cancellables)

        socket.kickedSubject
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.wasKicked = true }
            .store(in: &cancellables)

        // ─── Live Activity → fold bridge ──────────────────────────────────────
        // When the user taps "Fold" in the Dynamic Island / Lock Screen tile,
        // the OpenIntent in the widget extension launches the app with a
        // `stackpoker://table/<id>/action/fold` URL. StackPokerApp.swift's
        // .onOpenURL handler parses it and posts to the router, which fans
        // out via this notification. We filter to make sure the fold is for
        // *this* table (multiple GameViewModels could theoretically exist if
        // the user navigates between tables, even if the UI only shows one),
        // then run it through the same re-validating path the URL handler
        // uses on cold launch — so a tap that arrives after the turn ended
        // is silently dropped instead of firing on the next street.
        NotificationCenter.default.publisher(for: PokerActionDeepLinkRouter.foldNotification)
            .compactMap { $0.userInfo?["tableId"] as? String }
            .filter { [weak self] in $0 == self?.tableId }
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.foldFromDeepLink() }
            .store(in: &cancellables)
    }

    // ─── Game State Handler ───────────────────────────────────────────────────

    private func handleGameState(_ state: ClientGameState) {
        let wasMyTurn = gameState?.activePlayerId == userId
        let prevCardCount = gameState?.seats.first(where: { $0.userId == userId })?.holeCards?.count ?? 0
        let prevCommunityCount = gameState?.communityCards.count ?? 0

        // PERF: previously this assignment was wrapped in
        // `withAnimation(.easeInOut(duration: 0.25)) { ... }`. That wrap was
        // the root cause of the action-button stutter — it animated EVERY
        // property derived from gameState (isMyTurn, mySeat.status, every
        // seat field, legalActions, the works) inside a single 0.25s easeInOut
        // transaction. Downstream views with their own .animation(value:)
        // modifiers (hole cards' spring, community-board ease, pot/bets
        // springs in PokerTableView) then opened SECOND transactions on top,
        // and the two sets fought over the same animatable properties — which
        // is exactly what the user saw: a smooth deal during quiet moments,
        // but a visible "snap-back / hitch" the moment a button press caused
        // a state broadcast that flipped many properties at once.
        //
        // Each view that should animate already has a scoped .animation(value:)
        // attached to the specific value it cares about, so removing the global
        // wrap leaves every intentional animation intact while killing the
        // accidental cross-cutting one.
        gameState = state
        // Per-hand reset of the checked-down auto-reveal flags. Detected via
        // handNumber transition rather than phase, because phase can re-enter
        // .waiting between hands without strictly bumping the hand number on
        // some server builds. handNumber is the most authoritative
        // monotonic identifier of "this is a fresh hand".
        if state.handNumber != lastSeenHandNumber {
            lastSeenHandNumber   = state.handNumber
            noBetsThisHand       = true
            hasAutoShownThisHand = false
        }
        updateTurnTimer(state)

        // ─── Cold-launch fold consumption ─────────────────────────────────────
        // If the app was launched from a Live Activity Fold tap while the
        // process was killed, the URL handler ran *before* this VM existed,
        // so the NotificationCenter sink above missed it. The router caches
        // the request as `pendingFold` for exactly this case. On every
        // incoming game state we ask the router whether there's a fresh
        // pending fold for this table — `consumePendingFold` clears the slot
        // on first hit, so it's idempotent across subsequent state pushes.
        // The fold itself still goes through `foldFromDeepLink`, which
        // re-validates that it's actually our turn before firing.
        if PokerActionDeepLinkRouter.shared.consumePendingFold(forTableId: tableId) {
            foldFromDeepLink()
        }

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
            // Aggression tracking for the "checked-down auto-reveal" path:
            // any RAISE or ALL_IN by ANYONE means the hand had real betting,
            // so we drop the flag for the remainder of the hand. Blinds
            // (SMALL_BLIND / BIG_BLIND) are forced posts and don't count.
            // CHECK / CALL / FOLD don't put new aggression into the pot.
            if last.action == "RAISE" || last.action == "ALL_IN" {
                noBetsThisHand = false
            }
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

        // Checked-down auto-reveal. Fires once per hand the first time we
        // see winners declared on a hand with no aggression by the local
        // player or anyone else — broadcasts every still-hidden hole card
        // so the table sees them automatically, instead of forcing the
        // user to tap each one. We gate on `mySeat?.status != .folded`
        // because a folded hero shouldn't have their cards exposed
        // against their will (they intentionally mucked); they can still
        // opt in via the existing tap-to-show flow.
        //
        // Additionally require at least one winner to have `showCards`
        // true: the server flips that on for genuine contested showdowns
        // (endHand(true)) but leaves it false for uncontested fold-wins
        // (endHand(false)). Without this guard, winning a hand because
        // everyone folded preflop — no RAISE/ALL_IN, so `noBetsThisHand`
        // is still true — would auto-broadcast the winner's hole cards
        // even though they took the pot uncontested. That defeats the
        // whole point of folding for protection. Fold-winners can still
        // voluntarily flex via tap-to-show.
        if !hasAutoShownThisHand,
           noBetsThisHand,
           let winners = state.winners,
           !winners.isEmpty,
           winners.contains(where: { $0.showCards }),
           let me = state.seats.first(where: { $0.userId == userId }),
           me.status != .folded,
           me.status != .sittingOut,
           let cards = me.holeCards,
           !cards.isEmpty {
            // Mark first so subsequent state pushes during the same
            // hand-end window don't re-fire the broadcasts.
            hasAutoShownThisHand = true
            let alreadyShown = Set((me.revealedCards ?? []).map(\.index))
            // Pin handNumber from the snapshot we're auto-showing for.
            // If the hand transitions before these reach the server (rare,
            // but possible during a fast HAND_START_DELAY) the server-side
            // handNumber guard will drop the stale tap.
            let handNumber = state.handNumber
            for idx in 0..<cards.count where !alreadyShown.contains(idx) {
                socket.showCard(tableId: tableId, cardIndex: idx, handNumber: handNumber)
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
            turnClock.progress    = 1.0
            // Fallback only — real value is server-authoritative via
            // state.turnDuration. The matching shorter base TURN_DURATION
            // belongs in the backend; this just keeps offline/test UIs sane.
            turnClock.secondsLeft = 20
            // Clear the absolute deadline so the TimelineView-driven ring
            // hides itself. Without this it would keep ticking down past
            // the previous turn's deadline until the next state push.
            turnClock.deadline    = nil
            turnClock.duration    = 0
            // No active player or no deadline → end any running Live
            // Activity. This is the path hit when the hand resolves, when
            // we leave the table, and during showdown — all moments where
            // a lingering "your action" island chip would be misleading.
            PokerActionActivityManager.shared.end()
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

        // Publish the absolute deadline + total span once. The ring view
        // (TimelineView, ~60Hz) reads these directly and computes its trim
        // ratio on the fly, so we don't need to push thousands of progress
        // values through @Published just to feed a single Circle.
        // Set duration first: if the view happens to read between these two
        // assignments, a non-zero duration with the previous deadline is
        // self-correcting on the next frame.
        turnClock.duration = total
        turnClock.deadline = deadline
        // Snap progress to the initial ratio so any consumer that still
        // reads `progress` (currently none in the ring path) gets a sane
        // initial value rather than a stale 0/1 from the previous turn.
        turnClock.progress = max(0, min(1, deadline.timeIntervalSinceNow / total))

        // ── Live Activity sync ─────────────────────────────────────────────
        // Start a Live Activity at the moment it becomes the local player's
        // turn, end it the moment the turn passes to anyone else. Doing
        // this here (inside updateTurnTimer) keeps the activity perfectly
        // aligned with the in-app turn ring — every server state push that
        // changes the timer also touches the activity.
        if isMe {
            // Build the content state from the latest server snapshot.
            // The deadline is absolute, so the widget self-ticks the
            // countdown without us pushing per-second updates.
            let myStack = state.seats.first(where: { $0.userId == userId })?.stack ?? 0
            let toCall  = state.legalActions.first(where: { $0.action == .call })?.callAmount ?? 0
            let content = PokerActionAttributes.ContentState(
                deadline: deadline,
                pot:      state.totalPot,
                toCall:   toCall,
                myStack:  myStack
            )
            PokerActionActivityManager.shared.start(
                tableId:     state.tableId,
                tableName:   tableName,
                blindsLabel: "\(state.smallBlind)/\(state.bigBlind)",
                state:       content
            )
        } else {
            // Not our turn anymore (or never was) — clear any activity from
            // a prior turn. The manager is idempotent if nothing's running.
            PokerActionActivityManager.shared.end()
        }

        turnTimerTask = Task { [weak self] in
            // Loop responsibilities, post-refactor: drive the whole-second
            // countdown digit and fire the per-second warning haptic in the
            // final 5s. We no longer publish a fractional `progress` here —
            // the ring view computes that itself from clock.deadline via
            // TimelineView, which renders at the display's refresh rate
            // (typically 60Hz, 120Hz on ProMotion) for a fluid sweep instead
            // of the previous 5Hz step. Sleep cadence dropped to 1s for the
            // same reason: nothing in this loop needs sub-second granularity
            // anymore.
            while !Task.isCancelled {
                let remaining = deadline.timeIntervalSinceNow
                let secs      = max(0, Int(ceil(remaining)))
                if let clock = self?.turnClock {
                    if clock.secondsLeft != secs { clock.secondsLeft = secs }
                }
                if isMe, secs <= 5, secs > 0, secs != self?.lastWarningSecond {
                    self?.lastWarningSecond = secs
                    self?.haptic(.light)
                    SoundManager.shared.play(.timerWarning)
                }
                if remaining <= 0 {
                    // Deadline elapsed locally — also end the Live Activity
                    // here as a safety net. The next server state push will
                    // arrive momentarily and will also call end() via the
                    // isMe==false branch above; this just makes sure the
                    // island chip never overstays the actual decision
                    // window even if that next push is briefly delayed.
                    if isMe {
                        await PokerActionActivityManager.shared.end()
                    }
                    break
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    // ─── Live Activity bridge ─────────────────────────────────────────────────
    // Allow callers (e.g. the URL handler in StackPokerApp.swift, when the
    // user taps "Fold" in the Dynamic Island) to trigger a fold without
    // touching internal state directly. Re-validates that it is in fact
    // our turn — if the deep link arrives after the turn has already passed
    // (because of app launch latency), we silently discard rather than
    // accidentally firing a fold on the wrong street.
    func foldFromDeepLink() {
        guard let s = gameState,
              s.activePlayerId == userId,
              s.legalActions.contains(where: { $0.action == .fold })
        else {
            // Turn already gone — clean up the now-stale activity if any.
            PokerActionActivityManager.shared.end()
            return
        }
        fold()
    }

    // ─── Player Actions ───────────────────────────────────────────────────────

    func sendAction(_ action: PokerAction, amount: Int? = nil) {
        guard !isSendingAction else { return }
        isSendingAction = true
        showRaiseSlider = false

        socket.sendAction(tableId: tableId, action: action, amount: amount)

        // Optimistic label
        lastActionLabel = action.label
        Task { [weak self] in
            // [weak self]: see EXC_BAD_ACCESS notes on the showWinners /
            // errorMessage Tasks. If the VM is torn down (scene-disconnect,
            // user swipes away) during the 2s sleep, the trailing property
            // write must no-op rather than crash on a zombie self.
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            self?.lastActionLabel = nil
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
        Task { [weak self] in
            // Double-tap haptic for the all-in. [weak self] so the second
            // pulse no-ops if the VM has been torn down in the 100ms gap.
            try? await Task.sleep(nanoseconds: 100_000_000)
            self?.haptic(.heavy)
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
        // Snapshot the hand number at the moment of tap. The server's
        // handNumber guard rejects this tap if the engine has rolled
        // forward to the next hand by the time it arrives, which prevents
        // a last-second tap from exposing a card in the next deal.
        let handNumber = gameState?.handNumber ?? 0
        socket.showCard(tableId: tableId, cardIndex: index, handNumber: handNumber)
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
    // surface any error message. authVM is passed in so we can sync the HUD
    // from the server-returned newBalance (rather than refetching /auth/me).
    func topUpChips(amount: Int, authVM: AuthViewModel) {
        guard amount > 0 else { return }
        topUpInProgress = true
        Task {
            defer { topUpInProgress = false }
            do {
                struct Body: Encodable { let amount: Int }
                struct TopUpResponse: Decodable {
                    let newStack:    String
                    let addedAmount: String
                    /// Caller's post-debit wallet balance (BigInt-as-string).
                    /// Server-authoritative — see TECH_DEBT.md.
                    let newBalance:  String
                }
                let resp: TopUpResponse = try await NetworkService.shared.request(
                    .topUpChips(tableId: tableId),
                    method: .POST,
                    body: Body(amount: amount)
                )
                // CHIP MUTATION: server returned newBalance; sync HUD.
                authVM.applyServerBalance(resp.newBalance)
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

    /// True when any community cards are visible (flop / turn / river).
    /// Drives the action-bar betting-row preset set: false → preflop
    /// [2BB / 3BB / 4BB], true → postflop [33% / 66% / 100%]. Reads from
    /// `communityCards.isEmpty` rather than `street == .preflop` so any
    /// future "rabbit-hunt" or replay state that backfills board cards
    /// onto a preflop fold-out hand picks the right preset set without
    /// needing a parallel boolean on the server payload.
    var isPostflop: Bool {
        !(gameState?.communityCards.isEmpty ?? true)
    }

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

    /// True iff the current showdown will trigger the checked-down
    /// auto-reveal of the local player's hole cards. Mirrors the predicate
    /// inside `handleGameState` (around L489) — keep these two in sync.
    ///
    /// GameView uses this to decide whether to *suppress* the tap-to-show
    /// prompt: if auto-reveal will fire, the explicit "TAP A CARD TO SHOW"
    /// prompt would be misleading. The previous version of this check lived
    /// inline in GameView and only tested `noBetsThisHand && anyWinnersDeclared
    /// && !isFolded`, which gave a false positive on uncontested preflop
    /// fold-wins: those satisfy all three conditions but the *real*
    /// auto-reveal additionally requires at least one winner with
    /// `showCards == true` (set by the server only for contested showdowns).
    /// That false positive blocked the user from voluntarily flexing their
    /// winning hand after the opponent folded preflop — fixed 2026-05-13.
    var isAutoRevealingMyCards: Bool {
        guard noBetsThisHand,
              let winners = gameState?.winners,
              !winners.isEmpty,
              winners.contains(where: { $0.showCards }),
              mySeat?.status != .folded,
              mySeat?.status != .sittingOut
        else { return false }
        return true
    }

    /// True only when *the local player* is among the declared winners. Used
    /// to gate the gold winning-card border on the local hole-cards overlay
    /// (GameView.localPlayerOverlay) so a card whose rank+suit happens to
    /// appear in winnerCardIds — impossible by construction today, but a
    /// cheap defence-in-depth guard against future regressions — won't get
    /// painted gold while you're the loser at a PLO all-in showdown.
    var isMeWinner: Bool {
        guard let winners = gameState?.winners else { return false }
        return winners.contains(where: { $0.playerId == userId })
    }

    var legalActions: [LegalAction] { gameState?.legalActions ?? [] }

    var canCheck: Bool { legalActions.contains { $0.action == .check } }
    var canCall:  Bool { legalActions.contains { $0.action == .call } }
    var canRaise: Bool { legalActions.contains { $0.action == .raise } }
    var callAmount: Int { legalActions.first { $0.action == .call }?.callAmount ?? 0 }
    var minRaise: Int   { legalActions.first { $0.action == .raise }?.minAmount ?? 0 }
    var maxRaise: Int   { legalActions.first { $0.action == .raise }?.maxAmount ?? mySeat?.stack ?? 0 }
}
