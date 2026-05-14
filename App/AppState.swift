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

    // Two parallel events gate the splash dismissal: video playback ends
    // and `checkSession()` completes. We track them as separate flags so
    // either can fire first without racing — the splash dismisses when
    // both are true. Using a hardcoded duration would be fragile if the
    // video asset changes; this approach scales with whatever the asset
    // happens to be.
    @State private var sessionChecked = false
    @State private var videoFinished  = false
    // Hard ceiling so the splash can't get stuck if the video fails to
    // play (e.g. asset corruption, AVFoundation reporting no end-time).
    // Slightly longer than the asset's ~5s duration.
    private let splashMaxDuration: TimeInterval = 7.0

    var body: some View {
        ZStack {
            SPColors.background.ignoresSafeArea()

            Group {
                switch appState.route {
                case .splash:
                    SplashView(onFinished: {
                        videoFinished = true
                        advanceIfReady()
                    })
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

            // Daily-bonus reveal overlay — sits above MainTabView so the
            // celebration covers the entire screen (tab bar included), but
            // below the toast so a critical toast can still cut through.
            // Renders nothing while idle, so cost is zero outside of a claim.
            DailyBonusRevealOverlay()
                .zIndex(800)
        }
        .onAppear {
            Task {
                await authViewModel.checkSession()
                sessionChecked = true
                advanceIfReady()
            }
            // Hard ceiling — if the video never reports end-of-play (asset
            // missing, decode failure), force-advance after this timeout
            // so the splash can't strand the user on a black screen.
            Task {
                try? await Task.sleep(nanoseconds: UInt64(splashMaxDuration * 1_000_000_000))
                videoFinished = true
                advanceIfReady()
            }
        }
        .onChange(of: authViewModel.isAuthenticated) { _, authenticated in
            // Auth state changes that happen post-splash (logout from
            // inside MainTabView, post-login transitions from AuthFlow)
            // route immediately. During the splash we skip this branch
            // entirely — `checkSession()` flips isAuthenticated false→true
            // mid-video on a cached login, and we don't want that to cut
            // the intro short. `advanceIfReady` handles the splash→main
            // transition once both the video and the session check
            // complete.
            guard appState.route != .splash else { return }
            withAnimation(.easeInOut(duration: 0.4)) {
                appState.route = authenticated ? .main : .auth
            }
        }
    }

    private func advanceIfReady() {
        guard appState.route == .splash, sessionChecked, videoFinished else { return }
        withAnimation(.easeInOut(duration: 0.4)) {
            appState.route = authViewModel.isAuthenticated ? .main : .auth
        }
    }
}
