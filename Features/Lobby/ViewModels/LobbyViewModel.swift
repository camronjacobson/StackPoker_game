import SwiftUI
import Combine

// ─── Table-scoped client preferences ──────────────────────────────────────────
// Server-side, all tables allow bots. The "allow bots?" choice is local —
// it's the creator opting in/out at create time. Stored in UserDefaults so
// GameView/PokerTableView can hide bot UI for tables created with the toggle
// off. For tables we joined (no preference recorded), default to true so we
// preserve existing behavior.
enum TablePreferences {
  static func setBotsAllowed(_ allowed: Bool, forTableId id: String) {
    UserDefaults.standard.set(allowed, forKey: "botsAllowed_\(id)")
  }

  static func botsAllowed(forTableId id: String) -> Bool {
    if let raw = UserDefaults.standard.object(forKey: "botsAllowed_\(id)") as? Bool {
      return raw
    }
    return true
  }
}

@MainActor
final class LobbyViewModel: ObservableObject {

  // ─── Tables ────────────────────────────────────────────────────────────────

  @Published var tables: [TableListItem] = []
  @Published var isLoadingTables = false
  // Flips true after the *first* successful fetch. Used to suppress the
  // `isLoadingTables = true` flicker on background polls — without this,
  // every 5s poll on an empty lobby would briefly show "Loading…" and
  // swap the featured-carousel placeholder height (180 → 200 → 180),
  // making the whole screen visibly bounce.
  private var hasFetchedTables = false
  @Published var tablesError: String?
  @Published var selectedTable: TableDetail?

  // ─── Join flow ─────────────────────────────────────────────────────────────

  @Published var joinCode    = ""
  @Published var buyInAmount = ""
  @Published var isJoining   = false
  @Published var joinError: String?
  @Published var joinedTable: TableDetail?   // triggers navigation to game
  @Published var lastTable:   TableDetail?   // cached for quick rejoin

  // ─── Create flow ───────────────────────────────────────────────────────────

  @Published var showCreateSheet   = false
  @Published var showJoinCodeSheet = false
  @Published var showInvitesSheet  = false
  @Published var isCreating        = false
  @Published var createError: String?

  // Create form
  @Published var newTableName     = ""
  @Published var selectedPreset   = BlindPreset.presets[0]
  @Published var customSmallBlind = ""
  @Published var customBigBlind   = ""
  @Published var customMinBuyIn   = ""
  @Published var customMaxBuyIn   = ""
  @Published var newMaxPlayers    = 6
  // Default to public so other users can see the table in the lobby list.
  // Backend's `listTables` filters out isPrivate=true tables by design — they
  // only show up to invitees. Players who want a private table can flip the
  // toggle in CreateTableSheet.
  @Published var newIsPrivate     = false
  @Published var newGameType      = "TEXAS_HOLDEM"   // or "PLO"
  // Opt-in bot at creation. Off by default so a fresh table waits for real
  // players unless the creator explicitly wants company.
  @Published var addBotOnCreate   = false

  // ─── Game type filter ──────────────────────────────────────────────────────

  @Published var gameTypeFilter: String? = nil   // nil = all

  // ─── Invites ───────────────────────────────────────────────────────────────

  @Published var pendingInvites: [TableInvite] = []
  @Published var inviteBadgeCount = 0

  // Outgoing-invite state for the lobby's "Invite friends" sheet.
  @Published var showInviteFriendsSheet = false
  @Published var invitedFriendIds: Set<String> = []   // friendUserIds we've already sent
  @Published var inviteToast: String?                 // success/error banner

  // ─── Active filter ─────────────────────────────────────────────────────────

  @Published var statusFilter: TableStatus = .waiting

  private let network = NetworkService.shared
  private var pollTask: Task<Void, Never>?

  // ─── Lifecycle ─────────────────────────────────────────────────────────────

  func onAppear() {
    Task { await loadTables() }
    Task { await loadInvites() }
    startPolling()
  }

  func onDisappear() {
    pollTask?.cancel()
  }

