import Foundation
import SwiftUI

// ─── Cosmetic Data Model ──────────────────────────────────────────────────────
//
// Core value type for the entire cosmetics system. Loaded from the bundled
// `cosmetics_catalog.json` resource and surfaced through `CosmeticsCatalog`.
//
// Why this is in `Features/Cosmetics/Models/` rather than at the top level:
// matches the existing convention (`Features/<Domain>/Models/...`) used by
// Auth, Lobby, etc. Keeps the cosmetics surface area cleanly enclosed so
// later iterations (server-backed catalog, additional categories, bundle
// definitions) don't bleed into other features' import paths.
//
// All identifiers are plain `String`s for now. We chose String over a
// phantom-typed wrapper because:
//   1. The catalog JSON authoring path is human-edited — quoted strings are
//      the right ergonomics for hand-rolled config files.
//   2. The persistence path (UserDefaults JSON) round-trips cleanly without
//      a custom Codable for the wrapper.
//   3. Phantom types are added value only if we're mixing IDs across many
//      domains; here we only ever index cosmetics by their own ID.
// If we ever start cross-referencing CosmeticID with UserID / TableID and
// want compile-time type safety, this is a single-file refactor.

typealias CosmeticID = String

// ─── Category ─────────────────────────────────────────────────────────────────
//
// Each cosmetic belongs to exactly one category. The equipped-slots dict in
// PlayerInventory is keyed by category (one equipped item per category), so
// the enum case set IS the equipped-slot set — adding a new cosmetic type
// always means adding a case here, by design.

enum CosmeticCategory: String, Codable, CaseIterable, Hashable {
    case cardBack
    case chipSet
    case avatarFrame
    case tableFelt
    case cardFace
    case dealAnimation
    case winAnimation
    case emote
    case playerTitle

    /// Human-readable plural label, used in the catalog/inventory section
    /// headers and filter chips. Pre-localized via NSLocalizedString so the
    /// Phase-2 UI is set up for Localizable.strings without any later edits.
    var displayName: String {
        switch self {
        case .cardBack:       return NSLocalizedString("Card Backs",        comment: "Cosmetic category: card backs")
        case .chipSet:        return NSLocalizedString("Chip Sets",         comment: "Cosmetic category: chip sets")
        case .avatarFrame:    return NSLocalizedString("Avatar Frames",     comment: "Cosmetic category: avatar frames")
        case .tableFelt:      return NSLocalizedString("Table Felts",       comment: "Cosmetic category: table felts")
        case .cardFace:       return NSLocalizedString("Card Faces",        comment: "Cosmetic category: card faces")
        case .dealAnimation:  return NSLocalizedString("Deal Animations",   comment: "Cosmetic category: deal animations")
        case .winAnimation:   return NSLocalizedString("Win Celebrations",  comment: "Cosmetic category: win animations")
        case .emote:          return NSLocalizedString("Emotes",            comment: "Cosmetic category: emotes")
        case .playerTitle:    return NSLocalizedString("Titles",            comment: "Cosmetic category: player titles")
        }
    }

    /// SF Symbol used as the placeholder icon overlay on `CosmeticImageView`
    /// before the designer-supplied PNG is bundled. The mapping is intentionally
    /// generic — a card back image just shows "rectangle.on.rectangle", not
    /// the unique Black-Diamond pattern, since that's exactly the purpose of
    /// the placeholder (it should be visually distinct from real art so the
    /// gap is obvious at a glance).
    var placeholderIconSystemName: String {
        switch self {
        case .cardBack:       return "rectangle.on.rectangle.angled"
        case .chipSet:        return "circle.hexagongrid.fill"
        case .avatarFrame:    return "person.circle"
        case .tableFelt:      return "rectangle.fill"
        case .cardFace:       return "suit.spade.fill"
        case .dealAnimation:  return "hand.draw"
        case .winAnimation:   return "sparkles"
        case .emote:          return "face.smiling"
        case .playerTitle:    return "rosette"
        }
    }
}

