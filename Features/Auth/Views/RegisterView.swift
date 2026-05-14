import SwiftUI
import AuthenticationServices

struct RegisterView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @State private var step: RegisterStep = .credentials

    enum RegisterStep: Int, CaseIterable {
        case credentials, identity, avatar

        var title: String {
            switch self {
            case .credentials: return "Create account"
            case .identity:    return "Choose your identity"
            case .avatar:      return "Pick your avatar"
            }
        }

        var subtitle: String {
            switch self {
            case .credentials: return "Enter your email and password"
            case .identity:    return "Your username and display name"
            case .avatar:      return "Represent yourself at the table"
            }
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
        VStack(spacing: SPSpacing.lg) {

            // Step progress dots
            StepIndicator(currentStep: step.rawValue, totalSteps: RegisterStep.allCases.count)
                .padding(.horizontal, SPSpacing.md)

            // Step header
            VStack(spacing: 4) {
                Text(step.title)
                    .font(SPFonts.headline(18))
                    .foregroundStyle(SPColors.textPrimary)
                Text(step.subtitle)
                    .font(SPFonts.body(14))
                    .foregroundStyle(SPColors.textSecondary)
            }
            .animation(.easeInOut, value: step)

            // Step content
            Group {
                switch step {
                case .credentials:
                    CredentialsStep()
                case .identity:
                    IdentityStep()
                case .avatar:
                    AvatarStep(onComplete: {
                        Task { await authVM.register() }
                    })
                }
            }
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: step)
        .alert("Error", isPresented: Binding(
            get: { authVM.errorMessage != nil },
            set: { if !$0 { authVM.errorMessage = nil } }
        )) {
            Button("OK") { authVM.errorMessage = nil }
        } message: {
            if let error = authVM.errorMessage {
                Text(error)
            }
        }

            // Navigation buttons
            //
            // Force-unwrapping `RegisterStep(rawValue:)` used to crash here
            // when a fast double-tap on Continue fired the closure twice
            // before SwiftUI tore down the button on the new step's
            // re-render: tap #1 advanced 1→2, tap #2 advanced 2→3 → nil →
            // assertion failure. Optional-binding the result clamps the
            // edges and turns the second tap into a harmless no-op while
            // SwiftUI catches up. Same defensive guard for Back even
            // though it's less likely to misfire.
            HStack(spacing: SPSpacing.sm) {
                if step.rawValue > 0 {
                    SPButton("Back", style: .secondary) {
                        withAnimation {
                            if let prev = RegisterStep(rawValue: step.rawValue - 1) {
                                step = prev
                            }
                        }
                    }
                    .frame(width: 90)
                }

                if step.rawValue < RegisterStep.allCases.count - 1 {
                    SPButton("Continue", icon: "arrow.right") {
                        authVM.errorMessage = nil
                        withAnimation {
                            if let next = RegisterStep(rawValue: step.rawValue + 1) {
                                step = next
                            }
                        }
                    }
                    .disabled(!canContinue)
                    .opacity(canContinue ? 1 : 0.5)
                }
            }
            .padding(.horizontal, SPSpacing.md)
            .padding(.bottom, SPSpacing.xl)

            // Apple Sign Up option on first step — retro typographic
            // divider (ink hairlines + AmericanTypewriter ink-soft label),
            // matching the LoginView pattern so both screens read as the
            // same printed form.
            if step == .credentials {
                VStack(spacing: SPSpacing.sm) {
                    HStack {
                        Rectangle()
                            .fill(SPRetro.ink.opacity(0.4))
                            .frame(height: 1)
                        Text("or sign up with Apple")
                            .font(.custom("AmericanTypewriter", size: 12))
                            .tracking(1.0)
                            .foregroundStyle(SPRetro.inkMuted)
                            .fixedSize()
                        Rectangle()
                            .fill(SPRetro.ink.opacity(0.4))
                            .frame(height: 1)
                    }
                    .padding(.horizontal, SPSpacing.md)

                    AppleSignInButton()
                        .padding(.horizontal, SPSpacing.md)
                }
            }
        }
        } // end ScrollView
    }

    private var canContinue: Bool {
        switch step {
        case .credentials:
            return !authVM.email.isEmpty && authVM.password.count >= 8 && authVM.password == authVM.confirmPass
        case .identity:
            let usernameFormatValid = authVM.username.count >= 3 && authVM.username.count <= 20
            let usernameOk = usernameFormatValid && authVM.usernameAvailable != false
            return usernameOk && authVM.displayName.count >= 2
        case .avatar:
            return true
        }
    }
}

