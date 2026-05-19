import SwiftUI

// MAP: LobbyView (retro 60s comic theme)
// - LobbyView .................... main screen, paper bg + halftone
// - lobbyHeader .................. "FOR YOU" speech bubble + chip pill
// - featuredCarousel ............. retro FeaturedTableCard tiles
// - filterPills .................. PokerChip discs w/ retro tints + speech caption
// - activeGamesSection ........... comic-panel ActiveGameCards, fanned
// - friendsSection / groupsSection comic headlines + friend bubbles
// - FeaturedTableCard / ActiveGameCard ... comic-panel card silhouettes
// - FilterDisc / LiveDot / FriendBubble .. small retro primitives
// - InviteFriendsSheet / RejoinBanner .... sheets/banners (kept SPColors-themed
//   until those flows get their own retro pass)

struct LobbyView: View {
  @EnvironmentObject var vm: LobbyViewModel
  @StateObject private var fvm = FriendsViewModel()
  @EnvironmentObject var authVM: AuthViewModel
  // Phase 4b: lobby header shows the hero's equipped avatar frame.
  // CosmeticsContainer is injected at the app root (StackPokerApp) and
  // hands us the local inventory cache that the equip flow keeps in
  // sync with the server.
  @EnvironmentObject var cosmetics: CosmeticsContainer

  @State private var showBuyInSheet:  TableListItem?
  @State private var showFriends      = false
  @State private var showSettings     = false
  @State private var showTopUp        = false
  @State private var buyInInput       = ""
  @State private var featuredPage     = 0

  private var activeTables: [TableListItem] {
    // Show every open table the backend returns. We previously filtered out
    // tables with 0 players, but the server already excludes closed tables
    // and that client-side filter caused freshly-created tables to flash and
    // disappear (the creator is briefly counted as 0 between create→join).
    guard let filter = vm.gameTypeFilter else { return vm.tables }
    return vm.tables.filter { ($0.gameType ?? "TEXAS_HOLDEM") == filter }
  }

  private var featuredTables: [TableListItem] {
    // Show tables with players, or the most recent ones
    let withPlayers = vm.tables.filter { $0.currentPlayers > 0 }
    return withPlayers.isEmpty ? Array(vm.tables.prefix(3)) : Array(withPlayers.prefix(5))
  }

