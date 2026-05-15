import SwiftUI

// ─── Join by Code Sheet ───────────────────────────────────────────────────────

struct JoinByCodeSheet: View {
  @ObservedObject var vm: LobbyViewModel
  // Needed so the VM can apply the server-returned newBalance to the HUD
  // after a successful join-by-code (which debits the buy-in).
  @EnvironmentObject var authVM: AuthViewModel
  @Environment(\.dismiss) var dismiss

  var body: some View {
    NavigationStack {
      ZStack {
        // Aged-paper substrate keeps the sheet inside the same printed
        // booklet as the lobby instead of dropping to a flat surface.
        AgedPaperBackground().ignoresSafeArea()

        VStack(spacing: SPSpacing.xl) {
          VStack(spacing: SPSpacing.sm) {
            // Mustard burst-disc logo with ink panel border + hard offset
            // shadow — same vocab as AuthFlowView and UsernameSetupView so
            // every sheet header reads as the same stamp.
            ZStack {
              Circle()
                .fill(SPRetro.ink)
                .frame(width: 80, height: 80)
                .offset(x: 2.5, y: 3.5)
              Circle()
                .fill(SPRetro.mustard)
                .frame(width: 80, height: 80)
              Circle()
                .strokeBorder(SPRetro.ink, lineWidth: 2.5)
                .frame(width: 80, height: 80)
              Image(systemName: "number")
                .font(.system(size: 34, weight: .black))
                .foregroundStyle(SPRetro.ink)
            }
            .padding(.top, SPSpacing.xl)
            Text("ENTER JOIN CODE")
              .font(.custom("AmericanTypewriter-Bold", size: 22))
              .tracking(0.8)
              .foregroundStyle(SPRetro.ink)
            Text("Get the code from the table host")
              .font(.custom("AmericanTypewriter", size: 13))
              .foregroundStyle(SPRetro.inkMuted)
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
            ) { Task { await vm.joinByCode(authVM: authVM) } }
            .padding(.horizontal, SPSpacing.md)

            Text("Virtual chips only — no real money")
              .font(.custom("AmericanTypewriter", size: 11))
              .tracking(0.4)
              .foregroundStyle(SPRetro.inkMuted)
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
  // Needed so the VM can apply the server-returned newBalance to the HUD
  // when an accepted invite auto-joins the table (debits the buy-in).
  @EnvironmentObject var authVM: AuthViewModel
  @Environment(\.dismiss) var dismiss

  var body: some View {
    NavigationStack {
      ZStack {
        AgedPaperBackground().ignoresSafeArea()

        if vm.pendingInvites.isEmpty {
          // Retro empty-state: ink-soft envelope + AmericanTypewriter
          // copy. Reads as a printed "no mail" note on the page.
          VStack(spacing: SPSpacing.md) {
            Image(systemName: "envelope.open")
              .font(.system(size: 44))
              .foregroundStyle(SPRetro.inkMuted)
            Text("No pending invites")
              .font(.custom("AmericanTypewriter", size: 14))
              .foregroundStyle(SPRetro.inkMuted)
          }
        } else {
          List {
            ForEach(vm.pendingInvites) { invite in
              InviteRow(invite: invite) { accept in
                Task { await vm.respondToInvite(invite, accept: accept, authVM: authVM) }
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
    // Retro invite row: AmericanTypewriter typography on cream ground,
    // accept/decline as ink-bordered sticker buttons (mustard tick / pop-
    // red cross with hard offset shadows) — same vocab as the in-game
    // action stamps so confirming an invite reads as the same gesture.
    HStack(spacing: SPSpacing.sm) {
      AvatarView(avatarId: invite.sender.avatarId, size: 40)

      VStack(alignment: .leading, spacing: 3) {
        Text("\(invite.sender.displayName) invited you")
          .font(.custom("AmericanTypewriter-Bold", size: 14))
          .foregroundStyle(SPRetro.ink)
        Text("\(invite.table.name) · \(invite.table.blindsLabel) · \(invite.table.currentPlayers)/\(invite.table.maxPlayers)")
          .font(.custom("AmericanTypewriter", size: 12))
          .foregroundStyle(SPRetro.inkMuted)
      }

      Spacer()

      HStack(spacing: SPSpacing.xs) {
        // Decline — pop-red disc, ink border, hard offset shadow, paper X
        Button { onRespond(false) } label: {
          ZStack {
            Circle().fill(SPRetro.ink)
              .frame(width: 30, height: 30).offset(x: 1.5, y: 2)
            Circle().fill(SPRetro.popRed)
              .frame(width: 30, height: 30)
            Circle().strokeBorder(SPRetro.ink, lineWidth: 1.5)
              .frame(width: 30, height: 30)
            Image(systemName: "xmark")
              .font(.system(size: 12, weight: .black))
              .foregroundStyle(SPRetro.paper)
          }
        }.buttonStyle(.plain)

        // Accept — mustard disc, ink border, hard offset shadow, ink tick
        Button { onRespond(true) } label: {
          ZStack {
            Circle().fill(SPRetro.ink)
              .frame(width: 30, height: 30).offset(x: 1.5, y: 2)
            Circle().fill(SPRetro.mustard)
              .frame(width: 30, height: 30)
            Circle().strokeBorder(SPRetro.ink, lineWidth: 1.5)
              .frame(width: 30, height: 30)
            Image(systemName: "checkmark")
              .font(.system(size: 12, weight: .black))
              .foregroundStyle(SPRetro.ink)
          }
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
