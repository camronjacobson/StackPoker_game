import SwiftUI

// ─── Opponent quick-profile popup ────────────────────────────────────────────
// Lightweight panel that appears when the user taps another player's seat at
// the table. Shows the opponent's avatar, username, and VPIP%, plus a single
// friend-button CTA whose label/state mirrors the existing Friendship row in
// the DB (NONE → Add, PENDING/OUTGOING → Sent, INCOMING → Accept, ACCEPTED →
// Friends). The user explicitly asked for "less is more", so this view is
// intentionally compact — one card, one stat, one button.
//
// Lifecycle:
//   • The owning view (PokerTableView) drives presentation by setting
//     `selectedUserId`. The popup fetches its own data via /quick-profile.
//   • Tap on the dimmed backdrop, or successful friend send, dismisses by
//     clearing `selectedUserId`.

// ─── Model ────────────────────────────────────────────────────────────────────

/// Decoded shape of GET /api/users/:id/quick-profile.
/// `convertFromSnakeCase` is on globally for the JSONDecoder, so the camelCase
/// keys align directly with what the backend emits.
struct QuickProfile: Decodable {
    let userId: String
    let username: String
    let displayName: String
    let avatarId: String
    let handsPlayed: Int
    let vpipHands: Int
    let friendshipStatus: String     // NONE / PENDING / ACCEPTED / BLOCKED
    let friendshipDirection: String? // OUTGOING / INCOMING (when applicable)
    let friendshipId: String?
    let isSelf: Bool
    // Backend flags AI accounts (currently just StackBot) so the popup can
    // hide the meaningless 0% VPIP / 0 hands and label the row as AI. Optional
    // to stay backwards-compatible with older builds where the field is
    // absent — those clients fall through to the existing "—" small-sample
    // path and never see a misleading 0%.
    let isBot: Bool?

    /// Rendered VPIP percentage. Hidden by the view (see `vpipDisplay`) when
    /// the sample is too small to be meaningful — a single hand of "100%"
    /// or "0%" tells the reader nothing useful.
    var vpipPercent: Int {
        guard handsPlayed > 0 else { return 0 }
        return Int((Double(vpipHands) / Double(handsPlayed) * 100).rounded())
    }
}

// ─── ViewModel ────────────────────────────────────────────────────────────────

@MainActor
final class OpponentPopupVM: ObservableObject {
    @Published var profile: QuickProfile?
    @Published var isLoading = false
    @Published var isSending = false
    @Published var errorText: String?

    private let network = NetworkService.shared

    /// Fetch quick-profile for the tapped user. Re-callable — clears prior
    /// state so a stale popup never flashes the previous opponent's data.
    func load(userId: String) async {
        profile = nil
        errorText = nil
        isLoading = true
        defer { isLoading = false }
        do {
            let p: QuickProfile = try await network.request(.quickProfile(userId: userId))
            profile = p
        } catch let err as NetworkError {
            errorText = err.localizedDescription
        } catch {
            errorText = "Couldn't load profile"
        }
    }

    /// Send a friend request. Optimistically advances `friendshipStatus` to
    /// PENDING/OUTGOING so the button updates instantly; the backend remains
    /// the source of truth on next refresh.
    func sendFriendRequest() async {
        guard let p = profile, !isSending else { return }
        isSending = true
        defer { isSending = false }
        do {
            struct Empty: Decodable {}
            let _: Empty = try await network.request(
                .sendFriendRequest(userId: p.userId),
                method: .POST
            )
            // Reflect the new state without re-fetching.
            profile = QuickProfile(
                userId: p.userId,
                username: p.username,
                displayName: p.displayName,
                avatarId: p.avatarId,
                handsPlayed: p.handsPlayed,
                vpipHands: p.vpipHands,
                friendshipStatus: "PENDING",
                friendshipDirection: "OUTGOING",
                friendshipId: p.friendshipId,
                isSelf: p.isSelf,
                isBot: p.isBot
            )
        } catch let err as NetworkError {
            errorText = err.localizedDescription
        } catch {
            errorText = "Couldn't send request"
        }
    }

    /// Accept an incoming friend request (the case where the popup target
    /// already invited *us* — then the CTA reads "Accept").
    func acceptIncoming() async {
        guard let p = profile, let id = p.friendshipId, !isSending else { return }
        isSending = true
        defer { isSending = false }
        do {
            struct Body: Encodable { let accept: Bool }
            struct Empty: Decodable {}
            let _: Empty = try await network.request(
                .respondFriendRequest(id: id),
                method: .POST,
                body: Body(accept: true)
            )
            profile = QuickProfile(
                userId: p.userId,
                username: p.username,
                displayName: p.displayName,
                avatarId: p.avatarId,
                handsPlayed: p.handsPlayed,
                vpipHands: p.vpipHands,
                friendshipStatus: "ACCEPTED",
                friendshipDirection: nil,
                friendshipId: id,
                isSelf: p.isSelf,
                isBot: p.isBot
            )
        } catch let err as NetworkError {
            errorText = err.localizedDescription
        } catch {
            errorText = "Couldn't accept request"
        }
    }
}

