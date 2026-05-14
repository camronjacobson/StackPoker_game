import SwiftUI
import Combine

@MainActor
final class FriendsViewModel: ObservableObject {

  @Published var friends: [Friend] = []
  @Published var pendingRequests: [FriendRequest] = []
  @Published var searchResults: [SearchedUser] = []

  @Published var isLoadingFriends = false
  @Published var isLoadingRequests = false
  @Published var isSearching = false

  @Published var searchQuery = ""
  @Published var activeTab: FriendTab = .friends
  @Published var requestBadge = 0

  @Published var error: String?
  @Published var successMessage: String?

  enum FriendTab { case friends, requests, search }

  private let network = NetworkService.shared
  private var searchCancellable: AnyCancellable?
  private var searchTask: Task<Void, Never>?

  init() {
    searchCancellable = $searchQuery
      .debounce(for: .milliseconds(350), scheduler: RunLoop.main)
      .removeDuplicates()
      .sink { [weak self] q in
        guard !q.isEmpty else { self?.searchResults = []; return }
        self?.performSearch(q)
      }
  }

  // ─── Load ──────────────────────────────────────────────────────────────────

  func load() async {
    async let f: () = loadFriends()
    async let r: () = loadRequests()
    await f
    await r
  }

  func loadFriends() async {
    isLoadingFriends = true
    do {
      let response: FriendsResponse = try await network.request(.friends)
      friends = response.friends
    } catch {}
    isLoadingFriends = false
  }

  func loadRequests() async {
    isLoadingRequests = true
    do {
      let response: FriendRequestsResponse = try await network.request(.friendRequests)
      pendingRequests = response.requests
      requestBadge = response.requests.count
    } catch {}
    isLoadingRequests = false
  }

  // ─── Search ────────────────────────────────────────────────────────────────

  private func performSearch(_ query: String) {
    searchTask?.cancel()
    searchTask = Task {
      isSearching = true
      do {
        let response: SearchUsersResponse = try await network.request(.searchUsers(query: query))
        if !Task.isCancelled { searchResults = response.users }
      } catch {}
      isSearching = false
    }
  }

  // ─── Send Friend Request ───────────────────────────────────────────────────

  func sendRequest(to user: SearchedUser) async {
    do {
      struct Empty: Decodable {}
      let _: Empty = try await network.request(.sendFriendRequest(userId: user.id), method: .POST)
      // Optimistically update search results
      if let idx = searchResults.firstIndex(where: { $0.id == user.id }) {
        let updated = SearchedUser(
          id: user.id, username: user.username, displayName: user.displayName,
          avatarId: user.avatarId, chipBalance: user.chipBalance,
          friendshipStatus: "PENDING", friendshipId: nil
        )
        searchResults[idx] = updated
      }
      successMessage = "Friend request sent to \(user.username)"
    } catch let err as NetworkError {
      error = err.localizedDescription
    } catch {}
  }

  // ─── Accept / Decline ──────────────────────────────────────────────────────

  func acceptRequest(_ request: FriendRequest) async {
    do {
      struct Body: Encodable { let accept: Bool }
      struct Empty: Decodable {}
      let _: Empty = try await network.request(.respondFriendRequest(id: request.id), method: .POST, body: Body(accept: true))
      pendingRequests.removeAll { $0.id == request.id }
      requestBadge = pendingRequests.count
      await loadFriends()
      successMessage = "You and \(request.sender.username) are now friends"
    } catch let err as NetworkError {
      error = err.localizedDescription
    } catch {}
  }

  func declineRequest(_ request: FriendRequest) async {
    do {
      struct Body: Encodable { let accept: Bool }
      struct Empty: Decodable {}
      let _: Empty = try await network.request(.respondFriendRequest(id: request.id), method: .POST, body: Body(accept: false))
      pendingRequests.removeAll { $0.id == request.id }
      requestBadge = pendingRequests.count
    } catch {}
  }

  // ─── Remove Friend ─────────────────────────────────────────────────────────

  func removeFriend(_ friend: Friend) async {
    do {
      struct Empty: Decodable {}
      let _: Empty = try await network.request(.removeFriend(id: friend.friendshipId), method: .DELETE)
      friends.removeAll { $0.friendshipId == friend.friendshipId }
    } catch {}
  }
}