  var body: some View {
    NavigationStack {
      ZStack {
        // ── Page substrate ──────────────────────────────────────────────────
        // Aged cream paper + a low-density halftone overlay. This replaces the
        // previous navy gradient + FeltTexture combo and is the single biggest
        // visual shift — every other element reads as "printed on this page"
        // because of it. The halftone sits OUTSIDE the ScrollView so it stays
        // pinned to the screen (mimics how a real magazine page doesn't slide
        // its print pattern around as you turn the page).
        AgedPaperBackground()
        HalftoneOverlay(density: 44, tint: SPRetro.ink, opacity: 0.08)
          .ignoresSafeArea()

        ScrollView(showsIndicators: false) {
          VStack(spacing: SPSpacing.lg) {
            lobbyHeader
            // Daily bonus banner — sits right under the header so it's the
            // first thing the user sees on app open. Self-contained: handles
            // its own claim/cooldown state and refreshes the chip balance via
            // AuthViewModel on success. Not yet retro-skinned — the card has
            // its own visual treatment we'll revisit in a later pass.
            DailyBonusCard()
            featuredCarousel
            filterPills
            activeGamesSection
            friendsSection
            groupsSection
            Color.clear.frame(height: 80) // tab bar padding
          }
        }
        .refreshable { await vm.loadTables(); await fvm.load() }
        // Tint the pull-to-refresh spinner with the retro maroon (same
        // tone as "TAP A CARD TO SHOW" / Fold CTA). `.tint()` on the
        // ScrollView is the SwiftUI hook that the system UIRefreshControl
        // adopts, so the spinner reads as a printed red stamp on the
        // paper page instead of a generic white indicator.
        .tint(SPRetro.maroon)
      }
      .navigationBarHidden(true)
      .sheet(isPresented: $vm.showCreateSheet)  { CreateTableSheet(vm: vm) }
      .sheet(isPresented: $vm.showJoinCodeSheet) { JoinByCodeSheet(vm: vm) }
      .sheet(isPresented: $vm.showInvitesSheet)  { InvitesSheet(vm: vm) }
      .sheet(item: $showBuyInSheet) { table in
        BuyInSheet(table: table, buyIn: $buyInInput) {
          guard let amount = Int(buyInInput) else { return }
          showBuyInSheet = nil
          Task { await vm.joinTable(table, buyIn: amount, authVM: authVM) }
        }
      }
      .sheet(isPresented: $showFriends) { FriendsSheet(vm: fvm) }
      .sheet(isPresented: $vm.showInviteFriendsSheet) {
        InviteFriendsSheet(vm: vm, fvm: fvm)
      }
      .sheet(isPresented: $showSettings) {
        SettingsSheet().environmentObject(authVM)
      }
      .sheet(isPresented: $showTopUp) {
        ChipStoreSheet().environmentObject(authVM)
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
      .onAppear  {
        vm.onAppear()
        Task { await fvm.load() }
        // Pull a fresh user profile so the chip pill reflects any
        // server-side balance change since the last visit — covers the
        // soft-leave cash-out (Option C) where chips are returned to the
        // wallet the moment the user taps Leave Table.
        Task { await authVM.refreshProfile() }
      }
      .onDisappear { vm.onDisappear() }
    }
  }

  // ─── Header: avatar + "LOBBY" title + chip pill ────────────────────────────

  private var lobbyHeader: some View {
    HStack(alignment: .center, spacing: SPSpacing.sm) {
      // Profile avatar — wrapped in an ink ring so it sits inside the
      // comic-page styling instead of floating loose. Tap → Settings.
      Button { showSettings = true } label: {
        ZStack {
          Circle()
            .fill(SPRetro.paperShade)
          if let user = authVM.currentUser {
            AvatarView(
              avatarId:      user.avatarId,
              size:          40,
              // Hero-facing site: lobby top-bar avatar tile.
              avatarFrameId: cosmetics.inventory.equippedItem(for: .avatarFrame)
            )
          }
        }
        .frame(width: 46, height: 46)
        .overlay(Circle().strokeBorder(SPRetro.ink, lineWidth: 2.5))
        .background(
          Circle().fill(SPRetro.ink).offset(x: 2, y: 2)   // hard ink shadow
        )
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Settings")

      // "LOBBY" headline — uppercased, AmericanTypewriter-Bold so it reads
      // like a comic title strip rather than a UI label. Tap is still
      // Settings (kept the existing affordance from the previous design).
      Button { showSettings = true } label: {
        Text("LOBBY")
          .font(SPRetroFonts.headline(26))
          .foregroundStyle(SPRetro.ink)
          .tracking(1.5)
      }
      .buttonStyle(.plain)

      // Decorative POW! burst — pure visual flourish establishing the comic
      // tone. Tilted so the eye reads it as stamped onto the page rather
      // than placed in a UI slot. Smaller than a hero burst so it shares
      // the header without dominating it.
      ComicBurst(text: "POW!",
                 fill: SPRetro.popRed,
                 textColor: SPRetro.paper,
                 size: 42,
                 rotation: -14)
        .padding(.leading, -4)

      Spacer()

      if authVM.currentUser != nil {
        RetroChipPill(amount: authVM.currentUser?.formattedChips ?? "0") {
          showTopUp = true
        }
        .accessibilityLabel("Buy chips")
      }
    }
    .padding(.horizontal, SPSpacing.md)
    .padding(.top, SPSpacing.sm)
  }

  // ─── Featured game carousel ────────────────────────────────────────────────

  // Pressing "Join" on a card you were already seated at (until you walked
  // away) is really a rejoin — your session is still alive on the server, so
  // we shouldn't ask for another buy-in. Falls through to the regular
  // BuyInSheet flow for any other table.
  private func handleJoinTap(_ table: TableListItem) {
    if vm.lastTable?.id == table.id {
      vm.rejoinTable()
      return
    }
    buyInInput = table.minBuyIn
    showBuyInSheet = table
  }

  private var featuredCarousel: some View {
    VStack(spacing: SPSpacing.sm) {
      if !featuredTables.isEmpty {
        TabView(selection: $featuredPage) {
          ForEach(Array(featuredTables.enumerated()), id: \.element.id) { idx, table in
            // isRejoin: same condition as the active-card row. Featured
            // cards also need the maroon-burst CTA + REJOIN sticker so the
            // user knows tapping JOIN here will skip the buy-in sheet.
            FeaturedTableCard(
              table: table,
              isRejoin: vm.lastTable?.id == table.id
            ) { handleJoinTap(table) }
              .tag(idx)
              .padding(.horizontal, SPSpacing.md)
          }
        }
        .tabViewStyle(.page(indexDisplayMode: .automatic))
        .frame(height: 230)
      } else if vm.isLoadingTables {
        RoundedRectangle(cornerRadius: 10)
          .fill(SPRetro.paperShade)
          .frame(height: 200)
          .padding(.horizontal, SPSpacing.md)
          .shimmer()
      } else {
        // Empty state — paper card calling for "first table". Mustard plus
        // icon + body type. Comic-panel border so the empty slot still
        // belongs to the page.
        VStack(spacing: SPSpacing.md) {
          Image(systemName: "plus.circle.fill")
            .font(.system(size: 40, weight: .bold))
            .foregroundStyle(SPRetro.maroon)
          Text("Create your first table!")
            .font(SPRetroFonts.headline(16))
            .foregroundStyle(SPRetro.ink)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 180)
        .comicPanel(fill: SPRetro.paperShade, corner: 10)
        .padding(.horizontal, SPSpacing.md)
        .padding(.trailing, 4)    // give the hard-ink shadow room
        .onTapGesture { vm.showCreateSheet = true }
      }
    }
  }

  // ─── Filter pills ──────────────────────────────────────────────────────────

  private var filterPills: some View {
    // Game-type chips with retro tints. We keep the PokerChip token-coin so
    // the row still reads as "casino chips" (which is honest — these select
    // the game type), but the caption underneath is now a small speech-bubble
    // tag so the row visually belongs to the comic page.
    HStack(spacing: 22) {
      FilterDisc(
        text: "NLH",
        caption: "Hold'em",
        tint: SPRetro.popRed,
        textColor: SPRetro.paper,
        isSelected: vm.gameTypeFilter == nil || vm.gameTypeFilter == "TEXAS_HOLDEM"
      ) {
        withAnimation(.spring(response: 0.3)) {
          vm.gameTypeFilter = vm.gameTypeFilter == "TEXAS_HOLDEM" ? nil : "TEXAS_HOLDEM"
        }
      }
      FilterDisc(
        text: "SNG",
        caption: "SNG",
        tint: SPRetro.ink,
        textColor: SPRetro.paper,
        isSelected: false
      ) { }
      FilterDisc(
        text: "PLO",
        caption: "PLO4",
        tint: SPRetro.popBlue,
        textColor: SPRetro.paper,
        isSelected: vm.gameTypeFilter == "PLO"
      ) {
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
      HStack(spacing: 10) {
        // Section heading inside a speech bubble so it reads as a comic-panel
        // caption rather than a UI subtitle. The bubble's tail points
        // downward at the row, which subtly tells the eye "these cards
        // belong to this caption".
        SpeechBubble(fill: SPRetro.mustard) {
          Text("ACTIVE GAMES!")
            .font(SPRetroFonts.headline(16))
            .foregroundStyle(SPRetro.ink)
            .tracking(1)
        }
        if !activeTables.isEmpty {
          LiveDot()
        }
        Spacer()
        // Refresh control — kept the constant-size ZStack trick from the
        // previous design (button + overlapping spinner) so the row geometry
        // never reflows mid-refresh. Repainted in ink for the retro palette.
        ZStack {
          Button {
            Task { await vm.loadTables() }
          } label: {
            Image(systemName: "arrow.clockwise")
              .font(.system(size: 13, weight: .heavy))
              .foregroundStyle(SPRetro.ink)
              .opacity(vm.isLoadingTables ? 0 : 1)
              .padding(8)
              .background(SPRetro.paperShade)
              .clipShape(Circle())
              .overlay(Circle().strokeBorder(SPRetro.ink, lineWidth: 1.5))
          }
          .buttonStyle(.plain)
          .disabled(vm.isLoadingTables)

          if vm.isLoadingTables {
            ProgressView()
              .progressViewStyle(.circular)
              .controlSize(.mini)
              .tint(SPRetro.ink)
              .allowsHitTesting(false)
          }
        }
        .frame(width: 36, height: 36)
      }
      .padding(.horizontal, SPSpacing.md)

      // Error surface — kept the same retry affordance but recolored to the
      // retro palette so it doesn't read as a foreign Material-Design alert.
      if let err = vm.tablesError {
        HStack(spacing: 8) {
          Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(SPRetro.maroon)
          Text(err)
            .font(SPRetroFonts.body(13))
            .foregroundStyle(SPRetro.inkSoft)
            .lineLimit(2)
          Spacer()
          Button("Retry") { Task { await vm.loadTables() } }
            .font(SPRetroFonts.callout(13))
            .foregroundStyle(SPRetro.maroon)
        }
        .padding(.horizontal, SPSpacing.md)
        .padding(.vertical, 8)
        .comicPanel(fill: SPRetro.paperShade, corner: 6, lineWidth: 2, shadowOffset: 2)
        .padding(.horizontal, SPSpacing.md)
      }

      if activeTables.isEmpty {
        HStack {
          Spacer()
          VStack(spacing: 6) {
            Text(vm.isLoadingTables ? "Loading tables…" : "No active games")
              .font(SPRetroFonts.body(14))
              .foregroundStyle(SPRetro.inkSoft)
            if !vm.isLoadingTables && vm.tablesError == nil {
              Text("Pull down to refresh")
                .font(SPRetroFonts.body(11))
                .foregroundStyle(SPRetro.inkSoft.opacity(0.7))
            }
          }
          Spacer()
        }
        .frame(height: 100)
      } else {
        ScrollView(.horizontal, showsIndicators: false) {
          // Fanned row of cards: each card gets a tiny alternating tilt so
          // the strip reads as a hand of cards laid out on the page rather
          // than a CSS tile grid. The rotation is small (±2°) — large
          // enough to feel hand-placed, small enough that text stays
          // readable. Vertical pad so rotated corners don't clip against
          // the scroll's vertical bounds.
          HStack(spacing: SPSpacing.sm + 4) {
            ForEach(Array(activeTables.enumerated()), id: \.element.id) { idx, table in
              // isRejoin lights up the maroon border + REJOIN sticker when
              // this card is the user's last-active table — handleJoinTap()
              // already routes that case to vm.rejoinTable() (no buy-in
              // prompt), but without this flag the visual cue was missing.
              ActiveGameCard(table: table, isRejoin: vm.lastTable?.id == table.id) { handleJoinTap(table) }
                .rotationEffect(.degrees(fanAngle(forIndex: idx)))
                .offset(y: idx.isMultiple(of: 2) ? 0 : -2)
            }
          }
          .padding(.horizontal, SPSpacing.md)
          .padding(.vertical, 12)
        }
      }
    }
  }

  private func fanAngle(forIndex idx: Int) -> Double {
    let pattern: [Double] = [-2.0, 1.5, -1.0, 2.0, -1.5, 1.0]
    return pattern[idx % pattern.count]
  }

  // ─── Friends section ───────────────────────────────────────────────────────

  private var friendsSection: some View {
    VStack(alignment: .leading, spacing: SPSpacing.sm) {
      HStack {
        SpeechBubble(fill: SPRetro.popBlue) {
          Text("FRIENDS")
            .font(SPRetroFonts.headline(15))
            .foregroundStyle(SPRetro.paper)
            .tracking(1)
        }
        Spacer()
      }
      .padding(.horizontal, SPSpacing.md)

      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: SPSpacing.md) {
          ForEach(fvm.friends) { friend in
            FriendBubble(friend: friend)
              .onTapGesture {
                if vm.canSendInvites {
                  vm.resetInviteSheet()
                  vm.showInviteFriendsSheet = true
                } else {
                  showFriends = true
                }
              }
          }
          // Invite affordance — mustard ink-bordered circle with a "+". Same
          // tap behavior as before (opens invite sheet if you're seated at a
          // table, otherwise the friends list).
          VStack(spacing: 6) {
            ZStack {
              Circle()
                .fill(vm.canSendInvites ? SPRetro.mustard : SPRetro.paperShade)
              Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 24, weight: .heavy))
                .foregroundStyle(SPRetro.ink)
            }
            .frame(width: 60, height: 60)
            .overlay(Circle().strokeBorder(SPRetro.ink, lineWidth: 2.5))
            .background(Circle().fill(SPRetro.ink).offset(x: 2, y: 2))

            Text("Invite")
              .font(SPRetroFonts.callout(11))
              .foregroundStyle(SPRetro.ink)
          }
          .onTapGesture {
            if vm.canSendInvites {
              vm.resetInviteSheet()
              vm.showInviteFriendsSheet = true
            } else {
              showFriends = true
            }
          }
        }
        .padding(.horizontal, SPSpacing.md)
        .padding(.vertical, 6)
      }
    }
  }

  // ─── Groups section ────────────────────────────────────────────────────────

  private var groupsSection: some View {
    VStack(alignment: .leading, spacing: SPSpacing.sm) {
      HStack {
        SpeechBubble(fill: SPRetro.maroon) {
          Text("GROUPS")
            .font(SPRetroFonts.headline(15))
            .foregroundStyle(SPRetro.paper)
            .tracking(1)
        }
        Spacer()
      }
      .padding(.horizontal, SPSpacing.md)

      HStack {
        Spacer()
        VStack(spacing: 6) {
          Image(systemName: "person.3.fill")
            .font(.system(size: 26, weight: .bold))
            .foregroundStyle(SPRetro.inkSoft.opacity(0.5))
          Text("Join or create a group")
            .font(SPRetroFonts.body(13))
            .foregroundStyle(SPRetro.inkSoft)
        }
        Spacer()
      }
      .frame(height: 90)
      .padding(.horizontal, SPSpacing.md)
    }
  }
}

