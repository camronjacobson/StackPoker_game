import SwiftUI

struct LobbyView: View {
  @EnvironmentObject var vm: LobbyViewModel
  @StateObject private var fvm = FriendsViewModel()
  @EnvironmentObject var authVM: AuthViewModel

  @State private var showBuyInSheet:  TableListItem?
  @State private var showFriends      = false
  @State private var showSettings     = false
  @State private var buyInInput       = ""
  @State private var featuredPage     = 0

  private var activeTables: [TableListItem] {
    let filtered = vm.tables.filter { $0.currentPlayers > 0 }
    guard let filter = vm.gameTypeFilter else { return filtered }
    return filtered.filter { ($0.gameType ?? "TEXAS_HOLDEM") == filter }
  }

  private var featuredTables: [TableListItem] {
    // Show tables with players, or the most recent ones
    let withPlayers = vm.tables.filter { $0.currentPlayers > 0 }
    return withPlayers.isEmpty ? Array(vm.tables.prefix(3)) : Array(withPlayers.prefix(5))
  }

  var body: some View {
    NavigationStack {
      ZStack {
        // Dark gradient background
        LinearGradient(
          colors: [Color(hex: "#0A0E1A"), Color(hex: "#0A0A0F")],
          startPoint: .top, endPoint: .bottom
        ).ignoresSafeArea()

        ScrollView(showsIndicators: false) {
          VStack(spacing: SPSpacing.lg) {
            lobbyHeader
            featuredCarousel
            filterPills
            activeGamesSection
            friendsSection
            groupsSection
            Color.clear.frame(height: 80) // tab bar padding
          }
        }
        .refreshable { await vm.loadTables(); await fvm.load() }
      }
      .navigationBarHidden(true)
      .sheet(isPresented: $vm.showCreateSheet)  { CreateTableSheet(vm: vm) }
      .sheet(isPresented: $vm.showJoinCodeSheet) { JoinByCodeSheet(vm: vm) }
      .sheet(isPresented: $vm.showInvitesSheet)  { InvitesSheet(vm: vm) }
      .sheet(item: $showBuyInSheet) { table in
        BuyInSheet(table: table, buyIn: $buyInInput) {
          guard let amount = Int(buyInInput) else { return }
          showBuyInSheet = nil
          Task { await vm.joinTable(table, buyIn: amount) }
        }
      }
      .sheet(isPresented: $showFriends) { FriendsSheet(vm: fvm) }
      .sheet(isPresented: $showSettings) {
        SettingsSheet().environmentObject(authVM)
      }
      .fullScreenCover(item: $vm.joinedTable) { table in
        GamePlaceholderView(table: table) { vm.joinedTable = nil }
      }
      .safeAreaInset(edge: .top, spacing: 0) {
        if vm.lastTable != nil && vm.joinedTable == nil {
          RejoinBanner(tableName: vm.lastTable!.name) {
            vm.rejoinTable()
          }
        }
      }
      .onAppear  { vm.onAppear(); Task { await fvm.load() } }
      .onDisappear { vm.onDisappear() }
    }
  }

  // ─── Header: avatar + "For You" + chip balance ─────────────────────────────

