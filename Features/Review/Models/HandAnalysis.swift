import SwiftUI

// ─── Frame analysis ───────────────────────────────────────────────────────────
// Output of HandAnalyzer for a single decision point in the recorded hand.
// One frame can be a *user* decision (yourMove + recommendation are filled),
// an *opponent* decision (only opponentRead filled), or simply informational
// (e.g. "Flop dealt").

enum AnalysisVerdict: String, Codable {
    case correct       // strong, +EV by basic theory
    case fine          // reasonable, no clear leak
    case questionable  // suboptimal but defensible
    case mistake       // clear leak by basic theory
    case info          // informational, not a verdict on the hero

    var color: Color {
        switch self {
        case .correct:      return SPColors.success
        case .fine:         return SPColors.info
        case .questionable: return SPColors.warning
        case .mistake:      return SPColors.danger
        case .info:         return SPColors.textSecondary
        }
    }

    var label: String {
        switch self {
        case .correct:      return "Solid"
        case .fine:         return "Fine"
        case .questionable: return "Borderline"
        case .mistake:      return "Leak"
        case .info:         return "Note"
        }
    }

    var icon: String {
        switch self {
        case .correct:      return "checkmark.seal.fill"
        case .fine:         return "checkmark.circle"
        case .questionable: return "exclamationmark.triangle"
        case .mistake:      return "xmark.octagon.fill"
        case .info:         return "info.circle"
        }
    }
}

struct FrameAnalysis: Identifiable, Codable {
    let id: String                  // UUID
    let frameIndex: Int             // index into RecordedHand.frames
    let title: String               // e.g. "Preflop · You raised $50"
    let yourMove: String?           // verdict text on the hero's action
    let recommendation: String?     // alternative line if applicable
    let opponentRead: String?       // what opponent's action might mean
    let verdict: AnalysisVerdict

    /// True if this analysis frame is hero-actionable (i.e. the hero made the
    /// decision being analyzed). Used to gate the "Recommended" panel.
    var isHeroDecision: Bool { yourMove != nil }
}
