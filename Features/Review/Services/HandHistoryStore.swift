import Foundation

// ─── Hand History Store ───────────────────────────────────────────────────────
// On-disk JSON persistence under ~/Documents/HandHistory/<userId>/.
//
//   <userId>/index.json         — array of RecordedHandSummary, newest first
//   <userId>/hands/<id>.json    — full RecordedHand (with all frames)
//   <userId>/bookmarks.json     — Set<String> of bookmarked hand IDs (PR 4)
//
// Splitting summary from full hand keeps the list screen fast even after
// hundreds of hands: we only load the summary array on launch and lazily
// fetch the full hand when the user taps in.
//
// Bookmarks (PR 4) are stored as a separate flat ID set rather than a field
// on RecordedHandSummary so existing on-disk hands stay backwards-compatible
// (no Codable migration needed) and so toggling a bookmark doesn't have to
// rewrite the whole index.json.
//
// Per-user scoping: the store starts in an "anonymous" state with no active
// user and empty summaries. AuthViewModel calls `setActiveUser(_:)` on
// login / session-restore / logout so the Review tab only ever surfaces the
// signed-in user's hands. Without this, any hand recorded by a previous
// account on the same device would still count against a freshly-registered
// account's stats — the bug that motivated this scoping.

@MainActor
final class HandHistoryStore: ObservableObject {
    static let shared = HandHistoryStore()

    @Published private(set) var summaries: [RecordedHandSummary] = []

    /// IDs of hands the user has starred for later review. Decoupled from
    /// the summary index so bookmark toggles don't require rewriting every
    /// summary, and so the persisted RecordedHand JSON stays untouched.
    @Published private(set) var bookmarkedIds: Set<String> = []

    /// The user whose hand history is currently loaded into memory. `nil`
    /// means "no one is signed in" — `summaries`/`bookmarkedIds` are empty
    /// and `save()` is a no-op (writing without an owner would re-introduce
    /// the cross-account leak this scoping was added to fix).
    private(set) var activeUserId: String?

    private let fm = FileManager.default
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private init() {
        // One-time migration of any pre-scoping hands. Safe to run on every
        // launch — it short-circuits when there's nothing legacy to move.
        migrateLegacyIfNeeded()
        // We deliberately do NOT load anything here. Wait for the auth layer
        // to call setActiveUser(_:) — see the type-level note above.
    }

    // ─── Active user ──────────────────────────────────────────────────────────

    /// Switch the store to a different user (or to "no user" with `nil`).
    /// Reloads `summaries` and `bookmarkedIds` from that user's directory.
    /// Idempotent — calling with the same id is a cheap no-op.
    func setActiveUser(_ userId: String?) {
        guard userId != activeUserId else { return }
        activeUserId = userId

        if userId != nil {
            try? ensureDirectories()
            loadIndex()
            loadBookmarks()
        } else {
            // Signed out: drop in-memory state. On-disk data for the previous
            // user stays intact for when they log back in.
            summaries = []
            bookmarkedIds = []
        }
    }

    // ─── Paths ────────────────────────────────────────────────────────────────

    /// Top-level container that holds every user's per-user subdirectory.
    /// Used by the migration helper; per-user reads/writes go through
    /// `rootDir` instead.
    private var containerDir: URL {
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("HandHistory", isDirectory: true)
    }

    /// Active user's directory. Force-unwraps `activeUserId` because every
    /// path-using method below already guards on it; calling these without
    /// an active user is a programmer error.
    private var rootDir: URL {
        containerDir.appendingPathComponent(activeUserId!, isDirectory: true)
    }
    private var handsDir: URL { rootDir.appendingPathComponent("hands", isDirectory: true) }
    private var indexURL: URL { rootDir.appendingPathComponent("index.json") }
    private var bookmarksURL: URL { rootDir.appendingPathComponent("bookmarks.json") }

    private func ensureDirectories() throws {
        try fm.createDirectory(at: handsDir, withIntermediateDirectories: true)
    }

    // ─── Public API ───────────────────────────────────────────────────────────

