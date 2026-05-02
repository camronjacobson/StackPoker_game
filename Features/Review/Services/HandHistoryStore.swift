import Foundation

// ─── Hand History Store ───────────────────────────────────────────────────────
// On-disk JSON persistence under ~/Documents/HandHistory.
//
//   index.json                  — array of RecordedHandSummary, newest first
//   hands/<id>.json             — full RecordedHand (with all frames)
//   bookmarks.json              — Set<String> of bookmarked hand IDs (PR 4)
//
// Splitting summary from full hand keeps the list screen fast even after
// hundreds of hands: we only load the summary array on launch and lazily
// fetch the full hand when the user taps in.
//
// Bookmarks (PR 4) are stored as a separate flat ID set rather than a field
// on RecordedHandSummary so existing on-disk hands stay backwards-compatible
// (no Codable migration needed) and so toggling a bookmark doesn't have to
// rewrite the whole index.json.

@MainActor
final class HandHistoryStore: ObservableObject {
    static let shared = HandHistoryStore()

    @Published private(set) var summaries: [RecordedHandSummary] = []

    /// IDs of hands the user has starred for later review. Decoupled from
    /// the summary index so bookmark toggles don't require rewriting every
    /// summary, and so the persisted RecordedHand JSON stays untouched.
    @Published private(set) var bookmarkedIds: Set<String> = []

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
        try? ensureDirectories()
        loadIndex()
        loadBookmarks()
    }

    // ─── Paths ────────────────────────────────────────────────────────────────

    private var rootDir: URL {
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("HandHistory", isDirectory: true)
    }
    private var handsDir: URL { rootDir.appendingPathComponent("hands", isDirectory: true) }
    private var indexURL: URL { rootDir.appendingPathComponent("index.json") }
    private var bookmarksURL: URL { rootDir.appendingPathComponent("bookmarks.json") }

    private func ensureDirectories() throws {
        try fm.createDirectory(at: handsDir, withIntermediateDirectories: true)
    }

    // ─── Public API ───────────────────────────────────────────────────────────

    func save(_ hand: RecordedHand) {
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
        let url = handsDir.appendingPathComponent("\(id).json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(RecordedHand.self, from: data)
    }

    func delete(id: String) {
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
