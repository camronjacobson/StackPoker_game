import SwiftUI

// ─── Poker Table View ─────────────────────────────────────────────────────────
// Pure Poker-style layout: tall pill-shaped blue felt table, flat (no 3D tilt),
// seats positioned around the rim, chip stacks between seats and pot.

// MAP: PokerTableView — table felt, seats, chips, action bubbles (1734 lines)
// - TableLayout (geometry/seat positions) .. L9
// - PokerTableView (root) .................. L108
// - feltOval (table surface) ............... L193
// - seatOverlay (positions seats on rim) ... L547
// - TargetSeatView (single opponent seat) .. L1045
// - triggerBubbleIfNeeded (action bubbles) . L1286
// - actionBubbleKind (color/label mapping) . L1353
// - StackPill (player chip count display) .. L1373
// - OpponentHoleCardsView (face-down + reveals) L1453
// - TableTheme (colors) .................... L1646
// - FeltTexture ............................ L1692

// ─── Table Layout ─────────────────────────────────────────────────────────────

struct TableLayout {
    let size: CGSize
    let isLandscape: Bool

    // Felt dimensions — tall vertical pill (taller than wide) in portrait,
    // classic landscape oval when the device is rotated.
    var tableWidth: CGFloat {
        if isLandscape { return min(size.width - 48, size.height * 1.6) }
        // Portrait: pill is narrow relative to screen width so it reads as
        // tall, not wide.
        return min(size.width * 0.72, size.height * 0.42)
    }
    var tableHeight: CGFloat {
        if isLandscape { return tableWidth / 1.6 }
        // Vertically stretched — ~1.65 × width, capped to ~72% of screen height.
        return min(size.height * 0.72, tableWidth * 1.65)
    }
    // Pill shape — radius = half of the shorter side (width in portrait).
    var tableCornerRadius: CGFloat {
        min(tableWidth, tableHeight) / 2
    }
    var tableCenter: CGPoint {
        CGPoint(x: size.width / 2, y: size.height * 0.46)
    }
    var tableRect: CGRect {
        CGRect(
            x: tableCenter.x - tableWidth / 2,
            y: tableCenter.y - tableHeight / 2,
            width: tableWidth,
            height: tableHeight
        )
    }

    // Community cards
    // Sized so the 5-card row spans ~80% of the table width, reaching into
    // the inner betting-line ring (which sits at tableWidth - 60). Total
    // span = 5 * cardWidth + 4 * cardSpacing = 5*0.145 + 4*0.020 = 0.805.
    // That keeps the cards comfortably *inside* the inner ring on iPhone
    // (where the inset is proportionally tightest at ~83%) while still
    // giving them a commanding visual presence on the felt.
    var cardWidth: CGFloat { tableWidth * 0.145 }
    var cardSpacing: CGFloat { tableWidth * 0.020 }

    // Center layout positions (all relative to tableCenter).
    // Tuned for the tall pill felt: community cards high, pot stack sits
    // directly below the cards, then NLH/Blinds/Hosted by stack toward the
    // bottom. Watermark is tucked at the very bottom so it doesn't compete.
    var boardCenter: CGPoint {
        CGPoint(x: tableCenter.x, y: tableCenter.y - tableHeight * 0.12)
    }
    var potCenter: CGPoint {
        CGPoint(x: tableCenter.x, y: tableCenter.y + tableHeight * 0.04)
    }
    var gamePillCenter: CGPoint {
        CGPoint(x: tableCenter.x, y: tableCenter.y + tableHeight * 0.19)
    }
    var blindsCenter: CGPoint {
        CGPoint(x: tableCenter.x, y: tableCenter.y + tableHeight * 0.26)
    }
    var hostedByCenter: CGPoint {
        CGPoint(x: tableCenter.x, y: tableCenter.y + tableHeight * 0.34)
    }
    var brandCenter: CGPoint {
        CGPoint(x: tableCenter.x, y: tableCenter.y + tableHeight * 0.40)
    }

    // Seats
    var seatAvatarSize: CGFloat { isLandscape ? 52 : 56 }

    // ── Forced perspective ───────────────────────────────────────────────────
    // The felt is rendered as a trapezoid (wider at the bottom, near the
    // viewer; narrower at the top, "deeper into the screen"). `topRatio` is
    // the proportion of the bottom width that the top measures. Landscape
    // uses 1.0 (symmetric oval) so a rotated device still shows the classic
    // shape — perspective only kicks in when the device is held upright.
    //
    // Items on the felt (cards, pot, pills, brand mark) are still placed at
    // tableCenter and sized off `tableWidth`, so they keep the dimensions
    // they had before the perspective change. Only seats and the felt rim
    // itself follow the trapezoidal warp.
    var topRatio: CGFloat { isLandscape ? 1.0 : 0.84 }

    func seatPositions(count: Int) -> [CGPoint] {
        let cx = tableCenter.x
        let cy = tableCenter.y
        let rx = tableWidth / 2 + 8
        let ry = tableHeight / 2 + 20

        // Fixed angle slots — local player at bottom (270 degrees = bottom in standard math)
        // But we use 90 = bottom visually
        let angles: [Double] = {
            switch count {
            case 2: return [90, 270]
            case 3: return [90, 210, 330]
            case 4: return [90, 180, 270, 0]
            case 5: return [90, 162, 234, 306, 18]
            case 6: return [90, 150, 210, 270, 330, 30]
            case 7: return [90, 141, 193, 244, 296, 347, 38]
            case 8: return [90, 129, 168, 207, 270, 333, 12, 51]
            case 9: return [90, 130, 170, 210, 250, 290, 330, 10, 50]
            default: return [90, 270]
            }
        }()
        let tr = topRatio
        return angles.map { deg in
            let rad = deg * .pi / 180
            // depth: 0 at the top of the rim (sin = -1), 1 at the bottom (sin = 1).
            // xScale linearly interpolates between topRatio (top, narrowest) and
            // 1.0 (bottom, full width). Top seats squeeze toward the centerline
            // so they hug the narrower top arc; bottom seats stay on the wider
            // rim, preserving the "near-the-viewer" feeling.
            let depth  = (sin(rad) + 1) / 2
            let xScale = tr + (1.0 - tr) * depth
            return CGPoint(x: cx + rx * cos(rad) * xScale,
                           y: cy + ry * sin(rad))
        }
    }
}

// ─── Table Perspective Shape ──────────────────────────────────────────────────
// Forced-perspective table silhouette: a smaller circle at the top (further
// from the viewer) joined by two *external common tangent* lines to a larger
// circle at the bottom (close to the viewer). Because the side lines are
// tangent to both arcs at the meeting points, the join is C¹-continuous —
// the eye reads it as a single smooth curve instead of a stadium with two
// kinks where unequal-radius arcs meet straight lines.
//
// Earlier version connected unequal arcs with vertical lines, which produced
// visible angle breaks at the top of each side. That broke the illusion: a
// real round table photographed in perspective has no such breaks. Switching
// to common tangents was the only way to get a clean smooth pill.
//
// `topRatio` = top-circle width ÷ bottom-circle width.
//   1.00 → symmetric stadium (no perspective)
//   0.85 → subtle perspective, reads as "round table tilted slightly back"
//   0.65 → strong perspective, can look squished on phone-sized rects
struct TablePerspectiveShape: Shape {
    var topRatio: CGFloat = 0.84

    // Animatable so a future tween of `topRatio` (e.g. animated reveal of the
    // table on hand start) interpolates smoothly instead of snapping.
    var animatableData: CGFloat {
        get { topRatio }
        set { topRatio = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()

        let botW = rect.width
        let topW = rect.width * topRatio
        let rBot = botW / 2
        let rTop = topW / 2
        let midX = rect.midX
        let yTopC = rect.minY + rTop          // top circle is tangent to rect.minY
        let yBotC = rect.maxY - rBot          // bottom circle is tangent to rect.maxY
        let d     = yBotC - yTopC             // distance between circle centers

        // Defensive: if the rect collapses (very short / very wide) so that
        // the two circles can't even sit clear of each other, fall back to a
        // rounded rect so we never produce garbage geometry.
        guard d > 0.001, rBot >= rTop else {
            path.addRoundedRect(in: rect, cornerSize: CGSize(width: rBot, height: rBot))
            return path
        }

        // External common tangent angle. For two stacked circles with the
        // smaller on top and the larger on bottom, the right-side external
        // tangent slopes outward going down at angle β from vertical, where
        // sin β = (rBot − rTop) / d. Both tangent points sit *above* their
        // circle's horizontal equator — that's the geometric property that
        // makes the join smooth: the radius at the tangent point is
        // perpendicular to the tangent line, so the arc and the line share
        // a common tangent direction at the meeting point. No kink.
        let sinB = max(-1.0, min(1.0, (rBot - rTop) / d))
        let beta = asin(sinB)
        let bDeg = beta * 180.0 / .pi
        let cosB = cos(beta)

        // SwiftUI angle convention on a y-down canvas:
        //   0° → right, 90° → screen-bottom, 180° → left, 270° → screen-top.
        // `clockwise: false` traces increasing angle (visually clockwise on
        // screen because y is flipped relative to math convention).

        // Tangent meeting points. Note y = center.y − r·sin β (smaller y on
        // screen = above the circle's equator).
        let topLeft  = CGPoint(x: midX - rTop * cosB, y: yTopC - rTop * sinB)
        let botRight = CGPoint(x: midX + rBot * cosB, y: yBotC - rBot * sinB)

        // Trace: topLeft → over-the-top arc → topRight → tangent line down
        // to botRight → around-the-bottom arc → botLeft → tangent line back
        // up to topLeft. Top arc spans <180° (tangent points above equator);
        // bottom arc spans >180° (mirrors the same property on the larger
        // circle). The two tangent lines fill the rest.
        path.move(to: topLeft)
        path.addArc(center: CGPoint(x: midX, y: yTopC),
                    radius: rTop,
                    startAngle: .degrees(180 + bDeg),
                    endAngle:   .degrees(360 - bDeg),
                    clockwise:  false)
        path.addLine(to: botRight)
        path.addArc(center: CGPoint(x: midX, y: yBotC),
                    radius: rBot,
                    // -bDeg ≡ 360 - bDeg; using the negative form keeps
                    // start < end so the CCW (increasing-angle) trace stays
                    // monotonic and SwiftUI doesn't need to wrap modulo 360.
                    startAngle: .degrees(-bDeg),
                    endAngle:   .degrees(180 + bDeg),
                    clockwise:  false)
        path.addLine(to: topLeft)
        path.closeSubpath()
        return path
    }
}

// ─── Surface tilt modifier ────────────────────────────────────────────────────
// Rotates a flat 2D view backward around its horizontal axis so it visually
// "lies on" the trapezoidal felt instead of looking pasted on flat. Applied
// per-item (chip, card, etc.) around each item's own center, so a chip's
// position on the felt stays put — only its visual is foreshortened.
//
// Why per-item rather than tilting the whole content layer:
//   - A layer-level tilt would compress chip *positions* vertically, which
//     would no longer line up with the seat ring and pot center.
//   - Per-item tilt keeps positions in the original 2D coords (which already
//     follow the trapezoidal seat warp) and only foreshortens each glyph in
//     place. Result: chips read as ellipses, cards as trapezoids, everything
//     still anchored exactly where the layout said.
//
// 26° was chosen by eye to approximately match the table's `topRatio = 0.84`
// foreshortening — strong enough to read as 3D, gentle enough that card
// pips and chip text remain legible.
private extension View {
    func tableSurfaceTilt(_ degrees: Double = 26) -> some View {
        rotation3DEffect(
            .degrees(degrees),
            axis: (x: 1, y: 0, z: 0),
            anchor: .center,
            // Lower perspective than the default = milder "bigger at bottom,
            // smaller at top" within each glyph. We want consistent
            // foreshortening across small icons, not a wide-angle camera
            // distortion per chip.
            perspective: 0.55
        )
    }
}

// ─── PokerTableView ───────────────────────────────────────────────────────────

struct PokerTableView: View {
    let seats:       [GameSeat]
    let maxSeats:    Int
    @ObservedObject var vm: GameViewModel
    var isLandscape: Bool = false

