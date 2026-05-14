import SwiftUI

// ─── Daily Bonus Card ─────────────────────────────────────────────────────────
// Lobby element that lets the user claim a once-per-24h chip bonus. Backend
// (`POST /chips/daily`) is the source of truth: it grants 1000 chips (1500
// when balance < 200) and rejects repeat calls today with code
// "ALREADY_CLAIMED" + a message containing hours-until-reset.
//
// Visual model (rev 2):
//   • READY    — a single card-back, sized large, gently bouncing with a
//                pulsing gold glow. The whole card is the tap target —
//                "pull a card from the deck" framing.
//   • CLAIMING — bounce/glow freeze; spinner overlays the card.
//   • SUCCESS  — card flips 180° to reveal a gold "+1000 CHIPS" face,
//                holds briefly, then collapses to nothing.
//   • COOLDOWN — view collapses entirely (EmptyView). The lobby VStack
//                spacing absorbs the gap so the home screen looks like
//                the bonus simply isn't there until it's ready again.
//                The card reappears automatically when the local cooldown
//                timer ticks down to zero.
//
// Local cache (`@AppStorage`) tracks the next-eligible timestamp so the card
// boots into the right state without a network round-trip and survives app
// relaunches. The server remains authoritative — every tap calls the API.

struct DailyBonusCard: View {
    @EnvironmentObject var authVM: AuthViewModel
    // Root-level reveal presenter. The card itself no longer animates the
    // flip / reveal; it hands the amount off to this presenter, which drives
    // a full-screen overlay so the celebration can grow above the lobby and
    // tab bar instead of being clipped inside the ScrollView.
    @EnvironmentObject var revealPresenter: DailyBonusRevealPresenter

    // Captured at tap-time via GeometryReader — passed to the presenter so
    // the expanding card animates from the exact spot the user tapped, not
    // from the screen center. Updated continuously so scroll position and
    // device rotation don't desync the origin frame.
    @State private var inlineFrame: CGRect = .zero

    // Local cache: ms-since-epoch when the user can next claim. Backend remains
    // authoritative; we just read this on appear so we don't flash "Claim" when
    // we already know the user is in cooldown. Cleared after a successful claim
    // (set forward to roughly "now + 24h") and after the cooldown elapses.
    //
    // Keyed per-user (suffixed with the current account id) — earlier we used a
    // single `@AppStorage("lastDailyBonusClaimMs")` value, but UserDefaults is
    // per-device, so signing out of one account and into another inherited the
    // first account's cooldown and left brand-new accounts with no card visible
    // at all (cooldown phase renders EmptyView). Per-user keying isolates each
    // account's cooldown without needing to clear keys on logout.
    private var lastClaimMs: Double {
        get { UserDefaults.standard.double(forKey: claimStorageKey) }
        nonmutating set { UserDefaults.standard.set(newValue, forKey: claimStorageKey) }
    }
    private var claimStorageKey: String {
        // Fall back to "anonymous" before the user profile loads. The first
        // hydrate runs against this bucket; we re-hydrate as soon as the real
        // user id arrives via .onChange below, so the brief anonymous window
        // never causes a stuck cooldown.
        "lastDailyBonusClaimMs." + (authVM.currentUser?.id ?? "anonymous")
    }

    // ── UI state machine ─────────────────────────────────────────────────────
    private enum Phase {
        case ready
        case claiming
        case success(amount: Int)
        case cooldown(secondsLeft: Int)
    }

    @State private var phase: Phase = .ready
    @State private var errorMessage: String?

    // Drives the bounce + glow loop while .ready. Toggled in onAppear and
    // animated with a `.repeatForever` so the motion runs continuously.
    @State private var bounce = false

