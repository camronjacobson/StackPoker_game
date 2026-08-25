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
    ///
    /// `compact` only affects PNG-backed frames — procedural frames ignore
    /// it (they have no wisps zone; their geometry is exact). Pass
    /// `compact: true` at surfaces with a high-contrast (dark) background
    /// where the avatar disc silhouette is sharp and any sliver between
    /// the disc edge and the PNG ornament reads as a perceptible gap.
    /// See the comment block above the PNG section for full rationale.
    @ViewBuilder
    static func view(for id: CosmeticID?,
                     diameter: CGFloat,
                     compact: Bool = false) -> some View {
        switch id {
        case "avatar_frame_bronze":           bronze(diameter: diameter)
        case "avatar_frame_silver":           silver(diameter: diameter)
        case "avatar_frame_gold":             goldPNG(diameter: diameter, compact: compact)
        case "avatar_frame_platinum":         platinum(diameter: diameter)
        case "avatar_frame_diamond":          diamond(diameter: diameter)
        case "avatar_frame_royal":            royal(diameter: diameter)
        case "avatar_frame_champion":         champion(diameter: diameter)
        case "avatar_frame_mythic_inferno":   mythicInfernoPNG(diameter: diameter, compact: compact)
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

    /// Returns true for ids whose `view(for:diameter:)` renders a PNG asset
    /// that extends well past the avatar disc (~2.1–2.3× diameter). Layout
    /// containers with a fixed footprint (store preview cells, locker tiles)
    /// use this to budget space — procedural frames fit comfortably at
    /// avatar+~10pt, but PNG frames need ~2.3× the avatar diameter of
    /// headroom or their outer spikes clip at the container edge.
    /// Update this list every time a procedural frame is migrated to a PNG.
    static func isPNGBacked(_ id: CosmeticID?) -> Bool {
        switch id {
        case "avatar_frame_gold",
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

    // ─── PNG-backed frame section ─────────────────────────────────────────────
    //
    // Why two ratios exist per PNG (regular + compact)
    // ------------------------------------------------
    // Every hand-illustrated frame PNG has a "wisps zone" — a band of sparse
    // pigment (decorative tendrils, hairline glints, soft fades) that
    // extends inward from the dense ring body toward the avatar disc. The
    // alpha-channel scan picks up that band as the "inner edge" of the
    // image, but the user's eye perceives the DENSE ring body as the inner
    // edge of the frame. The wisps zone reads as ornament on a cream
    // background (low contrast → wisps blend with page) but reads as a
    // visible gap on a dark background (high contrast → cream disc silhouette
    // is sharp, wisps look like sparse decoration floating in empty space).
    //
    // We size with two ratios:
    //   • `regularRatio` — anchored to the hard-pigment first-pixel point
    //     (the wisp edge). Math gives pixel-perfect or sub-pixel overlap at
    //     the disc edge. Right answer on cream backgrounds where the wisps
    //     read as ornament, not gap.
    //   • `compactRatio` — anchored deeper into the frame, so the dense
    //     ring body itself sits ~1.3pt INSIDE the avatar disc edge at small
    //     sizes. This pushes the ornament physically onto the disc,
    //     eliminating any perceptible cream-on-dark gap. Right answer on
    //     felt-green or similarly high-contrast backgrounds.
    //
    // When to pass `compact: true`
    // ----------------------------
    // Pass at surfaces where the avatar disc has a high-contrast background
    // making its silhouette sharp. Today that's only `TargetSeatView` (poker
    // felt). Lobby header, profile header, store preview, locker tile, etc.
    // all sit on cream paper and stay default (`compact: false`).
    //
    // Future spectator/popup surfaces that overlay the felt should also use
    // `compact: true`. When friend-row cosmetic plumbing lands (see
    // TECH_DEBT) the friend rows themselves stay default — they sit on
    // cream paper.
    //
    // How to measure both ratios for a new PNG
    // -----------------------------------------
    // 1. Run an alpha-channel scan from canvas center outward in all four
    //    cardinal directions.
    // 2. `regularRatio` = average of the E/W (side) measurements where alpha
    //    first exceeds 200 (hard pigment). Side avg is preferred over global
    //    avg because asymmetric frames (bottom tips, top spikes) skew the
    //    global avg and the user's eye anchors to the sides.
    // 3. `compactRatio` = side avg from a DENSE pigment scan (window of ~16
    //    consecutive pixels with ≥60% alpha>128), then divide by ~0.93 to
    //    push the dense body ~1.3pt inside the disc at D=40. Equivalent:
    //    `dense_sides / 0.93`. Verify on a felt-background mockup.
    //
    // Both ratios MUST be declared per-PNG below; the pngFrame helper picks
    // the right one based on the `compact` flag passed by the caller.
    // -----------------------------------------------------------------------

    /// Shared helper for PNG-backed frames. Every PNG renders as a
    /// `.resizable().fit` Image sized so the alpha-scan inner-hole position
    /// equals (or just-overlaps) the avatar disc edge. Picks `compactInner`
    /// when the caller is rendering against a high-contrast background.
    @ViewBuilder
    private static func pngFrame(asset: String,
                                 innerRatio: CGFloat,
                                 compactInnerRatio: CGFloat,
                                 diameter: CGFloat,
                                 compact: Bool) -> some View {
        let r = compact ? compactInnerRatio : innerRatio
        let canvas = diameter / r
        Image(asset)
            .renderingMode(.original)       // preserve PNG colors; don't tint
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: canvas, height: canvas)
    }

    // Gold (Rare, PNG-backed)
    //
    // regularRatio = 0.485 — sides hard-pigment avg from alpha-scan
    // (E=0.4824, W=0.4883). Sub-pixel overlap with disc edge at the wisps
    // zone; perfect on cream paper.
    //
    // compactRatio = 0.500 — middle ground between "wisps-fuzzy" at 0.485
    // (visible cream sliver on felt) and "clipping disc" at 0.525 (dense
    // ring body cuts into the avatar disc edge). 0.500 lands the PNG
    // inner edge at ~D-1pt at D=40 — disc edge meets PNG inner edge
    // cleanly without geometric clip. A small static gap may remain at
    // table size on felt; that's accepted as the cost of not clipping
    // the avatar. The deeper fix is a unified view hierarchy where the
    // disc and frame animate together (winner pulse / turn indicator
    // currently desync because they live in different view trees) —
    // tracked separately, not fixable via ratio tuning.
    private static let goldPNGInnerRatio:        CGFloat = 0.485
    private static let goldPNGInnerRatioCompact: CGFloat = 0.500

    // Mythic Inferno (Mythic, PNG-backed)
    //
    // regularRatio = 0.495 — sides hard-pigment avg (E=0.4833, W=0.4880) +
    // 2.6% margin so the disc gets ~0.5pt overlap at D=40 with the wisps
    // zone on cream paper.
    //
    // compactRatio = 0.500 — same rationale as gold (see above). The demon
    // head at top still intrudes regardless (intrinsic ratio 0.24 at N),
    // so apex-tier silhouette is preserved. Matched to gold's compact
    // ratio for uniform tightness across PNG-backed frames at the table.
    private static let mythicInfernoPNGInnerRatio:        CGFloat = 0.495
    private static let mythicInfernoPNGInnerRatioCompact: CGFloat = 0.500

    private static func goldPNG(diameter: CGFloat, compact: Bool) -> some View {
        // Sepia poker-engraved ornate ring (cards, chips, dice, horseshoe,
        // clover). Roughly symmetric except for a small fleur tip at the
        // bottom (~12% inner-radius asymmetry) that just-grazes the avatar's
        // bottom edge — reads as "avatar sitting in the frame," not as clip.
        //
        // Footprint: PNG canvas ≈ 2.06×diameter (regular) or 1.90×diameter
        // (compact). Larger than procedural gold's avatar+5pt; intentional
        // Phase 5 art lift.
        pngFrame(asset:             "avatar_frame_gold",
                 innerRatio:        goldPNGInnerRatio,
                 compactInnerRatio: goldPNGInnerRatioCompact,
                 diameter:          diameter,
                 compact:           compact)
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

    // ── Mythic (PNG-backed apex tier) ────────────────────────────────────────

    private static func mythicInfernoPNG(diameter: CGFloat, compact: Bool) -> some View {
        // Demonic flame ring at apex tier — black/red/orange flames with a
        // horned demon head at top and inward-pointing spikes around.
        //
        // Asymmetry: the demon head + horns intrude regardless of the chosen
        // ratio (intrinsic ratio 0.24 at N). The demon covers the top
        // ~25–30% of the avatar disc, hovering over the empty area above the
        // centered emoji. Reads as "demon menacing the avatar" — on-brand
        // for mythic and accepted as a deliberate art choice.
        //
        // Footprint: PNG canvas ≈ 2.02×diameter (regular) or 1.90×diameter
        // (compact). The set is intentionally non-uniform — each tier's
        // illustration carries its own proportions; normalizing would
        // require re-illustrating or padding the source PNGs.
        pngFrame(asset:             "avatar_frame_mythic_inferno",
                 innerRatio:        mythicInfernoPNGInnerRatio,
                 compactInnerRatio: mythicInfernoPNGInnerRatioCompact,
                 diameter:          diameter,
                 compact:           compact)
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
