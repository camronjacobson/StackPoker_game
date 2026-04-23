import SwiftUI

// ─── Join by Code Sheet ───────────────────────────────────────────────────────

struct JoinByCodeSheet: View {
  @ObservedObject var vm: LobbyViewModel
  @Environment(\.dismiss) var dismiss

  var body: some View {
    NavigationStack {
      ZStack {
        SPColors.background.ignoresSafeArea()

        VStack(spacing: SPSpacing.xl) {
          VStack(spacing: SPSpacing.sm) {
            ZStack {
              Circle().fill(SPColors.accent.opacity(0.12)).frame(width: 80, height: 80)
              Image(systemName: "number.circle.fill").font(.system(size: 40)).foregroundStyle(SPColors.accent)
            }
            .padding(.top, SPSpacing.xl)
            Text("Enter join code")
              .font(SPFonts.headline(18)).foregroundStyle(SPColors.textPrimary)
            Text("Get the code from the table host")
              .font(SPFonts.body(14)).foregroundStyle(SPColors.textSecondary)
              .multilineTextAlignment(.center)
          }

          VStack(spacing: SPSpacing.sm) {
            SPTextField(
              placeholder: "e.g. ABC123",
              text: Binding(get: { vm.joinCode }, set: { vm.joinCode = $0.uppercased() }),
              icon: "number",
              autocapitalization: .characters,
              autocorrect: false
            )
            SPTextField(
              placeholder: "Buy-in amount",
              text: $vm.buyInAmount,
              icon: "dollarsign",
              keyboardType: .numberPad
            )
          }
          .padding(.horizontal, SPSpacing.md)

          if let err = vm.joinError {
            ErrorBanner(message: err).padding(.horizontal, SPSpacing.md)
          }

          Spacer()

          VStack(spacing: SPSpacing.sm) {
            SPButton(
              "Join Table",
              icon: "arrow.right.circle.fill",
              isLoading: vm.isJoining,
              isDisabled: vm.joinCode.count < 4 || vm.buyInAmount.isEmpty
            ) { Task { await vm.joinByCode() } }
            .padding(.horizontal, SPSpacing.md)

            Text("Virtual chips only — no real money")
              .font(SPFonts.caption(11)).foregroundStyle(SPColors.textTertiary)
          }
          .padding(.bottom, SPSpacing.xl)
        }
      }
      .navigationTitle("Join by Code")
      .navigationBarTitleDisplayMode(.inline)
      .spNavigationStyle()
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }.foregroundStyle(SPColors.textSecondary)
        }
      }
    }
    .presentationDetents([.medium])
    .presentationDragIndicator(.visible)
    .presentationBackground(SPColors.background)
  }
}

// ─── Invites Sheet ────────────────────────────────────────────────────────────

struct InvitesSheet: View {
  @ObservedObject var vm: LobbyViewModel
  @Environment(\.dismiss) var dismiss

  var body: some View {
    NavigationStack {
      ZStack {
        SPColors.background.ignoresSafeArea()

        if vm.pendingInvites.isEmpty {
          VStack(spacing: SPSpacing.md) {
            Image(systemName: "envelope.open").font(.system(size: 44)).foregroundStyle(SPColors.textTertiary)
            Text("No pending invites").font(SPFonts.body()).foregroundStyle(SPColors.textSecondary)
          }
        } else {
          List {
            ForEach(vm.pendingInvites) { invite in
              InviteRow(invite: invite) { accept in
                Task { await vm.respondToInvite(invite, accept: accept) }
              }
              .listRowBackground(SPColors.surface)
              .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            }
          }
          .listStyle(.plain)
          .scrollContentBackground(.hidden)
        }
      }
      .navigationTitle("Invites (\(vm.pendingInvites.count))")
      .navigationBarTitleDisplayMode(.inline)
      .spNavigationStyle()
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }.foregroundStyle(SPColors.accent)
        }
      }
    }
    .presentationDetents([.medium, .large])
    .presentationDragIndicator(.visible)
    .presentationBackground(SPColors.background)
  }
}

// ─── Invite Row ───────────────────────────────────────────────────────────────

struct InviteRow: View {
  let invite: TableInvite
  let onRespond: (Bool) -> Void

  var body: some View {
    HStack(spacing: SPSpacing.sm) {
      AvatarView(avatarId: invite.sender.avatarId, size: 40)

      VStack(alignment: .leading, spacing: 3) {
        Text("\(invite.sender.displayName) invited you")
          .font(SPFonts.headline(14)).foregroundStyle(SPColors.textPrimary)
        Text("\(invite.table.name) · \(invite.table.blindsLabel) · \(invite.table.currentPlayers)/\(invite.table.maxPlayers)")
          .font(SPFonts.caption(12)).foregroundStyle(SPColors.textSecondary)
      }

      Spacer()

      HStack(spacing: SPSpacing.xs) {
        Button { onRespond(false) } label: {
          Image(systemName: "xmark")
            .font(.system(size: 12, weight: .bold)).foregroundStyle(SPColors.danger)
            .padding(8).background(SPColors.danger.opacity(0.12)).clipShape(Circle())
        }.buttonStyle(.plain)

        Button { onRespond(true) } label: {
          Image(systemName: "checkmark")
            .font(.system(size: 12, weight: .bold)).foregroundStyle(SPColors.success)
            .padding(8).background(SPColors.success.opacity(0.12)).clipShape(Circle())
        }.buttonStyle(.plain)
      }
    }
    .padding(.vertical, 4)
  }
}

// ─── Game screen wrapper (wraps real GameView) ────────────────────────────────

struct GamePlaceholderView: View {
  let table: TableDetail
  let onLeave: () -> Void

  var body: some View {
    GameView(tableId: table.id, tableName: table.name, maxSeats: table.maxPlayers)
  }
}
