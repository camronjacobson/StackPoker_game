import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var appState: AppState
    @State private var showLogoutConfirm = false

    var body: some View {
        NavigationStack {
            ZStack {
                SPColors.background.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: SPSpacing.lg) {
                        profileHeader
                        statsGrid
                        settingsSection
                        legalSection
                        logoutButton
                    }
                    .padding(.bottom, 100)
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(SPColors.surface, for: .navigationBar)
            .confirmationDialog("Sign Out", isPresented: $showLogoutConfirm, titleVisibility: .visible) {
                Button("Sign Out", role: .destructive) { authVM.logout() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You'll need to sign in again to play.")
            }
        }
    }

    // ─── Profile Header ────────────────────────────────────────────────────────

    @ViewBuilder
    private var profileHeader: some View {
        if let user = authVM.currentUser {
            VStack(spacing: SPSpacing.md) {
                ZStack(alignment: .bottomTrailing) {
                    AvatarView(avatarId: user.avatarId, size: 90, showBorder: true)

                    Circle()
                        .fill(SPColors.success)
                        .frame(width: 16, height: 16)
                        .overlay(Circle().strokeBorder(SPColors.background, lineWidth: 2))
                }

                VStack(spacing: 4) {
                    Text(user.displayName)
                        .font(SPFonts.title(22))
                        .foregroundStyle(SPColors.textPrimary)

                    Text("@\(user.username)")
                        .font(SPFonts.body())
                        .foregroundStyle(SPColors.textSecondary)
                }

                ChipBadge(amount: user.formattedChips, size: .large)
                    .padding(.horizontal, SPSpacing.lg)
                    .padding(.vertical, SPSpacing.sm)
                    .background(SPColors.surface)
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(SPColors.border, lineWidth: 0.5))
            }
            .padding(.top, SPSpacing.lg)
        }
    }

    // ─── Stats Grid ────────────────────────────────────────────────────────────

    @ViewBuilder
    private var statsGrid: some View {
        if let user = authVM.currentUser {
            LazyVGrid(columns: [GridItem(.fixed(160)), GridItem(.fixed(160))], spacing: SPSpacing.sm) {
                StatCard(
                    label: "Hands Played",
                    value: "\(user.handsPlayed ?? 0)",
                    icon: "suit.spade.fill",
                    color: SPColors.accent
                )
                StatCard(
                    label: "Games Played",
                    value: "\(user.gamesPlayed ?? 0)",
                    icon: "rectangle.stack.fill",
                    color: SPColors.info
                )
                StatCard(
                    label: "Total Won",
                    value: formatChips(user.totalWon ?? "0"),
                    icon: "arrow.up.circle.fill",
                    color: SPColors.success
                )
                StatCard(
                    label: "Total Lost",
                    value: formatChips(user.totalLost ?? "0"),
                    icon: "arrow.down.circle.fill",
                    color: SPColors.danger
                )
            }
            .padding(.horizontal, SPSpacing.md)
        }
    }

    private func formatChips(_ raw: String) -> String {
        let n = Int64(raw) ?? 0
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000     { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }

    // ─── Settings Section ──────────────────────────────────────────────────────

    @ViewBuilder
    private var settingsSection: some View {
        VStack(spacing: 0) {
            SPSectionHeader(title: "Account")
                .padding(.bottom, SPSpacing.sm)

            SPCard {
                VStack(spacing: 0) {
                    SettingsRow(icon: "person.circle", label: "Edit Profile", showChevron: true)
                    SPDivider()
                    SettingsRow(icon: "bell", label: "Notifications", showChevron: true)
                    SPDivider()
                    SettingsRow(icon: "shield", label: "Privacy & Security", showChevron: true)
                }
            }
        }
        .padding(.horizontal, SPSpacing.md)
    }

    // ─── Legal Section ─────────────────────────────────────────────────────────

    @ViewBuilder
    private var legalSection: some View {
        VStack(spacing: 0) {
            SPSectionHeader(title: "About")
                .padding(.bottom, SPSpacing.sm)

            SPCard {
                VStack(spacing: 0) {
                    SettingsRow(icon: "doc.text", label: "Terms of Service", showChevron: true)
                    SPDivider()
                    SettingsRow(icon: "hand.raised", label: "Privacy Policy", showChevron: true)
                    SPDivider()

                    // Required App Store social game disclosure
                    HStack(spacing: SPSpacing.sm) {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(SPColors.info)
                            .font(.system(size: 16))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Virtual Chips Only")
                                .font(SPFonts.caption(13))
                                .foregroundStyle(SPColors.textPrimary)
                            Text("No real money · No gambling · Social game for entertainment")
                                .font(SPFonts.caption(11))
                                .foregroundStyle(SPColors.textTertiary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, SPSpacing.md)
                    .padding(.vertical, SPSpacing.sm + 2)
                }
            }
        }
        .padding(.horizontal, SPSpacing.md)
    }

    // ─── Logout ────────────────────────────────────────────────────────────────

    @ViewBuilder
    private var logoutButton: some View {
        SPButton("Sign Out", style: .danger, icon: "rectangle.portrait.and.arrow.right") {
            showLogoutConfirm = true
        }
        .padding(.horizontal, SPSpacing.md)
    }
}

// ─── Stat Card ────────────────────────────────────────────────────────────────

struct StatCard: View {
    let label: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        SPCard {
            VStack(alignment: .leading, spacing: SPSpacing.xs) {
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 14))
                        .foregroundStyle(color)
                    Spacer()
                }
                Text(value)
                    .font(SPFonts.chips(22))
                    .foregroundStyle(SPColors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(label)
                    .font(SPFonts.caption(12))
                    .foregroundStyle(SPColors.textSecondary)
                    .lineLimit(1)
            }
            .padding(SPSpacing.md)
        }
    }
}

