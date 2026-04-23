import SwiftUI

// ─── Table Card ───────────────────────────────────────────────────────────────

struct TableCard: View {
  let table: TableListItem
  let onJoin: () -> Void

  var body: some View {
    SPCard {
      HStack(spacing: SPSpacing.md) {
        // Status indicator + avatar
        VStack(spacing: SPSpacing.xs) {
          AvatarView(avatarId: table.ownerAvatarId, size: 40)
          StatusDot(status: table.status)
        }

        // Table info
        VStack(alignment: .leading, spacing: SPSpacing.xs) {
          HStack {
            Text(table.name)
              .font(SPFonts.headline(15))
              .foregroundStyle(SPColors.textPrimary)
              .lineLimit(1)

            if let clubName = table.clubName {
              Text(clubName)
                .font(SPFonts.caption(10))
                .foregroundStyle(SPColors.accent)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(SPColors.accent.opacity(0.12))
                .clipShape(Capsule())
            }
          }

          HStack(spacing: SPSpacing.sm) {
            // Blinds
            Label(table.blindsLabel, systemImage: "suit.spade.fill")
              .font(SPFonts.caption(12))
              .foregroundStyle(SPColors.textSecondary)

            // Seats
            Label(table.seatLabel, systemImage: "person.fill")
              .font(SPFonts.caption(12))
              .foregroundStyle(table.isFull ? SPColors.danger : SPColors.textSecondary)
          }

          // Buy-in range
          Text("Buy-in: \(formatChips(table.minBuyIn))–\(formatChips(table.maxBuyIn))")
            .font(SPFonts.caption(11))
            .foregroundStyle(SPColors.textTertiary)
        }

        Spacer()

        // Join button
        if !table.isFull && table.status == .waiting {
          Button(action: onJoin) {
            Text("Join")
              .font(SPFonts.headline(13))
              .foregroundStyle(.white)
              .padding(.horizontal, SPSpacing.md)
              .padding(.vertical, 8)
              .background(SPColors.accent)
              .clipShape(RoundedRectangle(cornerRadius: SPRadius.sm))
          }
          .buttonStyle(ScaleButtonStyle())
        } else {
          Text(table.isFull ? "Full" : table.status.label)
            .font(SPFonts.caption(12))
            .foregroundStyle(SPColors.textTertiary)
            .padding(.horizontal, SPSpacing.sm)
            .padding(.vertical, 6)
            .background(SPColors.surfaceHighlight)
            .clipShape(RoundedRectangle(cornerRadius: SPRadius.sm))
        }
      }
      .padding(SPSpacing.md)
    }
    .frame(height: 88)
  .opacity(table.isFull || table.status != .waiting ? 0.6 : 1)
  }
}

// ─── Status Dot ───────────────────────────────────────────────────────────────

struct StatusDot: View {
  let status: TableStatus

  var body: some View {
    Circle()
      .fill(color)
      .frame(width: 7, height: 7)
      .shadow(color: color.opacity(0.6), radius: 3)
  }

  private var color: Color {
    switch status {
    case .waiting:    return SPColors.success
    case .inProgress: return SPColors.warning
    case .paused:     return SPColors.info
    case .closed:     return SPColors.textTertiary
    }
  }
}

// ─── Seat Visualizer ──────────────────────────────────────────────────────────

struct SeatVisualizer: View {
  let maxPlayers: Int
  let currentPlayers: Int

  var body: some View {
    HStack(spacing: 2) {
      ForEach(0..<maxPlayers, id: \.self) { i in
        RoundedRectangle(cornerRadius: 2)
          .fill(i < currentPlayers ? SPColors.accent : SPColors.surfaceHighlight)
          .frame(width: 10, height: 10)
      }
    }
  }
}

// ─── Buy-In Sheet ─────────────────────────────────────────────────────────────

struct BuyInSheet: View {
  let table: TableListItem
  @Binding var buyIn: String
  let onConfirm: () -> Void
  @Environment(\.dismiss) var dismiss