// ─── Rarity ───────────────────────────────────────────────────────────────────
//
// Rarity tiers and their canonical color tokens. The hex values match the
// spec literally — these are the *only* place where these specific colors
// should be defined; every store/inventory rendering site reads from here.
// If we ever rebrand, this is the one file that changes.

enum CosmeticRarity: String, Codable, CaseIterable, Hashable {
    case common
    case rare
    case epic
    case legendary
    case mythic

    /// Sort ordinal — higher = rarer. Used by the default "rarity desc"
    /// sort in the catalog tab. Stored explicitly rather than relying on
    /// `CaseIterable.allCases.firstIndex` so adding a future "uncommon"
    /// tier between common and rare doesn't silently reshuffle every
    /// existing comparison.
    var sortOrdinal: Int {
        switch self {
        case .common:    return 0
        case .rare:      return 1
        case .epic:      return 2
        case .legendary: return 3
        case .mythic:    return 4
        }
    }

    /// Solid display color. Mythic returns the *base* color of its
    /// animated gradient (red-orange #EF4444 → #F59E0B); the animated
    /// gradient itself is built in the view layer via `gradientStops` so
    /// the static-color call sites still work.
    var solidColor: Color {
        switch self {
        case .common:    return Color(hex: "#9CA3AF")
        case .rare:      return Color(hex: "#3B82F6")
        case .epic:      return Color(hex: "#A855F7")
        case .legendary: return Color(hex: "#F59E0B")
        case .mythic:    return Color(hex: "#EF4444")
        }
    }

    /// Mythic-only — the two stops of its animated gradient. Empty array
    /// for every other rarity so callers can write a single conditional
    /// `if !gradientStops.isEmpty { animate } else { solid }`.
    var gradientStops: [Color] {
        switch self {
        case .mythic: return [Color(hex: "#EF4444"), Color(hex: "#F59E0B")]
        default:      return []
        }
    }

    /// Human-readable label for the rarity badge.
    var displayName: String {
        switch self {
        case .common:    return NSLocalizedString("Common",    comment: "Rarity tier")
        case .rare:      return NSLocalizedString("Rare",      comment: "Rarity tier")
        case .epic:      return NSLocalizedString("Epic",      comment: "Rarity tier")
        case .legendary: return NSLocalizedString("Legendary", comment: "Rarity tier")
        case .mythic:    return NSLocalizedString("Mythic",    comment: "Rarity tier")
        }
    }
}

// ─── Unlock Condition ─────────────────────────────────────────────────────────
//
// How a cosmetic can be acquired. `purchase` is the only path that flows
// through StorePurchaseService; the rest are granted by the matching
// engagement-loop system (achievement, season pass, leaderboard reward,
// event reward — all stubs in Phase 1, real in Phase 5).
//
// Why this is an enum on the cosmetic itself rather than a field on the
// player's inventory entry: it's an immutable *property* of the cosmetic
// (a Mythic Inferno frame is always a season-only unlock, regardless of
// which player owns it). Moving it onto the inventory entry would invert
// the relationship — every owner would need to know the unlock path, and
// migrations between paths would be impossible.

enum UnlockCondition: String, Codable, Hashable {
    case purchase        // priceChips > 0, store-purchasable
    case achievement     // granted by AchievementService (Phase 5c)
    case seasonPass      // granted by SeasonPassService (Phase 5d)
    case leaderboard     // weekly top-10 reward (Phase 5e)
    case eventReward     // ad-hoc limited-time event drops
}

// ─── Cosmetic ─────────────────────────────────────────────────────────────────

struct Cosmetic: Codable, Identifiable, Hashable {
    let id: CosmeticID
    let name: String
    let category: CosmeticCategory
    let rarity: CosmeticRarity

    /// Price in virtual chips. Zero (or absent in JSON) for any cosmetic
    /// whose `unlockCondition` isn't `.purchase`. Validated by
    /// `StorePurchaseService` — a purchase attempt against a non-purchase
    /// cosmetic returns `.error(.notPurchasable)`.
    let priceChips: Int

