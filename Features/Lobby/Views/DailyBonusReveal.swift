import SwiftUI
import Combine
import UIKit

// ─── Daily Bonus Reveal — full-screen presentation ───────────────────────────
// Owns the post-claim celebration:
//
//   1. Card grows from its inline tap location to a hero size that nearly
//      fills the screen (capped so it never crowds the edges on iPad), and
//      flips from back to front during the same interval.
//   2. Sits there waiting for the user to swipe down on the card. The drag
//      progressively pulls the two halves apart along a jagged seam — so
//      the user actively "tears" the card open. Releasing before the
//      threshold snaps the halves back together.
//   3. Past threshold, the rip commits and the two uneven halves tumble
//      off-screen at slightly different timings to mimic air resistance.
//
// Why a separate presenter (vs. doing it inside DailyBonusCard):
//   The card lives inside the lobby's ScrollView. Anything we render inline
//   gets clipped by that scroll content and can't overlap the tab bar.
//   Pulling the celebration out to a root-level overlay lets it cover the
//   entire screen so the swipe gesture and falling halves don't fight the
//   scroll system.
//
// Performance:
//   • Overlay is mounted lazily — returns EmptyView when idle, so cost is
//     zero outside of an active reveal.
//   • The two halves use the same source artwork via a mask Path; SwiftUI
//     reuses the layer instead of compositing two separate cards.
//   • The jagged rip path is generated once at reveal start and stays put
//     so the seam doesn't shimmer during the drag.
//   • No timers; drag gesture and Task.sleep drive everything, so the OS
//     schedules updates only when something actually moves.

// ─── Presenter ────────────────────────────────────────────────────────────────
// Tiny observable bus the inline card writes into and the root overlay reads.
// Stays minimal on purpose: the overlay owns its own animation state, this
// just carries the "what amount, starting from where" payload.

@MainActor
final class DailyBonusRevealPresenter: ObservableObject {
    @Published private(set) var pending: Pending?

    struct Pending: Equatable {
        let amount: Int
        // Approximate global frame of the inline card at tap time. The overlay
        // animates the expanding card from this frame outward so the reveal
        // looks like the same physical card the user tapped.
        let originRect: CGRect
        // Stable id so SwiftUI treats every new reveal as a fresh view —
        // prevents the previous animation from "blending" into the next.
        let id: UUID
    }

    /// Triggered by DailyBonusCard once the backend confirms a successful claim.
    func present(amount: Int, from originRect: CGRect) {
        pending = Pending(amount: amount, originRect: originRect, id: UUID())
    }

    /// Called by the overlay when its choreography finishes.
    func clear() {
        pending = nil
    }
}

// ─── Root overlay ─────────────────────────────────────────────────────────────
// Mounted once at app root above MainTabView. Watches the presenter; when a
// payload arrives, renders the celebration full-screen.

struct DailyBonusRevealOverlay: View {
    @EnvironmentObject var presenter: DailyBonusRevealPresenter

    var body: some View {
        Group {
            if let pending = presenter.pending {
                // .id() forces a fresh subview per reveal so the inner @State
                // resets cleanly between back-to-back claims.
                RevealStage(pending: pending) { presenter.clear() }
                    .id(pending.id)
                    // ignoresSafeArea so the falling halves can leave through
                    // the bottom of the screen, behind the tab bar.
                    .ignoresSafeArea()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: presenter.pending?.id)
    }
}

// ─── Stage ────────────────────────────────────────────────────────────────────
// One reveal "performance".

private struct RevealStage: View {
    let pending: DailyBonusRevealPresenter.Pending
    let onFinished: () -> Void

    private enum Phase: Equatable {
        case expanding     // growing from inline rect + flipping
        case awaitingTear  // sitting big in center, waiting on a swipe
        case falling       // halves tumbling out
        case gone
    }
    @State private var phase: Phase = .expanding

