import SwiftUI

// ─── Paywall View ────────────────────────────────────────────────────────────
// Shown in place of ReviewDashboardView when the user lacks premium access.
// Two CTAs:
//   1. "Start 2-Day Free Trial" — only visible if trial unused. Tapping it
//      flips SubscriptionManager state and the parent gate re-renders into
//      the real Review dashboard.
//   2. "Subscribe Monthly" — stubbed until StoreKit is wired up. Surfaces a
//      "Coming soon" alert rather than silently doing nothing.
//
// No "dismiss" button: this view replaces the Review tab content, so the
// user can leave by tapping any other tab. That's intentional — modal
// paywalls feel pushier than tab-replacement paywalls.

struct PaywallView: View {
    @EnvironmentObject var sub: SubscriptionManager
    @State private var showStoreKitComingSoon = false

    // Single price string so changing $9.99 → $4.99 only touches one line.
    // Will move to StoreKit Product.displayPrice once products are configured.
    private let monthlyPrice = "$9.99"

    var body: some View {
        ZStack {
            // Aged-paper substrate — paywall now reads as a printed
            // premium-club page in the same booklet as the lobby and
            // game, rather than a dark "upsell" surface bolted on.
            AgedPaperBackground().ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    header
                    featureList
                    Spacer(minLength: 8)
                    trialAlreadyUsedNote
                    ctaStack
                    Spacer(minLength: 80)  // room above tab bar
                }
                .padding(.horizontal, 22)
                .padding(.top, 32)
            }
        }
        .alert("Subscriptions coming soon",
               isPresented: $showStoreKitComingSoon) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("In the meantime, start your 2-day free trial to test out hand review and equity analysis.")
        }
    }

    // ─── Header ──────────────────────────────────────────────────────────────

    private var header: some View {
        // Retro premium header — mustard burst-disc crown with ink panel
        // border + hard offset shadow (same vocab as the lobby logo disc
        // and the auth header), AmericanTypewriter-Bold ink title.
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(SPRetro.ink)
                    .frame(width: 76, height: 76)
                    .offset(x: 2.5, y: 3.5)
                Circle()
                    .fill(SPRetro.mustard)
                    .frame(width: 76, height: 76)
                Circle()
                    .strokeBorder(SPRetro.ink, lineWidth: 2.5)
                    .frame(width: 76, height: 76)
                Image(systemName: "crown.fill")
                    .font(.system(size: 34, weight: .black))
                    .foregroundStyle(SPRetro.ink)
            }

            Text("STACK PREMIUM")
                .font(.custom("AmericanTypewriter-Bold", size: 28))
                .tracking(1.2)
                .foregroundStyle(SPRetro.ink)

            Text("Study your hands. Plug your leaks. Win more.")
                .font(.custom("AmericanTypewriter", size: 14))
                .foregroundStyle(SPRetro.inkSoft)
                .multilineTextAlignment(.center)
        }
    }

    // ─── Feature List ────────────────────────────────────────────────────────

    private var featureList: some View {
        VStack(spacing: 12) {
            FeatureRow(
                icon: "rectangle.stack.fill",
                title: "Full hand replay",
                detail: "Step through every action, every street. See exactly what you did right — and wrong."
            )
            FeatureRow(
                icon: "chart.bar.fill",
                title: "Equity analysis",
                detail: "Live equity at every street. Know whether you were ahead before the river surprised you."
            )
            FeatureRow(
                icon: "scope",
                title: "Leak detection",
                detail: "Coach-style breakdowns of recurring mistakes across your hand history."
            )
            FeatureRow(
                icon: "infinity",
                title: "Unlimited history",
                detail: "Every hand you've ever played, kept and searchable."
            )
        }
        .padding(16)
        .background(
            // Retro feature panel — paperShade card with ink panel
            // border, no offset shadow (this is a body block, not a CTA).
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(SPRetro.paperShade)
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(SPRetro.ink, lineWidth: 1.5)
            }
        )
    }

    // ─── CTA Stack ───────────────────────────────────────────────────────────
    // Trial button is the primary; subscription is secondary. If the trial
    // has already been consumed, the trial button is hidden and subscription
    // becomes primary (visual emphasis swaps).

    @ViewBuilder
    private var ctaStack: some View {
        VStack(spacing: 12) {
            // Retro primary CTA: mustard pill with ink panel border and
            // a hard offset shadow — same vocab as SPButton primary so
            // the trial offer reads as the same stamped sticker the user
            // taps everywhere else in the app.
            if !sub.trialUsed {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    sub.startTrial()
                } label: {
                    VStack(spacing: 2) {
                        Text("Start 2-Day Free Trial")
                            .font(.custom("AmericanTypewriter-Bold", size: 17))
                            .tracking(0.5)
                            .foregroundStyle(SPRetro.ink)
                        Text("No card required")
                            .font(.custom("AmericanTypewriter", size: 11))
                            .foregroundStyle(SPRetro.inkMuted)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 60)
                    .background(
                        ZStack {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(SPRetro.ink)
                                .offset(x: 2, y: 3)
                            RoundedRectangle(cornerRadius: 16)
                                .fill(SPRetro.mustard)
                            RoundedRectangle(cornerRadius: 16)
                                .strokeBorder(SPRetro.ink, lineWidth: 2)
                        }
                    )
                }
                .buttonStyle(.plain)
            }

            // Retro secondary CTA: paperShade pill with ink border and a
            // small offset shadow. Mustard accent-dark price so it still
            // reads as a price-button without competing with the primary.
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showStoreKitComingSoon = true
            } label: {
                HStack {
                    Text("Subscribe Monthly")
                        .font(.custom("AmericanTypewriter-Bold", size: 16))
                        .foregroundStyle(SPRetro.ink)
                    Spacer()
                    Text("\(monthlyPrice)/mo")
                        .font(.custom("ChalkboardSE-Bold", size: 16))
                        .foregroundStyle(SPRetro.mustardDark)
                }
                .padding(.horizontal, 18)
                .frame(height: 56)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(SPRetro.ink)
                            .offset(x: 1.5, y: 2.5)
                        RoundedRectangle(cornerRadius: 14)
                            .fill(SPRetro.paperShade)
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(SPRetro.ink, lineWidth: 1.5)
                    }
                )
            }
            .buttonStyle(.plain)

            Text("Auto-renews monthly. Cancel anytime in Settings.")
                .font(.custom("AmericanTypewriter", size: 11))
                .foregroundStyle(SPRetro.inkMuted)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
        }
    }

    // ─── Trial-Already-Used Note ─────────────────────────────────────────────
    // If the trial was started and then expired, we want to acknowledge that
    // without making it feel like a punishment. A muted line is enough.

    @ViewBuilder
    private var trialAlreadyUsedNote: some View {
        if sub.trialUsed && !sub.trialActive {
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.system(size: 12, weight: .semibold))
                Text("Your free trial has ended.")
                    .font(.custom("AmericanTypewriter-Bold", size: 13))
            }
            .foregroundStyle(SPRetro.inkMuted)
        }
    }
}