// ─── Settings Row ─────────────────────────────────────────────────────────────

struct SettingsRow: View {
    let icon: String
    let label: String
    var showChevron: Bool = false
    var action: (() -> Void)?

    var body: some View {
        Button {
            action?()
        } label: {
            HStack(spacing: SPSpacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundStyle(SPColors.accent)
                    .frame(width: 24)

                Text(label)
                    .font(SPFonts.body())
                    .foregroundStyle(SPColors.textPrimary)

                Spacer()

                if showChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(SPColors.textTertiary)
                }
            }
            .padding(.horizontal, SPSpacing.md)
            .padding(.vertical, SPSpacing.sm + 4)
        }
        .buttonStyle(.plain)
    }
}

// ─── Settings Sheet ───────────────────────────────────────────────────────────
// Opens from the lobby avatar tap. Exposes: avatar picker, table theme,
// display name edit, and sign out. All actions are real (no stubs).

struct SettingsSheet: View {
    @EnvironmentObject var authVM: AuthViewModel
    @Environment(\.dismiss) var dismiss

    @AppStorage("tableThemeId") private var tableThemeId: String = "classic_blue"
    @AppStorage(SoundManager.enabledKey) private var soundEnabled: Bool = true
    @AppStorage(SoundManager.volumeKey)  private var soundVolume: Double = 0.8

