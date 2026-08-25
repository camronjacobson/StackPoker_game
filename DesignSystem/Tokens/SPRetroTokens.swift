import SwiftUI

// ─── Appearance Mode ──────────────────────────────────────────────────────────
//
// Two-mode toggle: "Day" (default — original cream-paper retro palette) and
// "Night" (warm dark-brown sepia — "aged paper at night"). This is NOT a true
// system dark mode — the app stays in light mode at the OS level (see
// App/StackPokerApp.swift's `.preferredColorScheme(.light)` lock). The mode
// only swaps the SPRetro / SPColors token *values*.
//
// Stored in @AppStorage("appearanceMode") via the raw String. Absence of a
// stored value resolves to .day on first launch.

enum AppearanceMode: String {
    case day
    case night

    /// Storage key shared by RootView (@AppStorage source) and the palette
    /// resolver below (UserDefaults read at color-resolution time).
    static let storageKey = "appearanceMode"

    /// Reads the current mode from UserDefaults. Called from inside SPRetro /
    /// SPColors computed-token getters at every Color resolution. UserDefaults
    /// has a fast in-memory cache so the read is cheap. We do NOT cache the
    /// result here because that would require an invalidation hook on toggle
    /// — relying on UserDefaults's own cache plus the RootView `.id(...)`
    /// rebuild keeps the mechanism stateless.
    static var current: AppearanceMode {
        let raw = UserDefaults.standard.string(forKey: storageKey)
            ?? AppearanceMode.day.rawValue
        return AppearanceMode(rawValue: raw) ?? .day
    }
}

// ─── Retro Palette (per-appearance value table) ───────────────────────────────
//
// All appearance-variant Color tokens for both SPRetro and SPColors. Single
// source of truth — `SPRetro.paper` and `SPColors.background` both resolve to
// `SPRetroPalette.current.paper` so the day/night swap is automatic and the
// SPColors-vs-SPRetro remap stays consistent.
//
// `tableRail` is intentionally absent from this struct — it's sampled from the
// rendered poker_table_standard.png and must not change between day and night.
// Defined as a static `let` on the namespaces below with an
// `Appearance-invariant` marker comment.

struct SPRetroPalette {
    // Paper / ink
    let paper:           Color
    let paperShade:      Color
    let paperEdge:       Color
    let ink:             Color
    let inkSoft:         Color
    let inkMuted:        Color
    // Pop accents
    let mustard:         Color
    let mustardDark:     Color
    let maroon:          Color
    let maroonDark:      Color
    let popRed:          Color
    let popBlue:         Color
    let teal:            Color
    // SPColors-only extras (no SPRetro equivalent, but still appearance-variant)
    let surfaceElevated:  Color
    let surfaceHighlight: Color
    let accentLight:      Color

    // ── Day (default) ────────────────────────────────────────────────────────
    // Aged-newsprint cream. Original retro values, unchanged from pre-Night-
    // mode codebase — these used to be `static let` literals in SPRetro /
    // SPColors directly.
    static let day = SPRetroPalette(
        paper:            Color(hex: "#F4E4BC"),
        paperShade:       Color(hex: "#E8D49A"),
        paperEdge:        Color(hex: "#C9B17A"),
        ink:              Color(hex: "#1A1410"),
        inkSoft:          Color(hex: "#3A2E22"),
        inkMuted:         Color(hex: "#5C4838"),
        mustard:          Color(hex: "#E8B923"),
        mustardDark:      Color(hex: "#B68A14"),
        maroon:           Color(hex: "#8B2C2C"),
        maroonDark:       Color(hex: "#5C1818"),
        popRed:           Color(hex: "#D33232"),
        popBlue:          Color(hex: "#2A6DB5"),
        teal:             Color(hex: "#2E7C8B"),
        surfaceElevated:  Color(hex: "#DCC58A"),
        surfaceHighlight: Color(hex: "#CFB57A"),
        accentLight:      Color(hex: "#F1CE5C")
    )

