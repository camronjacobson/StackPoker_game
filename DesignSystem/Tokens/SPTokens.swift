import SwiftUI

// ─── Color Tokens ─────────────────────────────────────────────────────────────
//
// Every appearance-variant SPColors token is a computed `static var` that
// resolves to a value from SPRetroPalette.current (see SPRetroTokens.swift).
// This keeps SPColors and SPRetro in lockstep across the Day / Night swap —
// they share one source of truth instead of being parallel hex-literal sets.
//
// Original "retro remap" semantic mapping preserved:
//   • background / surface / surfaceElevated → paper / paperShade / shade2
//   • accent (was purple)                   → mustard
//   • textPrimary (was off-white)           → ink
//   • danger (was red-orange)               → maroon
//   • success (was teal-green)              → muted teal
//   • felt (was green)                      → paper-shade
//   • cardBack (was navy)                   → maroon
//
// `tableRail` is the one appearance-invariant token: sampled from the rendered
// poker_table_standard.png rail band, must not change between Day and Night.

enum SPColors {
    // Backgrounds — aged paper page tones.
    static var background:        Color { SPRetroPalette.current.paper }            // paper
    static var surface:           Color { SPRetroPalette.current.paperShade }       // paperShade
    static var surfaceElevated:   Color { SPRetroPalette.current.surfaceElevated }  // shade2 (modal/sheet)
    static var surfaceHighlight:  Color { SPRetroPalette.current.surfaceHighlight } // shade3 (hover/press)

    // Brand — mustard yellow replaces purple.
    static var accent:            Color { SPRetroPalette.current.mustard }
    static var accentLight:       Color { SPRetroPalette.current.accentLight }
    static var accentDark:        Color { SPRetroPalette.current.mustardDark }

    // Chip colors — retro mustard. (Same values as accent / accentDark; kept
    // as separate tokens so chip-specific tuning can diverge later without
    // affecting button accents.)
    static var chipGold:          Color { SPRetroPalette.current.mustard }
    static var chipGoldDark:      Color { SPRetroPalette.current.mustardDark }

    // Semantic — pulled into the retro palette so alerts/badges don't look
    // like foreign Material-Design colors next to the cream page.
    static var success:           Color { SPRetroPalette.current.teal }     // muted teal
    static var warning:           Color { SPRetroPalette.current.mustard }
    static var danger:            Color { SPRetroPalette.current.maroon }
    static var info:              Color { SPRetroPalette.current.popBlue }

    // Text — warm-black ink in Day mode, cream in Night mode.
    static var textPrimary:       Color { SPRetroPalette.current.ink }
    static var textSecondary:     Color { SPRetroPalette.current.inkSoft }
    static var textTertiary:      Color { SPRetroPalette.current.inkMuted }

    // Table felt — paper substrate. The PokerTableView gets a halftone
    // overlay on top so it reads as a printed comic page, not a flat fill.
    // Both fall back to the appearance-variant paper tones; the table view
    // itself doesn't use these (it uses tier-specific PNGs), so they remain
    // variant for any non-table "felt-styled" badge that consumes them.
    static var felt:              Color { SPRetroPalette.current.paper }
    static var feltDark:          Color { SPRetroPalette.current.paperShade }
    static var feltBorder:        Color { SPRetroPalette.current.ink }

    // Table rail — solid ink "panel border" instead of walnut wood. Same
    // values for outer/mid/light so the rail reads as a single ink frame.
    static var railOuter:         Color { SPRetroPalette.current.ink }
    static var railMid:           Color { SPRetroPalette.current.inkSoft }
    static var railLight:         Color { SPRetroPalette.current.inkMuted }
    static var railCushion:       Color { SPRetroPalette.current.mustard }    // mustard cushion edge

    // Appearance-invariant — sampled from the rendered poker_table_standard.png
    // rail band (y=120–160 at x=512), mean of five interior samples ≈ #1F100B.
    // Distinct from the procedural `railOuter`/`railMid` (warmer & lighter
    // brown) because the image's rail is a deeper, redder near-black. Reused
    // by views that need to color-match the table rail border directly —
    // e.g. the right-edge vertical bet slider's outline. The table is
    // excluded from appearance theming, so this token must not change
    // between Day and Night.
    static let tableRail          = Color(hex: "#1F100B")

