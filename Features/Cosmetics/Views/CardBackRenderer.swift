import SwiftUI

// ─── Card Back Renderer ───────────────────────────────────────────────────────
//
// Phase 4 cosmetics ship without any real art assets — that comes in
// Phase 5 (artist-delivered .pdf / .png variants). For the vertical slice
// we render every card-back variant procedurally from primitives that
// already match the retro paper/ink design language. The catalog still
// references each variant by id, so swapping in real art later is a
// one-line replacement inside `view(for:size:cornerRadius:)`.
//
// Two ids are shipped today; everything else falls back to the engine's
// default back (drawn by `PlayingCardView.cardBack` when this returns
// `AnyView?.none`). The narrow surface keeps the catalog forward-
// compatible: a future iOS build can add cases here without a server
// migration, and a future server-only catalog addition will simply
// render via the default until iOS catches up.
//
// Returning `AnyView?` (rather than a generic some-view) is deliberate —
// SwiftUI's type system can't accommodate a conditional "either custom
// or fallback" branch through a generic, and the renderer's call site
// is one layer deep (PlayingCardView only). A single AnyView allocation
// per face-down card is negligible against the rest of the table's
// shadow / stroke / filter cost.

enum CardBackRenderer {

    /// Returns a procedural card-back view for the given id, or `nil` if
    /// the id isn't recognised. Callers (PlayingCardView) interpret nil
    /// as "use the engine default back". `size` is the rendered card
    /// width — every primitive scales off it so the same id reads
    /// consistently from the 22pt opponent cluster up to the 56pt hero
    /// hole card.
    @ViewBuilder
    static func view(for id: CosmeticID?,
                     size: CGFloat,
                     cornerRadius: CGFloat) -> some View {
        switch id {
        case "card_back_classic_red":
            classicRed(size: size, cornerRadius: cornerRadius)
        case "card_back_classic_blue":
            classicBlue(size: size, cornerRadius: cornerRadius)
        default:
            // Sentinel — PlayingCardView checks `supports(_:)` BEFORE
            // calling this, so the default branch is only ever hit if a
            // future caller forgets to gate. EmptyView keeps things
            // graceful (renders nothing, doesn't crash) and lets the
            // caller fall through to its default cardBack instead.
            EmptyView()
        }
    }

    /// Cheap, allocation-free "do we render this id?" check. PlayingCardView
    /// calls this to decide between procedural and default render — we don't
    /// want to round-trip through view(for:) just to detect unknown ids.
    static func supports(_ id: CosmeticID?) -> Bool {
        guard let id else { return false }
        switch id {
        case "card_back_classic_red", "card_back_classic_blue":
            return true
        default:
            return false
        }
    }

    // ── Classic red ──────────────────────────────────────────────────────────
    //
    // Diamond lattice over a deep red field with a paper hairline inset
    // and a mustard center pip. Calibrated to read instantly as "classic
    // playing card back" at 22pt opponent size while still looking
    // intentional at 56pt hero size.

    private static func classicRed(size: CGFloat, cornerRadius: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color(red: 0.62, green: 0.13, blue: 0.18))

            // Diamond lattice. The dot grid is the cheapest "patterned
            // card back" primitive — a Canvas with a tile size that
            // scales with the card so a 22pt back has ~6 visible rows
            // and a 56pt back has ~14. Clipped to the card shape so the
            // pattern doesn't bleed past the rounded corners.
            Canvas { ctx, rect in
                let step = max(3, size * 0.10)
                let dot  = max(0.7, size * 0.02)
                var y: CGFloat = step / 2
                var row = 0
                while y < rect.height {
                    let xOffset: CGFloat = (row % 2 == 0) ? 0 : step / 2
                    var x = xOffset + step / 2
                    while x < rect.width {
                        let path = Path(
                            ellipseIn: CGRect(
                                x: x - dot/2, y: y - dot/2,
                                width: dot, height: dot
                            )
                        )
                        ctx.fill(path, with: .color(.white.opacity(0.18)))
                        x += step
                    }
                    y += step
                    row += 1
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))

            // Ink panel border + paper inset hairline — same chassis as
            // the engine's default back so the cosmetic feels in-family
            // rather than tacked on.
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(Color.black, lineWidth: 1.2)
            RoundedRectangle(cornerRadius: max(2, cornerRadius - 2))
                .strokeBorder(Color(red: 0.96, green: 0.89, blue: 0.74).opacity(0.55),
                              lineWidth: 1)
                .padding(4)

            // Center pip — small mustard diamond. Sized as a fraction of
            // the card width so it reads at every scale without a
            // separate small/large asset.
            Rectangle()
                .fill(Color(red: 0.92, green: 0.74, blue: 0.27))
                .frame(width: size * 0.18, height: size * 0.18)
                .rotationEffect(.degrees(45))
                .overlay(
                    Rectangle()
                        .strokeBorder(Color.black.opacity(0.7), lineWidth: 1)
                        .rotationEffect(.degrees(45))
                        .frame(width: size * 0.18, height: size * 0.18)
                )
        }
    }

    // ── Classic blue ─────────────────────────────────────────────────────────
    //
    // Same chassis as red — keeps the slot variants visually consistent
    // so opponents at the same table can run different backs without
    // one looking like it belongs to a different deck. Only the field
    // hue + pip glyph differ.

    private static func classicBlue(size: CGFloat, cornerRadius: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color(red: 0.13, green: 0.30, blue: 0.55))

            Canvas { ctx, rect in
                let step = max(3, size * 0.10)
                let dot  = max(0.7, size * 0.02)
                var y: CGFloat = step / 2
                var row = 0
                while y < rect.height {
                    let xOffset: CGFloat = (row % 2 == 0) ? 0 : step / 2
                    var x = xOffset + step / 2
                    while x < rect.width {
                        let path = Path(
                            ellipseIn: CGRect(
                                x: x - dot/2, y: y - dot/2,
                                width: dot, height: dot
                            )
                        )
                        ctx.fill(path, with: .color(.white.opacity(0.20)))
                        x += step
                    }
                    y += step
                    row += 1
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))

            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(Color.black, lineWidth: 1.2)
            RoundedRectangle(cornerRadius: max(2, cornerRadius - 2))
                .strokeBorder(Color(red: 0.96, green: 0.89, blue: 0.74).opacity(0.55),
                              lineWidth: 1)
                .padding(4)

            // Spade pip for blue — pulls visual contrast with red's
            // diamond pip so two players running classic-red and
            // classic-blue side-by-side never read as "the same back in
            // two colours" at small sizes.
            Image(systemName: "suit.spade.fill")
                .font(.system(size: size * 0.30))
                .foregroundStyle(Color(red: 0.96, green: 0.89, blue: 0.74))
        }
    }
}
