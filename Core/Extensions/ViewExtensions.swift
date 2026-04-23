import SwiftUI

// ─── View Modifiers ───────────────────────────────────────────────────────────

extension View {
    // Hide keyboard on tap
    func hideKeyboardOnTap() -> some View {
        self.onTapGesture {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
    }

    // Conditional modifier
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition { transform(self) }
        else { self }
    }

    // Glow effect (used for accent highlights)
    func glowEffect(color: Color = SPColors.accent, radius: CGFloat = 8) -> some View {
        self.shadow(color: color.opacity(0.4), radius: radius)
    }

    // Card-style background
    func cardBackground(radius: CGFloat = SPRadius.lg) -> some View {
        self
            .background(SPColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: radius))
            .overlay(
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(SPColors.border, lineWidth: 0.5)
            )
    }

    // Shimmer loading effect
    func shimmer(active: Bool = true) -> some View {
        self.modifier(ShimmerModifier(active: active))
    }
}

// ─── Shimmer Modifier ─────────────────────────────────────────────────────────

struct ShimmerModifier: ViewModifier {
    let active: Bool
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        if active {
            content
                .redacted(reason: .placeholder)
                .overlay(
                    LinearGradient(
                        colors: [
                            .clear,
                            SPColors.surfaceHighlight.opacity(0.5),
                            .clear,
                        ],
                        startPoint: .init(x: phase - 0.3, y: 0.5),
                        endPoint: .init(x: phase + 0.3, y: 0.5)
                    )
                )
                .onAppear {
                    withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                        phase = 1.3
                    }
                }
        } else {
            content
        }
    }
}

// ─── Animated Number Counter ──────────────────────────────────────────────────

struct AnimatedCounter: View {
    let value: Int64
    var prefix: String = ""
    var font: Font = SPFonts.chips()
    var color: Color = SPColors.textPrimary

    @State private var displayValue: Int64 = 0

    var body: some View {
        Text("\(prefix)\(displayValue)")
            .font(font)
            .foregroundStyle(color)
            .onAppear {
                withAnimation(.easeOut(duration: 0.8)) {
                    displayValue = value
                }
            }
            .onChange(of: value) { _, newValue in
                withAnimation(.easeOut(duration: 0.5)) {
                    displayValue = newValue
                }
            }
            .contentTransition(.numericText())
    }
}

// ─── Navigation Bar Helpers ───────────────────────────────────────────────────

struct SPNavigationStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .toolbarBackground(SPColors.surface, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

extension View {
    func spNavigationStyle() -> some View {
        modifier(SPNavigationStyle())
    }

    // Card shimmer — holographic highlight sweep
    func cardShimmer(active: Bool = true) -> some View {
        self.modifier(CardShimmerModifier(active: active))
    }

    // Breathing glow — subtle pulsing outline
    func breathingGlow(color: Color, active: Bool) -> some View {
        self.modifier(BreathingGlowModifier(glowColor: color, active: active))
    }
}

// ─── Card Shimmer (holographic sweep on deal) ────────────────────────────────

struct CardShimmerModifier: ViewModifier {
    let active: Bool
    @State private var phase: CGFloat = -0.5

    func body(content: Content) -> some View {
        content
            .overlay(
                Group {
                    if active {
                        LinearGradient(
                            colors: [
                                .clear,
                                Color.white.opacity(0.25),
                                Color.white.opacity(0.05),
                                .clear,
                            ],
                            startPoint: .init(x: phase - 0.3, y: phase - 0.3),
                            endPoint: .init(x: phase + 0.3, y: phase + 0.3)
                        )
                        .mask(content)
                        .onAppear {
                            withAnimation(.easeInOut(duration: 0.8).delay(0.2)) {
                                phase = 1.5
                            }
                        }
                    }
                }
            )
    }
}

// ─── Breathing Glow ──────────────────────────────────────────────────────────

struct BreathingGlowModifier: ViewModifier {
    let glowColor: Color
    let active: Bool
    @State private var intensity: CGFloat = 0.3

    func body(content: Content) -> some View {
        content
            .shadow(
                color: active ? glowColor.opacity(intensity) : .clear,
                radius: active ? 12 : 0
            )
            .onAppear {
                guard active else { return }
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    intensity = 0.8
                }
            }
            .onChange(of: active) { _, isActive in
                if isActive {
                    withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                        intensity = 0.8
                    }
                } else {
                    intensity = 0.3
                }
            }
    }
}

// ─── Win Confetti Particles ──────────────────────────────────────────────────

struct WinParticlesView: View {
    let color: Color
    @State private var particles: [(id: Int, x: CGFloat, y: CGFloat, rotation: Double, scale: CGFloat)] = []
    @State private var animate = false

    var body: some View {
        ZStack {
            ForEach(particles, id: \.id) { p in
                Circle()
                    .fill(color.opacity(animate ? 0 : 0.8))
                    .frame(width: 4, height: 4)
                    .scaleEffect(animate ? p.scale * 0.3 : p.scale)
                    .offset(
                        x: animate ? p.x * 2 : 0,
                        y: animate ? p.y * 2 - 30 : 0
                    )
                    .rotationEffect(.degrees(animate ? p.rotation * 2 : 0))
            }
        }
        .onAppear {
            particles = (0..<12).map { i in
                let angle = Double(i) / 12.0 * .pi * 2
                return (
                    id: i,
                    x: CGFloat(cos(angle)) * CGFloat.random(in: 20...40),
                    y: CGFloat(sin(angle)) * CGFloat.random(in: 20...40),
                    rotation: Double.random(in: -180...180),
                    scale: CGFloat.random(in: 0.6...1.2)
                )
            }
            withAnimation(.easeOut(duration: 1.0)) {
                animate = true
            }
        }
    }
}
