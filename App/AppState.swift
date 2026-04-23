import SwiftUI
import Combine

// ─── App State ────────────────────────────────────────────────────────────────

@MainActor
final class AppState: ObservableObject {
    enum Route: Equatable {
        case splash
        case auth
        case usernameSetup(appleToken: String)
        case main
    }

    @Published var route: Route = .splash
    @Published var toastMessage: ToastMessage?

    func showToast(_ message: String, style: ToastMessage.Style = .info) {
        toastMessage = ToastMessage(text: message, style: style)
    }
}

struct ToastMessage: Identifiable {
    let id = UUID()
    let text: String
    let style: Style

    enum Style {
        case info, success, error, warning
    }
}

// ─── Root View ────────────────────────────────────────────────────────────────

struct RootView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var authViewModel: AuthViewModel

    var body: some View {
        ZStack {
            SPColors.background.ignoresSafeArea()

            Group {
                switch appState.route {
                case .splash:
                    SplashView()
                case .auth:
                    AuthFlowView()
                case .usernameSetup(let token):
                    UsernameSetupView(appleToken: token)
                case .main:
                    MainTabView()
                }
            }
            .transition(.opacity.animation(.easeInOut(duration: 0.35)))

            // Toast overlay
            if let toast = appState.toastMessage {
                ToastView(message: toast)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.spring(response: 0.4), value: appState.toastMessage?.id)
                    .zIndex(999)
            }
        }
        .onAppear {
            Task {
                await authViewModel.checkSession()
                withAnimation(.easeInOut(duration: 0.4)) {
                    appState.route = authViewModel.isAuthenticated ? .main : .auth
                }
            }
        }
        .onChange(of: authViewModel.isAuthenticated) { _, authenticated in
            withAnimation(.easeInOut(duration: 0.4)) {
                appState.route = authenticated ? .main : .auth
            }
        }
    }
}