// ─── Featured Table Card ─────────────────────────────────────────────────────
//
// Reskin of the previous navy-gradient playing-card silhouette. The card now
// reads as a comic-cover panel: paper background, ink-thick border, hard-ink
// offset shadow, mustard "JOIN!" burst-button, maroon corner badge. The
// information hierarchy (blinds, label, seats, button) is preserved from the
// previous design so the muscle memory of returning users still works.

private struct FeaturedTableCard: View {
  let table: TableListItem
  let onJoin: () -> Void
  // Same flag ActiveGameCard uses — true when this is the player's last
  // active table. Drives the maroon-burst CTA + REJOIN sticker so the
  // featured card's "this picks up where you left off" affordance is
  // visible, not just implicit in the button handler.
  var isRejoin: Bool = false

  private var gameCode: String {
    table.gameTypeLabel == "PLO" ? "PL" : "NL"
  }
  private var indexColor: Color {
    table.gameTypeLabel == "PLO" ? SPRetro.popBlue : SPRetro.popRed
  }

  // Featured CTA label + fill swap on rejoin: maroon "REJOIN!" trumps the
  // mustard "JOIN!/RESUME!" so it reads as the higher-affinity action.
  private var ctaLabel: String {
    if isRejoin { return "REJOIN!" }
    return table.status == .inProgress ? "RESUME!" : "JOIN!"
  }
  private var ctaFill: Color { isRejoin ? SPRetro.maroon : SPRetro.mustard }
  private var ctaTextColor: Color { isRejoin ? SPRetro.paper : SPRetro.ink }