    func save(_ hand: RecordedHand) {
        // Refuse to write hands that don't belong to the active user, or
        // when no one's signed in. Either case is a bug: it means the
        // recorder fired without a matching auth context and writing would
        // re-introduce cross-account stat leaks.
        guard let activeUserId, hand.userId == activeUserId else {
            print("[HandHistoryStore] save skipped — active=\(activeUserId ?? "nil") hand=\(hand.userId)")
            return
        }
        do {
            try ensureDirectories()
            let data = try encoder.encode(hand)
            let url = handsDir.appendingPathComponent("\(hand.id).json")
            try data.write(to: url, options: [.atomic])
            // Update in-memory + on-disk index
            summaries.insert(hand.summary, at: 0)
            persistIndex()
        } catch {
            print("[HandHistoryStore] save failed: \(error)")
        }
    }

    func loadHand(id: String) -> RecordedHand? {
        guard activeUserId != nil else { return nil }
        let url = handsDir.appendingPathComponent("\(id).json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(RecordedHand.self, from: data)
    }

    func delete(id: String) {
        guard activeUserId != nil else { return }
        let url = handsDir.appendingPathComponent("\(id).json")
        try? fm.removeItem(at: url)
        summaries.removeAll { $0.id == id }
        // Bookmark must follow the hand it points at — leaving a dangling
        // bookmark would surface a "no result" row in the bookmarked filter.
        if bookmarkedIds.remove(id) != nil {
            persistBookmarks()
        }
        persistIndex()
    }

    func deleteAll() {
        guard activeUserId != nil else { return }
        try? fm.removeItem(at: handsDir)
        try? fm.removeItem(at: indexURL)
        try? fm.removeItem(at: bookmarksURL)
        summaries = []
        bookmarkedIds = []
        try? ensureDirectories()
    }

    // ─── Bookmarks (PR 4) ─────────────────────────────────────────────────────

    /// Star/unstar a hand. We toggle in-memory, then persist asynchronously
    /// via `persistBookmarks()` — the file write is small (a JSON array of
    /// IDs) so a best-effort sync write is fine on the main actor.
    func toggleBookmark(id: String) {
        if bookmarkedIds.remove(id) == nil {
            bookmarkedIds.insert(id)
        }
        persistBookmarks()
    }

    /// Convenience read used by row views — avoids forcing every caller to
    /// hold a reference to `bookmarkedIds` directly.
    func isBookmarked(_ id: String) -> Bool { bookmarkedIds.contains(id) }

    // ─── Internal ─────────────────────────────────────────────────────────────

    private func loadIndex() {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? decoder.decode([RecordedHandSummary].self, from: data) else {
            // No index yet — try to rebuild by scanning the hands directory.
            // Cheap insurance against a corrupted/missing index.
            rebuildIndex()
            return
        }
        // Sort newest first in case the file got out of order.
        summaries = decoded.sorted { $0.endedAt > $1.endedAt }
    }

    private func persistIndex() {
        do {
            let data = try encoder.encode(summaries)
            try data.write(to: indexURL, options: [.atomic])
        } catch {
            print("[HandHistoryStore] persist index failed: \(error)")
        }
    }

    /// Read bookmarked IDs from disk. Stored as a flat `[String]` (Codable
    /// has no first-class Set encoding) and round-tripped to/from a Set in
    /// memory. Missing/corrupt file → empty set; we never crash the app over
    /// a bookmark read.
    private func loadBookmarks() {
        guard let data = try? Data(contentsOf: bookmarksURL),
              let decoded = try? decoder.decode([String].self, from: data) else {
            bookmarkedIds = []
            return
        }
        bookmarkedIds = Set(decoded)
    }

    /// Write bookmarked IDs to disk. Tiny payload (one short string per
    /// bookmark) so a synchronous write on the main actor is fine.
    private func persistBookmarks() {
        do {
            let data = try encoder.encode(Array(bookmarkedIds))
            try data.write(to: bookmarksURL, options: [.atomic])
        } catch {
            print("[HandHistoryStore] persist bookmarks failed: \(error)")
        }
    }

    // ─── Legacy migration ─────────────────────────────────────────────────────
    // Before per-user scoping, hands lived directly under HandHistory/hands.
    // This walks any leftover legacy files and moves each into its correct
    // owner's per-user directory based on the `userId` baked into the hand
    // JSON. Idempotent: once the legacy paths are gone the function returns
    // immediately, so it's safe to run on every launch.

    private var legacyHandsDir: URL { containerDir.appendingPathComponent("hands", isDirectory: true) }
    private var legacyIndexURL: URL { containerDir.appendingPathComponent("index.json") }
    private var legacyBookmarksURL: URL { containerDir.appendingPathComponent("bookmarks.json") }

    private func migrateLegacyIfNeeded() {
        // Fast path — nothing to do if the legacy hands directory doesn't exist.
        guard fm.fileExists(atPath: legacyHandsDir.path) else { return }

        // Track which user dirs got new content so we can rebuild their
        // indices once instead of after every move.
        var touchedUserIds = Set<String>()

        if let urls = try? fm.contentsOfDirectory(at: legacyHandsDir, includingPropertiesForKeys: nil) {
            for url in urls where url.pathExtension == "json" {
                guard let data = try? Data(contentsOf: url),
                      let hand = try? decoder.decode(RecordedHand.self, from: data) else {
                    // Unreadable/corrupt — leave it; user can wipe manually.
                    continue
                }
                let userDir = containerDir.appendingPathComponent(hand.userId, isDirectory: true)
                let userHandsDir = userDir.appendingPathComponent("hands", isDirectory: true)
                do {
                    try fm.createDirectory(at: userHandsDir, withIntermediateDirectories: true)
                    let dest = userHandsDir.appendingPathComponent(url.lastPathComponent)
                    // If a file with the same id already exists in the target
                    // (shouldn't, but be defensive), overwrite it.
                    if fm.fileExists(atPath: dest.path) { try? fm.removeItem(at: dest) }
                    try fm.moveItem(at: url, to: dest)
                    touchedUserIds.insert(hand.userId)
                } catch {
                    print("[HandHistoryStore] migrate move failed for \(url.lastPathComponent): \(error)")
                }
            }
        }

        // Remove the legacy hands dir if it's now empty, plus the global
        // index/bookmarks files (their content is now per-user-irrelevant).
        if let remaining = try? fm.contentsOfDirectory(at: legacyHandsDir, includingPropertiesForKeys: nil),
           remaining.isEmpty {
            try? fm.removeItem(at: legacyHandsDir)
        }
        try? fm.removeItem(at: legacyIndexURL)
        try? fm.removeItem(at: legacyBookmarksURL)

        // Rebuild each touched user's index from their freshly-populated
        // hands dir. Done out-of-band (without flipping activeUserId) so the
        // currently-signed-in user — once setActiveUser() runs — sees a
        // consistent index.
        for uid in touchedUserIds {
            rebuildIndexAt(userDir: containerDir.appendingPathComponent(uid, isDirectory: true))
        }
    }

    /// Out-of-band index rebuild for an arbitrary user directory. Used by
    /// the legacy migration; the active-user version goes through `rebuildIndex()`.
    private func rebuildIndexAt(userDir: URL) {
        let handsDir = userDir.appendingPathComponent("hands", isDirectory: true)
        let indexURL = userDir.appendingPathComponent("index.json")
        guard let urls = try? fm.contentsOfDirectory(at: handsDir, includingPropertiesForKeys: nil) else {
            return
        }
        var rebuilt: [RecordedHandSummary] = []
        for url in urls where url.pathExtension == "json" {
            if let data = try? Data(contentsOf: url),
               let hand = try? decoder.decode(RecordedHand.self, from: data) {
                rebuilt.append(hand.summary)
            }
        }
        rebuilt.sort { $0.endedAt > $1.endedAt }
        if let data = try? encoder.encode(rebuilt) {
            try? data.write(to: indexURL, options: [.atomic])
        }
    }

    /// Walk the hands/ directory and rebuild the summary index. Used on a fresh
    /// install or after the index file goes missing/corrupt.
    private func rebuildIndex() {
        guard let urls = try? fm.contentsOfDirectory(at: handsDir, includingPropertiesForKeys: nil) else {
            summaries = []
            return
        }
        var rebuilt: [RecordedHandSummary] = []
        for url in urls where url.pathExtension == "json" {
            if let data = try? Data(contentsOf: url),
               let hand = try? decoder.decode(RecordedHand.self, from: data) {
                rebuilt.append(hand.summary)
            }
        }
        summaries = rebuilt.sorted { $0.endedAt > $1.endedAt }
        persistIndex()
    }
}
