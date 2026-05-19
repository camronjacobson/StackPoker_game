import SwiftUI

// ─── Avatar Frame Renderer ────────────────────────────────────────────────────
//
// Phase 4b sibling to CardBackRenderer. Phase 4 cosmetics ship without real
// art assets — that comes in Phase 5 (artist-delivered .pdf / .png variants).
// For the vertical slice we render every avatar-frame variant procedurally
// from primitives so equipping is observable across the 8 catalog entries.
//
// Render contract: the frame is an OVERLAY ring that sits OUTSIDE the avatar
// disc. Total footprint = avatar diameter + 2×thickness. This is deliberate —
// AvatarView already owns its ink hairline / 2.5pt "selection" border, and
// TargetSeatView already owns the isMyTurn-thickens / winnerPulse-glow
// treatments on its inline avatar Circle. We don't want a cosmetic to
// interact with those state borders. Stamping the frame outside the disc
// keeps cosmetic + state decoration fully orthogonal: someone with the gold
// frame on their turn reads as "gold frame + active turn", not "gold frame
// replaced my turn indicator".
//
// Decoration sizing (dot/star/spike) scales off `diameter` so the same id
// reads at 40pt (lobby tile) through 100pt (profile header). Decorations sit
// ON the ring at the four cardinal points — visible at every size without
// requiring small/large asset swaps.
//
// Mythic stays STATIC for v1 (AngularGradient, no TimelineView). The static
// gradient + spikes + glow already reads as "elite tier"; animating across
// the table's opponent cluster + every AvatarView call site is a perf risk
// best tested on real devices, not simulator. Animation is a follow-up.
// See NEXT_STEPS / TECH_DEBT for the rotation+particle polish pass.

enum AvatarFrameRenderer {

    /// Returns a procedural frame ring for the given id, sized to overlay an
    /// avatar of `diameter` pts. Callers (AvatarView, TargetSeatView) apply
    /// this as an `.overlay` on top of the avatar disc — so the ring sits
    /// outside the disc and grows the visual footprint by 2×thickness.
    /// EmptyView for unknown ids; callers should gate with `supports(_:)`.
    @ViewBuilder
    static func view(for id: CosmeticID?, diameter: CGFloat) -> some View {
        switch id {
        case "avatar_frame_bronze":           bronze(diameter: diameter)
        case "avatar_frame_silver":           silver(diameter: diameter)
        case "avatar_frame_gold":             gold(diameter: diameter)
        case "avatar_frame_platinum":         platinum(diameter: diameter)
        case "avatar_frame_diamond":          diamond(diameter: diameter)
        case "avatar_frame_royal":            royal(diameter: diameter)
        case "avatar_frame_champion":         champion(diameter: diameter)
        case "avatar_frame_mythic_inferno":   mythicInferno(diameter: diameter)
        default:
            // Sentinel — AvatarView / TargetSeatView check `supports(_:)`
            // before calling this, so the default branch is only ever hit
            // if a future caller forgets to gate. EmptyView keeps things
            // graceful (renders nothing, doesn't crash) so the avatar
            // falls through to its existing default rendering.
            EmptyView()
        }
    }

    /// Cheap "do we render this id?" check. Callers use this to decide
    /// between overlay and no-op without round-tripping through view(for:).
    static func supports(_ id: CosmeticID?) -> Bool {
        guard let id else { return false }
        switch id {
        case "avatar_frame_bronze",
             "avatar_frame_silver",
             "avatar_frame_gold",
             "avatar_frame_platinum",
             "avatar_frame_diamond",
             "avatar_frame_royal",
             "avatar_frame_champion",
             "avatar_frame_mythic_inferno":
            return true
        default:
            return false
        }
    }

    // ── Palette ──────────────────────────────────────────────────────────────
    // Pulled from the SPRetro family where possible (mustard for champion,
    // popRed/etc. for mythic) so frames feel in-family with the rest of the
    // page. Where the rarity needs a distinct hue (bronze, silver, platinum,
    // royal purple, diamond cyan) we hardcode — these are intentional
    // "outside the retro palette" accents that signal premium.

    private static let bronzeC    = Color(red: 0.66, green: 0.42, blue: 0.17)
    private static let silverC    = Color(red: 0.72, green: 0.72, blue: 0.75)
    private static let goldC      = Color(red: 0.88, green: 0.66, blue: 0.18)
    private static let platinumC  = Color(red: 0.61, green: 0.64, blue: 0.69)
    private static let diamondC   = Color(red: 0.36, green: 0.75, blue: 0.87)
    private static let royalC     = Color(red: 0.42, green: 0.25, blue: 0.63)
    private static let championC  = Color(red: 0.90, green: 0.71, blue: 0.23)

    // ── Common (thin solid, no decoration) ───────────────────────────────────

    private static func bronze(diameter: CGFloat) -> some View {
        SolidRing(diameter: diameter, thickness: 1.5, color: bronzeC)
    }