  var body: some View {
    ZStack {
      // ── Card face ─────────────────────────────────────────────────────────
      // Paper fill, then a soft wash of the game-type color (red for NLH,
      // blue for PLO) so the card visually echoes the chip pill above it
      // and reads as "filled in" instead of just an empty paper slot. The
      // halftone dots also swap tint to the same color, which keeps the
      // wash from looking like a flat overlay — the dots and the wash blend
      // into one coherent printed-page treatment.
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(SPRetro.paper)
        .overlay(
          indexColor.opacity(0.16)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        )
        .overlay(
          HalftoneOverlay(density: 28, tint: indexColor, opacity: 0.18)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        )

      // ── Corner badge ─────────────────────────────────────────────────────
      // Comic-style maroon/blue "NL"/"PL" tag in the top-left — replaces the
      // previous gold-on-navy corner index. Reads as a stamped issue badge.
      VStack {
        HStack {
          CornerIndex(code: gameCode, badgeColor: indexColor)
          Spacer()
        }
        Spacer()
      }
      .padding(12)

      // ── Center copy ───────────────────────────────────────────────────────
      VStack(spacing: 8) {
        Text(table.blindsLabel)
          .font(SPRetroFonts.body(13))
          .foregroundStyle(SPRetro.inkSoft)
        Text(table.gameTypeLabel == "PLO" ? "POT LIMIT OMAHA" : "NO LIMIT HOLD'EM")
          .font(SPRetroFonts.headline(20))
          .foregroundStyle(SPRetro.ink)
          .tracking(1)
          .lineLimit(1)
          .minimumScaleFactor(0.6)
        HStack(spacing: 6) {
          Image(systemName: "lock.fill")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(SPRetro.inkSoft)
          Text(table.ownerUsername)
            .font(SPRetroFonts.body(12))
            .foregroundStyle(SPRetro.inkSoft)
            .lineLimit(1)
          Text("·").foregroundStyle(SPRetro.inkSoft.opacity(0.6))
          Text("\(table.currentPlayers) seats")
            .font(SPRetroFonts.body(12))
            .foregroundStyle(SPRetro.inkSoft)
        }

        // Join / Resume button — comic-burst CTA on mustard so it reads as
        // the primary "punch the button" action on the page. Hard ink border
        // + offset shadow ties it to the rest of the comic-panel system.
        // On rejoin, the fill flips to maroon and the label becomes "REJOIN!"
        // so the user can SEE this isn't a fresh buy-in.
        Button(action: onJoin) {
          Text(ctaLabel)
            .font(SPRetroFonts.display(18))
            .foregroundStyle(ctaTextColor)
            .tracking(1.5)
            .padding(.horizontal, 28)
            .padding(.vertical, 10)
            .comicPanel(fill: ctaFill, corner: 22, lineWidth: 2.5, shadowOffset: 3)
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
      }
      .padding(.horizontal, 36)
    }
    .frame(maxWidth: .infinity)
    .frame(height: 210)
    .overlay(
      // Border switches to maroon on rejoin so the featured slot reads as
      // "this is YOUR table" the moment you open the lobby.
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .strokeBorder(isRejoin ? SPRetro.maroon : SPRetro.ink, lineWidth: 3)
    )
    .overlay(alignment: .topTrailing) {
      // REJOIN sticker — mirrors the one on ActiveGameCard so users see the
      // same affordance whether the table sits in the featured slot or in
      // the active row. Rotated + offset shadow plate so it reads as a
      // physical sticker, not a UI label.
      if isRejoin {
        ZStack {
          Capsule()
            .fill(SPRetro.ink)
            .offset(x: 1.5, y: 2)
          Capsule()
            .fill(SPRetro.maroon)
            .overlay(Capsule().strokeBorder(SPRetro.ink, lineWidth: 1.5))
        }
        .frame(width: 72, height: 24)
        .overlay(
          Text("REJOIN")
            .font(SPRetroFonts.headline(11))
            .foregroundStyle(SPRetro.paper)
            .tracking(1.3)
        )
        .rotationEffect(.degrees(8))
        .offset(x: 10, y: -12)
      }
    }
    .background(
      // Hard ink offset shadow — gives the comic-page punch where a blurred
      // shadow would feel UI-y. Sits behind the entire card.
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(SPRetro.ink)
        .offset(x: 5, y: 5)
    )
  }
}

// Reusable corner badge for the featured + active cards. Now a real
// rounded-square "issue stamp" with ink border, not just text + a dot.
private struct CornerIndex: View {
  let code:        String
  let badgeColor:  Color

