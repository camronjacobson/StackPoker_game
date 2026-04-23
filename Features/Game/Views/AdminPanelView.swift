import SwiftUI

// ─── Admin Panel View ─────────────────────────────────────────────────────────
// Accessible only to table owners and system admins.

@MainActor
final class AdminViewModel: ObservableObject {
    @Published var isLoading    = false
    @Published var successMsg:  String?
    @Published var errorMsg:    String?

    private let network = NetworkService.shared

    func kickPlayer(tableId: String, userId: String, username: String) async {
        await perform("Kicked \(username)") {
            struct Body: Encodable { let targetUserId: String }
            struct Resp: Decodable { let message: String }
            let _: Resp = try await self.network.request(
                .adminKick(tableId: tableId, userId: userId),
                method: .POST,
                body: Body(targetUserId: userId)
            )
        }
    }

    func banPlayer(userId: String, username: String, reason: String) async {
        await perform("Banned \(username)") {
            struct Body: Encodable { let reason: String }
            struct Resp: Decodable { let message: String }
            let _: Resp = try await self.network.request(
                .adminBan(userId: userId),
                method: .POST,
                body: Body(reason: reason)
            )
        }
    }

    func resetTable(tableId: String) async {
        await perform("Table reset") {
            struct Resp: Decodable { let message: String }
            let _: Resp = try await self.network.request(
                .adminReset(tableId: tableId),
                method: .POST
            )
        }
    }

    func grantChips(userId: String, username: String, amount: Int) async {
        await perform("Granted \(formatChips(String(amount))) to \(username)") {
            struct Body: Encodable { let amount: Int }
            struct Resp: Decodable { let message: String }
            let _: Resp = try await self.network.request(
                .adminGrantChips(userId: userId),
                method: .POST,
                body: Body(amount: amount)
            )
        }
    }

    private func perform(_ successText: String, _ work: @escaping () async throws -> Void) async {
        isLoading = true
        errorMsg  = nil
        do {
            try await work()
            successMsg = successText
        } catch let e as NetworkError {
            errorMsg = e.localizedDescription
        } catch {}
        isLoading = false
    }
}

struct AdminPanelView: View {
    let tableId:   String
    let tableName: String
    let players:   [GameSeat]

    @StateObject private var vm = AdminViewModel()
    @Environment(\.dismiss) var dismiss

    @State private var banTarget:   GameSeat?
    @State private var banReason    = ""
    @State private var grantTarget: GameSeat?
    @State private var grantAmount  = ""
    @State private var showReset    = false

    var body: some View {
        NavigationStack {
            ZStack {
                SPColors.background.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: SPSpacing.lg) {

                        // Status messages
                        if let msg = vm.successMsg {
                            HStack { Image(systemName: "checkmark.circle.fill").foregroundStyle(SPColors.success); Text(msg).font(SPFonts.caption()).foregroundStyle(SPColors.success); Spacer() }
                                .padding(SPSpacing.md).background(SPColors.success.opacity(0.1)).clipShape(RoundedRectangle(cornerRadius: SPRadius.sm))
                                .padding(.horizontal, SPSpacing.md)
                        }
                        if let err = vm.errorMsg {
                            ErrorBanner(message: err).padding(.horizontal, SPSpacing.md)
                        }

                        // Players list
                        VStack(spacing: 0) {
                            SPSectionHeader(title: "Players at Table").padding(.bottom, SPSpacing.sm)
                            SPCard {
                                VStack(spacing: 0) {
                                    ForEach(Array(players.enumerated()), id: \.element.id) { i, seat in
                                        AdminPlayerRow(
                                            seat: seat,
                                            onKick: { Task { await vm.kickPlayer(tableId: tableId, userId: seat.userId, username: seat.username) } },
                                            onBan:  { banTarget = seat },
                                            onGrant: { grantTarget = seat }
                                        )
                                        if i < players.count - 1 { SPDivider() }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, SPSpacing.md)

                        // Table controls
                        VStack(spacing: 0) {
                            SPSectionHeader(title: "Table Controls").padding(.bottom, SPSpacing.sm)
                            SPCard {
                                VStack(spacing: 0) {
                                    SettingsRow(icon: "arrow.counterclockwise", label: "Reset Table") { showReset = true }
                                    SPDivider()
                                    SettingsRow(icon: "xmark.rectangle", label: "Close Table", action: nil)
                                }
                            }
                        }
                        .padding(.horizontal, SPSpacing.md)
                    }
                    .padding(.bottom, 100)
                }
            }
            .navigationTitle("Admin — \(tableName)")
            .navigationBarTitleDisplayMode(.inline)
            .spNavigationStyle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.foregroundStyle(SPColors.accent)
                }
            }
            // Ban confirmation
            .alert("Ban Player", isPresented: Binding(get: { banTarget != nil }, set: { if !$0 { banTarget = nil } })) {
                TextField("Reason", text: $banReason)
                Button("Ban", role: .destructive) {
                    if let t = banTarget { Task { await vm.banPlayer(userId: t.userId, username: t.username, reason: banReason) }; banTarget = nil; banReason = "" }
                }
                Button("Cancel", role: .cancel) { banTarget = nil; banReason = "" }
            } message: { Text("Ban \(banTarget?.username ?? "")? This prevents them from logging in.") }
            // Grant chips
            .alert("Grant Chips", isPresented: Binding(get: { grantTarget != nil }, set: { if !$0 { grantTarget = nil } })) {
                TextField("Amount", text: $grantAmount).keyboardType(.numberPad)
                Button("Grant") {
                    if let t = grantTarget, let amt = Int(grantAmount) { Task { await vm.grantChips(userId: t.userId, username: t.username, amount: amt) }; grantTarget = nil; grantAmount = "" }
                }
                Button("Cancel", role: .cancel) { grantTarget = nil; grantAmount = "" }
            } message: { Text("Grant chips to \(grantTarget?.username ?? "").") }
            // Reset confirmation
            .confirmationDialog("Reset Table?", isPresented: $showReset, titleVisibility: .visible) {
                Button("Reset", role: .destructive) { Task { await vm.resetTable(tableId: tableId) } }
                Button("Cancel", role: .cancel) {}
            } message: { Text("All stacks will be reset to buy-in amounts. Current hand will end.") }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(SPColors.background)
    }
}

struct AdminPlayerRow: View {
    let seat:    GameSeat
    let onKick:  () -> Void
    let onBan:   () -> Void
    let onGrant: () -> Void

    var body: some View {
        HStack(spacing: SPSpacing.sm) {
            AvatarView(avatarId: seat.avatarId, size: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(seat.username).font(SPFonts.headline(14)).foregroundStyle(SPColors.textPrimary)
                Text("Stack: \(formatChips(String(seat.stack))) · Seat \(seat.seatIndex + 1)")
                    .font(SPFonts.caption(11)).foregroundStyle(SPColors.textSecondary)
            }

            Spacer()

            Menu {
                Button("Grant Chips", action: onGrant)
                Button("Kick Player", action: onKick)
                Button("Ban Player", role: .destructive, action: onBan)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 18))
                    .foregroundStyle(SPColors.textSecondary)
            }
        }
        .padding(.horizontal, SPSpacing.md)
        .padding(.vertical, SPSpacing.sm + 2)
    }
}