    // Felt theme — read from user settings. Defaults to classic blue. Changes
    // in the settings sheet propagate here live via @AppStorage.
    @AppStorage("tableThemeId") private var tableThemeId: String = "classic_blue"
    private var theme: TableTheme { TableTheme.find(tableThemeId) }

    // Tapping an empty seat surfaces this confirmation dialog so the user
    // can fill the seat with a bot (or, when more options arrive, an invite).
    @State private var showOpenSeatSheet = false

    private var hasBotSeated: Bool {
        vm.gameState?.seats.contains { $0.username == "StackBot" } ?? false
    }

    /// Honors the per-table bot preference recorded when the creator opted
    /// in/out at table creation. Defaults to true for tables we joined.
    private var botsAllowedHere: Bool {
        TablePreferences.botsAllowed(forTableId: vm.tableId)
    }

    var body: some View {
        GeometryReader { geo in
            let layout = TableLayout(size: geo.size, isLandscape: isLandscape)

            ZStack {
                // ── Table layer (flat, no 3D tilt)
                feltOval(layout)
                brandMark(layout)
                potCluster(layout)
                communityBoard(layout)
                // Replaces the previous trio (gamePill / blindsLabel /
                // hostedByLabel). Game type + blinds in a single low-key
                // pill keeps the bottom of the felt readable instead of
                // stacking three separate text rows on top of each other.
                tableInfoPill(layout)
                dealerRailButton(layout)
                blindRailChips(layout)
                betChipsLayer(layout)
                // potFlowLayer removed — the pot stack itself now slides to
                // the winner via potCluster's AwardingPotStack. Keeping the
                // old separate flying-chip layer would double up animations.
                winningHandBanner(layout)

                // ── Seat overlay
                seatOverlay(layout)
            }
            .animation(.easeInOut(duration: 0.3), value: vm.gameState?.communityCards.count)
            .animation(.easeInOut(duration: 0.3), value: vm.gameState?.totalPot)
            // Slightly slower spring with lighter damping = chips have
            // "weight" as they migrate to the pot. Response 0.65 gives a
            // ~0.65s arc; damping 0.78 lets the pot stack do a tiny settle
            // overshoot when it scales in, which reads as chips landing.
            .animation(.spring(response: 0.65, dampingFraction: 0.78), value: betsSignature)
            .confirmationDialog(
                "Open Seat",
                isPresented: $showOpenSeatSheet,
                titleVisibility: .visible
            ) {
                if !hasBotSeated && botsAllowedHere {
                    Button("Add Bot Player") { vm.addBot() }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                if !botsAllowedHere {
                    Text("Bots are disabled for this table. Invite a friend from the lobby to fill this seat.")
                } else if hasBotSeated {
                    Text("A bot is already seated. Invite a friend from the lobby to fill more seats.")
                } else {
                    Text("Fill this seat with StackBot or invite a friend from the lobby.")
                }
            }
        }
    }

    private var betsSignature: String {
        seats.map { "\($0.userId):\($0.betThisStreet)" }.joined(separator: "|")
    }

    // ─── Felt + rail ──────────────────────────────────────────────────────────
    // Rendered as a layered stack:
    //   1. Cast shadow on the "floor" beneath the table
    //   2. Padded leather rail surrounding the felt
    //   3. Inner bevel + stitch line where rail meets felt
    //   4. Felt surface (themed gradient + cloth texture + sheen + vignette)
    //   5. Inset betting line where chips land

    private static let railWidth: CGFloat = 22

    private func feltOval(_ l: TableLayout) -> some View {
        let cr      = l.tableCornerRadius
        let rw      = Self.railWidth
        let outerW  = l.tableWidth  + rw * 2
        let outerH  = l.tableHeight + rw * 2
        let outerCR = cr + rw

        let tr = l.topRatio

        // Underside skirt — visible "edge thickness" of the table viewed
        // from above-front. Drawn behind the rail; bottom band peeks out
        // below the rail's lower curve. Because the trapezoid is wider at
        // the bottom, the skirt's silhouette also widens down — and because
        // the offset is purely vertical, the top of the skirt is fully
        // hidden by the rail (skirt has zero thickness up there). The
        // result is a natural "thicker at bottom, thinning to nothing at
        // the top" appearance with no per-side computed offsets needed.
        let skirtDrop: CGFloat = 14

        return ZStack {
            // 1. Cast shadow on the floor — soft, slightly offset down. Uses
            //    the trapezoid shape so the floor-shadow silhouette tracks
            //    the felt instead of betraying a rectangular underlay.
            //    Pushed a touch further down to clear the new skirt so the
            //    skirt reads as solid table edge, not as part of the shadow.
            TablePerspectiveShape(topRatio: tr)
                .fill(Color.black.opacity(0.55))
                .frame(width: outerW + 28, height: outerH + 28)
                .blur(radius: 26)
                .offset(y: 18 + skirtDrop)
                .allowsHitTesting(false)

            // 1b. Underside skirt. Dark wood/leather band that gives the
            //     table apparent thickness. Top-to-bottom gradient: deepest
            //     at the top (recessed under the rail), warmed slightly at
            //     the bottom (catches indirect light from below). A faint
            //     highlight stroke at the very bottom edge sells the front
            //     lip of the table — tiny detail, big perceptual lift.
            TablePerspectiveShape(topRatio: tr)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: "#0A0502"),
                            Color(hex: "#1B0F06"),
                            Color(hex: "#241408"),
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .frame(width: outerW, height: outerH)
                .overlay(
                    // Bottom-edge highlight — only the lower portion of this
                    // stroke is visible (the rest is hidden behind the rail
                    // once the offset moves the skirt down). Reads as a
                    // thin lit lip running along the front curve of the
                    // table.
                    TablePerspectiveShape(topRatio: tr)
                        .stroke(Color(hex: "#5A3C20").opacity(0.55), lineWidth: 1)
                        .frame(width: outerW, height: outerH)
                )
                .offset(y: skirtDrop)
                .allowsHitTesting(false)

            // 2. Padded leather rail
            railLayer(outerW: outerW, outerH: outerH, outerCR: outerCR, topRatio: tr)

            // 3a. Inner bevel — DARK top edge / bright bottom edge. Same
            //     reversal as the rail: with the table tilted back, the far
            //     side of the bevel is in shadow under the rail, while the
            //     near side catches a hint of light spilling off the felt.
            //     Old top-bright bevel reinforced the "raised flap" look at
            //     the top of the table.
            TablePerspectiveShape(topRatio: tr)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.55),
                            Color.black.opacity(0.18),
                            Color.white.opacity(0.16),
                        ],
                        startPoint: .top, endPoint: .bottom
                    ),
                    lineWidth: 2.5
                )
                .frame(width: l.tableWidth + 4, height: l.tableHeight + 4)
                .allowsHitTesting(false)

            // 3b. Saddle stitching where rail meets felt
            TablePerspectiveShape(topRatio: tr)
                .stroke(
                    Color(hex: "#C9A574").opacity(0.32),
                    style: StrokeStyle(lineWidth: 0.6, dash: [3, 2.5])
                )
                .frame(width: l.tableWidth + 2, height: l.tableHeight + 2)
                .allowsHitTesting(false)

            // 3c. Inner rim gleam — warm highlight right at the felt/rail
            //     boundary, top-biased. Required because the rail's top
            //     depth fade darkens the far edge so much that the rail
            //     visually "dissolves" into the felt up there. This thin
            //     stroke re-anchors the boundary at the top without
            //     fighting the perspective gradient: peak opacity at the
            //     top (where the rail is otherwise lost), fading to nearly
            //     nothing at the bottom (where the rail's bottom highlight
            //     already defines the edge). Tan/copper tone reads as a
            //     leather lip catching ambient light, not a hard outline.
            TablePerspectiveShape(topRatio: tr)
                .stroke(
                    LinearGradient(
                        stops: [
                            .init(color: Color(hex: "#8A6038").opacity(0.65), location: 0.00),
                            .init(color: Color(hex: "#8A6038").opacity(0.30), location: 0.35),
                            .init(color: Color(hex: "#8A6038").opacity(0.08), location: 0.70),
                            .init(color: Color.clear,                          location: 1.00),
                        ],
                        startPoint: .top, endPoint: .bottom
                    ),
                    lineWidth: 1.2
                )
                .frame(width: l.tableWidth + 1, height: l.tableHeight + 1)
                .allowsHitTesting(false)

            // 4. Felt surface (gradient + cloth texture + sheen + vignette)
            feltSurface(l, cr: cr)

            // 5. Inset betting line — the guide curve where action chips land.
            //    Same trapezoidal silhouette, just inset 30pt on each axis so
            //    it nests inside the felt rim.
            TablePerspectiveShape(topRatio: tr)
                .stroke(Color.white.opacity(0.085), lineWidth: 1)
                .frame(width: l.tableWidth - 60, height: l.tableHeight - 60)
                .allowsHitTesting(false)
        }
        .position(x: l.tableCenter.x, y: l.tableCenter.y)
    }

    // ── Rail (padded leather) ────────────────────────────────────────────────

    private func railLayer(outerW: CGFloat,
                           outerH: CGFloat,
                           outerCR: CGFloat,
                           topRatio: CGFloat) -> some View {
        ZStack {
            // Base leather — DARK at top (far end, foreshortened, in shadow),
            // warmer/lighter at the bottom (near end, catches lamp light off
            // the felt). Old gradient ran the opposite way, which painted the
            // far rim brighter than the near rim and made the top of the
            // table read as a "flap" sitting *above* the felt instead of
            // receding away from the viewer.
            TablePerspectiveShape(topRatio: topRatio)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: "#0A0502"),
                            Color(hex: "#1A0F06"),
                            Color(hex: "#352213"),
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .frame(width: outerW, height: outerH)

            // Bottom highlight — light grazing the front lip of the rail
            // (closest to the viewer). Bottom-up gradient inverts what used
            // to be a top-down "sheen" — the highlight now lives where the
            // light source would actually hit on a tilted-back table, not on
            // the recessed far edge. Greatly reduced opacity vs. the old top
            // sheen so it reads as a subtle gleam, not a polished band.
            TablePerspectiveShape(topRatio: topRatio)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.clear,
                            Color.white.opacity(0.03),
                            Color.white.opacity(0.12),
                        ],
                        startPoint: UnitPoint(x: 0.5, y: 0.55),
                        endPoint:   .bottom
                    )
                )
                .frame(width: outerW, height: outerH)
                .blendMode(.plusLighter)

            // Top depth fade — explicit darkening of the top third of the
            // rail. Pushes the far end into noticeable shadow so the eye
            // reads it as "further away" rather than "thicker." Falls off
            // to clear by the rail's vertical midpoint, leaving the bottom
            // half untouched.
            TablePerspectiveShape(topRatio: topRatio)
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: Color.black.opacity(0.55), location: 0.00),
                            .init(color: Color.black.opacity(0.22), location: 0.30),
                            .init(color: Color.clear,               location: 0.55),
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .frame(width: outerW, height: outerH)

            // Outer rail edge — dim at top (in shadow with the rail), bright
            // at bottom (catches the front-lip highlight). Mirrors the
            // gradient direction of the base leather so the silhouette stays
            // consistent under the new lighting.
            TablePerspectiveShape(topRatio: topRatio)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.55),
                            Color.black.opacity(0.20),
                            Color.white.opacity(0.18),
                        ],
                        startPoint: .top, endPoint: .bottom
                    ),
                    lineWidth: 1.5
                )
                .frame(width: outerW, height: outerH)
        }
        .allowsHitTesting(false)
    }

    // ── Felt surface ─────────────────────────────────────────────────────────

    private func feltSurface(_ l: TableLayout, cr: CGFloat) -> some View {
        let tr = l.topRatio

        return TablePerspectiveShape(topRatio: tr)
            .fill(
                // Sharper center-to-edge gradient than before. Tighter inner
                // radius keeps the bright "spotlight" smaller, and pushing
                // through `theme.edge` at the perimeter sells the bowl shape
                // — a flat surface wouldn't have this much contrast.
                RadialGradient(
                    colors: [
                        Color(hex: theme.inner),
                        Color(hex: theme.mid),
                        Color(hex: theme.edge),
                    ],
                    center: UnitPoint(x: 0.5, y: 0.42),
                    startRadius: l.tableWidth * 0.03,
                    endRadius: l.tableWidth * 0.72
                )
            )
            .frame(width: l.tableWidth, height: l.tableHeight)
            .overlay(
                // Cloth weave — fine speckle clipped to felt shape.
                // Reduced opacity inline (in FeltTexture) means it doesn't
                // muddy the new lighting layers.
                FeltTexture()
                    .frame(width: l.tableWidth, height: l.tableHeight)
                    .clipShape(TablePerspectiveShape(topRatio: tr))
                    .allowsHitTesting(false)
            )
            .overlay(
                ZStack {
                    // ── Directional top-down lighting ────────────────────
                    // Light from the upper-front. Brighter band across the
                    // top third, then a subtle dim across the bottom. This
                    // is what makes the felt look slightly *domed* rather
                    // than perfectly flat.
                    TablePerspectiveShape(topRatio: tr)
                        .fill(
                            LinearGradient(
                                stops: [
                                    .init(color: Color.white.opacity(0.14),  location: 0.00),
                                    .init(color: Color.white.opacity(0.04),  location: 0.35),
                                    .init(color: Color.clear,                location: 0.55),
                                    .init(color: Color.black.opacity(0.10),  location: 1.00),
                                ],
                                startPoint: .top,
                                endPoint:   .bottom
                            )
                        )
                        .frame(width: l.tableWidth, height: l.tableHeight)
                        .blendMode(.plusLighter)

                    // ── Stronger center-to-edge vignette ─────────────────
                    // Was 0.22 max → now 0.42. Combined with the sharper base
                    // gradient, the felt now has clear depth: bright concave
                    // center, dark recessed perimeter. Pushes attention to
                    // the community cards / pot.
                    TablePerspectiveShape(topRatio: tr)
                        .fill(
                            RadialGradient(
                                colors: [Color.clear, Color.black.opacity(0.42)],
                                center: .center,
                                startRadius: l.tableWidth * 0.28,
                                endRadius: l.tableWidth * 0.66
                            )
                        )
                        .frame(width: l.tableWidth, height: l.tableHeight)

                    // ── Inner shadow at the rim (recessed felt) ──────────
                    // Drawn as a thick stroke just inside the felt edge,
                    // blurred so it fades softly toward the center. This is
                    // the single most impactful 3D cue: the felt now reads
                    // as *sunken below* the leather rail rather than sitting
                    // flat at the same plane. Roughly mimics the inner-
                    // shadow effect from CSS / Figma without needing a
                    // bespoke shader.
                    TablePerspectiveShape(topRatio: tr)
                        .stroke(Color.black.opacity(0.65), lineWidth: 14)
                        .blur(radius: 10)
                        .frame(width: l.tableWidth, height: l.tableHeight)
                        .mask(
                            // Mask keeps the shadow only inside the felt
                            // trapezoid — without this, the blurred stroke
                            // would bleed onto the rail.
                            TablePerspectiveShape(topRatio: tr)
                                .frame(width: l.tableWidth, height: l.tableHeight)
                        )

                    // ── Subtle bottom contact shadow ─────────────────────
                    // The lower edge of the felt sits in a touch more
                    // shadow than the top, mimicking a light source above.
                    // Helps the 3D shape feel anchored to a "down" axis.
                    TablePerspectiveShape(topRatio: tr)
                        .fill(
                            LinearGradient(
                                stops: [
                                    .init(color: Color.clear,               location: 0.65),
                                    .init(color: Color.black.opacity(0.18), location: 1.00),
                                ],
                                startPoint: .top,
                                endPoint:   .bottom
                            )
                        )
                        .frame(width: l.tableWidth, height: l.tableHeight)
                }
                .clipShape(TablePerspectiveShape(topRatio: tr))
                .allowsHitTesting(false)
            )
    }

    // ─── StackPoker watermark ────────────────────────────────────────────────

    private func brandMark(_ l: TableLayout) -> some View {
        Text("StackPoker")
            .font(.system(size: min(l.tableWidth * 0.11, 42), weight: .heavy, design: .rounded))
            .foregroundStyle(Color.white.opacity(0.05))
            .kerning(2)
            .position(x: l.brandCenter.x, y: l.brandCenter.y)
    }

    // ─── Pot cluster ─────────────────────────────────────────────────────────

    // The pot stack should only show chips that have *physically been
    // collected* into the middle — i.e. chips from completed streets, not
    // chips currently sitting in front of seats as live bets. Without this
    // gate, the pot double-counts: bet badges show chips in front of each
    // seat AND those same chips appear in the middle pot, which is wrong
    // (e.g. preflop with just SB+BB posted there should be NO chips in the
    // middle, since the betting round hasn't ended yet).
    //
    // Collected = totalPot − sum(betThisStreet). Once a street completes
    // the engine resets every seat's betThisStreet to 0, at which point
    // the bet badges remove (their `.transition` flies them to the pot
    // center) and `collected` jumps to the new total — the visual is the
    // chips physically migrating from in front of each seat into the
    // middle stack, which is exactly how a live dealer collects.
    @ViewBuilder
    private func potCluster(_ l: TableLayout) -> some View {
        if let state = vm.gameState {
            let onTable   = seats.reduce(0) { $0 + $1.betThisStreet }
            let collected = max(0, state.totalPot - onTable)
            let winners   = state.winners ?? []

            if !winners.isEmpty {
                // Hand resolved — slide the actual pot stack toward each
                // winner. Replaces the old "static pot in middle + separate
                // flying chip" pattern, which read as two simultaneous
                // animations playing past each other. Now the pot itself
                // moves: the chips you've been watching collect in the
                // middle physically migrate to the winner's seat, then fade
                // as they're "absorbed" into the winner's stack.
                //
                // For split pots we render one stack per winner, each with
                // its own share. They slide independently to their seats.
                let positions = l.seatPositions(count: maxSeats)
                ForEach(winners, id: \.playerId) { winner in
                    if let idx = seats.firstIndex(where: { $0.userId == winner.playerId }),
                       idx < positions.count {
                        AwardingPotStack(
                            amount: winner.amount,
                            from:   l.potCenter,
                            to:     positions[idx]
                        )
                    }
                }
            } else if collected > 0 {
                PotChipStack(amount: collected)
                    // Tilt before .position so each chip stack tilts around
                    // its own center, not the felt center.
                    .tableSurfaceTilt()
                    .position(x: l.potCenter.x, y: l.potCenter.y)
                    // Removal is .identity (instant) instead of a scale-fade
                    // because at hand-end this view is replaced by the
                    // AwardingPotStack at the same position — overlapping
                    // a fading copy with the new sliding copy would render
                    // two stacks for ~0.3s. Instant swap = continuous look:
                    // user sees the same chip stack pop into "moving" mode.
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.7).combined(with: .opacity),
                        removal:   .identity
                    ))
                    .id(ChipTier.forAmount(collected))
            }
        }
    }

    // ─── Community board ──────────────────────────────────────────────────────

    private func communityBoard(_ l: TableLayout) -> some View {
        // Surface the run-out preview only while phase==ENDED. The server
        // already gates this server-side, but double-gating client-side
        // keeps the UI honest if a stale or out-of-order broadcast lands —
        // we never want face-down "tap to reveal" placeholders to flash on
        // the table during a live hand.
        let runOut: [PokerCard] = (vm.gameState?.phase == .ended)
            ? (vm.gameState?.revealableBoard ?? [])
            : []
        return CommunityCardsView(
            cards:           vm.gameState?.communityCards ?? [],
            winnersCards:    winnerCardIds,
            cardWidth:       l.cardWidth,
            cardSpacing:     l.cardSpacing,
            colored:         true,
            revealableBoard: runOut
        )
        // Cards lie flat on the felt — tilt them by the felt's full
        // foreshortening angle. Chips stand vertically on the felt so
        // the default 26° tilt reads correctly for them, and the same
        // tilt is applied here so the board sits at the shared surface
        // angle.
        .tableSurfaceTilt()
        .position(x: l.boardCenter.x, y: l.boardCenter.y)
    }

    // ─── Combined table info pill (game type · blinds) ──────────────────────
    // Single low-contrast pill replaces what used to be three separate text
    // rows (NLH pill / Blinds label / Hosted-by). Game type and blinds are
    // the only two pieces of info worth surfacing on the felt itself; host
    // identity already lives in the lobby header. One pill = far less
    // crowding around the pot/community-card area.
    @ViewBuilder
    private func tableInfoPill(_ l: TableLayout) -> some View {
        if let state = vm.gameState {
            let game = state.gameType == "PLO" ? "PLO" : "NLH"
            let sb   = formatChips(String(state.smallBlind))
            let bb   = formatChips(String(state.bigBlind))
            HStack(spacing: 8) {
                Text(game)
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.65))
                // Thin divider keeps the two halves visually distinct
                // without adding extra pixels of vertical clutter.
                Rectangle()
                    .fill(Color.white.opacity(0.18))
                    .frame(width: 1, height: 10)
                Text("\(sb) / \(bb)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.22))
                    .overlay(
                        Capsule().strokeBorder(
                            Color.white.opacity(0.06),
                            lineWidth: 0.5
                        )
                    )
            )
            // Sits where the old gamePill was — closest to the pot, far
            // enough above the watermark to leave breathing room.
            .position(x: l.gamePillCenter.x, y: l.gamePillCenter.y)
            .allowsHitTesting(false)
        }
    }

    // ─── Dealer "D" button ───────────────────────────────────────────────────

    @ViewBuilder
    private func dealerRailButton(_ l: TableLayout) -> some View {
        if let dealerIdx = dealerDisplayIndex {
            let positions = l.seatPositions(count: maxSeats)
            if dealerIdx < positions.count {
                let seatPt = positions[dealerIdx]
                let dx = l.tableCenter.x - seatPt.x
                let dy = l.tableCenter.y - seatPt.y
                let bx = seatPt.x + dx * 0.50
                let by = seatPt.y + dy * 0.50

                // Dealer button — classic ivory chip with bold "D".
                PokerChip(text: "D",
                          tint: Color(hex: "#F4ECDC"),
                          textColor: Color(hex: "#1B1B1B"),
                          size: 24)
                    .tableSurfaceTilt()
                    .position(x: bx, y: by)
            }
        }
    }

    private var dealerDisplayIndex: Int? {
        seats.firstIndex(where: { $0.isDealer })
    }

    // ─── Blind markers (small ambient icons next to each seat) ──────────────
    // Previous design parked SB/BB chips out on the felt (rail-ratio 0.30
    // toward center), which drew the eye and competed with the bet stacks
    // for attention. New design: tiny muted chip pinned to the LEFT of the
    // player avatar so the marker is *always* with the player and never on
    // the action area. The dealer button keeps its rail-line placement
    // because it visually rotates around the table each hand — it's
    // information about *where the action is*, not about a specific seat.
    @ViewBuilder
    private func blindRailChips(_ l: TableLayout) -> some View {
        let positions = l.seatPositions(count: maxSeats)
        let markerSize: CGFloat = 14
        // Distance from seat center to the marker. Avatar radius +
        // half-marker + a small gap so the chip kisses the avatar
        // border without overlapping it.
        let offset = l.seatAvatarSize / 2 + markerSize / 2 + 4
        ForEach(Array(seats.enumerated()), id: \.element.userId) { idx, seat in
            if idx < positions.count, seat.isSmallBlind || seat.isBigBlind {
                let seatPt = positions[idx]
                // Always to the *screen-left* of the seat, regardless of
                // where the seat sits around the rim. Keeps the marker
                // location predictable for the player's eye.
                let bx = seatPt.x - offset
                let by = seatPt.y
                let tint = seat.isSmallBlind
                    ? Color(hex: "#3B7DD8")
                    : Color(hex: "#C9342B")
                let label = seat.isSmallBlind ? "SB" : "BB"
                PokerChip(text: label,
                          tint: tint,
                          textColor: .white,
                          size: markerSize,
                          muted: true)
                    .tableSurfaceTilt()
                    .position(x: bx, y: by)
            }
        }
    }

    // ─── Bet chip layer ──────────────────────────────────────────────────────

    @ViewBuilder
    private func betChipsLayer(_ l: TableLayout) -> some View {
        let positions = l.seatPositions(count: maxSeats)
        ZStack {
            ForEach(Array(seats.enumerated()), id: \.element.userId) { idx, seat in
                if idx < positions.count && seat.betThisStreet > 0 {
                    let seatPt = positions[idx]
                    let bx = seatPt.x + (l.tableCenter.x - seatPt.x) * 0.40
                    let by = seatPt.y + (l.tableCenter.y - seatPt.y) * 0.40
                    let dx = l.potCenter.x - bx
                    let dy = l.potCenter.y - by
                    BetChipBadge(amount: seat.betThisStreet)
                        // Tilt the chip around its own center BEFORE
                        // positioning, so the chip's spot on the felt stays
                        // exactly where the layout placed it. Cards/chips
                        // would look pasted-on flat without this.
                        .tableSurfaceTilt()
                        .position(x: bx, y: by)
                        // Insertion: chip pops up from in front of the seat.
                        // Removal (street ended): chip translates to potCenter
                        // AND scales down to 0.45 — visually the chips look
                        // like they're falling/settling onto the pot stack
                        // rather than just sliding flat on the felt. The
                        // opacity fade is part of the same transition so the
                        // chip dissolves into the pot at arrival, never
                        // hard-cutting. Spring physics on `betsSignature`
                        // (see body's `.animation`) gives the motion weight.
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.35, anchor: .bottom)
                                .combined(with: .opacity),
                            removal: .offset(x: dx, y: dy)
                                .combined(with: .scale(scale: 0.45, anchor: .center))
                                .combined(with: .opacity)
                        ))
                }
            }
        }
    }

    // ─── Seat overlay (flat) ─────────────────────────────────────────────────

    private func seatOverlay(_ l: TableLayout) -> some View {
        let positions = l.seatPositions(count: maxSeats)
        return ForEach(0..<maxSeats, id: \.self) { idx in
            Group {
                if idx < seats.count {
                    let seat = seats[idx]
                    let isMe = (idx == 0)
                    let isActive = vm.gameState?.activePlayerId == seat.userId
                    let isWinner = winnerIds.contains(seat.userId)
                    TargetSeatView(
                        seat: seat,
                        isMe: isMe,
                        isMyTurn: isActive,
                        isWinner: isWinner,
                        turnProgress: isActive ? vm.turnTimeRemaining : 1.0,
                        turnSecondsLeft: isActive ? vm.turnSecondsLeft : 0,
                        lastAction: vm.gameState?.lastAction,
                        avatarSize: l.seatAvatarSize,
                        winningCardIds: winnerCardIds,
                        anyWinnersDeclared: !winnerIds.isEmpty
                    )
                    .position(x: positions[idx].x, y: positions[idx].y)
                    .zIndex(isWinner ? 20 : (isActive ? 10 : 1))
                } else {
                    // Hit area MUST be bounded before .position(). Applying
                    // .contentShape after .position lets the empty-seat tap
                    // swallow taps anywhere on the table (because .position
                    // expands the view to the full parent rect), which is
                    // why tapping run-out cards was firing the invite sheet.
                    TargetEmptySeat(avatarSize: l.seatAvatarSize)
                        .contentShape(Rectangle())
                        .onTapGesture { showOpenSeatSheet = true }
                        .position(x: positions[idx].x, y: positions[idx].y)
                }
            }
        }
    }

    private var winnerCardIds: Set<String> {
        guard let winners = vm.gameState?.winners else { return [] }
        return Set(winners.flatMap { $0.bestCards.map { $0.id } })
    }

    // ─── Winning-hand-name banner ───────────────────────────────────────────
    // Shown the moment the server announces winners. Sits between the
    // (now-enlarged) community cards and the pot stack so the user reads
    // *what* won the hand at a glance — "Full House", "Straight", etc.
    // Multiple winners with different hands (rare but possible across split
    // pots in mixed games) are joined with a separator. zIndex(50) keeps it
    // above the pot/chips during pot collection.
    @ViewBuilder
    private func winningHandBanner(_ l: TableLayout) -> some View {
        if let winners = vm.gameState?.winners, !winners.isEmpty {
            // De-dupe hand names: chopped pots usually share one hand name
            // ("Two Pair") between both seats — show it once, not twice.
            let names = winners.map(\.handName)
            let unique = Array(NSOrderedSet(array: names)) as? [String] ?? names
            VStack(spacing: 2) {
                Text("WINNING HAND")
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
                    .tracking(1.2)
                Text(unique.joined(separator: " · "))
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundStyle(Color(hex: "#F5C842"))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .shadow(color: Color(hex: "#F5C842").opacity(0.5), radius: 6)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.55))
                    .overlay(
                        Capsule().strokeBorder(
                            Color(hex: "#F5C842").opacity(0.4),
                            lineWidth: 1
                        )
                    )
            )
            .position(
                x: l.tableCenter.x,
                y: l.tableCenter.y - l.tableHeight * 0.02
            )
            .transition(.scale(scale: 0.7).combined(with: .opacity))
            .zIndex(50)
            // Purely informational text — must not intercept taps. Without
            // this, the banner's frame overlaps the bottom of the community
            // board (board at tableHeight*0.12 above center, banner at
            // tableHeight*0.02 above center) and swallows taps targeted at
            // the run-out face-down placeholders, which sit on the right
            // side of the board during a fold-out reveal.
            .allowsHitTesting(false)
        }
    }

    private var winnerIds: Set<String> {
        guard let winners = vm.gameState?.winners else { return [] }
        return Set(winners.map { $0.playerId })
    }
}