  private var lobbyHeader: some View {
    HStack(spacing: SPSpacing.sm) {
      // Profile avatar — tap to open Settings
      Button { showSettings = true } label: {
        if let user = authVM.currentUser {
          AvatarView(avatarId: user.avatarId, size: 40)
        } else {
          Circle()
            .fill(Color(hex: "#1A1A24"))
            .frame(width: 40, height: 40)
        }
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Settings")

      Button { showSettings = true } label: {
        Text("For You")
          .font(.system(size: 28, weight: .bold, design: .rounded))
          .foregroundStyle(.white)
      }
      .buttonStyle(.plain)

      Spacer()

      // Chip balance pill
      if let user = authVM.currentUser {
        HStack(spacing: 6) {
          Image(systemName: "creditcard.fill")
            .font(.system(size: 13))
            .foregroundStyle(.white.opacity(0.7))
          Text(user.formattedChips)
            .font(.system(size: 15, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.08))
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
      }
    }
    .padding(.horizontal, SPSpacing.md)
    .padding(.top, SPSpacing.sm)
  }

  // ─── Featured game carousel ────────────────────────────────────────────────

  private var featuredCarousel: some View {
    VStack(spacing: SPSpacing.sm) {
      if !featuredTables.isEmpty {
        TabView(selection: $featuredPage) {
          ForEach(Array(featuredTables.enumerated()), id: \.element.id) { idx, table in
            FeaturedTableCard(table: table) {
              buyInInput = table.minBuyIn
              showBuyInSheet = table
            }
            .tag(idx)
            .padding(.horizontal, SPSpacing.md)
          }
        }
        .tabViewStyle(.page(indexDisplayMode: .automatic))
        .frame(height: 200)
      } else if vm.isLoadingTables {
        RoundedRectangle(cornerRadius: SPRadius.xl)
          .fill(Color(hex: "#13131A"))
          .frame(height: 200)
          .padding(.horizontal, SPSpacing.md)
          .shimmer()
      } else {
        // Empty state card
        VStack(spacing: SPSpacing.md) {
          Image(systemName: "plus.circle")
            .font(.system(size: 36))
            .foregroundStyle(Color(hex: "#6C5CE7").opacity(0.5))
          Text("Create your first table")
            .font(SPFonts.headline(16))
            .foregroundStyle(SPColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 180)
        .background(
          RoundedRectangle(cornerRadius: SPRadius.xl)
            .fill(Color(hex: "#13131A"))
            .overlay(
              RoundedRectangle(cornerRadius: SPRadius.xl)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
            )
        )
        .padding(.horizontal, SPSpacing.md)
        .onTapGesture { vm.showCreateSheet = true }
      }
    }
  }

  // ─── Filter pills ──────────────────────────────────────────────────────────

  private var filterPills: some View {
    HStack(spacing: SPSpacing.sm) {
      FilterChip(label: "Hold'em", isSelected: vm.gameTypeFilter == nil || vm.gameTypeFilter == "TEXAS_HOLDEM") {
        withAnimation(.spring(response: 0.3)) {
          vm.gameTypeFilter = vm.gameTypeFilter == "TEXAS_HOLDEM" ? nil : "TEXAS_HOLDEM"
        }
      }
      FilterChip(label: "SNG", isSelected: false) { }
      FilterChip(label: "PLO4", isSelected: vm.gameTypeFilter == "PLO") {
        withAnimation(.spring(response: 0.3)) {
          vm.gameTypeFilter = vm.gameTypeFilter == "PLO" ? nil : "PLO"
        }
      }
      Spacer()
    }
    .padding(.horizontal, SPSpacing.md)
  }

  // ─── Active games section ──────────────────────────────────────────────────

  private var activeGamesSection: some View {
    VStack(alignment: .leading, spacing: SPSpacing.sm) {
      HStack {
        HStack(spacing: 4) {
          Text("Active games")
            .font(.system(size: 22, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
          Image(systemName: "chevron.right")
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(SPColors.textTertiary)
        }
        Spacer()
        if !activeTables.isEmpty {
          Text("See all (\(activeTables.count))")
            .font(SPFonts.caption(13))
            .foregroundStyle(SPColors.textSecondary)
        }
      }
      .padding(.horizontal, SPSpacing.md)

      if activeTables.isEmpty {
        HStack {
          Spacer()
          VStack(spacing: 6) {
            Text("No active games")
              .font(SPFonts.body())
              .foregroundStyle(SPColors.textTertiary)
          }
          Spacer()
        }
        .frame(height: 100)
      } else {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: SPSpacing.sm) {
            ForEach(activeTables) { table in
              ActiveGameCard(table: table) {
                buyInInput = table.minBuyIn
                showBuyInSheet = table
              }
            }
          }
          .padding(.horizontal, SPSpacing.md)
        }
      }
    }
  }

  // ─── Friends section ───────────────────────────────────────────────────────

  private var friendsSection: some View {
    VStack(alignment: .leading, spacing: SPSpacing.sm) {
      HStack {
        HStack(spacing: 4) {
          Text("Friends")
            .font(.system(size: 22, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
          Image(systemName: "chevron.right")
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(SPColors.textTertiary)
        }
        Spacer()
        if !fvm.friends.isEmpty {
          Text("See all (\(fvm.friends.count))")
            .font(SPFonts.caption(13))
            .foregroundStyle(SPColors.textSecondary)
        }
      }
      .padding(.horizontal, SPSpacing.md)

      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: SPSpacing.md) {
          ForEach(fvm.friends) { friend in
            FriendBubble(friend: friend)
          }
          // Invite button
          VStack(spacing: 6) {
            Circle()
              .strokeBorder(Color.white.opacity(0.2), lineWidth: 1.5)
              .frame(width: 60, height: 60)
              .overlay(
                Image(systemName: "plus")
                  .font(.system(size: 20, weight: .medium))
                  .foregroundStyle(Color.white.opacity(0.4))
              )
            Text("Invite")
              .font(SPFonts.caption(11))
              .foregroundStyle(SPColors.textTertiary)
          }
          .onTapGesture { showFriends = true }
        }
        .padding(.horizontal, SPSpacing.md)
      }
    }
  }

  // ─── Groups section ────────────────────────────────────────────────────────

  private var groupsSection: some View {
    VStack(alignment: .leading, spacing: SPSpacing.sm) {
      HStack {
        HStack(spacing: 4) {
          Text("Groups")
            .font(.system(size: 22, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
          Image(systemName: "chevron.right")
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(SPColors.textTertiary)
        }
        Spacer()
        Text("My groups (0)")
          .font(SPFonts.caption(13))
          .foregroundStyle(SPColors.textSecondary)
      }
      .padding(.horizontal, SPSpacing.md)

      HStack {
        Spacer()
        VStack(spacing: 6) {
          Image(systemName: "person.3.fill")
            .font(.system(size: 24))
            .foregroundStyle(SPColors.textTertiary.opacity(0.5))
          Text("Join or create a group")
            .font(SPFonts.body(13))
            .foregroundStyle(SPColors.textTertiary)
        }
        Spacer()
      }
      .frame(height: 80)
    }
  }
}

// ─── Featured Table Card ─────────────────────────────────────────────────────

private struct FeaturedTableCard: View {
  let table: TableListItem
  let onJoin: () -> Void

  var body: some View {
    VStack(spacing: SPSpacing.md) {
      Spacer()

      // Blinds
      Text(table.blindsLabel)
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(.white.opacity(0.6))

      // Game type
      Text(table.gameTypeLabel == "PLO" ? "Pot Limit Omaha" : "No Limit Hold'em")
        .font(.system(size: 24, weight: .bold, design: .rounded))
        .foregroundStyle(.white)

      // Owner + seats
      HStack(spacing: 6) {
        Image(systemName: "lock.fill")
          .font(.system(size: 11))
          .foregroundStyle(.white.opacity(0.5))
        Text(table.ownerUsername)
          .font(SPFonts.caption(13))
          .foregroundStyle(.white.opacity(0.6))
        Text("  \(table.currentPlayers) seats open")
          .font(SPFonts.caption(13))
          .foregroundStyle(.white.opacity(0.6))
      }

      // Join / Resume button
      Button(action: onJoin) {
        Text(table.status == .inProgress ? "Resume Game" : "Join Game")
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(.white)
          .frame(maxWidth: 220)
          .padding(.vertical, 12)
          .background(Color.white.opacity(0.12))
          .clipShape(RoundedRectangle(cornerRadius: SPRadius.md))
          .overlay(
            RoundedRectangle(cornerRadius: SPRadius.md)
              .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
          )
      }
      .buttonStyle(.plain)

      Spacer()
    }
    .frame(maxWidth: .infinity)
    .background(
      ZStack {
        RoundedRectangle(cornerRadius: SPRadius.xl)
          .fill(
            LinearGradient(
              colors: [Color(hex: "#1A2744"), Color(hex: "#0D1525")],
              startPoint: .topLeading, endPoint: .bottomTrailing
            )
          )
        // Subtle blue glow at top
        RoundedRectangle(cornerRadius: SPRadius.xl)
          .fill(
            RadialGradient(
              colors: [Color(hex: "#2563EB").opacity(0.15), Color.clear],
              center: .top,
              startRadius: 20,
              endRadius: 200
            )
          )
        RoundedRectangle(cornerRadius: SPRadius.xl)
          .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
      }
    )
  }
}

// ─── Active Game Card ────────────────────────────────────────────────────────

private struct ActiveGameCard: View {
  let table: TableListItem
  let onJoin: () -> Void

  private var seatProgress: CGFloat {
    guard table.maxPlayers > 0 else { return 0 }
    return CGFloat(table.currentPlayers) / CGFloat(table.maxPlayers)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: SPSpacing.sm) {
      HStack {
        // Game type
        Text(table.gameTypeLabel)
          .font(.system(size: 24, weight: .heavy, design: .rounded))
          .foregroundStyle(.white)

        Spacer()

        // Seat count ring
        ZStack {
          Circle()
            .stroke(Color.white.opacity(0.1), lineWidth: 3)
          Circle()
            .trim(from: 0, to: seatProgress)
            .stroke(Color(hex: "#4A90E2"), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            .rotationEffect(.degrees(-90))
          VStack(spacing: 0) {
            Text("\(table.currentPlayers)/\(table.maxPlayers)")
              .font(.system(size: 11, weight: .bold))
              .foregroundStyle(.white)
            Text("seats")
              .font(.system(size: 8, weight: .medium))
              .foregroundStyle(.white.opacity(0.5))
          }
        }
        .frame(width: 44, height: 44)
      }

      // Blinds
      Text(table.blindsLabel)
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(.white.opacity(0.6))

      Spacer()

      // Owner badge
      HStack(spacing: 4) {
        Image(systemName: table.isPrivate ? "lock.fill" : "globe")
          .font(.system(size: 9))
          .foregroundStyle(.white.opacity(0.5))
        Text(table.ownerUsername)
          .font(SPFonts.caption(11))
          .foregroundStyle(.white.opacity(0.6))
          .lineLimit(1)
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(Color.white.opacity(0.08))
      .clipShape(Capsule())
    }
    .padding(SPSpacing.md)
    .frame(width: 170, height: 160)
    .background(
      RoundedRectangle(cornerRadius: SPRadius.lg)
        .fill(
          LinearGradient(
            colors: [Color(hex: "#1A2744"), Color(hex: "#0F1A2E")],
            startPoint: .topLeading, endPoint: .bottomTrailing
          )
        )
        .overlay(
          RoundedRectangle(cornerRadius: SPRadius.lg)
            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    )
    .onTapGesture(perform: onJoin)
  }
}

// ─── Filter Chip ─────────────────────────────────────────────────────────────

private struct FilterChip: View {
  let label: String
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Text(label)
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(isSelected ? .white : SPColors.textSecondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(isSelected ? Color.white.opacity(0.12) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: SPRadius.md))
        .overlay(
          RoundedRectangle(cornerRadius: SPRadius.md)
            .strokeBorder(isSelected ? Color.white.opacity(0.15) : Color.white.opacity(0.08), lineWidth: 1)
        )
    }
    .buttonStyle(.plain)
  }
}

// ─── Friend Bubble ───────────────────────────────────────────────────────────

private struct FriendBubble: View {
  let friend: Friend

  var body: some View {
    VStack(spacing: 6) {
      ZStack {
        Circle()
          .strokeBorder(
            friend.isOnline ? Color(hex: "#4A90E2") : Color.white.opacity(0.15),
            lineWidth: 2
          )
          .frame(width: 64, height: 64)

        AvatarView(avatarId: friend.avatarId, size: 56)
      }
      Text(friend.username.count > 9 ? String(friend.username.prefix(8)) + "..." : friend.username)
        .font(SPFonts.caption(11))
        .foregroundStyle(SPColors.textSecondary)
        .lineLimit(1)
    }
  }
}

// ─── Rejoin Banner ───────────────────────────────────────────────────────────

struct RejoinBanner: View {
  let tableName: String
  let onRejoin: () -> Void

  var body: some View {
    Button(action: onRejoin) {
      HStack(spacing: SPSpacing.sm) {
        Image(systemName: "arrow.uturn.left.circle.fill")
          .font(.system(size: 18))
          .foregroundStyle(SPColors.accent)
        VStack(alignment: .leading, spacing: 1) {
          Text("Return to table")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(SPColors.textSecondary)
          Text(tableName)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(SPColors.textPrimary)
            .lineLimit(1)
        }
        Spacer()
        Text("Rejoin")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(.white)
          .padding(.horizontal, 12)
          .padding(.vertical, 6)
          .background(SPColors.accent)
          .clipShape(Capsule())
      }
      .padding(.horizontal, SPSpacing.md)
      .padding(.vertical, SPSpacing.sm)
      .background(SPColors.surface)
    }
    .buttonStyle(.plain)
  }
}