  var body: some View {
    Text(code)
      .font(SPRetroFonts.display(14))
      .foregroundStyle(SPRetro.paper)
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(badgeColor)
      .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 4, style: .continuous)
          .strokeBorder(SPRetro.ink, lineWidth: 1.5)
      )
  }
}

// ─── Active Game Card ────────────────────────────────────────────────────────
//
// Smaller comic-panel sibling of FeaturedTableCard for the horizontal scroller.
// Same visual language: paper bg, ink border, hard offset shadow, maroon/blue
// corner badge. Seat-fill ring uses ink stroke + mustard progress so the
// "how full is this table" cue still reads at a glance.

private struct ActiveGameCard: View {
  let table: TableListItem
  let onJoin: () -> Void
  // True when this card refers to a table the player previously seated at
  // and walked away from. The server still has their seat + stack, so
  // tapping JOIN here actually rejoins (no buy-in prompt). We change the
  // visual treatment so the user can SEE this is a rejoin, not a fresh
  // buy-in — maroon border + a "REJOIN" sticker stamp in the corner.
  var isRejoin: Bool = false

  private var seatProgress: CGFloat {
    guard table.maxPlayers > 0 else { return 0 }
    return CGFloat(table.currentPlayers) / CGFloat(table.maxPlayers)
  }

