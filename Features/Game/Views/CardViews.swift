import SwiftUI

// MAP: CardViews — reusable card SwiftUI components (446 lines)
// - PlayingCardView (single card face) ..... L5
// - CardSize (small/medium/large) .......... L14
// - FlippableCardView (3D flip) ............ L200
// - HoleCardsView (own pair) ............... L246
// - CommunityCardsView (board row) ......... L293
// - AnimatedCommunityCard (street reveal) .. L346
// - ChipStackView .......................... L402

// ─── Playing Card ─────────────────────────────────────────────────────────────

struct PlayingCardView: View {
    let card:     PokerCard?   // nil = face-down
    var size:     CardSize = .medium
    var isFaceDown: Bool  = false
    var isHighlighted: Bool = false
    // When true, render with a bright per-suit background and white glyphs —
    // used for community cards in the target design. Hole cards stay false.
    var coloredBackground: Bool = false
    // Optional cosmetic id for the face-down back. nil (or unrecognised id) →
    // the engine's default maroon back. Recognised ids route through
    // CardBackRenderer so the same single source of truth controls both
    // hero hole cards and the opponent reveal cluster. Resolved per-render —
    // no caching layer, because the catalog itself is constant for a session.
    var cardBackId: CosmeticID? = nil

    enum CardSize: Equatable {
        case small, medium, large, hero
        case custom(CGFloat)   // explicit width, height auto-derived (×1.4)

        var width:  CGFloat {
            switch self {
            case .small:  return 28
            case .medium: return 42
            case .large:  return 56
            case .hero:   return 72
            case .custom(let w): return w
            }
        }
        var height: CGFloat { width * 1.4 }
        var rankSize: CGFloat {
            switch self {
            case .small:  return 11
            case .medium: return 16
            case .large:  return 20
            case .hero:   return 26
            case .custom(let w): return max(10, w * 0.36)
            }
        }
        var suitSize: CGFloat {
            switch self {
            case .small:  return 9
            case .medium: return 13
            case .large:  return 16
            case .hero:   return 20
            case .custom(let w): return max(8, w * 0.28)
            }
        }
        var cornerRadius: CGFloat {
            switch self {
            case .small:  return 3
            case .medium: return 5
            case .large:  return 7
            case .hero:   return 9
            case .custom(let w): return max(4, w * 0.12)
            }
        }
    }

    var body: some View {
        ZStack {
            if isFaceDown || card == nil {
                cardBack
            } else {
                cardFront(card!)
            }
        }
        .frame(width: size.width, height: size.height)
        // Ink offset shadow (not a soft black blur) so cards read as
        // stickers on the paper page. Tighter blur on highlight so the
        // winner card still "lifts" but stays in the comic vocabulary.
        .shadow(color: SPRetro.ink.opacity(isHighlighted ? 0.55 : 0.3),
                radius: isHighlighted ? 4 : 1.5,
                x: isHighlighted ? 0 : 1,
                y: isHighlighted ? 3 : 2)
        .scaleEffect(isHighlighted ? 1.08 : 1.0)
        .animation(.spring(response: 0.3), value: isHighlighted)
    }

    // ─── Card-illustration palette (appearance-invariant) ────────────────────
    //
    // Cards are illustrated objects: the suit fills below are hardcoded
    // (a red heart is red, a blue diamond is blue, etc.) and the
    // foreground elements painted ON those fills — outer ink border,
    // inset paper hairline, rank glyph, centered suit glyph — must be
    // hardcoded too, so the on-card contrast composition stays correct
    // regardless of the user's appearance preference.
    //
    // Using `SPRetro.ink` / `SPRetro.paper` here would have made these
    // foreground elements theme-flip while the suit fills did not — in
    // Night mode that produced dark-sepia rank text on a red heart fill
    // (illegible) and a cream outer border on the colored panel (wrong
    // against the hardcoded fill).
    //
    // Values are the Day-mode `SPRetroPalette.day` paper/ink hexes, so
    // Day-mode rendering is byte-identical to the prior `SPRetro.*`
    // call sites. Night mode now renders the cards identically to Day
    // — intentional: the rest of the table view follows the user's
    // appearance preference; only these illustrated card elements are
    // locked.
    //
    // Scope is intentionally limited to `coloredFront` / its sub-views
    // (`compactCornerIndicator`, `standardLargeFront`). `whiteFront`
    // and `defaultCardBack` continue to use `SPRetro.*` because their
    // fills also theme-flip — those compositions flip coherently as
    // a unit.
    private static let cardInk   = Color(hex: "#1A1410")
    private static let cardPaper = Color(hex: "#F4E4BC")

