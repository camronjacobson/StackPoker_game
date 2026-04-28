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

                Divider().background(SPColors.border)

                analysisList
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Hand #\(vm.hand.handNumber)")
                    .font(SPFonts.headline())
                    .foregroundStyle(SPColors.textPrimary)
            }
        }
        .tint(SPColors.textPrimary)   // colors the system back chevron
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
                    .font(SPFonts.headline(15))
                    .foregroundStyle(SPColors.textPrimary)
                    .lineLimit(1)
                Text("vs \(vm.hand.opponents.joined(separator: ", "))")
                    .font(SPFonts.caption(11))
                    .foregroundStyle(SPColors.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(vm.hand.iWon ? "+\(formatChips(vm.hand.stackDelta))"
                                  : formatChips(vm.hand.stackDelta))
                    .font(SPFonts.chips(16))
                    .foregroundStyle(vm.hand.iWon ? SPColors.success : SPColors.danger)
                if let name = vm.hand.winningHandName {
                    Text(name)
                        .font(SPFonts.caption(10))
                        .foregroundStyle(SPColors.textSecondary)
                        .lineLimit(1)
                }
            }
        }
    }

    // ─── Controls ────────────────────────────────────────────────────────────

    private var controls: some View {
        VStack(spacing: SPSpacing.xs) {
            // Scrubber
            HStack(spacing: SPSpacing.sm) {
                Text("\(vm.frameIndex + 1)/\(vm.totalFrames)")
                    .font(SPFonts.caption(11))
                    .foregroundStyle(SPColors.textSecondary)
                    .monospacedDigit()
                    .frame(width: 50, alignment: .leading)

                Slider(
                    value: Binding(
                        get: { Double(vm.frameIndex) },
                        set: { vm.seek(to: Int($0.rounded())) }
                    ),
                    in: 0...Double(max(0, vm.totalFrames - 1)),
                    step: 1
                )
                .tint(SPColors.accent)
            }

            // Buttons
            HStack(spacing: SPSpacing.lg) {
                Button { vm.restart() } label: {
                    Image(systemName: "backward.end.fill")
                        .font(.system(size: 18))
                }

                Button { vm.stepBack() } label: {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 22))
                }
                .disabled(!vm.canStepBack)

                Button { vm.togglePlay() } label: {
                    ZStack {
                        Circle()
                            .fill(SPColors.accent)
                            .frame(width: 44, height: 44)
                        Image(systemName: vm.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 18, weight: .heavy))
                            .foregroundStyle(.white)
                    }
                }

                Button { vm.stepForward() } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 22))
                }
                .disabled(!vm.canStepForward)

                // Speed cycle
                Button {
                    let next: [Double] = [0.5, 1.0, 1.5, 2.0]
                    let idx = next.firstIndex(of: vm.playbackSpeed) ?? 1
                    vm.playbackSpeed = next[(idx + 1) % next.count]
                } label: {
                    Text("\(speedLabel(vm.playbackSpeed))")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .frame(width: 38, height: 28)
                        .background(Capsule().fill(SPColors.surfaceElevated))
                }

                // Narration toggle — speaks each new analysis card aloud in
                // a soft female voice so the review feels like real coaching.
                Button {
                    narrator.toggle()
                    // If turning on mid-replay, immediately read the latest
                    // visible card so the user gets feedback that it works.
                    if narrator.enabled, let newest = vm.visibleAnalyses.first {
                        narrator.speak(newest)
                    }
                } label: {
                    Image(systemName: narrator.enabled
                          ? "speaker.wave.2.fill"
                          : "speaker.slash.fill")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 32, height: 28)
                        .background(
                            Capsule()
                                .fill(narrator.enabled
                                      ? SPColors.accent.opacity(0.25)
                                      : SPColors.surfaceElevated)
                        )
                        .foregroundStyle(narrator.enabled
                                         ? SPColors.accent
                                         : SPColors.textPrimary)
                }
                .accessibilityLabel(narrator.enabled ? "Mute narration" : "Enable narration")
            }
            .foregroundStyle(SPColors.textPrimary)
        }
    }

    private func speedLabel(_ s: Double) -> String {
        s == 1 ? "1×" : "\(s)×"
    }

    // ─── Analysis list ───────────────────────────────────────────────────────

    private var analysisList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: SPSpacing.sm) {
                    if vm.visibleAnalyses.isEmpty {
                        Text("Press play or scrub to see commentary.")
                            .font(SPFonts.body(13))
                            .foregroundStyle(SPColors.textSecondary)
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
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: analysis.verdict.icon)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(analysis.verdict.color)
                Text(analysis.verdict.label.uppercased())
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .foregroundStyle(analysis.verdict.color)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(
                        Capsule().fill(analysis.verdict.color.opacity(0.15))
                    )
                Text(analysis.title)
                    .font(SPFonts.headline(13))
                    .foregroundStyle(SPColors.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }

            if let your = analysis.yourMove {
                CommentaryRow(label: "What you did", text: your, accent: analysis.verdict.color)
            }
            if let rec = analysis.recommendation {
                CommentaryRow(label: "Try this", text: rec, accent: SPColors.accentLight)
            }
            if let read = analysis.opponentRead {
                CommentaryRow(label: analysis.isHeroDecision ? "Why" : "Their story",
                              text: read, accent: SPColors.info)
            }
        }
        .padding(SPSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: SPRadius.md)
                .fill(SPColors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: SPRadius.md)
                        .strokeBorder(analysis.verdict.color.opacity(0.20), lineWidth: 1)
                )
        )
    }
}

private struct CommentaryRow: View {
    let label: String
    let text: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .foregroundStyle(accent)
                .tracking(0.5)
            Text(text)
                .font(SPFonts.body(13))
                .foregroundStyle(SPColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// ─── Hero hole-card chip ─────────────────────────────────────────────────────

private struct HeroCardView: View {
    let card: PFCard

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.white)
            VStack(spacing: -1) {
                Text(card.live.displayRank)
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                Text(card.live.suitSymbol)
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundStyle(card.live.isRed ? SPColors.cardRed : SPColors.cardBlack)
        }
        .frame(width: 26, height: 36)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.black.opacity(0.20), lineWidth: 0.5)
        )
    }
}