  private var gameCode: String {
    table.gameTypeLabel == "PLO" ? "PL" : "NL"
  }
  private var indexColor: Color {
    table.gameTypeLabel == "PLO" ? SPRetro.popBlue : SPRetro.popRed
  }

  var body: some View {
    ZStack(alignment: .topLeading) {
      // Card face — same paper + game-type-tinted wash + halftone treatment
      // as FeaturedTableCard so the active-row cards read as "filled in"
      // and color-match the chip pill above them (red = NLH, blue = PLO).
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(SPRetro.paper)
        .overlay(
          indexColor.opacity(0.16)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        )
        .overlay(
          HalftoneOverlay(density: 22, tint: indexColor, opacity: 0.15)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        )

      // ── Foreground content ──────────────────────────────────────────────
      VStack(alignment: .leading, spacing: SPSpacing.sm) {
        HStack(alignment: .top) {
          CornerIndex(code: gameCode, badgeColor: indexColor)

          Spacer()

          // Seat-fill ring — ink track + mustard progress so the indicator
          // matches the rest of the comic-page palette while still reading
          // as "how full is the table" at a glance.
          ZStack {
            Circle()
              .stroke(SPRetro.inkSoft.opacity(0.25), lineWidth: 3)
            Circle()
              .trim(from: 0, to: seatProgress)
              .stroke(SPRetro.mustard,
                      style: StrokeStyle(lineWidth: 3, lineCap: .round))
              .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
              Text("\(table.currentPlayers)/\(table.maxPlayers)")
                .font(SPRetroFonts.headline(11))
                .foregroundStyle(SPRetro.ink)
              Text("seats")
                .font(SPRetroFonts.body(8))
                .foregroundStyle(SPRetro.inkSoft)
            }
          }
          .frame(width: 44, height: 44)
        }

        Spacer(minLength: 0)

        Text(table.blindsLabel)
          .font(SPRetroFonts.display(18))
          .foregroundStyle(SPRetro.ink)

        // Owner / privacy badge — mustard pill with ink border. Reads as a
        // little "by-line" stamp at the foot of the card.
        HStack(spacing: 4) {
          Image(systemName: table.isPrivate ? "lock.fill" : "globe")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(SPRetro.ink)
          Text(table.ownerUsername)
            .font(SPRetroFonts.callout(11))
            .foregroundStyle(SPRetro.ink)
            .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(SPRetro.mustard)
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(SPRetro.ink, lineWidth: 1.5))
      }
      .padding(SPSpacing.md)
    }
    .frame(width: 180, height: 170)
    .overlay(
      // Border is maroon on rejoin tables so the card visually pops out
      // of the row at a glance; otherwise standard ink.
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .strokeBorder(isRejoin ? SPRetro.maroon : SPRetro.ink, lineWidth: 3)
    )
    .overlay(alignment: .topTrailing) {
      // REJOIN sticker stamp — slightly rotated maroon pill with ink
      // border and a hard ink offset shadow. Only renders when this is
      // the user's last-active table. Designed to feel like a vintage
      // "FRAGILE" or "RUSH" sticker slapped onto the card corner.
      if isRejoin {
        ZStack {
          Capsule()
            .fill(SPRetro.ink)
            .offset(x: 1.5, y: 2)
          Capsule()
            .fill(SPRetro.maroon)
            .overlay(Capsule().strokeBorder(SPRetro.ink, lineWidth: 1.5))
        }
        .frame(width: 64, height: 22)
        .overlay(
          Text("REJOIN")
            .font(SPRetroFonts.headline(10))
            .foregroundStyle(SPRetro.paper)
            .tracking(1.2)
        )
        .rotationEffect(.degrees(8))
        .offset(x: 8, y: -10)
      }
    }
    .background(
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(SPRetro.ink)
        .offset(x: 4, y: 4)
    )
    .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    .onTapGesture(perform: onJoin)
  }
}

// ─── Filter Disc ─────────────────────────────────────────────────────────────
//
// PokerChip token-coin in retro tints + a caption. Selected state still drives
// saturation/opacity, but the selection ring is now ink-thick to match the
// rest of the comic-panel system.

private struct FilterDisc: View {
  let text: String
  let caption: String
  let tint: Color
  let textColor: Color
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(spacing: 6) {
        PokerChip(
          text: text,
          tint: tint,
          textColor: textColor,
          size: 46
        )
        .saturation(isSelected ? 1.0 : 0.55)
        .opacity(isSelected ? 1.0 : 0.6)
        .overlay(
          Circle()
            .stroke(SPRetro.ink, lineWidth: isSelected ? 2.5 : 1.5)
        )
        .background(
          // Hard ink shadow — only when selected, since this is the same
          // pattern we use for "primary tappable thing" elsewhere on the
          // page (chip pill, join button, friend invite circle).
          Circle()
            .fill(SPRetro.ink)
            .offset(x: 2, y: 2)
            .opacity(isSelected ? 1 : 0)
        )

        Text(caption)
          .font(SPRetroFonts.callout(11))
          .foregroundStyle(isSelected ? SPRetro.ink : SPRetro.inkSoft.opacity(0.6))
          .tracking(0.6)
      }
    }
    .buttonStyle(.plain)
  }
}