    // ─── Suit colors (for coloredBackground mode) ─────────────────────────────

    // True four-color deck: hearts red, diamonds blue, clubs green, spades
    // black. Splitting diamonds out to blue is the small change that makes
    // hand-strength reading instant — hearts and diamonds are no longer
    // both "the red one", which matters most when you're checking for a
    // flush at a glance and your hole cards live in a colored frame.
    private func suitFillColor(_ card: PokerCard) -> Color {
        switch card.suit {
        case "H": return Color(hex: "#D63838")  // hearts   — red
        case "D": return Color(hex: "#2E6FD6")  // diamonds — blue
        case "C": return Color(hex: "#2D8B3E")  // clubs    — green
        case "S": return Color(hex: "#1A1A1A")  // spades   — black
        default:  return Color(hex: "#1A1A1A")
        }
    }

    // ─── Front ────────────────────────────────────────────────────────────────

    @ViewBuilder
    private func cardFront(_ card: PokerCard) -> some View {
        if coloredBackground {
            coloredFront(card)
        } else {
            whiteFront(card)
        }
    }

    private func whiteFront(_ card: PokerCard) -> some View {
        // "White" front retained for legacy callers (tutorials, replay).
        // Now uses the retro paper face (#F4E4BC) with an ink border so it
        // looks like a printed card on the page rather than a pure-white
        // playing card that fights the cream backdrop.
        ZStack {
            RoundedRectangle(cornerRadius: size.cornerRadius)
                .fill(SPRetro.paper)

            RoundedRectangle(cornerRadius: size.cornerRadius)
                .strokeBorder(SPRetro.ink.opacity(0.35), lineWidth: 0.6)

            // Top-left rank + suit
            VStack(alignment: .leading, spacing: 0) {
                Text(card.displayRank)
                    .font(.system(size: size.rankSize, weight: .bold, design: .rounded))
                    .foregroundStyle(card.isRed ? SPColors.cardRed : SPColors.cardBlack)
                Text(card.suitSymbol)
                    .font(.system(size: size.suitSize))
                    .foregroundStyle(card.isRed ? SPColors.cardRed : SPColors.cardBlack)
            }
            .padding(.leading, 3)
            .padding(.top, 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            // Center suit
            Text(card.suitSymbol)
                .font(.system(size: size.width * 0.55))
                .foregroundStyle((card.isRed ? SPColors.cardRed : SPColors.cardBlack).opacity(0.15))

            // Bottom-right (rotated)
            VStack(alignment: .leading, spacing: 0) {
                Text(card.displayRank)
                    .font(.system(size: size.rankSize, weight: .bold, design: .rounded))
                    .foregroundStyle(card.isRed ? SPColors.cardRed : SPColors.cardBlack)
                Text(card.suitSymbol)
                    .font(.system(size: size.suitSize))
                    .foregroundStyle(card.isRed ? SPColors.cardRed : SPColors.cardBlack)
            }
            .rotationEffect(.degrees(180))
            .padding(.trailing, 3)
            .padding(.bottom, 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
    }

    private func coloredFront(_ card: PokerCard) -> some View {
        // Two layouts share the same ink-panel chassis. The compact path
        // (< 30pt — i.e. the 22pt opponent-reveal cluster) drops the big
        // centered suit entirely because at lift-scale it overwhelmed the
        // corner rank, hiding the number. Instead the compact card uses a
        // real-playing-card-style corner indicator (rank stacked on top of
        // a small suit glyph) which keeps the rank legible regardless of
        // fan rotation or neighbour overlap. The standard path (community
        // 36pt+, hero 56pt+) is preserved byte-for-byte — those bigger
        // cards have plenty of room and the bold centered suit is part of
        // the felt's design language.
        let isCompact = size.width < 30
        let fill = suitFillColor(card)
        return ZStack {
            RoundedRectangle(cornerRadius: size.cornerRadius)
                .fill(fill)

            // Ink panel border — same hairline weight as every other
            // comic panel on the page. Hardcoded (Self.cardInk) — see
            // the card-illustration palette block near suitFillColor.
            RoundedRectangle(cornerRadius: size.cornerRadius)
                .strokeBorder(Self.cardInk, lineWidth: 1.2)

            // Paper inner border for the printed-stamp inset feel.
            // Hardcoded (Self.cardPaper) for the same reason.
            RoundedRectangle(cornerRadius: max(2, size.cornerRadius - 1))
                .strokeBorder(Self.cardPaper.opacity(0.85), lineWidth: 1)
                .padding(2)

            if isCompact {
                compactCornerIndicator(card)
            } else {
                standardLargeFront(card)
            }
        }
    }

    // Real-playing-card corner indicator: big rank on top, small suit glyph
    // immediately below it. Used only on compact reveal-cluster cards so
    // the rank is *the* readable element even when the cluster is fanned,
    // rotated, and scaled.
    @ViewBuilder
    private func compactCornerIndicator(_ card: PokerCard) -> some View {
        // Rank is the headline — sized to dominate the card. Suit is small
        // and tucked directly under it like the corner of a real playing
        // card. lineSpacing(-2) tightens the stack so the suit sits flush
        // under the rank's baseline rather than floating a line-height
        // away — at this size SwiftUI's default leading would push the
        // suit half off the card.
        VStack(alignment: .leading, spacing: 0) {
            Text(card.displayRank)
                .font(.custom("ChalkboardSE-Bold", size: size.width * 0.55))
                .foregroundStyle(Self.cardPaper)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(card.suitSymbol)
                .font(.system(size: size.width * 0.34, weight: .bold))
                .foregroundStyle(Self.cardPaper)
                .offset(y: -size.width * 0.08)   // pull suit up under the rank
        }
        .padding(.leading, 4)
        .padding(.top, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // Original colored-front layout — preserved byte-identical to what
    // shipped before. Used by community cards (cardWidth 36+) and the
    // hero's own hole cards (.large = 56pt) where the prominent centered
    // suit reads as a stamped design element rather than crowding the
    // rank.
    @ViewBuilder
    private func standardLargeFront(_ card: PokerCard) -> some View {
        // Rank (top-left) — ChalkboardSE-Bold cream (Self.cardPaper).
        Text(card.displayRank)
            .font(.custom("ChalkboardSE-Bold", size: size.rankSize * 1.15))
            .foregroundStyle(Self.cardPaper)
            .padding(.leading, 5)
            .padding(.top, 3)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

        // Large centered suit glyph — cream for contrast on the
        // colored face. Hardcoded (Self.cardPaper).
        Text(card.suitSymbol)
            .font(.system(size: size.width * 0.62, weight: .bold))
            .foregroundStyle(Self.cardPaper)
            .offset(y: size.width * 0.12)
    }

    // ─── Back ─────────────────────────────────────────────────────────────────

    @ViewBuilder
    private var cardBack: some View {
        // Cosmetic-aware back. CardBackRenderer.supports gates the procedural
        // path — unknown / nil ids fall back to the engine's default retro
        // maroon back so a future server-only catalog addition simply renders
        // as default until iOS catches up. Same shadow / stroke chassis wraps
        // both branches via the outer .frame in `body`.
        if CardBackRenderer.supports(cardBackId) {
            CardBackRenderer.view(for: cardBackId,
                                  size: size.width,
                                  cornerRadius: size.cornerRadius)
        } else {
            defaultCardBack
        }
    }

    private var defaultCardBack: some View {
        // Retro card back: flat maroon fill (SPColors.cardBack) with an ink
        // panel border, a paper-tinted inset hairline for the "printed
        // border" feel, and a mustard spade pip at the center. Replaces the
        // accent gradient + white-opacity strokes that read as glossy.
        ZStack {
            RoundedRectangle(cornerRadius: size.cornerRadius)
                .fill(SPRetro.maroon)

            RoundedRectangle(cornerRadius: size.cornerRadius)
                .strokeBorder(SPRetro.ink, lineWidth: 1.2)

            // Paper-tone inset hairline — reads as a printed border on
            // a paper-stock playing card.
            RoundedRectangle(cornerRadius: size.cornerRadius - 2)
                .strokeBorder(SPRetro.paper.opacity(0.4), lineWidth: 1)
                .padding(4)

            Image(systemName: "suit.spade.fill")
                .font(.system(size: size.width * 0.35))
                .foregroundStyle(SPRetro.mustard)
        }
    }
}

// ─── Flippable Card ───────────────────────────────────────────────────────────
// Deals in with a scale animation, then flips from face-down to face-up.
// Uses the X-axis scale trick: squish to 0, swap content, expand back.

struct FlippableCardView: View {
    let card:      PokerCard
    let size:      PlayingCardView.CardSize
    let dealDelay: Double   // seconds before the card appears
    let flipDelay: Double   // seconds after appearing before the flip
    var colored:   Bool = true   // 4-color front (default matches HoleCardsView)
    // Forwarded to the face-down PlayingCardView during the pre-flip phase
    // so the deal animation matches the equipped back. nil → engine default.
    var cardBackId: CosmeticID? = nil

    @State private var appeared  = false
    @State private var showFront = false
    @State private var flipScaleX: CGFloat = 1

    var body: some View {
        Group {
            if showFront {
                PlayingCardView(card: card, size: size,
                                coloredBackground: colored)
            } else {
                PlayingCardView(card: nil, size: size, isFaceDown: true,
                                cardBackId: cardBackId)
            }
        }
        .scaleEffect(x: flipScaleX, y: 1)
        .scaleEffect(appeared ? 1 : 0.4)
        .opacity(appeared ? 1 : 0)
        .onAppear { animateDeal() }
    }

    private func animateDeal() {
        // Single Task drives the full pop-in → squish → swap → expand sequence.
        // Replaces the previous DispatchQueue.main.asyncAfter chain (three
        // separate scheduled closures) for the same reason it was replaced in
        // AnimatedCommunityCard: when several cards animate in together, the
        // pile-up of three queued closures per card lands on the main runloop
        // at the exact same instants and jostles the layout pass that fires
        // when the parent HoleCardsView mounts. The Task's awaits yield
        // between phases so each animation transaction commits cleanly before
        // the next one starts. Visible timing is identical (delays unchanged).
        Task { @MainActor in
            withAnimation(.spring(response: 0.32, dampingFraction: 0.72).delay(dealDelay)) {
                appeared = true
            }
            let flipStart = dealDelay + flipDelay
            try? await Task.sleep(nanoseconds: UInt64(flipStart * 1_000_000_000))
            withAnimation(.easeIn(duration: 0.14)) { flipScaleX = 0 }
            try? await Task.sleep(nanoseconds: 140_000_000)
            showFront = true
            withAnimation(.easeOut(duration: 0.14)) { flipScaleX = 1 }
        }
    }
}

// ─── Hole Card Pair ───────────────────────────────────────────────────────────

struct HoleCardsView: View {
    let cards:     [PokerCard]
    let cardCount: Int          // for opponents (may have 0 actual cards)
    var isHidden:  Bool = false
    var size:      PlayingCardView.CardSize = .medium
    var animate:   Bool = false  // use deal animation for local player
    // Defaults to true so hole cards inherit the same 4-color (red /
    // blue / green / black) palette as the community board. Callers
    // that want the legacy white front (e.g. tutorials) can opt out.
    var colored:   Bool = true
    // Cosmetic card back id forwarded down to PlayingCardView /
    // FlippableCardView. nil → engine default. The hero passes their own
    // equipped id; opponents pass the seat's broadcast id.
    var cardBackId: CosmeticID? = nil

    var body: some View {
        HStack(spacing: size == .large ? 4 : -(size == .hero ? 12 : 6)) {
            if isHidden || cards.isEmpty {
                ForEach(0..<max(cardCount, isHidden ? 2 : 0), id: \.self) { i in
                    PlayingCardView(card: nil, size: size, isFaceDown: true,
                                    cardBackId: cardBackId)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.5).combined(with: .opacity),
                            removal: .opacity
                        ))
                }
            } else if animate {
                ForEach(Array(cards.enumerated()), id: \.element.id) { idx, card in
                    FlippableCardView(
                        card:       card,
                        size:       size,
                        dealDelay:  Double(idx) * 0.18,
                        flipDelay:  0.22,
                        colored:    colored,
                        cardBackId: cardBackId
                    )
                }
            } else {
                ForEach(cards) { card in
                    PlayingCardView(card: card, size: size,
                                    coloredBackground: colored)
                        .transition(.asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal: .opacity
                        ))
                }
            }
        }
    }
}

// ─── Community Cards Row ──────────────────────────────────────────────────────

struct CommunityCardsView: View {
    let cards:       [PokerCard]
    var winnersCards: Set<String> = []
    var cardWidth:    CGFloat = 56           // overridable by the table layout
    var cardSpacing:  CGFloat = 6
    var colored:      Bool    = true         // bright per-suit backs (community default)
    // Server-provided "what would have come" cards. Non-empty only when the
    // hand ended before the river (fold-out) and phase==ENDED. Length always
    // equals (5 - cards.count). When non-empty, the empty stroke placeholders
    // are replaced with face-down PokerCards that flip face-up on tap. Tap on
    // any one reveals all of them together so the player gets the full
    // "what if?" view in one gesture.
    var revealableBoard: [PokerCard] = []

