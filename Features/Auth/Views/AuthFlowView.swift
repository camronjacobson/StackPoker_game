import SwiftUI
import AuthenticationServices

// ─── Auth Flow Container ──────────────────────────────────────────────────────

struct AuthFlowView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @State private var selectedTab = 0

    var body: some View {
        ZStack {
            // Aged-paper substrate — same base the lobby and tab bar use,
            // so the auth screen reads as part of the same printed page.
            AgedPaperBackground().ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // Logo — mustard burst-circle with ink border and a
                    // hard offset shadow. Same comic-panel vocabulary as
                    // the +15s button, the lobby's JOIN! CTA, and the
                    // dealer button on the table.
                    VStack(spacing: SPSpacing.sm) {
                        ZStack {
                            Circle()
                                .fill(SPRetro.ink)
                                .frame(width: 72, height: 72)
                                .offset(x: 2.5, y: 3.5)
                            Circle()
                                .fill(SPRetro.mustard)
                                .frame(width: 72, height: 72)
                            Circle()
                                .strokeBorder(SPRetro.ink, lineWidth: 2.5)
                                .frame(width: 72, height: 72)
                            Image(systemName: "suit.spade.fill")
                                .font(.system(size: 34, weight: .black))
                                .foregroundStyle(SPRetro.ink)
                        }

                        Text("StackPoker")
                            .font(.custom("AmericanTypewriter-Bold", size: 32))
                            .tracking(0.8)
                            .foregroundStyle(SPRetro.ink)

                        Text("Virtual chips only · Social game")
                            .font(.custom("AmericanTypewriter", size: 12))
                            .foregroundStyle(SPRetro.inkMuted)
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
        // Retro segmented control: paperShade strip with an ink border;
        // selected tab is a mustard pill sliding underneath. Selected
        // label flips to ink; unselected stays ink-soft. The mustard pill
        // is sized slightly smaller than half-width and inset by 3pt so
        // the ink border around the whole strip stays visible.
        HStack(spacing: 0) {
            ForEach(["Sign In", "Create Account"].indices, id: \.self) { i in
                Button {
                    withAnimation(.spring(response: 0.3)) { selected = i }
                } label: {
                    Text(["Sign In", "Create Account"][i])
                        .font(.custom("AmericanTypewriter-Bold", size: 15))
                        .tracking(0.6)
                        .foregroundStyle(selected == i
                                         ? SPRetro.ink
                                         : SPRetro.inkMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, SPSpacing.sm + 2)
                }
            }
        }
        .background(
            // Sliding mustard pill — ink border + tight ink offset shadow
            // so it reads as a sticker dragged across the page.
            GeometryReader { geo in
                ZStack {
                    RoundedRectangle(cornerRadius: SPRadius.sm)
                        .fill(SPRetro.ink)
                        .frame(width: geo.size.width / 2 - 6)
                        .offset(x: selected == 0 ? 4 : geo.size.width / 2 + 2,
                                y: 2)
                    RoundedRectangle(cornerRadius: SPRadius.sm)
                        .fill(SPRetro.mustard)
                        .frame(width: geo.size.width / 2 - 6)
                        .offset(x: selected == 0 ? 3 : geo.size.width / 2 + 3)
                    RoundedRectangle(cornerRadius: SPRadius.sm)
                        .strokeBorder(SPRetro.ink, lineWidth: 1.5)
                        .frame(width: geo.size.width / 2 - 6)
                        .offset(x: selected == 0 ? 3 : geo.size.width / 2 + 3)
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selected)
            },
            alignment: .leading
        )
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: SPRadius.sm + 2)
                    .fill(SPRetro.paperShade)
                RoundedRectangle(cornerRadius: SPRadius.sm + 2)
                    .strokeBorder(SPRetro.ink, lineWidth: 1.5)
            }
        )
    }
}
