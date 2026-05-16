import SwiftUI

// ─── Retro 60s Comic Theme Tokens ─────────────────────────────────────────────
//
// Vintage Adam-West-Batman era visual language. Aged newsprint paper, ink-black
// outlines, mustard yellow + deep maroon accents, splashes of pop red and teal.
// Kept namespaced (`SPRetro`) instead of redefining the existing `SPColors`
// values so the rest of the app keeps rendering with its current dark theme
// until each screen is migrated screen-by-screen. Mixing themes mid-migration
// would look like a broken build, not a redesign-in-progress.
//
// All colors are *opaque* solid swatches. Comic books don't do gradients — the
// vintage feel comes from flat fills, halftone dots, and hard ink lines. Any
// gradient call site should be reconsidered before being added here.

enum SPRetro {

    // ── Paper / ink ──────────────────────────────────────────────────────────
    // Aged newsprint cream — slightly warmer than off-white so flat fills don't
    // glare. `paperDark` is for inset panels (Sunday-funnies inner page tone).
    static let paper       = Color(hex: "#F4E4BC")
    static let paperShade  = Color(hex: "#E8D49A")
    static let paperEdge   = Color(hex: "#C9B17A")    // worn paper-edge shadow

    // Warm-black ink — never pure #000 (would look like a vector logo, not a
    // printed line). All panel borders, text outlines, and speech-bubble tails
    // use this so the whole page reads as printed-with-the-same-press.
    static let ink         = Color(hex: "#1A1410")
    static let inkSoft     = Color(hex: "#3A2E22")    // body text, less heavy
    // Mid-brown — used for muted/secondary text (e.g. "Folded" stamp, dimmed
    // labels, sub-headings). Sits between `inkSoft` and `paperEdge` in tone.
    static let inkMuted    = Color(hex: "#5C4838")

    // ── Pop accents ──────────────────────────────────────────────────────────
    // The "Batman" mustard. Used for the brand chip, callouts, the primary CTA
    // button. Slightly muted from a pure #FFC107 so it reads vintage-print and
    // not 2010s-flat-design.
    static let mustard     = Color(hex: "#E8B923")
    static let mustardDark = Color(hex: "#B68A14")

    // Comic-book maroon — used for the secondary CTA, deeper panels, and the
    // "BIFF!" burst. Reads as a printed dark red rather than a UI alert color.
    static let maroon      = Color(hex: "#8B2C2C")
    static let maroonDark  = Color(hex: "#5C1818")

    // Sampled directly from the rendered poker_table.png rail band — the
    // darker red ring that frames the bright playing-surface felt. Mean
    // of 13,434 "rail-red" pixels (filtered to R 80–160 to exclude the
    // halftone ink speckles) across both top (y=165–185) and bottom
    // (y=1260–1280) rail bands ≈ #71201E.
    //
    // Distinct from:
    //   - `maroon` / `maroonDark`  — printed-comic accent palette;
    //                                neither matches the rail tone
    //                                (>5% R-channel deviation each way).
    //   - `SPColors.tableRail`     — the *ink outline* of the rail
    //                                (#1F100B). This token is the
    //                                *darker red* of the rail's interior
    //                                band, so the two are intentionally
    //                                paired: rail surface (this) + rail
    //                                outline (SPColors.tableRail).
    //
    // Reused by views that need to color-match the table's rail surface
    // — e.g. the right-edge vertical bet slider track, future on-rail
    // overlays.
    static let tableRail   = Color(hex: "#71201E")

    // Tertiary pops. Pop blue is the "ZAP!" / superhero blue; teal is the
    // muted secondary used for accents that need to not compete with mustard.
    static let popRed      = Color(hex: "#D33232")
    static let popBlue     = Color(hex: "#2A6DB5")
    static let teal        = Color(hex: "#2E7C8B")
}

// ─── Retro Typography ─────────────────────────────────────────────────────────
//
// Pure system-font choices — no custom fonts means no Info.plist `UIAppFonts`
// edits, no missing-font crashes when a future build doesn't bundle the otf.
//
//   - `display` ........ ChalkboardSE-Bold: rough, hand-drawn-feeling — perfect
//                       for POW/BIFF/ZAP bursts and section headers.
//   - `headline` ....... AmericanTypewriter-Bold: 60s-print-shop vibe, used
//                       for screen titles ("FOR YOU", "ACTIVE GAMES").
//   - `body` ........... AmericanTypewriter for paragraph text — keeps the
//                       printed-page feel without becoming illegible.
//   - `callout` ........ Same as display but smaller; used for in-line
//                       speech-bubble labels.

enum SPRetroFonts {
    static func display(_ size: CGFloat = 32) -> Font {
        .custom("ChalkboardSE-Bold", size: size)
    }
    static func headline(_ size: CGFloat = 22) -> Font {
        .custom("AmericanTypewriter-Bold", size: size)
    }
    static func body(_ size: CGFloat = 15) -> Font {
        .custom("AmericanTypewriter", size: size)
    }
    static func callout(_ size: CGFloat = 14) -> Font {
        .custom("ChalkboardSE-Bold", size: size)
    }
}
