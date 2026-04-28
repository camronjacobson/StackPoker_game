import Foundation

// ─── Hand History Store ───────────────────────────────────────────────────────
// On-disk JSON persistence under ~/Documents/HandHistory.
//
//   index.json                  — array of RecordedHandSummary, newest first
//   hands/<id>.json             — full RecordedHand (with all frames)
//
// Splitting summary from full hand keeps the list screen fast even after
// hundreds of hands: we only load the summary array on launch and lazily
// fetch the full hand when the user taps in.

@MainActor
final class HandHistoryStore: ObservableObject {
    static let shared = HandHistoryStore()

    @Published private(set) var summaries: [RecordedHandSummary] = []

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
    }

    // ─── Paths ────────────────────────────────────────────────────────────────

    private var rootDir: URL {
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("HandHistory", isDirectory: true)
    }
    private var handsDir: URL { rootDir.appendingPathComponent("hands", isDirectory: true) }
    private var indexURL: URL { rootDir.appendingPathComponent("index.json") }

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
        persistIndex()
    }

    func deleteAll() {
        try? fm.removeItem(at: handsDir)
        try? fm.removeItem(at: indexURL)
        summaries = []
        try? ensureDirectories()
    }

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
