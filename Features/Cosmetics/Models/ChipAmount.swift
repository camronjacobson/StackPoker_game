import Foundation

// ─── ChipAmount ───────────────────────────────────────────────────────────────
//
// Value type for chip amounts. The server represents `chipBalance` as a
// BigInt-serialized String (see UserProfile.chipBalance) because product
// has historically reserved the option to scale balances past Int64. In
// practice every read path in the app today bridges through `Int64`, and
// the cosmetics store needs trustworthy arithmetic (subtract for the
// purchase-preview alert, compare for "can afford?") in one place rather
// than scattered `Int64(string) ?? 0` calls.
//
// Strategy:
//   • Internally Int64. Cheap arithmetic, overflow-safe via &
//     -free addition/subtraction below (we trap on overflow — a chip
//     balance overflowing Int64 means something is very wrong upstream
//     and we'd rather crash than silently corrupt math).
//   • Constructed from either the server String (BigInt) or a plain
//     Int (catalog priceChips). The String initializer is failable so
//     a malformed payload doesn't get silently zeroed.
//   • Subtraction returns `Result<ChipAmount, InsufficientFunds>` so
//     callers can't accidentally produce a negative balance for the
//     preview copy. `+` is total — there is no "too many chips" failure.
//   • Formatting matches the existing UserProfile.formattedChips
//     convention (K/M suffix) so the store doesn't render a different
//     style than ChipsView / ProfileView. Long-form `description` is
//     the raw count with thousands separators, used inside the alert
//     copy where the player wants to see the exact number.
//
// The type is intentionally not Codable; the server contract stays as
// `String` on UserProfile / catalog payloads, and the conversions live
// at the boundary (initializers + `serverString`).

struct ChipAmount: Equatable, Hashable, Comparable {

    /// Underlying chip count. Always >= 0 by construction — every
    /// public path that could go negative is funneled through
    /// `subtracting(_:)` which returns `.insufficientFunds` instead.
    let rawValue: Int64

    // ── Constants ────────────────────────────────────────────────────────────

    static let zero = ChipAmount(rawValue: 0)

    // ── Initializers ─────────────────────────────────────────────────────────

    /// Designated init. Negative inputs are clamped to zero rather than
    /// crashing — a negative chip count is nonsensical, and the only
    /// way to reach this in practice is a malformed server payload that
    /// we'd rather render as 0 than fatal-error on.
    init(rawValue: Int64) {
        self.rawValue = max(0, rawValue)
    }

    /// From a small literal price (catalog `priceChips: Int`). Negative
    /// prices are clamped to zero — the catalog validator should reject
    /// them upstream but defense-in-depth here keeps the type total.
    init(_ value: Int) {
        self.init(rawValue: Int64(max(0, value)))
    }

    /// From the server BigInt-as-String form. Returns nil on a
    /// non-numeric or whitespace-padded payload so the caller can decide
    /// whether to fall back to zero or surface an error. We deliberately
    /// do NOT accept "1.5K" / "1,000" / locale-formatted strings here —
    /// those are display formats, not transport formats.
    init?(serverString: String) {
        guard let n = Int64(serverString) else { return nil }
        self.init(rawValue: n)
    }

    // ── Arithmetic ───────────────────────────────────────────────────────────

    enum SubtractionFailure: Error, Equatable {
        case insufficientFunds(shortBy: ChipAmount)
    }

    /// Total subtraction. Returns `.failure(.insufficientFunds)` instead
    /// of producing a negative amount. The `shortBy` payload makes the
    /// "you need N more chips" copy possible without a second arithmetic
    /// pass at the call site.
    func subtracting(_ other: ChipAmount) -> Result<ChipAmount, SubtractionFailure> {
        if other.rawValue > rawValue {
            return .failure(.insufficientFunds(
                shortBy: ChipAmount(rawValue: other.rawValue - rawValue)
            ))
        }
        return .success(ChipAmount(rawValue: rawValue - other.rawValue))
    }

    /// Total addition. Traps on Int64 overflow — that scenario is
    /// already an upstream contract violation (chipBalance must fit in
    /// Int64 today; if product moves past that we revisit this whole
    /// type). Silent wraparound would be worse than a crash here.
    func adding(_ other: ChipAmount) -> ChipAmount {
        let (sum, overflow) = rawValue.addingReportingOverflow(other.rawValue)
        precondition(!overflow, "ChipAmount.adding overflowed Int64; balance contract violated")
        return ChipAmount(rawValue: sum)
    }

    /// Convenience predicate for the "can afford" check at the call
    /// site — same semantics as `self >= price` but reads better in
    /// view-model code: `if balance.canAfford(price) { ... }`.
    func canAfford(_ price: ChipAmount) -> Bool {
        rawValue >= price.rawValue
    }

    // ── Comparable ───────────────────────────────────────────────────────────

    static func < (lhs: ChipAmount, rhs: ChipAmount) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    // ── Output forms ─────────────────────────────────────────────────────────

    /// Serialize back to the server transport format. Round-trips with
    /// `init?(serverString:)`. Used when we need to send the balance
    /// (or a derived amount) back to the backend.
    var serverString: String { String(rawValue) }

    /// Short K/M-suffixed form matching UserProfile.formattedChips so
    /// chip pills across the app render identically. Used by the
    /// top-right balance pill in StoreView.
    var shortFormatted: String {
        let n = rawValue
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000     { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }

    /// Long form with thousands separators ("1,234,567"). Used inside
    /// the purchase confirmation alert where the exact number matters
    /// ("You'll have 12,345 chips remaining"). Locale-aware so users
    /// in regions that use "." or " " as the thousands separator see
    /// their native grouping.
    var longFormatted: String {
        ChipAmount.longFormatter.string(from: NSNumber(value: rawValue)) ?? "\(rawValue)"
    }

    private static let longFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSize = 3
        f.usesGroupingSeparator = true
        return f
    }()
}