    // Animated quantities for the intro.
    //
    // We deliberately keep the card's *frame* fixed at hero size and animate
    // a separate scale + position. Earlier we interpolated the frame itself,
    // but that forced the Canvas-based diamond lattice on the card-back to
    // re-rasterize every frame as the size changed — visibly choppy on
    // anything but a Pro device. Fixed-frame + transform lets Core Animation
    // GPU-scale the cached layer instead.
    @State private var cardScale: CGFloat = 1
    @State private var cardCenter: CGPoint = .zero
    @State private var heroSize: CGSize = .zero
    @State private var flipDegrees: Double = 0
    @State private var dimOpacity: Double = 0
    // Set true the first time tearProgress crosses a small threshold during
    // a single drag, so the rip sfx plays once per active rip and doesn't
    // re-trigger on every gesture sample. Reset on snap-back so a second
    // attempt plays the sound again.
    @State private var ripSoundPlayed = false

    // Live drag state — 0 means halves still touching, 1 means they're
    // separated by the maximum pull width. Driven by DragGesture.onChanged.
    @State private var tearProgress: Double = 0

    // After commit, each half gets its own translation / rotation values so
    // they can fall on slightly different curves. Drives the "air resistance"
    // feel — neither half tumbles in lockstep with the other.
    @State private var leftFallY:    CGFloat = 0
    @State private var leftFallX:    CGFloat = 0
    @State private var leftRotation: Double  = 0
    @State private var rightFallY:    CGFloat = 0
    @State private var rightFallX:    CGFloat = 0
    @State private var rightRotation: Double  = 0

    // Hint chevron — fades in once the card has finished expanding.
    @State private var hintOpacity: Double = 0

    // The jagged rip seam, frozen at reveal start. Both halves clip against
    // this same path (one to the left, one to the right) so the inner edges
    // line up perfectly when tearProgress == 0.
    @State private var ripPath: RipPath = .empty

    var body: some View {
        GeometryReader { proxy in
            // Hero size — ~85% of screen width but capped so it never gets
            // absurd on iPad. Aspect ratio matches a real playing card.
            let heroWidth  = min(proxy.size.width * 0.85, 360)
            let heroHeight = heroWidth * (308.0 / 220.0)
            let screenCenter = CGPoint(x: proxy.size.width / 2,
                                        y: proxy.size.height / 2)
            let hintY = screenCenter.y + heroHeight / 2 + 38

            ZStack {
                // ── Backdrop dim ────────────────────────────────────────────
                Color.black
                    .opacity(dimOpacity)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .allowsHitTesting(true) // swallow stray taps behind the card

                // ── Torn card ──────────────────────────────────────────────
                // Fixed frame at hero size — Canvas paints once. The visible
                // size during the intro is driven by .scaleEffect, which
                // Core Animation handles as a GPU transform on the cached
                // layer (no per-frame re-rasterization).
                tornCard
                    .frame(width: heroWidth, height: heroHeight)
                    .scaleEffect(cardScale, anchor: .center)
                    .position(cardCenter)

                // ── Swipe hint ─────────────────────────────────────────────
                if phase == .awaitingTear {
                    VStack(spacing: 4) {
                        Image(systemName: "chevron.compact.down")
                            .font(.system(size: 28, weight: .black))
                            .foregroundStyle(SPRetro.paper.opacity(0.85))
                        Text("Swipe down to tear!")
                            .font(.custom("ChalkboardSE-Bold", size: 13))
                            .foregroundStyle(SPRetro.paper.opacity(0.85))
                    }
                    .opacity(hintOpacity)
                    .position(x: proxy.size.width / 2, y: hintY)
                    .allowsHitTesting(false)
                }
            }
            .onAppear {
                heroSize = CGSize(width: heroWidth, height: heroHeight)
                runIntro(screenCenter: screenCenter, heroWidth: heroWidth)
            }
        }
    }

    // ─── Torn card composite ─────────────────────────────────────────────────
    // Two halves of the same artwork, each masked to one side of the rip
    // seam. The shared DragGesture controls how far apart they're pulled
    // while the user is mid-swipe.

