import SwiftUI
import Combine

// ─── Replay View Model ────────────────────────────────────────────────────────
// Drives the playback of a recorded hand. Owns:
//   • the hand and its precomputed analyses
//   • the current frame index
//   • playback state (playing/paused, speed)
//
// The view (HandReplayView/ReplayTableView) observes `currentFrame` and the
// `currentAnalyses` array to render. Stepping is manual or auto-advanced by
// a Task that respects `playbackSpeed`.

@MainActor
final class ReplayViewModel: ObservableObject {

    // ─── Inputs ───────────────────────────────────────────────────────────────
    let hand: RecordedHand
    let analyses: [FrameAnalysis]

    // ─── Playback state ───────────────────────────────────────────────────────
    @Published private(set) var frameIndex: Int = 0
    @Published var isPlaying: Bool = false
    @Published var playbackSpeed: Double = 1.0   // 0.5x .. 2.0x

    // Cached lookup: analyses keyed by frame index for the currently visible
    // frame. Multiple analysis entries can share a frame index (info + hero
    // verdict on the same step). We keep them in order.
    @Published private(set) var visibleAnalyses: [FrameAnalysis] = []

    private var playbackTask: Task<Void, Never>?

    // ─── Init ─────────────────────────────────────────────────────────────────
    init(hand: RecordedHand) {
        self.hand = hand
        self.analyses = HandAnalyzer.analyze(hand)
        recomputeVisibleAnalyses()
    }

    deinit {
        playbackTask?.cancel()
    }

    // ─── Computed ─────────────────────────────────────────────────────────────

    var currentFrame: ReplayFrame {
        // Clamp defensively — RecordedHand always has at least one frame.
        let i = min(max(frameIndex, 0), max(0, hand.frames.count - 1))
        return hand.frames[i]
    }

    var totalFrames: Int { hand.frames.count }
    var canStepBack: Bool { frameIndex > 0 }
    var canStepForward: Bool { frameIndex < totalFrames - 1 }
    var progress: Double {
        totalFrames <= 1 ? 1 : Double(frameIndex) / Double(totalFrames - 1)
    }

    // ─── Equity / strength / decision (PR 5) ──────────────────────────────────
    // Three derived values consumed by `EquityStripView`. Recomputed on every
    // `currentFrame` read — cheap (O(seats + analyses) at worst) and pure, so
    // we don't bother caching. Animation is driven by `.animation(...)` on
    // the consumer view watching these values.

    /// Hero's rough win probability at the *current* frame, on a 0…1 scale.
    /// Postflop reuses `HandAnalyzer.estimatedEquity`; preflop is bucketed
    /// off the Chen score because we don't run a full preflop equity solver.
    /// The arc gauge in EquityStripView is calibrated for these buckets, so
    /// any future replacement (Monte Carlo, range-vs-range solver) just
    /// needs to keep the 0…1 contract.
    var currentEquity: Double {
        let frame = currentFrame
        let hole  = hand.myHoleCards
        // Preflop OR not enough board for a postflop strength call.
        if frame.street == "PREFLOP" || frame.communityCards.count < 3 {
            switch HandAnalyzer.classify(chen: HandAnalyzer.chenScore(hole)) {
            case .premium:  return 0.72
            case .strong:   return 0.58
            case .marginal: return 0.48
            case .weak:     return 0.38
            }
        }
        let strength = HandAnalyzer.postflopStrength(hole: hole, board: frame.communityCards)
        return HandAnalyzer.estimatedEquity(strength: strength, street: frame.street)
    }

    /// Short, human-readable name for the hero's current holding. On preflop
    /// frames we return the Chen-bucket label ("Premium" / "Strong" / …);
    /// postflop we return the pokersolver hand name ("Top Pair", "Flush", …).
    var currentStrengthLabel: String {
        let frame = currentFrame
        if frame.street == "PREFLOP" || frame.communityCards.count < 3 {
            return HandAnalyzer.classify(chen: HandAnalyzer.chenScore(hand.myHoleCards)).label
        }
        return HandAnalyzer.handStrengthLabel(hole: hand.myHoleCards, board: frame.communityCards)
    }

    /// Bundles the hero's most recent decision visible at the current frame
    /// (its analysis verdict + the raw action that triggered it). Drives the
    /// "You did X" left card in the side-by-side decision compare. Returns
    /// nil before the hero has acted at all in this hand.
    var currentHeroDecision: HeroDecision? {
        // Analyses are produced in chronological order by HandAnalyzer.
        // Walk from newest backwards to find the latest hero decision at or
        // before the current frame.
        guard let a = analyses
            .filter({ $0.frameIndex <= frameIndex && $0.yourMove != nil })
            .last
        else { return nil }
        // The frame at that index always has the matching lastAction (the
        // analyzer keys off it). Defend defensively anyway.
        let f = hand.frames[a.frameIndex]
        guard let action = f.lastAction, action.playerId == hand.userId else { return nil }
        return HeroDecision(analysis: a, action: action)
    }

