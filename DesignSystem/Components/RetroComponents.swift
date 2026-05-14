import SwiftUI

// ─── Retro Comic Components ───────────────────────────────────────────────────
//
// Reusable visual primitives for the vintage-comic redesign. Kept private to
// this file's namespace as plain SwiftUI views/modifiers rather than wrapped in
// an enum so call sites stay readable (`AgedPaperBackground()` not
// `SPRetro.Bg.aged()`).

// ─── Aged Paper Background ────────────────────────────────────────────────────
//
// Cream base + a subtle radial vignette so the page reads as a slightly worn
// printed leaf instead of a flat color fill. The vignette is opacity-only on
// `paperEdge` so it never clips into pure black around the corners — the goal
// is "Sunday-comics page that has been folded once", not "spotlit poster".

struct AgedPaperBackground: View {
    var body: some View {
        ZStack {
            SPRetro.paper
            // Radial darken at the corners. Center stays bright cream, the
            // outer 30% picks up a soft warm shadow that suggests page wear.
            RadialGradient(
                colors: [Color.clear, SPRetro.paperEdge.opacity(0.45)],
                center: .center,
                startRadius: 120,
                endRadius: 520
            )
            .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }
}

// ─── Halftone / Ben-Day Dot Overlay ──────────────────────────────────────────
//
// Procedural dot grid drawn with Canvas. Used as a semi-transparent overlay on
// panels and the page background to give the printed-comic feel. We draw dots
// only — no shapes inside — so the overlay can sit at low opacity (8–18%) and
// still read as halftone instead of a pattern.
//
// `density` controls how many dots fit horizontally; `tint` is usually
// SPRetro.ink at low opacity for the page, or SPRetro.maroon/popBlue for a
// "Ben-Day printed in color" feel on accent panels.

struct HalftoneOverlay: View {
    var density: Int = 36
    var tint: Color = SPRetro.ink
    var opacity: Double = 0.12

    var body: some View {
        Canvas { ctx, size in
            // Spacing derives from density so the overlay scales with the
            // container — a tiny pill and a full-screen background both look
            // "halftoned at the same press".
            let spacing = size.width / CGFloat(density)
            let radius = max(0.6, spacing * 0.18)
            // Stagger every other row by half a column for the diagonal feel
            // characteristic of offset-print Ben-Day dots.
            var y = spacing / 2
            var row = 0
            while y < size.height + spacing {
                let xOffset = row.isMultiple(of: 2) ? 0 : spacing / 2
                var x = spacing / 2 + xOffset
                while x < size.width + spacing {
                    let rect = CGRect(x: x - radius, y: y - radius,
                                      width: radius * 2, height: radius * 2)
                    ctx.fill(Path(ellipseIn: rect), with: .color(tint))
                    x += spacing
                }
                y += spacing
                row += 1
            }
        }
        .opacity(opacity)
        .allowsHitTesting(false)
    }
}

// ─── Comic Panel Modifier ─────────────────────────────────────────────────────
//
// Thick black border + a small offset "hard ink" shadow. The shadow is a SOLID
// black rectangle behind the panel, not a blurred SwiftUI shadow — comic
// panels in the 60s had no blur; the offset duplicate is what gives the
// printed feel. Apply via `.comicPanel()`.

struct ComicPanelModifier: ViewModifier {
    var fill: Color = SPRetro.paper
    var corner: CGFloat = 8
    var lineWidth: CGFloat = 3
    var shadowOffset: CGFloat = 4

    func body(content: Content) -> some View {
        content
            .background(fill)
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(SPRetro.ink, lineWidth: lineWidth)
            )
            .background(
                // Hard-edge solid shadow offset down-right. Sits BEHIND the
                // panel so the border is the visible stroke and the shadow
                // peeks out at the bottom + trailing edge.
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(SPRetro.ink)
                    .offset(x: shadowOffset, y: shadowOffset)
            )
    }
}

extension View {
    func comicPanel(fill: Color = SPRetro.paper,
                    corner: CGFloat = 8,
                    lineWidth: CGFloat = 3,
                    shadowOffset: CGFloat = 4) -> some View {
        modifier(ComicPanelModifier(fill: fill, corner: corner,
                                    lineWidth: lineWidth,
                                    shadowOffset: shadowOffset))
    }
}