    @ViewBuilder
    private var tornCard: some View {
        let drag = DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard phase == .awaitingTear else { return }
                let h = max(heroSize.height, 1)
                // Map vertical drag distance to 0..1. The 1.4 multiplier
                // means the tear maxes out at roughly 70% of the card's
                // height, which feels responsive without requiring a full
                // swipe down to commit.
                let p = max(0, value.translation.height / h)
                tearProgress = min(p * 1.4, 1.0)

                // Trigger the rip sfx the first time the user crosses a
                // small threshold during this drag — sound plays "during
                // the ripping motion" rather than only at commit. Cheap
                // guard prevents per-frame re-trigger.
                if !ripSoundPlayed && tearProgress > 0.06 {
                    SoundManager.shared.play(.cardRip)
                    ripSoundPlayed = true
                }
            }
            .onEnded { value in
                guard phase == .awaitingTear else { return }
                // Commit if the user pulled past 50% OR released with
                // downward velocity (predictedEnd minus current = remaining
                // momentum from the gesture). Velocity check matters when
                // the user flicks the card hard but doesn't drag far.
                let velocity = value.predictedEndTranslation.height
                             - value.translation.height
                if tearProgress >= 0.5 || velocity > 240 {
                    commitTear()
                } else {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) {
                        tearProgress = 0
                    }
                    // Reset so a second attempt re-plays the rip sfx.
                    ripSoundPlayed = false
                }
            }

        ZStack {
            CardHalf(amount: pending.amount,
                     flipDegrees: flipDegrees,
                     ripPath: ripPath,
                     side: .left)
                // Pulled left + tilted slightly outward as the user drags.
                // .top anchor so the rotation hinges from the top of the
                // card — visually reads as "tearing from the top down".
                .offset(x: -tearProgress * 26 + leftFallX,
                        y: leftFallY)
                .rotationEffect(
                    .degrees(-tearProgress * 3 + leftRotation),
                    anchor: .top
                )

            CardHalf(amount: pending.amount,
                     flipDegrees: flipDegrees,
                     ripPath: ripPath,
                     side: .right)
                .offset(x: tearProgress * 26 + rightFallX,
                        y: rightFallY)
                .rotationEffect(
                    .degrees(tearProgress * 3 + rightRotation),
                    anchor: .top
                )
        }
        .shadow(color: Color.black.opacity(0.35), radius: 18, y: 10)
        .contentShape(Rectangle())
        .gesture(drag)
    }

    // ─── Intro choreography ──────────────────────────────────────────────────

    @MainActor
    private func runIntro(screenCenter: CGPoint, heroWidth: CGFloat) {
        // Initial state — card sits exactly where the user tapped, scaled
        // down to match the inline size. Origin scale = origin width / hero
        // width so the on-screen size is identical to the inline tap target
        // at frame 0 of the animation.
        let originRect = pending.originRect == .zero
            ? CGRect(origin: screenCenter, size: .zero)
            : pending.originRect
        let originScale: CGFloat = max(0.05, originRect.width / heroWidth)
        let originCenter = pending.originRect == .zero
            ? screenCenter
            : CGPoint(x: originRect.midX, y: originRect.midY)

        cardScale   = originScale
        cardCenter  = originCenter
        flipDegrees = 0
        dimOpacity  = 0
        ripPath     = RipPath.generate()

        Task { @MainActor in
            // Phase 1: expand + flip together. Slower (0.85s) than before
            // and a softer ease curve — gives the rotation time to read
            // and the arrival a cushioned feel instead of slamming to a
            // stop. The dim fades in slightly faster so the backdrop is
            // already established before the card lands.
            withAnimation(.easeInOut(duration: 0.85)) {
                cardScale   = 1.0
                cardCenter  = screenCenter
                flipDegrees = 180
            }
            withAnimation(.easeOut(duration: 0.40)) {
                dimOpacity  = 0.6
            }
            phase = .expanding
            try? await Task.sleep(nanoseconds: 880_000_000)

            // Phase 2: hand off to the user. Hint fades in and the gesture
            // becomes active.
            phase = .awaitingTear
            withAnimation(.easeInOut(duration: 0.35)) {
                hintOpacity = 1
            }
        }
    }

    // ─── Commit + fall ───────────────────────────────────────────────────────

    @MainActor
    private func commitTear() {
        phase = .falling
        UINotificationFeedbackGenerator().notificationOccurred(.success)

        // Belt-and-suspenders: if the user committed via a hard flick (a
        // velocity-only commit before tearProgress crossed our drag-trigger
        // threshold), the rip sfx still needs to play.
        if !ripSoundPlayed {
            SoundManager.shared.play(.cardRip)
            ripSoundPlayed = true
        }

        // Snap the rip fully open the instant we commit so the fall starts
        // from a clean separated state.
        withAnimation(.easeOut(duration: 0.10)) {
            tearProgress = 1
            hintOpacity  = 0
        }

        // Each half gets its own animation block — different durations and
        // slightly different rotation magnitudes so they tumble out of
        // sync (mimics two scraps falling through air).
        let exitY = UIScreen.main.bounds.height + heroSize.height

        // Left half — falls a touch faster, drifts further left, rotates ccw.
        withAnimation(.timingCurve(0.42, 0.0, 0.7, 1.0, duration: 1.05)) {
            leftFallY    = exitY
            leftFallX    = -28
            leftRotation = -18
        }

        // Right half — slightly slower, drifts right, rotates cw.
        withAnimation(.timingCurve(0.40, 0.0, 0.72, 1.0, duration: 1.25)) {
            rightFallY    = exitY
            rightFallX    = 30
            rightRotation = 16
        }

        // Dim fades out as the halves clear the screen.
        withAnimation(.easeIn(duration: 0.55).delay(0.55)) {
            dimOpacity = 0
        }

        // Wait for the slower half to leave, then dismiss.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_300_000_000)
            phase = .gone
            onFinished()
        }
    }
}

