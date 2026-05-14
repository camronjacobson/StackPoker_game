import SwiftUI
import AuthenticationServices
import Combine

@MainActor
final class AuthViewModel: ObservableObject {

    // ─── Published State ───────────────────────────────────────────────────────

    @Published var isAuthenticated = false
    @Published var currentUser: UserProfile?

    // Form fields
    @Published var email         = ""
    @Published var password      = ""
    @Published var confirmPass   = ""
    @Published var username      = ""
    @Published var displayName   = ""
    @Published var selectedAvatarId = "avatar_1"

    // UI state
    @Published var isLoading     = false
    @Published var errorMessage: String?
    @Published var activeSheet: AuthSheet?

    // Username check
    @Published var usernameAvailable: Bool?
    @Published var isCheckingUsername = false

    // Apple auth flow
    @Published var pendingAppleToken: String?
    @Published var needsAppleUsername = false

    enum AuthSheet: Identifiable {
        case avatarPicker
        var id: String { "avatarPicker" }
    }

    // ─── Dependencies ──────────────────────────────────────────────────────────

    private let network = NetworkService.shared
    private let keychain = KeychainManager.shared
    private var usernameCancellable: AnyCancellable?
    private var usernameCheckTask: Task<Void, Never>?

    init() {
        // Inject access token into network layer
        network.accessToken = keychain.accessToken
        // Set refresh callback
        network.onTokenExpired = { [weak self] in
            await self?.silentRefresh() ?? false
        }

        // Debounced username check
        usernameCancellable = $username
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] value in
                guard value.count >= 3 else {
                    self?.usernameAvailable = nil
                    return
                }
                self?.checkUsernameAvailability(value)
            }
    }

    // ─── Session Restore ───────────────────────────────────────────────────────

    func checkSession() async {
        guard keychain.hasValidSession else {
            isAuthenticated = false
            return
        }

        // Try silent token refresh first
        let refreshed = await silentRefresh()
        if !refreshed {
            isAuthenticated = false
            return
        }

        // Load profile
        do {
            let user: UserProfile = try await network.request(.me)
            currentUser = user
            // Scope hand history to this user before any UI binds to it,
            // otherwise the Review tab can briefly render the previous
            // session's data on a cold launch. See HandHistoryStore for
            // why this scoping exists.
            HandHistoryStore.shared.setActiveUser(user.id)
            isAuthenticated = true
        } catch {
            // Refresh succeeded but profile failed — clear session
            logout()
        }
    }

    // ─── Register ─────────────────────────────────────────────────────────────

    func register() async {
        guard validateRegistration() else { return }

        isLoading = true
        errorMessage = nil

        let req = RegisterRequest(
            email: email.lowercased().trimmingCharacters(in: .whitespaces),
            password: password,
            username: username.lowercased(),
            displayName: displayName.trimmingCharacters(in: .whitespaces),
            avatarId: selectedAvatarId
        )

        do {
            let response: AuthResponse = try await network.request(
                .register, method: .POST, body: req, requiresAuth: false
            )
            handleAuthSuccess(response)
        } catch let err as NetworkError {
            errorMessage = err.localizedDescription
        } catch {
            errorMessage = "Something went wrong. Please try again."
        }

        isLoading = false
    }

    // ─── Login ────────────────────────────────────────────────────────────────

    func login() async {
        guard !email.isEmpty, !password.isEmpty else {
            errorMessage = "Please enter your email and password"
            return
        }

        isLoading = true
        errorMessage = nil

        let req = LoginRequest(email: email.lowercased(), password: password)

        do {
            let response: AuthResponse = try await network.request(
                .login, method: .POST, body: req, requiresAuth: false
            )
            handleAuthSuccess(response)
        } catch let err as NetworkError {
            errorMessage = err.localizedDescription
        } catch {
            errorMessage = "Login failed. Please try again."
        }

        isLoading = false
    }

    // ─── Apple Sign In ────────────────────────────────────────────────────────

    func handleAppleSignIn(result: Result<ASAuthorization, Error>) async {
        switch result {
        case .failure(let err):
            if (err as? ASAuthorizationError)?.code != .canceled {
                errorMessage = "Apple Sign In failed. Please try again."
            }
            return

        case .success(let auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let identityToken = String(data: tokenData, encoding: .utf8),
                  let codeData = credential.authorizationCode,
                  let authCode = String(data: codeData, encoding: .utf8) else {
                errorMessage = "Invalid Apple credentials"
                return
            }

            isLoading = true
            errorMessage = nil

            let fullName = credential.fullName.map {
                AppleAuthRequest.AppleFullName(
                    givenName: $0.givenName,
                    familyName: $0.familyName
                )
            }

            let req = AppleAuthRequest(
                identityToken: identityToken,
                authorizationCode: authCode,
                fullName: fullName,
                username: nil,
                avatarId: nil
            )

            do {
                let response: AuthResponse = try await network.request(
                    .appleAuth, method: .POST, body: req, requiresAuth: false
                )

                if response.isNewUser == true || response.user.username.isEmpty {
                    // New Apple user — needs username/avatar selection
                    pendingAppleToken = identityToken
                    needsAppleUsername = true
                } else {
                    handleAuthSuccess(response)
                }
            } catch let err as NetworkError {
                switch err {
                case .serverError(let code, _) where code == "USERNAME_REQUIRED":
                    pendingAppleToken = identityToken
                    needsAppleUsername = true
                default:
                    errorMessage = err.localizedDescription
                }
            } catch {
                errorMessage = "Apple Sign In failed"
            }

            isLoading = false
        }
    }

    // ─── Complete Apple Sign In (after username selection) ────────────────────

    func completeAppleSignIn(identityToken: String) async {
        guard validateUsername(), !selectedAvatarId.isEmpty else { return }

        isLoading = true
        errorMessage = nil

        let req = AppleAuthRequest(
            identityToken: identityToken,
            authorizationCode: "",
            fullName: nil,
            username: username.lowercased(),
            avatarId: selectedAvatarId
        )

        do {
            let response: AuthResponse = try await network.request(
                .appleAuth, method: .POST, body: req, requiresAuth: false
            )
            needsAppleUsername = false
            pendingAppleToken = nil
            handleAuthSuccess(response)
        } catch let err as NetworkError {
            errorMessage = err.localizedDescription
        } catch {
            errorMessage = "Setup failed. Please try again."
        }

        isLoading = false
    }

    // ─── Update Profile (avatar / display name) ───────────────────────────────
    // Hits PATCH /auth/me. On success the server returns the full updated
    // profile which we write back to `currentUser` so the rest of the UI
    // (lobby header, profile screen) updates immediately.
    //
    // Returns `true` on success, `false` on failure. The caller can rely on
    // `errorMessage` being set in the failure case.

    @discardableResult
    func updateProfile(avatarId: String? = nil, displayName: String? = nil) async -> Bool {
        guard avatarId != nil || displayName != nil else { return false }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let req = UpdateProfileRequest(avatarId: avatarId, displayName: displayName)

        do {
            let user: UserProfile = try await network.request(
                .updateProfile, method: .PATCH, body: req
            )
            currentUser = user
            return true
        } catch let err as NetworkError {
            errorMessage = err.localizedDescription
            return false
        } catch {
            errorMessage = "Failed to update profile"
            return false
        }
    }

    // ─── Refresh Profile ──────────────────────────────────────────────────────
    // Pulls the latest UserProfile from /auth/me so UI bound to chipBalance,
    // avatar, etc. reflects server-side changes (e.g. after an admin grant).

    func refreshProfile() async {
        do {
            let user: UserProfile = try await network.request(.me)
            currentUser = user
        } catch {
            // Silent — caller can fall back to the stale copy.
        }
    }

    // ─── Daily Bonus ──────────────────────────────────────────────────────────
    // Calls POST /chips/daily to claim the once-per-24h chip bonus. The backend
    // is the source of truth — it checks today's chipTransaction history for a
    // DAILY_BONUS row and rejects the call with code "ALREADY_CLAIMED" if the
    // user has already redeemed today (the message includes hours-until-reset).
    //
    // On success we refresh the profile so chipBalance bound elsewhere in the
    // UI updates immediately; the caller still gets the bonus amount for any
    // success animation (e.g. "+1000" pop in DailyBonusCard).

    enum DailyBonusResult {
        case success(amount: Int)
        case alreadyClaimed(message: String)
        case failure(message: String)
    }

    func claimDailyBonus() async -> DailyBonusResult {
        do {
            let response: DailyBonusResponse = try await network.request(
                .dailyBonus, method: .POST
            )
            await refreshProfile()
            // bonusAmount is a BigInt-as-string from the backend; coerce here
            // so the caller (DailyBonusCard) can show "+\(amount)" plainly.
            return .success(amount: Int(response.bonusAmount) ?? 0)
        } catch let err as NetworkError {
            // The backend throws { code: "ALREADY_CLAIMED", message: "Come back
            // in Xh ..." } when today's bonus row already exists. Surface that
            // distinct case so the UI can switch into its cooldown state with
            // the server's countdown message instead of a generic error.
            if case .serverError(let code, let message) = err,
               code == "ALREADY_CLAIMED" {
                return .alreadyClaimed(message: message)
            }
            return .failure(message: err.localizedDescription)
        } catch {
            return .failure(message: "Couldn't claim bonus. Please try again.")
        }
    }

    // ─── Logout ───────────────────────────────────────────────────────────────

    func logout() {
        if let token = keychain.refreshToken {
            Task {
                try? await network.requestVoid(.logout, body: LogoutRequest(refreshToken: token), requiresAuth: false)
            }
        }

        keychain.clearAll()
        network.accessToken = nil
        currentUser = nil
        isAuthenticated = false
        // Detach hand history. The previous user's data stays on disk under
        // their userId path so it's still there if they sign back in; this
        // call just clears the in-memory copy so the Review tab is empty
        // until the next user signs in.
        HandHistoryStore.shared.setActiveUser(nil)
        clearForm()
    }

    // ─── Username Check ───────────────────────────────────────────────────────

    private func checkUsernameAvailability(_ username: String) {
        usernameCheckTask?.cancel()
        usernameCheckTask = Task {
            isCheckingUsername = true
            do {
                let response: UsernameCheckResponse = try await network.request(
                    .checkUsername(username), requiresAuth: false
                )
                if !Task.isCancelled {
                    usernameAvailable = response.available && response.valid
                }
            } catch {
                if !Task.isCancelled {
                    usernameAvailable = nil
                }
            }
            isCheckingUsername = false
        }
    }

    // ─── Private Helpers ──────────────────────────────────────────────────────

    private func handleAuthSuccess(_ response: AuthResponse) {
        keychain.saveTokens(access: response.tokens.accessToken, refresh: response.tokens.refreshToken)
        keychain.save(response.user.id, for: .userId)
        keychain.save(response.user.username, for: .username)
        network.accessToken = response.tokens.accessToken

        currentUser = response.user
        // Scope hand history to the freshly-signed-in user. Same reason as
        // checkSession — must run before isAuthenticated flips so any view
        // that observes that flag reads the correct summaries on first paint.
        HandHistoryStore.shared.setActiveUser(response.user.id)
        isAuthenticated = true
        clearForm()
    }

    @discardableResult
    func silentRefresh() async -> Bool {
        guard let refreshToken = keychain.refreshToken else { return false }

        do {
            let response: TokensResponse = try await network.request(
                .refresh,
                method: .POST,
                body: RefreshRequest(refreshToken: refreshToken),
                requiresAuth: false,
                retryOnExpiry: false
            )
            keychain.saveTokens(access: response.tokens.accessToken, refresh: response.tokens.refreshToken)
            network.accessToken = response.tokens.accessToken
            return true
        } catch {
            keychain.clearAll()
            return false
        }
    }

    private func validateRegistration() -> Bool {
        errorMessage = nil

        if email.isEmpty {
            errorMessage = "Email is required"; return false
        }
        if !email.contains("@") {
            errorMessage = "Enter a valid email"; return false
        }
        if password.count < 8 {
            errorMessage = "Password must be at least 8 characters"; return false
        }
        if password != confirmPass {
            errorMessage = "Passwords don't match"; return false
        }
        if !validateUsername() { return false }
        if displayName.trimmingCharacters(in: .whitespaces).count < 2 {
            errorMessage = "Display name must be at least 2 characters"; return false
        }

        return true
    }

    @discardableResult
    private func validateUsername() -> Bool {
        let trimmed = username.lowercased().trimmingCharacters(in: .whitespaces)
        if trimmed.count < 3 {
            errorMessage = "Username must be at least 3 characters"
            return false
        }
        if trimmed.count > 20 {
            errorMessage = "Username must be 20 characters or fewer"
            return false
        }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        if !trimmed.unicodeScalars.allSatisfy({ allowed.contains($0) }) {
            errorMessage = "Username can only contain letters, numbers, and underscores"
            return false
        }
        if usernameAvailable == false {
            errorMessage = "Username is already taken"
            return false
        }
        return true
    }

    private func clearForm() {
        email = ""; password = ""; confirmPass = ""
        username = ""; displayName = ""
        selectedAvatarId = "avatar_1"
        errorMessage = nil
        usernameAvailable = nil
    }
}
