import SwiftUI

// ─── Cosmetic Image View ──────────────────────────────────────────────────────
//
// THE single switch-point between "real art shipped in Assets.xcassets" and
// "programmatic rarity-tinted placeholder". Replacing all placeholders with
// real art later is a single change here, never anywhere else.
//
// Resolution order:
//   1. If `Assets.xcassets` contains an image named `cosmetic.previewAssetName`,
//      render that image.
//   2. Otherwise, render the rarity-tinted placeholder: a rounded rect filled
//      with the rarity color (or animated gradient for mythic), with the
//      category SF Symbol icon centred and the cosmetic name overlaid below.
//
// Why a single component rather than per-category views: every category's
// store cell, locker tile, preview modal, and at-table render needs the
// same fallback logic. Spreading the switch-point across the codebase is
// how things drift — a designer drops in a new Black Diamond PNG but the
// store still shows a placeholder because that call site got missed.

struct CosmeticImageView: View {
    let cosmetic: Cosmetic
    /// Width-height square dimension. Use 80-100 for grid cells, 200+ for
    /// the preview modal. The placeholder layout adapts (name only shows
    /// at sizes >= 60).
    var size: CGFloat = 100
    /// If true, the rarity glow halo is drawn behind the artwork — used in
    /// the store grid where rarity is the primary visual signal. Off in
    /// the inventory locker (where rarity is shown by a sidebar badge,
    /// not a glow, to keep the grid calmer).
    var showRarityGlow: Bool = true

    var body: some View {
        ZStack {
            if showRarityGlow { glowHalo }
            artwork
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(cosmetic.rarity.solidColor, lineWidth: 2)
                )
        }
        .frame(width: size, height: size)
    }

    private var cornerRadius: CGFloat { size * 0.12 }

    // ── Artwork resolution ───────────────────────────────────────────────────
    //
    // UIImage(named:) returns nil if the asset isn't in any catalog the
    // bundle knows about. We use that as the switch — no need to register
    // an explicit "missing-art" list. Adding a new PNG to Assets.xcassets
    // under the convention name automatically promotes that cosmetic from
    // placeholder to real.

    @ViewBuilder private var artwork: some View {
        if assetExists {
            Image(cosmetic.previewAssetName)
                .resizable()
                .scaledToFill()
        } else {
            placeholder
        }
    }

    /// Synchronous existence probe via UIImage(named:). Cheap because
    /// UIImage uses an internal cache after the first miss, so we don't
    /// hit disk every body evaluation.
    private var assetExists: Bool {
        UIImage(named: cosmetic.previewAssetName) != nil
    }

    // ── Placeholder ──────────────────────────────────────────────────────────

    @ViewBuilder private var placeholder: some View {
        ZStack {
            placeholderFill
            VStack(spacing: size * 0.05) {
                Image(systemName: cosmetic.category.placeholderIconSystemName)
                    .font(.system(size: size * 0.32, weight: .bold))
                    .foregroundStyle(.white.opacity(0.95))
                if size >= 60 {
                    Text(cosmetic.name)
                        .font(.system(size: size * 0.11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.95))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .padding(.horizontal, size * 0.08)
                }
            }
        }
    }

    /// Fill — solid rarity color for common/rare/epic/legendary, animated
    /// linear gradient for mythic. Mythic animates because it's the literal
    /// "ultimate flex" rarity per the spec and should read differently at
    /// a glance even in motion-thumbnailed previews.
    @ViewBuilder private var placeholderFill: some View {
        if cosmetic.rarity == .mythic {
            MythicGradientFill()
        } else {
            cosmetic.rarity.solidColor
        }
    }

    // ── Rarity glow halo ─────────────────────────────────────────────────────
    //
    // A soft outer glow tinted by rarity. Common items get a very faint
    // halo so the visual language is consistent across tiers; legendaries
    // get a strong glow that genuinely makes them stand out in a grid.
    // Mythic uses the animated gradient color stop for its glow.

    @ViewBuilder private var glowHalo: some View {
        RoundedRectangle(cornerRadius: cornerRadius + 4)
            .fill(cosmetic.rarity.solidColor)
            .opacity(glowOpacity)
            .blur(radius: glowBlur)
            .frame(width: size + 16, height: size + 16)
    }

    private var glowOpacity: Double {
        switch cosmetic.rarity {
        case .common:    return 0.05
        case .rare:      return 0.20
        case .epic:      return 0.35
        case .legendary: return 0.55
        case .mythic:    return 0.65
        }
    }

    private var glowBlur: CGFloat {
        switch cosmetic.rarity {
        case .common:    return 4
        case .rare:      return 8
        case .epic:      return 12
        case .legendary: return 16
        case .mythic:    return 20
        }
    }
}

// ─── Mythic animated gradient fill ────────────────────────────────────────────
//
// Animates the gradient angle continuously. Kept as a separate view so
// SwiftUI can isolate the animation invalidation — only this subview
// re-renders per tick, not the whole CosmeticImageView body.

private struct MythicGradientFill: View {
    @State private var rotation: Double = 0

    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            // 8-second full rotation. Slow enough to feel premium, fast
            // enough to be noticeable on a still preview tile.
            let angle = Angle(degrees: t.truncatingRemainder(dividingBy: 8) / 8 * 360)
            LinearGradient(
                colors: CosmeticRarity.mythic.gradientStops,
                startPoint: UnitPoint(
                    x: 0.5 + 0.5 * cos(angle.radians),
                    y: 0.5 + 0.5 * sin(angle.radians)
                ),
                endPoint: UnitPoint(
                    x: 0.5 - 0.5 * cos(angle.radians),
                    y: 0.5 - 0.5 * sin(angle.radians)
                )
            )
        }
    }
}