// ─── Card half ───────────────────────────────────────────────────────────────
// One side of the rip. Renders the same AnimatedCard as the other half but
// masked to the relevant side of the seam, so when the two are stacked at
// tearProgress == 0 they form a single seamless card.

private enum CardSide { case left, right }

private struct CardHalf: View {
    let amount: Int
    let flipDegrees: Double
    let ripPath: RipPath
    let side: CardSide

    var body: some View {
        AnimatedCard(amount: amount, flipDegrees: flipDegrees)
            .mask(
                GeometryReader { proxy in
                    let path = side == .left
                        ? ripPath.leftMask(in: proxy.size)
                        : ripPath.rightMask(in: proxy.size)
                    path.fill(Color.white)
                }
            )
    }
}

// ─── Animated card ───────────────────────────────────────────────────────────
// The expanding/flipping card itself. Two faces stacked in a ZStack with a
// shared 3-D rotation — same approach as the inline card, but sized to grow
// with the parent .frame so geometry interpolates smoothly.

private struct AnimatedCard: View {
    let amount: Int
    let flipDegrees: Double

    var body: some View {
        ZStack {
            // .drawingGroup() snapshots each face into a single Metal-backed
            // texture, so the diamond-lattice Canvas (card-back) and sunburst
            // Canvas (reward face) each render exactly once — Core Animation
            // then handles the flip rotation and the intro scale as cheap
            // GPU transforms on the cached bitmaps. This is what removed the
            // visible chop during the expand+flip on non-Pro devices.
            DailyBonusCardBack()
                .drawingGroup()
                .opacity(flipDegrees < 90 ? 1 : 0)

            DailyBonusRewardFace(amount: amount)
                .drawingGroup()
                .opacity(flipDegrees >= 90 ? 1 : 0)
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
        }
        .rotation3DEffect(
            .degrees(flipDegrees),
            axis: (x: 0, y: 1, z: 0),
            perspective: 0.55
        )
    }
}

