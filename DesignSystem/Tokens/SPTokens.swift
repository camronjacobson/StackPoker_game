import SwiftUI

// ─── Color Tokens ─────────────────────────────────────────────────────────────
// All colors defined for dark mode default with light mode variants

enum SPColors {
    // Backgrounds
    static let background     = Color(hex: "#0A0A0F")
    static let surface        = Color(hex: "#13131A")
    static let surfaceElevated = Color(hex: "#1A1A24")
    static let surfaceHighlight = Color(hex: "#22222F")

    // Brand
    static let accent         = Color(hex: "#6C5CE7")   // Purple — primary action
    static let accentLight    = Color(hex: "#A29BFE")
    static let accentDark     = Color(hex: "#4A3AB4")

    // Chip colors
    static let chipGold       = Color(hex: "#F9CA24")
    static let chipGoldDark   = Color(hex: "#C4A11A")

    // Semantic
    static let success        = Color(hex: "#00B894")
    static let warning        = Color(hex: "#FDCB6E")
    static let danger         = Color(hex: "#E17055")
    static let info           = Color(hex: "#74B9FF")

    // Text
    static let textPrimary    = Color(hex: "#F0F0F8")
    static let textSecondary  = Color(hex: "#8888A8")
    static let textTertiary   = Color(hex: "#55556A")

    // Table felt — WPT bright green
    static let felt           = Color(hex: "#1F8840")
    static let feltDark       = Color(hex: "#166132")
    static let feltBorder     = Color(hex: "#0F4A25")

    // Table rail — dark walnut wood
    static let railOuter      = Color(hex: "#120800")
    static let railMid        = Color(hex: "#3B1A06")
    static let railLight      = Color(hex: "#6B3A18")
    static let railCushion    = Color(hex: "#0E3D1E")

    // Card colors
    static let cardBack       = Color(hex: "#2D2D4A")
    static let cardFace       = Color(hex: "#F5F5FA")
    static let cardRed        = Color(hex: "#E84393")
    static let cardBlack      = Color(hex: "#1A1A2E")

    // Borders
    static let border         = Color(hex: "#2A2A3A")
    static let borderLight    = Color(hex: "#3A3A52")
}

// ─── Typography ───────────────────────────────────────────────────────────────

enum SPFonts {
    static func title(_ size: CGFloat = 28) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }

    static func headline(_ size: CGFloat = 17) -> Font {
        .system(size: size, weight: .semibold, design: .rounded)
    }

    static func body(_ size: CGFloat = 15) -> Font {
        .system(size: size, weight: .regular, design: .default)
    }

    static func caption(_ size: CGFloat = 12) -> Font {
        .system(size: size, weight: .medium, design: .default)
    }

    static func chips(_ size: CGFloat = 16) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }

    static func card(_ size: CGFloat = 20) -> Font {
        .system(size: size, weight: .bold, design: .default)
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

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