// ─── Chip Color Tiers ────────────────────────────────────────────────────────

enum ChipTier {
    case white, red, blue, black, purple, gold

    static func forAmount(_ amount: Int) -> ChipTier {
        switch amount {
        case ..<100:       return .white
        case 100..<500:    return .red
        case 500..<1000:   return .blue
        case 1000..<5000:  return .black
        case 5000..<25000: return .purple
        default:           return .gold
        }
    }

    var colors: (primary: Color, secondary: Color, edge: Color) {
        switch self {
        case .white:  return (Color(hex: "#E8E8E8"), Color(hex: "#C0C0C0"), Color(hex: "#AAAAAA"))
        case .red:    return (Color(hex: "#E05555"), Color(hex: "#B83A3A"), Color(hex: "#8B2020"))
        case .blue:   return (Color(hex: "#4A90E2"), Color(hex: "#2D6CC0"), Color(hex: "#1A4F8F"))
        case .black:  return (Color(hex: "#3A3A3A"), Color(hex: "#222222"), Color(hex: "#111111"))
        case .purple: return (Color(hex: "#8B5CF6"), Color(hex: "#6C3CD8"), Color(hex: "#4A2B9E"))
        case .gold:   return (Color(hex: "#F5C842"), Color(hex: "#D4A520"), Color(hex: "#B8860B"))
        }
    }
}

