import SwiftUI

// ─── Friends Sheet ────────────────────────────────────────────────────────────

struct FriendsSheet: View {
    @ObservedObject var vm: FriendsViewModel
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                // Aged-paper substrate — keeps the friends sheet inside
                // the same printed-booklet aesthetic as the lobby.
                AgedPaperBackground().ignoresSafeArea()

                VStack(spacing: 0) {
                    FriendsTabBar(vm: vm)
                        .padding(.horizontal, SPSpacing.md)
                        .padding(.top, SPSpacing.sm)
                        .padding(.bottom, SPSpacing.md)

                    SPDivider()

                    Group {
                        switch vm.activeTab {
                        case .friends:  FriendsListTab(vm: vm)
                        case .requests: FriendRequestsTab(vm: vm)
                        case .search:   FriendSearchTab(vm: vm)
                        }
                    }
                    .transition(.opacity.animation(.easeInOut(duration: 0.18)))
                    .animation(.easeInOut(duration: 0.18), value: vm.activeTab)
                }
            }
            .navigationTitle("Friends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(SPColors.surface, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(SPColors.accent)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        withAnimation { vm.activeTab = .search }
                    } label: {
                        Image(systemName: "person.badge.plus")
                            .foregroundStyle(SPColors.accent)
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(SPColors.background)
        .task { await vm.load() }
    }
}

// ─── Tab Bar ──────────────────────────────────────────────────────────────────

struct FriendsTabBar: View {
    @ObservedObject var vm: FriendsViewModel

    var body: some View {
        HStack(spacing: SPSpacing.sm) {
            FriendTabButton(label: "Friends", count: nil, isSelected: vm.activeTab == .friends) {
                withAnimation { vm.activeTab = .friends }
            }
            FriendTabButton(
                label: "Requests",
                count: vm.requestBadge > 0 ? vm.requestBadge : nil,
                isSelected: vm.activeTab == .requests
            ) {
                withAnimation { vm.activeTab = .requests }
            }
            FriendTabButton(label: "Find", count: nil, isSelected: vm.activeTab == .search) {
                withAnimation { vm.activeTab = .search }
            }
        }
    }
}

struct FriendTabButton: View {
    let label: String
    let count: Int?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        // Retro tab button: ink-bordered rounded rect; mustard fill when
        // selected (with a small hard offset shadow so the selected tab
        // visibly lifts), paperShade when idle. Count badge becomes a
        // pop-red sticker with ink border. Same vocab as the auth tab
        // picker so all segmented controls feel like the same printed UI.
        Button(action: action) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.custom("AmericanTypewriter-Bold", size: 13))
                    .tracking(0.4)
                    .foregroundStyle(SPRetro.ink)
                if let count {
                    Text("\(count)")
                        .font(.custom("AmericanTypewriter-Bold", size: 10))
                        .foregroundStyle(SPRetro.paper)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            ZStack {
                                Capsule().fill(SPRetro.popRed)
                                Capsule().strokeBorder(SPRetro.ink, lineWidth: 1)
                            }
                        )
                }
            }
            .padding(.horizontal, SPSpacing.md)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(
                ZStack {
                    if isSelected {
                        RoundedRectangle(cornerRadius: SPRadius.sm)
                            .fill(SPRetro.ink)
                            .offset(x: 1.5, y: 2)
                    }
                    RoundedRectangle(cornerRadius: SPRadius.sm)
                        .fill(isSelected
                              ? SPRetro.mustard
                              : SPRetro.paperShade)
                    RoundedRectangle(cornerRadius: SPRadius.sm)
                        .strokeBorder(SPRetro.ink,
                                      lineWidth: isSelected ? 1.8 : 1.2)
                }
            )
        }
        .buttonStyle(.plain)
    }
}

// ─── Friends List Tab ─────────────────────────────────────────────────────────

struct FriendsListTab: View {
    @ObservedObject var vm: FriendsViewModel

    private var onlineFriends: [Friend] { vm.friends.filter(\.isOnline) }
    private var offlineFriends: [Friend] { vm.friends.filter { !$0.isOnline } }

