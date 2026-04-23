import SwiftUI

// Shown when a new Apple Sign In user needs to choose a username + avatar

struct UsernameSetupView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var appState: AppState
    let appleToken: String

    @State private var step: SetupStep = .username
    private let columns = Array(repeating: GridItem(.flexible(), spacing: SPSpacing.sm), count: 4)

    enum SetupStep { case username, avatar }

    var body: some View {
        ZStack {
            SPColors.background.ignoresSafeArea()

            Circle()
                .fill(SPColors.accent.opacity(0.06))
                .frame(width: 400, height: 400)
                .blur(radius: 100)
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: SPSpacing.xl) {

                    // Header
                    VStack(spacing: SPSpacing.sm) {
                        ZStack {
                            Circle()
                                .fill(SPColors.accent.opacity(0.15))
                                .frame(width: 72, height: 72)
                            Image(systemName: "person.crop.circle.badge.plus")
                                .font(.system(size: 32))
                                .foregroundStyle(SPColors.accent)
                        }
                        .padding(.top, 60)

                        Text("One more step")
                            .font(SPFonts.title(26))
                            .foregroundStyle(SPColors.textPrimary)

                        Text("Set up your StackPoker identity")
                            .font(SPFonts.body())
                            .foregroundStyle(SPColors.textSecondary)
                    }

                    // Step indicator
                    StepIndicator(currentStep: step == .username ? 0 : 1, totalSteps: 2)
                        .padding(.horizontal, SPSpacing.xl)

                    // Content
                    if step == .username {
                        usernameStep
                    } else {
                        avatarStep
                    }
                }
                .padding(.bottom, SPSpacing.xxl)
            }
        }
    }

    @ViewBuilder
    private var usernameStep: some View {
        VStack(spacing: SPSpacing.lg) {
            VStack(spacing: SPSpacing.sm) {
                UsernameField(
                    username: $authVM.username,
                    isChecking: authVM.isCheckingUsername,
                    isAvailable: authVM.usernameAvailable
                )

                SPTextField(
                    placeholder: "Display name",
                    text: $authVM.displayName,
                    icon: "person"
                )

                Text("3–20 characters · letters, numbers, underscores")
                    .font(SPFonts.caption(11))
                    .foregroundStyle(SPColors.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }
            .padding(.horizontal, SPSpacing.md)

            if let error = authVM.errorMessage {
                ErrorBanner(message: error)
                    .padding(.horizontal, SPSpacing.md)
            }

            SPButton(
                "Continue",
                icon: "arrow.right",
                isDisabled: authVM.username.count < 3 || authVM.usernameAvailable != true
            ) {
                authVM.errorMessage = nil
                withAnimation(.spring(response: 0.4)) { step = .avatar }
            }
            .padding(.horizontal, SPSpacing.md)
        }
    }

    @ViewBuilder
    private var avatarStep: some View {
        VStack(spacing: SPSpacing.lg) {
            VStack(spacing: SPSpacing.sm) {
                AvatarView(avatarId: authVM.selectedAvatarId, size: 80, showBorder: true)
                    .animation(.spring(response: 0.3), value: authVM.selectedAvatarId)
                Text(AvatarOption.find(authVM.selectedAvatarId).label)
                    .font(SPFonts.headline())
                    .foregroundStyle(SPColors.textPrimary)
            }

            LazyVGrid(columns: columns, spacing: SPSpacing.sm) {
                ForEach(AvatarOption.all) { avatar in
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            authVM.selectedAvatarId = avatar.id
                        }
                    } label: {
                        AvatarView(
                            avatarId: avatar.id,
                            size: 64,
                            showBorder: authVM.selectedAvatarId == avatar.id
                        )
                        .scaleEffect(authVM.selectedAvatarId == avatar.id ? 1.1 : 1)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, SPSpacing.md)

            VStack(spacing: SPSpacing.sm) {
                if let error = authVM.errorMessage {
                    ErrorBanner(message: error)
                }

                SPButton(
                    "Let's Play",
                    icon: "suit.spade.fill",
                    isLoading: authVM.isLoading
                ) {
                    Task { await authVM.completeAppleSignIn(identityToken: appleToken) }
                }

                SPButton("Back", style: .ghost) {
                    withAnimation(.spring(response: 0.4)) { step = .username }
                }
            }
            .padding(.horizontal, SPSpacing.md)
        }
    }
}