private func pokerChipIcon(diameter: CGFloat, amount: Int = 0) -> some View {
    let tier = ChipTier.forAmount(amount)
    let c = tier.colors
    return ZStack {
        Circle()
            .fill(
                LinearGradient(
                    colors: [c.primary, c.secondary],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            )
        Circle()
            .strokeBorder(Color.white.opacity(0.5), lineWidth: 1)
        Circle()
            .strokeBorder(c.edge, style: StrokeStyle(lineWidth: 1.5, dash: [2, 2]))
            .padding(diameter * 0.18)
    }
    .frame(width: diameter, height: diameter)
    .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
}

// ─── Poker Chip ──────────────────────────────────────────────────────────────
// Reusable chip view used for the dealer button (D) and blind markers (SB/BB).
// Built up in layers to mimic a real ceramic / clay-composite poker chip:
//   1. Soft cast shadow on the felt.
//   2. Outer rim disk in the chip's tint, with a subtle 3D dome via a radial
//      highlight (upper-left) and a darker bottom from a vertical shade.
//   3. Eight inlaid white edge spots evenly spaced around the rim, each with
//      its own thin dark border + tiny inner gradient for an inlay feel.
//   4. Thin dark separator ring between the rim and the center face.
//   5. Outer center band — a slightly different tone of the tint so the
//      center reads as multi-layer instead of flat.
//   6. Center face — domed inset with its own radial highlight.
//   7. Thin inner detail ring on the face (typical of casino chips).
//   8. Bold rounded text with a soft emboss shadow.
//   9. A short top gloss arc suggesting a glossy ceramic finish.

private struct PokerChip: View {
    let text:      String
    let tint:      Color
    let textColor: Color
    var size:      CGFloat = 22
    // Muted = dimmer, lower-saturation rendering for ambient markers
    // (small SB/BB indicators that should sit quietly next to a seat).
    // The detailed chip rendering still applies — we just reduce the
    // visual weight via opacity + a desaturating overlay so the eye
    // goes to action chips first.
    var muted:     Bool   = false

    var body: some View {
        ZStack {
            // ── 1. Cast shadow on the felt ───────────────────────────────
            Circle()
                .fill(Color.black.opacity(0.55))
                .frame(width: size * 1.04, height: size * 1.04)
                .blur(radius: 3)
                .offset(y: 2)
                .opacity(0.85)

            // ── 2. Outer rim — tinted disk with 3D shading ───────────────
            Circle()
                .fill(tint)
                .overlay(
                    // Top-to-bottom shade: chip catches light up top, falls
                    // off into shadow at the bottom edge.
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.18),
                            Color.clear,
                            Color.black.opacity(0.28)
                        ],
                        startPoint: .top,
                        endPoint:   .bottom
                    )
                    .clipShape(Circle())
                )
                .overlay(
                    // Off-center radial sheen — sells the dome.
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.45),
                            Color.clear
                        ],
                        center: UnitPoint(x: 0.30, y: 0.26),
                        startRadius: 0,
                        endRadius: size * 0.55
                    )
                    .clipShape(Circle())
                    .blendMode(.softLight)
                )
                .overlay(
                    Circle()
                        .strokeBorder(Color.black.opacity(0.55), lineWidth: 0.7)
                )

            // ── 3. Eight inlaid white edge spots ─────────────────────────
            ForEach(0..<8, id: \.self) { i in
                RoundedRectangle(cornerRadius: size * 0.04, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white,
                                Color(white: 0.86)
                            ],
                            startPoint: .top,
                            endPoint:   .bottom
                        )
                    )
                    .frame(width: size * 0.16, height: size * 0.30)
                    .overlay(
                        RoundedRectangle(cornerRadius: size * 0.04,
                                         style: .continuous)
                            .strokeBorder(Color.black.opacity(0.30),
                                          lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.35),
                            radius: 0.6, x: 0, y: 0.5)
                    .offset(y: -size * 0.36)
                    .rotationEffect(.degrees(Double(i) * 45))
            }

            // ── 4. Dark separator ring ───────────────────────────────────
            Circle()
                .strokeBorder(Color.black.opacity(0.65), lineWidth: 0.8)
                .frame(width: size * 0.70, height: size * 0.70)

            // ── 5. Outer center band — slightly lighter tone of the tint
            //       so the chip reads as having a stepped center.
            Circle()
                .fill(tint)
                .overlay(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.22),
                            Color.black.opacity(0.10)
                        ],
                        startPoint: .top,
                        endPoint:   .bottom
                    )
                    .clipShape(Circle())
                )
                .frame(width: size * 0.68, height: size * 0.68)

            // ── 6. Center face — domed inset ─────────────────────────────
            Circle()
                .fill(tint)
                .overlay(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.40),
                            Color.clear,
                            Color.black.opacity(0.20)
                        ],
                        center: UnitPoint(x: 0.32, y: 0.28),
                        startRadius: 0,
                        endRadius: size * 0.32
                    )
                    .clipShape(Circle())
                )
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.5)
                )
                .frame(width: size * 0.58, height: size * 0.58)

            // ── 7. Thin inner detail ring ────────────────────────────────
            Circle()
                .strokeBorder(Color.black.opacity(0.20), lineWidth: 0.4)
                .frame(width: size * 0.46, height: size * 0.46)

            // ── 8. Center text with subtle emboss ────────────────────────
            Text(text)
                .font(.system(size: size * 0.42,
                              weight: .black,
                              design: .rounded))
                .foregroundStyle(textColor)
                .shadow(color: .black.opacity(0.45), radius: 0.6, y: 0.6)

            // ── 9. Top gloss arc — short highlight along the upper rim
            //       to suggest a glossy ceramic finish.
            Circle()
                .trim(from: 0.58, to: 0.72)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.0),
                            Color.white.opacity(0.55),
                            Color.white.opacity(0.0)
                        ],
                        startPoint: .leading,
                        endPoint:   .trailing
                    ),
                    style: StrokeStyle(lineWidth: size * 0.045,
                                       lineCap: .round)
                )
                .frame(width: size * 0.92, height: size * 0.92)
                .blendMode(.plusLighter)
                .allowsHitTesting(false)
        }
        .frame(width: size, height: size)
        .compositingGroup()
        // Muted rendering: pull saturation/contrast down so the chip recedes
        // visually next to fully-saturated action chips. Implementation note:
        // .saturation requires iOS 16+, but the project already targets 17+
        // (see other modifiers throughout this file), so it's safe.
        .saturation(muted ? 0.55 : 1.0)
        .opacity(muted ? 0.72 : 1.0)
    }
}