    /// Limited-time items disappear from the Featured/Catalog tabs after
    /// `availableUntil`. Already-owned copies are unaffected — the limit
    /// is on acquisition, not on use. `false` means evergreen.
    let isLimitedTime: Bool

    /// Absolute deadline for purchasability. Nil for evergreen items. The
    /// Phase 2 store filters this server-clock-aware via the existing
    /// network time source so a client with skewed clock can't extend the
    /// window by changing local time — but in Phase 1 (client-only catalog)
    /// we use `Date()`; the cost of clock skew is at worst showing a
    /// limited item for an extra few minutes, not a security issue.
    let availableUntil: Date?

    /// Bundle asset name for the *real* image, when one exists.
    /// `CosmeticImageView` falls back to a rarity-tinted programmatic
    /// placeholder if the named asset isn't found in `Assets.xcassets`.
    /// Convention: `cosmetic_<category>_<id>` — see CosmeticImageView
    /// for the resolution policy.
    let previewAssetName: String

    let unlockCondition: UnlockCondition

    /// True if this cosmetic can be acquired through the store. Computed
    /// rather than stored so the `unlockCondition == .purchase` invariant
    /// isn't expressed in two places that could diverge.
    var isPurchasable: Bool {
        unlockCondition == .purchase && priceChips > 0
    }

    /// True if a limited-time window has elapsed (or, defensively, if the
    /// `availableUntil` is missing for an item flagged `isLimitedTime`).
    /// Drives the store's "Leaves in 3d 4h" countdown surface — when this
    /// returns true the item is greyed out and unpurchasable.
    func isExpired(now: Date = Date()) -> Bool {
        guard isLimitedTime else { return false }
        guard let deadline = availableUntil else { return true }
        return now >= deadline
    }

    /// Time remaining until the limited-time deadline, or nil for evergreen
    /// items. Used by the Featured tab countdown.
    func timeUntilExpiry(now: Date = Date()) -> TimeInterval? {
        guard isLimitedTime, let deadline = availableUntil else { return nil }
        return max(0, deadline.timeIntervalSince(now))
    }

    // ── Codable customisation ────────────────────────────────────────────────
    // We allow `priceChips` and `availableUntil` and `isLimitedTime` to be
    // *absent* in the JSON for evergreen non-purchasable items (achievement
    // titles etc.) so the catalog file stays readable — the typical row is
    // 4-5 fields, not 8.
    private enum CodingKeys: String, CodingKey {
        case id, name, category, rarity, priceChips, isLimitedTime,
             availableUntil, previewAssetName, unlockCondition
    }

    init(id: CosmeticID,
         name: String,
         category: CosmeticCategory,
         rarity: CosmeticRarity,
         priceChips: Int = 0,
         isLimitedTime: Bool = false,
         availableUntil: Date? = nil,
         previewAssetName: String,
         unlockCondition: UnlockCondition) {
        self.id = id
        self.name = name
        self.category = category
        self.rarity = rarity
        self.priceChips = priceChips
        self.isLimitedTime = isLimitedTime
        self.availableUntil = availableUntil
        self.previewAssetName = previewAssetName
        self.unlockCondition = unlockCondition
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id               = try c.decode(CosmeticID.self,        forKey: .id)
        name             = try c.decode(String.self,            forKey: .name)
        category         = try c.decode(CosmeticCategory.self,  forKey: .category)
        rarity           = try c.decode(CosmeticRarity.self,    forKey: .rarity)
        priceChips       = try c.decodeIfPresent(Int.self,      forKey: .priceChips)       ?? 0
        isLimitedTime    = try c.decodeIfPresent(Bool.self,     forKey: .isLimitedTime)    ?? false
        availableUntil   = try c.decodeIfPresent(Date.self,     forKey: .availableUntil)
        previewAssetName = try c.decode(String.self,            forKey: .previewAssetName)
        unlockCondition  = try c.decode(UnlockCondition.self,   forKey: .unlockCondition)
    }
}
