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
            // Dark gradient background — matches the rest of the app's
            // dark-mode aesthetic so the paywall feels native, not bolted-on.
            LinearGradient(
                colors: [Color(hex: "#0A0E1A"), Color(hex: "#0A0A0F")],
                startPoint: .top, endPoint: .bottom
            ).ignoresSafeArea()

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
        VStack(spacing: 12) {
            // Crown badge — gold gradient circle, signals "premium" without
            // shouting. Sized to read at a glance without dominating the view.
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "#F5C842"), Color(hex: "#D4A02A")],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 76, height: 76)
                    .shadow(color: Color(hex: "#F5C842").opacity(0.5),
                            radius: 18, y: 6)
                Image(systemName: "crown.fill")
                    .font(.system(size: 34, weight: .black))
                    .foregroundStyle(Color(hex: "#0D1B2A"))
            }

            Text("Stack Premium")
                .font(.system(size: 28, weight: .black, design: .rounded))
                .foregroundStyle(.white)

            Text("Study your hands. Plug your leaks. Win more.")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
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
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(hex: "#0D1B2A").opacity(0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(Color(hex: "#2A3D6A"), lineWidth: 1)
                )
        )
    }

    // ─── CTA Stack ───────────────────────────────────────────────────────────
    // Trial button is the primary; subscription is secondary. If the trial
    // has already been consumed, the trial button is hidden and subscription
    // becomes primary (visual emphasis swaps).

    @ViewBuilder
    private var ctaStack: some View {
        VStack(spacing: 12) {
            if !sub.trialUsed {
                // Primary: free trial. Big gold pill — same color language as
                // the daily bonus card so the user reads "free chips" energy.
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    sub.startTrial()
                } label: {
                    VStack(spacing: 2) {
                        Text("Start 2-Day Free Trial")
                            .font(.system(size: 17, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color(hex: "#0D1B2A"))
                        Text("No card required")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color(hex: "#0D1B2A").opacity(0.6))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 60)
                    .background(
                        LinearGradient(
                            colors: [Color(hex: "#F5C842"), Color(hex: "#D4A02A")],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: Color(hex: "#F5C842").opacity(0.4),
                            radius: 12, y: 4)
                }
                .buttonStyle(.plain)
            }

            // Subscription button — secondary when trial is available,
            // primary when trial has been consumed. We don't actually swap
            // the visual style yet; both states use the dark-pill treatment
            // because StoreKit is stubbed and we don't want to over-promote
            // a button that pops "Coming soon".
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showStoreKitComingSoon = true
                // TODO: when StoreKit is live, replace with:
                //   Task { await sub.purchaseMonthly() }
            } label: {
                HStack {
                    Text("Subscribe Monthly")
                        .font(.system(size: 16, weight: .bold))
                    Spacer()
                    Text("\(monthlyPrice)/mo")
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color(hex: "#F5C842"))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .frame(height: 56)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(hex: "#1A2744"))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(Color(hex: "#2A3D6A"), lineWidth: 1)
                        )
                )
            }
            .buttonStyle(.plain)

            // Fine print — required by the App Store to disclose
            // auto-renewing-subscription terms. Even though we're stubbed,
            // adding the language now means we don't forget at submission.
            Text("Auto-renews monthly. Cancel anytime in Settings.")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
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
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(.white.opacity(0.5))
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
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color(hex: "#F5C842"))
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.65))
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
            HStack(spacing: 8) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 12, weight: .heavy))
                Text("Premium trial — \(formatRemaining(secs)) left")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                Spacer(minLength: 0)
            }
            .foregroundStyle(Color(hex: "#0D1B2A"))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                LinearGradient(
                    colors: [Color(hex: "#F5C842"), Color(hex: "#D4A02A")],
                    startPoint: .leading, endPoint: .trailing
                )
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