// ─── Live Dot ────────────────────────────────────────────────────────────────
//
// Small pulsing pop-red indicator next to the active games caption.
// Now ink-bordered so it reads as part of the comic-panel system.

private struct LiveDot: View {
  @State private var pulse = false

  var body: some View {
    ZStack {
      Circle()
        .fill(SPRetro.popRed.opacity(0.35))
        .frame(width: 16, height: 16)
        .scaleEffect(pulse ? 1.4 : 0.8)
        .opacity(pulse ? 0.0 : 0.7)
      Circle()
        .fill(SPRetro.popRed)
        .frame(width: 10, height: 10)
        .overlay(Circle().strokeBorder(SPRetro.ink, lineWidth: 1.5))
    }
    .onAppear {
      withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) {
        pulse = true
      }
    }
    .accessibilityHidden(true)
  }
}

// ─── Friend Bubble ───────────────────────────────────────────────────────────
//
// Avatar inside an ink ring with a hard offset shadow. Online state colors the
// outer ring mustard (the "look here, they're up") instead of blue so the
// online cue follows the rest of the retro palette.

private struct FriendBubble: View {
  let friend: Friend

  var body: some View {
    VStack(spacing: 6) {
      ZStack {
        Circle()
          .fill(friend.isOnline ? SPRetro.mustard : SPRetro.paperShade)
        AvatarView(avatarId: friend.avatarId, size: 52)
      }
      .frame(width: 64, height: 64)
      .overlay(Circle().strokeBorder(SPRetro.ink, lineWidth: 2.5))
      .background(Circle().fill(SPRetro.ink).offset(x: 2, y: 2))

      Text(friend.username.count > 9 ? String(friend.username.prefix(8)) + "..." : friend.username)
        .font(SPRetroFonts.callout(11))
        .foregroundStyle(SPRetro.ink)
        .lineLimit(1)
    }
  }
}

// ─── Invite Friends Sheet ────────────────────────────────────────────────────
// Lists the user's friends with an "Invite" button per row that posts to
// `/tables/:id/invite` for the user's most-recent table. Tapped friends flip
// to "Invited" and stay there for the lifetime of the sheet so the user
// doesn't accidentally double-invite. A toast banner surfaces server errors.
//
// NOTE: Kept on the dark `SPColors` palette for now — this sheet is part of
// the "table flow" surface that hasn't been retro'd yet. Will get its own
// retro pass when we revisit the in-game flows.

struct InviteFriendsSheet: View {
  @ObservedObject var vm: LobbyViewModel
  @ObservedObject var fvm: FriendsViewModel
  @Environment(\.dismiss) private var dismiss

  var onlineOnly: Bool = false
  var onAddBot: (() -> Void)? = nil
  var addBotDisabled: Bool = false

  private var visibleFriends: [Friend] {
    onlineOnly ? fvm.friends.filter { $0.isOnline } : fvm.friends
  }