    var body: some View {
        Group {
            if vm.isLoadingFriends && vm.friends.isEmpty {
                loadingSkeleton
            } else if vm.friends.isEmpty {
                emptyFriendsState
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
                        if !onlineFriends.isEmpty {
                            Section {
                                ForEach(onlineFriends) { friend in
                                    FriendRow(friend: friend, vm: vm)
                                    SPDivider().padding(.leading, 68)
                                }
                            } header: {
                                sectionHeader("Online \u{2014} \(onlineFriends.count)")
                            }
                        }

                        if !offlineFriends.isEmpty {
                            Section {
                                ForEach(offlineFriends) { friend in
                                    FriendRow(friend: friend, vm: vm)
                                    if friend.id != offlineFriends.last?.id {
                                        SPDivider().padding(.leading, 68)
                                    }
                                }
                            } header: {
                                sectionHeader("Offline \u{2014} \(offlineFriends.count)")
                            }
                        }
                    }
                    .padding(.bottom, 40)
                }
                .refreshable { await vm.loadFriends() }
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        // Retro section header — typewriter-bold all-caps tracked, sits
        // on paperShade so it visually separates pinned section breaks
        // from the cream page below.
        HStack {
            Text(title)
                .font(.custom("AmericanTypewriter-Bold", size: 11))
                .foregroundStyle(SPRetro.inkMuted)
                .textCase(.uppercase)
                .tracking(1.2)
            Spacer()
        }
        .padding(.horizontal, SPSpacing.md)
        .padding(.vertical, SPSpacing.xs)
        .background(SPRetro.paperShade)
    }

    private var loadingSkeleton: some View {
        VStack(spacing: 0) {
            ForEach(0..<6, id: \.self) { _ in
                HStack(spacing: SPSpacing.md) {
                    Circle().fill(SPColors.surface).frame(width: 44, height: 44).shimmer()
                    VStack(alignment: .leading, spacing: 4) {
                        RoundedRectangle(cornerRadius: 4).fill(SPColors.surface).frame(width: 120, height: 12).shimmer()
                        RoundedRectangle(cornerRadius: 4).fill(SPColors.surface).frame(width: 80, height: 10).shimmer()
                    }
                    Spacer()
                }
                .padding(.horizontal, SPSpacing.md)
                .padding(.vertical, SPSpacing.sm + 4)
                SPDivider().padding(.leading, 68)
            }
        }
    }

    private var emptyFriendsState: some View {
        // Retro empty state — ink-soft icon + typewriter copy + the
        // SPButton CTA already inherits the new retro vocab via the
        // SPComponents pass.
        VStack(spacing: SPSpacing.lg) {
            Spacer()
            Image(systemName: "person.2.slash")
                .font(.system(size: 44))
                .foregroundStyle(SPRetro.inkMuted)
            VStack(spacing: 4) {
                Text("No friends yet")
                    .font(.custom("AmericanTypewriter-Bold", size: 18))
                    .foregroundStyle(SPRetro.ink)
                Text("Find players to add as friends")
                    .font(.custom("AmericanTypewriter", size: 14))
                    .foregroundStyle(SPRetro.inkMuted)
            }
            SPButton("Find Players", icon: "magnifyingglass") {
                withAnimation { vm.activeTab = .search }
            }
            .padding(.horizontal, 80)
            Spacer()
        }
    }
}

// ─── Friend Row ───────────────────────────────────────────────────────────────

struct FriendRow: View {
    let friend: Friend
    @ObservedObject var vm: FriendsViewModel
    @State private var showRemoveConfirm = false

