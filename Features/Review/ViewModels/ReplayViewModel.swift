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