    private static func silver(diameter: CGFloat) -> some View {
        SolidRing(diameter: diameter, thickness: 1.5, color: silverC)
    }

    // ── Rare (medium, decoration starts here) ────────────────────────────────

    private static func gold(diameter: CGFloat) -> some View {
        // Solid gold ring + 4 cardinal dots. Dots sized as a fraction of the
        // ring diameter so they read at lobby (40pt) and profile (100pt).
        ZStack {
            SolidRing(diameter: diameter, thickness: 2.5, color: goldC)
            CardinalDots(ringDiameter: diameter + 2.5,
                         dotSize: max(3, diameter * 0.07),
                         color: goldC)
        }
    }

    private static func platinum(diameter: CGFloat) -> some View {
        // Double concentric ring — outer 2.5pt + inner hairline 1pt with a
        // 2pt gap between them. The double-line reads as "premium / engraved"
        // at every size and is visually distinct from gold's dot-decorated
        // single ring at the same rarity tier.
        ZStack {
            SolidRing(diameter: diameter, thickness: 2.5, color: platinumC)
            SolidRing(diameter: diameter + 6, thickness: 1.0,
                      color: platinumC.opacity(0.75))
        }
    }

    // ── Epic (thicker, distinct ring style + decoration) ─────────────────────

    private static func diamond(diameter: CGFloat) -> some View {
        // Dashed cyan ring — dashed pattern instantly signals "different tier"
        // from the solid rings below. 4 cardinal dots reinforce the cyan tint
        // when the dash gap happens to land on a cardinal.
        ZStack {
            Circle()
                .strokeBorder(diamondC,
                              style: StrokeStyle(lineWidth: 3.5,
                                                 dash: [6, 3]))
                .frame(width: diameter + 7, height: diameter + 7)
            CardinalDots(ringDiameter: diameter + 7,
                         dotSize: max(3, diameter * 0.08),
                         color: diamondC)
        }
    }

    private static func royal(diameter: CGFloat) -> some View {
        // Solid royal-purple ring + 4 cardinal stars. Stars (vs gold's dots)
        // give epic-tier a distinct decorative vocabulary — "royal" reads as
        // ceremonial / heraldic at any size.
        ZStack {
            SolidRing(diameter: diameter, thickness: 3.5, color: royalC)
            CardinalStars(ringDiameter: diameter + 3.5,
                          starSize: max(5, diameter * 0.11),
                          color: royalC)
        }
    }

    // ── Legendary (thick + soft glow) ────────────────────────────────────────

    private static func champion(diameter: CGFloat) -> some View {
        // Thick mustard ring + 4 cardinal dots + outer halo glow. The glow is
        // a separate, larger blurred Circle stroke at low opacity — reads as
        // a soft "trophy" glow at the table without competing with the
        // active-turn / winnerPulse decorations on TargetSeatView.
        ZStack {
            // Outer glow halo. Separate circle so we can blur it without
            // blurring the crisp ring itself.
            Circle()
                .strokeBorder(championC.opacity(0.45), lineWidth: 6)
                .frame(width: diameter + 10, height: diameter + 10)
                .blur(radius: 4)

            SolidRing(diameter: diameter, thickness: 4, color: championC)
            CardinalDots(ringDiameter: diameter + 4,
                         dotSize: max(4, diameter * 0.09),
                         color: championC)
        }
    }

    // ── Mythic (gradient + spikes + outer glow) ──────────────────────────────

    private static func mythicInferno(diameter: CGFloat) -> some View {
        // AngularGradient flame palette (red → orange → yellow → red) painted
        // around the ring, plus 4 cardinal spike triangles, plus a soft red
        // glow halo. Static v1 — animation is a follow-up polish pass once
        // category landing is validated (see TECH_DEBT.md).
        let flame = AngularGradient(
            gradient: Gradient(colors: [
                Color(red: 0.78, green: 0.16, blue: 0.10),
                Color(red: 0.95, green: 0.50, blue: 0.16),
                Color(red: 0.98, green: 0.83, blue: 0.27),
                Color(red: 0.95, green: 0.50, blue: 0.16),
                Color(red: 0.78, green: 0.16, blue: 0.10),
            ]),
            center: .center
        )
        return ZStack {
            // Outer flame glow — larger blurred halo behind the gradient
            // ring. Red-shifted so the glow reads as "heat" rather than
            // matching the gold/yellow tint of champion.
            Circle()
                .strokeBorder(Color(red: 0.95, green: 0.30, blue: 0.10)
                                  .opacity(0.50),
                              lineWidth: 8)
                .frame(width: diameter + 12, height: diameter + 12)
                .blur(radius: 6)

            // Gradient flame ring.
            Circle()
                .strokeBorder(flame, lineWidth: 4.5)
                .frame(width: diameter + 4.5, height: diameter + 4.5)

            // 4 cardinal flame spikes — small filled triangles pointing
            // outward. Spike length scales with diameter so the silhouette
            // reads at small sizes too.
            CardinalSpikes(ringDiameter: diameter + 4.5,
                           spikeSize: max(5, diameter * 0.13),
                           color: Color(red: 0.98, green: 0.66, blue: 0.20))
        }
    }
}