  var body: some View {
    NavigationStack {
      ZStack {
        SPColors.background.ignoresSafeArea()

        VStack(spacing: SPSpacing.xl) {

          // Table preview
          VStack(spacing: SPSpacing.sm) {
            AvatarView(avatarId: table.ownerAvatarId, size: 56)
            Text(table.name)
              .font(SPFonts.headline(20))
              .foregroundStyle(SPColors.textPrimary)

            HStack(spacing: SPSpacing.md) {
              InfoPill(label: "Blinds", value: table.blindsLabel)
              InfoPill(label: "Seats", value: table.seatLabel)
              InfoPill(label: "Buy-in", value: "\(formatChips(table.minBuyIn))–\(formatChips(table.maxBuyIn))")
            }
          }
          .padding(.top, SPSpacing.md)

          // Buy-in input
          VStack(spacing: SPSpacing.sm) {
            Text("Choose your buy-in")
              .font(SPFonts.body())
              .foregroundStyle(SPColors.textSecondary)

            // Quick presets
            let min = Int(table.minBuyIn) ?? 0
            let max = Int(table.maxBuyIn) ?? 0
            HStack(spacing: SPSpacing.sm) {
              ForEach([min, min * 2, max], id: \.self) { amount in
                Button {
                  withAnimation { buyIn = String(amount) }
                } label: {
                  Text(formatChips(String(amount)))
                    .font(SPFonts.headline(13))
                    .foregroundStyle(buyIn == String(amount) ? .white : SPColors.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(buyIn == String(amount) ? SPColors.accent : SPColors.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: SPRadius.sm))
                }
                .buttonStyle(.plain)
              }
            }

            SPTextField(
              placeholder: "Custom amount",
              text: $buyIn,
              icon: "dollarsign",
              keyboardType: .numberPad
            )
          }
          .padding(.horizontal, SPSpacing.md)

          // Validation hint
          if let amount = Int(buyIn) {
            let min = Int(table.minBuyIn) ?? 0
            let max = Int(table.maxBuyIn) ?? 0
            if amount < min || amount > max {
              Text(amount < min ? "Minimum buy-in is \(formatChips(table.minBuyIn))" : "Maximum buy-in is \(formatChips(table.maxBuyIn))")
                .font(SPFonts.caption(12))
                .foregroundStyle(SPColors.danger)
            }
          }

          Spacer()

          VStack(spacing: SPSpacing.sm) {
            SPButton("Take a Seat", icon: "chair.lounge.fill", isDisabled: !isValidBuyIn) {
              onConfirm()
            }
            .padding(.horizontal, SPSpacing.md)

            Text("Virtual chips only — no real money")
              .font(SPFonts.caption(11))
              .foregroundStyle(SPColors.textTertiary)
          }
          .padding(.bottom, SPSpacing.xl)
        }
      }
      .navigationTitle("Join Table")
      .navigationBarTitleDisplayMode(.inline)
      .toolbarBackground(SPColors.surface, for: .navigationBar)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
            .foregroundStyle(SPColors.textSecondary)
        }
      }
    }
    .presentationDetents([.medium])
    .presentationDragIndicator(.visible)
    .presentationBackground(SPColors.background)
  }

  private var isValidBuyIn: Bool {
    guard let amount = Int(buyIn) else { return false }
    let min = Int(table.minBuyIn) ?? 0
    let max = Int(table.maxBuyIn) ?? 0
    return amount >= min && amount <= max
  }
}

// ─── Info Pill ────────────────────────────────────────────────────────────────

struct InfoPill: View {
  let label: String
  let value: String

  var body: some View {
    VStack(spacing: 2) {
      Text(value)
        .font(SPFonts.headline(13))
        .foregroundStyle(SPColors.textPrimary)
      Text(label)
        .font(SPFonts.caption(10))
        .foregroundStyle(SPColors.textTertiary)
    }
    .padding(.horizontal, SPSpacing.sm)
    .padding(.vertical, SPSpacing.xs)
    .background(SPColors.surfaceElevated)
    .clipShape(RoundedRectangle(cornerRadius: SPRadius.sm))
  }
}
