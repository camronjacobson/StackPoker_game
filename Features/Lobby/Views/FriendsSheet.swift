import SwiftUI

// ─── Friends Sheet ────────────────────────────────────────────────────────────

struct FriendsSheet: View {
    @ObservedObject var vm: FriendsViewModel
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                SPColors.background.ignoresSafeArea()

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
        Button(action: action) {
            HStack(spacing: 4) {
                Text(label)
                    .font(SPFonts.headline(13))
                    .foregroundStyle(isSelected ? .white : SPColors.textSecondary)
                if let count {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(isSelected ? SPColors.accent : .white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(isSelected ? .white : SPColors.danger)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, SPSpacing.md)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(isSelected ? SPColors.accent : SPColors.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: SPRadius.sm))
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
        HStack {
            Text(title)
                .font(SPFonts.caption(11))
                .foregroundStyle(SPColors.textTertiary)
                .textCase(.uppercase)
                .tracking(0.8)
            Spacer()
        }
        .padding(.horizontal, SPSpacing.md)
        .padding(.vertical, SPSpacing.xs)
        .background(SPColors.background)
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
        VStack(spacing: SPSpacing.lg) {
            Spacer()
            Image(systemName: "person.2.slash")
                .font(.system(size: 44))
                .foregroundStyle(SPColors.textTertiary)
            VStack(spacing: 4) {
                Text("No friends yet")
                    .font(SPFonts.headline())
                    .foregroundStyle(SPColors.textPrimary)
                Text("Find players to add as friends")
                    .font(SPFonts.body(14))
                    .foregroundStyle(SPColors.textSecondary)
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
        HStack(spacing: SPSpacing.md) {
            ZStack(alignment: .bottomTrailing) {
                AvatarView(avatarId: friend.avatarId, size: 44)
                if friend.isOnline {
                    Circle()
                        .fill(SPColors.success)
                        .frame(width: 11, height: 11)
                        .overlay(Circle().strokeBorder(SPColors.background, lineWidth: 1.5))
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(friend.displayName)
                    .font(SPFonts.headline(14))
                    .foregroundStyle(SPColors.textPrimary)
                HStack(spacing: SPSpacing.xs) {
                    Text("@\(friend.username)")
                        .font(SPFonts.caption(12))
                        .foregroundStyle(SPColors.textTertiary)
                    if friend.isOnline {
                        Text("\u{00B7} Online")
                            .font(SPFonts.caption(12))
                            .foregroundStyle(SPColors.success)
                    }
                }
            }

            Spacer()

            ChipBadge(amount: friend.formattedChips, size: .small)

            Button {
                showRemoveConfirm = true
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16))
                    .foregroundStyle(SPColors.textTertiary)
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
                    .font(SPFonts.headline(14))
                    .foregroundStyle(SPColors.textPrimary)
                Text("@\(request.sender.username) wants to be friends")
                    .font(SPFonts.caption(12))
                    .foregroundStyle(SPColors.textTertiary)
            }

            Spacer()

            HStack(spacing: SPSpacing.xs) {
                Button {
                    Task { await vm.declineRequest(request) }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SPColors.textSecondary)
                        .frame(width: 34, height: 34)
                        .background(SPColors.surfaceElevated)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                Button {
                    Task { await vm.acceptRequest(request) }
                } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(SPColors.accent)
                        .clipShape(Circle())
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
            HStack(spacing: SPSpacing.sm) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundStyle(SPColors.textTertiary)
                TextField("Search by username or name", text: $vm.searchQuery)
                    .font(SPFonts.body())
                    .foregroundStyle(SPColors.textPrimary)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                if !vm.searchQuery.isEmpty {
                    Button { vm.searchQuery = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(SPColors.textTertiary)
                    }
                }
            }
            .padding(.horizontal, SPSpacing.md)
            .frame(height: 44)
            .background(SPColors.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: SPRadius.md))
            .overlay(RoundedRectangle(cornerRadius: SPRadius.md).strokeBorder(SPColors.border, lineWidth: 0.5))
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
                    .font(SPFonts.headline(14))
                    .foregroundStyle(SPColors.textPrimary)
                Text("@\(user.username)")
                    .font(SPFonts.caption(12))
                    .foregroundStyle(SPColors.textTertiary)
            }

            Spacer()

            ChipBadge(amount: user.formattedChips, size: .small)

            addButton
        }
        .padding(.horizontal, SPSpacing.md)
        .padding(.vertical, SPSpacing.sm + 2)
    }

    @ViewBuilder
    private var addButton: some View {
        if user.isFriend {
            Label("Friends", systemImage: "checkmark")
                .font(SPFonts.caption(11))
                .foregroundStyle(SPColors.success)
        } else if user.hasPendingRequest {
            Text("Pending")
                .font(SPFonts.caption(11))
                .foregroundStyle(SPColors.textTertiary)
                .padding(.horizontal, SPSpacing.sm)
                .padding(.vertical, 5)
                .background(SPColors.surfaceHighlight)
                .clipShape(RoundedRectangle(cornerRadius: SPRadius.sm))
        } else {
            Button {
                Task { await vm.sendRequest(to: user) }
            } label: {
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(SPColors.accent)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }
}
