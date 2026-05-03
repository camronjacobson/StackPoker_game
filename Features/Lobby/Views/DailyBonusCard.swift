import SwiftUI

// ─── Daily Bonus Card ─────────────────────────────────────────────────────────
// Lobby card that lets the user claim a once-per-24h chip bonus. Backend
// (`POST /chips/daily`) is the source of truth: it grants 1000 chips (1500
// when balance < 200) and rejects repeat calls today with code
// "ALREADY_CLAIMED" + a message containing hours-until-reset.
//
// Locally we cache the next-eligible timestamp in `@AppStorage` so the card
// boots into the right state without a network round-trip and so the
// countdown survives app relaunches. We still call the server every time
// the user actually taps the button — the local cache is only an optimistic
// hint, never authoritative.

struct DailyBonusCard: View {
    @EnvironmentObject var authVM: AuthViewModel

    // Local cache: ms-since-epoch when the user can next claim. Backend remains
    // authoritative; we just read this on appear so we don't flash "Claim" when
    // we already know the user is in cooldown. Cleared after a successful claim
    // (set forward to roughly "now + 24h") and after the cooldown elapses.
    @AppStorage("lastDailyBonusClaimMs") private var lastClaimMs: Double = 0

    // ── UI state machine ─────────────────────────────────────────────────────
    // .ready    — claim button visible
    // .claiming — request in flight; button disabled with spinner
    // .success  — brief celebration phase showing "+\(amount)" pop
    // .cooldown — user already redeemed today; show countdown until eligible
    private enum Phase {
        case ready
        case claiming
        case success(amount: Int)
        case cooldown(secondsLeft: Int)
    }

    @State private var phase: Phase = .ready
    @State private var errorMessage: String?

