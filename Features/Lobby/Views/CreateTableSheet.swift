import SwiftUI

struct CreateTableSheet: View {
  @ObservedObject var vm: LobbyViewModel
  @Environment(\.dismiss) var dismiss

  // Continuous slider state — decouples thumb animation from discrete VM values
  @State private var seatsSlider: Double = 6
  @State private var blindsSlider: Double = 0

  var body: some View {
    NavigationStack {
      ZStack {
        SPColors.background.ignoresSafeArea()

        ScrollView(showsIndicators: false) {
          VStack(spacing: SPSpacing.xl) {

            // Game type
            VStack(alignment: .leading, spacing: SPSpacing.sm) {
              SPSectionHeader(title: "Game Type")
              HStack(spacing: SPSpacing.sm) {
                GameTypeChip(label: "No Limit Hold'em", tag: "TEXAS_HOLDEM", selected: $vm.newGameType)
                GameTypeChip(label: "PLO", tag: "PLO", selected: $vm.newGameType)
              }
              .padding(.horizontal, SPSpacing.md)
            }

            // Table name
            VStack(alignment: .leading, spacing: SPSpacing.sm) {
              SPSectionHeader(title: "Table Name")
              SPTextField(
                placeholder: "e.g. Friday Night Game",
                text: $vm.newTableName,
                icon: "rectangle.stack"
              )
            }
            .padding(.horizontal, SPSpacing.md)

            // Blind structure
            VStack(alignment: .leading, spacing: SPSpacing.sm) {
              SPSectionHeader(title: "Blind Structure: \(vm.selectedPreset.label)")

              VStack(spacing: SPSpacing.xs) {
                Slider(
                  value: $blindsSlider,
                  in: 0...Double(BlindPreset.presets.count - 1)
                )
                .tint(SPColors.accent)
                .onChange(of: blindsSlider) { _, new in
                  let i = min(max(Int(new.rounded()), 0), BlindPreset.presets.count - 1)
                  if vm.selectedPreset.id != BlindPreset.presets[i].id {
                    vm.selectedPreset = BlindPreset.presets[i]
                  }
                }

                HStack {
                  ForEach(BlindPreset.presets) { preset in
                    Text(preset.label)
                      .font(SPFonts.caption(10))
                      .foregroundStyle(vm.selectedPreset.id == preset.id ? SPColors.accent : SPColors.textTertiary)
                      .frame(maxWidth: .infinity)
                  }
                }
              }
              .padding(.horizontal, SPSpacing.md)

              // Custom fields
              if vm.selectedPreset.label == "Custom" {
                VStack(spacing: SPSpacing.sm) {
                  HStack(spacing: SPSpacing.sm) {
                    SPTextField(
                      placeholder: "Small blind",
                      text: $vm.customSmallBlind,
                      icon: "chevron.left.2",
                      keyboardType: .numberPad
                    )
                    SPTextField(
                      placeholder: "Big blind",
                      text: $vm.customBigBlind,
                      icon: "chevron.right.2",
                      keyboardType: .numberPad
                    )
                  }
                  HStack(spacing: SPSpacing.sm) {
                    SPTextField(
                      placeholder: "Min buy-in",
                      text: $vm.customMinBuyIn,
                      icon: "arrow.down.circle",
                      keyboardType: .numberPad
                    )
                    SPTextField(
                      placeholder: "Max buy-in",
                      text: $vm.customMaxBuyIn,
                      icon: "arrow.up.circle",
                      keyboardType: .numberPad
                    )
                  }
                }
                .padding(.horizontal, SPSpacing.md)
                .transition(.opacity.combined(with: .move(edge: .top)))
              } else {
                // Preview for selected preset
                HStack(spacing: SPSpacing.xl) {
                  LabeledValue(label: "Small blind", value: formatChips(String(vm.selectedPreset.smallBlind)))
                  LabeledValue(label: "Big blind",   value: formatChips(String(vm.selectedPreset.bigBlind)))
                  LabeledValue(label: "Buy-in",      value: "\(formatChips(String(vm.selectedPreset.defaultMinBuyIn)))–\(formatChips(String(vm.selectedPreset.defaultMaxBuyIn)))")
                }
                .padding(.horizontal, SPSpacing.md)
                .transition(.opacity)
              }
            }
            .animation(.spring(response: 0.35), value: vm.selectedPreset.id)

            // Max players
            VStack(alignment: .leading, spacing: SPSpacing.sm) {
              SPSectionHeader(title: "Seats: \(vm.newMaxPlayers)")

              VStack(spacing: SPSpacing.xs) {
                Slider(value: $seatsSlider, in: 2...9)
                  .tint(SPColors.accent)
                  .onChange(of: seatsSlider) { _, new in
                    let rounded = min(max(Int(new.rounded()), 2), 9)
                    if vm.newMaxPlayers != rounded { vm.newMaxPlayers = rounded }
                  }

                HStack {
                  Text("2")
                  Spacer()
                  Text("9")
                }
                .font(SPFonts.caption(11))
                .foregroundStyle(SPColors.textTertiary)
              }
              .padding(.horizontal, SPSpacing.md)
            }

            // Privacy toggle
            VStack(spacing: 0) {
              SPSectionHeader(title: "Privacy")
                .padding(.bottom, SPSpacing.sm)
              SPCard {
                Toggle(isOn: $vm.newIsPrivate) {
                  HStack(spacing: SPSpacing.sm) {
                    Image(systemName: vm.newIsPrivate ? "lock.fill" : "globe")
                      .font(.system(size: 15))
                      .foregroundStyle(vm.newIsPrivate ? SPColors.accent : SPColors.textSecondary)
                      .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                      Text(vm.newIsPrivate ? "Private — invite only" : "Public — anyone can join")
                        .font(SPFonts.body())
                        .foregroundStyle(SPColors.textPrimary)
                      Text(vm.newIsPrivate ? "Share the join code to let players in" : "Visible in the public table list")
                        .font(SPFonts.caption(12))
                        .foregroundStyle(SPColors.textTertiary)
                    }
                  }
                }
                .tint(SPColors.accent)
                .padding(SPSpacing.md)
              }
              .padding(.horizontal, SPSpacing.md)
            }

            // Error
            if let err = vm.createError {
              ErrorBanner(message: err)
                .padding(.horizontal, SPSpacing.md)
            }

            // Submit
            SPButton(
              "Create Table",
              icon: "plus.rectangle.fill",
              isLoading: vm.isCreating,
              isDisabled: vm.newTableName.count < 2
            ) {
              Task { await vm.createTable() }
            }
            .padding(.horizontal, SPSpacing.md)
            .padding(.bottom, SPSpacing.xl)
          }
          .padding(.top, SPSpacing.md)
        }
      }
      .navigationTitle("New Table")
      .navigationBarTitleDisplayMode(.inline)
      .toolbarBackground(SPColors.surface, for: .navigationBar)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
            .foregroundStyle(SPColors.textSecondary)
        }
      }
    }
    .presentationDetents([.large])
    .presentationDragIndicator(.visible)
    .presentationBackground(SPColors.background)
    .onAppear {
      seatsSlider = Double(vm.newMaxPlayers)
      blindsSlider = Double(BlindPreset.presets.firstIndex(where: { $0.id == vm.selectedPreset.id }) ?? 0)
    }
  }
}