// ─── Pot Flow Chip ───────────────────────────────────────────────────────────

// ─── Awarding pot stack ──────────────────────────────────────────────────────
// Replaces the old PotFlowChip "+amount" capsule. When a hand resolves, the
// actual pot stack mounted at potCenter is replaced (in `potCluster`) by one
// AwardingPotStack per winner. Each stack:
//
//   1. Renders at potCenter on first frame (so the visual is continuous from
//      the static pot — the user sees the same chip stack they were watching
//      "decide" to move).
//   2. Spring-slides to the winner's seat. Spring physics give the slide
//      "weight"; ease-in-out alone reads as a UI tween rather than chips
//      being raked across the felt.
//   3. Fades to zero on arrival, simulating the chips being absorbed into
//      the winner's stack.
//
// All three timings (slide duration, fade delay, fade duration) are tuned so
// the fade *starts* roughly when the slide reaches the seat — not before
// (would look like the stack disintegrates mid-flight) and not after (would
// look like the stack hovers awkwardly over the avatar before disappearing).
private struct AwardingPotStack: View {
    let amount: Int
    let from:   CGPoint
    let to:     CGPoint

    @State private var arrived = false
    @State private var faded   = false

    var body: some View {
        PotChipStack(amount: amount)
            // Same tilt as the static pot — keeps visual continuity at the
            // moment of swap (no sudden flatten or rotate during transition).
            .tableSurfaceTilt()
            .position(arrived ? to : from)
            .opacity(faded ? 0 : 1)
            .onAppear {
                // Slide: spring with moderate response and damping ~0.85 so
                // the stack settles cleanly at the winner's seat without an
                // overshoot bounce (overshooting reads as cartoonish).
                withAnimation(.spring(response: 0.65, dampingFraction: 0.85)) {
                    arrived = true
                }
                // Fade kicks in just before the slide finishes settling, so
                // the chips appear to *arrive and dissolve* into the player's
                // stack rather than hovering then blinking out. Delay is the
                // spring's effective travel time.
                withAnimation(.easeOut(duration: 0.30).delay(0.55)) {
                    faded = true
                }
            }
    }
}