    // Drives the cooldown countdown without holding a long-running Task. Fires
    // every second only while the card is on screen; we tear it down via the
    // VStack collapse when it transitions to .cooldown EmptyView.
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        // Whole view collapses when the bonus isn't ready. Caller's VStack
        // spacing closes the gap automatically — no placeholder needed.
        Group {
            switch phase {
            case .cooldown:
                EmptyView()
            default:
                cardSurface
            }
        }
        .onAppear  {
            hydrateFromCache()
            startBounceLoop()
        }
        // Re-hydrate when the user id resolves (post-login) or changes
        // (logout → re-login as another account). Without this, the first
        // hydrate runs against the "anonymous" bucket and never re-checks
        // once the real user id arrives.
        .onChange(of: authVM.currentUser?.id) { _, _ in hydrateFromCache() }
        .onReceive(ticker) { _ in tickCooldown() }
        .animation(.spring(response: 0.45, dampingFraction: 0.75), value: phaseKey)
    }

    // ─── Main card surface ───────────────────────────────────────────────────
    // Centered card-back with bounce + glow when ready, spinner overlay while
    // claiming, and a flipped reward face on success.

    @ViewBuilder
    private var cardSurface: some View {
        VStack(spacing: 8) {
            // ── Card-back tap target ────────────────────────────────────────
            // The flip / reveal is now handled by DailyBonusRevealOverlay at
            // the app root, so the inline card just needs to render the back
            // face, broadcast its on-screen frame to the presenter, and show
            // a spinner while the network call is in flight.
            DailyBonusCardBack()
                .frame(width: 64, height: 90)
                .frame(width: 76, height: 92) // breathing room for glow
                .overlay(claimingOverlay)
                // Capture the inline frame in global coordinates and stash
                // it so claim() can hand it to the presenter as the origin
                // for the expand animation. .global means the rect is in
                // window-space and lines up correctly with the overlay.
                .background(
                    GeometryReader { proxy in
                        Color.clear
                            .onAppear { inlineFrame = proxy.frame(in: .global) }
                            .onChange(of: proxy.frame(in: .global)) { _, new in
                                inlineFrame = new
                            }
                    }
                )
                // Bounce only when ready — frozen during claim so the motion
                // doesn't compete with the overlay reveal.
                .offset(y: isReady && bounce ? -6 : 0)
            // Scale pulse runs alongside the bounce — same trigger value so
            // the two stay phase-locked. Keep the amplitude small (3%) so it
            // reads as "alive" rather than "broken layout".
            .scaleEffect(isReady && bounce ? 1.03 : 1.0)
            // Soft gold glow pulse — biggest tell that the card is tappable.
            .shadow(color: glowColor.opacity(isReady && bounce ? 0.8 : 0.35),
                    radius: isReady && bounce ? 22 : 12,
                    y: 4)
            // The full card silhouette is the tap target. We use a Button so
            // VoiceOver picks it up; .plain style strips the system tinting.
            .onTapGesture { Task { await claim() } }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Daily Chips. Tap to claim your free chips.")
            .accessibilityAddTraits(.isButton)

            // ── Caption under the card ──────────────────────────────────────
            // Two-line copy gives just enough context (what + cadence) without
            // re-introducing the wide banner the previous design had.
            captionView
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, SPSpacing.md)
        .padding(.vertical, 4)
        // Whole card-and-caption fades / scales in when reappearing after a
        // cooldown ends, and out after the success reveal collapses to none.
        .transition(.scale(scale: 0.85).combined(with: .opacity))
    }

    // ─── Caption (varies by phase) ───────────────────────────────────────────

    @ViewBuilder
    private var captionView: some View {
        switch phase {
        case .ready:
            VStack(spacing: 2) {
                Text("DAILY CHIPS!")
                    .font(SPRetroFonts.display(15))
                    .foregroundStyle(SPRetro.ink)
                    .tracking(1)
                if let err = errorMessage {
                    Text(err)
                        .font(SPRetroFonts.callout(12))
                        .foregroundStyle(SPRetro.popRed)
                } else {
                    Text("Tap to reveal your reward")
                        .font(SPRetroFonts.body(12))
                        .foregroundStyle(SPRetro.inkSoft)
                }
            }
        case .claiming:
            Text("Claiming…")
                .font(SPRetroFonts.callout(13))
                .foregroundStyle(SPRetro.inkSoft)
        case .success(let amount):
            Text("+\(formatChips(String(amount))) chips!")
                .font(SPRetroFonts.display(15))
                .foregroundStyle(SPRetro.maroon)
        case .cooldown:
            EmptyView()
        }
    }

    // Spinner overlay — only shown while the request is in flight. Sits on
    // top of the back face so the bounce halts but the card is still visible.
    // Retro: ink scrim instead of system black; mustard spinner tint so it
    // sits in the same comic-panel palette as the rest of the card.
    @ViewBuilder
    private var claimingOverlay: some View {
        if case .claiming = phase {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(SPRetro.ink.opacity(0.55))
                ProgressView()
                    .tint(SPRetro.mustard)
            }
            .padding(2) // sit just inside the card's outer corner radius
        }
    }

    // ─── Actions ─────────────────────────────────────────────────────────────

    private func claim() async {
        // Guard against rapid double-taps. We only flip into .claiming from
        // .ready; any other phase silently ignores the tap.
        guard case .ready = phase else { return }

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        errorMessage = nil
        withAnimation(.easeInOut(duration: 0.2)) { phase = .claiming }

        let result = await authVM.claimDailyBonus()
        switch result {
        case .success(let amount):
            UINotificationFeedbackGenerator().notificationOccurred(.success)

            // Hand the celebration off to the root-level overlay. We pass the
            // captured global frame so the expanding card grows from the
            // exact spot the user tapped — a brief geometry handshake makes
            // the transition feel like the inline card *is* the card that
            // expanded, instead of a separate animation kicking in.
            revealPresenter.present(amount: amount, from: inlineFrame)

            // Optimistically lock out claims for the next 24h locally. The
            // backend will still gate independently; this just keeps the UI
            // consistent across relaunches before midnight.
            lastClaimMs = Date().addingTimeInterval(24 * 3600).timeIntervalSince1970 * 1000

            // Inline card collapses immediately so the "expanding" card in
            // the overlay isn't competing with a duplicate sitting in the
            // lobby. Cooldown phase renders EmptyView, which yanks the card
            // out of the lobby's VStack — the celebration plays solo.
            transitionToCooldown()

        case .alreadyClaimed(let message):
            // Server says the user already claimed today — extract the hour
            // count from its message ("Come back in 7h ..."). If parsing fails
            // we fall back to a default 12h estimate so the UI still ticks.
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            let secs = parseSecondsFromMessage(message) ?? (12 * 3600)
            lastClaimMs = Date().addingTimeInterval(TimeInterval(secs))
                .timeIntervalSince1970 * 1000
            withAnimation(.easeInOut(duration: 0.3)) {
                phase = .cooldown(secondsLeft: secs)
            }

        case .failure(let message):
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            errorMessage = message
            withAnimation { phase = .ready }
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
    // to .ready when the timer hits zero, with a spring transition so the
    // card pops back into the lobby. Also resets the flip rotation so the
    // back face is what the user sees on the next claim cycle.
    private func tickCooldown() {
        guard case .cooldown(let secs) = phase else { return }
        if secs <= 1 {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                phase = .ready
            }
            lastClaimMs = 0
        } else {
            // Don't animate every tick — the UI doesn't change while
            // cooldown is showing (EmptyView), but assigning still triggers
            // SwiftUI body re-evaluation. Cheap; fine to leave un-animated.
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
        withAnimation(.easeInOut(duration: 0.4)) {
            phase = .cooldown(secondsLeft: secs)
        }
    }

    // Kicks off the perpetual bounce/glow loop. Safe to call repeatedly —
    // SwiftUI's withAnimation will simply restart the same loop with the
    // current value as the starting point.
    private func startBounceLoop() {
        // Slight delay so the initial layout doesn't fight the first
        // animation tick (otherwise the card sometimes mounts mid-bounce).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                bounce = true
            }
        }
    }

    // ─── Derived helpers ─────────────────────────────────────────────────────

    private var isReady: Bool {
        if case .ready = phase { return true }
        return false
    }

    private var glowColor: Color {
        // Mustard glow when ready (soliciting a tap), muted maroon when the
        // card is mid-claim. Both colors live in the retro palette so the
        // glow blends with the rest of the home screen instead of reading as
        // a foreign neon effect on the paper.
        isReady ? SPRetro.mustard : SPRetro.maroon
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

    // SwiftUI's .animation(_:value:) needs an Equatable hash; the Phase enum
    // has associated values so we expose a stable string key for animation
    // change detection only (not for any logic).
    private var phaseKey: String {
        switch phase {
        case .ready:               return "ready"
        case .claiming:            return "claiming"
        case .success:             return "success"
        case .cooldown:            return "cooldown"
        }
    }
}

