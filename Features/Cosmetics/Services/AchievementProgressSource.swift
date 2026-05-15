import Foundation

// ─── Achievement Progress Source ──────────────────────────────────────────────
//
// Phase 2 stub for "23/100 hands with pocket aces" style progress badges on
// aspirational catalog tiles whose unlockCondition is achievement-based.
//
// Why a protocol now even though we have nothing to feed it: the Store /
// Detail views render an optional progress bar based on this source's
// return value. By introducing the abstraction in Phase 2, the Phase 5
// engagement-loop work can drop in a real implementation (reading from
// /stats/achievements or wherever) without touching any view code.
//
// The contract is intentionally narrow:
//   - Returns nil → don't render a progress bar at all (treat as opaque).
//   - Returns a triple → render "<label>: <current>/<target>" with a bar.
// No "in-progress vs locked vs done" trichotomy — current >= target is the
// caller's signal that the achievement is complete.

struct AchievementProgress: Equatable {
    /// Current count toward the achievement (e.g., 23).
    let current: Int
    /// Target count (e.g., 100).
    let target: Int
    /// Short human-readable label, e.g. "Hands with pocket aces".
    /// Kept on the protocol output (not pulled from a localized table here)
    /// so the source layer owns wording — the view is dumb.
    let label: String

    var fraction: Double {
        guard target > 0 else { return 0 }
        return min(1.0, Double(current) / Double(target))
    }

    var isComplete: Bool { current >= target && target > 0 }
}

protocol AchievementProgressSource: AnyObject {
    /// Return progress toward unlocking `cosmetic`, or nil if:
    ///   - the cosmetic isn't achievement-gated, OR
    ///   - the source doesn't have data for it yet (Phase 2 default).
    ///
    /// Pure read — no side effects, safe to call from view body.
    func progress(for cosmetic: Cosmetic) -> AchievementProgress?
}

// ─── Stub ─────────────────────────────────────────────────────────────────────
//
// Phase 2 default. Returns nil for everything, so Store/Detail views never
// render a progress bar until Phase 5 wires in a real source.

final class StubAchievementProgressSource: AchievementProgressSource {
    func progress(for cosmetic: Cosmetic) -> AchievementProgress? { nil }
}