// ─── Bet chip badge ──────────────────────────────────────────────────────────
// Mini chip stack shown in front of each seat between the seat and the pot,
// scaled by amount so raises look physically heavier than calls. The stack
// renders 1..6 chips of the amount's tier color with overlapping circles to
// read as a short stack of ceramic chips on the felt.

private struct BetChipBadge: View {
    let amount: Int

    private var chipCount: Int {
        // Visual chip count grows with amount but caps to keep the stack
        // compact. Tuned so min-raises look like a short stack and all-ins
        // look like a tall one.
        switch amount {
        case ..<50:         return 1
        case 50..<200:      return 2
        case 200..<1_000:   return 3
        case 1_000..<5_000: return 4
        case 5_000..<25_000: return 5
        default:            return 6
        }
    }

    // Bumped from 14 → 18 so the detailed chip rendering (edge spots,
    // gloss arc, inner rings) actually reads at this size. Step grows
    // proportionally so taller stacks still look like real chip stacks.
    private let chipDiameter: CGFloat = 18
    private let stackStep:    CGFloat = 4

    // Tint pulled from the same ChipTier the pot uses, so action chips
    // visually match the pot in front of you (a 5K bet looks the same
    // color as the chips already in the pot at 5K).
    private var tint: Color {
        ChipTier.forAmount(amount).colors.primary
    }

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .bottom) {
                // Base shadow under the stack to anchor it to the felt.
                Ellipse()
                    .fill(Color.black.opacity(0.40))
                    .frame(width: chipDiameter * 1.15, height: 4)
                    .offset(y: 2)
                    .blur(radius: 0.6)

                ForEach(0..<chipCount, id: \.self) { i in
                    // Use the detailed PokerChip rendering (edge spots, gloss,
                    // dome shading) instead of the simple gradient icon. No
                    // center label — bet stacks read as anonymous chips and
                    // get their amount from the pill below.
                    PokerChip(
                        text: "",
                        tint: tint,
                        textColor: .white,
                        size: chipDiameter
                    )
                    .offset(y: -CGFloat(i) * stackStep)
                }
            }
            .frame(height: chipDiameter + CGFloat(chipCount - 1) * stackStep)

            // Larger, bolder amount pill so the bet size is the dominant
            // signal — outweighs the SB/BB markers and matches the pot pill
            // visual weight. 10pt → 13pt, slightly bigger horizontal pad.
            Text(formatChips(String(amount)))
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(
                    Capsule()
                        .fill(Color.black.opacity(0.65))
                        .overlay(
                            Capsule().strokeBorder(
                                Color.white.opacity(0.10),
                                lineWidth: 0.5
                            )
                        )
                )
                .contentTransition(.numericText())
        }
    }
}

// ─── Pot chip stack ──────────────────────────────────────────────────────────
// Main pot visualization — taller stack of chips sitting below the community
// cards, colored by the pot-size tier (white → red → blue → black → purple →
// gold). Amount pill sits beneath the stack.

private struct PotChipStack: View {
    let amount: Int

    private var chipCount: Int {
        // Pot stack is more generous than per-seat bet stacks. Caps at 10 so
        // it never overflows the felt.
        switch amount {
        case ..<200:          return 3
        case 200..<1_000:     return 4
        case 1_000..<5_000:   return 6
        case 5_000..<25_000:  return 8
        case 25_000..<100_000: return 9
        default:              return 10
        }
    }

    private let chipDiameter: CGFloat = 24
    private let stackStep:    CGFloat = 5

    // Tint = the same ChipTier used by the bet stacks. As bets feed the
    // pot, a 5K pot's chips look identical to the 5K chips that just
    // arrived — visually reinforces "those chips are now this stack".
    private var tint: Color {
        ChipTier.forAmount(amount).colors.primary
    }

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .bottom) {
                // Cast shadow under the stack.
                Ellipse()
                    .fill(Color.black.opacity(0.50))
                    .frame(width: chipDiameter * 1.25, height: 6)
                    .offset(y: 2)
                    .blur(radius: 1.2)

                // Detailed PokerChip rendering — same chip the BetChipBadge
                // uses, so the pot reads as "the same chips, just stacked
                // higher". The top-chip highlight overlay we used to add by
                // hand is redundant: PokerChip already has its own gloss
                // arc + dome shading on every chip.
                ForEach(0..<chipCount, id: \.self) { i in
                    PokerChip(
                        text: "",
                        tint: tint,
                        textColor: .white,
                        size: chipDiameter
                    )
                    .offset(y: -CGFloat(i) * stackStep)
                }
            }
            .frame(height: chipDiameter + CGFloat(chipCount - 1) * stackStep + 4)

            VStack(spacing: 1) {
                Text("Pot")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .tracking(0.8)
                Text(formatChips(String(amount)))
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(ChipTier.forAmount(amount).colors.primary)
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 3)
            .background(Color.black.opacity(0.45))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        ChipTier.forAmount(amount).colors.primary.opacity(0.35),
                        lineWidth: 0.5
                    )
            )
        }
    }
}

// ─── Target-style seat ───────────────────────────────────────────────────────

struct TargetSeatView: View {
    let seat:         GameSeat
    let isMe:         Bool
    let isMyTurn:     Bool
    var isWinner:     Bool = false
    let turnProgress: Double
    var turnSecondsLeft: Int = 0
    var lastAction:   LastAction?
    let avatarSize:   CGFloat
    // Showdown context — used by OpponentHoleCardsView to highlight the
    // cards in the winning combination once winners have been declared.
    var winningCardIds:     Set<String> = []
    var anyWinnersDeclared: Bool = false

    @State private var allInPulse = false
    @State private var winnerPulse = false

    // Transient action bubble: holds the label/color of this seat's most
    // recent action for ~1.8s, then clears. Decoupled from `lastAction`
    // (which the server keeps populated for the rest of the street) so the
    // bubble reads as a *notification* — pops up, settles, fades — rather
    // than a sticky tag.
    @State private var bubble: ActionKind? = nil
    // Stamp of the lastAction that produced the *currently visible* bubble.
    // Lets the dismiss-after-delay task no-op if a newer action has already
    // replaced this one (prevents racing tasks from clearing a fresh bubble).
    @State private var bubbleStamp: Int = 0

    private var plateWidth: CGFloat { avatarSize * 1.55 }