// ─── Step 1: Credentials ──────────────────────────────────────────────────────

struct CredentialsStep: View {
    @EnvironmentObject var authVM: AuthViewModel

    var body: some View {
        VStack(spacing: SPSpacing.sm) {
            SPTextField(
                placeholder: "Email address",
                text: $authVM.email,
                icon: "envelope",
                keyboardType: .emailAddress,
                autocapitalization: .never,
                autocorrect: false
            )

            SPTextField(
                placeholder: "Password (min. 8 characters)",
                text: $authVM.password,
                icon: "lock",
                isSecure: true
            )

            SPTextField(
                placeholder: "Confirm password",
                text: $authVM.confirmPass,
                icon: "lock.fill",
                isSecure: true
            )

            // Password match indicator
            if !authVM.password.isEmpty && !authVM.confirmPass.isEmpty {
                HStack {
                    Image(systemName: authVM.password == authVM.confirmPass ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(authVM.password == authVM.confirmPass ? SPColors.success : SPColors.danger)
                        .font(.system(size: 13))
                    Text(authVM.password == authVM.confirmPass ? "Passwords match" : "Passwords don't match")
                        .font(SPFonts.caption(12))
                        .foregroundStyle(authVM.password == authVM.confirmPass ? SPColors.success : SPColors.danger)
                    Spacer()
                }
                .padding(.horizontal, 4)
                .transition(.opacity.combined(with: .scale))
            }
        }
        .padding(.horizontal, SPSpacing.md)
        .animation(.spring(response: 0.3), value: authVM.password == authVM.confirmPass)
    }
}

// ─── Step 2: Identity ─────────────────────────────────────────────────────────

struct IdentityStep: View {
    @EnvironmentObject var authVM: AuthViewModel

    var body: some View {
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

            // Username rules hint
            Text("3–20 characters · letters, numbers, and underscores")
                .font(SPFonts.caption(11))
                .foregroundStyle(SPColors.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
        }
        .padding(.horizontal, SPSpacing.md)
    }
}

// ─── Step 3: Avatar ───────────────────────────────────────────────────────────

struct AvatarStep: View {
    @EnvironmentObject var authVM: AuthViewModel
    let onComplete: () -> Void
    private let columns = Array(repeating: GridItem(.flexible(), spacing: SPSpacing.sm), count: 4)

    var body: some View {
        VStack(spacing: SPSpacing.lg) {
            // Selected preview
            VStack(spacing: SPSpacing.sm) {
                AvatarView(avatarId: authVM.selectedAvatarId, size: 80, showBorder: true)
                Text(AvatarOption.find(authVM.selectedAvatarId).label)
                    .font(SPFonts.headline())
                    .foregroundStyle(SPColors.textPrimary)
            }
            .animation(.spring(response: 0.3), value: authVM.selectedAvatarId)

            // Grid
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
                        .animation(.spring(response: 0.25), value: authVM.selectedAvatarId)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, SPSpacing.md)

            SPButton(
                "Create Account",
                icon: "checkmark",
                isLoading: authVM.isLoading,
                action: onComplete
            )
            .padding(.horizontal, SPSpacing.md)
        }
    }
}

// ─── Step Indicator ───────────────────────────────────────────────────────────

struct StepIndicator: View {
    let currentStep: Int
    let totalSteps: Int

    var body: some View {
        HStack(spacing: SPSpacing.xs) {
            ForEach(0..<totalSteps, id: \.self) { i in
                Capsule()
                    .fill(i <= currentStep ? SPColors.accent : SPColors.surfaceHighlight)
                    .frame(height: 3)
                    .animation(.spring(response: 0.4), value: currentStep)
            }
        }
    }
}
