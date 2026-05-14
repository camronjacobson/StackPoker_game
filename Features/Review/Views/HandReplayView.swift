import SwiftUI

// ─── Hand Replay Screen ──────────────────────────────────────────────────────
// Three regions stacked vertically:
//
//   • Header   — hand metadata (table, hand #, result)
//   • Table    — ReplayTableView showing the current frame
//   • Analysis — running list of FrameAnalysis cards (newest at top)
//   • Controls — scrubber + prev/play/next + speed
//
// All driven by a single ReplayViewModel. The user is the only audience —
// nothing here goes back to the server.

struct HandReplayView: View {
    @StateObject var vm: ReplayViewModel
    @StateObject private var narrator = ReplayNarrator.shared
    @Environment(\.dismiss) private var dismiss

    init(hand: RecordedHand) {
        _vm = StateObject(wrappedValue: ReplayViewModel(hand: hand))
    }

    var body: some View {
        ZStack {
            SPColors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, SPSpacing.md)
                    .padding(.top, SPSpacing.sm)

                ReplayTableView(
                    frame: vm.currentFrame,
                    userId: vm.hand.userId,
                    winnerIds: Set(vm.hand.winners.map { $0.playerId })
                )
                .frame(height: 280)
                .padding(.top, SPSpacing.xs)

                controls
                    .padding(.horizontal, SPSpacing.md)
                    .padding(.vertical, SPSpacing.sm)

                // ── Equity strip (PR 5) ─────────────────────────────────
                // Pinned between the transport controls and the scrolling
                // analysis list so the "where do I stand right now?" gauge
                // and the most recent decision compare are always visible
                // — they don't scroll away with the commentary cards.
                EquityStripView(vm: vm)

                // Retro divider: solid ink hairline. No system Divider().
                Rectangle()
                    .fill(SPRetro.ink)
                    .frame(height: 1)

                analysisList
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Hand #\(vm.hand.handNumber)")
                    .font(.custom("AmericanTypewriter-Bold", size: 17))
                    .foregroundStyle(SPRetro.ink)
            }
        }
        .tint(SPRetro.ink)   // colors the system back chevron
        .onAppear  { TabBarVisibility.shared.isHidden = true }
        .onDisappear {
            TabBarVisibility.shared.isHidden = false
            narrator.stop()    // don't keep talking after the user leaves
        }
    }

    // ─── Header ──────────────────────────────────────────────────────────────

    private var header: some View {
        HStack(alignment: .center, spacing: SPSpacing.md) {
            // Hero hole cards
            HStack(spacing: 4) {
                ForEach(vm.hand.myHoleCards, id: \.id) { c in
                    HeroCardView(card: c)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(vm.hand.tableName)
                    .font(.custom("AmericanTypewriter-Bold", size: 15))
                    .foregroundStyle(SPRetro.ink)
                    .lineLimit(1)
                Text("vs \(vm.hand.opponents.joined(separator: ", "))")
                    .font(.custom("AmericanTypewriter", size: 11))
                    .foregroundStyle(SPRetro.inkMuted)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(vm.hand.iWon ? "+\(formatChips(vm.hand.stackDelta))"
                                  : formatChips(vm.hand.stackDelta))
                    .font(.custom("ChalkboardSE-Bold", size: 16))
                    .foregroundStyle(vm.hand.iWon ? SPColors.success : SPColors.danger)
                if let name = vm.hand.winningHandName {
                    Text(name)
                        .font(.custom("AmericanTypewriter", size: 10))
                        .foregroundStyle(SPRetro.inkMuted)
                        .lineLimit(1)
                }
            }
        }
    }

    // ─── Controls ────────────────────────────────────────────────────────────

    private var controls: some View {
        VStack(spacing: SPSpacing.sm) {
            // ── Street-zoned timeline rail. Replaces the bare system slider
            //    with four labeled bands (PRE / FLOP / TURN / RIVER), each
            //    proportional to the number of frames in that street. The
            //    playhead rides a tinted track and the rail accepts both
            //    taps and drags. The frame counter rides on the right.
            HStack(spacing: SPSpacing.sm) {
                StreetTimelineRail(
                    frames:     vm.hand.frames,
                    frameIndex: vm.frameIndex,
                    progress:   vm.progress,
                    onSeek:     { vm.seek(to: $0) }
                )
                .frame(height: 32)

                Text("\(vm.frameIndex + 1)/\(vm.totalFrames)")
                    .font(.custom("ChalkboardSE-Bold", size: 11))
                    .foregroundStyle(SPRetro.inkMuted)
                    .monospacedDigit()
            }

            // ── Transport row ────────────────────────────────────────────
            HStack(spacing: SPSpacing.lg) {
                Button {
                    haptic(.light)
                    vm.restart()
                } label: {
                    Image(systemName: "backward.end.fill")
                        .font(.system(size: 18))
                }

                Button {
                    haptic(.light)
                    vm.stepBack()
                } label: {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 22))
                }
                .disabled(!vm.canStepBack)

                // Play / pause with a thin progress ring around the button
                // mirroring playback position. Gives the user a second
                // visual anchor for "where am I in this hand?" right where
                // their thumb already is.
                Button {
                    haptic(.medium)
                    vm.togglePlay()
                } label: {
                    // Retro play disc: ink track + mustard progress arc +
                    // mustard inner disc with ink border + hard ink offset
                    // shadow. Reads as a stamped sticker button.
                    ZStack {
                        Circle()
                            .stroke(SPRetro.ink.opacity(0.25), lineWidth: 2.5)
                            .frame(width: 50, height: 50)
                        Circle()
                            .trim(from: 0, to: max(0.001, vm.progress))
                            .stroke(
                                SPRetro.mustardDark,
                                style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                            )
                            .frame(width: 50, height: 50)
                            .rotationEffect(.degrees(-90))
                        Circle()
                            .fill(SPRetro.ink)
                            .frame(width: 42, height: 42)
                            .offset(x: 1.5, y: 2)
                        Circle()
                            .fill(SPRetro.mustard)
                            .frame(width: 42, height: 42)
                        Circle()
                            .strokeBorder(SPRetro.ink, lineWidth: 1.5)
                            .frame(width: 42, height: 42)
                        Image(systemName: vm.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 17, weight: .heavy))
                            .foregroundStyle(SPRetro.ink)
                            .offset(x: vm.isPlaying ? 0 : 1.5) // optical center play tri.
                    }
                }

                Button {
                    haptic(.light)
                    vm.stepForward()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 22))
                }
                .disabled(!vm.canStepForward)

                // Speed cycle — icon changes with speed (turtle → hare →
                // bolt) so the metaphor is visible, not just the number.
                Button {
                    haptic(.light)
                    let next: [Double] = [0.5, 1.0, 1.5, 2.0]
                    let idx = next.firstIndex(of: vm.playbackSpeed) ?? 1
                    vm.playbackSpeed = next[(idx + 1) % next.count]
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: speedIcon(vm.playbackSpeed))
                            .font(.system(size: 11, weight: .bold))
                        Text(speedLabel(vm.playbackSpeed))
                            .font(.custom("ChalkboardSE-Bold", size: 11))
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 28)
                    .background(
                        ZStack {
                            Capsule().fill(SPRetro.paperShade)
                            Capsule().strokeBorder(SPRetro.ink, lineWidth: 1.2)
                        }
                    )
                }

                // Narration toggle — speaks each new analysis card aloud in
                // a soft female voice so the review feels like real coaching.
                Button {
                    haptic(.medium)
                    narrator.toggle()
                    // If turning on mid-replay, immediately read the latest
                    // visible card so the user gets feedback that it works.
                    if narrator.enabled, let newest = vm.visibleAnalyses.first {
                        narrator.speak(newest)
                    }
                } label: {
                    // Retro narration toggle: mustard sticker capsule when
                    // on, paperShade idle. Both with ink border 1.2pt.
                    Image(systemName: narrator.enabled
                          ? "speaker.wave.2.fill"
                          : "speaker.slash.fill")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 32, height: 28)
                        .background(
                            ZStack {
                                Capsule().fill(
                                    narrator.enabled
                                        ? SPRetro.mustard
                                        : SPRetro.paperShade
                                )
                                Capsule().strokeBorder(SPRetro.ink, lineWidth: 1.2)
                            }
                        )
                        .foregroundStyle(SPRetro.ink)
                }
                .accessibilityLabel(narrator.enabled ? "Mute narration" : "Enable narration")
            }
            .foregroundStyle(SPRetro.ink)
        }
    }

    private func speedLabel(_ s: Double) -> String {
        s == 1 ? "1×" : "\(s)×"
    }

    private func speedIcon(_ s: Double) -> String {
        switch s {
        case ..<1.0:  return "tortoise.fill"
        case 1.0:     return "hare.fill"
        case 1.5:     return "hare.fill"
        default:      return "bolt.fill"
        }
    }

    private func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    // ─── Analysis list ───────────────────────────────────────────────────────

    private var analysisList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: SPSpacing.sm) {
                    if vm.visibleAnalyses.isEmpty {
                        Text("Press play or scrub to see commentary.")
                            .font(.custom("AmericanTypewriter", size: 13))
                            .foregroundStyle(SPRetro.inkMuted)
                            .padding(.top, SPSpacing.xl)
                    } else {
                        ForEach(vm.visibleAnalyses) { a in
                            AnalysisCardView(analysis: a)
                                .id(a.id)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                }
                .padding(.horizontal, SPSpacing.md)
                .padding(.vertical, SPSpacing.md)
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: vm.visibleAnalyses.map(\.id))
            }
            .onChange(of: vm.visibleAnalyses.first?.id) { _, newId in
                if let newId {
                    withAnimation { proxy.scrollTo(newId, anchor: .top) }
                }
            }
        }
    }
}