// ─── Primitives ───────────────────────────────────────────────────────────────
//
// Small ring + decoration helpers. Kept inside this file (file-private) since
// they're tightly coupled to the frame catalog above — extracting them to a
// shared module would invite over-generalization for a vertical-slice
// renderer that gets replaced wholesale in Phase 5.

private struct SolidRing: View {
    let diameter:  CGFloat
    let thickness: CGFloat
    let color:     Color

    var body: some View {
        Circle()
            .strokeBorder(color, lineWidth: thickness)
            // Outer-edge anchor: ring footprint = avatar diameter + thickness.
            // strokeBorder centers the line on the path, so framing at
            // `diameter + thickness` puts half the line outside the avatar
            // disc and half on its edge — visually it looks like the frame
            // sits OUTSIDE the avatar without quite floating off it.
            .frame(width: diameter + thickness, height: diameter + thickness)
    }
}

/// 4 dots positioned at N/E/S/W on a circle of `ringDiameter`. Cardinals
/// (vs 6/8 evenly spaced) read cleanest at small sizes — at 40pt lobby tile
/// scale, 6+ decoration points blur into noise; 4 stays crisp.
private struct CardinalDots: View {
    let ringDiameter: CGFloat
    let dotSize:      CGFloat
    let color:        Color

    var body: some View {
        ZStack {
            ForEach(0..<4, id: \.self) { i in
                Circle()
                    .fill(color)
                    .frame(width: dotSize, height: dotSize)
                    .offset(y: -ringDiameter / 2)
                    .rotationEffect(.degrees(Double(i) * 90))
            }
        }
    }
}

/// 4 filled stars at N/E/S/W. SF Symbols "star.fill" — keeps render cost
/// low (no custom Path) and inherits the same retina crispness as Apple's
/// own glyphs at every size.
private struct CardinalStars: View {
    let ringDiameter: CGFloat
    let starSize:     CGFloat
    let color:        Color

    var body: some View {
        ZStack {
            ForEach(0..<4, id: \.self) { i in
                Image(systemName: "star.fill")
                    .font(.system(size: starSize, weight: .bold))
                    .foregroundStyle(color)
                    .offset(y: -ringDiameter / 2)
                    .rotationEffect(.degrees(Double(i) * 90))
            }
        }
    }
}

/// 4 outward-pointing triangle spikes at N/E/S/W. Custom Path because
/// SF Symbols don't have a "spike pointing outward at known angle" glyph
/// that scales without distortion. Each spike is rotated by its cardinal
/// then placed at the ring edge.
private struct CardinalSpikes: View {
    let ringDiameter: CGFloat
    let spikeSize:    CGFloat
    let color:        Color

    var body: some View {
        ZStack {
            ForEach(0..<4, id: \.self) { i in
                Triangle()
                    .fill(color)
                    .frame(width: spikeSize, height: spikeSize)
                    .offset(y: -ringDiameter / 2 - spikeSize / 2)
                    .rotationEffect(.degrees(Double(i) * 90))
            }
        }
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to:    CGPoint(x: rect.midX, y: rect.minY))   // top point
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))   // bottom right
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))   // bottom left
        p.closeSubpath()
        return p
    }
}

// ─── Preview ──────────────────────────────────────────────────────────────────
//
// All 8 catalog ids rendered at three sizes — lobby (40), profile (80), table
// hero (56) — so canvas verifies that decoration scaling reads correctly at
// every site without simulator boot. The wrapped Circle is a stand-in for
// AvatarView's paper-fill + emoji so each preview looks like the real
// render context.

#Preview("All frames × 3 sizes") {
    let ids: [String] = [
        "avatar_frame_bronze",
        "avatar_frame_silver",
        "avatar_frame_gold",
        "avatar_frame_platinum",
        "avatar_frame_diamond",
        "avatar_frame_royal",
        "avatar_frame_champion",
        "avatar_frame_mythic_inferno",
    ]
    return ScrollView {
        VStack(spacing: 24) {
            ForEach(ids, id: \.self) { id in
                HStack(spacing: 28) {
                    ForEach([CGFloat(40), 56, 80], id: \.self) { d in
                        ZStack {
                            Circle()
                                .fill(Color(red: 0.96, green: 0.93, blue: 0.84))
                                .overlay(Circle().strokeBorder(.black, lineWidth: 1))
                                .frame(width: d, height: d)
                                .overlay(Text("🦊").font(.system(size: d * 0.5)))
                            AvatarFrameRenderer.view(for: id, diameter: d)
                        }
                        .frame(width: d + 24, height: d + 24)
                    }
                    Text(id.replacingOccurrences(of: "avatar_frame_", with: ""))
                        .font(.system(size: 11, design: .monospaced))
                }
            }
        }
        .padding()
    }
}