// ─── View ─────────────────────────────────────────────────────────────────────

struct OpponentPopupView: View {
    let userId: String
    let onDismiss: () -> Void

    @StateObject private var vm = OpponentPopupVM()

    var body: some View {
        ZStack {
            // Ink-tinted scrim instead of a black overlay — sits in the
            // retro palette without going pure black on the cream page.
            SPRetro.ink.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }
                .transition(.opacity)

            card
                .frame(maxWidth: 280)
                .transition(.scale(scale: 0.85).combined(with: .opacity))
        }
        .task(id: userId) { await vm.load(userId: userId) }
    }

    // ─── Card ─────────────────────────────────────────────────────────────────

    private var card: some View {
        // Retro comic panel: paper substrate, ink panel border, hard ink
        // offset shadow (no blur). The shadow sits beneath the rounded
        // paper card via a ZStack so it isn't clipped by .background.
        VStack(spacing: 14) {
            avatarRow
            vpipRow
            actionButton
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(SPRetro.ink)
                    .offset(x: 2.5, y: 4)
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(SPRetro.paper)
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(SPRetro.ink, lineWidth: 2)
            }
        )
    }

    // Avatar + name. We use displayName as the primary line and @username
    // small underneath so the popup reads as a real social mini-profile.
    @ViewBuilder
    private var avatarRow: some View {
        HStack(spacing: 12) {
            // Avatar disc — paperShade circle with an ink border, matches
            // the seat avatars on the table.
            Circle()
                .fill(SPRetro.paperShade)
                .overlay(
                    Circle().strokeBorder(SPRetro.ink, lineWidth: 1.5)
                )
                .frame(width: 46, height: 46)
                .overlay(
                    Text(AvatarOption.find(vm.profile?.avatarId ?? "avatar_1").emoji)
                        .font(.system(size: 26))
                )

            VStack(alignment: .leading, spacing: 2) {
                // Display name in AmericanTypewriter-Bold ink; @handle in
                // AmericanTypewriter ink-soft. Same pairing the rest of the
                // app uses for primary + secondary labels.
                Text(vm.profile?.displayName ?? " ")
                    .font(.custom("AmericanTypewriter-Bold", size: 16))
                    .foregroundStyle(SPRetro.ink)
                    .lineLimit(1)
                if let u = vm.profile?.username {
                    Text("@\(u)")
                        .font(.custom("AmericanTypewriter", size: 12))
                        .foregroundStyle(SPRetro.inkMuted)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
    }

    // Single VPIP stat. Below ~10 hands the % is too noisy to be worth
    // showing, so we show "—" and explain it's still being measured. This
    // matches how poker apps typically gate small-sample stats.
    //
    // For AI seats (StackBot) the backend flags `isBot: true` and we swap the
    // whole row for an "AI Opponent" line. Bots never have stats written for
    // them, so previously this row read "0%" with "0 hands", which the player
    // correctly perceived as a glitch. Showing the bot label is the honest
    // version of "no data" — and it tells them *why* there's no data.
    @ViewBuilder
    private var vpipRow: some View {
        // Retro stat row: paperShade card on the paper substrate, ink
        // border + a tiny hard offset shadow so the stat panel reads as
        // pasted onto the popup. Retro fonts (AmericanTypewriter-Bold
        // labels with tracking, ChalkboardSE-Bold numbers).
        if vm.profile?.isBot == true {
            HStack(spacing: 10) {
                Image(systemName: "cpu")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SPRetro.inkMuted)
                VStack(alignment: .leading, spacing: 2) {
                    Text("AI OPPONENT")
                        .font(.custom("AmericanTypewriter-Bold", size: 11))
                        .foregroundStyle(SPRetro.inkMuted)
                        .tracking(1.2)
                    Text("Stats not tracked")
                        .font(.custom("AmericanTypewriter", size: 13))
                        .foregroundStyle(SPRetro.inkSoft)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(retroStatBackground)
        } else {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("VPIP")
                        .font(.custom("AmericanTypewriter-Bold", size: 11))
                        .foregroundStyle(SPRetro.inkMuted)
                        .tracking(1.2)
                    Text(vpipDisplay)
                        .font(.custom("ChalkboardSE-Bold", size: 22))
                        .foregroundStyle(SPRetro.ink)
                }
                Spacer()
                Text("\(vm.profile?.handsPlayed ?? 0) hands")
                    .font(.custom("AmericanTypewriter", size: 11))
                    .foregroundStyle(SPRetro.inkMuted)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(retroStatBackground)
        }
    }

    /// PaperShade card behind a stat row — ink hairline + tiny offset
    /// shadow. Extracted so both VPIP and AI variants stay in lockstep.
    private var retroStatBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(SPRetro.ink)
                .offset(x: 1, y: 1.5)
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(SPRetro.paperShade)
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(SPRetro.ink, lineWidth: 1)
        }
    }

    private var vpipDisplay: String {
        guard let p = vm.profile else { return "—" }
        if p.handsPlayed < 10 { return "—" }
        return "\(p.vpipPercent)%"
    }

    // Single CTA whose label + behavior depends on friendship state. We hide
    // the button entirely for self-taps (isSelf) so the popup degrades to a
    // read-only card — there's nothing useful to do with your own row here.
    @ViewBuilder
    private var actionButton: some View {
        // Hide the friend button for self AND for bot accounts. There's no
        // "befriend the AI" flow on the server, and showing an Add button
        // that errors on tap would be confusing — better to keep the popup
        // a clean read-only card for bot taps.
        if let p = vm.profile, !p.isSelf, p.isBot != true {
            // Retro CTA: hard ink offset shadow + color capsule + ink
            // border. The capsule color is decided per friendship state
            // (see ctaColor). Text/icon color flips to ink on the lighter
            // states (paperShade for "Request Sent"/"Unavailable") and
            // paper on the saturated states.
            Button(action: handlePrimaryAction) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(SPRetro.ink)
                        .offset(x: 1.5, y: 2.5)
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(ctaColor)
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(SPRetro.ink, lineWidth: 1.5)
                    HStack(spacing: 6) {
                        if vm.isSending {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .controlSize(.small)
                                .tint(ctaForeground)
                        } else {
                            Image(systemName: ctaIcon)
                                .font(.system(size: 13, weight: .bold))
                        }
                        Text(ctaLabel)
                            .font(.custom("AmericanTypewriter-Bold", size: 14))
                    }
                    .foregroundStyle(ctaForeground)
                    .padding(.vertical, 10)
                }
                .frame(maxWidth: .infinity)
                .fixedSize(horizontal: false, vertical: true)
            }
            .disabled(!ctaEnabled || vm.isSending)
            .opacity(ctaEnabled ? 1.0 : 0.65)
        } else if vm.isLoading {
            // Loading shimmer in ink-soft so the placeholder reads as a
            // printed line on the cream popup rather than a white halo.
            ProgressView()
                .progressViewStyle(.circular)
                .tint(SPRetro.inkMuted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
        }
    }

    // Maps current friendship status to button copy + icon + tap behavior.
    // Centralizing this keeps the per-state branching out of the view body
    // and makes it obvious which states are dead-ends (Already Friends,
    // Blocked, Pending Outgoing) vs. actionable (Add, Accept).
    private var ctaLabel: String {
        guard let p = vm.profile else { return "Add Friend" }
        switch (p.friendshipStatus, p.friendshipDirection) {
        case ("ACCEPTED", _):           return "Friends"
        case ("PENDING", "OUTGOING"):   return "Request Sent"
        case ("PENDING", "INCOMING"):   return "Accept Request"
        case ("BLOCKED", _):            return "Unavailable"
        default:                        return "Add Friend"
        }
    }
    private var ctaIcon: String {
        guard let p = vm.profile else { return "person.badge.plus" }
        switch (p.friendshipStatus, p.friendshipDirection) {
        case ("ACCEPTED", _):           return "checkmark"
        case ("PENDING", "OUTGOING"):   return "clock"
        case ("PENDING", "INCOMING"):   return "person.badge.plus"
        case ("BLOCKED", _):            return "xmark"
        default:                        return "person.badge.plus"
        }
    }
    /// Retro CTA palette per friendship state:
    ///   - ACCEPTED:        muted teal — already friends, neutral confirm
    ///   - PENDING OUTGOING: paperShade — read-only "sent" sticker
    ///   - PENDING INCOMING: mustard   — primary "accept" call-to-action
    ///   - BLOCKED:         paperShade — inert
    ///   - default (NONE):  mustard   — primary "add friend" CTA
    private var ctaColor: Color {
        guard let p = vm.profile else { return SPRetro.mustard }
        switch (p.friendshipStatus, p.friendshipDirection) {
        case ("ACCEPTED", _):           return SPRetro.teal
        case ("PENDING", "OUTGOING"):   return SPRetro.paperShade
        case ("PENDING", "INCOMING"):   return SPRetro.mustard
        case ("BLOCKED", _):            return SPRetro.paperShade
        default:                        return SPRetro.mustard
        }
    }

    /// Foreground (icon + label) color paired with `ctaColor`. Mustard /
    /// paperShade pills get ink text for contrast; muted-teal gets paper.
    private var ctaForeground: Color {
        guard let p = vm.profile else { return SPRetro.ink }
        switch (p.friendshipStatus, p.friendshipDirection) {
        case ("ACCEPTED", _):           return SPRetro.paper
        default:                        return SPRetro.ink
        }
    }
    private var ctaEnabled: Bool {
        guard let p = vm.profile else { return false }
        switch (p.friendshipStatus, p.friendshipDirection) {
        case ("PENDING", "INCOMING"): return true
        case ("NONE", _):             return true
        default:                      return false
        }
    }

    private func handlePrimaryAction() {
        guard let p = vm.profile else { return }
        Task {
            if p.friendshipStatus == "PENDING" && p.friendshipDirection == "INCOMING" {
                await vm.acceptIncoming()
            } else if p.friendshipStatus == "NONE" {
                await vm.sendFriendRequest()
            }
        }
    }
}
