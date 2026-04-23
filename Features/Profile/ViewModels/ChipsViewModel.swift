import SwiftUI
import Combine

// ─── Response Models ──────────────────────────────────────────────────────────

struct ChipTransaction: Decodable, Identifiable {
    let id:          String
    let type:        String
    let amount:      String
    let description: String?
    let createdAt:   String
    let isCredit:    Bool

    var formattedAmount: String {
        "\(isCredit ? "+" : "-")\(formatChips(amount))"
    }

    var typeLabel: String {
        switch type {
        case "SIGNUP_BONUS":      return "Welcome Bonus"
        case "DAILY_BONUS":       return "Daily Bonus"
        case "WIN":               return "Hand Won"
        case "LOSS":              return "Hand Lost"
        case "TRANSFER_SENT":     return "Transfer Sent"
        case "TRANSFER_RECEIVED": return "Transfer Received"
        case "BUY_IN":            return "Table Buy-in"
        case "CASH_OUT":          return "Cash Out"
        case "ADMIN_GRANT":       return "Admin Grant"
        default: return type.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    var icon: String {
        isCredit ? "arrow.up.circle.fill" : "arrow.down.circle.fill"
    }
}

struct ChipHistoryResponse: Decodable {
    let transactions: [ChipTransaction]
    let total:        Int
    let page:         Int
    let totalPages:   Int
}

struct DailyBonusResponse: Decodable {
    let bonusAmount: String
    let message:     String
}

struct TransferRequest: Encodable {
    let recipientId: String
    let amount:      Int
    let note:        String?
}

struct TransferResponse: Decodable {
    let transferred: Int
    let recipient:   String
}

// ─── ViewModel ────────────────────────────────────────────────────────────────

@MainActor
final class ChipsViewModel: ObservableObject {
    @Published var transactions:     [ChipTransaction] = []
    @Published var isLoading         = false
    @Published var isClaiming        = false
    @Published var isTransferring    = false
    @Published var error:            String?
    @Published var successMessage:   String?
    @Published var showTransferSheet = false

    // Transfer form
    @Published var recipientId   = ""
    @Published var transferAmount = ""
    @Published var transferNote   = ""

    private let network = NetworkService.shared

    func onAppear() {
        Task { await loadHistory() }
    }

    func loadHistory() async {
        isLoading = transactions.isEmpty
        defer { isLoading = false }
        do {
            let resp: ChipHistoryResponse = try await network.request(.chipHistory)
            transactions = resp.transactions
        } catch let e as NetworkError {
            error = e.localizedDescription
        } catch {}
    }

    func claimDailyBonus() async {
        isClaiming = true
        defer { isClaiming = false }
        do {
            struct Empty: Decodable {}
            let resp: DailyBonusResponse = try await network.request(.dailyBonus, method: .POST)
            successMessage = "+\(formatChips(resp.bonusAmount)) chips added!"
            await loadHistory()
        } catch let e as NetworkError {
            error = e.localizedDescription
        } catch {}
    }

    func transfer() async {
        guard let amt = Int(transferAmount), amt >= 100 else {
            error = "Minimum transfer is 100 chips"; return
        }
        guard !recipientId.trimmingCharacters(in: .whitespaces).isEmpty else {
            error = "Enter a recipient user ID"; return
        }
        isTransferring = true
        defer { isTransferring = false }
        do {
            let req = TransferRequest(recipientId: recipientId, amount: amt, note: transferNote.isEmpty ? nil : transferNote)
            let resp: TransferResponse = try await network.request(.transferChips, method: .POST, body: req)
            successMessage = "\(formatChips(String(resp.transferred))) chips sent to \(resp.recipient)"
            recipientId = ""; transferAmount = ""; transferNote = ""
            showTransferSheet = false
            await loadHistory()
        } catch let e as NetworkError {
            error = e.localizedDescription
        } catch {}
    }
}
