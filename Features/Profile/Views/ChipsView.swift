import SwiftUI
import Combine

struct ChipsView: View {
    @StateObject private var vm = ChipsViewModel()
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var cosmetics: CosmeticsContainer
    /// Drives the cosmetics store sheet presentation. Local @State (not
    /// in ChipsViewModel) because the sheet's lifecycle is purely view-
    /// owned — nothing in the VM needs to know whether the store is open.
    @State private var showCosmeticsStore = false

    var body: some View {
        NavigationStack {
            ZStack {
                SPColors.background.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: SPSpacing.lg) {
                        balanceCard
                        actionsRow
                        if let msg = vm.successMessage { successBanner(msg) }
                        if let err = vm.error { ErrorBanner(message: err).padding(.horizontal, SPSpacing.md) }
                        historySection
                    }
                    .padding(.bottom, 100)
                }
            }
            .navigationTitle("Chips")
            .navigationBarTitleDisplayMode(.inline)
            .spNavigationStyle()
            .sheet(isPresented: $vm.showTransferSheet) { TransferSheet(vm: vm) }
            .onAppear { vm.onAppear() }
            .refreshable { await vm.loadHistory() }
        }
    }

    // ─── Balance card ─────────────────────────────────────────────────────────

    private var balanceCard: some View {
        VStack(spacing: SPSpacing.sm) {
            Text("Your Balance")
                .font(SPFonts.caption(11))
                .foregroundStyle(SPColors.textTertiary)
                .textCase(.uppercase)
                .tracking(1.5)

            if let user = authVM.currentUser {
                ChipBadge(amount: user.formattedChips, size: .large)
            } else {
                ChipBadge(amount: "—", size: .large)
            }

            Text("Virtual chips only · No real money value")
                .font(SPFonts.caption(11))
                .foregroundStyle(SPColors.textTertiary)
        }
        .padding(.vertical, SPSpacing.xl)
        .frame(maxWidth: .infinity)
        .cardBackground()
        .padding(.horizontal, SPSpacing.md)
        .padding(.top, SPSpacing.md)
    }

    // ─── Actions row ──────────────────────────────────────────────────────────

    private var actionsRow: some View {
        VStack(spacing: SPSpacing.sm) {
            HStack(spacing: SPSpacing.sm) {
                SPButton("Daily Bonus", icon: "gift.fill", isLoading: vm.isClaiming) {
                    Task { await vm.claimDailyBonus() }
                }
                SPButton("Transfer", style: .secondary, icon: "arrow.left.arrow.right") {
                    vm.showTransferSheet = true
                }
            }
            // Cosmetics store entry point #1. Full-width secondary button
            // sits below the primary two so it's discoverable but doesn't
            // compete with Daily Bonus for first-tap real estate. The
            // store sheet is sized large (.large detent) because the
            // store needs vertical breathing room for the rails.
            SPButton("Cosmetics Store", style: .secondary, icon: "sparkles") {
                showCosmeticsStore = true
            }
        }
        .padding(.horizontal, SPSpacing.md)
        .sheet(isPresented: $showCosmeticsStore) {
            StoreView(vm: makeStoreViewModel(entryPoint: .chipsView))
        }
    }

    /// Factory for the store VM. Builds the balance publisher from the
    /// auth VM's `currentUser` stream so the in-store balance pill
    /// reflects any chip changes (daily bonus, transfer, purchase) in
    /// real time. ChipAmount parses the BigInt-as-String safely; bad
    /// payloads fall back to .zero rather than displaying a stale value.
    private func makeStoreViewModel(entryPoint: StoreEntryPoint) -> StoreViewModel {
        let balancePublisher = authVM.$currentUser
            .map { profile -> ChipAmount in
                ChipAmount(serverString: profile?.chipBalance ?? "0") ?? .zero
            }
            .eraseToAnyPublisher()
        return StoreViewModel(
            container:        cosmetics,
            balancePublisher: balancePublisher,
            entryPoint:       entryPoint
        )
    }

    // ─── History section ──────────────────────────────────────────────────────

    @ViewBuilder
    private var historySection: some View {
        VStack(spacing: 0) {
            SPSectionHeader(title: "Transaction History")
                .padding(.bottom, SPSpacing.sm)

            if vm.isLoading {
                VStack(spacing: 8) {
                    ForEach(0..<5, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 8)
                            .fill(SPColors.surface)
                            .frame(height: 56)
                            .shimmer()
                    }
                }
                .padding(.horizontal, SPSpacing.md)
            } else if vm.transactions.isEmpty {
                VStack(spacing: SPSpacing.sm) {
                    Image(systemName: "list.bullet.clipboard")
                        .font(.system(size: 40))
                        .foregroundStyle(SPColors.textTertiary)
                    Text("No transactions yet")
                        .font(SPFonts.body())
                        .foregroundStyle(SPColors.textSecondary)
                    Text("Play a game to see your chip history here")
                        .font(SPFonts.caption(12))
                        .foregroundStyle(SPColors.textTertiary)
                }
                .padding(.vertical, SPSpacing.xxl)
            } else {
                SPCard {
                    VStack(spacing: 0) {
                        ForEach(Array(vm.transactions.enumerated()), id: \.element.id) { i, tx in
                            TransactionRow(tx: tx)
                            if i < vm.transactions.count - 1 { SPDivider() }
                        }
                    }
                }
                .padding(.horizontal, SPSpacing.md)
            }
        }
    }

    private func successBanner(_ msg: String) -> some View {
        HStack(spacing: SPSpacing.sm) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(SPColors.success)
            Text(msg).font(SPFonts.caption()).foregroundStyle(SPColors.success)
            Spacer()
        }
        .padding(SPSpacing.md)
        .background(SPColors.success.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: SPRadius.sm))
        .overlay(RoundedRectangle(cornerRadius: SPRadius.sm).strokeBorder(SPColors.success.opacity(0.3), lineWidth: 1))
        .padding(.horizontal, SPSpacing.md)
        .onAppear {
            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                vm.successMessage = nil
            }
        }
    }
}