  var body: some View {
    NavigationStack {
      ZStack(alignment: .top) {
        SPColors.background.ignoresSafeArea()

        VStack(spacing: 0) {
          if let table = vm.lastTable {
            HStack(spacing: SPSpacing.sm) {
              Image(systemName: "person.2.fill")
                .font(.system(size: 14))
                .foregroundStyle(SPColors.accent)
              VStack(alignment: .leading, spacing: 2) {
                Text("Inviting to")
                  .font(SPFonts.caption(11))
                  .foregroundStyle(SPColors.textTertiary)
                Text(table.name)
                  .font(SPFonts.headline(14))
                  .foregroundStyle(SPColors.textPrimary)
                  .lineLimit(1)
              }
              Spacer()
              Text("Code: \(table.joinCode)")
                .font(SPFonts.caption(11))
                .foregroundStyle(SPColors.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(SPColors.surfaceElevated)
                .clipShape(Capsule())
            }
            .padding(.horizontal, SPSpacing.md)
            .padding(.vertical, SPSpacing.sm)
            .background(SPColors.surface)

            SPDivider()
          }

          if let onAddBot {
            Button {
              if !addBotDisabled { onAddBot() }
            } label: {
              HStack(spacing: SPSpacing.md) {
                ZStack {
                  Circle()
                    .fill(SPColors.surfaceElevated)
                    .frame(width: 44, height: 44)
                  Image(systemName: "cpu")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(addBotDisabled ? SPColors.textTertiary : SPColors.accent)
                }
                VStack(alignment: .leading, spacing: 3) {
                  Text("Add Bot Player")
                    .font(SPFonts.headline(14))
                    .foregroundStyle(addBotDisabled ? SPColors.textTertiary : SPColors.textPrimary)
                  Text(addBotDisabled
                       ? "The table is full"
                       : "Fill this seat with a bot")
                    .font(SPFonts.caption(12))
                    .foregroundStyle(SPColors.textTertiary)
                }
                Spacer()
                if !addBotDisabled {
                  Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SPColors.textTertiary)
                }
              }
              .padding(.horizontal, SPSpacing.md)
              .padding(.vertical, SPSpacing.sm + 2)
            }
            .buttonStyle(.plain)
            .disabled(addBotDisabled)
            SPDivider()
          }

          if visibleFriends.isEmpty {
            VStack(spacing: SPSpacing.md) {
              Spacer()
              Image(systemName: "person.2.slash")
                .font(.system(size: 40))
                .foregroundStyle(SPColors.textTertiary)
              if fvm.friends.isEmpty {
                Text("No friends to invite yet")
                  .font(SPFonts.body())
                  .foregroundStyle(SPColors.textSecondary)
                Text("Add friends from the Friends tab first")
                  .font(SPFonts.caption(12))
                  .foregroundStyle(SPColors.textTertiary)
              } else {
                Text("No friends online right now")
                  .font(SPFonts.body())
                  .foregroundStyle(SPColors.textSecondary)
                Text("Try again later or invite someone via share link")
                  .font(SPFonts.caption(12))
                  .foregroundStyle(SPColors.textTertiary)
              }
              Spacer()
            }
            .frame(maxWidth: .infinity)
          } else {
            ScrollView(showsIndicators: false) {
              LazyVStack(spacing: 0) {
                ForEach(visibleFriends) { friend in
                  InviteFriendRow(friend: friend, vm: vm)
                  if friend.id != visibleFriends.last?.id {
                    SPDivider().padding(.leading, 68)
                  }
                }
              }
              .padding(.bottom, 60)
            }
          }
        }

        if let toast = vm.inviteToast {
          Text(toast)
            .font(SPFonts.body(13))
            .foregroundStyle(.white)
            .padding(.horizontal, SPSpacing.md)
            .padding(.vertical, SPSpacing.sm)
            .background(SPColors.surfaceElevated)
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(SPColors.accent.opacity(0.4), lineWidth: 1))
            .padding(.top, SPSpacing.md)
            .transition(.move(edge: .top).combined(with: .opacity))
            .onAppear {
              Task {
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                withAnimation { vm.inviteToast = nil }
              }
            }
        }
      }
      .animation(.spring(response: 0.4), value: vm.inviteToast)
      .navigationTitle("Invite Friends")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Done") { dismiss() }
            .foregroundStyle(SPColors.accent)
        }
      }
    }
    .presentationDetents([.large])
    .presentationDragIndicator(.visible)
    .presentationBackground(SPColors.background)
    .task { await fvm.loadFriends() }
  }
}

private struct InviteFriendRow: View {
  let friend: Friend
  @ObservedObject var vm: LobbyViewModel

  private var isInvited: Bool { vm.invitedFriendIds.contains(friend.userId) }

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
        Text("@\(friend.username)")
          .font(SPFonts.caption(12))
          .foregroundStyle(SPColors.textTertiary)
      }

      Spacer()

      if isInvited {
        Label("Invited", systemImage: "checkmark.circle.fill")
          .font(SPFonts.caption(12))
          .foregroundStyle(SPColors.success)
          .padding(.horizontal, 10)
          .padding(.vertical, 6)
          .background(SPColors.success.opacity(0.12))
          .clipShape(Capsule())
      } else {
        Button {
          Task {
            await vm.inviteFriend(userId: friend.userId, username: friend.username)
          }
        } label: {
          Text("Invite")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(SPColors.accent)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
      }
    }
    .padding(.horizontal, SPSpacing.md)
    .padding(.vertical, SPSpacing.sm + 2)
  }
}

// ─── Rejoin Banner ───────────────────────────────────────────────────────────
//
// Reskinned to the retro palette since this banner appears AT the top of the
// lobby (safeAreaInset) — leaving it dark would create a jarring stripe across
// the cream page.

struct RejoinBanner: View {
  let tableName: String
  let onRejoin: () -> Void

  var body: some View {
    Button(action: onRejoin) {
      HStack(spacing: SPSpacing.sm) {
        Image(systemName: "arrow.uturn.left.circle.fill")
          .font(.system(size: 20, weight: .heavy))
          .foregroundStyle(SPRetro.maroon)
        VStack(alignment: .leading, spacing: 1) {
          Text("Return to table")
            .font(SPRetroFonts.callout(11))
            .foregroundStyle(SPRetro.inkSoft)
          Text(tableName)
            .font(SPRetroFonts.headline(14))
            .foregroundStyle(SPRetro.ink)
            .lineLimit(1)
        }
        Spacer()
        Text("REJOIN!")
          .font(SPRetroFonts.display(13))
          .foregroundStyle(SPRetro.ink)
          .tracking(1)
          .padding(.horizontal, 12)
          .padding(.vertical, 6)
          .background(SPRetro.mustard)
          .clipShape(Capsule())
          .overlay(Capsule().strokeBorder(SPRetro.ink, lineWidth: 2))
      }
      .padding(.horizontal, SPSpacing.md)
      .padding(.vertical, SPSpacing.sm)
      .background(SPRetro.paperShade)
      .overlay(
        Rectangle().frame(height: 2).foregroundStyle(SPRetro.ink),
        alignment: .bottom
      )
    }
    .buttonStyle(.plain)
  }
}