    // ── Night ────────────────────────────────────────────────────────────────
    // "Aged paper at night" — warm dark sepia background, cream replaces warm-
    // black ink, pops slightly desaturated and lifted so they read on dark
    // without glowing. Hand-curated; not derived. inkMuted is #B8A082 (not
    // #A89272) because the audit found body-sized 13pt secondary text on
    // paperShade surfaces — the brighter value clears WCAG AA (~5.5:1).
    static let night = SPRetroPalette(
        paper:            Color(hex: "#2A1F15"),
        paperShade:       Color(hex: "#3A2C1F"),
        paperEdge:        Color(hex: "#4D3C2C"),
        ink:              Color(hex: "#F4E4BC"),
        inkSoft:          Color(hex: "#D9C5A0"),
        inkMuted:         Color(hex: "#B8A082"),
        mustard:          Color(hex: "#D4A82B"),
        mustardDark:      Color(hex: "#9A7818"),
        maroon:           Color(hex: "#A04848"),
        maroonDark:       Color(hex: "#6B2424"),
        popRed:           Color(hex: "#C84545"),
        popBlue:          Color(hex: "#5A9AD4"),
        teal:             Color(hex: "#4DA0AE"),
        surfaceElevated:  Color(hex: "#45342A"),
        surfaceHighlight: Color(hex: "#503D30"),
        accentLight:      Color(hex: "#E4BB45")
    )

    /// Resolves the active palette by reading AppearanceMode.current. Called
    /// from every computed SPRetro / SPColors token. Cheap — palette static
    /// instances are initialized once at type load; this is a switch over an
    /// enum read from UserDefaults's in-memory cache.
    static var current: SPRetroPalette {
        switch AppearanceMode.current {
        case .day:   return .day
        case .night: return .night
        }
    }
}

// ─── Retro 60s Comic Theme Tokens ─────────────────────────────────────────────
//
// Vintage Adam-West-Batman era visual language. Aged newsprint paper, ink-black
// outlines, mustard yellow + deep maroon accents, splashes of pop red and teal.
// In Night mode the same vocabulary swaps to a "candlelit print" palette (warm
// dark sepia paper, cream ink, slightly faded pops) — see SPRetroPalette above.
//
// All tokens are computed (`static var`) reading from SPRetroPalette.current.
// Call sites stay unchanged — `SPRetro.paper`, `SPRetro.ink`, etc. — and the
// day/night swap propagates automatically when AppearanceMode changes (the
// RootView `.id(appearanceMode)` rebuild is what triggers SwiftUI to redraw
// every view with the new values).
//
// `tableRail` is the one exception: it's a static `let` because it's sampled
// from the rendered table image and must not change between modes.

enum SPRetro {

    // ── Paper / ink ──────────────────────────────────────────────────────────
    static var paper:      Color { SPRetroPalette.current.paper }
    static var paperShade: Color { SPRetroPalette.current.paperShade }
    static var paperEdge:  Color { SPRetroPalette.current.paperEdge }
    static var ink:        Color { SPRetroPalette.current.ink }
    static var inkSoft:    Color { SPRetroPalette.current.inkSoft }
    static var inkMuted:   Color { SPRetroPalette.current.inkMuted }

    // ── Pop accents ──────────────────────────────────────────────────────────
    static var mustard:     Color { SPRetroPalette.current.mustard }
    static var mustardDark: Color { SPRetroPalette.current.mustardDark }
    static var maroon:      Color { SPRetroPalette.current.maroon }
    static var maroonDark:  Color { SPRetroPalette.current.maroonDark }
    static var popRed:      Color { SPRetroPalette.current.popRed }
    static var popBlue:     Color { SPRetroPalette.current.popBlue }
    static var teal:        Color { SPRetroPalette.current.teal }

    // ── Appearance-invariant ─────────────────────────────────────────────────
    // Sampled directly from the rendered poker_table_standard.png rail band
    // (mean of 13,434 "rail-red" pixels filtered to R 80–160 ≈ #71201E).
    // The table is excluded from appearance theming (per the dark-mode audit
    // — table imagery is its own future theming axis), so this token stays
    // a static hex literal in both Day and Night modes.
    //
    // Distinct from `maroon` / `maroonDark` (printed-comic accent palette;
    // neither matches the rail tone), and from `SPColors.tableRail` which
    // is the *ink outline* of the rail (#1F100B). The two are paired:
    // rail surface (this) + rail outline (SPColors.tableRail).
    static let tableRail = Color(hex: "#71201E")
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