// ─── Speech Bubble ────────────────────────────────────────────────────────────
//
// Rounded rect + a small downward-pointing tail on the lower-left. Used for
// section headers and labels so the page reads as comic dialogue, not as a UI
// form. Tail position is fixed because every consumer (so far) wants the
// "speaker is below-left" arrangement.

struct SpeechBubbleShape: Shape {
    var corner: CGFloat = 14
    var tailWidth: CGFloat = 16
    var tailHeight: CGFloat = 10

    func path(in rect: CGRect) -> Path {
        let bubble = CGRect(x: rect.minX,
                            y: rect.minY,
                            width: rect.width,
                            height: rect.height - tailHeight)
        var path = Path(roundedRect: bubble, cornerRadius: corner, style: .continuous)
        // Tail triangle hanging from the lower-left.
        let tailStartX = bubble.minX + corner + 8
        path.move(to: CGPoint(x: tailStartX, y: bubble.maxY))
        path.addLine(to: CGPoint(x: tailStartX - 4, y: rect.maxY))
        path.addLine(to: CGPoint(x: tailStartX + tailWidth, y: bubble.maxY))
        path.closeSubpath()
        return path
    }
}

struct SpeechBubble<Content: View>: View {
    var fill: Color = SPRetro.paper
    var lineWidth: CGFloat = 2.5
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .padding(.bottom, 10)               // room for the tail
            .background(SpeechBubbleShape().fill(fill))
            .overlay(SpeechBubbleShape().stroke(SPRetro.ink, lineWidth: lineWidth))
    }
}

// ─── Burst (POW! / BIFF! / ZAP!) ─────────────────────────────────────────────
//
// Classic spiky star shape. Number of points controls the burst's "energy" —
// 12 reads as a sharp action burst, 8 reads more like a callout/sticker.
// `innerRatio` is how deep the inner notches cut toward the center (smaller =
// pointier). The shape draws around `rect`'s center using the full minimum
// dimension as the radius.

struct BurstShape: Shape {
    var points: Int = 12
    var innerRatio: CGFloat = 0.72

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outerR = min(rect.width, rect.height) / 2
        let innerR = outerR * innerRatio
        let step = Double.pi * 2 / Double(points * 2)
        // Rotate so a point sits at the top — burst doesn't look right with a
        // flat edge facing the viewer.
        var angle = -Double.pi / 2
        for i in 0..<(points * 2) {
            let r = i.isMultiple(of: 2) ? outerR : innerR
            let pt = CGPoint(
                x: center.x + CGFloat(cos(angle)) * r,
                y: center.y + CGFloat(sin(angle)) * r
            )
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
            angle += step
        }
        path.closeSubpath()
        return path
    }
}

struct ComicBurst: View {
    let text: String
    var fill: Color = SPRetro.mustard
    var textColor: Color = SPRetro.ink
    var size: CGFloat = 64
    var rotation: Double = -8

    var body: some View {
        ZStack {
            BurstShape()
                .fill(fill)
            BurstShape()
                .stroke(SPRetro.ink, lineWidth: 2.5)
            Text(text)
                .font(SPRetroFonts.display(size * 0.34))
                .foregroundStyle(textColor)
                // Slight counter-rotate so the text stays readable while the
                // burst itself tilts — classic comic-cover treatment.
                .rotationEffect(.degrees(-rotation * 0.4))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .padding(.horizontal, size * 0.18)
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(rotation))
    }
}

// ─── Retro Chip Pill ──────────────────────────────────────────────────────────
//
// Replaces the dark-glass capsule in the lobby header with a comic-page
// equivalent: mustard fill, ink border, hard-shadow offset. Composes the
// existing `PokerChip` token-coin on the left so the brand chip stays the
// visual anchor.

struct RetroChipPill: View {
    let amount: String
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                PokerChip(
                    text: "$",
                    tint: SPRetro.mustard,
                    textColor: SPRetro.ink,
                    size: 24
                )
                Text(amount)
                    .font(SPRetroFonts.headline(15))
                    .foregroundStyle(SPRetro.ink)
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(SPRetro.maroon)
            }
            .padding(.leading, 6)
            .padding(.trailing, 10)
            .padding(.vertical, 5)
            .comicPanel(fill: SPRetro.paperShade, corner: 22,
                        lineWidth: 2, shadowOffset: 2)
        }
        .buttonStyle(.plain)
    }
}
