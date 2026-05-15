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

    // Felt dimensions — sized to fill ~92% of available width while
    // preserving the poker_table.png intrinsic aspect ratio (1 : 1.5 W:H).
    // The image is the source of truth for the silhouette now, so the frame
    // matches it exactly — no more letterboxing inside a taller pill.
    // Landscape kept on the old oval math (image is portrait-shaped;
    // landscape framing is a follow-up if it ends up looking off).
    var tableWidth: CGFloat {
        if isLandscape { return min(size.width - 48, size.height * 1.6) }
        // Portrait: 92% screen width, with a height-derived guard so a very
        // short screen (iPhone SE) doesn't push the bottom of the table
        // under the action bar.
        return min(size.width * 0.92, size.height * 0.92 / 1.5)
    }
    var tableHeight: CGFloat {
        if isLandscape { return tableWidth / 1.6 }
        // Locked to the image's 1.5× height-to-width ratio.
        return tableWidth * 1.5
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
    // Sized so the 5-card row spans ~64% of the table width, leaving
    // comfortable breathing room against the narrower middle felt section
    // of the new poker_table.png illustration. Total span =
    // 5 * cardWidth + 4 * cardSpacing = 5*0.112 + 4*0.020 = 0.640.
    // Width factor was 0.145 prior to the 2026-05-15 image swap — at that
    // size all five river cards crowded into the inner rim where the new
    // illustration narrows toward the back. Spacing factor unchanged; at
    // the smaller card size the same absolute gap is proportionally more
    // breathing room (~18% of card width vs ~14% before).
    // Aspect ratio (1:1.4) is preserved inside CommunityCardsView.
    var cardWidth: CGFloat { tableWidth * 0.112 }
    var cardSpacing: CGFloat { tableWidth * 0.020 }

    // Center layout positions (all relative to tableCenter).
    // Tuned for the tall pill felt: community cards high, pot stack sits
    // directly below the cards, then NLH/Blinds/Hosted by stack toward the
    // bottom. Watermark is tucked at the very bottom so it doesn't compete.
    var boardCenter: CGPoint {
        // y-offset reduced from 0.12 → 0.09 of tableHeight. The original
        // 0.12 placed the leftmost/rightmost flop cards at the same vertical
        // band as the upper-side seats (angles 210° / 330° in 6-max), and the
        // avatar's name plate (avatarSize × 1.55 wide) clipped the right
        // corner of the leftmost card by ~1pt on phone-sized felts — exactly
        // where the rank glyph lives, so the number became unreadable. A
        // 0.03 drop shifts the cards ~8pt downward (relative to a 280pt
        // tableHeight), restoring clearance under the side seats while
        // keeping a comfortable gap above the pot stack at potCenter
        // (`tableHeight * 0.04` below center). Pure layout change, no
        // animation interaction.
        CGPoint(x: tableCenter.x, y: tableCenter.y - tableHeight * 0.09)
    }
    var potCenter: CGPoint {
        // Bumped from 0.04 → 0.10 of tableHeight. The pot VStack is taller
        // than it looks at first glance — chip stack (up to ~73pt for big
        // pots) plus the "Pot" + amount text below (~28pt) — so when it was
        // centered at +0.04 the top of the chip stack reached ~34pt above
        // table center, while the bottom edge of the community cards (at
        // boardCenter -0.09) sat at ~+5pt. That ~40pt overlap was the chip
        // stack visibly clipping the cards. 0.10 gives clean separation
        // without crowding gamePillCenter (still at 0.19).
        CGPoint(x: tableCenter.x, y: tableCenter.y + tableHeight * 0.10)
    }
    // gamePillCenter and blindsCenter pushed down (was 0.19 / 0.26) so the
    // NLH pill + small/big-blind label sit visually closer to the bottom rim
    // and don't crowd the pot stack. Kept the 0.07 gap between the two so
    // the row spacing is unchanged.
    var gamePillCenter: CGPoint {
        CGPoint(x: tableCenter.x, y: tableCenter.y + tableHeight * 0.24)
    }
    var blindsCenter: CGPoint {
        CGPoint(x: tableCenter.x, y: tableCenter.y + tableHeight * 0.31)
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

// TODO: Dead code after poker_table.png swap (2026-05-15).
// Remove in follow-up cleanup commit unless procedural rendering is revived.
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

    // TODO: Dead code after poker_table.png swap (2026-05-15).
    // Remove in follow-up cleanup commit unless procedural rendering is revived.
    // (GameView still reads tableThemeId for the room background gradient;
    // only this view's local @AppStorage + theme are orphaned.)
    // Felt theme — read from user settings. Defaults to classic blue. Changes
    // in the settings sheet propagate here live via @AppStorage.
    @AppStorage("tableThemeId") private var tableThemeId: String = "classic_blue"
    private var theme: TableTheme { TableTheme.find(tableThemeId) }

    // Tapping an empty seat surfaces this confirmation dialog so the user
    // can fill the seat with a bot (or, when more options arrive, an invite).
    @State private var showOpenSeatSheet = false

    // Tapping the "Invite Friends" action in the open-seat dialog opens the
    // existing InviteFriendsSheet (the same one the lobby uses) constrained
    // to currently-online friends. We use `.fullScreenCover`-friendly state
    // here rather than the lobby VM's `showInviteFriendsSheet` because the
    // game scene is itself presented as a fullScreenCover — chaining a
    // sheet through that env ObservableObject would race with dismissal.
    @State private var showInviteFriendsSheet = false

    // Tapping an opponent seat opens the quick-profile popup. Identified by
    // userId so we don't have to hold a stale GameSeat snapshot — the popup
    // pulls fresh stats from the server keyed off the userId.
    @State private var profilePopupUserId: String? = nil

    // LobbyViewModel comes from the same env the lobby itself uses (set on
    // MainTabView). We need it to access `lastTable` (the currently-joined
    // table id used as the invite target) and the `inviteFriend` action.
    // Available because fullScreenCover propagates @EnvironmentObject from
    // the presenting view.
    @EnvironmentObject private var lobbyVM: LobbyViewModel

    // Friends list for the invite sheet. Owned locally because the lobby's
    // FriendsViewModel is a @StateObject scoped to LobbyView and isn't in
    // the env. The sheet's `.task` calls loadFriends() so the list arrives
    // populated; nothing else in the game scene needs friends data.
    @StateObject private var friendsVM = FriendsViewModel()

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
                // PERF: The felt + brand are static during a hand. Wrapping
                // them in their own ZStack lets us avoid hanging implicit
                // animations on the rest of the layout from the (now-moved)
                // .animation(value:) modifiers below — those used to live on
                // the whole root ZStack which forced SwiftUI to walk every
                // child (including the 520-dot felt Canvas) in the animation
                // transaction whenever the pot, board, or bets changed.
                feltOval(layout)
                brandMark(layout)
                potCluster(layout)
                    // Pot scale-in / migrate happens on totalPot change.
                    .animation(.easeInOut(duration: 0.3), value: vm.gameState?.totalPot)
                communityBoard(layout)
                    // Flop/turn/river deal animates communityBoard only.
                    .animation(.easeInOut(duration: 0.3), value: vm.gameState?.communityCards.count)
                // Replaces the previous trio (gamePill / blindsLabel /
                // hostedByLabel). Game type + blinds in a single low-key
                // pill keeps the bottom of the felt readable instead of
                // stacking three separate text rows on top of each other.
                tableInfoPill(layout)
                blindRailChips(layout)
                betChipsLayer(layout)
                    // Slightly slower spring with lighter damping = chips
                    // have "weight" as they migrate to the pot. Response
                    // 0.65 gives a ~0.65s arc; damping 0.78 lets the pot
                    // stack do a tiny settle overshoot when it scales in,
                    // which reads as chips landing.
                    .animation(.spring(response: 0.65, dampingFraction: 0.78), value: betsSignature)
                // potFlowLayer removed — the pot stack itself now slides to
                // the winner via potCluster's AwardingPotStack. Keeping the
                // old separate flying-chip layer would double up animations.
                winningHandBanner(layout)

                // ── Seat overlay
                seatOverlay(layout)
            }
            // Tapping an open seat now goes straight to a slide-up
            // InviteFriendsSheet (online friends only). The previous
            // confirmationDialog was a two-step UX — pick "Invite Friends"
            // → sheet — and the "bots are disabled" copy lived in the
            // dialog's message so users never saw it once we removed the
            // dialog. Bot fallback now rides inside the sheet itself
            // (via `onAddBot`) so a single sheet covers both paths.
            //
            // `showOpenSeatSheet` is still the binding fired from the
            // empty-seat tap gesture; we just route it to the sheet
            // directly. Resetting the lobby VM's "already-invited" set
            // each time keeps multi-seat invite flows clean.
            .sheet(
                isPresented: $showOpenSeatSheet,
                onDismiss: { lobbyVM.resetInviteSheet() }
            ) {
                InviteFriendsSheet(
                    vm: lobbyVM,
                    fvm: friendsVM,
                    // Show every friend regardless of presence. The previous
                    // `onlineOnly: true` filter hid a freshly-accepted friend
                    // any time they weren't connected — the user complaint
                    // was "I added a friend, he's in Friends, but not in the
                    // invite sheet". Push notifications wake offline
                    // recipients, so excluding them just penalises new
                    // friendships. Each row's invite button still works the
                    // same; the recipient simply receives the notification
                    // when they next launch the app.
                    onAddBot: botsAllowedHere ? { [weak vm = vm] in
                        vm?.addBot()
                        showOpenSeatSheet = false
                    } : nil,
                    addBotDisabled: hasBotSeated
                )
            }
            // Legacy binding kept around in case any other code path
            // flips it; no-op now that the open-seat tap drives the
            // sheet directly above. Safe to remove if a future audit
            // confirms nothing else writes to it.
            .sheet(isPresented: $showInviteFriendsSheet) {
                InviteFriendsSheet(vm: lobbyVM, fvm: friendsVM)
            }
            // Quick-profile popup overlays the entire GeometryReader so the
            // dimming scrim covers the whole table (not just the seat zone).
            // We key the OpponentPopupView on userId so SwiftUI tears it down
            // and rebuilds when switching from one opponent to another —
            // otherwise the previous opponent's stats would briefly show
            // before the new fetch resolves.
            .overlay {
                if let uid = profilePopupUserId {
                    OpponentPopupView(
                        userId: uid,
                        onDismiss: {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                                profilePopupUserId = nil
                            }
                        }
                    )
                    .id(uid)
                    .zIndex(100)
                }
            }
            .animation(.spring(response: 0.32, dampingFraction: 0.85), value: profilePopupUserId)
        }
    }

    private var betsSignature: String {
        seats.map { "\($0.userId):\($0.betThisStreet)" }.joined(separator: "|")
    }

    // ─── Felt + rail ──────────────────────────────────────────────────────────
    // Previously a 13-layer stack of TablePerspectiveShape fills/strokes plus
    // FeltTexture (cast shadow, ink shadow, underside skirt + front-lip
    // highlight, padded leather rail with top specular + bottom AO, inner
    // bevel, saddle stitching, inner rim gleam, themed felt radial gradient,
    // cloth weave, top-light, bowl vignette, ink rim, directional contact
    // shadow, inset betting line). Replaced 2026-05-15 with a single
    // illustrated PNG (poker_table.png in Assets.xcassets). The image carries
    // the rail / felt / shadows / texture all baked in.
    //
    // Geometry preserved verbatim: tableWidth/tableHeight/tableCenter from
    // TableLayout still drive the image's frame and position, so every
    // sibling layer (seats, community cards, pot, dealer button, bet chips,
    // brand mark) keeps its existing anchor. The image is `.aspectRatio(.fit)`
    // inside that frame, so its silhouette ratio (intrinsic 1 : 1.5) and the
    // pill's frame ratio (1 : 1.65 in portrait) will produce ~9% of empty
    // space at the top + bottom of the frame — top/bottom seats may float
    // past the painted rim. Per-item tableSurfaceTilt() and topRatio: 0.84
    // intentionally left untouched in this commit — visual swap only,
    // positioning math is a follow-up.
    //
    // TODO: Dead code after poker_table.png swap (2026-05-15).
    // The orphaned procedural rendering helpers (TablePerspectiveShape,
    // railLayer, feltSurface, FeltTexture, railWidth static, the
    // PokerTableView-local @AppStorage("tableThemeId") + theme) are kept in
    // place pending a cleanup commit. Remove unless procedural rendering is
    // revived.
    private static let railWidth: CGFloat = 22

    private func feltOval(_ l: TableLayout) -> some View {
        Image("poker_table")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: l.tableWidth, height: l.tableHeight)
            .position(x: l.tableCenter.x, y: l.tableCenter.y)
            .allowsHitTesting(false)
    }

    // TODO: Dead code after poker_table.png swap (2026-05-15).
    // Remove in follow-up cleanup commit unless procedural rendering is revived.
    // ── Rail (padded leather) ────────────────────────────────────────────────

    private func railLayer(outerW: CGFloat,
                           outerH: CGFloat,
                           outerCR: CGFloat,
                           topRatio: CGFloat) -> some View {
        ZStack {
            // Base rail — warm-black leather body. Subtle top→bottom
            // gradient (rather than the previous flat fill) gives the
            // rail a hint of a rounded cushion: brighter at the top edge
            // where it would catch overhead light, deeper at the bottom
            // where it falls into shadow before meeting the felt.
            TablePerspectiveShape(topRatio: topRatio)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: "#3A2818"),
                            Color(hex: "#241814"),
                            SPRetro.ink,
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .frame(width: outerW, height: outerH)

            // Top-edge specular — narrow warm sheen biased to the very
            // top of the rail simulating a light source above and behind
            // the player. Reads as a leather lip catching light, which
            // is what pushes the rail from "flat ink panel" toward
            // "padded cushion you could rest your elbows on".
            TablePerspectiveShape(topRatio: topRatio)
                .stroke(
                    LinearGradient(
                        stops: [
                            .init(color: Color(hex: "#C9A574").opacity(0.55), location: 0.00),
                            .init(color: Color(hex: "#8A6038").opacity(0.20), location: 0.20),
                            .init(color: Color.clear,                          location: 0.45),
                        ],
                        startPoint: .top, endPoint: .bottom
                    ),
                    lineWidth: 2.5
                )
                .frame(width: outerW - 2, height: outerH - 2)

            // Bottom-edge ambient occlusion — subtle ink darkening along
            // the lower rim where the rail meets the skirt. Sells the
            // physical seam between the cushion and the underside.
            TablePerspectiveShape(topRatio: topRatio)
                .stroke(
                    LinearGradient(
                        stops: [
                            .init(color: Color.clear,                       location: 0.55),
                            .init(color: Color.black.opacity(0.45),         location: 1.00),
                        ],
                        startPoint: .top, endPoint: .bottom
                    ),
                    lineWidth: 2
                )
                .frame(width: outerW - 1, height: outerH - 1)
        }
        .allowsHitTesting(false)
    }

    // TODO: Dead code after poker_table.png swap (2026-05-15).
    // Remove in follow-up cleanup commit unless procedural rendering is revived.
    // ── Felt surface ─────────────────────────────────────────────────────────

    private func feltSurface(_ l: TableLayout, cr: CGFloat) -> some View {
        let tr = l.topRatio

        return TablePerspectiveShape(topRatio: tr)
            .fill(
                // Retro 3-stop gradient. Themes are now same-hue triples
                // (inner = lighter shade, mid = identity, edge = darker
                // shade), so the radial reads as a coherent color block on
                // the paper page rather than the old paper→theme→ink
                // sequence that created a heavy vignette. Start radius
                // widened from 3% → 14% so there's no bright pinprick
                // spotlight at the center.
                RadialGradient(
                    colors: [
                        Color(hex: theme.inner),
                        Color(hex: theme.mid),
                        Color(hex: theme.edge),
                    ],
                    center: UnitPoint(x: 0.5, y: 0.42),
                    startRadius: l.tableWidth * 0.14,
                    endRadius: l.tableWidth * 0.74
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
                    // ── Top-light highlight ──────────────────────────────
                    // Soft white wash biased toward the upper portion of
                    // the felt — simulates an overhead room light catching
                    // the cloth's high point. This is what reads as a
                    // concave bowl when paired with the perimeter darkening
                    // below: bright center-top, dark edges = curvature.
                    TablePerspectiveShape(topRatio: tr)
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color.white.opacity(0.18),
                                    Color.white.opacity(0.06),
                                    Color.clear,
                                ],
                                center: UnitPoint(x: 0.5, y: 0.30),
                                startRadius: l.tableWidth * 0.05,
                                endRadius: l.tableWidth * 0.55
                            )
                        )
                        .frame(width: l.tableWidth, height: l.tableHeight)
                        .blendMode(.plusLighter)

                    // Bowl vignette — stronger than the previous flat 0.20
                    // ink wash. Pushes the edges into shadow so the felt
                    // reads as a sunken concave surface, not a flat decal.
                    TablePerspectiveShape(topRatio: tr)
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color.clear,
                                    Color(hex: "#0F0A06").opacity(0.20),
                                    Color(hex: "#0F0A06").opacity(0.55),
                                ],
                                center: UnitPoint(x: 0.5, y: 0.42),
                                startRadius: l.tableWidth * 0.22,
                                endRadius: l.tableWidth * 0.78
                            )
                        )
                        .frame(width: l.tableWidth, height: l.tableHeight)

                    // Thin ink rim — flat hairline just inside the felt
                    // edge. Reads as a stamped boundary between felt and
                    // rail and anchors the bowl shape against the rail.
                    TablePerspectiveShape(topRatio: tr)
                        .stroke(SPRetro.ink.opacity(0.65), lineWidth: 1.5)
                        .frame(width: l.tableWidth - 2, height: l.tableHeight - 2)

                    // ── Directional contact shadow ───────────────────────
                    // Light source above-front: the bottom (forward) edge
                    // of the felt sits in heavier shadow than the top
                    // (back) edge. Strengthened from 0.18 → 0.32 so the
                    // bowl reads as physically receding from the viewer.
                    TablePerspectiveShape(topRatio: tr)
                        .fill(
                            LinearGradient(
                                stops: [
                                    .init(color: Color.clear,               location: 0.55),
                                    .init(color: Color.black.opacity(0.32), location: 1.00),
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
            // Retro game-info pill — paper face + ink divider + ink text.
            // Reads as a print-shop credit line below the pot.
            HStack(spacing: 8) {
                Text(game)
                    .font(.custom("AmericanTypewriter-Bold", size: 10))
                    .tracking(1.5)
                    .foregroundStyle(SPRetro.ink)
                Rectangle()
                    .fill(SPRetro.ink.opacity(0.45))
                    .frame(width: 1, height: 10)
                Text("\(sb) / \(bb)")
                    .font(.custom("AmericanTypewriter", size: 10))
                    .foregroundStyle(SPRetro.inkSoft)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(SPRetro.paper)
                    .overlay(
                        Capsule().strokeBorder(
                            SPRetro.ink,
                            lineWidth: 1.5
                        )
                    )
            )
            // Sits where the old gamePill was — closest to the pot, far
            // enough above the watermark to leave breathing room.
            .position(x: l.gamePillCenter.x, y: l.gamePillCenter.y)
            .allowsHitTesting(false)
        }
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
                // Retro SB/BB chips — pop blue (SB) / pop red (BB) on the
                // paper felt. textColor = paper so the letters stay legible
                // on the saturated chip face.
                let tint = seat.isSmallBlind
                    ? SPRetro.popBlue
                    : SPRetro.popRed
                let label = seat.isSmallBlind ? "SB" : "BB"
                PokerChip(text: label,
                          tint: tint,
                          textColor: SPRetro.paper,
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
                    // Every seat is wrapped in TickingSeat — the same
                    // struct type at this position regardless of who is
                    // currently active. SwiftUI keys @State to the view's
                    // type + position in the tree, so a stable wrapper is
                    // what preserves TargetSeatView's `@State bubble` when
                    // a player transitions from active → not-active after
                    // taking their action. Previously this slot branched
                    // between TickingSeat and TargetSeatView, which SwiftUI
                    // saw as two different types — every turn change tore
                    // down/recreated the inner view, wiped its bubble
                    // @State, and the bubble that should have popped up
                    // for the just-acted player vanished before render.
                    //
                    // Perf cost of always-observing the clock: TickingSeat's
                    // body re-evaluates at 5Hz for every seat (6 cheap
                    // struct constructions/sec). The inner TargetSeatView
                    // only re-evaluates when its stored inputs differ; for
                    // non-active seats we pass constant `turnProgress: 1.0`
                    // and `turnSecondsLeft: 0`, so SwiftUI's diff detects
                    // no input change and skips the body. Same optimization
                    // as the original split, without breaking @State
                    // identity.
                    TickingSeat(
                        clock: vm.turnClock,
                        seat: seat,
                        isMe: isMe,
                        isMyTurn: isActive,
                        isWinner: isWinner,
                        lastAction: vm.gameState?.lastAction,
                        avatarSize: l.seatAvatarSize,
                        winningCardIds: winnerCardIds,
                        anyWinnersDeclared: !winnerIds.isEmpty,
                        onProfileTap: { profilePopupUserId = seat.userId }
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
        // Only surface winning-card highlights when the hand was actually
        // contested (≥ 2 seats reached showdown). On an uncontested win
        // (everyone but one player folded) there's no showdown and no
        // "better hand" to celebrate — lighting up the lone remaining
        // player's cards reads as a glitch since there was nothing to beat.
        guard isContestedShowdown,
              let winners = vm.gameState?.winners else { return [] }
        return Set(winners.flatMap { $0.bestCards.map { $0.id } })
    }

    /// True when the hand reached a real showdown — at least two seats
    /// finished the hand without folding. Uncontested wins (single non-
    /// folded seat) flip this to false so the table suppresses the
    /// winner gold ring / glow / card highlights, since "winning" by
    /// fold-equity isn't a hand-vs-hand outcome to highlight.
    private var isContestedShowdown: Bool {
        guard let seats = vm.gameState?.seats else { return false }
        // Status reflects each seat's posture at hand end. .active and
        // .allIn both count as "in the pot at showdown"; sittingOut /
        // waiting / disconnected / folded are out.
        let inPot = seats.filter {
            $0.status == .active || $0.status == .allIn
        }
        return inPot.count >= 2
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
            // PERF: pre-joined into a single String so the de-dupe + join
            // doesn't reallocate on every body invalidation while the
            // banner is on-screen (which is also when chips are flying to
            // winners — the hot path we're trying to keep smooth).
            let joined = winningBannerLabel(winners: winners)
            // Retro winning-hand banner — mustard paper pill with ink border
            // and an ink "WINNING HAND" stamp above the hand name. Uses
            // SPRetro tokens so the colors/fonts stay in lockstep with the
            // rest of the retro surfaces (lobby pills, daily bonus, etc.)
            // rather than drifting from hard-coded hex.
            VStack(spacing: 2) {
                Text("WINNING HAND")
                    .font(SPRetroFonts.headline(9))
                    .foregroundStyle(SPRetro.ink)
                    .tracking(1.8)
                Text(joined)
                    .font(SPRetroFonts.display(16))
                    .foregroundStyle(SPRetro.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            // Background ZStack: ink "shadow plate" capsule offset behind
            // the face capsule, instead of a `.shadow()` modifier on the
            // whole VStack. `.shadow()` rasterizes the entire subtree —
            // text glyphs included — which produced a "doubled text" look
            // on "WINNING HAND" / hand-name. Shape-only offset gives the
            // same comic-panel feel with crisp text.
            .background(
                ZStack {
                    Capsule()
                        .fill(SPRetro.ink.opacity(0.75))
                        .offset(x: 2, y: 3)
                    Capsule()
                        .fill(SPRetro.mustard)
                        .overlay(
                            Capsule().strokeBorder(SPRetro.ink, lineWidth: 2)
                        )
                }
            )
            // Lowered from `-tableHeight * 0.02` (just above center) to
            // `+tableHeight * 0.05` (just below center) so the banner clears
            // the bottom edge of the (enlarged) community board, which sits
            // at `-tableHeight * 0.12`. Previously the banner's top edge
            // grazed the board cards on tall tables and obscured the river
            // card during the showdown reveal.
            .position(
                x: l.tableCenter.x,
                y: l.tableCenter.y + l.tableHeight * 0.05
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
        // Same contested-showdown gate as winnerCardIds: don't mark a seat
        // as a "winner" for visual purposes when it just outlasted folds.
        // This collapses the gold avatar ring + winnerPulse + the
        // OpponentHoleCardsView card glow back to their resting state on
        // uncontested wins, all from a single source-of-truth check.
        guard isContestedShowdown,
              let winners = vm.gameState?.winners else { return [] }
        return Set(winners.map { $0.playerId })
    }

    // Show only the *best* hand name from the showdown, not every winning
    // hand. In a side-pot scenario, two different players can each win a
    // pot with different hand ranks (e.g. all-in full house wins main,
    // larger flush wins side pot) — joining them produced confusing
    // banners like "Flush · Full House" that imply a split.
    //
    // The backend builds payouts by iterating pots starting at the main
    // pot (potManager.ts:distributePots), so winners[0] is always the
    // main pot winner. By definition the main pot contests all eligible
    // hands at showdown, so its winner has the highest-ranked hand.
    //
    // We recompute the label client-side via `HandStrength.label(hole:board:)`
    // using the winner's hole cards + the community board. This is the *same*
    // source the under-card subtitle reads from, so the banner and the text
    // beneath the winning player's cards always match — including PLO's
    // "Quads" rename (server still emits "Four of a Kind") and the PLO 2+3
    // restriction that keeps a 3-hearts-in-hand / 2-on-board combo from being
    // labeled "Flush". Falls back to `WinnerPayout.handName` if the winner's
    // hole cards aren't available (shouldn't happen at showdown — server
    // reveals them — but the fallback keeps the banner present rather than
    // blank in that edge case).
    private func winningBannerLabel(winners: [WinnerPayout]) -> String {
        guard let top = winners.first else { return "" }
        if let seat = vm.gameState?.seats.first(where: { $0.userId == top.playerId }),
           let hole = seat.holeCards, !hole.isEmpty {
            let board = vm.gameState?.communityCards ?? []
            if let lbl = HandStrength.label(hole: hole, board: board) {
                return lbl
            }
        }
        return top.handName
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
        case .gold:   return (SPRetro.mustard, Color(hex: "#D4A520"), Color(hex: "#B8860B"))
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

// Exposed (was `private`) so the lobby's chip-balance pill and filter chips
// can reuse the same physical-chip rendering instead of inventing a parallel
// "circle with text" component. Internal — still scoped to the StackPoker
// module, just visible across files.
struct PokerChip: View {
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
                // Retro pot pill — paper face + ink border + ink text.
                // Tracking + AmericanTypewriter mimics the "POT" stamp on a
                // 60s editorial print.
                Text("POT")
                    .font(.custom("AmericanTypewriter-Bold", size: 9))
                    .foregroundStyle(SPRetro.ink)
                    .tracking(1.5)
                Text(formatChips(String(amount)))
                    .font(.custom("ChalkboardSE-Bold", size: 16))
                    .foregroundStyle(SPRetro.ink)
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 3)
            .background(SPRetro.paper)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(SPRetro.ink, lineWidth: 2)
            )
        }
    }
}

// ─── Ticking-seat wrapper ────────────────────────────────────────────────────
// Tiny subview whose only job is to observe `vm.turnClock` and feed the live
// progress / secondsLeft into a TargetSeatView. The wrapper lets the rest of
// PokerTableView stay subscribed to the broader VM only — when the clock
// ticks at 5Hz, just this view re-evaluates, not the whole table layout.
// Used solely for the seat that is currently on-turn (one at a time).
struct TickingSeat: View {
    // Always observe the clock so this wrapper has stable view-tree type
    // for every seat regardless of who is currently active (see the call
    // site in seatOverlay for the @State-identity rationale). For non-
    // active seats we substitute constant placeholders below so the inner
    // TargetSeatView still diffs to a no-op when the clock ticks.
    @ObservedObject var clock: TurnClock
    let seat:           GameSeat
    let isMe:           Bool
    let isMyTurn:       Bool
    let isWinner:       Bool
    let lastAction:     LastAction?
    let avatarSize:     CGFloat
    let winningCardIds: Set<String>
    let anyWinnersDeclared: Bool
    let onProfileTap:   () -> Void

    var body: some View {
        TargetSeatView(
            seat:               seat,
            isMe:               isMe,
            isMyTurn:           isMyTurn,
            isWinner:           isWinner,
            // Only feed the live clock values to the active seat. For
            // non-active seats we hard-code the same placeholders the
            // original branch used (turnProgress 1.0, no seconds left) so
            // SwiftUI diffs an unchanged TargetSeatView and skips its
            // body — same perf shape as before the merge.
            turnProgress:       isMyTurn ? clock.progress    : 1.0,
            turnSecondsLeft:    isMyTurn ? clock.secondsLeft : 0,
            // Live deadline/duration drive the TimelineView-based ring
            // for the active seat so the sweep runs at the display
            // refresh rate. nil/0 on idle seats falls back to the
            // static turnProgress path (no per-frame work).
            turnDeadline:       isMyTurn ? clock.deadline    : nil,
            turnDuration:       isMyTurn ? clock.duration    : 0,
            lastAction:         lastAction,
            avatarSize:         avatarSize,
            winningCardIds:     winningCardIds,
            anyWinnersDeclared: anyWinnersDeclared,
            onProfileTap:       onProfileTap
        )
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
    // Absolute end-of-turn date + total span. When non-nil the ring uses
    // these directly inside a TimelineView so the trim sweeps at the
    // display refresh rate. Optional so replay/preview call sites that
    // don't have a live clock can keep passing nil and the ring just
    // falls back to the static `turnProgress` value.
    var turnDeadline: Date? = nil
    var turnDuration: Double = 0
    var lastAction:   LastAction?
    let avatarSize:   CGFloat
    // Showdown context — used by OpponentHoleCardsView to highlight the
    // cards in the winning combination once winners have been declared.
    var winningCardIds:     Set<String> = []
    var anyWinnersDeclared: Bool = false
    // Tapping an opponent seat opens the quick-profile popup. Optional so
    // ReplayTableView (and other read-only contexts) keep their non-tappable
    // seats — only the live PokerTableView wires this up.
    var onProfileTap: (() -> Void)? = nil

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
                // Retro action bubble — ChalkboardSE-Bold label on a tinted
                // panel with ink border + hard offset shadow. Label color
                // stays paper so the panel tint (call/raise/fold colors,
                // remapped via actionBubbleKind below) reads as a stamp.
                Text(kind.label)
                    .font(.custom("ChalkboardSE-Bold", size: 11))
                    .foregroundStyle(SPRetro.paper)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    // Shape-only offset plate instead of `.shadow()` so the
                    // action label text doesn't get rasterized into a
                    // doubled glyph.
                    .background(
                        ZStack {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(SPRetro.ink.opacity(0.7))
                                .offset(x: 1.5, y: 2)
                            RoundedRectangle(cornerRadius: 6)
                                .fill(kind.color)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .strokeBorder(SPRetro.ink, lineWidth: 1.5)
                                )
                        }
                    )
                    .padding(.bottom, 3)
                    .transition(.scale.combined(with: .opacity))
            } else if seat.isLeaving {
                // Mid-hand leave: server-side `pendingLeave` flag. Takes
                // priority over the "Folded" badge so the rest of the
                // table sees that the player has actually bailed (the
                // engine auto-folds them on leave, but a generic
                // "Folded" tag would be misleading — it implies a real
                // poker decision rather than an exit). Seat disappears
                // entirely on the next ClientGameState after endHand.
                // Retro "Left" badge — ink-soft text on a faint paper chip.
                Text("Left")
                    .font(.custom("AmericanTypewriter-Bold", size: 11))
                    .foregroundStyle(SPRetro.inkSoft)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(SPRetro.paper.opacity(0.8))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(SPRetro.ink.opacity(0.5), lineWidth: 1)
                    )
                    .padding(.bottom, 3)
            } else if seat.status == .folded {
                // "Folded" stamp — maroon ink so it reads as a struck-out
                // print stamp on the paper page.
                Text("Folded")
                    .font(.custom("AmericanTypewriter-Bold", size: 11))
                    .foregroundStyle(SPRetro.maroon)
                    .padding(.bottom, 3)
            }

            ZStack {
                // Winner glow
                if isWinner {
                    Circle()
                        .strokeBorder(
                            SPRetro.mustard,
                            lineWidth: winnerPulse ? 4 : 2
                        )
                        .frame(
                            width:  avatarSize + (winnerPulse ? 16 : 8),
                            height: avatarSize + (winnerPulse ? 16 : 8)
                        )
                        .shadow(
                            color: SPRetro.mustard.opacity(winnerPulse ? 0.8 : 0.3),
                            radius: winnerPulse ? 16 : 4
                        )
                }

                // Turn-timer animation lives on the stack pill below the
                // avatar now (see StackPill's drain fill). The avatar
                // identifies the active seat purely through the thicker
                // ink border applied to the portrait circle below.

                // Retro avatar circle — paper face + ink border. The ink
                // border thickens when it's the player's turn (replaces the
                // old white-on-navy highlight). Reads as a pasted-on
                // newspaper portrait inside an ink panel.
                Circle()
                    .fill(SPRetro.paper)
                    .overlay(
                        Circle().strokeBorder(
                            SPRetro.ink,
                            lineWidth: isMyTurn ? 2.5 : 1.5
                        )
                    )
                    .frame(width: avatarSize, height: avatarSize)
                    .overlay(
                        Text(AvatarOption.find(seat.avatarId).emoji)
                            .font(.system(size: avatarSize * 0.58))
                    )
                    // Same dimmed treatment for `isLeaving` as for folded —
                    // the player has already mentally checked out, so the
                    // avatar should read as "not in play" regardless of
                    // whether the underlying status is FOLDED (auto-folded
                    // on leave) or ALL_IN (still entitled to showdown).
                    .opacity(seat.status == .folded || seat.isLeaving ? 0.45 : 1.0)
                    .saturation(seat.isLeaving ? 0 : 1)
                    .shadow(
                        color: seat.status == .allIn
                            ? SPRetro.mustard.opacity(allInPulse ? 0.7 : 0.15)
                            : Color.black.opacity(0.4),
                        radius: seat.status == .allIn ? (allInPulse ? 10 : 3) : 5,
                        y: 2
                    )

                // Last-5-seconds countdown — sits in front of the avatar at
                // half opacity so it reads as a subtle urgency cue without
                // competing with the timer ring.
                if isMyTurn, turnSecondsLeft > 0, turnSecondsLeft <= 5 {
                    // Retro urgency countdown — pop-red ChalkboardSE numeral
                    // floating over the paper avatar. Pop red replaces the
                    // washed-out white-on-dark so the urgency cue still
                    // screams against the cream avatar face.
                    Text("\(turnSecondsLeft)")
                        .font(.custom("ChalkboardSE-Bold", size: avatarSize * 0.7))
                        .foregroundStyle(SPRetro.popRed.opacity(0.85))
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
                    // Previously wrapped in `.tableSurfaceTilt()` to make
                    // the cluster lie flat on the felt at the table's 26°
                    // foreshortening angle. The user found the resulting
                    // foreshortening read as "weirdly tilted" rather than
                    // "lying flat" — at the small (22pt) cluster size the
                    // 3D rotation just looks like a skew. Rendering them
                    // upright (no tilt) keeps the cards readable as
                    // standing-up cards next to the avatar.
                    .offset(x: -avatarSize * 0.52, y: -avatarSize * 0.15)
                    .zIndex(8)
                }

                // SB / BB markers are rendered on the felt itself (see
                // `blindRailChips` in the table layer), not pinned to the
                // avatar — that way they can't collide with the opponent
                // face-down cards or the avatar plate.

                // Disconnect indicator
                if !seat.isConnected {
                    // Retro disconnect badge — pop-red disc with ink border
                    // and paper "wifi.slash" glyph so it reads as a printed
                    // warning stamp on the avatar.
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(SPRetro.paper)
                        .padding(3)
                        .background(SPRetro.popRed)
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(SPRetro.ink, lineWidth: 1))
                        .offset(x: avatarSize * 0.38, y: -avatarSize * 0.38)
                }
            }
            .frame(width: avatarSize + 10, height: avatarSize + 10)
            // Tap on an opponent's avatar opens the quick-profile popup.
            // Bounded to the avatar circle so we don't swallow taps targeted
            // at neighboring chips, run-out cards, or the open-seat tile.
            // contentShape MUST come before onTapGesture, otherwise the
            // gesture only registers on opaque pixels (the emoji glyph).
            .contentShape(Circle())
            .onTapGesture {
                // Allow self-tap so the player can read their own VPIP / hand
                // count in the same popup opponents use. The popup itself
                // hides the friend-action button when isSelf=true (server
                // marks the row), so there's nothing dangerous about tapping
                // your own seat — it just becomes a read-only stat card.
                guard let cb = onProfileTap else { return }
                cb()
            }

            // Retro name plate — ink panel + paper username text. The pill
            // sits directly under the avatar so the inverted color (paper
            // text on ink) reads as a name *card* clipped to the portrait,
            // matching the home-screen player tiles.
            Text(truncatedName)
                .font(.custom("AmericanTypewriter-Bold", size: 11))
                .foregroundStyle(SPRetro.paper)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 2.5)
                .frame(maxWidth: plateWidth)
                // Shape-only offset plate (not `.shadow()`) so the player
                // name doesn't render as doubled glyphs. The shadow plate
                // is a slightly lighter ink so it's distinguishable from
                // the dark name plate itself.
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(SPRetro.inkMuted.opacity(0.65))
                            .offset(x: 1, y: 1.5)
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(SPRetro.ink)
                            .overlay(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .strokeBorder(SPRetro.ink, lineWidth: 1)
                            )
                    }
                )
                .offset(y: -4)

            // ── Stack pill ─ dedicated chip-amount area beneath the icon
            // Chip-tier-colored accents so the value reads at a glance and
            // ties visually to the chip stacks on the felt.
            StackPill(
                amount:       seat.stack,
                status:       seat.status,
                isMyTurn:     isMyTurn,
                turnDeadline: turnDeadline,
                turnDuration: turnDuration
            )
                .offset(y: -2)
                .overlay(alignment: .topTrailing) {
                    // "+N pending" badge for mid-hand top-ups. Sits above
                    // the pill's top-right corner so it doesn't obstruct
                    // the stack value or the avatar plate. Gold to read
                    // as "incoming chips" without competing with the
                    // green stack number, and small enough that it
                    // disappears once the hand ends (server drops the
                    // pendingTopUp field to nil at that point).
                    if seat.pendingTopUpAmount > 0 {
                        // Retro pending-topup badge — mustard pill with ink
                        // border + hard offset shadow.
                        Text("+\(formatChips(String(seat.pendingTopUpAmount)))")
                            .font(.custom("ChalkboardSE-Bold", size: 9))
                            .foregroundStyle(SPRetro.ink)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            // Shape-only offset plate — no `.shadow()` on
                            // the badge so the "+N" digit stays crisp.
                            .background(
                                ZStack {
                                    Capsule()
                                        .fill(SPRetro.ink.opacity(0.6))
                                        .offset(x: 1, y: 1)
                                    Capsule()
                                        .fill(SPRetro.mustard)
                                        .overlay(
                                            Capsule().strokeBorder(SPRetro.ink, lineWidth: 1.2)
                                        )
                                }
                            )
                            .offset(x: 8, y: -8)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .animation(.spring(response: 0.35), value: seat.pendingTopUpAmount)
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

    // Retro stack/timer color — ink as the resting color, mustard for
    // attention, pop-red for urgency. Replaces the old casino-green active /
    // gold low / red-orange critical scheme.
    private var stackColor: Color {
        switch seat.status {
        case .active:  return SPRetro.ink
        case .folded:  return SPRetro.inkMuted
        case .allIn:   return SPRetro.popRed
        default:       return SPRetro.inkSoft
        }
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
        // Retro action-bubble colors — pulled into the retro palette so the
        // floating stamps over each seat sit in the same pop-color system
        // as the rest of the app (pop red / teal / pop blue / mustard).
        case "FOLD":   return ActionKind(label: "Fold",   color: SPRetro.popRed)
        case "CHECK":  return ActionKind(label: "Check",  color: SPRetro.teal)
        case "CALL":   return ActionKind(label: "Call",   color: SPRetro.teal)
        case "RAISE":  return ActionKind(label: "Raise",  color: SPRetro.popBlue)
        case "ALL_IN": return ActionKind(label: "All In", color: SPRetro.mustard)
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
    // Turn-timer inputs — when isMyTurn is true and a live deadline is
    // supplied, the pill's paper background gets a left-anchored color
    // fill that drains as the turn elapses (replaces the old ring that
    // hugged the avatar). Optional/default-nil so non-live call sites
    // (and the rest of the table) can keep invoking StackPill the way
    // they always have.
    var isMyTurn:     Bool   = false
    var turnDeadline: Date?  = nil
    var turnDuration: Double = 0

    private var tier: ChipTier { ChipTier.forAmount(amount) }

    // Same teal → mustard → pop-red thresholds the avatar ring used.
    // Duplicated locally so StackPill doesn't need to reach into
    // TargetSeatView's private helpers.
    private func timerColor(for p: Double) -> Color {
        if p > 0.5  { return SPRetro.teal }
        if p > 0.25 { return SPRetro.mustard }
        return SPRetro.popRed
    }

    private func currentTrim(at now: Date) -> Double {
        guard let deadline = turnDeadline, turnDuration > 0 else { return 1 }
        let remaining = deadline.timeIntervalSince(now)
        return max(0, min(1, remaining / turnDuration))
    }

    // Retro palette — ink/maroon on paper. All-in lights up in pop red so
    // it still screams against the cream pill, but the muted states are
    // ink-soft instead of washed-out white-on-dark.
    private var amountColor: Color {
        switch status {
        case .folded:       return SPRetro.inkMuted.opacity(0.55)
        case .sittingOut,
             .disconnected: return SPRetro.inkMuted.opacity(0.70)
        case .allIn:        return SPRetro.popRed
        default:            return SPRetro.ink
        }
    }

    private var borderColor: Color {
        switch status {
        case .folded, .sittingOut, .disconnected:
            return SPRetro.ink.opacity(0.35)
        default:
            return SPRetro.ink
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
                .font(.custom("ChalkboardSE-Bold", size: 12))
                .foregroundStyle(amountColor)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        // Shape-only offset plate (not `.shadow()`) so the chip count
        // digit doesn't rasterize into a doubled glyph.
        //
        // When it's this seat's turn, a left-anchored color fill drains
        // through the paper background as the turn elapses. We layer it
        // *under* the chip-amount text but *over* the paper fill so the
        // value stays legible — paper → drain → border → text. Replaces
        // the old ring that hugged the avatar (which got hidden behind
        // overlapping seats on busy tables).
        .background(
            ZStack {
                Capsule()
                    .fill(SPRetro.ink.opacity(0.6))
                    .offset(x: 1, y: 1.5)
                Capsule()
                    .fill(SPRetro.paper)

                // Live drain fill — only mounts on this seat's turn.
                // TimelineView re-evaluates at the display refresh
                // rate so the width sweep is smooth (not the 5Hz
                // staircase from the old @Published progress value).
                if isMyTurn, turnDeadline != nil, turnDuration > 0 {
                    TimelineView(.animation) { context in
                        let p = currentTrim(at: context.date)
                        let c = timerColor(for: p)
                        GeometryReader { geo in
                            // Left-anchored rectangle, width proportional
                            // to remaining time. Clipped to the capsule
                            // so the edge follows the pill's rounded
                            // ends rather than poking past them.
                            Rectangle()
                                .fill(c.opacity(0.45))
                                .frame(width: geo.size.width * p,
                                       height: geo.size.height,
                                       alignment: .leading)
                        }
                    }
                    .clipShape(Capsule())
                    .allowsHitTesting(false)
                }

                Capsule()
                    .strokeBorder(borderColor, lineWidth: 1.5)
            }
        )
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
    // Either source of "this card face should be visible" — showdown reveal
    // (`revealedCards`) OR a voluntary tap-to-show / bot-auto-show
    // (`partialReveals`). The lift / enlarge state needs to trigger on
    // EITHER, otherwise voluntary shows render at the tiny face-down
    // geometry — small, overlapping (-6pt spacing), and tucked behind the
    // avatar plate — which is exactly the "cards are blocked by the symbol"
    // bug.
    private var hasAnyReveal: Bool { hasReveal || !partialReveals.isEmpty }
    // Lookup helper — slot i → voluntarily-shown card if any. Used by
    // `cardSlot` to override the face-down placeholder when the owner has
    // tapped that slot.
    private func revealedAt(_ i: Int) -> PokerCard? {
        partialReveals.first(where: { $0.index == i })?.card
    }
    private let cardSize: PlayingCardView.CardSize = .custom(22)

    var body: some View {
        // Card layout shifts between two states:
        //   Hidden (face-down): tight overlap (-6) + steeper fan (5° step) so
        //     the cluster reads as a compact stacked deck next to the avatar.
        //   Lifted (revealed/showing): positive spacing (3) so cards no longer
        //     smush into each other, a flatter fan (3° step) so adjacent
        //     rotated corners don't overlap the neighbouring face, and a bigger
        //     visual scale (1.85). The scale anchor is .bottom so growing the
        //     cluster pushes it UP away from the avatar rather than expanding
        //     in all directions and intersecting the seat plate or the +15s /
        //     wifi.slash badges that float around the avatar circle.
        // PLO (4-card) geometry needs to be tighter than NLH (2-card) when
        // lifted: at NLH's 2.1x scale a 4-card HStack is ~150pt wide, which
        // extends past the felt's rounded edge and clips the outer card. We
        // detect "this is a PLO-sized cluster" via displayCount==4 and switch
        // to a more compact fan + a smaller lift-scale so the whole hand fits
        // in the same horizontal footprint as the NLH version while still
        // reading as visibly enlarged.
        let isPLOWidth = displayCount == 4
        // PLO fan needs MORE separation than NLH, not less — with 4 cards the
        // eye has to distinguish more values, and the previous near-zero gap
        // (`-1`) + 2.5° fan stacked them into an indistinguishable wedge. A
        // 4.5° per-card step + 2.5pt positive spacing gives a true 13.5°
        // spread across the cluster and ~2.5pt of visible felt between
        // adjacent cards, so each rank/suit reads as its own card rather
        // than a smushed pile. Total cluster width stays inside the felt:
        // 4×16 + 3×2.5 = 71.5pt; ×1.55 scale ≈ 111pt — still narrower than
        // the 130pt I had budget for with the earlier overflow check.
        // Face-down (hidden) geometry: NLH uses 5° per-card step → 5° total
        // spread for 2 cards. PLO uses HALF that step (2.5°) so 4 cards
        // span only 7.5° total — close to NLH's overall tilt rather than
        // the 15° dramatic fan we get with a matched step. Previous attempt
        // matched NLH's per-card step (5°) and ended up with a -15°…0°
        // rotation range that overlapped 4 dark card backs into an
        // indistinguishable black wedge. Halving the step keeps the right-
        // most card at 0° (still aligned with NLH's top card) but the
        // leftmost tilts only to -7.5°, so individual cards remain visible.
        //   NLH (count=2): rotations (-5°,    0°)             — 5° spread
        //   PLO (count=4): rotations (-7.5°, -5°, -2.5°, 0°) — 7.5° spread
        //                                  ^ matches NLH's leftmost card exactly
        let fanStep:    Double  = lifted ? (isPLOWidth ? 4.5 : 3)   : (isPLOWidth ? 2.5 : 5)
        let fanBase:    Double  = lifted ? (isPLOWidth ? 6.75 : 4.5) : (isPLOWidth ? 7.5 : 5)
        let cardGap:    CGFloat = lifted ? (isPLOWidth ? 2.5 : 3)   : -6

        HStack(spacing: cardGap) {
            ForEach(0..<displayCount, id: \.self) { i in
                cardSlot(at: i)
                    .rotationEffect(.degrees(Double(i) * fanStep - fanBase))
            }
        }
        .scaleEffect(x: flipScaleX, y: 1)
        // Anchor the lift-scale at .bottom: when the cluster grows the bottom
        // edge stays put and the cards rise upward, so the enlarged hand
        // never punches into the avatar/name plate below. scaleEffect itself
        // doesn't change the layout footprint, so siblings (badges, dealer
        // chip, etc.) never reflow off this animation — only the in-place
        // visual scale of the cluster changes.
        //
        // PLO scale is dialled back from 2.1 → 1.45 because the 4-card
        // HStack is already twice as wide as the 2-card version; at 2.1x it
        // overflowed the felt and clipped the rightmost card. 1.45x keeps
        // the cluster readable while leaving room inside the screen on
        // both left- and right-side seats.
        // Face-down PLO uses the same 1.0x scale as NLH so individual cards
        // are the same physical size. The visual difference is just "2 more
        // cards on the left of the same cluster", not "the whole cluster
        // shrinks/recenters". The 0.6x shrink that was here previously was
        // wrong direction — the user wants PLO to read as four real-size
        // cards stacked behind the avatar, matching NLH's two-card stack.
        .scaleEffect(lifted ? (isPLOWidth ? 1.45 : 2.1) : 1.0, anchor: .bottom)
        // Horizontal nudge intentionally LARGER for PLO (+22) than NLH (-6).
        // Why: the parent seat layout pins this view with
        // `.offset(x: -avatarSize * 0.52)` — i.e. the cluster is always
        // anchored to the LEFT of the avatar. For NLH that's fine because
        // 2 cards × 2.1x ≈ 74pt total — comfortably inside the screen even
        // at the leftmost seat. For PLO the lifted cluster is ~132pt wide,
        // so the leftmost-card extent on a left-side seat (avatar_center
        // ≈ 80pt) was landing at x ≈ -14pt — clipped off-screen. Pushing
        // the cluster +22pt to the right re-centers it near the avatar's
        // horizontal axis, bringing the leftmost card back on-screen
        // without pushing the rightmost card off the felt on right-side
        // seats (whose rightmost extent moves from screen_edge to
        // screen_edge - 22 = still well inside).
        // Face-down PLO x-shift: counter the HStack's auto-centering.
        // NLH HStack width = 2 * 22 + 1 * (-6) = 38pt → right edge at
        //   parent_center + 19.
        // PLO HStack width = 4 * 22 + 3 * (-6) = 70pt → right edge at
        //   parent_center + 35 — 16pt further right than NLH.
        // The user wants PLO's RIGHTMOST card at the same screen position
        // as NLH's rightmost card (only the LEFT side should extend), so
        // we shift the whole PLO cluster -16pt to bring the right edge
        // back in line. The two extra cards naturally extend leftward
        // from that re-anchored position.
        .offset(x: lifted ? (isPLOWidth ? 22 : -6) : (isPLOWidth ? -16 : 0),
                y: lifted ? (isPLOWidth ? -12 : -22) : 0)
        .zIndex(lifted ? 5 : 0)
        .shadow(color: .black.opacity(lifted ? 0.55 : 0.3),
                radius: lifted ? 9 : 2,
                y: lifted ? 5 : 1)
        .shadow(color: (isWinner && glowPulse) ? SPRetro.mustard.opacity(0.7) : .clear,
                radius: 14)
        .animation(.spring(response: 0.45, dampingFraction: 0.78), value: lifted)
        .onAppear {
            // Late-joiner safety: if the seat already has revealed cards when
            // this view first mounts (e.g. user opened the app mid-showdown
            // OR mid-fold-show from the bot), jump straight to revealed +
            // lifted without animating. Uses `hasAnyReveal` so voluntary
            // partial reveals also trigger the enlarged state.
            if hasAnyReveal {
                revealed = true
                lifted   = true
            }
            if isWinner { startGlowPulse() }
        }
        .onChange(of: hasReveal) { _, new in
            if new {
                runRevealSequence()
            } else if partialReveals.isEmpty {
                // Showdown reveal cleared by the next hand starting (server
                // wipes `revealedCards` when dealing). Without an explicit
                // reset here, `revealed`/`lifted` stay true across the
                // hand boundary and the new face-down cards render in the
                // expanded fan geometry (spread spacing + 1.45/2.1x scale
                // + offset) — exactly the "cards don't return to compact
                // stack" bug. Guard on partialReveals.isEmpty so a
                // voluntary show that survives the new hand keeps the
                // lifted treatment.
                revealed   = false
                lifted     = false
                flipScaleX = 1
                glowPulse  = false
            }
        }
        // Voluntary reveals (tap-to-show / bot fold-show) arrive via
        // partialReveals and don't go through the showdown flip sequence.
        // When the first one lands, lift the cluster so the shown faces
        // render at the enlarged geometry (positive spacing, bigger scale,
        // raised off the avatar plate). Watch `.count` rather than the
        // array itself so the closure isn't forced to compare RevealedCard
        // by identity.
        .onChange(of: partialReveals.count) { _, count in
            if count > 0 && !lifted {
                lifted = true
            } else if count == 0 && !hasReveal && lifted {
                // Symmetric to the hasReveal reset: when the last
                // voluntary reveal clears (typically next-hand wipe) and
                // there's no showdown reveal keeping the cluster lifted,
                // collapse back to the compact face-down geometry.
                revealed = false
                lifted   = false
            }
        }
        .onChange(of: isWinner) { _, new in
            if new { startGlowPulse() } else { glowPulse = false }
        }
    }

    private var displayCount: Int {
        // After a fold the seat's `cardCount` drops to 0 (mucked), but if
        // the owner (or the bot) voluntarily shows cards we still need to
        // render enough slots to host the highest revealed index. Take the
        // max of the showdown-revealed count, the in-hand cardCount, and
        // (highest partial-reveal index + 1) so any of the three reveal
        // sources gets a slot to land in. Clamped to [0, 4] — PLO max.
        let baseCount    = hasReveal ? (revealedCards?.count ?? 0) : cardCount
        let partialMax   = partialReveals.map(\.index).max().map { $0 + 1 } ?? 0
        return max(min(max(baseCount, partialMax), 4), 0)
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
            // Gate the gold highlight on `isWinner`. card.id is unique
            // (rank+suit), so a loser's hole card can't match a winner's
            // bestCards entry — but at a PLO river all-in showdown a user
            // reported losing-side cards reading as highlighted. Anchoring
            // on the seat-winner flag closes the door on any stale-state
            // or future regression path (same defence as the local hero
            // overlay in GameView.localPlayerOverlay).
            let isWinningCard = isWinner && winningCardIds.contains(card.id)
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
                            isWinningCard ? SPRetro.mustard : Color.clear,
                            lineWidth: 1.6
                        )
                )
                .shadow(color: isWinningCard ? SPRetro.mustard.opacity(0.6) : .clear,
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

    // Retro comic remap. All six themes keep their ids (so persisted user
    // selections survive) but the values are now retro paper/ink variants
    // instead of casino felts. The felt itself stays paper-toned across all
    // themes — the differentiation lives in the rail/room edge color so each
    // theme reads as a different printed page tint, not as a different
    // synthetic felt. Inner = warm paper, mid = mustard or accent rim, edge
    // = ink. Room top/bottom = slightly darker page so the table panel pops
    // off the surrounding ZStack without going full black.
    // Each theme is a same-hue triple: a lighter "lit" interior, the mid
    // accent that defines the theme's identity, and a deeper rim of the
    // same family (not pure ink). Previously every theme jumped paper →
    // theme → black, which produced a heavy vignette that fought the
    // paper background. Same-hue triples let the felt read as a stamped
    // color block on the comic page.
    static let all: [TableTheme] = [
        TableTheme(id: "classic_blue", label: "Pop Blue",
                   inner: "#3F87C9", mid: "#2A6DB5", edge: "#143961",
                   roomTop: "#DCC58A", roomBottom: "#B89A6A"),
        TableTheme(id: "emerald", label: "Muted Teal",
                   inner: "#4093A3", mid: "#2E7C8B", edge: "#1A4651",
                   roomTop: "#DCC58A", roomBottom: "#B89A6A"),
        TableTheme(id: "crimson", label: "Maroon",
                   inner: "#A53939", mid: "#8B2C2C", edge: "#4A1717",
                   roomTop: "#DCC58A", roomBottom: "#B89A6A"),
        TableTheme(id: "royal_purple", label: "Pop Red",
                   inner: "#E04848", mid: "#D33232", edge: "#7A1A1A",
                   roomTop: "#DCC58A", roomBottom: "#B89A6A"),
        TableTheme(id: "midnight", label: "Ink",
                   inner: "#5C4838", mid: "#3A2E22", edge: "#1A1410",
                   roomTop: "#DCC58A", roomBottom: "#B89A6A"),
        TableTheme(id: "bourbon", label: "Mustard",
                   inner: "#F0CC4D", mid: "#E8B923", edge: "#8A6D14",
                   roomTop: "#DCC58A", roomBottom: "#B89A6A"),
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

// TODO: Dead code after poker_table.png swap (2026-05-15).
// Remove in follow-up cleanup commit unless procedural rendering is revived.
// (Was previously also reused by the lobby background per the comment above;
// confirm no other call sites before removing.)
// Exposed (was `private`) so non-felt screens (e.g. the lobby background)
// can reuse the same procedural cloth weave at low opacity for an
// at-the-table aesthetic without re-implementing the deterministic dot
// pattern. Internal — still scoped to the StackPoker module.
struct FeltTexture: View {
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
        // PERF: rasterize the 520-dot weave to a Metal texture once, so
        // unrelated body invalidations elsewhere on the table (pot updates,
        // bet changes, winner reveal) don't re-run all 520 ellipse fills.
        // .drawingGroup() must come BEFORE .blendMode() so the blend
        // applies to the rasterized layer against the felt below, not
        // against each individual dot — same visual, far less CPU.
        .drawingGroup()
        .blendMode(.overlay)
        .opacity(0.85)
    }
}