    // Whether the run-out reveal has been triggered for the current hand.
    // Reset when `revealableBoard` empties (next hand begins or live play).
    @State private var runOutRevealed: Bool = false

    // Per-street stagger: cards dealt together (flop=3) fan in at 0.10s intervals;
    // turn/river singletons still use index 0 so they zip in immediately.
    private func delay(for index: Int, total: Int) -> Double {
        Double(index) * 0.10
    }

    // Each card flies from a virtual "deck" position above the HStack's center
    // (the pot cluster). We express that origin as a per-card offset from its
    // final seat in the board row so SwiftUI can animate a single offset value.
    private func deckOffset(for index: Int) -> CGSize {
        // HStack lays children out centered; slot i (0-indexed, 5 total slots)
        // sits at x = (i - 2) * (cardWidth + cardSpacing) relative to HStack
        // center. Deck origin is (0, -deckRise) from that center, so the card
        // needs to travel by the inverse to end at its slot.
        let slotX = CGFloat(index - 2) * (cardWidth + cardSpacing)
        let deckRise: CGFloat = cardWidth * 1.8   // how far above the board the deck sits
        return CGSize(width: -slotX, height: -deckRise)
    }

    var body: some View {
        let size: PlayingCardView.CardSize = .custom(cardWidth)
        HStack(spacing: cardSpacing) {
            ForEach(Array(cards.enumerated()), id: \.element.id) { idx, card in
                AnimatedCommunityCard(
                    card:          card,
                    size:          size,
                    isHighlighted: winnersCards.contains(card.id),
                    delay:         delay(for: idx, total: cards.count),
                    colored:       colored,
                    deckOffset:    deckOffset(for: idx)
                )
            }
            // Placeholder slots. When the server has surfaced a run-out
            // (hand ended early), swap the dead stroke rectangles for
            // face-down cards the player can tap to flip — tapping any one
            // flips all of them so the table's "what could have been" view
            // arrives in a single gesture.
            if !revealableBoard.isEmpty &&
               revealableBoard.count == 5 - cards.count {
                ForEach(Array(revealableBoard.enumerated()), id: \.element.id) { idx, card in
                    RunOutPlaceholder(
                        card:         card,
                        size:         size,
                        colored:      colored,
                        staggerDelay: Double(idx) * 0.08,   // gentle ripple, left → right
                        isRevealed:   runOutRevealed,
                        onTap: {
                            // Trigger the reveal once. SwiftUI animates each
                            // RunOutPlaceholder's flip individually with its
                            // own staggerDelay; we just flip the bool.
                            runOutRevealed = true
                        }
                    )
                    .frame(width: cardWidth, height: cardWidth * 1.4)
                }
            } else {
                ForEach(cards.count..<5, id: \.self) { _ in
                    // Empty community slot — dashed-ink hairline so the
                    // unfilled flop/turn/river slots read as a printed
                    // outline on the page rather than a faint white frame.
                    RoundedRectangle(cornerRadius: size.cornerRadius)
                        .strokeBorder(SPRetro.ink.opacity(0.18),
                                      style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .frame(width: cardWidth, height: cardWidth * 1.4)
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: cards.count)
        // Reset the reveal so the next hand starts with face-down placeholders
        // again. The trigger is the run-out array becoming empty (server
        // clears it on startHand), which is also exactly when we want the
        // local @State to forget the previous hand.
        .onChange(of: revealableBoard.count) { _, count in
            if count == 0 { runOutRevealed = false }
        }
    }
}

// One run-out placeholder: face-down PokerCard that flips on tap (or when
// `isRevealed` is set externally — useful so a tap on any sibling can flip
// the whole row together). Uses the same X-axis-scale flip trick as
// FlippableCardView/AnimatedCommunityCard so it visually matches the
// neighbouring board cards.
private struct RunOutPlaceholder: View {
    let card:         PokerCard
    let size:         PlayingCardView.CardSize
    let colored:      Bool
    let staggerDelay: Double          // delay added to this card's flip
    let isRevealed:   Bool             // external trigger from the parent
    let onTap:        () -> Void

    @State private var showFront    = false
    @State private var flipScaleX:  CGFloat = 1
    @State private var hasAnimated  = false

    var body: some View {
        Group {
            if showFront {
                PlayingCardView(card: card, size: size,
                                coloredBackground: colored)
            } else {
                PlayingCardView(card: nil, size: size, isFaceDown: true)
            }
        }
        .scaleEffect(x: flipScaleX, y: 1)
        // Subtle hint that the card is interactive — slight pulse on the
        // face-down state. We don't want it to look like a regular community
        // card the user might mistake for a real result.
        .overlay(
            // Mustard hint outline on the still-face-down run-out placeholder
            // so it reads as a tappable "what could have been" card on the
            // paper page — distinct from the muted-ink empty-slot strokes
            // above. Drops once revealed so the card looks like a normal
            // board card afterward.
            isRevealed ? nil :
            RoundedRectangle(cornerRadius: size.cornerRadius)
                .strokeBorder(SPRetro.mustard.opacity(0.65), lineWidth: 1.2)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            // Forward the tap to the parent (which sets `isRevealed=true` for
            // every sibling). Guarded so a second tap on an already-revealed
            // card is a no-op rather than re-running the flip.
            if !isRevealed { onTap() }
        }
        .onChange(of: isRevealed) { _, revealed in
            if revealed && !hasAnimated {
                hasAnimated = true
                animateFlip()
            }
        }
        .onChange(of: card.id) { _, _ in
            // New hand reusing the slot — reset visual state.
            showFront    = false
            flipScaleX   = 1
            hasAnimated  = false
        }
    }

    private func animateFlip() {
        // Squish to 0 (face-down still showing), swap to face-up, expand to 1.
        // Mirrors FlippableCardView's two-stage flip; staggerDelay creates the
        // left-to-right ripple across the row when sibling taps flip us all.
        // Driven by a Task instead of nested DispatchQueue.main.asyncAfter so
        // the squish→swap handoff happens cleanly between SwiftUI animation
        // transactions rather than landing as a queued closure that races the
        // sibling cards' flips. Same delays — visible timing unchanged.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(staggerDelay * 1_000_000_000))
            withAnimation(.easeIn(duration: 0.13)) { flipScaleX = 0 }
            try? await Task.sleep(nanoseconds: 130_000_000)
            showFront = true
            withAnimation(.easeOut(duration: 0.13)) { flipScaleX = 1 }
        }
    }
}

// Community card: flies from the deck (above pot) to its slot on the board,
// settles, then flips face-up. The caller computes `deckOffset` so the card
// visually originates from a single shared deck position regardless of slot.
private struct AnimatedCommunityCard: View {
    let card:         PokerCard
    let size:         PlayingCardView.CardSize
    let isHighlighted: Bool
    let delay:        Double
    var colored:      Bool = false
    var deckOffset:   CGSize = .zero

    @State private var appeared  = false
    @State private var showFront = false
    @State private var flipScaleX: CGFloat = 1

    var body: some View {
        Group {
            if showFront {
                PlayingCardView(
                    card: card,
                    size: size,
                    isHighlighted: isHighlighted,
                    coloredBackground: colored
                )
            } else {
                PlayingCardView(card: nil, size: size, isFaceDown: true)
            }
        }
        // Flatten each face into a Metal-backed bitmap before applying the
        // flight + flip transforms. Without this, the card-back's gradient +
        // suit-glyph + stroke layers re-rasterize every frame as the spring
        // animates offset/scale/rotation simultaneously — that re-raster on
        // up to 5 cards at once is what produced the visible flop hitch.
        // With drawingGroup the only per-frame work is a GPU transform on a
        // cached texture, which is what we want.
        .drawingGroup()
        .scaleEffect(x: flipScaleX, y: 1)
        // Fly in from the deck offset, settle to (0,0). Rotate slightly on the
        // way so it reads as a tossed card rather than a translation.
        .offset(
            x: appeared ? 0 : deckOffset.width,
            y: appeared ? 0 : deckOffset.height
        )
        .rotationEffect(.degrees(appeared ? 0 : -12))
        .scaleEffect(appeared ? 1 : 0.88)
        .opacity(appeared ? 1 : 0)
        .onAppear { animateIn() }
    }

    // Single Task drives the whole sequence (slide → squish → swap → expand).
    // Replaces the previous nested DispatchQueue.main.asyncAfter chain, which
    // pushed three closures onto the main queue at the exact same moment the
    // engine was already laying out a new community-card slot — that pile-up
    // of layout + scheduled work was the second source of flop stutter. A
    // Task with awaits yields between phases so SwiftUI can finish each
    // animation transaction cleanly before the next one starts.
    private func animateIn() {
        Task { @MainActor in
            withAnimation(.spring(response: 0.42, dampingFraction: 0.78).delay(delay)) {
                appeared = true
            }
            // Wait until the card has nearly reached its slot, then flip.
            try? await Task.sleep(nanoseconds: UInt64((delay + 0.32) * 1_000_000_000))
            withAnimation(.easeIn(duration: 0.13)) { flipScaleX = 0 }
            try? await Task.sleep(nanoseconds: 130_000_000)
            showFront = true
            withAnimation(.easeOut(duration: 0.13)) { flipScaleX = 1 }
        }
    }
}

// ─── Chip Stack View ──────────────────────────────────────────────────────────

struct ChipStackView: View {
    let amount: Int
    var compact: Bool = false

    var body: some View {
        // Retro chip pill: paper-shade capsule with an ink border, a small
        // stack of pop-color chip discs (each circled in ink for the
        // comic-panel look), and a ChalkboardSE-Bold ink amount. Replaces
        // the dark translucent capsule that read as Material Design.
        HStack(spacing: 3) {
            ZStack {
                ForEach(0..<min(chipCount, 4), id: \.self) { i in
                    Circle()
                        .fill(chipColor(i))
                        .frame(width: compact ? 10 : 14, height: compact ? 10 : 14)
                        .overlay(
                            Circle().strokeBorder(SPRetro.ink,
                                                  lineWidth: 0.8)
                        )
                        .offset(y: CGFloat(-i * (compact ? 2 : 3)))
                }
            }
            .frame(width: compact ? 14 : 18, height: compact ? 18 : 24)

            Text(formatChips(String(amount)))
                .font(.custom("ChalkboardSE-Bold", size: compact ? 11 : 13))
                .foregroundStyle(SPRetro.ink)
        }
        .padding(.horizontal, compact ? 5 : 7)
        .padding(.vertical, compact ? 2 : 3)
        .background(
            ZStack {
                Capsule().fill(SPRetro.paperShade)
                Capsule().strokeBorder(SPRetro.ink, lineWidth: 1)
            }
        )
    }

    private var chipCount: Int {
        if amount >= 10_000 { return 5 }
        if amount >= 1_000  { return 4 }
        if amount >= 500    { return 3 }
        if amount >= 100    { return 2 }
        return 1
    }

    /// Retro chip palette — mustard, pop red, pop blue, muted teal. Pulled
    /// from the SPRetro family so chip discs match the rest of the page
    /// rather than the old neon Material set.
    private func chipColor(_ index: Int) -> Color {
        switch index % 4 {
        case 0: return SPRetro.mustard  // mustard
        case 1: return SPRetro.popRed  // pop red
        case 2: return SPRetro.popBlue  // pop blue
        default: return SPRetro.teal // muted teal
        }
    }
}
