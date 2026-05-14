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

                // "or" divider — ink hairlines with an AmericanTypewriter
                // ink-soft label. Reads as the kind of printed
                // typographic break used in retro forms rather than a
                // faint Material divider.
                HStack {
                    Rectangle()
                        .fill(SPRetro.ink.opacity(0.4))
                        .frame(height: 1)
                    Text("or")
                        .font(.custom("AmericanTypewriter", size: 12))
                        .tracking(1.5)
                        .foregroundStyle(SPRetro.inkMuted)
                        .padding(.horizontal, SPSpacing.sm)
                    Rectangle()
                        .fill(SPRetro.ink.opacity(0.4))
                        .frame(height: 1)
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
        // .black Apple style sits in the retro ink-on-paper palette much
        // better than the .white default, which previously read as a
        // chrome control floating on the cream substrate. Wrapped in an
        // ink-bordered rounded rect with a hard offset shadow so it
        // matches the SPButton vocabulary directly above it.
        .signInWithAppleButtonStyle(.black)
        .frame(height: 52)
        .clipShape(RoundedRectangle(cornerRadius: SPRadius.md))
        .overlay(
            RoundedRectangle(cornerRadius: SPRadius.md)
                .strokeBorder(SPRetro.ink, lineWidth: 2)
        )
        .background(
            RoundedRectangle(cornerRadius: SPRadius.md)
                .fill(SPRetro.ink)
                .offset(x: 2, y: 3)
        )
    }
}