  private func startPolling() {
    pollTask?.cancel()
    pollTask = Task {
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: 5_000_000_000) // 5s — snappier so a new table on Phone A shows up on Phone B quickly
        guard !Task.isCancelled else { return }
        await loadTables()
        await loadInvites()
        // Also re-validate the rejoin banner's target table. The lobby's
        // /tables endpoint filters to (status=WAITING, isPrivate=false),
        // so it won't tell us whether the user's IN_PROGRESS or private
        // table still exists. The dedicated detail probe handles closed
        // tables / 404s / private-table membership checks server-side.
        await refreshLastTable()
      }
    }
  }

  // ─── Rejoin-target validation ──────────────────────────────────────────────
  // Called from the polling loop to keep the top-of-lobby rejoin banner
  // honest. The banner is gated on `lastTable != nil`, but `lastTable`
  // used to be set on join/create and *never cleared*, so after the
  // table closed (owner closed it, server reaped it, etc.) the banner
  // would persist and tapping it would route the user into a dead
  // table. We re-fetch the table detail; if the table is gone, marked
  // CLOSED, or the user is no longer in its active players list, we
  // drop `lastTable` so the banner disappears on the next render.
  //
  // We deliberately do NOT clear `lastTable` for status==PAUSED or
  // IN_PROGRESS even with stack==0 — busted players are parked at
  // SITTING_OUT and can still rejoin to top up. Only true unreachable
  // states clear the banner.
  private func refreshLastTable() async {
    guard let cached = lastTable else { return }
    do {
      let detail: TableDetail = try await network.request(
        .tableDetail(id: cached.id), method: .GET
      )
      // Table got closed — drop the rejoin target.
      if detail.status == .closed {
        lastTable = nil
        return
      }
      // User is no longer seated with an active session (e.g. server
      // reaped them, or they were kicked). `players` reflects
      // tableSession rows with isActive=true; absence here means rejoin
      // would 4xx.
      let userId = KeychainManager.shared.userId ?? ""
      let stillSeated = detail.players.contains { $0.userId == userId && $0.isActive }
      if !stillSeated {
        lastTable = nil
        return
      }
      // Otherwise refresh the cache with the latest detail so the
      // banner shows the current table name / blinds.
      lastTable = detail
    } catch let err as NetworkError {
      // Treat NOT_FOUND / FORBIDDEN as "table is gone for this user" and
      // drop the rejoin target. Transient network failures (timeouts,
      // 5xx) keep the cache so a single bad poll doesn't hide a still-
      // valid banner.
      switch err {
      case .notFound:
        lastTable = nil
      case .serverError(let code, _) where code == "NOT_FOUND" || code == "FORBIDDEN":
        lastTable = nil
      default:
        break
      }
    } catch {
      // Unknown error type — leave the cache alone.
    }
  }

  // ─── Load Tables ───────────────────────────────────────────────────────────

  func loadTables() async {
    // Only show the "Loading…" placeholder on the *initial* fetch when the
    // list is still empty. Background polls (every 5s) would otherwise
    // toggle isLoadingTables true→false and bounce the featured-carousel
    // placeholder height (180→200→180), making the whole lobby jump.
    if !hasFetchedTables && tables.isEmpty {
      isLoadingTables = true
    }
    tablesError = nil
    do {
      let response: TableListResponse = try await network.request(
        .tables, method: .GET
      )
      tables = response.tables
      hasFetchedTables = true
    } catch let err as NetworkError {
      // Don't surface a banner for *transient* refresh failures when we
      // already have a cached list of tables to show. The 5s background
      // poll (LobbyViewModel.startPolling at L113) and pull-to-refresh
      // both call this; one blip on either path used to flash a red
      // "Server Error" banner over a perfectly usable lobby, which is the
      // bug the user hit on 2026-05-13. We still surface the error on the
      // *initial* load (when there's nothing to fall back to) so the user
      // gets the Retry button and isn't staring at an empty screen.
      if tables.isEmpty {
        tablesError = err.localizedDescription
      }
      // Else: silently drop. The next successful poll will refresh data
      // and `tablesError = nil` at the top of this function will keep the
      // banner cleared even if a future call partially fails.
    } catch {}
    isLoadingTables = false
  }

  // ─── Join by Code ──────────────────────────────────────────────────────────

  func joinByCode() async {
    let code = joinCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    guard !code.isEmpty else { joinError = "Enter a join code"; return }

    guard let amount = Int(buyInAmount), amount > 0 else {
      joinError = "Enter a valid buy-in amount"
      return
    }

    isJoining = true
    joinError = nil

    do {
      let table: TableDetail = try await network.request(
        .joinTable(code: code),
        method: .POST,
        body: JoinTableRequest(buyInAmount: amount, seatIndex: nil)
      )
      showJoinCodeSheet = false
      joinCode = ""
      buyInAmount = ""
      lastTable   = table
      joinedTable = table
    } catch let err as NetworkError {
      joinError = err.localizedDescription
    } catch {}

    isJoining = false
  }

  // ─── Join by ID (from list) ────────────────────────────────────────────────

  func joinTable(_ table: TableListItem, buyIn: Int) async {
    isJoining = true
    joinError = nil

    do {
      let detail: TableDetail = try await network.request(
        .joinTable(code: table.joinCode),
        method: .POST,
        body: JoinTableRequest(buyInAmount: buyIn, seatIndex: nil)
      )
      lastTable   = detail
      joinedTable = detail
    } catch let err as NetworkError {
      joinError = err.localizedDescription
    } catch {}

    isJoining = false
  }

  // ─── Create Table ──────────────────────────────────────────────────────────

  func createTable() async {
    guard validateCreateForm() else { return }

    isCreating = true
    createError = nil

    let sb = selectedPreset.label == "Custom" ? Int(customSmallBlind) ?? 0 : selectedPreset.smallBlind
    let bb = selectedPreset.label == "Custom" ? Int(customBigBlind) ?? 0  : selectedPreset.bigBlind
    let min = selectedPreset.label == "Custom" ? Int(customMinBuyIn) ?? 0 : selectedPreset.defaultMinBuyIn
    let max = selectedPreset.label == "Custom" ? Int(customMaxBuyIn) ?? 0 : selectedPreset.defaultMaxBuyIn

    let req = CreateTableRequest(
      name: newTableName.trimmingCharacters(in: .whitespaces),
      maxPlayers: newMaxPlayers,
      smallBlind: sb,
      bigBlind: bb,
      minBuyIn: min,
      maxBuyIn: max,
      isPrivate: newIsPrivate,
      clubId: nil,
      gameType: newGameType
    )

    do {
      // Step 1: create the table
      let table: TableDetail = try await network.request(
        .createTable, method: .POST, body: req
      )

      // Step 2: seat the creator — table creation doesn't auto-seat the owner
      let _: TableDetail = try await network.request(
        .joinTable(code: table.joinCode),
        method: .POST,
        body: JoinTableRequest(buyInAmount: min, seatIndex: nil)
      )

      // Persist the creator's bot preference so the game screen knows whether
      // to surface bot UI later. We don't have a server-side `allowBots`
      // field — this lives in UserDefaults keyed by table id and is read by
      // GameView / PokerTableView via `TablePreferences.botsAllowed(for:)`.
      TablePreferences.setBotsAllowed(addBotOnCreate, forTableId: table.id)

      // Step 3 (optional): add a bot opponent if the creator opted in. Failure
      // here is non-fatal — the table is already up, the user can add a bot
      // manually from the waiting room.
      if addBotOnCreate {
        struct AddBotResponse: Decodable { let message: String? }
        let _: AddBotResponse? = try? await network.request(
          .addBot(tableId: table.id),
          method: .POST
        )
      }

      showCreateSheet = false
      resetCreateForm()
      lastTable   = table
      joinedTable = table
    } catch let err as NetworkError {
      createError = err.localizedDescription
    } catch {}

    isCreating = false
  }

  // ─── Invites ───────────────────────────────────────────────────────────────

  func loadInvites() async {
    do {
      let response: InvitesResponse = try await network.request(.tableInvites)
      pendingInvites = response.invites
      inviteBadgeCount = response.invites.count
    } catch {}
  }

  func respondToInvite(_ invite: TableInvite, accept: Bool) async {
    do {
      struct RespondBody: Encodable { let accept: Bool }
      struct RespondResponse: Decodable { let joinCode: String? }
      let response: RespondResponse = try await network.request(
        .respondInvite(id: invite.id),
        method: .POST,
        body: RespondBody(accept: accept)
      )
      pendingInvites.removeAll { $0.id == invite.id }
      inviteBadgeCount = pendingInvites.count

      if accept, let code = response.joinCode {
        // Auto-join: use the invite table's minimum buy-in
        let minBuyIn = Int(invite.table.smallBlind) ?? 0
        isJoining = true
        joinError = nil
        do {
          let detail: TableDetail = try await network.request(
            .joinTable(code: code),
            method: .POST,
            body: JoinTableRequest(buyInAmount: minBuyIn > 0 ? minBuyIn * 20 : 1000, seatIndex: nil)
          )
          lastTable = detail
          joinedTable = detail
        } catch let err as NetworkError {
          joinError = err.localizedDescription
        } catch {}
        isJoining = false
      }
    } catch {}
  }

  // ─── Send Invite ───────────────────────────────────────────────────────────
  // Invite a friend to the user's most-recently-joined table. We use
  // `lastTable` rather than `joinedTable` so the user can dismiss the game
  // screen, open the lobby, and still send invites to the table they're in.

  /// True when there's a table we can send invites to.
  var canSendInvites: Bool { lastTable != nil }

  /// Send an invite for the given friend's userId. Idempotent on the client —
  /// repeat taps are no-ops once an invite has been recorded for that friend.
  func inviteFriend(userId: String, username: String) async {
    guard let tableId = lastTable?.id else {
      inviteToast = "Create or join a table first to invite friends"
      return
    }
    guard !invitedFriendIds.contains(userId) else { return }

    struct InviteBody: Encodable { let recipientId: String }
    struct InviteResponse: Decodable { let message: String? }

    do {
      let _: InviteResponse = try await network.request(
        .sendInvite(tableId: tableId),
        method: .POST,
        body: InviteBody(recipientId: userId)
      )
      invitedFriendIds.insert(userId)
      inviteToast = "Invite sent to \(username)"
    } catch let err as NetworkError {
      // Server already has logic for "INVITE_EXISTS"; surface that as a soft
      // success so the UI still flips to "Invited".
      if case .serverError(let code, _) = err, code == "INVITE_EXISTS" {
        invitedFriendIds.insert(userId)
        inviteToast = "Already invited \(username)"
      } else {
        inviteToast = err.localizedDescription
      }
    } catch {
      inviteToast = "Couldn't send invite. Try again."
    }
  }

  /// Called when the invite sheet opens — clears stale state so a new table
  /// session starts fresh (different table = different "already invited" set).
  func resetInviteSheet() {
    invitedFriendIds.removeAll()
    inviteToast = nil
  }

  // ─── Rejoin ────────────────────────────────────────────────────────────────

  func rejoinTable() {
    guard let table = lastTable else { return }
    joinedTable = table
  }

  // ─── Helpers ───────────────────────────────────────────────────────────────

  private func validateCreateForm() -> Bool {
    createError = nil
    if newTableName.trimmingCharacters(in: .whitespaces).count < 2 {
      createError = "Table name must be at least 2 characters"; return false
    }
    if selectedPreset.label == "Custom" {
      guard let sb = Int(customSmallBlind), sb > 0 else { createError = "Enter small blind"; return false }
      guard let bb = Int(customBigBlind),  bb > 0 else { createError = "Enter big blind";   return false }
      if bb != sb * 2 { createError = "Big blind must be 2× small blind"; return false }
      guard let min = Int(customMinBuyIn), min >= bb * 10 else {
        createError = "Min buy-in must be at least 10× big blind"; return false
      }
      guard let max = Int(customMaxBuyIn), max >= min else {
        createError = "Max buy-in must be ≥ min buy-in"; return false
      }
    }
    return true
  }

  private func resetCreateForm() {
    newTableName = ""
    selectedPreset = BlindPreset.presets[0]
    customSmallBlind = ""
    customBigBlind = ""
    customMinBuyIn = ""
    customMaxBuyIn = ""
    newMaxPlayers = 6
    newIsPrivate = false
    newGameType = "TEXAS_HOLDEM"
    addBotOnCreate = false
    createError = nil
  }
}