// ─── Transaction Row ──────────────────────────────────────────────────────────

struct TransactionRow: View {
    let tx: ChipTransaction

    var body: some View {
        HStack(spacing: SPSpacing.sm) {
            ZStack {
                Circle()
                    .fill((tx.isCredit ? SPColors.success : SPColors.danger).opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: tx.icon)
                    .font(.system(size: 15))
                    .foregroundStyle(tx.isCredit ? SPColors.success : SPColors.danger)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(tx.typeLabel)
                    .font(SPFonts.body(14))
                    .foregroundStyle(SPColors.textPrimary)
                    .lineLimit(1)
                if let desc = tx.description, !desc.isEmpty {
                    Text(desc)
                        .font(SPFonts.caption(11))
                        .foregroundStyle(SPColors.textTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }

            Spacer()

            Text(tx.formattedAmount)
                .font(SPFonts.chips(14))
                .foregroundStyle(tx.isCredit ? SPColors.success : SPColors.danger)
        }
        .padding(.horizontal, SPSpacing.md)
        .padding(.vertical, SPSpacing.sm + 2)
    }
}

// ─── Transfer Sheet ───────────────────────────────────────────────────────────

struct TransferSheet: View {
    @ObservedObject var vm: ChipsViewModel
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                SPColors.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: SPSpacing.lg) {
                        // Hero
                        VStack(spacing: SPSpacing.sm) {
                            ZStack {
                                Circle().fill(SPColors.accent.opacity(0.12)).frame(width: 72, height: 72)
                                Image(systemName: "arrow.left.arrow.right.circle.fill")
                                    .font(.system(size: 36))
                                    .foregroundStyle(SPColors.accent)
                            }
                            .padding(.top, SPSpacing.lg)

                            Text("Transfer Chips")
                                .font(SPFonts.headline(20))
                                .foregroundStyle(SPColors.textPrimary)
                            Text("Send virtual chips to another player")
                                .font(SPFonts.body(14))
                                .foregroundStyle(SPColors.textSecondary)
                        }

                        // Form
                        VStack(spacing: SPSpacing.sm) {
                            SPTextField(
                                placeholder: "Recipient user ID",
                                text: $vm.recipientId,
                                icon: "person",
                                autocapitalization: .never,
                                autocorrect: false
                            )
                            SPTextField(
                                placeholder: "Amount (min 100 chips)",
                                text: $vm.transferAmount,
                                icon: "dollarsign",
                                keyboardType: .numberPad
                            )
                            SPTextField(
                                placeholder: "Note (optional)",
                                text: $vm.transferNote,
                                icon: "text.bubble"
                            )
                        }
                        .padding(.horizontal, SPSpacing.md)

                        if let err = vm.error {
                            ErrorBanner(message: err).padding(.horizontal, SPSpacing.md)
                        }

                        SPButton(
                            "Send Chips",
                            icon: "paperplane.fill",
                            isLoading: vm.isTransferring,
                            isDisabled: vm.recipientId.isEmpty || vm.transferAmount.isEmpty
                        ) {
                            Task { await vm.transfer() }
                        }
                        .padding(.horizontal, SPSpacing.md)

                        Text("Virtual chips only — no real monetary value")
                            .font(SPFonts.caption(11))
                            .foregroundStyle(SPColors.textTertiary)
                            .multilineTextAlignment(.center)

                        Spacer()
                    }
                }
            }
            .navigationTitle("Transfer Chips")
            .navigationBarTitleDisplayMode(.inline)
            .spNavigationStyle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(SPColors.textSecondary)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(SPColors.background)
    }
}