    @State private var showAvatarPicker = false
    @State private var showEditName     = false
    @State private var showLogoutConfirm = false
    @State private var isSavingAvatar    = false
    @State private var isGrantingChips   = false
    @State private var toastMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                SPColors.background.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: SPSpacing.xl) {
                        header
                        accountSection
                        appearanceSection
                        soundSection
                        devSection
                        legalSection
                        signOutButton
                    }
                    .padding(.top, SPSpacing.md)
                    .padding(.bottom, SPSpacing.xl)
                }

                if let toast = toastMessage {
                    VStack {
                        Spacer()
                        Text(toast)
                            .font(SPFonts.body(14))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(SPColors.success.opacity(0.9))
                            .clipShape(Capsule())
                            .padding(.bottom, 40)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(SPColors.surface, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(SPColors.accent)
                }
            }
            .sheet(isPresented: $showAvatarPicker) {
                AvatarPickerSaveSheet(onSave: { newId in
                    await saveAvatar(newId)
                })
                .environmentObject(authVM)
            }
            .sheet(isPresented: $showEditName) {
                EditDisplayNameSheet(onSave: { newName in
                    await saveDisplayName(newName)
                })
                .environmentObject(authVM)
            }
            .confirmationDialog("Sign Out", isPresented: $showLogoutConfirm, titleVisibility: .visible) {
                Button("Sign Out", role: .destructive) {
                    authVM.logout()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You'll need to sign in again to play.")
            }
            .animation(.spring(response: 0.3), value: toastMessage)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(SPColors.background)
    }

    @ViewBuilder
    private var header: some View {
        if let user = authVM.currentUser {
            VStack(spacing: SPSpacing.sm) {
                AvatarView(avatarId: user.avatarId, size: 88, showBorder: true)
                    .overlay(alignment: .bottomTrailing) {
                        if isSavingAvatar {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)
                                .padding(6)
                                .background(SPColors.accent)
                                .clipShape(Circle())
                        }
                    }

                Text(user.displayName)
                    .font(SPFonts.title(20))
                    .foregroundStyle(SPColors.textPrimary)

                Text("@\(user.username)")
                    .font(SPFonts.caption(12))
                    .foregroundStyle(SPColors.textSecondary)
            }
        }
    }

    private var accountSection: some View {
        VStack(spacing: 0) {
            SPSectionHeader(title: "Account")
                .padding(.bottom, SPSpacing.sm)

            SPCard {
                VStack(spacing: 0) {
                    SettingsRow(icon: "person.crop.circle", label: "Change Avatar", showChevron: true) {
                        showAvatarPicker = true
                    }
                    SPDivider()
                    SettingsRow(icon: "pencil", label: "Edit Display Name", showChevron: true) {
                        showEditName = true
                    }
                }
            }
        }
        .padding(.horizontal, SPSpacing.md)
    }

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SPSectionHeader(title: "Table Color")
                .padding(.bottom, SPSpacing.sm)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: SPSpacing.sm) {
                    ForEach(TableTheme.all) { theme in
                        TableThemeChip(
                            theme: theme,
                            isSelected: tableThemeId == theme.id
                        ) {
                            withAnimation(.spring(response: 0.3)) {
                                tableThemeId = theme.id
                            }
                            showToast("Table color: \(theme.label)")
                        }
                    }
                }
                .padding(.horizontal, SPSpacing.md)
                .padding(.vertical, 4)
            }
        }
    }

    private var soundSection: some View {
        VStack(spacing: 0) {
            SPSectionHeader(title: "Sound")
                .padding(.bottom, SPSpacing.sm)

            SPCard {
                VStack(spacing: 0) {
                    HStack(spacing: SPSpacing.sm) {
                        Image(systemName: soundEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(SPColors.accent)
                            .frame(width: 24)
                        Toggle(isOn: $soundEnabled) {
                            Text("Sound Effects")
                                .font(SPFonts.body())
                                .foregroundStyle(SPColors.textPrimary)
                        }
                        .tint(SPColors.accent)
                    }
                    .padding(.horizontal, SPSpacing.md)
                    .padding(.vertical, SPSpacing.sm + 4)
                    .onChange(of: soundEnabled) { _, _ in
                        SoundManager.shared.applyVolumeFromDefaults()
                        if soundEnabled { SoundManager.shared.play(.call) }
                    }

                    if soundEnabled {
                        SPDivider()
                        HStack(spacing: SPSpacing.sm) {
                            Image(systemName: "speaker.wave.1.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(SPColors.textSecondary)
                                .frame(width: 24)
                            Slider(value: $soundVolume, in: 0...1) { editing in
                                if !editing {
                                    SoundManager.shared.applyVolumeFromDefaults()
                                    SoundManager.shared.play(.call)
                                }
                            }
                            .tint(SPColors.accent)
                            Image(systemName: "speaker.wave.3.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(SPColors.textSecondary)
                                .frame(width: 24)
                        }
                        .padding(.horizontal, SPSpacing.md)
                        .padding(.vertical, SPSpacing.sm + 4)
                        .onChange(of: soundVolume) { _, _ in
                            SoundManager.shared.applyVolumeFromDefaults()
                        }
                    }
                }
            }
        }
        .padding(.horizontal, SPSpacing.md)
    }

    // Dev-only helper: call the existing admin-grant endpoint to top up the
    // current user's chip balance so testing doesn't keep running out.
    // Only works against an account with `isAdmin = true` server-side — if it
    // isn't, the server will return an error and we surface it via toast.
    private var devSection: some View {
        VStack(spacing: 0) {
            SPSectionHeader(title: "Dev Tools")
                .padding(.bottom, SPSpacing.sm)

            SPCard {
                SettingsRow(
                    icon: "plus.circle.fill",
                    label: isGrantingChips ? "Granting…" : "Top up chips (+10M)",
                    showChevron: false
                ) {
                    Task { await grantSelfChips(amount: 10_000_000) }
                }
                .disabled(isGrantingChips)
            }
        }
        .padding(.horizontal, SPSpacing.md)
    }

    private func grantSelfChips(amount: Int) async {
        guard let user = authVM.currentUser, !isGrantingChips else { return }
        isGrantingChips = true
        defer { isGrantingChips = false }

        struct Body: Encodable { let amount: Int }
        struct Resp: Decodable { let message: String }

        do {
            let _: Resp = try await NetworkService.shared.request(
                .adminGrantChips(userId: user.id),
                method: .POST,
                body: Body(amount: amount)
            )
            await authVM.refreshProfile()
            toastMessage = "+\(formatChips(String(amount))) chips added"
        } catch let e as NetworkError {
            toastMessage = e.localizedDescription
        } catch {
            toastMessage = "Top-up failed"
        }

        try? await Task.sleep(nanoseconds: 1_800_000_000)
        toastMessage = nil
    }

    private var legalSection: some View {
        VStack(spacing: 0) {
            SPSectionHeader(title: "About")
                .padding(.bottom, SPSpacing.sm)

            SPCard {
                VStack(spacing: 0) {
                    Link(destination: URL(string: "https://stackpoker.app/terms")!) {
                        SettingsRow(icon: "doc.text", label: "Terms of Service", showChevron: true)
                    }
                    .buttonStyle(.plain)
                    SPDivider()
                    Link(destination: URL(string: "https://stackpoker.app/privacy")!) {
                        SettingsRow(icon: "hand.raised", label: "Privacy Policy", showChevron: true)
                    }
                    .buttonStyle(.plain)
                    SPDivider()
                    HStack(spacing: SPSpacing.sm) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 15))
                            .foregroundStyle(SPColors.textSecondary)
                            .frame(width: 24)
                        Text("Version")
                            .font(SPFonts.body())
                            .foregroundStyle(SPColors.textPrimary)
                        Spacer()
                        Text(appVersion)
                            .font(SPFonts.caption(13))
                            .foregroundStyle(SPColors.textTertiary)
                    }
                    .padding(.horizontal, SPSpacing.md)
                    .padding(.vertical, SPSpacing.sm + 4)
                }
            }
        }
        .padding(.horizontal, SPSpacing.md)
    }

    private var signOutButton: some View {
        SPButton("Sign Out", style: .danger, icon: "rectangle.portrait.and.arrow.right") {
            showLogoutConfirm = true
        }
        .padding(.horizontal, SPSpacing.md)
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    private func saveAvatar(_ id: String) async {
        isSavingAvatar = true
        defer { isSavingAvatar = false }
        let ok = await authVM.updateProfile(avatarId: id)
        if ok {
            showToast("Avatar updated")
        } else if let msg = authVM.errorMessage {
            showToast(msg)
        }
    }

    private func saveDisplayName(_ name: String) async {
        let ok = await authVM.updateProfile(displayName: name)
        if ok {
            showToast("Name updated")
        } else if let msg = authVM.errorMessage {
            showToast(msg)
        }
    }

    private func showToast(_ text: String) {
        toastMessage = text
        Task {
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            if toastMessage == text { toastMessage = nil }
        }
    }
}