    var body: some View {
        VStack(spacing: 0) {
            // Above-avatar label slot — the transient action bubble takes
            // priority while it's visible. After it dismisses, the
            // persistent "Folded" tag (if applicable) takes over so the
            // seat still reads as folded for the rest of the hand.
            if let kind = bubble {
                Text(kind.label)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(kind.color)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                    .padding(.bottom, 3)
                    .transition(.scale.combined(with: .opacity))
            } else if seat.status == .folded {
                Text("Folded")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color(hex: "#E8A838"))
                    .padding(.bottom, 3)
            }

            ZStack {
                // Winner glow
                if isWinner {
                    Circle()
                        .strokeBorder(
                            Color(hex: "#F5C842"),
                            lineWidth: winnerPulse ? 4 : 2
                        )
                        .frame(
                            width:  avatarSize + (winnerPulse ? 16 : 8),
                            height: avatarSize + (winnerPulse ? 16 : 8)
                        )
                        .shadow(
                            color: Color(hex: "#F5C842").opacity(winnerPulse ? 0.8 : 0.3),
                            radius: winnerPulse ? 16 : 4
                        )
                }

                // Turn timer ring
                if isMyTurn {
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.06), lineWidth: 3)
                            .frame(width: avatarSize + 8, height: avatarSize + 8)

                        Circle()
                            .trim(from: 0, to: turnProgress)
                            .stroke(
                                AngularGradient(
                                    gradient: Gradient(colors: [
                                        timerColor.opacity(0.0),
                                        timerColor.opacity(0.4),
                                        timerColor,
                                        Color.white
                                    ]),
                                    center: .center,
                                    startAngle: .degrees(0),
                                    endAngle:   .degrees(360 * turnProgress)
                                ),
                                style: StrokeStyle(lineWidth: 3, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                            .frame(width: avatarSize + 8, height: avatarSize + 8)
                            .shadow(color: timerColor.opacity(0.4), radius: 4)
                            .animation(.linear(duration: 0.1), value: turnProgress)
                    }
                }

                // Avatar circle
                Circle()
                    .fill(Color(hex: "#1A2744"))
                    .overlay(
                        Circle().strokeBorder(
                            isMyTurn ? Color.white.opacity(0.6) : Color(hex: "#2A3D6A"),
                            lineWidth: isMyTurn ? 2 : 1
                        )
                    )
                    .frame(width: avatarSize, height: avatarSize)
                    .overlay(
                        Text(AvatarOption.find(seat.avatarId).emoji)
                            .font(.system(size: avatarSize * 0.58))
                    )
                    .opacity(seat.status == .folded ? 0.5 : 1.0)
                    .shadow(
                        color: seat.status == .allIn
                            ? Color(hex: "#F5C842").opacity(allInPulse ? 0.7 : 0.15)
                            : Color.black.opacity(0.4),
                        radius: seat.status == .allIn ? (allInPulse ? 10 : 3) : 5,
                        y: 2
                    )

                // Last-5-seconds countdown — sits in front of the avatar at
                // half opacity so it reads as a subtle urgency cue without
                // competing with the timer ring.
                if isMyTurn, turnSecondsLeft > 0, turnSecondsLeft <= 5 {
                    Text("\(turnSecondsLeft)")
                        .font(.system(size: avatarSize * 0.7, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                        .shadow(color: .black.opacity(0.6), radius: 2, y: 1)
                        .frame(width: avatarSize, height: avatarSize)
                        .transition(.scale.combined(with: .opacity))
                        .id(turnSecondsLeft) // retrigger transition each tick
                        .zIndex(5)
                }

                // Opponent hole cards. During the hand these render face-down;
                // at showdown the server starts populating `seat.holeCards`,
                // which triggers a flip-up + elevate animation. Cards in the
                // winning combination are then highlighted in gold while the
                // rest dim, so the winning hand reads at a glance across the
                // whole table.
                // Render the small hole-card cluster beside the avatar in
                // three cases:
                //   1. The opponent is still in the hand (face-down → flips
                //      face-up at showdown). Existing behavior.
                //   2. The opponent folded but voluntarily tapped to show
                //      one or both cards — keep the cluster mounted so the
                //      reveal has a place to render.
                // `seat.cardCount` covers both: it reflects holeCards.length
                // for live seats and mucked.length for folded seats, so
                // `hasCards` is still the correct mount predicate. The
                // status check just excludes folded-with-no-reveal so we
                // don't draw face-down cards in front of a folded seat.
                let hasShown = !seat.revealed.isEmpty
                if !isMe && seat.hasCards && (seat.status != .folded || hasShown) {
                    OpponentHoleCardsView(
                        revealedCards:      seat.holeCards,
                        cardCount:          seat.cardCount,
                        isWinner:           isWinner,
                        anyWinnersDeclared: anyWinnersDeclared,
                        winningCardIds:     winningCardIds,
                        partialReveals:     seat.revealed
                    )
                    // Tilt the cluster so the small face-down cards lie on
                    // the felt at the same angle as the community board.
                    // Applied before .offset so the card tilts in place
                    // rather than swinging the whole cluster off the avatar.
                    .tableSurfaceTilt()
                    .offset(x: -avatarSize * 0.52, y: -avatarSize * 0.15)
                    .zIndex(8)
                }

                // SB / BB markers are rendered on the felt itself (see
                // `blindRailChips` in the table layer), not pinned to the
                // avatar — that way they can't collide with the opponent
                // face-down cards or the avatar plate.

                // Disconnect indicator
                if !seat.isConnected {
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(3)
                        .background(Color.red.opacity(0.85))
                        .clipShape(Circle())
                        .offset(x: avatarSize * 0.38, y: -avatarSize * 0.38)
                }
            }
            .frame(width: avatarSize + 10, height: avatarSize + 10)

            // ── Name pill ─ slim, just the username
            Text(truncatedName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.95))
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 2.5)
                .frame(maxWidth: plateWidth)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color(hex: "#1C2030").opacity(0.92))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.45), radius: 2, y: 1)
                .offset(y: -4)

            // ── Stack pill ─ dedicated chip-amount area beneath the icon
            // Chip-tier-colored accents so the value reads at a glance and
            // ties visually to the chip stacks on the felt.
            StackPill(amount: seat.stack, status: seat.status)
                .offset(y: -2)
        }
        .onAppear {
            if seat.status == .allIn { startAllInPulse() }
            if isWinner              { startWinnerPulse() }
        }
        .onChange(of: seat.status) { _, new in
            if new == .allIn { startAllInPulse() } else { allInPulse = false }
        }
        .onChange(of: isWinner) { _, new in
            if new { startWinnerPulse() } else { winnerPulse = false }
        }
        // Drive the transient action bubble. We key on `lastAction.timestamp`
        // (server-authored, monotonically increasing) rather than the action
        // string, so successive same-action events from the same seat (e.g.
        // two checks across two streets) still re-trigger a pop. SwiftUI
        // suppresses initial-render firings, so a player who acted before
        // this view mounted won't get a stale bubble on join.
        .onChange(of: lastAction?.timestamp ?? 0) { _, newTs in
            triggerBubbleIfNeeded(timestamp: newTs)
        }
        .animation(.spring(response: 0.3), value: seat.status)
        .animation(.spring(response: 0.3), value: isMyTurn)
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: bubble?.label)
    }

    /// Pops the bubble for ~1.8s when this seat is the actor on the latest
    /// `lastAction`. The `bubbleStamp` guard prevents an older dismiss task
    /// from clearing a fresh bubble if two actions land within the window.
    private func triggerBubbleIfNeeded(timestamp: Int) {
        guard let action = lastAction,
              action.playerId == seat.userId,
              timestamp != 0,
              let baseKind = actionBubbleKind(for: action.action)
        else { return }
        // Special-case "raise to max" → render as red "All In" instead of
        // the blue Raise bubble. The slider's max button sends action=RAISE
        // with the player's full stack as the amount, so the server still
        // sees a RAISE, but the actor's seat status flips to ALL_IN on the
        // next state broadcast. We treat that combination as an all-in
        // visually so the table reads it correctly.
        let kind: ActionKind = (action.action == "RAISE" && seat.status == .allIn)
            ? ActionKind(label: "All In", color: Color(hex: "#C8344A"))
            : baseKind
        bubbleStamp = timestamp
        bubble = kind
        Task {
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            await MainActor.run {
                if bubbleStamp == timestamp {
                    bubble = nil
                }
            }
        }
    }

    private func startWinnerPulse() {
        withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
            winnerPulse = true
        }
    }

    private var truncatedName: String {
        let n = seat.username
        return n.count > 9 ? String(n.prefix(8)) + "..." : n
    }

    private var stackColor: Color {
        switch seat.status {
        case .active:  return Color(hex: "#2ECC71")
        case .folded:  return Color(hex: "#F5C842")
        case .allIn:   return Color(hex: "#F5C842")
        default:       return Color(hex: "#F5C842")
        }
    }

    private var timerColor: Color {
        if turnProgress > 0.5  { return Color(hex: "#2ECC71") }
        if turnProgress > 0.25 { return Color(hex: "#F5C842") }
        return Color(hex: "#E05555")
    }

    private func startAllInPulse() {
        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
            allInPulse = true
        }
    }

    /// Equatable so `.animation(_:value:)` can react to bubble label
    /// changes. Color isn't compared because label-uniqueness is enough —
    /// every action maps to a single label.
    private struct ActionKind: Equatable {
        let label: String
        let color: Color
        static func == (l: ActionKind, r: ActionKind) -> Bool { l.label == r.label }
    }
    private func actionBubbleKind(for raw: String) -> ActionKind? {
        switch raw {
        // Fold — red, like the Fold button. Skipped for SB/BB posts so the
        // first actions of each hand don't trigger a fake "fold" bubble on
        // anyone (SB/BB are auto-posted, not player decisions).
        case "FOLD":   return ActionKind(label: "Fold",   color: Color(hex: "#C8344A"))
        case "CHECK":  return ActionKind(label: "Check",  color: Color(hex: "#2D8B3E"))
        case "CALL":   return ActionKind(label: "Call",   color: Color(hex: "#2D8B3E"))
        case "RAISE":  return ActionKind(label: "Raise",  color: Color(hex: "#4A90E2"))
        case "ALL_IN": return ActionKind(label: "All In", color: Color(hex: "#F5C842"))
        default:       return nil
        }
    }
}

// ─── Stack Pill ──────────────────────────────────────────────────────────────
// Small dedicated chip-amount area shown beneath each seat. Color tiers
// mirror the chip stacks on the felt so the value reads at a glance:
// white → red → blue → black → purple → gold as the stack grows.

private struct StackPill: View {
    let amount: Int
    let status: PlayerStatus

    private var tier: ChipTier { ChipTier.forAmount(amount) }

    private var amountColor: Color {
        switch status {
        case .folded:       return Color.white.opacity(0.45)
        case .sittingOut,
             .disconnected: return Color.white.opacity(0.55)
        case .allIn:        return Color(hex: "#F5C842")
        default:            return tier.colors.primary
        }
    }

    private var borderColor: Color {
        switch status {
        case .folded, .sittingOut, .disconnected:
            return Color.white.opacity(0.12)
        default:
            return tier.colors.primary.opacity(0.40)
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            // Mini chip — same visual language as the felt chips, scaled
            // way down so it reads as a "chip-icon + amount" pill.
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [tier.colors.primary, tier.colors.secondary],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                Circle()
                    .strokeBorder(Color.white.opacity(0.55), lineWidth: 0.6)
                Circle()
                    .strokeBorder(
                        tier.colors.edge,
                        style: StrokeStyle(lineWidth: 0.8, dash: [1.5, 1.5])
                    )
                    .padding(2)
            }
            .frame(width: 11, height: 11)
            .opacity(status == .folded ? 0.45 : 1.0)
            .shadow(color: .black.opacity(0.35), radius: 1, y: 0.5)

            Text(formatChips(String(amount)))
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(amountColor)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(Color(hex: "#0E1220").opacity(0.92))
        )
        .overlay(
            Capsule()
                .strokeBorder(borderColor, lineWidth: 0.6)
        )
        .shadow(color: .black.opacity(0.45), radius: 3, y: 1)
    }
}

