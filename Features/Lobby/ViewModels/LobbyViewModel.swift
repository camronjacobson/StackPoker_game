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
      }
    }
  }

  // ─── Load Tables ───────────────────────────────────────────────────────────

  func loadTables() async {
    isLoadingTables = tables.isEmpty
    tablesError = nil
    do {
      let response: TableListResponse = try await network.request(
        .tables, method: .GET
      )
      tables = response.tables
    } catch let err as NetworkError {
      tablesError = err.localizedDescription
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