    var body: some View {
        // Retro friend row: AmericanTypewriter typography, muted-teal
        // online dot with paper hairline (same as PlayerSeatView), ink-
        // soft ellipsis. The whole row sits on the cream page; rows are
        // separated by SPDivider's ink hairline.
        HStack(spacing: SPSpacing.md) {
            ZStack(alignment: .bottomTrailing) {
                AvatarView(avatarId: friend.avatarId, size: 44)
                if friend.isOnline {
                    Circle()
                        .fill(SPRetro.teal)
                        .frame(width: 11, height: 11)
                        .overlay(Circle().strokeBorder(SPRetro.paper, lineWidth: 1.5))
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(friend.displayName)
                    .font(.custom("AmericanTypewriter-Bold", size: 14))
                    .foregroundStyle(SPRetro.ink)
                HStack(spacing: SPSpacing.xs) {
                    Text("@\(friend.username)")
                        .font(.custom("AmericanTypewriter", size: 12))
                        .foregroundStyle(SPRetro.inkMuted)
                    if friend.isOnline {
                        Text("\u{00B7} Online")
                            .font(.custom("AmericanTypewriter-Bold", size: 12))
                            .foregroundStyle(SPRetro.teal)
                    }
                }
            }

            Spacer()

            ChipBadge(amount: friend.formattedChips, size: .small)

            Button {
                showRemoveConfirm = true
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(SPRetro.inkMuted)
                    .frame(width: 32, height: 32)
            }
        }
        .padding(.horizontal, SPSpacing.md)
        .padding(.vertical, SPSpacing.sm + 2)
        .confirmationDialog(friend.displayName, isPresented: $showRemoveConfirm) {
            Button("Remove Friend", role: .destructive) {
                Task { await vm.removeFriend(friend) }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

// ─── Friend Requests Tab ──────────────────────────────────────────────────────

struct FriendRequestsTab: View {
    @ObservedObject var vm: FriendsViewModel

    var body: some View {
        Group {
            if vm.isLoadingRequests && vm.pendingRequests.isEmpty {
                ProgressView().tint(SPColors.accent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if vm.pendingRequests.isEmpty {
                VStack(spacing: SPSpacing.md) {
                    Spacer()
                    Image(systemName: "tray")
                        .font(.system(size: 40))
                        .foregroundStyle(SPColors.textTertiary)
                    Text("No pending requests")
                        .font(SPFonts.body())
                        .foregroundStyle(SPColors.textSecondary)
                    Spacer()
                }
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(vm.pendingRequests) { request in
                            FriendRequestRow(request: request, vm: vm)
                            SPDivider().padding(.leading, 68)
                        }
                    }
                    .padding(.bottom, 40)
                }
            }
        }
        .task { await vm.loadRequests() }
    }
}

struct FriendRequestRow: View {
    let request: FriendRequest
    @ObservedObject var vm: FriendsViewModel

    var body: some View {
        HStack(spacing: SPSpacing.md) {
            AvatarView(avatarId: request.sender.avatarId, size: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text(request.sender.displayName)
                    .font(.custom("AmericanTypewriter-Bold", size: 14))
                    .foregroundStyle(SPRetro.ink)
                Text("@\(request.sender.username) wants to be friends")
                    .font(.custom("AmericanTypewriter", size: 12))
                    .foregroundStyle(SPRetro.inkMuted)
            }

            Spacer()

            // Retro accept/decline sticker buttons — same vocab as the
            // InviteRow in LobbySheets so confirming a friend request
            // reads as the same gesture as confirming a table invite.
            HStack(spacing: SPSpacing.xs) {
                Button {
                    Task { await vm.declineRequest(request) }
                } label: {
                    ZStack {
                        Circle().fill(SPRetro.ink)
                            .frame(width: 34, height: 34).offset(x: 1.5, y: 2)
                        Circle().fill(SPRetro.paperShade)
                            .frame(width: 34, height: 34)
                        Circle().strokeBorder(SPRetro.ink, lineWidth: 1.5)
                            .frame(width: 34, height: 34)
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .black))
                            .foregroundStyle(SPRetro.ink)
                    }
                }
                .buttonStyle(.plain)

                Button {
                    Task { await vm.acceptRequest(request) }
                } label: {
                    ZStack {
                        Circle().fill(SPRetro.ink)
                            .frame(width: 34, height: 34).offset(x: 1.5, y: 2)
                        Circle().fill(SPRetro.mustard)
                            .frame(width: 34, height: 34)
                        Circle().strokeBorder(SPRetro.ink, lineWidth: 1.5)
                            .frame(width: 34, height: 34)
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .black))
                            .foregroundStyle(SPRetro.ink)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, SPSpacing.md)
        .padding(.vertical, SPSpacing.sm + 2)
    }
}

// ─── Friend Search Tab ────────────────────────────────────────────────────────

struct FriendSearchTab: View {
    @ObservedObject var vm: FriendsViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Retro search field — paperShade fill, ink panel border,
            // AmericanTypewriter input. Same vocab as SPTextField.
            HStack(spacing: SPSpacing.sm) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SPRetro.inkMuted)
                TextField("Search by username or name", text: $vm.searchQuery)
                    .font(.custom("AmericanTypewriter", size: 15))
                    .foregroundStyle(SPRetro.ink)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                if !vm.searchQuery.isEmpty {
                    Button { vm.searchQuery = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(SPRetro.inkMuted)
                    }
                }
            }
            .padding(.horizontal, SPSpacing.md)
            .frame(height: 44)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: SPRadius.md)
                        .fill(SPRetro.paperShade)
                    RoundedRectangle(cornerRadius: SPRadius.md)
                        .strokeBorder(SPRetro.ink, lineWidth: 1.2)
                }
            )
            .padding(.horizontal, SPSpacing.md)
            .padding(.vertical, SPSpacing.md)

            SPDivider()

            Group {
                if vm.isSearching {
                    ProgressView().tint(SPColors.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.top, SPSpacing.xl)
                } else if vm.searchQuery.count >= 2 && vm.searchResults.isEmpty {
                    VStack(spacing: SPSpacing.md) {
                        Spacer()
                        Image(systemName: "person.slash")
                            .font(.system(size: 36))
                            .foregroundStyle(SPColors.textTertiary)
                        Text("No users found for \"\(vm.searchQuery)\"")
                            .font(SPFonts.body(14))
                            .foregroundStyle(SPColors.textSecondary)
                            .multilineTextAlignment(.center)
                        Spacer()
                    }
                    .padding(.horizontal, SPSpacing.lg)
                } else if vm.searchQuery.isEmpty {
                    VStack(spacing: SPSpacing.md) {
                        Spacer()
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 36))
                            .foregroundStyle(SPColors.textTertiary)
                        Text("Search for players to add as friends")
                            .font(SPFonts.body(14))
                            .foregroundStyle(SPColors.textSecondary)
                            .multilineTextAlignment(.center)
                        Spacer()
                    }
                    .padding(.horizontal, SPSpacing.lg)
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 0) {
                            ForEach(vm.searchResults) { user in
                                SearchUserRow(user: user, vm: vm)
                                if user.id != vm.searchResults.last?.id {
                                    SPDivider().padding(.leading, 68)
                                }
                            }
                        }
                        .padding(.bottom, 40)
                    }
                }
            }
        }
    }
}