// ─── Opponent Hole Cards ─────────────────────────────────────────────────────
// Renders the small pair of hole cards beside an opponent's avatar. Three
// states, in order:
//   1. Hidden — face-down rectangles (during the hand)
//   2. Revealed — flips face-up the moment the server sends `holeCards`
//      (i.e. at showdown). Cards lift slightly off the seat to read clearly.
//   3. Resolved — once winners are declared, cards in the winning hand glow
//      gold; cards that aren't part of the winning combo dim and desaturate.

private struct OpponentHoleCardsView: View {
    let revealedCards:      [PokerCard]?
    let cardCount:          Int
    let isWinner:           Bool
    let anyWinnersDeclared: Bool
    let winningCardIds:     Set<String>
    // Voluntary tap-to-show reveals from the seat's owner — partial (one or
    // both indices) and may arrive at any time during/after the hand,
    // including after they've folded. We render face-up specifically at
    // the matching slot index, leaving any non-shown slots face-down.
    var partialReveals:     [RevealedCard] = []

    @State private var revealed:   Bool    = false
    @State private var flipScaleX: CGFloat = 1
    @State private var lifted:     Bool    = false
    @State private var glowPulse:  Bool    = false

    private var hasReveal: Bool { (revealedCards?.count ?? 0) > 0 }
    // Lookup helper — slot i → voluntarily-shown card if any. Used by
    // `cardSlot` to override the face-down placeholder when the owner has
    // tapped that slot.
    private func revealedAt(_ i: Int) -> PokerCard? {
        partialReveals.first(where: { $0.index == i })?.card
    }
    private let cardSize: PlayingCardView.CardSize = .custom(22)

    var body: some View {
        HStack(spacing: -6) {
            ForEach(0..<displayCount, id: \.self) { i in
                cardSlot(at: i)
                    .rotationEffect(.degrees(Double(i) * 5 - 5))
            }
        }
        .scaleEffect(x: flipScaleX, y: 1)
        .scaleEffect(lifted ? 1.55 : 1.0)
        .offset(y: lifted ? -10 : 0)
        .shadow(color: .black.opacity(lifted ? 0.6 : 0.3),
                radius: lifted ? 8 : 2,
                y: lifted ? 4 : 1)
        .shadow(color: (isWinner && glowPulse) ? Color(hex: "#F5C842").opacity(0.7) : .clear,
                radius: 14)
        .animation(.spring(response: 0.45, dampingFraction: 0.78), value: lifted)
        .onAppear {
            // Late-joiner safety: if the seat already has revealed cards when
            // this view first mounts (e.g. user opened the app mid-showdown),
            // jump straight to the revealed state without animating.
            if hasReveal {
                revealed = true
                lifted   = true
            }
            if isWinner { startGlowPulse() }
        }
        .onChange(of: hasReveal) { _, new in
            if new { runRevealSequence() }
        }
        .onChange(of: isWinner) { _, new in
            if new { startGlowPulse() } else { glowPulse = false }
        }
    }

    private var displayCount: Int {
        max(min(hasReveal ? (revealedCards?.count ?? 0) : cardCount, 4), 0)
    }

    @ViewBuilder
    private func cardSlot(at i: Int) -> some View {
        // Voluntarily-shown card at this slot wins over showdown-revealed —
        // both populate the same visual position, but partial reveals can
        // arrive earlier (mid-hand fold-show) and should display the moment
        // the server broadcasts them, not wait for the showdown flip
        // sequence.
        if let shown = revealedAt(i) {
            // Soft white glow ring marks the card as voluntarily shown so
            // it's distinguishable from a normal showdown reveal.
            PlayingCardView(card: shown, size: cardSize, coloredBackground: true)
                .overlay(
                    RoundedRectangle(cornerRadius: cardSize.cornerRadius)
                        .strokeBorder(Color.white.opacity(0.85), lineWidth: 1.4)
                )
                .shadow(color: Color.white.opacity(0.45), radius: 6)
                .transition(.scale(scale: 0.6).combined(with: .opacity))
        } else if revealed, let cards = revealedCards, i < cards.count {
            let card = cards[i]
            let isWinningCard = winningCardIds.contains(card.id)
            // Once winners are declared, dim cards that aren't part of the
            // winning hand so the gold-bordered ones pop.
            let dim = anyWinnersDeclared && !isWinningCard
            // Match the community-card 4-color treatment so when opponent
            // hole cards flip up at showdown, the whole table reads in the
            // same suit-tinted palette (red hearts / blue diamonds /
            // green clubs / black spades).
            PlayingCardView(card: card, size: cardSize, coloredBackground: true)
                .overlay(
                    RoundedRectangle(cornerRadius: cardSize.cornerRadius)
                        .strokeBorder(
                            isWinningCard ? Color(hex: "#F5C842") : Color.clear,
                            lineWidth: 1.6
                        )
                )
                .shadow(color: isWinningCard ? Color(hex: "#F5C842").opacity(0.6) : .clear,
                        radius: 5)
                .saturation(dim ? 0.5 : 1.0)
                .opacity(dim ? 0.55 : 1.0)
        } else {
            cardBack
        }
    }

    private var cardBack: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(
                LinearGradient(
                    colors: [Color(hex: "#2D2D4A"), Color(hex: "#1A1A30")],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            )
            .frame(width: 18, height: 24)
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
            )
    }

    // X-axis squish-flip → swap to face-up → expand. Then a small spring
    // lift settles the cards above the seat so they read as "presented".
    private func runRevealSequence() {
        withAnimation(.easeIn(duration: 0.14)) { flipScaleX = 0.001 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
            revealed = true
            withAnimation(.easeOut(duration: 0.14)) { flipScaleX = 1 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.34) {
            lifted = true
        }
    }

    private func startGlowPulse() {
        withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
            glowPulse = true
        }
    }
}

// ─── Empty Seat ──────────────────────────────────────────────────────────────

struct TargetEmptySeat: View {
    let avatarSize: CGFloat
    var body: some View {
        // Match the seated layout's vertical footprint (avatar + name pill +
        // stack pill) so empty seats sit at the same rim height as filled
        // ones — no jagged misalignment around the table.
        VStack(spacing: 3) {
            Circle()
                .strokeBorder(
                    Color.white.opacity(0.08),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                )
                .frame(width: avatarSize, height: avatarSize)
                .overlay(
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.18))
                )
            Text("Open")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.30))
                .padding(.horizontal, 10)
                .padding(.vertical, 2.5)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color(hex: "#1C2030").opacity(0.55))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
                )
                .offset(y: -2)

            // Placeholder dash to match the stack-pill height on filled seats.
            Text("—")
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .foregroundStyle(.white.opacity(0.15))
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color(hex: "#0E1220").opacity(0.45)))
        }
    }
}

// ─── Table Theme ──────────────────────────────────────────────────────────────
// Felt color presets chosen in Settings. Persisted via @AppStorage
// ("tableThemeId"). Read here by PokerTableView and GameView for live updates.

struct TableTheme: Identifiable, Equatable {
    let id: String
    let label: String
    // Three-stop radial gradient for the felt.
    let inner: String
    let mid:   String
    let edge:  String
    // Room background (gradient behind the felt).
    let roomTop:    String
    let roomBottom: String

    static let all: [TableTheme] = [
        TableTheme(id: "classic_blue", label: "Classic Blue",
                   inner: "#1E5BA8", mid: "#143E7A", edge: "#0C2850",
                   roomTop: "#05070D", roomBottom: "#0A1F44"),
        TableTheme(id: "emerald", label: "Emerald",
                   inner: "#1E8A5F", mid: "#0F5E3E", edge: "#08351F",
                   roomTop: "#060B08", roomBottom: "#0B2A1C"),
        TableTheme(id: "crimson", label: "Crimson",
                   inner: "#B0394A", mid: "#7A1F2B", edge: "#3F0A12",
                   roomTop: "#0D0406", roomBottom: "#2A0B11"),
        TableTheme(id: "royal_purple", label: "Royal Purple",
                   inner: "#6B4CC5", mid: "#44288F", edge: "#1F1252",
                   roomTop: "#07060D", roomBottom: "#1E1640"),
        TableTheme(id: "midnight", label: "Midnight",
                   inner: "#2D3847", mid: "#1A222E", edge: "#0A0F17",
                   roomTop: "#030506", roomBottom: "#0B1219"),
        TableTheme(id: "bourbon", label: "Bourbon",
                   inner: "#C68E3C", mid: "#8A5A1E", edge: "#3F2807",
                   roomTop: "#0C0805", roomBottom: "#2A1B08"),
    ]

    static func find(_ id: String) -> TableTheme {
        all.first { $0.id == id } ?? all[0]
    }

    var primaryColor: Color { Color(hex: inner) }
    var edgeColor:    Color { Color(hex: edge) }
}

// ─── Felt Texture ─────────────────────────────────────────────────────────────
// Procedural cloth weave drawn into a Canvas — small light/dark speckle dots
// at deterministic pseudorandom positions (seeded LCG so the pattern is stable
// across renders and identical for every table). The result is a subtle noise
// that breaks up the gradient and reads as fabric instead of plastic.

private struct FeltTexture: View {
    private struct Dot { let x: CGFloat; let y: CGFloat; let alpha: Double; let size: CGFloat; let light: Bool }

    private static let dots: [Dot] = {
        // Seeded linear-congruential generator → deterministic, no Foundation rand.
        var state: UInt64 = 0x9E3779B97F4A7C15
        func next() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 11) / Double(1 << 53)
        }
        var arr: [Dot] = []
        arr.reserveCapacity(520)
        for i in 0..<520 {
            arr.append(Dot(
                x: CGFloat(next()),
                y: CGFloat(next()),
                alpha: 0.022 + next() * 0.060,
                size: 0.5 + CGFloat(next()) * 1.2,
                light: i % 2 == 0
            ))
        }
        return arr
    }()

    var body: some View {
        Canvas { ctx, size in
            for d in Self.dots {
                let rect = CGRect(
                    x: d.x * size.width,
                    y: d.y * size.height,
                    width: d.size,
                    height: d.size
                )
                let color: Color = d.light
                    ? Color.white.opacity(d.alpha)
                    : Color.black.opacity(d.alpha * 0.75)
                ctx.fill(Path(ellipseIn: rect), with: .color(color))
            }
        }
        .blendMode(.overlay)
        .opacity(0.85)
    }
}
