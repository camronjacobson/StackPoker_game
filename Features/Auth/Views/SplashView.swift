import SwiftUI

struct SplashView: View {
    @State private var logoScale: CGFloat = 0.6
    @State private var logoOpacity: Double = 0
    @State private var taglineOpacity: Double = 0
    @State private var chipRotation: Double = -15

    var body: some View {
        ZStack {
            SPColors.background.ignoresSafeArea()

            // Ambient background glow
            Circle()
                .fill(SPColors.accent.opacity(0.08))
                .frame(width: 400, height: 400)
                .blur(radius: 80)
                .offset(y: -60)

            VStack(spacing: SPSpacing.lg) {
                Spacer()

                // Logo mark
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [SPColors.accent, SPColors.accentDark],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 100, height: 100)
                        .shadow(color: SPColors.accent.opacity(0.4), radius: 24, y: 8)

                    // Spade symbol
                    Image(systemName: "suit.spade.fill")
                        .font(.system(size: 46, weight: .bold))
                        .foregroundStyle(.white)
                        .rotationEffect(.degrees(chipRotation))
                }
                .scaleEffect(logoScale)
                .opacity(logoOpacity)

                VStack(spacing: SPSpacing.xs) {
                    Text("StackPoker")
                        .font(SPFonts.title(34))
                        .foregroundStyle(SPColors.textPrimary)

                    Text("Play with friends")
                        .font(SPFonts.body(15))
                        .foregroundStyle(SPColors.textSecondary)
                }
                .opacity(taglineOpacity)

                Spacer()

                // Legal disclaimer — required for App Store
                VStack(spacing: 4) {
                    Text("Virtual chips only — no real money or gambling")
                        .font(SPFonts.caption(11))
                        .foregroundStyle(SPColors.textTertiary)
                    Text("Social game for entertainment purposes")
                        .font(SPFonts.caption(11))
                        .foregroundStyle(SPColors.textTertiary)
                }
                .multilineTextAlignment(.center)
                .padding(.bottom, SPSpacing.xl)
                .opacity(taglineOpacity)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.6).delay(0.1)) {
                logoScale = 1
                logoOpacity = 1
            }
            withAnimation(.spring(response: 0.5).delay(0.3)) {
                chipRotation = 0
            }
            withAnimation(.easeOut(duration: 0.5).delay(0.5)) {
                taglineOpacity = 1
            }
        }
    }
}