// ─── Feature Row ─────────────────────────────────────────────────────────────
// Single line item in the paywall feature list. Gold check + title + body.
// Kept fileprivate-style as a sibling struct so it can't be reused
// elsewhere by accident — the styling is paywall-specific.

private struct FeatureRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        // Retro feature row: mustard ink-stroke icon + ink title + ink-
        // soft body, sits on paperShade panel from the parent.
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(SPRetro.mustardDark)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.custom("AmericanTypewriter-Bold", size: 15))
                    .foregroundStyle(SPRetro.ink)
                Text(detail)
                    .font(.custom("AmericanTypewriter", size: 12))
                    .foregroundStyle(SPRetro.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

// ─── Trial Banner ────────────────────────────────────────────────────────────
// Thin gold strip rendered above ReviewDashboardView while the trial is
// active. Shows time remaining so the user knows the clock is ticking.
// Self-driving via Timer.publish — no parent state required.

struct TrialBanner: View {
    @EnvironmentObject var sub: SubscriptionManager

    // Minute-resolution ticker. We don't need second-level precision here
    // (the banner says "1d 14h"), so this barely costs anything and means
    // SwiftUI doesn't re-render this view 60x more than needed.
    private let ticker = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    @State private var nowTick: Int = 0

    var body: some View {
        // Read live so the countdown updates per tick. The body re-runs
        // whenever `nowTick` changes, which re-evaluates the manager's
        // `trialSecondsRemaining`.
        let _ = nowTick
        let secs = sub.trialSecondsRemaining
        if sub.trialActive {
            // Retro trial banner: solid mustard strip with ink top/bottom
            // hairlines and AmericanTypewriter-Bold ink copy. Reads as a
            // printed ribbon stamped across the top of the Review tab.
            HStack(spacing: 8) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 12, weight: .heavy))
                Text("Premium trial — \(formatRemaining(secs)) left")
                    .font(.custom("AmericanTypewriter-Bold", size: 12))
                    .tracking(0.4)
                Spacer(minLength: 0)
            }
            .foregroundStyle(SPRetro.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                ZStack {
                    Rectangle().fill(SPRetro.mustard)
                    VStack(spacing: 0) {
                        Rectangle().fill(SPRetro.ink).frame(height: 1)
                        Spacer()
                        Rectangle().fill(SPRetro.ink).frame(height: 1)
                    }
                }
            )
            .onReceive(ticker) { _ in nowTick &+= 1 }
        }
    }

    // "1d 14h", "23h 12m", "47m" — picks the two largest non-zero units so
    // the string stays compact. Falls back to seconds in the final minute.
    private func formatRemaining(_ seconds: Int) -> String {
        let s = max(0, seconds)
        let d = s / 86400
        let h = (s % 86400) / 3600
        let m = (s % 3600) / 60
        if d > 0 { return "\(d)d \(h)h" }
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m" }
        return "<1m"
    }
}