// ─── Table Theme Chip ─────────────────────────────────────────────────────────

private struct TableThemeChip: View {
    let theme: TableTheme
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color(hex: theme.inner),
                                    Color(hex: theme.mid),
                                    Color(hex: theme.edge),
                                ],
                                center: .center,
                                startRadius: 4,
                                endRadius: 46
                            )
                        )
                        .frame(width: 72, height: 54)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(
                                    isSelected ? SPColors.accent : Color.white.opacity(0.15),
                                    lineWidth: isSelected ? 2 : 1
                                )
                        )
                        .shadow(color: theme.primaryColor.opacity(0.35), radius: isSelected ? 8 : 3)

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.5), radius: 2)
                    }
                }
                Text(theme.label)
                    .font(SPFonts.caption(11))
                    .foregroundStyle(isSelected ? SPColors.accent : SPColors.textSecondary)
                    .lineLimit(1)
            }
            .scaleEffect(isSelected ? 1.04 : 1.0)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3), value: isSelected)
    }
}

// ─── Avatar Picker with Save ──────────────────────────────────────────────────

private struct AvatarPickerSaveSheet: View {
    @EnvironmentObject var authVM: AuthViewModel
    @Environment(\.dismiss) var dismiss

    let onSave: (String) async -> Void

    @State private var tempSelection: String = ""
    @State private var isSaving = false
    private let columns = Array(repeating: GridItem(.flexible(), spacing: SPSpacing.md), count: 3)

