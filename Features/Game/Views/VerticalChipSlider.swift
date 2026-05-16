import SwiftUI

// ─── Vertical Chip Slider ─────────────────────────────────────────────────────
//
// Right-side bet picker. Replaces the slim horizontal slider that sat
// above the action row. The column lives in GameView.portraitLayout's
// overlay (NOT inside ActionBar) so it can claim the right edge of the
// screen as a dedicated vertical region, anchored just above the action
// row. ActionBar renders the [preset₁ preset₂ preset₃ Confirm] row at
// the bottom; this view renders:
//
//   ┌──────────┐
//   │  amount  │  ← retro pill, current chip amount, scale-pulses on change
//   ├──────────┤
//   │          │
//   │   ▓▓▓    │  ← track: red felt fill (tableFelt) + FeltTexture
//   │   ▓▓▓    │     overlay + tableRail border. Tick marks at BB steps,
//   │          │     emphasized every 5 BBs.
//   │   ◉     │  ← chip thumb — rotates continuously with raw drag.
//   │   ▓▓▓    │     Value snaps to BB, haptic clicks at each crossing.
//   │          │
//   └──────────┘
//
// Read/write surface: vm.raiseAmount (Int), bounded by
// [vm.minRaise, vm.maxRaise], stepped by vm.gameState?.bigBlind. The
// parent is expected to gate the entire mount on vm.showRaiseSlider —
// this view does NOT check that flag itself, it only renders.

// ─── Tunables ─────────────────────────────────────────────────────────────────
//
// Pulled out here so the canvas-iteration loop is a one-line edit. Most of
// these were eyeballed; expect 2-3 visual passes to dial in.
private let columnWidth:   CGFloat = 64    // overall width of the right-edge column
private let trackWidth:    CGFloat = 44    // visible track width (< columnWidth so the chip can overhang)
private let trackMaxHeight: CGFloat = 380  // tune in canvas — keeps drag precision sane
private let amountPillHeight: CGFloat = 30
private let chipDiameter:  CGFloat = 30
// Bumped from 14° → 15° so the full-sweep range is a clean 30°. With the
// new raw-drag rotation source (not the snapped value), the user can
// actually *see* the chip rotate continuously as they drag, so a slightly
// larger swing reads as a deliberate physical-dial cue rather than noise.
private let chipMaxRotation: Double = 15

struct VerticalChipSlider: View {
    @ObservedObject var vm: GameViewModel

    // ── Pulse state for the amount pill ──────────────────────────────
    // Briefly scales the pill 1.0 → 1.08 → 1.0 when the value changes
    // so the user feels the number tick during preset taps and during
    // drag step-crossings. Triggered by `.onChange(of: vm.raiseAmount)`.
    @State private var pulse: CGFloat = 1.0

    // ── Drag state ───────────────────────────────────────────────────
    // `dragProgress` is the *raw* finger position along the track as a
    // 0...1 value, set on .onChanged and cleared on .onEnded. While
    // non-nil, the chip thumb renders at this raw position (smooth
    // visual). The vm.raiseAmount value is snapped to the nearest BB
    // step (discrete value). On release, dragProgress goes nil and the
    // thumb springs to the snapped position. This is the "smooth
    // visual / discrete value / tactile click" model — physical dial
    // with detents.
    @State private var dragProgress: CGFloat? = nil

    // Tracks whether the user is currently dragging past the legal
    // range. We fire a single heavy "thunk" haptic on the *transition*
    // into past-boundary territory, then suppress further haptics
    // while held there. Resets when the finger returns to legal range.
    @State private var wasPastBoundary: Bool = false

    // ── Haptics ──────────────────────────────────────────────────────
    // @State (not `let`) because SwiftUI re-initializes the View struct
    // on every parent body re-render. A `private let` generator would be
    // destroyed and recreated on every recompute, never properly
    // prepare()'d before fire — which is exactly the bug shipped last
    // commit: the haptics simply did not fire. @State persists across
    // re-inits, so prepare() in .onAppear actually warms the same
    // generator instance we later .impactOccurred() on.
    @State private var lastHapticValue: Int = .min
    @State private var tickHaptic     = UIImpactFeedbackGenerator(style: .light)
    @State private var boundaryHaptic = UIImpactFeedbackGenerator(style: .heavy)