// ─── Rip path ────────────────────────────────────────────────────────────────
// A jagged, mostly-vertical seam from top to bottom of the card. Built once
// per reveal with random horizontal jitter so each tear looks slightly
// different. Both endpoints are anchored at exactly x=0.5 so the seam meets
// the card edges cleanly.

struct RipPath {
    /// Normalized points (0...1 in both axes) along the seam, ordered top to
    /// bottom. Stored normalized so a single path generation can be reused
    /// at any size.
    let points: [CGPoint]

    static func generate() -> RipPath {
        // 22 points gives a satisfyingly jagged silhouette without making
        // the path expensive to fill. Endpoints are anchored at exactly
        // x = 0.5 so the seam meets the card edges with no gap.
        let count = 22
        var pts: [CGPoint] = []
        for i in 0..<count {
            let t = Double(i) / Double(count - 1)
            let jitter: Double = (i == 0 || i == count - 1)
                ? 0
                : Double.random(in: -0.16 ... 0.16)
            pts.append(CGPoint(x: 0.5 + jitter, y: t))
        }
        return RipPath(points: pts)
    }

    /// Placeholder before the real path is generated. Straight vertical
    /// line so masks render sensibly if they ever sample empty.
    static var empty: RipPath {
        RipPath(points: [CGPoint(x: 0.5, y: 0), CGPoint(x: 0.5, y: 1)])
    }

    /// Closed path covering the left half of the card up to the seam.
    func leftMask(in size: CGSize) -> Path {
        var p = Path()
        p.move(to: .zero)
        p.addLine(to: CGPoint(x: points.first!.x * size.width, y: 0))
        for pt in points.dropFirst() {
            p.addLine(to: CGPoint(x: pt.x * size.width,
                                  y: pt.y * size.height))
        }
        p.addLine(to: CGPoint(x: 0, y: size.height))
        p.closeSubpath()
        return p
    }

    /// Closed path covering the right half of the card from the seam outward.
    func rightMask(in size: CGSize) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: size.width, y: 0))
        p.addLine(to: CGPoint(x: points.first!.x * size.width, y: 0))
        for pt in points.dropFirst() {
            p.addLine(to: CGPoint(x: pt.x * size.width,
                                  y: pt.y * size.height))
        }
        p.addLine(to: CGPoint(x: size.width, y: size.height))
        p.closeSubpath()
        return p
    }
}

// ─── Shared face views ────────────────────────────────────────────────────────
// Promoted out of DailyBonusCard so the inline tap target and the full-screen
// reveal can render the exact same artwork at any size. Both views grow with
// their parent frame instead of using fixed dimensions — important so the
// hero-size reveal isn't a tiny card stuck inside a big container.