    var body: some View {
        NavigationStack {
            ZStack {
                SPColors.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: SPSpacing.xl) {
                        VStack(spacing: SPSpacing.sm) {
                            AvatarView(avatarId: tempSelection, size: 100, showBorder: true)
                                .animation(.spring(response: 0.3), value: tempSelection)
                            Text(AvatarOption.find(tempSelection).label)
                                .font(SPFonts.headline(18))
                                .foregroundStyle(SPColors.textPrimary)
                        }
                        .padding(.top, SPSpacing.md)

                        LazyVGrid(columns: columns, spacing: SPSpacing.md) {
                            ForEach(AvatarOption.all) { avatar in
                                AvatarGridCell(
                                    avatar: avatar,
                                    isSelected: tempSelection == avatar.id
                                ) {
                                    withAnimation(.spring(response: 0.3)) {
                                        tempSelection = avatar.id
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, SPSpacing.md)

                        SPButton(
                            "Save",
                            icon: "checkmark",
                            isLoading: isSaving,
                            isDisabled: tempSelection == authVM.currentUser?.avatarId
                        ) {
                            Task {
                                isSaving = true
                                await onSave(tempSelection)
                                isSaving = false
                                dismiss()
                            }
                        }
                        .padding(.horizontal, SPSpacing.md)
                        .padding(.bottom, SPSpacing.xl)
                    }
                }
            }
            .navigationTitle("Choose Avatar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(SPColors.surface, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(SPColors.textSecondary)
                }
            }
            .onAppear {
                tempSelection = authVM.currentUser?.avatarId ?? "avatar_1"
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(SPColors.background)
    }
}

// ─── Edit Display Name Sheet ──────────────────────────────────────────────────

private struct EditDisplayNameSheet: View {
    @EnvironmentObject var authVM: AuthViewModel
    @Environment(\.dismiss) var dismiss

    let onSave: (String) async -> Void

    @State private var name: String = ""
    @State private var isSaving = false
    @State private var localError: String?

    var body: some View {
        NavigationStack {
            ZStack {
                SPColors.background.ignoresSafeArea()

                VStack(alignment: .leading, spacing: SPSpacing.lg) {
                    SPSectionHeader(title: "Display Name")
                    SPTextField(
                        placeholder: "How others see you",
                        text: $name,
                        icon: "person"
                    )

                    if let localError {
                        Text(localError)
                            .font(SPFonts.caption(12))
                            .foregroundStyle(SPColors.danger)
                    }

                    SPButton(
                        "Save",
                        icon: "checkmark",
                        isLoading: isSaving,
                        isDisabled: !isValid
                    ) {
                        Task {
                            let trimmed = name.trimmingCharacters(in: .whitespaces)
                            isSaving = true
                            await onSave(trimmed)
                            isSaving = false
                            dismiss()
                        }
                    }

                    Spacer()
                }
                .padding(SPSpacing.md)
            }
            .navigationTitle("Edit Name")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(SPColors.surface, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(SPColors.textSecondary)
                }
            }
            .onAppear { name = authVM.currentUser?.displayName ?? "" }
            .onChange(of: name) { _, new in
                let t = new.trimmingCharacters(in: .whitespaces)
                if t.isEmpty || t.count >= 2 { localError = nil }
                else                         { localError = "Must be at least 2 characters" }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(SPColors.background)
    }

    private var isValid: Bool {
        let t = name.trimmingCharacters(in: .whitespaces)
        return t.count >= 2 && t.count <= 30 && t != authVM.currentUser?.displayName
    }
}