    // ── Bounds (derived) ─────────────────────────────────────────────
    private var lo:   Int { max(1, vm.minRaise) }
    private var hi:   Int { max(vm.maxRaise, lo + step) }
    private var step: Int { max(1, vm.gameState?.bigBlind ?? 10) }

    var body: some View {
        VStack(spacing: 6) {
            amountPill
            track
        }
        .frame(width: columnWidth)
        .frame(maxHeight: trackMaxHeight + amountPillHeight + 6,
               alignment: .bottom)
        .onAppear {
            tickHaptic.prepare()
            boundaryHaptic.prepare()
        }
        // Scale-pulse the amount pill whenever vm.raiseAmount changes.
        // Using a discrete `.onChange` plus a withAnimation block keeps
        // the pulse short (~120ms) — putting an .animation modifier on
        // `pulse` directly would also animate other state transitions
        // we don't want animated (e.g., initial mount).
        .onChange(of: vm.raiseAmount) { _, _ in
            withAnimation(.spring(response: 0.18, dampingFraction: 0.6)) {
                pulse = 1.08
            }
            // Settle back to 1.0 after the peak. The second spring is
            // slightly slower so the settle reads as a deliberate beat
            // rather than a snap.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) {
                    pulse = 1.0
                }
            }
        }
    }

    // ─── Amount pill ─────────────────────────────────────────────────
    // Cream capsule, ink border, hard-offset ink shadow — same comic
    // vocabulary as the +15s and preset pills so the slider reads as
    // part of the same family. Shows the current chip amount with no
    // label; "the number floats above the slider thumb" is enough
    // context. Uses `.contentTransition(.numericText())` so digit
    // rolls render as a tick rather than a fade.
    private var amountPill: some View {
        ZStack {
            Capsule()
                .fill(SPRetro.ink)
                .offset(x: 1.5, y: 2)
            Capsule()
                .fill(SPRetro.paper)
            Capsule()
                .strokeBorder(SPRetro.ink, lineWidth: 1.5)
            Text(formatChips(String(vm.raiseAmount)))
                .font(.custom("AmericanTypewriter-Bold", size: 14))
                .foregroundStyle(SPRetro.ink)
                .contentTransition(.numericText())
                .padding(.horizontal, 8)
        }
        .frame(height: amountPillHeight)
        .fixedSize(horizontal: true, vertical: false)
        .scaleEffect(pulse)
    }

    // ─── Track ───────────────────────────────────────────────────────
    // GeometryReader gives us the actual rendered height so the drag
    // math is correct even when the parent shrinks the slider below
    // `trackMaxHeight` (e.g., on iPhone SE in landscape).
    private var track: some View {
        GeometryReader { geo in
            let h        = max(1, geo.size.height)
            let span     = max(1, Double(hi - lo))
            // Snapped progress — derived from the committed value in
            // the view model. This is where the thumb sits at rest.
            let snappedProgress = CGFloat((Double(vm.raiseAmount) - Double(lo)) / span)
                .clamped(to: 0...1)
            // Render progress — raw finger position while dragging,
            // snapped position when at rest. The thumb glides smoothly
            // with the finger but the *value* (vm.raiseAmount) only
            // changes at BB step boundaries — that's where the tick
            // haptic fires. Smooth visual, discrete value, tactile click.
            let renderProgress = dragProgress ?? snappedProgress
            // Thumb Y position: 0 progress = bottom of track (low value),
            // 1.0 = top (high value). SwiftUI coords are top-left, so we
            // invert and offset the chip's center from the top by
            // `h - h*progress`.
            let thumbCenterY = h - (h * renderProgress)
            // Rotation comes from the *render* progress (raw drag), not
            // the snapped value — so the chip rotates continuously with
            // the finger, even between BB step crossings. This is the
            // visible-rotation fix.
            let rotation: Double = (Double(renderProgress) - 0.5) * 2.0 * chipMaxRotation

            ZStack(alignment: .top) {
                trackBackground
                tickMarks(in: h)
                chipThumb(rotation: rotation)
                    .offset(y: thumbCenterY - chipDiameter / 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(dragGesture(trackHeight: h))
        }
        .frame(width: columnWidth, height: trackMaxHeight)
    }

    // ─── Track background ────────────────────────────────────────────
    // Felt-rail design — the slider track reads as an extension of the
    // poker table's *rail*, not its bright playing-surface felt center:
    //   - Fill        : SPRetro.tableRail (#71201E, the darker red band
    //                   sampled from the rail surface of poker_table.png).
    //                   Earlier iteration mistakenly used the brighter
    //                   felt-center tone (#BB1A1C) which read as pink
    //                   against the rail — switched to the rail-band
    //                   color so the track matches the wood/felt frame
    //                   the eye expects to see at the table edge.
    //   - Wood grain  : `woodGrain` Canvas — ~10 vertical lines in a
    //                   slightly darker red, with deterministic per-line
    //                   wobble and stroke-width variation for a hand-drawn
    //                   feel. Sits between the fill and the FeltTexture
    //                   so the halftone speckle still reads as the
    //                   topmost surface texture (matching the rail's
    //                   actual look in poker_table.png: darker-red base +
    //                   speckle on top).
    //   - Texture     : FeltTexture() overlay (same noise/dot pattern
    //                   used on the main table felt, .blendMode(.overlay)
    //                   inside the struct itself), clipped to the rounded
    //                   rect so the texture stops at the rail edge.
    //   - Border      : SPColors.tableRail (#1F100B, the ink outline of
    //                   the rail, sampled from the same image) at 1.5pt
    //                   — color-matches the actual rail outline so the
    //                   slider reads as a miniature piece of the rail.
    //   - Drop shadow : hard ink offset, same comic vocabulary.
    private var trackBackground: some View {
        let radius: CGFloat = 12
        return ZStack {
            // Hard ink shadow — comic-page drop shadow vocabulary.
            RoundedRectangle(cornerRadius: radius)
                .fill(SPRetro.ink)
                .offset(x: 2, y: 2.5)
            // Rail-band color fill, sampled directly from the table image.
            RoundedRectangle(cornerRadius: radius)
                .fill(SPRetro.tableRail)
            // Vertical wood-grain. Clipped to the rounded rect so grain
            // stops at the rail border. Below the FeltTexture so the
            // halftone speckle remains the topmost texture layer.
            woodGrain
                .clipShape(RoundedRectangle(cornerRadius: radius))
            // Reuse the same FeltTexture used on the main table so the
            // slider visually reads as the same printed felt material.
            // Clipped to the rounded rect so texture stops cleanly at
            // the rail border instead of bleeding into the shadow.
            FeltTexture()
                .clipShape(RoundedRectangle(cornerRadius: radius))
            // Rail border — matches table rail color so the slider's
            // edge reads as "a piece of the rail" not "an ink line".
            RoundedRectangle(cornerRadius: radius)
                .strokeBorder(SPColors.tableRail, lineWidth: 1.5)
        }
        .frame(width: trackWidth)
        // Center the narrower track within the wider column so the chip
        // (which is wider than the track) overhangs symmetrically.
        .frame(maxWidth: .infinity)
    }

    // ─── Wood grain ──────────────────────────────────────────────────
    // Scattered short ink dashes — matches how the rail grain in
    // poker_table.png actually looks (near-black streaks of varied
    // length, loosely vertical, clustered not uniform). NOT continuous
    // pinstripes — an earlier iteration used 10 parallel lines in a
    // subtly-darkened red and read as "painted block with stripes"
    // instead of "piece of the rail material". This implementation
    // matches the image: short broken ink dashes scattered across the
    // track interior.
    //
    // Each dash:
    //   - Color  : SPRetro.ink at 0.55 opacity → reads as visible ink,
    //              not whisper-quiet stripes.
    //   - Length : 3–12pt, sin-seeded per index.
    //   - Angle  : within ±15° of straight vertical, sin-seeded per
    //              index → loose vertical bias with per-mark variation.
    //   - Width  : 0.5–1.2pt, sin-seeded per index → not uniform.
    //   - Pos    : low-discrepancy scatter using sqrt(2) and golden-
    //              ratio fractional sequences → naturally produces
    //              clusters and gaps without uniform spacing, all
    //              deterministic so the pattern doesn't dance on
    //              redraw.
    private var woodGrain: some View {
        let dashColor = SPRetro.ink.opacity(0.55)
        let markCount = 80
        return Canvas { ctx, size in
            // Inset from the rounded-rect corners so dashes near the
            // edge don't visually clip into the radius.
            let pad: CGFloat = 2
            let usableW = size.width  - pad * 2
            let usableH = size.height - pad * 2

            for i in 0..<markCount {
                // Low-discrepancy 2D scatter. fract(i * sqrt(2)-1) for
                // x and fract(i * (golden ratio - 1)) for y — these
                // sequences spread points pseudo-evenly across the
                // 0..1 unit square but leave natural clusters & gaps,
                // unlike a uniform grid or a true RNG.
                let xFrac = CGFloat(fmod(Double(i) * 0.41421356, 1.0))
                let yFrac = CGFloat(fmod(Double(i) * 0.61803399, 1.0))
                // Small sin-based jitter so the scatter doesn't betray
                // its low-discrepancy origin as a regular pattern.
                let xJitter = CGFloat(sin(Double(i) * 5.7)) * 1.5
                let yJitter = CGFloat(sin(Double(i) * 3.1)) * 2.0
                let baseX = pad + xFrac * usableW + xJitter
                let baseY = pad + yFrac * usableH + yJitter

                // Length 3–12pt: sin(-1..1) → +1 → /2 → 0..1 → ×9 → +3.
                let lenT  = (CGFloat(sin(Double(i) * 1.7)) + 1) / 2
                let length = 3 + lenT * 9

                // Angle: -π/2 is straight up. ±0.26 rad ≈ ±15° skew.
                let angle = -.pi / 2 + Double(sin(Double(i) * 2.3)) * 0.26

                // Stroke width 0.5–1.2pt with same sin-mapping trick.
                let widthT      = (CGFloat(sin(Double(i) * 4.1)) + 1) / 2
                let strokeWidth = 0.5 + widthT * 0.7

                // Center the dash on (baseX, baseY) so half extends
                // each direction from the seed point — keeps endpoints
                // inside the usable rect when the seed is near a wall.
                let dx = CGFloat(cos(angle)) * length / 2
                let dy = CGFloat(sin(angle)) * length / 2
                var path = Path()
                path.move(to: CGPoint(x: baseX - dx, y: baseY - dy))
                path.addLine(to: CGPoint(x: baseX + dx, y: baseY + dy))
                ctx.stroke(path,
                           with: .color(dashColor),
                           style: StrokeStyle(lineWidth: strokeWidth,
                                              lineCap: .round))
            }
        }
        // .drawingGroup() rasterizes once per layout pass instead of
        // re-running the loop on every body recompute.
        .drawingGroup()
    }

    // ─── Tick marks ──────────────────────────────────────────────────
    // Pencil-style horizontal marks at each BB increment, slightly
    // thicker every 5 BB. Hand-drawn imperfection comes from jittering
    // the X start by ±0.5pt seeded by index (deterministic so the
    // ticks don't dance on every re-render). The marks live INSIDE the
    // track on both edges so they read as scale-tick notches rather
    // than full crossbars.
    private func tickMarks(in trackHeight: CGFloat) -> some View {
        let totalSteps = max(1, (hi - lo) / step)
        // Cap tick density so we don't draw 500 ticks on big-stack
        // hands. Stride is computed so we get ~25 visible ticks max;
        // the eye reads them as a continuous scale regardless of stack.
        let visibleStride = max(1, totalSteps / 25)
        return ZStack(alignment: .top) {
            ForEach(0...totalSteps, id: \.self) { i in
                if i.isMultiple(of: visibleStride) {
                    tickMark(index: i, atY: yForStep(i, in: trackHeight),
                             emphasized: i.isMultiple(of: visibleStride * 5))
                }
            }
        }
        .frame(width: trackWidth)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func yForStep(_ stepIndex: Int, in trackHeight: CGFloat) -> CGFloat {
        let totalSteps = max(1, (hi - lo) / step)
        // Step 0 (lo) sits at the BOTTOM, max step at the TOP — same as
        // the thumb. Invert from top-down SwiftUI coords.
        let progress = CGFloat(stepIndex) / CGFloat(totalSteps)
        return trackHeight - (trackHeight * progress)
    }

    private func tickMark(index: Int, atY y: CGFloat, emphasized: Bool) -> some View {
        // Deterministic ±0.5pt jitter so the marks read as hand-drawn
        // pencil strokes rather than vector-perfect. Sin(index) gives
        // a stable per-index offset without an RNG.
        let jitter = CGFloat(sin(Double(index) * 1.7)) * 0.5
        let length: CGFloat = emphasized ? 10 : 6
        let thickness: CGFloat = emphasized ? 1.4 : 1.0
        // Tick color is the table-rail ink at 55% opacity — dark enough
        // to read clearly against the red felt without being a stark
        // black slash that would compete with the chip thumb. Matches
        // the rail border color so ticks read as "marks burned into the
        // same rail material" rather than a foreign overlay.
        let tickColor = SPColors.tableRail.opacity(0.55)
        return HStack {
            Rectangle()
                .fill(tickColor)
                .frame(width: length, height: thickness)
                .offset(x: jitter)
            Spacer()
            Rectangle()
                .fill(tickColor)
                .frame(width: length, height: thickness)
                .offset(x: -jitter)
        }
        .frame(width: trackWidth)
        .offset(y: y)
    }

    // ─── Chip thumb ──────────────────────────────────────────────────
    // A small poker chip illustration: ink-shadow disc behind a maroon
    // body, paper inner ring, and 8 stripe segments around the rim —
    // the standard comic poker-chip silhouette. Kept simple so the
    // rotation effect reads cleanly during drag (a too-detailed chip
    // would make the rotation feel jittery).
    private func chipThumb(rotation: Double) -> some View {
        ZStack {
            // Hard ink shadow
            Circle()
                .fill(SPRetro.ink)
                .frame(width: chipDiameter, height: chipDiameter)
                .offset(x: 1.5, y: 2)
            // Chip body
            Circle()
                .fill(SPRetro.maroon)
                .frame(width: chipDiameter, height: chipDiameter)
            // Ink border
            Circle()
                .strokeBorder(SPRetro.ink, lineWidth: 2)
                .frame(width: chipDiameter, height: chipDiameter)
            // Rim stripes — 8 alternating paper segments at 45° each.
            // Drawn as small rectangles around the chip's perimeter.
            ForEach(0..<8) { i in
                Rectangle()
                    .fill(i.isMultiple(of: 2) ? SPRetro.paper : SPRetro.maroon)
                    .frame(width: chipDiameter * 0.18, height: 5)
                    .overlay(Rectangle().strokeBorder(SPRetro.ink, lineWidth: 0.5))
                    .offset(y: -chipDiameter / 2 + 2.5)
                    .rotationEffect(.degrees(Double(i) * 45))
            }
            // Center disc — paper face with the chip's "denomination"
            // space. Left blank (no number) so the chip reads as a
            // generic poker chip across stake levels.
            Circle()
                .fill(SPRetro.paper)
                .frame(width: chipDiameter * 0.5, height: chipDiameter * 0.5)
                .overlay(
                    Circle().strokeBorder(SPRetro.ink, lineWidth: 1)
                )
        }
        .rotationEffect(.degrees(rotation))
        // Frame is wider than the chip itself so the gesture's hit area
        // on the thumb is a bit forgiving — without this, the chip's
        // own circle bounds make drags feel sticky at the edges.
        .frame(width: chipDiameter + 8, height: chipDiameter + 8)
        .frame(maxWidth: .infinity)
    }

    // ─── Drag gesture ────────────────────────────────────────────────
    // Smooth-visual / discrete-value / tactile-click model:
    //   - `dragProgress` (a 0...1 raw finger position) drives the thumb
    //     and rotation visually. The thumb glides smoothly with the
    //     finger between BB steps.
    //   - `vm.raiseAmount` only changes at BB-step boundaries. Every
    //     change fires the light "click" haptic, gated by
    //     `lastHapticValue` so we don't repeat-fire while the finger
    //     hovers inside a single step's region.
    //   - When the finger goes past the legal range, the thumb is
    //     clamped (no overshoot bounce — per user) and a *single* heavy
    //     "thunk" haptic fires on the transition into past-boundary
    //     territory. Held-past-boundary doesn't repeat-fire. Returning
    //     to legal range re-arms the boundary haptic.
    //   - On release, dragProgress goes nil with a spring so the thumb
    //     settles to the snapped position (the "detent" feel).
    //
    // minimumDistance: 0 → tap anywhere on the track to jump there.
    private func dragGesture(trackHeight h: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                // Raw finger position as a 0...1 progress, clamped to
                // the legal track range. This is what drives the thumb
                // and the chip rotation visually.
                let yFromBottom = max(0, min(h, h - g.location.y))
                let rawProgress = CGFloat(yFromBottom / h)
                dragProgress = rawProgress

                // Snap to nearest BB step for the *value* write.
                let span    = Double(hi - lo)
                let raw     = Double(lo) + span * Double(rawProgress)
                let steps   = (raw / Double(step)).rounded()
                let snapped = Int(steps * Double(step))
                let clamped = max(lo, min(hi, snapped))

                if clamped != vm.raiseAmount {
                    vm.raiseAmount = clamped
                    if clamped != lastHapticValue {
                        // Light "click" per BB-step crossing — this is
                        // the detent feel. .prepare() after each fire
                        // re-warms the generator for the next click.
                        tickHaptic.impactOccurred()
                        tickHaptic.prepare()
                        lastHapticValue = clamped
                    }
                }

                // Boundary detection — fire heavy haptic ONCE on the
                // transition into past-boundary territory. The finger
                // is "past" when the raw unclamped y is outside
                // [0, h]. No visual overshoot — the user explicitly
                // asked for resistance/clamp, not bounce.
                let unclampedY = h - g.location.y
                let isPast     = unclampedY > h || unclampedY < 0
                if isPast && !wasPastBoundary {
                    boundaryHaptic.impactOccurred()
                    boundaryHaptic.prepare()
                    wasPastBoundary = true
                } else if !isPast && wasPastBoundary {
                    // Re-arm so the next boundary press fires again.
                    wasPastBoundary = false
                }
            }
            .onEnded { _ in
                // Spring the thumb from its raw position to the snapped
                // position. This is the "detent settle" — visually
                // confirms which value the user actually selected.
                withAnimation(.spring(response: 0.25,
                                      dampingFraction: 0.75)) {
                    dragProgress = nil
                }
                wasPastBoundary = false
            }
    }
}

// Tiny helper so the progress math stays readable. Equivalent to clamping
// against a closed range without pulling in numeric protocols. Moved here
// from ActionBar.swift along with the slider that used it — SlimRaiseSlider
// was the only consumer.
fileprivate extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