struct DailyBonusCardBack: View {
    var body: some View {
        GeometryReader { proxy in
            let cornerLg: CGFloat = max(7, proxy.size.width * 0.10)
            let cornerSm: CGFloat = max(5, proxy.size.width * 0.075)
            ZStack {
                // Flat maroon — no gradient. Comic pages use solid ink fills,
                // never gradients, so this is the most "60s print" change.
                RoundedRectangle(cornerRadius: cornerLg, style: .continuous)
                    .fill(SPRetro.maroon)

                // Ink inner border in place of the previous gold one — the
                // comic-panel system uses thick ink lines for every border.
                RoundedRectangle(cornerRadius: cornerSm, style: .continuous)
                    .strokeBorder(SPRetro.ink,
                                  lineWidth: max(1, proxy.size.width * 0.018))
                    .padding(proxy.size.width * 0.045)

                // Diamond lattice — kept the algorithm but tinted mustard
                // (instead of gold-on-red) so it reads as Ben-Day printing
                // on top of the maroon backplate.
                Canvas { ctx, size in
                    let spacing: CGFloat = max(6, size.width * 0.10)
                    let r: CGFloat       = max(1.5, size.width * 0.029)
                    let inset: CGFloat   = size.width * 0.075
                    let rect = CGRect(x: inset, y: inset,
                                      width: size.width - inset * 2,
                                      height: size.height - inset * 2)
                    ctx.clip(to: Path(roundedRect: rect, cornerRadius: cornerSm * 0.6))

                    var y: CGFloat = inset
                    var row = 0
                    while y <= size.height - inset {
                        let xOffset = (row % 2 == 0) ? CGFloat(0) : spacing / 2
                        var x: CGFloat = inset + xOffset
                        while x <= size.width - inset {
                            var dia = Path()
                            dia.move(to: CGPoint(x: x, y: y - r))
                            dia.addLine(to: CGPoint(x: x + r, y: y))
                            dia.addLine(to: CGPoint(x: x, y: y + r))
                            dia.addLine(to: CGPoint(x: x - r, y: y))
                            dia.closeSubpath()
                            ctx.fill(dia, with: .color(SPRetro.mustard.opacity(0.55)))
                            x += spacing
                        }
                        y += spacing / 2
                        row += 1
                    }
                }
                .allowsHitTesting(false)

                // Center dollar monogram — mustard disc with ink border + ink
                // "$". Mirrors the brand chip used throughout the home screen.
                Circle()
                    .fill(SPRetro.mustard)
                    .frame(width: proxy.size.width * 0.44,
                           height: proxy.size.width * 0.44)
                    .overlay(
                        Circle()
                            .strokeBorder(SPRetro.ink,
                                          lineWidth: max(1.5, proxy.size.width * 0.022))
                    )
                Text("$")
                    .font(.custom("ChalkboardSE-Bold", size: proxy.size.width * 0.30))
                    .foregroundStyle(SPRetro.ink)
            }
        }
    }
}

struct DailyBonusRewardFace: View {
    let amount: Int

    var body: some View {
        GeometryReader { proxy in
            let cornerLg: CGFloat = max(7, proxy.size.width * 0.10)
            let cornerSm: CGFloat = max(5, proxy.size.width * 0.075)
            ZStack {
                // Flat mustard — replaces the gold gradient. Burst rays do
                // the heavy lifting for "celebration" visually so the base
                // doesn't need a gradient.
                RoundedRectangle(cornerRadius: cornerLg, style: .continuous)
                    .fill(SPRetro.mustard)

                RoundedRectangle(cornerRadius: cornerSm, style: .continuous)
                    .strokeBorder(SPRetro.ink,
                                  lineWidth: max(1, proxy.size.width * 0.018))
                    .padding(proxy.size.width * 0.045)

                // Sunburst rays — tinted maroon at modest opacity so the
                // burst reads as printed comic linework on the mustard page.
                Canvas { ctx, size in
                    let center = CGPoint(x: size.width / 2, y: size.height / 2)
                    let count = 12
                    for i in 0..<count {
                        let angle = Double(i) / Double(count) * .pi * 2
                        var ray = Path()
                        ray.move(to: center)
                        ray.addLine(to: CGPoint(
                            x: center.x + CGFloat(cos(angle)) * size.width,
                            y: center.y + CGFloat(sin(angle)) * size.height
                        ))
                        ctx.stroke(ray,
                                   with: .color(SPRetro.maroon.opacity(0.22)),
                                   lineWidth: max(2, size.width * 0.06))
                    }
                }
                .allowsHitTesting(false)

                VStack(spacing: 2) {
                    Text("+\(amount)")
                        .font(.custom("ChalkboardSE-Bold", size: proxy.size.width * 0.28))
                        .foregroundStyle(SPRetro.ink)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    Text("CHIPS!")
                        .font(.custom("AmericanTypewriter-Bold", size: proxy.size.width * 0.13))
                        .tracking(proxy.size.width * 0.025)
                        .foregroundStyle(SPRetro.maroon)
                }
                .padding(.horizontal, proxy.size.width * 0.08)
            }
        }
    }
}