    // Playing-card surfaces. NOTE: these resolve through the palette so a
    // card-back rendered in a non-table context (Locker preview, Store grid)
    // picks up the Night-mode maroon. On the table itself the renderer reads
    // the cosmetic cardBack asset, not this token, so table cards are
    // unaffected.
    static var cardBack:          Color { SPRetroPalette.current.maroon }
    static var cardFace:          Color { SPRetroPalette.current.paper }
    static var cardRed:           Color { SPRetroPalette.current.popRed }
    static var cardBlack:         Color { SPRetroPalette.current.ink }

    // Borders — ink hairlines.
    static var border:            Color { SPRetroPalette.current.ink }
    static var borderLight:       Color { SPRetroPalette.current.inkSoft }
}

// ─── Typography ───────────────────────────────────────────────────────────────

// Retro typography — vintage-print-shop pairing:
//   • AmericanTypewriter-Bold for headlines/titles — heavy 60s editorial feel.
//   • AmericanTypewriter for body — the same family at non-bold, lower
//     weight so paragraphs are still legible but printed-page in tone.
//   • ChalkboardSE-Bold for chips/cards — slightly hand-drawn, reads as the
//     burst/POW family used elsewhere.
// All fonts are bundled with iOS — no Info.plist edits, no missing-font
// crashes on a future build that forgot to ship the font file.
enum SPFonts {
    static func title(_ size: CGFloat = 28) -> Font {
        .custom("AmericanTypewriter-Bold", size: size)
    }

    static func headline(_ size: CGFloat = 17) -> Font {
        .custom("AmericanTypewriter-Bold", size: size)
    }

    static func body(_ size: CGFloat = 15) -> Font {
        .custom("AmericanTypewriter", size: size)
    }

    static func caption(_ size: CGFloat = 12) -> Font {
        .custom("AmericanTypewriter", size: size)
    }

    static func chips(_ size: CGFloat = 16) -> Font {
        .custom("ChalkboardSE-Bold", size: size)
    }

    static func card(_ size: CGFloat = 20) -> Font {
        .custom("ChalkboardSE-Bold", size: size)
    }
}

// ─── Spacing ──────────────────────────────────────────────────────────────────

enum SPSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48
}

// ─── Radius ───────────────────────────────────────────────────────────────────

enum SPRadius {
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let full: CGFloat = 9999
}

// ─── Hex Color Extension ──────────────────────────────────────────────────────

// Per-process Color(hex:) cache. SwiftUI body re-evaluations call
// Color(hex:) hundreds of times per frame across the table (PokerTableView
// alone has 50+ literal hex sites; the seat view, action bar and chip stacks
// add more). The previous implementation allocated a CharacterSet,
// constructed a Scanner, and made a trimmed String on every call — measurable
// per-frame overhead during interactive moments (drag, animation, tick).
//
// Cache rules:
//   - Main-thread only. SwiftUI body evaluation is on the main thread, so we
//     don't pay for a lock.
//   - Keyed by the original input string (cheap for the call sites which
//     always pass string literals — those are interned, equality is O(1)).
//   - Bounded growth: hex strings used in the app are a small fixed set
//     (~50 unique values), so unbounded growth isn't a real concern.
private var hexColorCache: [String: Color] = [:]

extension Color {
    init(hex: String) {
        if let cached = hexColorCache[hex] {
            self = cached
            return
        }
        // Allocation-free parser: walk the bytes, skip a leading '#' if
        // present, accumulate hex nibbles directly. No Scanner, no
        // trimmingCharacters, no CharacterSet.
        var int: UInt64 = 0
        var count = 0
        for u in hex.utf8 {
            let nibble: UInt64
            switch u {
            case 0x30...0x39: nibble = UInt64(u - 0x30)        // '0'..'9'
            case 0x41...0x46: nibble = UInt64(u - 0x41 + 10)   // 'A'..'F'
            case 0x61...0x66: nibble = UInt64(u - 0x61 + 10)   // 'a'..'f'
            case 0x23: continue                                 // '#'
            default:  continue                                  // ignore stray chars
            }
            int = (int << 4) | nibble
            count += 1
        }
        let a, r, g, b: UInt64
        switch count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        let c = Color(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
        hexColorCache[hex] = c
        self = c
    }
}