    // ─── Controls ─────────────────────────────────────────────────────────────

    func stepBack() {
        guard canStepBack else { return }
        seek(to: frameIndex - 1)
    }

    func stepForward() {
        guard canStepForward else {
            pause()
            return
        }
        seek(to: frameIndex + 1)
    }

    func seek(to index: Int) {
        let clamped = min(max(index, 0), totalFrames - 1)
        guard clamped != frameIndex else { return }
        // Wrap in withAnimation so the table (community cards, seat bets, last
        // action banner, pot) cross-fades instead of snapping. The analysis
        // list animates separately via its own .animation modifier.
        withAnimation(.easeInOut(duration: 0.35)) {
            frameIndex = clamped
            recomputeVisibleAnalyses()
        }
    }

    func play() {
        guard !isPlaying else { return }
        isPlaying = true
        playbackTask?.cancel()
        playbackTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if !self.isPlaying { return }
                if !self.canStepForward {
                    self.pause()
                    return
                }
                // Pause length depends on whether the next frame has analysis
                // attached. Decision frames linger longer so the user can read.
                let nextIndex = self.frameIndex + 1
                let hasAnalysis = self.analyses.contains { $0.frameIndex == nextIndex && ($0.yourMove != nil || $0.recommendation != nil) }
                let basePauseMs: UInt64 = hasAnalysis ? 2_400_000_000 : 900_000_000
                let pause = UInt64(Double(basePauseMs) / max(0.25, self.playbackSpeed))
                try? await Task.sleep(nanoseconds: pause)
                if Task.isCancelled { return }
                self.stepForward()
            }
        }
    }

    func pause() {
        isPlaying = false
        playbackTask?.cancel()
        playbackTask = nil
    }

    func togglePlay() {
        isPlaying ? pause() : play()
    }

    func restart() {
        pause()
        seek(to: 0)
    }

    // ─── Internal ─────────────────────────────────────────────────────────────

    /// Lightweight value type that pairs the analyzer's verdict for a hero
    /// decision with the raw `PFAction` that triggered it. Lives next to the
    /// VM so the side-by-side decision view can stay a pure renderer (no
    /// reaching into `analyses` or `frames` directly).
    struct HeroDecision {
        let analysis: FrameAnalysis
        let action:   PFAction

        /// Short verb form for the action, suitable for a one-line button-
        /// like card. Includes the amount on call/raise so the user can see
        /// *exactly* what they put in, not just "called".
        var actionLabel: String {
            switch action.action {
            case "FOLD":   return "Fold"
            case "CHECK":  return "Check"
            case "CALL":   return action.amount.map { "Call \(formatChips($0))" } ?? "Call"
            case "RAISE":  return action.amount.map { "Raise to \(formatChips($0))" } ?? "Raise"
            case "ALL_IN": return action.amount.map { "All-In \(formatChips($0))" } ?? "All-In"
            default:       return action.action.capitalized
            }
        }

        /// Best-effort extraction of a recommended action verb from the
        /// freeform `recommendation` text. We can't reliably reverse-engineer
        /// every recommendation phrase, so we look for the most common verbs
        /// in a deliberate order (specific → general) and fall back to nil.
        /// `nil` tells the view to render a "See tip below" hint instead of
        /// guessing a verb that might mismatch the actual advice.
        var suggestedActionLabel: String? {
            guard let rec = analysis.recommendation?.lowercased() else { return nil }
            // Order matters — "fold" is unambiguous, "raise" before "bet"
            // because "raise" implies "bet" by default, and we'd rather
            // surface the more aggressive verb.
            if rec.contains("fold") { return "Fold" }
            if rec.contains("3-bet") || rec.contains("re-raise") { return "Re-raise" }
            if rec.contains("raise") { return "Raise" }
            if rec.contains("bet for value") || rec.contains("bet ") || rec.contains("lead") { return "Bet" }
            if rec.contains("call") { return "Call" }
            if rec.contains("check") { return "Check" }
            return nil
        }
    }

    private func recomputeVisibleAnalyses() {
        // Show every analysis up to and including the current frame, so the
        // panel reads as a running commentary. Newest first.
        visibleAnalyses = analyses
            .filter { $0.frameIndex <= frameIndex }
            .reversed()

        // Hand the newest entry to the narrator. The narrator dedupes on id
        // and no-ops when narration is disabled, so this is cheap.
        if let newest = visibleAnalyses.first {
            ReplayNarrator.shared.speak(newest)
        }
    }
}