// ─── Analysis Card ────────────────────────────────────────────────────────────

struct AnalysisCardView: View {
    let analysis: FrameAnalysis

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // ── Left-edge accent bar in the verdict color (Slack/Linear
            //    style). The single most important visual signal in the
            //    review feature — promoted from a thin border to a 4pt
            //    full-height bar so the verdict reads at a glance.
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(analysis.verdict.color)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: analysis.verdict.icon)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(analysis.verdict.color)
                    Text(analysis.verdict.label.uppercased())
                        .font(.custom("AmericanTypewriter-Bold", size: 10))
                        .foregroundStyle(SPRetro.ink)
                        .tracking(0.8)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(
                            ZStack {
                                Capsule().fill(analysis.verdict.color)
                                Capsule().strokeBorder(SPRetro.ink, lineWidth: 1)
                            }
                        )
                    Text(analysis.title)
                        .font(.custom("AmericanTypewriter-Bold", size: 13))
                        .foregroundStyle(SPRetro.ink)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }

                if let your = analysis.yourMove {
                    CommentaryRow(
                        icon:   "person.fill",
                        label:  "What you did",
                        text:   your,
                        accent: analysis.verdict.color
                    )
                }
                if let rec = analysis.recommendation {
                    CommentaryRow(
                        icon:   "lightbulb.fill",
                        label:  "Try this",
                        text:   rec,
                        accent: SPRetro.mustardDark
                    )
                }
                if let read = analysis.opponentRead {
                    CommentaryRow(
                        icon:   analysis.isHeroDecision ? "questionmark.circle.fill"
                                                       : "eye.fill",
                        label:  analysis.isHeroDecision ? "Why" : "Their story",
                        text:   read,
                        accent: SPRetro.popBlue
                    )
                }
            }
            .padding(.vertical, SPSpacing.sm)
            .padding(.horizontal, SPSpacing.sm + 2)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Retro analysis card: paperShade card with ink border + hard ink
        // offset shadow. The 4pt verdict accent bar lives at the leading
        // edge (already in the HStack above) and remains the single most
        // important visual signal in the card.
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: SPRadius.md)
                    .fill(SPRetro.ink)
                    .offset(x: 1.5, y: 2.5)
                RoundedRectangle(cornerRadius: SPRadius.md)
                    .fill(SPRetro.paperShade)
                RoundedRectangle(cornerRadius: SPRadius.md)
                    .strokeBorder(SPRetro.ink, lineWidth: 1.2)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: SPRadius.md))
    }
}

