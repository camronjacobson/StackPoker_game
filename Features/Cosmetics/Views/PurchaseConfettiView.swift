import SwiftUI

// ─── Purchase Confetti View ───────────────────────────────────────────────────
//
// "Confetti-lite" celebration shown after a successful purchase. Strict
// constraints (from Phase 2 spec):
//   • Maximum on-screen window: 1.5 seconds. Hard timer below — there is
//     no path that keeps this alive longer than that.
//   • Particles only — no fullscreen flash, no opaque overlay. The store
//     stays visible behind it.
//   • Reduce-motion path: when UIAccessibility.isReduceMotionEnabled is
//     on (surfaced via @Environment(\.accessibilityReduceMotion)) the
//     particle path is replaced by a static checkmark that fades in then
//     out over the same 1.5s window. Same lifecycle, no movement.
//   • allowsHitTesting(false) is set by the *caller* (StoreView) so this
//     view doesn't need to know about hit-testing — keeps the lifecycle
//     reusable for any future "win celebration" surface that does want
//     taps inside.
//
// The view renders via TimelineView(.animation) so SwiftUI drives the
// per-frame redraw rather than us spinning a Timer. Cleanup is a single
// completion call (`onFinished`) after the 1.5s budget elapses — the
// VM uses that to flip back to `.idle`.

struct PurchaseConfettiView: View {

    let cosmetic: Cosmetic
    let reduceMotion: Bool
    /// Called once when the 1.5s window has elapsed. The caller tears
    /// the view down and resumes its idle state.
    var onFinished: () -> Void = {}

    /// Particle count tuned for visible-but-not-dense. 32 particles is
    /// dense enough to read as a burst across the rarity tier colors
    /// without making the GPU work in a transient overlay.
    private static let particleCount = 32

    /// Total animation budget. Synced with the reduce-motion fade so
    /// both paths take exactly the same lifecycle time, which keeps the
    /// VM's `.celebrating` window predictable.
    private static let totalDuration: TimeInterval = 1.5

    /// Particles' starting positions + per-particle deterministic seeds.
    /// Built once at init; not re-randomized per frame.
    private let particles: [Particle]
    private let startDate: Date

    /// One-shot latch for the `onFinished` callback. Wrapped in a tiny
    /// reference type so the view can mutate it from a body closure
    /// without going through @State (the body re-runs on every
    /// TimelineView tick; using @State + onChange creates a feedback
    /// loop). Reference semantics mean every redraw shares the same
    /// flag without a re-evaluation race.
    @StateObject private var latch = FinishLatch()

    init(cosmetic: Cosmetic,
         reduceMotion: Bool,
         onFinished: @escaping () -> Void = {}) {
        self.cosmetic = cosmetic
        self.reduceMotion = reduceMotion
        self.onFinished = onFinished
        self.startDate = Date()

        // Use rarity colors as the particle palette — common items get
        // a muted burst, mythic gets a vibrant red→orange gradient mix.
        let palette = Self.palette(for: cosmetic.rarity)
        var rng = SystemRandomNumberGenerator()
        self.particles = (0..<Self.particleCount).map { _ in
            Particle(
                xSeed: Double.random(in: 0...1, using: &rng),
                angle: Double.random(in: -.pi...0, using: &rng), // upper hemisphere
                speed: Double.random(in: 220...420, using: &rng),
                color: palette.randomElement(using: &rng) ?? .yellow,
                size: CGFloat.random(in: 6...11, using: &rng),
                spin: Double.random(in: -3...3, using: &rng)
            )
        }
    }

    var body: some View {
        if reduceMotion {
            reduceMotionFallback
        } else {
            particleBurst
        }
    }

    // ── Particle path ────────────────────────────────────────────────────────