// ─── Blind Preset Chip ────────────────────────────────────────────────────────

struct BlindPresetChip: View {
  let preset: BlindPreset
  let isSelected: Bool
  let onTap: () -> Void

  var body: some View {
    Button(action: onTap) {
      VStack(spacing: 2) {
        Text(preset.label)
          .font(SPFonts.headline(13))
          .foregroundStyle(isSelected ? .white : SPColors.textPrimary)
        if preset.label != "Custom" {
          Text("\(formatChips(String(preset.smallBlind)))/\(formatChips(String(preset.bigBlind)))")
            .font(SPFonts.caption(11))
            .foregroundStyle(isSelected ? .white.opacity(0.8) : SPColors.textTertiary)
        }
      }
      .padding(.horizontal, SPSpacing.md)
      .padding(.vertical, SPSpacing.sm)
      .background(isSelected ? SPColors.accent : SPColors.surfaceElevated)
      .clipShape(RoundedRectangle(cornerRadius: SPRadius.md))
      .overlay(
        RoundedRectangle(cornerRadius: SPRadius.md)
          .strokeBorder(isSelected ? SPColors.accent : SPColors.border, lineWidth: 1)
      )
    }
    .buttonStyle(ScaleButtonStyle())
  }
}

// ─── Labeled Value ────────────────────────────────────────────────────────────

struct LabeledValue: View {
  let label: String
  let value: String

  var body: some View {
    VStack(spacing: 2) {
      Text(value)
        .font(SPFonts.headline(14))
        .foregroundStyle(SPColors.textPrimary)
      Text(label)
        .font(SPFonts.caption(11))
        .foregroundStyle(SPColors.textTertiary)
    }
  }
}

// ─── Game Type Chip ──────────────────────────────────────────────────────────

struct GameTypeChip: View {
  let label: String
  let tag: String
  @Binding var selected: String

  var isSelected: Bool { selected == tag }

  var body: some View {
    Button {
      withAnimation(.spring(response: 0.25)) { selected = tag }
    } label: {
      Text(label)
        .font(SPFonts.headline(14))
        .foregroundStyle(isSelected ? .white : SPColors.textSecondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(isSelected ? SPColors.accent : SPColors.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: SPRadius.md))
        .overlay(
          RoundedRectangle(cornerRadius: SPRadius.md)
            .strokeBorder(isSelected ? SPColors.accent : SPColors.border, lineWidth: 1)
        )
    }
    .buttonStyle(ScaleButtonStyle())
  }
}
