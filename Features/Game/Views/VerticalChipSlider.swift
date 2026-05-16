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
//   │   ▒▒▒    │  ← track (cream fill, ink border), tick marks inside
//   │   ▒▒▒    │     halftone dot texture, drag thumb is a small chip
//   │          │
//   │   ◉     │  ← chip thumb (rotates while dragging)
//   │   ▒▒▒    │
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
private let chipMaxRotation: Double = 14   // degrees swept across full track length
private let boundaryOvershoot: CGFloat = 7 // visual bounce when drag tries to exceed lo/hi

struct VerticalChipSlider: View {
    @ObservedObject var vm: GameViewModel

    // ── Pulse state for the amount pill ──────────────────────────────
    // Briefly scales the pill 1.0 → 1.08 → 1.0 when the value changes
    // so the user feels the number tick during preset taps and during
    // drag step-crossings. Triggered by `.onChange(of: vm.raiseAmount)`.
    @State private var pulse: CGFloat = 1.0

    // ── Drag state ───────────────────────────────────────────────────
    // `bounce` is the visual-only overshoot applied to the thumb when the
    // user tries to drag past the legal range. It's never written into
    // vm.raiseAmount — only used for offset on render. We snap it back
    // to 0 in onEnded with an explicit spring.
    @State private var bounce: CGFloat = 0

    // ── Haptics ──────────────────────────────────────────────────────
    // Two generators: light impact for per-BB tick crossings (fired in
    // .onChanged), heavy impact for the boundary bump (fired once when
    // we first try to exceed lo or hi). Both prepared in .onAppear to
    // reduce first-fire latency from ~120ms → ~10ms.
    @State private var lastHapticValue: Int = .min
    private let tickHaptic    = UIImpactFeedbackGenerator(style: .light)
    private let boundaryHaptic = UIImpactFeedbackGenerator(style: .heavy)

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
            let progress = CGFloat((Double(vm.raiseAmount) - Double(lo)) / span)
                .clamped(to: 0...1)
            // Thumb Y position: 0 progress = bottom of track (low value),
            // 1.0 = top (high value). SwiftUI coords are top-left, so we
            // invert and offset the chip's center from the top by
            // `h - h*progress`. `bounce` is added so visual overshoot
            // sits on top of the legal-range position.
            let thumbCenterY = h - (h * progress) + bounce
            let rotation: Double = (Double(progress) - 0.5) * 2.0 * chipMaxRotation

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
    // Cream fill + ink stroke, rounded rect (not capsule — the corners
    // should read as "page rectangle with rounded corners" not "pill",
    // distinct from the action buttons below). Halftone dot texture is
    // a static SwiftUI Canvas overlay at very low opacity — picks up
    // the same comic-print idiom the lobby cream background uses.
    private var trackBackground: some View {
        let radius: CGFloat = 12
        return ZStack {
            RoundedRectangle(cornerRadius: radius)
                .fill(SPRetro.ink)
                .offset(x: 2, y: 2.5)
            RoundedRectangle(cornerRadius: radius)
                .fill(SPRetro.paper)
            // Halftone dots — small ink circles at low opacity. The
            // pattern is a 6pt grid offset on alternating rows for the
            // classic comic shading look. Clipped to the rounded rect
            // so dots near the border don't bleed past the ink stroke.
            Canvas { ctx, size in
                let spacing: CGFloat = 6
                let dotR:    CGFloat = 0.8
                let rows = Int(size.height / spacing) + 1
                let cols = Int(size.width  / spacing) + 1
                for row in 0..<rows {
                    let xOffset = row.isMultiple(of: 2) ? 0 : spacing / 2
                    for col in 0..<cols {
                        let x = CGFloat(col) * spacing + xOffset
                        let y = CGFloat(row) * spacing
                        let rect = CGRect(x: x - dotR, y: y - dotR,
                                          width: dotR * 2, height: dotR * 2)
                        ctx.fill(Path(ellipseIn: rect),
                                 with: .color(SPRetro.ink.opacity(0.12)))
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: radius))
            RoundedRectangle(cornerRadius: radius)
                .strokeBorder(SPRetro.ink, lineWidth: 1.8)
        }
        .frame(width: trackWidth)
        // Center the narrower track within the wider column so the chip
        // (which is wider than the track) overhangs symmetrically.
        .frame(maxWidth: .infinity)
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
        return HStack {
            Rectangle()
                .fill(SPRetro.ink.opacity(0.7))
                .frame(width: length, height: thickness)
                .offset(x: jitter)
            Spacer()
            Rectangle()
                .fill(SPRetro.ink.opacity(0.7))
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
    // minimumDistance: 0 → tap anywhere on the track to jump the thumb
    // to that position. Subsequent drag updates write through to
    // vm.raiseAmount, snapped to `step` and clamped to [lo, hi]. Per-BB
    // crossings fire a light haptic; boundary attempts fire a heavy
    // haptic ONCE per attempt (gated by lastHapticValue), so holding
    // the finger past the boundary doesn't repeat-fire.
    private func dragGesture(trackHeight h: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                let yFromBottom = max(0, min(h, h - g.location.y))
                let p           = Double(yFromBottom / h)
                let span        = Double(hi - lo)
                let raw         = Double(lo) + span * p
                let steps       = (raw / Double(step)).rounded()
                let snapped     = Int(steps * Double(step))
                // Detect attempts to exceed range: location is past
                // the visual top/bottom of the track. We compute the
                // unclamped value separately so we know whether to
                // play the boundary bump.
                let unclampedY  = h - g.location.y
                let pastTop     = unclampedY > h
                let pastBottom  = unclampedY < 0
                let clamped     = max(lo, min(hi, snapped))

                if clamped != vm.raiseAmount {
                    vm.raiseAmount = clamped
                    if clamped != lastHapticValue {
                        tickHaptic.impactOccurred()
                        tickHaptic.prepare()
                        lastHapticValue = clamped
                    }
                }
                // Boundary bump: visual overshoot + heavy haptic.
                // Gate haptic on transition (only fire once per
                // boundary press) by checking if we're at the
                // boundary value AND were already there last tick.
                if pastTop && clamped == hi {
                    if bounce > -boundaryOvershoot {
                        withAnimation(.spring(response: 0.15,
                                              dampingFraction: 0.6)) {
                            bounce = -boundaryOvershoot
                        }
                        boundaryHaptic.impactOccurred()
                        boundaryHaptic.prepare()
                    }
                } else if pastBottom && clamped == lo {
                    if bounce < boundaryOvershoot {
                        withAnimation(.spring(response: 0.15,
                                              dampingFraction: 0.6)) {
                            bounce = boundaryOvershoot
                        }
                        boundaryHaptic.impactOccurred()
                        boundaryHaptic.prepare()
                    }
                }
            }
            .onEnded { _ in
                // Always settle bounce back to 0 on release. Using
                // a separate spring (not the default) so the snap
                // reads as deliberate.
                withAnimation(.spring(response: 0.3,
                                      dampingFraction: 0.55)) {
                    bounce = 0
                }
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