private struct CommentaryRow: View {
    let icon:   String
    let label:  String
    let text:   String
    let accent: Color

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Icon column — gives each row a stable, scannable left rail.
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(accent)
                .frame(width: 14, alignment: .center)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(label.uppercased())
                    .font(.custom("AmericanTypewriter-Bold", size: 9))
                    .foregroundStyle(accent)
                    .tracking(1.0)
                Text(text)
                    .font(.custom("AmericanTypewriter", size: 13))
                    .foregroundStyle(SPRetro.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// ─── Street Timeline Rail ────────────────────────────────────────────────────
// Custom scrubber that replaces the bare system slider. Renders the hand as a
// horizontal strip of color-coded street zones (PRE / FLOP / TURN / RIVER /
// SHOW), each zone's width proportional to how many frames live in that
// street. A playhead line marks current position. Drag/tap anywhere on the
// rail seeks. The street labels give the user a sense of *where* they are in
// the hand — not just a percentage.

private struct StreetTimelineRail: View {
    let frames:     [ReplayFrame]
    let frameIndex: Int
    let progress:   Double
    let onSeek:     (Int) -> Void

    private struct Zone: Identifiable {
        let id = UUID()
        let label: String
        let color: Color
        let count: Int
    }

    // Retro zone palette: muted pop-blue / muted teal / mustard / maroon-ish
    // / pop-red — all keyed to the retro accents already in use across the
    // app so the rail reads like printed colored tabs on an index card.
    private var zones: [Zone] {
        let order: [(Street, String, Color)] = [
            (.preflop,  "PRE",   SPRetro.popBlue),
            (.flop,     "FLOP",  SPRetro.teal),
            (.turn,     "TURN",  SPRetro.mustard),
            (.river,    "RIVER", SPRetro.maroon),
            (.showdown, "SHOW",  SPRetro.popRed),
        ]
        return order.compactMap { (street, label, color) -> Zone? in
            let count = frames.filter { $0.streetEnum == street }.count
            return count > 0
                ? Zone(label: label, color: color, count: count)
                : nil
        }
    }

    var body: some View {
        GeometryReader { geo in
            let totalW = geo.size.width
            let total  = max(1, frames.count)
            // Pre-compute (zone, leading-x, width) so we can position each
            // strip absolutely. HStack would also work but absolute layout
            // keeps the playhead pixel-aligned with zone boundaries.
            let bounds: [(z: Zone, x: CGFloat, w: CGFloat)] = {
                var acc: CGFloat = 0
                return zones.map { z in
                    let w = (CGFloat(z.count) / CGFloat(total)) * totalW
                    let r = (z: z, x: acc, w: w)
                    acc += w
                    return r
                }
            }()
            let playheadX = totalW * CGFloat(max(0, min(1, progress)))

            // Retro rail: paperShade base, flat zone tints (no gradient
            // overlay), ink playhead line, ink panel border. No glow.
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(SPRetro.paperShade)

                ForEach(bounds.indices, id: \.self) { i in
                    let item = bounds[i]
                    ZStack {
                        Rectangle()
                            .fill(item.z.color)
                        if item.w > 28 {
                            Text(item.z.label)
                                .font(.custom("AmericanTypewriter-Bold", size: 9))
                                .foregroundStyle(SPRetro.ink)
                                .tracking(0.8)
                        }
                    }
                    .frame(width: item.w, height: 32)
                    .offset(x: item.x)
                }

                // Playhead — solid ink line with no glow, sits flush on
                // top of the zone tints like a pen stroke.
                Rectangle()
                    .fill(SPRetro.ink)
                    .frame(width: 2.5, height: 32)
                    .offset(x: playheadX - 1.25)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(SPRetro.ink, lineWidth: 1.2)
            )
            .contentShape(Rectangle())
            .gesture(
                // minimumDistance: 0 lets a plain tap also seek.
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        let frac = max(0, min(1, v.location.x / max(1, totalW)))
                        let idx  = Int(round(frac * Double(max(0, frames.count - 1))))
                        if idx != frameIndex { onSeek(idx) }
                    }
            )
        }
    }
}

// ─── Hero hole-card chip ─────────────────────────────────────────────────────

private struct HeroCardView: View {
    let card: PFCard

    // Retro hero card chip: paper face + ChalkboardSE-Bold rank/suit + ink
    // hairline border. Flat (no soft shadow) — matches the table cards.
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(SPRetro.paper)
            VStack(spacing: -1) {
                Text(card.live.displayRank)
                    .font(.custom("ChalkboardSE-Bold", size: 14))
                Text(card.live.suitSymbol)
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundStyle(card.live.isRed ? SPColors.cardRed : SPColors.cardBlack)
        }
        .frame(width: 26, height: 36)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(SPRetro.ink, lineWidth: 1)
        )
    }
}
