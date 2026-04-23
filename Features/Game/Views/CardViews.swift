import SwiftUI

// ─── Playing Card ─────────────────────────────────────────────────────────────

struct PlayingCardView: View {
    let card:     PokerCard?   // nil = face-down
    var size:     CardSize = .medium
    var isFaceDown: Bool  = false
    var isHighlighted: Bool = false
    // When true, render with a bright per-suit background and white glyphs —
    // used for community cards in the target design. Hole cards stay false.
    var coloredBackground: Bool = false

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
        .shadow(color: .black.opacity(isHighlighted ? 0.5 : 0.25), radius: isHighlighted ? 8 : 3, y: 2)
        .scaleEffect(isHighlighted ? 1.08 : 1.0)
        .animation(.spring(response: 0.3), value: isHighlighted)
    }

    // ─── Suit colors (for coloredBackground mode) ─────────────────────────────

    private func suitFillColor(_ card: PokerCard) -> Color {
        switch card.suit {
        case "H", "D": return Color(hex: "#D63838")
        case "C":      return Color(hex: "#2D8B3E")
        case "S":      return Color(hex: "#1A1A1A")
        default:       return Color(hex: "#1A1A1A")
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
        ZStack {
            RoundedRectangle(cornerRadius: size.cornerRadius)
                .fill(Color.white)

            RoundedRectangle(cornerRadius: size.cornerRadius)
                .strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5)

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
        let fill = suitFillColor(card)
        return ZStack {
            RoundedRectangle(cornerRadius: size.cornerRadius)
                .fill(fill)

            // Thin white inner border
            RoundedRectangle(cornerRadius: max(2, size.cornerRadius - 1))
                .strokeBorder(Color.white.opacity(0.85), lineWidth: 1)
                .padding(2)

            // Rank (top-left)
            Text(card.displayRank)
                .font(.system(size: size.rankSize * 1.15, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .padding(.leading, 5)
                .padding(.top, 3)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            // Large centered suit glyph
            Text(card.suitSymbol)
                .font(.system(size: size.width * 0.62, weight: .bold))
                .foregroundStyle(.white)
                .offset(y: size.width * 0.12)
        }
    }

    // ─── Back ─────────────────────────────────────────────────────────────────

    private var cardBack: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size.cornerRadius)
                .fill(
                    LinearGradient(
                        colors: [SPColors.accentDark, SPColors.accent],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            RoundedRectangle(cornerRadius: size.cornerRadius)
                .strokeBorder(.white.opacity(0.15), lineWidth: 0.5)

            // Diamond pattern
            RoundedRectangle(cornerRadius: size.cornerRadius - 2)
                .strokeBorder(.white.opacity(0.1), lineWidth: 1)
                .padding(4)

            Image(systemName: "suit.spade.fill")
                .font(.system(size: size.width * 0.35))
                .foregroundStyle(.white.opacity(0.3))
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

    @State private var appeared  = false
    @State private var showFront = false
    @State private var flipScaleX: CGFloat = 1

    var body: some View {
        Group {
            if showFront {
                PlayingCardView(card: card, size: size)
            } else {
                PlayingCardView(card: nil, size: size, isFaceDown: true)
            }
        }
        .scaleEffect(x: flipScaleX, y: 1)
        .scaleEffect(appeared ? 1 : 0.4)
        .opacity(appeared ? 1 : 0)
        .onAppear { animateDeal() }
    }

    private func animateDeal() {
        // 1. Pop in from the deck position
        withAnimation(.spring(response: 0.32, dampingFraction: 0.72).delay(dealDelay)) {
            appeared = true
        }
        // 2. Squish down (first half of flip)
        let flipStart = dealDelay + flipDelay
        DispatchQueue.main.asyncAfter(deadline: .now() + flipStart) {
            withAnimation(.easeIn(duration: 0.14)) { flipScaleX = 0 }
        }
        // 3. Swap to face-up and expand (second half of flip)
        DispatchQueue.main.asyncAfter(deadline: .now() + flipStart + 0.14) {
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

    var body: some View {
        HStack(spacing: size == .large ? 4 : -(size == .hero ? 12 : 6)) {
            if isHidden || cards.isEmpty {
                ForEach(0..<max(cardCount, isHidden ? 2 : 0), id: \.self) { i in
                    PlayingCardView(card: nil, size: size, isFaceDown: true)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.5).combined(with: .opacity),
                            removal: .opacity
                        ))
                }
            } else if animate {
                ForEach(Array(cards.enumerated()), id: \.element.id) { idx, card in
                    FlippableCardView(
                        card:      card,
                        size:      size,
                        dealDelay: Double(idx) * 0.18,
                        flipDelay: 0.22
                    )
                }
            } else {
                ForEach(cards) { card in
                    PlayingCardView(card: card, size: size)
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
            // Placeholder slots — same custom width so the 5-slot row always fits
            ForEach(cards.count..<5, id: \.self) { _ in
                RoundedRectangle(cornerRadius: size.cornerRadius)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                    .frame(width: cardWidth, height: cardWidth * 1.4)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: cards.count)
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

    private func animateIn() {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.78).delay(delay)) {
            appeared = true
        }
        // Flip starts once the card has nearly arrived at its slot.
        let flipStart = delay + 0.32
        DispatchQueue.main.asyncAfter(deadline: .now() + flipStart) {
            withAnimation(.easeIn(duration: 0.13)) { flipScaleX = 0 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + flipStart + 0.13) {
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
        HStack(spacing: 3) {
            // Stack of chip circles
            ZStack {
                ForEach(0..<min(chipCount, 4), id: \.self) { i in
                    Circle()
                        .fill(chipColor(i))
                        .frame(width: compact ? 10 : 14, height: compact ? 10 : 14)
                        .offset(y: CGFloat(-i * (compact ? 2 : 3)))
                        .shadow(color: .black.opacity(0.3), radius: 1)
                }
            }
            .frame(width: compact ? 14 : 18, height: compact ? 18 : 24)

            Text(formatChips(String(amount)))
                .font(compact ? SPFonts.caption(11) : SPFonts.chips(13))
                .foregroundStyle(SPColors.chipGold)
        }
        .padding(.horizontal, compact ? 5 : 7)
        .padding(.vertical, compact ? 2 : 3)
        .background(Color.black.opacity(0.45))
        .clipShape(Capsule())
    }

    private var chipCount: Int {
        if amount >= 10_000 { return 5 }
        if amount >= 1_000  { return 4 }
        if amount >= 500    { return 3 }
        if amount >= 100    { return 2 }
        return 1
    }

    private func chipColor(_ index: Int) -> Color {
        switch index % 4 {
        case 0: return SPColors.chipGold
        case 1: return Color(hex: "#E84393")
        case 2: return Color(hex: "#6C5CE7")
        default: return Color(hex: "#00B894")
        }
    }
}