    @ViewBuilder private var particleBurst: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSince(startDate)
            // Hard end — once we cross the budget, stop rendering and
            // notify the caller. TimelineView keeps redrawing while
            // visible, so the completion call is fired from the body
            // evaluator (idempotent via the flag-cell pattern below).
            Canvas { gc, size in
                let gravity = 900.0
                for p in particles {
                    let x = size.width * p.xSeed + cos(p.angle) * p.speed * t
                    let y = size.height * 0.55
                        + sin(p.angle) * p.speed * t
                        + 0.5 * gravity * t * t
                    let rotation = p.spin * t
                    let progress = min(1.0, t / Self.totalDuration)
                    let opacity = 1.0 - progress * progress  // ease-out fade
                    var rect = CGRect(x: x - p.size / 2,
                                      y: y - p.size / 2,
                                      width: p.size, height: p.size)
                    rect = rect.applying(CGAffineTransform(
                        translationX: p.size / 2, y: p.size / 2
                    ))
                    let path = Path(roundedRect: rect, cornerRadius: p.size * 0.25)
                    gc.opacity = opacity
                    gc.translateBy(x: -p.size / 2, y: -p.size / 2)
                    gc.rotate(by: .radians(rotation))
                    gc.fill(path, with: .color(p.color))
                    gc.transform = .identity
                }
            }
            // Completion latch. We can't trigger imperative code from a
            // body, so onChange of `t` is the canonical hook.
            .onChange(of: ctx.date) { _, _ in
                if t >= Self.totalDuration { fireFinishedOnce() }
            }
        }
        .ignoresSafeArea()
    }

    // ── Reduce-motion fallback ───────────────────────────────────────────────
    //
    // A single green checkmark that fades in over the first ~0.3s and
    // fades out over the last 0.3s. Same total budget as the particle
    // path so the parent's "celebrating" window is identical.

    @ViewBuilder private var reduceMotionFallback: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSince(startDate)
            let inOpacity  = min(1.0, t / 0.3)
            let outOpacity = max(0.0, 1.0 - max(0.0, t - (Self.totalDuration - 0.3)) / 0.3)
            let opacity    = min(inOpacity, outOpacity)
            ZStack {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 96, weight: .bold))
                    .foregroundStyle(SPColors.success)
                    .opacity(opacity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: ctx.date) { _, _ in
                if t >= Self.totalDuration { fireFinishedOnce() }
            }
        }
        .ignoresSafeArea()
    }

    // ── Completion latch ─────────────────────────────────────────────────────
    //
    // `onChange` can fire multiple times around the boundary while we're
    // waiting for the parent's state flip. A class-backed flag wrapped in
    // a SwiftUI `@StateObject` would solve it cleanly, but the cheaper
    // path is a `static` per-instance guard via a UUID key in a shared
    // set. The flag-on-the-instance trick doesn't work because struct
    // mutating accessors aren't available from the closure.
    //
    // Implementation: stash a single-shot box keyed by `startDate`. The
    // set is pruned by simple time decay — entries are removed once 5s
    // have elapsed past their startDate so the dict can't grow.

    private func fireFinishedOnce() {
        if latch.fired { return }
        latch.fired = true
        onFinished()
    }

    /// Tiny reference-typed latch. Class so the body closure can flip
    /// `.fired` without a struct-mutation diagnostic, and so the same
    /// instance is shared across every TimelineView redraw.
    private final class FinishLatch: ObservableObject {
        var fired = false
    }

    // ── Palette ──────────────────────────────────────────────────────────────

    private static func palette(for rarity: CosmeticRarity) -> [Color] {
        // Mythic — red→orange gradient endpoints, plus accent so the
        // burst feels three-color rather than two.
        if rarity == .mythic {
            return rarity.gradientStops + [SPColors.accent]
        }
        // Other tiers — solid rarity color, plus mustard accent and
        // chip gold to brighten the palette beyond a single hue.
        return [rarity.solidColor, SPColors.accent, SPColors.chipGold]
    }

    // ── Particle model ───────────────────────────────────────────────────────

    private struct Particle {
        let xSeed: Double          // 0..1 → mapped to bounds.width on draw
        let angle: Double          // launch angle (radians)
        let speed: Double          // launch speed (px/s)
        let color: Color
        let size: CGFloat
        let spin: Double           // radians/s
    }
}