struct SearchUserRow: View {
    let user: SearchedUser
    @ObservedObject var vm: FriendsViewModel

    var body: some View {
        HStack(spacing: SPSpacing.md) {
            AvatarView(avatarId: user.avatarId, size: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text(user.displayName)
                    .font(.custom("AmericanTypewriter-Bold", size: 14))
                    .foregroundStyle(SPRetro.ink)
                Text("@\(user.username)")
                    .font(.custom("AmericanTypewriter", size: 12))
                    .foregroundStyle(SPRetro.inkMuted)
            }

            Spacer()

            ChipBadge(amount: user.formattedChips, size: .small)

            addButton
        }
        .padding(.horizontal, SPSpacing.md)
        .padding(.vertical, SPSpacing.sm + 2)
    }

    // Retro "add user" affordance — three states each rendered as a
    // small ink-bordered sticker: muted-teal "Friends" pill (paid),
    // paperShade "Pending" pill (idle/awaiting), mustard +badge disc
    // with offset shadow (CTA).
    @ViewBuilder
    private var addButton: some View {
        if user.isFriend {
            Label("Friends", systemImage: "checkmark")
                .font(.custom("AmericanTypewriter-Bold", size: 11))
                .tracking(0.4)
                .foregroundStyle(SPRetro.teal)
        } else if user.hasPendingRequest {
            Text("Pending")
                .font(.custom("AmericanTypewriter-Bold", size: 11))
                .tracking(0.4)
                .foregroundStyle(SPRetro.inkMuted)
                .padding(.horizontal, SPSpacing.sm)
                .padding(.vertical, 5)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: SPRadius.sm)
                            .fill(SPRetro.paperShade)
                        RoundedRectangle(cornerRadius: SPRadius.sm)
                            .strokeBorder(SPRetro.ink, lineWidth: 1)
                    }
                )
        } else {
            Button {
                Task { await vm.sendRequest(to: user) }
            } label: {
                ZStack {
                    Circle().fill(SPRetro.ink)
                        .frame(width: 34, height: 34).offset(x: 1.5, y: 2)
                    Circle().fill(SPRetro.mustard)
                        .frame(width: 34, height: 34)
                    Circle().strokeBorder(SPRetro.ink, lineWidth: 1.5)
                        .frame(width: 34, height: 34)
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(SPRetro.ink)
                }
            }
            .buttonStyle(.plain)
        }
    }
}
