import SwiftUI
import AuthenticationServices

// ─── Auth Flow Container ──────────────────────────────────────────────────────

struct AuthFlowView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @State private var selectedTab = 0

    var body: some View {
        ZStack {
            SPColors.background.ignoresSafeArea()

            // Background decoration
            GeometryReader { geo in
                ZStack {
                    Circle()
                        .fill(SPColors.accent.opacity(0.06))
                        .frame(width: 500, height: 500)
                        .blur(radius: 100)
                        .offset(x: -100, y: -200)
                    Circle()
                        .fill(Color(hex: "#00B894").opacity(0.04))
                        .frame(width: 400, height: 400)
                        .blur(radius: 100)
                        .offset(x: geo.size.width - 100, y: geo.size.height - 100)
                }
            }
            .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // Logo
                    VStack(spacing: SPSpacing.sm) {
                        ZStack {
                            Circle()
                                .fill(SPColors.accent.opacity(0.15))
                                .frame(width: 72, height: 72)
                            Image(systemName: "suit.spade.fill")
                                .font(.system(size: 32, weight: .bold))
                                .foregroundStyle(SPColors.accent)
                        }

                        Text("StackPoker")
                            .font(SPFonts.title(28))
                            .foregroundStyle(SPColors.textPrimary)

                        Text("Virtual chips only · Social game")
                            .font(SPFonts.caption(12))
                            .foregroundStyle(SPColors.textTertiary)
                    }
                    .padding(.top, SPSpacing.xxl)
                    .padding(.bottom, SPSpacing.xl)

                    // Tab switcher
                    AuthTabPicker(selected: $selectedTab)
                        .padding(.horizontal, SPSpacing.md)
                        .padding(.bottom, SPSpacing.lg)

                    // Tab content
                    if selectedTab == 0 {
                        LoginView()
                            .transition(.asymmetric(
                                insertion: .move(edge: .leading).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)
                            ))
                    } else {
                        RegisterView()
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .trailing).combined(with: .opacity)
                            ))
                    }
                }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: selectedTab)
        .sheet(item: $authVM.activeSheet) { sheet in
            switch sheet {
            case .avatarPicker:
                AvatarPickerSheet()
                    .environmentObject(authVM)
            }
        }
    }
}

// ─── Tab Picker ───────────────────────────────────────────────────────────────

struct AuthTabPicker: View {
    @Binding var selected: Int

    var body: some View {
        HStack(spacing: 0) {
            ForEach(["Sign In", "Create Account"].indices, id: \.self) { i in
                Button {
                    withAnimation(.spring(response: 0.3)) { selected = i }
                } label: {
                    Text(["Sign In", "Create Account"][i])
                        .font(SPFonts.headline(15))
                        .foregroundStyle(selected == i ? SPColors.textPrimary : SPColors.textTertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, SPSpacing.sm + 2)
                }
            }
        }
        .background(
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: SPRadius.sm)
                    .fill(SPColors.accent)
                    .frame(width: geo.size.width / 2)
                    .offset(x: selected == 0 ? 0 : geo.size.width / 2)
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selected)
            },
            alignment: .leading
        )
        .background(SPColors.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: SPRadius.sm + 2))
    }
}