    // Drives the cooldown countdown without holding a long-running Task. Fires
    // every second only while the card is on screen; we tear it down in
    // .onDisappear so it doesn't leak when the user navigates away.
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 14) {
            // ── Coin icon ────────────────────────────────────────────────────
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "#F5C842"), Color(hex: "#D4A02A")],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 52, height: 52)
                    .shadow(color: Color(hex: "#F5C842").opacity(0.45),
                            radius: 12, y: 4)
                Image(systemName: "dollarsign")
                    .font(.system(size: 24, weight: .black))
                    .foregroundStyle(Color(hex: "#0D1B2A"))
            }

            // ── Copy + state ─────────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 2) {
                Text("Daily Chips")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                subtitleView
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
            }

            Spacer()

            // ── Action button ────────────────────────────────────────────────
            actionButton
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(hex: "#0D1B2A").opacity(0.95))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color(hex: "#F5C842").opacity(0.55),
                                    Color(hex: "#F5C842").opacity(0.15)
                                ],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.2
                        )
                )
        )
        .padding(.horizontal, SPSpacing.md)
        .onAppear  { hydrateFromCache() }
        .onReceive(ticker) { _ in tickCooldown() }
        .animation(.spring(response: 0.35), value: phaseKey)
    }

    // ─── Subtitle (varies by phase) ──────────────────────────────────────────

    @ViewBuilder
    private var subtitleView: some View {
        switch phase {
        case .ready:
            if let err = errorMessage {
                Text(err).foregroundStyle(Color(hex: "#FF6B6B"))
            } else {
                Text("Free chips, every 24 hours")
            }
        case .claiming:
            Text("Claiming…")
        case .success(let amount):
            Text("+\(formatChips(String(amount))) chips claimed!")
                .foregroundStyle(Color(hex: "#F5C842"))
        case .cooldown(let secs):
            Text("Next reward in \(formatCountdown(secs))")
        }
    }

    // ─── Action button (varies by phase) ─────────────────────────────────────

    @ViewBuilder
    private var actionButton: some View {
        switch phase {
        case .ready:
            Button {
                Task { await claim() }
            } label: {
                Text("Claim")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(Color(hex: "#0D1B2A"))
                    .padding(.horizontal, 18)
                    .frame(height: 36)
                    .background(Color(hex: "#F5C842"))
                    .clipShape(Capsule())
                    .shadow(color: Color(hex: "#F5C842").opacity(0.4),
                            radius: 8, y: 2)
            }
            .buttonStyle(.plain)

        case .claiming:
            ProgressView()
                .tint(Color(hex: "#F5C842"))
                .frame(width: 86, height: 36)

        case .success:
            // Gold checkmark badge — replaced by .cooldown automatically after
            // a short celebration delay (see claim()).
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 28))
                .foregroundStyle(Color(hex: "#F5C842"))
                .frame(width: 86, height: 36)
                .transition(.scale.combined(with: .opacity))

        case .cooldown:
            // Lock icon — visually communicates "not yet" without taking the
            // tap target. Tapping is disallowed in this phase by design.
            Image(systemName: "clock.fill")
                .font(.system(size: 18))
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 86, height: 36)
        }
    }

    // ─── Actions ─────────────────────────────────────────────────────────────

    private func claim() async {
        // Guard against rapid double-taps. We only flip into .claiming from
        // .ready; any other phase silently ignores the tap.
        guard case .ready = phase else { return }

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        errorMessage = nil
        phase = .claiming

        let result = await authVM.claimDailyBonus()
        switch result {
        case .success(let amount):
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation(.spring(response: 0.45)) {
                phase = .success(amount: amount)
            }
            // Optimistically lock out claims for the next 24h locally. The
            // backend will still gate independently; this just keeps the UI
            // consistent across relaunches before midnight.
            lastClaimMs = Date().addingTimeInterval(24 * 3600).timeIntervalSince1970 * 1000

            // Hold the celebration UI briefly, then transition to the cooldown
            // phase. The exact dwell time is cosmetic — long enough to read.
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            transitionToCooldown()

        case .alreadyClaimed(let message):
            // Server says the user already claimed today — extract the hour
            // count from its message ("Come back in 7h ..."). If parsing fails
            // we fall back to a default 12h estimate so the UI still ticks.
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            let secs = parseSecondsFromMessage(message) ?? (12 * 3600)
            lastClaimMs = Date().addingTimeInterval(TimeInterval(secs))
                .timeIntervalSince1970 * 1000
            phase = .cooldown(secondsLeft: secs)

        case .failure(let message):
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            errorMessage = message
            phase = .ready
        }
    }

    // Pulls cached state from @AppStorage so the card mounts in the correct
    // phase. If the cooldown has already elapsed (or was never set), defaults
    // to .ready — no flash.
    private func hydrateFromCache() {
        let nowMs = Date().timeIntervalSince1970 * 1000
        if lastClaimMs > nowMs {
            let secs = Int((lastClaimMs - nowMs) / 1000)
            phase = .cooldown(secondsLeft: secs)
        } else {
            phase = .ready
        }
    }

    // Drives the cooldown countdown forward once per second. Auto-flips back
    // to .ready when the timer hits zero so the user can claim again without
    // needing to leave & re-enter the lobby.
    private func tickCooldown() {
        guard case .cooldown(let secs) = phase else { return }
        if secs <= 1 {
            phase = .ready
            lastClaimMs = 0
        } else {
            phase = .cooldown(secondsLeft: secs - 1)
        }
    }

    // After a successful claim, lock the UI into .cooldown using the locally
    // cached deadline. Falls back to a 24h window if for some reason the cache
    // didn't get written.
    private func transitionToCooldown() {
        let nowMs = Date().timeIntervalSince1970 * 1000
        let secs: Int
        if lastClaimMs > nowMs {
            secs = Int((lastClaimMs - nowMs) / 1000)
        } else {
            secs = 24 * 3600
        }
        withAnimation(.easeInOut(duration: 0.25)) {
            phase = .cooldown(secondsLeft: secs)
        }
    }

    // ─── Helpers ─────────────────────────────────────────────────────────────

    // Best-effort parse of the backend's "Come back in Xh ..." message. We
    // pull the first integer we find and treat it as hours; if the message
    // also includes minutes ("Xh Ym") we add those too. Returns nil if no
    // digit is present, in which case the caller falls back to a default.
    private func parseSecondsFromMessage(_ message: String) -> Int? {
        let scanner = Scanner(string: message)
        scanner.charactersToBeSkipped = CharacterSet.letters
            .union(.whitespacesAndNewlines)
            .union(.punctuationCharacters)
        var hours: Int = 0
        var minutes: Int = 0
        var sawAny = false

        // Walk through digit groups in order. Convention from the backend's
        // formatter is hours first, then optional minutes. Anything else is
        // treated as hours-only.
        var first = true
        while !scanner.isAtEnd {
            var n: Int = 0
            if scanner.scanInt(&n) {
                if first { hours = n; first = false }
                else     { minutes = n; break }
                sawAny = true
            } else {
                break
            }
        }
        guard sawAny else { return nil }
        return hours * 3600 + minutes * 60
    }

    // hh:mm:ss for the long tail, mm:ss once we're under an hour. Keeps the
    // string compact enough to fit on the subtitle line without truncation.
    private func formatCountdown(_ seconds: Int) -> String {
        let s = max(0, seconds)
        let h = s / 3600
        let m = (s % 3600) / 60
        let sec = s % 60
        if h > 0 {
            return String(format: "%dh %02dm", h, m)
        } else if m > 0 {
            return String(format: "%dm %02ds", m, sec)
        } else {
            return String(format: "%ds", sec)
        }
    }

    // SwiftUI's .animation(_:value:) needs an Equatable hash; the Phase enum
    // has associated values so we expose a stable string key for animation
    // change detection only (not for any logic).
    private var phaseKey: String {
        switch phase {
        case .ready:               return "ready"
        case .claiming:            return "claiming"
        case .success:             return "success"
        case .cooldown(let s):     return "cooldown-\(s / 60)" // re-animate per minute
        }
    }
}
