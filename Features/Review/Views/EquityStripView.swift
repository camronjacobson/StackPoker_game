import SwiftUI

// ─── Equity Strip View ────────────────────────────────────────────────────────
// PR 5 of the Review-feature overhaul.
//
// A fixed-height strip pinned between the replay controls and the analysis
// list. Two regions side-by-side:
//
//   • Left  — `EquityArcView`. A circular gauge that visualizes the hero's
//             rough win probability (0–1) at the current frame. Color tier
//             goes red → amber → blue → green so a glance reveals whether
//             the hero is ahead/behind, no number-reading required.
//
//   • Right — `DecisionCompareView` when the hero has a decision visible at
//             the current frame; `HandStrengthLabel` otherwise.
//             The compare view is a side-by-side: "YOU did X" vs "VERDICT" /
//             "SUGGESTED Y", with verdict color carrying through.
//
// Why a strip and not embedded inside AnalysisCardView?
//   The analysis list scrolls (running commentary). The equity arc is a
//   "where am I right now?" indicator and needs to stay visible at all
//   times, so it lives outside the scroll view.
//
// All data comes from `ReplayViewModel`. This view is a pure renderer — no
// state of its own beyond animation tracking.

struct EquityStripView: View {
    @ObservedObject var vm: ReplayViewModel

    var body: some View {
        HStack(spacing: SPSpacing.md) {
            // ── Equity arc on the left ──────────────────────────────────────
            EquityArcView(equity: vm.currentEquity)
                .frame(width: 56, height: 56)

            // ── Right-hand panel: decision compare OR strength label ───────
            // Decision compare wins when present — it contains the equity
            // signal too (verdict color), so we hide the strength label to
            // avoid duplicate signaling. We use Group so the transition
            // crossfades cleanly when scrubbing across decision boundaries.
            Group {
                if let decision = vm.currentHeroDecision {
                    DecisionCompareView(decision: decision)
                } else {
                    HandStrengthLabel(label: vm.currentStrengthLabel)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .id(vm.currentHeroDecision?.analysis.id ?? "no-decision")
            .transition(.opacity.combined(with: .move(edge: .trailing)))
        }
        .padding(.horizontal, SPSpacing.md)
        .padding(.vertical, SPSpacing.sm)
        .background(SPColors.surface)
        .overlay(
            // Hairline top + bottom rules so the strip reads as its own
            // band rather than blending into the controls or the list.
            VStack {
                Rectangle()
                    .fill(SPColors.border.opacity(0.6))
                    .frame(height: 0.5)
                Spacer()
                Rectangle()
                    .fill(SPColors.border.opacity(0.6))
                    .frame(height: 0.5)
            }
        )
        .animation(.easeInOut(duration: 0.3), value: vm.currentHeroDecision?.analysis.id)
    }
}

// ─── Equity Arc View ─────────────────────────────────────────────────────────
// Circular dial: light gray track behind, color-tiered arc in front. Number
// in the middle. Tier color makes the "am I ahead?" question answerable
// pre-cognitively — green/blue = good, amber = marginal, red = behind.

struct EquityArcView: View {
    let equity: Double  // 0…1; clamped on render

    /// Bucketed tint. Boundaries chosen so a coin-flip lands on the
    /// red/amber boundary (0.50) and a clear favorite hits green (0.65+).
    /// Tweaking these breakpoints is cheap — they only affect color, not
    /// the displayed number.
    private var tint: Color {
        switch clamped {
        case ..<0.30: return SPColors.danger    // far behind
        case ..<0.50: return SPColors.warning   // dog
        case ..<0.65: return SPColors.info      // marginal favorite
        default:      return SPColors.success   // clear favorite
        }
    }

    private var clamped: Double { max(0, min(1, equity)) }

    var body: some View {
        ZStack {
            // Background track — full circle so even a 0% equity hand
            // still has the gauge frame visible.
            Circle()
                .stroke(Color.white.opacity(0.10), lineWidth: 5)

            // Foreground arc — trimmed to the equity fraction. Rotated so
            // the arc starts at 12 o'clock (visually expected for a gauge)
            // and the round caps soften the start/end edges.
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [
                            tint.opacity(0.55),
                            tint,
                            tint.opacity(0.85)
                        ]),
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle:   .degrees(360 * clamped)
                    ),
                    style: StrokeStyle(lineWidth: 5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: tint.opacity(0.45), radius: 4)
                .animation(.easeInOut(duration: 0.45), value: clamped)

            // Numeric value. `.contentTransition(.numericText())` makes the
            // digits flip rather than swap, which reads as the gauge being
            // alive even when the user just steps one frame.
            VStack(spacing: -2) {
                Text("\(Int((clamped * 100).rounded()))")
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundStyle(tint)
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.3), value: clamped)
                Text("%")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(SPColors.textSecondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Equity \(Int((clamped * 100).rounded())) percent")
    }
}

// ─── Decision Compare View ───────────────────────────────────────────────────
// Two-card side-by-side comparison of the hero's most recent decision. Left
// card is what the hero actually did (verdict-tinted). Right card is the
// verdict outcome plus, when extractable, a suggested alternative verb.

struct DecisionCompareView: View {
    let decision: ReplayViewModel.HeroDecision

    private var verdictColor: Color { decision.analysis.verdict.color }

    var body: some View {
        HStack(spacing: 6) {
            // ── YOU card ────────────────────────────────────────────────────
            decisionCard(
                heading:    "YOU",
                value:      decision.actionLabel,
                accent:     verdictColor,
                fillOpacity: 0.18,
                strokeOpacity: 0.40
            )

            // Tiny "vs" connector — purely decorative but communicates that
            // the two cards are in dialogue, not just adjacent.
            Image(systemName: "arrow.right")
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(SPColors.textTertiary)

            // ── VERDICT / SUGGESTED card ────────────────────────────────────
            // If we managed to extract a suggested verb from the freeform
            // recommendation text, show it. Otherwise show the verdict label
            // (Solid / Fine / Borderline / Leak) — still useful at-a-glance.
            decisionCard(
                heading:    decision.suggestedActionLabel != nil ? "TRY" : "VERDICT",
                value:      decision.suggestedActionLabel ?? decision.analysis.verdict.label,
                accent:     decision.suggestedActionLabel != nil
                              ? SPColors.accentLight
                              : verdictColor,
                fillOpacity:  decision.suggestedActionLabel != nil ? 0.22 : 0.32,
                strokeOpacity: decision.suggestedActionLabel != nil ? 0.45 : 0.60
            )
        }
    }

    /// Reusable two-line card used for both the YOU and TRY/VERDICT cells.
    /// Centralized so the two cards stay visually paired (same height, same
    /// padding, same typography hierarchy) — only color and label differ.
    private func decisionCard(
        heading: String,
        value: String,
        accent: Color,
        fillOpacity: Double,
        strokeOpacity: Double
    ) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(heading)
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .foregroundStyle(accent)
                .tracking(0.8)
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(SPColors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(accent.opacity(fillOpacity))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(accent.opacity(strokeOpacity), lineWidth: 0.7)
                )
        )
    }
}

// ─── Hand Strength Label ─────────────────────────────────────────────────────
// Fallback right-hand panel shown when the hero hasn't acted yet (e.g. the
// opening "Dealt in" frame, or scrubbed back before any decision). Just
// surfaces the hand-strength text alongside the arc so the strip never
// renders empty.

private struct HandStrengthLabel: View {
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("HAND STRENGTH")
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .foregroundStyle(SPColors.textSecondary)
                .tracking(0.8)
            Text(label)
                .font(SPFonts.headline(14))
                .foregroundStyle(SPColors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}
