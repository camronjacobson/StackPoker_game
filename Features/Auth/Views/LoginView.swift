import SwiftUI
import AuthenticationServices

struct LoginView: View {
    @EnvironmentObject var authVM: AuthViewModel

    var body: some View {
        VStack(spacing: SPSpacing.md) {
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
                    placeholder: "Password",
                    text: $authVM.password,
                    icon: "lock",
                    isSecure: true
                )
            }
            .padding(.horizontal, SPSpacing.md)

            // Error
            if let error = authVM.errorMessage {
                ErrorBanner(message: error)
                    .padding(.horizontal, SPSpacing.md)
                    .animation(.spring(response: 0.3), value: error)
            }

            VStack(spacing: SPSpacing.sm) {
                SPButton(
                    "Sign In",
                    isLoading: authVM.isLoading,
                    isDisabled: authVM.email.isEmpty || authVM.password.isEmpty
                ) {
                    Task { await authVM.login() }
                }

                // Divider with "or"
                HStack {
                    Rectangle().fill(SPColors.border).frame(height: 0.5)
                    Text("or")
                        .font(SPFonts.caption(12))
                        .foregroundStyle(SPColors.textTertiary)
                        .padding(.horizontal, SPSpacing.sm)
                    Rectangle().fill(SPColors.border).frame(height: 0.5)
                }

                // Apple Sign In
                AppleSignInButton()
            }
            .padding(.horizontal, SPSpacing.md)
            .padding(.bottom, SPSpacing.xl)
        }
        .onSubmit {
            Task { await authVM.login() }
        }
    }
}

// ─── Apple Sign In Button ─────────────────────────────────────────────────────

struct AppleSignInButton: View {
    @EnvironmentObject var authVM: AuthViewModel

    var body: some View {
        SignInWithAppleButton(.signIn) { request in
            request.requestedScopes = [.fullName, .email]
        } onCompletion: { result in
            Task { await authVM.handleAppleSignIn(result: result) }
        }
        .signInWithAppleButtonStyle(.white)
        .frame(height: 52)
        .clipShape(RoundedRectangle(cornerRadius: SPRadius.md))
    }
}
